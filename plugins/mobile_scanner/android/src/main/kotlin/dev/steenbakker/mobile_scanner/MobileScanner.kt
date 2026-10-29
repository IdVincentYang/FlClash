package dev.steenbakker.mobile_scanner

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.Size
import android.view.Surface
import androidx.annotation.VisibleForTesting
import androidx.camera.camera2.Camera2Config
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.CameraXConfig
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ExperimentalLensFacing
import androidx.camera.core.FocusMeteringAction
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888
import androidx.camera.core.ImageProxy
import androidx.camera.core.MeteringPoint
import androidx.camera.core.MeteringPointFactory
import androidx.camera.core.Preview
import androidx.camera.core.SurfaceOrientedMeteringPointFactory
import androidx.camera.core.SurfaceRequest
import androidx.camera.core.TorchState
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import dev.steenbakker.mobile_scanner.objects.DetectionSpeed
import dev.steenbakker.mobile_scanner.objects.MobileScannerErrorCodes
import dev.steenbakker.mobile_scanner.objects.MobileScannerStartParameters
import dev.steenbakker.mobile_scanner.utils.serialize
import io.flutter.view.TextureRegistry

class MobileScanner(
    private val activity: Activity,
    private val textureRegistry: TextureRegistry,
    private val mobileScannerCallback: MobileScannerCallback,
    private val mobileScannerErrorCallback: MobileScannerErrorCallback,
    private val deviceOrientationListener: DeviceOrientationListener,
) {

    init {
        configureCameraProcessProvider()
    }

    /// Internal variables
    private var cameraProvider: ProcessCameraProvider? = null
    private var camera: Camera? = null
    private var cameraSelector: CameraSelector? = null
    private var preview: Preview? = null
    private var surfaceProducer: TextureRegistry.SurfaceProducer? = null
    private var lastScanned: List<String?>? = null
    private var imageAnalysis: ImageAnalysis? = null
    private var analysisExecutor: QrCameraWork.Lease? = null
    @Volatile private var active = false
    @Volatile private var epoch = 0
    private data class Frame(val epoch: Int, val values: List<Map<String, Any?>>, val width: Int, val height: Int, val error: Boolean = false)
    private val pendingFrame = java.util.concurrent.atomic.AtomicReference<Frame?>()
    private val frameScheduled = java.util.concurrent.atomic.AtomicBoolean(false)
    private var pendingStart: ((Exception) -> Unit)? = null

    /// Configurable variables
    @Volatile var scanWindow: List<Float>? = null
    private var invertImage: Boolean = false
    private var detectionSpeed: DetectionSpeed = DetectionSpeed.NO_DUPLICATES
    private var detectionTimeout: Long = 250
    private var lastAnalysisAt = -250L
    private var isPaused = false

    companion object {
        // Configure the `ProcessCameraProvider` to only log errors.
        // This prevents the informational log spam from CameraX.
        private fun configureCameraProcessProvider() {
            try {
                val config = CameraXConfig.Builder.fromConfig(Camera2Config.defaultConfig()).apply {
                    setMinimumLoggingLevel(Log.ERROR)
                }
                ProcessCameraProvider.configureInstance(config.build())
            } catch (_: IllegalStateException) {
                // The ProcessCameraProvider was already configured.
                // Do nothing.
            }
        }

    }

    @ExperimentalGetImage
    val captureOutput = ImageAnalysis.Analyzer { image ->
        val current = epoch
        try {
            if (!active) return@Analyzer
            val now = android.os.SystemClock.elapsedRealtime()
            if (detectionSpeed == DetectionSpeed.NORMAL && now - lastAnalysisAt < detectionTimeout) return@Analyzer
            lastAnalysisAt = now
            val plane = image.planes.firstOrNull() ?: return@Analyzer
            val decoded = QrDecoder.decode(QrDecoder.luminance(
                plane.buffer.duplicate(), image.width, image.height,
                plane.rowStride, plane.pixelStride, image.imageInfo.rotationDegrees,
                image.cropRect, scanWindow, invertImage,
            ))
            if (decoded.isNotEmpty()) publishFrame(Frame(current, decoded, image.width, image.height))
        } catch (_: Exception) {
            publishFrame(Frame(current, emptyList(), 0, 0, true))
        } finally {
            image.close()
        }
    }

    private fun publishFrame(frame: Frame) {
        pendingFrame.set(frame)
        if (!frameScheduled.compareAndSet(false, true)) return
        Handler(Looper.getMainLooper()).post {
            val next = pendingFrame.getAndSet(null)
            frameScheduled.set(false)
            if (next == null || !active || epoch != next.epoch) return@post
            if (next.error) { mobileScannerErrorCallback("qr_decode_failed"); return@post }
            val values = next.values.map { it["rawValue"] as String }.sorted()
            if (detectionSpeed == DetectionSpeed.NO_DUPLICATES && values == lastScanned) return@post
            lastScanned = values
            mobileScannerCallback(next.values, null, next.width, next.height)
        }
    }

    private fun failStart(error: Exception) {
        val callback = pendingStart
        pendingStart = null
        stop(true)
        callback?.invoke(error)
    }

    /**
     * Create a {@link Preview.SurfaceProvider} that specifies how to provide a {@link Surface} to a
     * {@code Preview}.
     */
    @VisibleForTesting
    fun createSurfaceProvider(surfaceProducer: TextureRegistry.SurfaceProducer): Preview.SurfaceProvider {
        return Preview.SurfaceProvider {
            request: SurfaceRequest ->
            run {
                // Set the callback for the surfaceProducer to invalidate Surfaces that it produces
                // when they get destroyed.
                surfaceProducer.setCallback(
                    object : TextureRegistry.SurfaceProducer.Callback {
                        override fun onSurfaceAvailable() {
                            // Do nothing. The Preview.SurfaceProvider will handle this
                            // whenever a new Surface is needed.
                        }

                        override fun onSurfaceCleanup() {
                            // Invalidate the SurfaceRequest so that CameraX knows to to make a new request
                            // for a surface.
                            request.invalidate()
                        }
                    }
                )

                // Provide the surface.
                surfaceProducer.setSize(request.resolution.width, request.resolution.height)

                val surface: Surface = surfaceProducer.surface

                // The single thread executor is only used to invoke the result callback.
                // Thus it is safe to use a new executor,
                // instead of reusing the executor that is passed to the camera process provider.
                request.provideSurface(surface, ContextCompat.getMainExecutor(activity)) {
                    // Handle the result of the request for a surface.
                    // See: https://developer.android.com/reference/androidx/camera/core/SurfaceRequest.Result

                    // Always attempt a release.
                    surface.release()

                    val resultCode: Int = it.resultCode

                    when(resultCode) {
                        SurfaceRequest.Result.RESULT_REQUEST_CANCELLED,
                        SurfaceRequest.Result.RESULT_WILL_NOT_PROVIDE_SURFACE,
                        SurfaceRequest.Result.RESULT_SURFACE_ALREADY_PROVIDED,
                        SurfaceRequest.Result.RESULT_SURFACE_USED_SUCCESSFULLY -> {
                            // Only need to release, do nothing.
                        }
                        SurfaceRequest.Result.RESULT_INVALID_SURFACE -> {
                            // The surface was invalid, so it is not clear how to recover from this.
                        }
                        else -> {
                            // Fallthrough, in case any result codes are added later.
                        }
                    }
                }
            }
        }
    }

    @ExperimentalLensFacing
    private fun getCameraLensFacing(camera: Camera?): Int? {
        return when(camera?.cameraInfo?.lensFacing) {
            CameraSelector.LENS_FACING_BACK -> 1
            CameraSelector.LENS_FACING_FRONT -> 0
            CameraSelector.LENS_FACING_EXTERNAL -> 2
            CameraSelector.LENS_FACING_UNKNOWN -> null
            else -> null
        }
    }

    /**
     * Start barcode scanning by initializing the camera and barcode scanner.
     */
    @ExperimentalLensFacing
    @ExperimentalGetImage
    fun start(
        cameraPosition: CameraSelector,
        torch: Boolean,
        detectionSpeed: DetectionSpeed,
        torchStateCallback: TorchStateCallback,
        zoomScaleStateCallback: ZoomScaleStateCallback,
        mobileScannerStartedCallback: MobileScannerStartedCallback,
        mobileScannerErrorCallback: (exception: Exception) -> Unit,
        detectionTimeout: Long,
        cameraResolutionWanted: Size?,
        invertImage: Boolean,
        initialZoom: Double?,
    ) {
        this.detectionSpeed = detectionSpeed
        this.detectionTimeout = detectionTimeout.coerceAtLeast(0)
        lastAnalysisAt = -this.detectionTimeout
        this.invertImage = invertImage

        if (camera?.cameraInfo != null && preview != null && surfaceProducer != null && !isPaused) {

            mobileScannerErrorCallback(AlreadyStarted())

            return
        }

        isPaused = false

        lastScanned = null
        val lease = QrCameraWork.acquire()
        if (lease == null) { mobileScannerErrorCallback(CameraError()); return }
        analysisExecutor = lease
        active = true
        val current = ++epoch
        pendingStart = mobileScannerErrorCallback

        val cameraProviderFuture = ProcessCameraProvider.getInstance(activity)
        val mainExecutor = ContextCompat.getMainExecutor(activity)

        cameraProviderFuture.addListener({
            if (!active || epoch != current) return@addListener
            try {
                cameraProvider = cameraProviderFuture.get()
            } catch (e: Exception) {
                // CameraX can fail to initialize on some devices (e.g.
                // "Available cameras: 0", camera held by another process, or a
                // transient HAL error). get() rethrows that as an uncaught
                // ExecutionException here, which crashes the host app. Route it
                // through the normal error callback instead so the Dart side can
                // surface it via errorBuilder rather than terminating.
                failStart(NoCamera())

                return@addListener
            }
            val numberOfCameras = cameraProvider?.availableCameraInfos?.size

            if (cameraProvider == null) {
                failStart(CameraError())

                return@addListener
            }

            cameraProvider?.unbindAll()
            surfaceProducer = surfaceProducer ?: textureRegistry.createSurfaceProducer()
            val surfaceProvider: Preview.SurfaceProvider = createSurfaceProvider(surfaceProducer!!)

            // Preview

            // Build the preview to be shown on the Flutter texture
            val previewBuilder = Preview.Builder()
            preview = previewBuilder.build().apply { setSurfaceProvider(surfaceProvider) }

            // Camera and gallery keep independent worker quotas.
            val analysisBuilder = ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .setOutputImageFormat(OUTPUT_IMAGE_FORMAT_YUV_420_888)

            val cameraResolution =  cameraResolutionWanted ?: Size(1920, 1080)

            val selectorBuilder = ResolutionSelector.Builder()
            selectorBuilder.setResolutionStrategy(
                ResolutionStrategy(
                    cameraResolution,
                    ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER
                )
            )
            analysisBuilder.setResolutionSelector(selectorBuilder.build()).build()

            deviceOrientationListener.onDisplayRotationChanged = { rotation ->
                imageAnalysis?.targetRotation = rotation
            }

            val analysis = analysisBuilder.build().apply { setAnalyzer(lease, captureOutput) }
            imageAnalysis = analysis

            try {
                camera = cameraProvider?.bindToLifecycle(
                    activity as LifecycleOwner,
                    cameraPosition,
                    preview,
                    analysis
                )
                cameraSelector = cameraPosition
            } catch(_: Exception) {
                failStart(NoCamera())

                return@addListener
            }

            camera?.let {
                // Register the torch listener
                it.cameraInfo.torchState.observe(activity as LifecycleOwner) { state ->
                    // TorchState.OFF = 0; TorchState.ON = 1
                    torchStateCallback(state)
                }

                // Register the zoom scale listener
                it.cameraInfo.zoomState.observe(activity) { state ->
                    zoomScaleStateCallback(state.linearZoom.toDouble())
                }

                // Enable torch if provided
                if (it.cameraInfo.hasFlashUnit()) {
                    it.cameraControl.enableTorch(torch)
                }

                if (initialZoom != null) {
                    try {
                        if (initialZoom in 0.0..1.0) {
                            it.cameraControl.setLinearZoom(initialZoom.toFloat())
                        } else {
                            it.cameraControl.setZoomRatio(initialZoom.toFloat())
                        }
                    } catch (e: Exception) {
                        failStart(ZoomNotInRange())

                        return@addListener
                    }
                }
            }

            val resolution = analysis.resolutionInfo!!.resolution
            val width = resolution.width.toDouble()
            val height = resolution.height.toDouble()
            val sensorRotationDegrees = camera?.cameraInfo?.sensorRotationDegrees ?: 0
            val portrait = sensorRotationDegrees % 180 == 0
            val cameraDirection = getCameraLensFacing(camera)

            // Start with 'unavailable' torch state.
            var currentTorchState: Int = -1

            camera?.cameraInfo?.let {
                if (!it.hasFlashUnit()) {
                    return@let
                }

                currentTorchState = it.torchState.value ?: -1
            }

            deviceOrientationListener.start()

            pendingStart = null
            mobileScannerStartedCallback(
                MobileScannerStartParameters(
                    if (portrait) width else height,
                    if (portrait) height else width,
                    deviceOrientationListener.getOrientation().serialize(),
                    sensorRotationDegrees,
                    surfaceProducer!!.handlesCropAndRotation(),
                    currentTorchState,
                    surfaceProducer!!.id(),
                    numberOfCameras ?: 0,
                    cameraDirection,
                )
            )
        }, mainExecutor)

    }

    /**
     * Pause barcode scanning.
     */
    fun pause(force: Boolean = false) {
        if (!force) {
            if (isPaused) {
                throw AlreadyPaused()
            } else if (isStopped()) {
                throw AlreadyStopped()
            }
        }

        stop(true)
        isPaused = true
    }

    /**
     * Stop barcode scanning.
     */
    fun stop(force: Boolean = false) {
        active = false
        epoch++
        pendingFrame.set(null)
        val pending = pendingStart
        pendingStart = null
        pending?.invoke(CameraError())
        imageAnalysis?.clearAnalyzer()
        analysisExecutor?.close()
        analysisExecutor = null
        if (!force) {
            if (!isPaused && isStopped()) {
                throw AlreadyStopped()
            }
        }

        deviceOrientationListener.stop()
        releaseCamera()
    }

    private fun releaseCamera() {
        val owner = activity as LifecycleOwner
        // Release the camera observers first.
        camera?.cameraInfo?.let {
            it.torchState.removeObservers(owner)
            it.zoomState.removeObservers(owner)
            it.cameraState.removeObservers(owner)
        }

        // Unbind the camera use cases, the preview is a use case.
        // The camera will be closed when the last use case is unbound.
        cameraProvider?.unbindAll()
        camera = null
        preview = null
        cameraSelector = null
        imageAnalysis = null

        // Release the surface for the preview.
        surfaceProducer?.release()
        surfaceProducer = null

        lastScanned = null

    }

    private fun isStopped() = camera == null && preview == null

    /**
     * Toggles the flash light on or off.
     */
    fun toggleTorch() {
        camera?.let {
            if (!it.cameraInfo.hasFlashUnit()) {
                return@let
            }

            when(it.cameraInfo.torchState.value) {
                TorchState.OFF -> it.cameraControl.enableTorch(true)
                TorchState.ON -> it.cameraControl.enableTorch(false)
            }
        }
    }

    /**
     * Set the zoom rate of the camera.
     */
    fun setScale(scale: Double) {
        if (scale > 1.0 || scale < 0) throw ZoomNotInRange()
        if (camera == null) throw ZoomWhenStopped()
        camera?.cameraControl?.setLinearZoom(scale.toFloat())
    }

    fun setZoomRatio(zoomRatio: Double) {
        if (camera == null) throw ZoomWhenStopped()
        camera?.cameraControl?.setZoomRatio(zoomRatio.toFloat())
    }

    /**
     * Reset the zoom rate of the camera.
     */
    fun resetScale() {
        if (camera == null) throw ZoomWhenStopped()
        camera?.cameraControl?.setZoomRatio(1f)
    }

    fun setFocus(x: Float, y: Float) {
        val cam = camera ?: throw ZoomWhenStopped()

        // Ensure x,y are normalized (0f..1f)
        if (x !in 0f..1f || y !in 0f..1f) {
            throw IllegalArgumentException("Focus coordinates must be between 0.0 and 1.0")
        }

        val factory: MeteringPointFactory = SurfaceOrientedMeteringPointFactory(1f, 1f)
        val afPoint: MeteringPoint = factory.createPoint(x, y)

        val action = FocusMeteringAction.Builder(afPoint, FocusMeteringAction.FLAG_AF)
            .build()

        cam.cameraControl.startFocusAndMetering(action)
    }

    /**
     * Dispose of this scanner instance.
     */
    fun dispose() {
        stop(true)
    }
}

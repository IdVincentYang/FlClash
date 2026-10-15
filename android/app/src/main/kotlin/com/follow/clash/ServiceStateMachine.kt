package com.follow.clash

import com.follow.clash.common.RunIntentArbiter
import com.follow.clash.common.ApplicationRequestState
import com.follow.clash.common.RequestNetworkFacts
import com.follow.clash.common.RequestProtection
import com.follow.clash.common.RequestServiceIdentity
import java.util.UUID
import com.follow.clash.models.SharedState
import com.follow.clash.service.models.NotificationParams
import com.follow.clash.service.models.VpnOptions
import com.google.gson.Gson
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlin.coroutines.resume

enum class RunState {
    STARTED,
    STARTING,
    STOPPING,
    STOPPED,
}

internal typealias RunRequest = RunIntentArbiter.Token

internal const val MISSING_CONFIG_MESSAGE = "No configuration found."
internal const val INVALID_CONFIG_MESSAGE = "Invalid configuration."
internal const val VPN_PERMISSION_MESSAGE = "VPN permission required."
internal const val START_FAILED_MESSAGE = "Failed to start service."

/**
 * Callers request a transition; the newest request always wins. Every step that outlives its own
 * suspension point re-checks [isCurrent] before it publishes anything, so a start that was overtaken
 * by a stop cannot report itself as started.
 */
internal class ServiceStateMachine(private val host: ServiceStateHost) {
    private val transitionLock = Mutex()
    private val startPreparationLock = Mutex()
    private val mutableRunState = MutableStateFlow(RunState.STOPPED)
    private val arbiter = RunIntentArbiter()
    private val publicationLock = Any()
    private val mutableRequestState = MutableStateFlow(ApplicationRequestState(processEpoch = UUID.randomUUID().toString()))
    private var networkInput = RequestNetworkFacts()
    private var protection: RequestProtection? = null
    private var protectionIdentity: RequestServiceIdentity? = null
    private var serviceRequestId = 0L

    val requestState = mutableRequestState.asStateFlow()

    fun getRequestState(): ApplicationRequestState = mutableRequestState.value

    fun getNetworkInput(): RequestNetworkFacts = synchronized(publicationLock) { networkInput }

    fun getProtection(): Pair<RequestProtection, RequestServiceIdentity>? = synchronized(publicationLock) {
        val service = protection ?: return@synchronized null
        val identity = protectionIdentity ?: return@synchronized null
        service to identity
    }

    private fun publish(change: (ApplicationRequestState) -> ApplicationRequestState?): Boolean {
        var applied = false
        synchronized(publicationLock) {
            val previous = mutableRequestState.value
            val candidate = change(previous)
            if (candidate != null) {
                var next = candidate.copy(revision = previous.revision + 1)
                if (!host.publishRequestState(next)) {
                    arbiter.resetToStopped(arbiter.current())
                    next = next.copy(revision = next.revision + 1, phase = "failed", reason = "setupFailed")
                    if (!host.publishRequestState(next)) host.blockRequestState()
                }
                mutableRequestState.value = next
                mutableRunState.value = when (next.phase) {
                    "preparing", "starting" -> RunState.STARTING
                    "started" -> RunState.STARTED
                    "stopping" -> RunState.STOPPING
                    else -> RunState.STOPPED
                }
                applied = true
            }
        }
        if (applied) host.finishRequestPublication()
        return applied
    }

    fun prepareRunIntent(running: Boolean, source: String = "ui", paused: Boolean = getRequestState().paused): Long {
        require(source in setOf("ui", "tile", "notification", "alwaysOn", "ssid", "bootstrap", "exit"))
        check(getRequestState().reason != "exiting") { "Application is exiting" }
        lateinit var token: RunRequest
        publish { previous ->
            token = arbiter.request(running && !paused)
            previous.copy(
                intentRevision = token.id,
                intentRunning = running,
                paused = paused,
                source = source,
                phase = if (running && !paused) "preparing" else "stopping",
                reason = when { source == "exit" -> "exiting"; paused && running -> "excludedSsid"; !running -> "userStop"; else -> "none" },
            )
        }
        return token.id
    }

    fun initializeRequestState(expectedRevision: Long, recovery: Boolean): Boolean = publish { previous ->
        if (previous.revision != expectedRevision || previous.intentRunning || runTimeMillis != 0L || previous.phase != "stopped" || previous.reason != "none") null
        else previous.copy(reason = if (recovery) "recovery" else "initializedIdle", phase = if (recovery) "failed" else "stopped")
    }

    fun failRunIntent(requestId: Long): Boolean {
        val request = preparedRequest(requestId) ?: return false
        fail(request)
        return true
    }

    fun observeNetwork(facts: RequestNetworkFacts) {
        publish { previous ->
            if (!host.isNetworkSourceCurrent(facts.sourceEpoch) || facts.sourceEpoch == networkInput.sourceEpoch && facts.revision <= networkInput.revision) null
            else {
                networkInput = facts
                previous.copy(networkRevision = facts.revision, networkSourceEpoch = facts.sourceEpoch, defaultNetworkKind = facts.defaultNetworkKind,
                    defaultNetworkId = facts.defaultNetworkId, directNetworkId = facts.directNetworkId)
            }
        }
    }

    fun bindService(serviceId: String, requestId: Long): Boolean = publish { previous ->
        if (arbiter.current().id != requestId || !previous.intentRunning || previous.paused) null
        else { serviceRequestId = requestId; previous.copy(serviceId = serviceId) }
    }

    fun observeProtection(service: RequestProtection, identity: RequestServiceIdentity, phase: String, reason: String): Long {
        var generation = 0L
        publish { previous ->
            when (phase) {
                "starting" -> if (identity.serviceId != previous.serviceId || arbiter.current().id != identity.requestId || !previous.intentRunning || previous.paused) null else {
                    generation = previous.protectGeneration + 1
                    protection = service
                    protectionIdentity = identity.copy(generation = generation)
                    previous.copy(protectGeneration = generation, protectPhase = "starting")
                }
                "ready" -> if (protection !== service || protectionIdentity != identity || arbiter.current().id != identity.requestId || !previous.intentRunning || previous.paused) null else {
                    generation = identity.generation
                    previous.copy(protectPhase = "ready")
                }
                "retiring", "none" -> if (protection !== service || protectionIdentity != identity) null else {
                    generation = identity.generation
                    if (phase == "none") { protection = null; protectionIdentity = null }
                    if (reason == "vpnRevoked" && serviceRequestId == arbiter.current().id) {
                        arbiter.resetToStopped(arbiter.current())
                        previous.copy(protectPhase = phase, phase = "failed", reason = reason)
                    } else previous.copy(protectPhase = phase)
                }
                else -> null
            }
        }
        return generation
    }

    fun observeBindingLost(requestId: Long) {
        publish { previous ->
            val current = arbiter.current()
            if (current.id != requestId || !previous.intentRunning || previous.phase !in setOf("preparing", "starting")) null
            else { arbiter.resetToStopped(current); previous.copy(phase = "failed", reason = "serviceLost") }
        }
    }

    fun observeServiceLost(serviceId: String, requestId: Long) {
        publish { previous ->
            if (previous.serviceId != serviceId || serviceRequestId != requestId) null else {
                protection = null
                protectionIdentity = null
                val current = arbiter.current()
                if (current.id == requestId) {
                    arbiter.resetToStopped(current)
                    previous.copy(serviceId = "", protectPhase = "none", phase = "failed", reason = "serviceLost")
                } else previous.copy(serviceId = "", protectPhase = "none")
            }
        }
    }

    private fun setPhase(request: RunRequest, phase: String) = publish { previous ->
        if (!isCurrent(request)) null else previous.copy(phase = phase)
    }

    private fun preparedRequest(requestId: Long): RunRequest? = arbiter.current().takeIf { it.id == requestId }


    @Volatile
    private var sharedState = SharedState()

    @Volatile
    private var pendingVpnPreparation: (() -> Unit)? = null

    val runState = mutableRunState.asStateFlow()

    private val runTimeMillis: Long
        get() = host.runTimeMillis

    suspend fun handleToggleAction(source: String = "notification") {
        if (isRunningRequested()) {
            handleStopAction(source)
        } else {
            handleStartAction(source)
        }
    }

    suspend fun refresh(): Long = runTimeMillis

    fun captureRequestToken(): RunRequest = arbiter.current()

    /**
     * Settles the state after the bound service was lost. [token] is the request that was current
     * when the loss was observed, so a start that raced ahead of this callback keeps its intent.
     */
    suspend fun handleServiceLost(token: RunRequest) = transitionLock.withLock {
        if (runTimeMillis != 0L) {
            return@withLock
        }
        publish { previous ->
            if (!arbiter.resetToStopped(token)) null else previous.copy(phase = "failed", reason = "serviceLost")
        }
    }

    suspend fun handleStartAction(source: String = "tile") {
        if (isRunningRequested()) {
            return
        }
        val requestId = prepareRunIntent(running = true, source = source)
        handlePreparedStartAction(requestId)
    }

    suspend fun handleStopAction(source: String = "notification") {
        val previous = getRequestState()
        val idle = !previous.intentRunning && runTimeMillis == 0L && previous.serviceId.isEmpty() && previous.protectPhase == "none"
        val requestId = prepareRunIntent(running = false, source = source)
        if (idle) { requestStop(requestId).await(); return }
        val tile = host.tile()
        if (tile != null) {
            tile.handleStop(requestId)
            return
        }
        host.showToast(sharedState.stopTip)
        requestStop(requestId).await()
    }

    suspend fun handleVpnRevokeAction() {
        if (getRequestState().reason == "vpnRevoked") reconcileStopped()
    }

    suspend fun handlePreparedStartAction(requestId: Long) {
        val request = preparedRequest(requestId) ?: return
        if (!request.running) return
        val tile = host.tile()
        if (tile != null) { tile.handleStart(requestId); return }
        loadPreferencesAndStart(request)
    }

    fun requestStart(requestId: Long? = null): Deferred<Boolean> {
        val id = requestId ?: prepareRunIntent(running = true)
        val request = preparedRequest(id) ?: return CompletableDeferred(false)
        if (!request.running) return CompletableDeferred(false)
        val result = CompletableDeferred<Boolean>()
        val launchRequest: (Boolean) -> Unit = { shouldStart ->
            if (!shouldStart) {
                fail(request, "permissionDenied")
                result.complete(false)
            } else {
                host.scope.launch {
                    result.complete(
                        runCatching { start(request) }
                            .onFailure { error ->
                                host.log("Unable to process service start request: $error")
                                fail(request)
                                reconcileStopped()
                            }
                            .getOrDefault(false),
                    )
                }
            }
        }
        val app = host.app()
        if (app != null) {
            app.requestNotificationPermission { shouldStart ->
                if (shouldStart) {
                    app.requestLocalNetworkPermission { launchRequest(true) }
                } else {
                    launchRequest(false)
                }
            }
        } else {
            launchRequest(true)
        }
        return result
    }

    fun requestStop(requestId: Long? = null): Deferred<Boolean> {
        val id = requestId ?: prepareRunIntent(running = false)
        val request = preparedRequest(id) ?: return CompletableDeferred(false)
        if (request.running) return CompletableDeferred(false)
        val result = CompletableDeferred<Boolean>()
        host.scope.launch {
            result.complete(
                runCatching { stop(request) }
                    .onFailure { error ->
                        host.log("Unable to process service stop request: $error")
                    }
                    .getOrDefault(false),
            )
        }
        return result
    }

    fun syncSharedState(state: SharedState) {
        sharedState = state
        applySharedState()
    }

    private suspend fun loadPreferencesAndStart(request: RunRequest) {
        val loadedState = host.loadSharedStateForStart() ?: run { fail(request); return }
        if (!isCurrent(request)) return
        sharedState = loadedState
        if (sharedState.setupParams == null || sharedState.vpnOptions == null) {
            host.showToast(MISSING_CONFIG_MESSAGE)
            fail(request)
            return
        }
        if (setupCore() && isCurrent(request)) {
            if (!requestStart(request.id).await()) {
                host.showToast(START_FAILED_MESSAGE)
            }
        } else { fail(request) }
    }

    private fun applySharedState() {
        host.updateNotificationParams(notificationParams(sharedState))
    }

    private suspend fun setupCore(): Boolean {
        applySharedState()
        host.showToast(sharedState.startTip)
        return host.quickSetup(
            initParams(host.homeDirPath, host.sdkInt),
            Gson().toJson(sharedState.setupParams),
        ).fold(
            onSuccess = { message ->
                if (message.isEmpty()) {
                    true
                } else {
                    host.log("Unable to set up core: $message")
                    showConfigError(message)
                    false
                }
            },
            onFailure = { error ->
                host.log("Unable to set up core: $error")
                showConfigError(error.message)
                false
            },
        )
    }

    private fun showConfigError(message: String?) {
        host.showToast(message?.takeIf { it.isNotBlank() } ?: INVALID_CONFIG_MESSAGE)
    }

    private suspend fun start(request: RunRequest): Boolean = startPreparationLock.withLock {
        val started = runStart(request)
        if (!started) {
            reconcileStopped()
        }
        started
    }

    private suspend fun runStart(request: RunRequest): Boolean {
        if (!isCurrent(request)) {
            return false
        }
        val options = sharedState.vpnOptions
        if (options == null) {
            fail(request)
            return false
        }
        if (!prepareVpn(options)) {
            if (host.app() == null && isCurrent(request)) {
                host.showToast(VPN_PERMISSION_MESSAGE)
            }
            fail(request, "permissionDenied")
            return false
        }
        if (!isCurrent(request)) {
            return false
        }

        return transitionLock.withLock transition@{
            if (!isCurrent(request)) {
                return@transition false
            }
            if (runTimeMillis != 0L && host.isVpnServiceActive() == options.enable) {
                host.adoptServiceRequest(request.id)
                if (!isCurrent(request)) return@transition false
                setPhase(request, "started")
                return@transition true
            }
            setPhase(request, "starting")
            val startedAtMillis = host.startService(withLocalNetworkFallback(options), request.id)
            if (startedAtMillis == 0L) {
                fail(request)
                return@transition false
            }
            if (!isCurrent(request)) {
                return@transition false
            }
            setPhase(request, "started")
            true
        }
    }

    // system/mixed hand TCP to the kernel via the tun subnet, which Android 17 gates as local network.
    private fun withLocalNetworkFallback(options: VpnOptions): VpnOptions {
        if (!options.enable || options.stack !in KERNEL_TCP_STACKS ||
            host.isLocalNetworkPermissionGranted()
        ) {
            return options
        }
        host.showToast(sharedState.localNetworkTip)
        return options.copy(stack = FALLBACK_STACK)
    }

    private suspend fun reconcileStopped() = transitionLock.withLock {
        if (isRunningRequested() || runTimeMillis == 0L) {
            return@withLock
        }
        val request = arbiter.current()
        setPhase(request, "stopping")
        host.stopService()
        setPhase(request, if (getRequestState().reason in setOf("setupFailed", "permissionDenied", "serviceLost", "vpnRevoked", "recovery")) "failed" else "stopped")
    }

    private suspend fun stop(request: RunRequest): Boolean = transitionLock.withLock {
        if (!isCurrent(request)) {
            return@withLock false
        }
        abandonVpnPreparation()
        val snapshot = getRequestState()
        if (runTimeMillis == 0L && snapshot.serviceId.isEmpty() && snapshot.protectPhase == "none") {
            setPhase(request, "stopped")
            return@withLock true
        }
        setPhase(request, "stopping")
        host.stopService()
        setPhase(request, "stopped")
        isCurrent(request)
    }

    private suspend fun prepareVpn(options: VpnOptions): Boolean {
        val app = host.app()
            ?: return !options.enable || host.isVpnPermissionGranted()
        return suspendCancellableCoroutine { continuation ->
            val callback: (Boolean) -> Unit = { granted ->
                pendingVpnPreparation = null
                if (continuation.isActive) {
                    continuation.resume(granted)
                }
            }
            pendingVpnPreparation = {
                app.cancelVpnPreparation(callback)
                callback(false)
            }
            continuation.invokeOnCancellation {
                pendingVpnPreparation = null
                app.cancelVpnPreparation(callback)
            }
            app.prepareVpn(options.enable, callback)
        }
    }

    private fun abandonVpnPreparation() {
        val abandon = pendingVpnPreparation ?: return
        pendingVpnPreparation = null
        abandon()
    }

    private fun isRunningRequested(): Boolean = arbiter.isRunningRequested

    private fun isCurrent(request: RunRequest): Boolean = arbiter.isCurrent(request)

    private fun fail(request: RunRequest, reason: String = "setupFailed") {
        publish { previous ->
            if (!arbiter.resetToStopped(request)) null else previous.copy(phase = "failed", reason = reason)
        }
    }

    internal companion object {
        val KERNEL_TCP_STACKS = setOf("system", "mixed")
        const val FALLBACK_STACK = "gvisor"

        /**
         * The Core init payload. The key spelling is a cross-language contract with the Go wrapper,
         * not an implementation detail.
         */
        fun initParams(homeDirPath: String, sdkInt: Int): String = Gson().toJson(
            mapOf(
                "home-dir" to homeDirPath,
                "version" to sdkInt,
            ),
        )

        fun notificationParams(state: SharedState): NotificationParams = NotificationParams(
            title = state.currentProfileName,
            stopText = state.stopText,
            onlyStatisticsProxy = state.onlyStatisticsProxy,
            showStopAction = state.showStopAction,
        )
    }
}

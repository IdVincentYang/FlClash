package com.follow.clash

import com.follow.clash.common.RunIntentArbiter
import com.follow.clash.common.ApplicationRequestState
import com.follow.clash.common.RequestNetworkFacts
import com.follow.clash.common.RequestProtection
import com.follow.clash.common.RequestServiceIdentity
import java.util.UUID
import com.follow.clash.models.SharedState
import com.follow.clash.models.ConfigReceipt
import com.follow.clash.models.ConfigApplyResult
import com.follow.clash.models.ConfigFact
import com.follow.clash.models.ConfigCleanupResult
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicLong
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
    private var retiringService: RequestServiceIdentity? = null
    private val configToken = AtomicLong()
    @Volatile private var configFact = ConfigFact()
    private var preparedOptionsFingerprint: String? = null
    @Volatile private var pendingConfigReceipt = ConfigReceipt()

    val requestState = mutableRequestState.asStateFlow()

    fun getRequestState(): ApplicationRequestState = mutableRequestState.value

    fun configOperationToken(): Long = configToken.get()

    fun getNetworkInput(): RequestNetworkFacts = synchronized(publicationLock) { networkInput }

    fun getProtection(): Pair<RequestProtection, RequestServiceIdentity>? = synchronized(publicationLock) {
        val service = protection ?: return@synchronized null
        val identity = protectionIdentity ?: return@synchronized null
        service to identity
    }

    private fun publish(change: (ApplicationRequestState) -> ApplicationRequestState?): Boolean {
        var applied = false
        var phaseChanged = false
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
                phaseChanged = previous.phase != next.phase
                mutableRunState.value = when (next.phase) {
                    "preparing", "starting" -> RunState.STARTING
                    "started" -> RunState.STARTED
                    "stopping" -> RunState.STOPPING
                    else -> RunState.STOPPED
                }
                applied = true
            }
        }
        if (applied) {
            host.finishRequestPublication()
            if (phaseChanged) applySharedState()
        }
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

    suspend fun failRunIntent(requestId: Long, token: Long, abort: Boolean = true): ConfigCleanupResult {
        val request = preparedRequest(requestId) ?: return ConfigCleanupResult("superseded")
        val receipt = pendingConfigReceipt
        if (abort && receipt.owner != 0L && receipt.token == token && isCurrent(request) && configToken.get() == token) {
            val result = host.configPhase("abortConfig", receipt)
            if (result.status == "superseded") return ConfigCleanupResult("superseded")
            observeConfigFact(result.fact, authoritative = true)
        }
        return transitionLock.withLock {
            if (!isCurrent(request) || configToken.get() != token) return@withLock ConfigCleanupResult("superseded")
            val state = getRequestState()
            val identity = RequestServiceIdentity(state.serviceId, serviceRequestId, if (state.protectPhase in setOf("starting", "ready")) state.protectGeneration else 0)
            fail(request)
            synchronized(publicationLock) { retiringService = identity }
            try {
                val cleaned = identity.serviceId.isEmpty() || host.stopOwnedService(identity)
                if (arbiter.current().id != request.id || configToken.get() != token) return@withLock ConfigCleanupResult("superseded")
                if (!cleaned) return@withLock ConfigCleanupResult("cleanupFailed", "Owned service cleanup did not complete")
                preparedOptionsFingerprint = null
                applySharedState()
                ConfigCleanupResult("cleaned")
            } catch (error: Exception) {
                ConfigCleanupResult("cleanupFailed", error.message.orEmpty())
            }
        }
    }

    fun observeConfigFact(fact: ConfigFact, authoritative: Boolean = false) {
        val previous = configFact
        if (fact.runtimeEpoch.isEmpty() || !authoritative && previous.runtimeEpoch.isNotEmpty() && fact.runtimeEpoch != previous.runtimeEpoch || fact.runtimeEpoch == previous.runtimeEpoch && fact.version < previous.version) return
        configFact = fact
        applySharedState()
    }

    suspend fun failConfigBuild(input: JsonObject): ConfigApplyResult {
        val request = arbiter.current()
        val token = configToken.get()
        val state = getRequestState()
        val expectedRun = input.getAsJsonObject("expectedRun")
        val expectedToken = input.get("registeredToken")?.takeUnless { it.isJsonNull }?.asLong
        if (expectedToken != null && expectedToken != token || expectedRun != null && (
            expectedRun.get("processEpoch")?.asString != state.processEpoch ||
            expectedRun.get("intentRevision")?.asLong != state.intentRevision ||
            expectedRun.get("intentRunning")?.asBoolean != state.intentRunning ||
            expectedRun.get("paused")?.asBoolean != state.paused
        )) return ConfigApplyResult("superseded", fact = configFact)
        val payload = input.deepCopy().apply {
            if (!has("expectedRun")) add("expectedRun", Gson().toJsonTree(state))
            if (!has("registeredToken")) addProperty("registeredToken", token)
        }
        val result = host.failConfigBuild(payload)
        if (!isCurrent(request) || configToken.get() != token) return ConfigApplyResult("superseded", fact = configFact)
        observeConfigFact(result.fact, authoritative = true)
        if (result.status != "blocked") return result
        val cleanup = failRunIntent(request.id, token, abort = false)
        return if (cleanup.status == "cleaned") result else result.copy(status = cleanup.status, message = cleanup.message)
    }

    fun applyConfig(input: JsonObject): Deferred<ConfigApplyResult> {
        val state = getRequestState()
        val expectedRequest = input.get("requestId")?.takeUnless { it.isJsonNull }?.asLong
        if (expectedRequest != null && expectedRequest != state.intentRevision) return CompletableDeferred(ConfigApplyResult("superseded"))
        val request = arbiter.current()
        val desired = sharedState
        val payload = input.deepCopy().apply {
            add("expectedRun", Gson().toJsonTree(state))
            addProperty("active", input.get("active")?.asBoolean != false && state.intentRunning && !state.paused)
            add("init", JsonParser.parseString(initParams(host.homeDirPath, host.sdkInt)))
        }
        val receipt = host.registerConfigInput(payload)
        configToken.accumulateAndGet(receipt.token, ::maxOf)
        if (configToken.get() == receipt.token) {
            pendingConfigReceipt = receipt
            abandonVpnPreparation()
        }
        val result = CompletableDeferred<ConfigApplyResult>()
        host.scope.launch {
            val applied = startPreparationLock.withLock {
                runCatching { runConfigApply(request, payload.get("active").asBoolean, desired, receipt, state) }
                    .getOrElse { error ->
                        host.log("Unable to apply configuration: $error")
                        val owned = pendingConfigReceipt.takeIf { it.token == receipt.token } ?: receipt
                        finishConfigFailure(request, owned, error.message.orEmpty())
                    }
            }
            result.complete(applied)
        }
        return result
    }

    private fun currentConfigRequest(request: RunRequest, receipt: ConfigReceipt): Boolean =
        isCurrent(request) && configToken.get() == receipt.token

    private suspend fun finishConfigFailure(request: RunRequest, receipt: ConfigReceipt, message: String): ConfigApplyResult {
        if (!currentConfigRequest(request, receipt)) return ConfigApplyResult("superseded", receipt = receipt)
        val aborted = runCatching { host.configPhase("abortConfig", receipt) }.getOrNull()
        if (aborted?.status == "superseded") return aborted
        if (aborted != null) observeConfigFact(aborted.fact, authoritative = true)
        val cleanup = failRunIntent(request.id, receipt.token, abort = false)
        return ConfigApplyResult(if (cleanup.status == "cleaned") "blocked" else cleanup.status, message.ifEmpty { cleanup.message }, receipt, fact = aborted?.fact ?: configFact)
    }

    private suspend fun runConfigApply(request: RunRequest, active: Boolean, desired: SharedState, registered: ConfigReceipt, expectedRun: ApplicationRequestState): ConfigApplyResult {
        if (!currentConfigRequest(request, registered)) return ConfigApplyResult("superseded", receipt = registered)
        val prepared = host.configPhase("prepareConfig", registered)
        if (currentConfigRequest(request, registered)) pendingConfigReceipt = prepared.receipt
        if (prepared.status != "prepared") {
            observeConfigFact(prepared.fact, authoritative = true)
            if (prepared.status == "staleInput") return prepared
            if (prepared.status == "rejected" && currentConfigRequest(request, registered)) {
                val failed = failConfigBuild(JsonObject().apply {
                    add("expected", Gson().toJsonTree(prepared.fact))
                    add("expectedRun", Gson().toJsonTree(expectedRun))
                    addProperty("registeredToken", registered.token)
                })
                if (failed.status != "retained") return failed
            }
            if (active && getRequestState().phase == "preparing" && currentConfigRequest(request, registered)) failRunIntent(request.id, registered.token)
            return prepared
        }
        val receipt = prepared.receipt
        observeConfigFact(prepared.fact, authoritative = true)
        var serviceReceipt = receipt
        if (active) {
            if (!prepareStartPermissions()) return finishConfigFailure(request, receipt, "Notification permission denied")
            val core = requireNotNull(prepared.coreParams)
            val desiredOptions = requireNotNull(desired.vpnOptions) { MISSING_CONFIG_MESSAGE }
            val options = withLocalNetworkFallback(desiredOptions.copy(
                port = core.mixedPort,
                systemProxy = desired.systemProxyRequested && host.sdkInt >= 29 && core.bindingId != 0L && core.mixedPort != 0 && core.localReachable && !core.authenticationRequired,
            ))
            if (!prepareVpn(options)) return finishConfigFailure(request, receipt, VPN_PERMISSION_MESSAGE)
            val fingerprint = MessageDigest.getInstance("SHA-256").digest(Gson().toJson(options).toByteArray()).joinToString("") { "%02x".format(it) }
            val preparedService = transitionLock.withLock {
                if (!currentConfigRequest(request, receipt)) return@withLock null
                val before = getRequestState()
                val compatible = runTimeMillis != 0L && preparedOptionsFingerprint == fingerprint && host.isVpnServiceActive() == options.enable && serviceRequestId == request.id && before.serviceId.isNotEmpty()
                setPhase(request, "starting")
                if (!compatible) {
                    if (before.serviceId.isNotEmpty()) {
                        val old = RequestServiceIdentity(before.serviceId, serviceRequestId, if (before.protectPhase in setOf("starting", "ready")) before.protectGeneration else 0)
                        synchronized(publicationLock) { retiringService = old }
                        check(host.stopOwnedService(old)) { "Owned service cleanup did not complete" }
                    }
                    if (!currentConfigRequest(request, receipt)) return@withLock null
                    check(host.startService(options, request.id) != 0L) { START_FAILED_MESSAGE }
                    preparedOptionsFingerprint = fingerprint
                }
                if (!currentConfigRequest(request, receipt)) return@withLock null
                val state = getRequestState()
                check(state.serviceId.isNotEmpty() && (!options.enable || state.protectGeneration != 0L && state.protectPhase == "ready")) { START_FAILED_MESSAGE }
                receipt.copy(serviceId = state.serviceId, protectGeneration = if (options.enable) state.protectGeneration else 0, optionsFingerprint = fingerprint)
            } ?: return ConfigApplyResult("superseded", receipt = receipt)
            serviceReceipt = preparedService
        }
        val installed = host.configPhase("installConfig", receipt)
        observeConfigFact(installed.fact, authoritative = true)
        if (installed.status != "installed") {
            if (installed.status in setOf("superseded", "bootstrapRequired")) return installed
            return finishConfigFailure(request, receipt, installed.message)
        }
        return transitionLock.withLock {
            if (!currentConfigRequest(request, receipt)) return@withLock ConfigApplyResult("superseded", receipt = receipt)
            val activated = host.configPhase("activateConfig", serviceReceipt)
            observeConfigFact(activated.fact, authoritative = true)
            if (activated.status == "activated") setPhase(request, "started")
            activated
        }.let { activated ->
            if (activated.status in setOf("activated", "installedInactive", "superseded")) activated
            else finishConfigFailure(request, receipt, activated.message)
        }
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
                if (retiringService?.let { it.serviceId == serviceId && it.requestId == requestId } == true) {
                    retiringService = null
                    serviceRequestId = 0
                    previous.copy(serviceId = "", protectPhase = "none")
                } else if (current.id == requestId) {
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
    private var hasSharedState = false

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

    suspend fun refresh(): Long = if (getRequestState().phase == "started" && configFact.businessActive) runTimeMillis else 0L

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
        val originalToken = configToken.get()
        host.scope.launch {
            val started = try { start(request) } catch (error: Exception) {
                host.log("Unable to process service start request: $error")
                failRunIntent(request.id, originalToken)
                false
            }
            result.complete(started)
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
        hasSharedState = true
        applySharedState()
    }

    private suspend fun loadPreferencesAndStart(request: RunRequest): Boolean {
        val originalToken = configToken.get()
        val loaded = try { if (hasSharedState) sharedState else host.loadSharedStateForStart() } catch (error: Exception) {
            host.log("Unable to read service preferences: $error")
            null
        }
        if (loaded == null) {
            if (isCurrent(request)) {
                showConfigError(MISSING_CONFIG_MESSAGE)
                failRunIntent(request.id, originalToken)
            }
            return false
        }
        if (!isCurrent(request)) return false
        sharedState = loaded
        hasSharedState = true
        applySharedState()
        if (sharedState.vpnOptions == null) {
            showConfigError(MISSING_CONFIG_MESSAGE)
            failRunIntent(request.id, originalToken)
            return false
        }
        host.showToast(sharedState.startTip)
        return try {
            val input = host.replayConfigInput().apply { addProperty("requestId", request.id) }
            val result = applyConfig(input).await()
            if (result.status != "activated") {
                showConfigError(result.message)
                if (result.status == "bootstrapRequired") failRunIntent(request.id, result.receipt.token)
            }
            result.status == "activated"
        } catch (error: Exception) {
            showConfigError(error.message)
            failRunIntent(request.id, originalToken)
            false
        }
    }

    private fun applySharedState() {
        val state = getRequestState()
        val title = when {
            state.phase == "started" && configFact.businessActive && configFact.phase == "ready" -> configFact.profileName.ifEmpty { "FlClash" }
            state.phase in setOf("preparing", "starting") -> sharedState.configApplyingTip
            else -> sharedState.configInactiveTip
        }
        host.updateNotificationParams(notificationParams(sharedState).copy(title = title))
    }

    private fun showConfigError(message: String?) {
        host.showToast(message?.takeIf { it.isNotBlank() } ?: INVALID_CONFIG_MESSAGE)
    }

    private suspend fun start(request: RunRequest): Boolean = loadPreferencesAndStart(request)

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

    private suspend fun prepareStartPermissions(): Boolean {
        val app = host.app() ?: return true
        return suspendCancellableCoroutine { continuation ->
            app.requestNotificationPermission { granted ->
                if (!granted) {
                    if (continuation.isActive) continuation.resume(false)
                } else {
                    app.requestLocalNetworkPermission { if (continuation.isActive) continuation.resume(true) }
                }
            }
        }
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
            if (!arbiter.resetToStopped(request)) null else previous.copy(intentRunning = false, phase = "failed", reason = reason)
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
            title = "FlClash",
            stopText = state.stopText,
            onlyStatisticsProxy = state.onlyStatisticsProxy,
            showStopAction = state.showStopAction,
        )
    }
}

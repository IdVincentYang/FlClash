package com.follow.clash

import com.follow.clash.models.SharedState
import com.follow.clash.common.ApplicationRequestState
import com.follow.clash.common.GlobalState
import com.follow.clash.common.RequestNetworkFacts
import com.follow.clash.common.RequestObservationHandler
import com.follow.clash.common.RequestObservations
import com.follow.clash.common.RequestProtection
import com.follow.clash.common.RequestServiceIdentity
import com.follow.clash.core.Core
import kotlinx.coroutines.launch
import io.flutter.embedding.engine.FlutterEngine
import kotlinx.coroutines.Deferred

object ServiceState {
    private val machine = ServiceStateMachine(AndroidServiceStateHost)

    val runState = machine.runState
    val requestState = machine.requestState

    fun getRequestState(): ApplicationRequestState = machine.getRequestState()

    fun configOperationToken(): Long = machine.configOperationToken()

    fun getNetworkInput(): RequestNetworkFacts = machine.getNetworkInput()

    fun getProtection(): Pair<RequestProtection, RequestServiceIdentity>? = machine.getProtection()

    fun prepareRunIntent(running: Boolean, source: String = "ui", paused: Boolean = getRequestState().paused): Long {
        val requestId = machine.prepareRunIntent(running, source, paused)
        if (source == "exit") GlobalState.stopRequestNetworkObservation()
        return requestId
    }

    fun initializeRequestState(expectedRevision: Long, recovery: Boolean): Boolean = machine.initializeRequestState(expectedRevision, recovery)

    suspend fun failRunIntent(requestId: Long, token: Long) = machine.failRunIntent(requestId, token)

    suspend fun failConfigBuild(input: com.google.gson.JsonObject) = machine.failConfigBuild(input)

    fun applyConfig(input: com.google.gson.JsonObject) = machine.applyConfig(input)

    fun observeConfigFact(fact: com.follow.clash.models.ConfigFact) = machine.observeConfigFact(fact)

    fun bindService(serviceId: String, requestId: Long): Boolean = machine.bindService(serviceId, requestId)

    fun observeBindingLost(requestId: Long) = machine.observeBindingLost(requestId)

    fun observeServiceLost(serviceId: String, requestId: Long) = machine.observeServiceLost(serviceId, requestId)

    internal fun bindRequestObservers() {
        Core.setRequestSocketListener(AndroidRequestSocketGate)
        RequestObservations.handler = object : RequestObservationHandler {
            override fun onNetworkChanged(facts: RequestNetworkFacts) = machine.observeNetwork(facts)
            override fun onProtectionChanged(service: RequestProtection, identity: RequestServiceIdentity, phase: String, reason: String): Long =
                machine.observeProtection(service, identity, phase, reason)
            override fun onServiceLost(serviceId: String, requestId: Long) = machine.observeServiceLost(serviceId, requestId)
            override fun onVpnStartRequested(serviceId: String): Long {
                if (machine.getRequestState().reason == "exiting") return 0
                val requestId = machine.prepareRunIntent(running = true, source = "alwaysOn")
                if (!machine.bindService(serviceId, requestId)) return 0
                GlobalState.launch { machine.handlePreparedStartAction(requestId) }
                return requestId
            }
        }
    }

    fun attachFlutterEngine(engine: FlutterEngine) =
        AndroidServiceStateHost.attachFlutterEngine(engine)

    fun detachFlutterEngine(engine: FlutterEngine) =
        AndroidServiceStateHost.detachFlutterEngine(engine)

    suspend fun handleToggleAction() = machine.handleToggleAction()

    suspend fun handleStartAction() = machine.handleStartAction()

    suspend fun handleStopAction() = machine.handleStopAction()

    suspend fun handleVpnRevokeAction() = machine.handleVpnRevokeAction()

    suspend fun refresh(): Long = machine.refresh()

    fun requestStart(requestId: Long? = null): Deferred<Boolean> = machine.requestStart(requestId)

    fun requestStop(requestId: Long? = null): Deferred<Boolean> = machine.requestStop(requestId)

    fun syncSharedState(state: SharedState) = machine.syncSharedState(state)

    internal fun captureRequestToken(): RunRequest = machine.captureRequestToken()

    internal suspend fun handleServiceLost(token: RunRequest) = machine.handleServiceLost(token)
}

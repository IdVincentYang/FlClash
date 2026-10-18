package com.follow.clash

import com.follow.clash.models.SharedState
import com.google.gson.Gson
import com.google.gson.JsonElement
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking

// Local test transport: real ServiceStateMachine with controlled Core and OS hosts.
object ConfigApplyBridge {
    @JvmStatic fun main(args: Array<String>) = runBlocking {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val host = ConfigServiceTestHost(scope)
        val machine = host.createMachine()
        val gson = Gson()
        var dataset = 1L
        var receiptSequence = 0L
        fun reply(id: JsonElement, result: Any?) = synchronized(System.out) {
            println(gson.toJson(mapOf("id" to id, "result" to result)))
            System.out.flush()
        }
        scope.launch {
            machine.requestState.collect { state ->
                synchronized(System.out) {
                    println(gson.toJson(mapOf("event" to "requestState","value" to gson.toJson(state))))
                    System.out.flush()
                }
            }
        }
        while (true) {
            val line = readlnOrNull() ?: break
            val call = JsonParser.parseString(line).asJsonObject
            val id = call.get("id")
            val method = call.get("method").asString
            val arguments = call.get("arguments")
            try {
                when (method) {
                    "init" -> reply(id, "")
                    "syncState" -> { machine.syncSharedState(gson.fromJson(arguments.asString, SharedState::class.java)); reply(id, "") }
                    "getRequestState" -> {
                        val state = gson.toJsonTree(machine.getRequestState()).asJsonObject
                        state.addProperty("configToken",machine.configOperationToken())
                        reply(id,gson.toJson(state))
                    }
                    "initializeRequestState" -> reply(id, true)
                    "prepareRunIntent" -> reply(id, machine.prepareRunIntent(arguments.asJsonObject.get("running").asBoolean))
                    "getRunTime" -> reply(id, machine.refresh())
                    "stop" -> { machine.requestStop(arguments?.takeUnless { it.isJsonNull }?.asLong); reply(id,true) }
                    "shutdown" -> reply(id,true)
                    "applyConfig" -> {
                        val pending = machine.applyConfig(JsonParser.parseString(arguments.asString).asJsonObject)
                        scope.launch { reply(id,gson.toJson(pending.await())) }
                    }
                    "failRunIntent" -> scope.launch {
                        val cleanup = machine.failRunIntent(arguments.asJsonObject.get("requestId").asLong, arguments.asJsonObject.get("token").asLong)
                        reply(id,gson.toJson(cleanup))
                    }
                    "failConfigBuild" -> scope.launch {
                        reply(id,gson.toJson(machine.failConfigBuild(JsonParser.parseString(arguments.asString).asJsonObject)))
                    }
                    "invokeMethod" -> {
                        val core = JsonParser.parseString(arguments.asString).asJsonObject
                        val result = when(core.get("method").asString) {
                            "getConfigState" -> host.lastConfigFact
                            "getConfig" -> mapOf("mode" to "rule","proxies" to listOf(mapOf("name" to "reset","type" to "direct")),"proxy-groups" to emptyList<Any>(),"rule" to listOf("MATCH,REJECT"))
                            "getExternalProviders" -> emptyList<Any>()
                            "getProxies" -> mapOf("proxies" to emptyMap<String,Any>(),"providers" to emptyMap<String,Any>())
                            else -> true
                        }
                        val envelope = mapOf("id" to core.get("id"),"result" to result)
                        reply(id,gson.toJson(envelope))
                    }
                    "requestControl" -> {
                        val control = JsonParser.parseString(arguments.asString).asJsonObject
                        val result: Any = when(control.get("action").asString) {
                            "attach" -> { dataset++; mapOf("client" to "bridge") }
                            "ready" -> mapOf("ready" to true)
                            "inspect" -> mapOf("state" to machine.getRequestState(),"owner" to host.lastConfigFact.owner,"dataset" to dataset,"sourceRevision" to 0,"operation" to 0,"commits" to 0)
                            "grant", "lock" -> mapOf("ok" to true,"id" to "local-${++receiptSequence}")
                            else -> mapOf("ok" to true)
                        }
                        reply(id,gson.toJson(result))
                    }
                    "startCleanupFixture" -> scope.launch {
                        host.cleanupFailure = null
                        reply(id, machine.requestStart().await())
                    }
                    "revokeCleanupFixture" -> {
                        host.buildFailureStatus = "blocked"
                        host.cleanupFailure = arguments.asString
                        host.lastConfigFact = host.lastConfigFact.copy(version=host.lastConfigFact.version+1,profileId=1,replayEligible=false)
                        machine.observeConfigFact(host.lastConfigFact,authoritative=true)
                        reply(id,true)
                    }
                    "holdCleanupAndFailInstall" -> {
                        host.cleanupGate=CompletableDeferred()
                        host.failingPhase="installConfig"
                        reply(id,true)
                    }
                    "bootstrapInstall" -> {
                        host.failingPhase="installConfig"
                        host.phaseFailureStatus="bootstrapRequired"
                        reply(id,true)
                    }
                    "allowInstall" -> { host.failingPhase=null;host.phaseFailureStatus="blocked";reply(id,true) }
                    "holdActivation" -> {
                        host.phaseGate=CompletableDeferred()
                        host.phaseEntered=CompletableDeferred()
                        host.heldPhase="activateConfig"
                        reply(id,true)
                    }
                    "waitHeldPhase" -> scope.launch { host.phaseEntered!!.await();reply(id,true) }
                    "releasePhase" -> { host.phaseGate?.complete(Unit);reply(id,true) }
                    "releaseCleanup" -> { host.failingPhase=null; host.cleanupGate?.complete(Unit); reply(id,true) }
                    "snapshot" -> reply(id,mapOf("state" to machine.getRequestState(),"fact" to host.lastConfigFact,"starts" to host.startCalls,"stops" to host.stopCalls,"phases" to host.phaseCalls.toList()))
                    else -> error("Unsupported test transport method")
                }
            } catch (error: Exception) {
                reply(id,mapOf("error" to error.toString()))
            }
        }
        scope.cancel()
    }
}

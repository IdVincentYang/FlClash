package com.follow.clash

import com.follow.clash.common.ApplicationRequestState
import com.follow.clash.models.ConfigApplyResult
import com.follow.clash.models.ConfigReceipt
import com.google.gson.Gson
import com.google.gson.JsonElement
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking

// Production machine and Core; only Android service/permission operations use the controlled host.
object ServiceCoreBridge {
    @JvmStatic fun main(args: Array<String>) = runBlocking {
        val gson = Gson()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val home = requireNotNull(System.getenv("L2_CORE_BRIDGE_HOME"))
        val child = ProcessBuilder(requireNotNull(System.getenv("FLCLASH_APPLICATION_INPUT_BRIDGE")), "-test.run=^TestApplicationInputBridge$")
            .directory(File(requireNotNull(System.getenv("L2_CORE_BRIDGE_CWD"))))
            .apply {
                environment()["FLCLASH_APPLICATION_INPUT_BRIDGE_HOME"] = home
                redirectError(File(home, "core-stderr.log"))
            }.start()
        val reader = child.inputStream.bufferedReader()
        val writer = child.outputStream.bufferedWriter()
        val gate = Any()
        var sequence = 0
        fun call(method: String, arguments: Any? = null): JsonElement = synchronized(gate) {
            val id = ++sequence
            writer.write(gson.toJson(mapOf("id" to id, "method" to method, "arguments" to arguments)))
            writer.newLine()
            writer.flush()
            while (true) {
                val line = reader.readLine() ?: error("Core bridge closed")
                if (!line.startsWith("application-input-bridge:")) continue
                val response = JsonParser.parseString(line.substringAfter(':')).asJsonObject
                check(response.get("id").asInt == id)
                return@synchronized response.get("result")
            }
            @Suppress("UNREACHABLE_CODE") error("Core response unavailable")
        }
        val fixture = call("fixture")
        val service = ConfigServiceTestHost(scope)
        val host = object : ServiceStateHost by service {
            override val homeDirPath = home
            override fun publishRequestState(state: ApplicationRequestState): Boolean =
                call("control", mapOf("action" to "publish", "state" to state)).asJsonObject.get("applied").asBoolean
            override fun finishRequestPublication() { call("control", mapOf("action" to "flush")) }
            override fun blockRequestState() { call("control", mapOf("action" to "block")) }
            override fun registerConfigInput(input: JsonObject): ConfigReceipt = gson.fromJson(call("register", input), ConfigReceipt::class.java)
            override suspend fun configPhase(method: String, receipt: ConfigReceipt): ConfigApplyResult =
                gson.fromJson(call(when(method) {
                    "prepareConfig" -> "prepare"
                    "installConfig" -> "install"
                    "activateConfig" -> "activate"
                    "abortConfig" -> "abort"
                    else -> error("Unsupported Core phase")
                }, receipt), ConfigApplyResult::class.java)
            override suspend fun failConfigBuild(input: JsonObject): ConfigApplyResult =
                gson.fromJson(call("fail", input), ConfigApplyResult::class.java)
        }
        val machine = service.createMachine(host)
        machine.syncSharedState(service.storedSharedState)
        try {
            while (true) {
                val line = readlnOrNull() ?: break
                val input = JsonParser.parseString(line).asJsonObject
                val arguments = input.get("arguments")
                val result: Any = when (input.get("method").asString) {
                    "fixture" -> fixture
                    "fact" -> call("fact")
                    "prepare" -> mapOf("requestId" to machine.prepareRunIntent(arguments.asBoolean))
                    "apply" -> machine.applyConfig(arguments.asJsonObject).await()
                    "pauseIntent" -> mapOf("state" to machine.preparePauseIntent(arguments.asBoolean))
                    "pause" -> {
                        val state = machine.preparePauseIntent(true)
                        mapOf("stopped" to machine.requestStop(state.intentRevision).await(), "state" to machine.getRequestState())
                    }
                    "stop" -> {
                        val id = machine.prepareRunIntent(false)
                        mapOf("stopped" to machine.requestStop(id).await(), "state" to machine.getRequestState())
                    }
                    "lose" -> {
                        val identity = requireNotNull(service.ownedService())
                        machine.observeServiceLost(identity.serviceId, identity.requestId)
                        mapOf("state" to machine.getRequestState())
                    }
                    "snapshot" -> mapOf("state" to machine.getRequestState(), "fact" to call("fact"), "starts" to service.startCalls, "stops" to service.stopCalls)
                    "probe" -> call("probe", arguments.asString)
                    else -> error("Unsupported service test operation")
                }
                println("application-input-bridge:" + gson.toJson(mapOf("id" to input.get("id"), "result" to result)))
                System.out.flush()
            }
        } catch (error: Throwable) {
            File(home, "native-error.log").writeText(error.stackTraceToString())
            throw error
        } finally {
            scope.cancel()
            writer.close()
            child.waitFor()
        }
    }
}

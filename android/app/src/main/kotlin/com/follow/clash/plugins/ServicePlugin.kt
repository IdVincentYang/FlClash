package com.follow.clash.plugins

import com.follow.clash.ServiceController
import com.follow.clash.ServiceState
import com.follow.clash.common.Components
import com.follow.clash.core.Core
import com.google.gson.JsonParser
import com.follow.clash.models.SharedState
import com.google.gson.Gson
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.Job

class ServicePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var scope: CoroutineScope
    private val gson = Gson()
    private var requestStateJob: Job? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        channel = MethodChannel(binding.binaryMessenger, "${Components.PACKAGE_NAME}/service")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        runCatching { Core.requestControl("{\"action\":\"engineDetach\"}") }
        scope.cancel()
        ServiceController.setEventListener(null)
    }

    override fun onMethodCall(call: MethodCall, rawResult: MethodChannel.Result) {
        // Most handlers below reply from a scope worker on Dispatchers.Default,
        // but a MethodChannel.Result has to be answered on the platform thread.
        // Wrapping once here covers every branch, including notImplemented.
        val result = MainThreadResult(rawResult)
        when (call.method) {
            "init" -> initialize(result)
            "shutdown" -> shutdown(result)
            "invokeMethod" -> invokeMethod(call, result)
            "getRunTime" -> getRunTime(result)
            "syncState" -> syncState(call, result)
            "start" -> start(call, result)
            "stop" -> stop(call, result)
            "getRequestState" -> result.success(gson.toJson(ServiceState.getRequestState()))
            "prepareRunIntent" -> prepareRunIntent(call, result)
            "failRunIntent" -> result.success((call.arguments as? Number)?.toLong()?.let(ServiceState::failRunIntent) ?: false)
            "initializeRequestState" -> initializeRequestState(call, result)
            "requestControl" -> requestControl(call, result)
            else -> result.notImplemented()
        }
    }

    private fun initialize(result: MethodChannel.Result) {
        requestStateJob?.cancel()
        requestStateJob = scope.launch {
            ServiceState.requestState.collect { state ->
                scope.launch(Dispatchers.Main) { channel.invokeMethod("requestState", gson.toJson(state)) }
            }
        }
        ServiceController.setEventListener(::sendEvent)
            .onSuccess { result.success("") }
            .onFailure { error -> result.success(error.message.orEmpty()) }
    }

    private fun shutdown(result: MethodChannel.Result) {
        scope.launch {
            ServiceController.unbind()
            result.success(true)
        }
    }

    private fun invokeMethod(call: MethodCall, result: MethodChannel.Result) {
        val data = call.arguments as? String
        if (data == null) {
            result.error("INVALID_ARGUMENT", "Method call payload must be a string", null)
            return
        }
        // Inline rather than a coroutine per call, which could swap two: watchRoute
        // keeps the latest intent by the order calls reach the Core
        // (dispatchMethodCall in core/method.go), and this only hands data over.
        ServiceController.invokeMethod(data) { response ->
            result.success(response)
        }.onFailure { error ->
            result.error("CORE_ERROR", error.message, null)
        }
    }

    private fun getRunTime(result: MethodChannel.Result) {
        scope.launch {
            result.success(ServiceState.refresh())
        }
    }

    private fun syncState(call: MethodCall, result: MethodChannel.Result) {
        val data = call.arguments as? String
        val state = runCatching {
            gson.fromJson(data, SharedState::class.java)
        }.getOrNull()
        if (state == null) {
            result.success("Invalid shared state")
            return
        }
        scope.launch {
            ServiceState.syncSharedState(state)
            result.success("")
        }
    }

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        ServiceState.requestStart((call.arguments as? Number)?.toLong())
        result.success(true)
    }

    private fun stop(call: MethodCall, result: MethodChannel.Result) {
        ServiceState.requestStop((call.arguments as? Number)?.toLong())
        result.success(true)
    }

    private fun prepareRunIntent(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *> ?: return result.error("INVALID_ARGUMENT", "Missing intent", null)
        val running = args["running"] as? Boolean ?: return result.error("INVALID_ARGUMENT", "Missing running value", null)
        val source = args["source"] as? String ?: "ui"
        val paused = args["paused"] as? Boolean ?: ServiceState.getRequestState().paused
        runCatching { ServiceState.prepareRunIntent(running, source, paused) }
            .onSuccess { result.success(it) }
            .onFailure { result.error("INVALID_ARGUMENT", "Invalid intent", null) }
    }

    private fun initializeRequestState(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *> ?: return result.error("INVALID_ARGUMENT", "Missing initialization", null)
        val revision = (args["revision"] as? Number)?.toLong() ?: return result.error("INVALID_ARGUMENT", "Missing revision", null)
        result.success(ServiceState.initializeRequestState(revision, args["recovery"] == true))
    }

    private fun requestControl(call: MethodCall, result: MethodChannel.Result) {
        val data = call.arguments as? String ?: return result.error("INVALID_ARGUMENT", "Missing request control", null)
        val action = runCatching { JsonParser.parseString(data).asJsonObject.get("action").asString }.getOrNull()
        if (action !in setOf("begin", "cancel", "check", "grant", "attach", "ready", "inspect", "permit", "invalidate", "invalidateDataset", "lock", "complete", "detach")) {
            result.error("INVALID_ARGUMENT", "Invalid request control", null)
            return
        }
        runCatching { Core.requestControl(data) }
            .onSuccess { result.success(it) }
            .onFailure { result.error("REQUEST_CONTROL_FAILED", "Request control unavailable", null) }
    }

    private fun sendEvent(value: String?) {
        scope.launch(Dispatchers.Main) {
            channel.invokeMethod("event", value)
        }
    }
}

package com.follow.clash

import android.Manifest
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import androidx.core.content.ContextCompat
import com.follow.clash.common.GlobalState
import com.follow.clash.common.ApplicationRequestState
import com.follow.clash.core.Core
import com.google.gson.Gson
import com.google.gson.JsonParser
import com.follow.clash.models.SharedState
import com.follow.clash.models.ConfigReceipt
import com.follow.clash.models.ConfigApplyResult
import com.google.gson.JsonObject
import com.follow.clash.common.RequestServiceIdentity
import com.follow.clash.plugins.AppPlugin
import com.follow.clash.plugins.TilePlugin
import com.follow.clash.service.ServiceConfig
import com.follow.clash.service.models.NotificationParams
import com.follow.clash.service.models.VpnOptions
import io.flutter.embedding.engine.FlutterEngine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * The machine owns the arbitration and the transitions; this is only the part that cannot run on a
 * plain JVM, so unit tests can drive the state machine with an in-memory implementation.
 */
internal interface ServiceStateHost {
    val scope: CoroutineScope
    val runTimeMillis: Long
    val homeDirPath: String
    val sdkInt: Int

    fun log(message: String)

    fun showToast(message: String)

    fun updateNotificationParams(params: NotificationParams)

    fun loadSharedState(): SharedState

    suspend fun loadSharedStateForStart(): SharedState? = loadSharedState()

    fun isVpnPermissionGranted(): Boolean

    fun isLocalNetworkPermissionGranted(): Boolean

    fun tile(): TileGateway?

    fun app(): AppGateway?


    suspend fun startService(options: VpnOptions): Long

    suspend fun stopService()

    suspend fun isVpnServiceActive(): Boolean

    fun publishRequestState(state: ApplicationRequestState): Boolean = true

    fun finishRequestPublication() {}

    fun blockRequestState() {}

    fun isNetworkSourceCurrent(epoch: String): Boolean = true

    suspend fun startService(options: VpnOptions, requestId: Long): Long = startService(options)

    suspend fun adoptServiceRequest(requestId: Long) {}

    fun registerConfigInput(input: JsonObject): ConfigReceipt = error("Configuration registration unavailable")

    suspend fun configPhase(method: String, receipt: ConfigReceipt): ConfigApplyResult = error("Configuration phase unavailable")

    suspend fun failConfigBuild(input: JsonObject): ConfigApplyResult = error("Configuration cleanup unavailable")

    suspend fun replayConfigInput(): JsonObject = error("Configuration checkpoint unavailable")

    suspend fun stopOwnedService(identity: RequestServiceIdentity): Boolean = false
}

internal interface TileGateway {
    fun handleStart()

    fun handleStop()

    fun handleStart(requestId: Long) = handleStart()

    fun handleStop(requestId: Long) = handleStop()
}

internal interface AppGateway {
    fun requestNotificationPermission(callback: (Boolean) -> Unit)

    fun requestLocalNetworkPermission(callback: (Boolean) -> Unit)

    fun prepareVpn(enable: Boolean, callback: (Boolean) -> Unit)

    fun cancelVpnPreparation(callback: (Boolean) -> Unit)
}

internal object AndroidServiceStateHost : ServiceStateHost {
    @Volatile
    private var flutterEngine: FlutterEngine? = null

    override val scope: CoroutineScope
        get() = GlobalState

    override val runTimeMillis: Long
        get() = ServiceController.getRunTimeMillis()

    override val homeDirPath: String
        get() = GlobalState.application.filesDir.path

    override val sdkInt: Int
        get() = android.os.Build.VERSION.SDK_INT

    fun attachFlutterEngine(engine: FlutterEngine) {
        flutterEngine = engine
    }

    fun detachFlutterEngine(engine: FlutterEngine) {
        if (flutterEngine === engine) {
            flutterEngine = null
        }
    }

    override fun log(message: String) = GlobalState.log(message)

    override fun showToast(message: String) = GlobalState.application.showToast(message)

    override fun updateNotificationParams(params: NotificationParams) =
        ServiceConfig.updateNotificationParams(params)

    override fun loadSharedState(): SharedState = GlobalState.application.sharedState

    override suspend fun loadSharedStateForStart(): SharedState? = withContext(Dispatchers.IO) {
        runCatching {
            val result = JsonParser.parseString(Core.requestControl("{\"action\":\"readData\"}")).asJsonObject
            val id = result.get("id")?.asString ?: return@runCatching null
            try { loadSharedState() }
            finally { Core.requestControl(Gson().toJson(mapOf("action" to "endRead", "id" to id))) }
        }.getOrNull()
    }

    override fun isVpnPermissionGranted(): Boolean =
        VpnService.prepare(GlobalState.application) == null

    override fun isLocalNetworkPermissionGranted(): Boolean =
        sdkInt < Build.VERSION_CODES.CINNAMON_BUN ||
            ContextCompat.checkSelfPermission(
                GlobalState.application,
                Manifest.permission.ACCESS_LOCAL_NETWORK,
            ) == PackageManager.PERMISSION_GRANTED

    override fun tile(): TileGateway? = flutterEngine?.plugin<TilePlugin>()?.let { plugin ->
        object : TileGateway {
            override fun handleStart() = plugin.handleStart()

            override fun handleStop() = plugin.handleStop()

            override fun handleStart(requestId: Long) = plugin.handleStart(requestId)

            override fun handleStop(requestId: Long) = plugin.handleStop(requestId)
        }
    }

    override fun app(): AppGateway? = flutterEngine?.plugin<AppPlugin>()?.let { plugin ->
        object : AppGateway {
            override fun requestNotificationPermission(callback: (Boolean) -> Unit) =
                plugin.requestNotificationPermission(callback)

            override fun requestLocalNetworkPermission(callback: (Boolean) -> Unit) =
                plugin.requestLocalNetworkPermission(callback)

            override fun prepareVpn(enable: Boolean, callback: (Boolean) -> Unit) =
                plugin.prepareVpn(enable, callback)

            override fun cancelVpnPreparation(callback: (Boolean) -> Unit) =
                plugin.cancelVpnPreparation(callback)
        }
    }

    override suspend fun startService(options: VpnOptions): Long =
        ServiceController.start(options, ServiceState.captureRequestToken().id)

    override suspend fun startService(options: VpnOptions, requestId: Long): Long = ServiceController.start(options, requestId)

    override suspend fun adoptServiceRequest(requestId: Long) = ServiceController.adoptRequest(requestId)

    override fun registerConfigInput(input: JsonObject): ConfigReceipt {
        val request = Gson().toJson(mapOf("action" to "registerConfigInput", "ConfigInput" to input))
        val response = JsonParser.parseString(Core.requestControl(request)).asJsonObject
        check(!response.has("error")) { "Configuration registration rejected" }
        return Gson().fromJson(response, ConfigReceipt::class.java)
    }

    override suspend fun configPhase(method: String, receipt: ConfigReceipt): ConfigApplyResult =
        Gson().fromJson(ServiceController.configCall(method, Gson().toJsonTree(receipt)), ConfigApplyResult::class.java)

    override suspend fun failConfigBuild(input: JsonObject): ConfigApplyResult =
        Gson().fromJson(ServiceController.configCall("failConfigBuild", input), ConfigApplyResult::class.java)

    override suspend fun replayConfigInput(): JsonObject = ServiceController.configCall(
        "getReplayInput", JsonParser.parseString(ServiceStateMachine.initParams(homeDirPath, sdkInt)),
    ).asJsonObject

    override suspend fun stopOwnedService(identity: RequestServiceIdentity): Boolean = ServiceController.stopOwned(identity)

    override fun publishRequestState(state: ApplicationRequestState): Boolean = runCatching {
        val response = Core.requestControl(Gson().toJson(mapOf("action" to "publish", "state" to state)))
        JsonParser.parseString(response).asJsonObject.get("applied")?.asBoolean == true
    }.getOrDefault(false)

    override fun blockRequestState() { runCatching { Core.requestControl("{\"action\":\"block\"}") } }

    override fun finishRequestPublication() { runCatching { Core.requestControl("{\"action\":\"flush\"}") } }

    override fun isNetworkSourceCurrent(epoch: String): Boolean = GlobalState.networkSource?.selection()?.facts?.sourceEpoch == epoch

    override suspend fun stopService() = ServiceController.stop()

    override suspend fun isVpnServiceActive(): Boolean = ServiceController.isVpnServiceActive()
}

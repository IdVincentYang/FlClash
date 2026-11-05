package com.follow.clash

import android.app.Application
import android.os.Looper
import com.follow.clash.core.Core
import com.follow.clash.plugins.ServicePlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows
import org.robolectric.annotation.Config
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.util.ReflectionHelpers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest

@RunWith(RobolectricTestRunner::class)
@Config(application = Application::class, sdk = [31], shadows = [RequestControlCoreShadow::class])
class ServicePluginRequestControlTest {
    @OptIn(ExperimentalCoroutinesApi::class)
    @Test fun unregisteredCleanupFlagReachesActualStateMachine() = runTest {
        val host = ConfigServiceTestHost(backgroundScope)
        val machine = ReflectionHelpers.getStaticField<ServiceStateMachine>(ServiceState::class.java, "machine")
        val previousHost = ReflectionHelpers.getField<ServiceStateHost>(machine, "host")
        ReflectionHelpers.setField(host, "machine", machine)
        ReflectionHelpers.setField(machine, "host", object : ServiceStateHost by host {
            override suspend fun configPhase(method: String, receipt: com.follow.clash.models.ConfigReceipt): com.follow.clash.models.ConfigApplyResult =
                if (method == "abortConfig") com.follow.clash.models.ConfigApplyResult("superseded", receipt = receipt, fact = host.lastConfigFact)
                else host.configPhase(method, receipt)
        })
        try {
            machine.syncSharedState(host.storedSharedState)
            val idle = machine.prepareRunIntent(false)
            assertEquals("installedInactive", machine.applyConfig(com.google.gson.JsonParser.parseString("""{"inputId":"${"a".repeat(64)}","requestId":$idle}""").asJsonObject).await().status)
            val token = machine.configOperationToken()
            val request = machine.prepareRunIntent(true)
            val plugin = ServicePlugin()
            ReflectionHelpers.setField(plugin, "scope", backgroundScope)
            var response: String? = null
            plugin.onMethodCall(MethodCall("failRunIntent", mapOf("requestId" to request, "token" to token, "unregistered" to true)), object : MethodChannel.Result {
                override fun success(result: Any?) { response = result as String }
                override fun error(errorCode: String, message: String?, details: Any?) { fail(errorCode) }
                override fun notImplemented() { fail("cleanup missing") }
            })
            testScheduler.runCurrent()
            Shadows.shadowOf(Looper.getMainLooper()).idle()
            assertEquals("cleaned", com.google.gson.JsonParser.parseString(response).asJsonObject.get("status").asString)
            assertEquals("failed", machine.getRequestState().phase)
            assertFalse(machine.getRequestState().intentRunning)
        } finally {
            ReflectionHelpers.setField(machine, "host", previousHost)
        }
    }

    private fun invoke(plugin: ServicePlugin, payload: String): Pair<String?, Any?> {
        var code: String? = null
        var value: Any? = null
        plugin.onMethodCall(MethodCall("requestControl", payload), object : MethodChannel.Result {
            override fun success(result: Any?) { value = result }
            override fun error(errorCode: String, message: String?, details: Any?) { code = errorCode }
            override fun notImplemented() { fail("requestControl missing") }
        })
        Shadows.shadowOf(Looper.getMainLooper()).idle()
        return code to value
    }

    @Test fun commitActionsReachCoreWithoutRewritingReceiptOwnership() {
        val plugin = ServicePlugin()
        for (action in listOf("beginCommit", "markRecovery", "clearRecovery", "complete")) {
            val payload = """{"action":"$action","id":"owned-receipt","client":"owned-client"}"""
            RequestControlCoreShadow.received = null
            RequestControlCoreShadow.response = """{"error":"request_restart_required"}"""
            val result = invoke(plugin, payload)
            assertNull(result.first)
            assertEquals(payload, RequestControlCoreShadow.received)
            assertEquals(RequestControlCoreShadow.response, result.second)
        }
    }

    @Test fun internalAndUnknownActionsNeverReachCore() {
        val plugin = ServicePlugin()
        for (action in listOf("publish", "block", "engineDetach", "registerConfigInput", "readData", "anything", "")) {
            RequestControlCoreShadow.received = null
            assertEquals("INVALID_ARGUMENT", invoke(plugin, """{"action":"$action"}""").first)
            assertNull(RequestControlCoreShadow.received)
        }
        assertEquals("INVALID_ARGUMENT", invoke(plugin, "not-json").first)
    }
}

@Implements(Core::class)
class RequestControlCoreShadow {
    @Implementation fun requestControl(data: String): String {
        received = data
        return response
    }

    companion object {
        var received: String? = null
        var response = "{}"
        @JvmStatic @Implementation fun __staticInitializer__() {
            ReflectionHelpers.setStaticField(Core::class.java, "INSTANCE", ReflectionHelpers.callConstructor(Core::class.java))
        }
    }
}

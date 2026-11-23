package com.nihaisha.nihaisha_app

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

/**
 * Main-engine bridge for the isolated Android Keystore capability.
 *
 * All Keystore operations execute on a dedicated worker. MainActivity only
 * registers this plugin; it does not own license, key or token business logic.
 */
internal class LicensePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private val keystore = LicenseKeystore()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var executor: ExecutorService? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
        executor = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "yanji-license-keystore").apply { isDaemon = true }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        executor?.shutdown()
        executor = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getDeviceKey" -> dispatch(result) { keystore.getDeviceKey().toChannelMap() }
            "createDeviceKeyForActivation" ->
                dispatch(result) { keystore.createDeviceKeyForActivation().toChannelMap() }
            "signActivationRequest" -> {
                val payload = call.argument<String>("payloadBase64Url")
                if (payload == null) {
                    result.error("invalidArgument", "缺少 payloadBase64Url。", null)
                } else {
                    dispatch(result) {
                        mapOf("signatureBase64Url" to keystore.signActivationRequest(payload))
                    }
                }
            }
            "checkPrivateKeyUsability" ->
                dispatch(result) { keystore.checkPrivateKeyUsability().toChannelMap() }
            else -> result.notImplemented()
        }
    }

    private fun dispatch(
        result: MethodChannel.Result,
        operation: () -> Any
    ) {
        val worker = executor
        if (worker == null) {
            result.error("keystoreUnavailable", "授权插件尚未完成初始化。", null)
            return
        }

        try {
            worker.execute {
                try {
                    val value = operation()
                    mainHandler.post { result.success(value) }
                } catch (error: LicenseKeystoreException) {
                    mainHandler.post {
                        result.error(error.code, error.message, null)
                    }
                } catch (error: Exception) {
                    mainHandler.post {
                        result.error(
                            "providerError",
                            "设备密钥操作失败：${error.javaClass.simpleName}",
                            null
                        )
                    }
                }
            }
        } catch (_: RejectedExecutionException) {
            result.error("keystoreUnavailable", "授权插件正在关闭，设备密钥操作未执行。", null)
        }
    }

    private companion object {
        const val CHANNEL_NAME = "com.nihaisha.nihaisha_app/licensing"
    }
}

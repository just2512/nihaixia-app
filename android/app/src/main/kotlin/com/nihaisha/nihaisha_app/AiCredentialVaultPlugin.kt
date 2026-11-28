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
 * Dedicated Flutter bridge for provider API credentials.
 * It is separate from LicensePlugin/LicenseKeystore/LicenseTokenStore.
 */
internal class AiCredentialVaultPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var executor: ExecutorService? = null
    private var store: AiCredentialVaultStore? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        store = AiCredentialVaultStore(binding.applicationContext)
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
        executor = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "yanji-ai-credential-vault").apply { isDaemon = true }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        store = null
        executor?.shutdown()
        executor = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "save" -> {
                val providerId = call.argument<String>("providerId")
                val secret = call.argument<String>("secret")
                if (providerId == null || secret == null) {
                    result.error(
                        "CREDENTIAL_INPUT_INVALID",
                        "缺少供应商标识或凭证。",
                        null,
                    )
                } else {
                    dispatch(result) {
                        mapOf("credentialRef" to requireStore().save(providerId, secret))
                    }
                }
            }
            "read" -> {
                val credentialRef = call.argument<String>("credentialRef")
                if (credentialRef == null) {
                    result.error("CREDENTIAL_REFERENCE_INVALID", "凭证引用无效。", null)
                } else {
                    dispatch(result) {
                        val secret = requireStore().read(credentialRef)
                        if (secret == null) {
                            mapOf("found" to false)
                        } else {
                            mapOf(
                                "found" to true,
                                "providerId" to secret.providerId,
                                "secret" to secret.secret,
                            )
                        }
                    }
                }
            }
            "delete" -> {
                val credentialRef = call.argument<String>("credentialRef")
                if (credentialRef == null) {
                    result.error("CREDENTIAL_REFERENCE_INVALID", "凭证引用无效。", null)
                } else {
                    dispatch(result) {
                        mapOf("deleted" to requireStore().delete(credentialRef))
                    }
                }
            }
            "exists" -> {
                val credentialRef = call.argument<String>("credentialRef")
                if (credentialRef == null) {
                    result.error("CREDENTIAL_REFERENCE_INVALID", "凭证引用无效。", null)
                } else {
                    dispatch(result) {
                        mapOf("exists" to requireStore().exists(credentialRef))
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun requireStore(): AiCredentialVaultStore =
        store ?: throw AiCredentialVaultException(
            "CREDENTIAL_VAULT_UNAVAILABLE",
            "设备安全凭证库尚未初始化。",
        )

    private fun dispatch(result: MethodChannel.Result, operation: () -> Any) {
        val worker = executor
        if (worker == null) {
            result.error(
                "CREDENTIAL_VAULT_UNAVAILABLE",
                "设备安全凭证库尚未初始化。",
                null,
            )
            return
        }
        try {
            worker.execute {
                try {
                    val value = operation()
                    mainHandler.post { result.success(value) }
                } catch (error: AiCredentialVaultException) {
                    mainHandler.post {
                        result.error(error.code, error.safeMessage, null)
                    }
                } catch (_: Exception) {
                    mainHandler.post {
                        result.error(
                            "CREDENTIAL_VAULT_UNAVAILABLE",
                            "设备安全凭证操作失败。",
                            null,
                        )
                    }
                }
            }
        } catch (_: RejectedExecutionException) {
            result.error(
                "CREDENTIAL_VAULT_UNAVAILABLE",
                "设备安全凭证库正在关闭，操作未执行。",
                null,
            )
        }
    }

    private companion object {
        const val CHANNEL_NAME = "com.nihaisha.app/ai_credential_vault"
    }
}

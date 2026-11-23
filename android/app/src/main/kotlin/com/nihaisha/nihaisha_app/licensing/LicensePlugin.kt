package com.nihaisha.nihaisha_app.licensing

import android.os.Build
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.util.AtomicFile
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.IOException
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.SecureRandom
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import java.util.Base64
import java.util.concurrent.Executors

private const val LICENSE_CHANNEL = "com.nihaisha.nihaisha_app/licensing"
private const val DEVICE_KEY_ALIAS = "yanji.pro.device.p256.v1"
private const val MAX_TOKEN_CHARS = 16_384
private const val MAX_TOKEN_BYTES = 16_384

class LicensePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val keyCreationLock = Any()

    private var channel: MethodChannel? = null
    private var applicationContext: android.content.Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, LICENSE_CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        applicationContext = null
        ioExecutor.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        ioExecutor.execute {
            try {
                val context = applicationContext
                    ?: throw LicensePlatformException("PLATFORM_UNAVAILABLE")
                val value = when (call.method) {
                    "readActiveToken" -> readActiveToken(context)
                    "writeActiveTokenAtomically" -> {
                        val token = call.argument<String>("token")
                            ?: throw LicensePlatformException("INVALID_TOKEN")
                        writeActiveTokenAtomically(context, token)
                        null
                    }
                    "deleteActiveToken" -> {
                        deleteActiveToken(context)
                        null
                    }
                    "getDeviceKey" -> deviceKeyInfo(requireExisting = true)
                    "createDeviceKeyForActivation" -> synchronized(keyCreationLock) {
                        createDeviceKeyForActivation()
                    }
                    "checkPrivateKeyUsability" -> {
                        checkPrivateKeyUsability()
                        null
                    }
                    else -> {
                        mainHandler.post { result.notImplemented() }
                        return@execute
                    }
                }
                mainHandler.post { result.success(value) }
            } catch (error: LicensePlatformException) {
                mainHandler.post {
                    result.error(error.code, error.message, null)
                }
            } catch (error: SecurityException) {
                mainHandler.post {
                    result.error("KEYSTORE_UNAVAILABLE", error.message, null)
                }
            } catch (error: IOException) {
                mainHandler.post {
                    result.error("STORAGE_UNAVAILABLE", error.message, null)
                }
            } catch (error: Exception) {
                mainHandler.post {
                    result.error("PROVIDER_ERROR", error.message, null)
                }
            }
        }
    }

    private fun tokenFile(context: android.content.Context): AtomicFile {
        val directory = File(context.noBackupFilesDir, "yanji_license")
        if (!directory.exists() && !directory.mkdirs()) {
            throw LicensePlatformException("STORAGE_UNAVAILABLE", "Cannot create license directory")
        }
        if (!directory.isDirectory) {
            throw LicensePlatformException("STORAGE_UNAVAILABLE", "License path is not a directory")
        }
        return AtomicFile(File(directory, "active_license.token"))
    }

    private fun readActiveToken(context: android.content.Context): String? {
        val atomicFile = tokenFile(context)
        if (!atomicFile.baseFile.exists()) return null
        return try {
            atomicFile.openRead().use { input ->
                val output = ByteArrayOutputStream()
                val buffer = ByteArray(4096)
                var total = 0
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    total += read
                    if (total > MAX_TOKEN_BYTES) {
                        throw LicensePlatformException("STORE_CORRUPT", "Token exceeds size limit")
                    }
                    output.write(buffer, 0, read)
                }
                val bytes = output.toByteArray()
                val token = bytes.toString(Charsets.UTF_8)
                if (token.isBlank() || token != token.trim() || !token.startsWith("YANJI1.")) {
                    throw LicensePlatformException("STORE_CORRUPT", "Token file format is invalid")
                }
                token
            }
        } catch (error: LicensePlatformException) {
            throw error
        } catch (error: IOException) {
            throw LicensePlatformException("STORE_CORRUPT", error.message)
        }
    }

    private fun writeActiveTokenAtomically(
        context: android.content.Context,
        token: String
    ) {
        if (token.isBlank() || token.length > MAX_TOKEN_CHARS ||
            token != token.trim() || !token.startsWith("YANJI1.")
        ) {
            throw LicensePlatformException("INVALID_TOKEN", "Token format or size is invalid")
        }
        val atomicFile = tokenFile(context)
        var stream: java.io.FileOutputStream? = null
        try {
            stream = atomicFile.startWrite()
            stream.write(token.toByteArray(Charsets.UTF_8))
            stream.flush()
            stream.fd.sync()
            atomicFile.finishWrite(stream)
        } catch (error: Exception) {
            if (stream != null) atomicFile.failWrite(stream)
            throw LicensePlatformException("STORAGE_UNAVAILABLE", error.message)
        }
    }

    private fun deleteActiveToken(context: android.content.Context) {
        tokenFile(context).delete()
    }

    private fun loadKeyStore(): KeyStore =
        KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    private fun createDeviceKeyForActivation(): Map<String, String> {
        val keyStore = loadKeyStore()
        if (!keyStore.containsAlias(DEVICE_KEY_ALIAS)) {
            generateDeviceKey()
        }
        return deviceKeyInfo(requireExisting = true)
    }

    private fun generateDeviceKey() {
        fun generate(strongBox: Boolean) {
            val generator = KeyPairGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_EC,
                "AndroidKeyStore"
            )
            val builder = KeyGenParameterSpec.Builder(
                DEVICE_KEY_ALIAS,
                KeyProperties.PURPOSE_SIGN
            )
                .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                .setDigests(KeyProperties.DIGEST_SHA256)
                .setUserAuthenticationRequired(false)
            if (strongBox) builder.setIsStrongBoxBacked(true)
            generator.initialize(builder.build())
            generator.generateKeyPair()
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                generate(strongBox = true)
            } catch (_: StrongBoxUnavailableException) {
                // Fall back only when StrongBox is explicitly unavailable.
                generate(strongBox = false)
            }
        } else {
            generate(strongBox = false)
        }
    }

    private fun loadPrivateKey(): PrivateKey {
        val keyStore = loadKeyStore()
        if (!keyStore.containsAlias(DEVICE_KEY_ALIAS)) {
            throw LicensePlatformException("KEY_MISSING")
        }
        return (keyStore.getKey(DEVICE_KEY_ALIAS, null) as? PrivateKey)
            ?: throw LicensePlatformException("KEY_INVALIDATED")
    }

    private fun deviceKeyInfo(requireExisting: Boolean): Map<String, String> {
        val keyStore = loadKeyStore()
        if (!keyStore.containsAlias(DEVICE_KEY_ALIAS)) {
            if (requireExisting) throw LicensePlatformException("KEY_MISSING")
            throw LicensePlatformException("KEY_MISSING")
        }
        val certificate = keyStore.getCertificate(DEVICE_KEY_ALIAS)
            ?: throw LicensePlatformException("KEY_INVALIDATED")
        val spki = certificate.publicKey.encoded
        if (spki.isEmpty()) throw LicensePlatformException("KEY_INVALIDATED")

        val digest = MessageDigest.getInstance("SHA-256").digest(spki)
        val keyInfo = try {
            val privateKey = loadPrivateKey()
            KeyFactory.getInstance("EC", "AndroidKeyStore")
                .getKeySpec(privateKey, KeyInfo::class.java)
        } catch (error: Exception) {
            throw LicensePlatformException("KEY_INVALIDATED", error.message)
        }

        return mapOf(
            "spki_der_base64url" to Base64.getUrlEncoder().withoutPadding().encodeToString(spki),
            "sha256_base64url" to Base64.getUrlEncoder().withoutPadding().encodeToString(digest),
            "security_level" to securityLevel(keyInfo)
        )
    }

    private fun securityLevel(keyInfo: KeyInfo): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            when (keyInfo.securityLevel) {
                KeyProperties.SECURITY_LEVEL_STRONGBOX -> "STRONGBOX"
                KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT -> "TRUSTED_ENVIRONMENT"
                KeyProperties.SECURITY_LEVEL_SOFTWARE -> "SOFTWARE"
                else -> "UNKNOWN"
            }
        } else {
            if (keyInfo.isInsideSecureHardware) "TRUSTED_ENVIRONMENT" else "SOFTWARE"
        }
    }

    private fun checkPrivateKeyUsability() {
        val privateKey = loadPrivateKey()
        val certificate = loadKeyStore().getCertificate(DEVICE_KEY_ALIAS)
            ?: throw LicensePlatformException("KEY_INVALIDATED")
        val challenge = ByteArray(32).also { SecureRandom().nextBytes(it) }
        try {
            val signer = Signature.getInstance("SHA256withECDSA")
            signer.initSign(privateKey)
            signer.update(challenge)
            val signed = signer.sign()

            val verifier = Signature.getInstance("SHA256withECDSA")
            verifier.initVerify(certificate.publicKey)
            verifier.update(challenge)
            if (!verifier.verify(signed)) {
                throw LicensePlatformException("KEY_INVALIDATED", "Local key challenge verification failed")
            }
        } catch (error: LicensePlatformException) {
            throw error
        } catch (error: Exception) {
            throw LicensePlatformException("KEYSTORE_UNAVAILABLE", error.message)
        }
    }
}

private class LicensePlatformException(
    val code: String,
    override val message: String? = null
) : Exception(message)

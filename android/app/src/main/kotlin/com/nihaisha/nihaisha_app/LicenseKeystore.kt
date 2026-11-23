package com.nihaisha.nihaisha_app

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.util.Base64
import java.nio.charset.StandardCharsets
import java.security.GeneralSecurityException
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.ProviderException
import java.security.SecureRandom
import java.security.Signature
import java.security.UnrecoverableKeyException
import java.security.KeyStoreException
import java.security.spec.ECGenParameterSpec

internal data class LicenseDeviceKeyInfo(
    val publicKeySpkiBase64Url: String,
    val publicKeySha256: String,
    val securityLevel: String,
    val strongBoxFallback: Boolean = false
) {
    fun toChannelMap(): Map<String, Any> = mapOf(
        "publicKeySpkiBase64Url" to publicKeySpkiBase64Url,
        "publicKeySha256" to publicKeySha256,
        "securityLevel" to securityLevel,
        "strongBoxFallback" to strongBoxFallback
    )
}

internal class LicenseKeystoreException(
    val code: String,
    override val message: String,
    cause: Throwable? = null
) : Exception(message, cause)

/**
 * Device-key lifecycle adapter. Read and signing operations are strictly
 * get-only; only createDeviceKeyForActivation() can create an alias.
 */
internal class LicenseKeystore {
    private val lock = Any()

    fun getDeviceKey(): LicenseDeviceKeyInfo = synchronized(lock) {
        withMappedErrors {
            describe(loadKeyPairOrThrow(), strongBoxFallback = false)
        }
    }

    fun createDeviceKeyForActivation(): LicenseDeviceKeyInfo = synchronized(lock) {
        withMappedErrors {
            if (loadKeyPairOrNull() != null) {
                throw LicenseKeystoreException(
                    "keyAlreadyExists",
                    "设备密钥已存在；读取现有密钥，不允许覆盖或重建。"
                )
            }

            var fellBackToTee = false
            if (LicenseKeystorePolicy.shouldAttemptStrongBox(Build.VERSION.SDK_INT)) {
                try {
                    generateDeviceKey(strongBoxBacked = true)
                } catch (_: StrongBoxUnavailableException) {
                    // The alias was confirmed absent before this explicit create
                    // operation. Remove only a partial entry from this attempt.
                    deletePartialAlias()
                    generateDeviceKey(strongBoxBacked = false)
                    fellBackToTee = true
                }
            } else {
                generateDeviceKey(strongBoxBacked = false)
            }

            describe(loadKeyPairOrThrow(), strongBoxFallback = fellBackToTee)
        }
    }

    /**
     * Signs the protocol-defined request message: ASCII("YANJIR1.") followed
     * by the exact canonical Base64URL payload segment supplied by Dart.
     */
    fun signActivationRequest(payloadBase64Url: String): String = synchronized(lock) {
        withMappedErrors {
            if (!LicenseKeystorePolicy.isValidActivationPayloadSegment(payloadBase64Url)) {
                throw LicenseKeystoreException(
                    "invalidArgument",
                    "设备申请 Payload 必须是未填充的 Base64URL 单段。"
                )
            }
            val payloadBytes = decodeBase64Url(payloadBase64Url)
            if (encodeBase64Url(payloadBytes) != payloadBase64Url) {
                throw LicenseKeystoreException(
                    "invalidArgument",
                    "设备申请 Payload 不是规范 Base64URL 编码。"
                )
            }

            val keyPair = loadKeyPairOrThrow()
            val message = "YANJIR1.$payloadBase64Url".toByteArray(StandardCharsets.US_ASCII)
            val signer = Signature.getInstance("SHA256withECDSA")
            signer.initSign(keyPair.private)
            signer.update(message)
            encodeBase64Url(signer.sign())
        }
    }

    /**
     * Local private-key usability check only. This is not remote hardware
     * attestation and its result must not be persisted across process restarts.
     */
    fun checkPrivateKeyUsability(): LicenseDeviceKeyInfo = synchronized(lock) {
        withMappedErrors {
            val keyPair = loadKeyPairOrThrow()
            val challenge = ByteArray(32).also { SecureRandom().nextBytes(it) }

            val signer = Signature.getInstance("SHA256withECDSA")
            signer.initSign(keyPair.private)
            signer.update(challenge)
            val signature = signer.sign()

            val verifier = Signature.getInstance("SHA256withECDSA")
            verifier.initVerify(keyPair.public)
            verifier.update(challenge)
            if (!verifier.verify(signature)) {
                throw LicenseKeystoreException(
                    "providerError",
                    "本地设备密钥挑战签名无法通过对应公钥验证。"
                )
            }
            describe(keyPair, strongBoxFallback = false)
        }
    }

    private fun generateDeviceKey(strongBoxBacked: Boolean) {
        val generator = KeyPairGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_EC,
            ANDROID_KEYSTORE
        )
        val builder = KeyGenParameterSpec.Builder(
            DEVICE_KEY_ALIAS,
            KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY
        )
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setUserAuthenticationRequired(false)

        if (strongBoxBacked) {
            builder.setIsStrongBoxBacked(true)
        }

        generator.initialize(builder.build())
        generator.generateKeyPair()
    }

    private fun loadKeyPairOrThrow(): KeyPair =
        loadKeyPairOrNull() ?: throw LicenseKeystoreException(
            "keyMissing",
            "本机尚无专业版设备密钥；只有用户主动生成激活申请时才允许创建。"
        )

    private fun loadKeyPairOrNull(): KeyPair? {
        val keyStore = loadAndroidKeyStore()
        if (!keyStore.containsAlias(DEVICE_KEY_ALIAS)) return null

        val certificate = keyStore.getCertificate(DEVICE_KEY_ALIAS)
            ?: throw LicenseKeystoreException(
                "keyInvalidated",
                "设备密钥证书不存在或已失效。"
            )
        val privateKey = keyStore.getKey(DEVICE_KEY_ALIAS, null) as? PrivateKey
            ?: throw LicenseKeystoreException(
                "keyInvalidated",
                "设备私钥不可用；禁止自动创建替代密钥。"
            )
        return KeyPair(certificate.publicKey, privateKey)
    }

    private fun loadAndroidKeyStore(): KeyStore {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE)
        keyStore.load(null)
        return keyStore
    }

    private fun deletePartialAlias() {
        val keyStore = loadAndroidKeyStore()
        if (keyStore.containsAlias(DEVICE_KEY_ALIAS)) {
            keyStore.deleteEntry(DEVICE_KEY_ALIAS)
        }
    }

    private fun describe(
        keyPair: KeyPair,
        strongBoxFallback: Boolean
    ): LicenseDeviceKeyInfo {
        val publicKey = keyPair.public.encoded
            ?: throw LicenseKeystoreException(
                "providerError",
                "Android Keystore 未返回可编码的 SPKI 公钥。"
            )
        val fingerprint = MessageDigest.getInstance("SHA-256").digest(publicKey)
        val keyFactory = KeyFactory.getInstance(KeyProperties.KEY_ALGORITHM_EC, ANDROID_KEYSTORE)
        val keyInfo = keyFactory.getKeySpec(keyPair.private, KeyInfo::class.java)
        val securityLevel = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            LicenseKeystorePolicy.securityLevelForModernApi(
                keyInfo.securityLevel,
                KeyProperties.SECURITY_LEVEL_SOFTWARE,
                KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT,
                KeyProperties.SECURITY_LEVEL_STRONGBOX
            )
        } else {
            LicenseKeystorePolicy.securityLevelForLegacyApi(keyInfo.isInsideSecureHardware)
        }

        return LicenseDeviceKeyInfo(
            publicKeySpkiBase64Url = encodeBase64Url(publicKey),
            publicKeySha256 = encodeBase64Url(fingerprint),
            securityLevel = securityLevel,
            strongBoxFallback = strongBoxFallback
        )
    }

    private fun decodeBase64Url(value: String): ByteArray =
        Base64.decode(value, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)

    private fun encodeBase64Url(value: ByteArray): String =
        Base64.encodeToString(
            value,
            Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING
        )

    private inline fun <T> withMappedErrors(block: () -> T): T {
        try {
            return block()
        } catch (error: LicenseKeystoreException) {
            throw error
        } catch (error: KeyPermanentlyInvalidatedException) {
            throw LicenseKeystoreException(
                "keyInvalidated",
                "Android Keystore 设备密钥已失效；不得自动创建替代密钥。",
                error
            )
        } catch (error: UnrecoverableKeyException) {
            throw LicenseKeystoreException(
                "keyInvalidated",
                "Android Keystore 无法恢复现有设备密钥；不得自动创建替代密钥。",
                error
            )
        } catch (error: KeyStoreException) {
            throw LicenseKeystoreException(
                "keystoreUnavailable",
                "Android Keystore 暂不可用。",
                error
            )
        } catch (error: ProviderException) {
            throw LicenseKeystoreException(
                "providerError",
                "Android Keystore Provider 操作失败。",
                error
            )
        } catch (error: GeneralSecurityException) {
            throw LicenseKeystoreException(
                "providerError",
                "设备密钥密码学操作失败。",
                error
            )
        } catch (error: Exception) {
            throw LicenseKeystoreException(
                "providerError",
                "设备密钥操作失败：${error.javaClass.simpleName}",
                error
            )
        }
    }

    private companion object {
        const val ANDROID_KEYSTORE = "AndroidKeyStore"
        const val DEVICE_KEY_ALIAS = "yanji_pro_device_signing_key_v1"
    }
}

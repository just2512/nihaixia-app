package com.nihaisha.nihaisha_app

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.security.KeyStore
import java.util.UUID
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal class AiCredentialVaultException(
    val code: String,
    val safeMessage: String,
) : Exception(safeMessage)

/**
 * Android-only secret storage.
 *
 * AES-GCM ciphertext is written atomically beneath noBackupFilesDir. The AES
 * key has an alias separate from the ECDSA License KeyRing and is never
 * exported. No plaintext secret is written to SQLite, preferences, logs or
 * backup-visible app files.
 */
internal class AiCredentialVaultStore(context: Context) {
    private val appContext = context.applicationContext
    private val lock = Any()
    private val directory: File
        get() = File(appContext.noBackupFilesDir, DIRECTORY_NAME)

    fun save(providerId: String, secret: String): String = synchronized(lock) {
        try {
            AiCredentialVaultPolicy.validateProviderId(providerId)
            AiCredentialVaultPolicy.validateSecret(secret)
            val payload = AiCredentialVaultPolicy.encodePayload(providerId, secret)
            val key = getOrCreateKey()
            val credentialRef = newCredentialRef()
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, key)
            cipher.updateAAD(AiCredentialVaultPolicy.associatedData(credentialRef))
            val ciphertext = cipher.doFinal(payload)
            val envelope = AiCredentialVaultPolicy.encodeEnvelope(cipher.iv, ciphertext)
            writeAtomically(credentialRef, envelope)
            credentialRef
        } catch (error: AiCredentialVaultException) {
            throw error
        } catch (_: IllegalArgumentException) {
            throw AiCredentialVaultException(
                "CREDENTIAL_INPUT_INVALID",
                "供应商凭证参数不符合安全存储要求。",
            )
        } catch (_: Exception) {
            throw AiCredentialVaultException(
                "CREDENTIAL_VAULT_UNAVAILABLE",
                "设备安全凭证库暂不可用；凭证未保存。",
            )
        }
    }

    fun read(credentialRef: String): AiCredentialVaultPolicy.CredentialPayload? = synchronized(lock) {
        val file = credentialFile(credentialRef)
        val backupFile = File(file.path + ".bak")
        if (!file.isFile && !backupFile.isFile) return null
        try {
            val key = getExistingKey()
            val envelopeBytes = readBounded(AtomicFile(file).openRead())
            val envelope = AiCredentialVaultPolicy.decodeEnvelope(envelopeBytes)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(
                Cipher.DECRYPT_MODE,
                key,
                GCMParameterSpec(AiCredentialVaultPolicy.TAG_BITS, envelope.iv),
            )
            cipher.updateAAD(
                AiCredentialVaultPolicy.associatedData(credentialRef, envelope.version),
            )
            val payload = cipher.doFinal(envelope.ciphertext)
            AiCredentialVaultPolicy.decodePayload(payload)
        } catch (_: AEADBadTagException) {
            throw AiCredentialVaultException(
                "CREDENTIAL_DATA_AUTHENTICATION_FAILED",
                "凭证数据完整性校验失败；请重新录入该供应商凭证。",
            )
        } catch (error: AiCredentialVaultException) {
            throw error
        } catch (_: Exception) {
            throw AiCredentialVaultException(
                "CREDENTIAL_READ_FAILED",
                "设备安全凭证无法读取；请重新录入该供应商凭证。",
            )
        }
    }

    fun delete(credentialRef: String): Boolean = synchronized(lock) {
        val file = credentialFile(credentialRef)
        val backupFile = File(file.path + ".bak")
        if (!file.exists() && !backupFile.exists()) return false
        try {
            AtomicFile(file).delete()
            !file.exists() && !backupFile.exists()
        } catch (_: Exception) {
            throw AiCredentialVaultException(
                "CREDENTIAL_DELETE_FAILED",
                "设备安全凭证删除失败。",
            )
        }
    }

    fun exists(credentialRef: String): Boolean = synchronized(lock) {
        val file = credentialFile(credentialRef)
        val backupFile = File(file.path + ".bak")
        if (!file.isFile && !backupFile.isFile) return false
        getExistingKey()
        true
    }

    private fun credentialFile(credentialRef: String): File {
        try {
            return AiCredentialVaultPolicy.credentialFile(directory, credentialRef)
        } catch (_: Exception) {
            throw AiCredentialVaultException(
                "CREDENTIAL_REFERENCE_INVALID",
                "供应商凭证引用无效。",
            )
        }
    }

    private fun newCredentialRef(): String {
        if (!directory.exists() && !directory.mkdirs()) {
            throw IOException("vault directory unavailable")
        }
        repeat(3) {
            val candidate = UUID.randomUUID().toString()
            if (!AiCredentialVaultPolicy.credentialFile(directory, candidate).exists()) {
                return candidate
            }
        }
        throw IOException("credential reference allocation failed")
    }

    private fun writeAtomically(credentialRef: String, bytes: ByteArray) {
        val file = credentialFile(credentialRef)
        if (!directory.exists() && !directory.mkdirs()) {
            throw IOException("vault directory unavailable")
        }
        val atomicFile = AtomicFile(file)
        val output = atomicFile.startWrite()
        try {
            output.write(bytes)
            atomicFile.finishWrite(output)
        } catch (error: Exception) {
            atomicFile.failWrite(output)
            throw error
        }
    }

    private fun readBounded(input: java.io.FileInputStream): ByteArray {
        input.use { stream ->
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(4096)
            var total = 0
            while (true) {
                val count = stream.read(buffer)
                if (count < 0) break
                total += count
                if (total > AiCredentialVaultPolicy.MAX_ENVELOPE_BYTES) {
                    throw IOException("credential envelope too large")
                }
                output.write(buffer, 0, count)
            }
            return output.toByteArray()
        }
    }

    private fun getOrCreateKey(): SecretKey {
        val keyStore = loadKeyStore()
        val existing = keyStore.getKey(KEY_ALIAS, null) as? SecretKey
        if (existing != null) return existing

        // Never replace a missing key while encrypted records remain. Doing so
        // would make old credentials look like valid but unreadable records.
        if (directory.listFiles()?.any { it.isFile } == true) {
            throw AiCredentialVaultException(
                "CREDENTIAL_VAULT_KEY_MISSING",
                "设备安全密钥缺失，现有凭证无法安全解密；请重新录入。",
            )
        }

        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            ANDROID_KEYSTORE,
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setRandomizedEncryptionRequired(true)
                .build(),
        )
        return generator.generateKey()
    }

    private fun getExistingKey(): SecretKey {
        val key = loadKeyStore().getKey(KEY_ALIAS, null) as? SecretKey
        return key ?: throw AiCredentialVaultException(
            "CREDENTIAL_VAULT_KEY_MISSING",
            "设备安全密钥缺失；请重新录入供应商凭证。",
        )
    }

    private fun loadKeyStore(): KeyStore =
        KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }

    private companion object {
        const val ANDROID_KEYSTORE = "AndroidKeyStore"
        const val KEY_ALIAS = "yanji.ai.credentials.aes.v1"
        const val DIRECTORY_NAME = "ai_credentials"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
    }
}

package com.nihaisha.nihaisha_app

import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets
import java.util.UUID

/**
 * Pure validation/serialization policy for encrypted AI credential envelopes.
 *
 * This class contains no Android Keystore or file IO so its data-boundary
 * behavior can be tested on the JVM without pretending to test device crypto.
 */
internal object AiCredentialVaultPolicy {
    const val ENVELOPE_VERSION = 1
    const val PAYLOAD_VERSION = 1
    const val IV_BYTES = 12
    const val TAG_BITS = 128
    const val MAX_PROVIDER_ID_BYTES = 512
    const val MAX_SECRET_BYTES = 64 * 1024
    const val MAX_ENVELOPE_BYTES = MAX_SECRET_BYTES + MAX_PROVIDER_ID_BYTES + 256

    private const val MAGIC = 0x41494356 // "AICV"
    private const val AAD_PREFIX = "nihaisha.ai-credential.v1:"

    data class Envelope(
        val version: Int,
        val iv: ByteArray,
        val ciphertext: ByteArray,
    )

    data class CredentialPayload(
        val providerId: String,
        val secret: String,
    )

    fun validateProviderId(providerId: String) {
        val bytes = providerId.toByteArray(StandardCharsets.UTF_8)
        require(providerId.isNotBlank() && providerId == providerId.trim()) {
            "CREDENTIAL_PROVIDER_ID_INVALID"
        }
        require(bytes.isNotEmpty() && bytes.size <= MAX_PROVIDER_ID_BYTES) {
            "CREDENTIAL_PROVIDER_ID_INVALID"
        }
    }

    fun validateSecret(secret: String) {
        val bytes = secret.toByteArray(StandardCharsets.UTF_8)
        require(secret.isNotEmpty()) { "CREDENTIAL_SECRET_EMPTY" }
        require(bytes.isNotEmpty() && bytes.size <= MAX_SECRET_BYTES) {
            "CREDENTIAL_SECRET_TOO_LARGE"
        }
    }

    fun validateCredentialRef(credentialRef: String) {
        val parsed = try {
            UUID.fromString(credentialRef)
        } catch (_: IllegalArgumentException) {
            throw IllegalArgumentException("CREDENTIAL_REFERENCE_INVALID")
        }
        require(parsed.toString() == credentialRef) {
            "CREDENTIAL_REFERENCE_INVALID"
        }
    }

    fun associatedData(credentialRef: String, version: Int = ENVELOPE_VERSION): ByteArray {
        validateCredentialRef(credentialRef)
        require(version == ENVELOPE_VERSION) { "CREDENTIAL_ENVELOPE_VERSION_UNSUPPORTED" }
        return "$AAD_PREFIX$version:$credentialRef".toByteArray(StandardCharsets.UTF_8)
    }

    fun encodePayload(providerId: String, secret: String): ByteArray {
        validateProviderId(providerId)
        validateSecret(secret)
        val providerBytes = providerId.toByteArray(StandardCharsets.UTF_8)
        val secretBytes = secret.toByteArray(StandardCharsets.UTF_8)
        val size = 4 + 4 + providerBytes.size + 4 + secretBytes.size
        return ByteBuffer.allocate(size)
            .order(ByteOrder.BIG_ENDIAN)
            .putInt(PAYLOAD_VERSION)
            .putInt(providerBytes.size)
            .put(providerBytes)
            .putInt(secretBytes.size)
            .put(secretBytes)
            .array()
    }

    fun decodePayload(bytes: ByteArray): CredentialPayload {
        require(bytes.size >= 12 && bytes.size <= MAX_SECRET_BYTES + MAX_PROVIDER_ID_BYTES + 12) {
            "CREDENTIAL_PAYLOAD_INVALID"
        }
        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.BIG_ENDIAN)
        val version = buffer.int
        require(version == PAYLOAD_VERSION) { "CREDENTIAL_PAYLOAD_VERSION_UNSUPPORTED" }

        val providerLength = buffer.int
        require(providerLength in 1..MAX_PROVIDER_ID_BYTES && providerLength <= buffer.remaining() - 4) {
            "CREDENTIAL_PAYLOAD_INVALID"
        }
        val providerBytes = ByteArray(providerLength)
        buffer.get(providerBytes)

        val secretLength = buffer.int
        require(secretLength in 1..MAX_SECRET_BYTES && secretLength == buffer.remaining()) {
            "CREDENTIAL_PAYLOAD_INVALID"
        }
        val secretBytes = ByteArray(secretLength)
        buffer.get(secretBytes)

        val providerId = decodeUtf8(providerBytes)
        val secret = decodeUtf8(secretBytes)
        validateProviderId(providerId)
        validateSecret(secret)
        return CredentialPayload(providerId, secret)
    }

    fun encodeEnvelope(iv: ByteArray, ciphertext: ByteArray): ByteArray {
        require(iv.size == IV_BYTES) { "CREDENTIAL_ENVELOPE_IV_INVALID" }
        require(ciphertext.size >= TAG_BITS / 8 && ciphertext.size <= MAX_ENVELOPE_BYTES) {
            "CREDENTIAL_ENVELOPE_CIPHERTEXT_INVALID"
        }
        return ByteBuffer.allocate(4 + 4 + 1 + iv.size + ciphertext.size)
            .order(ByteOrder.BIG_ENDIAN)
            .putInt(MAGIC)
            .putInt(ENVELOPE_VERSION)
            .put(iv.size.toByte())
            .put(iv)
            .put(ciphertext)
            .array()
    }

    fun decodeEnvelope(bytes: ByteArray): Envelope {
        require(bytes.size in (4 + 4 + 1 + IV_BYTES + TAG_BITS / 8)..MAX_ENVELOPE_BYTES) {
            "CREDENTIAL_ENVELOPE_INVALID"
        }
        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.BIG_ENDIAN)
        require(buffer.int == MAGIC) { "CREDENTIAL_ENVELOPE_INVALID" }
        val version = buffer.int
        require(version == ENVELOPE_VERSION) { "CREDENTIAL_ENVELOPE_VERSION_UNSUPPORTED" }
        val ivLength = buffer.get().toInt() and 0xff
        require(ivLength == IV_BYTES && buffer.remaining() > ivLength) {
            "CREDENTIAL_ENVELOPE_IV_INVALID"
        }
        val iv = ByteArray(ivLength)
        buffer.get(iv)
        val ciphertext = ByteArray(buffer.remaining())
        buffer.get(ciphertext)
        require(ciphertext.size >= TAG_BITS / 8) {
            "CREDENTIAL_ENVELOPE_CIPHERTEXT_INVALID"
        }
        return Envelope(version, iv, ciphertext)
    }

    fun credentialFile(directory: File, credentialRef: String): File {
        validateCredentialRef(credentialRef)
        val root = directory.canonicalFile
        val target = File(root, "$credentialRef.bin").canonicalFile
        require(target.parentFile == root) { "CREDENTIAL_PATH_OUTSIDE_VAULT" }
        return target
    }

    private fun decodeUtf8(bytes: ByteArray): String {
        val decoder = StandardCharsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
        return try {
            decoder.decode(ByteBuffer.wrap(bytes)).toString()
        } catch (_: Exception) {
            throw IllegalArgumentException("CREDENTIAL_PAYLOAD_UTF8_INVALID")
        }
    }
}

package com.nihaisha.nihaisha_app

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.fail
import org.junit.Test

class AiCredentialVaultPolicyTest {
    private val validReference = "123e4567-e89b-12d3-a456-426614174000"

    @Test
    fun encodesAndDecodesSecretPayloadWithoutLoss() {
        val payload = AiCredentialVaultPolicy.encodePayload(
            "provider-1",
            "secret-with-中文-and-symbols-!@#",
        )

        val decoded = AiCredentialVaultPolicy.decodePayload(payload)
        assertEquals("provider-1", decoded.providerId)
        assertEquals("secret-with-中文-and-symbols-!@#", decoded.secret)
    }

    @Test
    fun rejectsEmptyOrOversizedSecret() {
        assertRejects { AiCredentialVaultPolicy.encodePayload("provider", "") }
        assertRejects {
            AiCredentialVaultPolicy.encodePayload(
                "provider",
                "x".repeat(AiCredentialVaultPolicy.MAX_SECRET_BYTES + 1),
            )
        }
    }

    @Test
    fun rejectsInvalidCredentialReferencesAndPathTraversal() {
        assertRejects {
            AiCredentialVaultPolicy.validateCredentialRef("../outside")
        }
        withTempDirectory { directory ->
            assertRejects {
                AiCredentialVaultPolicy.credentialFile(directory, "../outside")
            }
            val file = AiCredentialVaultPolicy.credentialFile(directory, validReference)
            assertEquals(directory.canonicalFile, file.parentFile)
        }
    }

    @Test
    fun authenticatesReferenceAndEnvelopeVersionAsAssociatedData() {
        val expected = AiCredentialVaultPolicy.associatedData(validReference)
        assertArrayEquals(expected, AiCredentialVaultPolicy.associatedData(validReference))
        assertRejects {
            AiCredentialVaultPolicy.associatedData(
                validReference,
                AiCredentialVaultPolicy.ENVELOPE_VERSION + 1,
            )
        }
    }

    @Test
    fun roundTripsEnvelopeAndRejectsCorruptHeaderOrIvLength() {
        val iv = ByteArray(AiCredentialVaultPolicy.IV_BYTES) { it.toByte() }
        val ciphertext = ByteArray(64) { (it * 3).toByte() }
        val encoded = AiCredentialVaultPolicy.encodeEnvelope(iv, ciphertext)
        val decoded = AiCredentialVaultPolicy.decodeEnvelope(encoded)
        assertEquals(AiCredentialVaultPolicy.ENVELOPE_VERSION, decoded.version)
        assertArrayEquals(iv, decoded.iv)
        assertArrayEquals(ciphertext, decoded.ciphertext)

        val corruptMagic = encoded.copyOf().apply { this[0] = 0 }
        assertRejects { AiCredentialVaultPolicy.decodeEnvelope(corruptMagic) }
        val corruptIv = encoded.copyOf().apply { this[8] = 1 }
        assertRejects { AiCredentialVaultPolicy.decodeEnvelope(corruptIv) }
    }

    @Test
    fun aesGcmAuthenticatesCredentialReferenceAndDoesNotExposePlaintext() {
        val keyGenerator = javax.crypto.KeyGenerator.getInstance("AES")
        keyGenerator.init(256)
        val key = keyGenerator.generateKey()
        val secret = "private-api-secret-do-not-persist-in-plain"
        val payload = AiCredentialVaultPolicy.encodePayload("provider-1", secret)
        val cipher = javax.crypto.Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(javax.crypto.Cipher.ENCRYPT_MODE, key)
        cipher.updateAAD(AiCredentialVaultPolicy.associatedData(validReference))
        val envelopeBytes = AiCredentialVaultPolicy.encodeEnvelope(
            cipher.iv,
            cipher.doFinal(payload),
        )
        assertFalse(String(envelopeBytes, Charsets.ISO_8859_1).contains(secret))

        val envelope = AiCredentialVaultPolicy.decodeEnvelope(envelopeBytes)
        val decrypt = javax.crypto.Cipher.getInstance("AES/GCM/NoPadding")
        decrypt.init(
            javax.crypto.Cipher.DECRYPT_MODE,
            key,
            javax.crypto.spec.GCMParameterSpec(AiCredentialVaultPolicy.TAG_BITS, envelope.iv),
        )
        decrypt.updateAAD(AiCredentialVaultPolicy.associatedData(validReference))
        assertEquals(secret, AiCredentialVaultPolicy.decodePayload(
            decrypt.doFinal(envelope.ciphertext),
        ).secret)

        val tamperedReference = "123e4567-e89b-12d3-a456-426614174001"
        val wrongReferenceDecrypt = javax.crypto.Cipher.getInstance("AES/GCM/NoPadding")
        wrongReferenceDecrypt.init(
            javax.crypto.Cipher.DECRYPT_MODE,
            key,
            javax.crypto.spec.GCMParameterSpec(AiCredentialVaultPolicy.TAG_BITS, envelope.iv),
        )
        wrongReferenceDecrypt.updateAAD(
            AiCredentialVaultPolicy.associatedData(tamperedReference),
        )
        try {
            wrongReferenceDecrypt.doFinal(envelope.ciphertext)
            fail("Credential reference must be authenticated as AAD")
        } catch (_: javax.crypto.AEADBadTagException) {
            // Expected: a ciphertext cannot be moved to another reference.
        }
    }

    @Test
    fun rejectsPayloadWithTrailingOrTruncatedBytes() {
        val valid = AiCredentialVaultPolicy.encodePayload("provider", "secret")
        assertRejects {
            AiCredentialVaultPolicy.decodePayload(valid + byteArrayOf(1))
        }
        assertRejects {
            AiCredentialVaultPolicy.decodePayload(valid.copyOf(valid.size - 1))
        }
    }

    private fun assertRejects(block: () -> Unit) {
        try {
            block()
            fail("Expected invalid credential data to be rejected")
        } catch (_: IllegalArgumentException) {
            // Expected fail-closed validation result.
        }
    }

    private fun withTempDirectory(block: (File) -> Unit) {
        val directory = Files.createTempDirectory("ai-credential-vault-policy-").toFile()
        try {
            block(directory)
        } finally {
            directory.deleteRecursively()
        }
    }
}

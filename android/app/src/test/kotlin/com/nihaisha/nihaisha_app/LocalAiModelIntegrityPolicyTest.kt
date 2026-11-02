package com.nihaisha.nihaisha_app

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalAiModelIntegrityPolicyTest {
    @Test
    fun calculatesSha256ForAFile() {
        withTempFile("abc") { file ->
            assertEquals(
                "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                LocalAiModelIntegrityPolicy.sha256(file)
            )
        }
    }

    @Test
    fun acceptsTheExpectedDigestCaseInsensitively() {
        val expected = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        assertTrue(LocalAiModelIntegrityPolicy.matches(expected.uppercase(), expected))
    }

    @Test
    fun rejectsDifferentContentsEvenWhenFileSizeIsUnchanged() {
        withTempFile("abd") { file ->
            assertEquals(3L, file.length())
            val expected = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
            val actual = LocalAiModelIntegrityPolicy.sha256(file)
            assertFalse(LocalAiModelIntegrityPolicy.matches(actual, expected))
        }
    }

    @Test
    fun rejectsMissingOrNonRegularFiles() {
        val missing = File(System.getProperty("java.io.tmpdir"), "missing-model-${System.nanoTime()}")
        try {
            LocalAiModelIntegrityPolicy.sha256(missing)
            throw AssertionError("Expected a missing file to be rejected")
        } catch (_: IllegalArgumentException) {
            // Expected.
        }

        val directory = Files.createTempDirectory("model-integrity-directory-").toFile()
        try {
            try {
                LocalAiModelIntegrityPolicy.sha256(directory)
                throw AssertionError("Expected a directory to be rejected")
            } catch (_: IllegalArgumentException) {
                // Expected.
            }
        } finally {
            directory.deleteRecursively()
        }
    }

    private fun withTempFile(content: String, block: (File) -> Unit) {
        val file = Files.createTempFile("model-integrity-", ".litertlm").toFile()
        try {
            file.writeText(content)
            block(file)
        } finally {
            file.delete()
        }
    }
}

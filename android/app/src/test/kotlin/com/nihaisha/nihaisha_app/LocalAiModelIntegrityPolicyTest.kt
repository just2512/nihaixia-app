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
    fun hashesLargeFilesAcrossMultipleBufferReads() {
        // Spanning several 1 MiB reads exercises the streaming loop; a buffer
        // off-by-one (digest.update(buffer, 0, count ± 1)) would corrupt the
        // digest on real multi-chunk files while this tiny-file suite stays green.
        val pattern = "0123456789abcdef".toByteArray(Charsets.US_ASCII)
        val totalBytes = 1024 * 1024 * 2 + 1234567 // > 2 buffers, non-aligned tail
        val expectedSha256 = "ef65925a4f90d5e2ab153b1d7c584ce0d759edcf3ecb2c314e118bbf80865b4d"
        withTempBinaryFile(totalBytes) { file ->
            java.io.RandomAccessFile(file, "rw").use { out ->
                var written = 0L
                out.setLength(totalBytes.toLong())
                while (written < totalBytes) {
                    out.write(pattern, 0, minOf(pattern.size, (totalBytes - written).toInt()))
                    written = out.filePointer
                }
            }
            assertEquals(expectedSha256, LocalAiModelIntegrityPolicy.sha256(file))
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

package com.nihaisha.nihaisha_app

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalAiDataCleanupTest {
    @Test
    fun deletesOnlyDedicatedAiDirectoriesAndPreservesOtherCacheFiles() {
        withTempDirectory { cache ->
            val runtime = File(cache, "litertlm/nested")
            val attachments = File(cache, "local_ai_attachments")
            assertTrue(runtime.mkdirs())
            assertTrue(attachments.mkdirs())
            File(runtime, "runtime.bin").writeText("runtime")
            File(attachments, "photo.jpg").writeText("photo")
            val unrelated = File(cache, "other-feature.bin")
            unrelated.writeText("keep")

            assertEquals(1, LocalAiDataCleanup.deleteOwnedDirectory(cache, "litertlm"))
            assertEquals(1, LocalAiDataCleanup.deleteOwnedDirectory(cache, "local_ai_attachments"))
            assertFalse(File(cache, "litertlm").exists())
            assertFalse(File(cache, "local_ai_attachments").exists())
            assertTrue(unrelated.isFile)
            assertEquals("keep", unrelated.readText())
        }
    }

    @Test
    fun rejectsAiOwnedDirectorySymlinkThatEscapesCacheRoot() {
        withTempDirectory { cache ->
            val outside = Files.createTempDirectory("local-ai-outside-").toFile()
            try {
                val sentinel = File(outside, "keep.bin")
                sentinel.writeText("keep")
                val link = File(cache, "local_ai_attachments")
                Files.createSymbolicLink(link.toPath(), outside.toPath())

                try {
                    LocalAiDataCleanup.deleteOwnedDirectory(cache, "local_ai_attachments")
                    throw AssertionError("Expected symbolic-link target to be rejected")
                } catch (expected: IllegalArgumentException) {
                    assertTrue(expected.message!!.contains("direct child") || expected.message!!.contains("symbolic link"))
                }

                assertTrue(sentinel.isFile)
                assertEquals("keep", sentinel.readText())
                assertTrue(Files.isSymbolicLink(link.toPath()))
            } finally {
                outside.deleteRecursively()
            }
        }
    }

    @Test
    fun deletesOnlyLegacyLocalAiRecordingNamesAtCacheRoot() {
        withTempDirectory { cache ->
            val legacy = File(cache, "local_ai_123456.wav")
            val otherRecording = File(cache, "voice_123456.wav")
            val image = File(cache, "local_ai_photo.jpg")
            val nested = File(cache, "local_ai_attachments/local_ai_654321.wav")
            assertTrue(nested.parentFile!!.mkdirs())
            legacy.writeText("legacy")
            otherRecording.writeText("keep")
            image.writeText("keep")
            nested.writeText("managed")

            assertEquals(1, LocalAiDataCleanup.deleteLegacyRecordingFiles(cache))
            assertFalse(legacy.exists())
            assertTrue(otherRecording.isFile)
            assertTrue(image.isFile)
            assertTrue(nested.isFile)
        }
    }

    @Test
    fun rejectsDirectoryTraversalOutsideCacheRoot() {
        withTempDirectory { cache ->
            val outside = File(cache.parentFile, "outside-ai-cache")
            assertTrue(outside.mkdirs())
            File(outside, "keep").writeText("keep")

            try {
                LocalAiDataCleanup.deleteOwnedDirectory(cache, "../outside-ai-cache")
                throw AssertionError("Expected traversal to be rejected")
            } catch (expected: IllegalArgumentException) {
                assertTrue(expected.message!!.contains("direct child"))
            }
            assertTrue(File(outside, "keep").isFile)
            outside.deleteRecursively()
        }
    }

    private fun withTempDirectory(block: (File) -> Unit) {
        val directory = Files.createTempDirectory("local-ai-data-cleanup-").toFile()
        try {
            block(directory)
        } finally {
            directory.deleteRecursively()
        }
    }
}

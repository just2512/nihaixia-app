package com.nihaisha.nihaisha_app

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalAiRuntimeCacheClearPolicyTest {
    @Test
    fun releasesRuntimeBeforeDeletingOnlyLiteRtCacheAndPreservesModel() {
        val root = Files.createTempDirectory("local-ai-runtime-clear").toFile()
        try {
            val cache = File(root, "cache/litertlm")
            val nested = File(cache, "nested")
            assertTrue(nested.mkdirs())
            File(nested, "runtime.bin").writeBytes(byteArrayOf(1, 2, 3))
            val model = File(root, "files/ai_models/gemma-4-E4B-it.litertlm")
            assertTrue(model.parentFile!!.mkdirs())
            model.writeBytes(byteArrayOf(9, 8, 7))

            var released = false
            val result = LocalAiRuntimeCacheClearPolicy.clear(
                runtimeCacheDirectory = cache,
                modelFile = model
            ) {
                released = true
                assertTrue("runtime must be released before cache deletion", cache.exists())
            }

            assertTrue(released)
            assertTrue(result.runtimeReleased)
            assertTrue(result.cacheDeleted)
            assertTrue(result.modelFileExists)
            assertEquals(null, result.errorCode)
            assertFalse(cache.exists())
            assertTrue(model.isFile)
            assertEquals(listOf<Byte>(9, 8, 7), model.readBytes().toList())
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun keepsCacheWhenRuntimeReleaseFails() {
        val root = Files.createTempDirectory("local-ai-runtime-release-failure").toFile()
        try {
            val cache = File(root, "cache/litertlm")
            assertTrue(cache.mkdirs())
            val cacheFile = File(cache, "mapped.bin")
            cacheFile.writeBytes(byteArrayOf(4, 5, 6))
            val model = File(root, "model.litertlm")
            model.writeBytes(byteArrayOf(7))

            val result = LocalAiRuntimeCacheClearPolicy.clear(
                runtimeCacheDirectory = cache,
                modelFile = model
            ) {
                throw IllegalStateException("injected close failure")
            }

            assertFalse(result.runtimeReleased)
            assertFalse(result.cacheDeleted)
            assertEquals("RUNTIME_RELEASE_FAILED", result.errorCode)
            assertTrue(cacheFile.isFile)
            assertTrue(model.isFile)
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun treatsMissingCacheAsDeletedOnlyAfterRuntimeRelease() {
        val root = Files.createTempDirectory("local-ai-runtime-no-cache").toFile()
        try {
            val cache = File(root, "cache/litertlm")
            val model = File(root, "model.litertlm")
            var released = false

            val result = LocalAiRuntimeCacheClearPolicy.clear(
                runtimeCacheDirectory = cache,
                modelFile = model
            ) {
                released = true
            }

            assertTrue(released)
            assertTrue(result.runtimeReleased)
            assertTrue(result.cacheDeleted)
            assertFalse(result.modelFileExists)
            assertEquals(null, result.errorCode)
        } finally {
            root.deleteRecursively()
        }
    }
}

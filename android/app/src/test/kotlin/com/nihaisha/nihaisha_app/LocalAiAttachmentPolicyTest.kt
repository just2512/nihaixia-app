package com.nihaisha.nihaisha_app

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LocalAiAttachmentPolicyTest {
    private val cacheRoot = File.separator + "app" + File.separator + "cache"
    private val validPath = cacheRoot + File.separator + "local-ai" + File.separator + "input.wav"

    @Test
    fun acceptsNonEmptyFileInsideNestedCacheDirectory() {
        assertNull(
            LocalAiAttachmentPolicy.validationError(
                filePath = validPath,
                cacheRootPath = cacheRoot,
                isFile = true,
                sizeBytes = 1024L,
                kind = "录音"
            )
        )
    }

    @Test
    fun acceptsFileAtExactlyTheFifteenMebibyteLimit() {
        assertNull(
            LocalAiAttachmentPolicy.validationError(
                filePath = validPath,
                cacheRootPath = cacheRoot,
                isFile = true,
                sizeBytes = LocalAiAttachmentPolicy.MAX_FILE_SIZE_BYTES,
                kind = "照片"
            )
        )
    }

    @Test
    fun rejectsFileLargerThanTheLimit() {
        assertEquals(
            "录音 文件超过 15 MB，请重新选择",
            LocalAiAttachmentPolicy.validationError(
                filePath = validPath,
                cacheRootPath = cacheRoot,
                isFile = true,
                sizeBytes = LocalAiAttachmentPolicy.MAX_FILE_SIZE_BYTES + 1L,
                kind = "录音"
            )
        )
    }

    @Test
    fun rejectsPathsOutsideCacheAndSiblingPrefixDirectories() {
        val outsidePath = File.separator + "app" + File.separator + "other" + File.separator + "input.wav"
        val siblingPrefixPath = cacheRoot + "-outside" + File.separator + "input.wav"

        for (path in listOf(outsidePath, siblingPrefixPath)) {
            assertEquals(
                "照片 文件无效或不在应用缓存目录内",
                LocalAiAttachmentPolicy.validationError(
                    filePath = path,
                    cacheRootPath = cacheRoot,
                    isFile = true,
                    sizeBytes = 1024L,
                    kind = "照片"
                )
            )
        }
    }

    @Test
    fun rejectsDirectoriesMissingFilesAndEmptyFiles() {
        val invalidCases = listOf(
            Triple(validPath, false, 1024L),
            Triple(validPath, true, 0L),
            Triple(validPath, true, -1L)
        )

        for ((path, isFile, sizeBytes) in invalidCases) {
            assertEquals(
                "录音 文件无效或不在应用缓存目录内",
                LocalAiAttachmentPolicy.validationError(
                    filePath = path,
                    cacheRootPath = cacheRoot,
                    isFile = isFile,
                    sizeBytes = sizeBytes,
                    kind = "录音"
                )
            )
        }
    }
}

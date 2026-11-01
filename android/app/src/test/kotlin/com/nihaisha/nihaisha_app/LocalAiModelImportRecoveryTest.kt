package com.nihaisha.nihaisha_app

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalAiModelImportRecoveryTest {
    @Test
    fun restoresPreviousModelAfterInterruptedReplacement() {
        withTempDirectory { directory ->
            val model = File(directory, "model.litertlm")
            val backup = File(directory, "model.litertlm.previous")
            val temp = File(directory, "model.litertlm.importing")
            backup.writeText("previous-model")
            temp.writeText("partial-new-model")

            LocalAiModelImportRecovery.recover(model)

            assertTrue(model.isFile)
            assertEquals("previous-model", model.readText())
            assertFalse(backup.exists())
            assertFalse(temp.exists())
        }
    }

    @Test
    fun keepsReplacedModelAndDeletesStaleBackupAndTempFile() {
        withTempDirectory { directory ->
            val model = File(directory, "model.litertlm")
            val backup = File(directory, "model.litertlm.previous")
            val temp = File(directory, "model.litertlm.importing")
            model.writeText("verified-new-model")
            backup.writeText("previous-model")
            temp.writeText("stale-temp-model")

            LocalAiModelImportRecovery.recover(model)

            assertEquals("verified-new-model", model.readText())
            assertFalse(backup.exists())
            assertFalse(temp.exists())
        }
    }

    @Test
    fun cleansAbandonedTempFileWithoutChangingInstalledModel() {
        withTempDirectory { directory ->
            val model = File(directory, "model.litertlm")
            val temp = File(directory, "model.litertlm.importing")
            model.writeText("installed-model")
            temp.writeText("partial-import")

            LocalAiModelImportRecovery.recover(model)

            assertEquals("installed-model", model.readText())
            assertFalse(temp.exists())
        }
    }

    @Test
    fun leavesAnAlreadyValidModelAloneWhenNoRecoveryFilesExist() {
        withTempDirectory { directory ->
            val model = File(directory, "model.litertlm")
            model.writeText("installed-model")

            LocalAiModelImportRecovery.recover(model)

            assertEquals("installed-model", model.readText())
            assertTrue(model.exists())
        }
    }

    @Test
    fun doesNotDeleteBackupWhenTargetPathIsNotARegularFile() {
        withTempDirectory { directory ->
            val model = File(directory, "model.litertlm")
            val backup = File(directory, "model.litertlm.previous")
            assertTrue(model.mkdir())
            backup.writeText("previous-model")

            val error = try {
                LocalAiModelImportRecovery.recover(model)
                throw AssertionError("Expected recovery to reject a directory target")
            } catch (expected: IllegalStateException) {
                expected
            }

            assertTrue(error.message!!.contains("不是普通文件"))
            assertTrue(backup.isFile)
            assertEquals("previous-model", backup.readText())
        }
    }
    private fun withTempDirectory(block: (File) -> Unit) {
        val directory = Files.createTempDirectory("model-import-recovery-").toFile()
        try {
            block(directory)
        } finally {
            directory.deleteRecursively()
        }
    }
}

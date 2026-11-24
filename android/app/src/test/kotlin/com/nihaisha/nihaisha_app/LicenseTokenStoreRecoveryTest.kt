package com.nihaisha.nihaisha_app

import java.io.File
import java.io.FileInputStream
import java.io.FileNotFoundException
import java.io.FileOutputStream
import java.io.InputStream
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LicenseTokenStoreRecoveryTest {
    @Test
    fun restoresLegacyAtomicBackupBeforeReportingTokenMissing() {
        val noBackupFilesDir = Files.createTempDirectory("license-token-recovery").toFile()
        try {
            val directory = File(noBackupFilesDir, "yanji_license")
            assertTrue(directory.mkdirs())
            val baseFile = File(directory, "active_license.token")
            val backupFile = File(baseFile.path + ".bak")
            backupFile.writeText(VALID_TOKEN)
            assertFalse(baseFile.exists())

            val atomicFile = FakeLicenseAtomicFile(baseFile)
            val store = LicenseTokenStore(noBackupFilesDir, atomicFile)

            assertEquals(VALID_TOKEN, store.read())
            assertEquals(1, atomicFile.openReadCalls)
            assertTrue(baseFile.exists())
            assertFalse(backupFile.exists())
        } finally {
            noBackupFilesDir.deleteRecursively()
        }
    }

    @Test
    fun reportsStorageUnavailableWhenAnExistingBackupCannotBeRecovered() {
        val noBackupFilesDir = Files.createTempDirectory("license-token-unavailable").toFile()
        try {
            val directory = File(noBackupFilesDir, "yanji_license")
            assertTrue(directory.mkdirs())
            val baseFile = File(directory, "active_license.token")
            val backupFile = File(baseFile.path + ".bak")
            backupFile.writeText(VALID_TOKEN)
            val store = LicenseTokenStore(
                noBackupFilesDir,
                FakeLicenseAtomicFile(baseFile, failBackupRecovery = true)
            )

            try {
                store.read()
                throw AssertionError("Expected storageUnavailable when the backup cannot be restored")
            } catch (error: LicenseTokenStoreException) {
                assertEquals("storageUnavailable", error.code)
            }
            assertFalse(baseFile.exists())
            assertTrue(backupFile.exists())
        } finally {
            noBackupFilesDir.deleteRecursively()
        }
    }

    @Test
    fun returnsNullOnlyWhenNeitherBaseFileNorBackupExists() {
        val noBackupFilesDir = Files.createTempDirectory("license-token-empty").toFile()
        try {
            val baseFile = File(
                File(noBackupFilesDir, "yanji_license"),
                "active_license.token"
            )
            val atomicFile = FakeLicenseAtomicFile(baseFile)
            val store = LicenseTokenStore(noBackupFilesDir, atomicFile)

            assertNull(store.read())
            assertEquals(1, atomicFile.openReadCalls)
        } finally {
            noBackupFilesDir.deleteRecursively()
        }
    }

    private class FakeLicenseAtomicFile(
        private val baseFile: File,
        private val failBackupRecovery: Boolean = false
    ) : LicenseAtomicFile {
        var openReadCalls = 0
            private set

        private val backupFile = File(baseFile.path + ".bak")

        override fun openRead(): InputStream {
            openReadCalls++
            if (backupFile.exists()) {
                if (failBackupRecovery) {
                    throw FileNotFoundException("simulated backup restore failure")
                }
                if (baseFile.exists() && !baseFile.delete()) {
                    throw FileNotFoundException("could not replace stale base file")
                }
                if (!backupFile.renameTo(baseFile)) {
                    throw FileNotFoundException("could not restore legacy backup")
                }
            }
            return FileInputStream(baseFile)
        }

        override fun hasRecoverableFile(): Boolean =
            baseFile.exists() || backupFile.exists()

        override fun startWrite(): FileOutputStream = FileOutputStream(baseFile)

        override fun finishWrite(output: FileOutputStream) {
            output.fd.sync()
            output.close()
        }

        override fun failWrite(output: FileOutputStream) {
            output.close()
        }

        override fun delete() {
            baseFile.delete()
            backupFile.delete()
        }
    }

    private companion object {
        const val VALID_TOKEN = "YANJI1.YWJj.ZGVm"
    }
}

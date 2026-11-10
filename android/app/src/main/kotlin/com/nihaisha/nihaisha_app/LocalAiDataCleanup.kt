package com.nihaisha.nihaisha_app

import java.io.File

/**
 * Deletes only directories and legacy files owned by local AI.
 * The caller must release the LiteRT-LM Engine before removing runtime cache.
 */
internal object LocalAiDataCleanup {
    fun deleteOwnedDirectory(cacheRoot: File, directoryName: String): Int {
        val canonicalRoot = cacheRoot.canonicalFile
        val rawTarget = File(canonicalRoot, directoryName)
        val target = rawTarget.canonicalFile
        if (target.parentFile != canonicalRoot) {
            throw IllegalArgumentException("AI cache directory must be a direct child of cacheDir")
        }
        if (target.path != rawTarget.absoluteFile.path) {
            throw IllegalArgumentException("AI cache directory must not be a symbolic link")
        }
        if (!target.exists()) return 0
        if (!target.isDirectory) {
            throw IllegalStateException("AI cache path is not a directory: ${target.name}")
        }
        val deletedFiles = deleteRecursively(target, canonicalRoot)
        if (!target.delete()) {
            throw IllegalStateException("Unable to delete AI cache directory: ${target.name}")
        }
        return deletedFiles
    }

    fun deleteLegacyRecordingFiles(cacheRoot: File): Int {
        val canonicalRoot = cacheRoot.canonicalFile
        if (!canonicalRoot.exists()) return 0
        if (!canonicalRoot.isDirectory) {
            throw IllegalStateException("cacheDir is not a directory")
        }
        val legacyFiles = canonicalRoot.listFiles()
            ?: throw IllegalStateException("Unable to enumerate cacheDir")
        var deleted = 0
        legacyFiles
            .filter { it.isFile && LEGACY_RECORDING_NAME.matches(it.name) }
            .forEach { file ->
                if (!file.delete()) {
                    throw IllegalStateException("Unable to delete legacy AI recording: ${file.name}")
                }
                deleted++
            }
        return deleted
    }

    private fun deleteRecursively(directory: File, canonicalRoot: File): Int {
        val children = directory.listFiles()
            ?: throw IllegalStateException("Unable to enumerate AI cache directory: ${directory.name}")
        var deletedFiles = 0
        children.forEach { child ->
            // Never follow symlinks out of the AI-owned cache tree.
            if (child.canonicalFile.path != child.absoluteFile.path) {
                if (!child.delete()) {
                    throw IllegalStateException("Unable to delete AI cache link: ${child.name}")
                }
                return@forEach
            }
            val canonicalChild = child.canonicalFile
            if (!canonicalChild.path.startsWith(canonicalRoot.path + File.separator)) {
                throw IllegalStateException("AI cache entry escapes cacheDir: ${child.name}")
            }
            if (child.isDirectory) {
                deletedFiles += deleteRecursively(child, canonicalRoot)
                if (!child.delete()) {
                    throw IllegalStateException("Unable to delete AI cache directory: ${child.name}")
                }
            } else {
                if (!child.delete()) {
                    throw IllegalStateException("Unable to delete AI cache file: ${child.name}")
                }
                deletedFiles++
            }
        }
        return deletedFiles
    }

    private val LEGACY_RECORDING_NAME = Regex("^local_ai_[0-9]+\\.wav$")
}

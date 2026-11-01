package com.nihaisha.nihaisha_app

import java.io.File

/**
 * Recovers and cleans the sibling files used by the transactional model importer.
 *
 * If the process stopped after moving the installed model to `.previous` but
 * before moving the verified `.importing` file into place, restore the old model.
 * If the target already exists, replacement completed and the old backup is stale.
 */
internal object LocalAiModelImportRecovery {
    fun recover(modelFile: File) {
        val parent = modelFile.parentFile
            ?: throw IllegalStateException("模型目录不可用")
        val backupFile = File(parent, modelFile.name + ".previous")
        val tempFile = File(parent, modelFile.name + ".importing")

        if (modelFile.exists() && !modelFile.isFile) {
            throw IllegalStateException("模型目标路径不是普通文件，无法恢复旧模型")
        }
        if (backupFile.exists() && !backupFile.isFile) {
            throw IllegalStateException("旧模型备份路径不是普通文件，无法安全恢复")
        }
        if (tempFile.exists() && !tempFile.isFile) {
            throw IllegalStateException("模型临时导入路径不是普通文件，无法安全清理")
        }
        if (!modelFile.exists() && backupFile.exists() && !backupFile.renameTo(modelFile)) {
            throw IllegalStateException("检测到旧模型备份，但无法恢复；请检查应用存储空间")
        }
        if (backupFile.exists() && !backupFile.delete()) {
            throw IllegalStateException("无法清理旧模型备份文件")
        }
        if (tempFile.exists() && !tempFile.delete()) {
            throw IllegalStateException("无法清理上一次未完成的导入文件")
        }
    }
}

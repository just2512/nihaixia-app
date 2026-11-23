package com.nihaisha.nihaisha_app

import android.content.Context
import android.util.AtomicFile
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets

internal class LicenseTokenStoreException(
    val code: String,
    override val message: String,
    cause: Throwable? = null
) : Exception(message, cause)

/**
 * One-token atomic persistence under Context.noBackupFilesDir.
 *
 * The caller must verify signature, protocol revision, Feature set and device
 * fingerprint before calling writeAfterVerification(). This adapter does not
 * grant entitlements and stores no derived is_pro/Feature state.
 */
internal class LicenseTokenStore(context: Context) {
    private val lock = Any()
    private val directory = File(context.noBackupFilesDir, "yanji_license")
    private val baseFile = File(directory, "active_license.token")
    private val atomicFile = AtomicFile(baseFile)

    fun read(): String? = synchronized(lock) {
        if (!baseFile.exists()) return@synchronized null

        try {
            val bytes = ByteArrayOutputStream()
            atomicFile.openRead().use { input ->
                val buffer = ByteArray(4096)
                var total = 0
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    total += count
                    if (total > LicenseTokenStorePolicy.MAX_TOKEN_BYTES) {
                        throw LicenseTokenStoreException(
                            "storeCorrupt",
                            "本地授权 Token 超过协议长度上限。"
                        )
                    }
                    bytes.write(buffer, 0, count)
                }
            }

            val raw = bytes.toByteArray()
            if (!LicenseTokenStorePolicy.isValidStoredTokenBytes(raw)) {
                throw LicenseTokenStoreException(
                    "storeCorrupt",
                    "本地授权 Token 文件内容为空、格式错误或长度超限。"
                )
            }
            val decoded = StandardCharsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(raw))
                .toString()
            if (!LicenseTokenStorePolicy.isValidStoredToken(decoded)) {
                throw LicenseTokenStoreException(
                    "storeCorrupt",
                    "本地授权 Token 文件不是规范的完整 Token。"
                )
            }
            decoded
        } catch (error: LicenseTokenStoreException) {
            throw error
        } catch (error: FileNotFoundException) {
            if (!baseFile.exists()) {
                null
            } else {
                throw LicenseTokenStoreException(
                    "storageUnavailable",
                    "本地授权 Token 文件暂时无法读取。",
                    error
                )
            }
        } catch (error: CharacterCodingException) {
            throw LicenseTokenStoreException(
                "storeCorrupt",
                "本地授权 Token 文件不是有效 UTF-8。",
                error
            )
        } catch (error: IOException) {
            throw LicenseTokenStoreException(
                "storageUnavailable",
                "本地授权 Token 文件读取失败。",
                error
            )
        }
    }

    /**
     * Removes only the Token file. The device signing key is never deleted here.
     */
    fun deleteToken() = synchronized(lock) {
        try {
            atomicFile.delete()
        } catch (error: Exception) {
            throw LicenseTokenStoreException(
                "storageUnavailable",
                "无法删除本地授权 Token 文件。",
                error
            )
        }
    }

    fun writeAfterVerification(token: String) = synchronized(lock) {
        if (!LicenseTokenStorePolicy.isValidStoredToken(token)) {
            throw LicenseTokenStoreException(
                "invalidArgument",
                "待保存内容不是有效的完整授权 Token 外层格式。"
            )
        }
        val raw = token.toByteArray(StandardCharsets.UTF_8)
        if (!LicenseTokenStorePolicy.isValidStoredTokenBytes(raw)) {
            throw LicenseTokenStoreException(
                "invalidArgument",
                "待保存授权 Token 超过协议长度上限。"
            )
        }
        if (!directory.exists() && !directory.mkdirs()) {
            throw LicenseTokenStoreException(
                "storageUnavailable",
                "无法创建应用私有授权目录。"
            )
        }

        var output: java.io.FileOutputStream? = null
        try {
            output = atomicFile.startWrite()
            output.write(raw)
            output.flush()
            output.fd.sync()
            atomicFile.finishWrite(output)
            output = null
        } catch (error: Exception) {
            output?.let { atomicFile.failWrite(it) }
            throw LicenseTokenStoreException(
                "storageUnavailable",
                "授权 Token 原子写入失败；旧文件应保持不变。",
                error
            )
        }
    }
}

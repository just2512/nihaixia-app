package com.nihaisha.nihaisha_app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val expectedModelBytes = 3_659_530_240L
    private val expectedModelSha256 = "0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0"
    private val modelImportRequestCode = 8427
    private var pendingModelImportResult: MethodChannel.Result? = null
    private val installChannel = "com.nihaisha.app/install"
    private val localAiChannel = "com.nihaisha.app/local_ai"
    private val aiExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    // The model stays outside the APK. Copy the .litertlm file into this app-private folder.
    private val modelFile: File
        get() = File(File(filesDir, "ai_models"), "gemma-4-E4B-it.litertlm")

    private var aiEngine: Engine? = null
    private var aiConversation: Conversation? = null
    private var activeBackend = "not_loaded"
    private var conversationHasSuccessfulTurn = false

    // Only explicit user text and pending audio transcripts enter symptom extraction.
    // Image observations and assistant responses are intentionally excluded.
    private val userReportedInputs = mutableListOf<String>()

    private fun recordUserInput(source: String, value: String) {
        val normalized = value.trim()
        if (normalized.isEmpty()) return
        if (userReportedInputs.size >= 100) userReportedInputs.removeAt(0)
        userReportedInputs.add("$source：" + normalized.take(2000))
    }

    private val systemInstruction = """
        你是一个离线健康信息整理助手。你的任务是倾听用户描述、提出必要的澄清问题，并用通俗中文解释一般健康信息。
        严格边界：
        1. 不作现代医学疾病诊断，不作中医六经辨证结论。
        2. 不选择、推荐或生成中药方剂，不提供药物剂量、加减或停药建议。
        3. 不把推测写成事实；信息不足时明确询问，不连续堆砌问题。
        4. 可以帮助用户整理其自述的症状、持续时间、变化、诱因和伴随表现，但必须标记为“用户自述”，不能自行补全。
        5. 遇到胸痛、呼吸困难、意识障碍、突发偏瘫/言语障碍、大量出血、自伤风险等急症信号，先建议立即寻求当地急救，不继续普通问诊。
        6. 你的回复不会直接进入辨证引擎。最终辨证由应用内独立的、用户可核对的规则问诊流程完成。
        语气自然、克制，避免模板化开场、夸张承诺和“作为AI”等表述。
    """.trimIndent()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, installChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "installApk") {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        installApk(File(path))
                        result.success(true)
                    } else {
                        result.error("INVALID_PATH", "APK路径为空", null)
                    }
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, localAiChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getModelStatus" -> runAiTask(result) { modelStatus() }
                    "importModel" -> beginModelImport(result)
                    "loadModel" -> runAiTask(result) { loadLocalModel() }
                    "extractSymptoms" -> runAiTask(result) { extractSymptoms() }
                    "sendImage" -> {
                        val path = call.argument<String>("path")?.trim().orEmpty()
                        val prompt = call.argument<String>("prompt")?.trim().orEmpty()
                        if (path.isEmpty()) {
                            result.error("EMPTY_IMAGE_PATH", "没有选择照片", null)
                        } else {
                            runAiTask(result) { sendLocalImage(path, prompt) }
                        }
                    }
                    "sendAudio" -> {
                        val path = call.argument<String>("path")?.trim().orEmpty()
                        val prompt = call.argument<String>("prompt")?.trim().orEmpty()
                        if (path.isEmpty()) {
                            result.error("EMPTY_AUDIO_PATH", "没有录音文件", null)
                        } else {
                            runAiTask(result) { sendLocalAudio(path, prompt) }
                        }
                    }
                    "sendMessage" -> {
                        val text = call.argument<String>("text")?.trim().orEmpty()
                        if (text.isEmpty()) {
                            result.error("EMPTY_MESSAGE", "请输入内容后再发送", null)
                        } else {
                            runAiTask(result) { sendLocalMessage(text) }
                        }
                    }
                    "resetConversation" -> runAiTask(result) { resetLocalConversation() }
                    "releaseModel" -> runAiTask(result) { releaseLocalModel() }
                    else -> result.notImplemented()
                }
            }
    }

    private fun runAiTask(result: MethodChannel.Result, task: () -> Any?) {
        aiExecutor.execute {
            try {
                val value = task()
                mainHandler.post { result.success(value) }
            } catch (error: Exception) {
                mainHandler.post {
                    result.error(
                        "LOCAL_AI_ERROR",
                        error.message ?: error.javaClass.simpleName,
                        null
                    )
                }
            }
        }
    }

    private fun beginModelImport(result: MethodChannel.Result) {
        if (pendingModelImportResult != null) {
            result.error("MODEL_IMPORT_BUSY", "已有模型文件选择操作正在进行", null)
            return
        }
        pendingModelImportResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            startActivityForResult(intent, modelImportRequestCode)
        } catch (error: Exception) {
            pendingModelImportResult = null
            result.error("MODEL_PICKER_UNAVAILABLE", error.message ?: "无法打开系统文件选择器", null)
        }
    }

    private fun importModelFromUri(uri: Uri): Map<String, Any> {
        if (aiEngine != null || aiConversation != null) {
            throw IllegalStateException("请先释放本地模型，再导入新的模型文件")
        }

        val parent = modelFile.parentFile
            ?: throw IllegalStateException("模型目录不可用")
        if (!parent.exists() && !parent.mkdirs()) {
            throw IllegalStateException("无法创建模型目录")
        }

        val tempFile = File(parent, modelFile.name + ".importing")
        val backupFile = File(parent, modelFile.name + ".previous")
        // Recover the previous model if the process was interrupted between backup and replacement.
        if (!modelFile.exists() && backupFile.exists() && !backupFile.renameTo(modelFile)) {
            throw IllegalStateException("检测到旧模型备份，但无法恢复；请检查应用存储空间")
        }
        if (backupFile.exists() && !backupFile.delete()) {
            throw IllegalStateException("无法清理旧模型备份文件")
        }
        if (tempFile.exists() && !tempFile.delete()) {
            throw IllegalStateException("无法清理上一次未完成的导入文件")
        }

        try {
            val digest = MessageDigest.getInstance("SHA-256")
            var totalBytes = 0L
            val input = contentResolver.openInputStream(uri)
                ?: throw IllegalArgumentException("无法读取所选模型文件")

            input.use { source ->
                tempFile.outputStream().buffered().use { target ->
                    val buffer = ByteArray(1024 * 1024)
                    while (true) {
                        val count = source.read(buffer)
                        if (count < 0) break
                        if (count == 0) continue
                        totalBytes += count
                        if (totalBytes > expectedModelBytes) {
                            throw IllegalArgumentException("模型文件超过预期大小 3,659,530,240 bytes")
                        }
                        digest.update(buffer, 0, count)
                        target.write(buffer, 0, count)
                    }
                }
            }

            if (totalBytes != expectedModelBytes || tempFile.length() != expectedModelBytes) {
                throw IllegalArgumentException(
                    "模型文件大小不正确：实际 $totalBytes bytes，要求 $expectedModelBytes bytes"
                )
            }

            val actualSha256 = digest.digest().joinToString("") {
                "%02x".format(it.toInt() and 0xff)
            }
            if (!actualSha256.equals(expectedModelSha256, ignoreCase = true)) {
                throw IllegalArgumentException(
                    "模型 SHA-256 校验失败：文件不是受支持的 Gemma 4 E4B IT 模型"
                )
            }

            val hadPreviousModel = modelFile.exists()
            if (hadPreviousModel && !modelFile.renameTo(backupFile)) {
                throw IllegalStateException("无法暂存旧模型文件，未覆盖原文件")
            }
            if (!tempFile.renameTo(modelFile)) {
                if (hadPreviousModel) backupFile.renameTo(modelFile)
                throw IllegalStateException("模型文件导入完成但无法替换目标文件，已尝试恢复旧文件")
            }
            if (backupFile.exists()) backupFile.delete()
            return modelStatus()
        } catch (error: Exception) {
            if (tempFile.exists()) tempFile.delete()
            throw error
        }
    }

    private fun modelStatus(): Map<String, Any> {
        modelFile.parentFile?.mkdirs()
        val fileExists = modelFile.isFile && modelFile.length() > 0L
        val exists = fileExists && modelFile.length() == expectedModelBytes
        return mapOf(
            "installed" to exists,
            "fileExists" to fileExists,
            "modelPath" to modelFile.absolutePath,
            "sizeBytes" to if (fileExists) modelFile.length() else 0L,
            "expectedSizeBytes" to expectedModelBytes,
            "ready" to (aiEngine != null && aiConversation != null),
            "backend" to activeBackend
        )
    }

    private fun loadLocalModel(): Map<String, Any> {
        if (!modelFile.isFile || modelFile.length() != expectedModelBytes) {
            return modelStatus()
        }
        if (aiEngine != null && aiConversation != null) return modelStatus()

        modelFile.parentFile?.mkdirs()
        val cachePath = File(cacheDir, "litertlm").apply { mkdirs() }.absolutePath

        // Prefer GPU where the device exposes a compatible OpenCL runtime; retry on CPU.
        // A failed Engine.initialize() instance is intentionally not closed: LiteRT-LM
        // documents that closing an engine whose initialize() failed can throw.
        var loadedEngine: Engine? = null
        var gpuFailure: Exception? = null
        try {
            val candidate = Engine(
                EngineConfig(
                    modelPath = modelFile.absolutePath,
                    backend = Backend.GPU(),
                    visionBackend = Backend.GPU(),
                    audioBackend = Backend.CPU(),
                    cacheDir = cachePath
                )
            )
            candidate.initialize()
            loadedEngine = candidate
            activeBackend = "gpu"
        } catch (error: Exception) {
            gpuFailure = error
        }

        if (loadedEngine == null) {
            val candidate = Engine(
                EngineConfig(
                    modelPath = modelFile.absolutePath,
                    backend = Backend.CPU(),
                    visionBackend = Backend.CPU(),
                    audioBackend = Backend.CPU(),
                    cacheDir = cachePath
                )
            )
            try {
                candidate.initialize()
                loadedEngine = candidate
                activeBackend = "cpu"
            } catch (cpuError: Exception) {
                activeBackend = "not_loaded"
                throw IllegalStateException(
                    "GPU 初始化失败：${gpuFailure?.message ?: "未知错误"}；CPU 初始化也失败：${cpuError.message}",
                    cpuError
                )
            }
        }

        aiEngine = loadedEngine
        try {
            aiConversation = loadedEngine!!.createConversation(
                ConversationConfig(systemInstruction = Contents.of(systemInstruction))
            )
            conversationHasSuccessfulTurn = false
        } catch (error: Exception) {
            releaseLocalModel()
            throw error
        }
        return modelStatus()
    }

    private fun sendLocalMessage(text: String): Map<String, Any> {
        val reply = sendWithFirstTurnGpuFallback { conversation ->
            conversation.sendMessage(text).toString()
        }
        recordUserInput("用户文字自述", text)
        return mapOf("reply" to reply, "backend" to activeBackend)
    }

    private fun <T> sendWithFirstTurnGpuFallback(send: (Conversation) -> T): T {
        val conversation = aiConversation
            ?: throw IllegalStateException("本地模型尚未加载")
        return try {
            val result = send(conversation)
            conversationHasSuccessfulTurn = true
            result
        } catch (error: Exception) {
            if (!FirstTurnGpuFallbackPolicy.shouldFallback(
                    activeBackend,
                    conversationHasSuccessfulTurn,
                    error
                )
            ) {
                throw error
            }

            recreateCpuEngineAfterFirstTurnOpenClFailure(error)
            val cpuConversation = aiConversation
                ?: throw IllegalStateException("CPU 回退后没有创建有效会话")
            try {
                val result = send(cpuConversation)
                conversationHasSuccessfulTurn = true
                result
            } catch (cpuError: Exception) {
                throw IllegalStateException(
                    "GPU 首轮推理报告 OpenCL 不可用；已切换 CPU，但重试仍失败：${cpuError.message}",
                    cpuError
                ).also { it.addSuppressed(error) }
            }
        }
    }

    private fun recreateCpuEngineAfterFirstTurnOpenClFailure(originalError: Exception) {
        val previousConversation = aiConversation
        val previousEngine = aiEngine

        // Detach first so no failed object can be reused or closed twice.
        aiConversation = null
        aiEngine = null
        activeBackend = "not_loaded"
        conversationHasSuccessfulTurn = false

        var releaseFailure: Exception? = null
        try {
            previousConversation?.close()
        } catch (error: Exception) {
            releaseFailure = error
        }
        try {
            previousEngine?.close()
        } catch (error: Exception) {
            if (releaseFailure == null) {
                releaseFailure = error
            } else {
                releaseFailure.addSuppressed(error)
            }
        }
        if (releaseFailure != null) {
            releaseFailure.addSuppressed(originalError)
            throw IllegalStateException(
                "GPU 首轮推理失败，旧 GPU 会话或引擎未能安全释放；已跳过 CPU 自动重试",
                releaseFailure
            )
        }

        val cachePath = File(cacheDir, "litertlm").apply { mkdirs() }.absolutePath
        val cpuEngine = Engine(
            EngineConfig(
                modelPath = modelFile.absolutePath,
                backend = Backend.CPU(),
                visionBackend = Backend.CPU(),
                audioBackend = Backend.CPU(),
                cacheDir = cachePath
            )
        )

        try {
            cpuEngine.initialize()
        } catch (error: Exception) {
            // LiteRT-LM forbids closing an Engine whose initialize() failed.
            error.addSuppressed(originalError)
            throw IllegalStateException(
                "GPU 首轮 OpenCL 错误后，CPU 引擎初始化也失败：${error.message}",
                error
            )
        }

        val cpuConversation = try {
            cpuEngine.createConversation(
                ConversationConfig(systemInstruction = Contents.of(systemInstruction))
            )
        } catch (error: Exception) {
            try {
                cpuEngine.close()
            } catch (closeError: Exception) {
                error.addSuppressed(closeError)
            }
            error.addSuppressed(originalError)
            throw IllegalStateException(
                "CPU 引擎已初始化，但无法创建问诊会话：${error.message}",
                error
            )
        }

        aiEngine = cpuEngine
        aiConversation = cpuConversation
        activeBackend = "cpu"
    }

    private fun requireCachedInput(path: String, kind: String): File {
        val file = File(path).canonicalFile
        val cacheRoot = cacheDir.canonicalFile
        val error = LocalAiAttachmentPolicy.validationError(
            filePath = file.path,
            cacheRootPath = cacheRoot.path,
            isFile = file.isFile,
            sizeBytes = file.length(),
            kind = kind
        )
        if (error != null) throw IllegalArgumentException(error)
        return file
    }

    private fun sendLocalImage(path: String, userPrompt: String): Map<String, Any> {
        val image = requireCachedInput(path, "照片")
        val prompt =
            "请只描述照片中能够直接观察到的舌体形态、舌色和舌苔分布。" +
            "不要作现代医学诊断或中医证型辨证，不推荐方剂、药物或剂量。" +
            "若照片存在模糊、遮挡、光线或曝光问题，请明确说明；无法确认的特征请说无法判断。" +
            if (userPrompt.isBlank()) "" else "\n用户补充问题：" + userPrompt.take(500)
        val reply = sendWithFirstTurnGpuFallback { conversation ->
            conversation.sendMessage(
                Contents.of(
                    Content.ImageFile(image.absolutePath),
                    Content.Text(prompt)
                )
            ).toString()
        }
        recordUserInput("用户随照片输入的文字", userPrompt)
        return mapOf("reply" to reply, "backend" to activeBackend)
    }

    private fun sendLocalAudio(path: String, userPrompt: String): Map<String, Any> {
        val audio = requireCachedInput(path, "录音")
        LocalAiWavPolicy.validationError(audio)?.let { error ->
            throw IllegalArgumentException(error)
        }
        val prompt =
            "请逐句转写这段用户语音，尽量保留原始措辞，只可补充必要标点；听不清的内容标记为“听不清”，" +
            "不要总结、推断、改写或自行补全。只做语音转写，不作诊断或辨证，不推荐药物或方剂。" +
            if (userPrompt.isBlank()) "" else "\n用户补充问题：" + userPrompt.take(500)
        val reply = sendWithFirstTurnGpuFallback { conversation ->
            conversation.sendMessage(
                Contents.of(
                    Content.AudioFile(audio.absolutePath),
                    Content.Text(prompt)
                )
            ).toString()
        }
        recordUserInput("用户随录音输入的文字", userPrompt)
        recordUserInput("语音识别草稿（模型生成，尚待用户核对）", reply)
        return mapOf("reply" to reply, "backend" to activeBackend)
    }

    private fun extractSymptoms(): Map<String, Any> {
        val engine = aiEngine
            ?: throw IllegalStateException("本地模型尚未加载")
        if (userReportedInputs.isEmpty()) {
            return mapOf(
                "draft" to """{"main_complaint":null,"onset":null,"duration":null,"location":null,"sensation":null,"aggravating_factors":[],"relieving_factors":[],"associated_symptoms":[],"red_flags":[],"unknowns":[]}"""
            )
        }
        val userInputContext = userReportedInputs.mapIndexed { index, input ->
            (index + 1).toString() + ". " + input
        }.joinToString("\n")
        val prompt = """
            请根据当前对话中用户明确提供的信息，整理一份“用户自述症状草稿”。
            只记录用户通过文字或语音明确表达的事实，不记录模型对照片的观察，不推断、不补全，
            不作任何现代医学诊断或中医辨证，不推荐方剂或药物。
            未提及的字段必须填 null 或空数组。输出严格 JSON，不要 Markdown 代码围栏，不要附加解释。
            JSON 字段固定为：
            {
              "main_complaint": string|null,
              "onset": string|null,
              "duration": string|null,
              "location": string|null,
              "sensation": string|null,
              "aggravating_factors": string[],
              "relieving_factors": string[],
              "associated_symptoms": string[],
              "red_flags": string[],
              "unknowns": string[]
            }
            red_flags 只记录用户明确说出的急症相关表现，不要自行判定风险等级。
            unknowns 记录仍需向用户核实的信息。
            以下内容是应用单独保存的用户原始文字输入和待核对语音识别草稿。
            不得使用照片、舌象观察或模型此前的回复；这些内容没有提供给你。
            语音识别草稿尚未由用户核对，只能按其文字整理，不得补全。

            用户输入记录：
            $userInputContext
        """.trimIndent()
        val extractionConversation = engine.createConversation(
            ConversationConfig(
                systemInstruction = Contents.of(
                    "你只整理应用提供的用户输入记录。不要诊断、辨证、开方或提供剂量。"
                )
            )
        )
        return try {
            mapOf("draft" to extractionConversation.sendMessage(prompt).toString())
        } finally {
            extractionConversation.close()
        }
    }

    private fun resetLocalConversation(): Map<String, Any> {
        val engine = aiEngine ?: throw IllegalStateException("本地模型尚未加载")
        val previousConversation = aiConversation
        aiConversation = null

        return try {
            val nextConversation = ConversationResetPolicy.recreateConversation(
                closePrevious = { previousConversation?.close() },
                createNext = {
                    engine.createConversation(
                        ConversationConfig(systemInstruction = Contents.of(systemInstruction))
                    )
                },
                closeEngine = { engine.close() }
            )
            aiConversation = nextConversation
            userReportedInputs.clear()
            conversationHasSuccessfulTurn = false
            modelStatus()
        } catch (error: Exception) {
            // Never retain an Engine without a usable Conversation. A later load
            // must start from a clean state rather than overwrite a live engine.
            aiEngine = null
            aiConversation = null
            userReportedInputs.clear()
            activeBackend = "not_loaded"
            conversationHasSuccessfulTurn = false
            throw error
        }
    }

    private fun releaseLocalModel(): Map<String, Any> {
        val conversation = aiConversation
        val engine = aiEngine
        // Clear references before close: LiteRT-LM objects must be closed exactly once.
        aiConversation = null
        aiEngine = null
        userReportedInputs.clear()
        activeBackend = "not_loaded"
        conversationHasSuccessfulTurn = false
        ConversationResourceReleasePolicy.closeBoth(
            closeConversation = { conversation?.close() },
            closeEngine = { engine?.close() }
        )
        return modelStatus()
    }

    private fun installApk(file: File) {
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(
                FileProvider.getUriForFile(
                    this@MainActivity,
                    "${packageName}.fileprovider",
                    file
                ),
                "application/vnd.android.package-archive"
            )
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(intent)
    }

    @Deprecated("Deprecated in Android, retained for FlutterActivity file-picker result compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != modelImportRequestCode) return

        val pending = pendingModelImportResult
        pendingModelImportResult = null
        if (pending == null) return

        val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
        if (uri == null) {
            pending.success(modelStatus())
            return
        }

        aiExecutor.execute {
            try {
                val status = importModelFromUri(uri)
                mainHandler.post { pending.success(status) }
            } catch (error: Exception) {
                mainHandler.post {
                    pending.error(
                        "MODEL_IMPORT_FAILED",
                        error.message ?: error.javaClass.simpleName,
                        null
                    )
                }
            }
        }
    }

    override fun onDestroy() {
        pendingModelImportResult = null
        aiExecutor.execute {
            try {
                releaseLocalModel()
            } catch (_: Exception) {
                // Activity teardown must not crash if native runtime shutdown fails.
            }
        }
        aiExecutor.shutdown()
        super.onDestroy()
    }
}

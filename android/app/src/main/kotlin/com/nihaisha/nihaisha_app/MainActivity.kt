package com.nihaisha.nihaisha_app

import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
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
                    "getModelStatus" -> result.success(modelStatus())
                    "loadModel" -> runAiTask(result) { loadLocalModel() }
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

    private fun modelStatus(): Map<String, Any> {
        val exists = modelFile.isFile && modelFile.length() > 0L
        return mapOf(
            "installed" to exists,
            "modelPath" to modelFile.absolutePath,
            "sizeBytes" to if (exists) modelFile.length() else 0L,
            "ready" to (aiEngine != null && aiConversation != null),
            "backend" to activeBackend
        )
    }

    private fun loadLocalModel(): Map<String, Any> {
        if (!modelFile.isFile || modelFile.length() == 0L) {
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
        } catch (error: Exception) {
            releaseLocalModel()
            throw error
        }
        return modelStatus()
    }

    private fun sendLocalMessage(text: String): Map<String, Any> {
        val conversation = aiConversation
            ?: throw IllegalStateException("本地模型尚未加载")
        val reply = conversation.sendMessage(text)
        return mapOf("reply" to reply, "backend" to activeBackend)
    }

    private fun resetLocalConversation(): Map<String, Any> {
        val engine = aiEngine ?: throw IllegalStateException("本地模型尚未加载")
        aiConversation?.close()
        aiConversation = engine.createConversation(
            ConversationConfig(systemInstruction = Contents.of(systemInstruction))
        )
        return modelStatus()
    }

    private fun releaseLocalModel(): Map<String, Any> {
        aiConversation?.close()
        aiConversation = null
        aiEngine?.close()
        aiEngine = null
        activeBackend = "not_loaded"
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

    override fun onDestroy() {
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

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../utils/fold_aware_routes.dart';
import '../widgets/adaptive_master_detail.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../services/local_ai_service.dart';
import '../services/red_flag_gate.dart';
import '../services/red_flag_preflight.dart';
import '../services/ai_trace.dart';
import '../services/ai_trace_runtime.dart';
import '../services/local_ai_attachment_store.dart';
import '../services/assistant_knowledge_context.dart';
import '../services/assistant_conversation_orchestrator.dart';
import '../services/tcm_interview_conversation_controller.dart';
import 'assistant_tool_router.dart';
import '../data/database_helper.dart';
import '../data/assistant_conversation_store.dart';
import '../data/settings_repository.dart';
import '../models/tcm_interview_task_state.dart';
import '../models/diagnosis.dart';
import '../models/bookmark.dart';
import '../models/diagnosis_result_codec.dart';
import '../models/zangfu_evidence.dart';
import '../models/assistant_tool_result.dart';
import '../models/assistant_message_metadata.dart';
import '../services/yijing_tool_executor.dart';
import '../services/dosage_tool_executor.dart';
import '../services/dosage_conversion_service.dart';
import '../services/ziwuliuzhu_tool_executor.dart';
import 'assistant_history_screen.dart';
import '../theme/app_tokens.dart';
import '../data/formula_repository.dart';
import '../data/herb_repository.dart';
import '../data/acupuncture_repository.dart';
import '../data/acupoint_repository.dart';
import '../data/medical_case_data.dart';
import '../services/classic_search_service.dart';
import 'formula_detail_screen.dart';
import 'herb_detail_screen.dart';
import 'acupoint_detail_screen.dart';
import 'acupuncture_screen.dart';
import 'medical_case_detail_screen.dart';
import 'neijing_knowledge_screen.dart';
import 'markdown_doc_screen.dart';
import 'guji_library_screen.dart';

/// Provenance for results returned by the existing deterministic DiagnosticEngine.
/// This is an engine origin, not a knowledge-base citation.
const _diagnosticEngineSourceIds = <String>[
  'local-engine:diagnostic-engine',
];

bool _needsTcmKnowledgeForTool(AssistantMode mode, String toolId) =>
    mode == AssistantMode.tools &&
    const {'yunqi', 'dosage', 'ziwu_liuzhu'}.contains(toolId);

String _tcmToolKnowledgeQuery(String userText, AssistantToolDefinition tool) =>
    '${userText.trim()} ${tool.title}';

abstract interface class LocalAiAudioRecorder {
  Future<bool> hasPermission();
  Future<void> start(RecordConfig config, {required String path});
  Future<String?> stop();
  Future<void> dispose();
}

/// File-system boundary for validating a completed recording before it can
/// be attached to a consultation message.
abstract interface class LocalAiRecordingFileInspector {
  /// Returns null when the path does not resolve to an existing file.
  Future<int?> sizeBytes(String path);
}

/// Path-based adapter for deterministic camera and Android lost-result tests.
abstract interface class LocalAiImagePicker {
  Future<String?> pickCameraImagePath();
  Future<String?> pickGalleryImagePath();
  Future<String?> retrieveLostImagePath();
}

class _IoLocalAiRecordingFileInspector
    implements LocalAiRecordingFileInspector {
  @override
  Future<int?> sizeBytes(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    return file.length();
  }
}

class _PluginLocalAiAudioRecorder implements LocalAiAudioRecorder {
  final AudioRecorder _recorder = AudioRecorder();

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start(RecordConfig config, {required String path}) =>
      _recorder.start(config, path: path);

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> dispose() => _recorder.dispose();
}

class _PluginLocalAiImagePicker implements LocalAiImagePicker {
  final ImagePicker _picker = ImagePicker();

  @override
  Future<String?> pickCameraImagePath() async {
    final photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
      maxWidth: 1600,
      maxHeight: 1600,
      requestFullMetadata: false,
    );
    return photo?.path;
  }

  @override
  Future<String?> pickGalleryImagePath() async {
    final photo = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: 1600,
      maxHeight: 1600,
      requestFullMetadata: false,
    );
    return photo?.path;
  }

  @override
  Future<String?> retrieveLostImagePath() async {
    final response = await _picker.retrieveLostData();
    if (response.isEmpty || response.files == null ||
        response.files!.isEmpty) {
      return null;
    }
    return response.files!.first.path;
  }
}

class LocalAiInterviewScreen extends StatefulWidget {
  const LocalAiInterviewScreen({
    super.key,
    this.service,
    this.redFlagGate,
    this.audioRecorder,
    this.recordingFileInspector,
    this.imagePicker,
    this.attachmentStore,
    this.conversationStore,
    this.bookmarkWriter,
    this.shareDiagnosisText,
    this.copyPrescriptionText,
    this.preferredAnchorPoint,
    this.initialPrompt,
    this.testToolRouteBuilder,
    this.testHeadlessToolExecutor,
    this.traceRecorder,
  });

  /// Optional gate injection for B2 entrypoint-order tests. Production must not
  /// supply this until a medically reviewed detector and rollout policy exist.
  /// A missing gate is recorded as NOT_APPLICABLE, never as CLEAR.
  @visibleForTesting
  final RedFlagGate? redFlagGate;

  /// Injectable to verify initialization and error states without a native model.
  final LocalAiService? service;

  /// Optional recorder adapter for deterministic recording lifecycle tests.
  final LocalAiAudioRecorder? audioRecorder;

  /// Optional file inspector to isolate recording lifecycle tests from disk IO.
  final LocalAiRecordingFileInspector? recordingFileInspector;

  /// Optional camera/recovery adapter for deterministic attachment lifecycle tests.
  final LocalAiImagePicker? imagePicker;
  /// Injectable owner for local AI attachment files.
  final LocalAiAttachmentStore? attachmentStore;
  final AssistantConversationStore? conversationStore;

  /// Test seam for verifying the assistant's diagnosis bookmark action.
  @visibleForTesting
  final Future<int> Function(Bookmark bookmark)? bookmarkWriter;

  /// Test seam for verifying the unified assistant's diagnosis share action.
  @visibleForTesting
  final void Function(String text)? shareDiagnosisText;

  /// Test seam for verifying the exact prescription text sent to the clipboard.
  @visibleForTesting
  final Future<void> Function(String text)? copyPrescriptionText;

  /// Deterministic route seam for persistence/retry widget tests. Production
  /// callers leave this null and use the registered in-app tool page.
  @visibleForTesting
  final Widget Function(AssistantToolDefinition tool, AssistantToolArguments arguments)?
      testToolRouteBuilder;

  /// Test seam for forcing typed Headless results through the production validator.
  @visibleForTesting
  final FutureOr<AssistantToolResult> Function(Map<String, String> arguments)?
      testHeadlessToolExecutor;

  /// Optional draft supplied by a knowledge/detail page. It is prefilled but
  /// never sent automatically; the user remains responsible for submission.
  final String? initialPrompt;

  /// Injectable recorder for deterministic per-turn TRACE tests.
  @visibleForTesting
  final AiTraceRecorder? traceRecorder;

  /// Physical-panel anchor inherited from the control that opened this route.
  final Offset? preferredAnchorPoint;

  @override
  State<LocalAiInterviewScreen> createState() => _LocalAiInterviewScreenState();
}

const _assistantWelcomeMessage =
    '你可以直接描述身体情况、询问中医知识，或提出工具任务。助手会先识别任务类型；意图不清时会先向你确认。';

class _AssistantTurnResponse {
  const _AssistantTurnResponse({
    required this.text,
    this.sourceIds = const [],
    this.knowledgeStatus,
  });

  final String text;
  final List<String> sourceIds;
  final String? knowledgeStatus;
}

class _LocalAiInterviewScreenState extends State<LocalAiInterviewScreen> {
  AiTraceRecorder get _traceRecorder => widget.traceRecorder ?? AiTraceRuntime.recorder;
  late final LocalAiService _service;
  late final LocalAiImagePicker _imagePicker;
  late final LocalAiAttachmentStore _attachmentStore;
  late final LocalAiAudioRecorder _audioRecorder;
  late final LocalAiRecordingFileInspector _recordingFileInspector;
  Timer? _recordingTimer;
  String? _imagePath;
  String? _audioPath;
  bool _recording = false;
  bool _recordingBusy = false;
  // Lost-camera-result recovery runs during initialization. Keep all
  // attachment-sensitive actions locked until it has completed.
  bool _attachmentBusy = true;
  bool _recorderMayBeActive = false;
  String? _activeRecordingPath;
  Future<void> _recorderOperation = Future<void>.value();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_InterviewMessage> _messages = [
    const _InterviewMessage(
      text: _assistantWelcomeMessage,
      isUser: false,
    ),
  ];

  LocalAiModelStatus? _status;
  bool _statusUnknown = false;
  bool _checking = true;
  bool _loading = false;
  bool _importingModel = false;
  bool _sending = false;
  // Prevent two rapid taps from pushing duplicate tool routes concurrently.
  bool _toolRouteActive = false;
  bool _extracting = false;
  bool _modelControlBusy = false;
  bool _structuredDiagnosisBusy = false;
  TcmInterviewConversationController? _tcmInterviewController;
  late Future<int?> _conversationIdFuture;
  Future<void> _taskStateWrite = Future<void>.value();
  final Set<String> _persistedDiagnosisTaskIds = <String>{};
  String? _pendingHistoryTranscript;
  List<String> _pendingHistoryUserMessages = const [];
  int _historyRestoreGeneration = 0;
  AssistantMode _assistantMode = AssistantMode.automatic;
  AssistantMode? _lastEffectiveMode;
  bool _pendingToolSelection = false;
  AssistantToolArguments? _pendingBaziArguments;
  AssistantToolArguments? _pendingZiweiArguments;
  AssistantToolArguments? _pendingGuanshaArguments;
  AssistantToolArguments? _pendingMeihuaArguments;
  AssistantToolArguments? _pendingChengguArguments;
  AssistantToolArguments? _pendingHuangdiSijiArguments;
  AssistantToolArguments? _pendingXiaoliurenArguments;
  AssistantToolArguments? _pendingYiJingArguments;
  AssistantToolArguments? _pendingDosageArguments;
  AssistantToolArguments? _pendingZiWuArguments;
  AssistantToolArguments? _pendingDreamArguments;
  LocalAiSymptomDraft? _confirmedDraft;
  String? _error;

  AssistantConversationStore get _conversationStore =>
      widget.conversationStore ?? DatabaseHelper.instance;

  // One conversation trace can pass through _send -> routing -> tool execution.
  // Identity-based memoization ensures the injected detector is called once for
  // the originating input while every downstream boundary still checks it.
  final Set<AiTraceContext> _redFlagPreflightedContexts =
      Set<AiTraceContext>.identity();

  Future<bool> _blockIfRedFlagPreflightDoesNotClear({
    required RedFlagInputSource source,
    required String? text,
    required AiTraceContext traceContext,
    required String route,
  }) async {
    if (_redFlagPreflightedContexts.contains(traceContext)) return false;

    final gate = widget.redFlagGate;
    if (gate == null) {
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.redFlag,
        status: AiTraceStatus.notApplicable,
        route: route,
        errorCode: 'REDFLAG_GATE_NOT_CONFIGURED',
      );
      return false;
    }

    final result = await gate.evaluate(
      RedFlagInput(source: source, text: text),
    );
    final traceStatus = switch (result.status) {
      RedFlagPreflightStatus.clear => AiTraceStatus.succeeded,
      RedFlagPreflightStatus.blockUrgent => AiTraceStatus.failed,
      RedFlagPreflightStatus.clarify ||
      RedFlagPreflightStatus.reviewRequired => AiTraceStatus.unknown,
    };
    await _traceRecorder.record(
      traceContext,
      stage: AiTraceStage.redFlag,
      status: traceStatus,
      route: route,
      errorCode: result.reason,
    );

    if (result.mayContinueOrdinaryFlow) {
      if (_redFlagPreflightedContexts.length >= 32) {
        _redFlagPreflightedContexts.clear();
      }
      _redFlagPreflightedContexts.add(traceContext);
      return false;
    }

    final message = switch (result.status) {
      RedFlagPreflightStatus.blockUrgent =>
        '安全评估命中阻断条件，普通助手流程已暂停。系统不会在此处生成未经审核的医疗处置建议。',
      RedFlagPreflightStatus.clarify =>
        '安全评估无法确认内容范围，普通助手流程已暂停。请先澄清相关信息。',
      RedFlagPreflightStatus.reviewRequired =>
        '安全评估尚未完成（${result.reason}），普通助手流程已暂停；未完成评估不能视为无风险。',
      RedFlagPreflightStatus.clear => '',
    };
    if (mounted) setState(() => _error = message);
    await _traceRecorder.record(
      traceContext,
      stage: AiTraceStage.finalRender,
      status: mounted ? AiTraceStatus.succeeded : AiTraceStatus.notApplicable,
      route: route,
      errorCode: 'REDFLAG_${result.status.name.toUpperCase()}',
    );
    return true;
  }

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? LocalAiService();
    _imagePicker = widget.imagePicker ?? _PluginLocalAiImagePicker();
    _attachmentStore = widget.attachmentStore ?? LocalAiAttachmentStore();
    _audioRecorder = widget.audioRecorder ?? _PluginLocalAiAudioRecorder();
    _recordingFileInspector =
        widget.recordingFileInspector ?? _IoLocalAiRecordingFileInspector();
    final initialPrompt = widget.initialPrompt?.trim();
    if (initialPrompt != null && initialPrompt.isNotEmpty) {
      _inputController.text = initialPrompt;
      _inputController.selection = TextSelection.collapsed(
        offset: initialPrompt.length,
      );
    }
    _conversationIdFuture = _createNewConversation();
    _refreshStatus();
    _recoverLostImage();
  }

  Future<void> _refreshStatus({bool showProgress = false}) async {
    if (showProgress && mounted) {
      setState(() {
        _checking = true;
        _error = null;
      });
    }
    try {
      final status = await _service.getStatus();
      final shouldClearStaleConversation = _statusUnknown && !status.ready;
      if (shouldClearStaleConversation) {
        await _deleteCachedAttachments([_imagePath, _audioPath]);
      }
      if (!mounted) return;
      if (shouldClearStaleConversation) {
        _conversationIdFuture = _createNewConversation();
        _lastEffectiveMode = null;
        _pendingToolSelection = false;
        _pendingBaziArguments = null;
        _pendingZiweiArguments = null;
        _pendingMeihuaArguments = null;
        _pendingChengguArguments = null;
        _pendingHuangdiSijiArguments = null;
        _pendingXiaoliurenArguments = null;
        _pendingYiJingArguments = null;
        _pendingDosageArguments = null;
        _pendingZiWuArguments = null;
        _pendingDreamArguments = null;
        _pendingHistoryTranscript = null;
        _pendingHistoryUserMessages = const [];
      }
      setState(() {
        _status = status;
        _statusUnknown = false;
        _checking = false;
        if (shouldClearStaleConversation) {
          _messages
            ..clear()
            ..add(const _InterviewMessage(
              text: '已确认原生模型当前未就绪。此前会话已结束，重新加载模型后可开始新对话。',
              isUser: false,
            ));
          _confirmedDraft = null;
          _imagePath = null;
          _audioPath = null;
        }
        _error = null;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _status = null;
        _statusUnknown = true;
        _checking = false;
        _error = error.message ?? '无法确认本地模型状态，请重新检查后继续。';
      });
    } on MissingPluginException {
      if (!mounted) return;
      setState(() {
        _status = null;
        _statusUnknown = true;
        _checking = false;
        _error = '本地 E4B 推理目前仅接入 Android 版本，无法确认模型状态。';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = null;
        _statusUnknown = true;
        _checking = false;
        _error = '读取本地模型状态失败：$error。请重新检查后继续。';
      });
    }
  }

  Future<void> _loadModel() async {
    if (_attachmentBusy ||
        _modelControlBusy ||
        _loading ||
        _importingModel ||
        _statusUnknown ||
        _checking ||
        _status?.installed != true ||
        _status?.ready != false) {
      return;
    }
    setState(() {
      _modelControlBusy = true;
      _loading = true;
      _error = null;
    });
    try {
      final status = await _service.loadModel();
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
      });
      if (!status.ready) {
        setState(() => _error = '模型文件尚未安装，请先将 Gemma 4 E4B 模型放入应用目录。');
      } else {
        await _restorePendingHistory();
      }
    } on PlatformException catch (error) {
      await _refreshStatusAfterLoadFailure(error.message ?? '模型加载失败');
    } catch (error) {
      await _refreshStatusAfterLoadFailure('模型加载失败：$error');
    } finally {
      if (mounted) setState(() => _modelControlBusy = false);
    }
  }

  Future<void> _refreshStatusAfterLoadFailure(String message) async {
    try {
      final status = await _service.getStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _statusUnknown = false;
        _loading = false;
        _error = message;
      });
    } catch (statusError) {
      if (!mounted) return;
      setState(() {
        _status = null;
        _statusUnknown = true;
        _checking = false;
        _loading = false;
        _error = '$message；重新读取本地模型状态失败：$statusError。请重新检查后继续。';
      });
    }
  }

  Future<void> _importModel() async {
    if (_attachmentBusy ||
        _modelControlBusy ||
        _importingModel ||
        _loading ||
        _statusUnknown ||
        _checking ||
        _status == null ||
        _status?.ready == true) {
      return;
    }
    setState(() {
      _modelControlBusy = true;
      _importingModel = true;
      _error = null;
    });
    try {
      final status = await _service.importModel();
      if (!mounted) return;
      setState(() {
        _status = status;
        _importingModel = false;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _importingModel = false;
        _error = error.message ?? '模型导入失败';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _importingModel = false;
        _error = '模型导入失败：$error';
      });
    } finally {
      if (mounted) setState(() => _modelControlBusy = false);
    }
  }

  Future<void> _deleteCachedAttachments(Iterable<String?> paths) async {
    final candidates = paths
        .whereType<String>()
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    if (candidates.isEmpty) return;

    try {
      final tempRoot = p.normalize((await getTemporaryDirectory()).absolute.path);
      for (final rawPath in candidates) {
        final normalizedPath = p.normalize(File(rawPath).absolute.path);
        if (!p.isWithin(tempRoot, normalizedPath)) continue;
        try {
          final file = File(normalizedPath);
          if (await file.exists()) await file.delete();
        } catch (_) {
          // Cache cleanup is best-effort and must not mask the primary action.
        }
      }
    } catch (_) {
      // Temporary-directory lookup may fail during Activity teardown.
    }
  }

  Future<String?> _validateTonguePhoto(String path) async {
    final file = File(path);
    if (!await file.exists()) return '照片文件不存在，请重新拍摄。';
    final fileSize = await file.length();
    if (fileSize <= 0 || fileSize > 15 * 1024 * 1024) {
      return '照片文件无效或超过 15 MB，请重新拍摄。';
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return '照片文件无效，请重新拍摄。';

    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        // Check the encoded source dimensions before decoding. A target decode
        // may upscale small images, which must not let them pass the 480px gate.
        if (math.min(descriptor.width, descriptor.height) < 480) {
          return '照片分辨率不足。请靠近拍摄，确保舌体清晰且短边至少 480 像素。';
        }
        final codec = await descriptor.instantiateCodec(
          targetWidth: math.min(descriptor.width, 1600),
          targetHeight: math.min(descriptor.height, 1600),
        );
        try {
          final frame = await codec.getNextFrame();
          frame.image.dispose();
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
    return null;
  }

  Future<void> _recoverLostImage() async {
    String? ownedPath;
    try {
      final path = await _imagePicker.retrieveLostImagePath();
      if (path == null || path.isEmpty) return;
      if (!mounted) {
        await _deleteCachedAttachments([path]);
        return;
      }
      final validationError = await _validateTonguePhoto(path);
      if (!mounted) {
        await _deleteCachedAttachments([path]);
        return;
      }
      if (validationError != null) {
        await _deleteCachedAttachments([path]);
        if (!mounted) return;
        setState(() => _error = validationError);
        return;
      }
      ownedPath = await _attachmentStore.importFile(path);
      // image_picker may leave an app-cache copy in the shared temp root.
      // The cleanup helper deletes only paths contained by that root; external
      // provider paths are left untouched.
      await _deleteCachedAttachments([path]);
      if (!mounted) {
        await _deleteCachedAttachments([ownedPath]);
        return;
      }
      final previousPath = _imagePath;
      setState(() {
        _imagePath = ownedPath;
        _audioPath = null;
        _error = null;
      });
      if (previousPath != null && previousPath != ownedPath) {
        unawaited(_deleteCachedAttachments([previousPath]));
      }
    } catch (error) {
      if (ownedPath != null) await _deleteCachedAttachments([ownedPath]);
      if (!mounted) return;
      setState(() => _error = '恢复照片失败：$error');
    } finally {
      if (mounted) setState(() => _attachmentBusy = false);
    }
  }

  Future<void> _pickTonguePhoto() async {
    if (_attachmentBusy ||
        _modelControlBusy ||
        _sending ||
        _extracting ||
        _recording ||
        _recordingBusy ||
        _audioPath != null) {
      return;
    }
    final fromGallery = await _showTonguePhotoSourceSheet();
    if (fromGallery == null) return;
    await _captureTonguePhoto(fromGallery: fromGallery);
  }

  Future<bool?> _showTonguePhotoSourceSheet() {
    final scheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      // ColorOS 上默认 bottom sheet 背景可能半透明，显式用不透明 surface 避免
      // 菜单文字与后方对话气泡重叠。
      backgroundColor: scheme.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(sheetContext, false),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(sheetContext, true),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _captureTonguePhoto({required bool fromGallery}) async {
    setState(() {
      _attachmentBusy = true;
      _error = null;
    });

    String? photoPath;
    try {
      photoPath = fromGallery
          ? await _imagePicker.pickGalleryImagePath()
          : await _imagePicker.pickCameraImagePath();
      if (photoPath == null || photoPath.isEmpty) return;
      if (!mounted) {
        await _deleteCachedAttachments([photoPath]);
        return;
      }
      final validationError = await _validateTonguePhoto(photoPath);
      if (!mounted) {
        await _deleteCachedAttachments([photoPath]);
        return;
      }
      if (validationError != null) {
        await _deleteCachedAttachments([photoPath]);
        if (!mounted) return;
        setState(() => _error = validationError);
        return;
      }
      final ownedPath = await _attachmentStore.importFile(photoPath);
      // Remove only the picker-owned cache copy after the AI-owned copy is safe.
      // External gallery/provider paths are outside the app temp root and survive.
      await _deleteCachedAttachments([photoPath]);
      if (!mounted) {
        await _deleteCachedAttachments([ownedPath]);
        return;
      }
      final previousPath = _imagePath;
      setState(() {
        _imagePath = ownedPath;
        _audioPath = null;
        _error = null;
      });
      if (previousPath != null && previousPath != ownedPath) {
        unawaited(_deleteCachedAttachments([previousPath]));
      }
    } on PlatformException catch (error) {
      if (photoPath != null) {
        await _deleteCachedAttachments([photoPath]);
      }
      if (!mounted) return;
      setState(() => _error = error.message ?? '无法打开相机');
    } catch (error) {
      if (photoPath != null) {
        await _deleteCachedAttachments([photoPath]);
      }
      if (!mounted) return;
      setState(() => _error = '照片检查失败：$error');
    } finally {
      if (mounted) setState(() => _attachmentBusy = false);
    }
  }
  Future<void> _startRecording() {
    if (_attachmentBusy ||
        _modelControlBusy ||
        _extracting ||
        _sending ||
        _imagePath != null ||
        _audioPath != null ||
        _recording ||
        _recordingBusy ||
        _recorderMayBeActive) {
      return Future<void>.value();
    }
    setState(() => _recordingBusy = true);
    final operation = _startRecordingInternal();
    _recorderOperation = operation;
    return operation;
  }

  Future<void> _startRecordingInternal() async {
    try {
      if (!await _audioRecorder.hasPermission()) {
        if (!mounted) return;
        setState(() {
          _recordingBusy = false;
          _error = '需要麦克风权限才能录制语音。';
        });
        return;
      }
      final path = await _attachmentStore.createRecordingPath(
        extension: '.wav',
      );
      _activeRecordingPath = path;
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      _recorderMayBeActive = true;
      if (!mounted) {
        final stoppedPath = await _audioRecorder.stop();
        _recorderMayBeActive = false;
        _activeRecordingPath = null;
        await _deleteCachedAttachments([stoppedPath, path]);
        return;
      }
      setState(() {
        _recording = true;
        _recordingBusy = false;
        _audioPath = null;
        _error = null;
      });
      _recordingTimer?.cancel();
      _recordingTimer = Timer(
        const Duration(seconds: 30),
        _stopRecording,
      );
    } on PlatformException catch (error) {
      final failedPath = _activeRecordingPath;
      _activeRecordingPath = null;
      await _deleteCachedAttachments([failedPath]);
      if (!mounted) return;
      setState(() {
        _recordingBusy = false;
        _error = error.message ?? '无法开始录音';
      });
    } catch (error) {
      final failedPath = _activeRecordingPath;
      _activeRecordingPath = null;
      await _deleteCachedAttachments([failedPath]);
      if (!mounted) return;
      setState(() {
        _recordingBusy = false;
        _error = '录音启动失败：$error';
      });
    }
  }

  Future<void> _stopRecording() {
    if (!_recording || _recordingBusy) return Future<void>.value();
    _recordingTimer?.cancel();
    _recordingTimer = null;
    setState(() {
      _recording = false;
      _recordingBusy = true;
    });
    final operation = _stopRecordingInternal();
    _recorderOperation = operation;
    return operation;
  }

  Future<void> _stopRecordingInternal() async {
    String? expectedPath;
    String? stoppedPath;
    try {
      expectedPath = _activeRecordingPath;
      stoppedPath = await _audioRecorder.stop();
      _recorderMayBeActive = false;
      _activeRecordingPath = null;
      if (!mounted) {
        await _deleteCachedAttachments([stoppedPath, expectedPath]);
        return;
      }
      final fileSize = stoppedPath == null
          ? null
          : await _recordingFileInspector.sizeBytes(stoppedPath);
      if (fileSize == null || fileSize <= 0) {
        await _deleteCachedAttachments([stoppedPath, expectedPath]);
        if (!mounted) return;
        setState(() {
          _recordingBusy = false;
          _error = '没有生成有效录音，请重试。';
        });
        return;
      }
      if (fileSize > 15 * 1024 * 1024) {
        await _deleteCachedAttachments([stoppedPath]);
        if (!mounted) return;
        setState(() {
          _recordingBusy = false;
          _error = '录音文件超过 15 MB，请缩短语音后重录。';
        });
        return;
      }
      setState(() {
        _recordingBusy = false;
        _audioPath = stoppedPath;
        _error = null;
      });
    } on PlatformException catch (error) {
      _handleRecordingStopError(
        error.message ?? error.code,
        expectedPath: expectedPath,
        stoppedPath: stoppedPath,
      );
    } catch (error) {
      _handleRecordingStopError(
        error.toString(),
        expectedPath: expectedPath,
        stoppedPath: stoppedPath,
      );
    }
  }

  void _handleRecordingStopError(
    String details, {
    required String? expectedPath,
    required String? stoppedPath,
  }) {
    final recorderStillActive = _recorderMayBeActive;
    if (!recorderStillActive) {
      // Recorder.stop() already succeeded; this is a post-stop file error.
      // Do not show a stop-retry control for a recorder that is no longer active.
      unawaited(_deleteCachedAttachments([stoppedPath, expectedPath]));
    }
    if (!mounted) return;
    setState(() {
      _recording = recorderStillActive;
      _recordingBusy = false;
      _error = recorderStillActive
          ? '录音停止失败，录音可能仍在继续。请再次点击“停止录音”重试。（$details）'
          : '录音已停止，但读取录音文件失败，未添加为附件。请重新录制。（$details）';
    });
  }
  void _discardAttachment() {
    if (_attachmentBusy || _modelControlBusy || _sending) return;
    final paths = <String?>[_imagePath, _audioPath];
    setState(() {
      _imagePath = null;
      _audioPath = null;
      _error = null;
    });
    unawaited(_deleteCachedAttachments(paths));
  }

  Future<LocalAiModelStatus?> _readNativeStatus() async {
    try {
      return await _service.getStatus();
    } catch (_) {
      return null;
    }
  }


  Future<AssistantKnowledgeContextResult> _retrieveKnowledgeWithTrace(
    String query, {
    required AiTraceContext traceContext,
    bool includeMedicalCases = true,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final result =
          await AssistantKnowledgeContextBuilder.buildWithSourcesAsync(
        query,
        includeMedicalCases: includeMedicalCases,
      );
      stopwatch.stop();
      final failed =
          result.status == AssistantKnowledgeRetrievalStatus.failed;
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.retrieval,
        status: failed ? AiTraceStatus.failed : AiTraceStatus.succeeded,
        durationMs: stopwatch.elapsedMilliseconds,
        sourceIds: result.sourceIds,
        errorCode: failed
            ? 'RETRIEVAL_FAILED'
            : result.status == AssistantKnowledgeRetrievalStatus.partial
                ? 'RETRIEVAL_PARTIAL'
                : null,
      );
      return result;
    } catch (_) {
      stopwatch.stop();
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.retrieval,
        status: AiTraceStatus.failed,
        durationMs: stopwatch.elapsedMilliseconds,
        errorCode: 'RETRIEVAL_FAILED',
      );
      rethrow;
    }
  }

  Future<_AssistantTurnResponse> _sendTextWithKnowledgeContext(
    String text, {
    required AssistantMode mode,
    required AiTraceContext traceContext,
    String? retrievalQuery,
  }) async {
    final traceId = traceContext.traceId;
    Future<String> sendWithContext(String context) async {
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.contextAssembly,
        status: AiTraceStatus.succeeded,
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.modelInput,
        status: AiTraceStatus.succeeded,
      );
      return traceId == null
          ? _service.sendMessageWithContext(text, context: context)
          : _service.sendMessageWithContextAndTrace(
              text,
              context: context,
              traceId: traceId,
            );
    }
    switch (mode) {
      case AssistantMode.automatic:
        final query = _knowledgeQueryForCurrentTurn(text);
        final knowledge =
            await _retrieveKnowledgeWithTrace(query, traceContext: traceContext);
        // 无命中且无失败时，不注入知识检索框架与角色 context——
        // 否则"本轮知识检索状态：NO_RESULTS"会把寒暄(你好/hello)或一般聊天
        // 误导成知识检索问题，模型答非所问。systemInstruction 已足够应对一般对话。
        if (knowledge.status == AssistantKnowledgeRetrievalStatus.noResults &&
            knowledge.failureMessage == null) {
          await _traceRecorder.record(
            traceContext,
            stage: AiTraceStage.contextAssembly,
            status: AiTraceStatus.notApplicable,
          );
          await _traceRecorder.record(
            traceContext,
            stage: AiTraceStage.modelInput,
            status: AiTraceStatus.succeeded,
          );
          final reply = traceId == null
              ? await _service.sendMessage(text)
              : await _service.sendMessageWithTrace(text, traceId: traceId);
          return _AssistantTurnResponse(
            text: reply,
            sourceIds: knowledge.sourceIds,
            knowledgeStatus: knowledge.statusLabel,
          );
        }
        final context = StringBuffer(
          '当前角色：通用助手。\n${AssistantMode.automatic.promptHint}\n'
          '先正常回答用户的一般问题；只有识别到明确的个人症状、知识学习或工具执行意图时，'
          '才切换对应领域。不要把普通寒暄或一般聊天强行归入中医学习。\n',
        );
        context.writeln('本轮知识检索状态：${knowledge.statusLabel}。');
        if (knowledge.failureMessage != null) {
          context.writeln('知识检索失败：${knowledge.failureMessage}');
        }
        if (knowledge.text.isNotEmpty) {
          context
            ..writeln('App 本地知识库相关检索结果（仅作有来源的参考）：')
            ..write(knowledge.text);
        }
        final reply = await sendWithContext(context.toString());
        return _AssistantTurnResponse(
          text: reply + knowledge.citationFooter,
          sourceIds: knowledge.sourceIds,
          knowledgeStatus: knowledge.statusLabel,
        );
      case AssistantMode.consultation:
        // Consultation uses the same bundled classical-text and TCM retrieval
        // as learning, but excludes unverified case records to avoid case-based
        // diagnostic anchoring. Retrieved text remains reference-only.
        final query = _knowledgeQueryForCurrentTurn(text);
        final knowledge =
            await _retrieveKnowledgeWithTrace(
          query,
          traceContext: traceContext,
          includeMedicalCases: false,
        );
        final knowledgeContext = switch (knowledge.status) {
          AssistantKnowledgeRetrievalStatus.noResults => 'App 本地知识库本轮未命中可引用条目（NO_RESULTS）。',
          AssistantKnowledgeRetrievalStatus.failed => 'App 本地知识库检索失败（FAILED）：${knowledge.failureMessage ?? 'MISSING'}。不得将失败说成无命中。',
          AssistantKnowledgeRetrievalStatus.partial => 'App 本地知识库部分命中；仅引用已反查成功的来源（PARTIAL）：\n${knowledge.text}',
          AssistantKnowledgeRetrievalStatus.retrieved => 'App 本地知识库检索结果（仅供知识解释，不是个体诊断依据）：\n${knowledge.text}',
        };
        final reply = await sendWithContext(
          '当前角色：问诊助手。\n${AssistantMode.consultation.promptHint}\n'
              '先澄清症状与时间线，不把模型整理内容当成已确认事实。'
              '只有用户明确启动结构化辨证时，才通过 App 的 DiagnosticEngine 工具执行规则问诊。'
              '若历史对话已经包含该引擎的结构化结果，用户追问时应解释和归纳已有结果，并结合本轮检索到的知识条目说明依据；'
              '必须区分规则输出、知识来源与 AI 解释，不得自行新增或改写证型/规则结论，也不得给出个体处方或剂量。\n'
              '$knowledgeContext',
        );
        return _AssistantTurnResponse(
          text: reply + knowledge.citationFooter,
          sourceIds: knowledge.sourceIds,
          knowledgeStatus: knowledge.statusLabel,
        );
      case AssistantMode.learning:
        final query = _knowledgeQueryForCurrentTurn(text);
        final knowledge =
            await _retrieveKnowledgeWithTrace(query, traceContext: traceContext);
        final context = '当前角色：学习助手。\n${AssistantMode.learning.promptHint}\n'
            '本轮知识检索状态：${knowledge.statusLabel}。\n'
            '${knowledge.failureMessage == null ? '' : '检索失败：${knowledge.failureMessage}\n'}'
            '${knowledge.text.isEmpty ? '未返回可引用条目；不得编造原文或出处。' : knowledge.text}';
        final reply = await sendWithContext(context);
        return _AssistantTurnResponse(
          text: reply + knowledge.citationFooter,
          sourceIds: knowledge.sourceIds,
          knowledgeStatus: knowledge.statusLabel,
        );
      case AssistantMode.tools:
        final availableTools = AssistantToolRouter.quickActions(AssistantMode.tools)
            .map((tool) => tool.title)
            .join('、');
        final requestedQuery = retrievalQuery?.trim().isNotEmpty == true
            ? retrievalQuery!.trim()
            : text;
        final query = _knowledgeQueryForCurrentTurn(requestedQuery);
        final knowledge = AssistantKnowledgeContextBuilder.shouldRetrieveForQuery(query)
            ? await _retrieveKnowledgeWithTrace(
                query,
                traceContext: traceContext,
                // Tool-result explanation uses the bundled formula/herb/classic/
                // acupoint corpus. Do not load unrelated case records (some
                // still have MISSING bibliographic locators) for unit or
                // calendrical tool explanations.
                includeMedicalCases: false,
              )
            : null;
        final knowledgeContext = switch (knowledge?.status) {
          null => '',
          AssistantKnowledgeRetrievalStatus.noResults =>
            '本轮本地知识库未命中可引用条目（NO_RESULTS）。',
          AssistantKnowledgeRetrievalStatus.failed =>
            '本轮本地知识库检索失败（FAILED）：${knowledge?.failureMessage ?? 'MISSING'}。不得将失败说成无命中。',
          AssistantKnowledgeRetrievalStatus.partial =>
            '本轮本地知识库部分命中；只使用已返回的资料（PARTIAL）：\n${knowledge?.text}',
          AssistantKnowledgeRetrievalStatus.retrieved =>
            '本轮本地知识库检索结果：\n${knowledge?.text}',
        };
        final context = '当前角色：工具助手。\n${AssistantMode.tools.promptHint}\n'
            '当前 App 已注册工具：$availableTools。'
            '新动作优先通过 App 已有 Headless Capability 在当前对话内执行；只有该能力仍为 Page-only 且确需页面交互时，才建议打开工具页。'
            '对已经完成的工具结果追问，应复用当前会话中的已验证结果与本轮知识检索，不重复执行、不把用户送到工具页面。\n'
            '$knowledgeContext';
        final reply = await sendWithContext(context);
        return _AssistantTurnResponse(
          text: reply + (knowledge?.citationFooter ?? ''),
          sourceIds: knowledge?.sourceIds ?? const [],
          knowledgeStatus: knowledge?.statusLabel,
        );
      case AssistantMode.metaphysics:
        final availableTools = AssistantToolRouter.quickActions(AssistantMode.metaphysics)
            .map((tool) => tool.title)
            .join('、');
        final context = '当前角色：玄学大师。\n${AssistantMode.metaphysics.promptHint}\n'
            '当前 App 已注册工具：$availableTools。'
            '八字、紫微等排盘结果必须由 App 工具生成；结果返回后，应基于完整回传字段作总结、关联解释和分层归纳。'
            '明确区分 App 确定性计算、App 规则模板与 AI 解释，不得自行重排、篡改计算字段或补造 MISSING。';
        return _AssistantTurnResponse(
          text: await sendWithContext(context),
        );
    }
  }


  Future<int?> _createNewConversation() async {
    try {
      final id = await _conversationStore.createAssistantConversation(
        mode: 'unified',
      );
      return id;
    } catch (error, stack) {
      debugPrint('[AssistantHistory] 无法创建会话：$error\n$stack');
      return null;
    }
  }

  Future<void> _persistTcmInterviewTaskState(
    TcmInterviewTaskState state,
  ) {
    // Capture the conversation future at callback time. History navigation may
    // switch the active conversation while an earlier SQLite write is queued.
    final targetConversation = _conversationIdFuture;
    _taskStateWrite = _taskStateWrite.catchError((Object error) {
      debugPrint('[TcmInterviewTask] 上一次状态保存失败，继续后续写入：$error');
    }).then((_) async {
      final id = await targetConversation;
      if (id == null) return;
      await _conversationStore.saveTcmInterviewTaskState(
        conversationId: id,
        state: state,
      );
    });
    return _taskStateWrite;
  }

  Future<bool> _persistSuccessfulTurn({
    required String userText,
    required String assistantText,
    AssistantMode? mode,
    String? attachmentType,
    String? toolId,
    String? toolStatus,
    bool expectsToolSelection = false,
    List<String> sourceIds = const [],
    Map<String, String> toolArguments = const {},
    String? knowledgeStatus,
    String? traceId,
  }) async {
    try {
      final id = await _conversationIdFuture;
      if (id == null) return false;
      final activeMode = mode ?? _assistantMode;
      final replayable = userText.trim().isNotEmpty;
      final metadata = AssistantMessageMetadata(
        mode: activeMode.name,
        selectedMode: _assistantMode.name,
        replayable: replayable,
        attachmentType: attachmentType,
        toolArguments: toolArguments,
        traceId: traceId,
      ).encode();
      final storedUserText = attachmentType == null
          ? userText
          : replayable
              ? '$userText（另附$attachmentType；原始附件未持久化）'
              : '已附加$attachmentType（原始附件未持久化）';
      await _conversationStore.saveAssistantTurn(
        conversationId: id,
        userContent: storedUserText.trim().isEmpty ? null : storedUserText,
        userMetadata: metadata,
        assistantContent: assistantText,
        assistantMetadata: AssistantMessageMetadata(
          mode: activeMode.name,
          selectedMode: _assistantMode.name,
          toolId: toolId,
          toolStatus: toolStatus,
          toolChoicePending: expectsToolSelection,
          sourceIds: sourceIds,
          toolArguments: toolArguments,
          knowledgeStatus: knowledgeStatus,
          traceId: traceId,
        ).encode(),
      );
      return true;
    } catch (error, stack) {
      debugPrint('[AssistantHistory] 保存对话失败：$error\\n$stack');
      if (mounted) {
        setState(() {
          _error = '本轮回复已生成，但保存到历史记录失败。请先复制重要内容，再重试或继续。';
        });
      }
      return false;
    }
  }

  Future<void> _startInlineTcmInterview({
    required String initialUserMessage,
    String? userContext,
    AiTraceContext? traceContext,
  }) async {
    final activeTraceContext = traceContext ??
        _traceRecorder.start(
          stage: AiTraceStage.input,
          route: 'structured_diagnosis',
          mode: AssistantMode.consultation.name,
        );
    if (traceContext == null) {
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.succeeded,
        route: 'structured_diagnosis',
        mode: AssistantMode.consultation.name,
        toolId: 'structured_diagnosis',
      );
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.dispatch,
        status: AiTraceStatus.succeeded,
        route: 'structured_diagnosis',
        mode: AssistantMode.consultation.name,
        toolId: 'structured_diagnosis',
      );
    }
    if (_structuredDiagnosisBusy) {
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.businessExecution,
        status: AiTraceStatus.notStarted,
        toolId: 'structured_diagnosis',
        errorCode: 'STRUCTURED_DIAGNOSIS_BUSY',
      );
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.succeeded,
        toolId: 'structured_diagnosis',
      );
      return;
    }
    if (_tcmInterviewController?.canAnswer == true) {
      setState(() {
        _error = '当前对话已有一项未完成的规则问诊。请先回答下方问题，或从历史记录恢复该任务。';
      });
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.businessExecution,
        status: AiTraceStatus.notStarted,
        toolId: 'structured_diagnosis',
        errorCode: 'STRUCTURED_TASK_ALREADY_ACTIVE',
      );
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.succeeded,
        toolId: 'structured_diagnosis',
      );
      return;
    }

    final controller = TcmInterviewConversationController(
      defaultGender: SettingsRepository.instance.defaultGender,
    );
    _tcmInterviewController = controller;
    setState(() {
      _structuredDiagnosisBusy = true;
      _lastEffectiveMode = AssistantMode.consultation;
      _pendingToolSelection = false;
      _pendingBaziArguments = null;
      _pendingZiweiArguments = null;
      _pendingGuanshaArguments = null;
      _pendingMeihuaArguments = null;
      _pendingChengguArguments = null;
      _pendingHuangdiSijiArguments = null;
      _pendingXiaoliurenArguments = null;
      _error = null;
    });
    final before = controller.messages.length;
    final executionWatch = Stopwatch()..start();
    try {
      controller.start(
        initialUserMessage: initialUserMessage,
        userContext: userContext,
      );
      executionWatch.stop();
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.businessExecution,
        status: AiTraceStatus.succeeded,
        durationMs: executionWatch.elapsedMilliseconds,
        toolId: 'structured_diagnosis',
      );
    } catch (error) {
      executionWatch.stop();
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.businessExecution,
        status: AiTraceStatus.failed,
        durationMs: executionWatch.elapsedMilliseconds,
        toolId: 'structured_diagnosis',
        errorCode: 'STRUCTURED_DIAGNOSIS_START_FAILED',
      );
      if (mounted) {
        setState(() {
          _structuredDiagnosisBusy = false;
          _error = '无法启动规则问诊：$error';
        });
      }
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.succeeded,
        toolId: 'structured_diagnosis',
      );
      return;
    }

    _inputController.clear();
    try {
      final persistenceResult = await _appendTcmInterviewMessages(
        before,
        traceContext: activeTraceContext,
      );
      final messagePersistenceStatus =
          !persistenceResult.transcriptMessagesApplicable
              ? AiTraceStatus.notApplicable
              : persistenceResult.transcriptMessagesPersisted
                  ? AiTraceStatus.succeeded
                  : AiTraceStatus.failed;
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.persistence,
        status: messagePersistenceStatus,
        toolId: 'structured_diagnosis',
        errorCode: messagePersistenceStatus == AiTraceStatus.failed
            ? 'PERSISTENCE_FAILED'
            : null,
      );
    } catch (error) {
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.persistence,
        status: AiTraceStatus.failed,
        toolId: 'structured_diagnosis',
        errorCode: 'PERSISTENCE_FAILED',
      );
      if (mounted) {
        setState(() => _error = '规则问诊已启动，但进度保存失败：$error');
      }
    }
    if (mounted) {
      setState(() {
        _confirmedDraft = null;
        _structuredDiagnosisBusy = false;
      });
    }
    await _traceRecorder.record(
      activeTraceContext,
      stage: AiTraceStage.finalRender,
      status: AiTraceStatus.succeeded,
      toolId: 'structured_diagnosis',
    );
  }

  String _diagnosisInterpretationPrompt(DiagnosisResult result) =>
      '请总结并解释刚才 App DiagnosticEngine 已完成的结构化辨证结果。'
      '本次结果字段：六经 ${result.displayMeridian}；'
      '${result.isCombined ? '合病 ${result.meridian}与${result.combinedMeridian}；' : ''}'
      '证型 ${result.pattern}；方剂 ${result.formula.isEmpty ? 'MISSING' : result.formula}。'
      '请说明现有规则结果表达了什么、各字段之间的关系，并结合本轮本地知识检索来源解释依据；'
      '知识库内容只用于解释已有规则，不得据此新增个体诊断结论。'
      '只解释 App 已返回的结果，不重新辨证，不增加或修改规则结论，不补造缺失字段。'
      '不要生成个体处方、药物或剂量建议；原结果中的处方字段只可按原文引用，不得增删改。';

  _InterviewMessage _diagnosisActionMessage(
    String text,
    DiagnosisResult result,
  ) {
    return _InterviewMessage(
      text: text,
      isUser: false,
      actionLabel: 'AI解读辨证结果',
      sourceIds: _diagnosticEngineSourceIds,
      onAction: () => unawaited(_requestAssistantResultInterpretation(
        prompt: _diagnosisInterpretationPrompt(result),
        mode: AssistantMode.consultation,
        toolId: 'structured_diagnosis',
        toolStatus: 'SUCCEEDED',
        sourceIds: _diagnosticEngineSourceIds,
      )),
      diagnosisResult: result,
      onBookmark: () => _bookmarkDiagnosisResult(result),
      onShare: () => _shareDiagnosisResult(result),
      onCopyPrescription: result.prescription == null
          ? null
          : () => _copyDiagnosisPrescription(result.prescription!),
    );
  }

  Future<void> _bookmarkDiagnosisResult(DiagnosisResult result) async {
    final formula = FormulaRepository.getByName(result.formula);
    final content = [
      '六经：${result.displayMeridian}病',
      if (result.isCombined)
        '合病：${result.meridian}与${result.combinedMeridian}同病',
      '证型：${result.pattern}',
      if (result.formula.isNotEmpty) '方剂：${result.formula}',
      if (formula != null && formula.components.isNotEmpty)
        '组成：${formula.componentsText}',
      result.patternDetail,
      result.explanation,
      if (result.pulseTongueContradiction != null)
        '脉舌交叉核验：${result.pulseTongueContradiction}',
      if (result.recommendConsult || result.formula.isEmpty)
        '状态：证据不足，不自动推荐方剂；请由执业中医师面诊核实。',
    ].where((line) => line.trim().isNotEmpty).join('\n');
    try {
      await (widget.bookmarkWriter ?? DatabaseHelper.instance.insertBookmark)(Bookmark(
        title: '${result.displayMeridian}病 - ${result.pattern}',
        content: content,
        category: '辨证结果',
        source: 'chat_diagnosis',
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已添加到收藏')),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = '收藏辨证结果失败：$error');
    }
  }

  void _shareDiagnosisResult(DiagnosisResult result) {
    final formula = FormulaRepository.getByName(result.formula);
    final lines = <String>[
      '【汉唐中医辨证结果】',
      '六经：${result.displayMeridian}病',
      if (result.isCombined)
        '合病：${result.meridian}与${result.combinedMeridian}同病',
      '证型：${result.pattern}',
      if (result.formula.isNotEmpty) '方剂：${result.formula}',
      if (formula != null && formula.components.isNotEmpty)
        '组成：${formula.componentsText}',
      if (result.tongueCoating != null ||
          result.tongueShape != null ||
          result.pulseType != null)
        '舌脉：${[
          if (result.tongueCoating != null) '苔${result.tongueCoating}',
          if (result.tongueShape != null) '形${result.tongueShape}',
          if (result.pulseType != null) '脉${result.pulseType}',
          if (result.pulseTypeSecondary != null) '兼脉${result.pulseTypeSecondary}',
        ].join(' ')}',
      result.patternDetail,
      result.explanation,
      if (result.careAdvice != null) ...[
        '调护建议：',
        for (final entry in result.careAdvice!.entries)
          '【${entry.key}】${entry.value.join('、')}',
      ],
      if (result.prescription != null) result.prescription!.toCopyText(),
      if (result.recommendConsult || result.formula.isEmpty)
        '证据不足，不自动推荐方剂；请由执业中医师结合四诊面诊核实。',
      '—— 来自「汉唐中医」App',
    ];
    final text = lines.where((line) => line.trim().isNotEmpty).join('\n\n');
    final testShare = widget.shareDiagnosisText;
    if (testShare != null) {
      testShare(text);
    } else {
      Share.share(text);
    }
  }

  Future<void> _copyDiagnosisPrescription(FormulaPrescription prescription) async {
    final text = prescription.toCopyText();
    await (widget.copyPrescriptionText?.call(text) ??
        Clipboard.setData(ClipboardData(text: text)));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('处方已复制到剪贴板')),
      );
    }
  }

  Future<void> _persistDiagnosisHistoryOnce(
    TcmInterviewConversationController controller,
  ) async {
    final result = controller.completedDiagnosis;
    if (result == null ||
        widget.conversationStore != null ||
        !_persistedDiagnosisTaskIds.add(controller.taskId)) {
      return;
    }
    try {
      await DatabaseHelper.instance.saveDiagnosisHistory(
        result.displayMeridian,
        result.pattern,
        result.formula,
        result.confidence,
        jsonEncode(DiagnosisResultCodec.toJson(result)),
      );
    } catch (error) {
      debugPrint('[TcmInterviewTask] 结构化诊断历史索引写入失败：$error');
      if (mounted) {
        setState(() {
          _error = '结构化诊断结果已保存在助手会话中，但旧版诊断历史索引写入失败：$error';
        });
      }
    }
  }

  Future<_TcmInterviewMessagePersistenceResult>
      _appendTcmInterviewMessages(
    int startIndex, {
    AiTraceContext? traceContext,
  }) async {
    final controller = _tcmInterviewController;
    if (controller == null) {
      return const _TcmInterviewMessagePersistenceResult.notApplicable();
    }
    final traceId = traceContext?.traceId;
    final added = controller.messages.skip(startIndex).toList(growable: false);
    if (added.isEmpty) {
      final conversationId = await _conversationIdFuture;
      final persistedStateWatch = Stopwatch()..start();
      var taskStatePersisted = false;
      String? taskStateErrorCode;
      try {
        await _persistTcmInterviewTaskState(controller.createTaskState());
        taskStatePersisted = conversationId != null;
        if (!taskStatePersisted) {
          taskStateErrorCode = 'CONVERSATION_UNAVAILABLE';
        }
      } catch (error) {
        taskStateErrorCode = 'TASK_STATE_PERSISTENCE_FAILED';
        debugPrint('[TcmInterviewTask] 问诊快照保存失败：$error');
        if (mounted) {
          setState(() {
            _error = '本次没有新增问诊消息，但问诊进度快照保存失败；请核实后再继续。';
          });
        }
      } finally {
        persistedStateWatch.stop();
      }
      if (traceContext != null) {
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.persistedState,
          status: taskStatePersisted
              ? AiTraceStatus.succeeded
              : AiTraceStatus.failed,
          durationMs: persistedStateWatch.elapsedMilliseconds,
          toolId: 'structured_diagnosis',
          errorCode: taskStateErrorCode,
        );
      }
      return const _TcmInterviewMessagePersistenceResult.notApplicable();
    }

    final taskState = controller.createTaskState();
    setState(() {
      for (final entry in added) {
        final isPendingPrompt = !entry.isUser &&
            controller.canAnswer &&
            entry.text == controller.pendingPromptText;
        if (entry.isResult && controller.completedDiagnosis != null) {
          _messages.add(
            _diagnosisActionMessage(entry.text, controller.completedDiagnosis!),
          );
        } else {
          _messages.add(_InterviewMessage(
            text: entry.text,
            isUser: entry.isUser,
            options: isPendingPrompt ? controller.pendingOptions : const [],
            onOptionSelected:
                isPendingPrompt ? _handleTcmInterviewOption : null,
          ));
        }
      }
      _error = null;
    });

    final conversationId = await _conversationIdFuture;
    var messagesPersisted = conversationId != null;
    if (conversationId != null) {
      final messageBatch = added
          .map((entry) => AssistantMessageDraft(
                role: entry.isUser ? 'user' : 'assistant',
                content: entry.text,
                metadata: AssistantMessageMetadata(
                  mode: 'consultation',
                  selectedMode: _assistantMode.name,
                  tcmTaskId: controller.taskId,
                  replayable: entry.isUser,
                  traceId: traceId,
                ).encode(),
              ))
          .toList(growable: false);
      try {
        await _conversationStore.saveAssistantMessagesAtomically(
          conversationId: conversationId,
          messages: messageBatch,
        );
      } catch (error, stack) {
        messagesPersisted = false;
        debugPrint('[TcmInterviewTask] 问诊消息批量保存失败：$error\\n$stack');
      }
    }

    final persistedStateWatch = Stopwatch()..start();
    var taskStatePersisted = false;
    String? taskStateErrorCode;
    try {
      await _persistTcmInterviewTaskState(taskState);
      taskStatePersisted = conversationId != null;
      if (!taskStatePersisted) {
        taskStateErrorCode = 'CONVERSATION_UNAVAILABLE';
      }
    } catch (error) {
      taskStateErrorCode = 'TASK_STATE_PERSISTENCE_FAILED';
      debugPrint('[TcmInterviewTask] 问诊快照保存失败：$error');
    } finally {
      persistedStateWatch.stop();
    }
    if (traceContext != null) {
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.persistedState,
        status: taskStatePersisted
            ? AiTraceStatus.succeeded
            : AiTraceStatus.failed,
        durationMs: persistedStateWatch.elapsedMilliseconds,
        toolId: 'structured_diagnosis',
        errorCode: taskStateErrorCode,
      );
    }

    if (!messagesPersisted && mounted) {
      setState(() {
        _error = '规则问诊消息未能完整保存，当前页面仍保留内容；历史记录可能不完整，请核实后再继续。';
      });
    }
    if (!taskStatePersisted && mounted) {
      setState(() {
        _error = messagesPersisted
            ? '问诊消息已保存，但进度快照保存失败；重新进入历史记录时可能无法恢复到当前步骤，请核实后再继续。'
            : '问诊消息与进度快照均未能完整保存；当前页面仍保留内容，历史记录可能不完整，请核实后再继续。';
      });
    }

    if (taskStatePersisted) {
      await _persistDiagnosisHistoryOnce(controller);
      final completedDiagnosis = controller.completedDiagnosis;
      if (completedDiagnosis?.prescription != null &&
          SettingsRepository.instance.autoCopyPrescription) {
        try {
          await _copyDiagnosisPrescription(completedDiagnosis!.prescription!);
        } catch (error) {
          if (mounted) {
            setState(() => _error = '问诊记录已保存，但自动复制处方失败：$error');
          }
        }
      }
    }

    var modelContextRestored = false;
    if (controller.isCompleted) {
      try {
        await _restoreVisibleConversationToModel();
        modelContextRestored = true;
      } catch (error) {
        if (mounted) {
          setState(() {
            _error = '规则辨证结果已保存，但同步到本地模型上下文失败：$error';
          });
        }
      }
    }
    _scrollToBottom();
    if (traceContext != null) {
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.presentation,
        status: mounted ? AiTraceStatus.succeeded : AiTraceStatus.notApplicable,
        toolId: 'structured_diagnosis',
      );
    }

    final completedDiagnosis = controller.completedDiagnosis;
    final hasNewDiagnosisResult = added.any((entry) => entry.isResult);
    if (mounted &&
        modelContextRestored &&
        messagesPersisted &&
        taskStatePersisted &&
        controller.isCompleted &&
        hasNewDiagnosisResult &&
        completedDiagnosis != null &&
        _status?.ready == true &&
        !_statusUnknown &&
        _diagnosticEngineSourceIds.isNotEmpty) {
      // The deterministic result and completed task snapshot are durable, and
      // the exact visible transcript has been restored before E4B can interpret.
      await _requestAssistantResultInterpretation(
        prompt: _diagnosisInterpretationPrompt(completedDiagnosis),
        mode: AssistantMode.consultation,
        toolId: 'structured_diagnosis',
        toolStatus: 'SUCCEEDED',
        sourceIds: _diagnosticEngineSourceIds,
        showPromptInTimeline: false,
        allowWhileSending: true,
        restoreVisibleConversation: false,
      );
    }

    return _TcmInterviewMessagePersistenceResult(
      transcriptMessagesApplicable: true,
      transcriptMessagesPersisted: messagesPersisted,
    );
  }

  Future<void> _handleTcmInterviewOption(
    String option, {
    AiTraceContext? traceContext,
  }) async {
    final controller = _tcmInterviewController;
    if (controller == null || !controller.canAnswer) return;
    final activeTraceContext = traceContext ??
        _traceRecorder.start(
          stage: AiTraceStage.input,
          route: 'structured_interview_option',
          mode: AssistantMode.consultation.name,
        );
    if (await _blockIfRedFlagPreflightDoesNotClear(
      source: RedFlagInputSource.structuredInterview,
      text: option,
      traceContext: activeTraceContext,
      route: 'structured_interview_option',
    )) {
      return;
    }
    if (traceContext == null) {
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.succeeded,
        route: 'structured_interview_option',
        mode: AssistantMode.consultation.name,
        toolId: 'structured_diagnosis',
      );
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.dispatch,
        status: AiTraceStatus.succeeded,
        route: 'structured_interview_option',
        mode: AssistantMode.consultation.name,
        toolId: 'structured_diagnosis',
      );
    }
    if (controller.pendingPromptId == 'tongue_pulse' &&
        option == '选择舌诊脉诊') {
      await _showUnifiedTonguePulseDialog(
        traceContext: activeTraceContext,
      );
      return;
    }

    final before = controller.messages.length;
    final executionWatch = Stopwatch()..start();
    try {
      controller.answerOption(option);
      executionWatch.stop();
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.businessExecution,
        status: AiTraceStatus.succeeded,
        durationMs: executionWatch.elapsedMilliseconds,
        toolId: 'structured_diagnosis',
      );
    } catch (error) {
      executionWatch.stop();
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.businessExecution,
        status: AiTraceStatus.failed,
        durationMs: executionWatch.elapsedMilliseconds,
        toolId: 'structured_diagnosis',
        errorCode: 'STRUCTURED_INTERVIEW_FAILED',
      );
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.succeeded,
        toolId: 'structured_diagnosis',
      );
      if (mounted) setState(() => _error = '问诊选项未能提交：$error');
      return;
    }

    try {
      final persistenceResult = await _appendTcmInterviewMessages(
        before,
        traceContext: activeTraceContext,
      );
      final messagePersistenceStatus =
          !persistenceResult.transcriptMessagesApplicable
              ? AiTraceStatus.notApplicable
              : persistenceResult.transcriptMessagesPersisted
                  ? AiTraceStatus.succeeded
                  : AiTraceStatus.failed;
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.persistence,
        status: messagePersistenceStatus,
        toolId: 'structured_diagnosis',
        errorCode: messagePersistenceStatus == AiTraceStatus.failed
            ? 'PERSISTENCE_FAILED'
            : null,
      );
    } catch (error) {
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.persistence,
        status: AiTraceStatus.failed,
        toolId: 'structured_diagnosis',
        errorCode: 'PERSISTENCE_FAILED',
      );
      if (mounted) setState(() => _error = '问诊进度保存失败：$error');
    }
    await _traceRecorder.record(
      activeTraceContext,
      stage: AiTraceStage.finalRender,
      status: AiTraceStatus.succeeded,
      toolId: 'structured_diagnosis',
    );
  }

  String _zangFuEvidenceStateLabel(ZangFuEvidenceAnswerState state) =>
      switch (state) {
        ZangFuEvidenceAnswerState.answered => '已回答',
        ZangFuEvidenceAnswerState.explicitNormal => '明确正常/否定',
        ZangFuEvidenceAnswerState.unknown => '未知',
        ZangFuEvidenceAnswerState.unanswered => '未作答',
        ZangFuEvidenceAnswerState.invalid => '无效选项',
      };

  Future<void> _showZangFuEvidenceDialog() async {
    final controller = _tcmInterviewController;
    if (controller == null) return;

    final assessment = controller.currentZangFuEvidence;
    final visibleRecords = assessment.records
        .where((record) =>
            record.state != ZangFuEvidenceAnswerState.unanswered)
        .toList(growable: false);
    final unansweredCount = assessment.records
        .where((record) =>
            record.state == ZangFuEvidenceAnswerState.unanswered)
        .length;

    await showFoldAwareDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('脏腑证据（只读）'),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.65,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '仅展示本次问诊原始回答与来源；不进行脏腑归属、诊断或方剂计算。',
                ),
                const SizedBox(height: 12),
                if (visibleRecords.isEmpty)
                  const Text('尚无已记录的问诊证据。'),
                for (final record in visibleRecords) ...[
                  Text(
                    record.questionLabel,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    record.answerText ??
                        _zangFuEvidenceStateLabel(record.state),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '状态：${_zangFuEvidenceStateLabel(record.state)} · 来源：${record.sourceId}',
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                  const Divider(height: 16),
                ],
                if (assessment.unclassifiedAdditionalEvidence.isNotEmpty)
                  Text(
                    '未分类扩展线索：${assessment.unclassifiedAdditionalEvidence.join('、')}',
                  ),
                if (unansweredCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('尚未回答问项：$unansweredCount 项'),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    '脏腑归属：${assessment.organMappingStatus}。当前没有经过逐条核验的问项—脏腑映射，不输出脏腑诊断。',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _showUnifiedTonguePulseDialog({
    AiTraceContext? traceContext,
  }) async {
    final activeTraceContext = traceContext ??
        _traceRecorder.start(
          stage: AiTraceStage.input,
          route: 'structured_interview_tongue_pulse',
          mode: AssistantMode.consultation.name,
        );
    if (traceContext == null) {
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.succeeded,
        route: 'structured_interview_tongue_pulse',
        mode: AssistantMode.consultation.name,
        toolId: 'structured_diagnosis',
      );
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.dispatch,
        status: AiTraceStatus.succeeded,
        route: 'structured_interview_tongue_pulse',
        mode: AssistantMode.consultation.name,
        toolId: 'structured_diagnosis',
      );
    }
    final controller = _tcmInterviewController;
    if (controller == null || controller.pendingPromptId != 'tongue_pulse') {
      return;
    }
    String? tongueCoating;
    String? tongueShape;
    String? primaryPulse;
    String? secondaryPulse;
    final confirmed = await showFoldAwareDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('舌诊脉诊'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('舌苔', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: controller.tongueCoatingOptions.map((option) =>
                    FilterChip(
                      label: Text(option),
                      selected: tongueCoating == option,
                      onSelected: (selected) => setDialogState(
                        () => tongueCoating = selected ? option : null,
                      ),
                    ),
                  ).toList(),
                ),
                const SizedBox(height: 12),
                const Text('舌形', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: controller.tongueShapeOptions.map((option) =>
                    FilterChip(
                      label: Text(option),
                      selected: tongueShape == option,
                      onSelected: (selected) => setDialogState(
                        () => tongueShape = selected ? option : null,
                      ),
                    ),
                  ).toList(),
                ),
                const SizedBox(height: 12),
                const Text('主脉象', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: controller.pulseOptions.map((option) =>
                    FilterChip(
                      label: Text(option),
                      selected: primaryPulse == option,
                      onSelected: (selected) => setDialogState(() {
                        primaryPulse = selected ? option : null;
                        if (primaryPulse == null ||
                            secondaryPulse == primaryPulse) {
                          secondaryPulse = null;
                        }
                      }),
                    ),
                  ).toList(),
                ),
                const SizedBox(height: 12),
                const Text(
                  '兼脉（选填；必须与主脉不同，两项同时填写才识别组合脉）',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: controller.pulseOptions.map((option) =>
                    FilterChip(
                      label: Text(option),
                      selected: secondaryPulse == option,
                      onSelected: primaryPulse == null || primaryPulse == option
                          ? null
                          : (selected) => setDialogState(
                                () => secondaryPulse = selected ? option : null,
                              ),
                    ),
                  ).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('确认'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.businessExecution,
        status: AiTraceStatus.notStarted,
        toolId: 'structured_diagnosis',
        errorCode: 'USER_CANCELLED_INPUT_DIALOG',
      );
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.succeeded,
        toolId: 'structured_diagnosis',
      );
      return;
    }
    final before = controller.messages.length;
    final executionWatch = Stopwatch()..start();
    try {
      controller.answerTonguePulse(
        tongueCoating: tongueCoating,
        tongueShape: tongueShape,
        primaryPulse: primaryPulse,
        secondaryPulse: secondaryPulse,
      );
      executionWatch.stop();
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.businessExecution,
        status: AiTraceStatus.succeeded,
        durationMs: executionWatch.elapsedMilliseconds,
        toolId: 'structured_diagnosis',
      );
    } catch (error) {
      executionWatch.stop();
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.businessExecution,
        status: AiTraceStatus.failed,
        durationMs: executionWatch.elapsedMilliseconds,
        toolId: 'structured_diagnosis',
        errorCode: 'STRUCTURED_INTERVIEW_FAILED',
      );
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.succeeded,
        toolId: 'structured_diagnosis',
      );
      if (mounted) setState(() => _error = '舌诊脉诊输入未能提交：$error');
      return;
    }

    try {
      final persistenceResult = await _appendTcmInterviewMessages(
        before,
        traceContext: activeTraceContext,
      );
      final messagePersistenceStatus =
          !persistenceResult.transcriptMessagesApplicable
              ? AiTraceStatus.notApplicable
              : persistenceResult.transcriptMessagesPersisted
                  ? AiTraceStatus.succeeded
                  : AiTraceStatus.failed;
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.persistence,
        status: messagePersistenceStatus,
        toolId: 'structured_diagnosis',
        errorCode: messagePersistenceStatus == AiTraceStatus.failed
            ? 'PERSISTENCE_FAILED'
            : null,
      );
    } catch (error) {
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.persistence,
        status: AiTraceStatus.failed,
        toolId: 'structured_diagnosis',
        errorCode: 'PERSISTENCE_FAILED',
      );
      if (mounted) setState(() => _error = '舌脉问诊进度保存失败：$error');
    }
    await _traceRecorder.record(
      activeTraceContext,
      stage: AiTraceStage.finalRender,
      status: AiTraceStatus.succeeded,
      toolId: 'structured_diagnosis',
    );
  }

  /// Reuses verified conversation context for elliptical knowledge follow-ups.
  /// This expands only retrieval text; it never chooses a tool or business input.
  String _knowledgeQueryForCurrentTurn(String currentText) {
    final normalized = currentText.trim();
    if (normalized.isEmpty) return '';

    const followUpCues = [
      '为什么', '怎么理解', '什么意思', '含义', '依据', '原理',
      '组成', '禁忌', '适应证', '区别', '差异', '进一步', '详细解释',
      '再解释', '这个', '它的', '它呢', '这些', '刚才', '上面', '上述',
      '那它', '那这个',
    ];
    if (!followUpCues.any(normalized.contains)) return normalized;

    final priorUserTurns = _messages
        .where((message) => message.isUser)
        .map((message) => message.text.trim())
        .where((text) => text.isNotEmpty && text != normalized)
        .toList(growable: false);
    final boundedStart =
        priorUserTurns.length > 3 ? priorUserTurns.length - 3 : 0;
    final contextParts = <String>[...priorUserTurns.skip(boundedStart)];

    // Reuse only a source-attributed App result, never free-form AI prose.
    for (final message in _messages.reversed) {
      if (message.isUser || message.sourceIds.isEmpty) continue;
      final isAppToolResult =
          message.text.startsWith('【') &&
              message.text.contains('执行结果】') &&
              message.sourceIds.any((sourceId) =>
                  sourceId.startsWith('local-engine:'));
      final isAppDiagnosisResult =
          message.diagnosisResult != null &&
              message.sourceIds.contains('local-engine:diagnostic-engine');
      final isAppResult = isAppToolResult || isAppDiagnosisResult;
      if (!isAppResult) continue;
      final resultText = message.text.trim();
      contextParts.add(
        resultText.length > 1600 ? resultText.substring(0, 1600) : resultText,
      );
      break;
    }

    if (contextParts.isEmpty) return normalized;
    final contextualQuery = '${contextParts.join(' ')} $normalized';
    return AssistantKnowledgeContextBuilder.shouldRetrieveForQuery(
      contextualQuery,
    )
        ? contextualQuery
        : normalized;
  }

  String _tcmToolKnowledgeQueryForResult(
    String currentUserText,
    AssistantToolDefinition tool,
  ) {
    final userTurns = _messages
        .where((message) => message.isUser)
        .map((message) => message.text.trim())
        .where((text) => text.isNotEmpty)
        .toList(growable: true);
    final current = currentUserText.trim();
    if (current.isNotEmpty && (userTurns.isEmpty || userTurns.last != current)) {
      userTurns.add(current);
    }
    final boundedStart = userTurns.length > 4 ? userTurns.length - 4 : 0;
    final boundedUserContext = userTurns.skip(boundedStart).join(' ');
    return _tcmToolKnowledgeQuery(boundedUserContext, tool);
  }

  Future<void> _executeHeadlessTool(
    String userText,
    AssistantToolDefinition tool, {
    required AssistantMode mode,
    required AiTraceContext traceContext,
    AssistantToolArguments? arguments,
  }) async {
    if (await _blockIfRedFlagPreflightDoesNotClear(
      source: RedFlagInputSource.toolArguments,
      text: userText,
      traceContext: traceContext,
      route: 'headless_tool:${tool.id}',
    )) {
      return;
    }
    final request = arguments ??
        AssistantToolArguments(toolId: tool.id);
    final argumentErrors = request.validateAgainst(tool);
    await _traceRecorder.record(
      traceContext,
      stage: AiTraceStage.argumentValidation,
      status: argumentErrors.isEmpty
          ? AiTraceStatus.succeeded
          : AiTraceStatus.failed,
      toolId: tool.id,
      errorCode: argumentErrors.isEmpty ? null : 'INVALID_ARGUMENTS',
    );
    final executor = widget.testHeadlessToolExecutor ?? tool.headlessExecutor!;
    final executionWatch = Stopwatch()..start();
    AssistantToolResult result;
    if (argumentErrors.isEmpty) {
      try {
        result = await executor(request.values);
        executionWatch.stop();
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.businessExecution,
          status: switch (result.status) {
            AssistantToolExecutionStatus.failed => AiTraceStatus.failed,
            AssistantToolExecutionStatus.unknown => AiTraceStatus.unknown,
            AssistantToolExecutionStatus.succeeded ||
            AssistantToolExecutionStatus.noResult => AiTraceStatus.succeeded,
            AssistantToolExecutionStatus.cancelled => AiTraceStatus.failed,
          },
          durationMs: executionWatch.elapsedMilliseconds,
          toolId: tool.id,
          errorCode: switch (result.status) {
            AssistantToolExecutionStatus.failed => 'BUSINESS_EXECUTION_FAILED',
            AssistantToolExecutionStatus.cancelled =>
              'BUSINESS_EXECUTION_CANCELLED',
            AssistantToolExecutionStatus.succeeded ||
            AssistantToolExecutionStatus.noResult ||
            AssistantToolExecutionStatus.unknown => null,
          },
        );
      } catch (_) {
        executionWatch.stop();
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.businessExecution,
          status: AiTraceStatus.failed,
          durationMs: executionWatch.elapsedMilliseconds,
          toolId: tool.id,
          errorCode: 'BUSINESS_EXECUTION_FAILED',
        );
        rethrow;
      }
    } else {
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.businessExecution,
        status: AiTraceStatus.notStarted,
        toolId: tool.id,
        errorCode: 'ARGUMENT_VALIDATION_FAILED',
      );
      result = AssistantToolResult(
            toolId: tool.id,
            title: tool.title,
            status: AssistantToolExecutionStatus.failed,
            values: {'参数错误': argumentErrors.join('；')},
            arguments: request.values,
            disclaimer: '参数校验未通过；本次没有执行工具。',
          );
    }
    final contractErrors = <String>[
      ...result.validateFor(tool.id),
      ...result.validateArgumentsMatch(request.values),
    ];
    if (contractErrors.isNotEmpty) {
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.resultValidation,
        status: AiTraceStatus.failed,
        toolId: tool.id,
        errorCode: 'RESULT_CONTRACT_INVALID',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.persistence,
        status: AiTraceStatus.notStarted,
        toolId: tool.id,
        errorCode: 'RESULT_CONTRACT_INVALID',
      );
      if (mounted) {
        setState(() {
          _error = 'Headless 工具结果未通过契约校验：${contractErrors.join('；')}';
        });
      }
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.finalRender,
        status: mounted ? AiTraceStatus.succeeded : AiTraceStatus.notApplicable,
        toolId: tool.id,
        errorCode: 'RESULT_CONTRACT_INVALID',
      );
      return;
    }
    await _traceRecorder.record(
      traceContext,
      stage: AiTraceStage.resultValidation,
      status: AiTraceStatus.succeeded,
      toolId: tool.id,
    );

    final needsDreamFollowUp = tool.id == 'dream' &&
        (result.status == AssistantToolExecutionStatus.noResult ||
            result.values['检索状态'] == 'CANDIDATES_REQUIRE_CLARIFICATION');
    if (tool.id == 'dream') {
      _pendingDreamArguments = needsDreamFollowUp ? request : null;
    }

    final unresolvedBirthplace =
        result.values['未执行原因']?.contains('无法唯一识别') == true;
    if ((tool.id == 'bazi' || tool.id == 'ziwei' || tool.id == 'guansha') &&
        result.status == AssistantToolExecutionStatus.failed &&
        unresolvedBirthplace) {
      if (tool.id == 'bazi') {
        _pendingBaziArguments = request;
        _pendingZiweiArguments = null;
        _pendingGuanshaArguments = null;
      } else if (tool.id == 'ziwei') {
        _pendingZiweiArguments = request;
        _pendingBaziArguments = null;
        _pendingGuanshaArguments = null;
      } else {
        _pendingGuanshaArguments = request;
        _pendingBaziArguments = null;
        _pendingZiweiArguments = null;
      }
      _pendingHuangdiSijiArguments = null;
      _pendingXiaoliurenArguments = null;
      final clarification = switch (tool.id) {
        'ziwei' => '本地城市目录无法唯一识别刚才的出生地点。请补充省/州和城市/区县，使用“出生地：省市区”的格式；本次没有执行紫微排盘。',
        'guansha' => '本地城市目录无法唯一识别刚才的出生地点。请补充省/州和城市/区县，使用“出生地：省市区”的格式；没有使用默认地点，本次没有执行关煞测算。',
        _ => '本地城市目录无法唯一识别刚才的出生地点。请补充省/州和城市/区县，使用“出生地：省市区”的格式；本次没有执行八字排盘。',
      };
      setState(() {
        _lastEffectiveMode = mode;
        _messages
          ..add(_InterviewMessage(text: userText, isUser: true))
          ..add(_InterviewMessage(text: clarification, isUser: false));
        _error = null;
      });
      _inputController.clear();
      final persisted = await _persistSuccessfulTurn(
        userText: userText,
        assistantText: clarification,
        mode: mode,
        toolId: tool.id,
        toolStatus: 'AWAITING_PARAMETERS',
        toolArguments: request.values,
        traceId: traceContext.traceId,
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.persistence,
        status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
        toolId: tool.id,
        errorCode: persisted ? null : 'PERSISTENCE_FAILED',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.succeeded,
        toolId: tool.id,
      );
      _scrollToBottom();
      return;
    }
    final response =
        '【${tool.title}执行结果】\n${result.toConversationText()}';
    final canInterpret = result.status == AssistantToolExecutionStatus.succeeded &&
        result.sourceIds.isNotEmpty;
    final autoInterpret = canInterpret && _status?.ready == true && !_statusUnknown;
    final needsTcmKnowledge = _needsTcmKnowledgeForTool(mode, tool.id);
    final interpretationPrompt = tool.id == 'guansha'
        ? '请只解释 App 本地关煞引擎返回的结构化字段和数据集原文。必须明确这属于传统民俗文化文本，不是科学事实、命运预测或医学判断。'
            '不得把关煞名称、儿童身体部位、犯者忌或化解文字解释为孩子患病、身体缺陷、寿命或健康风险；不得给出治疗、用药或就医替代建议，也不得鼓励因民俗结果采取惩罚、恐吓或限制儿童的做法。'
            '只总结已返回的实际出生参数、四柱、命中条目、规则依据和数据集范围；不重新排盘、不改写命中结果，不补造未返回的出处。'
        : tool.id == 'bazi'        ? '请结合用户原始请求“$userText”，总结并解释刚才由 App 本地引擎返回的八字排盘结果。'
            '先概括本次实际出生参数和排盘口径，再解释四柱、十神、格局、强弱依据、五行状态和大运之间的关系。'
            '区分 App 本地引擎输出与 AI 归纳；不改动原始四柱，不补造缺失字段，也不把传统命理表述成科学预测。'
        : tool.id == 'dream'
            ? '请解释刚才 App 本地梦境民俗数据集的检索结果。用户原始描述只是检索线索，不是事实证据。'
                '只归纳结果字段中的原文和候选差异，不补写数据集中不存在的释义，不把“吉/凶”等民俗标签说成现实预测或事实。'
                '若检索状态为 CANDIDATES_REQUIRE_CLARIFICATION，必须明确尚未选定匹配词条，只按数据集原始顺序简要列出候选，不得替用户挑选或排序，并只向用户追问一个能区分情节的问题。'
                '若为 SINGLE_MATCH，也必须说明这是本地民俗文本条目，不是科学结论或未来预言。不要给医疗、法律或投资建议。'
            : '请根据本轮用户原始请求“$userText”和下方已通过 App 结果契约校验的“' +
                tool.title +
                '”执行结果，自动总结并解释实际输入、关键输出、字段含义、字段间关系和结果口径。'
                '明确区分 App 确定性计算/数据与 AI 的语言化归纳；缺失字段标记 MISSING，不猜算、不修改 App 返回值。'
                '只有在本地知识库返回了可引用条目时才结合该资料解释，并保留来源。';
    setState(() {
      _lastEffectiveMode = mode;
      _messages
        ..add(_InterviewMessage(text: userText, isUser: true))
        ..add(_InterviewMessage(
          text: response,
          isUser: false,
          sourceIds: result.sourceIds,
          actionLabel: canInterpret && !autoInterpret ? 'AI总结解读' : null,
          onAction: canInterpret && !autoInterpret
              ? () => unawaited(_requestAssistantResultInterpretation(
                    prompt: interpretationPrompt,
                    mode: mode,
                    retrievalQuery: needsTcmKnowledge
            ? _tcmToolKnowledgeQueryForResult(userText, tool)
            : null,
                    toolId: needsDreamFollowUp ? null : tool.id,
                    toolStatus: needsDreamFollowUp ? null : result.statusLabel,
                    sourceIds: result.sourceIds,
                  ))
              : null,
        ));
      _error = null;
    });
    _inputController.clear();
    final persisted = await _persistSuccessfulTurn(
      userText: userText,
      assistantText: response,
      mode: mode,
      toolId: tool.id,
      toolStatus: needsDreamFollowUp ? 'AWAITING_PARAMETERS' : result.statusLabel,
      sourceIds: result.sourceIds,
      toolArguments: result.arguments,
      traceId: traceContext.traceId,
    );
    await _traceRecorder.record(
      traceContext,
      stage: AiTraceStage.persistence,
      status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
      toolId: tool.id,
      sourceIds: result.sourceIds,
      errorCode: persisted ? null : 'PERSISTENCE_FAILED',
    );
    await _traceRecorder.record(
      traceContext,
      stage: AiTraceStage.finalRender,
      status: AiTraceStatus.succeeded,
      toolId: tool.id,
      sourceIds: result.sourceIds,
    );
    _scrollToBottom();
    if (autoInterpret && mounted) {
      await _requestAssistantResultInterpretation(
        prompt: interpretationPrompt,
        mode: mode,
        retrievalQuery: needsTcmKnowledge
            ? _tcmToolKnowledgeQueryForResult(userText, tool)
            : null,
        toolId: needsDreamFollowUp ? null : tool.id,
        toolStatus: needsDreamFollowUp ? null : result.statusLabel,
        sourceIds: result.sourceIds,
        showPromptInTimeline: false,
        allowWhileSending: true,
      );
    }
  }

  Future<void> _requestTool(
    String userText,
    AssistantToolDefinition tool, {
    AssistantMode? mode,
    AiTraceContext? traceContext,
    AssistantToolArguments? arguments,
  }) async {
    final activeTraceContext = traceContext ??
        _traceRecorder.start(
          stage: AiTraceStage.input,
          route: 'manual_tool',
          mode: (mode ?? _assistantMode).name,
        );
    if (await _blockIfRedFlagPreflightDoesNotClear(
      source: RedFlagInputSource.toolArguments,
      text: userText,
      traceContext: activeTraceContext,
      route: 'tool_dispatch:${tool.id}',
    )) {
      return;
    }
    if (traceContext == null) {
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.succeeded,
        route: 'manual_tool',
        mode: (mode ?? _assistantMode).name,
        toolId: tool.id,
      );
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.dispatch,
        status: AiTraceStatus.succeeded,
        route: 'manual_tool',
        mode: (mode ?? _assistantMode).name,
        toolId: tool.id,
      );
    }
    if (tool.id == 'structured_diagnosis') {
      await _startInlineTcmInterview(
        initialUserMessage: userText,
        traceContext: activeTraceContext,
      );
      return;
    }
    _pendingToolSelection = false;
    if (tool.id != 'guansha') _pendingGuanshaArguments = null;
    if (tool.id != 'yijing') _pendingYiJingArguments = null;
    if (tool.id != 'dosage') _pendingDosageArguments = null;
    if (tool.id != 'ziwu_liuzhu') _pendingZiWuArguments = null;
    if (tool.id != 'dream') _pendingDreamArguments = null;
    final activeMode = mode ??
        (tool.modes.contains(AssistantMode.metaphysics)
            ? AssistantMode.metaphysics
            : tool.modes.contains(AssistantMode.tools)
                ? AssistantMode.tools
                : AssistantMode.consultation);
    if (tool.id == 'guansha' && tool.headlessExecutor != null) {
      final currentArguments = arguments ??
          AssistantConversationOrchestrator.argumentsFor(tool, userText);
      final request = AssistantToolArguments(
        toolId: 'guansha',
        values: Map<String, String>.unmodifiable({
          ...?_pendingGuanshaArguments?.values,
          ...currentArguments.values,
        }),
      );
      final argumentErrors = request.validateAgainst(tool);
      if (argumentErrors.isNotEmpty) {
        _pendingGuanshaArguments = request;
        _pendingBaziArguments = null;
        _pendingZiweiArguments = null;
        _pendingMeihuaArguments = null;
        _pendingChengguArguments = null;
        _pendingHuangdiSijiArguments = null;
        _pendingXiaoliurenArguments = null;
        final missingParameters = tool.parameters
            .where((parameter) =>
                parameter.isRequired &&
                (request[parameter.key]?.trim().isEmpty ?? true))
            .map((parameter) => parameter.label)
            .toList(growable: false);
        final suppliedParameters = tool.parameters
            .where((parameter) =>
                request[parameter.key]?.trim().isNotEmpty == true)
            .map((parameter) => '${parameter.label}：${request[parameter.key]}')
            .toList(growable: false);
        final invalidParameterErrors = argumentErrors
            .where((error) =>
                !error.startsWith('缺少必填参数：') &&
                !error.startsWith('未声明的参数：'))
            .toList(growable: false);
        final clarification = [
          '我会直接在当前对话中调用 App 原有的小儿关煞规则，不需要跳转工具页面。',
          if (suppliedParameters.isNotEmpty)
            '已识别的信息：${suppliedParameters.join('；')}。',
          if (missingParameters.isNotEmpty)
            '目前还缺少：${missingParameters.join('、')}。',
          if (invalidParameterErrors.isNotEmpty)
            '以下信息需要更正：${invalidParameterErrors.join('；')}。',
          if (userText.contains('农历') || userText.contains('阴历'))
            '当前 App 规则页要求公历出生日期；农历日期不会被当作公历，也不会由 AI 猜算转换。',
          '请提供公历日期（YYYY-MM-DD）、出生地当地钟表时间（24 小时制 HH:mm）、性别和出生地点。',
          '出生地点必须能被 App 本地城市目录唯一识别；地点不明确时会继续追问，不使用默认经纬度。',
          '出生日期、时间、性别或地点未齐全前不会执行测算；可以分多轮补充，发送“取消关煞”可结束。',
          '关煞内容是传统民俗文化文本，不代表疾病、健康风险或未来事件，不是医学诊断或治疗建议。',
        ].join('\\n');
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.argumentValidation,
          status: AiTraceStatus.notStarted,
          toolId: tool.id,
          errorCode: 'GUANSHA_PARAMETERS_INCOMPLETE',
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.businessExecution,
          status: AiTraceStatus.notStarted,
          toolId: tool.id,
          errorCode: 'AWAITING_PARAMETERS',
        );
        setState(() {
          _lastEffectiveMode = activeMode;
          _messages
            ..add(_InterviewMessage(text: userText, isUser: true))
            ..add(_InterviewMessage(text: clarification, isUser: false));
          _error = null;
        });
        _inputController.clear();
        final persisted = await _persistSuccessfulTurn(
          userText: userText,
          assistantText: clarification,
          mode: activeMode,
          toolId: tool.id,
          toolStatus: 'AWAITING_PARAMETERS',
          toolArguments: request.values,
          traceId: activeTraceContext.traceId,
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.persistence,
          status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
          toolId: tool.id,
          errorCode: persisted ? null : 'PERSISTENCE_FAILED',
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.succeeded,
          toolId: tool.id,
        );
        _scrollToBottom();
        return;
      }
      _pendingGuanshaArguments = null;
      _pendingBaziArguments = null;
      _pendingZiweiArguments = null;
      await _executeHeadlessTool(
        userText,
        tool,
        mode: activeMode,
        traceContext: activeTraceContext,
        arguments: request,
      );
      return;
    }

    if (tool.id == 'dream' && tool.headlessExecutor != null) {
      final currentArguments = arguments ??
          AssistantConversationOrchestrator.argumentsFor(tool, userText);
      final mergedValues = <String, String>{
        ...?_pendingDreamArguments?.values,
        ...currentArguments.values,
      };
      final request = AssistantToolArguments(
        toolId: 'dream',
        values: Map<String, String>.unmodifiable(mergedValues),
      );
      if (request['dream_text']?.trim().isNotEmpty != true) {
        _pendingDreamArguments = request;
        const clarification =
            '我会直接在当前对话中检索 App 本地梦境资料。请描述梦中实际出现的事物和具体情节，例如看到了什么、发生了什么、场景或结局如何；仅说“帮我解梦”还不足以检索。资料属于传统民俗文本，不代表现实吉凶或未来预测。';
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.argumentValidation,
          status: AiTraceStatus.notStarted,
          toolId: tool.id,
          errorCode: 'DREAM_DESCRIPTION_MISSING',
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.businessExecution,
          status: AiTraceStatus.notStarted,
          toolId: tool.id,
          errorCode: 'AWAITING_PARAMETERS',
        );
        setState(() {
          _lastEffectiveMode = activeMode;
          _messages
            ..add(_InterviewMessage(text: userText, isUser: true))
            ..add(const _InterviewMessage(text: clarification, isUser: false));
          _error = null;
        });
        _inputController.clear();
        final persisted = await _persistSuccessfulTurn(
          userText: userText,
          assistantText: clarification,
          mode: activeMode,
          toolId: tool.id,
          toolStatus: 'AWAITING_PARAMETERS',
          toolArguments: request.values,
          traceId: activeTraceContext.traceId,
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.persistence,
          status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
          toolId: tool.id,
          errorCode: persisted ? null : 'PERSISTENCE_FAILED',
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.succeeded,
          toolId: tool.id,
        );
        _scrollToBottom();
        return;
      }
      _pendingDreamArguments = null;
      await _executeHeadlessTool(
        userText,
        tool,
        mode: activeMode,
        traceContext: activeTraceContext,
        arguments: request,
      );
      return;
    }
    if (tool.id == 'ziwu_liuzhu' &&
        tool.headlessExecutor != null) {
      // Do not trust a model-proposed timestamp or slot value. Re-extract
      // only values visible in the user's current text, and carry forward only
      // the previously persisted AWAITING_PARAMETERS slots.
      final carriedSlots =
          _pendingZiWuArguments?.values ?? const <String, String>{};
      final currentTextSlots = AssistantConversationOrchestrator.argumentsFor(
        tool,
        userText,
      );
      final request = AssistantToolArguments(
        toolId: 'ziwu_liuzhu',
        values: ZiWuLiuZhuToolExecutor.prepareExecutionArguments({
          ...carriedSlots,
          ...currentTextSlots.values,
        }),
      );
      final argumentErrors = request.validateAgainst(tool);
      final businessErrors =
          ZiWuLiuZhuToolExecutor.validateArguments(request.values);
      final date = request['date'];
      final time = request['time'];
      final missingParameters = <String>[
        if (date != null &&
            date != 'AMBIGUOUS_DATE_SELECTION' &&
            time == null &&
            request['at'] == null)
          '具体时刻（HH:mm）',
      ];
      final invalidParameterErrors = <String>[
        if (date == 'AMBIGUOUS_DATE_SELECTION')
          '你提供了多个日期，请明确一个公历日期',
        if (date == 'INVALID_DATE' ||
            (date != null &&
                date != 'AMBIGUOUS_DATE_SELECTION' &&
                date != 'INVALID_DATE' &&
                !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)))
          '公历日期无效，请使用 YYYY-MM-DD',
        if (time == 'AMBIGUOUS_TIME_SELECTION')
          '你提供了多个时刻，请明确一个 HH:mm 时刻',
        if (time != null &&
            time != 'AMBIGUOUS_TIME_SELECTION' &&
            !RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(time))
          '时刻无效，请使用 24 小时制 HH:mm',
      ];
      final executionErrors = [
        ...argumentErrors,
        ...businessErrors.where(
          (error) => !error.startsWith('缺少完整的设备本地日期和时间'),
        ),
      ];
      if (executionErrors.isNotEmpty ||
          missingParameters.isNotEmpty ||
          invalidParameterErrors.isNotEmpty) {
        _pendingZiWuArguments = request;
        _pendingDosageArguments = null;
        _pendingYiJingArguments = null;
        _pendingBaziArguments = null;
        _pendingZiweiArguments = null;
        _pendingMeihuaArguments = null;
        _pendingChengguArguments = null;
        _pendingHuangdiSijiArguments = null;
        _pendingXiaoliurenArguments = null;
        final suppliedParameters = <String>[
          if (date != null &&
              date != 'INVALID_DATE' &&
              date != 'AMBIGUOUS_DATE_SELECTION')
            '公历日期：$date',
          if (time != null &&
              time != 'AMBIGUOUS_TIME_SELECTION')
            '设备本地时刻：$time',
          if (request['at'] != null) '最终计算时间：${request['at']}',
        ];
        final clarification = [
          '我会在当前对话中调用 App 原有子午流注引擎，不需要打开时辰开穴页面。',
          if (suppliedParameters.isNotEmpty)
            '已识别的信息：${suppliedParameters.join('；')}。',
          if (missingParameters.isNotEmpty)
            '目前还缺少：${missingParameters.join('、')}。',
          if (invalidParameterErrors.isNotEmpty)
            invalidParameterErrors.join('；') + '。',
          if (missingParameters.isNotEmpty)
            '请补充精确到分钟的设备本地时刻，例如“10:30”；补齐后会按 App 原有口径计算。',
          '未指定日期和时刻时，App 使用设备当前本地时间；指定日期时必须同时提供时刻。',
          '计算口径固定为默认经度 120E、纬度 30N，子时按 23:00 换日，未启用真太阳时。',
          '结果是传统时辰开穴计算资料，不是疾病诊断、针刺处方或个体治疗建议。',
        ].join('\n');
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.argumentValidation,
          status: AiTraceStatus.notStarted,
          toolId: tool.id,
          errorCode: 'ZIWU_PARAMETERS_INCOMPLETE',
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.businessExecution,
          status: AiTraceStatus.notStarted,
          toolId: tool.id,
          errorCode: 'AWAITING_PARAMETERS',
        );
        setState(() {
          _lastEffectiveMode = activeMode;
          _messages
            ..add(_InterviewMessage(text: userText, isUser: true))
            ..add(_InterviewMessage(text: clarification, isUser: false));
          _error = null;
        });
        _inputController.clear();
        final persisted = await _persistSuccessfulTurn(
          userText: userText,
          assistantText: clarification,
          mode: activeMode,
          toolId: tool.id,
          toolStatus: 'AWAITING_PARAMETERS',
          toolArguments: request.values,
          traceId: activeTraceContext.traceId,
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.persistence,
          status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
          toolId: tool.id,
          errorCode: persisted ? null : 'PERSISTENCE_FAILED',
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.succeeded,
          toolId: tool.id,
        );
        _scrollToBottom();
        return;
      }
      _pendingZiWuArguments = null;
      await _executeHeadlessTool(
        userText,
        tool,
        mode: activeMode,
        traceContext: activeTraceContext,
        arguments: request,
      );
      return;
    }

    if (tool.id == 'dosage' && tool.headlessExecutor != null) {
      final request = arguments ?? AssistantToolArguments(toolId: tool.id);
      final argumentErrors = request.validateAgainst(tool);
      final businessErrors =
          DosageToolExecutor.validateArguments(request.values);
      final missingParameters = <String>[
        if (request['value']?.trim().isNotEmpty != true) '换算数值',
        if (request['unit']?.trim().isNotEmpty != true) '原始单位',
        if (DosageConversionService.isWeightUnit(request['unit'] ?? '') &&
            request['standard']?.trim().isNotEmpty != true)
          '度量标准',
      ];
      final allErrors = [...argumentErrors, ...businessErrors];
      final invalidParameterErrors = allErrors
          .where((error) =>
              !error.startsWith('缺少必填参数：') &&
              !error.startsWith('缺少换算数值') &&
              !error.startsWith('缺少原始单位'))
          .toSet()
          .toList(growable: false);
      if (allErrors.isNotEmpty || missingParameters.isNotEmpty) {
        _pendingYiJingArguments = null;
        _pendingDosageArguments = request;
        _pendingBaziArguments = null;
        _pendingZiweiArguments = null;
        _pendingMeihuaArguments = null;
        _pendingChengguArguments = null;
        _pendingHuangdiSijiArguments = null;
        _pendingXiaoliurenArguments = null;
        final suppliedParameters = <String>[
          if (request['value']?.trim().isNotEmpty == true)
            '数值：${request['value']}',
          if (request['unit']?.trim().isNotEmpty == true &&
              request['unit'] != 'AMBIGUOUS_UNIT_SELECTION')
            '原始单位：${request['unit']}',
          if (request['standard']?.trim().isNotEmpty == true &&
              request['standard'] != 'AMBIGUOUS_STANDARD_SELECTION')
            '度量标准：${DosageConversionService.standardLabel(request['standard']!)}',
        ];
        final clarification = [
          '我会在当前对话中调用 App 原有经方度量衡单位换算函数，不需要打开换算器页面。',
          if (suppliedParameters.isNotEmpty)
            '已识别的信息：${suppliedParameters.join('；')}。',
          if (missingParameters.isNotEmpty)
            '目前还缺少：${missingParameters.join('、')}。',
          if (invalidParameterErrors.isNotEmpty)
            '以下信息需要明确或更正：${invalidParameterErrors.join('；')}。',
          if (missingParameters.contains('度量标准'))
            '重量单位必须明确选择汉制、台制或唐制；容量和长度单位不依赖这三种重量标准。',
          '支持重量单位：两、铢、斤、石、钱；容量单位：升、合、圭、撮；长度单位：尺、寸。',
          '本工具只把单位换算为克、毫升或厘米，不计算处方、药物剂量或个人用药建议。',
        ].join('\n');
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.argumentValidation,
          status: AiTraceStatus.notStarted,
          toolId: tool.id,
          errorCode: 'DOSAGE_PARAMETERS_INCOMPLETE',
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.businessExecution,
          status: AiTraceStatus.notStarted,
          toolId: tool.id,
          errorCode: 'AWAITING_PARAMETERS',
        );
        setState(() {
          _lastEffectiveMode = activeMode;
          _messages
            ..add(_InterviewMessage(text: userText, isUser: true))
            ..add(_InterviewMessage(text: clarification, isUser: false));
          _error = null;
        });
        _inputController.clear();
        final persisted = await _persistSuccessfulTurn(
          userText: userText,
          assistantText: clarification,
          mode: activeMode,
          toolId: tool.id,
          toolStatus: 'AWAITING_PARAMETERS',
          toolArguments: request.values,
          traceId: activeTraceContext.traceId,
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.persistence,
          status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
          toolId: tool.id,
          errorCode: persisted ? null : 'PERSISTENCE_FAILED',
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.succeeded,
          toolId: tool.id,
        );
        _scrollToBottom();
        return;
      }
      _pendingDosageArguments = null;
      await _executeHeadlessTool(
        userText,
        tool,
        mode: activeMode,
        traceContext: activeTraceContext,
        arguments: request,
      );
      return;
    }

    // Only auto-execute a Headless calculator when the user supplied its
    // explicit date argument. Without a date, preserve the existing Page Tool
    // flow so a broad "how is it calculated?" request is not silently run for
    // today's date.
    if (tool.id == 'solar_terms' && tool.headlessExecutor != null) {
      // A generic current-term request is valid with no slot. A named term is
      // deterministically extracted by AssistantConversationOrchestrator.
      // The executor owns current-term calculation and knowledge-asset lookup.
      await _executeHeadlessTool(
        userText,
        tool,
        mode: activeMode,
        traceContext: activeTraceContext,
        arguments: arguments ?? AssistantToolArguments(toolId: tool.id),
      );
      return;
    }

    if (tool.id == 'huangdi_siji' && tool.headlessExecutor != null) {
      final request = arguments ?? AssistantToolArguments(toolId: tool.id);
      final argumentErrors = request.validateAgainst(tool);
      if (argumentErrors.isNotEmpty) {
        _pendingHuangdiSijiArguments = request;
        _pendingBaziArguments = null;
        _pendingZiweiArguments = null;
        _pendingMeihuaArguments = null;
        _pendingChengguArguments = null;
        final missingParameters = tool.parameters
            .where((parameter) =>
                parameter.isRequired &&
                (request[parameter.key]?.trim().isEmpty ?? true))
            .map((parameter) => parameter.label)
            .toList(growable: false);
        final suppliedParameters = tool.parameters
            .where((parameter) =>
                (request[parameter.key]?.trim().isNotEmpty ?? false))
            .map((parameter) =>
                parameter.label + '：' + request[parameter.key]!)
            .toList(growable: false);
        final invalidParameterErrors = argumentErrors
            .where((error) =>
                !error.startsWith('缺少必填参数：') &&
                !error.startsWith('未声明的参数：'))
            .toList(growable: false);
        final unsupportedLunarDate =
            request['birth_date'] == 'LUNAR_DATE_NOT_SUPPORTED';
        final clarification = [
          '我会在当前对话中调用 App 原有黄帝四季歌本地算法和数据表，不需要打开工具页面。',
          if (suppliedParameters.isNotEmpty)
            '已识别的信息：' + suppliedParameters.join('；') + '。',
          if (missingParameters.isNotEmpty)
            '目前还缺少：' + missingParameters.join('、') + '。',
          if (invalidParameterErrors.isNotEmpty)
            '以下信息需要更正：' + invalidParameterErrors.join('；') + '。',
          if (unsupportedLunarDate)
            '现有页面按公历日期换算农历月份；请提供公历日期，不会把农历日期当作公历或自行猜测换算。',
          '请补充出生日期（公历 YYYY-MM-DD）和出生地当地钟表时间（24 小时制 HH:mm），可以分多轮发送。',
          '未提供的日期或时间不会使用页面示例值或默认值；结果会回显实际采用的农历月份、季节口径和时辰。',
          '例如：出生日期：1990-01-02；出生时间：晚上8:30。',
          '四季歌属于传统民俗文化资料，仅作文化参考，不是科学预测或生活决策依据。',
        ].join('\n');
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.argumentValidation,
          status: AiTraceStatus.notStarted,
          toolId: tool.id,
          errorCode: 'HUANGDI_SIJI_PARAMETERS_INCOMPLETE',
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.businessExecution,
          status: AiTraceStatus.notStarted,
          toolId: tool.id,
          errorCode: 'AWAITING_PARAMETERS',
        );
        setState(() {
          _lastEffectiveMode = activeMode;
          _messages
            ..add(_InterviewMessage(text: userText, isUser: true))
            ..add(_InterviewMessage(text: clarification, isUser: false));
          _error = null;
        });
        _inputController.clear();
        final persisted = await _persistSuccessfulTurn(
          userText: userText,
          assistantText: clarification,
          mode: activeMode,
          toolId: tool.id,
          toolStatus: 'AWAITING_PARAMETERS',
          toolArguments: request.values,
          traceId: activeTraceContext.traceId,
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.persistence,
          status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
          toolId: tool.id,
          errorCode: persisted ? null : 'PERSISTENCE_FAILED',
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.succeeded,
          toolId: tool.id,
        );
        _scrollToBottom();
        return;
      }
      _pendingHuangdiSijiArguments = null;
      _pendingXiaoliurenArguments = null;
      _pendingBaziArguments = null;
      _pendingZiweiArguments = null;
      _pendingMeihuaArguments = null;
      _pendingChengguArguments = null;
      await _executeHeadlessTool(
        userText,
        tool,
        mode: activeMode,
        traceContext: activeTraceContext,
        arguments: request,
      );
      return;
    }

    if (tool.id == 'chenggu' && tool.headlessExecutor != null) {
      final request = arguments ?? AssistantToolArguments(toolId: tool.id);
      final argumentErrors = request.validateAgainst(tool);
      if (argumentErrors.isNotEmpty) {
        _pendingChengguArguments = request;
        _pendingHuangdiSijiArguments = null;
        _pendingXiaoliurenArguments = null;
        _pendingBaziArguments = null;
        _pendingZiweiArguments = null;
        _pendingMeihuaArguments = null;
        final missingParameters = tool.parameters
            .where((parameter) =>
                parameter.isRequired &&
                (request[parameter.key]?.trim().isEmpty ?? true))
            .map((parameter) => parameter.label)
            .toList(growable: false);
        final suppliedParameters = tool.parameters
            .where((parameter) =>
                (request[parameter.key]?.trim().isNotEmpty ?? false))
            .map((parameter) =>
                parameter.label + '：' + request[parameter.key]!)
            .toList(growable: false);
        final invalidParameterErrors = argumentErrors
            .where((error) =>
                !error.startsWith('缺少必填参数：') &&
                !error.startsWith('未声明的参数：'))
            .toList(growable: false);
        final unsupportedLunarDate =
            request['birth_date'] == 'LUNAR_DATE_NOT_SUPPORTED';
        final clarification = [
          '我会在当前对话中调用 App 原有称骨算法，不需要跳转到称骨页面。',
          if (suppliedParameters.isNotEmpty)
            '已识别的信息：' + suppliedParameters.join('；') + '。',
          if (missingParameters.isNotEmpty)
            '目前还缺少：' + missingParameters.join('、') + '。',
          if (invalidParameterErrors.isNotEmpty)
            '以下信息需要更正：' + invalidParameterErrors.join('；') + '。',
          if (unsupportedLunarDate)
            '原页面使用公历出生日期；请提供公历日期，App 不会把农历日期直接当作公历，也不会自行猜测换算。',
          '请补充出生日期（公历 YYYY-MM-DD）和出生地当地钟表时间（24 小时制 HH:mm），可以分多轮发送。',
          '称骨计算沿用 App 当前已保存的真太阳时和早晚子时设置；不会使用页面示例生日或默认中午时间。',
          '例如：出生日期：1990-01-02；出生时间：08:30。',
          '称骨歌诀属于传统民俗文化资料，不是科学预测或生活决策依据。',
        ].join('\n');
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.argumentValidation,
          status: AiTraceStatus.notStarted,
          toolId: tool.id,
          errorCode: 'CHENGGU_PARAMETERS_INCOMPLETE',
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.businessExecution,
          status: AiTraceStatus.notStarted,
          toolId: tool.id,
          errorCode: 'AWAITING_PARAMETERS',
        );
        setState(() {
          _lastEffectiveMode = activeMode;
          _messages
            ..add(_InterviewMessage(text: userText, isUser: true))
            ..add(_InterviewMessage(text: clarification, isUser: false));
          _error = null;
        });
        _inputController.clear();
        final persisted = await _persistSuccessfulTurn(
          userText: userText,
          assistantText: clarification,
          mode: activeMode,
          toolId: tool.id,
          toolStatus: 'AWAITING_PARAMETERS',
          toolArguments: request.values,
          traceId: activeTraceContext.traceId,
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.persistence,
          status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
          toolId: tool.id,
          errorCode: persisted ? null : 'PERSISTENCE_FAILED',
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.succeeded,
          toolId: tool.id,
        );
        _scrollToBottom();
        return;
      }
      _pendingChengguArguments = null;
      _pendingHuangdiSijiArguments = null;
      _pendingXiaoliurenArguments = null;
      _pendingBaziArguments = null;
      _pendingZiweiArguments = null;
      _pendingMeihuaArguments = null;
      await _executeHeadlessTool(
        userText,
        tool,
        mode: activeMode,
        traceContext: activeTraceContext,
        arguments: request,
      );
      return;
    }

    if (tool.id == 'ziwei' && tool.headlessExecutor != null) {
      final request = arguments ?? AssistantToolArguments(toolId: tool.id);
      final argumentErrors = request.validateAgainst(tool);
      if (argumentErrors.isNotEmpty) {
        _pendingZiweiArguments = request;
        _pendingBaziArguments = null;
        _pendingMeihuaArguments = null;
        _pendingChengguArguments = null;
        _pendingHuangdiSijiArguments = null;
        _pendingXiaoliurenArguments = null;
        final missingParameters = tool.parameters
            .where((parameter) =>
                parameter.isRequired &&
                (request[parameter.key]?.trim().isEmpty ?? true))
            .map((parameter) => parameter.label)
            .toList(growable: false);
        final suppliedParameters = tool.parameters
            .where((parameter) =>
                (request[parameter.key]?.trim().isNotEmpty ?? false))
            .map((parameter) =>
                '${parameter.label}：${request[parameter.key]}')
            .toList(growable: false);
        final invalidParameterErrors = argumentErrors
            .where((error) =>
                !error.startsWith('缺少必填参数：') &&
                !error.startsWith('未声明的参数：'))
            .toList(growable: false);
        final unsupportedLunarDate =
            request['birth_date'] == 'LUNAR_DATE_NOT_SUPPORTED';
        final clarification = [
          '我会在当前对话中调用 App 原有紫微斗数本地排盘引擎，不需要打开排盘页面。',
          if (suppliedParameters.isNotEmpty)
            '已识别的信息：${suppliedParameters.join('；')}。',
          if (missingParameters.isNotEmpty)
            '目前还缺少：${missingParameters.join('、')}。',
          if (invalidParameterErrors.isNotEmpty)
            '以下信息需要更正：${invalidParameterErrors.join('；')}。',
          if (unsupportedLunarDate)
            '紫微排盘入口要求公历出生日期；请提供公历日期，不会把农历日期当作公历，也不会自行推算或猜测。',
          '请补充出生日期（公历 YYYY-MM-DD）、出生地当地钟表时间（24 小时制 HH:mm）、性别和出生地；可以分多轮发送。',
          '出生地必须能在 App 城市目录中唯一识别；不会使用页面示例生日、默认性别或默认经纬度。真太阳时和早晚子时按 App 当前设置执行。',
          '例如：出生日期：1990-01-02；出生时间：08:30；性别：男；出生地：上海市。',
          '紫微斗数属于传统术数文化参考，不是科学预测，不用于医疗、法律或投资决策。',
        ].join('\n');
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.argumentValidation,
          status: AiTraceStatus.notStarted,
          toolId: tool.id,
          errorCode: 'ZIWEI_PARAMETERS_INCOMPLETE',
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.businessExecution,
          status: AiTraceStatus.notStarted,
          toolId: tool.id,
          errorCode: 'AWAITING_PARAMETERS',
        );
        setState(() {
          _lastEffectiveMode = activeMode;
          _messages
            ..add(_InterviewMessage(text: userText, isUser: true))
            ..add(_InterviewMessage(text: clarification, isUser: false));
          _error = argumentErrors.join('；');
        });
        _inputController.clear();
        final persisted = await _persistSuccessfulTurn(
          userText: userText,
          assistantText: clarification,
          mode: activeMode,
          toolId: tool.id,
          toolStatus: 'AWAITING_PARAMETERS',
          toolArguments: request.values,
          traceId: activeTraceContext.traceId,
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.persistence,
          status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
          toolId: tool.id,
          errorCode: persisted ? null : 'PERSISTENCE_FAILED',
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.succeeded,
          toolId: tool.id,
        );
        _scrollToBottom();
        return;
      }
      _pendingZiweiArguments = null;
      await _executeHeadlessTool(
        userText,
        tool,
        mode: activeMode,
        traceContext: activeTraceContext,
        arguments: request,
      );
      return;
    }

    if (tool.id == 'bazi' && tool.headlessExecutor != null) {
      var request = arguments ?? AssistantToolArguments(toolId: tool.id);
      var argumentErrors = request.validateAgainst(tool);
      final missingKeys = tool.parameters
          .where((parameter) =>
              parameter.isRequired &&
              (request[parameter.key]?.trim().isEmpty ?? true))
          .map((parameter) => parameter.key)
          .toSet();
      final slotTraceId = activeTraceContext.traceId;
      if (argumentErrors.isNotEmpty &&
          _status?.ready == true &&
          slotTraceId != null &&
          AssistantConversationOrchestrator.shouldUseBaziSlotModel(
            userText,
            missingKeys,
          )) {
        setState(() => _sending = true);
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.nativeInference,
          status: AiTraceStatus.notStarted,
          route: 'bazi_slot_extraction',
          toolId: tool.id,
        );
        try {
          final draft = await _service.extractBaziSlotsWithTrace(
            query: userText,
            missingKeys: missingKeys,
            traceId: slotTraceId,
          );
          request = AssistantToolArguments(
            toolId: tool.id,
            values: {
              ...request.values,
              ...draft.values,
            },
          );
          await _traceRecorder.record(
            activeTraceContext,
            stage: AiTraceStage.nativeInference,
            status: AiTraceStatus.succeeded,
            route: 'bazi_slot_extraction',
            toolId: tool.id,
            backend: draft.backend,
          );
          await _traceRecorder.record(
            activeTraceContext,
            stage: AiTraceStage.modelOutput,
            status: AiTraceStatus.succeeded,
            route: 'bazi_slot_extraction',
            toolId: tool.id,
            backend: draft.backend,
          );
          await _traceRecorder.record(
            activeTraceContext,
            stage: AiTraceStage.resultValidation,
            status: AiTraceStatus.succeeded,
            route: 'bazi_slot_evidence_validation',
            toolId: tool.id,
          );
        } catch (error) {
          // Slot extraction is advisory. Invalid JSON, weak evidence, or Native
          // failure falls back to the deterministic missing-field prompt.
          await _traceRecorder.record(
            activeTraceContext,
            stage: AiTraceStage.nativeInference,
            status: AiTraceStatus.unknown,
            route: 'bazi_slot_extraction',
            toolId: tool.id,
            errorCode: 'BAZI_SLOT_EXTRACTION_FAILED',
          );
          await _traceRecorder.record(
            activeTraceContext,
            stage: AiTraceStage.modelOutput,
            status: AiTraceStatus.failed,
            route: 'bazi_slot_extraction',
            toolId: tool.id,
            errorCode: 'BAZI_SLOT_OUTPUT_REJECTED',
          );
          await _traceRecorder.record(
            activeTraceContext,
            stage: AiTraceStage.resultValidation,
            status: AiTraceStatus.notStarted,
            route: 'bazi_slot_evidence_validation',
            toolId: tool.id,
          );
        } finally {
          if (mounted) setState(() => _sending = false);
        }
        if (!mounted) return;
        argumentErrors = request.validateAgainst(tool);
      }
      if (argumentErrors.isNotEmpty) {
        _pendingBaziArguments = request;
        _pendingZiweiArguments = null;
        _pendingHuangdiSijiArguments = null;
        _pendingXiaoliurenArguments = null;
        final missingParameters = tool.parameters
            .where((parameter) =>
                parameter.isRequired &&
                (request[parameter.key]?.trim().isEmpty ?? true))
            .map((parameter) => parameter.label)
            .toList(growable: false);
        final suppliedParameters = tool.parameters
            .where((parameter) =>
                (request[parameter.key]?.trim().isNotEmpty ?? false))
            .map((parameter) =>
                '${parameter.label}：${request[parameter.key]}')
            .toList(growable: false);
        final invalidParameterErrors = argumentErrors
            .where((error) =>
                !error.startsWith('缺少必填参数：') &&
                !error.startsWith('未声明的参数：'))
            .toList(growable: false);
        final clarification = [
          '我会在当前对话中调用 App 本地八字排盘，不需要跳转到排盘页面。',
          if (suppliedParameters.isNotEmpty)
            '已识别的信息：${suppliedParameters.join('；')}。',
          if (missingParameters.isNotEmpty)
            '目前还缺少：${missingParameters.join('、')}。',
          if (invalidParameterErrors.isNotEmpty)
            '以下信息需要更正：${invalidParameterErrors.join('；')}。',
          '请只补充或更正上述项目，可以分多轮发送。',
          '示例：出生日期：1990-01-02；出生时间：08:30；性别：男；出生地：上海市。',
          '注意：出生日期使用公历；出生时间使用出生地当地钟表时间（24 小时制 HH:mm）。本地引擎按出生地经度执行真太阳时校正，不处理历史时区或夏令时换算；不会使用示例日期、默认性别或默认经纬度。',
        ].join();
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.argumentValidation,
          status: AiTraceStatus.notStarted,
          toolId: tool.id,
          errorCode: 'BAZI_PARAMETERS_INCOMPLETE',
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.businessExecution,
          status: AiTraceStatus.notStarted,
          toolId: tool.id,
          errorCode: 'AWAITING_PARAMETERS',
        );
        setState(() {
          _lastEffectiveMode = activeMode;
          _messages
            ..add(_InterviewMessage(text: userText, isUser: true))
            ..add(_InterviewMessage(text: clarification, isUser: false));
          _error = argumentErrors.join('；');
        });
        _inputController.clear();
        final persisted = await _persistSuccessfulTurn(
          userText: userText,
          assistantText: clarification,
          mode: activeMode,
          toolId: tool.id,
          toolStatus: 'AWAITING_PARAMETERS',
          toolArguments: request.values,
          traceId: activeTraceContext.traceId,
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.persistence,
          status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
          toolId: tool.id,
          errorCode: persisted ? null : 'PERSISTENCE_FAILED',
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.succeeded,
          toolId: tool.id,
        );
        _scrollToBottom();
        return;
      }
      _pendingBaziArguments = null;
      _pendingZiweiArguments = null;
      await _executeHeadlessTool(
        userText,
        tool,
        mode: activeMode,
        traceContext: activeTraceContext,
        arguments: request,
      );
      return;
    }

    // All three existing Meihua methods now use the same in-chat executor.
    // Method-specific values are still collected and validated before execution.
    if (tool.id == 'meihua' && tool.headlessExecutor != null) {
      final now = DateTime.now();
      var request = arguments ?? AssistantToolArguments(toolId: tool.id);
      final method = request['method'];
      final values = <String, String>{...request.values};
      if (method != null && request['date'] == null) {
        values['date'] = '${now.year.toString().padLeft(4, '0')}-'
            '${now.month.toString().padLeft(2, '0')}-'
            '${now.day.toString().padLeft(2, '0')}';
      }
      if (method == 'time' && request['hour_branch'] == null) {
        const branches = ['子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥'];
        final branchIndex = ((now.hour.clamp(0, 23) + 1) ~/ 2) % 12;
        values['hour_branch'] = branches[branchIndex];
      }
      request = AssistantToolArguments(
        toolId: tool.id,
        values: Map<String, String>.unmodifiable(values),
      );

      final argumentErrors = request.validateAgainst(tool);
      final missingParameters = <String>[];
      if (method == null || method.isEmpty) {
        missingParameters.add('起卦方式');
      } else if (method == 'number') {
        if (request['first']?.trim().isNotEmpty != true) {
          missingParameters.add('第一数（上卦）');
        }
        if (request['second']?.trim().isNotEmpty != true) {
          missingParameters.add('第二数（下卦）');
        }
      }
      final needsClarification = argumentErrors.isNotEmpty ||
          missingParameters.isNotEmpty;
      if (needsClarification) {
        _pendingMeihuaArguments = request;
        _pendingHuangdiSijiArguments = null;
        _pendingXiaoliurenArguments = null;
        _pendingBaziArguments = null;
        _pendingZiweiArguments = null;
        final methodLabel = switch (method) {
          'number' => '数字起卦',
          'time' => '时间起卦',
          'random' => '随机起卦',
          _ => null,
        };
        final suppliedParameters = <String>[
          if (methodLabel != null) '起卦方式：$methodLabel',
          for (final parameter in tool.parameters)
            if (parameter.key != 'method' &&
                (request[parameter.key]?.trim().isNotEmpty ?? false))
              '${parameter.label}：${request[parameter.key]}',
        ];
        final invalidParameterErrors = argumentErrors
            .where((error) =>
                !error.startsWith('缺少必填参数：') &&
                !error.startsWith('未声明的参数：'))
            .toList(growable: false);
        final clarification = [
          '三种梅花起卦方式都可以直接在当前对话中完成，使用 App 原有本地算法，不需要跳转页面。',
          if (suppliedParameters.isNotEmpty)
            '已识别的信息：${suppliedParameters.join('；')}。',
          if (missingParameters.isNotEmpty)
            '目前还缺少：${missingParameters.join('、')}。',
          if (method == null || method.isEmpty)
            '请先选择：数字起卦、时间起卦或随机起卦。',
          if (method == 'number')
            '数字起卦需要两个正整数，分别作为第一数（上卦）和第二数（下卦）；可以分多轮补充。',
          if (method == 'time')
            '时间起卦沿用 App 页面口径；未指定日期或时辰时，使用设备本地当天和当前时辰，并在结果中回显。',
          if (method == 'random')
            '随机起卦由 App 本地随机数生成上卦、下卦和动爻，模型不会生成卦象。',
          if (invalidParameterErrors.isNotEmpty)
            '以下信息需要更正：${invalidParameterErrors.join('；')}。',
          if (userText.contains('农历') || userText.contains('阴历'))
            '当前起卦日期参数使用公历；不会把农历日期误当成公历或自动换算。',
          '例如：数字起卦可说“用 3 和 7”；时间起卦可说“2026-11-13，申时”；随机起卦可直接说“随机起卦”。',
        ].join('\n');
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.argumentValidation,
          status: AiTraceStatus.notStarted,
          toolId: tool.id,
          errorCode: 'MEIHUA_PARAMETERS_INCOMPLETE',
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.businessExecution,
          status: AiTraceStatus.notStarted,
          toolId: tool.id,
          errorCode: 'AWAITING_PARAMETERS',
        );
        setState(() {
          _lastEffectiveMode = activeMode;
          _messages
            ..add(_InterviewMessage(text: userText, isUser: true))
            ..add(_InterviewMessage(text: clarification, isUser: false));
          _error = null;
        });
        _inputController.clear();
        final persisted = await _persistSuccessfulTurn(
          userText: userText,
          assistantText: clarification,
          mode: activeMode,
          toolId: tool.id,
          toolStatus: 'AWAITING_PARAMETERS',
          toolArguments: request.values,
          traceId: activeTraceContext.traceId,
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.persistence,
          status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
          toolId: tool.id,
          errorCode: persisted ? null : 'PERSISTENCE_FAILED',
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.succeeded,
          toolId: tool.id,
        );
        _scrollToBottom();
        return;
      }

      _pendingMeihuaArguments = null;
      _pendingChengguArguments = null;
      _pendingHuangdiSijiArguments = null;
      _pendingXiaoliurenArguments = null;
      _pendingBaziArguments = null;
      _pendingZiweiArguments = null;
      await _executeHeadlessTool(
        userText,
        tool,
        mode: activeMode,
        traceContext: activeTraceContext,
        arguments: request,
      );
      return;
    }

    if (tool.id == 'xiaoliuren' && tool.headlessExecutor != null) {
      final request = arguments ?? AssistantToolArguments(toolId: tool.id);
      final argumentErrors = request.validateAgainst(tool);
      if (argumentErrors.isNotEmpty) {
        _pendingXiaoliurenArguments = request;
        _pendingMeihuaArguments = null;
        _pendingChengguArguments = null;
        _pendingHuangdiSijiArguments = null;
        _pendingBaziArguments = null;
        _pendingZiweiArguments = null;
        final missingParameters = tool.parameters
            .where((parameter) =>
                parameter.isRequired &&
                (request[parameter.key]?.trim().isEmpty ?? true))
            .map((parameter) => parameter.label)
            .toList(growable: false);
        final suppliedParameters = tool.parameters
            .where((parameter) =>
                request[parameter.key]?.trim().isNotEmpty ?? false)
            .map((parameter) =>
                '${parameter.label}：${request[parameter.key]}')
            .toList(growable: false);
        final invalidParameterErrors = argumentErrors
            .where((error) =>
                !error.startsWith('缺少必填参数：') &&
                !error.startsWith('未声明的参数：'))
            .toList(growable: false);
        final lunarDate = request['date'] == 'LUNAR_DATE_NOT_SUPPORTED';
        final ambiguousDate = request['date'] == 'AMBIGUOUS_DATE_SELECTION';
        final ambiguousHour = request['hour'] == 'AMBIGUOUS_HOUR_SELECTION';
        final ambiguousRule = request['rule'] == 'AMBIGUOUS_RULE_SELECTION';
        final clarification = [
          '我会在当前对话中调用 App 原有的小六壬排课纯函数，不需要打开工具页面。',
          if (suppliedParameters.isNotEmpty)
            '已识别的信息：${suppliedParameters.join('；')}。',
          if (missingParameters.isNotEmpty)
            '目前还缺少：${missingParameters.join('、')}。',
          if (lunarDate)
            '小六壬此入口要求公历日期；不会把农历日期当作公历，也不会自行猜测换算。',
          if (ambiguousDate)
            '你提到了多个日期，请明确本次起课使用哪一天。',
          if (ambiguousHour)
            '你提到了多个时辰，请明确选择其中一个。',
          if (ambiguousRule)
            '你提到了两种起课口径，请明确选择其中一种。',
          if (invalidParameterErrors.isNotEmpty)
            '以下信息需要更正：${invalidParameterErrors.join('；')}。',
          '请提供公历日期、一个时辰（子时至亥时）和明确的起课口径：通行掌诀，或《多能鄙事》卷八。',
          '两种口径的月初一落宫规则不同；App 会按你明确选择的口径计算，不会替你默认选择。',
          '例如：公历日期：2026-11-14；时辰：午时；起课口径：通行掌诀。',
          '结果属于传统民俗文化参考，不是事实预测或吉凶指令，不用于医疗、法律、投资或其他重要决策。',
        ].join('\n');
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.argumentValidation,
          status: AiTraceStatus.notStarted,
          toolId: tool.id,
          errorCode: 'XIAOLIUREN_PARAMETERS_INCOMPLETE',
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.businessExecution,
          status: AiTraceStatus.notStarted,
          toolId: tool.id,
          errorCode: 'AWAITING_PARAMETERS',
        );
        setState(() {
          _lastEffectiveMode = activeMode;
          _messages
            ..add(_InterviewMessage(text: userText, isUser: true))
            ..add(_InterviewMessage(text: clarification, isUser: false));
          _error = null;
        });
        _inputController.clear();
        final persisted = await _persistSuccessfulTurn(
          userText: userText,
          assistantText: clarification,
          mode: activeMode,
          toolId: tool.id,
          toolStatus: 'AWAITING_PARAMETERS',
          toolArguments: request.values,
          traceId: activeTraceContext.traceId,
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.persistence,
          status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
          toolId: tool.id,
          errorCode: persisted ? null : 'PERSISTENCE_FAILED',
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.succeeded,
          toolId: tool.id,
        );
        _scrollToBottom();
        return;
      }
      _pendingXiaoliurenArguments = null;
      await _executeHeadlessTool(
        userText,
        tool,
        mode: activeMode,
        traceContext: activeTraceContext,
        arguments: request,
      );
      return;
    }

    if (tool.id == 'yijing' && tool.headlessExecutor != null) {
      var request = arguments ?? AssistantToolArguments(toolId: tool.id);
      final method = request['method'];
      // Device time and random coin outcomes are generated only by the App,
      // after the user explicitly selects one of these methods.
      if (method == 'time' || method == 'coins') {
        request = AssistantToolArguments(
          toolId: 'yijing',
          values: YiJingToolExecutor.prepareExecutionArguments(request.values),
        );
      }
      final argumentErrors = request.validateAgainst(tool);
      final missingParameters = <String>[];
      if (method == null || method.isEmpty || method == 'AMBIGUOUS_METHOD_SELECTION') {
        missingParameters.add('起卦方式');
      } else if (method == 'number') {
        if (request['first']?.trim().isNotEmpty != true) {
          missingParameters.add('第一数');
        }
        if (request['second']?.trim().isNotEmpty != true) {
          missingParameters.add('第二数');
        }
      } else if (method == 'manual') {
        if (request['upper']?.trim().isNotEmpty != true) {
          missingParameters.add('上卦');
        }
        if (request['lower']?.trim().isNotEmpty != true) {
          missingParameters.add('下卦');
        }
        if (request['moving']?.trim().isNotEmpty != true) {
          missingParameters.add('动爻（或明确说明静卦）');
        }
      }
      final needsClarification =
          argumentErrors.isNotEmpty || missingParameters.isNotEmpty;
      if (needsClarification) {
        _pendingYiJingArguments = request;
        _pendingXiaoliurenArguments = null;
        _pendingMeihuaArguments = null;
        _pendingChengguArguments = null;
        _pendingHuangdiSijiArguments = null;
        _pendingBaziArguments = null;
        _pendingZiweiArguments = null;
        final methodLabel = switch (method) {
          'number' => '数字起卦',
          'time' => '当前时间起卦',
          'manual' => '手动选卦',
          'coins' => '铜钱摇卦',
          _ => null,
        };
        final suppliedParameters = <String>[
          if (methodLabel != null) '起卦方式：$methodLabel',
          if (method == 'number' && request['first'] != null)
            '第一数：${request['first']}',
          if (method == 'number' && request['second'] != null)
            '第二数：${request['second']}',
          if (method == 'manual' && request['upper'] != null)
            '上卦先天数：${request['upper']}',
          if (method == 'manual' && request['lower'] != null)
            '下卦先天数：${request['lower']}',
          if (method == 'manual' && request['moving'] != null)
            '动爻：${request['moving']}',
        ];
        final invalidParameterErrors = argumentErrors
            .where((error) =>
                !error.startsWith('缺少必填参数：') &&
                !error.startsWith('未声明的参数：'))
            .toList(growable: false);
        final clarification = [
          '我会在当前对话中调用 App 原有易经引擎，不需要打开工具页面。',
          if (suppliedParameters.isNotEmpty)
            '已识别的信息：${suppliedParameters.join('；')}。',
          if (missingParameters.isNotEmpty)
            '目前还缺少：${missingParameters.join('、')}。',
          if (method == null || method == 'AMBIGUOUS_METHOD_SELECTION')
            '请明确选择一种方式：数字起卦、按当前时间起卦、手动选卦或铜钱摇卦；一次只执行一种方式。',
          if (method == 'number')
            '数字起卦需要两个非负整数，可以分两轮补充，例如“第一数：3”“第二数：7”。',
          if (method == 'time')
            '按当前时间起卦会由 App 读取本机当前本地日期和时间，并把实际时刻写入结果与历史。',
          if (method == 'manual')
            '手动选卦需要上卦、下卦（先天数 1–8 或乾、兑、离、震、巽、坎、艮、坤）以及动爻 0–6；静卦请明确说“静卦”。',
          if (method == 'coins')
            '铜钱摇卦的六次投掷由 App 随机生成并保存真实六爻值；AI 不生成随机结果，历史回放使用同一组投掷值。',
          if (invalidParameterErrors.isNotEmpty)
            '以下信息需要更正：${invalidParameterErrors.join('；')}。',
          '易经结果属于传统文化学习参考，不是科学预测或确定性结论，不用于医疗、法律或投资决策。',
        ].join('\n');
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.argumentValidation,
          status: AiTraceStatus.notStarted,
          toolId: tool.id,
          errorCode: 'YIJING_PARAMETERS_INCOMPLETE',
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.businessExecution,
          status: AiTraceStatus.notStarted,
          toolId: tool.id,
          errorCode: 'AWAITING_PARAMETERS',
        );
        setState(() {
          _lastEffectiveMode = activeMode;
          _messages
            ..add(_InterviewMessage(text: userText, isUser: true))
            ..add(_InterviewMessage(text: clarification, isUser: false));
          _error = null;
        });
        _inputController.clear();
        final persisted = await _persistSuccessfulTurn(
          userText: userText,
          assistantText: clarification,
          mode: activeMode,
          toolId: tool.id,
          toolStatus: 'AWAITING_PARAMETERS',
          toolArguments: request.values,
          traceId: activeTraceContext.traceId,
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.persistence,
          status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
          toolId: tool.id,
          errorCode: persisted ? null : 'PERSISTENCE_FAILED',
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.succeeded,
          toolId: tool.id,
        );
        _scrollToBottom();
        return;
      }
      _pendingDosageArguments = null;
      await _executeHeadlessTool(
        userText,
        tool,
        mode: activeMode,
        traceContext: activeTraceContext,
        arguments: request,
      );
      return;
    }

    final hasExplicitHeadlessDate = arguments?.values.containsKey('date') == true;
    if (tool.headlessExecutor != null && hasExplicitHeadlessDate) {
      await _executeHeadlessTool(
        userText,
        tool,
        mode: activeMode,
        traceContext: activeTraceContext,
        arguments: arguments,
      );
      return;
    }
    await _traceRecorder.record(
      activeTraceContext,
      stage: AiTraceStage.toolExecution,
      status: AiTraceStatus.notStarted,
      toolId: tool.id,
      route: 'page_tool',
    );
    final instruction =
        '已识别到你要使用「${tool.title}」。${tool.description}'
        '实际计算由 App 内置工具执行，不由模型猜测结果。点击下方按钮打开；完成后返回本对话，我会继续解释结果。';
    setState(() {
      _lastEffectiveMode = activeMode;
      _messages
        ..add(_InterviewMessage(text: userText, isUser: true))
        ..add(_InterviewMessage(
          text: instruction,
          isUser: false,
          actionLabel: '打开${tool.title}',
          onAction: () => _openTool(
            tool,
            mode: activeMode,
            arguments: arguments,
            traceContext: activeTraceContext,
          ),
        ));
      _error = null;
    });
    _inputController.clear();
    final persisted = await _persistSuccessfulTurn(
      userText: userText,
      assistantText: instruction,
      mode: activeMode,
      toolId: tool.id,
      toolArguments: arguments?.values ?? const {},
      traceId: activeTraceContext.traceId,
    );
    await _traceRecorder.record(
      activeTraceContext,
      stage: AiTraceStage.persistence,
      status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
      toolId: tool.id,
      errorCode: persisted ? null : 'PERSISTENCE_FAILED',
    );
    await _traceRecorder.record(
      activeTraceContext,
      stage: AiTraceStage.finalRender,
      status: AiTraceStatus.succeeded,
      toolId: tool.id,
    );
    _scrollToBottom();
  }

  Future<void> _restoreVisibleConversationToModel() async {
    if (_status?.ready != true) return;
    final transcriptLines = _messages
        .map((message) => '${message.isUser ? '用户' : '助手'}：${message.text}')
        .toList(growable: false);
    final fullTranscript = transcriptLines.join('\n');
    final transcript = fullTranscript.length > 10000
        ? '【较早历史已省略，以下为最近内容】\n'
            '${fullTranscript.substring(fullTranscript.length - 10000)}'
        : fullTranscript;
    final userMessages = _messages
        .where((message) => message.isUser)
        .map((message) => message.text)
        .toList(growable: false);
    await _service.restoreConversation(
      transcript: transcript,
      userMessages: userMessages,
    );
  }

  Future<void> _requestAssistantResultInterpretation({
    required String prompt,
    required AssistantMode mode,
    String? retrievalQuery,
    String? toolId,
    String? toolStatus,
    List<String> sourceIds = const [],
    bool showPromptInTimeline = true,
    bool allowWhileSending = false,
    bool restoreVisibleConversation = true,
  }) async {
    if ((_sending && !allowWhileSending) ||
        _modelControlBusy ||
        _structuredDiagnosisBusy) {
      return;
    }
    if (_status?.ready != true || _statusUnknown) {
      if (mounted) {
        setState(() => _error = '本地模型尚未就绪，无法生成结果解释；请先确认模型状态。');
      }
      return;
    }
    final normalizedPrompt = prompt.trim();
    if (normalizedPrompt.isEmpty) return;

    final traceContext = _traceRecorder.start(
      stage: AiTraceStage.input,
      route: 'result_interpretation',
      mode: mode.name,
    );
    var inferenceCompleted = false;
    try {
      // Ensure the immediately preceding deterministic result is part of the
      // native model context before adding this explicit user-requested action.
      if (restoreVisibleConversation) {
        await _restoreVisibleConversationToModel();
      }
      if (!mounted) return;
      setState(() {
        _lastEffectiveMode = mode;
        if (showPromptInTimeline) {
          _messages.add(_InterviewMessage(
            text: normalizedPrompt,
            isUser: true,
          ));
        }
        _sending = true;
        _error = null;
      });
      _scrollToBottom();
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.succeeded,
        route: 'result_interpretation',
        mode: mode.name,
        toolId: toolId,
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.dispatch,
        status: AiTraceStatus.succeeded,
        route: 'result_interpretation',
        mode: mode.name,
        toolId: toolId,
      );

      final response = await _sendTextWithKnowledgeContext(
        normalizedPrompt,
        mode: mode,
        traceContext: traceContext,
        retrievalQuery: retrievalQuery,
      );
      inferenceCompleted = true;
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.nativeInference,
        status: AiTraceStatus.succeeded,
        mode: mode.name,
        toolId: toolId,
      );
      final mergedSourceIds = <String>{
        ...sourceIds,
        ...response.sourceIds,
      }.toList(growable: false);
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.modelOutput,
        status: AiTraceStatus.succeeded,
        mode: mode.name,
        toolId: toolId,
        sourceIds: mergedSourceIds,
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.resultValidation,
        status: AiTraceStatus.succeeded,
        mode: mode.name,
        toolId: toolId,
        sourceIds: mergedSourceIds,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(_InterviewMessage(
          text: response.text,
          isUser: false,
          sourceIds: response.sourceIds,
          onSourceTap: _openKnowledgeSource,
          knowledgeStatus: response.knowledgeStatus,
        ));
      });
      final persisted = await _persistSuccessfulTurn(
        userText: showPromptInTimeline ? normalizedPrompt : '',
        assistantText: response.text,
        mode: mode,
        toolId: toolId,
        toolStatus: toolStatus,
        sourceIds: mergedSourceIds,
        knowledgeStatus: response.knowledgeStatus,
        traceId: traceContext.traceId,
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.persistence,
        status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
        mode: mode.name,
        toolId: toolId,
        sourceIds: mergedSourceIds,
        errorCode: persisted ? null : 'PERSISTENCE_FAILED',
      );
      if (mounted) _scrollToBottom();
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.finalRender,
        status: mounted ? AiTraceStatus.succeeded : AiTraceStatus.notApplicable,
        mode: mode.name,
        toolId: toolId,
        sourceIds: mergedSourceIds,
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'AI 结果解释未完成：$error');
      }
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.nativeInference,
        status: inferenceCompleted ? AiTraceStatus.succeeded : AiTraceStatus.unknown,
        mode: mode.name,
        toolId: toolId,
        errorCode: inferenceCompleted ? null : 'RESULT_INTERPRETATION_FAILED',
      );
      if (!inferenceCompleted) {
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.resultValidation,
          status: AiTraceStatus.notStarted,
          mode: mode.name,
          toolId: toolId,
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.persistence,
          status: AiTraceStatus.notStarted,
          mode: mode.name,
          toolId: toolId,
          errorCode: 'RESULT_INTERPRETATION_NOT_PERSISTED',
        );
      }
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.finalRender,
        status: mounted ? AiTraceStatus.succeeded : AiTraceStatus.notApplicable,
        mode: mode.name,
        toolId: toolId,
        errorCode: 'RESULT_INTERPRETATION_FAILED',
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _openKnowledgeSource(String sourceId) async {
    final parts = sourceId.split(':');
    if (parts.isEmpty || !mounted) return;
    Widget? destination;
    String? unavailableMessage;
    try {
      switch (parts.first) {
        case 'formula':
          if (parts.length < 2) break;
          await FormulaRepository.load();
          final matches = FormulaRepository.getAll()
              .where((item) => item.id == parts.sublist(1).join(':'));
          if (matches.isNotEmpty) {
            destination = FormulaDetailScreen(formula: matches.first);
          }
          break;
        case 'herb':
          if (parts.length < 2) break;
          await HerbRepository.load();
          final name = parts.sublist(1).join(':');
          final matches = HerbRepository.getAll().where((item) => item.name == name);
          if (matches.isNotEmpty) destination = HerbDetailScreen(herb: matches.first);
          break;
        case 'acupoint':
          if (parts.length < 2) break;
          await AcupointRepository.load();
          final name = parts.sublist(1).join(':');
          final matches = AcupointRepository.getAll().where((item) => item.name == name);
          if (matches.isNotEmpty) {
            destination = AcupointDetailScreen(acupoint: matches.first);
          }
          break;
        case 'acupuncture':
          if (parts.length < 3) break;
          await AcupunctureRepository.load();
          final categoryId = parts[1];
          final entryId = int.tryParse(parts.sublist(2).join(':'));
          if (entryId == null) break;
          final categories = AcupunctureRepository.getAll();
          final categoryMatches =
              categories.where((category) => category.id == categoryId);
          if (categoryMatches.isEmpty) break;
          final entryMatches = categoryMatches.first.entries
              .where((entry) => entry.id == entryId);
          if (entryMatches.isEmpty) break;
          destination = Scaffold(
            appBar: AppBar(title: Text('针灸来源：${entryMatches.first.symptom}')),
            body: AcupunctureScreen(
              initialCategoryId: categoryId,
              initialEntryId: entryId,
            ),
          );
          break;
        case 'medical_case':
          if (parts.length < 2) break;
          final sequence = int.tryParse(parts.sublist(1).join(':'));
          if (sequence == null) break;
          final cases = await getAllMedicalCases();
          final matches = cases.where((item) => item.seq == sequence);
          if (matches.isNotEmpty) {
            destination = MedicalCaseDetailScreen(c: matches.first, allCases: cases);
          }
          break;
        case 'neijing':
          final hit = await ClassicSearchService.findBySourceId(sourceId);
          if (hit?.asset != null) {
            destination = MarkdownDocScreen(title: hit!.title, asset: hit.asset!);
          } else if (hit?.bookId != null && hit?.chapterIndex != null) {
            destination = const GujiLibraryScreen();
            unavailableMessage = '已打开对应古籍书库；该来源的章节级深链尚未接入。';
          } else {
            // Structured Neijing IDs resolve through the local entry catalog;
            // classic lecture IDs resolve through ClassicSearchService above.
            destination = const NeijingKnowledgeScreen();
          }
          break;
        case 'shanghan':
        case 'jingui':
        case 'guji':
        case 'zhenjiu':
          final hit = await ClassicSearchService.findBySourceId(sourceId);
          if (hit == null) break;
          if (hit.asset != null) {
            destination = MarkdownDocScreen(title: hit.title, asset: hit.asset!);
          } else if (hit.bookId != null && hit.chapterIndex != null) {
            destination = const GujiLibraryScreen();
            unavailableMessage = '已打开对应古籍书库；该来源的章节级深链尚未接入。';
          }
          break;
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '来源打开失败：$error');
      }
      return;
    }
    if (!mounted) return;
    if (destination == null) {
      setState(() => _error = '该来源仍有可追溯标识，但没有可用的页面定位：$sourceId');
      return;
    }
    await Navigator.push<void>(
      context,
      FoldAwareMaterialPageRoute(
        sourceContext: context,
        builder: (_) => destination!,
      ),
    );
    if (mounted && unavailableMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(unavailableMessage)),
      );
    }
  }

  Future<void> _openTool(
    AssistantToolDefinition tool, {
    required AssistantMode mode,
    AssistantToolArguments? arguments,
    AiTraceContext? traceContext,
    bool pageOwnsInput = false,
  }) async {
    final activeTraceContext =
        traceContext ?? const AiTraceContext.disabled();
    if (tool.id == 'structured_diagnosis') {
      await _startInlineTcmInterview(
        initialUserMessage: '继续规则辨证',
        traceContext: traceContext,
      );
      return;
    }
    // Every execution path (including quick actions with no extracted args)
    // must pass the same contract. Otherwise required parameters can be
    // bypassed simply by opening a tool from a shortcut.
    final toolArguments =
        arguments ?? AssistantToolArguments(toolId: tool.id);
    if (!pageOwnsInput) {
      final errors = toolArguments.validateAgainst(tool);
      if (errors.isNotEmpty) {
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.argumentValidation,
          status: AiTraceStatus.failed,
          toolId: tool.id,
          errorCode: 'INVALID_ARGUMENTS',
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.toolExecution,
          status: AiTraceStatus.notStarted,
          toolId: tool.id,
          errorCode: 'ARGUMENT_VALIDATION_FAILED',
        );
        if (mounted) {
          setState(() => _error = '工具参数未通过校验：${errors.join('；')}');
        }
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.finalRender,
          status: mounted ? AiTraceStatus.succeeded : AiTraceStatus.notApplicable,
          toolId: tool.id,
          errorCode: 'INVALID_ARGUMENTS',
        );
        return;
      }
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.argumentValidation,
        status: AiTraceStatus.succeeded,
        toolId: tool.id,
      );
    } else {
      // Time/random Meihua methods collect their own inputs in the legacy
      // page. Headless number parameters must not block this separate method.
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.argumentValidation,
        status: AiTraceStatus.notApplicable,
        toolId: tool.id,
        errorCode: 'PAGE_OWNS_METHOD_INPUT',
      );
    }
    if (_toolRouteActive) {
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.toolExecution,
        status: AiTraceStatus.notStarted,
        toolId: tool.id,
        errorCode: 'TOOL_ROUTE_ALREADY_ACTIVE',
      );
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.succeeded,
        toolId: tool.id,
        errorCode: 'TOOL_ROUTE_ALREADY_ACTIVE',
      );
      return;
    }
    _toolRouteActive = true;
    _pendingToolSelection = false;
    _pendingBaziArguments = null;
    _pendingZiweiArguments = null;
    _pendingMeihuaArguments = null;
    Object? result;
    try {
      result = await Navigator.push<Object?>(

        context,
        FoldAwareMaterialPageRoute(
          sourceContext: context,
          builder: (_) => _AssistantToolRouteGuard(
            cancellationResult: AssistantToolResult(
              toolId: tool.id,
              title: tool.title,
              values: const {},
              status: AssistantToolExecutionStatus.cancelled,
              disclaimer: '用户退出工具页面，未提交执行结果。',
            ),
            child: widget.testToolRouteBuilder?.call(tool, toolArguments) ??
                (tool.builderWithArguments != null
                    ? tool.builderWithArguments!(toolArguments)
                    : tool.builder()),
          ),
        ),
      );
    } catch (error) {
      result = AssistantToolResult(
        toolId: tool.id,
        title: tool.title,
        status: AssistantToolExecutionStatus.failed,
        values: const {'错误': 'MISSING'},
        disclaimer: '工具页面执行异常：$error',
      );
    } finally {
      _toolRouteActive = false;
    }
    if (!mounted) {
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.toolExecution,
        status: AiTraceStatus.unknown,
        toolId: tool.id,
        errorCode: 'PAGE_RESULT_RECEIVED_AFTER_DISPOSE',
      );
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.resultValidation,
        status: AiTraceStatus.notApplicable,
        toolId: tool.id,
      );
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.persistence,
        status: AiTraceStatus.notStarted,
        toolId: tool.id,
        errorCode: 'SCREEN_DISPOSED',
      );
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.notApplicable,
        toolId: tool.id,
      );
      return;
    }
    if (result is AssistantToolResult) {
      final errors = result.validateFor(tool.id);
      if (errors.isNotEmpty) {
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.toolExecution,
          status: AiTraceStatus.unknown,
          toolId: tool.id,
          errorCode: 'PAGE_TOOL_RESULT_INVALID',
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.resultValidation,
          status: AiTraceStatus.failed,
          toolId: tool.id,
          errorCode: 'RESULT_CONTRACT_INVALID',
        );
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.persistence,
          status: AiTraceStatus.notStarted,
          toolId: tool.id,
          errorCode: 'RESULT_CONTRACT_INVALID',
        );
        setState(() => _error = '工具返回结果未通过契约校验：' + errors.join('；'));
        await _traceRecorder.record(
          activeTraceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.succeeded,
          toolId: tool.id,
          errorCode: 'RESULT_CONTRACT_INVALID',
        );
        return;
      }
    }
    final normalizedResult = (switch (result) {
      AssistantToolResult typed => typed,
      String legacy when legacy.trim().isNotEmpty => AssistantToolResult(
          toolId: tool.id,
          title: tool.title,
          values: {'结果': legacy.trim()},
          // The page returned a concrete result string from this registered
          // App tool. Record its route as provenance; do not mislabel it as an
          // engine or knowledge-base source.
          sourceIds: ['local-page-tool:${tool.id}'],
        ),
      _ => AssistantToolResult(
          toolId: tool.id,
          title: tool.title,
          status: AssistantToolExecutionStatus.noResult,
          values: const {'返回内容': 'MISSING'},
          disclaimer: '工具页面退出时未返回结构化结果；无法区分用户取消与旧页面未实现回传。',
        ),
    }).withArguments(toolArguments.values);
    final executionStatus = switch (normalizedResult.status) {
      AssistantToolExecutionStatus.succeeded => AiTraceStatus.succeeded,
      AssistantToolExecutionStatus.noResult => AiTraceStatus.unknown,
      AssistantToolExecutionStatus.failed => AiTraceStatus.failed,
      AssistantToolExecutionStatus.cancelled => AiTraceStatus.notStarted,
      AssistantToolExecutionStatus.unknown => AiTraceStatus.unknown,
    };
    await _traceRecorder.record(
      activeTraceContext,
      stage: AiTraceStage.toolExecution,
      status: executionStatus,
      toolId: tool.id,
      sourceIds: normalizedResult.sourceIds,
    );
    await _traceRecorder.record(
      activeTraceContext,
      stage: AiTraceStage.businessExecution,
      status: executionStatus,
      toolId: tool.id,
      sourceIds: normalizedResult.sourceIds,
    );
    final argumentErrors =
        normalizedResult.validateArgumentsMatch(toolArguments.values);
    if (argumentErrors.isNotEmpty) {
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.resultValidation,
        status: AiTraceStatus.failed,
        toolId: tool.id,
        errorCode: 'RESULT_ARGUMENTS_MISMATCH',
      );
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.persistence,
        status: AiTraceStatus.notStarted,
        toolId: tool.id,
        errorCode: 'RESULT_ARGUMENTS_MISMATCH',
      );
      setState(() => _error = '工具返回参数未通过契约校验：' + argumentErrors.join('；'));
      await _traceRecorder.record(
        activeTraceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.succeeded,
        toolId: tool.id,
        errorCode: 'RESULT_ARGUMENTS_MISMATCH',
      );
      return;
    }
    await _traceRecorder.record(
      activeTraceContext,
      stage: AiTraceStage.resultValidation,
      status: AiTraceStatus.succeeded,
      toolId: tool.id,
      sourceIds: normalizedResult.sourceIds,
    );
    final resultText = normalizedResult.toConversationText();
    final response = '【' + tool.title + '执行结果】\\n' + resultText;
    final canRetry = normalizedResult.status ==
        AssistantToolExecutionStatus.failed;
    final canInterpret = normalizedResult.status ==
            AssistantToolExecutionStatus.succeeded &&
        normalizedResult.sourceIds.isNotEmpty;
    final autoInterpret = canInterpret && _status?.ready == true && !_statusUnknown;
    final needsTcmKnowledge = _needsTcmKnowledgeForTool(mode, tool.id);
    final interpretationPrompt = '请总结并解释刚才返回的“${tool.title}”执行结果。'
        '先概括本次实际输入、关键输出和执行状态，再解释主要字段的含义、字段间关系及结果口径；'
        '明确区分 App 本地工具计算/数据原文与 AI 的语言化归纳。'
        '如果本地知识库返回了相关资料，请结合实际命中条目解释；'
        '未返回或缺失的字段标记 MISSING，不猜算、不改写 App 已返回的结果。';
    setState(() {
      _messages.add(_InterviewMessage(
        text: response,
        isUser: false,
        sourceIds: normalizedResult.sourceIds,
        actionLabel: canRetry
            ? '重试${tool.title}'
            : canInterpret && !autoInterpret
                ? 'AI总结解读'
                : null,
        onAction: canRetry
            ? () => unawaited(_openTool(
                  tool,
                  mode: mode,
                  arguments: toolArguments,
                  traceContext: activeTraceContext,
                ))
            : canInterpret && !autoInterpret
                ? () => unawaited(_requestAssistantResultInterpretation(
                      prompt: interpretationPrompt,
                      mode: mode,
                      retrievalQuery: needsTcmKnowledge
                          ? '${tool.title} $resultText'
                          : null,
                      toolId: tool.id,
                      toolStatus: normalizedResult.statusLabel,
                      sourceIds: normalizedResult.sourceIds,
                    ))
                : null,
      ));
    });
    int? conversationId;
    var persistenceStarted = false;
    var persistenceStatus = AiTraceStatus.notStarted;
    String? persistenceErrorCode;
    try {
      conversationId = await _conversationIdFuture;
      if (conversationId != null) {
        persistenceStarted = true;
        await _conversationStore.saveAssistantMessage(
          conversationId: conversationId,
          role: 'assistant',
          content: response,
          metadata: AssistantMessageMetadata(
            mode: mode.name,
            selectedMode: _assistantMode.name,
            toolId: tool.id,
            toolStatus: normalizedResult.statusLabel,
            sourceIds: normalizedResult.sourceIds,
            toolArguments: normalizedResult.arguments,
            traceId: activeTraceContext.traceId,
          ).encode(),
        );
        persistenceStatus = AiTraceStatus.succeeded;
      } else {
        persistenceErrorCode = 'CONVERSATION_UNAVAILABLE';
      }
    } catch (error) {
      persistenceStatus = persistenceStarted
          ? AiTraceStatus.unknown
          : AiTraceStatus.notStarted;
      persistenceErrorCode = persistenceStarted
          ? 'TOOL_RESULT_PERSISTENCE_UNKNOWN'
          : 'CONVERSATION_UNAVAILABLE';
      debugPrint('[AssistantHistory] 保存工具结果失败：$error');
    }
    await _traceRecorder.record(
      activeTraceContext,
      stage: AiTraceStage.persistence,
      status: persistenceStatus,
      conversationId: conversationId,
      toolId: tool.id,
      sourceIds: normalizedResult.sourceIds,
      errorCode: persistenceErrorCode,
    );
    await _traceRecorder.record(
      activeTraceContext,
      stage: AiTraceStage.persistedState,
      status: persistenceStatus,
      conversationId: conversationId,
      toolId: tool.id,
      sourceIds: normalizedResult.sourceIds,
      errorCode: persistenceErrorCode,
    );
    String? finalRenderErrorCode;
    try {
      // Automatic interpretation restores the same verified result in its
      // own traced call. Other result states still synchronize the normal context.
      if (!autoInterpret) {
        await _restoreVisibleConversationToModel();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '工具结果已加入对话记录，但同步到本地模型上下文失败：$error';
        });
      }
      finalRenderErrorCode = 'MODEL_CONTEXT_RESTORE_FAILED';
    }
    if (mounted) _scrollToBottom();
    await _traceRecorder.record(
      activeTraceContext,
      stage: AiTraceStage.finalRender,
      status: mounted ? AiTraceStatus.succeeded : AiTraceStatus.notApplicable,
      conversationId: conversationId,
      toolId: tool.id,
      sourceIds: normalizedResult.sourceIds,
      errorCode: finalRenderErrorCode,
    );
    if (autoInterpret && mounted) {
      await _requestAssistantResultInterpretation(
        prompt: interpretationPrompt,
        mode: mode,
        retrievalQuery: needsTcmKnowledge
            ? _tcmToolKnowledgeQueryForResult('', tool)
            : null,
        toolId: tool.id,
        toolStatus: normalizedResult.statusLabel,
        sourceIds: normalizedResult.sourceIds,
        showPromptInTimeline: false,
        allowWhileSending: true,
      );
    }

    // A validated result remains useful in the current timeline even when its
    // SQLite write is unavailable. Do not silently equate that with history
    // persistence, and never re-run a tool whose write outcome is unknown.
    if (mounted && persistenceStatus != AiTraceStatus.succeeded) {
      final existingError = _error?.trim();
      final persistenceWarning = switch (persistenceErrorCode) {
        'CONVERSATION_UNAVAILABLE' =>
          '工具结果已在当前对话显示，但当前会话不可用，未能写入历史记录。离开前请先复制结果。',
        'TOOL_RESULT_PERSISTENCE_UNKNOWN' =>
          '工具结果已在当前对话显示，但历史保存状态未知。为避免可能重复执行工具，本次未自动重跑；请先复制结果并核对历史记录。',
        _ =>
          '工具结果已在当前对话显示，但历史保存未确认（${persistenceErrorCode ?? 'UNKNOWN'}）。请先复制结果并核对历史记录。',
      };
      setState(() {
        _error = [
          if (existingError != null && existingError.isNotEmpty) existingError,
          persistenceWarning,
        ].join('\n\n');
      });
    }
  }

  Widget _buildModeSelector(BuildContext context) {
    final tools = AssistantToolRouter.quickActions(_assistantMode);
    final busy = _sending || _modelControlBusy || _structuredDiagnosisBusy;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, 0),
      child: Wrap(
        key: const ValueKey('assistant-mode-selector'),
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: [
          PopupMenuButton<AssistantMode>(
            tooltip: '切换助手角色',
            enabled: !busy,
            onSelected: (mode) => setState(() {
              _assistantMode = mode;
              if (mode != AssistantMode.automatic) {
                _lastEffectiveMode = mode;
              }
              _pendingToolSelection = false;
              _pendingBaziArguments = null;
              _pendingZiweiArguments = null;
              _pendingMeihuaArguments = null;
              _pendingChengguArguments = null;
              _pendingHuangdiSijiArguments = null;
            }),
            itemBuilder: (context) => [
              for (final mode in AssistantMode.values)
                PopupMenuItem<AssistantMode>(
                  value: mode,
                  child: Text(mode.label),
                ),
            ],
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome, size: 16),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      _assistantMode.label,
                      style: const TextStyle(
                        fontSize: AppType.caption,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    const Icon(Icons.expand_more, size: 17),
                  ],
                ),
              ),
            ),
          ),
          PopupMenuButton<AssistantToolDefinition>(
            tooltip: '调用 App 工具',
            enabled: !busy && tools.isNotEmpty,
            onSelected: (tool) => _requestTool('打开${tool.title}', tool),
            itemBuilder: (context) => [
              for (final tool in tools)
                PopupMenuItem<AssistantToolDefinition>(
                  value: tool,
                  child: Text(tool.title),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.apps_outlined, size: 18),
                  SizedBox(width: AppSpacing.xs),
                  Text('入口', style: TextStyle(fontSize: AppType.caption)),
                  Icon(Icons.expand_more, size: 17),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }



  Future<void> _openHistory() async {
    final generation = ++_historyRestoreGeneration;
    final selectedId = await Navigator.push<int>(
      context,
      FoldAwareMaterialPageRoute(
        sourceContext: context,
        builder: (_) => AssistantHistoryScreen(
          loadConversations: _conversationStore.getAssistantConversations,
          deleteConversations: _conversationStore.deleteAssistantConversations,
        ),
      ),
    );
    if (!mounted || generation != _historyRestoreGeneration || selectedId == null) return;

    final rows = await _conversationStore.getAssistantMessages(
      conversationId: selectedId,
    );
    if (!mounted || generation != _historyRestoreGeneration) return;
    TcmInterviewTaskState? taskState;
    try {
      taskState = await _conversationStore.getTcmInterviewTaskState(
        conversationId: selectedId,
      );
    } catch (error, stack) {
      debugPrint('[AssistantHistory] 结构化问诊状态读取失败：$error\n$stack');
    }
    if (!mounted || generation != _historyRestoreGeneration) return;
    final transcriptLines = <String>[];
    final replayableUserMessages = <String>[];
    final restoredMessages = <_InterviewMessage>[];
    var restoredMode = _assistantMode;
    var restoredEffectiveMode = _lastEffectiveMode;
    var restoredPendingToolSelection = false;
    AssistantToolArguments? restoredPendingBaziArguments;
    AssistantToolArguments? restoredPendingZiweiArguments;
    AssistantToolArguments? restoredPendingMeihuaArguments;
    AssistantToolArguments? restoredPendingChengguArguments;
    AssistantToolArguments? restoredPendingHuangdiSijiArguments;
    AssistantToolArguments? restoredPendingXiaoliurenArguments;
    AssistantToolArguments? restoredPendingYiJingArguments;
    AssistantToolArguments? restoredPendingDosageArguments;
    AssistantToolArguments? restoredPendingZiWuArguments;
    AssistantToolArguments? restoredPendingDreamArguments;
    for (final row in rows) {
      final role = row['role'] as String? ?? '';
      final content = row['content'] as String? ?? '';
      final metadata = row['metadata'] as String? ?? '';
      if (content.isEmpty || (role != 'user' && role != 'assistant')) continue;
      final messageMetadata = AssistantMessageMetadata.decode(metadata);
      final selectedModeValue = messageMetadata.selectedMode;
      final effectiveModeValue = messageMetadata.mode;
      final legacyModeValue = selectedModeValue == null ? effectiveModeValue : null;
      AssistantMode? messageEffectiveMode;
      for (final mode in AssistantMode.values) {
        if (mode.name == selectedModeValue || mode.name == legacyModeValue) {
          restoredMode = mode;
        }
        if (mode.name == effectiveModeValue && mode != AssistantMode.automatic) {
          restoredEffectiveMode = mode;
          messageEffectiveMode = mode;
        }
      }
      final isUser = role == 'user';
      if (isUser) {
        restoredPendingToolSelection = false;
        restoredPendingBaziArguments = null;
        restoredPendingZiweiArguments = null;
        restoredPendingMeihuaArguments = null;
        restoredPendingChengguArguments = null;
        restoredPendingHuangdiSijiArguments = null;
        restoredPendingXiaoliurenArguments = null;
        restoredPendingYiJingArguments = null;
        restoredPendingDosageArguments = null;
        restoredPendingZiWuArguments = null;
        restoredPendingDreamArguments = null;
      } else {
        restoredPendingToolSelection = messageMetadata.toolChoicePending;
      }
      final pendingToolId = isUser ? null : messageMetadata.toolId;
      final pendingTool = pendingToolId == null
          ? null
          : AssistantToolRouter.byId(pendingToolId);
      final actionMode = messageEffectiveMode ?? restoredEffectiveMode;
      final completedToolStatus = messageMetadata.toolStatus;
      final retryFailedTool = pendingTool != null &&
          completedToolStatus == AssistantToolExecutionStatus.failed.name.toUpperCase();
      final openPendingTool = pendingTool != null && completedToolStatus == null;
      final restoredToolArguments = pendingTool == null
          ? null
          : AssistantToolArguments(
              toolId: pendingTool.id,
              values: messageMetadata.toolArguments,
            );
      if (!isUser && pendingToolId == 'bazi') {
        restoredPendingBaziArguments =
            completedToolStatus == 'AWAITING_PARAMETERS'
                ? restoredToolArguments
                : null;
      }
      if (!isUser && pendingToolId == 'ziwei') {
        restoredPendingZiweiArguments =
            completedToolStatus == 'AWAITING_PARAMETERS'
                ? restoredToolArguments
                : null;
      }
      if (!isUser && pendingToolId == 'meihua') {
        restoredPendingMeihuaArguments =
            completedToolStatus == 'AWAITING_PARAMETERS'
                ? restoredToolArguments
                : null;
      }
      if (!isUser && pendingToolId == 'chenggu') {
        restoredPendingChengguArguments =
            completedToolStatus == 'AWAITING_PARAMETERS'
                ? restoredToolArguments
                : null;
      }
      if (!isUser && pendingToolId == 'huangdi_siji') {
        restoredPendingHuangdiSijiArguments =
            completedToolStatus == 'AWAITING_PARAMETERS'
                ? restoredToolArguments
                : null;
      }
      if (!isUser && pendingToolId == 'xiaoliuren') {
        restoredPendingXiaoliurenArguments =
            completedToolStatus == 'AWAITING_PARAMETERS'
                ? restoredToolArguments
                : null;
      }
      if (!isUser && pendingToolId == 'yijing') {
        restoredPendingYiJingArguments =
            completedToolStatus == 'AWAITING_PARAMETERS'
                ? restoredToolArguments
                : null;
      }
      if (!isUser && pendingToolId == 'dosage') {
        restoredPendingDosageArguments =
            completedToolStatus == 'AWAITING_PARAMETERS'
                ? restoredToolArguments
                : null;
      }
      if (!isUser && pendingToolId == 'ziwu_liuzhu') {
        restoredPendingZiWuArguments =
            completedToolStatus == 'AWAITING_PARAMETERS'
                ? restoredToolArguments
                : null;
      }
      if (!isUser && pendingToolId == 'dream') {
        restoredPendingDreamArguments =
            completedToolStatus == 'AWAITING_PARAMETERS'
                ? restoredToolArguments
                : null;
      }
      final resolvedActionMode = actionMode ??
          (pendingTool?.modes.contains(AssistantMode.metaphysics) == true
              ? AssistantMode.metaphysics
              : pendingTool?.modes.contains(AssistantMode.tools) == true
                  ? AssistantMode.tools
                  : AssistantMode.consultation);
      final restoredTraceId = messageMetadata.traceId?.trim();
      final restoredTraceContext =
          restoredTraceId == null || restoredTraceId.isEmpty
              ? const AiTraceContext.disabled()
              : AiTraceContext.enabled(
                  traceId: restoredTraceId,
                  startedAt: DateTime.now(),
                );
      restoredMessages.add(_InterviewMessage(
        text: content,
        isUser: isUser,
        sourceIds: isUser ? const [] : messageMetadata.sourceIds,
        onSourceTap: _openKnowledgeSource,
        knowledgeStatus: isUser ? null : messageMetadata.knowledgeStatus,
        actionLabel: retryFailedTool
            ? '重试${pendingTool.title}'
            : openPendingTool
                ? '打开${pendingTool.title}'
                : null,
        onAction: pendingTool == null
            ? null
            : retryFailedTool || openPendingTool
                ? () => _openTool(
                      pendingTool,
                      mode: resolvedActionMode,
                      arguments: restoredToolArguments,
                      traceContext: restoredTraceContext,
                    )
                : null,
      ));
      transcriptLines.add('${isUser ? '用户' : '助手'}：$content');
      if (isUser && messageMetadata.replayable) {
        final attachmentNote = content.indexOf('（另附');
        replayableUserMessages.add(
          attachmentNote > 0 ? content.substring(0, attachmentNote) : content,
        );
      }
    }
    final resumableTask = taskState;
    _tcmInterviewController = null;
    if (resumableTask != null && resumableTask.transcript.isNotEmpty) {
      final lastTaskMessage = resumableTask.transcript.last;
      final taskTranscriptAlreadyVisible = restoredMessages.any(
        (message) =>
            message.isUser == lastTaskMessage.isUser &&
            message.text == lastTaskMessage.text,
      );
      if (!taskTranscriptAlreadyVisible) {
        for (final taskMessage in resumableTask.transcript) {
          restoredMessages.add(_InterviewMessage(
            text: taskMessage.text,
            isUser: taskMessage.isUser,
          ));
          transcriptLines.add(
            '${taskMessage.isUser ? '用户' : '助手'}：${taskMessage.text}',
          );
          if (taskMessage.isUser) replayableUserMessages.add(taskMessage.text);
        }
      }
      if (resumableTask.status == 'in_progress' &&
          resumableTask.pendingPromptId != null &&
          resumableTask.pendingPromptText != null &&
          resumableTask.pendingOptions.isNotEmpty) {
        _tcmInterviewController = TcmInterviewConversationController.restore(
          resumableTask,
          defaultGender: SettingsRepository.instance.defaultGender,
        );
        var promptIndex = -1;
        for (var index = restoredMessages.length - 1; index >= 0; index--) {
          final message = restoredMessages[index];
          if (!message.isUser &&
              message.text == resumableTask.pendingPromptText) {
            promptIndex = index;
            break;
          }
        }
        final prompt = _InterviewMessage(
          text: resumableTask.pendingPromptText!,
          isUser: false,
          options: resumableTask.pendingOptions,
          onOptionSelected: _handleTcmInterviewOption,
        );
        if (promptIndex >= 0) {
          restoredMessages[promptIndex] = prompt;
        } else {
          restoredMessages.add(prompt);
          transcriptLines.add('助手：${resumableTask.pendingPromptText}');
        }
      } else if (resumableTask.status == 'completed' &&
          resumableTask.completedDiagnosis != null) {
        _tcmInterviewController = TcmInterviewConversationController.restore(
          resumableTask,
          defaultGender: SettingsRepository.instance.defaultGender,
        );
        _persistedDiagnosisTaskIds.add(resumableTask.taskId);
        TcmInterviewTaskMessage? resultEntry;
        for (final entry in resumableTask.transcript.reversed) {
          if (entry.isResult) {
            resultEntry = entry;
            break;
          }
        }
        if (resultEntry != null) {
          final resultIndex = restoredMessages.lastIndexWhere(
            (message) => !message.isUser && message.text == resultEntry!.text,
          );
          final resultMessage = _diagnosisActionMessage(
            resultEntry.text,
            resumableTask.completedDiagnosis!,
          );
          if (resultIndex >= 0) {
            restoredMessages[resultIndex] = resultMessage;
          } else {
            restoredMessages.add(resultMessage);
            transcriptLines.add('助手：${resultEntry.text}');
          }
        }
      }
    }
    if (restoredMessages.isEmpty) return;

    final fullTranscript = transcriptLines.join('\n');
    final transcript = fullTranscript.length > 10000
        ? '【较早历史已省略，以下为最近内容】\n'
            '${fullTranscript.substring(fullTranscript.length - 10000)}'
        : fullTranscript;
    setState(() {
      _conversationIdFuture = Future<int?>.value(selectedId);
      _assistantMode = restoredMode;
      _lastEffectiveMode = restoredEffectiveMode;
      _pendingToolSelection = restoredPendingToolSelection;
      _pendingBaziArguments = restoredPendingBaziArguments;
      _pendingZiweiArguments = restoredPendingZiweiArguments;
      _pendingMeihuaArguments = restoredPendingMeihuaArguments;
      _pendingChengguArguments = restoredPendingChengguArguments;
      _pendingHuangdiSijiArguments = restoredPendingHuangdiSijiArguments;
      _pendingXiaoliurenArguments = restoredPendingXiaoliurenArguments;
      _pendingYiJingArguments = restoredPendingYiJingArguments;
      _pendingDosageArguments = restoredPendingDosageArguments;
      _pendingZiWuArguments = restoredPendingZiWuArguments;
      _pendingDreamArguments = restoredPendingDreamArguments;
      _messages
        ..clear()
        ..addAll(restoredMessages);
      _confirmedDraft = null;
      _pendingHistoryTranscript = transcript;
      _pendingHistoryUserMessages = replayableUserMessages;
      _error = _status?.ready == true
          ? null
          : '历史消息已载入。模型加载完成后会自动恢复上下文，再继续对话。';
    });
    if (_status?.ready == true) {
      await _restorePendingHistory();
    }
    _scrollToBottom();
  }

  Future<void> _restorePendingHistory() async {
    final generation = _historyRestoreGeneration;
    final transcript = _pendingHistoryTranscript;
    if (transcript == null || _status?.ready != true) return;
    if (await _blockIfRedFlagPreflightDoesNotClear(
      source: RedFlagInputSource.historyRestore,
      text: transcript,
      traceContext: AiTraceContext.disabled(),
      route: 'history_restore',
    )) {
      return;
    }
    try {
      await _service.restoreConversation(
        transcript: transcript,
        userMessages: _pendingHistoryUserMessages,
      );
      if (!mounted || generation != _historyRestoreGeneration) return;
      setState(() {
        _pendingHistoryTranscript = null;
        _pendingHistoryUserMessages = const [];
        _error = null;
      });
    } catch (error) {
      if (!mounted || generation != _historyRestoreGeneration) return;
      setState(() => _error = '历史记录已显示，但模型上下文恢复失败：$error。请重新选择历史记录重试。');
    }
  }

  Future<void> _recordTurnPersistenceNotStarted(
    AiTraceContext traceContext, {
    required String errorCode,
    String? mode,
  }) async {
    int? conversationId;
    try {
      conversationId = await _conversationIdFuture;
    } catch (_) {
      // The trace still records that no history row was written.
    }
    await _traceRecorder.record(
      traceContext,
      stage: AiTraceStage.persistence,
      status: AiTraceStatus.notStarted,
      conversationId: conversationId,
      mode: mode,
      errorCode: errorCode,
    );
  }

  Future<void> _send() async {
    if (_modelControlBusy) return;
    final text = _inputController.text.trim();
    final imagePath = _imagePath;
    final audioPath = _audioPath;
    if (_sending ||
        _recording ||
        _recordingBusy ||
        _statusUnknown ||
        (text.isEmpty && imagePath == null && audioPath == null)) {
      return;
    }

    final traceContext = _traceRecorder.start(
      stage: AiTraceStage.input,
      route: audioPath != null
          ? 'audio'
          : imagePath != null
              ? 'image'
              : 'text',
      mode: _tcmInterviewController?.canAnswer == true
          ? AssistantMode.consultation.name
          : _assistantMode.name,
    );
    final traceId = traceContext.traceId;
    final activeTcmTask = _tcmInterviewController;
    final inputSource = audioPath != null
        ? RedFlagInputSource.audioAttachment
        : imagePath != null
            ? RedFlagInputSource.imageAttachment
            : activeTcmTask?.canAnswer == true
                ? RedFlagInputSource.structuredInterview
                : RedFlagInputSource.currentText;
    if (await _blockIfRedFlagPreflightDoesNotClear(
      source: inputSource,
      text: text.isEmpty ? null : text,
      traceContext: traceContext,
      route: 'assistant_send',
    )) {
      return;
    }

    if (activeTcmTask?.canAnswer == true) {
      if (imagePath != null || audioPath != null) {
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.route,
          status: AiTraceStatus.failed,
          route: 'structured_interview_attachment_rejected',
          mode: AssistantMode.consultation.name,
          errorCode: 'ATTACHMENT_BLOCKED_DURING_STRUCTURED_INTERVIEW',
        );
        setState(() {
          _error = '请先完成当前结构化问诊步骤，再发送照片或录音；附件不会被转换成规则答案。';
        });
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.succeeded,
          mode: AssistantMode.consultation.name,
        );
        return;
      }
      if (text.isNotEmpty) {
        if (activeTcmTask!.pendingOptions.contains(text)) {
          await _traceRecorder.record(
            traceContext,
            stage: AiTraceStage.route,
            status: AiTraceStatus.succeeded,
            route: 'structured_interview_option',
            mode: AssistantMode.consultation.name,
            toolId: 'structured_diagnosis',
          );
          await _traceRecorder.record(
            traceContext,
            stage: AiTraceStage.dispatch,
            status: AiTraceStatus.succeeded,
            route: 'structured_interview_option',
            mode: AssistantMode.consultation.name,
            toolId: 'structured_diagnosis',
          );
          _inputController.clear();
          await _handleTcmInterviewOption(
            text,
            traceContext: traceContext,
          );
          return;
        }
        const clarification =
            '当前步骤需要使用下方结构化选项。你输入的文字会保留在对话中，但不会自动映射为辨证条件；请从问题下方选择最符合的一项。';
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.route,
          status: AiTraceStatus.succeeded,
          route: 'structured_interview_clarification',
          mode: AssistantMode.consultation.name,
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.dispatch,
          status: AiTraceStatus.succeeded,
          route: 'structured_interview_clarification',
          mode: AssistantMode.consultation.name,
        );
        setState(() {
          _lastEffectiveMode = AssistantMode.consultation;
          _messages
            ..add(_InterviewMessage(text: text, isUser: true))
            ..add(const _InterviewMessage(text: clarification, isUser: false));
          _error = null;
        });
        _inputController.clear();
        final persisted = await _persistSuccessfulTurn(
          userText: text,
          assistantText: clarification,
          mode: AssistantMode.consultation,
          traceId: traceId,
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.persistence,
          status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
          errorCode: persisted ? null : 'PERSISTENCE_FAILED',
          mode: AssistantMode.consultation.name,
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.succeeded,
          mode: AssistantMode.consultation.name,
        );
        _scrollToBottom();
        return;
      }
    }

    final pendingDream = _pendingDreamArguments;
    if (pendingDream != null && (imagePath != null || audioPath != null)) {
      setState(() {
        _error = '周公解梦需要文字描述梦境情节；请用文字补充，或发送“取消解梦”结束本次操作。';
      });
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.failed,
        route: 'tool_follow_up:dream_attachment_rejected',
        mode: (_lastEffectiveMode ?? AssistantMode.metaphysics).name,
        toolId: 'dream',
        errorCode: 'DREAM_DESCRIPTION_REQUIRES_TEXT',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.succeeded,
        mode: (_lastEffectiveMode ?? AssistantMode.metaphysics).name,
        toolId: 'dream',
      );
      return;
    }
    if (pendingDream != null && text.isNotEmpty) {
      final command = text.trim().replaceAll(RegExp(r'[，。.!！?？]+$'), '');
      const cancelCommands = {
        '取消解梦',
        '停止解梦',
        '不用解梦了',
        '算了',
        '取消',
      };
      final cancelRequested = cancelCommands.contains(command);
      final mode = _lastEffectiveMode ?? AssistantMode.metaphysics;
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.succeeded,
        route: cancelRequested ? 'tool_cancel:dream' : 'tool_follow_up:dream',
        mode: mode.name,
        toolId: 'dream',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.dispatch,
        status: AiTraceStatus.succeeded,
        route: cancelRequested ? 'tool_cancel:dream' : 'tool_follow_up:dream',
        mode: mode.name,
        toolId: 'dream',
      );
      if (cancelRequested) {
        const reply = '已取消本次解梦查询；尚未生成新的解释结果。';
        setState(() {
          _pendingDreamArguments = null;
          _messages
            ..add(_InterviewMessage(text: text, isUser: true))
            ..add(const _InterviewMessage(text: reply, isUser: false));
          _error = null;
        });
        _inputController.clear();
        final persisted = await _persistSuccessfulTurn(
          userText: text,
          assistantText: reply,
          mode: mode,
          toolId: 'dream',
          toolStatus: AssistantToolExecutionStatus.cancelled.name.toUpperCase(),
          toolArguments: pendingDream.values,
          traceId: traceId,
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.persistence,
          status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
          toolId: 'dream',
          errorCode: persisted ? null : 'PERSISTENCE_FAILED',
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.succeeded,
          toolId: 'dream',
        );
        _scrollToBottom();
        return;
      }
      final previousDescription = pendingDream['dream_text']?.trim() ?? '';
      final combinedDescription = [
        if (previousDescription.isNotEmpty) previousDescription,
        text,
      ].join('\n补充梦境细节：');
      await _requestTool(
        text,
        AssistantToolRouter.dream,
        mode: mode,
        arguments: AssistantToolArguments(
          toolId: 'dream',
          values: {'dream_text': combinedDescription},
        ),
        traceContext: traceContext,
      );
      return;
    }

    final pendingHuangdiSiji = _pendingHuangdiSijiArguments;
    if (pendingHuangdiSiji != null &&
        (imagePath != null || audioPath != null)) {
      setState(() {
        _error = '黄帝四季歌需要文字出生资料。请补充公历出生日期和当地钟表时间，或发送“取消四季歌”结束本次操作。';
      });
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.failed,
        route: 'tool_follow_up:huangdi_siji_attachment_rejected',
        mode: AssistantMode.metaphysics.name,
        toolId: 'huangdi_siji',
        errorCode: 'HUANGDI_SIJI_PARAMETERS_REQUIRE_TEXT',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.succeeded,
        mode: AssistantMode.metaphysics.name,
        toolId: 'huangdi_siji',
      );
      return;
    }
    if (pendingHuangdiSiji != null && text.isNotEmpty) {
      final cancellationCommand = text
          .trim()
          .replaceAll(RegExp(r'[，。.!！?？]+$'), '');
      final cancelRequested = const {
        '取消四季歌',
        '取消黄帝四季歌',
        '停止查询',
        '先不查',
        '算了',
        '取消',
      }.contains(cancellationCommand);
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.succeeded,
        route: cancelRequested
            ? 'tool_cancel:huangdi_siji'
            : 'tool_follow_up:huangdi_siji',
        mode: AssistantMode.metaphysics.name,
        toolId: 'huangdi_siji',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.dispatch,
        status: AiTraceStatus.succeeded,
        route: cancelRequested
            ? 'tool_cancel:huangdi_siji'
            : 'tool_follow_up:huangdi_siji',
        mode: AssistantMode.metaphysics.name,
        toolId: 'huangdi_siji',
      );
      if (cancelRequested) {
        const reply = '已取消本次黄帝四季歌查询；尚未执行任何查询。';
        setState(() {
          _pendingHuangdiSijiArguments = null;
          _messages
            ..add(_InterviewMessage(text: text, isUser: true))
            ..add(const _InterviewMessage(text: reply, isUser: false));
          _error = null;
        });
        _inputController.clear();
        final persisted = await _persistSuccessfulTurn(
          userText: text,
          assistantText: reply,
          mode: AssistantMode.metaphysics,
          toolId: 'huangdi_siji',
          toolStatus: AssistantToolExecutionStatus.cancelled.name.toUpperCase(),
          toolArguments: pendingHuangdiSiji.values,
          traceId: traceId,
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.persistence,
          status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
          toolId: 'huangdi_siji',
          errorCode: persisted ? null : 'PERSISTENCE_FAILED',
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.succeeded,
          toolId: 'huangdi_siji',
        );
        _scrollToBottom();
        return;
      }
      final followUp = AssistantConversationOrchestrator.argumentsFor(
        AssistantToolRouter.huangdiSiji,
        text,
      );
      final mergedArguments = <String, String>{
        ...pendingHuangdiSiji.values,
        ...followUp.values,
      };
      await _requestTool(
        text,
        AssistantToolRouter.huangdiSiji,
        mode: _lastEffectiveMode ?? AssistantMode.metaphysics,
        arguments: AssistantToolArguments(
          toolId: 'huangdi_siji',
          values: Map<String, String>.unmodifiable(mergedArguments),
        ),
        traceContext: traceContext,
      );
      return;
    }

    final pendingChenggu = _pendingChengguArguments;
    if (pendingChenggu != null && (imagePath != null || audioPath != null)) {
      setState(() {
        _error = '称骨需要文字出生资料。请补充公历出生日期和当地钟表时间，或发送“取消称骨”结束本次操作。';
      });
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.failed,
        route: 'tool_follow_up:chenggu_attachment_rejected',
        mode: AssistantMode.metaphysics.name,
        toolId: 'chenggu',
        errorCode: 'CHENGGU_PARAMETERS_REQUIRE_TEXT',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.succeeded,
        mode: AssistantMode.metaphysics.name,
        toolId: 'chenggu',
      );
      return;
    }
    if (pendingChenggu != null && text.isNotEmpty) {
      final cancelRequested = [
        '取消称骨', '停止称骨', '不用称骨', '先不算', '算了', '取消'
      ].any(text.contains);
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.succeeded,
        route: cancelRequested ? 'tool_cancel:chenggu' : 'tool_follow_up:chenggu',
        mode: AssistantMode.metaphysics.name,
        toolId: 'chenggu',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.dispatch,
        status: AiTraceStatus.succeeded,
        route: cancelRequested ? 'tool_cancel:chenggu' : 'tool_follow_up:chenggu',
        mode: AssistantMode.metaphysics.name,
        toolId: 'chenggu',
      );
      if (cancelRequested) {
        const reply = '已取消本次称骨；尚未执行任何计算。';
        setState(() {
          _pendingChengguArguments = null;
          _pendingHuangdiSijiArguments = null;
          _messages
            ..add(_InterviewMessage(text: text, isUser: true))
            ..add(const _InterviewMessage(text: reply, isUser: false));
          _error = null;
        });
        _inputController.clear();
        final persisted = await _persistSuccessfulTurn(
          userText: text,
          assistantText: reply,
          mode: AssistantMode.metaphysics,
          toolId: 'chenggu',
          toolStatus: AssistantToolExecutionStatus.cancelled.name.toUpperCase(),
          toolArguments: pendingChenggu.values,
          traceId: traceId,
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.persistence,
          status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
          toolId: 'chenggu',
          errorCode: persisted ? null : 'PERSISTENCE_FAILED',
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.succeeded,
          toolId: 'chenggu',
        );
        _scrollToBottom();
        return;
      }
      final followUp = AssistantConversationOrchestrator.argumentsFor(
        AssistantToolRouter.chenggu,
        text,
      );
      final mergedArguments = <String, String>{
        ...pendingChenggu.values,
        ...followUp.values,
      };
      await _requestTool(
        text,
        AssistantToolRouter.chenggu,
        mode: _lastEffectiveMode ?? AssistantMode.metaphysics,
        arguments: AssistantToolArguments(
          toolId: 'chenggu',
          values: Map<String, String>.unmodifiable(mergedArguments),
        ),
        traceContext: traceContext,
      );
      return;
    }

    final pendingMeihua = _pendingMeihuaArguments;
    if (pendingMeihua != null && (imagePath != null || audioPath != null)) {
      setState(() {
        _error = '梅花起卦参数请用文字补充。数字起卦需提供两个正整数；时间或随机起卦请说明对应方式。也可以发送“取消起卦”结束本次操作。';
      });
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.failed,
        route: 'tool_follow_up:meihua_attachment_rejected',
        mode: AssistantMode.metaphysics.name,
        toolId: 'meihua',
        errorCode: 'MEIHUA_PARAMETERS_REQUIRE_TEXT',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.succeeded,
        mode: AssistantMode.metaphysics.name,
        toolId: 'meihua',
      );
      return;
    }
    if (pendingMeihua != null && text.isNotEmpty) {
      final cancelRequested =
          ['取消起卦', '停止起卦', '算了', '先不算', '不用起卦', '取消'].any(text.contains);
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.succeeded,
        route: cancelRequested ? 'tool_cancel:meihua' : 'tool_follow_up:meihua',
        mode: AssistantMode.metaphysics.name,
        toolId: 'meihua',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.dispatch,
        status: AiTraceStatus.succeeded,
        route: cancelRequested ? 'tool_cancel:meihua' : 'tool_follow_up:meihua',
        mode: AssistantMode.metaphysics.name,
        toolId: 'meihua',
      );
      if (cancelRequested) {
        const reply = '已取消本次梅花起卦；尚未执行任何计算。';
        setState(() {
          _pendingMeihuaArguments = null;
          _pendingChengguArguments = null;
          _pendingHuangdiSijiArguments = null;
          _messages
            ..add(_InterviewMessage(text: text, isUser: true))
            ..add(const _InterviewMessage(text: reply, isUser: false));
          _error = null;
        });
        _inputController.clear();
        final persisted = await _persistSuccessfulTurn(
          userText: text,
          assistantText: reply,
          mode: AssistantMode.metaphysics,
          toolId: 'meihua',
          toolStatus: AssistantToolExecutionStatus.cancelled.name.toUpperCase(),
          toolArguments: pendingMeihua.values,
          traceId: traceId,
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.persistence,
          status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
          toolId: 'meihua',
          errorCode: persisted ? null : 'PERSISTENCE_FAILED',
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.succeeded,
          toolId: 'meihua',
        );
        _scrollToBottom();
        return;
      }
      final followUp = AssistantConversationOrchestrator.argumentsFor(
        AssistantToolRouter.meihua,
        text,
      );
      final previousMethod = pendingMeihua['method'];
      final followUpMethod = followUp['method'];
      final methodChanged =
          followUpMethod != null && followUpMethod != previousMethod;
      final mergedArguments = <String, String>{
        if (!methodChanged) ...pendingMeihua.values,
        if (methodChanged) ...{
          if (pendingMeihua['date'] != null)
            'date': pendingMeihua['date']!,
          if (followUpMethod == 'time' &&
              pendingMeihua['hour_branch'] != null)
            'hour_branch': pendingMeihua['hour_branch']!,
          if (followUpMethod == 'number' &&
              pendingMeihua['first'] != null)
            'first': pendingMeihua['first']!,
          if (followUpMethod == 'number' &&
              pendingMeihua['second'] != null)
            'second': pendingMeihua['second']!,
        },
        ...followUp.values,
      };
      final selectedMethod = mergedArguments['method'];
      if (selectedMethod == 'number') {
        final missingNumberKeys = <String>[
          if (mergedArguments['first']?.trim().isNotEmpty != true) 'first',
          if (mergedArguments['second']?.trim().isNotEmpty != true) 'second',
        ];
        final singleNumber = int.tryParse(text.trim());
        if (missingNumberKeys.isNotEmpty &&
            singleNumber != null &&
            singleNumber > 0 &&
            !followUp.values.containsKey(missingNumberKeys.first)) {
          // A bare number fills the next missing numeric slot in order.
          mergedArguments[missingNumberKeys.first] = singleNumber.toString();
        }
      }
      await _requestTool(
        text,
        AssistantToolRouter.meihua,
        mode: _lastEffectiveMode ?? AssistantMode.metaphysics,
        arguments: AssistantToolArguments(
          toolId: 'meihua',
          values: Map<String, String>.unmodifiable(mergedArguments),
        ),
        traceContext: traceContext,
      );
      return;
    }

    final pendingGuansha = _pendingGuanshaArguments;
    if (pendingGuansha != null && (imagePath != null || audioPath != null)) {
      setState(() {
        _error = '小儿关煞参数需要文字资料。请用文字补齐公历出生日期、出生时间、性别和可唯一识别的出生地点，或发送“取消关煞”结束本次测算。';
      });
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.failed,
        route: 'tool_follow_up:guansha_attachment_rejected',
        mode: AssistantMode.metaphysics.name,
        toolId: 'guansha',
        errorCode: 'GUANSHA_PARAMETERS_REQUIRE_TEXT',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.succeeded,
        mode: AssistantMode.metaphysics.name,
        toolId: 'guansha',
      );
      return;
    }
    if (pendingGuansha != null && text.isNotEmpty) {
      final cancelText =
          text.trim().replaceAll(RegExp(r'[，。.!！?？]+    if (pendingZiwei != null && (imagePath != null || audioPath != null)) {
      setState(() {
        _error = '紫微排盘需要文本出生资料。请用文字补齐公历出生日期、出生时间、性别和出生地点，或发送“取消紫微”结束本次排盘。';
      });
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.failed,
        route: 'tool_follow_up:ziwei_attachment_rejected',
        mode: AssistantMode.metaphysics.name,
        toolId: 'ziwei',
        errorCode: 'ZIWEI_PARAMETERS_REQUIRE_TEXT',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.succeeded,
        mode: AssistantMode.metaphysics.name,
        toolId: 'ziwei',
      );
      return;
    }
    if (pendingZiwei != null && text.isNotEmpty) {
      final cancelRequested = const {
        '取消紫微',
        '取消排盘',
        '停止排盘',
        '算了',
        '取消',
        '先不排',
      }.contains(text.trim());
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.succeeded,
        route: cancelRequested ? 'tool_cancel:ziwei' : 'tool_follow_up:ziwei',
        mode: AssistantMode.metaphysics.name,
        toolId: 'ziwei',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.dispatch,
        status: AiTraceStatus.succeeded,
        route: cancelRequested ? 'tool_cancel:ziwei' : 'tool_follow_up:ziwei',
        mode: AssistantMode.metaphysics.name,
        toolId: 'ziwei',
      );
      if (cancelRequested) {
        const reply = '已取消本次紫微排盘；尚未执行任何计算。';
        setState(() {
          _pendingZiweiArguments = null;
          _messages
            ..add(_InterviewMessage(text: text, isUser: true))
            ..add(const _InterviewMessage(text: reply, isUser: false));
          _error = null;
        });
        _inputController.clear();
        final persisted = await _persistSuccessfulTurn(
          userText: text,
          assistantText: reply,
          mode: AssistantMode.metaphysics,
          toolId: 'ziwei',
          toolStatus: AssistantToolExecutionStatus.cancelled.name.toUpperCase(),
          toolArguments: pendingZiwei.values,
          traceId: traceId,
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.persistence,
          status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
          toolId: 'ziwei',
          errorCode: persisted ? null : 'PERSISTENCE_FAILED',
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.succeeded,
          toolId: 'ziwei',
        );
        _scrollToBottom();
        return;
      }
      final followUp = AssistantConversationOrchestrator.argumentsFor(
        AssistantToolRouter.ziwei,
        text,
      );
      final mergedArguments = <String, String>{
        ...pendingZiwei.values,
        ...followUp.values,
      };
      await _requestTool(
        text,
        AssistantToolRouter.ziwei,
        mode: _lastEffectiveMode ?? AssistantMode.metaphysics,
        arguments: AssistantToolArguments(
          toolId: 'ziwei',
          values: Map<String, String>.unmodifiable(mergedArguments),
        ),
        traceContext: traceContext,
      );
      return;
    }

    final pendingBazi = _pendingBaziArguments;
    if (pendingBazi != null && (imagePath != null || audioPath != null)) {
      setState(() {
        _error = '八字排盘需要文本出生资料。请先用文字补齐出生日期、时间、性别和出生地点，或发送“取消”结束本次排盘。';
      });
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.failed,
        route: 'tool_follow_up:bazi_attachment_rejected',
        mode: AssistantMode.metaphysics.name,
        toolId: 'bazi',
        errorCode: 'BAZI_PARAMETERS_REQUIRE_TEXT',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.succeeded,
        mode: AssistantMode.metaphysics.name,
        toolId: 'bazi',
      );
      return;
    }
    if (pendingBazi != null && text.isNotEmpty) {
      final cancelRequested =
          ['取消', '算了', '先不排', '不用排了', '停止排盘'].any(text.contains);
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.succeeded,
        route: cancelRequested ? 'tool_cancel:bazi' : 'tool_follow_up:bazi',
        mode: AssistantMode.metaphysics.name,
        toolId: 'bazi',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.dispatch,
        status: AiTraceStatus.succeeded,
        route: cancelRequested ? 'tool_cancel:bazi' : 'tool_follow_up:bazi',
        mode: AssistantMode.metaphysics.name,
        toolId: 'bazi',
      );
      if (cancelRequested) {
        const reply = '已取消本次八字排盘；尚未执行任何计算。';
        setState(() {
          _pendingBaziArguments = null;
          _pendingZiweiArguments = null;
          _messages
            ..add(_InterviewMessage(text: text, isUser: true))
            ..add(const _InterviewMessage(text: reply, isUser: false));
          _error = null;
        });
        _inputController.clear();
        final persisted = await _persistSuccessfulTurn(
          userText: text,
          assistantText: reply,
          mode: AssistantMode.metaphysics,
          toolId: 'bazi',
          toolStatus: AssistantToolExecutionStatus.cancelled.name.toUpperCase(),
          toolArguments: pendingBazi.values,
          traceId: traceId,
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.persistence,
          status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
          toolId: 'bazi',
          errorCode: persisted ? null : 'PERSISTENCE_FAILED',
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.succeeded,
          toolId: 'bazi',
        );
        _scrollToBottom();
        return;
      }
      final followUp = AssistantConversationOrchestrator.argumentsFor(
        AssistantToolRouter.bazi,
        text,
      );
      final mergedArguments = <String, String>{
        ...pendingBazi.values,
        ...followUp.values,
      };
      await _requestTool(
        text,
        AssistantToolRouter.bazi,
        mode: _lastEffectiveMode ?? AssistantMode.metaphysics,
        arguments: AssistantToolArguments(
          toolId: 'bazi',
          values: Map<String, String>.unmodifiable(mergedArguments),
        ),
        traceContext: traceContext,
      );
      return;
    }

    final pendingXiaoliuren = _pendingXiaoliurenArguments;
    if (pendingXiaoliuren != null &&
        (imagePath != null || audioPath != null)) {
      setState(() {
        _error = '小六壬起课需要文字资料。请用文字补齐公历日期、时辰和起课口径，或发送“取消小六壬”结束本次起课。';
      });
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.failed,
        route: 'tool_follow_up:xiaoliuren_attachment_rejected',
        mode: AssistantMode.metaphysics.name,
        toolId: 'xiaoliuren',
        errorCode: 'XIAOLIUREN_PARAMETERS_REQUIRE_TEXT',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.succeeded,
        mode: AssistantMode.metaphysics.name,
        toolId: 'xiaoliuren',
      );
      return;
    }
    if (pendingXiaoliuren != null && text.isNotEmpty) {
      final cancelText =
          text.trim().replaceAll(RegExp(r'[，。.!！?？]+$'), '');
      final cancelRequested = const {
        '取消小六壬',
        '取消起课',
        '停止起课',
        '算了',
        '先不算',
        '取消',
      }.contains(cancelText);
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.succeeded,
        route: cancelRequested
            ? 'tool_cancel:xiaoliuren'
            : 'tool_follow_up:xiaoliuren',
        mode: AssistantMode.metaphysics.name,
        toolId: 'xiaoliuren',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.dispatch,
        status: AiTraceStatus.succeeded,
        route: cancelRequested
            ? 'tool_cancel:xiaoliuren'
            : 'tool_follow_up:xiaoliuren',
        mode: AssistantMode.metaphysics.name,
        toolId: 'xiaoliuren',
      );
      if (cancelRequested) {
        const reply = '已取消本次小六壬起课；尚未执行任何计算。';
        setState(() {
          _pendingXiaoliurenArguments = null;
          _messages
            ..add(_InterviewMessage(text: text, isUser: true))
            ..add(const _InterviewMessage(text: reply, isUser: false));
          _error = null;
        });
        _inputController.clear();
        final persisted = await _persistSuccessfulTurn(
          userText: text,
          assistantText: reply,
          mode: AssistantMode.metaphysics,
          toolId: 'xiaoliuren',
          toolStatus: AssistantToolExecutionStatus.cancelled.name.toUpperCase(),
          toolArguments: pendingXiaoliuren.values,
          traceId: traceId,
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.persistence,
          status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
          toolId: 'xiaoliuren',
          errorCode: persisted ? null : 'PERSISTENCE_FAILED',
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.succeeded,
          toolId: 'xiaoliuren',
        );
        _scrollToBottom();
        return;
      }
      final followUp = AssistantConversationOrchestrator.argumentsFor(
        AssistantToolRouter.xiaoliuren,
        text,
      );
      final mergedArguments = <String, String>{
        ...pendingXiaoliuren.values,
        ...followUp.values,
      };
      await _requestTool(
        text,
        AssistantToolRouter.xiaoliuren,
        mode: _lastEffectiveMode ?? AssistantMode.metaphysics,
        arguments: AssistantToolArguments(
          toolId: 'xiaoliuren',
          values: Map<String, String>.unmodifiable(mergedArguments),
        ),
        traceContext: traceContext,
      );
      return;
    }

    final pendingZiWu = _pendingZiWuArguments;
    if (pendingZiWu != null &&
        (imagePath != null || audioPath != null)) {
      setState(() {
        _error = '子午流注计算需要明确的公历日期和本地时刻，请用文字补充；也可以发送“取消子午流注”结束本次操作。';
      });
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.failed,
        route: 'tool_follow_up:ziwu_attachment_rejected',
        mode: AssistantMode.tools.name,
        toolId: 'ziwu_liuzhu',
        errorCode: 'ZIWU_PARAMETERS_REQUIRE_TEXT',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.succeeded,
        mode: AssistantMode.tools.name,
        toolId: 'ziwu_liuzhu',
      );
      return;
    }
    if (pendingZiWu != null && text.isNotEmpty) {
      final cancelText =
          text.trim().replaceAll(RegExp(r'[，。.!！?？]+$'), '');
      final cancelRequested = const {
        '取消子午流注',
        '取消时辰开穴',
        '取消开穴计算',
        '停止计算',
        '算了',
        '先不算',
        '取消',
      }.contains(cancelText);
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.succeeded,
        route: cancelRequested ? 'tool_cancel:ziwu_liuzhu' : 'tool_follow_up:ziwu_liuzhu',
        mode: AssistantMode.tools.name,
        toolId: 'ziwu_liuzhu',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.dispatch,
        status: AiTraceStatus.succeeded,
        route: cancelRequested ? 'tool_cancel:ziwu_liuzhu' : 'tool_follow_up:ziwu_liuzhu',
        mode: AssistantMode.tools.name,
        toolId: 'ziwu_liuzhu',
      );
      if (cancelRequested) {
        const reply = '已取消本次子午流注计算；尚未执行计算。';
        setState(() {
          _pendingZiWuArguments = null;
          _messages
            ..add(_InterviewMessage(text: text, isUser: true))
            ..add(const _InterviewMessage(text: reply, isUser: false));
          _error = null;
        });
        _inputController.clear();
        final persisted = await _persistSuccessfulTurn(
          userText: text,
          assistantText: reply,
          mode: AssistantMode.tools,
          toolId: 'ziwu_liuzhu',
          toolStatus: AssistantToolExecutionStatus.cancelled.name.toUpperCase(),
          toolArguments: pendingZiWu.values,
          traceId: traceId,
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.persistence,
          status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
          toolId: 'ziwu_liuzhu',
          errorCode: persisted ? null : 'PERSISTENCE_FAILED',
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.succeeded,
          toolId: 'ziwu_liuzhu',
        );
        _scrollToBottom();
        return;
      }
      final followUp = AssistantConversationOrchestrator.argumentsFor(
        AssistantToolRouter.ziwu,
        text,
      );
      final mergedArguments = <String, String>{
        ...pendingZiWu.values,
        ...followUp.values,
      };
      await _requestTool(
        text,
        AssistantToolRouter.ziwu,
        mode: AssistantMode.tools,
        arguments: AssistantToolArguments(
          toolId: 'ziwu_liuzhu',
          values: Map<String, String>.unmodifiable(mergedArguments),
        ),
        traceContext: traceContext,
      );
      return;
    }

    final pendingDosage = _pendingDosageArguments;
    if (pendingDosage != null &&
        (imagePath != null || audioPath != null)) {
      setState(() {
        _error = '经方换算只需要文字数值、单位和必要的度量标准；请用文字补充，或发送“取消剂量换算”结束本次操作。';
      });
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.failed,
        route: 'tool_follow_up:dosage_attachment_rejected',
        mode: AssistantMode.tools.name,
        toolId: 'dosage',
        errorCode: 'DOSAGE_PARAMETERS_REQUIRE_TEXT',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.succeeded,
        mode: AssistantMode.tools.name,
        toolId: 'dosage',
      );
      return;
    }
    if (pendingDosage != null && text.isNotEmpty) {
      final cancelText =
          text.trim().replaceAll(RegExp(r'[，。.!！?？]+$'), '');
      final cancelRequested = const {
        '取消剂量换算',
        '取消换算',
        '停止换算',
        '算了',
        '先不算',
        '取消',
      }.contains(cancelText);
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.succeeded,
        route: cancelRequested ? 'tool_cancel:dosage' : 'tool_follow_up:dosage',
        mode: AssistantMode.tools.name,
        toolId: 'dosage',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.dispatch,
        status: AiTraceStatus.succeeded,
        route: cancelRequested ? 'tool_cancel:dosage' : 'tool_follow_up:dosage',
        mode: AssistantMode.tools.name,
        toolId: 'dosage',
      );
      if (cancelRequested) {
        const reply = '已取消本次单位换算；尚未执行计算。';
        setState(() {
          _pendingDosageArguments = null;
          _messages
            ..add(_InterviewMessage(text: text, isUser: true))
            ..add(const _InterviewMessage(text: reply, isUser: false));
          _error = null;
        });
        _inputController.clear();
        final persisted = await _persistSuccessfulTurn(
          userText: text,
          assistantText: reply,
          mode: AssistantMode.tools,
          toolId: 'dosage',
          toolStatus: AssistantToolExecutionStatus.cancelled.name.toUpperCase(),
          toolArguments: pendingDosage.values,
          traceId: traceId,
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.persistence,
          status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
          toolId: 'dosage',
          errorCode: persisted ? null : 'PERSISTENCE_FAILED',
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.succeeded,
          toolId: 'dosage',
        );
        _scrollToBottom();
        return;
      }
      final followUp = AssistantConversationOrchestrator.argumentsFor(
        AssistantToolRouter.dosage,
        text,
      );
      final mergedArguments = <String, String>{
        ...pendingDosage.values,
        ...followUp.values,
      };
      await _requestTool(
        text,
        AssistantToolRouter.dosage,
        mode: AssistantMode.tools,
        arguments: AssistantToolArguments(
          toolId: 'dosage',
          values: Map<String, String>.unmodifiable(mergedArguments),
        ),
        traceContext: traceContext,
      );
      return;
    }

    final pendingYiJing = _pendingYiJingArguments;
    if (pendingYiJing != null && (imagePath != null || audioPath != null)) {
      setState(() {
        _error = '易经起卦参数请用文字补充；铜钱摇卦由 App 自动投掷，无需上传结果。也可以发送“取消易经起卦”结束本次操作。';
      });
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.failed,
        route: 'tool_follow_up:yijing_attachment_rejected',
        mode: AssistantMode.metaphysics.name,
        toolId: 'yijing',
        errorCode: 'YIJING_PARAMETERS_REQUIRE_TEXT',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.succeeded,
        mode: AssistantMode.metaphysics.name,
        toolId: 'yijing',
      );
      return;
    }
    if (pendingYiJing != null && text.isNotEmpty) {
      final cancelText =
          text.trim().replaceAll(RegExp(r'[，。.!！?？]+$'), '');
      final cancelRequested = const {
        '取消易经',
        '取消易经起卦',
        '取消起卦',
        '停止起卦',
        '算了',
        '先不算',
        '取消',
      }.contains(cancelText);
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.succeeded,
        route: cancelRequested ? 'tool_cancel:yijing' : 'tool_follow_up:yijing',
        mode: AssistantMode.metaphysics.name,
        toolId: 'yijing',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.dispatch,
        status: AiTraceStatus.succeeded,
        route: cancelRequested ? 'tool_cancel:yijing' : 'tool_follow_up:yijing',
        mode: AssistantMode.metaphysics.name,
        toolId: 'yijing',
      );
      if (cancelRequested) {
        const reply = '已取消本次易经起卦；尚未执行任何计算。';
        setState(() {
          _pendingYiJingArguments = null;
          _pendingDosageArguments = null;
          _messages
            ..add(_InterviewMessage(text: text, isUser: true))
            ..add(const _InterviewMessage(text: reply, isUser: false));
          _error = null;
        });
        _inputController.clear();
        final persisted = await _persistSuccessfulTurn(
          userText: text,
          assistantText: reply,
          mode: AssistantMode.metaphysics,
          toolId: 'yijing',
          toolStatus: AssistantToolExecutionStatus.cancelled.name.toUpperCase(),
          toolArguments: pendingYiJing.values,
          traceId: traceId,
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.persistence,
          status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
          toolId: 'yijing',
          errorCode: persisted ? null : 'PERSISTENCE_FAILED',
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.succeeded,
          toolId: 'yijing',
        );
        _scrollToBottom();
        return;
      }
      final followUp = AssistantConversationOrchestrator.argumentsFor(
        AssistantToolRouter.yijing,
        text,
      );
      final mergedArguments = <String, String>{
        ...pendingYiJing.values,
        ...followUp.values,
      };
      await _requestTool(
        text,
        AssistantToolRouter.yijing,
        mode: _lastEffectiveMode ?? AssistantMode.metaphysics,
        arguments: AssistantToolArguments(
          toolId: 'yijing',
          values: Map<String, String>.unmodifiable(mergedArguments),
        ),
        traceContext: traceContext,
      );
      return;
    }

    var effectiveMode = _assistantMode;
    if (text.isNotEmpty && imagePath == null && audioPath == null) {
      var decision = AssistantConversationOrchestrator.resolve(
        query: text,
        selectedMode: _assistantMode,
        currentMode: _lastEffectiveMode,
        pendingToolSelection: _pendingToolSelection,
      );
      final mayUseBoundedIntentModel =
          decision.candidateTools.length >= 2 &&
          (decision.mode == AssistantMode.tools ||
              decision.mode == AssistantMode.metaphysics) &&
          !AssistantConversationOrchestrator.shouldExcludeFromIntentModel(text) &&
          _status?.ready == true;
      if (mayUseBoundedIntentModel && traceId != null) {
        setState(() => _sending = true);
        try {
          final resolution = await _service.resolveAssistantIntentWithTrace(
            query: text,
            candidates: decision.candidateTools
                .map(
                  (tool) => LocalAiIntentCandidate(
                    id: tool.id,
                    title: tool.title,
                    description: tool.description,
                  ),
                )
                .toList(growable: false),
            traceId: traceId,
          );
          await _traceRecorder.record(
            traceContext,
            stage: AiTraceStage.nativeInference,
            status: AiTraceStatus.succeeded,
            route: 'bounded_intent_selection',
            mode: decision.mode.name,
          );
          await _traceRecorder.record(
            traceContext,
            stage: AiTraceStage.modelOutput,
            status: AiTraceStatus.succeeded,
            route: 'bounded_intent_selection',
            mode: decision.mode.name,
          );
          await _traceRecorder.record(
            traceContext,
            stage: AiTraceStage.resultValidation,
            status: AiTraceStatus.succeeded,
            route: 'bounded_intent_selection:${resolution.action.name}',
            mode: decision.mode.name,
          );
          if (resolution.action == LocalAiIntentAction.select) {
            AssistantToolDefinition? selectedTool;
            for (final candidate in decision.candidateTools) {
              if (candidate.id == resolution.toolId) {
                selectedTool = candidate;
                break;
              }
            }
            if (selectedTool != null) {
              decision = AssistantDispatchDecision(
                mode: decision.mode,
                tool: selectedTool,
                toolArguments:
                    AssistantConversationOrchestrator.argumentsFor(
                  selectedTool,
                  text,
                ),
              );
            }
          }
        } catch (error) {
          // E4B is advisory only. A native failure or invalid schema falls
          // back to the deterministic L0 clarification; it never dispatches.
          await _traceRecorder.record(
            traceContext,
            stage: AiTraceStage.nativeInference,
            status: AiTraceStatus.unknown,
            route: 'bounded_intent_selection',
            mode: decision.mode.name,
            errorCode: 'INTENT_CLASSIFICATION_FAILED',
          );
          await _traceRecorder.record(
            traceContext,
            stage: AiTraceStage.modelOutput,
            status: AiTraceStatus.failed,
            route: 'bounded_intent_selection',
            mode: decision.mode.name,
            errorCode: 'INTENT_OUTPUT_INVALID',
          );
          await _traceRecorder.record(
            traceContext,
            stage: AiTraceStage.resultValidation,
            status: AiTraceStatus.notStarted,
            route: 'fallback_to_deterministic_l0',
            mode: decision.mode.name,
          );
        } finally {
          if (mounted) setState(() => _sending = false);
        }
        if (!mounted) return;
      }
      effectiveMode = decision.mode;
      _pendingToolSelection = decision.expectsToolSelection;
      final resolvedRoute = decision.needsClarification
          ? 'clarification'
          : decision.tool != null
              ? 'tool:${decision.tool!.id}'
              : 'model';
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.succeeded,
        route: resolvedRoute,
        mode: effectiveMode.name,
        toolId: decision.tool?.id,
      );
      if (decision.needsClarification) {
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.dispatch,
          status: AiTraceStatus.succeeded,
          route: 'clarification',
          mode: effectiveMode.name,
        );
        final clarification = decision.clarification!;
        setState(() {
          _lastEffectiveMode = effectiveMode;
          _messages
            ..add(_InterviewMessage(text: text, isUser: true))
            ..add(_InterviewMessage(text: clarification, isUser: false));
          _error = null;
        });
        _inputController.clear();
        final persisted = await _persistSuccessfulTurn(
          userText: text,
          assistantText: clarification,
          mode: effectiveMode,
          expectsToolSelection: decision.expectsToolSelection,
          traceId: traceId,
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.persistence,
          status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
          errorCode: persisted ? null : 'PERSISTENCE_FAILED',
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.succeeded,
        );
        _scrollToBottom();
        return;
      }
      if (decision.tool != null) {
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.dispatch,
          status: AiTraceStatus.succeeded,
          route: 'tool',
          mode: effectiveMode.name,
          toolId: decision.tool!.id,
        );
        await _requestTool(
          text,
          decision.tool!,
          mode: effectiveMode,
          arguments: decision.toolArguments,
          traceContext: traceContext,
        );
        return;
      }
    } else if (_assistantMode == AssistantMode.automatic) {
      // 照片/语音附件默认进入问诊域；不凭附件类型猜测排盘或学习任务。
      _pendingToolSelection = false;
      effectiveMode = AssistantMode.consultation;
    }
    if (_status?.ready != true) {
      setState(() => _error = '本地模型尚未加载。可以先使用上方 App 内置工具；AI 对话请先加载 Gemma 4 E4B。');
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.succeeded,
        mode: effectiveMode.name,
        errorCode: 'LOCAL_MODEL_NOT_READY',
      );
      return;
    }

    final userLabel = text.isNotEmpty
        ? text
        : imagePath != null
            ? '已附加一张舌象照片'
            : '已录制一段语音';
    setState(() {
      _lastEffectiveMode = effectiveMode;
      _messages.add(_InterviewMessage(text: userLabel, isUser: true));
      _sending = true;
      _error = null;
    });
    _scrollToBottom();

    var nativeInferenceCompleted = false;
    var resultValidationCompleted = false;
    var persistenceStarted = false;
    var persistenceRecorded = false;
    try {
      final turnResponse = audioPath != null
          ? _AssistantTurnResponse(
              text: traceId == null
                  ? await _service.sendAudio(audioPath, prompt: text)
                  : await _service.sendAudioWithTrace(
                      audioPath,
                      prompt: text,
                      traceId: traceId,
                    ),
            )
          : imagePath != null
              ? _AssistantTurnResponse(
                  text: traceId == null
                  ? await _service.sendImage(imagePath, prompt: text)
                  : await _service.sendImageWithTrace(
                      imagePath,
                      prompt: text,
                      traceId: traceId,
                    ),
                )
              : await _sendTextWithKnowledgeContext(
                  text,
                  mode: effectiveMode,
                  traceContext: traceContext,
                );
      final reply = turnResponse.text;
      nativeInferenceCompleted = true;
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.nativeInference,
        status: AiTraceStatus.succeeded,
        mode: effectiveMode.name,
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.modelOutput,
        status: AiTraceStatus.succeeded,
        mode: effectiveMode.name,
        sourceIds: turnResponse.sourceIds,
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.resultValidation,
        status: AiTraceStatus.succeeded,
        mode: effectiveMode.name,
        sourceIds: turnResponse.sourceIds,
      );
      resultValidationCompleted = true;
      persistenceStarted = true;
      final persisted = await _persistSuccessfulTurn(
        userText: text,
        assistantText: reply,
        mode: effectiveMode,
        traceId: traceId,
        attachmentType: audioPath != null ? '录音' : imagePath != null ? '照片' : null,
        sourceIds: turnResponse.sourceIds,
        knowledgeStatus: turnResponse.knowledgeStatus,
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.persistence,
        status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
        mode: effectiveMode.name,
        sourceIds: turnResponse.sourceIds,
        errorCode: persisted ? null : 'PERSISTENCE_FAILED',
      );
      persistenceRecorded = true;
      await _deleteCachedAttachments([imagePath, audioPath]);
      final refreshedStatus = await _readNativeStatus();
      if (!mounted) {
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.notApplicable,
          mode: effectiveMode.name,
          errorCode: 'SCREEN_DISPOSED',
        );
        return;
      }
      _inputController.clear();
      final nativeRuntimeUnavailable =
          refreshedStatus != null && !refreshedStatus.ready;
      setState(() {
        _status = refreshedStatus;
        _statusUnknown = refreshedStatus == null;
        if (nativeRuntimeUnavailable) {
          _messages
            ..clear()
            ..add(const _InterviewMessage(
              text: '本轮回复已生成，但原生模型已变为未加载状态。旧会话已结束；以下回复仅供查看，重新加载后请开始新对话。',
              isUser: false,
            ))
            ..add(_InterviewMessage(
              text: reply,
              isUser: false,
              sourceIds: turnResponse.sourceIds,
              onSourceTap: _openKnowledgeSource,
              knowledgeStatus: turnResponse.knowledgeStatus,
            ));
          _confirmedDraft = null;
        } else {
          _messages.add(_InterviewMessage(
            text: reply,
            isUser: false,
            sourceIds: turnResponse.sourceIds,
            onSourceTap: _openKnowledgeSource,
            knowledgeStatus: turnResponse.knowledgeStatus,
          ));
        }
        _sending = false;
        _imagePath = null;
        _audioPath = null;
        _error = refreshedStatus == null
            ? '本轮回复已生成，但无法确认本地模型状态。请重新检查后继续。'
            : null;
      });
      _scrollToBottom();
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.succeeded,
        mode: effectiveMode.name,
        sourceIds: turnResponse.sourceIds,
      );
    } on PlatformException catch (error) {
      final emptyReply = error.code == 'EMPTY_REPLY';
      final traceMismatch = error.code == 'TRACE_ID_MISMATCH';
      if (!nativeInferenceCompleted) {
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.nativeInference,
          status: emptyReply
              ? AiTraceStatus.succeeded
              : AiTraceStatus.unknown,
          mode: effectiveMode.name,
          errorCode: emptyReply
              ? null
              : traceMismatch
                  ? 'TRACE_ID_MISMATCH'
                  : 'NATIVE_CALL_FAILED',
        );
      }
      if (!resultValidationCompleted) {
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.resultValidation,
          status: emptyReply
              ? AiTraceStatus.failed
              : traceMismatch
                  ? AiTraceStatus.unknown
                  : AiTraceStatus.notStarted,
          mode: effectiveMode.name,
          errorCode: emptyReply
              ? 'MODEL_REPLY_INVALID'
              : traceMismatch
                  ? 'TRACE_ID_MISMATCH'
                  : null,
        );
      }
      if (!persistenceRecorded) {
        if (persistenceStarted) {
          await _traceRecorder.record(
            traceContext,
            stage: AiTraceStage.persistence,
            status: AiTraceStatus.unknown,
            mode: effectiveMode.name,
            errorCode: 'PERSISTENCE_STATE_UNKNOWN',
          );
        } else {
          await _recordTurnPersistenceNotStarted(
            traceContext,
            errorCode: 'NATIVE_TURN_NOT_PERSISTED',
            mode: effectiveMode.name,
          );
        }
      }
      final refreshedStatus = await _readNativeStatus();
      if (!mounted) {
        await _deleteCachedAttachments([imagePath, audioPath]);
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.notApplicable,
          mode: effectiveMode.name,
          errorCode: 'SCREEN_DISPOSED',
        );
        return;
      }
      setState(() {
        _status = refreshedStatus;
        _statusUnknown = refreshedStatus == null;
        if (_messages.isNotEmpty &&
            _messages.last.isUser &&
            _messages.last.text == userLabel) {
          _messages.removeLast();
        }
        final nativeRuntimeUnavailable =
            refreshedStatus != null && !refreshedStatus.ready;
        if (nativeRuntimeUnavailable) {
          _messages
            ..clear()
            ..add(const _InterviewMessage(
              text: '本地模型已变为未加载状态，旧会话已结束。编辑框中的内容和附件仍保留；重新加载后可重新发送。',
              isUser: false,
            ));
          _confirmedDraft = null;
        }
        _sending = false;
        final message = error.message ?? '本地推理失败';
        _error = refreshedStatus == null
            ? '$message；无法确认本地模型状态，请重新检查后继续。'
            : message;
      });
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.succeeded,
        mode: effectiveMode.name,
        errorCode: error.code,
      );
    } catch (error) {
      if (!nativeInferenceCompleted) {
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.nativeInference,
          status: AiTraceStatus.unknown,
          mode: effectiveMode.name,
          errorCode: 'NATIVE_CALL_FAILED',
        );
      }
      if (!resultValidationCompleted) {
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.resultValidation,
          status: nativeInferenceCompleted
              ? AiTraceStatus.unknown
              : AiTraceStatus.notStarted,
          mode: effectiveMode.name,
          errorCode: nativeInferenceCompleted ? 'RESULT_STATE_UNKNOWN' : null,
        );
      }
      if (!persistenceRecorded) {
        if (persistenceStarted) {
          await _traceRecorder.record(
            traceContext,
            stage: AiTraceStage.persistence,
            status: AiTraceStatus.unknown,
            mode: effectiveMode.name,
            errorCode: 'PERSISTENCE_STATE_UNKNOWN',
          );
        } else {
          await _recordTurnPersistenceNotStarted(
            traceContext,
            errorCode: 'NATIVE_TURN_NOT_PERSISTED',
            mode: effectiveMode.name,
          );
        }
      }
      final refreshedStatus = await _readNativeStatus();
      if (!mounted) {
        await _deleteCachedAttachments([imagePath, audioPath]);
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.notApplicable,
          mode: effectiveMode.name,
          errorCode: 'SCREEN_DISPOSED',
        );
        return;
      }
      setState(() {
        _status = refreshedStatus;
        _statusUnknown = refreshedStatus == null;
        if (_messages.isNotEmpty &&
            _messages.last.isUser &&
            _messages.last.text == userLabel) {
          _messages.removeLast();
        }
        final nativeRuntimeUnavailable =
            refreshedStatus != null && !refreshedStatus.ready;
        if (nativeRuntimeUnavailable) {
          _messages
            ..clear()
            ..add(const _InterviewMessage(
              text: '本地模型已变为未加载状态，旧会话已结束。编辑框中的内容和附件仍保留；重新加载后可重新发送。',
              isUser: false,
            ));
          _confirmedDraft = null;
        }
        _sending = false;
        _error = refreshedStatus == null
            ? '处理失败：$error；无法确认本地模型状态，请重新检查后继续。'
            : '处理失败：$error';
      });
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.succeeded,
        mode: effectiveMode.name,
        errorCode: persistenceStarted && !persistenceRecorded
            ? 'PERSISTENCE_STATE_UNKNOWN'
            : nativeInferenceCompleted
                ? 'RESULT_STATE_UNKNOWN'
                : 'NATIVE_CALL_FAILED',
      );
    }
  }

  Future<void> _extractSymptoms() async {
    if (_attachmentBusy || _modelControlBusy || _sending || _extracting) return;
    setState(() {
      _extracting = true;
      _error = null;
    });
    final traceContext = _traceRecorder.start(
      stage: AiTraceStage.input,
      route: 'symptom_extraction',
      mode: 'consultation',
    );
    Future<void> recordFinalRender({String? errorCode}) =>
        _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.finalRender,
          status: mounted
              ? AiTraceStatus.succeeded
              : AiTraceStatus.notApplicable,
          mode: 'consultation',
          errorCode: errorCode,
        );
    var nativeInferenceCompleted = false;
    var resultValidationCompleted = false;
    final userReportedText = _messages
        .where((message) => message.isUser)
        .map((message) => message.text)
        .join('\n');
    if (await _blockIfRedFlagPreflightDoesNotClear(
      source: RedFlagInputSource.structuredInterview,
      text: userReportedText.isEmpty ? null : userReportedText,
      traceContext: traceContext,
      route: 'symptom_extraction',
    )) {
      if (mounted) setState(() => _extracting = false);
      return;
    }
    try {
      final traceId = traceContext.traceId;
      final draft = traceId == null
          ? await _service.extractSymptoms()
          : await _service.extractSymptomsWithTrace(traceId: traceId);
      nativeInferenceCompleted = true;
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.nativeInference,
        status: AiTraceStatus.succeeded,
        mode: 'consultation',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.resultValidation,
        status: AiTraceStatus.succeeded,
        mode: 'consultation',
      );
      resultValidationCompleted = true;
      if (!mounted) {
        await recordFinalRender(errorCode: 'SCREEN_DISPOSED');
        return;
      }
      setState(() => _extracting = false);
      if (draft.summaryLines.isEmpty) {
        setState(() => _error = draft.sourceTruncated
            ? '原始输入记录曾被裁剪，但本次未提取到可核对内容。请补充遗漏描述后重新整理。'
            : '目前没有提取到明确的自述信息，请补充描述后再整理。');
        await recordFinalRender(errorCode: 'EMPTY_SYMPTOM_DRAFT');
        return;
      }

      final confirmed = await showFoldAwareDialog<bool>(
        context: context,
        builder: (dialogContext) {
          var checked = false;
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('核对症状整理'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '以下内容仅根据你提供的文字和待核对语音识别草稿整理，不包含舌象照片观察。请逐项核对；未提及的信息不会自动补全。',
                      style: TextStyle(fontSize: AppType.caption, height: 1.45),
                    ),
                    if (draft.sourceTruncated) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _buildSourceTruncationWarning(context),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    ...draft.summaryLines.map(
                      (line) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Text(line, style: const TextStyle(fontSize: AppType.caption)),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: checked,
                      onChanged: (value) =>
                          setDialogState(() => checked = value == true),
                      title: const Text(
                        '我已核对，内容符合我的实际描述',
                        style: TextStyle(fontSize: AppType.caption),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('返回修改'),
                ),
                FilledButton(
                  onPressed: checked
                      ? () => Navigator.pop(dialogContext, true)
                      : null,
                  child: const Text('确认这份整理'),
                ),
              ],
            ),
          );
        },
      );

      if (!mounted || confirmed != true) {
        await recordFinalRender(
          errorCode: mounted ? 'USER_CANCELLED_DRAFT_REVIEW' : 'SCREEN_DISPOSED',
        );
        return;
      }
      setState(() {
        _confirmedDraft = draft;
      });
      await recordFinalRender();
    } on PlatformException catch (error) {
      final traceMismatch = error.code == 'TRACE_ID_MISMATCH';
      final emptyReply = error.code == 'EMPTY_REPLY';
      if (!nativeInferenceCompleted) {
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.nativeInference,
          status: emptyReply
              ? AiTraceStatus.succeeded
              : AiTraceStatus.unknown,
          mode: 'consultation',
          errorCode: traceMismatch
              ? 'TRACE_ID_MISMATCH'
              : emptyReply
                  ? null
                  : 'NATIVE_CALL_FAILED',
        );
      }
      if (!resultValidationCompleted) {
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.resultValidation,
          status: emptyReply
              ? AiTraceStatus.failed
              : traceMismatch
                  ? AiTraceStatus.unknown
                  : AiTraceStatus.notStarted,
          mode: 'consultation',
          errorCode: emptyReply
              ? 'MODEL_REPLY_INVALID'
              : traceMismatch
                  ? 'TRACE_ID_MISMATCH'
                  : null,
        );
      }
      if (!mounted) {
        await recordFinalRender(errorCode: 'SCREEN_DISPOSED');
        return;
      }
      setState(() {
        _extracting = false;
        _error = error.message ?? '症状整理失败';
      });
      await recordFinalRender(errorCode: error.code);
    } on FormatException catch (error) {
      if (!nativeInferenceCompleted) {
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.nativeInference,
          status: AiTraceStatus.succeeded,
          mode: 'consultation',
        );
      }
      if (!resultValidationCompleted) {
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.resultValidation,
          status: AiTraceStatus.failed,
          mode: 'consultation',
          errorCode: 'MODEL_OUTPUT_INVALID',
        );
      }
      if (!mounted) {
        await recordFinalRender(errorCode: 'SCREEN_DISPOSED');
        return;
      }
      setState(() {
        _extracting = false;
        _error = error.message;
      });
      await recordFinalRender(errorCode: 'MODEL_OUTPUT_INVALID');
    } catch (error) {
      if (!nativeInferenceCompleted) {
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.nativeInference,
          status: AiTraceStatus.unknown,
          mode: 'consultation',
          errorCode: 'NATIVE_CALL_FAILED',
        );
      }
      if (!resultValidationCompleted) {
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.resultValidation,
          status: nativeInferenceCompleted
              ? AiTraceStatus.unknown
              : AiTraceStatus.notStarted,
          mode: 'consultation',
          errorCode: nativeInferenceCompleted ? 'RESULT_STATE_UNKNOWN' : null,
        );
      }
      if (!mounted) {
        await recordFinalRender(errorCode: 'SCREEN_DISPOSED');
        return;
      }
      setState(() {
        _extracting = false;
        _error = '症状整理失败：$error';
      });
      await recordFinalRender(
        errorCode: nativeInferenceCompleted
            ? 'RESULT_STATE_UNKNOWN'
            : 'NATIVE_CALL_FAILED',
      );
    }
  }

  Future<void> _releaseModel() async {
    if (_attachmentBusy ||
        _modelControlBusy ||
        _sending ||
        _extracting ||
        _recordingBusy ||
        _recording ||
        _statusUnknown ||
        _status?.ready != true) {
      return;
    }
    setState(() => _modelControlBusy = true);
    try {
      final paths = <String?>[_imagePath, _audioPath];
      final status = await _service.releaseModel();
      await _deleteCachedAttachments(paths);
      if (!mounted) return;
      setState(() {
        _status = status;
        _messages
          ..clear()
          ..add(const _InterviewMessage(
            text: '模型已释放，设备内存已归还。再次使用时可重新加载。',
            isUser: false,
          ));
        _confirmedDraft = null;
        _imagePath = null;
        _audioPath = null;
        _error = null;
      });
    } on PlatformException catch (error) {
      await _handleModelControlFailure(
        errorMessage: error.message ?? '无法释放模型',
        unavailableMessage: '释放操作发生错误，但原生模型运行态已清空。重新加载后可继续使用。',
      );
    } catch (error) {
      await _handleModelControlFailure(
        errorMessage: '无法释放模型：$error',
        unavailableMessage: '释放操作发生错误，但原生模型运行态已清空。重新加载后可继续使用。',
      );
    } finally {
      if (mounted) setState(() => _modelControlBusy = false);
    }
  }

  Future<void> _handleModelControlFailure({
    required String errorMessage,
    required String unavailableMessage,
  }) async {
    final refreshedStatus = await _readNativeStatus();
    if (refreshedStatus == null) {
      if (!mounted) return;
      setState(() {
        _status = null;
        _statusUnknown = true;
        _error = '$errorMessage；无法确认原生模型状态，请重新检查后再继续。';
      });
      return;
    }
    final nativeRuntimeUnavailable = !refreshedStatus.ready;
    if (nativeRuntimeUnavailable) {
      await _deleteCachedAttachments([_imagePath, _audioPath]);
    }
    if (!mounted) return;
    setState(() {
      _status = refreshedStatus;
      _statusUnknown = false;
      if (nativeRuntimeUnavailable) {
        _messages
          ..clear()
          ..add(_InterviewMessage(text: unavailableMessage, isUser: false));
        _confirmedDraft = null;
        _imagePath = null;
        _audioPath = null;
      }
      _error = errorMessage;
    });
  }
  Future<void> _resetConversation() async {
    if (_attachmentBusy ||
        _modelControlBusy ||
        _sending ||
        _extracting ||
        _recordingBusy ||
        _recording ||
        _statusUnknown ||
        _status?.ready != true) {
      return;
    }
    setState(() => _modelControlBusy = true);
    try {
      final paths = <String?>[_imagePath, _audioPath];
      final status = await _service.resetConversation();
      await _deleteCachedAttachments(paths);
      if (!mounted) return;
      _conversationIdFuture = _createNewConversation();
      _lastEffectiveMode = null;
      _pendingToolSelection = false;
      _pendingBaziArguments = null;
      _pendingZiweiArguments = null;
      _pendingMeihuaArguments = null;
      _pendingChengguArguments = null;
      _pendingHuangdiSijiArguments = null;
      _pendingXiaoliurenArguments = null;
      _pendingDreamArguments = null;
      _pendingHistoryTranscript = null;
      _pendingHistoryUserMessages = const [];
      setState(() {
        _status = status;
        _messages
          ..clear()
          ..add(const _InterviewMessage(
            text: '我们重新开始。先说说这次最想了解的身体情况。',
            isUser: false,
          ));
        _confirmedDraft = null;
        _imagePath = null;
        _audioPath = null;
        _error = null;
      });
    } on PlatformException catch (error) {
      await _handleModelControlFailure(
        errorMessage: error.message ?? '无法重置会话',
        unavailableMessage: '会话重置失败，原生会话已关闭。请重新加载模型后重新开始。',
      );
    } catch (error) {
      await _handleModelControlFailure(
        errorMessage: '无法重置会话：$error',
        unavailableMessage: '会话重置失败，原生会话已关闭。请重新加载模型后重新开始。',
      );
    } finally {
      if (mounted) setState(() => _modelControlBusy = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _disposeRecorder(Iterable<String?> pendingAttachments) async {
    final paths = <String?>[
      ...pendingAttachments,
      _activeRecordingPath,
    ];
    try {
      await _recorderOperation;
    } catch (_) {
      // Continue teardown even if the pending start/stop failed.
    }
    if (_recording || _recorderMayBeActive) {
      try {
        paths.add(await _audioRecorder.stop());
        _recorderMayBeActive = false;
      } catch (_) {
        // Dispose still releases any remaining native recorder resources.
      }
    }
    try {
      await _audioRecorder.dispose();
    } catch (_) {
      // Do not leak an asynchronous exception during widget teardown.
    }
    _activeRecordingPath = null;
    await _deleteCachedAttachments(paths);
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    final pendingAttachments = _sending
        ? const <String?>[]
        : <String?>[_imagePath, _audioPath];
    unawaited(_disposeRecorder(pendingAttachments));
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ready = _status?.ready == true;
    // 键盘弹出时收起顶部模型/模式/角色说明，把空间让给对话。
    // ColorOS 不一定 resize 窗口，但 MediaQuery.viewInsets 走 WindowInsets.Type.ime()
    // 现代 API，键盘可见时 bottom>0 可靠。
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    return AdaptiveSinglePane(
      preferredAnchorPoint: widget.preferredAnchorPoint,
      child: Scaffold(
      // 交由外层 AdaptiveHomeNavigation 的 Scaffold 统一处理键盘 inset；
      // 这里再 resize 会与外层叠加（ColorOS 下双重应用把 body 压到 ~0，
      // 输入框被挤到顶部、对话区变空白）。
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('汉唐 AI 助手'),
        actions: [
          if (_tcmInterviewController != null)
            IconButton(
              tooltip: '问诊证据',
              onPressed: _sending ? null : _showZangFuEvidenceDialog,
              icon: const Icon(Icons.fact_check_outlined),
            ),
          IconButton(
            tooltip: '历史对话',
            onPressed: _attachmentBusy || _modelControlBusy || _sending || _extracting || _recordingBusy || _recording ? null : _openHistory,
            icon: const Icon(Icons.history),
          ),
          if (ready) ...[
            IconButton(
              tooltip: '重新开始对话',
              onPressed: _attachmentBusy || _modelControlBusy || _sending || _extracting || _recordingBusy || _recording ? null : _resetConversation,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: '释放模型内存',
              onPressed: _attachmentBusy || _modelControlBusy || _sending || _extracting || _recordingBusy || _recording ? null : _releaseModel,
              icon: const Icon(Icons.memory_outlined),
            ),
          ],
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Center(
            child: ConstrainedBox(
              key: const ValueKey('local-ai-content-width'),
              constraints: const BoxConstraints(maxWidth: 640),
              child: SizedBox(
                height: constraints.maxHeight,
                child: Column(
        children: [
          Expanded(
            child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
            children: [
            if (!keyboardVisible) ...[
              _buildModelPanel(context),
              _buildModeSelector(context),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
                color: scheme.surfaceContainerLow,
                child: Text(
                  '当前角色：${_assistantMode.label}。模型负责对话与整理；辨证规则、知识检索和工具计算分别由 App 对应模块执行。',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: AppType.caption,
                    height: 1.45,
                  ),
                ),
              ),
            ],
            if (ready && _confirmedDraft == null && _messages.any((m) => m.isUser))
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _attachmentBusy || _modelControlBusy || _sending || _extracting ? null : _extractSymptoms,
                    icon: _extracting
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.fact_check_outlined, size: 18),
                    label: Text(_extracting ? '正在整理自述…' : '整理本次症状'),
                  ),
                ),
              ),
            if (_confirmedDraft != null)
              _buildConfirmedDraftPanel(context),
            ..._messages.map((message) => _InterviewMessageBubble(message: message)),
            if (_sending || _extracting)
              _InterviewMessageBubble(
                message: _InterviewMessage(
                  text: _extracting ? '正在整理本次对话…' : '正在生成回复…',
                  isUser: false,
                ),
              ),
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                color: scheme.errorContainer,
                child: Text(
                  _error!,
                  style: TextStyle(color: scheme.onErrorContainer, fontSize: AppType.caption),
                ),
              ),
          ],
            ),
          ),
          SafeArea(
            top: false,
            // 键盘弹出时输入框下沿紧贴键盘上沿：去掉底部安全区与内边距。
            bottom: !keyboardVisible,
            child: Padding(
                padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, keyboardVisible ? 0 : AppSpacing.sm),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_imagePath != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                              child: Image.file(
                                File(_imagePath!),
                                width: 52,
                                height: 52,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            const Expanded(
                              child: Text(
                                '舌象照片已选。请确认光线自然、对焦清晰、无滤镜。',
                                style: TextStyle(fontSize: AppType.caption, height: 1.4),
                              ),
                            ),
                            IconButton(
                              tooltip: '移除照片',
                              onPressed: _attachmentBusy || _modelControlBusy || _sending ? null : _discardAttachment,
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                    if (_audioPath != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.graphic_eq, size: 20),
                            const SizedBox(width: AppSpacing.sm),
                            const Expanded(
                              child: Text('语音已录制（最长 30 秒），发送前可移除。', style: TextStyle(fontSize: AppType.caption)),
                            ),
                            IconButton(
                              tooltip: '移除录音',
                              onPressed: _attachmentBusy || _modelControlBusy || _sending ? null : _discardAttachment,
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                    if (_recording)
                      const Padding(
                        padding: EdgeInsets.only(bottom: AppSpacing.xs),
                        child: Row(
                          children: [
                            Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
                            SizedBox(width: AppSpacing.xs),
                            Text('正在录音，最长 30 秒…', style: TextStyle(fontSize: AppType.caption)),
                          ],
                        ),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: '拍摄舌象',
                          onPressed: ready &&
                                  !_attachmentBusy &&
                                  !_modelControlBusy &&
                                  !_sending &&
                                  !_extracting &&
                                  !_recording &&
                                  !_recordingBusy &&
                                  _confirmedDraft == null &&
                                  _audioPath == null
                              ? _pickTonguePhoto
                              : null,
                          icon: const Icon(Icons.camera_alt_outlined),
                        ),
                        IconButton(
                          tooltip: _recording ? '停止录音' : '录制语音（最长 30 秒）',
                          onPressed: ready &&
                                  !_attachmentBusy &&
                                  !_modelControlBusy &&
                                  !_sending &&
                                  !_extracting &&
                                  !_recordingBusy &&
                                  (!_recorderMayBeActive || _recording) &&
                                  _confirmedDraft == null &&
                                  _imagePath == null &&
                                  _audioPath == null
                              ? (_recording ? _stopRecording : _startRecording)
                              : null,
                          icon: Icon(_recording ? Icons.stop_circle_outlined : Icons.mic_none),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _inputController,
                            minLines: 1,
                            maxLines: 4,
                            enabled: ready &&
                                !_attachmentBusy &&
                                !_modelControlBusy &&
                                !_sending &&
                                !_extracting &&
                                !_recording &&
                                !_recordingBusy &&
                                _confirmedDraft == null,
                            onChanged: (_) => setState(() {}),
                            textInputAction: TextInputAction.newline,
                            // 点击对话区任意处（含消息气泡）收起键盘、退出输入模式。
                            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                            decoration: InputDecoration(
                              hintText: ready ? '描述你的情况…' : '请先安装并加载本地模型',
                              filled: true,
                              fillColor: scheme.surfaceContainerLow,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppRadius.lg),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.lg,
                                vertical: AppSpacing.md,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        IconButton.filled(
                          tooltip: '发送',
                          onPressed: ready &&
                                  !_attachmentBusy &&
                                  !_modelControlBusy &&
                                  !_sending &&
                                  !_extracting &&
                                  !_recording &&
                                  !_recordingBusy &&
                                  _confirmedDraft == null &&
                                  (_inputController.text.trim().isNotEmpty ||
                                      _imagePath != null ||
                                      _audioPath != null)
                              ? _send
                              : null,
                          icon: const Icon(Icons.arrow_upward),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
                ),
              ),
            ),
          );
        },
      ),
      ),
    );
  }

  Widget _buildSourceTruncationWarning(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: scheme.onTertiaryContainer,
            size: 18,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              '记录范围不完整：较早或超长的输入可能未包含在本次整理中。请补充遗漏内容并逐项核对，不要把未显示的信息理解为你没有相关症状。',
              style: TextStyle(
                color: scheme.onTertiaryContainer,
                fontSize: AppType.caption,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildConfirmedDraftPanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final draft = _confirmedDraft!;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '已核对的用户自述',
            style: TextStyle(fontSize: AppType.caption, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...draft.summaryLines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(line, style: const TextStyle(fontSize: AppType.caption, height: 1.4)),
            ),
          ),
          if (draft.sourceTruncated) ...[
            const SizedBox(height: AppSpacing.sm),
            _buildSourceTruncationWarning(context),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            '可将已核对自述带入规则问诊；自由文本不会被自动转换成辨证选项。',
            style: TextStyle(fontSize: AppType.micro, color: scheme.onSurfaceVariant),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: _structuredDiagnosisBusy
                  ? null
                  : _continueWithStructuredDiagnosis,
              icon: _structuredDiagnosisBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.fact_check_outlined),
              label: Text(
                _structuredDiagnosisBusy ? '正在准备问诊…' : '继续规则辨证',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _continueWithStructuredDiagnosis() async {
    final draft = _confirmedDraft;
    if (draft == null || _structuredDiagnosisBusy) return;
    await _startInlineTcmInterview(
      initialUserMessage: '继续规则辨证',
      userContext: draft.summaryLines.join('\\n'),
    );
  }

  Widget _buildModelPanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_checking) {
      return const LinearProgressIndicator(minHeight: 2);
    }
    if (_statusUnknown) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.help_outline, size: 18, color: scheme.error),
                const SizedBox(width: AppSpacing.sm),
                const Expanded(
                  child: Text(
                    '无法确认本地模型状态',
                    style: TextStyle(
                      fontSize: AppType.caption,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '为避免继续使用可能已失效的会话，问诊、模型加载和文件导入暂时停用。请重新检查原生模型状态。',
              style: TextStyle(
                fontSize: AppType.caption,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: () => _refreshStatus(showProgress: true),
              icon: const Icon(Icons.refresh),
              label: const Text('重新检查状态'),
            ),
          ],
        ),
      );
    }

    final status = _status;
    final ready = status?.ready == true;
    final installed = status?.installed == true;
    final backendLabel = status?.backend.toUpperCase() ?? '';
    final modelSizeLabel = status?.sizeLabel ?? '';
    final hashVerified = status?.hashVerified ?? false;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ready ? Icons.memory : Icons.download_done_outlined,
                size: 18,
                color: ready ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  ready
                      ? 'Gemma 4 E4B · ${backendLabel}'
                      : installed
                          ? '模型已放入设备，尚未加载'
                          : '等待安装 Gemma 4 E4B 模型',
                  style: const TextStyle(fontSize: AppType.caption, fontWeight: FontWeight.w600),
                ),
              ),
              if (ready)
                Text(
                  modelSizeLabel,
                  style: TextStyle(fontSize: AppType.caption, color: scheme.onSurfaceVariant),
                ),
            ],
          ),
          if (!ready) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              installed
                  ? hashVerified
                      ? '模型文件大小与 SHA-256 均已通过校验：${modelSizeLabel}。'
                      : '模型文件大小符合要求：${modelSizeLabel}。首次加载前仍会校验 SHA-256。'
                  : status?.fileExists == true
                      ? '检测到模型文件，但大小不符合要求。请重新选择完整模型文件。'
                      : '模型约 3.66 GB，需从设备本地导入；不会随 APK 打包或自动联网下载。',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: AppType.caption, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: installed &&
                          !_attachmentBusy &&
                          !_modelControlBusy &&
                          !_loading &&
                          !_importingModel
                      ? _loadModel
                      : null,
                  child: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('加载本地模型'),
                ),
                OutlinedButton.icon(
                  onPressed: !_attachmentBusy &&
                          !_modelControlBusy &&
                          !_loading &&
                          !_importingModel
                      ? _importModel
                      : null,
                  icon: _importingModel
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.folder_open_outlined),
                  label: Text(_importingModel ? '正在导入…' : '选择并导入模型文件'),
                ),
              ],
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: AppSpacing.xs),
              dense: true,
              title: const Text(
                '模型文件位置与校验说明',
                style: TextStyle(fontSize: AppType.caption),
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    status?.modelPath ??
                        'Android 应用私有目录 /files/ai_models/gemma-4-E4B-it.litertlm',
                    style: TextStyle(
                      fontSize: AppType.micro,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _loading
                        ? '首次加载前正在核对约 3.66 GB 模型文件的 SHA-256。请保持应用在前台；当前文件版本验证通过后，同一进程内重新加载不会重复扫描。'
                        : _importingModel
                            ? '正在导入并校验文件，请保持应用在前台并确保设备有足够可用空间。'
                            : '导入时在本机流式复制并校验文件大小与 SHA-256；首次加载前也会核验文件完整性。不会上传模型或请求模型服务。',
                    style: TextStyle(
                      fontSize: AppType.micro,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TcmInterviewMessagePersistenceResult {
  const _TcmInterviewMessagePersistenceResult({
    required this.transcriptMessagesApplicable,
    required this.transcriptMessagesPersisted,
  });

  const _TcmInterviewMessagePersistenceResult.notApplicable()
      : transcriptMessagesApplicable = false,
        transcriptMessagesPersisted = false;

  final bool transcriptMessagesApplicable;
  final bool transcriptMessagesPersisted;
}

class _InterviewMessage {
  final String text;
  final bool isUser;
  final String? actionLabel;
  final VoidCallback? onAction;
  final List<String> options;
  final ValueChanged<String>? onOptionSelected;
  final List<String> sourceIds;
  final ValueChanged<String>? onSourceTap;
  final String? knowledgeStatus;
  final DiagnosisResult? diagnosisResult;
  final VoidCallback? onBookmark;
  final VoidCallback? onShare;
  final VoidCallback? onCopyPrescription;

  const _InterviewMessage({
    required this.text,
    required this.isUser,
    this.actionLabel,
    this.onAction,
    this.options = const [],
    this.onOptionSelected,
    this.sourceIds = const [],
    this.onSourceTap,
    this.knowledgeStatus,
    this.diagnosisResult,
    this.onBookmark,
    this.onShare,
    this.onCopyPrescription,
  });
}

bool _isNavigableKnowledgeSourceId(String sourceId) {
  final kind = sourceId.split(':').first;
  return const {
    'formula',
    'herb',
    'acupoint',
    'acupuncture',
    'medical_case',
    'neijing',
    'shanghan',
    'jingui',
    'guji',
    'zhenjiu',
  }.contains(kind);
}

String _knowledgeSourceLabel(String sourceId) {
  final parts = sourceId.split(':');
  final kind = parts.isEmpty ? '' : parts.first;
  final value = parts.length > 1 ? parts.sublist(1).join(':') : '';
  return switch (kind) {
    'formula' => '方剂：$value',
    'herb' => '本草：$value',
    'acupoint' => '穴位：$value',
    'acupuncture' => '针灸来源：$value',
    'medical_case' => '医案 #$value',
    'neijing' => '内经条目',
    'shanghan' => '伤寒论：$value',
    'jingui' => '金匮要略：$value',
    'guji' => '古籍原文：$value',
    'zhenjiu' => '针灸讲稿：$value',
    _ => '来源：$sourceId',
  };
}


class _KnowledgeStatusLabel extends StatelessWidget {
  const _KnowledgeStatusLabel({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      'RETRIEVED' => '知识检索：已检索到来源',
      'PARTIAL' => '知识检索：部分结果',
      'NO_RESULTS' => '知识检索：无匹配结果',
      'FAILED' => '知识检索：执行失败',
      _ => '知识检索：状态未知（$status）',
    };
    final color = switch (status) {
      'RETRIEVED' => Theme.of(context).colorScheme.primary,
      'PARTIAL' => Theme.of(context).colorScheme.tertiary,
      'FAILED' => Theme.of(context).colorScheme.error,
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        label,
        style: TextStyle(fontSize: AppType.micro, color: color),
      ),
    );
  }
}

class _InterviewMessageBubble extends StatelessWidget {
  final _InterviewMessage message;

  const _InterviewMessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final bubbleMaxWidth = availableWidth.isFinite
            ? availableWidth * 0.94
            : MediaQuery.sizeOf(context).width * 0.94;
        return Align(
          alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(maxWidth: bubbleMaxWidth),
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: message.isUser
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText(
                  message.text,
                  style: TextStyle(
                    color: message.isUser ? scheme.onPrimaryContainer : scheme.onSurface,
                    fontSize: AppType.body,
                    height: 1.55,
                  ),
                ),
                if (message.knowledgeStatus != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  _KnowledgeStatusLabel(status: message.knowledgeStatus!),
                ],
                if (message.sourceIds.any(_isNavigableKnowledgeSourceId) &&
                    message.onSourceTap != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: message.sourceIds
                        .where(_isNavigableKnowledgeSourceId)
                        .map((sourceId) => ActionChip(
                              avatar: const Icon(Icons.link, size: 14),
                              label: Text(_knowledgeSourceLabel(sourceId)),
                              onPressed: () => message.onSourceTap!(sourceId),
                            ))
                        .toList(),
                  ),
                ],
                if (message.options.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: message.options.map((option) => ActionChip(
                      label: Text(option),
                      onPressed: message.onOptionSelected == null
                          ? null
                          : () => message.onOptionSelected!(option),
                    )).toList(),
                  ),
                ],
                if (message.diagnosisResult != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.bookmark_add_outlined, size: 16),
                        label: const Text('收藏辨证结果'),
                        onPressed: message.onBookmark,
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.share_outlined, size: 16),
                        label: const Text('分享辨证结果'),
                        onPressed: message.onShare,
                      ),
                      if (message.diagnosisResult!.prescription != null)
                        ActionChip(
                          avatar: const Icon(Icons.content_copy, size: 16),
                          label: const Text('复制处方'),
                          onPressed: message.onCopyPrescription,
                        ),
                    ],
                  ),
                ],
                if (message.actionLabel != null && message.onAction != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: message.onAction,
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: Text(message.actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Blocks the first route-pop attempt long enough to translate a null/back
/// exit into a typed cancellation, while preserving non-null results returned
/// by legacy tool pages. A second pop is issued only after PopScope rebuilds
/// with canPop=true; calling Navigator.pop from inside a blocked callback would
/// otherwise be blocked by the same PopScope again.
class _AssistantToolRouteGuard extends StatefulWidget {
  const _AssistantToolRouteGuard({
    required this.child,
    required this.cancellationResult,
  });

  final Widget child;
  final AssistantToolResult cancellationResult;

  @override
  State<_AssistantToolRouteGuard> createState() =>
      _AssistantToolRouteGuardState();
}

class _AssistantToolRouteGuardState extends State<_AssistantToolRouteGuard> {
  bool _allowPop = false;
  bool _popScheduled = false;

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _popScheduled) return;
        _popScheduled = true;
        setState(() => _allowPop = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.of(context).pop(
            result ?? widget.cancellationResult,
          );
        });
      },
      child: widget.child,
    );
  }
}
), '');
      final cancelRequested = const {
        '取消关煞',
        '取消测算',
        '停止测算',
        '先不算',
        '算了',
        '取消',
      }.contains(cancelText);
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.succeeded,
        route: cancelRequested
            ? 'tool_cancel:guansha'
            : 'tool_follow_up:guansha',
        mode: AssistantMode.metaphysics.name,
        toolId: 'guansha',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.dispatch,
        status: AiTraceStatus.succeeded,
        route: cancelRequested
            ? 'tool_cancel:guansha'
            : 'tool_follow_up:guansha',
        mode: AssistantMode.metaphysics.name,
        toolId: 'guansha',
      );
      if (cancelRequested) {
        const reply = '已取消本次小儿关煞测算；尚未执行任何计算。';
        setState(() {
          _pendingGuanshaArguments = null;
          _messages
            ..add(_InterviewMessage(text: text, isUser: true))
            ..add(const _InterviewMessage(text: reply, isUser: false));
          _error = null;
        });
        _inputController.clear();
        final persisted = await _persistSuccessfulTurn(
          userText: text,
          assistantText: reply,
          mode: AssistantMode.metaphysics,
          toolId: 'guansha',
          toolStatus: AssistantToolExecutionStatus.cancelled.name.toUpperCase(),
          toolArguments: pendingGuansha.values,
          traceId: traceId,
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.persistence,
          status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
          toolId: 'guansha',
          errorCode: persisted ? null : 'PERSISTENCE_FAILED',
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.succeeded,
          toolId: 'guansha',
        );
        _scrollToBottom();
        return;
      }
      final followUp = AssistantConversationOrchestrator.argumentsFor(
        AssistantToolRouter.guansha,
        text,
      );
      final mergedArguments = <String, String>{
        ...pendingGuansha.values,
        ...followUp.values,
      };
      await _requestTool(
        text,
        AssistantToolRouter.guansha,
        mode: _lastEffectiveMode ?? AssistantMode.metaphysics,
        arguments: AssistantToolArguments(
          toolId: 'guansha',
          values: Map<String, String>.unmodifiable(mergedArguments),
        ),
        traceContext: traceContext,
      );
      return;
    }

    final pendingZiwei = _pendingZiweiArguments;
    if (pendingZiwei != null && (imagePath != null || audioPath != null)) {
      setState(() {
        _error = '紫微排盘需要文本出生资料。请用文字补齐公历出生日期、出生时间、性别和出生地点，或发送“取消紫微”结束本次排盘。';
      });
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.failed,
        route: 'tool_follow_up:ziwei_attachment_rejected',
        mode: AssistantMode.metaphysics.name,
        toolId: 'ziwei',
        errorCode: 'ZIWEI_PARAMETERS_REQUIRE_TEXT',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.succeeded,
        mode: AssistantMode.metaphysics.name,
        toolId: 'ziwei',
      );
      return;
    }
    if (pendingZiwei != null && text.isNotEmpty) {
      final cancelRequested = const {
        '取消紫微',
        '取消排盘',
        '停止排盘',
        '算了',
        '取消',
        '先不排',
      }.contains(text.trim());
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.succeeded,
        route: cancelRequested ? 'tool_cancel:ziwei' : 'tool_follow_up:ziwei',
        mode: AssistantMode.metaphysics.name,
        toolId: 'ziwei',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.dispatch,
        status: AiTraceStatus.succeeded,
        route: cancelRequested ? 'tool_cancel:ziwei' : 'tool_follow_up:ziwei',
        mode: AssistantMode.metaphysics.name,
        toolId: 'ziwei',
      );
      if (cancelRequested) {
        const reply = '已取消本次紫微排盘；尚未执行任何计算。';
        setState(() {
          _pendingZiweiArguments = null;
          _messages
            ..add(_InterviewMessage(text: text, isUser: true))
            ..add(const _InterviewMessage(text: reply, isUser: false));
          _error = null;
        });
        _inputController.clear();
        final persisted = await _persistSuccessfulTurn(
          userText: text,
          assistantText: reply,
          mode: AssistantMode.metaphysics,
          toolId: 'ziwei',
          toolStatus: AssistantToolExecutionStatus.cancelled.name.toUpperCase(),
          toolArguments: pendingZiwei.values,
          traceId: traceId,
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.persistence,
          status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
          toolId: 'ziwei',
          errorCode: persisted ? null : 'PERSISTENCE_FAILED',
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.succeeded,
          toolId: 'ziwei',
        );
        _scrollToBottom();
        return;
      }
      final followUp = AssistantConversationOrchestrator.argumentsFor(
        AssistantToolRouter.ziwei,
        text,
      );
      final mergedArguments = <String, String>{
        ...pendingZiwei.values,
        ...followUp.values,
      };
      await _requestTool(
        text,
        AssistantToolRouter.ziwei,
        mode: _lastEffectiveMode ?? AssistantMode.metaphysics,
        arguments: AssistantToolArguments(
          toolId: 'ziwei',
          values: Map<String, String>.unmodifiable(mergedArguments),
        ),
        traceContext: traceContext,
      );
      return;
    }

    final pendingBazi = _pendingBaziArguments;
    if (pendingBazi != null && (imagePath != null || audioPath != null)) {
      setState(() {
        _error = '八字排盘需要文本出生资料。请先用文字补齐出生日期、时间、性别和出生地点，或发送“取消”结束本次排盘。';
      });
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.failed,
        route: 'tool_follow_up:bazi_attachment_rejected',
        mode: AssistantMode.metaphysics.name,
        toolId: 'bazi',
        errorCode: 'BAZI_PARAMETERS_REQUIRE_TEXT',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.succeeded,
        mode: AssistantMode.metaphysics.name,
        toolId: 'bazi',
      );
      return;
    }
    if (pendingBazi != null && text.isNotEmpty) {
      final cancelRequested =
          ['取消', '算了', '先不排', '不用排了', '停止排盘'].any(text.contains);
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.succeeded,
        route: cancelRequested ? 'tool_cancel:bazi' : 'tool_follow_up:bazi',
        mode: AssistantMode.metaphysics.name,
        toolId: 'bazi',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.dispatch,
        status: AiTraceStatus.succeeded,
        route: cancelRequested ? 'tool_cancel:bazi' : 'tool_follow_up:bazi',
        mode: AssistantMode.metaphysics.name,
        toolId: 'bazi',
      );
      if (cancelRequested) {
        const reply = '已取消本次八字排盘；尚未执行任何计算。';
        setState(() {
          _pendingBaziArguments = null;
          _pendingZiweiArguments = null;
          _messages
            ..add(_InterviewMessage(text: text, isUser: true))
            ..add(const _InterviewMessage(text: reply, isUser: false));
          _error = null;
        });
        _inputController.clear();
        final persisted = await _persistSuccessfulTurn(
          userText: text,
          assistantText: reply,
          mode: AssistantMode.metaphysics,
          toolId: 'bazi',
          toolStatus: AssistantToolExecutionStatus.cancelled.name.toUpperCase(),
          toolArguments: pendingBazi.values,
          traceId: traceId,
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.persistence,
          status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
          toolId: 'bazi',
          errorCode: persisted ? null : 'PERSISTENCE_FAILED',
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.succeeded,
          toolId: 'bazi',
        );
        _scrollToBottom();
        return;
      }
      final followUp = AssistantConversationOrchestrator.argumentsFor(
        AssistantToolRouter.bazi,
        text,
      );
      final mergedArguments = <String, String>{
        ...pendingBazi.values,
        ...followUp.values,
      };
      await _requestTool(
        text,
        AssistantToolRouter.bazi,
        mode: _lastEffectiveMode ?? AssistantMode.metaphysics,
        arguments: AssistantToolArguments(
          toolId: 'bazi',
          values: Map<String, String>.unmodifiable(mergedArguments),
        ),
        traceContext: traceContext,
      );
      return;
    }

    final pendingXiaoliuren = _pendingXiaoliurenArguments;
    if (pendingXiaoliuren != null &&
        (imagePath != null || audioPath != null)) {
      setState(() {
        _error = '小六壬起课需要文字资料。请用文字补齐公历日期、时辰和起课口径，或发送“取消小六壬”结束本次起课。';
      });
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.failed,
        route: 'tool_follow_up:xiaoliuren_attachment_rejected',
        mode: AssistantMode.metaphysics.name,
        toolId: 'xiaoliuren',
        errorCode: 'XIAOLIUREN_PARAMETERS_REQUIRE_TEXT',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.succeeded,
        mode: AssistantMode.metaphysics.name,
        toolId: 'xiaoliuren',
      );
      return;
    }
    if (pendingXiaoliuren != null && text.isNotEmpty) {
      final cancelText =
          text.trim().replaceAll(RegExp(r'[，。.!！?？]+$'), '');
      final cancelRequested = const {
        '取消小六壬',
        '取消起课',
        '停止起课',
        '算了',
        '先不算',
        '取消',
      }.contains(cancelText);
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.succeeded,
        route: cancelRequested
            ? 'tool_cancel:xiaoliuren'
            : 'tool_follow_up:xiaoliuren',
        mode: AssistantMode.metaphysics.name,
        toolId: 'xiaoliuren',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.dispatch,
        status: AiTraceStatus.succeeded,
        route: cancelRequested
            ? 'tool_cancel:xiaoliuren'
            : 'tool_follow_up:xiaoliuren',
        mode: AssistantMode.metaphysics.name,
        toolId: 'xiaoliuren',
      );
      if (cancelRequested) {
        const reply = '已取消本次小六壬起课；尚未执行任何计算。';
        setState(() {
          _pendingXiaoliurenArguments = null;
          _messages
            ..add(_InterviewMessage(text: text, isUser: true))
            ..add(const _InterviewMessage(text: reply, isUser: false));
          _error = null;
        });
        _inputController.clear();
        final persisted = await _persistSuccessfulTurn(
          userText: text,
          assistantText: reply,
          mode: AssistantMode.metaphysics,
          toolId: 'xiaoliuren',
          toolStatus: AssistantToolExecutionStatus.cancelled.name.toUpperCase(),
          toolArguments: pendingXiaoliuren.values,
          traceId: traceId,
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.persistence,
          status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
          toolId: 'xiaoliuren',
          errorCode: persisted ? null : 'PERSISTENCE_FAILED',
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.succeeded,
          toolId: 'xiaoliuren',
        );
        _scrollToBottom();
        return;
      }
      final followUp = AssistantConversationOrchestrator.argumentsFor(
        AssistantToolRouter.xiaoliuren,
        text,
      );
      final mergedArguments = <String, String>{
        ...pendingXiaoliuren.values,
        ...followUp.values,
      };
      await _requestTool(
        text,
        AssistantToolRouter.xiaoliuren,
        mode: _lastEffectiveMode ?? AssistantMode.metaphysics,
        arguments: AssistantToolArguments(
          toolId: 'xiaoliuren',
          values: Map<String, String>.unmodifiable(mergedArguments),
        ),
        traceContext: traceContext,
      );
      return;
    }

    final pendingZiWu = _pendingZiWuArguments;
    if (pendingZiWu != null &&
        (imagePath != null || audioPath != null)) {
      setState(() {
        _error = '子午流注计算需要明确的公历日期和本地时刻，请用文字补充；也可以发送“取消子午流注”结束本次操作。';
      });
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.failed,
        route: 'tool_follow_up:ziwu_attachment_rejected',
        mode: AssistantMode.tools.name,
        toolId: 'ziwu_liuzhu',
        errorCode: 'ZIWU_PARAMETERS_REQUIRE_TEXT',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.succeeded,
        mode: AssistantMode.tools.name,
        toolId: 'ziwu_liuzhu',
      );
      return;
    }
    if (pendingZiWu != null && text.isNotEmpty) {
      final cancelText =
          text.trim().replaceAll(RegExp(r'[，。.!！?？]+$'), '');
      final cancelRequested = const {
        '取消子午流注',
        '取消时辰开穴',
        '取消开穴计算',
        '停止计算',
        '算了',
        '先不算',
        '取消',
      }.contains(cancelText);
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.succeeded,
        route: cancelRequested ? 'tool_cancel:ziwu_liuzhu' : 'tool_follow_up:ziwu_liuzhu',
        mode: AssistantMode.tools.name,
        toolId: 'ziwu_liuzhu',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.dispatch,
        status: AiTraceStatus.succeeded,
        route: cancelRequested ? 'tool_cancel:ziwu_liuzhu' : 'tool_follow_up:ziwu_liuzhu',
        mode: AssistantMode.tools.name,
        toolId: 'ziwu_liuzhu',
      );
      if (cancelRequested) {
        const reply = '已取消本次子午流注计算；尚未执行计算。';
        setState(() {
          _pendingZiWuArguments = null;
          _messages
            ..add(_InterviewMessage(text: text, isUser: true))
            ..add(const _InterviewMessage(text: reply, isUser: false));
          _error = null;
        });
        _inputController.clear();
        final persisted = await _persistSuccessfulTurn(
          userText: text,
          assistantText: reply,
          mode: AssistantMode.tools,
          toolId: 'ziwu_liuzhu',
          toolStatus: AssistantToolExecutionStatus.cancelled.name.toUpperCase(),
          toolArguments: pendingZiWu.values,
          traceId: traceId,
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.persistence,
          status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
          toolId: 'ziwu_liuzhu',
          errorCode: persisted ? null : 'PERSISTENCE_FAILED',
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.succeeded,
          toolId: 'ziwu_liuzhu',
        );
        _scrollToBottom();
        return;
      }
      final followUp = AssistantConversationOrchestrator.argumentsFor(
        AssistantToolRouter.ziwu,
        text,
      );
      final mergedArguments = <String, String>{
        ...pendingZiWu.values,
        ...followUp.values,
      };
      await _requestTool(
        text,
        AssistantToolRouter.ziwu,
        mode: AssistantMode.tools,
        arguments: AssistantToolArguments(
          toolId: 'ziwu_liuzhu',
          values: Map<String, String>.unmodifiable(mergedArguments),
        ),
        traceContext: traceContext,
      );
      return;
    }

    final pendingDosage = _pendingDosageArguments;
    if (pendingDosage != null &&
        (imagePath != null || audioPath != null)) {
      setState(() {
        _error = '经方换算只需要文字数值、单位和必要的度量标准；请用文字补充，或发送“取消剂量换算”结束本次操作。';
      });
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.failed,
        route: 'tool_follow_up:dosage_attachment_rejected',
        mode: AssistantMode.tools.name,
        toolId: 'dosage',
        errorCode: 'DOSAGE_PARAMETERS_REQUIRE_TEXT',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.succeeded,
        mode: AssistantMode.tools.name,
        toolId: 'dosage',
      );
      return;
    }
    if (pendingDosage != null && text.isNotEmpty) {
      final cancelText =
          text.trim().replaceAll(RegExp(r'[，。.!！?？]+$'), '');
      final cancelRequested = const {
        '取消剂量换算',
        '取消换算',
        '停止换算',
        '算了',
        '先不算',
        '取消',
      }.contains(cancelText);
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.succeeded,
        route: cancelRequested ? 'tool_cancel:dosage' : 'tool_follow_up:dosage',
        mode: AssistantMode.tools.name,
        toolId: 'dosage',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.dispatch,
        status: AiTraceStatus.succeeded,
        route: cancelRequested ? 'tool_cancel:dosage' : 'tool_follow_up:dosage',
        mode: AssistantMode.tools.name,
        toolId: 'dosage',
      );
      if (cancelRequested) {
        const reply = '已取消本次单位换算；尚未执行计算。';
        setState(() {
          _pendingDosageArguments = null;
          _messages
            ..add(_InterviewMessage(text: text, isUser: true))
            ..add(const _InterviewMessage(text: reply, isUser: false));
          _error = null;
        });
        _inputController.clear();
        final persisted = await _persistSuccessfulTurn(
          userText: text,
          assistantText: reply,
          mode: AssistantMode.tools,
          toolId: 'dosage',
          toolStatus: AssistantToolExecutionStatus.cancelled.name.toUpperCase(),
          toolArguments: pendingDosage.values,
          traceId: traceId,
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.persistence,
          status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
          toolId: 'dosage',
          errorCode: persisted ? null : 'PERSISTENCE_FAILED',
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.succeeded,
          toolId: 'dosage',
        );
        _scrollToBottom();
        return;
      }
      final followUp = AssistantConversationOrchestrator.argumentsFor(
        AssistantToolRouter.dosage,
        text,
      );
      final mergedArguments = <String, String>{
        ...pendingDosage.values,
        ...followUp.values,
      };
      await _requestTool(
        text,
        AssistantToolRouter.dosage,
        mode: AssistantMode.tools,
        arguments: AssistantToolArguments(
          toolId: 'dosage',
          values: Map<String, String>.unmodifiable(mergedArguments),
        ),
        traceContext: traceContext,
      );
      return;
    }

    final pendingYiJing = _pendingYiJingArguments;
    if (pendingYiJing != null && (imagePath != null || audioPath != null)) {
      setState(() {
        _error = '易经起卦参数请用文字补充；铜钱摇卦由 App 自动投掷，无需上传结果。也可以发送“取消易经起卦”结束本次操作。';
      });
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.failed,
        route: 'tool_follow_up:yijing_attachment_rejected',
        mode: AssistantMode.metaphysics.name,
        toolId: 'yijing',
        errorCode: 'YIJING_PARAMETERS_REQUIRE_TEXT',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.succeeded,
        mode: AssistantMode.metaphysics.name,
        toolId: 'yijing',
      );
      return;
    }
    if (pendingYiJing != null && text.isNotEmpty) {
      final cancelText =
          text.trim().replaceAll(RegExp(r'[，。.!！?？]+$'), '');
      final cancelRequested = const {
        '取消易经',
        '取消易经起卦',
        '取消起卦',
        '停止起卦',
        '算了',
        '先不算',
        '取消',
      }.contains(cancelText);
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.succeeded,
        route: cancelRequested ? 'tool_cancel:yijing' : 'tool_follow_up:yijing',
        mode: AssistantMode.metaphysics.name,
        toolId: 'yijing',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.dispatch,
        status: AiTraceStatus.succeeded,
        route: cancelRequested ? 'tool_cancel:yijing' : 'tool_follow_up:yijing',
        mode: AssistantMode.metaphysics.name,
        toolId: 'yijing',
      );
      if (cancelRequested) {
        const reply = '已取消本次易经起卦；尚未执行任何计算。';
        setState(() {
          _pendingYiJingArguments = null;
          _pendingDosageArguments = null;
          _messages
            ..add(_InterviewMessage(text: text, isUser: true))
            ..add(const _InterviewMessage(text: reply, isUser: false));
          _error = null;
        });
        _inputController.clear();
        final persisted = await _persistSuccessfulTurn(
          userText: text,
          assistantText: reply,
          mode: AssistantMode.metaphysics,
          toolId: 'yijing',
          toolStatus: AssistantToolExecutionStatus.cancelled.name.toUpperCase(),
          toolArguments: pendingYiJing.values,
          traceId: traceId,
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.persistence,
          status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
          toolId: 'yijing',
          errorCode: persisted ? null : 'PERSISTENCE_FAILED',
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.succeeded,
          toolId: 'yijing',
        );
        _scrollToBottom();
        return;
      }
      final followUp = AssistantConversationOrchestrator.argumentsFor(
        AssistantToolRouter.yijing,
        text,
      );
      final mergedArguments = <String, String>{
        ...pendingYiJing.values,
        ...followUp.values,
      };
      await _requestTool(
        text,
        AssistantToolRouter.yijing,
        mode: _lastEffectiveMode ?? AssistantMode.metaphysics,
        arguments: AssistantToolArguments(
          toolId: 'yijing',
          values: Map<String, String>.unmodifiable(mergedArguments),
        ),
        traceContext: traceContext,
      );
      return;
    }

    var effectiveMode = _assistantMode;
    if (text.isNotEmpty && imagePath == null && audioPath == null) {
      var decision = AssistantConversationOrchestrator.resolve(
        query: text,
        selectedMode: _assistantMode,
        currentMode: _lastEffectiveMode,
        pendingToolSelection: _pendingToolSelection,
      );
      final mayUseBoundedIntentModel =
          decision.candidateTools.length >= 2 &&
          (decision.mode == AssistantMode.tools ||
              decision.mode == AssistantMode.metaphysics) &&
          !AssistantConversationOrchestrator.shouldExcludeFromIntentModel(text) &&
          _status?.ready == true;
      if (mayUseBoundedIntentModel && traceId != null) {
        setState(() => _sending = true);
        try {
          final resolution = await _service.resolveAssistantIntentWithTrace(
            query: text,
            candidates: decision.candidateTools
                .map(
                  (tool) => LocalAiIntentCandidate(
                    id: tool.id,
                    title: tool.title,
                    description: tool.description,
                  ),
                )
                .toList(growable: false),
            traceId: traceId,
          );
          await _traceRecorder.record(
            traceContext,
            stage: AiTraceStage.nativeInference,
            status: AiTraceStatus.succeeded,
            route: 'bounded_intent_selection',
            mode: decision.mode.name,
          );
          await _traceRecorder.record(
            traceContext,
            stage: AiTraceStage.modelOutput,
            status: AiTraceStatus.succeeded,
            route: 'bounded_intent_selection',
            mode: decision.mode.name,
          );
          await _traceRecorder.record(
            traceContext,
            stage: AiTraceStage.resultValidation,
            status: AiTraceStatus.succeeded,
            route: 'bounded_intent_selection:${resolution.action.name}',
            mode: decision.mode.name,
          );
          if (resolution.action == LocalAiIntentAction.select) {
            AssistantToolDefinition? selectedTool;
            for (final candidate in decision.candidateTools) {
              if (candidate.id == resolution.toolId) {
                selectedTool = candidate;
                break;
              }
            }
            if (selectedTool != null) {
              decision = AssistantDispatchDecision(
                mode: decision.mode,
                tool: selectedTool,
                toolArguments:
                    AssistantConversationOrchestrator.argumentsFor(
                  selectedTool,
                  text,
                ),
              );
            }
          }
        } catch (error) {
          // E4B is advisory only. A native failure or invalid schema falls
          // back to the deterministic L0 clarification; it never dispatches.
          await _traceRecorder.record(
            traceContext,
            stage: AiTraceStage.nativeInference,
            status: AiTraceStatus.unknown,
            route: 'bounded_intent_selection',
            mode: decision.mode.name,
            errorCode: 'INTENT_CLASSIFICATION_FAILED',
          );
          await _traceRecorder.record(
            traceContext,
            stage: AiTraceStage.modelOutput,
            status: AiTraceStatus.failed,
            route: 'bounded_intent_selection',
            mode: decision.mode.name,
            errorCode: 'INTENT_OUTPUT_INVALID',
          );
          await _traceRecorder.record(
            traceContext,
            stage: AiTraceStage.resultValidation,
            status: AiTraceStatus.notStarted,
            route: 'fallback_to_deterministic_l0',
            mode: decision.mode.name,
          );
        } finally {
          if (mounted) setState(() => _sending = false);
        }
        if (!mounted) return;
      }
      effectiveMode = decision.mode;
      _pendingToolSelection = decision.expectsToolSelection;
      final resolvedRoute = decision.needsClarification
          ? 'clarification'
          : decision.tool != null
              ? 'tool:${decision.tool!.id}'
              : 'model';
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.route,
        status: AiTraceStatus.succeeded,
        route: resolvedRoute,
        mode: effectiveMode.name,
        toolId: decision.tool?.id,
      );
      if (decision.needsClarification) {
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.dispatch,
          status: AiTraceStatus.succeeded,
          route: 'clarification',
          mode: effectiveMode.name,
        );
        final clarification = decision.clarification!;
        setState(() {
          _lastEffectiveMode = effectiveMode;
          _messages
            ..add(_InterviewMessage(text: text, isUser: true))
            ..add(_InterviewMessage(text: clarification, isUser: false));
          _error = null;
        });
        _inputController.clear();
        final persisted = await _persistSuccessfulTurn(
          userText: text,
          assistantText: clarification,
          mode: effectiveMode,
          expectsToolSelection: decision.expectsToolSelection,
          traceId: traceId,
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.persistence,
          status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
          errorCode: persisted ? null : 'PERSISTENCE_FAILED',
        );
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.succeeded,
        );
        _scrollToBottom();
        return;
      }
      if (decision.tool != null) {
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.dispatch,
          status: AiTraceStatus.succeeded,
          route: 'tool',
          mode: effectiveMode.name,
          toolId: decision.tool!.id,
        );
        await _requestTool(
          text,
          decision.tool!,
          mode: effectiveMode,
          arguments: decision.toolArguments,
          traceContext: traceContext,
        );
        return;
      }
    } else if (_assistantMode == AssistantMode.automatic) {
      // 照片/语音附件默认进入问诊域；不凭附件类型猜测排盘或学习任务。
      _pendingToolSelection = false;
      effectiveMode = AssistantMode.consultation;
    }
    if (_status?.ready != true) {
      setState(() => _error = '本地模型尚未加载。可以先使用上方 App 内置工具；AI 对话请先加载 Gemma 4 E4B。');
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.succeeded,
        mode: effectiveMode.name,
        errorCode: 'LOCAL_MODEL_NOT_READY',
      );
      return;
    }

    final userLabel = text.isNotEmpty
        ? text
        : imagePath != null
            ? '已附加一张舌象照片'
            : '已录制一段语音';
    setState(() {
      _lastEffectiveMode = effectiveMode;
      _messages.add(_InterviewMessage(text: userLabel, isUser: true));
      _sending = true;
      _error = null;
    });
    _scrollToBottom();

    var nativeInferenceCompleted = false;
    var resultValidationCompleted = false;
    var persistenceStarted = false;
    var persistenceRecorded = false;
    try {
      final turnResponse = audioPath != null
          ? _AssistantTurnResponse(
              text: traceId == null
                  ? await _service.sendAudio(audioPath, prompt: text)
                  : await _service.sendAudioWithTrace(
                      audioPath,
                      prompt: text,
                      traceId: traceId,
                    ),
            )
          : imagePath != null
              ? _AssistantTurnResponse(
                  text: traceId == null
                  ? await _service.sendImage(imagePath, prompt: text)
                  : await _service.sendImageWithTrace(
                      imagePath,
                      prompt: text,
                      traceId: traceId,
                    ),
                )
              : await _sendTextWithKnowledgeContext(
                  text,
                  mode: effectiveMode,
                  traceContext: traceContext,
                );
      final reply = turnResponse.text;
      nativeInferenceCompleted = true;
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.nativeInference,
        status: AiTraceStatus.succeeded,
        mode: effectiveMode.name,
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.modelOutput,
        status: AiTraceStatus.succeeded,
        mode: effectiveMode.name,
        sourceIds: turnResponse.sourceIds,
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.resultValidation,
        status: AiTraceStatus.succeeded,
        mode: effectiveMode.name,
        sourceIds: turnResponse.sourceIds,
      );
      resultValidationCompleted = true;
      persistenceStarted = true;
      final persisted = await _persistSuccessfulTurn(
        userText: text,
        assistantText: reply,
        mode: effectiveMode,
        traceId: traceId,
        attachmentType: audioPath != null ? '录音' : imagePath != null ? '照片' : null,
        sourceIds: turnResponse.sourceIds,
        knowledgeStatus: turnResponse.knowledgeStatus,
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.persistence,
        status: persisted ? AiTraceStatus.succeeded : AiTraceStatus.failed,
        mode: effectiveMode.name,
        sourceIds: turnResponse.sourceIds,
        errorCode: persisted ? null : 'PERSISTENCE_FAILED',
      );
      persistenceRecorded = true;
      await _deleteCachedAttachments([imagePath, audioPath]);
      final refreshedStatus = await _readNativeStatus();
      if (!mounted) {
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.notApplicable,
          mode: effectiveMode.name,
          errorCode: 'SCREEN_DISPOSED',
        );
        return;
      }
      _inputController.clear();
      final nativeRuntimeUnavailable =
          refreshedStatus != null && !refreshedStatus.ready;
      setState(() {
        _status = refreshedStatus;
        _statusUnknown = refreshedStatus == null;
        if (nativeRuntimeUnavailable) {
          _messages
            ..clear()
            ..add(const _InterviewMessage(
              text: '本轮回复已生成，但原生模型已变为未加载状态。旧会话已结束；以下回复仅供查看，重新加载后请开始新对话。',
              isUser: false,
            ))
            ..add(_InterviewMessage(
              text: reply,
              isUser: false,
              sourceIds: turnResponse.sourceIds,
              onSourceTap: _openKnowledgeSource,
              knowledgeStatus: turnResponse.knowledgeStatus,
            ));
          _confirmedDraft = null;
        } else {
          _messages.add(_InterviewMessage(
            text: reply,
            isUser: false,
            sourceIds: turnResponse.sourceIds,
            onSourceTap: _openKnowledgeSource,
            knowledgeStatus: turnResponse.knowledgeStatus,
          ));
        }
        _sending = false;
        _imagePath = null;
        _audioPath = null;
        _error = refreshedStatus == null
            ? '本轮回复已生成，但无法确认本地模型状态。请重新检查后继续。'
            : null;
      });
      _scrollToBottom();
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.succeeded,
        mode: effectiveMode.name,
        sourceIds: turnResponse.sourceIds,
      );
    } on PlatformException catch (error) {
      final emptyReply = error.code == 'EMPTY_REPLY';
      final traceMismatch = error.code == 'TRACE_ID_MISMATCH';
      if (!nativeInferenceCompleted) {
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.nativeInference,
          status: emptyReply
              ? AiTraceStatus.succeeded
              : AiTraceStatus.unknown,
          mode: effectiveMode.name,
          errorCode: emptyReply
              ? null
              : traceMismatch
                  ? 'TRACE_ID_MISMATCH'
                  : 'NATIVE_CALL_FAILED',
        );
      }
      if (!resultValidationCompleted) {
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.resultValidation,
          status: emptyReply
              ? AiTraceStatus.failed
              : traceMismatch
                  ? AiTraceStatus.unknown
                  : AiTraceStatus.notStarted,
          mode: effectiveMode.name,
          errorCode: emptyReply
              ? 'MODEL_REPLY_INVALID'
              : traceMismatch
                  ? 'TRACE_ID_MISMATCH'
                  : null,
        );
      }
      if (!persistenceRecorded) {
        if (persistenceStarted) {
          await _traceRecorder.record(
            traceContext,
            stage: AiTraceStage.persistence,
            status: AiTraceStatus.unknown,
            mode: effectiveMode.name,
            errorCode: 'PERSISTENCE_STATE_UNKNOWN',
          );
        } else {
          await _recordTurnPersistenceNotStarted(
            traceContext,
            errorCode: 'NATIVE_TURN_NOT_PERSISTED',
            mode: effectiveMode.name,
          );
        }
      }
      final refreshedStatus = await _readNativeStatus();
      if (!mounted) {
        await _deleteCachedAttachments([imagePath, audioPath]);
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.notApplicable,
          mode: effectiveMode.name,
          errorCode: 'SCREEN_DISPOSED',
        );
        return;
      }
      setState(() {
        _status = refreshedStatus;
        _statusUnknown = refreshedStatus == null;
        if (_messages.isNotEmpty &&
            _messages.last.isUser &&
            _messages.last.text == userLabel) {
          _messages.removeLast();
        }
        final nativeRuntimeUnavailable =
            refreshedStatus != null && !refreshedStatus.ready;
        if (nativeRuntimeUnavailable) {
          _messages
            ..clear()
            ..add(const _InterviewMessage(
              text: '本地模型已变为未加载状态，旧会话已结束。编辑框中的内容和附件仍保留；重新加载后可重新发送。',
              isUser: false,
            ));
          _confirmedDraft = null;
        }
        _sending = false;
        final message = error.message ?? '本地推理失败';
        _error = refreshedStatus == null
            ? '$message；无法确认本地模型状态，请重新检查后继续。'
            : message;
      });
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.succeeded,
        mode: effectiveMode.name,
        errorCode: error.code,
      );
    } catch (error) {
      if (!nativeInferenceCompleted) {
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.nativeInference,
          status: AiTraceStatus.unknown,
          mode: effectiveMode.name,
          errorCode: 'NATIVE_CALL_FAILED',
        );
      }
      if (!resultValidationCompleted) {
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.resultValidation,
          status: nativeInferenceCompleted
              ? AiTraceStatus.unknown
              : AiTraceStatus.notStarted,
          mode: effectiveMode.name,
          errorCode: nativeInferenceCompleted ? 'RESULT_STATE_UNKNOWN' : null,
        );
      }
      if (!persistenceRecorded) {
        if (persistenceStarted) {
          await _traceRecorder.record(
            traceContext,
            stage: AiTraceStage.persistence,
            status: AiTraceStatus.unknown,
            mode: effectiveMode.name,
            errorCode: 'PERSISTENCE_STATE_UNKNOWN',
          );
        } else {
          await _recordTurnPersistenceNotStarted(
            traceContext,
            errorCode: 'NATIVE_TURN_NOT_PERSISTED',
            mode: effectiveMode.name,
          );
        }
      }
      final refreshedStatus = await _readNativeStatus();
      if (!mounted) {
        await _deleteCachedAttachments([imagePath, audioPath]);
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.finalRender,
          status: AiTraceStatus.notApplicable,
          mode: effectiveMode.name,
          errorCode: 'SCREEN_DISPOSED',
        );
        return;
      }
      setState(() {
        _status = refreshedStatus;
        _statusUnknown = refreshedStatus == null;
        if (_messages.isNotEmpty &&
            _messages.last.isUser &&
            _messages.last.text == userLabel) {
          _messages.removeLast();
        }
        final nativeRuntimeUnavailable =
            refreshedStatus != null && !refreshedStatus.ready;
        if (nativeRuntimeUnavailable) {
          _messages
            ..clear()
            ..add(const _InterviewMessage(
              text: '本地模型已变为未加载状态，旧会话已结束。编辑框中的内容和附件仍保留；重新加载后可重新发送。',
              isUser: false,
            ));
          _confirmedDraft = null;
        }
        _sending = false;
        _error = refreshedStatus == null
            ? '处理失败：$error；无法确认本地模型状态，请重新检查后继续。'
            : '处理失败：$error';
      });
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.finalRender,
        status: AiTraceStatus.succeeded,
        mode: effectiveMode.name,
        errorCode: persistenceStarted && !persistenceRecorded
            ? 'PERSISTENCE_STATE_UNKNOWN'
            : nativeInferenceCompleted
                ? 'RESULT_STATE_UNKNOWN'
                : 'NATIVE_CALL_FAILED',
      );
    }
  }

  Future<void> _extractSymptoms() async {
    if (_attachmentBusy || _modelControlBusy || _sending || _extracting) return;
    setState(() {
      _extracting = true;
      _error = null;
    });
    final traceContext = _traceRecorder.start(
      stage: AiTraceStage.input,
      route: 'symptom_extraction',
      mode: 'consultation',
    );
    Future<void> recordFinalRender({String? errorCode}) =>
        _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.finalRender,
          status: mounted
              ? AiTraceStatus.succeeded
              : AiTraceStatus.notApplicable,
          mode: 'consultation',
          errorCode: errorCode,
        );
    var nativeInferenceCompleted = false;
    var resultValidationCompleted = false;
    final userReportedText = _messages
        .where((message) => message.isUser)
        .map((message) => message.text)
        .join('\n');
    if (await _blockIfRedFlagPreflightDoesNotClear(
      source: RedFlagInputSource.structuredInterview,
      text: userReportedText.isEmpty ? null : userReportedText,
      traceContext: traceContext,
      route: 'symptom_extraction',
    )) {
      if (mounted) setState(() => _extracting = false);
      return;
    }
    try {
      final traceId = traceContext.traceId;
      final draft = traceId == null
          ? await _service.extractSymptoms()
          : await _service.extractSymptomsWithTrace(traceId: traceId);
      nativeInferenceCompleted = true;
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.nativeInference,
        status: AiTraceStatus.succeeded,
        mode: 'consultation',
      );
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.resultValidation,
        status: AiTraceStatus.succeeded,
        mode: 'consultation',
      );
      resultValidationCompleted = true;
      if (!mounted) {
        await recordFinalRender(errorCode: 'SCREEN_DISPOSED');
        return;
      }
      setState(() => _extracting = false);
      if (draft.summaryLines.isEmpty) {
        setState(() => _error = draft.sourceTruncated
            ? '原始输入记录曾被裁剪，但本次未提取到可核对内容。请补充遗漏描述后重新整理。'
            : '目前没有提取到明确的自述信息，请补充描述后再整理。');
        await recordFinalRender(errorCode: 'EMPTY_SYMPTOM_DRAFT');
        return;
      }

      final confirmed = await showFoldAwareDialog<bool>(
        context: context,
        builder: (dialogContext) {
          var checked = false;
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('核对症状整理'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '以下内容仅根据你提供的文字和待核对语音识别草稿整理，不包含舌象照片观察。请逐项核对；未提及的信息不会自动补全。',
                      style: TextStyle(fontSize: AppType.caption, height: 1.45),
                    ),
                    if (draft.sourceTruncated) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _buildSourceTruncationWarning(context),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    ...draft.summaryLines.map(
                      (line) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Text(line, style: const TextStyle(fontSize: AppType.caption)),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: checked,
                      onChanged: (value) =>
                          setDialogState(() => checked = value == true),
                      title: const Text(
                        '我已核对，内容符合我的实际描述',
                        style: TextStyle(fontSize: AppType.caption),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('返回修改'),
                ),
                FilledButton(
                  onPressed: checked
                      ? () => Navigator.pop(dialogContext, true)
                      : null,
                  child: const Text('确认这份整理'),
                ),
              ],
            ),
          );
        },
      );

      if (!mounted || confirmed != true) {
        await recordFinalRender(
          errorCode: mounted ? 'USER_CANCELLED_DRAFT_REVIEW' : 'SCREEN_DISPOSED',
        );
        return;
      }
      setState(() {
        _confirmedDraft = draft;
      });
      await recordFinalRender();
    } on PlatformException catch (error) {
      final traceMismatch = error.code == 'TRACE_ID_MISMATCH';
      final emptyReply = error.code == 'EMPTY_REPLY';
      if (!nativeInferenceCompleted) {
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.nativeInference,
          status: emptyReply
              ? AiTraceStatus.succeeded
              : AiTraceStatus.unknown,
          mode: 'consultation',
          errorCode: traceMismatch
              ? 'TRACE_ID_MISMATCH'
              : emptyReply
                  ? null
                  : 'NATIVE_CALL_FAILED',
        );
      }
      if (!resultValidationCompleted) {
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.resultValidation,
          status: emptyReply
              ? AiTraceStatus.failed
              : traceMismatch
                  ? AiTraceStatus.unknown
                  : AiTraceStatus.notStarted,
          mode: 'consultation',
          errorCode: emptyReply
              ? 'MODEL_REPLY_INVALID'
              : traceMismatch
                  ? 'TRACE_ID_MISMATCH'
                  : null,
        );
      }
      if (!mounted) {
        await recordFinalRender(errorCode: 'SCREEN_DISPOSED');
        return;
      }
      setState(() {
        _extracting = false;
        _error = error.message ?? '症状整理失败';
      });
      await recordFinalRender(errorCode: error.code);
    } on FormatException catch (error) {
      if (!nativeInferenceCompleted) {
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.nativeInference,
          status: AiTraceStatus.succeeded,
          mode: 'consultation',
        );
      }
      if (!resultValidationCompleted) {
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.resultValidation,
          status: AiTraceStatus.failed,
          mode: 'consultation',
          errorCode: 'MODEL_OUTPUT_INVALID',
        );
      }
      if (!mounted) {
        await recordFinalRender(errorCode: 'SCREEN_DISPOSED');
        return;
      }
      setState(() {
        _extracting = false;
        _error = error.message;
      });
      await recordFinalRender(errorCode: 'MODEL_OUTPUT_INVALID');
    } catch (error) {
      if (!nativeInferenceCompleted) {
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.nativeInference,
          status: AiTraceStatus.unknown,
          mode: 'consultation',
          errorCode: 'NATIVE_CALL_FAILED',
        );
      }
      if (!resultValidationCompleted) {
        await _traceRecorder.record(
          traceContext,
          stage: AiTraceStage.resultValidation,
          status: nativeInferenceCompleted
              ? AiTraceStatus.unknown
              : AiTraceStatus.notStarted,
          mode: 'consultation',
          errorCode: nativeInferenceCompleted ? 'RESULT_STATE_UNKNOWN' : null,
        );
      }
      if (!mounted) {
        await recordFinalRender(errorCode: 'SCREEN_DISPOSED');
        return;
      }
      setState(() {
        _extracting = false;
        _error = '症状整理失败：$error';
      });
      await recordFinalRender(
        errorCode: nativeInferenceCompleted
            ? 'RESULT_STATE_UNKNOWN'
            : 'NATIVE_CALL_FAILED',
      );
    }
  }

  Future<void> _releaseModel() async {
    if (_attachmentBusy ||
        _modelControlBusy ||
        _sending ||
        _extracting ||
        _recordingBusy ||
        _recording ||
        _statusUnknown ||
        _status?.ready != true) {
      return;
    }
    setState(() => _modelControlBusy = true);
    try {
      final paths = <String?>[_imagePath, _audioPath];
      final status = await _service.releaseModel();
      await _deleteCachedAttachments(paths);
      if (!mounted) return;
      setState(() {
        _status = status;
        _messages
          ..clear()
          ..add(const _InterviewMessage(
            text: '模型已释放，设备内存已归还。再次使用时可重新加载。',
            isUser: false,
          ));
        _confirmedDraft = null;
        _imagePath = null;
        _audioPath = null;
        _error = null;
      });
    } on PlatformException catch (error) {
      await _handleModelControlFailure(
        errorMessage: error.message ?? '无法释放模型',
        unavailableMessage: '释放操作发生错误，但原生模型运行态已清空。重新加载后可继续使用。',
      );
    } catch (error) {
      await _handleModelControlFailure(
        errorMessage: '无法释放模型：$error',
        unavailableMessage: '释放操作发生错误，但原生模型运行态已清空。重新加载后可继续使用。',
      );
    } finally {
      if (mounted) setState(() => _modelControlBusy = false);
    }
  }

  Future<void> _handleModelControlFailure({
    required String errorMessage,
    required String unavailableMessage,
  }) async {
    final refreshedStatus = await _readNativeStatus();
    if (refreshedStatus == null) {
      if (!mounted) return;
      setState(() {
        _status = null;
        _statusUnknown = true;
        _error = '$errorMessage；无法确认原生模型状态，请重新检查后再继续。';
      });
      return;
    }
    final nativeRuntimeUnavailable = !refreshedStatus.ready;
    if (nativeRuntimeUnavailable) {
      await _deleteCachedAttachments([_imagePath, _audioPath]);
    }
    if (!mounted) return;
    setState(() {
      _status = refreshedStatus;
      _statusUnknown = false;
      if (nativeRuntimeUnavailable) {
        _messages
          ..clear()
          ..add(_InterviewMessage(text: unavailableMessage, isUser: false));
        _confirmedDraft = null;
        _imagePath = null;
        _audioPath = null;
      }
      _error = errorMessage;
    });
  }
  Future<void> _resetConversation() async {
    if (_attachmentBusy ||
        _modelControlBusy ||
        _sending ||
        _extracting ||
        _recordingBusy ||
        _recording ||
        _statusUnknown ||
        _status?.ready != true) {
      return;
    }
    setState(() => _modelControlBusy = true);
    try {
      final paths = <String?>[_imagePath, _audioPath];
      final status = await _service.resetConversation();
      await _deleteCachedAttachments(paths);
      if (!mounted) return;
      _conversationIdFuture = _createNewConversation();
      _lastEffectiveMode = null;
      _pendingToolSelection = false;
      _pendingBaziArguments = null;
      _pendingZiweiArguments = null;
      _pendingMeihuaArguments = null;
      _pendingChengguArguments = null;
      _pendingHuangdiSijiArguments = null;
      _pendingXiaoliurenArguments = null;
      _pendingDreamArguments = null;
      _pendingHistoryTranscript = null;
      _pendingHistoryUserMessages = const [];
      setState(() {
        _status = status;
        _messages
          ..clear()
          ..add(const _InterviewMessage(
            text: '我们重新开始。先说说这次最想了解的身体情况。',
            isUser: false,
          ));
        _confirmedDraft = null;
        _imagePath = null;
        _audioPath = null;
        _error = null;
      });
    } on PlatformException catch (error) {
      await _handleModelControlFailure(
        errorMessage: error.message ?? '无法重置会话',
        unavailableMessage: '会话重置失败，原生会话已关闭。请重新加载模型后重新开始。',
      );
    } catch (error) {
      await _handleModelControlFailure(
        errorMessage: '无法重置会话：$error',
        unavailableMessage: '会话重置失败，原生会话已关闭。请重新加载模型后重新开始。',
      );
    } finally {
      if (mounted) setState(() => _modelControlBusy = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _disposeRecorder(Iterable<String?> pendingAttachments) async {
    final paths = <String?>[
      ...pendingAttachments,
      _activeRecordingPath,
    ];
    try {
      await _recorderOperation;
    } catch (_) {
      // Continue teardown even if the pending start/stop failed.
    }
    if (_recording || _recorderMayBeActive) {
      try {
        paths.add(await _audioRecorder.stop());
        _recorderMayBeActive = false;
      } catch (_) {
        // Dispose still releases any remaining native recorder resources.
      }
    }
    try {
      await _audioRecorder.dispose();
    } catch (_) {
      // Do not leak an asynchronous exception during widget teardown.
    }
    _activeRecordingPath = null;
    await _deleteCachedAttachments(paths);
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    final pendingAttachments = _sending
        ? const <String?>[]
        : <String?>[_imagePath, _audioPath];
    unawaited(_disposeRecorder(pendingAttachments));
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ready = _status?.ready == true;
    // 键盘弹出时收起顶部模型/模式/角色说明，把空间让给对话。
    // ColorOS 不一定 resize 窗口，但 MediaQuery.viewInsets 走 WindowInsets.Type.ime()
    // 现代 API，键盘可见时 bottom>0 可靠。
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    return AdaptiveSinglePane(
      preferredAnchorPoint: widget.preferredAnchorPoint,
      child: Scaffold(
      // 交由外层 AdaptiveHomeNavigation 的 Scaffold 统一处理键盘 inset；
      // 这里再 resize 会与外层叠加（ColorOS 下双重应用把 body 压到 ~0，
      // 输入框被挤到顶部、对话区变空白）。
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('汉唐 AI 助手'),
        actions: [
          if (_tcmInterviewController != null)
            IconButton(
              tooltip: '问诊证据',
              onPressed: _sending ? null : _showZangFuEvidenceDialog,
              icon: const Icon(Icons.fact_check_outlined),
            ),
          IconButton(
            tooltip: '历史对话',
            onPressed: _attachmentBusy || _modelControlBusy || _sending || _extracting || _recordingBusy || _recording ? null : _openHistory,
            icon: const Icon(Icons.history),
          ),
          if (ready) ...[
            IconButton(
              tooltip: '重新开始对话',
              onPressed: _attachmentBusy || _modelControlBusy || _sending || _extracting || _recordingBusy || _recording ? null : _resetConversation,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: '释放模型内存',
              onPressed: _attachmentBusy || _modelControlBusy || _sending || _extracting || _recordingBusy || _recording ? null : _releaseModel,
              icon: const Icon(Icons.memory_outlined),
            ),
          ],
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Center(
            child: ConstrainedBox(
              key: const ValueKey('local-ai-content-width'),
              constraints: const BoxConstraints(maxWidth: 640),
              child: SizedBox(
                height: constraints.maxHeight,
                child: Column(
        children: [
          Expanded(
            child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
            children: [
            if (!keyboardVisible) ...[
              _buildModelPanel(context),
              _buildModeSelector(context),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
                color: scheme.surfaceContainerLow,
                child: Text(
                  '当前角色：${_assistantMode.label}。模型负责对话与整理；辨证规则、知识检索和工具计算分别由 App 对应模块执行。',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: AppType.caption,
                    height: 1.45,
                  ),
                ),
              ),
            ],
            if (ready && _confirmedDraft == null && _messages.any((m) => m.isUser))
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _attachmentBusy || _modelControlBusy || _sending || _extracting ? null : _extractSymptoms,
                    icon: _extracting
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.fact_check_outlined, size: 18),
                    label: Text(_extracting ? '正在整理自述…' : '整理本次症状'),
                  ),
                ),
              ),
            if (_confirmedDraft != null)
              _buildConfirmedDraftPanel(context),
            ..._messages.map((message) => _InterviewMessageBubble(message: message)),
            if (_sending || _extracting)
              _InterviewMessageBubble(
                message: _InterviewMessage(
                  text: _extracting ? '正在整理本次对话…' : '正在生成回复…',
                  isUser: false,
                ),
              ),
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                color: scheme.errorContainer,
                child: Text(
                  _error!,
                  style: TextStyle(color: scheme.onErrorContainer, fontSize: AppType.caption),
                ),
              ),
          ],
            ),
          ),
          SafeArea(
            top: false,
            // 键盘弹出时输入框下沿紧贴键盘上沿：去掉底部安全区与内边距。
            bottom: !keyboardVisible,
            child: Padding(
                padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, keyboardVisible ? 0 : AppSpacing.sm),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_imagePath != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                              child: Image.file(
                                File(_imagePath!),
                                width: 52,
                                height: 52,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            const Expanded(
                              child: Text(
                                '舌象照片已选。请确认光线自然、对焦清晰、无滤镜。',
                                style: TextStyle(fontSize: AppType.caption, height: 1.4),
                              ),
                            ),
                            IconButton(
                              tooltip: '移除照片',
                              onPressed: _attachmentBusy || _modelControlBusy || _sending ? null : _discardAttachment,
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                    if (_audioPath != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.graphic_eq, size: 20),
                            const SizedBox(width: AppSpacing.sm),
                            const Expanded(
                              child: Text('语音已录制（最长 30 秒），发送前可移除。', style: TextStyle(fontSize: AppType.caption)),
                            ),
                            IconButton(
                              tooltip: '移除录音',
                              onPressed: _attachmentBusy || _modelControlBusy || _sending ? null : _discardAttachment,
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                    if (_recording)
                      const Padding(
                        padding: EdgeInsets.only(bottom: AppSpacing.xs),
                        child: Row(
                          children: [
                            Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
                            SizedBox(width: AppSpacing.xs),
                            Text('正在录音，最长 30 秒…', style: TextStyle(fontSize: AppType.caption)),
                          ],
                        ),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: '拍摄舌象',
                          onPressed: ready &&
                                  !_attachmentBusy &&
                                  !_modelControlBusy &&
                                  !_sending &&
                                  !_extracting &&
                                  !_recording &&
                                  !_recordingBusy &&
                                  _confirmedDraft == null &&
                                  _audioPath == null
                              ? _pickTonguePhoto
                              : null,
                          icon: const Icon(Icons.camera_alt_outlined),
                        ),
                        IconButton(
                          tooltip: _recording ? '停止录音' : '录制语音（最长 30 秒）',
                          onPressed: ready &&
                                  !_attachmentBusy &&
                                  !_modelControlBusy &&
                                  !_sending &&
                                  !_extracting &&
                                  !_recordingBusy &&
                                  (!_recorderMayBeActive || _recording) &&
                                  _confirmedDraft == null &&
                                  _imagePath == null &&
                                  _audioPath == null
                              ? (_recording ? _stopRecording : _startRecording)
                              : null,
                          icon: Icon(_recording ? Icons.stop_circle_outlined : Icons.mic_none),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _inputController,
                            minLines: 1,
                            maxLines: 4,
                            enabled: ready &&
                                !_attachmentBusy &&
                                !_modelControlBusy &&
                                !_sending &&
                                !_extracting &&
                                !_recording &&
                                !_recordingBusy &&
                                _confirmedDraft == null,
                            onChanged: (_) => setState(() {}),
                            textInputAction: TextInputAction.newline,
                            // 点击对话区任意处（含消息气泡）收起键盘、退出输入模式。
                            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                            decoration: InputDecoration(
                              hintText: ready ? '描述你的情况…' : '请先安装并加载本地模型',
                              filled: true,
                              fillColor: scheme.surfaceContainerLow,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppRadius.lg),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.lg,
                                vertical: AppSpacing.md,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        IconButton.filled(
                          tooltip: '发送',
                          onPressed: ready &&
                                  !_attachmentBusy &&
                                  !_modelControlBusy &&
                                  !_sending &&
                                  !_extracting &&
                                  !_recording &&
                                  !_recordingBusy &&
                                  _confirmedDraft == null &&
                                  (_inputController.text.trim().isNotEmpty ||
                                      _imagePath != null ||
                                      _audioPath != null)
                              ? _send
                              : null,
                          icon: const Icon(Icons.arrow_upward),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
                ),
              ),
            ),
          );
        },
      ),
      ),
    );
  }

  Widget _buildSourceTruncationWarning(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: scheme.onTertiaryContainer,
            size: 18,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              '记录范围不完整：较早或超长的输入可能未包含在本次整理中。请补充遗漏内容并逐项核对，不要把未显示的信息理解为你没有相关症状。',
              style: TextStyle(
                color: scheme.onTertiaryContainer,
                fontSize: AppType.caption,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildConfirmedDraftPanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final draft = _confirmedDraft!;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '已核对的用户自述',
            style: TextStyle(fontSize: AppType.caption, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...draft.summaryLines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(line, style: const TextStyle(fontSize: AppType.caption, height: 1.4)),
            ),
          ),
          if (draft.sourceTruncated) ...[
            const SizedBox(height: AppSpacing.sm),
            _buildSourceTruncationWarning(context),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            '可将已核对自述带入规则问诊；自由文本不会被自动转换成辨证选项。',
            style: TextStyle(fontSize: AppType.micro, color: scheme.onSurfaceVariant),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: _structuredDiagnosisBusy
                  ? null
                  : _continueWithStructuredDiagnosis,
              icon: _structuredDiagnosisBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.fact_check_outlined),
              label: Text(
                _structuredDiagnosisBusy ? '正在准备问诊…' : '继续规则辨证',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _continueWithStructuredDiagnosis() async {
    final draft = _confirmedDraft;
    if (draft == null || _structuredDiagnosisBusy) return;
    await _startInlineTcmInterview(
      initialUserMessage: '继续规则辨证',
      userContext: draft.summaryLines.join('\\n'),
    );
  }

  Widget _buildModelPanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_checking) {
      return const LinearProgressIndicator(minHeight: 2);
    }
    if (_statusUnknown) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.help_outline, size: 18, color: scheme.error),
                const SizedBox(width: AppSpacing.sm),
                const Expanded(
                  child: Text(
                    '无法确认本地模型状态',
                    style: TextStyle(
                      fontSize: AppType.caption,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '为避免继续使用可能已失效的会话，问诊、模型加载和文件导入暂时停用。请重新检查原生模型状态。',
              style: TextStyle(
                fontSize: AppType.caption,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: () => _refreshStatus(showProgress: true),
              icon: const Icon(Icons.refresh),
              label: const Text('重新检查状态'),
            ),
          ],
        ),
      );
    }

    final status = _status;
    final ready = status?.ready == true;
    final installed = status?.installed == true;
    final backendLabel = status?.backend.toUpperCase() ?? '';
    final modelSizeLabel = status?.sizeLabel ?? '';
    final hashVerified = status?.hashVerified ?? false;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ready ? Icons.memory : Icons.download_done_outlined,
                size: 18,
                color: ready ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  ready
                      ? 'Gemma 4 E4B · ${backendLabel}'
                      : installed
                          ? '模型已放入设备，尚未加载'
                          : '等待安装 Gemma 4 E4B 模型',
                  style: const TextStyle(fontSize: AppType.caption, fontWeight: FontWeight.w600),
                ),
              ),
              if (ready)
                Text(
                  modelSizeLabel,
                  style: TextStyle(fontSize: AppType.caption, color: scheme.onSurfaceVariant),
                ),
            ],
          ),
          if (!ready) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              installed
                  ? hashVerified
                      ? '模型文件大小与 SHA-256 均已通过校验：${modelSizeLabel}。'
                      : '模型文件大小符合要求：${modelSizeLabel}。首次加载前仍会校验 SHA-256。'
                  : status?.fileExists == true
                      ? '检测到模型文件，但大小不符合要求。请重新选择完整模型文件。'
                      : '模型约 3.66 GB，需从设备本地导入；不会随 APK 打包或自动联网下载。',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: AppType.caption, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: installed &&
                          !_attachmentBusy &&
                          !_modelControlBusy &&
                          !_loading &&
                          !_importingModel
                      ? _loadModel
                      : null,
                  child: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('加载本地模型'),
                ),
                OutlinedButton.icon(
                  onPressed: !_attachmentBusy &&
                          !_modelControlBusy &&
                          !_loading &&
                          !_importingModel
                      ? _importModel
                      : null,
                  icon: _importingModel
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.folder_open_outlined),
                  label: Text(_importingModel ? '正在导入…' : '选择并导入模型文件'),
                ),
              ],
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: AppSpacing.xs),
              dense: true,
              title: const Text(
                '模型文件位置与校验说明',
                style: TextStyle(fontSize: AppType.caption),
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    status?.modelPath ??
                        'Android 应用私有目录 /files/ai_models/gemma-4-E4B-it.litertlm',
                    style: TextStyle(
                      fontSize: AppType.micro,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _loading
                        ? '首次加载前正在核对约 3.66 GB 模型文件的 SHA-256。请保持应用在前台；当前文件版本验证通过后，同一进程内重新加载不会重复扫描。'
                        : _importingModel
                            ? '正在导入并校验文件，请保持应用在前台并确保设备有足够可用空间。'
                            : '导入时在本机流式复制并校验文件大小与 SHA-256；首次加载前也会核验文件完整性。不会上传模型或请求模型服务。',
                    style: TextStyle(
                      fontSize: AppType.micro,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TcmInterviewMessagePersistenceResult {
  const _TcmInterviewMessagePersistenceResult({
    required this.transcriptMessagesApplicable,
    required this.transcriptMessagesPersisted,
  });

  const _TcmInterviewMessagePersistenceResult.notApplicable()
      : transcriptMessagesApplicable = false,
        transcriptMessagesPersisted = false;

  final bool transcriptMessagesApplicable;
  final bool transcriptMessagesPersisted;
}

class _InterviewMessage {
  final String text;
  final bool isUser;
  final String? actionLabel;
  final VoidCallback? onAction;
  final List<String> options;
  final ValueChanged<String>? onOptionSelected;
  final List<String> sourceIds;
  final ValueChanged<String>? onSourceTap;
  final String? knowledgeStatus;
  final DiagnosisResult? diagnosisResult;
  final VoidCallback? onBookmark;
  final VoidCallback? onShare;
  final VoidCallback? onCopyPrescription;

  const _InterviewMessage({
    required this.text,
    required this.isUser,
    this.actionLabel,
    this.onAction,
    this.options = const [],
    this.onOptionSelected,
    this.sourceIds = const [],
    this.onSourceTap,
    this.knowledgeStatus,
    this.diagnosisResult,
    this.onBookmark,
    this.onShare,
    this.onCopyPrescription,
  });
}

bool _isNavigableKnowledgeSourceId(String sourceId) {
  final kind = sourceId.split(':').first;
  return const {
    'formula',
    'herb',
    'acupoint',
    'acupuncture',
    'medical_case',
    'neijing',
    'shanghan',
    'jingui',
    'guji',
    'zhenjiu',
  }.contains(kind);
}

String _knowledgeSourceLabel(String sourceId) {
  final parts = sourceId.split(':');
  final kind = parts.isEmpty ? '' : parts.first;
  final value = parts.length > 1 ? parts.sublist(1).join(':') : '';
  return switch (kind) {
    'formula' => '方剂：$value',
    'herb' => '本草：$value',
    'acupoint' => '穴位：$value',
    'acupuncture' => '针灸来源：$value',
    'medical_case' => '医案 #$value',
    'neijing' => '内经条目',
    'shanghan' => '伤寒论：$value',
    'jingui' => '金匮要略：$value',
    'guji' => '古籍原文：$value',
    'zhenjiu' => '针灸讲稿：$value',
    _ => '来源：$sourceId',
  };
}


class _KnowledgeStatusLabel extends StatelessWidget {
  const _KnowledgeStatusLabel({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      'RETRIEVED' => '知识检索：已检索到来源',
      'PARTIAL' => '知识检索：部分结果',
      'NO_RESULTS' => '知识检索：无匹配结果',
      'FAILED' => '知识检索：执行失败',
      _ => '知识检索：状态未知（$status）',
    };
    final color = switch (status) {
      'RETRIEVED' => Theme.of(context).colorScheme.primary,
      'PARTIAL' => Theme.of(context).colorScheme.tertiary,
      'FAILED' => Theme.of(context).colorScheme.error,
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        label,
        style: TextStyle(fontSize: AppType.micro, color: color),
      ),
    );
  }
}

class _InterviewMessageBubble extends StatelessWidget {
  final _InterviewMessage message;

  const _InterviewMessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final bubbleMaxWidth = availableWidth.isFinite
            ? availableWidth * 0.94
            : MediaQuery.sizeOf(context).width * 0.94;
        return Align(
          alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(maxWidth: bubbleMaxWidth),
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: message.isUser
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText(
                  message.text,
                  style: TextStyle(
                    color: message.isUser ? scheme.onPrimaryContainer : scheme.onSurface,
                    fontSize: AppType.body,
                    height: 1.55,
                  ),
                ),
                if (message.knowledgeStatus != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  _KnowledgeStatusLabel(status: message.knowledgeStatus!),
                ],
                if (message.sourceIds.any(_isNavigableKnowledgeSourceId) &&
                    message.onSourceTap != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: message.sourceIds
                        .where(_isNavigableKnowledgeSourceId)
                        .map((sourceId) => ActionChip(
                              avatar: const Icon(Icons.link, size: 14),
                              label: Text(_knowledgeSourceLabel(sourceId)),
                              onPressed: () => message.onSourceTap!(sourceId),
                            ))
                        .toList(),
                  ),
                ],
                if (message.options.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: message.options.map((option) => ActionChip(
                      label: Text(option),
                      onPressed: message.onOptionSelected == null
                          ? null
                          : () => message.onOptionSelected!(option),
                    )).toList(),
                  ),
                ],
                if (message.diagnosisResult != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.bookmark_add_outlined, size: 16),
                        label: const Text('收藏辨证结果'),
                        onPressed: message.onBookmark,
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.share_outlined, size: 16),
                        label: const Text('分享辨证结果'),
                        onPressed: message.onShare,
                      ),
                      if (message.diagnosisResult!.prescription != null)
                        ActionChip(
                          avatar: const Icon(Icons.content_copy, size: 16),
                          label: const Text('复制处方'),
                          onPressed: message.onCopyPrescription,
                        ),
                    ],
                  ),
                ],
                if (message.actionLabel != null && message.onAction != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: message.onAction,
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: Text(message.actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Blocks the first route-pop attempt long enough to translate a null/back
/// exit into a typed cancellation, while preserving non-null results returned
/// by legacy tool pages. A second pop is issued only after PopScope rebuilds
/// with canPop=true; calling Navigator.pop from inside a blocked callback would
/// otherwise be blocked by the same PopScope again.
class _AssistantToolRouteGuard extends StatefulWidget {
  const _AssistantToolRouteGuard({
    required this.child,
    required this.cancellationResult,
  });

  final Widget child;
  final AssistantToolResult cancellationResult;

  @override
  State<_AssistantToolRouteGuard> createState() =>
      _AssistantToolRouteGuardState();
}

class _AssistantToolRouteGuardState extends State<_AssistantToolRouteGuard> {
  bool _allowPop = false;
  bool _popScheduled = false;

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _popScheduled) return;
        _popScheduled = true;
        setState(() => _allowPop = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.of(context).pop(
            result ?? widget.cancellationResult,
          );
        });
      },
      child: widget.child,
    );
  }
}

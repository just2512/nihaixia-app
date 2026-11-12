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
    this.traceRecorder,
  });

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
  LocalAiSymptomDraft? _confirmedDraft;
  String? _error;

  AssistantConversationStore get _conversationStore =>
      widget.conversationStore ?? DatabaseHelper.instance;

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
        final knowledge =
            await _retrieveKnowledgeWithTrace(text, traceContext: traceContext);
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
        final knowledge =
            await _retrieveKnowledgeWithTrace(
          text,
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
              '只有用户明确启动结构化辨证时，才通过 App 的 DiagnosticEngine 工具执行规则问诊；'
              '普通对话不自动诊断、不推荐方剂或剂量。\n'
              '$knowledgeContext',
        );
        return _AssistantTurnResponse(
          text: reply + knowledge.citationFooter,
          sourceIds: knowledge.sourceIds,
          knowledgeStatus: knowledge.statusLabel,
        );
      case AssistantMode.learning:
        final knowledge =
            await _retrieveKnowledgeWithTrace(text, traceContext: traceContext);
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
        final context = '当前角色：工具助手。\n${AssistantMode.tools.promptHint}\n'
            '当前 App 已注册工具：$availableTools。'
            '只有用户明确提出动作时才建议打开对应工具；工具实际计算由 App 页面完成。';
        return _AssistantTurnResponse(
          text: await sendWithContext(context),
        );
      case AssistantMode.metaphysics:
        final availableTools = AssistantToolRouter.quickActions(AssistantMode.metaphysics)
            .map((tool) => tool.title)
            .join('、');
        final context = '当前角色：玄学大师。\n${AssistantMode.metaphysics.promptHint}\n'
            '当前 App 已注册工具：$availableTools。'
            '排盘结果必须由 App 工具生成，不得凭空推算。';
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
  }) async {
    if (_structuredDiagnosisBusy) return;
    if (_tcmInterviewController?.canAnswer == true) {
      setState(() {
        _error = '当前对话已有一项未完成的规则问诊。请先回答下方问题，或从历史记录恢复该任务。';
      });
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
      _error = null;
    });
    final before = controller.messages.length;
    try {
      controller.start(
        initialUserMessage: initialUserMessage,
        userContext: userContext,
      );
      _inputController.clear();
      await _appendTcmInterviewMessages(before);
      if (mounted) {
        setState(() {
          _confirmedDraft = null;
          _structuredDiagnosisBusy = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _structuredDiagnosisBusy = false;
          _error = '无法启动规则问诊：$error';
        });
      }
    }
  }


  _InterviewMessage _diagnosisActionMessage(
    String text,
    DiagnosisResult result,
  ) {
    return _InterviewMessage(
      text: text,
      isUser: false,
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

  Future<void> _appendTcmInterviewMessages(int startIndex) async {
    final controller = _tcmInterviewController;
    if (controller == null) return;
    final added = controller.messages.skip(startIndex).toList(growable: false);
    if (added.isEmpty) {
      await _persistTcmInterviewTaskState(controller.createTaskState());
      return;
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
    if (conversationId != null) {
      for (final entry in added) {
        try {
          await _conversationStore.saveAssistantMessage(
            conversationId: conversationId,
            role: entry.isUser ? 'user' : 'assistant',
            content: entry.text,
            metadata: AssistantMessageMetadata(
              mode: 'consultation',
              selectedMode: _assistantMode.name,
              tcmTaskId: controller.taskId,
              replayable: entry.isUser,
            ).encode(),
          );
        } catch (error, stack) {
          debugPrint('[TcmInterviewTask] 问诊消息保存失败：$error\n$stack');
        }
      }
    }
    await _persistTcmInterviewTaskState(taskState);
    await _persistDiagnosisHistoryOnce(controller);
    final completedDiagnosis = controller.completedDiagnosis;
    if (completedDiagnosis?.prescription != null &&
        SettingsRepository.instance.autoCopyPrescription) {
      await _copyDiagnosisPrescription(completedDiagnosis!.prescription!);
    }

    if (controller.isCompleted) {
      try {
        await _restoreVisibleConversationToModel();
      } catch (error) {
        if (mounted) {
          setState(() {
            _error = '规则辨证结果已保存，但同步到本地模型上下文失败：$error';
          });
        }
      }
    }
    _scrollToBottom();
  }

  Future<void> _handleTcmInterviewOption(String option) async {
    final controller = _tcmInterviewController;
    if (controller == null || !controller.canAnswer) return;
    if (controller.pendingPromptId == 'tongue_pulse' &&
        option == '选择舌诊脉诊') {
      await _showUnifiedTonguePulseDialog();
      return;
    }
    final before = controller.messages.length;
    try {
      controller.answerOption(option);
      await _appendTcmInterviewMessages(before);
    } catch (error) {
      if (mounted) setState(() => _error = '问诊选项未能提交：$error');
    }
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

  Future<void> _showUnifiedTonguePulseDialog() async {
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
    if (!mounted || confirmed != true) return;
    final before = controller.messages.length;
    try {
      controller.answerTonguePulse(
        tongueCoating: tongueCoating,
        tongueShape: tongueShape,
        primaryPulse: primaryPulse,
        secondaryPulse: secondaryPulse,
      );
      await _appendTcmInterviewMessages(before);
    } catch (error) {
      if (mounted) setState(() => _error = '舌诊脉诊输入未能提交：$error');
    }
  }

  Future<void> _executeHeadlessTool(
    String userText,
    AssistantToolDefinition tool, {
    required AssistantMode mode,
    AssistantToolArguments? arguments,
  }) async {
    final request = arguments ??
        AssistantToolArguments(toolId: tool.id);
    final argumentErrors = request.validateAgainst(tool);
    final executor = tool.headlessExecutor!;
    final result = argumentErrors.isEmpty
        ? executor(request.values)
        : AssistantToolResult(
            toolId: tool.id,
            title: tool.title,
            status: AssistantToolExecutionStatus.failed,
            values: {'参数错误': argumentErrors.join('；')},
            arguments: request.values,
            disclaimer: '参数校验未通过；本次没有执行工具。',
          );
    final contractErrors = <String>[
      ...result.validateFor(tool.id),
      ...result.validateArgumentsMatch(request.values),
    ];
    if (contractErrors.isNotEmpty) {
      if (mounted) {
        setState(() {
          _error = 'Headless 工具结果未通过契约校验：${contractErrors.join('；')}';
        });
      }
      return;
    }

    final response =
        '【${tool.title}执行结果】\n${result.toConversationText()}';
    setState(() {
      _lastEffectiveMode = mode;
      _messages
        ..add(_InterviewMessage(text: userText, isUser: true))
        ..add(_InterviewMessage(
          text: response,
          isUser: false,
          sourceIds: result.sourceIds,
        ));
      _error = null;
    });
    _inputController.clear();
    await _persistSuccessfulTurn(
      userText: userText,
      assistantText: response,
      mode: mode,
      toolId: tool.id,
      toolStatus: result.statusLabel,
      sourceIds: result.sourceIds,
      toolArguments: result.arguments,
    );
    _scrollToBottom();
  }

  Future<void> _requestTool(
    String userText,
    AssistantToolDefinition tool, {
    AssistantMode? mode,
    AssistantToolArguments? arguments,
  }) async {
    if (tool.id == 'structured_diagnosis') {
      await _startInlineTcmInterview(initialUserMessage: userText);
      return;
    }
    _pendingToolSelection = false;
    final activeMode = mode ??
        (tool.modes.contains(AssistantMode.metaphysics)
            ? AssistantMode.metaphysics
            : tool.modes.contains(AssistantMode.tools)
                ? AssistantMode.tools
                : AssistantMode.consultation);
    // Only auto-execute a Headless calculator when the user supplied its
    // explicit date argument. Without a date, preserve the existing Page Tool
    // flow so a broad "how is it calculated?" request is not silently run for
    // today's date.
    final hasExplicitHeadlessDate = arguments?.values.containsKey('date') == true;
    if (tool.headlessExecutor != null && hasExplicitHeadlessDate) {
      await _executeHeadlessTool(
        userText,
        tool,
        mode: activeMode,
        arguments: arguments,
      );
      return;
    }
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
          ),
        ));
      _error = null;
    });
    _inputController.clear();
    await _persistSuccessfulTurn(
      userText: userText,
      assistantText: instruction,
      mode: activeMode,
      toolId: tool.id,
      toolArguments: arguments?.values ?? const {},
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
  }) async {
    if (tool.id == 'structured_diagnosis') {
      await _startInlineTcmInterview(initialUserMessage: '继续规则辨证');
      return;
    }
    // Every execution path (including quick actions with no extracted args)
    // must pass the same contract. Otherwise required parameters can be
    // bypassed simply by opening a tool from a shortcut.
    final toolArguments =
        arguments ?? AssistantToolArguments(toolId: tool.id);
    final errors = toolArguments.validateAgainst(tool);
    if (errors.isNotEmpty) {
      if (mounted) {
        setState(() => _error = '工具参数未通过校验：${errors.join('；')}');
      }
      return;
    }
    if (_toolRouteActive) return;
    _toolRouteActive = true;
    _pendingToolSelection = false;
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
    if (!mounted) return;
    if (result is AssistantToolResult) {
      final errors = result.validateFor(tool.id);
      if (errors.isNotEmpty) {
        setState(() => _error = '工具返回结果未通过契约校验：' + errors.join('；'));
        return;
      }
    }
    final normalizedResult = (switch (result) {
      AssistantToolResult typed => typed,
      String legacy when legacy.trim().isNotEmpty => AssistantToolResult(
          toolId: tool.id,
          title: tool.title,
          values: {'结果': legacy.trim()},
        ),
      _ => AssistantToolResult(
          toolId: tool.id,
          title: tool.title,
          status: AssistantToolExecutionStatus.noResult,
          values: const {'返回内容': 'MISSING'},
          disclaimer: '工具页面退出时未返回结构化结果；无法区分用户取消与旧页面未实现回传。',
        ),
    }).withArguments(toolArguments.values);
    final argumentErrors =
        normalizedResult.validateArgumentsMatch(toolArguments.values);
    if (argumentErrors.isNotEmpty) {
      setState(() => _error = '工具返回参数未通过契约校验：' + argumentErrors.join('；'));
      return;
    }
    final resultText = normalizedResult.toConversationText();
    final response = '【' + tool.title + '执行结果】\n' + resultText;
    final canRetry = normalizedResult.status ==
        AssistantToolExecutionStatus.failed;
    setState(() {
      _messages.add(_InterviewMessage(
        text: response,
        isUser: false,
        actionLabel: canRetry ? '重试${tool.title}' : null,
        onAction: canRetry
            ? () => unawaited(_openTool(
                  tool,
                  mode: mode,
                  arguments: toolArguments,
                ))
            : null,
      ));
    });
    try {
      final id = await _conversationIdFuture;
      if (id != null) {
        await _conversationStore.saveAssistantMessage(
          conversationId: id,
          role: 'assistant',
          content: response,
          metadata: AssistantMessageMetadata(
            mode: mode.name,
            selectedMode: _assistantMode.name,
            toolId: tool.id,
            toolStatus: normalizedResult.statusLabel,
            sourceIds: normalizedResult.sourceIds,
            toolArguments: normalizedResult.arguments,
          ).encode(),
        );
      }
    } catch (error) {
      debugPrint('[AssistantHistory] 保存工具结果失败：$error');
    }
    try {
      // Returning a tool result to the visible timeline is not enough: rebuild
      // the native model context so the next user turn can actually discuss it.
      await _restoreVisibleConversationToModel();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '工具结果已加入对话记录，但同步到本地模型上下文失败：$error';
        });
      }
    }
    _scrollToBottom();
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
      final resolvedActionMode = actionMode ??
          (pendingTool?.modes.contains(AssistantMode.metaphysics) == true
              ? AssistantMode.metaphysics
              : pendingTool?.modes.contains(AssistantMode.tools) == true
                  ? AssistantMode.tools
                  : AssistantMode.consultation);
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

    final activeTcmTask = _tcmInterviewController;
    if (activeTcmTask?.canAnswer == true) {
      if (imagePath != null || audioPath != null) {
        setState(() {
          _error = '请先完成当前结构化问诊步骤，再发送照片或录音；附件不会被转换成规则答案。';
        });
        return;
      }
      if (text.isNotEmpty) {
        if (activeTcmTask!.pendingOptions.contains(text)) {
          _inputController.clear();
          await _handleTcmInterviewOption(text);
          return;
        }
        const clarification =
            '当前步骤需要使用下方结构化选项。你输入的文字会保留在对话中，但不会自动映射为辨证条件；请从问题下方选择最符合的一项。';
        setState(() {
          _lastEffectiveMode = AssistantMode.consultation;
          _messages
            ..add(_InterviewMessage(text: text, isUser: true))
            ..add(const _InterviewMessage(text: clarification, isUser: false));
          _error = null;
        });
        _inputController.clear();
        await _persistSuccessfulTurn(
          userText: text,
          assistantText: clarification,
          mode: AssistantMode.consultation,
        );
        _scrollToBottom();
        return;
      }
    }

    final traceContext = _traceRecorder.start(
      stage: AiTraceStage.input,
      route: audioPath != null
          ? 'audio'
          : imagePath != null
              ? 'image'
              : 'text',
      mode: _assistantMode.name,
    );
    final traceId = traceContext.traceId;

    var effectiveMode = _assistantMode;
    if (text.isNotEmpty && imagePath == null && audioPath == null) {
      final decision = AssistantConversationOrchestrator.resolve(
        query: text,
        selectedMode: _assistantMode,
        currentMode: _lastEffectiveMode,
        pendingToolSelection: _pendingToolSelection,
      );
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
      await _deleteCachedAttachments([imagePath, audioPath]);
      final refreshedStatus = await _readNativeStatus();
      if (!mounted) return;
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
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.nativeInference,
        status: AiTraceStatus.unknown,
        mode: effectiveMode.name,
        errorCode: error.code == 'TRACE_ID_MISMATCH'
            ? 'TRACE_ID_MISMATCH'
            : 'NATIVE_CALL_FAILED',
      );
      final refreshedStatus = await _readNativeStatus();
      if (!mounted) {
        await _deleteCachedAttachments([imagePath, audioPath]);
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
    } catch (error) {
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.nativeInference,
        status: AiTraceStatus.unknown,
        mode: effectiveMode.name,
        errorCode: 'NATIVE_CALL_FAILED',
      );
      final refreshedStatus = await _readNativeStatus();
      if (!mounted) {
        await _deleteCachedAttachments([imagePath, audioPath]);
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
    try {
      final traceId = traceContext.traceId;
      final draft = traceId == null
          ? await _service.extractSymptoms()
          : await _service.extractSymptomsWithTrace(traceId: traceId);
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.nativeInference,
        status: AiTraceStatus.succeeded,
        mode: 'consultation',
      );
      if (!mounted) return;
      setState(() => _extracting = false);
      if (draft.summaryLines.isEmpty) {
        setState(() => _error = draft.sourceTruncated
            ? '原始输入记录曾被裁剪，但本次未提取到可核对内容。请补充遗漏描述后重新整理。'
            : '目前没有提取到明确的自述信息，请补充描述后再整理。');
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

      if (!mounted || confirmed != true) return;
      setState(() {
        _confirmedDraft = draft;
      });
    } on PlatformException catch (error) {
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.nativeInference,
        status: AiTraceStatus.unknown,
        mode: 'consultation',
        errorCode: error.code == 'TRACE_ID_MISMATCH'
            ? 'TRACE_ID_MISMATCH'
            : 'NATIVE_CALL_FAILED',
      );
      if (!mounted) return;
      setState(() {
        _extracting = false;
        _error = error.message ?? '症状整理失败';
      });
    } on FormatException catch (error) {
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.nativeInference,
        status: AiTraceStatus.unknown,
        mode: 'consultation',
        errorCode: 'NATIVE_CALL_FAILED',
      );
      if (!mounted) return;
      setState(() {
        _extracting = false;
        _error = error.message;
      });
    } catch (error) {
      await _traceRecorder.record(
        traceContext,
        stage: AiTraceStage.nativeInference,
        status: AiTraceStatus.unknown,
        mode: 'consultation',
        errorCode: 'NATIVE_CALL_FAILED',
      );
      if (!mounted) return;
      setState(() {
        _extracting = false;
        _error = '症状整理失败：$error';
      });
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


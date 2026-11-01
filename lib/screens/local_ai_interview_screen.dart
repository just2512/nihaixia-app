import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../services/local_ai_service.dart';
import '../theme/app_tokens.dart';

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
  });

  /// Injectable to verify initialization and error states without a native model.
  final LocalAiService? service;

  /// Optional recorder adapter for deterministic recording lifecycle tests.
  final LocalAiAudioRecorder? audioRecorder;

  /// Optional file inspector to isolate recording lifecycle tests from disk IO.
  final LocalAiRecordingFileInspector? recordingFileInspector;

  /// Optional camera/recovery adapter for deterministic attachment lifecycle tests.
  final LocalAiImagePicker? imagePicker;

  @override
  State<LocalAiInterviewScreen> createState() => _LocalAiInterviewScreenState();
}

class _LocalAiInterviewScreenState extends State<LocalAiInterviewScreen> {
  late final LocalAiService _service;
  late final LocalAiImagePicker _imagePicker;
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
      text: '可以先说说目前最困扰你的情况。比如从什么时候开始、具体有什么感觉、什么情况下会加重或缓解。一次说一两件事就可以。',
      isUser: false,
    ),
  ];

  LocalAiModelStatus? _status;
  bool _statusUnknown = false;
  bool _checking = true;
  bool _loading = false;
  bool _importingModel = false;
  bool _sending = false;
  bool _extracting = false;
  bool _modelControlBusy = false;
  LocalAiSymptomDraft? _confirmedDraft;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? LocalAiService();
    _imagePicker = widget.imagePicker ?? _PluginLocalAiImagePicker();
    _audioRecorder = widget.audioRecorder ?? _PluginLocalAiAudioRecorder();
    _recordingFileInspector =
        widget.recordingFileInspector ?? _IoLocalAiRecordingFileInspector();
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
      }
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message ?? '模型加载失败';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '模型加载失败：$error';
      });
    } finally {
      if (mounted) setState(() => _modelControlBusy = false);
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
      final previousPath = _imagePath;
      setState(() {
        _imagePath = path;
        _audioPath = null;
        _error = null;
      });
      if (previousPath != null && previousPath != path) {
        unawaited(_deleteCachedAttachments([previousPath]));
      }
    } catch (error) {
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
    setState(() {
      _attachmentBusy = true;
      _error = null;
    });

    String? photoPath;
    try {
      photoPath = await _imagePicker.pickCameraImagePath();
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
      final previousPath = _imagePath;
      setState(() {
        _imagePath = photoPath;
        _audioPath = null;
        _error = null;
      });
      if (previousPath != null && previousPath != photoPath) {
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
      final directory = await getTemporaryDirectory();
      final path =
          '${directory.path}/local_ai_${DateTime.now().millisecondsSinceEpoch}.wav';
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

  Future<void> _send() async {
    if (_modelControlBusy) return;
    final text = _inputController.text.trim();
    final imagePath = _imagePath;
    final audioPath = _audioPath;
    if (_sending ||
        _recording ||
        _recordingBusy ||
        _statusUnknown ||
        _status?.ready != true ||
        (text.isEmpty && imagePath == null && audioPath == null)) {
      return;
    }

    final userLabel = text.isNotEmpty
        ? text
        : imagePath != null
            ? '已附加一张舌象照片'
            : '已录制一段语音';
    setState(() {
      _messages.add(_InterviewMessage(text: userLabel, isUser: true));
      _sending = true;
      _error = null;
    });
    _scrollToBottom();

    try {
      final reply = audioPath != null
          ? await _service.sendAudio(audioPath, prompt: text)
          : imagePath != null
              ? await _service.sendImage(imagePath, prompt: text)
              : await _service.sendMessage(text);
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
            ..add(_InterviewMessage(text: reply, isUser: false));
          _confirmedDraft = null;
        } else {
          _messages.add(_InterviewMessage(text: reply, isUser: false));
        }
        _sending = false;
        _imagePath = null;
        _audioPath = null;
        _error = refreshedStatus == null
            ? '本轮回复已生成，但无法确认本地模型状态。请重新检查后继续。'
            : null;
      });
      _scrollToBottom();
    } on PlatformException catch (error) {
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
    try {
      final draft = await _service.extractSymptoms();
      if (!mounted) return;
      setState(() => _extracting = false);
      if (draft.summaryLines.isEmpty) {
        setState(() => _error = draft.sourceTruncated
            ? '原始输入记录曾被裁剪，但本次未提取到可核对内容。请补充遗漏描述后重新整理。'
            : '目前没有提取到明确的自述信息，请补充描述后再整理。');
        return;
      }

      final confirmed = await showDialog<bool>(
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
      if (!mounted) return;
      setState(() {
        _extracting = false;
        _error = error.message ?? '症状整理失败';
      });
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _extracting = false;
        _error = error.message;
      });
    } catch (error) {
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('本地 AI 问诊'),
        actions: [
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
      body: Column(
        children: [
          _buildModelPanel(context),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
            color: scheme.surfaceContainerLow,
            child: Text(
              'AI 只负责交流和整理自述信息；六经辨证仍由原有规则问诊流程完成，不会由模型开方或调整剂量。',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: AppType.caption,
                height: 1.45,
              ),
            ),
          ),
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
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
              itemCount: _messages.length + (_sending || _extracting ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length) {
                  return _InterviewMessageBubble(
                    message: _InterviewMessage(
                      text: _extracting ? '正在整理本次对话…' : '正在生成回复…',
                      isUser: false,
                    ),
                  );
                }
                return _InterviewMessageBubble(message: _messages[index]);
              },
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
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
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
            '这份整理不会自动进入辨证引擎，也不会自动选择问诊选项。',
            style: TextStyle(fontSize: AppType.micro, color: scheme.onSurfaceVariant),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.pop(context, draft.summaryLines.join('\n')),
              child: const Text('返回规则问诊'),
            ),
          ),
        ],
      ),
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
                      ? 'Gemma 4 E4B · ${status!.backend.toUpperCase()}'
                      : installed
                          ? '模型已放入设备，尚未加载'
                          : '等待安装 Gemma 4 E4B 模型',
                  style: const TextStyle(fontSize: AppType.caption, fontWeight: FontWeight.w600),
                ),
              ),
              if (ready)
                Text(
                  status!.sizeLabel,
                  style: TextStyle(fontSize: AppType.caption, color: scheme.onSurfaceVariant),
                ),
            ],
          ),
          if (!ready) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              installed
                  ? '模型文件大小符合要求：${status!.sizeLabel}。导入流程还会校验 SHA-256。'
                  : status?.fileExists == true
                      ? '检测到模型文件，但大小不符合要求。请重新选择完整模型文件。'
                      : '模型文件约 3.66 GB，不随 APK 打包，也不会自动联网下载；请从设备本地存储导入。',
              style: TextStyle(fontSize: AppType.caption, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.xs),
            SelectableText(
              status?.modelPath ?? 'Android 应用私有目录 /files/ai_models/gemma-4-E4B-it.litertlm',
              style: TextStyle(fontSize: AppType.micro, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _importingModel
                  ? '正在导入并校验文件，请保持应用在前台并确保设备有足够可用空间。'
                  : '导入时在本机流式复制并校验文件大小与 SHA-256；不会上传模型或请求模型服务。',
              style: TextStyle(fontSize: AppType.micro, color: scheme.onSurfaceVariant),
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
          ],
        ],
      ),
    );
  }
}

class _InterviewMessage {
  final String text;
  final bool isUser;

  const _InterviewMessage({required this.text, required this.isUser});
}

class _InterviewMessageBubble extends StatelessWidget {
  final _InterviewMessage message;

  const _InterviewMessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.84,
        ),
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: message.isUser
              ? scheme.primaryContainer
              : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: SelectableText(
          message.text,
          style: TextStyle(
            color: message.isUser ? scheme.onPrimaryContainer : scheme.onSurface,
            fontSize: AppType.body,
            height: 1.55,
          ),
        ),
      ),
    );
  }
}

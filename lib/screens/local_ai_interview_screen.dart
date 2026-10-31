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

class LocalAiInterviewScreen extends StatefulWidget {
  const LocalAiInterviewScreen({super.key});

  @override
  State<LocalAiInterviewScreen> createState() => _LocalAiInterviewScreenState();
}

class _LocalAiInterviewScreenState extends State<LocalAiInterviewScreen> {
  final LocalAiService _service = LocalAiService();
  final ImagePicker _imagePicker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();
  Timer? _recordingTimer;
  String? _imagePath;
  String? _audioPath;
  bool _recording = false;
  bool _recordingBusy = false;
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
  bool _checking = true;
  bool _loading = false;
  bool _sending = false;
  bool _extracting = false;
  LocalAiSymptomDraft? _confirmedDraft;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
    _recoverLostImage();
  }

  Future<void> _refreshStatus() async {
    try {
      final status = await _service.getStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _checking = false;
        _error = null;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = error.message ?? '当前平台尚未接入本地模型运行环境';
      });
    } on MissingPluginException {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = '本地 E4B 推理目前仅接入 Android 版本。';
      });
    }
  }

  Future<void> _loadModel() async {
    setState(() {
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
    }
  }

  Future<void> _deleteCachedAttachments(Iterable<String?> paths) async {
    try {
      final tempRoot = p.normalize((await getTemporaryDirectory()).absolute.path);
      for (final rawPath in paths) {
        if (rawPath == null || rawPath.isEmpty) continue;
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
      final response = await _imagePicker.retrieveLostData();
      if (response.isEmpty || response.files == null ||
          response.files!.isEmpty) {
        return;
      }
      final path = response.files!.first.path;
      if (path.isEmpty) return;
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
    }
  }

  Future<void> _pickTonguePhoto() async {
    if (_sending || _recording || _recordingBusy || _audioPath != null) return;
    try {
      final photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
        maxWidth: 1600,
        maxHeight: 1600,
        requestFullMetadata: false,
      );
      if (photo == null) return;
      if (!mounted) {
        await _deleteCachedAttachments([photo.path]);
        return;
      }
      final validationError = await _validateTonguePhoto(photo.path);
      if (!mounted) {
        await _deleteCachedAttachments([photo.path]);
        return;
      }
      if (validationError != null) {
        await _deleteCachedAttachments([photo.path]);
        if (!mounted) return;
        setState(() => _error = validationError);
        return;
      }
      final previousPath = _imagePath;
      setState(() {
        _imagePath = photo.path;
        _audioPath = null;
        _error = null;
      });
      if (previousPath != null && previousPath != photo.path) {
        unawaited(_deleteCachedAttachments([previousPath]));
      }
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message ?? '无法打开相机');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '照片检查失败：$error');
    }
  }

  Future<void> _startRecording() {
    if (_sending || _imagePath != null || _audioPath != null || _recording || _recordingBusy || _recorderMayBeActive) {
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
    try {
      final expectedPath = _activeRecordingPath;
      final path = await _audioRecorder.stop();
      _recorderMayBeActive = false;
      _activeRecordingPath = null;
      if (!mounted) {
        await _deleteCachedAttachments([path, expectedPath]);
        return;
      }
      final file = path == null ? null : File(path);
      if (file == null || !await file.exists() || await file.length() == 0) {
        await _deleteCachedAttachments([path, expectedPath]);
        if (!mounted) return;
        setState(() {
          _recordingBusy = false;
          _error = '没有生成有效录音，请重试。';
        });
        return;
      }
      if (await file.length() > 15 * 1024 * 1024) {
        await _deleteCachedAttachments([path]);
        if (!mounted) return;
        setState(() {
          _recordingBusy = false;
          _error = '录音文件超过 15 MB，请缩短语音后重录。';
        });
        return;
      }
      setState(() {
        _recordingBusy = false;
        _audioPath = path;
        _error = null;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _recordingBusy = false;
        _error = error.message ?? '录音结束失败';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _recordingBusy = false;
        _error = '录音文件处理失败：$error';
      });
    }
  }

  void _discardAttachment() {
    final paths = <String?>[_imagePath, _audioPath];
    setState(() {
      _imagePath = null;
      _audioPath = null;
      _error = null;
    });
    unawaited(_deleteCachedAttachments(paths));
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    final imagePath = _imagePath;
    final audioPath = _audioPath;
    if (_sending ||
        _recording ||
        _recordingBusy ||
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
      if (!mounted) return;
      _inputController.clear();
      setState(() {
        _messages.add(_InterviewMessage(text: reply, isUser: false));
        _sending = false;
        _imagePath = null;
        _audioPath = null;
      });
      _scrollToBottom();
    } on PlatformException catch (error) {
      if (!mounted) {
        await _deleteCachedAttachments([imagePath, audioPath]);
        return;
      }
      setState(() {
        _sending = false;
        _error = error.message ?? '本地推理失败';
      });
    } catch (error) {
      if (!mounted) {
        await _deleteCachedAttachments([imagePath, audioPath]);
        return;
      }
      setState(() {
        _sending = false;
        _error = '处理失败：$error';
      });
    }
  }

  Future<void> _extractSymptoms() async {
    setState(() {
      _extracting = true;
      _error = null;
    });
    try {
      final draft = await _service.extractSymptoms();
      if (!mounted) return;
      setState(() => _extracting = false);
      if (draft.summaryLines.isEmpty) {
        setState(() => _error = '目前没有提取到明确的自述信息，请补充描述后再整理。');
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
                      style: TextStyle(fontSize: 13, height: 1.45),
                    ),
                    const SizedBox(height: 12),
                    ...draft.summaryLines.map(
                      (line) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(line, style: const TextStyle(fontSize: 13)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: checked,
                      onChanged: (value) =>
                          setDialogState(() => checked = value == true),
                      title: const Text(
                        '我已核对，内容符合我的实际描述',
                        style: TextStyle(fontSize: 13),
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
    }
  }

  Future<void> _releaseModel() async {
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
      if (!mounted) return;
      setState(() => _error = error.message ?? '无法释放模型');
    }
  }

  Future<void> _resetConversation() async {
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
      if (!mounted) return;
      setState(() => _error = error.message ?? '无法重置会话');
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
              onPressed: _sending || _extracting || _recordingBusy || _recording ? null : _resetConversation,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: '释放模型内存',
              onPressed: _sending || _extracting || _recordingBusy || _recording ? null : _releaseModel,
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            color: scheme.surfaceContainerLow,
            child: Text(
              'AI 只负责交流和整理自述信息；六经辨证仍由原有规则问诊流程完成，不会由模型开方或调整剂量。',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
          if (ready && _confirmedDraft == null && _messages.any((m) => m.isUser))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _sending || _extracting ? null : _extractSymptoms,
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
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              color: scheme.errorContainer,
              child: Text(
                _error!,
                style: TextStyle(color: scheme.onErrorContainer, fontSize: 12),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_imagePath != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(_imagePath!),
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              '舌象照片已选。请确认光线自然、对焦清晰、无滤镜。',
                              style: TextStyle(fontSize: 12, height: 1.4),
                            ),
                          ),
                          IconButton(
                            tooltip: '移除照片',
                            onPressed: _sending ? null : _discardAttachment,
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                  if (_audioPath != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.graphic_eq, size: 20),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text('语音已录制（最长 30 秒），发送前可移除。', style: TextStyle(fontSize: 12)),
                          ),
                          IconButton(
                            tooltip: '移除录音',
                            onPressed: _sending ? null : _discardAttachment,
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                  if (_recording)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
                          SizedBox(width: 6),
                          Text('正在录音，最长 30 秒…', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: '拍摄舌象',
                        onPressed: ready &&
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
                                !_sending &&
                                !_extracting &&
                                !_recordingBusy &&
                                !_recorderMayBeActive &&
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
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filled(
                        tooltip: '发送',
                        onPressed: ready &&
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

  Widget _buildConfirmedDraftPanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final draft = _confirmedDraft!;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '已核对的用户自述',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          ...draft.summaryLines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(line, style: const TextStyle(fontSize: 12, height: 1.4)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '这份整理不会自动进入辨证引擎，也不会自动选择问诊选项。',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
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

    final status = _status;
    final ready = status?.ready == true;
    final installed = status?.installed == true;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ready
                      ? 'Gemma 4 E4B · ${status!.backend.toUpperCase()}'
                      : installed
                          ? '模型已放入设备，尚未加载'
                          : '等待安装 Gemma 4 E4B 模型',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              if (ready)
                Text(
                  status!.sizeLabel,
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
            ],
          ),
          if (!ready) ...[
            const SizedBox(height: 7),
            Text(
              installed
                  ? '模型文件：${status!.sizeLabel}'
                  : status?.fileExists == true
                      ? '文件大小不符合当前 E4B 模型包要求（应为 3.66 GB），请重新复制完整文件。'
                      : '模型文件不随 APK 下载或打包，需由用户放入应用私有目录。',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 5),
            SelectableText(
              status?.modelPath ?? 'Android 应用私有目录 /files/ai_models/gemma-4-E4B-it.litertlm',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: installed && !_loading ? _loadModel : null,
                child: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('加载本地模型'),
              ),
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
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: message.isUser
              ? scheme.primaryContainer
              : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
        ),
        child: SelectableText(
          message.text,
          style: TextStyle(
            color: message.isUser ? scheme.onPrimaryContainer : scheme.onSurface,
            fontSize: 14,
            height: 1.55,
          ),
        ),
      ),
    );
  }
}

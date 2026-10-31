import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/services/local_ai_service.dart';

void main() {
  group('LocalAiModelStatus', () {
    test('reads installed model and active backend', () {
      final status = LocalAiModelStatus.fromMap({
        'installed': true,
        'ready': true,
        'fileExists': true,
        'modelPath': '/data/user/0/app/files/ai_models/gemma-4-E4B-it.litertlm',
        'sizeBytes': 3659530240,
        'expectedSizeBytes': 3659530240,
        'backend': 'gpu',
      });

      expect(status.installed, isTrue);
      expect(status.fileExists, isTrue);
      expect(status.ready, isTrue);
      expect(status.backend, 'gpu');
      expect(status.sizeLabel, '3.66 GB');
      expect(status.modelPath, contains('gemma-4-E4B-it.litertlm'));
    });

    test('uses safe defaults when native fields are missing', () {
      final status = LocalAiModelStatus.fromMap(const {});

      expect(status.installed, isFalse);
      expect(status.fileExists, isFalse);
      expect(status.ready, isFalse);
      expect(status.modelPath, isEmpty);
      expect(status.sizeBytes, 0);
      expect(status.expectedSizeBytes, 3659530240);
      expect(status.backend, 'not_loaded');
      expect(status.sizeLabel, '尚未安装');
    });

    test('does not report a model as installed for an empty file', () {
      final status = LocalAiModelStatus.fromMap({
        'installed': false,
        'ready': false,
        'sizeBytes': 0,
      });

      expect(status.installed, isFalse);
      expect(status.ready, isFalse);
      expect(status.sizeLabel, '尚未安装');
    });
  });
}

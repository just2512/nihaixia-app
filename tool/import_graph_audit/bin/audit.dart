import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

Future<void> main(List<String> args) async {
  final root = Directory(args.isEmpty ? '../../lib' : args.single);
  if (!root.existsSync()) {
    stderr.writeln('Dart source root does not exist: ${root.path}');
    exitCode = 2;
    return;
  }

  final dispatcher = File(
    '${root.path}/services/headless_tool_dispatcher.dart',
  ).absolute.path;
  final files = root
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final violations = <String>[];
  final parseFailures = <String>[];
  var executorImportCount = 0;

  for (final file in files) {
    final source = await file.readAsString();
    final parsed = parseString(content: source, path: file.path);
    if (parsed.errors.isNotEmpty) {
      parseFailures.add(file.path);
      for (final error in parsed.errors) {
        stderr.writeln(
          'PARSE ERROR ${file.path}:${error.offset}: ${error.message}',
        );
      }
      continue;
    }

    for (final directive in parsed.unit.directives.whereType<ImportDirective>()) {
      final uri = directive.uri.stringValue;
      if (uri == null || !uri.endsWith('_tool_executor.dart')) continue;
      executorImportCount++;
      if (file.absolute.path != dispatcher) {
        violations.add('${file.path} imports $uri');
      }
    }
  }

  if (executorImportCount == 0) {
    violations.add('No *_tool_executor.dart imports were found in lib/.');
  }

  if (parseFailures.isNotEmpty || violations.isNotEmpty) {
    for (final violation in violations) {
      stderr.writeln('IMPORT BOUNDARY VIOLATION: $violation');
    }
    stderr.writeln(
      'FAIL: ${parseFailures.length} Dart parse failures, '
      '${violations.length} import-boundary violations.',
    );
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'PASS: $executorImportCount executor imports are owned exclusively '
    'by lib/services/headless_tool_dispatcher.dart.',
  );
}

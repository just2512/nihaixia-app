import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

class _ForbiddenUiNodeVisitor extends RecursiveAstVisitor<void> {
  final Set<String> found = {};

  static const forbiddenNames = {
    'BuildContext',
    'Navigator',
    'NavigatorState',
    'Widget',
    'WidgetBuilder',
  };

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (forbiddenNames.contains(node.name)) found.add(node.name);
    super.visitSimpleIdentifier(node);
  }
}

Future<void> main(List<String> args) async {
  final root = Directory(args.isEmpty ? '../../lib' : args.single);
  if (!root.existsSync()) {
    stderr.writeln('Dart source root does not exist: ${root.path}');
    exitCode = 2;
    return;
  }

  final dispatcher = File(
    '${root.path}/services/headless_tool_dispatcher.dart',
  ).absolute.path.replaceAll(Platform.pathSeparator, '/');
  final files = root
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final violations = <String>[];
  final parseFailures = <String>[];
  var executorReferenceCount = 0;

  String normalizedPath(File file) =>
      file.absolute.path.replaceAll(Platform.pathSeparator, '/');

  void inspectExecutorUri(String? uri, File importer) {
    if (uri == null || !uri.endsWith('_tool_executor.dart')) return;
    executorReferenceCount++;
    if (normalizedPath(importer) != dispatcher) {
      violations.add('${importer.path} imports Executor implementation directly: $uri');
    }
  }

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

    for (final directive in parsed.unit.directives) {
      if (directive is ImportDirective) {
        inspectExecutorUri(directive.uri.stringValue, file);
        for (final configuration in directive.configurations) {
          inspectExecutorUri(configuration.uri.stringValue, file);
        }
        if (file.absolute.path == dispatcher &&
            (directive.uri.stringValue?.startsWith('package:flutter/') ??
                false)) {
          violations.add(
            'headless_tool_dispatcher.dart imports Flutter directly',
          );
        }
        for (final configuration in directive.configurations) {
          if (file.absolute.path == dispatcher &&
              (configuration.uri.stringValue?.startsWith('package:flutter/') ??
                  false)) {
            violations.add(
              'headless_tool_dispatcher.dart conditionally imports Flutter',
            );
          }
        }
      } else if (directive is ExportDirective) {
        inspectExecutorUri(directive.uri.stringValue, file);
        for (final configuration in directive.configurations) {
          inspectExecutorUri(configuration.uri.stringValue, file);
        }
      }
    }

    if (normalizedPath(file) == dispatcher) {
      final visitor = _ForbiddenUiNodeVisitor();
      parsed.unit.accept(visitor);
      for (final name in visitor.found) {
        violations.add(
          'headless_tool_dispatcher.dart references UI symbol $name',
        );
      }
    }
  }

  if (executorReferenceCount == 0) {
    violations.add('No *_tool_executor.dart references were found in lib/.');
  }

  if (parseFailures.isNotEmpty || violations.isNotEmpty) {
    for (final violation in violations) {
      stderr.writeln('IMPORT BOUNDARY VIOLATION: $violation');
    }
    stderr.writeln(
      'FAIL: ${parseFailures.length} Dart parse failures, '
      '${violations.length} import/UI-boundary violations.',
    );
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'PASS: $executorReferenceCount Executor imports are owned exclusively '
    'by lib/services/headless_tool_dispatcher.dart; Dispatcher has no Flutter UI '
    'imports or UI symbols.',
  );
}

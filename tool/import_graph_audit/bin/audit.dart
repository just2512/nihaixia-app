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
  ).absolute.path;
  final files = root
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final violations = <String>[];
  final parseFailures = <String>[];
  var dispatcherExecutorReferenceCount = 0;
  var headlessEntryImportCount = 0;
  final scannedHeadlessEntrypoints = <String>{};

  String normalizedPath(File file) => file.absolute.path.replaceAll('\\\\', '/');

  bool isHeadlessUiEntrypoint(File file) {
    final path = normalizedPath(file);
    return path.endsWith('/screens/assistant_tool_router.dart') ||
        path.endsWith('/screens/local_ai_interview_screen.dart') ||
        path.endsWith('/services/assistant_conversation_orchestrator.dart');
  }

  void inspectExecutorUri(String? uri, File importer) {
    if (uri == null || !uri.endsWith('_tool_executor.dart')) return;
    if (normalizedPath(importer) == dispatcher) {
      dispatcherExecutorReferenceCount++;
    } else if (isHeadlessUiEntrypoint(importer)) {
      headlessEntryImportCount++;
      violations.add('${importer.path} imports a Headless Executor directly: $uri');
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

    if (isHeadlessUiEntrypoint(file)) {
      scannedHeadlessEntrypoints.add(normalizedPath(file));
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

  if (dispatcherExecutorReferenceCount == 0) {
    violations.add('HeadlessToolDispatcher does not import any *_tool_executor.dart implementation.');
  }
  if (scannedHeadlessEntrypoints.length != 3) {
    violations.add('Expected to scan all 3 Headless UI entrypoints; found ${scannedHeadlessEntrypoints.length}.');
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
    'PASS: all 3 Headless UI entrypoints have no direct Executor imports; '
    'HeadlessToolDispatcher owns $dispatcherExecutorReferenceCount Executor imports '
    'and has no Flutter UI imports or UI symbols. Page-specific execution and '
    'result-context consumers remain outside this dispatch-boundary gate.',
  );
}

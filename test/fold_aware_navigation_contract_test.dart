import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps fold-aware routing as an enforceable production-code contract.
///
/// ChatScreen has one narrow exception: its local-AI hand-off computes an
/// anchor from the invoking BuildContext and passes it to AdaptiveSinglePane.
void main() {
  test('production dialogs use the fold-aware dialog helper', () async {
    final sources = await _loadProductionSources();
    final directDialogCall = RegExp(r'\bshowDialog(?:<[^>]+>)?\s*\(');
    final violations = <String>[];

    for (final source in sources) {
      // fold_aware_routes.dart defines showFoldAwareDialog/FoldAwareMaterialPageRoute;
      // it legitimately calls showDialog and extends MaterialPageRoute.
      if (source.key == 'lib/utils/fold_aware_routes.dart') continue;
      for (final match in directDialogCall.allMatches(source.value)) {
        violations.add(
          '${source.key}:${_lineNumber(source.value, match.start)}',
        );
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Use showFoldAwareDialog for dialogs opened from screens or widgets. '
          'Direct showDialog calls bypass the source-panel anchor.\n'
          '${violations.join('\n')}',
    );
  });

  test('production full-page routes are fold-aware or explicitly anchored',
      () async {
    final sources = await _loadProductionSources();
    final barePageRoute = RegExp(r'\bMaterialPageRoute(?:<[^>]+>)?\s*\(');
    final anchoredLocalAiRoute = RegExp(
      r'final routeAnchorPoint = foldAwareRouteAnchorPoint\(context\);\s*'
      r'final summary = await Navigator\.push<String>\(\s*context,\s*'
      r'MaterialPageRoute\(\s*builder:\s*\(_\)\s*=>\s*'
      r'LocalAiInterviewScreen\(\s*preferredAnchorPoint:\s*routeAnchorPoint',
    );
    final violations = <String>[];

    for (final source in sources) {
      if (source.key == 'lib/utils/fold_aware_routes.dart') continue;
      final routeMatches = barePageRoute.allMatches(source.value).toList();
      for (final match in routeMatches) {
        final documentedLocalAiException =
            source.key == 'lib/screens/chat_screen.dart' &&
                routeMatches.length == 1 &&
                anchoredLocalAiRoute.allMatches(source.value).any(
                      (exception) =>
                          exception.start <= match.start &&
                          exception.end >= match.end,
                    );

        if (!documentedLocalAiException) {
          violations.add(
            '${source.key}:${_lineNumber(source.value, match.start)}',
          );
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Use FoldAwareMaterialPageRoute for full-page navigation. '
          'The only direct route exception is ChatScreen local-AI hand-off, '
          'which must pass a source-derived preferredAnchorPoint.\n'
          '${violations.join('\n')}',
    );
  });
}

Future<List<MapEntry<String, String>>> _loadProductionSources() async {
  final sources = <MapEntry<String, String>>[];

  for (final rootPath in ['lib/screens', 'lib/widgets', 'lib/utils']) {
    final root = Directory(rootPath);
    if (!await root.exists()) {
      fail('Required production source directory is missing: $rootPath');
    }

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relativePath = entity.path.replaceAll(
        Platform.pathSeparator,
        '/',
      );
      sources.add(
        MapEntry(relativePath, await entity.readAsString()),
      );
    }
  }

  sources.sort((a, b) => a.key.compareTo(b.key));
  return sources;
}

int _lineNumber(String source, int offset) {
  return '\n'.allMatches(source.substring(0, offset)).length + 1;
}

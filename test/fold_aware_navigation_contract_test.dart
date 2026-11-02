import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps fold-aware routing as an enforceable production-code contract.
///
/// The only direct MaterialPageRoute call in screens/widgets is the local-AI
/// interview hand-off in ChatScreen. That route explicitly computes an anchor
/// from its invoking BuildContext and passes it to AdaptiveSinglePane.
void main() {
  test('production dialogs use the fold-aware dialog helper', () async {
    final sources = await _loadProductionSources();
    final directDialogCall = RegExp(r'\\bshowDialog(?:<[^>]+>)?\\s*\\(');
    final violations = <String>[];

    for (final source in sources) {
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
    final barePageRoute = RegExp(r'\\bMaterialPageRoute(?:<[^>]+>)?\\s*\\(');
    const sourceAnchor = 'final routeAnchorPoint = '
        'foldAwareRouteAnchorPoint(context);';
    const preferredAnchor = 'preferredAnchorPoint: routeAnchorPoint';
    final violations = <String>[];

    for (final source in sources) {
      for (final match in barePageRoute.allMatches(source.value)) {
        final anchorIsComputedBeforeRoute =
            source.value.lastIndexOf(sourceAnchor, match.start) >= 0;
        final anchorIsPassedToDestination =
            source.value.indexOf(preferredAnchor, match.end) > match.end;
        final documentedLocalAiException =
            source.key == 'lib/screens/chat_screen.dart' &&
                anchorIsComputedBeforeRoute &&
                anchorIsPassedToDestination;

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
          'A direct MaterialPageRoute is allowed only when the destination '
          'receives a source-derived preferredAnchorPoint.\n'
          '${violations.join('\n')}',
    );
  });
}

Future<List<MapEntry<String, String>>> _loadProductionSources() async {
  final sources = <MapEntry<String, String>>[];

  for (final rootPath in ['lib/screens', 'lib/widgets']) {
    final root = Directory(rootPath);
    if (!await root.exists()) {
      fail('Required production source directory is missing: $rootPath');
    }

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relativePath = entity.path.replaceAll('\\\\', '/');
      sources.add(
        MapEntry(relativePath, await entity.readAsString()),
      );
    }
  }

  sources.sort((a, b) => a.key.compareTo(b.key));
  return sources;
}

int _lineNumber(String source, int offset) {
  return '\\n'.allMatches(source.substring(0, offset)).length + 1;
}

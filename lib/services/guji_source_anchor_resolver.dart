import 'package:flutter/services.dart';

import '../data/guji_data.dart';

/// Resolves normalized chapter paragraphs back to physical lines in the
/// original public-domain TXT asset. If the chapter cannot be mapped uniquely,
/// the caller must leave contextual Ask AI disabled.
class GujiSourceAnchorResolver {
  static Future<List<int>?> loadSourceLineMap({
    required AssetBundle bundle,
    required GujiBook book,
    required GujiChapter chapter,
  }) async {
    if (chapter.index < 0) return null;

    final raw = await bundle.loadString(book.asset);
    final lines = raw.split('\n');
    final blocks = <List<int>>[];
    var current = <int>[];

    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      if (RegExp(r'^=+\s*$').hasMatch(lines[lineIndex].trim())) {
        blocks.add(current);
        current = <int>[];
      } else {
        current.add(lineIndex);
      }
    }
    blocks.add(current);

    var resolvedChapterIndex = 0;
    for (var blockIndex = 1;
        blockIndex + 1 < blocks.length;
        blockIndex += 2) {
      final title = blocks[blockIndex]
          .map((lineIndex) => lines[lineIndex].trim())
          .where((line) => line.isNotEmpty)
          .join(' ');
      final sourceBodyLines = blocks[blockIndex + 1]
          .where((lineIndex) => lines[lineIndex].trim().isNotEmpty)
          .toList(growable: false);
      final body = sourceBodyLines
          .map((lineIndex) => lines[lineIndex].trim())
          .join('\n');
      if (title.isEmpty || body.isEmpty) continue;

      if (resolvedChapterIndex == chapter.index) {
        // Verify this raw asset slice is still byte-for-byte equivalent after
        // the repository's normalization before exposing any source anchor.
        if (title != chapter.title || body != chapter.body) return null;
        final sourceLineMap = <int>[];
        for (var index = 0; index < sourceBodyLines.length; index++) {
          if (index > 0) sourceLineMap.add(-1);
          sourceLineMap.add(sourceBodyLines[index] + 1);
        }
        return sourceLineMap;
      }
      resolvedChapterIndex++;
    }
    return null;
  }
}

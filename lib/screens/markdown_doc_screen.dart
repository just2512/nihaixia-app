import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import '../utils/fold_aware_routes.dart';
import '../widgets/state_view.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../data/formula_repository.dart';
import '../data/herb_repository.dart';
import '../data/acupoint_repository.dart';
import '../data/zhenjiu_lecture_index.dart';
import 'formula_detail_screen.dart';
import 'herb_detail_screen.dart';
import 'acupoint_detail_screen.dart';
import '../models/ai_context_ref.dart';
import '../screens/assistant_tool_router.dart';
import '../services/ai_context_prompt_builder.dart';
import '../widgets/contextual_ai_sheet.dart';

/// 解码 flutter_markdown 传给 `onTapLink` 的 href。
///
/// flutter_markdown 会对链接目标做 percent-encoding：正文里的
/// `[四逆汤](formula://四逆汤)` 传到 `onTapLink` 时变成
/// `formula://%E5%9B%9B%E9%80%86%E6%B1%A4`。不在此解码，查库用的就是编码串，
/// 永远命中不到 → 点击「无任何反应」。
String decodeMarkdownHref(String href) {
  try {
    return Uri.decodeComponent(href);
  } catch (_) {
    return href; // 非法 % 序列：原样返回，不因一个坏链接崩掉整页
  }
}

/// 通用 Markdown 原文阅读页（加载 assets 资源渲染）。
/// 用于倪师《天纪》讲义/案例等原文展示，内容属传统文化参考。
///
/// [linkFormulas] 为真时，运行时将正文中出现的已知方剂名包成 `formula://方名`、
/// 药材名（含别名）包成 `herb://药名` 链接，点击分别跳转 [FormulaDetailScreen] /
/// [HerbDetailScreen]（实现闭门课正文↔方剂/药材双向联动）。
class MarkdownDocScreen extends StatefulWidget {
  final String title;

  /// 资产路径（从 assets 读取正文）。
  final String asset;

  /// 直接传入的 Markdown 正文（古籍原文按章节解析后走这里，无需一章一个资产）。
  /// 与 [asset] 二选一，[content] 优先。
  final String? content;

  final String? footer;
  final bool linkFormulas;

  /// Stable local entry identity. The contextual action is shown only when
  /// the raw document contains exactly one uniquely locatable blockquote.
  final String? contextualAskModuleId;
  final String? contextualAskAnchorId;
  final String? contextualAskSourceId;

  /// Enables safe paragraph-level contextual selection for prose lecture documents.
  final bool contextualAskParagraphs;
  /// Maps rendered Markdown line indices to original source line numbers.
  /// A value of -1 marks a synthetic separator line; invalid maps fail closed.
  final List<int>? contextualAskSourceLineMap;

  const MarkdownDocScreen({
    super.key,
    required this.title,
    this.asset = '',
    this.content,
    this.footer,
    this.linkFormulas = false,
    this.contextualAskModuleId,
    this.contextualAskAnchorId,
    this.contextualAskSourceId,
    this.contextualAskParagraphs = false,
    this.contextualAskSourceLineMap,
  }) : assert(asset != '' || content != null, 'asset 与 content 至少要提供一个');

  @override
  State<MarkdownDocScreen> createState() => _MarkdownDocScreenState();

  /// 构建随主题（含深色模式）生效的 Markdown 样式表。
  ///
  /// 修复背景：`MarkdownStyleSheet.fromTheme()` 有两处**不随主题切换**的硬编码：
  /// - `blockquoteDecoration` 固定 `Colors.blue.shade100`（#BBDEFB 浅蓝底）。深色
  ///   模式下引用块文字取 `textTheme.bodyMedium`（即 `onSurface` 近白 #F0DFD7），
  ///   白字压浅蓝底实测对比度仅 **1.09:1**（WCAG AA 要求 ≥4.5:1）。闭门课正文
  ///   通篇使用 `>` 引用块，故整页正文在深色模式下几乎不可读 —— 这正是
  ///   「标题/正文后面那块蓝色背景」的来源。
  /// - `a` 固定 `Colors.blue`（#2196F3），与品牌色不一致。
  ///
  /// 现全部改为读取 `ColorScheme` 语义色：文字统一 `onSurface`（深色 14.29:1 /
  /// 浅色 16.30:1），引用块底色 `surfaceContainerHighest`（浅色 #F0DFD7 / 深色
  /// #3D332D），并用一条 `primary` 竖线保留引用语义，蓝色块整体移除。
  static MarkdownStyleSheet styleSheetFor(ThemeData theme) {
    final cs = theme.colorScheme;
    final body =
        theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    final bodySize = body.fontSize ?? 14;
    final tt = theme.textTheme;
    return MarkdownStyleSheet(
      a: TextStyle(color: cs.primary, decoration: TextDecoration.underline),
      p: body.copyWith(color: cs.onSurface, fontSize: 14, height: 1.7),
      pPadding: EdgeInsets.zero,
      code: body.copyWith(
        color: cs.onSurface,
        backgroundColor: cs.surfaceContainerHighest,
        fontFamily: 'monospace',
        fontSize: bodySize * 0.85,
      ),
      h1: (tt.headlineSmall ?? const TextStyle(fontSize: 24))
          .copyWith(color: cs.onSurface),
      h1Padding: EdgeInsets.zero,
      h2: (tt.titleLarge ?? const TextStyle(fontSize: 22))
          .copyWith(color: cs.onSurface),
      h2Padding: EdgeInsets.zero,
      h3: (tt.titleMedium ?? const TextStyle(fontSize: 16))
          .copyWith(color: cs.onSurface),
      h3Padding: EdgeInsets.zero,
      h4: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
          .copyWith(color: cs.primary),
      h4Padding: EdgeInsets.zero,
      h5: (tt.bodyLarge ?? const TextStyle(fontSize: 16))
          .copyWith(color: cs.onSurface),
      h5Padding: EdgeInsets.zero,
      h6: (tt.bodyLarge ?? const TextStyle(fontSize: 16))
          .copyWith(color: cs.onSurface),
      h6Padding: EdgeInsets.zero,
      em: const TextStyle(fontStyle: FontStyle.italic),
      strong: const TextStyle(fontWeight: FontWeight.bold),
      del: const TextStyle(decoration: TextDecoration.lineThrough),
      blockquote:
          body.copyWith(color: cs.onSurface, fontSize: 14, height: 1.7),
      img: body.copyWith(color: cs.onSurface),
      checkbox: body.copyWith(color: cs.primary),
      blockSpacing: 8.0,
      listIndent: 24.0,
      listBullet: body.copyWith(color: cs.onSurface),
      listBulletPadding: const EdgeInsets.only(right: 4),
      tableHead: (tt.bodyMedium ?? body)
          .copyWith(color: cs.onSurface, fontWeight: FontWeight.w600),
      tableBody: body.copyWith(color: cs.onSurface),
      tableHeadAlign: TextAlign.center,
      tablePadding: const EdgeInsets.only(bottom: 4.0),
      tableBorder: TableBorder.all(color: cs.outlineVariant),
      tableColumnWidth: const FlexColumnWidth(),
      tableCellsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      tableCellsDecoration: const BoxDecoration(),
      blockquotePadding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      blockquoteDecoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius:
            const BorderRadius.horizontal(right: Radius.circular(4)),
        border: Border(left: BorderSide(color: cs.primary, width: 3)),
      ),
      codeblockPadding: const EdgeInsets.all(8.0),
      codeblockDecoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4.0),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(width: 1.0, color: cs.outlineVariant)),
      ),
    );
  }

  /// 便捷入口：从 [BuildContext] 取主题后构建样式表。
  static MarkdownStyleSheet buildStyleSheet(BuildContext context) =>
      styleSheetFor(Theme.of(context));
}

class _ContextualMarkdownPassage {
  const _ContextualMarkdownPassage({
    required this.before,
    required this.block,
    required this.plainText,
    required this.startLine,
    required this.endLine,
  });

  final String before;
  final String block;
  final String plainText;
  final int startLine;
  final int endLine;
}

class _MarkdownDocScreenState extends State<MarkdownDocScreen> {
  late Future<String> _future;
  String? _rawDocumentContent;
  final Map<int, String> _selectedTextByPassage = <int, String>{};

  bool get _contextualAskEnabled =>
      widget.contextualAskModuleId?.trim().isNotEmpty == true &&
      widget.contextualAskAnchorId?.trim().isNotEmpty == true &&
      widget.contextualAskSourceId?.trim().isNotEmpty == true;

  void _askAiAboutSelection(
    String selectedText,
    String fullPassage, {
    required int passageIndex,
    required int passageCount,
    String? stableAnchorId,
  }) {
    if (!_contextualAskEnabled || selectedText.trim().isEmpty) return;
    final moduleId = widget.contextualAskModuleId!;
    final baseAnchorId = widget.contextualAskAnchorId!;
    final anchorId = stableAnchorId ??
        (passageCount == 1
            ? baseAnchorId
            : baseAnchorId + ':passage:' + passageIndex.toString());
    final sourcePath = widget.contextualAskSourceId!;
    final version = sha256.convert(utf8.encode(fullPassage)).toString();
    final ref = AiContextRef(
      kind: AiContextKind.classic,
      moduleId: moduleId,
      anchorId: anchorId,
      anchorVersion: version,
      sourceId: moduleId + ':' + sourcePath,
      title: widget.title,
      selectedText: selectedText,
    );
    final prompt = AiContextPromptBuilder.buildClassicSelection(
      ref: ref,
      fullPassage: fullPassage,
    );
    unawaited(showContextualAiSheet(
      context: context,
      contextRef: ref,
      initialPrompt: prompt,
      initialMode: AssistantMode.learning,
      contextualTitle: widget.title,
      contextualExplanationOnly: true,
    ));
  }

  List<_ContextualMarkdownPassage> _findContextualPassages(String markdown) {
    final lines = markdown.split('\n');
    final starts = <int>[];
    final ends = <int>[];
    int? activeStart;
    for (var index = 0; index < lines.length; index++) {
      final isQuoteLine = RegExp(r'^\s*>\s?').hasMatch(lines[index]);
      if (isQuoteLine) {
        activeStart ??= index;
      } else if (activeStart != null) {
        starts.add(activeStart);
        ends.add(index);
        activeStart = null;
      }
    }
    if (activeStart != null) {
      starts.add(activeStart);
      ends.add(lines.length);
    }
    final passages = <_ContextualMarkdownPassage>[];
    var previousEnd = 0;
    for (var index = 0; index < starts.length; index++) {
      final start = starts[index];
      final end = ends[index];
      final blockLines = lines.sublist(start, end);
      final plainText = blockLines
          .map((line) => line.replaceFirst(RegExp(r'^\s*>\s?'), ''))
          .join('\n')
          .trim();
      if (plainText.isEmpty) return const <_ContextualMarkdownPassage>[];
      passages.add(_ContextualMarkdownPassage(
        before: lines.sublist(previousEnd, start).join('\n'),
        block: blockLines.join('\n'),
        plainText: plainText,
        startLine: start,
        endLine: end,
      ));
      previousEnd = end;
    }
    return passages;
  }

  /// Splits safe prose into source-addressable paragraphs. Markdown structures
  /// are deliberately excluded: headings, lists, quotes, tables, code, HTML,
  /// images and link definitions must never expose the contextual action.
  List<_ContextualMarkdownPassage> _findContextualParagraphs(String markdown) {
    final lines = markdown.split('\n');
    final passages = <_ContextualMarkdownPassage>[];
    int? activeStart;
    var activeContainsUnsafeBlock = false;
    var insideFence = false;
    String? fenceCharacter;
    var fenceLength = 0;
    final htmlBlockStack = <String>[];
    var insideHtmlComment = false;
    var insideCdata = false;
    String? mathClosingDelimiter;
    String? mathEnvironment;

    const voidHtmlTags = <String>{
      'area',
      'base',
      'br',
      'col',
      'embed',
      'hr',
      'img',
      'input',
      'link',
      'meta',
      'param',
      'source',
      'track',
      'wbr',
    };

    bool isSafeParagraph(List<String> blockLines) {
      if (blockLines.isEmpty) return false;
      for (final line in blockLines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty ||
            RegExp(r'^\s{0,3}#{1,6}\s+').hasMatch(line) ||
            RegExp(r'^\s*>').hasMatch(line) ||
            RegExp(r'^\s*(?:[-*+]\s+|\d+[.)]\s+)').hasMatch(line) ||
            RegExp(r'^\s*(?:-{3,}|_{3,}|\*{3,})\s*$').hasMatch(line) ||
            RegExp(r'^\s{4,}\S').hasMatch(line) ||
            RegExp(r'^\s*<').hasMatch(line) ||
            RegExp(r'<\/?[A-Za-z][^>]*>').hasMatch(line) ||
            RegExp(r'^\s*\$\$').hasMatch(line) ||
            RegExp(r'^\s*\\\[').hasMatch(line) ||
            RegExp(r'^\s*\\begin\{').hasMatch(line) ||
            RegExp(r'^\s*\[[^\]]+\]:\s').hasMatch(line) ||
            RegExp(r'^\s*\[\^[^\]]+\]:\s').hasMatch(line) ||
            RegExp(r'!\[[^\]]*\]\(').hasMatch(line) ||
            trimmed.startsWith('|') ||
            trimmed.startsWith('<!--')) {
          return false;
        }
      }
      final trailing = blockLines.last.trim();
      if (blockLines.length > 1 &&
          trailing.isNotEmpty &&
          trailing.codeUnits.every((unit) => unit == 0x3D)) {
        return false;
      }
      if (blockLines.length > 1 &&
          blockLines.any((line) => line.contains('|'))) {
        return false;
      }
      return blockLines.join('\n').trim().isNotEmpty;
    }

    void flush(int endLine) {
      final startLine = activeStart;
      if (startLine == null) return;
      final blockLines = lines.sublist(startLine, endLine);
      if (!activeContainsUnsafeBlock && isSafeParagraph(blockLines)) {
        final block = blockLines.join('\n');
        passages.add(_ContextualMarkdownPassage(
          before: '',
          block: block,
          plainText: block.trim(),
          startLine: startLine,
          endLine: endLine,
        ));
      }
      activeStart = null;
      activeContainsUnsafeBlock = false;
    }

    void consumeHtmlTags(String line) {
      final tags = RegExp(r'<(/?)([A-Za-z][A-Za-z0-9:-]*)\b[^>]*>');
      for (final match in tags.allMatches(line)) {
        final closing = match.group(1) == '/';
        final name = match.group(2)!.toLowerCase();
        final token = match.group(0)!.trimRight();
        final selfClosing =
            token.endsWith('/>') || voidHtmlTags.contains(name);
        if (closing) {
          final matchingIndex = htmlBlockStack.lastIndexOf(name);
          if (matchingIndex >= 0) {
            htmlBlockStack.removeRange(
              matchingIndex,
              htmlBlockStack.length,
            );
          }
        } else if (!selfClosing) {
          htmlBlockStack.add(name);
        }
      }
    }

    void beginUnsafeBlock(int lineIndex) {
      if (activeStart != null) flush(lineIndex);
      activeStart = lineIndex;
      activeContainsUnsafeBlock = true;
    }

    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final trimmed = line.trim();

      if (insideFence) {
        activeStart ??= index;
        activeContainsUnsafeBlock = true;
        final closingFence =
            RegExp(r'^\s*(\x60{3,}|~{3,})\s*$').firstMatch(line);
        if (closingFence != null) {
          final marker = closingFence.group(1)!;
          if (marker[0] == fenceCharacter && marker.length >= fenceLength) {
            insideFence = false;
            fenceCharacter = null;
            fenceLength = 0;
          }
        }
        continue;
      }

      final openingFence =
          RegExp(r'^\s*(\x60{3,}|~{3,})').firstMatch(line);
      if (openingFence != null) {
        beginUnsafeBlock(index);
        final marker = openingFence.group(1)!;
        insideFence = true;
        fenceCharacter = marker[0];
        fenceLength = marker.length;
        continue;
      }

      if (insideHtmlComment) {
        activeStart ??= index;
        activeContainsUnsafeBlock = true;
        if (line.contains('-->')) insideHtmlComment = false;
        continue;
      }

      if (insideCdata) {
        activeStart ??= index;
        activeContainsUnsafeBlock = true;
        if (line.contains(']]>')) insideCdata = false;
        continue;
      }

      if (htmlBlockStack.isNotEmpty) {
        activeStart ??= index;
        activeContainsUnsafeBlock = true;
        consumeHtmlTags(line);
        continue;
      }

      if (mathClosingDelimiter != null) {
        activeStart ??= index;
        activeContainsUnsafeBlock = true;
        if (trimmed.contains(mathClosingDelimiter)) {
          mathClosingDelimiter = null;
        }
        continue;
      }

      final activeMathEnvironment = mathEnvironment;
      if (activeMathEnvironment != null) {
        activeStart ??= index;
        activeContainsUnsafeBlock = true;
        if (line.contains(r'\end{' + activeMathEnvironment + '}')) {
          mathEnvironment = null;
        }
        continue;
      }

      final commentStart = line.indexOf('<!--');
      if (commentStart >= 0) {
        beginUnsafeBlock(index);
        if (!line.substring(commentStart + 4).contains('-->')) {
          insideHtmlComment = true;
        }
        continue;
      }

      final cdataStart = line.indexOf('<![CDATA[');
      if (cdataStart >= 0) {
        beginUnsafeBlock(index);
        if (!line.substring(cdataStart + 9).contains(']]>')) {
          insideCdata = true;
        }
        continue;
      }

      if (trimmed.startsWith(r'$$')) {
        beginUnsafeBlock(index);
        if (trimmed.indexOf(r'$$', 2) < 0) {
          mathClosingDelimiter = r'$$';
        }
        continue;
      }

      if (trimmed.startsWith(r'\[')) {
        beginUnsafeBlock(index);
        if (trimmed.indexOf(r'\]', 2) < 0) {
          mathClosingDelimiter = r'\]';
        }
        continue;
      }

      final environmentStart =
          RegExp(r'^\s*\\begin\{([^}]+)\}').firstMatch(line);
      if (environmentStart != null) {
        beginUnsafeBlock(index);
        final environment = environmentStart.group(1)!;
        if (!line.contains(r'\end{' + environment + '}')) {
          mathEnvironment = environment;
        }
        continue;
      }

      final htmlTagAtStart =
          RegExp(r'^\s*</?([A-Za-z][A-Za-z0-9:-]*)\b[^>]*>').hasMatch(line);
      if (htmlTagAtStart) {
        beginUnsafeBlock(index);
        consumeHtmlTags(line);
        continue;
      }

      if (trimmed.isEmpty) {
        flush(index);
        continue;
      }

      activeStart ??= index;
    }

    flush(lines.length);
    return passages;
  }

  Widget _buildContextualParagraphBody(String data) {
    final raw = _rawDocumentContent ?? data;
    final rawPassages = _findContextualParagraphs(raw);
    final lines = data.split('\n');
    debugPrint(
      '[ContextualParagraph] module=${widget.contextualAskModuleId} '
      'enabled=$_contextualAskEnabled paragraphs=${widget.contextualAskParagraphs} '
      'anchor=${widget.contextualAskAnchorId} source=${widget.contextualAskSourceId} '
      'rawReady=${_rawDocumentContent != null} rawLines=${raw.split('\n').length} '
      'displayLines=${lines.length} rawPassages=${rawPassages.length}',
    );

    // _injectLinks only wraps matched text inline and never inserts line breaks.
    // Therefore the original Markdown source line numbers remain the stable
    // mapping even when injected links change how a rendered paragraph would
    // be classified by a second Markdown-structure scan.
    final sourceLineMap = widget.contextualAskSourceLineMap;
    var sourceLineMapValid = true;
    if (sourceLineMap != null) {
      sourceLineMapValid = sourceLineMap.length == lines.length;
      var previousSourceLine = 0;
      if (sourceLineMapValid) {
        for (final sourceLine in sourceLineMap) {
          if (sourceLine == -1) continue;
          if (sourceLine <= previousSourceLine) {
            sourceLineMapValid = false;
            break;
          }
          previousSourceLine = sourceLine;
        }
      }
      if (sourceLineMapValid) {
        for (final passage in rawPassages) {
          if (passage.startLine < 0 ||
              passage.endLine <= passage.startLine ||
              passage.endLine > sourceLineMap.length ||
              sourceLineMap[passage.startLine] <= 0 ||
              sourceLineMap[passage.endLine - 1] <= 0) {
            sourceLineMapValid = false;
            break;
          }
        }
      }
    }
    final passagesMatch = rawPassages.isNotEmpty &&
        raw.split('\n').length == lines.length &&
        sourceLineMapValid;
    if (!passagesMatch) {
      // If any transformation changes the source line count, keep ordinary
      // selection only and fail closed for contextual AI.
      return Markdown(
        data: data,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        selectable: true,
        onTapLink: (text, href, title) => _onTapLink(href),
        styleSheet: MarkdownDocScreen.buildStyleSheet(context),
      );
    }

    final children = <Widget>[];
    var previousEnd = 0;
    final baseAnchorId = widget.contextualAskAnchorId!;
    for (var passageIndex = 0;
        passageIndex < rawPassages.length;
        passageIndex++) {
      final passage = rawPassages[passageIndex];
      final before = lines.sublist(previousEnd, passage.startLine).join('\n');
      if (before.trim().isNotEmpty || passageIndex == 0) {
        children.add(_buildPlainMarkdownBody(
          before,
          selectable: true,
          padding: EdgeInsets.fromLTRB(16, passageIndex == 0 ? 12 : 0, 16, 0),
        ));
      }
      final sourceStartLine =
          sourceLineMap == null
              ? passage.startLine + 1
              : sourceLineMap[passage.startLine];
      final sourceEndLine =
          sourceLineMap == null
              ? passage.endLine
              : sourceLineMap[passage.endLine - 1];
      final stableAnchorId = baseAnchorId +
          ':paragraph:' +
          sourceStartLine.toString() +
          '-' +
          sourceEndLine.toString();
      final displayedBlock =
          lines.sublist(passage.startLine, passage.endLine).join('\n');
      children.add(SelectionArea(
        onSelectionChanged: (selection) {
          final selected = selection?.plainText ?? '';
          if (_selectedTextByPassage[passageIndex] == selected) return;
          setState(() {
            if (selected.isEmpty) {
              _selectedTextByPassage.remove(passageIndex);
            } else {
              _selectedTextByPassage[passageIndex] = selected;
            }
          });
        },
        contextMenuBuilder: (context, state) {
          final items =
              List<ContextMenuButtonItem>.of(state.contextMenuButtonItems);
          final selected = _selectedTextByPassage[passageIndex] ?? '';
          if (selected.trim().isNotEmpty) {
            items.add(ContextMenuButtonItem(
              label: '问 AI',
              onPressed: () {
                state.hideToolbar();
                _askAiAboutSelection(
                  selected,
                  passage.plainText,
                  passageIndex: passageIndex,
                  passageCount: rawPassages.length,
                  stableAnchorId: stableAnchorId,
                );
              },
            ));
          }
          return AdaptiveTextSelectionToolbar.buttonItems(
            anchors: state.contextMenuAnchors,
            buttonItems: items,
          );
        },
        child: _buildPlainMarkdownBody(
          displayedBlock,
          selectable: false,
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ));
      previousEnd = passage.endLine;
    }
    final trailing = lines.skip(previousEnd).join('\n');
    if (trailing.trim().isNotEmpty) {
      children.add(_buildPlainMarkdownBody(
        trailing,
        selectable: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      ));
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _buildPlainMarkdownBody(
    String data, {
    required bool selectable,
    required EdgeInsets padding,
  }) {
    if (data.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: MarkdownBody(
        data: data,
        selectable: selectable,
        onTapLink: (text, href, title) => _onTapLink(href),
        styleSheet: MarkdownDocScreen.buildStyleSheet(context),
      ),
    );
  }

  Widget _buildMarkdownBody(String data) {
    if (!_contextualAskEnabled) {
      return Markdown(
        data: data,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        selectable: true,
        onTapLink: (text, href, title) => _onTapLink(href),
        styleSheet: MarkdownDocScreen.buildStyleSheet(context),
      );
    }
    if (widget.contextualAskParagraphs) {
      return _buildContextualParagraphBody(data);
    }
    final raw = _rawDocumentContent ?? data;
    final rawPassages = _findContextualPassages(raw);
    final displayedPassages = _findContextualPassages(data);
    var passagesMatch = rawPassages.isNotEmpty &&
        rawPassages.length == displayedPassages.length;
    for (var index = 0; passagesMatch && index < rawPassages.length; index++) {
      passagesMatch = rawPassages[index].startLine == displayedPassages[index].startLine &&
          rawPassages[index].endLine == displayedPassages[index].endLine;
    }
    if (!passagesMatch) {
      // Fail closed if raw and displayed quote blocks cannot be mapped one-to-one.
      return Markdown(
        data: data,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        selectable: true,
        onTapLink: (text, href, title) => _onTapLink(href),
        styleSheet: MarkdownDocScreen.buildStyleSheet(context),
      );
    }

    final lines = data.split('\n');
    final children = <Widget>[];
    var previousEnd = 0;
    for (var passageIndex = 0; passageIndex < displayedPassages.length; passageIndex++) {
      final passage = displayedPassages[passageIndex];
      final before = lines.sublist(previousEnd, passage.startLine).join('\n');
      if (before.trim().isNotEmpty || passageIndex == 0) {
        children.add(_buildPlainMarkdownBody(
          before,
          selectable: true,
          padding: EdgeInsets.fromLTRB(16, passageIndex == 0 ? 12 : 0, 16, 0),
        ));
      }
      children.add(SelectionArea(
        onSelectionChanged: (selection) {
          final selected = selection?.plainText ?? '';
          if (_selectedTextByPassage[passageIndex] == selected) return;
          setState(() {
            if (selected.isEmpty) {
              _selectedTextByPassage.remove(passageIndex);
            } else {
              _selectedTextByPassage[passageIndex] = selected;
            }
          });
        },
        contextMenuBuilder: (context, state) {
          final items = List<ContextMenuButtonItem>.of(state.contextMenuButtonItems);
          final selected = _selectedTextByPassage[passageIndex] ?? '';
          if (selected.trim().isNotEmpty) {
            items.add(ContextMenuButtonItem(
              label: '问 AI',
              onPressed: () {
                state.hideToolbar();
                _askAiAboutSelection(
                  selected,
                  rawPassages[passageIndex].plainText,
                  passageIndex: passageIndex,
                  passageCount: rawPassages.length,
                );
              },
            ));
          }
          return AdaptiveTextSelectionToolbar.buttonItems(
            anchors: state.contextMenuAnchors,
            buttonItems: items,
          );
        },
        child: _buildPlainMarkdownBody(
          passage.block,
          selectable: false,
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ));
      previousEnd = passage.endLine;
    }
    final trailing = lines.skip(previousEnd).join('\n');
    if (trailing.trim().isNotEmpty) {
      children.add(_buildPlainMarkdownBody(
        trailing,
        selectable: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      ));
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<String> _load() async {
    final raw = widget.content ?? await rootBundle.loadString(widget.asset);
    _rawDocumentContent = raw;
    return widget.linkFormulas ? _injectLinks(raw) : raw;
  }

  void _reload() {
    setState(() => _future = _load());
  }

  /// 将正文中的已知方剂名、药材名（含别名）、穴位名（含排除名单）包成链接，
  /// 点击分别跳方剂 / 药材 / 穴位详情。
  /// 三类合并为单一候选集、长度降序、单次非重叠扫描，避免嵌套/二次包裹。
  String _injectLinks(String md) {
    final formulaNames = FormulaRepository.getAll()
        .map((f) => f.name)
        .where((n) => n.length >= 2)
        .toList();
    final herbCandidates = <String>{
      ...HerbRepository.getAll().map((h) => h.name),
      ...HerbRepository.aliasNames,
    }.where((n) => n.length >= 2).toList();

    // 穴位候选：仓库正名去「穴」后缀 + 短名映射（子宫→子宫穴），
    // 应用讲稿排除名单（太阳/光明——详见 zhenjiu_lecture_index）。
    final shortForm = AcupointRepository.kShortNameLinkForm;
    final excluded = ZhenJiuLectureIndex.cachedExcluded ??
        ZhenJiuLectureIndex.kFallbackExcluded.toSet();
    final acupointCandidates = AcupointRepository.allNames
        .map((n) => shortForm[n] ?? n)
        .where((n) => n.length >= 2 && !excluded.contains(n.replaceAll('穴', '')))
        .toList();

    // 名称 → 链接类型；方剂优先（同名时 formula 生效，herb/acupoint 的 putIfAbsent 不覆盖）。
    final targetOf = <String, String>{};
    for (final n in formulaNames) {
      targetOf.putIfAbsent(n, () => 'formula');
    }
    for (final n in herbCandidates) {
      targetOf.putIfAbsent(n, () => 'herb');
    }
    for (final n in acupointCandidates) {
      targetOf.putIfAbsent(n, () => 'acupoint');
    }
    if (targetOf.isEmpty) return md;

    // Inline replacement must preserve Markdown source line boundaries.
    final sorted = targetOf.keys
        .where((name) => !name.contains('\n') && !name.contains('\r'))
        .toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final re = RegExp(sorted.map(RegExp.escape).join('|'));
    return md.replaceAllMapped(re, (m) {
      final name = m.group(0)!;
      final type = targetOf[name]!;
      return '[$name]($type://$name)';
    });
  }

  void _onTapLink(String? href) {
    if (href == null) return;
    if (href.startsWith('formula://')) {
      final name = decodeMarkdownHref(href.substring('formula://'.length));
      final formula = FormulaRepository.getByName(name);
      if (formula != null && mounted) {
        Navigator.push(
          context,
          FoldAwareMaterialPageRoute(sourceContext: context, 
              builder: (_) => FormulaDetailScreen(formula: formula)),
        );
      }
    } else if (href.startsWith('acupoint://')) {
      final name = decodeMarkdownHref(href.substring('acupoint://'.length));
      final acupoint = AcupointRepository.findByName(name);
      if (acupoint != null && mounted) {
        Navigator.push(
          context,
          FoldAwareMaterialPageRoute(sourceContext: context,
              builder: (_) => AcupointDetailScreen(acupoint: acupoint)),
        );
      }
    } else if (href.startsWith('herb://')) {
      final name = decodeMarkdownHref(href.substring('herb://'.length));
      // 精确 + 别名归一（无模糊兜底），避免「柴胡」误跳到含柴胡的方剂。
      final herb = HerbRepository.getExactByName(name);
      if (herb != null && mounted) {
        Navigator.push(
          context,
          FoldAwareMaterialPageRoute(sourceContext: context, builder: (_) => HerbDetailScreen(herb: herb)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: FutureBuilder<String>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: StateView.loading());
          }
          if (snapshot.hasError) {
            return Center(
              child: StateView.error(
                title: '原文加载失败',
                message: snapshot.error.toString(),
                onRetry: _reload,
              ),
            );
          }
          return Column(
            children: [
              Expanded(
                child: _buildMarkdownBody(snapshot.data ?? ''),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: Text(
                    widget.footer ?? '倪师《天纪》原文 · 传统文化参考 · 非医疗建议',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

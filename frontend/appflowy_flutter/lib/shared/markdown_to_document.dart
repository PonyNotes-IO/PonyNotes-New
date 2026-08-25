import 'dart:convert';
import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/parsers/sub_page_node_parser.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

Document customMarkdownToDocument(
  String markdown, {
  double? tableWidth,
}) {
  final normalizedMarkdown = _normalizeMathDelimiters(markdown);
  return markdownToDocument(
    normalizedMarkdown,
    markdownParsers: [
      const MarkdownMathBlockParser(),
      const MarkdownCodeBlockParser(),
      MarkdownSimpleTableParser(tableWidth: tableWidth),
    ],
    inlineSyntaxes: [
      MarkdownInlineMathSyntax(),
      MarkdownInlineMarkSyntax(),
    ],
  );
}

String _normalizeMathDelimiters(String markdown) {
  // Normalize common AI LaTeX delimiters before Markdown consumes escapes.
  // 在 Markdown 解析前归一化 AI 常见 LaTeX 分隔符，避免 \[...\] 变成普通方括号文本。
  final withDisplayMath = markdown.replaceAllMapped(
    RegExp(r'\\\[(.*?)\\\]', dotAll: true),
    (match) {
      final formula = match.group(1)?.trim();
      if (formula == null || formula.isEmpty) {
        return match.group(0)!;
      }
      return '\n\n\$\$\n$formula\n\$\$\n\n';
    },
  );

  return withDisplayMath.replaceAllMapped(
    RegExp(r'\\\((.*?)\\\)'),
    (match) {
      final formula = match.group(1)?.trim();
      if (formula == null || formula.isEmpty) {
        return match.group(0)!;
      }
      return '\$$formula\$';
    },
  );
}

Future<String> customDocumentToMarkdown(
  Document document, {
  String path = '',
  AsyncValueSetter<Archive>? onArchive,
  String lineBreak = '',

  /// When true, image nodes emit raw URLs (local paths) instead of
  /// archive-relative paths.  Used by PDF export where the encoder
  /// reads images directly from disk, not from an archive.
  bool useSimpleImageParser = false,
}) async {
  final List<Future<ArchiveFile>> fileFutures = [];

  /// create root Archive and directory
  final id = document.root.id,
      archive = Archive(),
      resourceDir = ArchiveFile('$id/', 0, const <int>[])..isFile = false,
      fileName = p.basenameWithoutExtension(path),
      dirName = resourceDir.name;

  String markdown = '';
  try {
    markdown = documentToMarkdown(
      document,
      lineBreak: lineBreak,
      customParsers: [
        const MathEquationNodeParser(),
        const CalloutNodeParser(),
        const ToggleListNodeParser(),
        if (useSimpleImageParser)
          const CustomImageNodeParser()
        else
          CustomImageNodeFileParser(fileFutures, dirName),
        if (useSimpleImageParser)
          const SimpleMultiImageNodeParser()
        else
          CustomMultiImageNodeFileParser(fileFutures, dirName),
        GridNodeParser(fileFutures, dirName),
        BoardNodeParser(fileFutures, dirName),
        CalendarNodeParser(fileFutures, dirName),
        const CustomParagraphNodeParser(),
        const SubPageNodeParser(),
        const SimpleTableNodeParser(),
        const LinkPreviewNodeParser(),
        const FileBlockNodeParser(),
      ],
    );
  } catch (e) {
    Log.error('documentToMarkdown error: $e');
  }

  /// create resource directory
  if (fileFutures.isNotEmpty) archive.addFile(resourceDir);

  for (final fileFuture in fileFutures) {
    archive.addFile(await fileFuture);
  }

  /// add markdown file to Archive
  final dataBytes = utf8.encode(markdown);
  archive.addFile(ArchiveFile('$fileName-$id.md', dataBytes.length, dataBytes));

  if (archive.isNotEmpty && path.isNotEmpty) {
    if (onArchive == null) {
      final zipEncoder = ZipEncoder();
      final zip = zipEncoder.encode(archive);
      if (zip != null) {
        final zipFile = await File(path).writeAsBytes(zip);
        if (Platform.isIOS) {
          await Share.shareUri(zipFile.uri);
          await zipFile.delete();
        } else if (Platform.isAndroid) {
          await Share.shareXFiles([XFile(zipFile.path)]);
          await zipFile.delete();
        }
        Log.info('documentToMarkdownFiles to $path');
      }
    } else {
      await onArchive.call(archive);
    }
  }
  return markdown;
}

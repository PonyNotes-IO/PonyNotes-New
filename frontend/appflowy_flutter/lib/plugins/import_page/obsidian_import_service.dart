import 'dart:io';

import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/shared/markdown_to_document.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

typedef ObsidianPageCreator = Future<String> Function(
  String parentId,
  String name,
  String? markdown,
);

/// Each directory becomes a parent page; files retain their original parent.
Future<int> importObsidianVault(
  Directory vault, {
  required String parentViewId,
  void Function(int completed, int total)? onProgress,
  ObsidianPageCreator? createPage,
}) async {
  if (vault.path.trim().isEmpty) throw ArgumentError('请选择 Vault 文件夹');
  final files = <String, File>{};
  final directories = <String>{};
  Future<void> scan(Directory directory) async {
    await for (final entry in directory.list(followLinks: false)) {
      if (p.basename(entry.path).startsWith('.')) continue;
      if (entry is Directory) {
        await scan(entry);
      } else if (entry is File &&
          {'.md', '.markdown'}
              .contains(p.extension(entry.path).toLowerCase())) {
        final relativePath = p.relative(entry.path, from: vault.path);
        files[relativePath] = entry;
        var parent = p.dirname(relativePath);
        while (parent != '.') {
          directories.add(parent);
          parent = p.dirname(parent);
        }
      }
    }
  }

  await scan(vault);
  if (files.isEmpty) throw StateError('所选文件夹中没有 Markdown 笔记');
  final paths = [...directories, ...files.keys]..sort((a, b) {
      final depth = p.split(a).length.compareTo(p.split(b).length);
      return depth == 0 ? a.compareTo(b) : depth;
    });
  final create = createPage ?? _createPage;
  final ids = <String, String>{};
  var completed = 0;
  var currentPath = p.basename(p.normalize(vault.absolute.path));
  final total = paths.length + 1;
  try {
    ids['.'] = await create(parentViewId, currentPath, null);
    onProgress?.call(++completed, total);
    for (final path in paths) {
      currentPath = path;
      final file = files[path];
      // ponytail: preserve the folder tree and Markdown; add attachment and
      // wiki-link migration through the existing media/link pipeline if needed.
      final markdown = file == null ? null : await file.readAsString();
      ids[path] = await create(
        ids[p.dirname(path)]!,
        file == null ? p.basename(path) : p.basenameWithoutExtension(path),
        markdown,
      );
      onProgress?.call(++completed, total);
    }
  } catch (error) {
    throw StateError(
      '导入在「$currentPath」中断（已创建 $completed/$total 个页面）。'
      '已导入的内容仍保留在外部导入空间，原文件未改动。原因：$error',
    );
  }
  return files.length;
}

Future<String> _createPage(
  String parentId,
  String name,
  String? markdown,
) async {
  final data = markdown == null || markdown.trim().isEmpty
      ? null
      : await compute(_markdownBytes, markdown);
  final result = await ViewBackendService.createView(
    layoutType: ViewLayoutPB.Document,
    parentViewId: parentId,
    name: name,
    openAfterCreate: false,
    initialDataBytes: data,
  );
  return result.fold((view) => view.id, (error) => throw StateError(error.msg));
}

List<int> _markdownBytes(String markdown) {
  final document = customMarkdownToDocument(markdown);
  final data = DocumentDataPBFromTo.fromDocument(document);
  if (data == null) throw StateError('无法转换 Markdown 内容');
  return data.writeToBuffer();
}

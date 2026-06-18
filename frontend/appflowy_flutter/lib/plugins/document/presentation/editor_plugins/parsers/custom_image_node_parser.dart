import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/image/multi_image_block_component/multi_image_block_component.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_backend/log.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../image/custom_image_block_component/custom_image_block_component.dart';

/// Simple parser for multi-image nodes that emits raw URLs without
/// archive bundling.  Used by PDF export where the encoder reads
/// images directly from local paths set by image preprocessing.
class SimpleMultiImageNodeParser extends NodeParser {
  const SimpleMultiImageNodeParser();

  @override
  String get id => MultiImageBlockKeys.type;

  @override
  String transform(Node node, DocumentMarkdownEncoder? encoder) {
    final images = node.attributes[MultiImageBlockKeys.images] as List?;
    if (images == null || images.isEmpty) return '';

    final List<String> markdownImages = [];
    for (int i = 0; i < images.length; i++) {
      final image = images[i] as Map<String, dynamic>;
      final String url = image['url'] ?? '';
      if (url.isEmpty) continue;
      markdownImages.add('![]($url)');
    }
    return markdownImages.join('\n');
  }
}

class CustomImageNodeParser extends NodeParser {
  const CustomImageNodeParser();

  @override
  String get id => ImageBlockKeys.type;

  @override
  String transform(Node node, DocumentMarkdownEncoder? encoder) {
    assert(node.children.isEmpty);
    final url = node.attributes[CustomImageBlockKeys.url];
    assert(url != null);
    return '![]($url)\n';
  }
}

class CustomImageNodeFileParser extends NodeParser {
  const CustomImageNodeFileParser(this.files, this.dirPath);

  final List<Future<ArchiveFile>> files;
  final String dirPath;

  @override
  String get id => ImageBlockKeys.type;

  @override
  String transform(Node node, DocumentMarkdownEncoder? encoder) {
    assert(node.children.isEmpty);
    final url = node.attributes[CustomImageBlockKeys.url];

    Log.info('CustomImageNodeFileParser.transform: url=$url');
    Log.info('CustomImageNodeFileParser.transform: 节点属性=${node.attributes}');

    final hasFile = File(url).existsSync();
    Log.info('CustomImageNodeFileParser.transform: hasFile=$hasFile');

    if (hasFile) {
      final bytes = File(url).readAsBytesSync();
      files.add(
        Future.value(
          ArchiveFile(p.join(dirPath, p.basename(url)), bytes.length, bytes),
        ),
      );
      Log.info('CustomImageNodeFileParser.transform: 添加文件到归档: ${p.join(dirPath, p.basename(url))}');
      return '![](${p.join(dirPath, p.basename(url))})\n';
    }
    assert(url != null);
    Log.info('CustomImageNodeFileParser.transform: 文件不存在，返回原始URL: $url');
    return '![]($url)\n';
  }
}

class CustomMultiImageNodeFileParser extends NodeParser {
  const CustomMultiImageNodeFileParser(this.files, this.dirPath);

  final List<Future<ArchiveFile>> files;
  final String dirPath;

  @override
  String get id => MultiImageBlockKeys.type;

  @override
  String transform(Node node, DocumentMarkdownEncoder? encoder) {
    assert(node.children.isEmpty);
    final images = node.attributes[MultiImageBlockKeys.images] as List;

    Log.info('CustomMultiImageNodeFileParser.transform: 图片数量=${images.length}');

    final List<String> markdownImages = [];
    for (int i = 0; i < images.length; i++) {
      final image = images[i] as Map<String, dynamic>;
      final String url = image['url'] ?? '';

      Log.info('CustomMultiImageNodeFileParser.transform: 图片 $i, url=$url');

      if (url.isEmpty) continue;
      final hasFile = File(url).existsSync();
      Log.info('CustomMultiImageNodeFileParser.transform: 图片 $i, hasFile=$hasFile');

      if (hasFile) {
        final bytes = File(url).readAsBytesSync();
        final filePath = p.join(dirPath, p.basename(url));
        files.add(
          Future.value(ArchiveFile(filePath, bytes.length, bytes)),
        );
        markdownImages.add('![]($filePath)');
        Log.info('CustomMultiImageNodeFileParser.transform: 图片 $i, 添加文件到归档: $filePath');
      } else {
        markdownImages.add('![]($url)');
        Log.info('CustomMultiImageNodeFileParser.transform: 图片 $i, 文件不存在，返回原始URL: $url');
      }
    }
    return markdownImages.join('\n');
  }
}

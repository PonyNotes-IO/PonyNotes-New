import 'package:appflowy/plugins/document/presentation/editor_plugins/link_embed/link_embed_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/mention/mention_block.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor_plugins/appflowy_editor_plugins.dart';

Node _linkPreviewNode({required String url, String? originalText}) => Node(
      type: LinkPreviewBlockKeys.type,
      attributes: {
        LinkPreviewBlockKeys.url: url,
        if (originalText != null) LinkEmbedKeys.originalText: originalText,
      },
    );

/// 检测URL是否为应用内笔记链接
/// 支持格式: ponynotes://open?viewId=xxx, /share?viewId=xxx&type=share
bool _isInAppPageLink(String url) {
  try {
    final uri = Uri.parse(url);
    final path = uri.path;
    final queryParams = uri.queryParameters;
    final linkType = queryParams['type'];
    var viewId = queryParams['viewId'];
    if (viewId != null && (viewId.contains('&') || viewId.contains('?'))) {
      final match = RegExp(r'[?&]viewId=([^&]+)').firstMatch(url);
      if (match != null) viewId = match.group(1);
    }
    // ponynotes://open?viewId=xxx 格式
    if (url.startsWith('ponynotes://') && viewId != null) {
      return true;
    }
    // /share?viewId=xxx&type=share 格式
    final isSharePath = path == '/share' || path == 'share';
    final isShareOrPublish = linkType == 'share' || linkType == 'publish';
    if (isSharePath && isShareOrPublish && viewId != null) {
      return true;
    }
  } catch (_) {}
  return false;
}

/// 从分享链接提取viewId
String? _extractViewIdFromShareUrl(String url) {
  try {
    final match = RegExp(r'[?&]viewId=([^&]+)').firstMatch(url);
    return match?.group(1);
  } catch (_) {}
  return null;
}

Future<void> convertUrlPreviewNodeToLink(
  EditorState editorState,
  Node node,
) async {
  if (node.type != LinkPreviewBlockKeys.type) {
    return;
  }

  final url = node.attributes[LinkPreviewBlockKeys.url];
  final originalText =
      node.attributes[LinkEmbedKeys.originalText] as String?;

  // 检测是否为应用内笔记链接
  if (_isInAppPageLink(url)) {
    // 应用内笔记：使用 mention 格式显示，带有 @ 符号
    final textToShow = originalText ?? 'Untitled';
    final delta = Delta()
      ..insert(
        MentionBlockKeys.mentionChar,
        attributes: {
          MentionBlockKeys.mention: {
            MentionBlockKeys.type: MentionType.page.name,
            MentionBlockKeys.url: url,
            MentionBlockKeys.originalText: originalText,
          },
        },
      );
    final transaction = editorState.transaction;
    transaction
      ..insertNode(node.path, paragraphNode(delta: delta))
      ..deleteNode(node);
    transaction.afterSelection = Selection.collapsed(
      Position(
        path: node.path,
        offset: 1, // mentionChar 后面的位置
      ),
    );
    return editorState.apply(transaction);
  }

  // 外部链接：使用普通超链接显示
  final delta = Delta()
    ..insert(
      originalText ?? url,
      attributes: {
        AppFlowyRichTextKeys.href: url,
      },
    );
  final transaction = editorState.transaction;
  transaction
    ..insertNode(node.path, paragraphNode(delta: delta))
    ..deleteNode(node);
  transaction.afterSelection = Selection.collapsed(
    Position(
      path: node.path,
      offset: (originalText ?? url).length,
    ),
  );
  return editorState.apply(transaction);
}

Future<void> convertUrlPreviewNodeToMention(
  EditorState editorState,
  Node node,
) async {
  if (node.type != LinkPreviewBlockKeys.type) {
    return;
  }

  final url = node.attributes[LinkPreviewBlockKeys.url];
  final delta = Delta()
    ..insert(
      MentionBlockKeys.mentionChar,
      attributes: {
        MentionBlockKeys.mention: {
          MentionBlockKeys.type: MentionType.externalLink.name,
          MentionBlockKeys.url: url,
        },
      },
    );
  final transaction = editorState.transaction;
  transaction
    ..insertNode(node.path, paragraphNode(delta: delta))
    ..deleteNode(node);
  transaction.afterSelection = Selection.collapsed(
    Position(
      path: node.path,
      offset: url.length,
    ),
  );
  return editorState.apply(transaction);
}

Future<void> removeUrlPreviewLink(
  EditorState editorState,
  Node node,
) async {
  if (node.type != LinkPreviewBlockKeys.type) {
    return;
  }

  final url = node.attributes[LinkPreviewBlockKeys.url] ?? '';
  // 尝试获取原始文字
  final originalText = node.attributes[LinkEmbedKeys.originalText] as String?;
  final textToRestore = originalText ?? url;
  final delta = Delta()..insert(textToRestore);
  final transaction = editorState.transaction;
  transaction
    ..insertNode(node.path, paragraphNode(delta: delta))
    ..deleteNode(node);
  transaction.afterSelection = Selection.collapsed(
    Position(
      path: node.path,
      offset: url.length,
    ),
  );
  return editorState.apply(transaction);
}

Future<void> convertUrlToLinkPreview(
  EditorState editorState,
  Selection selection,
  String url, {
  String? previewType,
}) async {
  final node = editorState.getNodeAtPath(selection.end.path);
  if (node == null) {
    return;
  }
  final delta = node.delta;
  if (delta == null) return;
  final List<TextInsert> beforeOperations = [], afterOperations = [];
  String selectedText = '';
  int index = 0;
  for (final insert in delta.whereType<TextInsert>()) {
    if (index < selection.startIndex) {
      beforeOperations.add(insert);
    } else if (index >= selection.endIndex) {
      afterOperations.add(insert);
    } else {
      // 保存选中的文本（原始文字）
      selectedText = insert.text;
    }
    index += insert.length;
  }
  final transaction = editorState.transaction;
  transaction
    ..deleteNode(node)
    ..insertNodes(node.path.next, [
      if (beforeOperations.isNotEmpty)
        paragraphNode(delta: Delta(operations: beforeOperations)),
      if (previewType == LinkEmbedKeys.embed)
        linkEmbedNode(url: url, originalText: selectedText)
      else
        _linkPreviewNode(url: url, originalText: selectedText),
      if (afterOperations.isNotEmpty)
        paragraphNode(delta: Delta(operations: afterOperations)),
    ]);
  await editorState.apply(transaction);
}

Future<void> convertUrlToMention(
  EditorState editorState,
  Selection selection,
) async {
  final node = editorState.getNodeAtPath(selection.end.path);
  if (node == null) {
    return;
  }
  final delta = node.delta;
  if (delta == null) return;
  String url = '';
  String originalText = '';
  int index = 0;
  for (final insert in delta.whereType<TextInsert>()) {
    if (index >= selection.startIndex && index < selection.endIndex) {
      final href = insert.attributes?.href ?? '';
      if (href.isNotEmpty) {
        url = href;
        originalText = insert.text;
        break;
      }
    }
    index += insert.length;
  }
  final transaction = editorState.transaction;
  transaction.replaceText(
    node,
    selection.startIndex,
    selection.length,
    MentionBlockKeys.mentionChar,
    attributes: {
      MentionBlockKeys.mention: {
        MentionBlockKeys.type: MentionType.externalLink.name,
        MentionBlockKeys.url: url,
        MentionBlockKeys.originalText: originalText,
      },
    },
  );
  await editorState.apply(transaction);
}

Future<void> convertLinkBlockToOtherLinkBlock(
  EditorState editorState,
  Node node,
  String toType, {
  String? url,
}) async {
  final nodeType = node.type;
  if (nodeType != LinkPreviewBlockKeys.type ||
      (nodeType == toType && url == null)) {
    return;
  }
  final insertedNode = <Node>[];

  final afterUrl = url ?? node.attributes[LinkPreviewBlockKeys.url] ?? '';
  final previewType = node.attributes[LinkEmbedKeys.previewType];
  Node afterNode = node.copyWith(
    type: toType,
    attributes: {
      LinkPreviewBlockKeys.url: afterUrl,
      LinkEmbedKeys.previewType: previewType,
      blockComponentBackgroundColor:
          node.attributes[blockComponentBackgroundColor],
      blockComponentTextDirection: node.attributes[blockComponentTextDirection],
      blockComponentDelta: (node.delta ?? Delta()).toJson(),
    },
  );
  afterNode = afterNode.copyWith(children: []);
  insertedNode.add(afterNode);
  insertedNode.addAll(node.children.map((e) => e.deepCopy()));
  final transaction = editorState.transaction;
  transaction.insertNodes(
    node.path,
    insertedNode,
  );
  transaction.deleteNodes([node]);
  await editorState.apply(transaction);
}

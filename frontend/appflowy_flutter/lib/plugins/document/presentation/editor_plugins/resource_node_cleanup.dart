import 'dart:io';

import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/custom_image_block_component/custom_image_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/multi_image_block_component/multi_image_block_component.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

enum _ResourceStorageKind {
  cloud,
  local,
}

class _ResourceCandidate {
  const _ResourceCandidate({
    required this.url,
    required this.kind,
  });

  final String url;
  final _ResourceStorageKind kind;
}

Future<void> cleanupResourceNodesBeforeDelete(
  EditorState editorState,
  List<Node> deletingNodes,
) async {
  if (deletingNodes.isEmpty) {
    return;
  }

  final deletingPaths = deletingNodes.map((e) => e.path).toList();
  final candidates = <_ResourceCandidate>[];
  final seen = <String>{};

  for (final node in deletingNodes) {
    _walkNode(node, (current) {
      final extracted = _extractDeletableCandidatesFromNode(current);
      for (final candidate in extracted) {
        final key = '${candidate.kind.name}:${candidate.url}';
        if (seen.add(key)) {
          candidates.add(candidate);
        }
      }
    });
  }

  for (final candidate in candidates) {
    if (_hasReferenceOutsideDeletingNodes(
      editorState.document.root,
      candidate.url,
      deletingPaths,
    )) {
      continue;
    }
    await _deleteResourceCandidate(candidate);
  }
}

/// Cleanup all deletable resources inside a document before deleting the page itself.
/// This is used by page-level delete flows where we don't have an editor instance.
Future<void> cleanupDocumentResourcesBeforeDelete({
  required String documentId,
  String? workspaceId,
}) async {
  final result = await DocumentService().getDocument(
    documentId: documentId,
    workspaceId: workspaceId,
  );

  final documentData = result.toNullable();
  if (documentData == null) {
    return;
  }
  final document = documentData.toDocument();
  if (document == null) {
    return;
  }

  final candidates = <_ResourceCandidate>[];
  final seen = <String>{};
  _walkNode(document.root, (current) {
    for (final candidate in _extractDeletableCandidatesFromNode(current)) {
      final key = '${candidate.kind.name}:${candidate.url}';
      if (seen.add(key)) {
        candidates.add(candidate);
      }
    }
  });

  for (final candidate in candidates) {
    await _deleteResourceCandidate(candidate);
  }
}

Future<void> _deleteResourceCandidate(_ResourceCandidate candidate) async {
  if (candidate.kind == _ResourceStorageKind.cloud) {
    final result = await DocumentService().deleteFile(url: candidate.url);
    result.fold(
      (_) async {},
      (err) async => Log.error('delete cloud resource failed: ${err.msg}'),
    );
    return;
  }

  try {
    final file = File(candidate.url);
    if (await file.exists()) {
      await file.delete();
    }
  } catch (e) {
    Log.error('delete local resource failed: ${candidate.url}', e);
  }
}

bool _hasReferenceOutsideDeletingNodes(
  Node root,
  String url,
  List<Path> deletingPaths,
) {
  bool found = false;

  void visit(Node node) {
    if (found) {
      return;
    }

    if (_isPathUnderDeletingPaths(node.path, deletingPaths)) {
      return;
    }

    final urls = _extractAllResourceUrlsFromNode(node);
    if (urls.contains(url)) {
      found = true;
      return;
    }

    for (final child in node.children) {
      visit(child);
    }
  }

  visit(root);
  return found;
}

bool _isPathUnderDeletingPaths(Path path, List<Path> deletingPaths) {
  for (final deletingPath in deletingPaths) {
    if (_isSameOrDescendant(path, deletingPath)) {
      return true;
    }
  }
  return false;
}

bool _isSameOrDescendant(Path path, Path parentPath) {
  if (parentPath.length > path.length) {
    return false;
  }
  for (var i = 0; i < parentPath.length; i++) {
    if (path[i] != parentPath[i]) {
      return false;
    }
  }
  return true;
}

void _walkNode(Node node, void Function(Node) visitor) {
  visitor(node);
  for (final child in node.children) {
    _walkNode(child, visitor);
  }
}

List<String> _extractAllResourceUrlsFromNode(Node node) {
  if (node.type == FileBlockKeys.type) {
    final url = node.attributes[FileBlockKeys.url] as String?;
    return url == null || url.isEmpty ? const [] : [url];
  }

  if (node.type == CustomImageBlockKeys.type) {
    final url = node.attributes[CustomImageBlockKeys.url] as String?;
    return url == null || url.isEmpty ? const [] : [url];
  }

  if (node.type == MultiImageBlockKeys.type) {
    final rawImages = node.attributes[MultiImageBlockKeys.images];
    if (rawImages is! List<dynamic>) {
      return const [];
    }
    try {
      final images = MultiImageData.fromJson(rawImages).images;
      return images.map((e) => e.url).where((e) => e.isNotEmpty).toList();
    } catch (e) {
      Log.error('parse multi image urls failed', e);
      return const [];
    }
  }

  return const [];
}

List<_ResourceCandidate> _extractDeletableCandidatesFromNode(Node node) {
  if (node.type == FileBlockKeys.type) {
    final url = node.attributes[FileBlockKeys.url] as String?;
    if (url == null || url.isEmpty) {
      return const [];
    }
    final urlType = node.attributes[FileBlockKeys.urlType] as int? ?? 0;
    if (urlType == FileUrlType.cloud.toIntValue()) {
      return [_ResourceCandidate(url: url, kind: _ResourceStorageKind.cloud)];
    }
    if (urlType == FileUrlType.local.toIntValue()) {
      return [_ResourceCandidate(url: url, kind: _ResourceStorageKind.local)];
    }
    return const [];
  }

  if (node.type == CustomImageBlockKeys.type) {
    final url = node.attributes[CustomImageBlockKeys.url] as String?;
    if (url == null || url.isEmpty) {
      return const [];
    }
    final imageType = node.attributes[CustomImageBlockKeys.imageType] as int? ?? 0;
    if (imageType == CustomImageType.internal.toIntValue()) {
      return [_ResourceCandidate(url: url, kind: _ResourceStorageKind.cloud)];
    }
    if (imageType == CustomImageType.local.toIntValue()) {
      return [_ResourceCandidate(url: url, kind: _ResourceStorageKind.local)];
    }
    return const [];
  }

  if (node.type == MultiImageBlockKeys.type) {
    final rawImages = node.attributes[MultiImageBlockKeys.images];
    if (rawImages is! List<dynamic>) {
      return const [];
    }
    try {
      final images = MultiImageData.fromJson(rawImages).images;
      final candidates = <_ResourceCandidate>[];
      for (final image in images) {
        if (image.url.isEmpty) {
          continue;
        }
        if (image.type == CustomImageType.internal) {
          candidates.add(
            _ResourceCandidate(url: image.url, kind: _ResourceStorageKind.cloud),
          );
        } else if (image.type == CustomImageType.local) {
          candidates.add(
            _ResourceCandidate(url: image.url, kind: _ResourceStorageKind.local),
          );
        }
      }
      return candidates;
    } catch (e) {
      Log.error('parse multi image candidates failed', e);
      return const [];
    }
  }

  return const [];
}

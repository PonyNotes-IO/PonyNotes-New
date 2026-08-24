import 'dart:convert';

import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';

bool isHandwritingNote(ViewPB view) {
  try {
    if (view.extra.isEmpty) {
      return false;
    }
    final extra = jsonDecode(view.extra);
    return extra is Map && extra['view_type'] == 'handwriting_saber';
  } catch (_) {
    return false;
  }
}

/// Whether SpaceHub should render [layout] with the regular document page.
///
/// Handwriting notes intentionally use the Document layout for folder
/// compatibility, but their content is owned by HandwritingSaberPlugin.
bool spaceHubUsesDocumentPage(
  ViewLayoutPB layout, {
  required bool isHandwriting,
}) {
  if (isHandwriting) {
    return false;
  }

  return switch (layout) {
    ViewLayoutPB.Document ||
    ViewLayoutPB.Folder ||
    ViewLayoutPB.Notebook =>
      true,
    _ => false,
  };
}

bool spaceHubShouldUpdateSelection(
  String? selectedViewId,
  String tappedViewId,
) {
  return selectedViewId != tappedViewId;
}

int? spaceHubDocumentListChildIndex(
  Key key,
  Iterable<String> viewIds,
) {
  if (key is! ValueKey<String>) {
    return null;
  }
  final id = key.value;
  const prefix = 'space_hub_';
  if (!id.startsWith(prefix)) {
    return null;
  }
  final viewId = id.substring(prefix.length);
  final index = viewIds.toList().indexOf(viewId);
  if (index < 0) {
    return null;
  }
  return index;
}

class SpaceHubDocumentListLoader<T> {
  SpaceHubDocumentListLoader({
    required String spaceId,
    required Future<T> Function(String spaceId) load,
  })  : _spaceId = spaceId,
        _load = load,
        _future = load(spaceId);

  String _spaceId;
  final Future<T> Function(String spaceId) _load;
  Future<T> _future;

  Future<T> get future => _future;

  void updateSpace(String spaceId) {
    if (_spaceId == spaceId) {
      return;
    }
    _spaceId = spaceId;
    reload();
  }

  void reload() {
    _future = _load(_spaceId);
  }
}

bool spaceHubChildViewIdsChanged(
  Iterable<String> previousIds,
  Iterable<String> currentIds,
) {
  final previous = previousIds.toList();
  final current = currentIds.toList();
  if (previous.length != current.length) {
    return true;
  }
  for (var i = 0; i < previous.length; i++) {
    if (previous[i] != current[i]) {
      return true;
    }
  }
  return false;
}

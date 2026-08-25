import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:fixnum/fixnum.dart' as fixnum;

class SharedCollabView {
  const SharedCollabView({
    required this.view,
    required this.ownerWorkspaceId,
  });

  final ViewPB view;
  final String ownerWorkspaceId;

  SharedCollabView copyWith({ViewPB? view}) {
    final nextView = view ?? this.view;
    if (ownerWorkspaceId.isNotEmpty && !nextView.hasWorkspaceId()) {
      nextView.workspaceId = ownerWorkspaceId;
    }
    return SharedCollabView(
      view: nextView,
      ownerWorkspaceId: ownerWorkspaceId,
    );
  }
}

SharedCollabView? sharedCollabViewFromJson(Map<String, dynamic> entry) {
  final id = (entry['oid'] ??
          entry['object_id'] ??
          entry['objectId'] ??
          entry['view_id'] ??
          '')
      .toString();
  if (id.isEmpty) {
    return null;
  }

  final name = (entry['name'] ?? '').toString();
  final ownerWorkspaceId =
      (entry['owner_workspace_id'] ?? entry['ownerWorkspaceId'] ?? '')
          .toString()
          .trim();
  final layout = _viewLayoutFromJson(
    entry['view_layout'] ?? entry['viewLayout'],
  );
  final createdSeconds = _parseTimestampSeconds(
    entry['created_at'] ?? entry['createdAt'] ?? entry['create_time'],
  );

  final view = ViewPB()
    ..id = id
    ..name = name.isNotEmpty ? name : '加载中...'
    ..layout = layout
    ..createTime = fixnum.Int64(createdSeconds);
  // Received shares belong to the owner's workspace. Preserve that identity
  // so DocumentBloc opens the collab against the correct workspace instead of
  // silently falling back to the currently active one.
  if (ownerWorkspaceId.isNotEmpty) {
    view.workspaceId = ownerWorkspaceId;
  }
  return SharedCollabView(
    view: view,
    ownerWorkspaceId: ownerWorkspaceId,
  );
}

ViewLayoutPB _viewLayoutFromJson(dynamic raw) {
  final value = raw is int ? raw : int.tryParse(raw?.toString() ?? '') ?? 0;
  return switch (value) {
    1 => ViewLayoutPB.Grid,
    2 => ViewLayoutPB.Board,
    3 => ViewLayoutPB.Calendar,
    _ => ViewLayoutPB.Document,
  };
}

int _parseTimestampSeconds(dynamic raw) {
  if (raw is int) {
    return raw > 1000000000000 ? raw ~/ 1000 : raw;
  }
  if (raw is double) {
    final value = raw.toInt();
    return value > 1000000000000 ? value ~/ 1000 : value;
  }
  if (raw is String && raw.isNotEmpty) {
    final parsedDate = DateTime.tryParse(raw);
    if (parsedDate != null) {
      return parsedDate.millisecondsSinceEpoch ~/ 1000;
    }
    final parsedNumber = int.tryParse(raw);
    if (parsedNumber != null) {
      return parsedNumber > 1000000000000 ? parsedNumber ~/ 1000 : parsedNumber;
    }
  }
  return DateTime.now().millisecondsSinceEpoch ~/ 1000;
}

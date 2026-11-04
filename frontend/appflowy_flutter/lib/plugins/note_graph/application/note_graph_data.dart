import 'package:appflowy/plugins/document/application/note_link_data.dart';
import 'dart:collection';

import 'package:appflowy/workspace/application/view/view_ext.dart';

import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';

/// Only explicit document references belong here; no hierarchy or inferred edges.
class NoteGraphEdge {
  NoteGraphEdge(this.source, this.target, Iterable<NoteLinkPB> references)
      : references = List.unmodifiable(references);
  final String source;
  final String target;
  final List<NoteLinkPB> references;
  int get occurrences => references.fold(
        0,
        (count, link) => count + (link.occurrence > 0 ? link.occurrence : 1),
      );
  int get blockReferences =>
      references.where((link) => link.dstBlockId.isNotEmpty).length;
  (String, String) get key => (source, target);
}

enum NoteGraphDirection { both, incoming, outgoing }

class NoteGraphData {
  NoteGraphData({
    required Map<String, ViewPB> notes,
    required Iterable<NoteGraphEdge> edges,
    this.omittedNotes = 0,
    Map<String, ViewPB> spaces = const {},
    Map<String, String> noteSpaceIds = const {},
  })  : spaces = Map.unmodifiable(spaces),
        noteSpaceIds = Map.unmodifiable(noteSpaceIds),
        notes = Map.unmodifiable(notes),
        edges = List.unmodifiable(edges);
  factory NoteGraphData.empty() => NoteGraphData(notes: {}, edges: []);

  factory NoteGraphData.fromIndex(
    Iterable<ViewPB> views,
    DocumentLinksPB snapshot, {
    String? workspaceId,
  }) {
    final byId = {
      for (final view in views)
        if (workspaceId == null ||
            view.workspaceId.isEmpty ||
            view.workspaceId == workspaceId)
          view.id: view,
    };
    final spaces = {
      for (final view in byId.values)
        if (view.isSpace) view.id: view,
    };
    final noteSpaceIds = <String, String>{};
    final notes = {
      for (final view in byId.values)
        if (view.layout == ViewLayoutPB.Document &&
            !view.isSpace &&
            !isWorkspaceRoot(view, workspaceId))
          view.id: view,
    };
    for (final note in notes.values) {
      final space = noteSpaceId(note.id, byId);
      if (space != null) noteSpaceIds[note.id] = space;
    }
    final groups = <(String, String), List<NoteLinkPB>>{};
    final seen = <(String, String, String, String, String)>{};
    for (final raw in snapshot.outgoing) {
      if (!notes.containsKey(raw.srcPageId) ||
          !notes.containsKey(raw.dstPageId) ||
          raw.srcPageId == raw.dstPageId) {
        continue;
      }
      if (!const {'reference', 'block_ref', 'embed'}.contains(raw.kind)) {
        continue;
      }
      if (raw.kind == 'embed' &&
          notes[raw.dstPageId]!.parentViewId == raw.srcPageId) {
        continue;
      }
      final id = (
        raw.srcPageId,
        raw.srcBlockId,
        raw.dstPageId,
        raw.dstBlockId,
        raw.kind
      );
      if (!seen.add(id)) continue;
      (groups[(raw.srcPageId, raw.dstPageId)] ??= [])
          .add(NoteLinkPB.fromBuffer(raw.writeToBuffer()));
    }
    final keys = groups.keys.toList()
      ..sort((a, b) {
        final order = a.$1.compareTo(b.$1);
        return order == 0 ? a.$2.compareTo(b.$2) : order;
      });
    return NoteGraphData(
      notes: notes,
      spaces: spaces,
      noteSpaceIds: noteSpaceIds,
      edges: [
        for (final key in keys) NoteGraphEdge(key.$1, key.$2, groups[key]!),
      ],
    );
  }

  final Map<String, ViewPB> notes;
  final Map<String, ViewPB> spaces;
  final Map<String, String> noteSpaceIds;
  final List<NoteGraphEdge> edges;
  final int omittedNotes;

  NoteGraphData inSpace(String? spaceId, {bool includeExternal = false}) {
    if (spaceId == null) return this;
    final internal = {
      for (final id in notes.keys)
        if (noteSpaceIds[id] == spaceId) id,
    };
    final connections = edges
        .where(
          (edge) => includeExternal
              ? internal.contains(edge.source) || internal.contains(edge.target)
              : internal.contains(edge.source) &&
                  internal.contains(edge.target),
        )
        .toList();
    final visible = {
      ...internal,
      if (includeExternal)
        for (final edge in connections) ...[edge.source, edge.target],
    };
    return NoteGraphData(
      notes: {for (final id in visible) id: notes[id]!},
      edges: connections,
      spaces: spaces,
      noteSpaceIds: noteSpaceIds,
    );
  }

  /// 工作区根文档（标题通常就是 "Workspace"）不是用户写的笔记，只是工作区外壳，
  /// 但它是个 `Document` 布局的 view，以前会混进图谱当一个真实节点。
  ///
  /// 它的 view id 恒等于 workspace id，据此排除——不用标题匹配，避免误杀用户
  /// 自己命名为 "Workspace" 的普通笔记。[workspaceId] 缺省时退回 view 自带的
  /// workspaceId 字段。
  static bool isWorkspaceRoot(ViewPB view, String? workspaceId) {
    final root = (workspaceId != null && workspaceId.isNotEmpty)
        ? workspaceId
        : view.workspaceId;
    return root.isNotEmpty && view.id == root;
  }

  Set<String> incomingTo(String id) => {
        for (final edge in edges)
          if (edge.target == id) edge.source,
      };
  Set<String> outgoingFrom(String id) => {
        for (final edge in edges)
          if (edge.source == id) edge.target,
      };
  int degree(String id) => {...incomingTo(id), ...outgoingFrom(id)}.length;

  NoteGraphData filtered({
    String query = '',
    String? focus,
    int depth = 1,
    NoteGraphDirection direction = NoteGraphDirection.both,
    bool showIsolated = true,
    bool blocksOnly = false,
    int limit = 400,
  }) {
    final eligible = blocksOnly
        ? edges
            .where((edge) => edge.blockReferences > 0)
            .map(
              (edge) => NoteGraphEdge(
                edge.source,
                edge.target,
                edge.references.where((link) => link.dstBlockId.isNotEmpty),
              ),
            )
            .toList()
        : edges;
    final adjacent = <String, Set<String>>{};
    for (final edge in eligible) {
      if (direction != NoteGraphDirection.incoming) {
        (adjacent[edge.source] ??= {}).add(edge.target);
      }
      if (direction != NoteGraphDirection.outgoing) {
        (adjacent[edge.target] ??= {}).add(edge.source);
      }
    }
    final order = <String>[];
    final distances = <String, int>{};
    if (focus != null) {
      if (!notes.containsKey(focus)) return NoteGraphData.empty();
      final queue = Queue<(String, int)>()..add((focus, 0));
      final visited = {focus};
      while (queue.isNotEmpty) {
        final (id, distance) = queue.removeFirst();
        order.add(id);
        distances[id] = distance;
        if (distance >= depth.clamp(1, 3)) continue;
        final neighbors = (adjacent[id] ?? {}).toList()..sort();
        for (final neighbor in neighbors) {
          if (visited.add(neighbor)) queue.add((neighbor, distance + 1));
        }
      }
    } else {
      final connected = {
        for (final edge in eligible) ...[edge.source, edge.target],
      };
      order.addAll(
        notes.keys.where((id) => showIsolated || connected.contains(id)),
      );
      final degrees = <String, int>{};
      for (final edge in eligible) {
        degrees.update(edge.source, (value) => value + 1, ifAbsent: () => 1);
        degrees.update(edge.target, (value) => value + 1, ifAbsent: () => 1);
      }
      order.sort((a, b) {
        final degreeOrder = (degrees[b] ?? 0).compareTo(degrees[a] ?? 0);
        return degreeOrder == 0 ? a.compareTo(b) : degreeOrder;
      });
    }
    final search = query.trim().toLowerCase();
    final matching = order
        .where(
          (id) =>
              search.isEmpty ||
              id == focus ||
              notes[id]!.name.toLowerCase().contains(search),
        )
        .toList();
    final visible = matching.take(limit.clamp(1, 1000)).toSet();
    return NoteGraphData(
      notes: {for (final id in visible) id: notes[id]!},
      edges: eligible.where(
        (edge) {
          if (!visible.contains(edge.source) ||
              !visible.contains(edge.target)) {
            return false;
          }
          if (focus == null || direction == NoteGraphDirection.both) {
            return true;
          }
          final from = direction == NoteGraphDirection.incoming
              ? edge.target
              : edge.source;
          return (distances[from] ?? 999) < depth.clamp(1, 3);
        },
      ),
      omittedNotes: matching.length - visible.length,
      spaces: spaces,
      noteSpaceIds: noteSpaceIds,
    );
  }
}

import 'dart:convert';

import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';

enum GraphEdgeKind { reference, hierarchy }

class GraphNode {
  const GraphNode({
    required this.id,
    required this.label,
    required this.view,
  });

  final String id;
  final String label;
  final ViewPB view;
}

class GraphEdge {
  const GraphEdge(this.source, this.target, this.kind);

  final String source;
  final String target;
  final GraphEdgeKind kind;

  @override
  bool operator ==(Object other) =>
      other is GraphEdge &&
      source == other.source &&
      target == other.target &&
      kind == other.kind;

  @override
  int get hashCode => Object.hash(source, target, kind);
}

class KnowledgeGraphData {
  const KnowledgeGraphData({this.nodes = const [], this.edges = const []});

  final List<GraphNode> nodes;
  final List<GraphEdge> edges;

  KnowledgeGraphData filtered({
    String query = '',
    bool hierarchy = true,
    bool orphans = true,
  }) {
    final search = query.trim().toLowerCase();
    var visible = nodes
        .where(
          (node) => search.isEmpty || node.label.toLowerCase().contains(search),
        )
        .toList();
    final ids = visible.map((node) => node.id).toSet();
    final links = edges
        .where(
          (edge) =>
              (hierarchy || edge.kind != GraphEdgeKind.hierarchy) &&
              ids.contains(edge.source) &&
              ids.contains(edge.target),
        )
        .toList();
    if (!orphans) {
      final connected =
          links.expand((edge) => [edge.source, edge.target]).toSet();
      visible = visible.where((node) => connected.contains(node.id)).toList();
    }
    return KnowledgeGraphData(nodes: visible, edges: links);
  }
}

/// Only resolves references to accessible workspace nodes. Never creates nodes
/// from arbitrary URLs or IDs found in document text.
class KnowledgeGraphBuilder {
  KnowledgeGraphBuilder(Iterable<ViewPB> views, {required String workspaceId}) {
    for (final view in views) {
      final extra = _json(view.extra);
      if (view.id.isEmpty ||
          view.id == workspaceId ||
          view.layout != ViewLayoutPB.Document ||
          extra is Map &&
              (extra['is_space'] == true ||
                  extra['view_type'] == 'handwriting_saber')) {
        continue;
      }
      _nodes[view.id] = GraphNode(
        id: view.id,
        label: view.name,
        view: view,
      );
    }
    for (final node in _nodes.values) {
      if (_nodes.containsKey(node.view.parentViewId)) {
        _edges.add(
          GraphEdge(
            node.view.parentViewId,
            node.id,
            GraphEdgeKind.hierarchy,
          ),
        );
      }
    }
  }

  final _nodes = <String, GraphNode>{};
  final _edges = <GraphEdge>{};

  KnowledgeGraphData build() {
    // The graph is undirected: reciprocal references and a parent-child link
    // between the same pages should appear as one connection.
    final connections = <(String, String), GraphEdge>{};
    for (final edge in _edges) {
      final pair = edge.source.compareTo(edge.target) < 0
          ? (edge.source, edge.target)
          : (edge.target, edge.source);
      final existing = connections[pair];
      if (existing == null || edge.kind == GraphEdgeKind.reference) {
        connections[pair] = edge;
      }
    }
    return KnowledgeGraphData(
      nodes: _nodes.values.toList()..sort((a, b) => a.id.compareTo(b.id)),
      edges: connections.values.toList(),
    );
  }

  void addDocument(ViewPB view, DocumentDataPB document) {
    if (!_nodes.containsKey(view.id)) return;
    for (final block in document.blocks.values) {
      final attributes = _json(block.data);
      _references(view.id, attributes);
    }
    // Rich text is stored separately from block attributes in AppFlowy.
    for (final text in document.meta.textMap.values) {
      _references(view.id, _json(text));
    }
  }

  void _references(String source, dynamic value) {
    if (value is Map) {
      for (final entry in value.entries) {
        final target = entry.value;
        if ((entry.key == 'page_id' || entry.key == 'view_id') &&
            target is String) {
          _addReference(source, target);
        } else if ((entry.key == 'href' || entry.key == 'url') &&
            target is String) {
          final uri = Uri.tryParse(target);
          if (uri != null &&
              (const {'ponynotes', 'appflowy-flutter', 'appflowy'}
                      .contains(uri.scheme) ||
                  uri.path == '/share')) {
            final id =
                uri.queryParameters['viewId'] ?? uri.queryParameters['page_id'];
            if (id != null) _addReference(source, id);
          }
        }
        _references(source, target);
      }
    } else if (value is List) {
      for (final item in value) {
        _references(source, item);
      }
    }
  }

  void _addReference(String source, String target) {
    if (source != target && _nodes.containsKey(target)) {
      _edges.add(GraphEdge(source, target, GraphEdgeKind.reference));
    }
  }

  static dynamic _json(String value) {
    try {
      return jsonDecode(value);
    } on FormatException {
      return null;
    }
  }
}

import 'dart:convert';

import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';

enum GraphEdgeKind { reference, hierarchy, relation, mention }

class GraphSource {
  const GraphSource({
    required this.viewId,
    required this.blockId,
    required this.text,
    this.blockOffsets = const [],
  });

  final String viewId;
  final String blockId;
  final String text;
  final List<(int, String)> blockOffsets;

  String blockFor(String quote) {
    final offset = text.toLowerCase().indexOf(quote.toLowerCase());
    return blockOffsets
        .lastWhere(
          (entry) => entry.$1 <= offset,
          orElse: () => (0, blockId),
        )
        .$2;
  }
}

class GraphNode {
  const GraphNode({
    required this.id,
    required this.label,
    required this.view,
    this.entityType,
    this.description = '',
    this.sources = const [],
  });

  final String id;
  final String label;
  final ViewPB view;
  final String? entityType;
  final String description;
  final List<GraphSource> sources;
}

class GraphEdge {
  const GraphEdge(
    this.source,
    this.target,
    this.kind, {
    this.label = '',
    this.sources = const [],
  });

  final String source;
  final String target;
  final GraphEdgeKind kind;
  final String label;
  final List<GraphSource> sources;

  @override
  bool operator ==(Object other) =>
      other is GraphEdge &&
      source == other.source &&
      target == other.target &&
      kind == other.kind &&
      label == other.label;

  @override
  int get hashCode => Object.hash(source, target, kind, label);
}

class KnowledgeGraphData {
  const KnowledgeGraphData({this.nodes = const [], this.edges = const []});

  final List<GraphNode> nodes;
  final List<GraphEdge> edges;

  KnowledgeGraphData filtered({
    String query = '',
    bool hierarchy = true,
    bool orphans = true,
    bool entitiesOnly = false,
    bool documentsOnly = false,
    String entityType = '',
    String? focus,
  }) {
    final search = query.trim().toLowerCase();
    var visible = nodes
        .where(
          (node) =>
              (!entitiesOnly || node.entityType != null) &&
              (!documentsOnly || node.entityType == null) &&
              (entityType.isEmpty || node.entityType == entityType),
        )
        .toList();
    var ids = visible.map((node) => node.id).toSet();
    var links = edges
        .where(
          (edge) =>
              (hierarchy || edge.kind != GraphEdgeKind.hierarchy) &&
              ids.contains(edge.source) &&
              ids.contains(edge.target),
        )
        .toList();
    // Keep one-hop context when searching, as in WeKnora's entity lookup.
    if (search.isNotEmpty || focus != null) {
      final matches = visible
          .where(
            (node) => focus != null
                ? node.id == focus
                : node.label.toLowerCase().contains(search),
          )
          .map((node) => node.id)
          .toSet();
      ids = {
        ...matches,
        for (final edge in links)
          if (matches.contains(edge.source)) edge.target,
        for (final edge in links)
          if (matches.contains(edge.target)) edge.source,
      };
      visible = visible.where((node) => ids.contains(node.id)).toList();
      links = links
          .where(
            (edge) => ids.contains(edge.source) && ids.contains(edge.target),
          )
          .toList();
    }
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
  KnowledgeGraphBuilder(
    Iterable<ViewPB> views, {
    required String workspaceId,
    String? focusViewId,
  }) {
    for (final view in views) {
      final extra = _json(view.extra);
      if (view.id.isEmpty ||
          view.id == workspaceId ||
          extra is Map && extra['is_space'] == true ||
          focusViewId == null && !isDocument(view)) {
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

  static bool isDocument(ViewPB view) {
    final extra = _json(view.extra);
    return view.layout == ViewLayoutPB.Document &&
        !(extra is Map && extra['view_type'] == 'handwriting_saber');
  }

  /// The model supplies names, never page IDs. Sources come from readable pages.
  void addExtraction(
    ViewPB view,
    GraphSource source,
    Map<String, dynamic> graph,
  ) {
    if (!_nodes.containsKey(view.id) || source.viewId != view.id) return;
    final names = <String, String>{};
    for (final raw in graph['node'] as List) {
      final name = raw['name'] as String;
      // ponytail: merge normalized names across notes; add disambiguation if
      // distinct people or concepts sharing a name need separate identities.
      final normalized =
          name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
      final id = 'entity:$normalized';
      names[name] = id;
      final existing = _nodes[id];
      final attributes = (raw['attributes'] as List).cast<String>();
      _nodes[id] = GraphNode(
        id: id,
        label: existing?.label ?? name,
        view: existing?.view ?? view,
        entityType: existing?.entityType ?? raw['type'] as String,
        description: {
          if (existing != null && existing.description.isNotEmpty)
            ...existing.description.split('\n'),
          ...attributes,
        }.join('\n'),
        sources: [
          ...?existing?.sources,
          GraphSource(
            viewId: source.viewId,
            blockId: source.blockFor(name),
            text: source.text,
          ),
        ],
      );
      _mergeEdge(
        GraphEdge(view.id, id, GraphEdgeKind.mention, sources: [source]),
      );
    }
    for (final raw in graph['relation'] as List) {
      final a = names[raw['node1']];
      final b = names[raw['node2']];
      if (a == null || b == null || a == b) continue;
      _mergeEdge(
        GraphEdge(
          a,
          b,
          GraphEdgeKind.relation,
          label: raw['type'] as String,
          sources: [
            GraphSource(
              viewId: view.id,
              blockId: source.blockFor(raw['evidence'] as String),
              text: raw['evidence'] as String,
            ),
          ],
        ),
      );
    }
  }

  void _mergeEdge(GraphEdge edge) {
    final previous = _edges.lookup(edge);
    if (previous == null) {
      _edges.add(edge);
    } else {
      _edges.remove(previous);
      _edges.add(
        GraphEdge(
          edge.source,
          edge.target,
          edge.kind,
          label: edge.label,
          sources: [...previous.sources, ...edge.sources],
        ),
      );
    }
  }

  KnowledgeGraphData build() {
    // Document references share one connection; semantic relations retain
    // their direction and type.
    final connections = <(String, String), GraphEdge>{};
    final directed = <GraphEdge>[];
    for (final edge in _edges) {
      if (edge.kind == GraphEdgeKind.relation ||
          edge.kind == GraphEdgeKind.mention) {
        directed.add(edge);
        continue;
      }
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
      edges: [...connections.values, ...directed],
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

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
    this.bidirectional = false,
  });

  final String source;
  final String target;
  final GraphEdgeKind kind;
  final String label;
  final List<GraphSource> sources;
  final bool bidirectional;

  @override
  bool operator ==(Object other) =>
      other is GraphEdge &&
      source == other.source &&
      target == other.target &&
      kind == other.kind &&
      label == other.label &&
      bidirectional == other.bidirectional;

  @override
  int get hashCode => Object.hash(source, target, kind, label, bidirectional);
}

class KnowledgeGraphData {
  const KnowledgeGraphData({
    this.nodes = const [],
    this.edges = const [],
    this.hiddenNodes = 0,
  });

  final int hiddenNodes;

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
    int depth = 1,
    int maxNodes = 0,
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
      ids = {...matches};
      for (var level = 0; level < depth.clamp(1, 2); level++) {
        final previous = Set<String>.of(ids);
        for (final edge in links) {
          if (previous.contains(edge.source)) ids.add(edge.target);
          if (previous.contains(edge.target)) ids.add(edge.source);
        }
      }
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
    var omitted = hiddenNodes;
    if (maxNodes > 0 && visible.length > maxNodes) {
      final degree = <String, int>{};
      for (final edge in links) {
        degree.update(edge.source, (value) => value + 1, ifAbsent: () => 1);
        degree.update(edge.target, (value) => value + 1, ifAbsent: () => 1);
      }
      visible.sort((a, b) {
        if (a.id == focus) return -1;
        if (b.id == focus) return 1;
        final byDegree = (degree[b.id] ?? 0).compareTo(degree[a.id] ?? 0);
        return byDegree == 0 ? a.id.compareTo(b.id) : byDegree;
      });
      omitted += visible.length - maxNodes;
      visible = visible.take(maxNodes).toList();
      final retained = visible.map((node) => node.id).toSet();
      links = links
          .where(
            (edge) =>
                retained.contains(edge.source) &&
                retained.contains(edge.target),
          )
          .toList();
    }
    return KnowledgeGraphData(
      nodes: visible,
      edges: links,
      hiddenNodes: omitted,
    );
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
      if (existing?.kind == GraphEdgeKind.reference &&
          edge.kind == GraphEdgeKind.reference) {
        connections[pair] = GraphEdge(
          existing!.source,
          existing.target,
          GraphEdgeKind.reference,
          bidirectional:
              existing.bidirectional || existing.source != edge.source,
          sources: [...existing.sources, ...edge.sources],
        );
      } else if (existing == null || edge.kind == GraphEdgeKind.reference) {
        connections[pair] = edge;
      }
    }
    return KnowledgeGraphData(
      nodes: _nodes.values.toList()..sort((a, b) => a.id.compareTo(b.id)),
      edges: [...connections.values, ...directed],
    );
  }

  /// Structural edges come from the local Rust index; only visible endpoints survive.
  void addLinks(Iterable<NoteLinkPB> links) {
    for (final link in links) {
      if (_nodes.containsKey(link.srcPageId)) {
        // An owned child-page block describes the folder tree, not a citation.
        if (link.kind == 'embed' &&
            _nodes[link.dstPageId]?.view.parentViewId == link.srcPageId) {
          continue;
        }
        _addReference(link.srcPageId, link.dstPageId);
      }
    }
  }

  /// Compatibility for imported document snapshots. Parse only editor link fields.
  void addDocument(ViewPB view, DocumentDataPB document) {
    if (!_nodes.containsKey(view.id)) return;
    void internalUrl(String url) {
      final uri = Uri.tryParse(url);
      if (uri == null ||
          !const {'ponynotes', 'appflowy-flutter', 'appflowy'}
              .contains(uri.scheme)) {
        return;
      }
      final id =
          uri.queryParameters['viewId'] ?? uri.queryParameters['page_id'];
      if (id != null) _addReference(view.id, id);
    }

    void delta(dynamic value) {
      if (value is Map) value = value['ops'] ?? value['delta'];
      if (value is! List) return;
      for (final op in value) {
        if (op is! Map) continue;
        final attributes = op['attributes'];
        if (attributes is! Map) continue;
        final mention = attributes['mention'];
        if (op['insert'] == r'$' &&
            mention is Map &&
            const {'page', 'childPage'}.contains(mention['type'] ?? 'page') &&
            mention['page_id'] is String) {
          _addReference(view.id, mention['page_id'] as String);
        }
        final href = attributes['href'];
        if (href is String) internalUrl(href);
      }
    }

    for (final block in document.blocks.values) {
      final data = _json(block.data);
      if (data is! Map) continue;
      if (const {'sub_page', 'mention', 'link_to_page'}.contains(block.ty) &&
          data['view_id'] is String) {
        _addReference(view.id, data['view_id'] as String);
      }
      if (block.ty == 'link_preview' && data['url'] is String) {
        internalUrl(data['url'] as String);
      }
      delta(data['delta']);
    }
    for (final text in document.meta.textMap.values) {
      delta(_json(text));
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

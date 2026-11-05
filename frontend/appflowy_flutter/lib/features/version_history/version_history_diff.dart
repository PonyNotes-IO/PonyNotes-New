import 'dart:convert';

import 'package:appflowy_backend/protobuf/flowy-document/protobuf.dart';
import 'package:diffutil_dart/diffutil.dart';

enum HistoryChange { unchanged, removed, added }

class HistoryDiffLine {
  const HistoryDiffLine(
    this.change,
    this.text,
    this.currentLine,
    this.versionLine, {
    this.attributesChanged = false,
  });

  final HistoryChange change;
  final String text;
  final int? currentLine;
  final int? versionLine;
  final bool attributesChanged;
}

class HistoryDiff {
  const HistoryDiff(this.lines);
  final List<HistoryDiffLine> lines;
  int get added => lines.where((e) => e.change == HistoryChange.added).length;
  int get removed =>
      lines.where((e) => e.change == HistoryChange.removed).length;
  bool get hasChanges => added > 0 || removed > 0;
}

// Runs off the UI isolate; compare semantic content, not internal block IDs.
HistoryDiff compareHistory((DocumentDataPB, DocumentDataPB) documents) {
  final current = _lines(documents.$1);
  final version = _lines(documents.$2);
  final updates = calculateListDiff(
    current.indexed.toList(),
    version.indexed.toList(),
    detectMoves: false,
    equalityChecker: (a, b) => a.$2.signature == b.$2.signature,
  ).getUpdatesWithData();
  final removed = <int>{};
  final added = <int>{};
  for (final update in updates) {
    if (update is DataRemove<(int, _Line)>) removed.add(update.data.$1);
    if (update is DataInsert<(int, _Line)>) added.add(update.data.$1);
  }
  final removedText = removed.map((i) => current[i].text).toSet();
  final addedText = added.map((i) => version[i].text).toSet();
  final result = <HistoryDiffLine>[];
  var i = 0;
  var j = 0;
  while (i < current.length || j < version.length) {
    if (removed.contains(i)) {
      result.add(
        HistoryDiffLine(
          HistoryChange.removed,
          current[i].text,
          i + 1,
          null,
          attributesChanged: addedText.contains(current[i].text),
        ),
      );
      i++;
    } else if (added.contains(j)) {
      result.add(
        HistoryDiffLine(
          HistoryChange.added,
          version[j].text,
          null,
          j + 1,
          attributesChanged: removedText.contains(version[j].text),
        ),
      );
      j++;
    } else {
      result.add(
        HistoryDiffLine(
          HistoryChange.unchanged,
          current[i].text,
          i + 1,
          j + 1,
        ),
      );
      i++;
      j++;
    }
  }
  return HistoryDiff(result);
}

class _Line {
  const _Line(this.text, this.signature);
  final String text;
  final String signature;
}

Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

List<_Line> _lines(DocumentDataPB document) {
  final result = <_Line>[];
  void visit(String id, int depth) {
    final block = document.blocks[id]!;
    final data = Map<String, dynamic>.from(jsonDecode(block.data) as Map);
    if (block.externalType == 'text' &&
        document.meta.textMap.containsKey(block.externalId)) {
      data['delta'] = jsonDecode(document.meta.textMap[block.externalId]!);
    }
    if (data['delta'] is List) {
      final normalized = <Map<String, dynamic>>[];
      for (final raw in data['delta'] as List) {
        final op = Map<String, dynamic>.from(raw as Map);
        if (op['attributes'] == null ||
            (op['attributes'] is Map && (op['attributes'] as Map).isEmpty)) {
          op.remove('attributes');
        }
        if (op['insert'] == '') continue;
        if (normalized.isNotEmpty &&
            op['insert'] is String &&
            normalized.last['insert'] is String &&
            jsonEncode(_canonical(op['attributes'])) ==
                jsonEncode(_canonical(normalized.last['attributes']))) {
          normalized.last['insert'] =
              '${normalized.last['insert']}${op['insert']}';
        } else {
          normalized.add(op);
        }
      }
      data['delta'] = normalized;
    }
    if (id != document.pageId || data.isNotEmpty) {
      final delta = data['delta'] as List?;
      final text = delta
              ?.map(
                (op) => op['insert'] is String ? op['insert'] as String : '…',
              )
              .join() ??
          ['name', 'caption', 'url', 'src', 'view_id']
              .map((key) => data[key])
              .whereType<String>()
              .join(' ');
      final marker = switch (block.ty) {
        'paragraph' => '',
        'heading' => '${'#' * ((data['level'] as num?)?.toInt() ?? 1)} ',
        'bulleted_list' => '- ',
        'numbered_list' => '1. ',
        'todo_list' => data['checked'] == true ? '[x] ' : '[ ] ',
        'quote' => '> ',
        _ => '[${block.ty}] ',
      };
      final signature = jsonEncode(
        _canonical([
          depth,
          block.ty,
          data,
          if (block.externalType.isNotEmpty && block.externalType != 'text')
            [block.externalType, block.externalId],
        ]),
      );
      result.add(_Line('${'  ' * depth}$marker$text', signature));
    }
    for (final child in document.meta.childrenMap[block.childrenId]?.children ??
        <String>[]) {
      visit(child, id == document.pageId ? 0 : depth + 1);
    }
  }

  visit(document.pageId, 0);
  return result;
}

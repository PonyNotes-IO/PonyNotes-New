import 'dart:async';
import 'dart:math' as math;
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import '../application/agent_controller.dart';
import 'agent_mode_details.dart';
import '../application/agent_reference.dart';

/// The welcome page and conversation share the same reference draft and picker.
class AgentReferenceField extends StatefulWidget {
  const AgentReferenceField({
    super.key,
    required this.controller,
    required this.selected,
    required this.onChanged,
    required this.load,
    required this.child,
    this.enabled = true,
    this.builder,
    this.smartMode = true,
    this.onModeChanged,
  });
  final TextEditingController controller;
  final List<AgentReference> selected;
  final ValueChanged<List<AgentReference>> onChanged;
  final Future<List<AgentReference>> Function() load;
  final Widget child;
  final bool enabled;
  final Widget Function(Widget field, Widget referenceButton)? builder;
  final bool smartMode;
  final ValueChanged<bool>? onModeChanged;

  @override
  State<AgentReferenceField> createState() => _AgentReferenceFieldState();
}

class _AgentReferenceFieldState extends State<AgentReferenceField> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  final _anchor = GlobalKey();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _scopedSearch = TextEditingController();
  final _scopedFocus = FocusNode();
  final _scroll = AutoScrollController();
  final _collapsedSections = <String>{};
  final _collapsedSpaces = <(String, String)>{};
  List<AgentReference> _items = [];
  String? _kind;
  String? _error;
  int? _typedStart;
  int _end = 0;
  int _focused = 0;
  int _generation = 0;
  bool _loading = false;
  bool _above = true;
  double _height = 320;
  bool _browsing = false;

  static const _modes = [
    (kind: 'quick', label: '快问快答', icon: Icons.bolt_outlined),
    (kind: 'smart', label: '智能推理', icon: Icons.auto_awesome_outlined),
  ];

  static const _categories = [
    (kind: 'base', label: '知识库', icon: Icons.menu_book_outlined),
    (kind: 'file', label: '文件', icon: Icons.folder_outlined),
    (kind: 'note', label: '笔记', icon: Icons.insert_drive_file_outlined),
  ];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_typed);
    AgentController.accountClearance.addListener(_close);
  }

  @override
  void didUpdateWidget(covariant AgentReferenceField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _portal.isShowing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !widget.enabled) _close();
      });
    }
  }

  @override
  void dispose() {
    ++_generation;
    widget.controller.removeListener(_typed);
    AgentController.accountClearance.removeListener(_close);
    _search.dispose();
    _searchFocus.dispose();
    _scopedSearch.dispose();
    _scopedFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _typed() {
    if (!widget.enabled) return;
    final value = widget.controller.value;
    if (!value.composing.isCollapsed) return;
    if (!value.selection.isCollapsed) {
      if (_typedStart != null) _close();
      return;
    }
    final end = value.selection.baseOffset;
    if (end < 0 || end > value.text.length) return;
    final match = RegExp(r'(?:^|[^a-zA-Z0-9_@.])@([^\s@]*)$')
        .firstMatch(value.text.substring(0, end));
    if (match == null) {
      if (_typedStart != null) _close();
      return;
    }
    _typedStart = end - match.group(1)!.length - 1;
    _end = end;
    _search.text = match.group(1)!;
    _focused = 0;
    if (!_portal.isShowing) {
      _open(fromTyping: true);
    } else {
      setState(() {
        _kind = null;
        _scopedSearch.clear();
        _browsing = _search.text.isNotEmpty;
      });
    }
  }

  void _open({bool fromTyping = false}) {
    if (!widget.enabled) return;
    if (!fromTyping) {
      _typedStart = null;
      _search.clear();
    }
    _kind = _search.text.isNotEmpty ? null : 'note';
    _browsing = _search.text.isNotEmpty;
    _focused = _browsing
        ? 0
        : math.max(0, _navigation.indexWhere((entry) => entry.kind == _kind));
    final box = _anchor.currentContext!.findRenderObject()! as RenderBox;
    final offset = box.localToGlobal(Offset.zero);
    final media = MediaQuery.of(context);
    final above = offset.dy - media.padding.top - 16;
    final below = media.size.height -
        media.viewInsets.bottom -
        offset.dy -
        box.size.height -
        16;
    _above = above >= below;
    _height = math.min(344, math.max(0, _above ? above : below));
    _scopedSearch.clear();
    _collapsedSections.clear();
    _collapsedSpaces.clear();
    _portal.show();
    unawaited(_load());
    if (!fromTyping) _searchFocus.requestFocus();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _items = [];
    });
    try {
      final items = await widget.load();
      if (!mounted || generation != _generation) return;
      setState(() => _items = items);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = '引用列表加载失败，请重试');
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _close() {
    ++_generation;
    _typedStart = null;
    _items = [];
    _search.clear();
    _scopedSearch.clear();
    _portal.hide();
  }

  List<AgentReference> get _filtered {
    final query =
        (_kind != null && !_showModes ? _scopedSearch.text : _search.text)
            .trim()
            .toLowerCase();
    final selected = widget.selected.map((r) => r.key).toSet();
    return _items
        .where(
          (r) =>
              (_kind == null || _showModes || r.kind == _kind) &&
              !selected.contains(r.key) &&
              '${r.name} ${r.subtitle} ${r.spaceName}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
  }

  bool get _showModes => _kind == 'smart' || _kind == 'quick';

  double get _width => math.min(
        _showModes ? 440 : 506,
        MediaQuery.sizeOf(context).width - 24,
      );

  bool get _singlePane => !_showModes && _width < 480;

  double get _offsetX {
    final box = _anchor.currentContext!.findRenderObject()! as RenderBox;
    final x = box.localToGlobal(Offset.zero).dx;
    return (x - 8).clamp(
          12.0,
          math.max(12.0, MediaQuery.sizeOf(context).width - _width - 12),
        ) -
        x;
  }

  Map<String, Map<String, List<AgentReference>>> get _noteGroups {
    final groups = <String, Map<String, List<AgentReference>>>{};
    for (final item in _filtered) {
      groups
          .putIfAbsent(item.noteSection, () => {})
          .putIfAbsent(item.noteSpace, () => [])
          .add(item);
    }
    return {
      for (final section in ['私有笔记', '协作笔记', '笔记'])
        if (groups.containsKey(section)) section: groups[section]!,
    };
  }

  bool get _searchingNotes => _scopedSearch.text.trim().isNotEmpty;

  List<AgentReference> get _visibleItems => _kind == 'note'
      ? [
          for (final section in _noteGroups.entries)
            if (_searchingNotes || !_collapsedSections.contains(section.key))
              for (final space in section.value.entries)
                if (_searchingNotes ||
                    !_collapsedSpaces.contains((section.key, space.key)))
                  ...space.value,
        ]
      : _filtered;

  void _browse(String kind, {bool enter = false}) {
    setState(() {
      if (_kind != kind) _scopedSearch.clear();
      _kind = kind;
      _browsing = enter;
      _focused = enter ? 0 : _navigation.indexWhere((e) => e.kind == kind);
    });
    if (enter) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _portal.isShowing && _kind == kind && _browsing) {
          _scopedFocus.requestFocus();
        }
      });
    }
  }

  void _backToCategories() {
    setState(() {
      _browsing = false;
      _focused = math.max(0, _navigation.indexWhere((e) => e.kind == _kind));
    });
    _searchFocus.requestFocus();
  }

  List<({String kind, String label, IconData icon})> get _navigation => [
        if (_showModes && widget.onModeChanged != null) ..._modes,
        ..._categories,
      ];

  void _consumeMention() {
    final start = _typedStart;
    final end = _end;
    _close();
    if (start != null) {
      widget.controller.value = TextEditingValue(
        text: widget.controller.text.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
      );
    }
  }

  void _selectMode(String kind) {
    if (!widget.enabled ||
        !widget.controller.value.composing.isCollapsed ||
        !_search.value.composing.isCollapsed) {
      return;
    }
    _consumeMention();
    widget.onModeChanged?.call(kind == 'smart');
  }

  void _select(AgentReference item) {
    if (!item.available || widget.selected.length >= 20) return;
    if (!widget.controller.value.composing.isCollapsed ||
        !_search.value.composing.isCollapsed ||
        !_scopedSearch.value.composing.isCollapsed) {
      return;
    }
    _consumeMention();
    widget.onChanged([...widget.selected, item]);
  }

  KeyEventResult _key(FocusNode _, KeyEvent event) {
    if (!_portal.isShowing || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (!widget.controller.value.composing.isCollapsed ||
        !_search.value.composing.isCollapsed ||
        !_scopedSearch.value.composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
        !_searchingNotes &&
        _search.text.isEmpty &&
        !_scopedFocus.hasFocus) {
      _backToCategories();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
        _search.text.isEmpty &&
        !_scopedFocus.hasFocus &&
        !_showModes) {
      setState(() {
        _browsing = true;
        _focused = 0;
      });
      return KeyEventResult.handled;
    }
    final navigation = _navigation;
    final length = _browsing ? _visibleItems.length : navigation.length;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (length > 0) {
        setState(
          () {
            _focused = (_focused +
                    (event.logicalKey == LogicalKeyboardKey.arrowDown
                        ? 1
                        : -1)) %
                length;
            if (!_browsing) {
              _kind = navigation[_focused].kind;
              _focused = _navigation.indexWhere((entry) => entry.kind == _kind);
              _scopedSearch.clear();
            }
          },
        );
        if (_browsing) unawaited(_scroll.scrollToIndex(_focused));
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (length > 0) {
        if (!_browsing) {
          final kind = navigation[_focused.clamp(0, length - 1)].kind;
          if (kind == 'smart' || kind == 'quick') {
            _selectMode(kind);
          } else {
            setState(() {
              _kind = kind;
              _browsing = true;
              _focused = 0;
            });
          }
        } else if (!_loading && _error == null) {
          _select(_visibleItems[_focused.clamp(0, length - 1)]);
        }
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Color get _foreground =>
      AppFlowyTheme.maybeOf(context)?.textColorScheme.primary ??
      Theme.of(context).colorScheme.onSurface;

  Color get _accent => Colors.indigo.shade400;

  Widget _surface(Widget child, {bool reference = false}) => Material(
        color: reference
            ? Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF262626)
                : Colors.white
            : AppFlowyTheme.maybeOf(context)?.surfaceColorScheme.layer01 ??
                Theme.of(context).colorScheme.surface,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: .2),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(reference ? 12 : 10),
          side: BorderSide(color: _foreground.withValues(alpha: .12)),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 5),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 10,
            color: _foreground.withValues(alpha: .45),
          ),
        ),
      );

  Widget _navigationItem(
    ({String kind, String label, IconData icon}) entry,
  ) {
    final mode = entry.kind == 'quick' || entry.kind == 'smart';
    final selected = _kind == entry.kind;
    final count = _items
        .where(
          (item) =>
              item.kind == entry.kind &&
              !widget.selected.any((selected) => selected.key == item.key),
        )
        .length;
    final current = mode && widget.smartMode == (entry.kind == 'smart');
    return MouseRegion(
      onEnter: (_) => _browse(entry.kind),
      child: Semantics(
        selected: selected,
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: () {
            if (mode) {
              _selectMode(entry.kind);
            } else {
              _browse(entry.kind, enter: true);
            }
          },
          child: Ink(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: selected ? _foreground.withValues(alpha: .08) : null,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              children: [
                Icon(
                  entry.icon,
                  size: 15,
                  color: _accent,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    entry.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (current)
                  const Icon(Icons.check, size: 12)
                else if (!mode)
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10,
                      color: _foreground.withValues(alpha: .45),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _referenceBrowser() {
    final menu = _surface(
      Column(
        key: const ValueKey('agent-reference-categories'),
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 37,
            child: TextField(
              controller: _search,
              focusNode: _searchFocus,
              style: TextStyle(fontSize: 12, color: _foreground),
              decoration: InputDecoration(
                hintText: '搜索知识库、文件、笔记等',
                hintStyle: TextStyle(color: _foreground.withValues(alpha: .4)),
                prefixIcon: Icon(
                  Icons.search,
                  size: 17,
                  color: _foreground.withValues(alpha: .4),
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 30),
                suffixIcon: IconButton(
                  tooltip: '关闭引用选择',
                  onPressed: _close,
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.close, size: 12),
                ),
                suffixIconConstraints:
                    const BoxConstraints.tightFor(width: 24, height: 28),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
              ),
              onChanged: (_) => setState(() {
                _kind = null;
                _browsing = _search.text.isNotEmpty;
                _focused = 0;
              }),
            ),
          ),
          Divider(
            height: 1,
            indent: 10,
            endIndent: 10,
            color: _foreground.withValues(alpha: .08),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(5),
              children: [for (final entry in _categories) _categoryRow(entry)],
            ),
          ),
        ],
      ),
      reference: true,
    );
    final results = _surface(_referenceResults(), reference: true);
    if (_singlePane) {
      return _browsing
          ? results
          : Align(
              alignment: _above ? Alignment.bottomCenter : Alignment.topCenter,
              child: menu,
            );
    }
    return Row(
      crossAxisAlignment:
          _above ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            padding: _above
                ? const EdgeInsets.only(bottom: 14)
                : const EdgeInsets.only(top: 14),
            child: menu,
          ),
        ),
        const SizedBox(width: 18),
        Expanded(child: results),
      ],
    );
  }

  Widget _categoryRow(({String kind, String label, IconData icon}) entry) {
    final active = _kind == entry.kind;
    final selected = widget.selected.map((r) => r.key).toSet();
    final count = _items
        .where(
          (item) => item.kind == entry.kind && !selected.contains(item.key),
        )
        .length;
    return MouseRegion(
      key: ValueKey('agent-reference-category-${entry.kind}'),
      onEnter: (_) => _browse(entry.kind),
      child: Semantics(
        selected: active,
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: () => _browse(entry.kind, enter: true),
          child: Ink(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              color: active ? _foreground.withValues(alpha: .08) : null,
            ),
            child: Row(
              children: [
                Icon(
                  entry.icon,
                  size: 17,
                  color: _foreground.withValues(alpha: .8),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    entry.label,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                if (!_loading)
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      color: _foreground.withValues(alpha: .35),
                    ),
                  ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  size: 15,
                  color: _foreground.withValues(alpha: .35),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _referenceResults() {
    final label = _kind == null
        ? '搜索结果'
        : _categories.firstWhere((c) => c.kind == _kind).label;
    return Column(
      key: const ValueKey('agent-reference-results'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 37,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: Row(
              children: [
                Icon(
                  Icons.search,
                  size: 17,
                  color: _foreground.withValues(alpha: .4),
                ),
                const SizedBox(width: 7),
                Tooltip(
                  message: '返回资料分类',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(5),
                    onTap: _backToCategories,
                    child: Ink(
                      padding: const EdgeInsets.fromLTRB(2, 3, 5, 3),
                      decoration: BoxDecoration(
                        color: _foreground.withValues(alpha: .05),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.chevron_left,
                            size: 13,
                            color: _foreground.withValues(alpha: .45),
                          ),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 12,
                              color: _foreground.withValues(alpha: .6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                if (_kind != null)
                  Expanded(
                    child: TextField(
                      key: const ValueKey('agent-reference-search'),
                      controller: _scopedSearch,
                      focusNode: _scopedFocus,
                      style: TextStyle(fontSize: 13, color: _foreground),
                      decoration: InputDecoration(
                        hintText: '在$label中搜索…',
                        hintStyle: TextStyle(
                          fontSize: 12,
                          color: _foreground.withValues(alpha: .4),
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 11),
                      ),
                      onChanged: (_) => setState(() {
                        _browsing = true;
                        _focused = 0;
                      }),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Divider(
          height: 1,
          indent: 10,
          endIndent: 10,
          color: _foreground.withValues(alpha: .08),
        ),
        Expanded(child: _referenceBody()),
      ],
    );
  }

  Widget _panel() => DefaultTextStyle.merge(
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 12,
              color: _foreground,
            ),
        child: SizedBox(
          key: const ValueKey('agent-mention-panel'),
          width: _width,
          height: _showModes ? math.min(280, _height) : _height,
          child: Focus(
            onKeyEvent: _key,
            child: !_showModes
                ? _referenceBrowser()
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: _width < 380 ? 128 : 174,
                        child: _surface(
                          Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(6, 4, 4, 0),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _search,
                                        focusNode: _searchFocus,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: _foreground,
                                        ),
                                        decoration: const InputDecoration(
                                          hintText: '搜索资料',
                                          prefixIcon:
                                              Icon(Icons.search, size: 14),
                                          prefixIconConstraints:
                                              BoxConstraints(minWidth: 24),
                                          border: InputBorder.none,
                                          isDense: true,
                                          contentPadding:
                                              EdgeInsets.symmetric(vertical: 9),
                                        ),
                                        onChanged: (_) => setState(() {
                                          _kind = null;
                                          _browsing = true;
                                          _focused = 0;
                                        }),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: '关闭引用选择',
                                      onPressed: _close,
                                      icon: const Icon(Icons.close, size: 13),
                                      padding: EdgeInsets.zero,
                                      constraints:
                                          const BoxConstraints.tightFor(
                                        width: 24,
                                        height: 28,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      style: IconButton.styleFrom(
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Divider(
                                height: 1,
                                color: _foreground.withValues(alpha: .06),
                              ),
                              Expanded(
                                child: ListView(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 5),
                                  children: [
                                    if (widget.onModeChanged != null) ...[
                                      _heading('对话模式'),
                                      ..._modes.map(_navigationItem),
                                    ],
                                    _heading('引用资料'),
                                    ..._categories.map(_navigationItem),
                                  ],
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 7),
                                child: Text(
                                  widget.selected.length >= 20
                                      ? '最多引用 20 项'
                                      : '↑↓ 选择 · Enter 确认',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: _foreground.withValues(alpha: .4),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _surface(
                          _modeDetails(),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      );

  Widget _modeDetails() => AgentModeDetails(
        smart: _kind == 'smart',
        current: widget.smartMode == (_kind == 'smart'),
        onSelected: () => _selectMode(_kind!),
      );

  Widget _referenceBody() => _loading
      ? const Center(
          child: SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        )
      : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      style: const TextStyle(fontSize: 11),
                    ),
                    TextButton(
                      onPressed: _load,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            )
          : _kind == 'note'
              ? _noteList()
              : _list();

  Widget _noteList() {
    if (_filtered.isEmpty) return _list();
    final items = _visibleItems;
    final indices = {for (var i = 0; i < items.length; i++) items[i].key: i};
    final rows = <Widget Function()>[];
    for (final section in _noteGroups.entries) {
      final expanded =
          _searchingNotes || !_collapsedSections.contains(section.key);
      final first = rows.isEmpty;
      rows.add(
        () => Padding(
          padding: EdgeInsets.only(top: first ? 0 : 13),
          child: _groupHeader(
            section.key,
            expanded: expanded,
            section: true,
            onTap: () => setState(() {
              if (!_collapsedSections.add(section.key)) {
                _collapsedSections.remove(section.key);
              }
              _focused = 0;
            }),
          ),
        ),
      );
      if (!expanded) continue;
      for (final space in section.value.entries) {
        final spaceKey = (section.key, space.key);
        final open = _searchingNotes || !_collapsedSpaces.contains(spaceKey);
        rows.add(
          () => _groupHeader(
            space.key,
            expanded: open,
            section: false,
            onTap: () => setState(() {
              if (!_collapsedSpaces.add(spaceKey)) {
                _collapsedSpaces.remove(spaceKey);
              }
              _focused = 0;
            }),
          ),
        );
        if (!open) continue;
        for (final item in space.value) {
          final index = indices[item.key]!;
          rows.add(
            () => AutoScrollTag(
              key: ValueKey('reference-${item.key}'),
              controller: _scroll,
              index: index,
              child: Tooltip(
                message: item.subtitle.isEmpty
                    ? item.name
                    : '${item.name}\n${item.subtitle}',
                child: ListTile(
                  dense: true,
                  minTileHeight: 28,
                  minVerticalPadding: 0,
                  minLeadingWidth: 16,
                  horizontalTitleGap: 4,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5),
                  ),
                  selectedTileColor: _foreground.withValues(alpha: .08),
                  selectedColor: _foreground,
                  enabled: item.available && widget.selected.length < 20,
                  selected: _browsing && index == _focused,
                  leading: Icon(
                    Icons.insert_drive_file_outlined,
                    size: 17,
                    color: _foreground.withValues(alpha: .6),
                  ),
                  title: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  onTap: () => _select(item),
                ),
              ),
            ),
          );
        }
      }
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(5, 8, 5, 8),
      itemCount: rows.length,
      itemBuilder: (_, index) => rows[index](),
    );
  }

  Widget _groupHeader(
    String label, {
    required bool expanded,
    required bool section,
    required VoidCallback onTap,
  }) =>
      Semantics(
        expanded: expanded,
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: _searchingNotes ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
            child: Row(
              children: [
                if (!section) ...[
                  Icon(
                    Icons.workspaces_outline,
                    size: 17,
                    color: _foreground.withValues(alpha: .7),
                  ),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: section ? 12 : 13,
                      fontWeight: FontWeight.w500,
                      color: section
                          ? const Color(0xFFFF4D00)
                          : _foreground.withValues(alpha: .85),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 14,
                  color: _foreground.withValues(alpha: .45),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _list() {
    final items = _filtered;
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            _search.text.isEmpty && !_searchingNotes ? '暂无可引用的资料' : '没有找到匹配的资料',
            style: TextStyle(
              fontSize: 11,
              color: _foreground.withValues(alpha: .5),
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(5),
      itemCount: items.length,
      itemBuilder: (_, index) {
        final item = items[index];
        return AutoScrollTag(
          key: ValueKey('reference-${item.key}'),
          controller: _scroll,
          index: index,
          child: ListTile(
            dense: true,
            minTileHeight: 44,
            minLeadingWidth: 16,
            horizontalTitleGap: 7,
            contentPadding: const EdgeInsets.symmetric(horizontal: 6),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
            selectedTileColor: _foreground.withValues(alpha: .06),
            selectedColor: _foreground,
            enabled: item.available && widget.selected.length < 20,
            selected: _browsing && index == _focused,
            leading: Icon(
              _categories.firstWhere((c) => c.kind == item.kind).icon,
              size: 16,
            ),
            title: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            subtitle: Text(
              item.available
                  ? (item.subtitle.isEmpty ? '可引用' : item.subtitle)
                  : '暂无可检索内容',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: _foreground.withValues(alpha: .45),
              ),
            ),
            onTap: () => _select(item),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final referenceButton = CompositedTransformTarget(
      key: _anchor,
      link: _link,
      child: IconButton(
        tooltip: '引用知识库、文件或笔记',
        onPressed: widget.enabled &&
                (widget.selected.length < 20 || widget.onModeChanged != null)
            ? _open
            : null,
        visualDensity: VisualDensity.compact,
        style: widget.builder == null
            ? null
            : IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                minimumSize: const Size(30, 30),
              ),
        icon: const Icon(Icons.alternate_email, size: 18),
      ),
    );
    final tagColor = Color.alphaBlend(
      _foreground.withValues(alpha: .06),
      AppFlowyTheme.maybeOf(context)?.surfaceColorScheme.layer01 ??
          Theme.of(context).colorScheme.surface,
    );
    final references = [
      for (final reference in widget.selected)
        InputChip(
          key: ValueKey('agent-reference-${reference.key}'),
          backgroundColor: tagColor,
          disabledColor: tagColor,
          surfaceTintColor: Colors.transparent,
          side: BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.only(left: 6, right: 2),
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          avatarBoxConstraints: const BoxConstraints.tightFor(
            width: 14,
            height: 14,
          ),
          avatar: Icon(
            reference.kind == 'base'
                ? Icons.menu_book_outlined
                : _categories.firstWhere((c) => c.kind == reference.kind).icon,
            size: 14,
            color: reference.kind == 'base'
                ? const Color(0xFFFF4D00)
                : _foreground.withValues(alpha: .65),
          ),
          labelStyle: TextStyle(
            fontSize: 12,
            height: 1.3,
            fontWeight: FontWeight.w400,
            color: _foreground.withValues(alpha: .85),
          ),
          label: Tooltip(
            message: reference.subtitle.isEmpty
                ? reference.name
                : '${reference.name}\n${reference.subtitle}',
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                reference.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          deleteIcon: const Icon(Icons.close, size: 12),
          deleteIconColor: _foreground.withValues(alpha: .5),
          deleteIconBoxConstraints: const BoxConstraints.tightFor(
            width: 20,
            height: 20,
          ),
          deleteButtonTooltipMessage: '移除引用：${reference.name}',
          onDeleted: widget.enabled
              ? () => widget.onChanged(
                    widget.selected
                        .where((r) => r.key != reference.key)
                        .toList(),
                  )
              : null,
        ),
      if (widget.selected.length >= 20) const Text('最多引用 20 项'),
    ];
    // Keep the selected sources above the draft in both composer states.
    final field = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (references.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(spacing: 6, runSpacing: 6, children: references),
          ),
        widget.child,
      ],
    );
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
            ),
          ),
          CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: _above ? Alignment.topLeft : Alignment.bottomLeft,
            followerAnchor: _above ? Alignment.bottomLeft : Alignment.topLeft,
            offset: Offset(_offsetX, _above ? -8 : 8),
            child: _panel(),
          ),
        ],
      ),
      child: Focus(
        onKeyEvent: _key,
        child: widget.builder?.call(
              field,
              referenceButton,
            ) ??
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                field,
                referenceButton,
              ],
            ),
      ),
    );
  }
}

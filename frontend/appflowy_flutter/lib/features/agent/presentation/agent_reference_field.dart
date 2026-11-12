import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import '../application/agent_controller.dart';
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
  });
  final TextEditingController controller;
  final List<AgentReference> selected;
  final ValueChanged<List<AgentReference>> onChanged;
  final Future<List<AgentReference>> Function() load;
  final Widget child;
  final bool enabled;

  @override
  State<AgentReferenceField> createState() => _AgentReferenceFieldState();
}

class _AgentReferenceFieldState extends State<AgentReferenceField> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  final _anchor = GlobalKey();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _scroll = AutoScrollController();
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

  static const _categories = [
    (kind: 'base', label: '知识库', icon: Icons.storage_outlined),
    (kind: 'file', label: '文件', icon: Icons.insert_drive_file_outlined),
    (kind: 'note', label: '笔记', icon: Icons.description_outlined),
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
      setState(() {});
    }
  }

  void _open({bool fromTyping = false}) {
    if (!widget.enabled) return;
    if (!fromTyping) {
      _typedStart = null;
      _search.clear();
    }
    _kind = null;
    _focused = 0;
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
    _height = math.min(380, math.max(120, _above ? above : below));
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
    _portal.hide();
  }

  List<AgentReference> get _filtered {
    final query = _search.text.trim().toLowerCase();
    final selected = widget.selected.map((r) => r.key).toSet();
    return _items
        .where(
          (r) =>
              (_kind == null || r.kind == _kind) &&
              !selected.contains(r.key) &&
              '${r.name} ${r.subtitle}'.toLowerCase().contains(query),
        )
        .toList();
  }

  bool get _showCategories => _kind == null && _search.text.isEmpty;

  void _select(AgentReference item) {
    if (!item.available || widget.selected.length >= 20) return;
    if (!widget.controller.value.composing.isCollapsed ||
        !_search.value.composing.isCollapsed) {
      return;
    }
    final start = _typedStart;
    final end = _end;
    _close();
    if (start != null) {
      final text = widget.controller.text;
      widget.controller.value = TextEditingValue(
        text: text.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
      );
    }
    widget.onChanged([...widget.selected, item]);
  }

  KeyEventResult _key(FocusNode _, KeyEvent event) {
    if (!_portal.isShowing || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (!widget.controller.value.composing.isCollapsed ||
        !_search.value.composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    final length = _showCategories ? _categories.length : _filtered.length;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (length > 0) {
        setState(
          () => _focused = (_focused +
                  (event.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1)) %
              length,
        );
        unawaited(_scroll.scrollToIndex(_focused));
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (!_loading && _error == null && length > 0) {
        if (_showCategories) {
          setState(() {
            _kind = _categories[_focused].kind;
            _focused = 0;
          });
        } else {
          _select(_filtered[_focused.clamp(0, length - 1)]);
        }
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _panel(double width) => Material(
        elevation: 8,
        surfaceTintColor: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: math.min(440, width),
          height: math.min(
            _height,
            72 +
                (_loading || _error != null
                        ? 1
                        : math.max(
                            1,
                            _showCategories
                                ? _categories.length
                                : _filtered.length,
                          )) *
                    72,
          ),
          child: Focus(
            onKeyEvent: _key,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 12, 4),
                  child: Row(
                    children: [
                      if (_kind != null)
                        IconButton(
                          tooltip: '返回引用分类',
                          icon: const Icon(Icons.arrow_back, size: 18),
                          onPressed: () => setState(() {
                            _kind = null;
                            _focused = 0;
                          }),
                        ),
                      Expanded(
                        child: TextField(
                          controller: _search,
                          focusNode: _searchFocus,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search, size: 18),
                            hintText: _kind == null
                                ? '搜索知识库、文件、笔记'
                                : '搜索${_categories.firstWhere((c) => c.kind == _kind).label}',
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() => _focused = 0),
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭引用选择',
                        onPressed: _close,
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_error!),
                                  TextButton(
                                    onPressed: _load,
                                    child: const Text('重试'),
                                  ),
                                ],
                              ),
                            )
                          : _list(),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _list() {
    final items = _filtered;
    if (!_showCategories && items.isEmpty) {
      return Center(
        child: Text(_search.text.isEmpty ? '暂无可引用的资料' : '没有找到匹配的资料'),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _showCategories ? _categories.length : items.length,
      itemBuilder: (_, index) {
        if (_showCategories) {
          final category = _categories[index];
          final count = items.where((r) => r.kind == category.kind).length;
          return AutoScrollTag(
            key: ValueKey('reference-category-${category.kind}'),
            controller: _scroll,
            index: index,
            child: ListTile(
              selected: index == _focused,
              leading: Icon(category.icon, size: 20),
              title: Text(category.label),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$count'),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
              onTap: () => setState(() {
                _kind = category.kind;
                _focused = 0;
              }),
            ),
          );
        }
        final item = items[index];
        return AutoScrollTag(
          key: ValueKey('reference-${item.key}'),
          controller: _scroll,
          index: index,
          child: ListTile(
            enabled: item.available && widget.selected.length < 20,
            selected: index == _focused,
            leading: Icon(
              _categories.firstWhere((c) => c.kind == item.kind).icon,
              size: 20,
            ),
            title:
                Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              item.available ? item.subtitle : '暂无可检索内容',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _select(item),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (_, constraints) => CompositedTransformTarget(
          key: _anchor,
          link: _link,
          child: OverlayPortal(
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
                  targetAnchor:
                      _above ? Alignment.topLeft : Alignment.bottomLeft,
                  followerAnchor:
                      _above ? Alignment.bottomLeft : Alignment.topLeft,
                  offset: Offset(0, _above ? -8 : 8),
                  child: _panel(constraints.maxWidth),
                ),
              ],
            ),
            child: Focus(
              onKeyEvent: _key,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  widget.child,
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    children: [
                      IconButton(
                        tooltip: '引用知识库、文件或笔记',
                        onPressed: widget.enabled && widget.selected.length < 20
                            ? _open
                            : null,
                        icon: const Icon(Icons.alternate_email, size: 18),
                      ),
                      for (final reference in widget.selected)
                        InputChip(
                          avatar: Icon(
                            _categories
                                .firstWhere(
                                  (c) => c.kind == reference.kind,
                                )
                                .icon,
                            size: 16,
                          ),
                          label: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 200),
                            child: Text(
                              reference.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          tooltip: reference.subtitle.isEmpty
                              ? reference.name
                              : '${reference.name}\n${reference.subtitle}',
                          onDeleted: widget.enabled
                              ? () => widget.onChanged(
                                    widget.selected
                                        .where((r) => r.key != reference.key)
                                        .toList(),
                                  )
                              : null,
                        ),
                      if (widget.selected.length >= 20) const Text('最多引用 20 项'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

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
  double _width = 440;
  double _offsetX = 0;
  bool _browsing = false;

  static const _modes = [
    (kind: 'quick', label: '快问快答', icon: Icons.bolt_outlined),
    (kind: 'smart', label: '智能推理', icon: Icons.auto_awesome_outlined),
  ];

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
      setState(() {
        _kind = null;
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
    _kind = _search.text.isNotEmpty
        ? null
        : widget.onModeChanged == null
            ? 'base'
            : widget.smartMode
                ? 'smart'
                : 'quick';
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
    _height = math.min(280, math.max(0, _above ? above : below));
    _width = math.min(440, media.size.width - 24);
    _offsetX = (offset.dx - 96)
            .clamp(12.0, math.max(12.0, media.size.width - _width - 12)) -
        offset.dx;
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
              (_kind == null || _showModes || r.kind == _kind) &&
              !selected.contains(r.key) &&
              '${r.name} ${r.subtitle}'.toLowerCase().contains(query),
        )
        .toList();
  }

  bool get _showModes => _kind == 'smart' || _kind == 'quick';

  List<({String kind, String label, IconData icon})> get _navigation => [
        if (widget.onModeChanged != null) ..._modes,
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
        !_search.value.composing.isCollapsed) {
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
        !_search.value.composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
        _search.text.isEmpty) {
      setState(() {
        _browsing = false;
        _focused = _navigation.indexWhere((entry) => entry.kind == _kind);
        if (_focused < 0) _focused = 0;
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
        _search.text.isEmpty &&
        !_showModes) {
      setState(() {
        _browsing = true;
        _focused = 0;
      });
      return KeyEventResult.handled;
    }
    final length = _browsing ? _filtered.length : _navigation.length;
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
            if (!_browsing) _kind = _navigation[_focused].kind;
          },
        );
        if (_browsing) unawaited(_scroll.scrollToIndex(_focused));
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (length > 0) {
        if (!_browsing) {
          final kind = _navigation[_focused.clamp(0, length - 1)].kind;
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
          _select(_filtered[_focused.clamp(0, length - 1)]);
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

  Widget _surface(Widget child) => Material(
        color: AppFlowyTheme.maybeOf(context)?.surfaceColorScheme.layer01 ??
            Theme.of(context).colorScheme.surface,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: .2),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
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
      onEnter: (_) => setState(() {
        _kind = entry.kind;
        _browsing = false;
        _focused = _navigation.indexOf(entry);
      }),
      child: Semantics(
        selected: selected,
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: () {
            if (mode) {
              _selectMode(entry.kind);
            } else {
              setState(() {
                _kind = entry.kind;
                _browsing = true;
                _focused = 0;
              });
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

  Widget _panel() => DefaultTextStyle.merge(
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 12,
              color: _foreground,
            ),
        child: SizedBox(
          key: const ValueKey('agent-mention-panel'),
          width: _width,
          height: _height,
          child: Focus(
            onKeyEvent: _key,
            child: Row(
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
                                    prefixIcon: Icon(Icons.search, size: 14),
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
                                constraints: const BoxConstraints.tightFor(
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
                            padding: const EdgeInsets.symmetric(horizontal: 5),
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
                          padding: const EdgeInsets.symmetric(vertical: 7),
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
                    _showModes ? _modeDetails() : _referenceList(),
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

  Widget _referenceList() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _kind == null
                      ? '搜索结果'
                      : _categories
                          .firstWhere((entry) => entry.kind == _kind)
                          .label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '选择资料，添加到当前问题',
                  style: TextStyle(
                    fontSize: 10,
                    color: _foreground.withValues(alpha: .45),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: _foreground.withValues(alpha: .06)),
          Expanded(
            child: _loading
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
                    : _list(),
          ),
        ],
      );

  Widget _list() {
    final items = _filtered;
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            _search.text.isEmpty ? '暂无可引用的资料' : '没有找到匹配的资料',
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
    final references = [
      for (final reference in widget.selected)
        InputChip(
          avatar: Icon(
            _categories.firstWhere((c) => c.kind == reference.kind).icon,
            size: 16,
          ),
          label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(reference.name, overflow: TextOverflow.ellipsis),
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
    ];
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
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  widget.child,
                  if (references.isNotEmpty)
                    Wrap(spacing: 6, runSpacing: 4, children: references),
                ],
              ),
              referenceButton,
            ) ??
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                widget.child,
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  children: [
                    referenceButton,
                    ...references,
                  ],
                ),
              ],
            ),
      ),
    );
  }
}

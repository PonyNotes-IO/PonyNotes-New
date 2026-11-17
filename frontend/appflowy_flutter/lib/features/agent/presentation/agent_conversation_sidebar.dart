import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/agent_conversations.dart';

class AgentConversationSidebar extends StatefulWidget {
  const AgentConversationSidebar({
    super.key,
    required this.entries,
    required this.selectedId,
    required this.loading,
    required this.enabled,
    required this.error,
    required this.onOpen,
    required this.onCreate,
    required this.onRefresh,
    required this.footer,
  });

  final List<AgentConversation> entries;
  final String? selectedId;
  final bool loading;
  final bool enabled;
  final String? error;
  final ValueChanged<AgentConversation> onOpen;
  final ValueChanged<AgentConversationVisibility> onCreate;
  final VoidCallback onRefresh;
  final Widget footer;

  @override
  State<AgentConversationSidebar> createState() =>
      _AgentConversationSidebarState();
}

class _AgentConversationSidebarState extends State<AgentConversationSidebar> {
  bool personalExpanded = true;
  bool membersExpanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final foreground = theme.textColorScheme.primary;
    final muted = foreground.withValues(alpha: .5);
    final privateEntries =
        widget.entries.where((entry) => !entry.shared).toList();
    final sharedEntries =
        widget.entries.where((entry) => entry.shared).toList();

    return Material(
      color: theme.surfaceColorScheme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '小马笔记AI',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: foreground,
                    ),
                  ),
                ),
                _action(
                  tooltip: '刷新会话',
                  icon: Icons.refresh,
                  onPressed: widget.enabled ? widget.onRefresh : null,
                  color: muted,
                ),
              ],
            ),
          ),
          if (widget.loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  sliver: SliverToBoxAdapter(
                    child: _section(
                      title: '私有对话',
                      expanded: personalExpanded,
                      onToggle: () => setState(
                        () => personalExpanded = !personalExpanded,
                      ),
                      trailing: _action(
                        tooltip: '新建对话',
                        icon: Icons.add,
                        onPressed: widget.enabled
                            ? () {
                                setState(() => personalExpanded = true);
                                widget.onCreate(
                                  AgentConversationVisibility.private,
                                );
                              }
                            : null,
                        color: muted,
                      ),
                    ),
                  ),
                ),
                if (widget.error != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                      child: Text(
                        '会话加载失败：${widget.error}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                if (personalExpanded)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    sliver: privateEntries.isEmpty
                        ? SliverToBoxAdapter(
                            child: widget.loading
                                ? null
                                : _empty('还没有对话\n点击 + 开始新对话'),
                          )
                        : SliverList.builder(
                            itemCount: privateEntries.length,
                            itemBuilder: (_, i) =>
                                _conversation(privateEntries[i]),
                          ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _section(
                          title: '协作对话',
                          expanded: membersExpanded,
                          onToggle: () => setState(
                            () => membersExpanded = !membersExpanded,
                          ),
                          trailing: _action(
                            tooltip: '新建协作对话',
                            icon: Icons.add,
                            onPressed: widget.enabled
                                ? () {
                                    setState(() => membersExpanded = true);
                                    widget.onCreate(
                                      AgentConversationVisibility.shared,
                                    );
                                  }
                                : null,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (membersExpanded)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
                    sliver: sharedEntries.isEmpty
                        ? SliverToBoxAdapter(child: _empty('暂无协作对话'))
                        : SliverList.builder(
                            itemCount: sharedEntries.length,
                            itemBuilder: (_, i) =>
                                _conversation(sharedEntries[i]),
                          ),
                  ),
              ],
            ),
          ),
          widget.footer,
        ],
      ),
    );
  }

  Widget _section({
    required String title,
    required bool expanded,
    required VoidCallback onToggle,
    Widget? trailing,
  }) {
    final muted =
        AppFlowyTheme.of(context).textColorScheme.primary.withValues(alpha: .5);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            expanded: expanded,
            child: InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Row(
                  children: [
                    Text(title, style: TextStyle(fontSize: 11, color: muted)),
                    const SizedBox(width: 4),
                    Icon(
                      expanded ? Icons.expand_more : Icons.chevron_right,
                      size: 14,
                      color: muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 5, 8, 8),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            height: 1.8,
            color: AppFlowyTheme.of(context)
                .textColorScheme
                .primary
                .withValues(alpha: .45),
          ),
        ),
      );

  Widget _conversation(AgentConversation entry) {
    final foreground = AppFlowyTheme.of(context).textColorScheme.primary;
    final selected = entry.id == widget.selectedId;
    return Material(
      color: selected ? foreground.withValues(alpha: .1) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => widget.onOpen(entry),
        borderRadius: BorderRadius.circular(8),
        child: Semantics(
          selected: selected,
          child: Padding(
            padding: EdgeInsets.only(
              left: 7,
              right: 2,
              top: entry.shared ? 4 : 0,
              bottom: entry.shared ? 4 : 0,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 16,
                  color: foreground.withValues(alpha: .6),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Tooltip(
                    message: entry.title,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            fontWeight:
                                selected ? FontWeight.w500 : FontWeight.w400,
                            color: foreground,
                          ),
                        ),
                        if (entry.shared && entry.creatorName.isNotEmpty)
                          Text(
                            '创建者：${entry.creatorName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              color: foreground.withValues(alpha: .6),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox.square(
                  dimension: 24,
                  child: PopupMenuButton<String>(
                    tooltip: '对话选项',
                    icon: Icon(
                      Icons.more_horiz,
                      size: 18,
                      color: foreground.withValues(alpha: .5),
                    ),
                    padding: EdgeInsets.zero,
                    onSelected: (_) => Clipboard.setData(
                      ClipboardData(text: entry.title),
                    ),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'copy',
                        child: Text('复制标题'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _action({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    required Color color,
  }) =>
      IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        constraints: const BoxConstraints.tightFor(width: 24, height: 24),
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: Icon(icon, size: icon == Icons.add ? 18 : 14, color: color),
      );
}

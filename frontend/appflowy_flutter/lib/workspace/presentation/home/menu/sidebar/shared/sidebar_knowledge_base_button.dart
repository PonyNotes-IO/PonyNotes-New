import 'dart:async';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/plugins/database/calendar/application/calendar_unsaved_guard.dart';
import 'package:appflowy/plugins/knowledge_base/knowledge_base_cubit.dart';
import 'package:appflowy/plugins/knowledge_base/knowledge_base_service.dart';
import 'package:appflowy/plugins/knowledge_base/knowledge_base_web_import_dialog.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_entry_style.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/widget/mouse_hover_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

class SidebarKnowledgeBaseButton extends StatefulWidget {
  const SidebarKnowledgeBaseButton({super.key});

  @override
  State<SidebarKnowledgeBaseButton> createState() =>
      _SidebarKnowledgeBaseButtonState();
}

class _SidebarKnowledgeBaseButtonState
    extends State<SidebarKnowledgeBaseButton> {
  bool _expanded = false;
  final _expandedCategories = <KnowledgeBaseCategory>{};
  KnowledgeBaseCategory? _selectedCategory;
  String? _addingToBaseId;

  KnowledgeBaseCubit get _cubit => context.read<KnowledgeBaseCubit>();

  void _open(Object? target, {bool dataSources = false}) =>
      CalendarUnsavedGuard.instance.maybeConfirmLeave(context, () {
        if (!mounted) return;
        _cubit.dataSourceBaseId.value =
            dataSources && target is KnowledgeBase ? target.id : null;
        context.read<TabsBloc>().add(
              TabsEvent.openPlugin(
                plugin: makePlugin(
                  pluginType: PluginType.knowledgeBase,
                  data: target,
                ),
              ),
            );
      });

  Future<void> _create(KnowledgeBaseCategory category) async {
    final workspace = context.read<UserWorkspaceBloc>().state.currentWorkspace;
    if (workspace == null) return;
    final cubit = _cubit;
    final base = await showDialog<KnowledgeBase>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CreateKnowledgeBaseDialog(
        service: cubit.service,
        workspaceId: workspace.workspaceId,
        category: category,
      ),
    );
    if (base == null || !mounted || cubit.isClosed) return;
    setState(() => _expandedCategories.add(category));
    await cubit.load();
    if (mounted) _open(base);
  }

  @override
  Widget build(BuildContext context) {
    final style = sidebarEntryTextStyle(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AFGhostIconTextButton.primary(
          text: kbText(context, '知识库', 'Knowledge bases'),
          showExpandArrow: true,
          isExpanded: _expanded,
          mainAxisAlignment: MainAxisAlignment.start,
          padding: sidebarEntryPadding,
          textStyle: style,
          borderRadius: AppFlowyTheme.of(context).borderRadius.s,
          iconTextGap: sidebarEntryIconTextGap,
          iconBuilder: (_, __, ___) =>
              Icon(Icons.menu_book_outlined, size: 18, color: style.color),
          onTap: () {
            setState(() {
              _expanded = !_expanded;
              _selectedCategory = null;
            });
            if (_expanded) unawaited(_cubit.load());
            _open(null);
          },
        ),
        if (_expanded)
          BlocBuilder<KnowledgeBaseCubit, AsyncSnapshot<List<KnowledgeBase>>>(
            builder: (context, state) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final category in KnowledgeBaseCategory.values)
                  _category(category, state),
              ],
            ),
          ),
      ],
    );
  }

  Widget _category(
    KnowledgeBaseCategory category,
    AsyncSnapshot<List<KnowledgeBase>> state,
  ) {
    final style = sidebarEntryTextStyle(context).copyWith(fontSize: 13);
    final expanded = _expandedCategories.contains(category);
    final selected = _selectedCategory == category;
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: selected
                  ? AppFlowyTheme.of(context).fillColorScheme.contentHover
                  : null,
              borderRadius: BorderRadius.circular(
                AppFlowyTheme.of(context).borderRadius.s,
              ),
            ),
            child: MouseHoverBuilder(
              builder: (context, isHovered) => Row(
                children: [
                  Expanded(
                    child: Semantics(
                      expanded: expanded,
                      child: AFGhostIconTextButton.primary(
                        key: ValueKey(
                          'knowledge-base-category-${category.name}',
                        ),
                        text: category.label(context),
                        showExpandArrow: true,
                        isExpanded: expanded,
                        mainAxisAlignment: MainAxisAlignment.start,
                        padding: sidebarEntryPadding,
                        textStyle: style,
                        borderRadius: AppFlowyTheme.of(context).borderRadius.s,
                        iconTextGap: sidebarEntryIconTextGap,
                        iconBuilder: (_, __, ___) =>
                            Icon(category.icon, size: 16, color: style.color),
                        onTap: () {
                          setState(() {
                            _selectedCategory = category;
                            if (expanded) {
                              _expandedCategories.remove(category);
                            } else {
                              _expandedCategories.add(category);
                            }
                          });
                          _open(category);
                        },
                      ),
                    ),
                  ),
                  if (isHovered && category != KnowledgeBaseCategory.favorites)
                    IconButton(
                      key: ValueKey('knowledge-base-create-${category.name}'),
                      tooltip: kbText(
                        context,
                        '创建${category.label(context)}',
                        'Create ${category == KnowledgeBaseCategory.private ? 'private' : 'shared'} knowledge base',
                      ),
                      constraints: const BoxConstraints.tightFor(
                        width: 28,
                        height: 28,
                      ),
                      style: IconButton.styleFrom(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      padding: EdgeInsets.zero,
                      icon: Icon(Icons.add, size: 16, color: style.color),
                      onPressed: () => _create(category),
                    ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: _bases(category, state),
            ),
        ],
      ),
    );
  }

  Widget _bases(
    KnowledgeBaseCategory category,
    AsyncSnapshot<List<KnowledgeBase>> state,
  ) {
    if (state.connectionState == ConnectionState.waiting) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (state.hasError) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(kbError(context, state.error)),
          TextButton(
            onPressed: () => _cubit.load(),
            child: Text(kbText(context, '重试', 'Retry')),
          ),
        ],
      );
    }
    final bases = (state.data ?? []).where(category.includes).toList();
    final style = sidebarEntryTextStyle(context).copyWith(fontSize: 13);
    if (bases.isEmpty) {
      return Padding(
        padding: sidebarEntryPadding,
        child: Text(
          kbText(context, '暂无知识库', 'No knowledge bases'),
          style: style.copyWith(
            color: AppFlowyTheme.of(context).textColorScheme.tertiary,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final base in bases)
          MouseHoverBuilder(
            builder: (context, isHovered) => Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: base.name,
                    child: AFGhostIconTextButton.primary(
                      key: ValueKey(
                        'knowledge-base-${category.name}-${base.id}',
                      ),
                      text: base.name,
                      mainAxisAlignment: MainAxisAlignment.start,
                      padding: sidebarEntryPadding,
                      textStyle: style,
                      borderRadius: AppFlowyTheme.of(context).borderRadius.s,
                      iconTextGap: sidebarEntryIconTextGap,
                      iconBuilder: (_, __, ___) => Icon(
                        Icons.menu_book_outlined,
                        size: 16,
                        color: style.color,
                      ),
                      onTap: () => _open(base),
                    ),
                  ),
                ),
                if (isHovered || _addingToBaseId == base.id)
                  SizedBox.square(
                    dimension: 28,
                    child: PopupMenuButton<String>(
                      key: ValueKey(
                        'knowledge-base-add-${category.name}-${base.id}',
                      ),
                      tooltip: kbText(context, '添加资料', 'Add content'),
                      padding: EdgeInsets.zero,
                      position: PopupMenuPosition.under,
                      icon: Icon(Icons.add, size: 16, color: style.color),
                      onOpened: () => setState(() => _addingToBaseId = base.id),
                      onCanceled: () => setState(() => _addingToBaseId = null),
                      onSelected: (action) async {
                        setState(() => _addingToBaseId = null);
                        if (action == 'Link data source') {
                          _open(base, dataSources: true);
                          return;
                        }
                        if (action != 'Import web page') return;
                        final cubit = _cubit;
                        final imported = await showDialog<bool>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => KnowledgeBaseWebImportDialog(
                            base: base,
                            service: cubit.service,
                          ),
                        );
                        if (imported != true || !mounted || cubit.isClosed) {
                          return;
                        }
                        await cubit.load();
                        if (mounted) _open(base);
                      },
                      itemBuilder: (context) => [
                        for (final (zh, en) in const [
                          ('选择笔记', 'Select notes'),
                          ('上传文件', 'Upload files'),
                          ('上传文件夹', 'Upload folder'),
                          ('导入网页', 'Import web page'),
                          ('在线编辑', 'Edit online'),
                          ('链接数据源', 'Link data source'),
                        ])
                          PopupMenuItem(
                            value: en,
                            enabled: en != 'Link data source' || base.canManage,
                            height: 32,
                            child: Text(
                              kbText(context, zh, en),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CreateKnowledgeBaseDialog extends StatefulWidget {
  const _CreateKnowledgeBaseDialog({
    required this.service,
    required this.workspaceId,
    required this.category,
  });

  final KnowledgeBaseService service;
  final String workspaceId;
  final KnowledgeBaseCategory category;

  @override
  State<_CreateKnowledgeBaseDialog> createState() =>
      _CreateKnowledgeBaseDialogState();
}

class _CreateKnowledgeBaseDialogState
    extends State<_CreateKnowledgeBaseDialog> {
  final _name = TextEditingController();
  String? _requestId;
  String? _requestName;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (_saving || name.isEmpty) return;
    if (_requestName != name) {
      _requestName = name;
      _requestId = const Uuid().v4();
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final data = await widget.service.post('create', {
        'workspace_id': widget.workspaceId,
        'name': name,
        'visibility': widget.category.name,
        'request_id': _requestId,
      });
      final base = KnowledgeBase.fromJson(data['base'] as Map<String, dynamic>);
      if (mounted) Navigator.of(context).pop(base);
    } catch (error) {
      if (mounted) setState(() => _error = kbError(context, error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: AlertDialog(
          title: Text(
            kbText(
              context,
              '创建${widget.category.label(context)}',
              'Create ${widget.category == KnowledgeBaseCategory.private ? 'private' : 'shared'} knowledge base',
            ),
          ),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _name,
                  autofocus: true,
                  enabled: !_saving,
                  maxLength: 100,
                  decoration: InputDecoration(
                    labelText: kbText(context, '知识库名称', 'Knowledge base name'),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: Text(kbText(context, '取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: _saving || _name.text.trim().isEmpty ? null : _submit,
              child: Text(
                _saving
                    ? kbText(context, '创建中…', 'Creating…')
                    : kbText(context, '创建', 'Create'),
              ),
            ),
          ],
        ),
      );
}

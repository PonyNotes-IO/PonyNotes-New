import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/plugins/knowledge_base/knowledge_base_cubit.dart';
import 'package:appflowy/plugins/knowledge_base/knowledge_base_contents.dart';
import 'package:appflowy/plugins/knowledge_base/knowledge_base_service.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class KnowledgeBasePage extends StatelessWidget {
  const KnowledgeBasePage({super.key, required this.category});
  final KnowledgeBaseCategory? category;

  @override
  Widget build(BuildContext context) {
    final identity = context.select(
      (UserWorkspaceBloc bloc) => (
        bloc.state.userProfile.id.toString(),
        bloc.state.currentWorkspace?.workspaceId,
      ),
    );
    return BlocProvider(
      key: ValueKey(identity),
      create: (_) => KnowledgeBaseCubit(
        KnowledgeBaseService.forUser(identity.$1),
      )..load(),
      child: KnowledgeBaseView(
        category: category ?? KnowledgeBaseCategory.shared,
        currentWorkspaceId: category == null ? identity.$2 : null,
      ),
    );
  }
}

class KnowledgeBaseView extends StatefulWidget {
  const KnowledgeBaseView({
    super.key,
    required this.category,
    this.currentWorkspaceId,
  });
  final KnowledgeBaseCategory category;
  final String? currentWorkspaceId;

  @override
  State<KnowledgeBaseView> createState() => _KnowledgeBaseViewState();
}

class _KnowledgeBaseViewState extends State<KnowledgeBaseView> {
  late KnowledgeBaseCategory _category = widget.category;
  String _query = '';
  KnowledgeBase? _selected;
  bool _browsing = false;
  int _tab = 0;

  KnowledgeBaseCubit get _cubit => context.read<KnowledgeBaseCubit>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onBases(_cubit.state);
    });
  }

  void _onBases(AsyncSnapshot<List<KnowledgeBase>> state) {
    if (state.hasError) {
      setState(() => _selected = null);
      return;
    }
    if (!state.hasData) return;
    final bases = state.data!;
    final selected = bases
        .where((base) => base.workspaceId == _selected?.workspaceId)
        .firstOrNull;
    final initial = bases
        .where((base) => base.workspaceId == widget.currentWorkspaceId)
        .firstOrNull;
    setState(() {
      _selected = selected ??
          (_browsing || widget.currentWorkspaceId == null
              ? null
              : initial ?? bases.where(_category.includes).firstOrNull);
    });
  }

  void _open(KnowledgeBase base) => setState(() => _selected = base);

  void _back() => setState(() {
        _browsing = true;
        _selected = null;
      });

  @override
  Widget build(BuildContext context) =>
      BlocListener<KnowledgeBaseCubit, AsyncSnapshot<List<KnowledgeBase>>>(
        listener: (_, state) => _onBases(state),
        child: _selected != null
            ? KnowledgeBaseContents(
                key: ValueKey(_selected!.workspaceId),
                base: _selected!,
                onBack: _back,
                onRefreshBases: () => _cubit.load(),
                initialTab: _tab,
              )
            : Material(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: Row(
                  children: [
                    SizedBox(
                      key: const ValueKey('knowledge-base-middle-pane'),
                      width: knowledgeBaseMiddlePaneWidth,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.menu_book_outlined, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    kbText(context, '知识库', 'Knowledge bases'),
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                PopupMenuButton<KnowledgeBaseCategory>(
                                  tooltip: kbText(
                                    context,
                                    '知识库分类',
                                    'Knowledge base category',
                                  ),
                                  icon: const Icon(Icons.filter_list, size: 18),
                                  onSelected: (category) =>
                                      setState(() => _category = category),
                                  itemBuilder: (_) => [
                                    for (final category
                                        in KnowledgeBaseCategory.values)
                                      PopupMenuItem(
                                        value: category,
                                        child: Text(
                                          '${category.label(context)}  ${(_cubit.state.data ?? []).where(category.includes).length}',
                                        ),
                                      ),
                                  ],
                                ),
                                IconButton(
                                  tooltip: kbText(context, '刷新', 'Refresh'),
                                  onPressed: () => _cubit.load(),
                                  icon: const Icon(Icons.refresh, size: 18),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Expanded(
                              child: BlocBuilder<KnowledgeBaseCubit,
                                  AsyncSnapshot<List<KnowledgeBase>>>(
                                builder: (context, state) => _bases(state),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _message(
                        kbText(
                          context,
                          '选择知识库以查看文件、数据源、Wiki 和图谱。',
                          'Select a knowledge base to browse files, data sources, Wiki and graph.',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      );

  Widget _bases(AsyncSnapshot<List<KnowledgeBase>> state) {
    final bases = state.data ?? [];
    final filtered = bases
        .where(
          (base) =>
              _category.includes(base) &&
              base.name.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();
    return DefaultTabController(
      length: 3,
      initialIndex: _tab,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          knowledgeBaseTabs(
            context,
            onTap: (index) => setState(() => _tab = index),
          ),
          const SizedBox(height: 18),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 19),
                hintText:
                    kbText(context, '搜索知识库名称', 'Search knowledge base names'),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: state.connectionState == ConnectionState.waiting
                ? const Center(child: CircularProgressIndicator())
                : state.hasError
                    ? _message(
                        kbError(context, state.error),
                        retry: () => _cubit.load(),
                      )
                    : filtered.isEmpty
                        ? _message(_emptyMessage())
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, index) =>
                                _baseRow(filtered[index]),
                          ),
          ),
        ],
      ),
    );
  }

  String _emptyMessage() {
    if (_query.isNotEmpty) {
      return kbText(context, '没有匹配的知识库。', 'No matching knowledge bases.');
    }
    return switch (_category) {
      KnowledgeBaseCategory.private => kbText(
          context,
          '暂无私有知识库。可在你拥有的知识库菜单中设为私有。',
          'No private knowledge bases. Set a knowledge base you own to private from its menu.',
        ),
      KnowledgeBaseCategory.shared => kbText(
          context,
          '暂无共享知识库。工作空间的知识库设为共享后会显示在这里。',
          'No shared knowledge bases. Shared workspace knowledge bases appear here.',
        ),
      KnowledgeBaseCategory.favorites => kbText(
          context,
          '暂无最爱知识库。点击知识库旁的星标即可收藏。',
          'No favorites yet. Select the star beside a knowledge base to add one.',
        ),
    };
  }

  Widget _baseRow(KnowledgeBase base) {
    final private = base.visibility == 'private';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      minLeadingWidth: 0,
      horizontalTitleGap: 8,
      leading:
          Icon(private ? Icons.lock_outline : Icons.people_outline, size: 18),
      title: Text(
        base.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(
        [
          kbText(context, '工作空间知识库', 'Workspace knowledge base'),
          private
              ? kbText(context, '仅所有者可见', 'Owner only')
              : kbText(context, '空间成员可见', 'Workspace members'),
          if (!base.ready) kbText(context, '等待同步', 'Awaiting sync'),
        ].join(' · '),
        style: const TextStyle(fontSize: 11),
      ),
      onTap: () => _open(base),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            constraints: const BoxConstraints.tightFor(width: 30, height: 32),
            padding: EdgeInsets.zero,
            iconSize: 18,
            tooltip: base.isFavorite
                ? kbText(context, '取消最爱', 'Remove favorite')
                : kbText(context, '加入最爱', 'Add favorite'),
            icon: Icon(
              base.isFavorite ? Icons.star : Icons.star_border,
              color: base.isFavorite ? const Color(0xFFD99A23) : null,
            ),
            onPressed: () => _cubit.load(
              action: 'favorite',
              payload: {
                'workspace_id': base.workspaceId,
                'is_favorite': !base.isFavorite,
              },
            ),
          ),
          if (base.canManage)
            PopupMenuButton<String>(
              constraints: const BoxConstraints(minWidth: 200),
              padding: EdgeInsets.zero,
              iconSize: 18,
              tooltip: kbText(context, '知识库权限', 'Knowledge base access'),
              icon: const Icon(Icons.more_horiz, size: 20),
              onSelected: (value) => _cubit.load(
                action: 'visibility',
                payload: {
                  'workspace_id': base.workspaceId,
                  'visibility': value,
                },
              ),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: private ? 'shared' : 'private',
                  child: Text(
                    private
                        ? kbText(
                            context,
                            '设为共享（空间成员可见）',
                            'Share with workspace members',
                          )
                        : kbText(
                            context,
                            '设为私有（仅自己可见）',
                            'Make private (owner only)',
                          ),
                  ),
                ),
              ],
            )
          else
            const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _message(String message, {VoidCallback? retry}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.menu_book_outlined,
                size: 34,
                color: Colors.grey,
              ),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              if (retry != null) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: retry,
                  child: Text(kbText(context, '重试', 'Retry')),
                ),
              ],
            ],
          ),
        ),
      );
}

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/features/shared_section/presentation/m_shared_section.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/application/mobile_router.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/bottom_sheet.dart';
import 'package:appflowy/mobile/presentation/home/space/mobile_create_space_sheet.dart';
import 'package:appflowy/mobile/presentation/home/space/mobile_space_menu.dart';
import 'package:appflowy/mobile/presentation/home/space/mobile_space_list_refresh.dart';
import 'package:appflowy/mobile/presentation/home/space/space_change_notifier.dart';
import 'package:appflowy/mobile/presentation/page_item/mobile_view_item.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/shared/list_extension.dart';
import 'package:appflowy/util/theme_extension.dart';
import 'package:appflowy/workspace/application/favorite/favorite_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/folder/folder_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/space_icon.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:async';
import 'dart:io' show Platform;

class MobileSpace extends StatefulWidget {
  const MobileSpace({super.key, required this.favoriteBloc});

  final FavoriteBloc favoriteBloc;

  @override
  State<MobileSpace> createState() => _MobileSpaceState();
}

class _MobileSpaceState extends State<MobileSpace> {
  @override
  void initState() {
    super.initState();
    // 当其他组件（例如空间管理页）创建/删除/修改了协作区，
    // 通过全局 notifier 通知首页重新拉取 SpaceBloc。
    SpaceChangeNotifier.instance.addListener(_onNotifierFire);
  }

  @override
  void dispose() {
    SpaceChangeNotifier.instance.removeListener(_onNotifierFire);
    super.dispose();
  }

  void _onNotifierFire() {
    // 把 notifier 当前携带的新创建 space（如果有）传给 refresh。
    final pending = SpaceChangeNotifier.instance.lastCreatedSpace;
    _refreshSpace(newSpaceFromNotifier: pending);
  }

  void _refreshSpace({ViewPB? newSpaceFromNotifier}) {
    if (!mounted) return;
    try {
      final spaceBloc = context.read<SpaceBloc>();

      // 关键修复：如果 notifier 传来了刚刚创建的新 space（带 viewId
      // + name + icon + permission 等元数据，已经 backend 返回），我们
      // 直接派发 SpaceEvent.upsertSpaces 让 SpaceBloc 把它合并到
      // state.spaces，不等 backend `getPublicViews` 缓存同步。
      //
      // 后端 cache 在创建后可能有秒级滞后，listener `DidUpdateSectionViews`
      // 也不一定每次都触发，所以兜底方案是直接 push。
      if (newSpaceFromNotifier != null) {
        spaceBloc.add(SpaceEvent.upsertSpaces(spaces: [newSpaceFromNotifier]));
      }

      // 先让 upsertSpaces 完成，再触发 initial。
      // 这样 initial 执行时 collab 可能还没同步，但因为 state 里已经有
      // newSpace 了，_mergeWithLocalPendingSpaces 会保护它。
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!mounted) return;
        try {
          final sb = context.read<SpaceBloc>();
          sb.add(const SpaceEvent.initial(openFirstPage: false));
        } catch (_) {}
      });

      // 2s 后再补一次 dispatch（collab sync 可能比较慢）。
      Future.delayed(const Duration(milliseconds: 2000), () {
        if (!mounted) return;
        try {
          final sb = context.read<SpaceBloc>();
          sb.add(const SpaceEvent.initial(openFirstPage: false));
        } catch (_) {}
      });

      // 关键修复：backend `getPublicViews` 缓存和 `DidUpdateSectionViews`
      // 通知可能在我们 dispatch upsertSpaces 之后**晚于 2s 才到达**，把
      // 刚合并的新 space 又覆盖回旧数据。`SpaceBloc` 是 desktop 端共用的，
      // 我们不该改它的核心 handler；这里在 mobile 端本地轮询：每次
      // SpaceBloc state 变化后，如果 backend 还没同步 new space 且
      // notifier 还缓存着，就**再次派发 upsertSpaces**。
      if (newSpaceFromNotifier != null) {
        _guardNewSpace(
          spaceBloc: spaceBloc,
          newSpace: newSpaceFromNotifier,
          // 持续 8s，足够 backend cache 同步
          duration: const Duration(seconds: 8),
        );
      }
    } catch (_) {}
  }

  /// 在 [duration] 内监听 [spaceBloc]，如果 backend 的 `initial` 或
  /// `didReceiveSpaceUpdate` 把 [newSpace] 覆盖掉了，就重新 push 一次。
  /// 仅 mobile 端生效，不影响 SpaceBloc 的核心行为。
  ///
  /// 关闭策略：
  ///   1. 启动后先观察一个**最小保护窗口**（2s），避免太早关闭。
  ///   2. 窗口过后，每次 emit 都判断：state.spaces 中仍包含 newSpace，
  ///      且 **lastBackendSyncCount > 0**（说明至少发生了一次 backend
  ///      同步覆盖事件），才认为 backend 已同步完成 → 关闭 guard。
  ///   3. 超时（duration）兜底关闭。
  void _guardNewSpace({
    required SpaceBloc spaceBloc,
    required ViewPB newSpace,
    required Duration duration,
  }) {
    DateTime? lastRescueAt;
    bool isClosed = false;
    late final StreamSubscription<SpaceState> sub;
    final start = DateTime.now();
    const minProtectWindow = Duration(seconds: 2);
    // 自 guard 启动以来观察到 state.spaces 数量**减少**的次数（说明有
    // backend 同步事件发生）。只有这个 > 0 之后，我们才允许关闭 guard。
    int backendSyncCount = 0;
    int? lastSpacesCount;

    void maybeRescue(SpaceState current) {
      if (isClosed) return;
      final elapsed = DateTime.now().difference(start);
      final hasIt = current.spaces.any((s) => s.id == newSpace.id);

      // 检测 backend 同步覆盖：state.spaces 数量比上次的观察值少
      // （说明 backend 拉取结果覆盖了之前的合并值）。
      if (lastSpacesCount != null && current.spaces.length < lastSpacesCount!) {
        backendSyncCount++;
      }
      lastSpacesCount = current.spaces.length;

      // 最小保护窗口 + 看到 backend 同步 + 同步后 state 仍包含 newSpace
      // → 关闭
      if (hasIt && elapsed >= minProtectWindow && backendSyncCount > 0) {
        isClosed = true;
        sub.cancel();
        return;
      }

      // 没同步 → 重新派发 upsertSpaces（throttle 200ms）
      final now = DateTime.now();
      if (lastRescueAt != null &&
          now.difference(lastRescueAt!) < const Duration(milliseconds: 200)) {
        return;
      }
      lastRescueAt = now;
      spaceBloc.add(SpaceEvent.upsertSpaces(spaces: [newSpace]));
    }

    sub = spaceBloc.stream.listen(maybeRescue);
    // 兜底：超时后停止监听（即使 backend 还没同步）
    Future.delayed(duration, () {
      if (!isClosed) {
        isClosed = true;
        sub.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SpaceBloc, SpaceState>(
      builder: (context, state) {
        if (state.spaces.isEmpty) {
          return const SizedBox.shrink();
        }

        final spaceBloc = context.read<SpaceBloc>();
        final privateSpaces = spaceBloc.privateSpaces;
        final publicSpaces = spaceBloc.publicSpaces;
        final isCollaborativeWorkspace =
            context.read<UserWorkspaceBloc>().state.isCollabWorkspaceOn;
        final workspaceId = context
                .read<UserWorkspaceBloc>()
                .state
                .currentWorkspace
                ?.workspaceId ??
            '';

        return Column(
          children: [
            if (isCollaborativeWorkspace) ...[
              // 私有空间（仅 Space）
              MobileSpaceSection(
                title: LocaleKeys.space_privateSpace.tr(),
                spaces: privateSpaces,
                spaceType: FolderSpaceType.private,
                onAddPressed: () => _showCreateSpaceBottomSheet(
                  context,
                  permission: SpacePermission.private,
                  title: '新建私有空间',
                ),
                favoriteBloc: widget.favoriteBloc,
              ),
              const VSpace(4.0),
              // 协作区 / 公共空间（仅 Space）
              MobileSpaceSection(
                title: LocaleKeys.sideBar_workspace.tr(),
                spaces: publicSpaces,
                spaceType: FolderSpaceType.public,
                onAddPressed: () => _showCreateSpaceBottomSheet(context),
                favoriteBloc: widget.favoriteBloc,
              ),
              const VSpace(4.0),
              MSharedSection(
                key: ValueKey(workspaceId),
                workspaceId: workspaceId,
              ),
            ] else ...[
              // 非协作工作区：个人空间仅使用公共空间中的 Space
              MobileSpaceSection(
                title: LocaleKeys.space_mySpace.tr(),
                spaces: publicSpaces,
                spaceType: FolderSpaceType.public,
                onAddPressed: () => _showCreateSpaceBottomSheet(
                  context,
                  title: LocaleKeys.space_createSpace.tr(),
                ),
                favoriteBloc: widget.favoriteBloc,
              ),
            ],
          ],
        );
      },
    );
  }

  void _showCreatePageMenu(BuildContext context, ViewPB space) {
    final title = space.name;
    showMobileBottomSheet(
      context,
      showHeader: true,
      title: title,
      showDragHandle: true,
      showCloseButton: true,
      useRootNavigator: true,
      showDivider: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) {
        return AddNewPageWidgetBottomSheet(
          view: space,
          onAction: (layout, {String? name, String? extra}) {
            Navigator.of(sheetContext).pop();
            final spaceBloc = context.read<SpaceBloc>();
            void createPage() {
              spaceBloc.add(
                SpaceEvent.createPage(
                  name: name ?? layout.defaultName,
                  layout: layout,
                  index: 0,
                  openAfterCreate: true,
                  extra: extra,
                ),
              );
              spaceBloc.add(SpaceEvent.expand(space, true));
            }

            if (spaceBloc.state.currentSpace?.id == space.id) {
              createPage();
            } else {
              spaceBloc.add(
                SpaceEvent.open(space: space, afterOpen: createPage),
              );
            }
          },
        );
      },
    );
  }

  void _showCreateSpaceBottomSheet(
    BuildContext context, {
    SpacePermission permission = SpacePermission.publicToAll,
    String? title,
  }) {
    // 与桌面端 sidebar 的 "+" 行为对齐：调 `SpaceBloc.create` 让新 space
    // 进入 home 的 SpaceBloc.state.spaces (而不是创建新的工作空间)。
    // 新 space 由 SpaceBloc 内部 `_onCreate` 触发 emit，本页
    // `BlocBuilder<SpaceBloc>` 立刻 rebuild，无需 notifier 桥接。
    final spaceBloc = context.read<SpaceBloc>();
    showMobileBottomSheet(
      context,
      showDragHandle: true,
      showHeader: true,
      title: title ?? LocaleKeys.space_createSpace.tr(),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      // 让外层 sheet 用 Flexible(SingleChildScrollView) 包住我们，
      // 避免键盘弹起时外层 Column overflow。
      enableScrollable: true,
      builder: (_) => MobileCreateSpaceSheet(
        spaceBloc: spaceBloc,
        initialPermission: permission,
        nameHint: LocaleKeys.space_spaceName.tr(),
        onCreated: () {
          // Sheet 内部已经 pop 过了；这里只做 toast（如需要）。
        },
      ),
    );
  }
}

class MobileSpaceSection extends StatelessWidget {
  const MobileSpaceSection({
    super.key,
    required this.title,
    required this.spaces,
    required this.spaceType,
    required this.onAddPressed,
    required this.favoriteBloc,
  });

  final String title;
  final List<ViewPB> spaces;
  final FolderSpaceType spaceType;
  final VoidCallback onAddPressed;
  final FavoriteBloc favoriteBloc;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<FolderBloc>(
      create: (context) =>
          FolderBloc(type: spaceType)..add(const FolderEvent.initial()),
      child: BlocBuilder<FolderBloc, FolderState>(
        builder: (context, state) {
          final borderColor = Theme.of(context).isLightMode
              ? const Color(0xFFE9E9EC)
              : const Color(0x1AFFFFFF);

          return Column(
            children: [
              MobileSpaceSectionHeader(
                title: title,
                isExpanded: state.isExpanded,
                onPressed: () => context
                    .read<FolderBloc>()
                    .add(const FolderEvent.expandOrUnExpand()),
                onAdded: onAddPressed,
              ),
              if (state.isExpanded)
                Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: HomeSpaceViewSizes.mHorizontalPadding,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor, width: 0.5),
                  ),
                  child: Column(
                    children: [
                      for (int i = 0; i < spaces.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 0.5,
                            thickness: 0.5,
                            color: borderColor,
                            indent: HomeSpaceViewSizes.mHorizontalPadding,
                            endIndent: HomeSpaceViewSizes.mHorizontalPadding,
                          ),
                        MobileSpaceItem(
                          key: ValueKey(spaces[i].id),
                          space: spaces[i],
                          favoriteBloc: favoriteBloc,
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class MobileSpaceSectionHeader extends StatefulWidget {
  const MobileSpaceSectionHeader({
    super.key,
    required this.title,
    required this.onPressed,
    required this.onAdded,
    required this.isExpanded,
  });

  final String title;
  final VoidCallback onPressed;
  final VoidCallback onAdded;
  final bool isExpanded;

  @override
  State<MobileSpaceSectionHeader> createState() =>
      _MobileSpaceSectionHeaderState();
}

class _MobileSpaceSectionHeaderState extends State<MobileSpaceSectionHeader> {
  double _turns = 0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          const HSpace(HomeSpaceViewSizes.mHorizontalPadding),
          Expanded(
            child: FlowyButton(
              text: FlowyText.medium(
                widget.title,
                lineHeight: 1.15,
                fontSize: 16.0,
              ),
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 2.0),
              expandText: false,
              iconPadding: 2,
              mainAxisAlignment: MainAxisAlignment.start,
              rightIcon: AnimatedRotation(
                duration: const Duration(milliseconds: 200),
                turns: _turns,
                child: const FlowySvg(
                  FlowySvgs.m_spaces_expand_s,
                ),
              ),
              onTap: () {
                setState(() {
                  _turns = widget.isExpanded ? -0.25 : 0;
                });
                widget.onPressed();
              },
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onAdded,
            child: Container(
              margin: const EdgeInsets.symmetric(
                horizontal: HomeSpaceViewSizes.mHorizontalPadding,
                vertical: 8.0,
              ),
              child: const FlowySvg(
                FlowySvgs.m_space_add_s,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MobileSpaceItem extends StatefulWidget {
  const MobileSpaceItem({
    super.key,
    required this.space,
    required this.favoriteBloc,
  });

  final ViewPB space;
  final FavoriteBloc favoriteBloc;

  @override
  State<MobileSpaceItem> createState() => _MobileSpaceItemState();
}

class _MobileSpaceItemState extends State<MobileSpaceItem> {
  late bool _isExpanded;
  double _turns = 0;
  ViewListener? _spaceListener;
  int _documentListRevision = 0;
  int _consumedMoveRefreshRevision = 0;

  @override
  void initState() {
    super.initState();
    _isExpanded = true;
    MobileSpaceListRefreshNotifier.instance.addListener(
      _consumeMoveRefresh,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumeMoveRefresh();
    });
    if (Platform.isIOS) {
      SpaceChangeNotifier.instance.addListener(_onTrashRestore);
    }
    _startSpaceListener();
  }

  @override
  void didUpdateWidget(covariant MobileSpaceItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.space.id == widget.space.id) {
      return;
    }
    _spaceListener?.stop();
    _spaceListener = null;
    _consumedMoveRefreshRevision = 0;
    _startSpaceListener();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumeMoveRefresh();
    });
  }

  @override
  void dispose() {
    MobileSpaceListRefreshNotifier.instance.removeListener(
      _consumeMoveRefresh,
    );
    if (Platform.isIOS) {
      SpaceChangeNotifier.instance.removeListener(_onTrashRestore);
    }
    _spaceListener?.stop();
    super.dispose();
  }

  void _startSpaceListener() {
    if (!Platform.isIOS) {
      return;
    }
    _spaceListener = ViewListener(viewId: widget.space.id)
      ..start(
        onViewDeleted: (result) {
          result.fold(
            (_) {
              if (mounted) setState(() => _documentListRevision++);
            },
            (_) {},
          );
        },
        onViewMoveToTrash: (_) {
          if (mounted) setState(() => _documentListRevision++);
        },
      );
  }

  void _consumeMoveRefresh() {
    if (!mounted) {
      return;
    }
    final revision = MobileSpaceListRefreshNotifier.instance.revisionFor(
      widget.space.id,
    );
    if (revision <= _consumedMoveRefreshRevision) {
      return;
    }
    _consumedMoveRefreshRevision = revision;
    Log.info(
      '[MobileSpace] 重新加载跨空间移动后的目标文档列表: '
      'space=${widget.space.id}, revision=$revision',
    );
    setState(() => _documentListRevision++);
  }

  void _onTrashRestore() {
    if (mounted) setState(() => _documentListRevision++);
  }

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
      _turns = _isExpanded ? 0 : -0.25;
    });
    context.read<SpaceBloc>().add(SpaceEvent.expand(widget.space, _isExpanded));
  }

  void _showCreatePageMenu() {
    final title = widget.space.name;
    showMobileBottomSheet(
      context,
      showHeader: true,
      title: title,
      showDragHandle: true,
      showCloseButton: true,
      useRootNavigator: true,
      showDivider: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) {
        return AddNewPageWidgetBottomSheet(
          view: widget.space,
          onAction: (layout, {String? name, String? extra}) {
            Navigator.of(sheetContext).pop();
            final spaceBloc = context.read<SpaceBloc>();
            void createPage() {
              spaceBloc.add(
                SpaceEvent.createPage(
                  name: name ?? layout.defaultName,
                  layout: layout,
                  index: 0,
                  openAfterCreate: true,
                  extra: extra,
                ),
              );
              spaceBloc.add(SpaceEvent.expand(widget.space, true));
            }

            if (spaceBloc.state.currentSpace?.id == widget.space.id) {
              createPage();
            } else {
              spaceBloc.add(
                SpaceEvent.open(space: widget.space, afterOpen: createPage),
              );
            }
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = Theme.of(context).isLightMode
        ? const Color(0xFFE9E9EC)
        : const Color(0x1AFFFFFF);

    return Column(
      children: [
        SizedBox(
          height: 48,
          child: Row(
            children: [
              const HSpace(HomeSpaceViewSizes.mHorizontalPadding),
              SpaceIcon(
                dimension: 28,
                textDimension: 18,
                cornerRadius: 8,
                space: widget.space,
                svgSize: 16,
              ),
              const HSpace(12),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _toggleExpand,
                  child: FlowyText.medium(
                    widget.space.name,
                    fontSize: 15,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              AnimatedRotation(
                duration: const Duration(milliseconds: 200),
                turns: _turns,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _toggleExpand,
                  child: const FlowySvg(
                    FlowySvgs.m_spaces_expand_s,
                  ),
                ),
              ),
              const HSpace(8),
              SpaceMenuItemTrailing(
                space: widget.space,
                currentSpace: null,
              ),
              const HSpace(8),
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _showCreatePageMenu,
                child: const FlowySvg(
                  FlowySvgs.m_space_add_s,
                ),
              ),
              const HSpace(HomeSpaceViewSizes.mHorizontalPadding),
            ],
          ),
        ),
        if (_isExpanded)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: BlocProvider(
              key: ValueKey('${widget.space.id} $_documentListRevision'),
              create: (context) => ViewBloc(
                view: widget.space,
                useNotificationViewUpdates: Platform.isIOS,
              )..add(const ViewEvent.initial()),
              child: BlocListener<SpaceBloc, SpaceState>(
                // Android keeps the 1.13 sequence list resident. Its ViewBloc
                // listener still applies create/delete/move/restore updates.
                listenWhen: (previous, current) =>
                    !mobileSpaceKeepsDocumentListCached(
                      isAndroid: Platform.isAndroid,
                    ) &&
                    previous.lastCreatedPage?.id !=
                        current.lastCreatedPage?.id &&
                    (current.lastCreatedPage?.parentViewId == widget.space.id ||
                        current.currentSpace?.id == widget.space.id),
                listener: (context, _) =>
                    context.read<ViewBloc>().reloadChildViews(),
                child: BlocBuilder<ViewBloc, ViewState>(
                  builder: (context, state) {
                    final spaceType = widget.space.spacePermission ==
                            SpacePermission.publicToAll
                        ? FolderSpaceType.public
                        : FolderSpaceType.private;
                    final childViews =
                        state.view.childViews.unique((view) => view.id);
                    if (childViews.length != state.view.childViews.length) {
                      final duplicatedViews = state.view.childViews
                          .where((view) => childViews.contains(view))
                          .toList();
                      Log.error(
                          'some view id are duplicated: $duplicatedViews');
                    }
                    return Column(
                      children: childViews.asMap().entries.map((entry) {
                        final index = entry.key;
                        final view = entry.value;
                        return Column(
                          children: [
                            if (index > 0)
                              Divider(
                                height: 0.5,
                                thickness: 0.5,
                                color: borderColor,
                              ),
                            MobileViewItem(
                              key: ValueKey(
                                '${widget.space.id} ${view.id}',
                              ),
                              spaceType: spaceType,
                              isFirstChild:
                                  view.id == state.view.childViews.first.id,
                              view: view,
                              level: 0,
                              leftPadding: HomeSpaceViewSizes.leftPadding,
                              isFeedback: false,
                              favoriteBloc: widget.favoriteBloc,
                              onSelected: (v) => context.pushView(
                                v,
                                tabs: [
                                  PickerTabType.emoji,
                                  PickerTabType.icon,
                                  PickerTabType.custom,
                                ].map((e) => e.name).toList(),
                              ),
                              endActionPane: (context) {
                                final view =
                                    context.read<ViewBloc>().state.view;
                                final actions = [
                                  MobilePaneActionType.more,
                                  if (view.layout == ViewLayoutPB.Document)
                                    MobilePaneActionType.add,
                                ];
                                return buildEndActionPane(
                                  context,
                                  actions,
                                  spaceType: spaceType,
                                  spaceRatio: actions.length == 1 ? 3 : 4,
                                );
                              },
                              onViewDuplicated: (duplicatedView) {
                                context
                                    .read<ViewBloc>()
                                    .insertDuplicatedView(duplicatedView);
                                if (duplicatedView.parentViewId !=
                                    widget.space.id) {
                                  try {
                                    context.read<SpaceBloc>().add(
                                          const SpaceEvent
                                              .didReceiveSpaceUpdate(),
                                        );
                                  } catch (_) {}
                                }
                              },
                            ),
                          ],
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}

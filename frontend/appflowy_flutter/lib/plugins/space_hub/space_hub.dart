library;

import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/util.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/sidebar/folder/folder_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/view_info/view_info_bloc.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_add_button.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_item.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/widgets/tab_bar_item.dart';
import 'package:appflowy/workspace/presentation/widgets/view_title_bar.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:appflowy/workspace/presentation/widgets/resizable_divider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// SpaceHubPluginBuilder 用于创建空间统一页面插件
/// 左侧显示空间下的文档/文件夹列表，右侧显示选中文档的详情
class SpaceHubPluginBuilder extends PluginBuilder {
  @override
  Plugin build(dynamic data) {
    if (data is ViewPB) {
      return SpaceHubPlugin(view: data);
    }
    throw FlowyPluginException.invalidData;
  }

  @override
  String get menuName => "空间";

  @override
  FlowySvgData get icon => FlowySvgs.folder_m;

  @override
  PluginType get pluginType => PluginType.folder; // 复用 folder 类型

  @override
  ViewLayoutPB? get layoutType => null; // 空间没有特定的 layoutType
}

class SpaceHubPlugin extends Plugin {
  SpaceHubPlugin({
    required this.view,
  })  : notifier = ViewPluginNotifier(view: view),
        _viewInfoBloc = ViewInfoBloc(view: view)..add(const ViewInfoEvent.started()),
        _pageAccessLevelBloc = PageAccessLevelBloc(view: view)..add(const PageAccessLevelEvent.initial()),
        _selectedViewNotifier = ValueNotifier<ViewPB?>(null);

  final ViewPB view;
  final ViewInfoBloc _viewInfoBloc;
  final PageAccessLevelBloc _pageAccessLevelBloc;
  final ValueNotifier<ViewPB?> _selectedViewNotifier;

  @override
  final ViewPluginNotifier notifier;

  @override
  PluginWidgetBuilder get widgetBuilder => SpaceHubPluginWidgetBuilder(
        bloc: _viewInfoBloc,
        pageAccessLevelBloc: _pageAccessLevelBloc,
        notifier: notifier,
        selectedViewNotifier: _selectedViewNotifier,
      );

  @override
  PluginType get pluginType => PluginType.folder;

  @override
  PluginId get id => notifier.view.id;

  @override
  void init() {
    // Blocs are already initialized in constructor
  }

  @override
  void dispose() {
    _viewInfoBloc.close();
    _pageAccessLevelBloc.close();
    _selectedViewNotifier.dispose();
    notifier.dispose();
  }
}

/// SpaceHubPluginWidgetBuilder 实现空间统一页面的布局
/// 左侧：空间文档列表，右侧：选中文档详情
class SpaceHubPluginWidgetBuilder extends PluginWidgetBuilder
    with NavigationItem {
  SpaceHubPluginWidgetBuilder({
    required this.bloc,
    required this.notifier,
    required this.pageAccessLevelBloc,
    required this.selectedViewNotifier,
  });

  final ViewInfoBloc bloc;
  final ViewPluginNotifier notifier;
  final PageAccessLevelBloc pageAccessLevelBloc;
  final ValueNotifier<ViewPB?> selectedViewNotifier;

  ViewPB get view => notifier.view;

  @override
  EdgeInsets get contentPadding => EdgeInsets.zero;

  @override
  Widget? get rightBarItem {
    // 当有选中文档时，返回该文档的右侧工具栏
    // 注意：ValueListenableBuilder 的 builder 不能返回 null，因此这里用 SizedBox.shrink 占位
    return ValueListenableBuilder<ViewPB?>(
      valueListenable: selectedViewNotifier,
      builder: (context, selectedView, _) {
        if (selectedView == null) {
          return const SizedBox.shrink();
        }

        try {
          final plugin = selectedView.plugin();
          plugin.init();
          final widgetBuilder = plugin.widgetBuilder;

          // PluginWidgetBuilder 已经 mixin 了 NavigationItem，直接访问 rightBarItem
          final toolbar = widgetBuilder.rightBarItem;
          if (toolbar != null) {
            return toolbar;
          }
        } catch (e) {
          debugPrint('[SpaceHub] Error getting rightBarItem for ${selectedView.name}: $e');
        }

        // 没有可用的工具栏时，返回一个空占位，避免报错
        return const SizedBox.shrink();
      },
    );
  }

  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) {
    // 使用 Builder 访问外层 context，尝试获取 SpaceBloc 或创建新的
    return Builder(
      builder: (outerContext) {
        // 尝试从外层 context 获取 SpaceBloc
        SpaceBloc? spaceBloc;
        try {
          spaceBloc = BlocProvider.of<SpaceBloc>(outerContext);
          debugPrint('[SpaceHub] Found existing SpaceBloc, isInitialized=${spaceBloc.state.isInitialized}, currentSpace=${spaceBloc.state.currentSpace?.id}');
          // 如果 SpaceBloc 已存在且已初始化，但当前空间不是目标空间，需要打开目标空间
          if (spaceBloc.state.isInitialized && spaceBloc.state.currentSpace?.id != view.id) {
            debugPrint('[SpaceHub] Existing SpaceBloc initialized but currentSpace != target, will open target space in listener');
          }
        } catch (_) {
          // SpaceBloc 不存在，尝试创建新的
          try {
            final userWorkspaceBloc = outerContext.read<UserWorkspaceBloc>();
            final userProfile = userWorkspaceBloc.state.userProfile;
            final workspaceId = userWorkspaceBloc.state.currentWorkspace?.workspaceId ?? '';
            if (workspaceId.isNotEmpty) {
              debugPrint('[SpaceHub] Creating new SpaceBloc for workspace: $workspaceId');
              spaceBloc = SpaceBloc(
                userProfile: userProfile,
                workspaceId: workspaceId,
              );
              // 先初始化 SpaceBloc，空间打开会在 BlocListener 中处理
              // 注意：初始化是异步的，需要等待 isInitialized 变为 true 后再打开空间
              spaceBloc.add(const SpaceEvent.initial(openFirstPage: false));
              debugPrint('[SpaceHub] SpaceBloc initial event dispatched');
            } else {
              debugPrint('[SpaceHub] workspaceId is empty, cannot create SpaceBloc');
            }
          } catch (e) {
            debugPrint('[SpaceHub] Failed to create SpaceBloc: $e');
            // UserWorkspaceBloc 也不存在，spaceBloc 保持为 null
          }
        }

        final providers = <BlocProvider>[
          BlocProvider<ViewInfoBloc>.value(value: bloc),
          BlocProvider<PageAccessLevelBloc>.value(value: pageAccessLevelBloc),
        ];

        // 如果创建了新的 SpaceBloc，添加到 providers
        if (spaceBloc != null) {
          providers.add(BlocProvider<SpaceBloc>.value(value: spaceBloc));
        }

        return MultiBlocProvider(
          providers: providers,
          child: _SpaceHubContent(
            spaceView: view,
            selectedViewNotifier: selectedViewNotifier,
            onDeleted: (deletedView, index) =>
                context.onDeleted?.call(deletedView, index),
          ),
        );
      },
    );
  }

  @override
  String? get viewName => notifier.view.nameOrDefault;

  @override
  Widget get leftBarItem {
    // If a specific document inside the space is selected, hide the
    // global space breadcrumb/title to avoid duplicate path UI.
    return ValueListenableBuilder<ViewPB?>(
      valueListenable: selectedViewNotifier,
      builder: (context, selectedView, _) {
        if (selectedView != null) {
          return const SizedBox.shrink();
        }

        return BlocProvider.value(
          value: pageAccessLevelBloc,
          child: ViewTitleBar(key: ValueKey(view.id), view: view),
        );
      },
    );
  }

  @override
  Widget tabBarItem(String pluginId, [bool shortForm = false]) =>
      ViewTabBarItem(view: notifier.view, shortForm: shortForm);

  @override
  List<NavigationItem> get navigationItems => [this];
}

/// 空间统一页面内容组件
class _SpaceHubContent extends StatefulWidget {
  const _SpaceHubContent({
    required this.spaceView,
    required this.selectedViewNotifier,
    required this.onDeleted,
  });

  final ViewPB spaceView;
  final ValueNotifier<ViewPB?> selectedViewNotifier;
  final Function(ViewPB, int?)? onDeleted;

  @override
  State<_SpaceHubContent> createState() => _SpaceHubContentState();
}

class _SpaceHubContentState extends State<_SpaceHubContent> {
  ViewPB? _selectedView;
  
  /// 左侧文档列表的宽度
  double _leftPanelWidth = 260.0;
  
  /// 左侧面板最小宽度
  static const double _minLeftWidth = 200.0;
  
  /// 左侧面板最大宽度
  static const double _maxLeftWidth = 450.0;

  @override
  void initState() {
    super.initState();
    debugPrint('[SpaceHub] _SpaceHubContentState initState, spaceView: ${widget.spaceView.name} (${widget.spaceView.id})');
    // 尝试从 SpaceBloc 获取当前空间的第一个文档作为默认选中
    _trySelectFirstDocument();
  }

  @override
  void didUpdateWidget(_SpaceHubContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果空间切换了，重置选中文档状态
    if (oldWidget.spaceView.id != widget.spaceView.id) {
      debugPrint('[SpaceHub] Space changed from ${oldWidget.spaceView.name} to ${widget.spaceView.name}, resetting selected view');
      setState(() {
        _selectedView = null;
      });
      widget.selectedViewNotifier.value = null;
      // 重新尝试选中新空间的第一个文档
      _trySelectFirstDocument();
    }
  }

  void _trySelectFirstDocument() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final spaceBloc = context.read<SpaceBloc>();
        final currentSpace = spaceBloc.state.currentSpace;
        debugPrint('[SpaceHub] _trySelectFirstDocument: currentSpace=${currentSpace?.id}, targetSpace=${widget.spaceView.id}');
        if (currentSpace?.id == widget.spaceView.id &&
            currentSpace!.childViews.isNotEmpty) {
          final firstView = currentSpace.childViews.first;
          debugPrint('[SpaceHub] Selecting first document: ${firstView.name}');
          setState(() {
            _selectedView = firstView;
          });
          // 更新共享的选中视图状态
          widget.selectedViewNotifier.value = firstView;
        }
      } catch (e) {
        debugPrint('[SpaceHub] _trySelectFirstDocument error: $e');
        // SpaceBloc 不存在，稍后通过 FutureBuilder 加载
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 尝试获取 SpaceBloc，如果不存在则使用 fallback 逻辑
    SpaceBloc? spaceBloc;
    try {
      spaceBloc = BlocProvider.of<SpaceBloc>(context);
    } catch (_) {
      spaceBloc = null;
    }

    debugPrint('[SpaceHub] _SpaceHubContent building, selectedView: ${_selectedView?.name}');
    
    Widget content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧：空间文档列表
        SizedBox(
          width: _leftPanelWidth,
          child: _SpaceDocumentList(
            spaceView: widget.spaceView,
            selectedView: _selectedView,
            onViewSelected: (view) {
              debugPrint('[SpaceHub] View selected: ${view.name} (${view.id})');
              setState(() {
                _selectedView = view;
              });
              // 更新共享的选中视图状态，以便 rightBarItem 可以访问
              widget.selectedViewNotifier.value = view;
            },
          ),
        ),
        // 可拖动分隔线 - 增强对比度并支持拖动调整大小
        ResizableDivider(
          initialLeftWidth: _leftPanelWidth,
          minLeftWidth: _minLeftWidth,
          maxLeftWidth: _maxLeftWidth,
          onResize: (newWidth) {
            setState(() {
              _leftPanelWidth = newWidth;
            });
          },
        ),
        // 右侧：选中文档详情（保留顶部间距，使正文不贴顶）
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(
                top: HomeSizes.topBarHeight + HomeInsets.topBarTitleVerticalPadding),
            child: _selectedView != null
                ? _buildSelectedViewContent(_selectedView!)
                : _buildEmptyState(),
          ),
        ),
      ],
    );

    // 如果有 SpaceBloc，使用 BlocListener 监听空间状态变化
    if (spaceBloc != null) {
      return BlocListener<SpaceBloc, SpaceState>(
        bloc: spaceBloc,
        listenWhen: (prev, curr) =>
            curr.currentSpace?.id == widget.spaceView.id &&
            curr.currentSpace!.childViews.isNotEmpty &&
            _selectedView == null,
        listener: (context, state) {
          // 当空间文档列表加载完成后，自动选中第一个文档
          final currentSpace = state.currentSpace;
          if (currentSpace?.id == widget.spaceView.id &&
              currentSpace!.childViews.isNotEmpty) {
            final firstView = currentSpace.childViews.first;
            setState(() {
              _selectedView = firstView;
            });
            // 更新共享的选中视图状态
            widget.selectedViewNotifier.value = firstView;
          }
        },
        child: content,
      );
    }

    return content;
  }

  Widget _buildSelectedViewContent(ViewPB view) {
    // 根据 view 的类型创建对应的插件并展示
    try {
      final plugin = view.plugin();
      // 确保插件已初始化
      plugin.init();
      
      // 获取 userProfile - AI Chat 等插件需要用户信息
      UserProfilePB? userProfile;
      try {
        final userWorkspaceBloc = context.read<UserWorkspaceBloc>();
        userProfile = userWorkspaceBloc.state.userProfile;
      } catch (e) {
        debugPrint('[SpaceHub] Failed to get userProfile: $e');
      }
      
      return plugin.widgetBuilder.buildWidget(
        context: PluginContext(
          onDeleted: widget.onDeleted,
          userProfile: userProfile,  // 传入用户配置
        ),
        shrinkWrap: false,
      );
    } catch (e, stackTrace) {
      debugPrint('[SpaceHub] Error loading view ${view.name} (${view.id}): $e');
      debugPrint('[SpaceHub] Stack trace: $stackTrace');
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FlowyText.regular(
              '无法加载视图: ${view.name}',
              fontSize: 14,
              color: Theme.of(context).colorScheme.error,
            ),
            const VSpace(8),
            FlowyText.regular(
              '错误: ${e.toString()}',
              fontSize: 12,
              color: Theme.of(context).hintColor,
            ),
          ],
        ),
      );
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FlowyText.regular(
            '请从左侧选择一个文档',
            fontSize: 16,
            color: Theme.of(context).hintColor,
          ),
          const VSpace(8),
          FlowyText.regular(
            '或点击左上角的 + 按钮创建新文档',
            fontSize: 14,
            color: Theme.of(context).hintColor,
          ),
        ],
      ),
    );
  }
}

/// 空间文档列表组件（左侧）
class _SpaceDocumentList extends StatelessWidget {
  const _SpaceDocumentList({
    required this.spaceView,
    required this.selectedView,
    required this.onViewSelected,
  });

  final ViewPB spaceView;
  final ViewPB? selectedView;
  final ValueChanged<ViewPB> onViewSelected;

  @override
  Widget build(BuildContext context) {
    // 尝试从 SpaceBloc 获取空间文档列表
    SpaceBloc? spaceBloc;
    try {
      spaceBloc = BlocProvider.of<SpaceBloc>(context);
    } catch (_) {
      spaceBloc = null;
    }

    // 调试信息
    debugPrint('[SpaceHub] _SpaceDocumentList building, spaceBloc: ${spaceBloc != null}, spaceView: ${spaceView.name} (${spaceView.id})');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 头部：空间名称 + 新增文档按钮
          _buildHeader(context, spaceBloc),
          VSpace(12),
          // 文档列表
          Expanded(
            child: spaceBloc != null
                ? _buildListFromSpaceBloc(context, spaceBloc)
                : _buildListFromBackend(context),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, SpaceBloc? spaceBloc) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
        color: Theme.of(context).colorScheme.surfaceContainer,
      ),
      child: Row(
        children: [
          Expanded(
            child: FlowyText(
              spaceView.name,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(
            width: 24,
            height: 24,
            child: ViewAddButton(
              parentViewId: spaceView.id,
              onEditing: (_) {},
              onSelected: (pluginBuilder, name, initialDataBytes,
                  openAfterCreated, createNewView) {
                final layout = pluginBuilder.layoutType;
                if (layout == null) return;

                if (spaceBloc != null) {
                  // 使用 SpaceBloc 创建文档
                  spaceBloc.add(
                    SpaceEvent.createPage(
                      name: name ?? layout.defaultName,
                      layout: layout,
                      index: 0,
                      openAfterCreate: false, // 不自动打开，由左侧列表选中触发
                    ),
                  );
                } else {
                  // Fallback: 直接创建文档
                  ViewBackendService.createView(
                    layoutType: layout,
                    parentViewId: spaceView.id,
                    name: name ?? layout.defaultName,
                    openAfterCreate: false,
                  );
                }
              },
              tooltipText: '新增文档',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListFromSpaceBloc(BuildContext context, SpaceBloc spaceBloc) {
    return BlocListener<SpaceBloc, SpaceState>(
      bloc: spaceBloc,
      listenWhen: (prev, curr) {
        // 监听初始化完成，或者当前空间变化，或者子视图列表变化
        final initialized = !prev.isInitialized && curr.isInitialized;
        final spaceChanged = prev.currentSpace?.id != curr.currentSpace?.id;
        final childViewsChanged = prev.currentSpace?.childViews.length != curr.currentSpace?.childViews.length ||
            prev.currentSpace?.childViews.map((v) => v.id).join(',') != curr.currentSpace?.childViews.map((v) => v.id).join(',');
        return initialized || spaceChanged || childViewsChanged;
      },
      listener: (context, state) {
        // 当 SpaceBloc 初始化完成后，如果当前空间不是目标空间，则打开目标空间
        if (state.isInitialized) {
          final currentSpace = state.currentSpace;
          if (currentSpace?.id != spaceView.id) {
            debugPrint('[SpaceHub] SpaceBloc initialized, opening target space: ${spaceView.name} (${spaceView.id}), currentSpace=${currentSpace?.id}');
            // 使用 Future.microtask 确保在下一帧执行，避免在 listener 中直接修改状态
            // 添加一个标记来避免重复触发
            Future.microtask(() {
              if (!spaceBloc.isClosed) {
                final currentState = spaceBloc.state;
                // 再次检查，避免重复打开
                if (currentState.isInitialized && currentState.currentSpace?.id != spaceView.id) {
                  debugPrint('[SpaceHub] Dispatching SpaceEvent.open for ${spaceView.name}');
                  spaceBloc.add(SpaceEvent.open(space: spaceView));
                } else {
                  debugPrint('[SpaceHub] Skipping open event, currentSpace already matches or SpaceBloc closed');
                }
              }
            });
          } else {
            debugPrint('[SpaceHub] Current space already matches target space: ${spaceView.name}');
          }
        }
      },
      child: BlocBuilder<SpaceBloc, SpaceState>(
        bloc: spaceBloc,
        buildWhen: (previous, current) {
          // 检查当前空间是否匹配目标空间
          final currSpace = current.currentSpace;
          final prevSpace = previous.currentSpace;
          
          debugPrint('[SpaceHub] buildWhen: prevSpace=${prevSpace?.id}, currSpace=${currSpace?.id}, targetSpace=${spaceView.id}');
          
          // 如果当前空间不匹配目标空间，只在空间ID变化时重建
          if (currSpace?.id != spaceView.id) {
            final shouldRebuild = prevSpace?.id != currSpace?.id;
            debugPrint('[SpaceHub] buildWhen: space not matching target, shouldRebuild=$shouldRebuild');
            return shouldRebuild;
          }
          
          // 当前空间匹配目标空间，检查子视图是否变化
          if (prevSpace?.id != currSpace?.id) {
            debugPrint('[SpaceHub] buildWhen: Space changed: ${prevSpace?.id} -> ${currSpace?.id}, shouldRebuild=true');
            return true;
          }
          
          // 检查子视图数量或ID列表是否变化
          final prevCount = prevSpace?.childViews.length ?? 0;
          final currCount = currSpace?.childViews.length ?? 0;
          if (prevCount != currCount) {
            debugPrint('[SpaceHub] buildWhen: Child views count changed: $prevCount -> $currCount, shouldRebuild=true');
            return true;
          }
          
          // 检查子视图ID列表是否变化（使用 Set 比较，忽略顺序）
          final prevIds = prevSpace?.childViews.map((v) => v.id).toSet();
          final currIds = currSpace?.childViews.map((v) => v.id).toSet();
          if (prevIds != currIds) {
            debugPrint('[SpaceHub] buildWhen: Child views IDs changed: prev=${prevIds?.toList()} curr=${currIds?.toList()}, shouldRebuild=true');
            return true;
          }
          
          // 其他重要状态变化也需要重建
          if (previous.isInitialized != current.isInitialized) {
            debugPrint('[SpaceHub] buildWhen: isInitialized changed, shouldRebuild=true');
            return true;
          }
          
          // 默认不重建（避免不必要的重建）
          debugPrint('[SpaceHub] buildWhen: No changes detected, shouldRebuild=false');
          return false;
        },
        builder: (context, state) {
          // 确保当前空间已加载，如果没有则触发加载
          final currentSpace = state.currentSpace;
          
          debugPrint('[SpaceHub] _buildListFromSpaceBloc: isInitialized=${state.isInitialized}, currentSpace=${currentSpace?.id}, targetSpace=${spaceView.id}');
          
          // 如果 SpaceBloc 还未初始化，显示加载中
          if (!state.isInitialized) {
            debugPrint('[SpaceHub] SpaceBloc not initialized yet, showing loading');
            return const Center(
              child: CircularProgressIndicator.adaptive(),
            );
          }

          // 如果当前空间不是目标空间，显示加载中（等待 SpaceEvent.open 完成）
          if (currentSpace?.id != spaceView.id) {
            debugPrint('[SpaceHub] Current space (${currentSpace?.id}) != target space (${spaceView.id}), showing loading');
            return const Center(
              child: CircularProgressIndicator.adaptive(),
            );
          }

          // 当前空间匹配，使用 currentSpace（它已经包含了加载的子视图）
          final displaySpace = currentSpace!;
          final childViews = displaySpace.childViews;

          debugPrint('[SpaceHub] childViews count: ${childViews.length}, displaySpace.id=${displaySpace.id}');

          if (childViews.isEmpty) {
            return Center(
              child: FlowyText.regular(
                '暂无文档',
                fontSize: 13,
                color: Theme.of(context).hintColor,
              ),
            );
          }

          return ListView.builder(
            itemCount: childViews.length,
            itemBuilder: (context, index) {
              final childView = childViews[index];
              return ViewItem(
                key: ValueKey('space_hub_${childView.id}'),
                view: childView,
                spaceType: childView.spacePermission == SpacePermission.private
                    ? FolderSpaceType.private
                    : FolderSpaceType.public,
                level: 0,
                leftPadding: 10,
                onSelected: (itemContext, selectedView) {
                  // 在空间统一页面中，点击文档只更新选中状态，不打开新 tab
                  // 更新 MenuSharedState 以便 ViewItem 显示选中状态
                  getIt<MenuSharedState>().latestOpenView = selectedView;
                  onViewSelected(selectedView);
                },
                isFeedback: false,
                shouldRenderChildren: true,
                shouldLoadChildViews: true,
                enableRightClickContext: true, // 保持右键菜单功能
                isHoverEnabled: true,
                disableSelectedStatus: false, // 允许显示选中状态
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildListFromBackend(BuildContext context) {
    return FutureBuilder<List<ViewPB>>(
      future: _loadChildViews(spaceView.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }

        final childViews = snapshot.data ?? const <ViewPB>[];

        if (childViews.isEmpty) {
          return Center(
            child: FlowyText.regular(
              '暂无文档',
              fontSize: 13,
              color: Theme.of(context).hintColor,
            ),
          );
        }

        return ListView.builder(
          itemCount: childViews.length,
          itemBuilder: (context, index) {
            final childView = childViews[index];
            return ViewItem(
              key: ValueKey('space_hub_${childView.id}'),
              view: childView,
              spaceType: childView.spacePermission == SpacePermission.private
                  ? FolderSpaceType.private
                  : FolderSpaceType.public,
              level: 0,
              leftPadding: 10,
              onSelected: (itemContext, selectedView) {
                // 更新 MenuSharedState 以便 ViewItem 显示选中状态
                getIt<MenuSharedState>().latestOpenView = selectedView;
                onViewSelected(selectedView);
              },
              isFeedback: false,
              shouldRenderChildren: true,
              shouldLoadChildViews: true,
              enableRightClickContext: true,
              isHoverEnabled: true,
              disableSelectedStatus: false, // 允许显示选中状态
            );
          },
        );
      },
    );
  }

  Future<List<ViewPB>> _loadChildViews(String spaceId) async {
    final result = await ViewBackendService.getChildViews(viewId: spaceId);
    return result.fold((views) => views, (_) => const <ViewPB>[]);
  }
}

import 'package:appflowy/plugins/blank/blank.dart';
import 'package:appflowy/plugins/util.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/util/expand_views.dart';
import 'package:appflowy/workspace/application/recent/cached_recent_service.dart';
import 'package:appflowy/workspace/application/view/expanded_views_cache.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:bloc/bloc.dart';
import 'package:collection/collection.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'tabs_bloc.freezed.dart';

class TabsBloc extends Bloc<TabsEvent, TabsState> {
  TabsBloc() : super(TabsState()) {
    menuSharedState = getIt<MenuSharedState>();
    _recentService = getIt<CachedRecentService>();
    // 初始化 ExpandedViewsCache（异步，不阻塞）
    ExpandedViewsCache.instance.initialize();
    _dispatch();
  }

  late final MenuSharedState menuSharedState;
  late final CachedRecentService _recentService;
  
  /// 上次添加到最近访问的视图 ID（用于防抖）
  String? _lastAddedRecentViewId;

  @override
  Future<void> close() {
    state.dispose();
    return super.close();
  }

  void _dispatch() {
    on<TabsEvent>(
      (event, emit) async {
        event.when(
          selectTab: (int index) {
            if (index != state.currentIndex &&
                index >= 0 &&
                index < state.pages) {
              emit(state.copyWith(currentIndex: index));
              _setLatestOpenView();
            }
          },
          moveTab: () {},
          closeTab: (String pluginId) {
            final pm = state._pageManagers
                .firstWhereOrNull((pm) => pm.plugin.id == pluginId);
            if (pm?.isPinned == true) {
              return;
            }

            emit(state.closeView(pluginId));
            _setLatestOpenView();
          },
          closeCurrentTab: () {
            if (state.currentPageManager.isPinned) {
              return;
            }

            emit(state.closeView(state.currentPageManager.plugin.id));
            _setLatestOpenView();
          },
          openTab: (Plugin plugin, ViewPB view) {
            state.currentPageManager
              ..hideSecondaryPlugin()
              ..setSecondaryPlugin(BlankPagePlugin());
            emit(state.openView(plugin));
            _setLatestOpenView(view);
          },
          openPlugin: (Plugin plugin, ViewPB? view, bool setLatest) {
            state.currentPageManager
              ..hideSecondaryPlugin()
              ..setSecondaryPlugin(BlankPagePlugin());
            emit(state.openPlugin(plugin: plugin, setLatest: setLatest));
            if (setLatest) {
              // the space view should be filtered out.
              if (view != null && view.isSpace) {
                return;
              }
              _setLatestOpenView(view);
              if (view != null) _expandAncestors(view);
            }
          },
          closeOtherTabs: (String pluginId) {
            final pageManagers = [
              ...state._pageManagers
                  .where((pm) => pm.plugin.id == pluginId || pm.isPinned),
            ];

            int newIndex;
            if (state.currentPageManager.isPinned) {
              // Retain current index if it's already pinned
              newIndex = state.currentIndex;
            } else {
              final pm = state._pageManagers
                  .firstWhereOrNull((pm) => pm.plugin.id == pluginId);
              newIndex = pm != null ? pageManagers.indexOf(pm) : 0;
            }

            emit(
              state.copyWith(
                currentIndex: newIndex,
                pageManagers: pageManagers,
              ),
            );

            _setLatestOpenView();
          },
          togglePin: (String pluginId) {
            final pm = state._pageManagers
                .firstWhereOrNull((pm) => pm.plugin.id == pluginId);
            if (pm != null) {
              final index = state._pageManagers.indexOf(pm);

              int newIndex = state.currentIndex;
              if (pm.isPinned) {
                // Unpinning logic
                final indexOfFirstUnpinnedTab =
                    state._pageManagers.indexWhere((tab) => !tab.isPinned);

                // Determine the correct insertion point
                final newUnpinnedIndex = indexOfFirstUnpinnedTab != -1
                    ? indexOfFirstUnpinnedTab // Insert before the first unpinned tab
                    : state._pageManagers
                        .length; // Append at the end if no unpinned tabs exist

                state._pageManagers.removeAt(index);

                final adjustedUnpinnedIndex = newUnpinnedIndex > index
                    ? newUnpinnedIndex - 1
                    : newUnpinnedIndex;

                state._pageManagers.insert(adjustedUnpinnedIndex, pm);
                newIndex = _adjustCurrentIndex(
                  currentIndex: state.currentIndex,
                  tabIndex: index,
                  newIndex: adjustedUnpinnedIndex,
                );
              } else {
                // Pinning logic
                final indexOfLastPinnedTab =
                    state._pageManagers.lastIndexWhere((tab) => tab.isPinned);
                final newPinnedIndex = indexOfLastPinnedTab + 1;

                state._pageManagers.removeAt(index);

                final adjustedPinnedIndex = newPinnedIndex > index
                    ? newPinnedIndex - 1
                    : newPinnedIndex;

                state._pageManagers.insert(adjustedPinnedIndex, pm);
                newIndex = _adjustCurrentIndex(
                  currentIndex: state.currentIndex,
                  tabIndex: index,
                  newIndex: adjustedPinnedIndex,
                );
              }

              pm.isPinned = !pm.isPinned;

              emit(
                state.copyWith(
                  currentIndex: newIndex,
                  pageManagers: [...state._pageManagers],
                ),
              );
            }
          },
          openSecondaryPlugin: (plugin, view) {
            state.currentPageManager
              ..setSecondaryPlugin(plugin)
              ..showSecondaryPlugin();
          },
          closeSecondaryPlugin: () {
            final pageManager = state.currentPageManager;
            pageManager.hideSecondaryPlugin();
          },
          expandSecondaryPlugin: () {
            final pageManager = state.currentPageManager;
            pageManager
              ..hideSecondaryPlugin()
              ..expandSecondaryPlugin();
            _setLatestOpenView();
          },
          switchWorkspace: (workspaceId) {
            // Workspace context changed: reset tabs to a clean blank page,
            // then HomeBloc can open the latest view for the new workspace.
            state.dispose();
            _lastAddedRecentViewId = null;
            emit(TabsState());
          },
          initial: () {
            // 在应用初始化时，检查当前打开的视图并添加到最近访问
            final pageManager = state.currentPageManager;
            final notifier = pageManager.plugin.notifier;
            if (notifier is ViewPluginNotifier && !notifier.view.isSpace) {
              _addToRecentViews(notifier.view.id);
            }
          },
        );
      },
    );
  }

  void _setLatestOpenView([ViewPB? view]) {
    ViewPB? targetView = view;
    
    if (targetView != null) {
      menuSharedState.latestOpenView = targetView;
    } else {
      final pageManager = state.currentPageManager;
      final notifier = pageManager.plugin.notifier;
      if (notifier is ViewPluginNotifier &&
          menuSharedState.latestOpenView?.id != notifier.view.id) {
        targetView = notifier.view;
        menuSharedState.latestOpenView = targetView;
      }
    }
    
    // 自动添加到最近访问列表（过滤掉空间视图）
    if (targetView != null && !targetView.isSpace) {
      _addToRecentViews(targetView.id);
    }
  }
  
  /// 添加视图到最近访问列表的异步方法（带防抖）
  void _addToRecentViews(String viewId) {
    // 防抖：如果是同一个视图，跳过
    if (_lastAddedRecentViewId == viewId) {
      return;
    }
    _lastAddedRecentViewId = viewId;
    
    // 使用异步方式更新最近访问，避免阻塞UI
    Future.microtask(() async {
      try {
        await _recentService.updateRecentViews([viewId], true);
      } catch (e) {
        // 静默处理错误，避免影响 UI
      }
    });
  }

  /// 展开视图祖先链（优化版本，使用缓存）
  Future<void> _expandAncestors(ViewPB view) async {
    final viewExpanderRegistry = getIt.get<ViewExpanderRegistry>();
    
    // 快速检查：如果父视图已展开，跳过
    if (viewExpanderRegistry.isViewExpanded(view.parentViewId)) return;
    
    // 使用缓存检查（同步操作，非常快）
    final cache = ExpandedViewsCache.instance;
    if (cache.isExpanded(view.parentViewId)) {
      // 父视图在缓存中已标记为展开，尝试通过 UI 展开器展开
      final expander = viewExpanderRegistry.getExpander(view.parentViewId);
      if (expander != null && !expander.isViewExpanded) {
        expander.expand();
      }
      return;
    }
    
    // 异步获取祖先链（后台操作，不阻塞 UI）
    try {
      final ancestors = await ViewBackendService.getViewAncestors(view.id)
          .fold((s) => s.items.map((e) => e.id).toList(), (f) => <String>[]);
      
      if (ancestors.isEmpty) return;
      
      // 批量更新缓存
      cache.setExpandedBatch(ancestors, true);
      
      // 找到第一个未展开的祖先并展开
      ViewExpander? viewExpander;
      for (final id in ancestors) {
        final expander = viewExpanderRegistry.getExpander(id);
        if (expander != null && !expander.isViewExpanded && viewExpander == null) {
          viewExpander = expander;
          break;
        }
      }
      viewExpander?.expand();
    } catch (e) {
      Log.error('expandAncestors error', e);
    }
  }

  int _adjustCurrentIndex({
    required int currentIndex,
    required int tabIndex,
    required int newIndex,
  }) {
    if (tabIndex < currentIndex && newIndex >= currentIndex) {
      return currentIndex - 1; // Tab moved forward, shift currentIndex back
    } else if (tabIndex > currentIndex && newIndex <= currentIndex) {
      return currentIndex + 1; // Tab moved backward, shift currentIndex forward
    } else if (tabIndex == currentIndex) {
      return newIndex; // Tab is the current tab, update to newIndex
    }

    return currentIndex;
  }

  /// Adds a [TabsEvent.openTab] event for the provided [ViewPB]
  void openTab(ViewPB view) {
    try {
      if (view.id.isEmpty) {
        Log.error('openTab called with empty view.id, aborting openTab');
        showToastNotification(
          message: '无法打开视图：视图 ID 为空',
          type: ToastificationType.error,
        );
        return;
      }
      final plugin = view.plugin();
      add(TabsEvent.openTab(plugin: plugin, view: view));
    } catch (e, stackTrace) {
      Log.error('Failed to open tab for view: ${view.id}, layout: ${view.layout}', e);
      Log.error('Stack trace:', stackTrace);
      
      // 显示错误提示
      String errorMessage = '加载笔记失败';
      if (e is UnimplementedError) {
        errorMessage = '不支持的笔记类型: ${view.layout}';
      } else if (e.toString().contains('404')) {
        errorMessage = '笔记不存在或已被删除';
      } else {
        errorMessage = '加载笔记失败: ${e.toString()}';
      }
      
      showToastNotification(
        message: errorMessage,
        type: ToastificationType.error,
      );
      
      // 如果打开失败，尝试打开一个空白页面作为降级方案
      try {
        add(TabsEvent.openTab(plugin: BlankPagePlugin(), view: view));
      } catch (fallbackError) {
        Log.error('Failed to open blank page as fallback', fallbackError);
      }
    }
  }

  /// Adds a [TabsEvent.openPlugin] event for the provided [ViewPB]
  void openPlugin(
    ViewPB view, {
    Map<String, dynamic> arguments = const {},
  }) {
    try {
      if (view.id.isEmpty) {
        Log.error('openPlugin called with empty view.id, aborting openPlugin');
        showToastNotification(
          message: '无法打开视图：视图 ID 为空',
          type: ToastificationType.error,
        );
        return;
      }
      final plugin = view.plugin(arguments: arguments);
      add(
        TabsEvent.openPlugin(
          plugin: plugin,
          view: view,
        ),
      );
    } catch (e, stackTrace) {
      Log.error('Failed to open plugin for view: ${view.id}, layout: ${view.layout}', e);
      Log.error('Stack trace:', stackTrace);
      
      // 显示错误提示
      String errorMessage = '加载笔记失败';
      if (e is UnimplementedError) {
        errorMessage = '不支持的笔记类型: ${view.layout}';
      } else if (e.toString().contains('404')) {
        errorMessage = '笔记不存在或已被删除';
      } else {
        errorMessage = '加载笔记失败: ${e.toString()}';
      }
      
      showToastNotification(
        message: errorMessage,
        type: ToastificationType.error,
      );
      
      // 如果打开失败，尝试打开一个空白页面作为降级方案
      try {
    add(
      TabsEvent.openPlugin(
            plugin: BlankPagePlugin(),
        view: view,
      ),
    );
      } catch (fallbackError) {
        Log.error('Failed to open blank page as fallback', fallbackError);
      }
    }
  }
}

@freezed
class TabsEvent with _$TabsEvent {
  const factory TabsEvent.moveTab() = _MoveTab;

  const factory TabsEvent.closeTab(String pluginId) = _CloseTab;

  const factory TabsEvent.closeOtherTabs(String pluginId) = _CloseOtherTabs;

  const factory TabsEvent.closeCurrentTab() = _CloseCurrentTab;

  const factory TabsEvent.selectTab(int index) = _SelectTab;

  const factory TabsEvent.togglePin(String pluginId) = _TogglePin;

  const factory TabsEvent.openTab({
    required Plugin plugin,
    required ViewPB view,
  }) = _OpenTab;

  const factory TabsEvent.openPlugin({
    required Plugin plugin,
    ViewPB? view,
    @Default(true) bool setLatest,
  }) = _OpenPlugin;

  const factory TabsEvent.openSecondaryPlugin({
    required Plugin plugin,
    ViewPB? view,
  }) = _OpenSecondaryPlugin;

  const factory TabsEvent.closeSecondaryPlugin() = _CloseSecondaryPlugin;

  const factory TabsEvent.expandSecondaryPlugin() = _ExpandSecondaryPlugin;

  const factory TabsEvent.switchWorkspace(String workspaceId) =
      _SwitchWorkspace;
      
  const factory TabsEvent.initial() = _Initial;
}

class TabsState {
  TabsState({
    this.currentIndex = 0,
    List<PageManager>? pageManagers,
  }) : _pageManagers = pageManagers ?? [PageManager()];

  final int currentIndex;
  final List<PageManager> _pageManagers;

  int get pages => _pageManagers.length;

  PageManager get currentPageManager => _pageManagers[currentIndex];

  List<PageManager> get pageManagers => _pageManagers;

  bool get isAllPinned => _pageManagers.every((pm) => pm.isPinned);

  /// This opens a new tab given a [Plugin].
  ///
  /// If the [Plugin.id] is already associated with an open tab,
  /// then it selects that tab.
  ///
  TabsState openView(Plugin plugin) {
    final selectExistingPlugin = _selectPluginIfOpen(plugin.id);

    if (selectExistingPlugin == null) {
      _pageManagers.add(PageManager()..setPlugin(plugin, true));

      return copyWith(
        currentIndex: pages - 1,
        pageManagers: [..._pageManagers],
      );
    }

    return selectExistingPlugin;
  }

  TabsState closeView(String pluginId) {
    // Avoid closing the only open tab
    if (_pageManagers.length == 1) {
      return this;
    }

    _pageManagers.removeWhere((pm) => pm.plugin.id == pluginId);

    /// If currentIndex is greater than the amount of allowed indices
    /// And the current selected tab isn't the first (index 0)
    ///   as currentIndex cannot be -1
    /// Then decrease currentIndex by 1
    final newIndex = currentIndex > pages - 1 && currentIndex > 0
        ? currentIndex - 1
        : currentIndex;

    return copyWith(
      currentIndex: newIndex,
      pageManagers: [..._pageManagers],
    );
  }

  /// This opens a plugin in the current selected tab,
  /// due to how Document currently works, only one tab
  /// per plugin can currently be active.
  ///
  /// If the plugin is already open in a tab, then that tab
  /// will become selected.
  ///
  TabsState openPlugin({required Plugin plugin, bool setLatest = true}) {
    final selectExistingPlugin = _selectPluginIfOpen(plugin.id);

    if (selectExistingPlugin == null) {
      final pageManagers = [..._pageManagers];
      pageManagers[currentIndex].setPlugin(plugin, setLatest);

      return copyWith(pageManagers: pageManagers);
    }

    return selectExistingPlugin;
  }

  /// Checks if a [Plugin.id] is already associated with an open tab.
  /// Returns a [TabState] with new index if there is a match.
  ///
  /// If no match it returns null
  ///
  TabsState? _selectPluginIfOpen(String id) {
    final index = _pageManagers.indexWhere((pm) => pm.plugin.id == id);

    if (index == -1) {
      return null;
    }

    if (index == currentIndex) {
      return this;
    }

    return copyWith(currentIndex: index);
  }

  TabsState copyWith({
    int? currentIndex,
    List<PageManager>? pageManagers,
  }) =>
      TabsState(
        currentIndex: currentIndex ?? this.currentIndex,
        pageManagers: pageManagers ?? _pageManagers,
      );

  void dispose() {
    for (final manager in pageManagers) {
      manager.dispose();
    }
  }
}

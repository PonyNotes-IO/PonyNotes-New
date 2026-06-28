import 'dart:async';

import 'package:appflowy/plugins/blank/blank.dart';
import 'package:appflowy/plugins/database/calendar/calendar.dart';
import 'package:appflowy/plugins/space_hub/space_hub.dart';
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
import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'tabs_bloc.freezed.dart';

class TabsBloc extends Bloc<TabsEvent, TabsState> {
  TabsBloc() : super(TabsState()) {
    menuSharedState = getIt<MenuSharedState>();
    _recentService = getIt<CachedRecentService>();
    // 初始化 ExpandedViewsCache（异步，不阻塞）
    ExpandedViewsCache.instance.initialize();
    // 尝试恢复上次打开的视图
    _restoreLastOpenView();
    _dispatch();
  }

  /// 恢复上次打开的视图
  Future<void> _restoreLastOpenView() async {
    try {
      // 从菜单共享状态获取上次打开的视图
      final lastOpenView = menuSharedState.latestOpenView;
      if (lastOpenView != null && lastOpenView.id.isNotEmpty) {
        Log.info('[TabsBloc] Restoring last open view: ${lastOpenView.id}');

        // 如果上次打开的是日历视图，直接打开日历插件
        if (lastOpenView.layout == ViewLayoutPB.Calendar) {
          final calendarPlugin = CalendarMainPlugin();
          add(TabsEvent.openPlugin(plugin: calendarPlugin, view: lastOpenView));
          return;
        }

        // 尝试打开普通视图
        final plugin = lastOpenView.plugin();
        add(TabsEvent.openPlugin(plugin: plugin, view: lastOpenView));
      }
    } catch (e) {
      Log.error('[TabsBloc] Failed to restore last open view', e);
    }
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

  void _disposePageManagersRemovedFrom(
    TabsState previousState,
    TabsState nextState,
  ) {
    for (final manager in previousState.pageManagers) {
      if (!nextState.pageManagers.contains(manager)) {
        unawaited(Future<void>.sync(manager.dispose));
      }
    }
  }

  void _dispatch() {
    on<TabsEvent>(
      (event, emit) async {
        // event.when 内部启动的异步回调(goBackToPreviousView)不会被 on handler
        // 顶层 await,bloc 会立即认为 handler 完成 → emit.isDone = true →
        // 异步回调里的 await 之后所有逻辑被 abort。所以在这里显式 await。
        Future<void>? pendingAsync;
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

            final previousState = state;
            final nextState = state.closeView(pluginId);
            emit(nextState);
            _disposePageManagersRemovedFrom(previousState, nextState);
            _setLatestOpenView();
          },
          closeCurrentTab: () {
            if (state.currentPageManager.isPinned) {
              return;
            }

            final previousState = state;
            final nextState =
                state.closeView(state.currentPageManager.plugin.id);
            emit(nextState);
            _disposePageManagersRemovedFrom(previousState, nextState);
            _setLatestOpenView();
          },
          openTab: (Plugin plugin, ViewPB view) {
            // ✅ 特殊情况:当前 plugin 是 SpaceHubPlugin 时,通知 SpaceHub
            // 选中子视图,不替换 SpaceHub。
            if (state.currentPageManager.plugin is SpaceHubPlugin) {
              try {
                final spaceHubPlugin =
                    state.currentPageManager.plugin as SpaceHubPlugin;
                spaceHubPlugin.selectViewInSpaceHub(view);
                return;
              } catch (_) {
                // 失败时回退到原有逻辑
              }
            }
            // 协作空间（isSpace=true）只做侧边栏导航，不生成选项卡
            if (view.isSpace) return;
            // 完全不触碰 SecondaryView,避免在文档内创建/打开子页面后
            // 右侧辅助面板（AI 对话等）被清掉或被隐藏。
            emit(state.openView(plugin));
            _setLatestOpenView(view);
          },
          openPlugin: (Plugin plugin, ViewPB? view, bool setLatest) {
            // ✅ 特殊情况:当前 plugin 是 SpaceHubPlugin 时,不应该把 SpaceHub
            // 整个替换掉。文档内的 mention/sub_page 链接会直接 add 这个 event,
            // 绕过 openPlugin() 入口的判断,这里再判断一次。
            if (view != null &&
                state.currentPageManager.plugin is SpaceHubPlugin) {
              // 如果点击的是空间视图，应该打开新的 SpaceHub 实例，而不是在当前 SpaceHub 内显示
              if (!view.isSpace) {
                try {
                  final spaceHubPlugin =
                      state.currentPageManager.plugin as SpaceHubPlugin;
                  spaceHubPlugin.selectViewInSpaceHub(view);
                  return;
                } catch (_) {
                  // 失败时回退到原有逻辑
                }
              }
            }
            // 完全不触碰 SecondaryView,避免在文档内创建/打开子页面后
            // 右侧辅助面板（AI 对话等）被清掉或被隐藏。
            emit(state.openPlugin(plugin: plugin, setLatest: setLatest));
            if (setLatest) {
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

            final previousState = state;
            final nextState = state.copyWith(
              currentIndex: newIndex,
              pageManagers: pageManagers,
            );
            emit(nextState);
            _disposePageManagersRemovedFrom(previousState, nextState);

            _setLatestOpenView();
          },
          togglePin: (String pluginId) {
            final pm = state._pageManagers
                .firstWhereOrNull((pm) => pm.plugin.id == pluginId);
            if (pm != null) {
              final index = state._pageManagers.indexOf(pm);

              // 创建副本，避免原地修改旧 State 的列表
              final newPageManagers = [...state._pageManagers];
              int newIndex = state.currentIndex;

              if (pm.isPinned) {
                // Unpinning logic
                final indexOfFirstUnpinnedTab =
                    state._pageManagers.indexWhere((tab) => !tab.isPinned);

                final newUnpinnedIndex = indexOfFirstUnpinnedTab != -1
                    ? indexOfFirstUnpinnedTab
                    : state._pageManagers.length;

                newPageManagers.removeAt(index);

                final adjustedUnpinnedIndex = newUnpinnedIndex > index
                    ? newUnpinnedIndex - 1
                    : newUnpinnedIndex;

                newPageManagers.insert(adjustedUnpinnedIndex, pm);
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

                newPageManagers.removeAt(index);

                final adjustedPinnedIndex = newPinnedIndex > index
                    ? newPinnedIndex - 1
                    : newPinnedIndex;

                newPageManagers.insert(adjustedPinnedIndex, pm);
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
                  pageManagers: newPageManagers,
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
          goBackToPreviousView: () async {
            pendingAsync = _goBackToPreviousView(emit);
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
        // 等待 event.when 启动的所有异步分支(目前只有 goBackToPreviousView)
        // 真正完成,避免 bloc 立即认为 handler 完成。
        if (pendingAsync != null) {
          await pendingAsync;
        }
      },
    );
  }

  void _setLatestOpenView([ViewPB? view]) {
    ViewPB? targetView = view;

    if (targetView != null) {
      // 在覆盖 latestOpenView 之前，把当前 view 快照到 previousOpenView。
      // 这样在 doc A 中通过 sub_page 块自动跳转到 doc B 时，B 的页面可以
      // 拿到 A 作为"上一文档"，提供返回按钮。
      // 当 source 和 target 相同时（同 tab 切换、不算导航）不清空。
      final currentLatest = menuSharedState.latestOpenView;
      if (currentLatest != null && currentLatest.id != targetView.id) {
        menuSharedState.setPreviousOpenView(currentLatest);
      }
      menuSharedState.latestOpenView = targetView;
    } else {
      final pageManager = state.currentPageManager;
      final notifier = pageManager.plugin.notifier;
      if (notifier is ViewPluginNotifier &&
          menuSharedState.latestOpenView?.id != notifier.view.id) {
        targetView = notifier.view;
        // 同样的快照逻辑（覆盖前先记录）
        final currentLatest = menuSharedState.latestOpenView;
        if (currentLatest != null && currentLatest.id != targetView.id) {
          menuSharedState.setPreviousOpenView(currentLatest);
        }
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
        if (expander != null &&
            !expander.isViewExpanded &&
            viewExpander == null) {
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
    // ✅ 特殊情况:当前 plugin 是 SpaceHubPlugin 时,不应该把 SpaceHub 整个
    // 替换掉,而是通知 SpaceHubPlugin 选中该子视图。
    if (state.currentPageManager.plugin is SpaceHubPlugin) {
      try {
        final plugin = state.currentPageManager.plugin as SpaceHubPlugin;
        plugin.selectViewInSpaceHub(view);
        return;
      } catch (_) {
        // 失败时回退到原有 openTab 流程
      }
    }
    // 协作空间不生成选项卡
    if (view.isSpace) return;
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
      Log.error(
        'Failed to open tab for view: ${view.id}, layout: ${view.layout}',
        e,
      );
      Log.error('Stack trace:', stackTrace);

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
    }
  }

  /// 异步加载一个 view，加载失败或 view id 为空时返回 null。
  Future<ViewPB?> _loadView(String viewId) async {
    if (viewId.isEmpty) return null;
    final result = await ViewBackendService.getView(viewId);
    return result.fold(
      (v) => v,
      (err) {
        Log.error('[TabsBloc] _loadView: failed to load $viewId: $err');
        return null;
      },
    );
  }

  /// 处理"返回上一文档"逻辑。提取为独立方法(而不是嵌在 event.when 回调内),
  /// 是因为 on<TabsEvent> handler 顶层没有 await 异步分支时,bloc 会认为
  /// handler 同步完成,emit.isDone 立即变 true,await 之后的逻辑被 abort。
  /// 在 on handler 顶层 await 此方法返回的 Future,可确保 bloc 一直保持
  /// handler 活跃直到真正结束。
  Future<void> _goBackToPreviousView(Emitter<TabsState> emit) async {
    // 1. 拿到当前 view
    final currentNotifier = state.currentPageManager.plugin.notifier;
    final currentView =
        currentNotifier is ViewPluginNotifier ? currentNotifier.view : null;
    if (currentView == null || currentView.id.isEmpty) {
      return;
    }

    // 1.5 特殊情况：当前是 SpaceHubPlugin 且中间栏选中了子视图(嵌入了文档)。
    //    用户期望的"返回"应该是切到父文档（如果存在），而不是清空选中。
    //    - 如果当前选中文档有父级且父级在同一个 SpaceHub 下 → selectViewInSpaceHub(父文档)
    //    - 否则 → 清空选中，回到 SpaceHub 主视图（空状态页）
    final currentPlugin = state.currentPageManager.plugin;
    if (currentPlugin is SpaceHubPlugin) {
      if (currentPlugin.hasSelectedView) {
        final currentSelected = currentPlugin.currentSelectedView;
        if (currentSelected != null &&
            currentSelected.parentViewId.isNotEmpty) {
          // 加载父文档，看是否属于同一个 SpaceHub
          final parentResult = await _loadView(currentSelected.parentViewId);
          if (parentResult != null && !parentResult.isSpace) {
            // 父级是普通文档，属于同一个 SpaceHub → 切到父文档
            currentPlugin.selectViewInSpaceHub(parentResult);
            return;
          }
        }
        // 父级是 space 或没有父级 → 清空选中，回到 SpaceHub 空状态
        currentPlugin.clearSelection();
        return;
      }
      return;
    }

    // 2. 父级 id 为空：没有父级可回退，保留旧行为（用 previousOpenView）
    if (currentView.parentViewId.isEmpty) {
      final previousView = menuSharedState.previousOpenView;
      if (previousView == null || previousView.id.isEmpty) {
        return;
      }
      menuSharedState.clearPreviousOpenView();
      final plugin = previousView.plugin();
      state.currentPageManager.setSecondaryPlugin(BlankPagePlugin());
      emit(state.openPlugin(plugin: plugin));
      menuSharedState.latestOpenView = previousView;
      return;
    }

    // 3. 沿父级链向上追溯，找到第一个 isSpace 的祖先作为返回目标。
    //    在协作空间内多层子页面里点返回，会回到"包含该子页面的协作空间"，
    //    而不是直接父级。这样进入子页面新建子页面后返回，UI 仍处于
    //    "父协作空间 + 中间一栏子页面列表" 的状态。
    ViewPB? targetView;
    ViewPB? childForSelected;
    String nextId = currentView.parentViewId;
    int safetyCounter = 0;
    while (nextId.isNotEmpty && safetyCounter < 16) {
      if (emit.isDone) return;
      safetyCounter++;
      final loaded = await _loadView(nextId);
      if (emit.isDone) return;
      if (loaded == null) break;
      if (loaded.isSpace) {
        targetView = loaded;
        if (childForSelected == null) {
          childForSelected = currentView;
        }
        break;
      }
      childForSelected ??= loaded;
      nextId = loaded.parentViewId;
    }
    targetView ??= childForSelected;
    if (targetView == null) return;

    // 4. 先清空 previousOpenView，避免 _setLatestOpenView 把当前 view 当成 previous 记录
    menuSharedState.clearPreviousOpenView();

    // 5. 打开目标 view；如果是 SpaceHub，把 childForSelected 作为初始选中，
    //    这样回退后能保持"父级展开 + 显示直接子页面"的状态。
    if (emit.isDone) return;
    final plugin = targetView.plugin(
      initialSelectedView: targetView.isSpace ? childForSelected : null,
    );
    state.currentPageManager
      ..setSecondaryPlugin(BlankPagePlugin())
      ..setPlugin(plugin, true);
    menuSharedState.latestOpenView = targetView;
  }

  /// Adds a [TabsEvent.openPlugin] event for the provided [ViewPB]
  void openPlugin(
    ViewPB view, {
    Map<String, dynamic> arguments = const {},
  }) {
    // ✅ 特殊情况:当前 plugin 是 SpaceHubPlugin 时,不应该把 SpaceHub 整个
    // 替换掉。SpaceHub 中间栏嵌入的子文档内,如果点击了 mention/sub_page
    // 等链接,这些链接的点击也会走到 openPlugin。
    // 正确做法:把点击的 view 通知给 SpaceHubPlugin,让它选中该子视图
    // (在 rightPanel 内显示),保持 SpaceHub 整体布局不变。
    if (state.currentPageManager.plugin is SpaceHubPlugin) {
      // 如果点击的是空间视图，应该打开新的 SpaceHub 实例，而不是在当前 SpaceHub 内显示
      if (view.isSpace) {
        Log.info(
            '[SpaceHubLink] Space view clicked in SpaceHub, opening new SpaceHub');
      } else {
        Log.info(
            '[SpaceHubLink] detected, calling selectViewInSpaceHub: ${view.name}(${view.id})');
        try {
          final plugin = state.currentPageManager.plugin as SpaceHubPlugin;
          plugin.selectViewInSpaceHub(view);
          return;
        } catch (e) {
          Log.error(
              '[SpaceHubLink] selectViewInSpaceHub failed, falling back: $e');
          // 失败时回退到原有 openPlugin 流程
        }
      }
    } else {
      Log.info(
          '[SpaceHubLink] NOT SpaceHubPlugin (${state.currentPageManager.plugin.runtimeType}), proceeding normal openPlugin');
    }

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
      Log.error(
        'Failed to open plugin for view: ${view.id}, layout: ${view.layout}',
        e,
      );
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

  /// 返回到上一文档（由 MenuSharedState.previousOpenView 记录）。
  /// 用于：在 doc A 内通过 sub_page 块自动跳转到新 doc B 后，
  /// B 的页面左上角返回按钮触发此事件，跳回 A。
  void goBackToPreviousView() {
    add(const TabsEvent.goBackToPreviousView());
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

  /// 从当前文档返回到上一文档（由 MenuSharedState.previousOpenView 记录）。
  /// 适用于：在 doc A 内通过 sub_page 块自动跳转到新 doc B 后，
  /// B 的页面左上角返回按钮触发此事件，跳回 A。
  const factory TabsEvent.goBackToPreviousView() = _GoBackToPreviousView;

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
      // 创建新列表而非原地修改，避免旧 State 对象的列表被污染
      final newPageManagers = [
        ..._pageManagers,
        PageManager()..setPlugin(plugin, true),
      ];

      return copyWith(
        currentIndex: newPageManagers.length - 1,
        pageManagers: newPageManagers,
      );
    }

    return selectExistingPlugin;
  }

  TabsState closeView(String pluginId) {
    // Avoid closing the only open tab
    if (_pageManagers.length == 1) {
      return this;
    }

    // 创建新列表而非原地修改，避免旧 State 对象的列表被污染（会导致 currentIndex 越界崩溃）
    final newPageManagers = [..._pageManagers]
      ..removeWhere((pm) => pm.plugin.id == pluginId);

    final newIndex =
        currentIndex > newPageManagers.length - 1 && currentIndex > 0
            ? currentIndex - 1
            : currentIndex;

    return copyWith(
      currentIndex: newIndex,
      pageManagers: newPageManagers,
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

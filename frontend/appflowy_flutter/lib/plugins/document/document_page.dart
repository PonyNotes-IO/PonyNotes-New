import 'dart:async';

import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:appflowy/mobile/application/page_style/document_page_style_bloc.dart';
import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/banner.dart';
import 'package:appflowy/plugins/space_hub/space_hub.dart';
import 'package:appflowy/plugins/document/presentation/editor_drop_handler.dart';
import 'package:appflowy/plugins/document/presentation/editor_page.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/ai/widgets/ai_writer_scroll_wrapper.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/cover/document_immersive_cover.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/shared_context/shared_context.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/transaction_handler/editor_transaction_service.dart';
import 'package:appflowy/plugins/document/presentation/editor_style.dart';
import 'package:appflowy/shared/flowy_error_page.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/action_navigation/action_navigation_bloc.dart';
import 'package:appflowy/workspace/application/action_navigation/navigation_action.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/prelude.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy/workspace/application/view_info/view_info_bloc.dart';
import 'package:appflowy/workspace/presentation/home/full_window_controller.dart';
import 'package:appflowy/workspace/presentation/widgets/favorite_button.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/more_view_actions.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart'
    hide AFRolePB;
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:appflowy/plugins/document/presentation/document_collaborators.dart';
import 'package:appflowy/plugins/shared/share/share_button.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra/platform_extension.dart';

import '../../startup/plugin/plugin.dart';

class DocumentPage extends StatefulWidget {
  const DocumentPage({
    super.key,
    required this.view,
    required this.onDeleted,
    required this.tabs,
    this.initialSelection,
    this.initialBlockId,
    this.fixedTitle,
    this.showShareAndFavorite = false,
    this.viewInfoBloc,
  });

  final ViewPB view;
  final VoidCallback onDeleted;
  final Selection? initialSelection;
  final String? initialBlockId;
  final String? fixedTitle;
  final List<PickerTabType> tabs;
  final bool showShareAndFavorite; // 是否显示分享和收藏工具栏
  final ViewInfoBloc? viewInfoBloc; // 可选：外部传入的 ViewInfoBloc

  @override
  State<DocumentPage> createState() => _DocumentPageState();
}

class _DocumentPageState extends State<DocumentPage>
    with WidgetsBindingObserver {
  EditorState? editorState;
  Selection? initialSelection;
  bool _handledDeletedInSpaceHub = false;
  bool _handledForceCloseNavigation = false;
  bool? _lastEditable;
  bool _editorStateRegistered = false; // 避免重复注册 ViewInfoBloc
  // 父级 view 是不是协作空间。null 表示尚未查询完成。
  // 用于决定"返回上一级文档"按钮是否显示：
  //   - parentIsSpace == true 时，按钮不应该显示（父级是协作空间，
  //     主视图是 SpaceHub，不是"上一级文档"，没有"上一级文档"可返回）；
  //   - parentIsSpace == false 时，按钮显示（父级是普通文档，点击返回
  //     可回到父级文档页面）；
  //   - 无父级（parentViewId 为空）时，按钮不显示。
  bool? _parentIsSpace;
  late final documentBloc = DocumentBloc(
      documentId: widget.view.id, workspaceId: widget.view.workspaceId)
    ..add(const DocumentEvent.initial());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadParentIsSpace();
  }

  @override
  void didUpdateWidget(covariant DocumentPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view.parentViewId != widget.view.parentViewId) {
      _parentIsSpace = null;
      _loadParentIsSpace();
    }
  }

  Future<void> _loadParentIsSpace() async {
    final parentId = widget.view.parentViewId;
    if (parentId.isEmpty) {
      if (mounted) setState(() => _parentIsSpace = false);
      return;
    }
    final result = await ViewBackendService.getView(parentId);
    if (!mounted) return;
    final parentView = result.toNullable();
    setState(() {
      _parentIsSpace = parentView?.isSpace ?? false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    documentBloc.close();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // 应用进入后台，清理 awareness states 和缓存
      documentBloc.add(const DocumentEvent.clearAwarenessStates());
      _clearDocumentCache();
    } else if (state == AppLifecycleState.resumed) {
      // 应用回到前台，同步 awareness states
      documentBloc.add(const DocumentEvent.syncAwarenessStates());
    }
  }

  /// 清理文档缓存
  void _clearDocumentCache() {
    Log.info('[DocumentPage] Clearing document cache on background');

    // 清理图片缓存
    // ImageCache.instance.clear();

    // 清理其他可能的缓存
    // ...

    Log.info('[DocumentPage] Document cache cleared');
  }

  @override
  Widget build(BuildContext context) {
    // 确定要使用的 ViewInfoBloc：优先使用传入的 bloc
    final viewInfoBloc = widget.viewInfoBloc;

    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: getIt<ActionNavigationBloc>()),
        BlocProvider.value(value: documentBloc),
        BlocProvider(
          create: (context) =>
              ViewBloc(view: widget.view)..add(const ViewEvent.initial()),
          lazy: false,
        ),
        if (viewInfoBloc != null)
          BlocProvider<ViewInfoBloc>.value(value: viewInfoBloc),
      ],
      child: BlocConsumer<PageAccessLevelBloc, PageAccessLevelState>(
        listenWhen: (prev, curr) =>
            curr.isLocked != prev.isLocked ||
            curr.accessLevel != prev.accessLevel ||
            curr.isLoadingLockStatus != prev.isLoadingLockStatus,
        listener: (context, pageAccessLevelState) {
          if (pageAccessLevelState.isLoadingLockStatus) {
            return;
          }

          final workspaceRole =
              _effectiveWorkspaceRole(context.read<UserWorkspaceBloc>().state);
          _syncEditorEditable(
            _canEditDocument(pageAccessLevelState, workspaceRole),
          );
        },
        builder: (context, pageAccessLevelState) {
          final workspaceRole = context.select(
            (UserWorkspaceBloc bloc) => _effectiveWorkspaceRole(bloc.state),
          );
          final canEditDocument =
              _canEditDocument(pageAccessLevelState, workspaceRole);
          return BlocBuilder<DocumentBloc, DocumentState>(
            buildWhen: shouldRebuildDocument,
            builder: (context, state) {
              if (state.isLoading) {
                return const Center(
                  child: CircularProgressIndicator.adaptive(),
                );
              }

              if (state.forceClose) {
                // 永久删除后，优先切回主页，避免停留在已删除文档导致错误页。
                if (!_handledForceCloseNavigation) {
                  _handledForceCloseNavigation = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) {
                      return;
                    }
                    try {
                      context.read<TabsBloc>().add(
                            TabsEvent.openPlugin(
                              plugin:
                                  makePlugin(pluginType: PluginType.homepage),
                            ),
                          );
                    } catch (_) {
                      // Fallback: if opening homepage fails, close the current tab.
                      context
                          .read<TabsBloc>()
                          .add(const TabsEvent.closeCurrentTab());
                    }
                  });
                }
                return const SizedBox.shrink();
              }

              final editorState = state.editorState;
              this.editorState = editorState;
              // 始终把当前权限同步到 editorState.editable。
              // 监听器(BlocConsumer/BlocListener)只在权限"发生变化"时触发；
              // 当文档打开时就已经是只读（无 fullAccess→readOnly 的变化），
              // 监听器不会 fire，导致 editorState.editable 没被设为 false、
              // 编辑器仍可输入。这里在每次 build 都同步，确保只读真正生效。
              if (editorState != null) {
                _syncEditorEditable(canEditDocument);
              }
              // editorState 就绪后注册到 ViewInfoBloc（仅首次），触发字数统计服务启动
              if (editorState != null && !_editorStateRegistered) {
                _editorStateRegistered = true;
                // 从 context 中获取 ViewInfoBloc
                final viewInfoBloc = context.read<ViewInfoBloc>();
                Log.debug(
                    'DocumentPage: registerEditorState for view: ${widget.view.id}, bloc hashCode: ${viewInfoBloc.hashCode}');
                viewInfoBloc.add(
                  ViewInfoEvent.registerEditorState(editorState: editorState),
                );
              }
              final error = state.error;
              if (error != null) {
                Log.error(error);
                return Center(child: AppFlowyErrorPage(error: error));
              }
              if (editorState == null) {
                // if bloc is initializing (retrying open/create), show waiting UI
                final bloc = context.read<DocumentBloc>();
                if (bloc.isInitializing) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator.adaptive(),
                        SizedBox(height: 12.0),
                        FlowyText.regular('正在准备文档，请稍候...', fontSize: 14),
                      ],
                    ),
                  );
                }
                Log.error('editorState is null and not initializing');
                return Center(child: AppFlowyErrorPage(error: error));
              }

              if (!state.isDeleted) {
                _handledDeletedInSpaceHub = false;
              }

              return MultiBlocListener(
                listeners: [
                  BlocListener<PageAccessLevelBloc, PageAccessLevelState>(
                    listener: (context, state) {
                      final workspaceRole = _effectiveWorkspaceRole(
                        context.read<UserWorkspaceBloc>().state,
                      );
                      _syncEditorEditable(
                        _canEditDocument(state, workspaceRole),
                      );
                    },
                  ),
                  BlocListener<UserWorkspaceBloc, UserWorkspaceState>(
                    listenWhen: (previous, current) =>
                        previous.currentUserRole != current.currentUserRole,
                    listener: (context, workspaceState) {
                      _syncEditorEditable(
                        _canEditDocument(
                          context.read<PageAccessLevelBloc>().state,
                          _effectiveWorkspaceRole(workspaceState),
                        ),
                      );
                    },
                  ),
                  BlocListener<ActionNavigationBloc, ActionNavigationState>(
                    listenWhen: (_, curr) => curr.action != null,
                    listener: onNotificationAction,
                  ),
                ],
                child: AiWriterScrollWrapper(
                  viewId: widget.view.id,
                  editorState: editorState,
                  child: buildEditorPage(context, state),
                ),
              );
            },
          );
        },
      ),
    );
  }

  AFRolePB? _effectiveWorkspaceRole(UserWorkspaceState state) {
    return state.currentUserRole ?? state.currentWorkspace?.role;
  }

  bool _canEditDocument(
    PageAccessLevelState pageAccessLevelState,
    AFRolePB? workspaceRole,
  ) {
    return pageAccessLevelState.isEditable && workspaceRole != AFRolePB.Guest;
  }

  void _syncEditorEditable(bool isEditable) {
    editorState?.editable = isEditable;

    final wasEditable = _lastEditable;
    _lastEditable = isEditable;
    if (wasEditable == true && !isEditable) {
      editorState?.service.keyboardService?.closeKeyboard();
      unawaited(documentBloc.discardLocalDocumentState());
    } else if (wasEditable == false && isEditable) {
      // 从只读恢复为可编辑的瞬间，先关闭输入法连接、丢弃查看期间残留在 IME
      // composing 缓冲里的预输入文本（未上屏的拼音/候选）。
      //
      // 桌面端只读时光标仍可聚焦，输入法照样 attach，A 打的字会进入 composing
      // 缓冲——这些字没经过 editorState.apply()，所以不显示在文档上；但若不清理，
      // 权限改回可编辑时这些缓冲会被一次性提交（“冒出来”）并同步给其他协作者。
      // closeKeyboard() 会清空 composingTextRange 并关闭平台输入连接，A 下次点击
      // 会重新 attach 一个干净的连接。
      editorState?.service.keyboardService?.closeKeyboard();
    }
  }

  Widget buildEditorPage(
    BuildContext context,
    DocumentState state,
  ) {
    final editorState = state.editorState;
    if (editorState == null) {
      return const SizedBox.shrink();
    }

    final width = context.read<DocumentAppearanceCubit>().state.width;

    // avoid the initial selection calculation change when the editorState is not changed
    initialSelection ??= _calculateInitialSelection(editorState);

    final Widget child;
    if (PlatformInfo.isMobile) {
      child = BlocBuilder<DocumentPageStyleBloc, DocumentPageStyleState>(
        builder: (context, styleState) => AppFlowyEditorPage(
          editorState: editorState,
          // if the view's name is empty, focus on the title
          autoFocus: widget.view.name.isEmpty ? false : null,
          styleCustomizer: EditorStyleCustomizer(
            context: context,
            width: width,
            padding: EditorStyleCustomizer.documentPadding,
            editorState: editorState,
          ),
          header: buildCoverAndIcon(context, state),
          initialSelection: initialSelection,
        ),
      );
    } else {
      child = EditorDropHandler(
        viewId: widget.view.id,
        editorState: editorState,
        isLocalMode: context.read<DocumentBloc>().isLocalMode,
        child: AppFlowyEditorPage(
          editorState: editorState,
          // if the view's name is empty, focus on the title
          autoFocus: widget.view.name.isEmpty ? false : null,
          styleCustomizer: EditorStyleCustomizer(
            context: context,
            width: width,
            padding: EditorStyleCustomizer.documentPadding,
            editorState: editorState,
          ),
          header: buildCoverAndIcon(context, state),
          initialSelection: initialSelection,
          placeholderText: (node) =>
              node.type == ParagraphBlockKeys.type && !node.isInTable
                  ? LocaleKeys.editor_slashPlaceHolder.tr()
                  : '',
        ),
      );
    }

    if (state.isDeleted && PlatformInfo.isDesktopOrTablet) {
      final shouldHandleDeletedInSpaceHub =
          _shouldHandleDeletedInSpaceHub(context);
      if (shouldHandleDeletedInSpaceHub && !_handledDeletedInSpaceHub) {
        _handledDeletedInSpaceHub = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          _refreshSpaceBlocIfNeeded(context);
          widget.onDeleted();
        });
        return const SizedBox.shrink();
      }
    }

    final editorContent = Provider(
      create: (_) {
        final context = SharedEditorContext();
        final children = editorState.document.root.children;
        final firstDelta = children.firstOrNull?.delta;
        final isEmptyDocument =
            children.length == 1 && (firstDelta == null || firstDelta.isEmpty);
        if (widget.view.name.isEmpty && isEmptyDocument) {
          context.requestCoverTitleFocus = true;
        }
        return context;
      },
      dispose: (buildContext, editorContext) => editorContext.dispose(),
      child: EditorTransactionService(
        viewId: widget.view.id,
        editorState: state.editorState!,
        child: Column(
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: FullWindowController.isFullWindow,
              builder: (context, isFullWindow, _) {
                try {
                  if (!mounted) {
                    return const SizedBox.shrink();
                  }
                  if (isFullWindow) {
                    return const SizedBox.shrink();
                  }
                  return _buildTopBar(context);
                } catch (error, stackTrace) {
                  Log.error(
                    '[DocumentPage] Error building top bar in full window mode: $error',
                    error,
                    stackTrace,
                  );
                  return const SizedBox.shrink();
                }
              },
            ),
            // the banner only shows on desktop
            if (state.isDeleted && PlatformInfo.isDesktopOrTablet)
              buildBanner(context),
            Expanded(child: child),
          ],
        ),
      ),
    );

    // 如果存在"上一文档"（例如 sub_page 自动跳转过来），显示返回按钮。
    // 侧边栏展开按钮已移至顶部栏（FlowyNavigation / HomeTopBar），不再在此处显示。
    // 监听 latestOpenView 和 previousOpenView 两个 ValueNotifier，
    // 合并两个的变更，确保 snapshot 写入后页面会重建。
    return ValueListenableBuilder<ViewPB?>(
      valueListenable: getIt<MenuSharedState>().previousOpenViewNotifier,
      builder: (context, previousView, _) {
        // previousView 仅用于触发该 ValueListenableBuilder 重建，自身不参与判断。
        // 真正决定是否显示返回按钮的是：当前 view 是否有"上一级文档"可返回。
        // 只有当父级是普通文档（不是协作空间）时，按钮才有意义——因为协作空间
        // 的主视图是 SpaceHub（不是普通 DocumentPage），不是"上一级文档"。
        // 无父级（parentViewId 为空）时同理，没有可返回的上一级文档。
        // _parentIsSpace == null 表示父级尚未查询完成，先按 false 渲染（保守不显示）
        final showBackButton = _parentIsSpace == false;
        const double buttonSize = 24.0;
        // macOS 上系统窗口按钮（关闭、最小化、最大化）占据约 88 像素宽度，
        // 需要留出足够空间避免按钮被遮挡
        // 其他平台使用较小的偏移量
        final leftBase = UniversalPlatform.isMacOS ? 48.0 : 16.0;
        final backButtonLeft = leftBase;
        final theme = AppFlowyTheme.of(context);
        return Stack(
          children: [
            editorContent,
            if (showBackButton)
              Positioned(
                top: 10,
                left: backButtonLeft,
                child: FlowyTooltip(
                  message: '返回上一文档',
                  child: FlowyIconButton(
                    width: buttonSize,
                    icon: FlowySvg(
                      FlowySvgs.arrow_left_s,
                      size: const Size.square(buttonSize),
                      color: theme.iconColorScheme.primary,
                    ),
                    onPressed: () => getIt<TabsBloc>().goBackToPreviousView(),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildTopBar(BuildContext context) {
    // 优先使用传入的 ViewInfoBloc，确保和 DocumentPage 注册 EditorState 使用同一个实例
    final effectiveViewInfoBloc = widget.viewInfoBloc;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 16.0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Share and favorite actions - only show in space hub
          if (widget.showShareAndFavorite)
            Row(
              children: [
                if (FeatureFlag.syncDocument.isOn) ...[
                  DocumentCollaborators(
                    key: ValueKey('collaborators_${widget.view.id}'),
                    width: 120,
                    height: 32,
                    view: widget.view,
                  ),
                  const SizedBox(width: 16),
                ] else
                  const SizedBox(width: 8),
                ViewFavoriteButton(
                  key: ValueKey('favorite_button_${widget.view.id}'),
                  view: widget.view,
                ),
                const SizedBox(width: 10),
                ShareButton(
                  key: ValueKey('share_button_${widget.view.id}'),
                  view: widget.view,
                ),
                const SizedBox(width: 4),
                if (effectiveViewInfoBloc != null)
                  MoreViewActions(
                      view: widget.view, viewInfoBloc: effectiveViewInfoBloc)
                else
                  MoreViewActions(view: widget.view),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTopActionsBar(BuildContext context) {
    // 优先使用传入的 ViewInfoBloc，确保和 DocumentPage 注册 EditorState 使用同一个实例
    final effectiveViewInfoBloc = widget.viewInfoBloc;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (FeatureFlag.syncDocument.isOn) ...[
            DocumentCollaborators(
              key: ValueKey('collaborators_${widget.view.id}'),
              width: 120,
              height: 32,
              view: widget.view,
            ),
            const SizedBox(width: 16),
          ] else
            const SizedBox(width: 8),
          ViewFavoriteButton(
            key: ValueKey('favorite_button_${widget.view.id}'),
            view: widget.view,
          ),
          const SizedBox(width: 10),
          ShareButton(
            key: ValueKey('share_button_${widget.view.id}'),
            view: widget.view,
          ),
          const SizedBox(width: 4),
          if (effectiveViewInfoBloc != null)
            MoreViewActions(
                view: widget.view, viewInfoBloc: effectiveViewInfoBloc)
          else
            MoreViewActions(view: widget.view),
        ],
      ),
    );
  }

  Widget buildBanner(BuildContext context) {
    return BlocListener<DocumentBloc, DocumentState>(
      listenWhen: (prev, curr) {
        // 监听恢复成功：从删除状态变为非删除状态
        // 或者监听彻底删除：forceClose 变为 true
        return (prev.isDeleted && !curr.isDeleted) ||
            (!prev.forceClose && curr.forceClose);
      },
      listener: (context, state) {
        // 恢复成功或彻底删除后，刷新 SpaceBloc 列表
        // 由于 listenWhen 已经过滤了状态变化，这里直接处理
        // 增加延迟时间，确保后端恢复操作完成（恢复可能需要更长时间）
        if (!state.isDeleted) {
          // 恢复操作：延迟更长时间，确保后端恢复操作完成
          // 使用更长的延迟，确保恢复操作完全完成
          Future.delayed(const Duration(milliseconds: 800), () {
            if (context.mounted) {
              _refreshSpaceBlocIfNeeded(context);
            }
          });
        } else if (state.forceClose) {
          // 彻底删除操作
          Future.delayed(const Duration(milliseconds: 500), () {
            if (context.mounted) {
              _refreshSpaceBlocIfNeeded(context);
            }
          });
        }
      },
      child: DocumentBanner(
        viewName: widget.view.nameOrDefault,
        onRestore: () {
          // 点击恢复按钮时，先触发恢复操作
          context.read<DocumentBloc>().add(const DocumentEvent.restorePage());
          // 同时立即触发刷新（作为备用机制，不等待状态变化）
          // 延迟一下，确保后端恢复操作完成
          Future.delayed(const Duration(milliseconds: 800), () {
            if (context.mounted) {
              _refreshSpaceBlocIfNeeded(context);
            }
          });
        },
        onDelete: () => context
            .read<DocumentBloc>()
            .add(const DocumentEvent.deletePermanently()),
      ),
    );
  }

  /// 刷新 SpaceBloc 的列表（如果存在）
  /// 用于在恢复、删除等操作后更新空间文档列表
  void _refreshSpaceBlocIfNeeded(BuildContext context) {
    try {
      // 尝试从外层 context 获取 SpaceBloc
      SpaceBloc? spaceBloc;

      // 方法1: 尝试从当前 context 读取（可能是外层提供的）
      try {
        spaceBloc = context.read<SpaceBloc>();
      } catch (_) {
        // 方法2: 通过 Navigator 获取根 context
        try {
          final navigator = Navigator.of(context, rootNavigator: false);
          final rootContext = navigator.context;
          spaceBloc = rootContext.read<SpaceBloc>();
        } catch (_) {
          // 根 context 也没有 SpaceBloc，忽略
        }
      }

      if (spaceBloc != null && !spaceBloc.isClosed) {
        // 触发子视图更新事件，刷新列表
        spaceBloc.add(const SpaceEvent.didUpdateCurrentSpaceChildViews());
      }
    } catch (_) {
      // SpaceBloc 不存在，忽略
    }
  }

  bool _shouldHandleDeletedInSpaceHub(BuildContext context) {
    try {
      final spaceBloc = context.read<SpaceBloc>();
      if (spaceBloc.isClosed) {
        return false;
      }
      final currentSpace = spaceBloc.state.currentSpace;
      return currentSpace != null;
    } catch (_) {
      return false;
    }
  }

  Widget buildCoverAndIcon(BuildContext context, DocumentState state) {
    final editorState = state.editorState;
    final userProfilePB = state.userProfilePB;
    if (editorState == null || userProfilePB == null) {
      return const SizedBox.shrink();
    }

    if (PlatformInfo.isMobile) {
      return DocumentImmersiveCover(
        fixedTitle: widget.fixedTitle,
        view: widget.view,
        tabs: widget.tabs,
        userProfilePB: userProfilePB,
      );
    }

    final page = editorState.document.root;
    return DocumentCoverWidget(
      node: page,
      tabs: widget.tabs,
      editorState: editorState,
      view: widget.view,
      onIconChanged: (icon) async => ViewBackendService.updateViewIcon(
        view: widget.view,
        viewIcon: icon,
      ),
    );
  }

  void onNotificationAction(
    BuildContext context,
    ActionNavigationState state,
  ) {
    final action = state.action;
    if (action == null ||
        action.type != ActionType.jumpToBlock ||
        action.objectId != widget.view.id) {
      return;
    }

    final editorState = context.read<DocumentBloc>().state.editorState;
    if (editorState == null) {
      return;
    }

    final Path? path = _getPathFromAction(action, editorState);
    if (path != null) {
      editorState.updateSelectionWithReason(
        Selection.collapsed(Position(path: path)),
      );
    }
  }

  Path? _getPathFromAction(NavigationAction action, EditorState editorState) {
    final path = action.arguments?[ActionArgumentKeys.nodePath];
    if (path is int) {
      return [path];
    } else if (path is List<int>?) {
      if (path == null || path.isEmpty) {
        final blockId = action.arguments?[ActionArgumentKeys.blockId];
        if (blockId != null) {
          return _findNodePathByBlockId(editorState, blockId);
        }
      }
    }
    return path;
  }

  Path? _findNodePathByBlockId(EditorState editorState, String blockId) {
    final document = editorState.document;
    final startNode = document.root.children.firstOrNull;
    if (startNode == null) {
      return null;
    }

    final nodeIterator = NodeIterator(document: document, startNode: startNode);
    while (nodeIterator.moveNext()) {
      final node = nodeIterator.current;
      if (node.id == blockId) {
        return node.path;
      }
    }

    return null;
  }

  bool shouldRebuildDocument(DocumentState previous, DocumentState current) {
    // only rebuild the document page when the below fields are changed
    // this is to prevent unnecessary rebuilds
    //
    // If you confirm the newly added fields should be rebuilt, please update
    // this function.
    if (previous.editorState != current.editorState) {
      return true;
    }

    if (previous.forceClose != current.forceClose ||
        previous.isDeleted != current.isDeleted) {
      return true;
    }

    if (previous.userProfilePB != current.userProfilePB) {
      return true;
    }

    if (previous.isLoading != current.isLoading ||
        previous.error != current.error) {
      return true;
    }

    return false;
  }

  Selection? _calculateInitialSelection(EditorState editorState) {
    if (widget.initialSelection != null) {
      return widget.initialSelection;
    }

    if (widget.initialBlockId != null) {
      final path = _findNodePathByBlockId(editorState, widget.initialBlockId!);
      if (path != null) {
        editorState.selectionType = SelectionType.block;
        editorState.selectionExtraInfo = {
          selectionExtraInfoDoNotAttachTextService: true,
        };
        return Selection.collapsed(
          Position(
            path: path,
          ),
        );
      }
    }

    return null;
  }
}

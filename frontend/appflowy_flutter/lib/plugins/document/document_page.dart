import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/application/page_style/document_page_style_bloc.dart';
import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/banner.dart';
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
import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/prelude.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/presentation/widgets/favorite_button.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/more_view_actions.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:appflowy/plugins/document/presentation/document_collaborators.dart';
import 'package:appflowy/plugins/shared/share/share_button.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';

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
    this.showShareAndFavorite = false, // 是否显示分享和收藏工具栏，默认不显示（工作区打开时不显示）
    this.isInSpaceHub = false, // 是否在 Space Hub 中打开
  });

  final ViewPB view;
  final VoidCallback onDeleted;
  final Selection? initialSelection;
  final String? initialBlockId;
  final String? fixedTitle;
  final List<PickerTabType> tabs;
  final bool showShareAndFavorite; // 是否显示分享和收藏工具栏
  final bool isInSpaceHub; // 是否在 Space Hub 中打开

  @override
  State<DocumentPage> createState() => _DocumentPageState();
}

class _DocumentPageState extends State<DocumentPage>
    with WidgetsBindingObserver {
  EditorState? editorState;
  Selection? initialSelection;
  bool _handledDeletedInSpaceHub = false;
  bool _handledForceCloseNavigation = false;
  late final documentBloc = DocumentBloc(documentId: widget.view.id, workspaceId: widget.view.workspaceId)
    ..add(const DocumentEvent.initial());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      documentBloc.add(const DocumentEvent.clearAwarenessStates());
    } else if (state == AppLifecycleState.resumed) {
      documentBloc.add(const DocumentEvent.syncAwarenessStates());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: getIt<ActionNavigationBloc>()),
        BlocProvider.value(value: documentBloc),
        BlocProvider(
          create: (context) =>
              ViewBloc(view: widget.view)..add(const ViewEvent.initial()),
          lazy: false,
        ),
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

          editorState?.editable = pageAccessLevelState.isEditable;
        },
        builder: (context, pageAccessLevelState) {
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
                              plugin: makePlugin(pluginType: PluginType.homepage),
                            ),
                          );
                    } catch (_) {
                      // Fallback: if opening homepage fails, close the current tab.
                      context.read<TabsBloc>().add(const TabsEvent.closeCurrentTab());
                    }
                  });
                }
                return const SizedBox.shrink();
              }

              final editorState = state.editorState;
              this.editorState = editorState;
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
                      editorState.editable = state.isEditable;
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
    if (UniversalPlatform.isMobile) {
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

    if (state.isDeleted && UniversalPlatform.isDesktop) {
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

    return Provider(
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
            // Top bar with back button and actions
            _buildTopBar(context),
            // the banner only shows on desktop
            if (state.isDeleted && UniversalPlatform.isDesktop)
              buildBanner(context),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0,),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Back button - only show when not in space hub and not in Space Hub
          if (!widget.showShareAndFavorite && !widget.isInSpaceHub)
            _buildBackButton(context),
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
                MoreViewActions(view: widget.view),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildBackButton(BuildContext context) {
    return FutureBuilder<List<ViewPB>>(
      future: ViewBackendService.getViewAncestors(widget.view.id).then((result) => result.fold((s) => s.items, (f) => [])),
      builder: (context, snapshot) {
        final ancestors = snapshot.data ?? [];
        final hasParent = ancestors.length > 2; // workspace + parent + current
        
        return FlowyIconButton(
          width: 32,
          height: 32,
          tooltipText: hasParent ? '返回上一级' : '返回空间',
          icon: const FlowySvg(FlowySvgs.back_m),
          onPressed: () {
            try {
              if (hasParent) {
                // Navigate to parent view
                final parentView = ancestors[ancestors.length - 2];
                
                // Check if we're in Space Hub
                if (widget.isInSpaceHub) {
                  // In Space Hub: we need to find the SpaceHubPluginWidgetBuilder
                  // and update its selected view
                  try {
                    // Find the nearest SpaceHubPluginWidgetBuilder
                    // This is a bit tricky since we don't have direct access
                    // Instead, we'll use the tabsBloc to open the parent view
                    // but with a special parameter to indicate it's from Space Hub
                    final tabsBloc = getIt<TabsBloc>();
                    tabsBloc.openPlugin(parentView);
                  } catch (e) {
                    // Fall back to normal navigation
                    final tabsBloc = getIt<TabsBloc>();
                    tabsBloc.openPlugin(parentView);
                  }
                } else {
                  // Not in Space Hub: use normal tabs navigation
                  final tabsBloc = getIt<TabsBloc>();
                  tabsBloc.openPlugin(parentView);
                }
              } else {
                // Navigate to space hub
                final tabsBloc = getIt<TabsBloc>();
                tabsBloc.add(
                  TabsEvent.openPlugin(
                    plugin: makePlugin(pluginType: PluginType.folder),
                  ),
                );
              }
            } catch (e) {
              Log.error('Failed to navigate back: $e');
            }
          },
        );
      },
    );
  }

  Widget _buildTopActionsBar(BuildContext context) {
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

    if (UniversalPlatform.isMobile) {
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

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/menu/sidebar_sections_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/folder/folder_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/folder/_folder_header.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/create_space_popup.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_item.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SectionFolder extends StatefulWidget {
  const SectionFolder({
    super.key,
    required this.title,
    required this.spaceType,
    required this.views,
    this.isHoverEnabled = true,
    required this.expandButtonTooltip,
    required this.addButtonTooltip,
  });

  final String title;
  final FolderSpaceType spaceType;
  final List<ViewPB> views;
  final bool isHoverEnabled;
  final String expandButtonTooltip;
  final String addButtonTooltip;

  @override
  State<SectionFolder> createState() => _SectionFolderState();
}

class _SectionFolderState extends State<SectionFolder> {
  final isHovered = ValueNotifier(false);

  @override
  void dispose() {
    isHovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => isHovered.value = true,
      onExit: (_) => isHovered.value = false,
      child: BlocProvider<FolderBloc>(
        create: (_) => FolderBloc(type: widget.spaceType)
          ..add(const FolderEvent.initial()),
        child: BlocBuilder<FolderBloc, FolderState>(
          builder: (context, state) => Column(
            children: [
              _buildHeader(context),
              // Pages
              ..._buildViews(context, state, isHovered),
              // Add a placeholder if there are no views
              // _buildDraggablePlaceholder(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    // 获取当前工作空间ID作为parentViewId
    final parentViewId =
        context.read<UserWorkspaceBloc>().state.currentWorkspace?.workspaceId;
    
    // 根据 spaceType 判断是否显示创建空间按钮
    // private 和 public 都支持创建空间
    final showCreateSpaceButton = widget.spaceType == FolderSpaceType.private ||
        widget.spaceType == FolderSpaceType.public;
    
    return FolderHeader(
      title: widget.title,
      isExpanded: context.watch<FolderBloc>().state.isExpanded,
      expandButtonTooltip: widget.expandButtonTooltip,
      addButtonTooltip: widget.addButtonTooltip,
      onPressed: () =>
          context.read<FolderBloc>().add(const FolderEvent.expandOrUnExpand()),
      onAdded: () {
        context.read<SidebarSectionsBloc>().add(
              SidebarSectionsEvent.createRootViewInSection(
                name: '',
                index: 0,
                viewSection: widget.spaceType.toViewSectionPB,
              ),
            );

        context
            .read<FolderBloc>()
            .add(const FolderEvent.expandOrUnExpand(isExpanded: true));
      },
      // 只为"我的空间"提供选择菜单功能
      parentViewId: parentViewId,
      onViewSelected: _onViewSelected,
      showCreateSpaceButton: showCreateSpaceButton,
      onCreateSpace: showCreateSpaceButton ? () => _showCreateSpaceDialog(context) : null,
    );
  }

  void _showCreateSpaceDialog(BuildContext context) {
    // 根据 spaceType 确定初始的 SpacePermission
    final initialPermission = widget.spaceType == FolderSpaceType.private
        ? SpacePermission.private
        : SpacePermission.publicToAll;
    
    final spaceBloc = context.read<SpaceBloc>();
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: BlocProvider.value(
          value: spaceBloc,
          child: CreateSpacePopup(
            initialPermission: initialPermission,
            disablePermissionChange: true,
          ),
        ),
      ),
    );
  }

  void _onViewSelected(
    PluginBuilder pluginBuilder,
    String? name,
    List<int>? initialDataBytes,
    bool openAfterCreated,
    bool createNewView,
  ) async {
    // 获取当前工作空间ID作为parentViewId
    final parentViewId =
        context.read<UserWorkspaceBloc>().state.currentWorkspace?.workspaceId;
    
    if (parentViewId == null) return;

    // 视图默认名称
    // 普通 Document 使用通用的默认名称；手写笔记（Saber）使用"未命名手记"
    final String viewName;
    if (pluginBuilder.pluginType == PluginType.handwritingSaber) {
      viewName = '未命名手记';
    } else {
      viewName = pluginBuilder.layoutType?.defaultName ?? '';
    }

    try {
      // 准备 extra 参数
      Map<String, String> ext = {};
      
      // 使用ViewBackendService创建指定类型的视图
      final result = await ViewBackendService.createView(
        layoutType: pluginBuilder.layoutType!,
        parentViewId: parentViewId,
        name: viewName,
        openAfterCreate: openAfterCreated,
        initialDataBytes: initialDataBytes,
        index: 0,
        section: widget.spaceType.toViewSectionPB,
        ext: ext,
      );

      await result.fold(
        (view) async {
          // 创建成功，展开文件夹以显示新创建的视图
          Log.info(
            '[SECTION_FOLDER] view created: id=${view.id}, layout=${view.layout}, extra=${view.extra}',
          );

          // 如果是 Saber 手写笔记，创建后需要在 extra 中写入 view_type，供 ViewExtension.plugin() 识别
          if (pluginBuilder.pluginType == PluginType.handwritingSaber) {
            const extraJson = '{"view_type": "handwriting_saber"}';
            final updateResult = await ViewBackendService.updateView(
              viewId: view.id,
              extra: extraJson,
            );
            updateResult.fold(
              (_) => Log.info(
                '[SECTION_FOLDER] set extra for handwriting_saber view success: ${view.id}, extra=$extraJson',
              ),
              (error) => Log.error(
                '[SECTION_FOLDER] set extra for handwriting_saber view failed: ${view.id}, error=${error.msg} (${error.code})',
              ),
            );
          }

          // 创建成功，展开文件夹以显示新创建的视图
          context
              .read<FolderBloc>()
              .add(const FolderEvent.expandOrUnExpand(isExpanded: true));
          
          // 为 Folder、Notebook、手写笔记等设置 extra 字段和默认图标
          if (pluginBuilder.layoutType == ViewLayoutPB.Folder) {
            // 设置文件夹的 extra 字段
            await ViewBackendService.updateView(
              viewId: view.id,
              extra: '{"view_type": "folder"}',
            );
            // 设置文件夹的默认 emoji 图标 📂
            await ViewBackendService.updateViewIcon(
              view: view,
              viewIcon: EmojiIconData.emoji('📂'),
            );
          } else if (pluginBuilder.layoutType == ViewLayoutPB.Notebook) {
            // 设置笔记本的 extra 字段
            await ViewBackendService.updateView(
              viewId: view.id,
              extra: '{"view_type": "notebook"}',
            );
            // 设置笔记本的默认 emoji 图标 📓
            await ViewBackendService.updateViewIcon(
              view: view,
              viewIcon: EmojiIconData.emoji('📓'),
            );
          }
          
          // 不需要手动刷新，系统会自动更新侧边栏
        },
        (error) {
          // 处理错误，可以显示错误消息
          // TODO: 可以添加错误提示
        },
      );
    } catch (e) {
      // 处理异常
      // TODO: 可以添加异常处理
    }
  }

  Iterable<Widget> _buildViews(
    BuildContext context,
    FolderState state,
    ValueNotifier<bool> isHovered,
  ) {
    if (!state.isExpanded) {
      return [];
    }

    // 为协作/个人空间的子项目设置统一缩进：私有空间和工作区都缩进一级
    final bool isIndentedSection =
        widget.spaceType == FolderSpaceType.private ||
            widget.spaceType == FolderSpaceType.public;
    final int itemLevel = isIndentedSection ? 1 : 0;

    return widget.views.map(
      (view) {
        // 识别 Space 类型和文档类型
        final bool isSpace = view.isSpace;
        final bool isDocument = view.isDocument;

        // 根据类型做不同的处理逻辑
        if (isSpace) {
          // Space 类型的特殊处理
          Log.info(
            '[SECTION_FOLDER] Building Space view: ${view.name} (id: ${view.id})',
          );
          // 可以在这里添加 Space 类型的特殊逻辑
          // 例如：不同的样式、不同的点击行为等
        } else if (isDocument) {
          // 文档类型的特殊处理
          Log.info(
            '[SECTION_FOLDER] Building Document view: ${view.name} (id: ${view.id})',
          );
          // 可以在这里添加文档类型的特殊逻辑
        }

        // 创建 ViewItem（可以根据类型传入不同的参数）
        return ViewItem(
          key: ValueKey('${widget.spaceType.name} ${view.id}'),
          spaceType: widget.spaceType,
          engagedInExpanding: !isSpace, // 空间类型不展开子集
          isFirstChild: view.id == widget.views.first.id,
          view: view,
          level: itemLevel, // 使用计算得出的缩进级别
          leftPadding: HomeSpaceViewSizes.leftPadding,
          isFeedback: false,
          isHovered: isHovered,
          enableRightClickContext: true,
          shouldRenderChildren: !isSpace, // 空间类型不渲染子视图
          shouldLoadChildViews: !isSpace, // 空间类型不加载子视图
          // 为空间类型提供自定义左侧图标，不显示展开/折叠图标
          leftIconBuilder: isSpace
              ? (context, view) => SizedBox(width: HomeSpaceViewSizes.leftPadding)
              : null,
          onSelected: (viewContext, view) {
            // 如果是 Space 类型，打开空间统一页面（SpaceHubPlugin）
            if (view.isSpace) {
              Log.info('[SECTION_FOLDER] Space clicked: ${view.name}');
              
              // 使用 SpaceBloc 打开空间（加载空间下的文档列表）
              final spaceBloc = context.read<SpaceBloc>();
              spaceBloc.add(SpaceEvent.open(space: view));
              
              // 打开空间统一页面插件
              if (HardwareKeyboard.instance.isControlPressed) {
                viewContext.read<TabsBloc>().openTab(view);
              } else {
                viewContext.read<TabsBloc>().openPlugin(view);
              }
              return;
            }
            
            // 文档类型的点击处理
            Log.info('[SECTION_FOLDER] Document clicked: ${view.name}');

            if (HardwareKeyboard.instance.isControlPressed) {
              context.read<TabsBloc>().openTab(view);
            }

            // Defensive: ensure view has a valid id before attempting to open plugin.
            if (view.id.isEmpty) {
              Log.error('[SECTION_FOLDER] Attempted to open plugin with empty view.id, aborting. view.name=${view.name}');
            } else {
              context.read<TabsBloc>().openPlugin(view);
            }
          },
          onTertiarySelected: (viewContext, view) =>
              context.read<TabsBloc>().openTab(view),
          isHoverEnabled: widget.isHoverEnabled,
        );
      },
    );
  }
}

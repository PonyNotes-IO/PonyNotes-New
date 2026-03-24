import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy/plugins/homepage/widgets/todo_plan_section.dart';
import 'package:appflowy/plugins/standalone_ai_chat/presentation/widgets/ai_input_area.dart';
import 'package:appflowy/plugins/standalone_ai_chat/models/chat_image.dart';
import 'package:appflowy/core/network/ai_model_service.dart';
import 'package:appflowy/workspace/application/view/ai_chat_view_service.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/material.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:flowy_svg/flowy_svg.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/workspace/workspace_service.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy/workspace/application/recent/recent_views_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:fixnum/fixnum.dart' as fixnum;
import 'dart:convert';
import 'package:appflowy/plugins/ai_chat/presentation/chat_page/ai_chat_usage_indicator.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:appflowy/workspace/presentation/widgets/user_avatar.dart';
import 'package:appflowy/shared/appflowy_network_image.dart';
import 'package:appflowy/util/string_extension.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:string_validator/string_validator.dart';

import '../../workspace/application/sidebar/space/space_bloc.dart';

class HomePagePluginBuilder extends PluginBuilder {
  @override
  Plugin build(dynamic data) {
    return HomePagePlugin();
  }

  @override
  String get menuName => "主页";

  @override
  FlowySvgData get icon => FlowySvgs.m_home_selected_m;

  @override
  PluginType get pluginType => PluginType.homepage;

  @override
  ViewLayoutPB? get layoutType => ViewLayoutPB.Document;
}

class HomePagePluginConfig implements PluginConfig {
  @override
  bool get creatable => false;
}

class HomePagePlugin extends Plugin {
  @override
  PluginWidgetBuilder get widgetBuilder => HomePagePluginWidgetBuilder();

  @override
  PluginId get id => "homepage";

  @override
  PluginType get pluginType => PluginType.homepage;
}

class HomePagePluginWidgetBuilder extends PluginWidgetBuilder
    with NavigationItem {
  @override
  String? get viewName => null; // 移除标题栏显示的"主页"

  @override
  Widget get leftBarItem => const SizedBox.shrink(); // 移除左侧栏显示的"主页"

  @override
  Widget tabBarItem(String pluginId, [bool shortForm = false]) =>
      const SizedBox.shrink(); // 移除标签栏显示的"主页"

  @override
  EdgeInsets get contentPadding =>
      const EdgeInsets.fromLTRB(40, 0, 40, 28); // 只移除顶部内边距，保持左右和底部内边距

  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) =>
      BlocProvider(
        create: (context) =>
            RecentViewsBloc()..add(const RecentViewsEvent.initial()),
        child: HomePage(userProfile: context.userProfile),
      );

  @override
  List<NavigationItem> get navigationItems => [this];
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.userProfile});

  final UserProfilePB? userProfile;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context
            .read<RecentViewsBloc>()
            .add(const RecentViewsEvent.fetchRecentViews());
      }
    });
  }

  // 最近访问卡片头部 5 色方案
  static const List<Color> _recentHeaderColors = [
    Color(0x0DE97418),
    Color(0x0D6EA53B),
    Color(0x0D4D7DF0),
    Color(0x0DCC7A50),
    Color(0x0D8A66D8),
  ];

  int _recentColorIndex(SectionViewPB sectionView) {
    final mixed = (sectionView.timestamp.toInt() ^
            sectionView.item.id.hashCode ^
            sectionView.item.name.hashCode)
        .abs();
    return mixed % _recentHeaderColors.length;
  }

  /// 处理来自AIInputArea的消息发送
  /// 改为创建原生AI Chat视图
  void _handleMessageSent(
      String message,
      AIModel? selectedModel,
      List<ChatImage>? images,
      bool enableDeepThinking,
      bool enableWebSearch) async {
    if (message.isEmpty) return;

    Log.info('🔄 主页: 处理消息发送');
    Log.info('   - 消息: $message');
    Log.info('   - 模型: ${selectedModel?.name} (${selectedModel?.id})');
    Log.info('   - 图片数: ${images?.length ?? 0}');
    Log.info('   - 深度思考: ${enableDeepThinking ? "开启" : "关闭"}');
    Log.info('   - 全网搜索: ${enableWebSearch ? "开启" : "关闭"}');

    try {
      // 1. 获取当前workspace ID
      final workspaceId = await AIChatViewService.getCurrentWorkspaceId();
      if (workspaceId == null) {
        Log.error('❌ 主页: 无法获取工作空间信息');
        _showError('无法获取工作空间信息');
        return;
      }

      Log.info('✅ 主页: 获取到workspace ID: $workspaceId');

      // 2. 创建并打开原生AI Chat视图
      final view = await AIChatViewService.createAndOpenAIChat(
        parentViewId: workspaceId,
        initialMessage: message,
        selectedModelId: selectedModel?.id,
        enableDeepThinking: enableDeepThinking,
        enableWebSearch: enableWebSearch,
        initialImages: images, // 传递图片数据
      );

      if (view == null) {
        Log.error('❌ 主页: 创建AI对话失败');
        _showError('创建AI对话失败');
      } else {
        Log.info('✅ 主页: AI Chat视图创建成功，view.id=${view.id}');
      }
    } catch (e, stackTrace) {
      Log.error('❌ 主页: 处理消息发送失败: $e', e, stackTrace);
      _showError('打开AI对话时发生错误: $e');
    }
  }

  void _showError(String message) {
    if (mounted) {
      showToastNotification(
        message: message,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appTheme = AppFlowyTheme.of(context);
    final now = DateTime.now();
    final hour = now.hour;
    String greeting;

    if (hour < 12) {
      greeting = "上午好";
    } else if (hour < 18) {
      greeting = "下午好";
    } else {
      greeting = "晚上好";
    }

    final userName = widget.userProfile?.name ?? "燕萍";

    return BlocListener<UserWorkspaceBloc, UserWorkspaceState>(
      listenWhen: (previous, current) =>
          previous.currentWorkspace?.workspaceId !=
          current.currentWorkspace?.workspaceId,
      listener: (context, state) {
        try {
          context
              .read<RecentViewsBloc>()
              .add(const RecentViewsEvent.resetRecentViews());
        } catch (e) {
          Log.warn('刷新首页内容失败: $e');
        }
      },
      child: BlocListener<TabsBloc, TabsState>(
        listenWhen: (previous, current) =>
            previous.currentPageManager.plugin.pluginType !=
                PluginType.homepage &&
            current.currentPageManager.plugin.pluginType == PluginType.homepage,
        listener: (context, state) {
          context
              .read<RecentViewsBloc>()
              .add(const RecentViewsEvent.resetRecentViews());
        },
        child: Container(
          color: theme.colorScheme.surface,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(90, 80.0, 90, 32.0),
            child: Column(
              children: [
              // 问候语区域 - 右对齐，与头像一起
              _buildGreetingSection(greeting, userName),
              const SizedBox(height: 50),

              // 问AI区域标题
              Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Row(
                  children: [
                    FlowySvg(
                      FlowySvgs.home_ai_icon_s,
                      size: Size(22, 18),
                      blendMode: null,
                    ),
                    const SizedBox(width: 8.0),
                    Text(
                      "问AI",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: appTheme.textColorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),

              // 问AI区域 - 复用AIInputArea组件，为主页定制更宽的显示，并在下方展示使用次数/未订阅状态
              LayoutBuilder(
                builder: (context, constraints) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AIInputArea(
                        onMessageSent: _handleMessageSent,
                        customWidth: constraints.maxWidth,
                        // 使用几乎全部可用宽度，只留8px左右边距
                        customMargin:
                            const EdgeInsets.symmetric(horizontal: 0.0),
                        // 最小边距
                        customToolbarPadding: const EdgeInsets.fromLTRB(
                          20,
                          15,
                          20,
                          13,
                        ),
                        // 左右边距各20px
                        customToolbarWidth: constraints.maxWidth -
                            40, // 工具栏宽度 = 容器宽度 - 左右边距(40)
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 50),

              // 最近访问标题
              Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 18,
                      color: appTheme.iconColorScheme.primary,
                    ),
                    const SizedBox(width: 8.0),
                    Text(
                      "最近访问",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: appTheme.textColorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),

              // 最近访问
              _buildRecentSection(),
              const SizedBox(height: 50),

              // 待办计划标题
              Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Row(
                  children: [
                    FlowySvg(
                      FlowySvgs.home_to_do_m,
                      size: const Size.square(18),
                      color: appTheme.iconColorScheme.primary,
                    ),
                    const SizedBox(width: 8.0),
                    Text(
                      "待办计划",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: appTheme.textColorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),

              // 待办计划
              TodoPlanSection(
                workspaceId: context
                    .read<UserWorkspaceBloc>()
                    .state
                    .currentWorkspace
                    ?.workspaceId,
              ),
            ],
          ),
        ),
      ),
    ),
  );
  }

  Widget _buildGreetingSection(String greeting, String userName) {
    final theme = AppFlowyTheme.of(context);
    return SizedBox(
      width: double.infinity,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 头像区域
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFECECEC),
                width: 0.59,
              ),
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/images/home_avatar.png',
                width: 60,
                height: 60,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 20),
          // 问候语文字
          Text(
            "$greeting，$userName～",
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: theme.textColorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentSection() {
    return BlocBuilder<RecentViewsBloc, RecentViewsState>(
      builder: (context, state) {
        if (state.isLoading) {
          return const SizedBox(
            height: 132,
            child: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // 允许显示空标题的文档，空标题时显示"无标题笔记"
        // 过滤掉 Space 视图，并限制显示数量
        final validRecentViews = state.views
            .where((sectionView) => !sectionView.item.isSpace) // 过滤掉 Space
            .take(4)
            .toList();

        if (validRecentViews.isEmpty) {
          // 如果没有最近访问的项目，只显示"添加笔记本"卡片
          return Align(
            alignment: Alignment.centerLeft,
            child: _buildAddNotebookCard(),
          );
        }

        return _buildRecentSectionWithArrows(validRecentViews);
      },
    );
  }

  Widget _buildRecentSectionWithArrows(List<SectionViewPB> validRecentViews) {
    return _RecentSectionWithArrows(
      recentViews: validRecentViews,
      buildCard: _buildRecentViewCard,
      buildAddCard: _buildAddNotebookCard,
    );
  }

  /// 获取或创建"最近访问"空间
  Future<ViewPB> _getOrCreateRecentAccessSpace(
      String workspaceId, fixnum.Int64 userId) async {
    const recentAccessName = '最近访问';

    // 获取工作空间服务
    final workspaceService = WorkspaceService(
      workspaceId: workspaceId,
      userId: userId,
    );

    // 获取私有空间和公共空间
    final privateViewsResult = await workspaceService.getPrivateViews();

    final privateViews = privateViewsResult.fold(
      (views) => views,
      (error) => throw Exception('获取私有空间失败: $error'),
    );

    final allSpaces = privateViews.where((view) => view.isSpace).toList();

    // 检查是否已存在"最近访问"空间
    Log.info(
        '检查私有空间中是否已存在"最近访问"，当前空间: ${allSpaces.map((v) => v.name).toList()}');
    final existingSpace = allSpaces.firstWhere(
      (space) => space.name == recentAccessName,
      orElse: () => ViewPB(),
    );

    if (existingSpace.id.isNotEmpty) {
      Log.info('找到已存在的"最近访问"空间，ID: ${existingSpace.id}');
      return existingSpace;
    }

    // 在私有空间中创建"最近访问"空间
    Log.info('在私有空间中创建新的"最近访问"空间');

    // 创建空间（参考导入笔记的逻辑）
    final spaceExtra = {
      ViewExtKeys.isSpaceKey: true,
      ViewExtKeys.spaceIconKey: '📋',
      ViewExtKeys.spaceIconColorKey: '#4A90E2',
      ViewExtKeys.spacePermissionKey: SpacePermission.private.index,
      ViewExtKeys.spaceCreatedAtKey: DateTime.now().millisecondsSinceEpoch,
    };

    final result = await workspaceService.createView(
      name: recentAccessName,
      viewSection: ViewSectionPB.Private,
      layout: ViewLayoutPB.Document,
      extra: jsonEncode(spaceExtra),
      setAsCurrent: false,
    );

    return result.fold(
      (view) {
        Log.info('成功创建"最近访问"空间，ID: ${view.id}');
        return view;
      },
      (error) => throw Exception('创建最近访问空间失败: $error'),
    );
  }

  /// 处理添加笔记本点击事件
  void _handleAddNotebook() async {
    try {
      // 获取当前用户和工作空间信息
      final userResult = await UserBackendService.getCurrentUserProfile();
      final workspaceResult =
          await FolderEventGetCurrentWorkspaceSetting().send();

      final userProfile = userResult.fold((user) => user, (error) => null);
      final workspaceId = workspaceResult.fold(
        (setting) => setting.workspaceId,
        (error) => null,
      );

      if (userProfile == null || workspaceId == null || workspaceId.isEmpty) {
        if (mounted) {
          showToastNotification(
            message: '无法获取当前用户或工作空间信息',
            type: ToastificationType.error,
          );
        }
        return;
      }

      // 先获取或创建"最近访问"空间
      final recentAccessSpace =
          await _getOrCreateRecentAccessSpace(workspaceId, userProfile.id);

      // 在"最近访问"空间中创建笔记本视图
      final result = await ViewBackendService.createView(
        parentViewId: recentAccessSpace.id,
        name: '新笔记本',
        layoutType: ViewLayoutPB.Document,
        openAfterCreate: true,
      );

      result.fold(
        (view) {
          // 成功创建，打开新创建的视图
          _openView(view);

          // 显示成功消息
          if (mounted) {
            showToastNotification(
              message: '笔记本创建成功',
              type: ToastificationType.success,
            );
          }

          // 刷新最近访问列表
          context
              .read<RecentViewsBloc>()
              .add(const RecentViewsEvent.fetchRecentViews());
        },
        (error) {
          // 显示错误消息
          if (mounted) {
            showToastNotification(
              message: '创建笔记本失败: ${error.msg}',
              type: ToastificationType.error,
            );
          }
        },
      );
    } catch (e) {
      // 显示错误消息
      if (mounted) {
        showToastNotification(
          message: '创建笔记本时发生错误: $e',
          type: ToastificationType.error,
        );
      }
    }
  }

  /// 构建最近访问项目的卡片
  Widget _buildRecentViewCard(SectionViewPB sectionView) {
    final view = sectionView.item;
    final timestamp = sectionView.timestamp;
    final colorIndex = _recentColorIndex(sectionView);
    final topHeaderColor = _recentHeaderColors[colorIndex];
    final theme = AppFlowyTheme.of(context);
    final displayTitle = view.name.isEmpty ? '无标题笔记' : view.name;

    return Container(
      width: 132,
      height: 132,
      margin: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: () => _openView(view),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.surfaceContainerColorScheme.layer01,
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(
              color: theme.borderColorScheme.primary,
              width: 1,
            ),
          ),
          child: Stack(
            children: [
              // 顶部彩色区域
              Positioned(
                top: 1,
                left: 1,
                right: 1,
                child: Container(
                  height: 30,
                  decoration: BoxDecoration(
                    color: topHeaderColor.withValues(alpha: 0.15),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(11),
                      topRight: Radius.circular(11),
                    ),
                  ),
                ),
              ),

              // 底部名称和时间区域
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 94,
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // 标题：如果为空则显示"无标题笔记"
                      Tooltip(
                        message: displayTitle,
                        waitDuration: const Duration(milliseconds: 300),
                        child: Text(
                          displayTitle,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: theme.textColorScheme.primary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // 时间和头像
                      Row(
                        children: [
                          // 时间图标
                          const Icon(
                            Icons.access_time,
                            size: 15,
                            color: Color(0xFF999999),
                          ),
                          const SizedBox(width: 4),
                          // 时间文本
                          Text(
                            _formatTimeAgo(timestamp),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF999999),
                            ),
                          ),
                          const Spacer(),
                          // 用户头像
                          _buildUserAvatar(view),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 20,
                left: 16,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE97418).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.description,
                    size: 14,
                    color: Color(0xFFE97418),
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  /// 格式化时间显示
  String _formatTimeAgo(fixnum.Int64 timestamp) {
    if (timestamp.toInt() == 0) {
      return '未知';
    }

    final now = DateTime.now();
    final dateTime =
        DateTime.fromMillisecondsSinceEpoch(timestamp.toInt() * 1000);
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return '刚刚';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}分钟前';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}小时前';
    } else if (difference.inDays == 1) {
      return '1天前';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}天前';
    } else {
      // 超过7天显示具体日期
      final month = dateTime.month;
      final day = dateTime.day;
      return '$month月$day号';
    }
  }

  /// 构建用户头像
  Widget _buildUserAvatar(ViewPB view) {
    final userProfile = widget.userProfile;
    if (userProfile == null) {
      return const SizedBox.shrink();
    }

    // 检查是否是当前用户创建的视图
    final isCurrentUser =
        view.hasCreatedBy() && view.createdBy == userProfile.id;

    if (!isCurrentUser) {
      return const SizedBox.shrink();
    }

    final iconUrl = userProfile.iconUrl;
    if (iconUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    // 检查是否是URL
    if (isURL(iconUrl)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 15,
          height: 15,
          child: FlowyNetworkImage(
            url: iconUrl,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    // 如果是emoji或其他，使用UserAvatar组件
    return SizedBox(
      width: 15,
      height: 15,
      child: UserAvatar(
        iconUrl: iconUrl,
        name: userProfile.name,
        size: AFAvatarSize.xs,
      ),
    );
  }

  /// 构建"添加笔记本"卡片
  Widget _buildAddNotebookCard() {
    final theme = AppFlowyTheme.of(context);
    return Container(
      width: 132,
      height: 132,
      margin: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: _handleAddNotebook,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.surfaceContainerColorScheme.layer01,
            borderRadius: BorderRadius.circular(10.0),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF8D69).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add,
                  size: 24,
                  color: Color(0xFFFF8D69),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "新建笔记",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 打开视图
  void _openView(ViewPB view) async {
    try {
      // 使用TabsBloc来打开视图
      final plugin = view.plugin();
      context.read<TabsBloc>().add(
            TabsEvent.openPlugin(
              plugin: plugin,
              view: view,
            ),
          );
    } catch (e) {
      // 显示错误消息
      if (mounted) {
        showToastNotification(
          message: '打开视图时发生错误: $e',
          type: ToastificationType.error,
        );
      }
    }
  }
}

/// 带左右滑动箭头的最近访问区域
class _RecentSectionWithArrows extends StatefulWidget {
  const _RecentSectionWithArrows({
    required this.recentViews,
    required this.buildCard,
    required this.buildAddCard,
  });

  final List<SectionViewPB> recentViews;
  final Widget Function(SectionViewPB) buildCard;
  final Widget Function() buildAddCard;

  @override
  State<_RecentSectionWithArrows> createState() =>
      _RecentSectionWithArrowsState();
}

class _RecentSectionWithArrowsState extends State<_RecentSectionWithArrows> {
  late final ScrollController _scrollController;
  bool _showLeftArrow = false;
  bool _showRightArrow = true;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_updateArrowVisibility);
    // 延迟检查，确保ListView已构建
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateArrowVisibility();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateArrowVisibility);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateArrowVisibility() {
    if (!_scrollController.hasClients) {
      return;
    }

    final newShowLeft = _scrollController.offset > 10;
    final newShowRight = _scrollController.offset <
        _scrollController.position.maxScrollExtent - 10;

    if (newShowLeft != _showLeftArrow || newShowRight != _showRightArrow) {
      setState(() {
        _showLeftArrow = newShowLeft;
        _showRightArrow = newShowRight;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SizedBox(
          height: 132,
          child: ListView.builder(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            itemCount: widget.recentViews.length + 1,
            itemBuilder: (context, index) {
              if (index == widget.recentViews.length) {
                return widget.buildAddCard();
              }
              return widget.buildCard(widget.recentViews[index]);
            },
          ),
        ),
        // 左箭头
        if (_showLeftArrow)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Theme.of(context).colorScheme.surface,
                    Theme.of(context).colorScheme.surface.withOpacity(0),
                  ],
                ),
              ),
              child: IconButton(
                icon: const Icon(Icons.chevron_left, size: 24),
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                onPressed: () {
                  _scrollController.animateTo(
                    _scrollController.offset - 150,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                },
              ),
            ),
          ),
        // 右箭头
        if (_showRightArrow)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  colors: [
                    Theme.of(context).colorScheme.surface,
                    Theme.of(context).colorScheme.surface.withOpacity(0),
                  ],
                ),
              ),
              child: IconButton(
                icon: const Icon(Icons.chevron_right, size: 24),
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                onPressed: () {
                  _scrollController.animateTo(
                    _scrollController.offset + 150,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

/// 首页问AI区域下方的使用情况/未订阅提示
class _HomeAIUsageIndicator extends StatelessWidget {
  const _HomeAIUsageIndicator();

  Future<FlowyResult<WorkspaceUsagePB?, FlowyError>> _loadUsage(
    BuildContext context,
  ) async {
    final workspaceBloc = context.read<UserWorkspaceBloc>();
    final workspaceId = workspaceBloc.state.currentWorkspace?.workspaceId;
    if (workspaceId == null || workspaceId.isEmpty) {
      Log.warn('[HomeAIUsage] 当前 workspaceId 为空，跳过使用情况查询');
      return FlowyResult.success(null);
    }

    final service = WorkspaceService(
      workspaceId: workspaceId,
      // getWorkspaceUsage 目前只使用 workspaceId，这里传 0 即可
      userId: fixnum.Int64.ZERO,
    );

    Log.info('[HomeAIUsage] 调用 getWorkspaceUsage, workspaceId=$workspaceId');
    return service.getWorkspaceUsage();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FlowyResult<WorkspaceUsagePB?, FlowyError>>(
      future: _loadUsage(context),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final result = snapshot.data!;
        return result.fold(
          (usage) {
            return AIChatUsageIndicator(usage: usage);
          },
          (error) {
            Log.error('[HomeAIUsage] 获取使用情况失败: $error');
            return const SizedBox.shrink();
          },
        );
      },
    );
  }
}

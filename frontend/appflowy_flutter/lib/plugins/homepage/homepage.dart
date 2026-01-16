import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy/plugins/homepage/widgets/todo_plan_section.dart';
import 'package:appflowy/plugins/standalone_ai_chat/presentation/widgets/ai_input_area.dart';
import 'package:appflowy/plugins/standalone_ai_chat/models/chat_image.dart';
import 'package:appflowy/core/network/ai_model_service.dart';
import 'package:appflowy/workspace/application/view/ai_chat_view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/material.dart';
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
import 'package:appflowy/plugins/ai_chat/presentation/chat_page/ai_chat_usage_indicator.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
  Widget tabBarItem(String pluginId, [bool shortForm = false]) => const SizedBox.shrink(); // 移除标签栏显示的"主页"

  @override
  EdgeInsets get contentPadding => const EdgeInsets.fromLTRB(40, 0, 40, 28); // 只移除顶部内边距，保持左右和底部内边距

  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) =>
      BlocProvider(
        create: (context) => RecentViewsBloc()..add(const RecentViewsEvent.initial()),
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

  /// 处理来自AIInputArea的消息发送
  /// 改为创建原生AI Chat视图
  void _handleMessageSent(String message, AIModel? selectedModel, List<ChatImage>? images, bool enableDeepThinking, bool enableWebSearch) async {
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
        initialImages: images,  // 传递图片数据
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
        // 当工作区切换时，刷新最近访问和待办计划
        try {
          // 刷新最近访问
          context.read<RecentViewsBloc>().add(
                const RecentViewsEvent.resetRecentViews(),
              );
          
          // 刷新待办计划 - 需要找到 TodoBloc
          // 由于 TodoBloc 在 TodoPlanSection 内部创建，我们需要通过其他方式刷新
          // 这里先刷新最近访问，待办计划的刷新会在 TodoPlanSection 中处理
        } catch (e) {
          Log.warn('刷新首页内容失败: $e');
        }
      },
      child: Container(
      color: Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(0, 80.0, 0, 32.0),
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
                  Image.asset(
                    'assets/images/home_ai_icon.png',
                    width: 22,
                    height: 18,
                  ),
                  const SizedBox(width: 8.0),
                  const Text(
                    "问AI",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF636363),
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
                      customWidth: constraints
                          .maxWidth, // 使用几乎全部可用宽度，只留8px左右边距
                      customMargin:
                          const EdgeInsets.symmetric(horizontal: 0.0), // 最小边距
                      customToolbarPadding: const EdgeInsets.fromLTRB(
                        20,
                        15,
                        20,
                        13,
                      ), // 左右边距各20px
                      customToolbarWidth: constraints.maxWidth -
                          40, // 工具栏宽度 = 容器宽度 - 左右边距(40)
                    ),
                    const SizedBox(height: 8),
                    const _HomeAIUsageIndicator(),
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
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                  const SizedBox(width: 8.0),
                  const Text(
                    "最近访问",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF636363),
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
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                  const SizedBox(width: 8.0),
                  const Text(
                    "待办计划",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF636363),
                    ),
                  ),
                ],
              ),
            ),

            // 待办计划
            const TodoPlanSection(),
          ],
          ),
        ),
      ),
    );
  }

  Widget _buildGreetingSection(String greeting, String userName) {
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
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Color(0xFF333333),
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

        // 过滤掉可能的无效视图，并限制显示数量
        final validRecentViews = state.views
            .where((sectionView) => sectionView.item.name.isNotEmpty) // 基本验证
            .take(6)
            .toList();

        if (validRecentViews.isEmpty) {
          // 如果没有最近访问的项目，只显示"添加笔记本"卡片
          return Align(
            alignment: Alignment.centerLeft,
            child: _buildAddNotebookCard(),
          );
        }

        return SizedBox(
          height: 132,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: validRecentViews.length + 1, // +1 for the "添加笔记本" card
            itemBuilder: (context, index) {
              if (index == validRecentViews.length) {
                // 最后一个位置显示"添加笔记本"卡片
                return _buildAddNotebookCard();
              }
              
              final recentView = validRecentViews[index];
              return _buildRecentViewCard(recentView.item);
            },
          ),
        );
      },
    );
  }

  /// 处理添加笔记本点击事件
  void _handleAddNotebook() async {
    try {
      // 获取当前用户和工作空间信息
      final userResult = await UserBackendService.getCurrentUserProfile();
      final workspaceResult = await FolderEventGetCurrentWorkspaceSetting().send();
      
      final userProfile = userResult.fold((user) => user, (error) => null);
      final workspaceId = workspaceResult.fold(
        (setting) => setting.workspaceId,
        (error) => null,
      );
      
      if (userProfile == null || workspaceId == null || workspaceId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('无法获取当前用户或工作空间信息'),
              duration: Duration(seconds: 3),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // 使用WorkspaceService创建笔记本视图
      final workspaceService = WorkspaceService(
        workspaceId: workspaceId,
        userId: userProfile.id,
      );

      // 创建Document类型的视图（而不是Notebook类型）
      final result = await workspaceService.createView(
        name: '新笔记本',
        viewSection: ViewSectionPB.Public, // 创建在公共区域，这样在"我的空间"中可见
        layout: ViewLayoutPB.Document, // 使用Document类型，这是稳定可用的类型
        setAsCurrent: true,
      );

      result.fold(
        (view) {
          // 成功创建，打开新创建的视图
          _openView(view);
          
          // 显示成功消息
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('笔记本创建成功'),
                duration: Duration(seconds: 2),
                backgroundColor: Colors.green,
              ),
            );
          }
          
           // 刷新最近访问列表
           context.read<RecentViewsBloc>().add(const RecentViewsEvent.fetchRecentViews());
        },
        (error) {
          // 显示错误消息
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('创建笔记本失败: ${error.msg}'),
                duration: const Duration(seconds: 3),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
      );
    } catch (e) {
      // 显示错误消息
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('创建笔记本时发生错误: $e'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 构建最近访问项目的卡片
  Widget _buildRecentViewCard(ViewPB view) {
    return Container(
      width: 132,
      height: 132,
      margin: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: () => _openView(view),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(10.0),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Stack(
            children: [
              // 顶部灰色区域
              Positioned(
                top: 1,
                left: 1,
                right: 1,
                child: Container(
                  height: 65,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(9),
                      topRight: Radius.circular(9),
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF8D69).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                       child: const Icon(
                         Icons.description,
                         size: 24,
                         color: Color(0xFFFF8D69),
                       ),
                    ),
                  ),
                ),
              ),
              
              // 底部名称区域
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 66,
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        view.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建"添加笔记本"卡片
  Widget _buildAddNotebookCard() {
    return Container(
      width: 132,
      height: 132,
      margin: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: _handleAddNotebook,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
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
                "添加笔记本",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('打开视图时发生错误: $e'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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


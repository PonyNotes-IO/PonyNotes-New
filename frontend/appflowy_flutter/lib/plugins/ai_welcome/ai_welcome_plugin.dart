import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/plugins/standalone_ai_chat/presentation/ai_welcome_page.dart';
import 'package:appflowy/plugins/standalone_ai_chat/models/chat_image.dart';
import 'package:appflowy/core/network/ai_model_service.dart';
import 'package:appflowy/workspace/application/view/ai_chat_view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/material.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';

class AIWelcomePluginBuilder extends PluginBuilder {
  @override
  Plugin build(dynamic data) {
    return AIWelcomePlugin();
  }

  @override
  String get menuName => "问AI";

  @override
  FlowySvgData get icon => FlowySvgs.icon_ai_s;

  @override
  PluginType get pluginType => PluginType.aiWelcome;

  @override
  ViewLayoutPB? get layoutType => null;
}

class AIWelcomePluginConfig implements PluginConfig {
  @override
  bool get creatable => false;
}

class AIWelcomePlugin extends Plugin {
  @override
  PluginWidgetBuilder get widgetBuilder => AIWelcomePluginWidgetBuilder();

  @override
  PluginId get id => "ai_welcome";

  @override
  PluginType get pluginType => PluginType.aiWelcome;
}

class AIWelcomePluginWidgetBuilder extends PluginWidgetBuilder
    with NavigationItem {
  @override
  String? get viewName => null; // 不显示标题

  @override
  Widget get leftBarItem => const SizedBox.shrink(); // 不显示左侧栏

  @override
  Widget tabBarItem(String pluginId, [bool shortForm = false]) => const SizedBox.shrink(); // 不显示标签栏

  @override
  EdgeInsets get contentPadding => EdgeInsets.zero; // 无内边距

  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) =>
      AIWelcomePluginPage();

  @override
  List<NavigationItem> get navigationItems => [this];
}

class AIWelcomePluginPage extends StatefulWidget {
  const AIWelcomePluginPage({super.key});

  @override
  State<AIWelcomePluginPage> createState() => _AIWelcomePluginPageState();
}

class _AIWelcomePluginPageState extends State<AIWelcomePluginPage> {
  /// 处理来自AIWelcomePage的消息发送
  void _handleMessageSent(String message, AIModel? selectedModel, List<ChatImage>? images) async {
    if (message.isEmpty) return;
    
    Log.info('🔄 AI欢迎页: 处理消息发送');
    Log.info('   - 消息: $message');
    Log.info('   - 模型: ${selectedModel?.name} (${selectedModel?.id})');
    Log.info('   - 图片数: ${images?.length ?? 0}');
    
    try {
      // 1. 获取当前workspace ID
      final workspaceId = await AIChatViewService.getCurrentWorkspaceId();
      if (workspaceId == null) {
        Log.error('❌ AI欢迎页: 无法获取工作空间信息');
        _showError('无法获取工作空间信息');
        return;
      }

      Log.info('✅ AI欢迎页: 获取到workspace ID: $workspaceId');
      
      // 2. 创建并打开原生AI Chat视图
      final view = await AIChatViewService.createAndOpenAIChat(
        parentViewId: workspaceId,
        initialMessage: message,
        selectedModelId: selectedModel?.id,
      );

      if (view == null) {
        Log.error('❌ AI欢迎页: 创建AI对话失败');
        _showError('创建AI对话失败');
      } else {
        Log.info('✅ AI欢迎页: AI Chat视图创建成功，view.id=${view.id}');
      }
    } catch (e, stackTrace) {
      Log.error('❌ AI欢迎页: 处理消息发送失败: $e', e, stackTrace);
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
    return AIWelcomePage(
      onMessageSent: _handleMessageSent,
    );
  }
}


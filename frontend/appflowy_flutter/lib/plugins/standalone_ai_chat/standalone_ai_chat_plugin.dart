import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-ai/entities.pb.dart';
import 'package:appflowy/core/config/ai_config.dart';
import 'package:flowy_infra_ui/style_widget/text.dart';
import 'package:flutter/material.dart';

import 'standalone_ai_chat_page.dart';

class StandaloneAiChatPluginBuilder extends PluginBuilder {
  @override
  Plugin build(dynamic data) {
    String? initialText;
    AIModelPB? selectedModel;
    String? selectedModelName;
    List<dynamic>? initialImages;
    AIProvider? selectedProvider;
    
    // data 可以是 null（默认情况）、String、或 Map
    if (data == null) {
      // 默认情况，所有参数为null
    } else if (data is String) {
      initialText = data;
    } else if (data is Map<String, dynamic>) {
      initialText = data['initialText'] as String?;
      selectedModel = data['selectedModel'] as AIModelPB?;
      selectedModelName = data['selectedModelName'] as String?;
      selectedProvider = data['selectedProvider'] as AIProvider?;
      initialImages = data['initialImages'] as List<dynamic>?;
      
      // 如果有选择的提供商但没有模型名称，使用提供商的显示名称
      if (selectedProvider != null && selectedModelName == null) {
        selectedModelName = selectedProvider.displayName;
      }
    }
    
    return StandaloneAiChatPlugin(
      pluginType: pluginType,
      initialText: initialText,
      selectedModel: selectedModel,
      selectedModelName: selectedModelName,
      selectedProvider: selectedProvider,
      initialImages: initialImages,
    );
  }

  @override
  String get menuName => "StandaloneAiChatPB";

  @override
  FlowySvgData get icon => FlowySvgs.m_home_ai_chat_icon_m;

  @override
  PluginType get pluginType => PluginType.standaloneAiChat;

  @override
  ViewLayoutPB get layoutType => ViewLayoutPB.Document;
}

class StandaloneAiChatPluginConfig implements PluginConfig {
  @override
  bool get creatable => false;
}

class StandaloneAiChatPlugin extends Plugin {
  StandaloneAiChatPlugin({
    required PluginType pluginType,
    this.initialText,
    this.selectedModel,
    this.selectedModelName,
    this.selectedProvider,
    List<dynamic>? initialImages,
  }) : _pluginType = pluginType, 
       _instanceId = DateTime.now().millisecondsSinceEpoch,
       initialImages = initialImages?.toList(); // 创建深拷贝

  final PluginType _pluginType;
  final int _instanceId;
  final String? initialText;
  final AIModelPB? selectedModel;
  final String? selectedModelName;
  final AIProvider? selectedProvider;
  final List<dynamic>? initialImages;

  @override
  PluginWidgetBuilder get widgetBuilder {
    return StandaloneAiChatPluginDisplay(
      initialText: initialText,
      selectedModel: selectedModel,
      selectedModelName: selectedModelName,
      selectedProvider: selectedProvider,
      initialImages: initialImages,
    );
  }

  @override
  PluginId get id => "StandaloneAiChatStack";

  @override
  PluginType get pluginType => _pluginType;
}

class StandaloneAiChatPluginDisplay extends PluginWidgetBuilder {
  StandaloneAiChatPluginDisplay({
    this.initialText, 
    this.selectedModel,
    this.selectedModelName,
    this.selectedProvider,
    this.initialImages,
  });

  final String? initialText;
  final AIModelPB? selectedModel;
  final String? selectedModelName;
  final AIProvider? selectedProvider;
  final List<dynamic>? initialImages;

  @override
  String? get viewName => '问AI';

  @override
  Widget get leftBarItem => const FlowyText.medium('问AI');

  @override
  Widget tabBarItem(String pluginId, [bool shortForm = false]) => leftBarItem;

  @override
  Widget? get rightBarItem => null;

  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) {
    final userProfile = context.userProfile;

    if (userProfile == null) {
      return const Center(
        child: Text('用户信息未加载'),
      );
    }

    return StandaloneAiChatPage(
      key: const ValueKey('StandaloneAiChatPage'),
      userProfile: userProfile,
      initialText: initialText,
      selectedModel: selectedModel,
      selectedModelName: selectedModelName,
      selectedProvider: selectedProvider,
      initialImages: initialImages,
    );
  }

  @override
  List<NavigationItem> get navigationItems => [this];

  @override
  EdgeInsets get contentPadding => EdgeInsets.zero; // 去除所有留白
}


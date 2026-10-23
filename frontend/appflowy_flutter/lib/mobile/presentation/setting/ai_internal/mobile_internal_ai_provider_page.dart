import 'package:appflowy/features/ai_internal/presentation/ai_provider_settings_view.dart';
import 'package:appflowy/mobile/presentation/base/app_bar/mobile_app_bar.dart';
import 'package:flutter/material.dart';

/// 移动端的内部 AI 模型配置页，复用桌面端的设置视图。
class MobileInternalAiProviderPage extends StatelessWidget {
  const MobileInternalAiProviderPage({super.key});

  static const routeName = '/mobile-internal-ai-provider';

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: MobileAppBar(title: '内部 AI 模型'),
      body: AiProviderSettingsView(),
    );
  }
}

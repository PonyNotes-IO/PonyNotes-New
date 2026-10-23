import 'package:appflowy/features/ai_internal/presentation/ai_chat_view.dart';
import 'package:appflowy/mobile/presentation/base/app_bar/mobile_app_bar.dart';
import 'package:flutter/material.dart';

/// 移动端的内部 AI 对话页，复用桌面端的 [AiChatView]。
class MobileInternalAiPage extends StatelessWidget {
  const MobileInternalAiPage({super.key});

  static const routeName = '/mobile-internal-ai';

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: MobileAppBar(title: '内部 AI 对话'),
      body: AiChatView(),
    );
  }
}

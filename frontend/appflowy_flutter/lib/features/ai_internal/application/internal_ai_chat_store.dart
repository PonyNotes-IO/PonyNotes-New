import 'package:appflowy/features/ai_internal/application/internal_ai_service.dart';
import 'package:flutter/foundation.dart';

/// 对话里的一轮：用户提问，或 AI 的回复（含工具调用记录）。
class AiChatTurn {
  AiChatTurn({
    required this.isUser,
    required this.text,
    this.toolCalls = const [],
  });

  factory AiChatTurn.user(String text) => AiChatTurn(isUser: true, text: text);

  factory AiChatTurn.assistant(String text, List<AiToolCallRecord> toolCalls) =>
      AiChatTurn(isUser: false, text: text, toolCalls: toolCalls);

  final bool isUser;
  final String text;
  final List<AiToolCallRecord> toolCalls;
}

/// 内部 AI 对话的会话状态。
///
/// 设置对话框按页面重建子树，页面一换对话就没了，所以状态放在单例里。
class InternalAiChatStore extends ChangeNotifier {
  InternalAiChatStore._();

  static final InternalAiChatStore instance = InternalAiChatStore._();

  final List<AiChatTurn> turns = [];

  /// 供下一轮使用的 OpenAI 格式历史，只放 user/assistant 文本。
  final List<Map<String, dynamic>> history = [];

  String? error;

  void addTurn(AiChatTurn turn) {
    turns.add(turn);
    notifyListeners();
  }

  void addHistory(String question, String answer) {
    history.add({'role': 'user', 'content': question});
    history.add({'role': 'assistant', 'content': answer});
    notifyListeners();
  }

  void setError(String? value) {
    error = value;
    notifyListeners();
  }

  void reset() {
    turns.clear();
    history.clear();
    error = null;
    notifyListeners();
  }
}

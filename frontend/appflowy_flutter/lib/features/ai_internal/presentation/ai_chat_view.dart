import 'package:appflowy/features/ai_internal/application/internal_ai_chat_store.dart';
import 'package:appflowy/features/ai_internal/application/internal_ai_service.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:flutter/material.dart';

/// 内部 AI 的对话界面：一问一答，工具调用逐条展示，写操作先确认。
///
/// 模型地址 / 模型名 / API Key 由「内部 AI 模型」页配置；未配置时这里只提示，不发请求。
class AiChatView extends StatefulWidget {
  const AiChatView({super.key});

  @override
  State<AiChatView> createState() => _AiChatViewState();
}

class _AiChatViewState extends State<AiChatView> {
  final _service = InternalAiService();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _store = InternalAiChatStore.instance;

  bool _sending = false;
  bool _configured = true;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
    _refreshConfigured();
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    _service.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshConfigured() async {
    final config = await _service.loadConfig();
    if (!mounted) return;
    setState(() => _configured = _service.isConfigured(config));
  }

  Future<void> _send() async {
    final question = _controller.text.trim();
    if (question.isEmpty || _sending) return;

    _controller.clear();
    setState(() => _sending = true);
    _store.setError(null);
    _store.addTurn(AiChatTurn.user(question));
    _scrollToEnd();

    try {
      final result = await _service.ask(
        question: question,
        history: List<Map<String, dynamic>>.of(_store.history),
        confirmWrite: _confirmWrite,
      );
      _store.addHistory(question, result.text);
      if (!mounted) return;
      _store.addTurn(AiChatTurn.assistant(result.text, result.toolCalls));
      setState(() => _configured = true);
    } on InternalAiException catch (e) {
      if (!mounted) return;
      // 用户主动中断，不当作错误展示
      if (e.kind == InternalAiErrorKind.canceled) return;
      _store.setError(e.message);
      if (e.kind == InternalAiErrorKind.notConfigured) {
        setState(() => _configured = false);
      }
    } catch (e) {
      if (!mounted) return;
      _store.setError('请求失败：$e');
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToEnd();
    }
  }

  /// 写操作确认：执行前弹一次框，拒绝则整轮中止，工具不会执行。
  Future<bool> _confirmWrite(AiToolCallRecord pending) async {
    if (!mounted) return false;
    final allowed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认写操作'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('AI 想执行：${pending.name}'),
              const VSpace(8),
              Text(
                _argumentSummary(pending.arguments),
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('执行'),
          ),
        ],
      ),
    );
    return allowed ?? false;
  }


  /// markdown_widget 的默认主题不跟随应用主题，深色模式下代码块和引用几乎是白的。
  MarkdownConfig _markdownConfig(AppFlowyThemeData theme) {
    final primary = theme.textColorScheme.primary;
    final secondary = theme.textColorScheme.secondary;
    final body = theme.textStyle.body.standard(color: primary);
    final codeBackground = theme.fillColorScheme.contentHover;
    return MarkdownConfig(
      configs: [
        PConfig(textStyle: body.copyWith(fontSize: 13)),
        H1Config(style: body.copyWith(fontSize: 20, fontWeight: FontWeight.bold)),
        H2Config(style: body.copyWith(fontSize: 17, fontWeight: FontWeight.bold)),
        H3Config(style: body.copyWith(fontSize: 15, fontWeight: FontWeight.bold)),
        CodeConfig(style: TextStyle(backgroundColor: codeBackground)),
        PreConfig(
          decoration: BoxDecoration(
            color: codeBackground,
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: body.copyWith(fontSize: 12, fontFamily: 'monospace'),
          language: 'plaintext',
        ),
        BlockquoteConfig(sideColor: secondary, textColor: secondary),
        LinkConfig(
          style: body.copyWith(
            fontSize: 13,
            color: secondary,
            decoration: TextDecoration.underline,
          ),
        ),
      ],
    );
  }

  void _stop() {
    _service.cancel();
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: FlowyText(
                  '内部 AI 对话',
                  fontSize: 20,
                  color: theme.textColorScheme.primary,
                ),
              ),
              if (_store.turns.isNotEmpty)
                TextButton(
                  onPressed: _sending ? null : _store.reset,
                  child: const Text('新对话'),
                ),
            ],
          ),
          const VSpace(4),
          FlowyText(
            '用你配置的模型理解意图，并能读写本机笔记。写操作会先问你。',
            fontSize: 12,
            color: theme.textColorScheme.secondary,
          ),
          const VSpace(12),
          if (!_configured) _buildNotConfigured(context),
          Expanded(
            child: _store.turns.isEmpty && _store.error == null
                ? _buildEmpty(context)
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: _store.turns.length,
                    itemBuilder: (context, index) =>
                        _buildTurn(context, _store.turns[index]),
                  ),
          ),
          if (_store.error != null) ...[
            const VSpace(8),
            FlowyText(
              _store.error!,
              fontSize: 13,
              color: Theme.of(context).colorScheme.error,
            ),
          ],
          const VSpace(8),
          _buildComposer(context),
        ],
      ),
    );
  }

  Widget _buildNotConfigured(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppFlowyTheme.of(context).surfaceColorScheme.layer01,
        borderRadius: BorderRadius.circular(8),
      ),
      child: FlowyText(
        '还没有配置模型。先在设置里的「内部 AI 模型」填写地址、模型名称和 API Key。',
        fontSize: 12,
        color: AppFlowyTheme.of(context).textColorScheme.secondary,
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Center(
      child: FlowyText(
        '可以试试：\n· 帮我总结最近改过的页面\n· 在我的空间里找「会议」相关的笔记',
        fontSize: 13,
        color: theme.textColorScheme.secondary,
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildTurn(BuildContext context, AiChatTurn turn) {
    final theme = AppFlowyTheme.of(context);
    final isUser = turn.isUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isUser
                  ? theme.fillColorScheme.contentHover
                  : theme.surfaceColorScheme.layer01,
              borderRadius: BorderRadius.circular(8),
            ),
            child: turn.isUser
                ? FlowyText(
                    turn.text,
                    fontSize: 13,
                    color: theme.textColorScheme.primary,
                  )
                : MarkdownWidget(
                    data: turn.text,
                    shrinkWrap: true,
                    config: _markdownConfig(theme),
                  ),
          ),
          for (final record in turn.toolCalls)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: FlowyText(
                '工具 ${record.name}${record.isError ? '（失败）' : ''}'
                '  ${_argumentSummary(record.arguments)}',
                fontSize: 11,
                color: record.isError
                    ? Theme.of(context).colorScheme.error
                    : theme.textColorScheme.secondary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildComposer(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            decoration: const InputDecoration(
              hintText: '问点什么，或者让它帮你整理笔记',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        const HSpace(8),
        FilledButton(
          onPressed: _sending ? _stop : _send,
          child: _sending
              ? const Icon(Icons.stop, size: 18)
              : const Text('发送'),
        ),
      ],
    );
  }
}

String _argumentSummary(Map<String, dynamic> arguments) {
  if (arguments.isEmpty) return '';
  final text = arguments.entries
      .map((entry) => '${entry.key}=${entry.value}')
      .join(', ');
  return text.length <= 120 ? text : '${text.substring(0, 120)}…';
}

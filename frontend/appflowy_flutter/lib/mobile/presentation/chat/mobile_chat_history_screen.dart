import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MobileChatHistoryScreen extends StatefulWidget {
  const MobileChatHistoryScreen({super.key});

  static const routeName = '/chat-history';

  @override
  State<MobileChatHistoryScreen> createState() =>
      _MobileChatHistoryScreenState();
}

class _MobileChatHistoryScreenState extends State<MobileChatHistoryScreen> {
  List<ViewPB> _chatViews = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadChatViews();
  }

  Future<void> _loadChatViews() async {
    final result = await ViewBackendService.getAllViews();
    result.fold(
      (views) {
        final chatViews = views.items
            .where((v) => v.layout == ViewLayoutPB.Chat)
            .toList();
        chatViews.sort(
          (a, b) => b.lastEdited.toInt().compareTo(a.lastEdited.toInt()),
        );
        if (mounted) {
          setState(() {
            _chatViews = chatViews;
            _isLoading = false;
          });
        }
      },
      (error) {
        if (mounted) {
          setState(() {
            _errorMessage = error.msg;
            _isLoading = false;
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _ChatHistoryAppBar(
              onBack: () => Navigator.of(context).maybePop(),
            ),
            const Divider(height: 1),
            // Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? _ErrorView(message: _errorMessage!)
                      : _chatViews.isEmpty
                          ? const _EmptyChatHistory()
                          : _ChatHistoryList(
                              chatViews: _chatViews,
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatHistoryAppBar extends StatelessWidget {
  const _ChatHistoryAppBar({
    required this.onBack,
  });

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: FlowySvg(
              FlowySvgs.mobile_return_s,
              size: const Size(7, 12),
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 4),
            Expanded(
              child: Text(
                '历史对话',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _ChatHistoryList extends StatelessWidget {
  const _ChatHistoryList({
    required this.chatViews,
  });

  final List<ViewPB> chatViews;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: chatViews.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final view = chatViews[index];

        return Material(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () {
              context.push(
                '/chat?id=${Uri.encodeComponent(view.id)}&title=${Uri.encodeComponent(view.name)}',
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  const FlowySvg(FlowySvgs.m_ai_history_m),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      view.name.isEmpty ? '无标题对话' : view.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  FlowySvg(
                    FlowySvgs.toolbar_arrow_right_m,
                    size: const Size.square(14),
                    color: theme.hintColor,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyChatHistory extends StatelessWidget {
  const _EmptyChatHistory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const FlowySvg(
            FlowySvgs.m_empty_trash_xl,
            size: Size.square(46),
          ),
          const SizedBox(height: 16.0),
          Text(
            '暂无对话记录',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8.0),
          Text(
            '开始新的 AI 对话吧',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).hintColor,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const FlowySvg(
            FlowySvgs.m_home_search_icon_m,
            size: Size.square(46),
          ),
          const SizedBox(height: 16.0),
          Text(
            '加载失败',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8.0),
          Text(
            message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).hintColor,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

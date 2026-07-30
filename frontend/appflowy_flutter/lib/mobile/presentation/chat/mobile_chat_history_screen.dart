import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/bottom_sheet.dart';
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

  String _formatTime(int timestamp) {
    if (timestamp == 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        return '${diff.inMinutes}分钟前';
      }
      return '${diff.inHours}小时前';
    } else if (diff.inDays == 1) {
      return '昨天';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}天前';
    } else {
      return '${date.month}/${date.day}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _ChatHistoryAppBar(
              onBack: () => Navigator.of(context).maybePop(),
              onMorePressed: _chatViews.isEmpty
                  ? null
                  : () => _showMoreOptions(context),
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
                              formatTime: _formatTime,
                            ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMoreOptions(BuildContext context) {
    showMobileBottomSheet(
      context,
      showDragHandle: true,
      showDivider: false,
      useRootNavigator: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: '操作',
      builder: (bottomSheetContext) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BottomSheetActionWidget(
              svg: FlowySvgs.m_delete_m,
              text: '清空历史记录',
              onTap: () {
                Navigator.pop(bottomSheetContext);
                _confirmDeleteAll(context);
              },
            ),
          ],
        );
      },
    );
  }

  void _confirmDeleteAll(BuildContext context) {
    // TODO: 实现清空逻辑（调用后端 delete view 接口）
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('清空功能开发中')),
    );
  }
}

class _ChatHistoryAppBar extends StatelessWidget {
  const _ChatHistoryAppBar({
    required this.onBack,
    this.onMorePressed,
  });

  final VoidCallback onBack;
  final VoidCallback? onMorePressed;

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
              'AI 对话历史',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ),
          if (onMorePressed != null)
            IconButton(
              onPressed: onMorePressed,
              icon: FlowySvg(
                FlowySvgs.three_dots_s,
                size: const Size.square(24),
                color: theme.colorScheme.onSurface,
              ),
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _ChatHistoryList extends StatelessWidget {
  const _ChatHistoryList({
    required this.chatViews,
    required this.formatTime,
  });

  final List<ViewPB> chatViews;
  final String Function(int) formatTime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: chatViews.length,
      separatorBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Divider(
          height: 1,
          color: theme.dividerColor,
        ),
      ),
      itemBuilder: (context, index) {
        final view = chatViews[index];
        final timeStr = formatTime(view.lastEdited.toInt());

        return InkWell(
          onTap: () {
            context.push(
              '/chat?id=${Uri.encodeComponent(view.id)}&title=${Uri.encodeComponent(view.name)}',
            );
          },
          child: Container(
            color: theme.colorScheme.surface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // Chat icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: FlowySvg(
                      FlowySvgs.m_home_ai_chat_icon_m,
                      size: const Size.square(22),
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        view.name.isEmpty ? '无标题对话' : view.name,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (timeStr.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          timeStr,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.hintColor,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FlowySvg(
                  FlowySvgs.toolbar_arrow_right_m,
                  size: const Size.square(16),
                  color: theme.hintColor,
                ),
              ],
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

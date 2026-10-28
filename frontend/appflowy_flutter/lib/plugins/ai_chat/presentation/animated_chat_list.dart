// ignore_for_file: implementation_imports

import 'dart:async';

import 'package:appflowy/util/debounce.dart';
import 'package:appflowy_backend/log.dart';
import 'package:diffutil_dart/diffutil.dart' as diffutil;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/src/scroll_to_bottom.dart';
import 'package:flutter_chat_ui/src/utils/message_list_diff.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flowy_infra/platform_extension.dart';

import '../application/chat_message_height_manager.dart';
import 'widgets/message_height_calculator.dart';

class ChatAnimatedList extends StatefulWidget {
  const ChatAnimatedList({
    super.key,
    required this.scrollController,
    required this.itemBuilder,
    this.insertAnimationDuration = const Duration(milliseconds: 250),
    this.removeAnimationDuration = const Duration(milliseconds: 250),
    this.scrollToEndAnimationDuration = const Duration(milliseconds: 250),
    this.scrollToBottomAppearanceDelay = const Duration(milliseconds: 250),
    this.bottomPadding = 8,
    this.onLoadPreviousMessages,
    this.scrollBottomPadding = 440,
  });

  final ScrollController scrollController;
  final ChatItem itemBuilder;
  final Duration insertAnimationDuration;
  final Duration removeAnimationDuration;
  final Duration scrollToEndAnimationDuration;
  final Duration scrollToBottomAppearanceDelay;
  final double? bottomPadding;
  final VoidCallback? onLoadPreviousMessages;
  final double scrollBottomPadding;

  @override
  State<ChatAnimatedList> createState() => _ChatAnimatedListState();
}

class _ChatAnimatedListState extends State<ChatAnimatedList>
    with SingleTickerProviderStateMixin {
  late final ChatController chatController = Provider.of<ChatController>(
    context,
    listen: false,
  );
  late List<Message> oldList;
  late StreamSubscription<ChatOperation> operationsSubscription;

  late final AnimationController scrollToBottomController;
  late final Animation<double> scrollToBottomAnimation;
  Timer? scrollToBottomShowTimer;

  final ScrollOffsetController scrollOffsetController =
      ScrollOffsetController();

  final ItemScrollController itemScrollController = ItemScrollController();

  final ScrollOffsetListener scrollOffsetListener =
      ScrollOffsetListener.create();

  final ItemPositionsListener itemPositionsListener =
      ItemPositionsListener.create();

  int lastUserMessageIndex = 0;
  bool isScrollingToBottom = false;

  /// 是否跟随最新内容（AI 流式输出时把视口贴在列表底部）。
  ///
  /// 用户主动向上滚动查看历史后置为 false，回到底部后重新置为 true。
  /// 流式增量走 ChatOperationType.set，原来的 _onDiffUpdate 是空实现，
  /// 导致回答超过一屏后新内容全部生成在屏幕外。
  bool _stickToBottom = true;

  /// 用户是否正在用手指拖动列表，用来区分用户滚动与程序滚动
  bool _isUserDragging = false;

  /// 保证一帧内只安排一次跟随滚动
  bool _followScheduled = false;

  /// 正在把最新一条用户消息滚到顶部，期间不要插手滚动
  bool _isScrollingToUserMessage = false;

  final loadPreviousMessagesDebounce = Debounce(
    duration: const Duration(milliseconds: 200),
  );

  int initialScrollIndex = 0;
  double initialAlignment = 1.0;
  List<Message> messages = [];

  final ChatMessageHeightManager heightManager = ChatMessageHeightManager();

  @override
  void initState() {
    super.initState();

    // TODO: Add assert for messages having same id
    oldList = List.from(chatController.messages);
    operationsSubscription = chatController.operationsStream.listen((event) {
      setState(() {
        messages = chatController.messages;
      });
      switch (event.type) {
        case ChatOperationType.insert:
          assert(
            event.index != null,
            'Index must be provided when inserting a message.',
          );
          assert(
            event.message != null,
            'Message must be provided when inserting a message.',
          );

          _onInserted(event.index!, event.message!);
          oldList = List.from(chatController.messages);
          break;
        case ChatOperationType.remove:
          assert(
            event.index != null,
            'Index must be provided when removing a message.',
          );
          assert(
            event.message != null,
            'Message must be provided when removing a message.',
          );

          _onRemoved(event.index!, event.message!);
          oldList = List.from(chatController.messages);
          break;
        case ChatOperationType.set:
          final newList = chatController.messages;

          final updates = diffutil
              .calculateDiff<Message>(
                MessageListDiff(oldList, newList),
              )
              .getUpdatesWithData();

          for (var i = updates.length - 1; i >= 0; i--) {
            _onDiffUpdate(updates.elementAt(i));
          }

          oldList = List.from(newList);
          break;
        default:
          break;
      }
    });

    messages = chatController.messages;

    scrollToBottomController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    scrollToBottomAnimation = CurvedAnimation(
      parent: scrollToBottomController,
      curve: Curves.easeInOut,
    );

    itemPositionsListener.itemPositions.addListener(() {
      _handleToggleScrollToBottom();
    });

    itemPositionsListener.itemPositions.addListener(() {
      _handleLoadPreviousMessages();
    });
  }

  @override
  void dispose() {
    scrollToBottomShowTimer?.cancel();
    scrollToBottomController.dispose();
    operationsSubscription.cancel();

    _clearMessageHeightCache();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final builders = context.watch<Builders>();

    // A trick to avoid the first message being scrolled to the top
    initialScrollIndex = messages.length;
    initialAlignment = 1.0;
    if (messages.length <= 2) {
      initialScrollIndex = 0;
      initialAlignment = 0.0;
    }

    // Mobile-only behavior change: when the message list is short the
    // Stack must fill its parent (instead of collapsing to the list's
    // intrinsic content height) so that no empty band appears between
    // the last message and the input bar rendered below. On
    // desktop/tablet the list keeps its original shrinkWrap layout,
    // and the ScrollToBottom button keeps its original centered
    // Positioned placement.
    final bool fillMode = PlatformInfo.isMobile;

    final Widget list = ScrollablePositionedList.builder(
      scrollOffsetController: scrollOffsetController,
      itemScrollController: itemScrollController,
      initialScrollIndex: initialScrollIndex,
      initialAlignment: initialAlignment,
      scrollOffsetListener: scrollOffsetListener,
      itemPositionsListener: itemPositionsListener,
      physics: ClampingScrollPhysics(),
      shrinkWrap: !fillMode,
      itemCount: messages.length + 1,
      itemBuilder: (context, index) {
        if (index < 0 || index > messages.length) {
          Log.error('[chat animation list] index out of range: $index');
          return const SizedBox.shrink();
        }

        if (index == messages.length) {
          return const SizedBox.shrink();
        }

        final message = messages[index];
        return MessageHeightCalculator(
          messageId: message.id,
          onHeightMeasured: _cacheMessageHeight,
          child: widget.itemBuilder(
            context,
            Tween<double>(begin: 1, end: 1).animate(
              CurvedAnimation(
                parent: scrollToBottomController,
                curve: Curves.easeInOut,
              ),
            ),
            message,
          ),
        );
      },
    );

    final Widget scrollToBottom = builders.scrollToBottomBuilder?.call(
          context,
          scrollToBottomAnimation,
          _handleScrollToBottom,
        ) ??
        ScrollToBottom(
          animation: scrollToBottomAnimation,
          onPressed: _handleScrollToBottom,
        );

    final Widget child = fillMode
        ? Stack(
            children: [
              Positioned.fill(child: list),
              scrollToBottom,
            ],
          )
        : Stack(
            children: [
              list,
              scrollToBottom,
            ],
          );

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: Listener(
        // 桌面/平板的滚轮、触控板滚动不带 dragDetails，单独靠指针信号判断
        onPointerSignal: _handlePointerSignal,
        child: child,
      ),
    );
  }

  /// 只跟踪用户主动滚动，程序滚动（跟随最新内容）不会改变跟随状态
  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _isUserDragging = true;
    } else if (notification is ScrollEndNotification) {
      _isUserDragging = false;
    } else if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null &&
        _isUserDragging) {
      // 拖动过程中实时更新：离开底部就停止跟随，回到底部再恢复
      _stickToBottom = _isContentPinnedToBottom();
    }
    return false;
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    final delta = event.scrollDelta.dy;
    if (delta < 0) {
      // 向上滚：用户回看历史，暂停跟随
      _stickToBottom = false;
    } else if (delta > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isContentPinnedToBottom()) {
          _stickToBottom = true;
        }
      });
    }
  }

  /// 列表底部（最后一条消息或末尾哨兵）是否已经贴在视口底部
  bool _isContentPinnedToBottom() {
    final positions = itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) {
      return _stickToBottom;
    }
    final maxItem = positions.reduce(
      (a, b) => a.index >= b.index ? a : b,
    );
    if (messages.isEmpty || maxItem.index < messages.length - 1) {
      return false;
    }
    return maxItem.itemTrailingEdge >= 0.99;
  }

  void _scheduleFollowBottom() {
    if (!_stickToBottom || _followScheduled) {
      return;
    }
    _followScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _followScheduled = false;
      if (!mounted) {
        return;
      }
      _followBottomIfNeeded();
    });
  }

  void _followBottomIfNeeded() {
    if (!_stickToBottom ||
        messages.isEmpty ||
        !itemScrollController.isAttached ||
        isScrollingToBottom ||
        _isScrollingToUserMessage) {
      return;
    }

    final lastMessageIndex = messages.length - 1;
    ItemPosition? lastMessagePosition;
    for (final position in itemPositionsListener.itemPositions.value) {
      if (position.index == lastMessageIndex) {
        lastMessagePosition = position;
        break;
      }
    }

    if (lastMessagePosition != null) {
      final viewportHeight = context.size?.height ?? 0;
      if (viewportHeight > 0) {
        // 内容还没超出视口（回答刚开始），不做滚动，保持"用户消息在顶部"的布局
        final overflow =
            (lastMessagePosition.itemTrailingEdge - 1.0) * viewportHeight;
        if (overflow <= 2.0) {
          return;
        }
      }
    }

    _jumpToBottom();
  }

  void _jumpToBottom() {
    if (!itemScrollController.isAttached) {
      return;
    }
    // 末尾哨兵项（index == messages.length，高度 0）对齐到视口底部即为列表底部
    itemScrollController.jumpTo(
      index: messages.length,
      alignment: 1.0,
    );
  }

  Future<void> _scrollLastUserMessageToTop() async {
    final user = Provider.of<User>(context, listen: false);
    final lastUserMessageIndex = messages.lastIndexWhere(
      (message) => message.author.id == user.id,
    );

    // waiting for the ai answer message to be inserted
    if (lastUserMessageIndex == -1 ||
        lastUserMessageIndex + 1 >= messages.length) {
      return;
    }

    if (this.lastUserMessageIndex != lastUserMessageIndex) {
      // scroll the current message to the top
      _isScrollingToUserMessage = true;
      try {
        await itemScrollController.scrollTo(
          index: lastUserMessageIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } finally {
        _isScrollingToUserMessage = false;
      }
    }

    this.lastUserMessageIndex = lastUserMessageIndex;
  }

  Future<void> _handleScrollToBottom() async {
    isScrollingToBottom = true;
    _stickToBottom = true;

    scrollToBottomShowTimer?.cancel();

    try {
      await scrollToBottomController.reverse();

      // index 上限是 itemCount - 1，itemCount == messages.length + 1
      await itemScrollController.scrollTo(
        index: messages.length,
        alignment: 1.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } finally {
      isScrollingToBottom = false;
    }
  }

  void _handleToggleScrollToBottom() {
    if (isScrollingToBottom) {
      return;
    }

    // get the max item
    final sortedItems = itemPositionsListener.itemPositions.value.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final maxItem = sortedItems.lastOrNull;

    if (maxItem == null) {
      return;
    }

    if (maxItem.index > messages.length - 1 ||
        (maxItem.index == messages.length - 1 &&
            maxItem.itemTrailingEdge <= 1.01)) {
      scrollToBottomShowTimer?.cancel();
      scrollToBottomController.reverse();
      return;
    }

    scrollToBottomShowTimer?.cancel();
    scrollToBottomShowTimer = Timer(widget.scrollToBottomAppearanceDelay, () {
      if (mounted) {
        scrollToBottomController.forward();
      }
    });
  }

  void _handleLoadPreviousMessages() {
    final sortedItems = itemPositionsListener.itemPositions.value.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final minItem = sortedItems.firstOrNull;

    if (minItem == null || minItem.index > 0) {
      return;
    }

    if (minItem.itemLeadingEdge <= 1.5) {
      loadPreviousMessagesDebounce.call(
        () {
          widget.onLoadPreviousMessages?.call();
        },
      );
    }
  }

  void _cacheMessageHeight(String messageId, double height) {
    heightManager.cacheHeight(messageId: messageId, height: height);
  }

  void _clearMessageHeightCache() {
    heightManager.clearCache();
  }

  Future<void> _onInserted(final int position, final Message data) async {
    // scroll the last user message to the top if it's the last message
    if (position == oldList.length) {
      // 新消息追加在末尾说明用户刚发问，重新开启跟随，保证回答能被看到
      _stickToBottom = true;
      await _scrollLastUserMessageToTop();
      _scheduleFollowBottom();
    }
  }

  void _onRemoved(final int position, final Message data) {
    // Clean up cached height for removed message
    heightManager.removeFromCache(messageId: data.id);
  }

  void _onDiffUpdate(diffutil.DataDiffUpdate<Message> update) {
    // AI 流式输出走的是 set 操作 + change 增量：内容是向下长高的，
    // 只要用户没有主动向上滚动，就把视口跟到底部。
    _scheduleFollowBottom();
  }
}

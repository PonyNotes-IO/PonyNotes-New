import 'dart:math';
import 'dart:async';
import 'package:flowy_infra/platform_extension.dart';

import 'package:universal_platform/universal_platform.dart';

class MessageHeightConstants {
  static const String answerSuffix = '_ans';

  static const String withoutMinHeightSuffix = '_without_min_height';

  // This offset comes from the chat input box height + navigation bar height
  // It's used to calculate the minimum height for answer messages
  //
  //  navigation bar height + last user message height
  //    + last AI message height + chat input box height = screen height
  static const double defaultDesktopScreenOffset = 220.0;
  static const double defaultMobileScreenOffset = 304.0;

  static const double relatedQuestionOffset = 72.0;
}

class ChatMessageHeightManager {
  factory ChatMessageHeightManager() => _instance;

  ChatMessageHeightManager._() {
    _startPeriodicCleanup();
  }

  static final ChatMessageHeightManager _instance =
      ChatMessageHeightManager._();

  static const int _maxCacheSize = 500;
  static const Duration _cleanupInterval = Duration(hours: 1);

  final Map<String, double> _heightCache = <String, double>{};
  Timer? _cleanupTimer;

  double get defaultScreenOffset {
    if (PlatformInfo.isMobile) {
      return MessageHeightConstants.defaultMobileScreenOffset;
    }
    return MessageHeightConstants.defaultDesktopScreenOffset;
  }

  /// Cache a message height
  void cacheHeight({
    required String messageId,
    required double height,
  }) {
    if (messageId.isEmpty || height <= 0) {
      assert(false, 'messageId or height is invalid');
      return;
    }

    _ensureCacheLimit();
    _heightCache[messageId] = height;
  }

  void cacheWithoutMinHeight({
    required String messageId,
    required double height,
  }) {
    if (messageId.isEmpty || height <= 0) {
      assert(false, 'messageId or height is invalid');
      return;
    }

    _ensureCacheLimit();
    _heightCache[messageId + MessageHeightConstants.withoutMinHeightSuffix] =
        height;
  }

  void _ensureCacheLimit() {
    if (_heightCache.length >= _maxCacheSize) {
      final keysToRemove = _heightCache.keys.take(_maxCacheSize ~/ 4).toList();
      for (final key in keysToRemove) {
        _heightCache.remove(key);
      }
    }
  }

  double? getCachedHeight({
    required String messageId,
  }) {
    if (messageId.isEmpty) return null;

    final height = _heightCache[messageId];
    return height;
  }

  double? getCachedWithoutMinHeight({
    required String messageId,
  }) {
    if (messageId.isEmpty) return null;
    final height =
        _heightCache[messageId + MessageHeightConstants.withoutMinHeightSuffix];
    return height;
  }

  /// Calculate minimum height for AI answer messages
  ///
  /// For the user message, we don't need to calculate the minimum height
  double calculateMinHeight({
    required String messageId,
    required double screenHeight,
  }) {
    if (!isAnswerMessage(messageId)) return 0.0;

    final originalMessageId = getOriginalMessageId(
      messageId: messageId,
    );
    final cachedHeight = getCachedHeight(
      messageId: originalMessageId,
    );

    if (cachedHeight == null) {
      return 0.0;
    }

    final calculatedHeight = screenHeight - cachedHeight - defaultScreenOffset;
    return max(calculatedHeight, 0.0);
  }

  /// Calculate minimum height for related question messages
  ///
  /// For the user message, we don't need to calculate the minimum height
  double calculateRelatedQuestionMinHeight({
    required String messageId,
  }) {
    final cacheHeight = getCachedHeight(
      messageId: messageId,
    );
    final cacheHeightWithoutMinHeight = getCachedWithoutMinHeight(
      messageId: messageId,
    );
    double minHeight = 0;
    if (cacheHeight != null && cacheHeightWithoutMinHeight != null) {
      minHeight = cacheHeight -
          cacheHeightWithoutMinHeight -
          MessageHeightConstants.relatedQuestionOffset;
    }
    minHeight = max(minHeight, 0);
    return minHeight;
  }

  bool isAnswerMessage(String messageId) {
    return messageId.endsWith(MessageHeightConstants.answerSuffix);
  }

  /// Get the original message ID from an answer message ID
  ///
  /// Answer message ID is like: "message_id_ans"
  /// Original message ID is like: "message_id"
  String getOriginalMessageId({
    required String messageId,
  }) {
    if (!isAnswerMessage(messageId)) {
      return messageId;
    }

    return messageId.replaceAll(MessageHeightConstants.answerSuffix, '');
  }

  void removeFromCache({
    required String messageId,
  }) {
    if (messageId.isEmpty) return;

    _heightCache.remove(messageId);

    final answerMessageId = messageId + MessageHeightConstants.answerSuffix;
    _heightCache.remove(answerMessageId);
  }

  void clearCache() {
    _heightCache.clear();
  }

  void _startPeriodicCleanup() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) {
      if (_heightCache.length > _maxCacheSize ~/ 2) {
        _ensureCacheLimit();
      }
    });
  }

  void dispose() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    clearCache();
  }
}

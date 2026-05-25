import 'dart:io';

import 'package:flutter/material.dart';
import 'webview_cache_manager.dart';

/// WebView元素在编辑器中的数据模型
/// 用于在手写笔记画布中嵌入可交互的网页
class WebViewEditorElement extends ChangeNotifier {
  /// 唯一标识符，在笔记中唯一
  int id;

  /// 原始网页URL
  String url;

  /// 网页标题（可选）
  String? title;

  /// 所属页面索引
  int pageIndex;

  /// 是否允许交互
  bool isInteractive;

  /// 缓存的HTML文件路径（相对于笔记文件）
  String? cachedHtmlPath;

  /// 缓存时间戳
  int? cacheTimestamp;

  /// 网页在画布上的位置和大小
  late Rect _dstRect;
  Rect get dstRect => _dstRect;
  set dstRect(Rect rect) {
    _dstRect = rect;
    // 确保最小尺寸
    const minWebViewSize = 100.0;
    if (_dstRect.width < minWebViewSize ||
        _dstRect.height < minWebViewSize) {
      final scale = _dstRect.width < minWebViewSize
          ? minWebViewSize / _dstRect.width
          : minWebViewSize / _dstRect.height;
      _dstRect = Rect.fromLTWH(
        _dstRect.left,
        _dstRect.top,
        _dstRect.width * scale,
        _dstRect.height * scale,
      );
    }
    notifyListeners();
  }

  /// 页面大小，用于确保WebView不会太大
  Size? pageSize;

  /// 是否是新创建的WebView（用于初始化时自动激活）
  bool newWebView;

  /// 回调：移动WebView
  void Function(WebViewEditorElement, Rect)? onMoveWebView;

  /// 回调：删除WebView
  void Function(WebViewEditorElement)? onDeleteWebView;

  /// 回调：其他变更
  void Function()? onMiscChange;

  /// 回调：加载完成
  VoidCallback? onLoad;

  /// 默认WebView宽度
  static const double defaultWebViewWidth = 600;

  /// 默认WebView高度
  static const double defaultWebViewHeight = 400;

  WebViewEditorElement({
    required this.id,
    required this.url,
    required this.pageIndex,
    this.title,
    this.isInteractive = true,
    this.cachedHtmlPath,
    this.cacheTimestamp,
    this.pageSize,
    this.newWebView = true,
    Rect dstRect = Rect.zero,
    this.onMoveWebView,
    this.onDeleteWebView,
    this.onMiscChange,
    this.onLoad,
  }) : _dstRect = dstRect {
    // 如果没有指定位置和大小，使用默认值
    if (dstRect == Rect.zero) {
      _dstRect = Rect.fromLTWH(
        0,
        0,
        defaultWebViewWidth,
        defaultWebViewHeight,
      );
    }
  }

  /// 从JSON反序列化
  factory WebViewEditorElement.fromJson(
    Map<String, dynamic> json, {
    required String sbnPath,
  }) {
    final id = json['id'] as int;
    final url = json['url'] as String;
    final pageIndex = json['i'] as int? ?? 0;
    final title = json['t'] as String?;
    final isInteractive = json['int'] as bool? ?? true;
    final cachedHtmlPath = json['cache'] as String?;
    final cacheTimestamp = json['ts'] as int?;

    final x = (json['x'] as num?)?.toDouble() ?? 0;
    final y = (json['y'] as num?)?.toDouble() ?? 0;
    final w = (json['w'] as num?)?.toDouble() ?? defaultWebViewWidth;
    final h = (json['h'] as num?)?.toDouble() ?? defaultWebViewHeight;

    return WebViewEditorElement(
      id: id,
      url: url,
      pageIndex: pageIndex,
      title: title,
      isInteractive: isInteractive,
      cachedHtmlPath: cachedHtmlPath,
      cacheTimestamp: cacheTimestamp,
      newWebView: false,
      dstRect: Rect.fromLTWH(x, y, w, h),
    );
  }

  /// 序列化为JSON
  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'i': pageIndex,
        if (title != null) 't': title,
        'int': isInteractive,
        if (cachedHtmlPath != null) 'cache': cachedHtmlPath,
        if (cacheTimestamp != null) 'ts': cacheTimestamp,
        'x': dstRect.left,
        'y': dstRect.top,
        'w': dstRect.width,
        'h': dstRect.height,
      };

  /// 检查缓存是否存在
  Future<bool> hasCachedContent(String sbnPath) async {
    if (cachedHtmlPath == null) return false;
    final cacheManager = WebViewCacheManager();
    return await cacheManager.hasCachedContent(sbnPath, cachedHtmlPath!);
  }

  /// 获取缓存内容
  Future<String?> getCachedContent(String sbnPath) async {
    if (cachedHtmlPath == null) return null;
    final cacheManager = WebViewCacheManager();
    return await cacheManager.loadCachedContent(sbnPath, cachedHtmlPath!);
  }

  /// 保存缓存内容
  Future<void> saveCachedContent(String sbnPath, String html) async {
    final cacheManager = WebViewCacheManager();
    final cachePath = 'webview_cache_${id}.html';
    await cacheManager.saveCachedContent(sbnPath, cachePath, html);
    cachedHtmlPath = cachePath;
    cacheTimestamp = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    onMiscChange?.call();
  }

  /// 清除缓存
  Future<void> clearCache(String sbnPath) async {
    if (cachedHtmlPath == null) return;
    final cacheManager = WebViewCacheManager();
    await cacheManager.deleteCachedContent(sbnPath, cachedHtmlPath!);
    cachedHtmlPath = null;
    cacheTimestamp = null;
    notifyListeners();
    onMiscChange?.call();
  }

  /// 复制WebView元素
  WebViewEditorElement copy() {
    return WebViewEditorElement(
      id: id,
      url: url,
      pageIndex: pageIndex,
      title: title,
      isInteractive: isInteractive,
      cachedHtmlPath: cachedHtmlPath,
      cacheTimestamp: cacheTimestamp,
      pageSize: pageSize,
      newWebView: false,
      dstRect: dstRect,
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}


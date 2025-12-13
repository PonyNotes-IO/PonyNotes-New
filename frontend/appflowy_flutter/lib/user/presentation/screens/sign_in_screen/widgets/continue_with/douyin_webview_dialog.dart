import 'dart:math';

import 'package:appflowy_backend/log.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 弹窗内嵌 WebView 完成抖音扫码登录（桌面端）
/// 
/// Note: AppID (Client Key) can be hardcoded here as it's public in OAuth flow.
/// AppSecret (Client Secret) must NEVER be in frontend code - it's only configured
/// in backend environment variables (GOTRUE_EXTERNAL_THIRD_PARTY_DOU_YIN_CLIENT_SECRET).
Future<String?> showDouYinWebViewDialog(BuildContext context) {
  // 生成随机 state，防止重放
  final state = DateTime.now().microsecondsSinceEpoch.toString() +
      Random().nextInt(100000).toString();
  // AppID 是安全的，因为它在 OAuth URL 中是公开的
  const appId = 'awwln96o098l1hik';
  const redirectUri = 'https://www.xiaomabiji.com/douyin/callback';

  final url = Uri.https(
    'open.douyin.com',
    '/platform/oauth/connect',
    <String, String>{
      'client_key': appId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': 'user_info',
      'state': state,
    },
  ).toString();

  return showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _DouYinWebViewDialog(
      authUrl: url,
      state: state,
    ),
  );
}

class _DouYinWebViewDialog extends StatefulWidget {
  const _DouYinWebViewDialog({
    required this.authUrl,
    required this.state,
  });

  final String authUrl;
  final String state;

  @override
  State<_DouYinWebViewDialog> createState() => _DouYinWebViewDialogState();
}

class _DouYinWebViewDialogState extends State<_DouYinWebViewDialog> {
  InAppWebViewController? _controller;
  bool _isLoading = true;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: theme.surfaceColorScheme.layer01,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        width: 520,
        height: 600,
        child: Column(
          children: [
            _buildHeader(theme),
            const Divider(height: 1),
            Expanded(
              child: Builder(
                builder: (context) {
                  try {
                    return Stack(
                      children: [
                        InAppWebView(
                    initialUrlRequest: URLRequest(url: WebUri(widget.authUrl)),
                    initialSettings: InAppWebViewSettings(
                      transparentBackground: true,
                      mediaPlaybackRequiresUserGesture: false,
                      javaScriptEnabled: true,
                      supportZoom: false,
                      useShouldOverrideUrlLoading: true,
                      useOnLoadResource: false,
                      cacheEnabled: true,
                      clearCache: false,
                      // Windows 特定设置
                      disableContextMenu: false,
                      disableHorizontalScroll: false,
                      disableVerticalScroll: false,
                      // 添加更多稳定性设置
                      isInspectable: false,
                      allowsLinkPreview: false,
                      allowsBackForwardNavigationGestures: false,
                      // 设置 User-Agent，模拟真实浏览器
                      userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                    ),
                    onWebViewCreated: (c) => _controller = c,
                    onLoadStop: (_, __) {
                      if (mounted) {
                        setState(() => _isLoading = false);
                      }
                    },
                    onLoadStart: (_, __) {
                      if (mounted) {
                        setState(() {
                          _isLoading = true;
                          _error = null;
                        });
                      }
                    },
                    onLoadError: (controller, url, code, message) {
                      Log.error('DouYin WebView load error: code=$code, message=$message, url=$url');
                      // 某些错误可能是正常的（如网络延迟），只在严重错误时显示
                      if (mounted && code != -999) { // -999 通常是用户取消
                        setState(() {
                          _isLoading = false;
                          // 简化错误信息，避免显示技术细节
                          if (message.contains('connection') || message.contains('网络')) {
                            _error = '网络连接失败，请检查网络后重试';
                          } else if (message.contains('SSL') || message.contains('证书')) {
                            _error = 'SSL 证书验证失败';
                          } else {
                            _error = '页面加载失败，请重试';
                          }
                        });
                      }
                    },
                    onConsoleMessage: (controller, message) {
                      Log.info('DouYin WebView console: ${message.message}');
                    },
                    onReceivedError: (controller, request, error) {
                      Log.error('DouYin WebView received error: ${error.description}, type: ${error.type}, url: ${request.url}');
                      // 不立即显示错误，因为可能是临时网络问题
                      // 只在 onLoadError 中显示最终错误
                    },
                    // 必须提供 onUpdateVisitedHistory 回调，即使为空，否则 Windows WebView2 可能崩溃
                    onUpdateVisitedHistory: (controller, url, isReload) {
                      // 最小化处理，只记录日志，不做任何可能引发崩溃的操作
                      try {
                        // 不访问 url 的任何属性，避免可能的崩溃
                        Log.info('DouYin WebView visited history updated, isReload: $isReload');
                      } catch (e) {
                        // 静默处理错误，避免崩溃
                        Log.error('DouYin WebView onUpdateVisitedHistory error: $e');
                      }
                    },
                    onLoadHttpError: (controller, url, statusCode, description) {
                      Log.error('DouYin WebView HTTP error: $statusCode $description');
                      if (mounted) {
                        setState(() {
                          _isLoading = false;
                          _error = 'HTTP错误 ($statusCode): $description';
                        });
                      }
                    },
                    onPermissionRequest: (controller, request) async {
                      // 必须处理权限请求，否则会导致 Windows WebView2 崩溃
                      // 使用 Future.microtask 确保异步操作安全
                      return Future.microtask(() {
                        try {
                          Log.info('DouYin WebView permission request: ${request.resources}');
                          // 自动批准所有权限请求（摄像头、麦克风等），避免崩溃
                          return PermissionResponse(
                            resources: request.resources,
                            action: PermissionResponseAction.GRANT,
                          );
                        } catch (e, stackTrace) {
                          Log.error('DouYin WebView onPermissionRequest error: $e', stackTrace);
                          // 如果出错，拒绝权限请求
                          return PermissionResponse(
                            resources: request.resources,
                            action: PermissionResponseAction.DENY,
                          );
                        }
                      });
                    },
                    shouldOverrideUrlLoading: (controller, action) async {
                      try {
                        final uri = action.request.url;
                        if (uri == null) {
                          return NavigationActionPolicy.ALLOW;
                        }

                        final uriString = uri.toString();
                        final scheme = uri.scheme;
                        final isCallback = uriString.contains('douyin/callback') ||
                            (scheme != null && scheme.startsWith('ponynotes'));
                        if (isCallback) {
                          final code = uri.queryParameters['code'];
                          final state = uri.queryParameters['state'];
                          Log.info('DouYin callback detected: code=${code != null ? 'present' : 'missing'}, state=$state, expectedState=${widget.state}');
                          // 检查 code 是否存在，state 可选（因为可能被抖音添加了额外参数）
                          if (code != null && code.isNotEmpty) {
                            // 如果 state 匹配，使用它；否则仍然返回 code（因为 code 是最重要的）
                            if (state == widget.state || state == null) {
                              Log.info('DouYin callback: returning code to caller');
                              if (mounted) {
                                Navigator.of(context).pop(code);
                              }
                              return NavigationActionPolicy.CANCEL;
                            } else {
                              // State 不匹配，但仍然返回 code（可能是抖音添加了额外参数）
                              Log.warn('DouYin callback: state mismatch, but returning code anyway');
                              if (mounted) {
                                Navigator.of(context).pop(code);
                              }
                              return NavigationActionPolicy.CANCEL;
                            }
                          }
                        }
                        return NavigationActionPolicy.ALLOW;
                      } catch (e) {
                        Log.error('DouYin WebView shouldOverrideUrlLoading error: $e');
                        return NavigationActionPolicy.ALLOW;
                      }
                    },
                  ),
                  if (_isLoading) const _LoadingMask(),
                  if (_error != null)
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _error!,
                            style: TextStyle(color: theme.textColorScheme.primary),
                          ),
                          const SizedBox(height: 12),
                          FlowyButton(
                            text: const Text('重试'),
                            onTap: () {
                              setState(() {
                                _isLoading = true;
                                _error = null;
                              });
                              _controller?.loadUrl(
                                urlRequest: URLRequest(url: WebUri(widget.authUrl)),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                      ],
                    );
                  } catch (e) {
                    Log.error('DouYin WebView initialization error: $e');
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'WebView 初始化失败',
                            style: TextStyle(color: theme.textColorScheme.primary),
                          ),
                          const SizedBox(height: 12),
                          FlowyButton(
                            text: const Text('关闭'),
                            onTap: () => Navigator.of(context).maybePop(),
                          ),
                        ],
                      ),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppFlowyThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(
            '抖音扫码登录',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: theme.textColorScheme.primary,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.close, color: theme.textColorScheme.secondary),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

class _LoadingMask extends StatelessWidget {
  const _LoadingMask();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.04),
      child: const Center(
        child: SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
    );
  }
}

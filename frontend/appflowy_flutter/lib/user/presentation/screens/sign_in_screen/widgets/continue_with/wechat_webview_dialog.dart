import 'dart:math';

import 'package:appflowy_backend/log.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 弹窗内嵌 WebView 完成微信扫码登录（桌面端）
Future<String?> showWeChatWebViewDialog(BuildContext context) {
  // 生成随机 state，防止重放
  final state = DateTime.now().microsecondsSinceEpoch.toString() +
      Random().nextInt(100000).toString();
  const appId = 'wxf2bf9058a11e9e14';
  const redirectUri = 'https://www.xiaomabiji.com/wechat/callback';

  final url = Uri.https(
    'open.weixin.qq.com',
    '/connect/qrconnect',
    <String, String>{
      'appid': appId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': 'snsapi_login',
      'state': state,
    },
  ).toString();

  return showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _WeChatWebViewDialog(
      authUrl: url,
      state: state,
    ),
  );
}

class _WeChatWebViewDialog extends StatefulWidget {
  const _WeChatWebViewDialog({
    required this.authUrl,
    required this.state,
  });

  final String authUrl;
  final String state;

  @override
  State<_WeChatWebViewDialog> createState() => _WeChatWebViewDialogState();
}

class _WeChatWebViewDialogState extends State<_WeChatWebViewDialog> {
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
              child: Stack(
                children: [
                  InAppWebView(
                    initialUrlRequest: URLRequest(url: WebUri(widget.authUrl)),
                    initialSettings: InAppWebViewSettings(
                      transparentBackground: true,
                      mediaPlaybackRequiresUserGesture: false,
                      javaScriptEnabled: true,
                      supportZoom: false,
                    ),
                    onWebViewCreated: (c) => _controller = c,
                    onLoadStop: (_, __) {
                      setState(() => _isLoading = false);
                    },
                    onLoadStart: (_, __) {
                      setState(() {
                        _isLoading = true;
                        _error = null;
                      });
                    },
                    onLoadError: (controller, url, code, message) {
                      Log.error('WeChat WebView load error: $code $message');
                      setState(() {
                        _isLoading = false;
                        _error = '加载页面失败 ($code)';
                      });
                    },
                    shouldOverrideUrlLoading: (controller, action) async {
                      try {
                      final uri = action.request.url;
                      if (uri == null) {
                        return NavigationActionPolicy.ALLOW;
                      }

                        final uriString = uri.toString();
                        final isCallback = uriString.contains('wechat/callback') ||
                            (uri.scheme != null && uri.scheme!.startsWith('ponynotes'));
                      if (isCallback) {
                        final code = uri.queryParameters['code'];
                        final state = uri.queryParameters['state'];
                        if (code != null && state == widget.state) {
                          if (mounted) {
                            Navigator.of(context).pop(code);
                          }
                          return NavigationActionPolicy.CANCEL;
                        }
                      }
                      return NavigationActionPolicy.ALLOW;
                      } catch (e) {
                        Log.error('WeChat WebView shouldOverrideUrlLoading error: $e');
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
            '微信扫码登录',
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


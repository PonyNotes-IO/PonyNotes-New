import 'package:appflowy_backend/log.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 显示支付 WebView 弹框
/// 
/// [payUrl] 可以是 HTML form 格式或直接的 URL
/// 如果是 HTML form，会提取 action URL 和参数并加载
Future<bool?> showPaymentWebViewDialog(
  BuildContext context, {
  required String payUrl,
  String? orderNo,
  String? expireTime,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false, // 支付过程中不允许关闭
    builder: (_) => _PaymentWebViewDialog(
      payUrl: payUrl,
      orderNo: orderNo,
      expireTime: expireTime,
    ),
  );
}

class _PaymentWebViewDialog extends StatefulWidget {
  const _PaymentWebViewDialog({
    required this.payUrl,
    this.orderNo,
    this.expireTime,
  });

  final String payUrl;
  final String? orderNo;
  final String? expireTime;

  @override
  State<_PaymentWebViewDialog> createState() => _PaymentWebViewDialogState();
}

class _PaymentWebViewDialogState extends State<_PaymentWebViewDialog> {
  InAppWebViewController? _controller;
  bool _isLoading = true;
  String? _error;
  bool _paymentCompleted = false;

  /// 检查是否是 HTML form 格式
  bool get _isHtmlForm => widget.payUrl.contains('<form');

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
        width: 600,
        height: 700,
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
                          // 如果是 HTML form，直接加载 HTML 内容
                          // 否则加载 URL
                          initialData: _isHtmlForm
                              ? InAppWebViewInitialData(data: widget.payUrl)
                              : null,
                          initialUrlRequest: _isHtmlForm
                              ? null
                              : URLRequest(url: WebUri(widget.payUrl)),
                          initialSettings: InAppWebViewSettings(
                            transparentBackground: true,
                            mediaPlaybackRequiresUserGesture: false,
                            javaScriptEnabled: true,
                            supportZoom: false,
                            useShouldOverrideUrlLoading: true,
                            useOnLoadResource: false,
                            cacheEnabled: true,
                            clearCache: false,
                            disableContextMenu: false,
                            disableHorizontalScroll: false,
                            disableVerticalScroll: false,
                            isInspectable: false,
                            allowsLinkPreview: false,
                            allowsBackForwardNavigationGestures: false,
                            userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                          ),
                          onWebViewCreated: (c) {
                            _controller = c;
                            // 如果是 HTML form，页面加载完成后自动提交
                            if (_isHtmlForm) {
                              // 延迟执行，确保页面已加载
                              Future.delayed(const Duration(milliseconds: 500), () {
                                _controller?.evaluateJavascript(source: '''
                                  (function() {
                                    try {
                                      var forms = document.getElementsByTagName('form');
                                      if (forms.length > 0) {
                                        // 查找提交按钮或直接提交
                                        var submitButton = forms[0].querySelector('input[type="submit"]');
                                        if (submitButton) {
                                          submitButton.click();
                                        } else {
                                          forms[0].submit();
                                        }
                                      }
                                    } catch(e) {
                                      console.error('Auto submit error:', e);
                                    }
                                  })();
                                ''');
                              });
                            }
                          },
                          onLoadStop: (_, __) {
                            if (mounted) {
                              setState(() => _isLoading = false);
                            }
                          },
                          onLoadStart: (_, url) {
                            if (mounted) {
                              setState(() {
                                _isLoading = true;
                                _error = null;
                              });
                              
                              // 检查是否是支付成功/失败的回调 URL
                              final urlString = url?.toString() ?? '';
                              if (urlString.contains('/payment/return/') ||
                                  urlString.contains('/payment/callback/')) {
                                // 支付完成，关闭弹框
                                _handlePaymentComplete();
                              }
                            }
                          },
                          onLoadError: (controller, url, code, message) {
                            Log.error('Payment WebView load error: code=$code, message=$message, url=$url');
                            if (mounted && code != -999) {
                              setState(() {
                                _isLoading = false;
                                if (message.contains('connection') || message.contains('网络')) {
                                  _error = '网络连接失败，请检查网络后重试';
                                } else {
                                  _error = '页面加载失败，请重试';
                                }
                              });
                            }
                          },
                          onReceivedError: (controller, request, error) {
                            Log.error('Payment WebView received error: ${error.description}');
                          },
                          onUpdateVisitedHistory: (controller, url, isReload) {
                            // 检查 URL 是否是支付回调
                            final urlString = url?.toString() ?? '';
                            if (urlString.contains('/payment/return/') ||
                                urlString.contains('/payment/callback/')) {
                              _handlePaymentComplete();
                            }
                          },
                          onLoadHttpError: (controller, url, statusCode, description) {
                            Log.error('Payment WebView HTTP error: $statusCode $description');
                            if (mounted) {
                              setState(() {
                                _isLoading = false;
                                _error = 'HTTP错误 ($statusCode): $description';
                              });
                            }
                          },
                          onPermissionRequest: (controller, request) async {
                            return Future.microtask(() {
                              try {
                                return PermissionResponse(
                                  resources: request.resources,
                                  action: PermissionResponseAction.GRANT,
                                );
                              } catch (e) {
                                Log.error('Payment WebView onPermissionRequest error: $e');
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
                              // 检查是否是支付回调 URL
                              if (uriString.contains('/payment/return/') ||
                                  uriString.contains('/payment/callback/')) {
                                _handlePaymentComplete();
                                return NavigationActionPolicy.ALLOW;
                              }

                              return NavigationActionPolicy.ALLOW;
                            } catch (e) {
                              Log.error('Payment WebView shouldOverrideUrlLoading error: $e');
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
                                    if (_isHtmlForm) {
                                      _controller?.loadData(data: widget.payUrl);
                                    } else {
                                      _controller?.loadUrl(
                                        urlRequest: URLRequest(url: WebUri(widget.payUrl)),
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  } catch (e) {
                    Log.error('Payment WebView initialization error: $e');
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
                            onTap: () => Navigator.of(context).pop(false),
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

  void _handlePaymentComplete() {
    if (!mounted || _paymentCompleted) return;
    
    setState(() {
      _paymentCompleted = true;
      _isLoading = false;
    });
    
    // 延迟关闭，让用户看到支付结果
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    });
  }

  Widget _buildHeader(AppFlowyThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(
            '支付',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: theme.textColorScheme.primary,
            ),
          ),
          if (widget.orderNo != null) ...[
            const SizedBox(width: 12),
            Expanded(
              flex: 1,
              child: Text(
                '订单号: ${widget.orderNo}',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.textColorScheme.secondary,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (widget.expireTime != null)
            Expanded(
              flex: 1,
              child: Text(
                '过期时间: ${widget.expireTime}',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.textColorScheme.secondary,
                ),
              ),
            ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.close, color: theme.textColorScheme.secondary),
            onPressed: () {
              // 支付过程中不允许关闭，但可以提示用户
              if (!_paymentCompleted) {
                // 可以显示确认对话框
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('确认关闭'),
                    content: const Text('支付尚未完成，确定要关闭吗？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop(); // 关闭确认对话框
                          Navigator.of(context).pop(false); // 关闭支付对话框
                        },
                        child: const Text('确定'),
                      ),
                    ],
                  ),
                );
              } else {
                Navigator.of(context).pop(true);
              }
            },
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

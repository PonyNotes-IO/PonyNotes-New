import 'package:appflowy_backend/log.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:appflowy/startup/tasks/webview2_task.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../generated/flowy_svgs.g.dart';

/// 法律文档展示页。
///
/// 原实现为 StatelessWidget，直接内嵌 InAppWebView 且不持有 controller 引用，
/// 页面退出时无法主动 dispose 原生 WebView，依赖框架隐式回收。在 macOS 上
/// WKWebView 的回收时序不可控，切换文档时若 MethodChannel 仍有挂起消息而
/// 原生 webView 已被释放，会触发 WebViewChannelDelegate.handle() 空指针
//  解引用崩溃。改为 StatefulWidget 后，dispose 中先解除 controller 引用，
/// 再延迟一帧销毁原生实例，缩小竞态窗口。
class LegalDocumentScreen extends StatefulWidget {
  const LegalDocumentScreen({
    super.key,
    required this.title,
    this.url,
    this.content,
  });

  final String title;
  final String? url;
  final String? content;

  @override
  State<LegalDocumentScreen> createState() => _LegalDocumentScreenState();
}

class _LegalDocumentScreenState extends State<LegalDocumentScreen> {
  InAppWebViewController? _controller;
  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    final controller = _controller;
    _controller = null;
    // 先解除引用，再延迟一帧销毁原生实例，避免与渲染线程竞态导致纹理崩溃。
    // controller.dispose() 幂等，platform view teardown 时也会再次销毁，
    // try/catch 兜底双重销毁。
    if (controller != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          controller.dispose();
        } catch (e) {
          Log.warn(
            '[LegalDocumentScreen] controller.dispose() failed: $e',
          );
        }
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          icon: FlowySvg(
            FlowySvgs.mobile_return_s,
            size: const Size(7, 12),
            color: theme.textColorScheme.primary,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        backgroundColor: theme.surfaceColorScheme.primary,
        foregroundColor: theme.textColorScheme.primary,
      ),
      body: widget.url != null && widget.url!.isNotEmpty
          ? InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(widget.url ?? '')),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                supportZoom: true,
              ),
              webViewEnvironment: sharedWebViewEnvironment,
              onWebViewCreated: (controller) {
                if (!_isDisposed) {
                  _controller = controller;
                }
              },
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                return SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: SingleChildScrollView(
                    child: Container(
                      width: constraints.maxWidth,
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      padding: const EdgeInsets.all(16.0),
                      child: SelectableText(
                        widget.content ?? '',
                        style: const TextStyle(fontSize: 14, height: 1.6),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

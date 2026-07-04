import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';

class RemoteWhiteboardPage extends StatefulWidget {
  const RemoteWhiteboardPage({
    super.key,
    required this.view,
    required this.roomId,
    required this.roomKey,
  });

  final ViewPB view;
  final String roomId;
  final String roomKey;

  @override
  State<RemoteWhiteboardPage> createState() => _RemoteWhiteboardPageState();
}

class _RemoteWhiteboardPageState extends State<RemoteWhiteboardPage> {
  InAppWebViewController? _controller;
  bool _isLoading = true;
  String? _loadingError;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri(_buildRemoteUrl()),
            ),
            initialSettings: InAppWebViewSettings(
              useShouldOverrideUrlLoading: true,
              mediaPlaybackRequiresUserGesture: false,
              javaScriptEnabled: true,
              javaScriptCanOpenWindowsAutomatically: true,
              supportZoom: true,
              allowFileAccessFromFileURLs: true,
              allowUniversalAccessFromFileURLs: true,
            ),
            onWebViewCreated: (controller) {
              _controller = controller;
            },
            onLoadStart: (controller, url) {
              setState(() {
                _isLoading = true;
                _loadingError = null;
              });
              Log.debug('🔄 [RemoteWhiteboard] Loading: $url');
            },
            onLoadStop: (controller, url) {
              setState(() {
                _isLoading = false;
              });
              Log.debug('✅ [RemoteWhiteboard] Loaded: $url');
            },
            onLoadError: (controller, url, code, message) {
              setState(() {
                _isLoading = false;
                _loadingError = message;
              });
              Log.error('❌ [RemoteWhiteboard] Load error: $code - $message');
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              return NavigationActionPolicy.ALLOW;
            },
          ),
          if (_isLoading)
            const Positioned.fill(
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          if (_loadingError != null)
            Positioned.fill(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '加载失败: $_loadingError',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        _controller?.reload();
                      },
                      child: const Text('重新加载'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _buildRemoteUrl() {
    return 'https://xm-arts.xiaomabiji.com/#room=${widget.roomId},${widget.roomKey}';
  }
}
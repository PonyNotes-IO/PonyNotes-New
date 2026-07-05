import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy/user/application/user_service.dart';

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
  String? _userNickname;

  @override
  void initState() {
    super.initState();
    _loadUserNickname();
  }

  Future<void> _loadUserNickname() async {
    Log.info('[RemoteWhiteboard] 🔍 Starting to load user nickname...');
    final userProfileResult = await UserBackendService.getCurrentUserProfile();
    String nickname = userProfileResult.fold(
      (profile) {
        Log.info('[RemoteWhiteboard] ✅ Got user profile: id=${profile.id}, name=${profile.name}, email=${profile.email}');
        return profile.name;
      },
      (error) {
        Log.error('[RemoteWhiteboard] ❌ Failed to get user nickname: $error');
        return '';
      },
    );
    
    if (nickname.isEmpty) {
      nickname = '小马笔记用户';
      Log.info('[RemoteWhiteboard] 📌 Nickname is empty, using default: "$nickname"');
    }
    
    setState(() {
      _userNickname = nickname;
    });
    Log.info('[RemoteWhiteboard] 📌 Final nickname: "$nickname", isEmpty: ${nickname.isEmpty}, length: ${nickname.length}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.white,
      body: _userNickname == null
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : Stack(
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
    Log.info('[RemoteWhiteboard] 🔨 Building remote URL...');
    Log.info('[RemoteWhiteboard] 🔨 _userNickname: "$_userNickname"');
    
    final encodedNickname = Uri.encodeComponent(_userNickname ?? '');
    Log.info('[RemoteWhiteboard] 🔨 Encoded nickname: "$encodedNickname"');
    
    final url = 'https://xm-arts.xiaomabiji.com/#room=${widget.roomId},${widget.roomKey}&ua=$encodedNickname';
    Log.info('[RemoteWhiteboard] ✅ Built URL: $url');
    return url;
  }
}
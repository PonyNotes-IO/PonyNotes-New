import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

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
                    useOnDownloadStart: true,
                    mediaPlaybackRequiresUserGesture: false,
                    javaScriptEnabled: true,
                    javaScriptCanOpenWindowsAutomatically: true,
                    supportZoom: true,
                    allowFileAccessFromFileURLs: true,
                    allowUniversalAccessFromFileURLs: true,
                  ),
                  initialUserScripts: UnmodifiableListView([
                    UserScript(
                      source: '''
                        (function() {
                          var originalDownload = HTMLAnchorElement.prototype.download;
                          Object.defineProperty(HTMLAnchorElement.prototype, 'download', {
                            set: function(value) {
                              if (this.href && (this.href.startsWith('blob:') || this.href.startsWith('data:'))) {
                                window.flutter_inappwebview.callHandler('downloadBlobFile', this.href, value || 'download');
                              }
                              originalDownload = value;
                            },
                            get: function() {
                              return originalDownload;
                            }
                          });
                          
                          window.addEventListener('click', function(e) {
                            var target = e.target;
                            while (target) {
                              if (target.tagName === 'A' && target.download !== undefined) {
                                if (target.href && (target.href.startsWith('blob:') || target.href.startsWith('data:'))) {
                                  e.preventDefault();
                                  e.stopPropagation();
                                  window.flutter_inappwebview.callHandler('downloadBlobFile', target.href, target.download || 'download');
                                }
                              }
                              target = target.parentElement;
                            }
                          }, true);
                        })();
                      ''',
                      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                    ),
                  ]),
                  onWebViewCreated: (controller) {
                    _controller = controller;
                    _setupDownloadHandler(controller);
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
                  onReceivedError: (controller, request, error) {
                    setState(() {
                      _isLoading = false;
                      _loadingError = error.description;
                    });
                    Log.error('❌ [RemoteWhiteboard] Load error: ${error.type} - ${error.description}');
                  },
                  shouldOverrideUrlLoading: (controller, navigationAction) async {
                    final url = navigationAction.request.url?.toString();
                    if (url != null && url.startsWith('blob:')) {
                      Log.info('[RemoteWhiteboard] 🚫 Blocking blob navigation, starting download: $url');
                      _downloadBlobUrl(controller, url, 'download');
                      return NavigationActionPolicy.CANCEL;
                    }
                    if (url != null && url.startsWith('data:')) {
                      Log.info('[RemoteWhiteboard] 🚫 Blocking data URL navigation, starting download: $url');
                      _saveDataUrlToFile(url, 'download');
                      return NavigationActionPolicy.CANCEL;
                    }
                    return NavigationActionPolicy.ALLOW;
                  },
                  onDownloadStartRequest: (controller, downloadStartRequest) async {
                    Log.info('[RemoteWhiteboard] 📥 Download request: ${downloadStartRequest.url}');
                    await _handleDownloadRequest(downloadStartRequest);
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
    
    final url = 'https://xm-arts.xiaomabiji.com/?ua=$encodedNickname#room=${widget.roomId},${widget.roomKey}';
    Log.info('[RemoteWhiteboard] ✅ Built URL: $url');
    return url;
  }

  void _setupDownloadHandler(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: 'downloadBlobFile',
      callback: (args) async {
        if (args.isEmpty) return;
        try {
          final String blobUrl = args[0];
          final String filename = args.length > 1 ? args[1] : 'download';
          Log.info('[RemoteWhiteboard] 📥 downloadBlobFile handler: blobUrl=$blobUrl, filename=$filename');
          
          if (blobUrl.startsWith('data:')) {
            await _saveDataUrlToFile(blobUrl, filename);
          } else if (blobUrl.startsWith('blob:')) {
            await _downloadBlobUrl(controller, blobUrl, filename);
          }
        } catch (e) {
          Log.error('[RemoteWhiteboard] ❌ downloadBlobFile handler error: $e');
        }
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'saveBase64File',
      callback: (args) async {
        if (args.length >= 2) {
          String base64Data = args[0];
          final String filename = args[1];
          String mimeType = args.length > 2 ? args[2] : '';
          
          if (base64Data.startsWith('data:')) {
            final parts = base64Data.split(',');
            if (parts.length >= 2) {
              mimeType = parts[0].split(':')[1].split(';')[0];
              base64Data = parts[1];
            }
          }
          
          await _saveBase64ToFile(base64Data, filename, mimeType);
        }
      },
    );
  }

  Future<void> _handleDownloadRequest(DownloadStartRequest downloadStartRequest) async {
    try {
      final url = downloadStartRequest.url.toString();
      Log.info('[RemoteWhiteboard] 📥 Handling download request: $url');
      
      if (url.startsWith('data:')) {
        final filename = downloadStartRequest.suggestedFilename ?? 'download';
        await _saveDataUrlToFile(url, filename);
      } else if (url.startsWith('blob:')) {
        if (_controller != null) {
          final filename = downloadStartRequest.suggestedFilename ?? 'download';
          await _downloadBlobUrl(_controller!, url, filename);
        }
      } else {
        Log.warn('[RemoteWhiteboard] ⚠️ Unsupported download URL scheme: $url');
      }
    } catch (e) {
      Log.error('[RemoteWhiteboard] ❌ _handleDownloadRequest error: $e');
    }
  }

  Future<void> _downloadBlobUrl(InAppWebViewController controller, String blobUrl, String filename) async {
    Log.info('[RemoteWhiteboard] 📥 Downloading blob URL: $blobUrl');
    
    try {
      final jsCode = '''
        (async function() {
          const response = await fetch('$blobUrl');
          const blob = await response.blob();
          const reader = new FileReader();
          reader.onloadend = function() {
            const base64Data = reader.result;
            const mimeType = blob.type;
            window.flutter_inappwebview.callHandler('saveBase64File', base64Data, '$filename', mimeType);
          };
          reader.readAsDataURL(blob);
        })();
      ''';
      
      await controller.evaluateJavascript(source: jsCode);
    } catch (e) {
      Log.error('[RemoteWhiteboard] ❌ _downloadBlobUrl error: $e');
    }
  }

  Future<void> _saveDataUrlToFile(String dataUrl, String filename) async {
    try {
      final parts = dataUrl.split(',');
      if (parts.length < 2) {
        Log.error('[RemoteWhiteboard] ❌ Invalid data URL format');
        return;
      }
      
      final String mimeType = parts[0].split(':')[1].split(';')[0];
      final String base64Data = parts[1];
      
      await _saveBase64ToFile(base64Data, filename, mimeType);
    } catch (e) {
      Log.error('[RemoteWhiteboard] ❌ _saveDataUrlToFile error: $e');
    }
  }

  Future<void> _saveBase64ToFile(String base64Data, String filename, String mimeType) async {
    try {
      final String cleanBase64 = base64Data.replaceAll('\n', '').replaceAll('\r', '');
      final List<int> bytes = base64Decode(cleanBase64);
      
      String ext = '';
      if (mimeType.isNotEmpty) {
        ext = _mapMimeTypeToExtension(mimeType);
      } else {
        ext = _getFileExtensionFromFilename(filename);
      }
      
      if (ext.isEmpty) {
        ext = _detectExtensionFromBytes(bytes);
      }
      
      final String finalFilename = _ensureFilenameExtension(filename, ext);
      
      final Directory downloadsDir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      final File file = File('${downloadsDir.path}/$finalFilename');
      
      await file.writeAsBytes(bytes);
      Log.info('[RemoteWhiteboard] ✅ File saved: ${file.path}');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('图片已保存到: ${file.path}'),
            action: SnackBarAction(
              label: '打开',
              onPressed: () => OpenFilex.open(file.path),
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
      
      await OpenFilex.open(file.path);
    } catch (e) {
      Log.error('[RemoteWhiteboard] ❌ _saveBase64ToFile error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存图片失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _mapMimeTypeToExtension(String mimeType) {
    switch (mimeType.toLowerCase()) {
      case 'image/png':
        return 'png';
      case 'image/svg+xml':
        return 'svg';
      case 'image/jpeg':
      case 'image/jpg':
        return 'jpg';
      case 'image/gif':
        return 'gif';
      case 'application/pdf':
        return 'pdf';
      default:
        return '';
    }
  }

  String _getFileExtensionFromFilename(String filename) {
    final parts = filename.split('.');
    if (parts.length > 1) {
      return parts.last.toLowerCase();
    }
    return '';
  }

  String _detectExtensionFromBytes(List<int> bytes) {
    if (bytes.length >= 4) {
      if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
        return 'png';
      }
      if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
        return 'jpg';
      }
      if (bytes.length >= 10 && 
          (bytes[0] == 0x3C && bytes[1] == 0x73) || 
          (bytes[0] == 0x3C && bytes[1] == 0x3F)) {
        return 'svg';
      }
    }
    return 'png';
  }

  String _ensureFilenameExtension(String filename, String ext) {
    if (ext.isEmpty) return filename;
    if (filename.toLowerCase().endsWith('.$ext')) {
      return filename;
    }
    return '$filename.$ext';
  }
}
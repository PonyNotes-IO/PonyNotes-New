import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_room_service.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_data_service.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

class MobileWhiteboardBody extends StatefulWidget {
  const MobileWhiteboardBody({
    super.key,
    required this.view,
  });

  final ViewPB view;

  @override
  State<MobileWhiteboardBody> createState() => _MobileWhiteboardBodyState();
}

class _MobileWhiteboardBodyState extends State<MobileWhiteboardBody> {
  InAppWebViewController? _controller;
  bool _isLoading = true;
  String? _loadingError;
  String? _userNickname;
  String? _roomId;
  String? _roomKey;
  bool _isFetchingRoom = false;

  @override
  void initState() {
    super.initState();
    _loadUserNickname();
    _tryFetchRoomInfo();
  }

  Future<void> _loadUserNickname() async {
    Log.info('[MobileWhiteboard] 🔍 Starting to load user nickname...');
    final userProfileResult = await UserBackendService.getCurrentUserProfile();
    String nickname = userProfileResult.fold(
      (profile) {
        Log.info('[MobileWhiteboard] ✅ Got user profile: id=${profile.id}, name=${profile.name}, email=${profile.email}');
        return profile.name;
      },
      (error) {
        Log.error('[MobileWhiteboard] ❌ Failed to get user nickname: $error');
        return '';
      },
    );
    
    if (nickname.isEmpty) {
      nickname = '小马笔记用户';
      Log.info('[MobileWhiteboard] 📌 Nickname is empty, using default: "$nickname"');
    }
    
    if (!mounted) return;
    setState(() {
      _userNickname = nickname;
    });
    Log.info('[MobileWhiteboard] 📌 Final nickname: "$nickname", isEmpty: ${nickname.isEmpty}, length: ${nickname.length}');
  }

  Future<void> _tryFetchRoomInfo() async {
    Log.debug('🔍 [MobileWhiteboard] Initial view: id=${widget.view.id}');

    if (_isFetchingRoom) return;
    setState(() => _isFetchingRoom = true);

    try {
      final room = await WhiteboardRoomService.getRoom(widget.view.id);
      
      if (room != null) {
        Log.debug('🟢 [MobileWhiteboard] Found room in local storage: roomId=${room.roomId}');
        // 本地 room 已足够构造远程白板 URL。不要在每次打开时再读取完整
        // collab 场景：该调用会先 openWhiteboard 再拉取整块 JSON，移动端会被
        // 网络和大白板数据拖住；白板页面会自行从 room 恢复场景。
        if (!mounted) return;
        setState(() {
          _roomId = room.roomId;
          _roomKey = room.roomKey;
        });
        Log.debug('⚡ [MobileWhiteboard] Local room fast path, skip collab preload');
        return;
      }

      final whiteboardData = await WhiteboardDataService().loadWhiteboardData(widget.view.id);
      Log.debug('🔍 [MobileWhiteboard] Loaded whiteboard data keys: ${whiteboardData.keys}');
      
      final serverRoomId = whiteboardData['roomId'];
      final serverRoomKey = whiteboardData['roomKey'];

      if (serverRoomId != null && serverRoomId.toString().isNotEmpty && serverRoomKey != null && serverRoomKey.toString().isNotEmpty) {
        final roomIdStr = serverRoomId is String ? serverRoomId : serverRoomId.toString();
        final roomKeyStr = serverRoomKey is String ? serverRoomKey : serverRoomKey.toString();
        
        Log.debug('🟢 [MobileWhiteboard] Found room in server data: roomId=$roomIdStr');
        
        if (roomIdStr != _roomId || roomKeyStr != _roomKey) {
          await WhiteboardRoomService.saveRoom(widget.view.id, roomIdStr, roomKeyStr);
          Log.debug('✅ [MobileWhiteboard] Synced server room to local storage: roomId=$roomIdStr');
        }
        
        if (!mounted) return;
        setState(() {
          _roomId = roomIdStr;
          _roomKey = roomKeyStr;
        });
        return;
      }

      if (_roomId != null && _roomKey != null) {
        Log.debug('🟢 [MobileWhiteboard] Using existing room from local storage: roomId=$_roomId');
        return;
      }

      Log.debug('🟡 [MobileWhiteboard] No room found for view ${widget.view.id}, generating new one');
      final newRoomId = WhiteboardRoomService.generateRoomId();
      final newRoomKey = WhiteboardRoomService.generateRoomKey();
      
      Log.info('🆕 [MobileWhiteboard] Generated NEW roomId=$newRoomId, roomKey=$newRoomKey for view ${widget.view.id}');
      
      await WhiteboardRoomService.saveRoom(widget.view.id, newRoomId, newRoomKey);
      Log.info('✅ [MobileWhiteboard] Saved room to local storage: viewId=${widget.view.id}, roomId=$newRoomId');
      
      Log.info('📤 [MobileWhiteboard] Saving room info to server...');
      final saveResult = await WhiteboardDataService().saveWhiteboardData(
        widget.view.id,
        {
          'roomId': newRoomId,
          'roomKey': newRoomKey,
        },
        source: 'room-init',
      );
      
      if (saveResult) {
        Log.info('✅ [MobileWhiteboard] SUCCESSFULLY saved room info to server: roomId=$newRoomId, roomKey=$newRoomKey');
      } else {
        Log.error('❌ [MobileWhiteboard] FAILED to save room info to server');
      }
      
      if (!mounted) return;
      setState(() {
        _roomId = newRoomId;
        _roomKey = newRoomKey;
      });
    } catch (e) {
      Log.error('❌ [MobileWhiteboard] Error fetching/generating room: $e');
    } finally {
      if (mounted) {
        setState(() => _isFetchingRoom = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isFetchingRoom || _userNickname == null || _roomId == null || _roomKey == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Stack(
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
            Log.debug('🔄 [MobileWhiteboard] Loading: $url');
          },
          onLoadStop: (controller, url) {
            setState(() {
              _isLoading = false;
            });
            Log.debug('✅ [MobileWhiteboard] Loaded: $url');
          },
          onReceivedError: (controller, request, error) {
            setState(() {
              _isLoading = false;
              _loadingError = error.description;
            });
            Log.error('❌ [MobileWhiteboard] Load error: ${error.type} - ${error.description}');
          },
          shouldOverrideUrlLoading: (controller, navigationAction) async {
            final url = navigationAction.request.url?.toString();
            final headers = navigationAction.request.headers;
            final filename = headers != null ? 
              (headers['Content-Disposition']?.split('filename=').last ?? 
               headers['content-disposition']?.split('filename=').last ?? 'download') : 'download';
            
            if (url != null && url.startsWith('blob:')) {
              Log.info('[MobileWhiteboard] 🚫 Blocking blob navigation, starting download: $url, filename: $filename');
              unawaited(_downloadBlobUrl(controller, url, filename.replaceAll('"', '')));
              return NavigationActionPolicy.CANCEL;
            }
            if (url != null && url.startsWith('data:')) {
              Log.info('[MobileWhiteboard] 🚫 Blocking data URL navigation, starting download: $url, filename: $filename');
              unawaited(_saveDataUrlToFile(url, filename.replaceAll('"', '')));
              return NavigationActionPolicy.CANCEL;
            }
            return NavigationActionPolicy.ALLOW;
          },
          onDownloadStartRequest: (controller, downloadStartRequest) async {
            Log.info('[MobileWhiteboard] 📥 Download request: ${downloadStartRequest.url}');
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
    );
  }

  String _buildRemoteUrl() {
    Log.info('[MobileWhiteboard] 🔨 Building remote URL...');
    Log.info('[MobileWhiteboard] 🔨 _userNickname: "$_userNickname"');
    
    final encodedNickname = Uri.encodeComponent(_userNickname ?? '');
    Log.info('[MobileWhiteboard] 🔨 Encoded nickname: "$encodedNickname"');
    
    final url = 'https://xm-arts.xiaomabiji.com/?ua=$encodedNickname#room=$_roomId,$_roomKey';
    Log.info('[MobileWhiteboard] ✅ Built URL: $url');
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
          Log.info('[MobileWhiteboard] 📥 downloadBlobFile handler: blobUrl=$blobUrl, filename=$filename');
          
          if (blobUrl.startsWith('data:')) {
            await _saveDataUrlToFile(blobUrl, filename);
          } else if (blobUrl.startsWith('blob:')) {
            await _downloadBlobUrl(controller, blobUrl, filename);
          }
        } catch (e) {
          Log.error('[MobileWhiteboard] ❌ downloadBlobFile handler error: $e');
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
      Log.info('[MobileWhiteboard] 📥 Handling download request: $url');
      
      if (url.startsWith('data:')) {
        final filename = downloadStartRequest.suggestedFilename ?? 'download';
        await _saveDataUrlToFile(url, filename);
      } else if (url.startsWith('blob:')) {
        if (_controller != null) {
          final filename = downloadStartRequest.suggestedFilename ?? 'download';
          await _downloadBlobUrl(_controller!, url, filename);
        }
      } else {
        Log.warn('[MobileWhiteboard] ⚠️ Unsupported download URL scheme: $url');
      }
    } catch (e) {
      Log.error('[MobileWhiteboard] ❌ _handleDownloadRequest error: $e');
    }
  }

  Future<void> _downloadBlobUrl(InAppWebViewController controller, String blobUrl, String filename) async {
    Log.info('[MobileWhiteboard] 📥 Downloading blob URL: $blobUrl');
    
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
      Log.error('[MobileWhiteboard] ❌ _downloadBlobUrl error: $e');
    }
  }

  Future<void> _saveDataUrlToFile(String dataUrl, String filename) async {
    try {
      final parts = dataUrl.split(',');
      if (parts.length < 2) {
        Log.error('[MobileWhiteboard] ❌ Invalid data URL format');
        return;
      }
      
      final String mimeType = parts[0].split(':')[1].split(';')[0];
      final String base64Data = parts[1];
      
      await _saveBase64ToFile(base64Data, filename, mimeType);
    } catch (e) {
      Log.error('[MobileWhiteboard] ❌ _saveDataUrlToFile error: $e');
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
      if (Platform.isAndroid || Platform.isIOS) {
        final savePath = await GetIt.instance<FilePickerService>().saveFile(
          dialogTitle: '保存白板图片',
          fileName: finalFilename,
          type: FileType.custom,
          allowedExtensions: [ext],
          bytes: Uint8List.fromList(bytes),
        );
        if (savePath == null) {
          Log.info('[MobileWhiteboard] 用户取消保存图片');
          return;
        }
        Log.info('[MobileWhiteboard] 图片已保存: $savePath');
        showToastNotification(
          message: '图片已保存',
          type: ToastificationType.success,
        );
        return;
      }
      
      final Directory downloadsDir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      await downloadsDir.create(recursive: true);
      final File file = File('${downloadsDir.path}/$finalFilename');
      
      await file.writeAsBytes(bytes);
      Log.info('[MobileWhiteboard] ✅ File saved: ${file.path}');
      
      showToastNotification(
        message: '文件已保存到: ${file.path.split('/').last}',
        type: ToastificationType.success,
        description: file.path,
      );
      
      await OpenFilex.open(file.path);
    } catch (e) {
      Log.error('[MobileWhiteboard] ❌ _saveBase64ToFile error: $e');
      showToastNotification(
        message: '保存文件失败',
        type: ToastificationType.error,
        description: e.toString(),
      );
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
      case 'application/vnd.excalidraw+json':
        return 'excalidraw';
      case 'application/json':
        return 'json';
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
      if (bytes[0] == 0x7B) {
        return 'json';
      }
    }
    return 'bin';
  }

  String _ensureFilenameExtension(String filename, String ext) {
    if (ext.isEmpty) return filename;
    if (filename.toLowerCase().endsWith('.$ext')) {
      return filename;
    }
    return '$filename.$ext';
  }
}

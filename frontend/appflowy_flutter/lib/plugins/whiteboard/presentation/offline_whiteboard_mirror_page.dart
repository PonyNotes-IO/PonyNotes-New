import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_mirror_service.dart';
import 'package:appflowy/plugins/whiteboard/presentation/excalidraw_webview.dart';
import 'package:appflowy/util/diagnostic_build.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// 断网时的「协作白板本地镜像 · 只读浏览」页面。
///
/// 仅在「协作空间白板 + room 服务不可达 + 本地已有镜像」时渲染：
/// - 用本地 B 套 Excalidraw（`ExcalidrawWebView`）渲染镜像数据；
/// - 强制 Excalidraw viewMode 只读（禁止编辑，仅浏览/缩放）；
/// - 顶部展示「离线只读」提示。
///
/// **安全红线**：本页完全没有任何写回路径 —— 不创建 CollabAdapter、
/// `onDataChanged` 传 null，因此镜像数据绝不会被上传/覆盖到 room 服务器。
class OfflineWhiteboardMirrorPage extends StatefulWidget {
  const OfflineWhiteboardMirrorPage({
    super.key,
    required this.view,
  });

  final ViewPB view;

  @override
  State<OfflineWhiteboardMirrorPage> createState() =>
      _OfflineWhiteboardMirrorPageState();
}

class _OfflineWhiteboardMirrorPageState
    extends State<OfflineWhiteboardMirrorPage> {
  final WhiteboardMirrorService _mirrorService = WhiteboardMirrorService();
  final GlobalKey<ExcalidrawWebViewState> _webViewKey =
      GlobalKey<ExcalidrawWebViewState>(
    debugLabel: 'offline_mirror_webview',
  );

  Map<String, dynamic>? _mirrorData;
  bool _loading = true;
  bool _missing = false;
  late final String _sessionTraceId;
  late final String _loadTraceId;
  Timer? _viewModeRetryTimer;

  @override
  void initState() {
    super.initState();
    _sessionTraceId =
        ponyNotesDiagTraceId('whiteboard-mirror-session', widget.view.id);
    _loadTraceId = ponyNotesDiagTraceId('whiteboard-mirror', widget.view.id);
    _loadMirror();
  }

  @override
  void dispose() {
    _viewModeRetryTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadMirror() async {
    final data = await _mirrorService.loadMirror(widget.view.id);
    if (!mounted) return;
    setState(() {
      _mirrorData = data;
      _missing = data == null;
      _loading = false;
    });
    Log.info(
      '[OfflineMirror] 加载本地镜像 view=${widget.view.id} '
      '${data == null ? '(无镜像)' : 'sceneVersion=${data['sceneVersion']}'}',
    );
  }

  void _enterViewMode() {
    // 强制只读：初次就绪立即进入 viewMode，并延时重试若干次，
    // 兜底数据恢复晚于 onInitialReady 时 viewMode 被场景覆盖的情况。
    _webViewKey.currentState?.setViewMode(true);
    var attempts = 0;
    _viewModeRetryTimer?.cancel();
    _viewModeRetryTimer = Timer.periodic(
      const Duration(milliseconds: 700),
      (timer) {
        attempts++;
        if (!mounted || attempts > 5) {
          timer.cancel();
          return;
        }
        _webViewKey.currentState?.setViewMode(true);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_missing || _mirrorData == null) {
      // 理论上路由已保证有镜像才进入本页；防御性兜底。
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Text(
            LocaleKeys.whiteboard_offlineMirrorMissing.tr(),
            style: const TextStyle(fontSize: 15, color: Colors.black54),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned.fill(
            child: ExcalidrawWebView(
              key: _webViewKey,
              viewId: widget.view.id,
              sessionTraceId: _sessionTraceId,
              loadTraceId: _loadTraceId,
              initialData: _mirrorData,
              // initialDataLoaded=true 且不 defer：直接用镜像数据渲染，
              // 不再回落到 collab 加载。
              initialDataLoaded: true,
              // 【红线】不传 onDataChanged（默认 null）：本页无任何写回路径，
              // 镜像绝不上传/覆盖 room 服务器。
              onInitialReady: _enterViewMode,
            ),
          ),
          _buildOfflineBanner(context),
        ],
      ),
    );
  }

  Widget _buildOfflineBanner(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Positioned(
      top: topInset + 10,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xF2222222),
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                size: 16,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      LocaleKeys.whiteboard_offlineReadOnlyTitle.tr(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      LocaleKeys.whiteboard_offlineReadOnlyHint.tr(),
                      style: const TextStyle(
                        color: Color(0xCCFFFFFF),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

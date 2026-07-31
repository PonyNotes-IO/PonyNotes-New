import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/whiteboard/presentation/whiteboard_migration_script.dart';
import 'package:appflowy_backend/log.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 迁移 webview 的执行结果。
class WhiteboardMigrationWebResult {
  const WhiteboardMigrationWebResult({
    required this.ok,
    this.error,
    this.scene,
  });

  /// 迁移的加解密步骤是否成功（PUSH=上传成功；PULL=读到可用明文场景）。
  final bool ok;

  /// 失败原因（诊断用，非用户可见文案）。
  final String? error;

  /// PULL 方向读回的明文场景（`{elements, files, appState}`）；PUSH 方向为 null。
  final Map<String, dynamic>? scene;
}

/// 启动一个「隐藏」的 xm-arts 迁移 webview，委托页面自身 collab 完成加解密。
///
/// [isPush] = true  私有→协作：把 [pushPayload]（`{elements, files}`，明文）灌入新
///                  room 画布，调用页面内部加密并 POST /api/scenes 上传，成功返回 ok。
/// [isPush] = false 协作→私有：让页面 GET+解密+渲染，读回画布明文场景于 result.scene。
///
/// 以模态弹窗形式承载（不可关闭），webview 全屏但被不透明进度层遮住——既保证
/// excalidraw 以真实尺寸初始化、又不干扰用户。任何异常/超时都会以 ok=false 返回，
/// 由调用方决定中止迁移（绝不因加解密失败而切 section）。
Future<WhiteboardMigrationWebResult> runWhiteboardMigrationWebView({
  required BuildContext context,
  required String roomId,
  required String roomKey,
  required bool isPush,
  Map<String, dynamic>? pushPayload,
  Duration timeout = const Duration(seconds: 40),
}) async {
  if (!context.mounted) {
    return const WhiteboardMigrationWebResult(
      ok: false,
      error: 'context-unmounted',
    );
  }

  final completer = Completer<WhiteboardMigrationWebResult>();

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return PopScope(
        canPop: false,
        child: _WhiteboardMigrationWebView(
          roomId: roomId,
          roomKey: roomKey,
          isPush: isPush,
          pushPayload: pushPayload,
          timeout: timeout,
          onDone: (result) {
            if (!completer.isCompleted) {
              completer.complete(result);
            }
            if (Navigator.of(dialogContext).canPop()) {
              Navigator.of(dialogContext).pop();
            }
          },
        ),
      );
    },
  );

  if (!completer.isCompleted) {
    // 弹窗被异常关闭（理论上不会，PopScope 已阻止），按失败处理，绝不误判成功。
    completer.complete(
      const WhiteboardMigrationWebResult(ok: false, error: 'dialog-dismissed'),
    );
  }
  return completer.future;
}

class _WhiteboardMigrationWebView extends StatefulWidget {
  const _WhiteboardMigrationWebView({
    required this.roomId,
    required this.roomKey,
    required this.isPush,
    required this.pushPayload,
    required this.timeout,
    required this.onDone,
  });

  final String roomId;
  final String roomKey;
  final bool isPush;
  final Map<String, dynamic>? pushPayload;
  final Duration timeout;
  final ValueChanged<WhiteboardMigrationWebResult> onDone;

  @override
  State<_WhiteboardMigrationWebView> createState() =>
      _WhiteboardMigrationWebViewState();
}

class _WhiteboardMigrationWebViewState
    extends State<_WhiteboardMigrationWebView> {
  InAppWebViewController? _controller;
  Timer? _timeoutTimer;
  bool _finished = false;
  bool _flowStarted = false;

  @override
  void initState() {
    super.initState();
    _timeoutTimer = Timer(widget.timeout, () {
      _finish(const WhiteboardMigrationWebResult(ok: false, error: 'timeout'));
    });
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  void _finish(WhiteboardMigrationWebResult result) {
    if (_finished) return;
    _finished = true;
    _timeoutTimer?.cancel();
    Log.info(
      '[WBMigrationWebView] 迁移 webview 结束 isPush=${widget.isPush} ok=${result.ok} error=${result.error}',
    );
    widget.onDone(result);
  }

  String _buildUrl() {
    // 隐藏迁移页无需昵称，room 决定内容。
    return 'https://xm-arts.xiaomabiji.com/?ua=migration#room=${widget.roomId},${widget.roomKey}';
  }

  Future<void> _startFlowIfNeeded() async {
    if (_flowStarted || _finished) return;
    _flowStarted = true;
    try {
      if (widget.isPush) {
        await _runPush();
      } else {
        await _runPull();
      }
    } catch (e) {
      _finish(WhiteboardMigrationWebResult(ok: false, error: 'flow-exception:$e'));
    }
  }

  /// 轮询等待 JS 侧就绪条件为 true，超时抛出。
  ///
  /// 超时前会把 JS 侧的诊断快照打进日志：就绪失败可能是「fiber 树里找不到
  /// Collab 实例」（xm-arts 改版会打中）或「/api/scenes 的 GET 从未发生」，
  /// 两者成因与修法完全不同，只看 ready-timeout 无从分辨。
  ///
  /// 30s 对冷启动的慢机器偏紧（webview 要完整跑起 excalidraw 再拉场景），
  /// 放宽到 60s；正常情况下几秒内就绪，不会因此变慢。
  Future<void> _waitReady(String readyExpr, {int maxMs = 60000}) async {
    final controller = _controller;
    if (controller == null) throw StateError('no-controller');
    var waited = 0;
    const step = 400;
    while (waited < maxMs && !_finished) {
      final r = await controller.evaluateJavascript(
        source: 'window.__xmMig && window.__xmMig.$readyExpr ? true : false',
      );
      if (r == true || r == 'true' || r == 1) return;
      await Future<void>.delayed(const Duration(milliseconds: step));
      waited += step;
    }

    String diag = '<unavailable>';
    try {
      final d = await controller.evaluateJavascript(
        source:
            'window.__xmMig ? JSON.stringify(window.__xmMig.diag()) : "no-__xmMig"',
      );
      diag = d?.toString() ?? '<null>';
    } catch (e) {
      diag = '<diag-failed:$e>';
    }
    Log.error(
      '[WBMigrationWebView] 就绪等待超时 expr=$readyExpr waited=${waited}ms 诊断=$diag',
    );

    throw TimeoutException('ready-timeout:$readyExpr');
  }

  Future<void> _runPull() async {
    final controller = _controller!;
    await _waitReady('pullReady()');
    // 读到就绪后，再给页面一点时间把解密后的场景渲染到画布，避免读到空。
    await Future<void>.delayed(const Duration(milliseconds: 800));

    Map<String, dynamic>? scene;
    // 连读几次取稳定/非空结果。
    for (var i = 0; i < 5 && !_finished; i++) {
      final raw = await controller.callAsyncJavaScript(
        functionBody: 'return JSON.stringify(window.__xmMig.getScene());',
      );
      final value = raw?.value;
      if (value is String && value.isNotEmpty && value != 'null') {
        try {
          scene = jsonDecode(value) as Map<String, dynamic>;
        } catch (_) {
          scene = null;
        }
      }
      final liveCount = (scene?['liveCount'] as num?)?.toInt() ?? 0;
      if (liveCount > 0) break;
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }

    if (scene == null) {
      _finish(const WhiteboardMigrationWebResult(ok: false, error: 'pull-read-null'));
      return;
    }

    final liveCount = (scene['liveCount'] as num?)?.toInt() ?? 0;
    final serverVersion = (scene['serverSceneVersion'] as num?)?.toInt() ?? 0;

    // 【数据安全红线】服务器确有内容（serverVersion>0）却读到 0 活元素 =>
    // 判定为「读取/解密未完成」，绝不当作空场景，直接中止，避免把空写进本地覆盖真数据。
    if (liveCount == 0 && serverVersion > 0) {
      _finish(
        WhiteboardMigrationWebResult(
          ok: false,
          error: 'server-has-content-but-read-empty:v=$serverVersion',
        ),
      );
      return;
    }

    // liveCount>0 正常迁移；liveCount==0 且 serverVersion==0（404/空房）= 合法空白板。
    _finish(WhiteboardMigrationWebResult(ok: true, scene: scene));
  }

  Future<void> _runPush() async {
    final controller = _controller!;
    await _waitReady('pushReady()');
    final payloadJson = jsonEncode(widget.pushPayload ?? const {});
    final raw = await controller.callAsyncJavaScript(
      functionBody:
          'return JSON.stringify(await window.__xmMig.loadAndSave(${jsonEncode(payloadJson)}));',
    );
    final value = raw?.value;
    Map<String, dynamic>? res;
    if (value is String && value.isNotEmpty && value != 'null') {
      try {
        res = jsonDecode(value) as Map<String, dynamic>;
      } catch (_) {
        res = null;
      }
    }
    if (res == null) {
      _finish(const WhiteboardMigrationWebResult(ok: false, error: 'push-result-null'));
      return;
    }
    final ok = res['ok'] == true;
    _finish(
      WhiteboardMigrationWebResult(
        ok: ok,
        error: ok ? null : (res['error']?.toString() ?? 'push-failed'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: EdgeInsets.zero,
      backgroundColor: Colors.transparent,
      child: Stack(
        children: [
          // 全屏但被下面进度层遮住的 webview：保证 excalidraw 以真实尺寸初始化。
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.01,
                child: InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(_buildUrl())),
                  initialSettings: InAppWebViewSettings(
                    javaScriptCanOpenWindowsAutomatically: true,
                    mediaPlaybackRequiresUserGesture: false,
                    allowFileAccessFromFileURLs: true,
                    allowUniversalAccessFromFileURLs: true,
                  ),
                  initialUserScripts: UnmodifiableListView([
                    UserScript(
                      source: whiteboardMigrationScript,
                      injectionTime:
                          UserScriptInjectionTime.AT_DOCUMENT_START,
                    ),
                  ]),
                  onWebViewCreated: (controller) => _controller = controller,
                  onLoadStop: (controller, url) {
                    _startFlowIfNeeded();
                  },
                  onReceivedError: (controller, request, error) {
                    Log.warn(
                      '[WBMigrationWebView] webview 加载错误: ${error.type} - ${error.description}',
                    );
                  },
                  onConsoleMessage: (controller, msg) {
                    if (msg.messageLevel == ConsoleMessageLevel.ERROR) {
                      Log.warn('[WBMigrationWebView][JS] ${msg.message}');
                    }
                  },
                ),
              ),
            ),
          ),
          // 不透明进度层。
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.55),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      LocaleKeys.space_whiteboardMigrating.tr(),
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

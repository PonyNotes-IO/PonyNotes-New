import 'dart:async';
import 'dart:convert';

import 'package:appflowy_backend/log.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 在 WebView 里执行一段**返回 Promise** 的 JS，并等待它的最终结果。
///
/// ## 为什么不能用 `controller.callAsyncJavaScript`
///
/// 它在 macOS 原生侧最终会调到 WKWebView 的 **Swift overlay**
/// `callAsyncJavaScript(_:arguments:in:in:completionHandler:)`。该符号在
/// flutter_inappwebview_macos 里是**弱导入**（weak-import，因为插件的部署目标
/// 10.15 低于这个 API 要求的 macOS 11）：
///
/// ```
/// __DATA __la_symbol_ptr 0x000E0508 lazy-bind
///   WebKit/_$sSo9WKWebViewC6WebKitE19callAsyncJavaScript... [weak-import]
/// ```
///
/// 弱导入的语义是「运行时解析不到就把符号地址绑定为 0」。一旦绑定为 0，调用它
/// 就是 `jmp` 到地址 0，进程立刻 SIGSEGV —— 崩溃报告表现为 `rip=0`、
/// `EXC_BAD_ACCESS (SIGSEGV) KERN_INVALID_ADDRESS at 0x0`、
/// `Error Code: 0x14 (no mapping for user instruction read)`，
/// 栈顶是 `WebViewChannelDelegate.handle(_:result:)`。
/// 已在 macOS 14.8.2 (Intel) 上实测复现，1.1.7～1.1.12 均可触发。
///
/// 而 `evaluateJavascript(source:)` **在不传 contentWorld 时**走的是 ObjC 的
/// `evaluateJavaScript:completionHandler:`，不涉及任何弱导入符号，因此安全。
/// 注意：传了 contentWorld 就会走 Swift overlay 的
/// `evaluateJavaScript(_:in:completionHandler:)`，那个同样是弱导入（0xE0500，
/// 就在上面那个符号的隔壁槽位）——**所以本文件一律不传 contentWorld**。
///
/// ## 做法
///
/// 既然不能让原生帮我们 await Promise，就把等待放回 JS 侧：
/// 先用一次普通的 `evaluateJavascript` **同步启动**一个 async IIFE，让它把结果
/// 写进 `window.__xmAsyncBox[token]`；再用普通的 `evaluateJavascript` 轮询这个
/// 「信箱」直到 done。全程只用安全的那条 API。
///
/// 代价是多了轮询往返（默认 50ms 一次）。白板这几处调用要么在迁移流程里、
/// 要么是切走前的冲刷保存，本身就是秒级操作，这点开销可以接受。
///
/// [asyncBody] 是**函数体**，写法与 `callAsyncJavaScript` 的 functionBody 一致，
/// 需自带 `return`，可以使用 `await`。
///
/// 返回 JS 侧的返回值（已过一次 JSON 序列化/反序列化，因此只支持可 JSON 化的值；
/// 白板这几处返回的都是字符串）。失败或超时返回 `null`，并记录日志 —— 调用方
/// 原本就按「拿不到结果」处理，不会因为本函数抛异常而中断白板流程。
///
/// [isCancelled] 用于在 widget 已 dispose 时提前退出轮询，避免对着一个正在
/// 销毁的 WebView 空转。
Future<Object?> evaluateAsyncJavascript(
  InAppWebViewController controller, {
  required String asyncBody,
  Duration timeout = const Duration(seconds: 10),
  Duration interval = const Duration(milliseconds: 50),
  bool Function()? isCancelled,
  String debugLabel = '',
}) async {
  final token = _nextToken();
  final tokenLiteral = jsonEncode(token);

  // 启动：注意这段本身是同步的，evaluateJavascript 立即返回，
  // Promise 在页面里继续跑。
  try {
    await controller.evaluateJavascript(
      source: '''
(function () {
  window.__xmAsyncBox = window.__xmAsyncBox || {};
  var k = $tokenLiteral;
  window.__xmAsyncBox[k] = { done: false };
  (async function () {
    try {
      var v = await (async function () { $asyncBody })();
      window.__xmAsyncBox[k] = { done: true, ok: true, value: v };
    } catch (e) {
      window.__xmAsyncBox[k] = { done: true, ok: false, error: String(e) };
    }
  })();
})();
''',
    );
  } catch (e) {
    Log.warn('[AsyncEval] 启动失败$debugLabel: $e');
    return null;
  }

  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (isCancelled?.call() ?? false) {
      // 已取消：顺手清掉信箱，避免页面上残留条目。
      unawaited(_clearBox(controller, tokenLiteral));
      Log.info('[AsyncEval] 已取消$debugLabel');
      return null;
    }

    await Future<void>.delayed(interval);

    Object? raw;
    try {
      raw = await controller.evaluateJavascript(
        source: 'JSON.stringify(window.__xmAsyncBox[$tokenLiteral] || null)',
      );
    } catch (e) {
      Log.warn('[AsyncEval] 轮询失败$debugLabel: $e');
      return null;
    }

    if (raw is! String || raw.isEmpty || raw == 'null') {
      continue;
    }

    Map<String, dynamic> box;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) continue;
      box = decoded;
    } catch (_) {
      continue;
    }

    if (box['done'] != true) {
      continue;
    }

    unawaited(_clearBox(controller, tokenLiteral));

    if (box['ok'] == true) {
      return box['value'];
    }
    Log.warn('[AsyncEval] JS 抛错$debugLabel: ${box['error']}');
    return null;
  }

  unawaited(_clearBox(controller, tokenLiteral));
  Log.warn('[AsyncEval] 超时(${timeout.inMilliseconds}ms)$debugLabel');
  return null;
}

Future<void> _clearBox(
  InAppWebViewController controller,
  String tokenLiteral,
) async {
  try {
    await controller.evaluateJavascript(
      source: 'try{delete window.__xmAsyncBox[$tokenLiteral]}catch(e){}',
    );
  } catch (_) {
    // 页面可能已销毁，清理失败无所谓 —— 信箱随页面一起消失。
  }
}

int _seq = 0;

String _nextToken() =>
    'xm_${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

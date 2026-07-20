package com.xiaomabiji.app.note.wechat

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import com.xiaomabiji.app.note.MainActivity

/**
 * 微信登录回调 Activity。
 *
 * 微信完成授权后，SDK 通过 PendingIntent 拉起 WXEntryActivity（在独立的 task 里）。
 * 我们这里解析回调 intent，并通过以下路径之一把结果送回 Dart：
 *
 * 1. **首选**：直接调用 [MainActivity.activeWeChatBridge] 上的
 *    [WeChatBridge.deliverResult]。同进程、静态引用、零依赖，绝对可靠。
 * 2. **Fallback**：如果 activeWeChatBridge 为 null（例如 app 进程刚被系统回收、
 *    WXEntryActivity 先于 MainActivity.configureFlutterEngine 跑完时），fallback
 *    到 [WeChatApi.notifyAuthResult] 广播。
 *
 * **历史 bug**：本类之前的实现只调 broadcast 不调 deliverResult，导致
 * MainActivity 进程里的 WeChatBridge 永远收不到回调，stale-resume 1.5s 后
 * 报 CANCELLED。修复后必须把 direct path 作为首选。
 *
 * exported=true 是微信 SDK 拉起此 Activity 的必要条件。
 * taskAffinity 独立避免与主 app 任务栈冲突。
 */
class WXEntryActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        android.util.Log.i("WXEntryActivity", "onCreate, handling intent")
        handleIntent(intent)
        finish()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        android.util.Log.i("WXEntryActivity", "onNewIntent, handling intent")
        setIntent(intent)
        handleIntent(intent)
        finish()
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) {
            android.util.Log.w("WXEntryActivity", "handleIntent: null intent")
            return
        }
        val api = WeChatApi(this)
        api.handleWXEntryIntent(intent, object : WeChatApi.AuthCallback {
            override fun onAuthResponse(errCode: Int, code: String?, state: String?) {
                android.util.Log.i(
                    "WXEntryActivity",
                    "auth response: errCode=$errCode, code=${code?.take(8)}, state=$state",
                )

                // 首选：同进程直接调 deliverResult。
                // activeWeChatBridge 是 MainActivity 在 configureFlutterEngine 时设置的静态引用，
                // 跟 WXEntryActivity 都在 :app 进程，绝对可达。
                val bridge = MainActivity.activeWeChatBridge
                if (bridge != null) {
                    android.util.Log.i("WXEntryActivity", "activeWeChatBridge present, calling deliverResult directly")
                    bridge.deliverResult(errCode, code, state)
                } else {
                    // Fallback：bridge 没起来（app 进程刚被回收重启），用 broadcast
                    // 通知 MainActivity 重建后再取一次。
                    android.util.Log.w("WXEntryActivity", "activeWeChatBridge is null, falling back to broadcast")
                    api.notifyAuthResult(errCode, code, state)
                }
            }
        })
    }
}

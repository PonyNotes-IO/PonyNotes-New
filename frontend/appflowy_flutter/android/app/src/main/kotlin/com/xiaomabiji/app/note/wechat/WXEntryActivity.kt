package com.xiaomabiji.app.note.wechat

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * 微信登录回调 Activity。
 *
 * 微信完成授权后，会通过 WXEntryActivity 的 task（因为 taskAffinity 独立）回调这个 Activity。
 * 我们用 WeChatApi.handleWXEntryIntent 解析回调 intent（不走 MMessageActV2，
 * 因此不受 Android 14+ PendingIntent bug 影响），然后通过 broadcast 把结果发回
 * [WeChatBridge]，再由 MethodChannel 传给 Flutter 层。
 *
 * exported=true 是微信 SDK 拉起此 Activity 的必要条件。
 * taskAffinity 独立避免与主 app 任务栈冲突。
 */
class WXEntryActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
        finish()
    }

    @Deprecated("Deprecated in Java")
    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        setIntent(intent)
        intent?.let { handleIntent(it) }
        finish()
    }

    private fun handleIntent(intent: Intent) {
        val api = WeChatApi(this)
        api.handleWXEntryIntent(intent, object : WeChatApi.AuthCallback {
            override fun onAuthResponse(errCode: Int, code: String?, state: String?) {
                api.notifyAuthResult(errCode, code, state)
            }
        })
    }
}

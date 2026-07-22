package com.xiaomabiji.app.note.wechat

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Bundle
import com.tencent.mm.opensdk.modelmsg.SendAuth
import com.tencent.mm.opensdk.openapi.IWXAPI
import com.tencent.mm.opensdk.openapi.WXAPIFactory

/**
 * WeChat SDK 桥接层。
 *
 * **历史背景**：
 * 腾讯 SDK 6.8.x 的 `MMessageActV2.sendUsingPendingIntent` 在 Android 14+ 上调用
 * `setPendingIntentBackgroundActivityStartMode(1)` 抛 IllegalArgumentException，
 * catch 块只打 log 就 return，永远无法拉起微信 App。
 *
 * **当前实现**：
 * - 升级 SDK 到 6.8.38，changelog 显示"适配 Android 15 的 PendingIntent Explicitly Opt-In/Out of Background Activity"
 * - 改为走 SDK 内置的 `wxApi.sendReq()` 流程，让 SDK 内部的 `MMessageActV2` 处理 PendingIntent opt-in
 * - 同时保留自构造 Intent 的 `_sendRawAuth` 作为 fallback（仅 SDK 内部仍 fail 时使用）
 */
class WeChatApi(private val context: Context) {

    companion object {
        const val APP_ID = "wx3b1a7737f52a004b"
        const val ACTION_HANDLE_RESP = "com.xiaomabiji.app.note.WECHAT_HANDLE_RESP"
    }

    private val appCtx: Context = context.applicationContext
    private val packageName: String = appCtx.packageName

    // 用于 isWXAppInstalled / sendReq 的 API 实例
    private val wxApi: IWXAPI by lazy {
        WXAPIFactory.createWXAPI(context, APP_ID, true)
    }

    fun isInstalled(): Boolean = runCatching { wxApi.isWXAppInstalled }.getOrDefault(false)

    /**
     * 发起微信授权登录。
     *
     * 走标准 IWXAPI.sendReq() 流程：SDK 内部会构造 PendingIntent 并加上 BAL opt-in。
     * 失败时回退到自构造 Intent 方式（不再依赖 PendingIntent）。
     *
     * @return true 表示至少有一种方式已尝试拉起微信
     */
    fun startAuth(state: String): Boolean {
        val req = SendAuth.Req().apply {
            this.scope = "snsapi_userinfo"
            this.state = state
        }

        // 主路径：让 SDK 走它内部的 MMessageActV2
        return try {
            wxApi.sendReq(req)
        } catch (e: Throwable) {
            android.util.Log.w("WeChatApi", "wxApi.sendReq failed, fallback to raw Intent", e)
            sendRawAuth(state)
        }
    }

    /**
     * Fallback 路径：自构造 Intent 拉起微信 WXEntryActivity，
     * 不走 SDK 的 PendingIntent。
     */
    private fun sendRawAuth(state: String): Boolean {
        val req = SendAuth.Req().apply {
            this.scope = "snsapi_userinfo"
            this.state = state
        }
        val reqBundle = Bundle()
        req.toBundle(reqBundle)
        val extras = Bundle().apply {
            putInt("_mmessage_sdkVersion", 638067200)
            putString("_mmessage_appPackage", packageName)
            putBundle("_mmessage_content", reqBundle)
            putString("_mmessage_checksum", computeChecksum(APP_ID, packageName, 638067200))
            putString("_wxapi_basereq_openid", req.openId ?: "")
            putString("_wxapi_basereq_transaction", req.transaction ?: "")
            putInt("_wxapi_command_type", 1)
        }
        val launchIntent = Intent().apply {
            setClassName("com.tencent.mm", "com.tencent.mm.plugin.base.stub.WXEntryActivity")
            putExtras(extras)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            appCtx.startActivity(launchIntent)
            true
        } catch (e: Throwable) {
            android.util.Log.e("WeChatApi", "Failed to launch WeChat (raw)", e)
            false
        }
    }

    fun notifyAuthResult(errCode: Int, code: String?, state: String?) {
        val intent = Intent(ACTION_HANDLE_RESP).apply {
            setPackage(packageName)
            putExtra("errCode", errCode)
            putExtra("code", code)
            putExtra("state", state)
        }
        android.util.Log.i("WeChatApi", "notifyAuthResult: errCode=$errCode, code=${code?.take(8)}, sending broadcast to $packageName")
        appCtx.sendBroadcast(intent)
        android.util.Log.i("WeChatApi", "notifyAuthResult: broadcast sent")
    }

    /**
     * 由 [WXEntryActivity.onCreate] 调用，处理来自微信的回调。
     */
    fun handleWXEntryIntent(intent: Intent, callback: AuthCallback) {
        android.util.Log.i("WeChatApi", "handleWXEntryIntent: intent action=${intent.action}")
        try {
            val result = wxApi.handleIntent(intent, object : com.tencent.mm.opensdk.openapi.IWXAPIEventHandler {
                override fun onReq(req: com.tencent.mm.opensdk.modelbase.BaseReq?) {
                    // 不处理 request
                }

                override fun onResp(resp: com.tencent.mm.opensdk.modelbase.BaseResp?) {
                    android.util.Log.i("WeChatApi", "handleWXEntryIntent onResp: type=${resp?.javaClass?.simpleName}, errCode=${resp?.errCode}")
                    if (resp is com.tencent.mm.opensdk.modelmsg.SendAuth.Resp) {
                        callback.onAuthResponse(resp.errCode, resp.code, resp.state)
                    } else if (resp != null) {
                        callback.onAuthResponse(resp.errCode, null, null)
                    } else {
                        callback.onAuthResponse(-1, null, null)
                    }
                }
            })
            android.util.Log.i("WeChatApi", "handleWXEntryIntent: handleIntent returned $result")
            if (!result) {
                callback.onAuthResponse(-1, null, null)
            }
        } catch (e: Throwable) {
            android.util.Log.e("WeChatApi", "handleIntent failed", e)
            callback.onAuthResponse(-1, null, null)
        }
    }

    interface AuthCallback {
        fun onAuthResponse(errCode: Int, code: String?, state: String?)
    }

    private fun computeChecksum(appId: String, pkgName: String, sdkVersion: Int): String {
        val input = "$appId$pkgName$sdkVersion"
        return try {
            val md = java.security.MessageDigest.getInstance("MD5")
            val digest = md.digest(input.toByteArray(Charsets.UTF_8))
            digest.joinToString("") { "%02x".format(it) }
        } catch (e: Exception) {
            ""
        }
    }
}

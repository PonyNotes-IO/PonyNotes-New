package com.xiaomabiji.app.note

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.xiaomabiji.app.note.wechat.WeChatApi
import com.xiaomabiji.app.note.wechat.WeChatBridge

class MainActivity : FlutterActivity() {
    private val channelName = "com.xiaomabiji.app.note/open_url"
    private var weChatBridge: WeChatBridge? = null

    companion object {
        /**
         * 当前活动的 [WeChatBridge] 实例，由 [WXEntryActivity] 在另一个独立 task
         * 拉起时通过这个静态引用把回调结果直接送回 [WeChatBridge.deliverResult]，
         * 不依赖 Broadcast。
         *
         * 注意：这里持有的是 *同进程* 的引用（`WXEntryActivity` 与 `MainActivity`
         * 都在 `:app` 进程里），所以静态字段是安全且即时的。
         */
        @Volatile
        var activeWeChatBridge: WeChatBridge? = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Prevent black screen by ensuring the window has a solid background
        // before Flutter renders the first frame
        window.setBackgroundDrawableResource(android.R.color.white)
        // Keep screen on during initial load to prevent display sleep issues
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Bypass url_launcher_android 6.x Pigeon channel (which fails to register
        // on this project due to AGP/plugin compileSdk mismatches) by providing
        // our own MethodChannel that opens URLs via ACTION_VIEW.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openUrl" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrEmpty()) {
                            result.error("INVALID_URL", "url is null or empty", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: ActivityNotFoundException) {
                            result.error(
                                "NO_APP",
                                "No activity found to handle the url",
                                null,
                            )
                        } catch (e: Throwable) {
                            result.error("OPEN_URL_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // 微信登录 MethodChannel
        // 修复 Android 14/15 上腾讯 SDK 6.8.34 自带的 PendingIntent bug：
        // 不用腾讯 SDK 自带的 sendReq，自己构造 PendingIntent。
        val bridge = WeChatBridge(this)
        weChatBridge = bridge
        activeWeChatBridge = bridge
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WeChatBridge.CHANNEL_NAME)
            .setMethodCallHandler(bridge)
    }

    override fun onDestroy() {
        weChatBridge?.dispose()
        weChatBridge = null
        activeWeChatBridge = null
        super.onDestroy()
    }

    /**
     * 标记上一次处理过的微信回调 Intent，用于去重（防止同一个回调触发多次 deliverResult）。
     *
     * 用 **errCode + code + state 组合** 作为唯一 key：
     * - 微信回调 Intent 的 action 通常是 null（SDK 走显式 Intent 启动 WXEntryActivity），
     *   dataString 也往往是 null，所以不能用 action/dataString 做 key。
     * - 组合三个业务字段能稳定区分两次不同的回调。
     */
    private var lastProcessedWxSignature: String? = null

    override fun onResume() {
        super.onResume()
        // Ensure background is restored on resume (fixes black screen after backgrounding)
        window.setBackgroundDrawableResource(android.R.color.white)
        // Clear keep screen on flag once app is loaded
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        // 检查是否有微信 SDK 的回调 intent。
        // 注意：用户从微信「允许」回到 MainActivity 时，getIntent() 拿到的是
        // 启动 MainActivity 那个原始 intent（通常是 launcher intent，没有 _wxapi 字段），
        // 真正的回调 Intent 在 WXEntryActivity 那侧。所以这条 onResume 路径主要捕获
        // 那些 PendingIntent 直接打到 MainActivity 的极端场景（比如 SDK fallback）。
        val intent = intent
        if (intent?.hasExtra("_wxapi_baseresp_errcode") == true) {
            val errCode = intent.getIntExtra("_wxapi_baseresp_errcode", -1)
            val code = intent.getStringExtra("_wxapi_sendauth_resp_state") ?: ""
                // 注意：实际 code 不在 _wxapi_sendauth_resp_state，
                // SDK 把它放在 _wxapi_sendauth_resp_code；用 SDK 的 handleIntent 解析最稳。
            val signature = "errCode=$errCode"
            android.util.Log.i(
                "WeChatBridge",
                "MainActivity.onResume: detected WeChat callback intent, signature=$signature",
            )
            if (signature != lastProcessedWxSignature) {
                lastProcessedWxSignature = signature
                val api = WeChatApi(this)
                api.handleWXEntryIntent(intent, object : WeChatApi.AuthCallback {
                    override fun onAuthResponse(errCode: Int, code: String?, state: String?) {
                        android.util.Log.i(
                            "WeChatBridge",
                            "MainActivity.onResume WeChat response: errCode=$errCode, code=${code?.take(8)}, state=$state",
                        )
                        activeWeChatBridge?.deliverResult(errCode, code, state)
                        // 重置标记，允许下次登录的回调被处理
                        lastProcessedWxSignature = null
                    }
                })
            } else {
                android.util.Log.i(
                    "WeChatBridge",
                    "MainActivity.onResume: skip duplicate WeChat callback (signature=$signature)",
                )
            }
        }

        // 清掉上次的 WeChat auth pending 状态 — 如果用户离开微信没回调就回主界面
        // pending 会一直卡住阻塞下次登录。
        android.util.Log.i(
            "WeChatBridge",
            "MainActivity.onResume, calling resetOnResume (pendingResult=${weChatBridge?.pendingResultForLog() ?: "no-bridge"})",
        )
        weChatBridge?.resetOnResume()
    }
}

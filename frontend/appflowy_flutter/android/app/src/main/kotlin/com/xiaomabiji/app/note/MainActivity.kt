package com.xiaomabiji.app.note

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.xiaomabiji.app.note.wechat.WeChatBridge

class MainActivity : FlutterActivity() {
    private val channelName = "com.xiaomabiji.app.note/open_url"
    private var weChatBridge: WeChatBridge? = null

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WeChatBridge.CHANNEL_NAME)
            .setMethodCallHandler(bridge)
    }

    override fun onDestroy() {
        weChatBridge?.dispose()
        weChatBridge = null
        super.onDestroy()
    }

    override fun onResume() {
        super.onResume()
        // Ensure background is restored on resume (fixes black screen after backgrounding)
        window.setBackgroundDrawableResource(android.R.color.white)
        // Clear keep screen on flag once app is loaded
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        // 清掉上次的 WeChat auth pending 状态 — 如果用户离开微信没回调就回主界面
        // pending 会一直卡住阻塞下次登录。
        weChatBridge?.resetOnResume()
    }
}
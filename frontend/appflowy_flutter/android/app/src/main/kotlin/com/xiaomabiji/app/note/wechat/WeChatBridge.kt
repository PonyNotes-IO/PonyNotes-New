package com.xiaomabiji.app.note.wechat

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 微信登录 MethodChannel 桥接。
 *
 * **Channel 名**：`com.xiaomabiji.app.note/wechat`
 *
 * **方法**：
 * - `isInstalled() -> bool`   检查微信是否已安装
 * - `auth(state: String) -> { errCode, code, state }`  发起授权，返回微信回调
 *
 * **回调机制**：
 * 1. Flutter 调用 `auth` 时，本类记下 pendingResult，向 WeChatApi 发送 PendingIntent
 * 2. 用户在微信里点同意 → 微信拉起 WXEntryActivity
 * 3. WXEntryActivity 通过 ACTION_HANDLE_RESP broadcast 把结果发回来
 * 4. WeChatBridge 收到 broadcast，调用 pendingResult.success(...)
 *
 * **安全机制**：
 * - 单实例守卫：同一时刻只有一个 auth 在 in-flight，否则返回 ALREADY_RUNNING
 * - 超时清理：2 分钟没拿到回调就自动 reset，避免上次残留阻塞
 * - onResume 主动 reset：返回主界面时清掉 pending
 */
class WeChatBridge(private val activity: FlutterActivity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL_NAME = "com.xiaomabiji.app.note/wechat"
        private const val AUTH_TIMEOUT_MS = 120_000L

        /**
         * onResume 后等这么久：如果 broadcast 还没到，pending 视为陈旧，按取消处理。
         *
         * 选 1500ms 是因为：
         * - 正常流程：用户在微信里点同意/拒绝 → 微信关掉 → 我们 onResume → broadcast 几乎同时到，
         *   远小于 1.5s
         * - 异常流程：微信 SDK 没回调、用户从别处回来 → 1.5s 后自动清理，避免 pending 卡住
         */
        private const val STALE_RESUME_MS = 1500L
    }

    private val api = WeChatApi(activity)
    private var pendingResult: MethodChannel.Result? = null
    private var pendingTimeout: Runnable? = null
    private val handler = Handler(Looper.getMainLooper())

    /**
     * pending 状态下的开始时间戳，用于 onResume 时判断 pending 是否已经"陈旧"。
     *
     * 调用时序：
     *   用户点按钮 → Flutter 调 auth → pendingResult 设置 + 记录 pendingTimestamp
     *   → 微信 APP 被拉起 → 我们 APP onPause
     *   → 用户在微信里点同意/拒绝 → 微信关掉 → 我们 APP onResume
     *   → 此时 broadcast 会在 onResume 之后很快到达（毫秒级）
     *
     * onResume 时不立即清 pending，而是 post 一个延迟任务：
     *   - 如果 [STALE_RESUME_MS] 毫秒内 broadcast 到了，pending 已被 receiver 清掉，
     *     这个 runnable 跑起来时看到 pendingResult==null 就直接 return。
     *   - 如果超过 [STALE_RESUME_MS] broadcast 还没来，说明用户是真取消/微信没回调，
     *     这时才当作 CANCELLED 处理。
     */
    private var pendingTimestamp: Long = 0L
    private val staleResumeCheckRunnable = Runnable {
        val result = pendingResult ?: return@Runnable
        val now = System.currentTimeMillis()
        if (now - pendingTimestamp > STALE_RESUME_MS) {
            android.util.Log.i("WeChatBridge", "pending stale after resume, treating as cancel")
            clearPending()
            result.error("CANCELLED", "WeChat auth cancelled (stale resume)", null)
        }
    }

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != WeChatApi.ACTION_HANDLE_RESP) return

            val result = pendingResult ?: return
            clearPending()

            val errCode = intent.getIntExtra("errCode", -1)
            val code = intent.getStringExtra("code")
            val state = intent.getStringExtra("state")

            result.success(
                mapOf(
                    "errCode" to errCode,
                    "code" to code,
                    "state" to state,
                ),
            )
        }
    }

    init {
        val filter = IntentFilter(WeChatApi.ACTION_HANDLE_RESP)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            activity.registerReceiver(receiver, filter)
        }
    }

    /**
     * 由 MainActivity.onResume 调用。
     *
     * 修复前的问题：onResume 时**无条件**清掉 pending 并 error CANCELLED，导致正常流程
     * （用户点同意/拒绝 → 微信关掉 → 我们 APP onResume → broadcast 紧跟着到达）也被
     * 误杀成 CANCELLED。
     *
     * 修复后：post 一个延迟任务 [staleResumeCheckRunnable]。如果 broadcast 在
     * [STALE_RESUME_MS] 毫秒内到达，receiver 会清掉 pending，runnable 跑起来时
     * pendingResult 已为 null 直接 return；如果超过这个窗口 broadcast 还没来，
     * 才当作"用户取消/微信没回调"处理。
     */
    fun resetOnResume() {
        if (pendingResult == null) return
        handler.removeCallbacks(staleResumeCheckRunnable)
        handler.postDelayed(staleResumeCheckRunnable, STALE_RESUME_MS)
    }

    fun dispose() {
        try {
            activity.unregisterReceiver(receiver)
        } catch (_: IllegalArgumentException) {
            // already unregistered
        }
        val r = pendingResult
        clearPending()
        r?.error("DISPOSED", "WeChatBridge disposed", null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isInstalled" -> {
                result.success(api.isInstalled())
            }
            "auth" -> {
                val state = call.argument<String>("state")
                    ?: System.currentTimeMillis().toString()

                // 已有 pending 时拒绝新请求（防止快速点击）
                if (pendingResult != null) {
                    result.error("ALREADY_RUNNING", "WeChat auth already in progress", null)
                    return
                }

                pendingResult = result
                pendingTimestamp = System.currentTimeMillis()
                val ok = api.startAuth(state)
                if (!ok) {
                    clearPending()
                    result.error("AUTH_FAILED", "Failed to start WeChat auth", null)
                    return
                }
                // 排个超时，2 分钟没拿到回调就主动 error 给 Flutter，避免永久卡死
                pendingTimeout = Runnable {
                    val r = pendingResult ?: return@Runnable
                    clearPending()
                    r.error("TIMEOUT", "WeChat auth timed out", null)
                }.also { handler.postDelayed(it, AUTH_TIMEOUT_MS) }
            }
            else -> result.notImplemented()
        }
    }

    private fun clearPending() {
        pendingResult = null
        pendingTimeout?.let { handler.removeCallbacks(it) }
        pendingTimeout = null
        handler.removeCallbacks(staleResumeCheckRunnable)
        pendingTimestamp = 0L
    }
}

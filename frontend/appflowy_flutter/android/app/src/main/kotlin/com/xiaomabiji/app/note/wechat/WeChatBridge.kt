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
 * **回调机制（双保险）**：
 * 1. **直接调用**：`WXEntryActivity` 解析完回调后直接调用
 *    [deliverResult]（同进程，零依赖），这是首选路径。
 * 2. **Broadcast**：`WeChatApi.notifyAuthResult` 也广播一条
 *    `ACTION_HANDLE_RESP`，receiver 兜底（处理 WXEntryActivity 跑在独立进程
 *    或被宿主进程强制重置的极端场景）。
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
         * onResume 后等这么久：如果回调还没到，pending 视为陈旧，按取消处理。
         *
         * 选 1500ms 是因为：
         * - 正常流程：用户在微信里点同意/拒绝 → 微信关掉 → 我们 onResume →
         *   WXEntryActivity 已经 finish 或正在 finish，回调会通过 [deliverResult]
         *   几乎同时到达，远小于 1.5s
         * - 异常流程：微信 SDK 没回调、用户从别处回来 → 1.5s 后自动清理，
         *   避免 pending 卡住
         */
        private const val STALE_RESUME_MS = 1500L
    }

    private val api = WeChatApi(activity)
    private var pendingResult: MethodChannel.Result? = null
    private var pendingTimeout: Runnable? = null
    private val handler = Handler(Looper.getMainLooper())

    /** 只读访问，给 log 用：返回当前 pending 是否存在。 */
    fun pendingResultForLog(): String = if (pendingResult != null) "present" else "null"

    /**
     * 由 [WXEntryActivity] 直接调用的回调入口。
     *
     * 这是首选回调路径：WXEntryActivity 解析完微信回调后，直接调用本方法，
     * 不依赖 Broadcast 系统。同进程内同步可达，没有 RECEIVER_NOT_EXPORTED、
     * PendingIntent flag、Android 14 广播优化等坑点。
     *
     * 通过 [Handler] post 到主线程，保证与 [onMethodCall] 同线程，避免
     * `pendingResult.success()` 在非主线程调用导致 MethodChannel 状态异常。
     */
    fun deliverResult(errCode: Int, code: String?, state: String?) {
        android.util.Log.i(
            "WeChatBridge",
            "deliverResult from WXEntryActivity: errCode=$errCode, code=${code?.take(8)}, state=$state",
        )
        handler.post {
            val result = pendingResult ?: run {
                android.util.Log.w("WeChatBridge", "deliverResult: no pendingResult, ignoring")
                return@post
            }
            clearPending()
            result.success(
                mapOf(
                    "errCode" to errCode,
                    "code" to code,
                    "state" to state,
                ),
            )
        }
    }

    /**
     * pending 状态下的开始时间戳，用于 onResume 时判断 pending 是否已经"陈旧"。
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
            android.util.Log.i("WeChatBridge", "receiver got broadcast: action=${intent.action}")
            if (intent.action != WeChatApi.ACTION_HANDLE_RESP) return

            val errCode = intent.getIntExtra("errCode", -1)
            val code = intent.getStringExtra("code")
            val state = intent.getStringExtra("state")
            // 直接走 deliverResult 的同一路径，避免两条路径双发结果。
            deliverResult(errCode, code, state)
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
     * （用户点同意/拒绝 → 微信关掉 → 我们 APP onResume → WXEntryActivity 紧跟着回调）
     * 也被误杀成 CANCELLED。
     *
     * 修复后：post 一个延迟任务 [staleResumeCheckRunnable]。如果回调在
     * [STALE_RESUME_MS] 毫秒内到达（无论是 WXEntryActivity 直接 deliverResult
     * 还是 receiver 收到 broadcast），pending 已被清掉，runnable 跑起来时
     * pendingResult 已为 null 直接 return；如果超过这个窗口回调还没来，
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

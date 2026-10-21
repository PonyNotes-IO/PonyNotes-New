package com.xiaomabiji.app.note.wechat

import android.os.Handler
import android.os.Looper
import com.tencent.mm.opensdk.modelpay.PayReq
import com.tencent.mm.opensdk.openapi.WXAPIFactory
import com.xiaomabiji.app.note.AndroidPrivacyConsent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class WeChatPayBridge(private val activity: FlutterActivity) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL_NAME = "com.xiaomabiji.app.note/wechat_pay"
    }

    private val handler = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private var prepayId: String? = null
    private val timeout = Runnable { finish(-3) }
    private val resumedWithoutCallback = Runnable { finish(-3) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "pay") {
            result.notImplemented()
            return
        }
        if (!AndroidPrivacyConsent.hasAccepted(activity)) {
            result.error("CONSENT_REQUIRED", "请先同意隐私政策", null)
            return
        }
        if (pending != null) {
            result.error("ALREADY_RUNNING", "正在处理微信支付", null)
            return
        }
        val fields = listOf("appid", "partnerid", "prepayid", "package", "noncestr", "timestamp", "sign")
        if (fields.any { call.argument<String>(it).isNullOrBlank() }
            || call.argument<String>("appid") != WeChatApi.APP_ID
            || call.argument<String>("package") != "Sign=WXPay"
            || call.argument<String>("timestamp")?.toLongOrNull() == null) {
            result.error("INVALID_ARGUMENT", "微信App支付参数无效", null)
            return
        }
        try {
            val api = WXAPIFactory.createWXAPI(activity, WeChatApi.APP_ID, true)
            if (!api.isWXAppInstalled) {
                result.error("NOT_INSTALLED", "请先安装微信", null)
                return
            }
            api.registerApp(WeChatApi.APP_ID)
            val request = PayReq().apply {
                appId = WeChatApi.APP_ID
                partnerId = call.argument<String>("partnerid")
                prepayId = call.argument<String>("prepayid")
                packageValue = "Sign=WXPay"
                nonceStr = call.argument<String>("noncestr")
                timeStamp = call.argument<String>("timestamp")
                sign = call.argument<String>("sign")
            }
            if (!AndroidPrivacyConsent.setAssociationFlowEnabled(activity, "wechatPay", true)) {
                result.error("CONSENT_REQUIRED", "请先同意隐私政策", null)
                return
            }
            pending = result
            prepayId = request.prepayId
            handler.postDelayed(timeout, 300_000L)
            if (!api.sendReq(request)) finish(-1)
        } catch (error: Exception) {
            if (pending != null) finish(-1)
            else result.error("START_FAILED", "无法启动微信支付", null)
        }
    }

    fun deliverResult(errCode: Int, responsePrepayId: String?) {
        if (!responsePrepayId.isNullOrEmpty() && responsePrepayId != prepayId) return
        finish(errCode)
    }

    fun onResume() {
        if (pending != null) handler.postDelayed(resumedWithoutCallback, 2_000L)
    }

    fun dispose() {
        finish(-3)
        handler.removeCallbacksAndMessages(null)
    }

    private fun finish(errCode: Int) {
        val result = pending ?: return
        pending = null
        prepayId = null
        handler.removeCallbacks(timeout)
        handler.removeCallbacks(resumedWithoutCallback)
        AndroidPrivacyConsent.setAssociationFlowEnabled(activity, "wechatPay", false)
        // SDK结果仅供展示，支付成功必须再向后端查单确认。
        result.success(mapOf("errCode" to errCode))
    }
}

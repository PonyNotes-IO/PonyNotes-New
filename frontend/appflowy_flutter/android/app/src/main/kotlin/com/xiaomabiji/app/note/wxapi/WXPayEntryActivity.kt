package com.xiaomabiji.app.note.wxapi

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import com.tencent.mm.opensdk.modelbase.BaseReq
import com.tencent.mm.opensdk.modelbase.BaseResp
import com.tencent.mm.opensdk.modelpay.PayResp
import com.tencent.mm.opensdk.openapi.IWXAPIEventHandler
import com.tencent.mm.opensdk.openapi.WXAPIFactory
import com.xiaomabiji.app.note.AndroidPrivacyConsent
import com.xiaomabiji.app.note.MainActivity
import com.xiaomabiji.app.note.wechat.WeChatApi

class WXPayEntryActivity : Activity(), IWXAPIEventHandler {
    private var holdsCallback = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleCallback(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleCallback(intent)
    }

    private fun handleCallback(callbackIntent: Intent?) {
        if (!AndroidPrivacyConsent.hasAccepted(this)) {
            finish()
            return
        }
        if (!holdsCallback) holdsCallback = AndroidPrivacyConsent.acquireWeChatPayCallback(this)
        try {
            if (callbackIntent != null) {
                WXAPIFactory.createWXAPI(this, WeChatApi.APP_ID, true).handleIntent(callbackIntent, this)
            }
            if (MainActivity.activeWeChatPayBridge == null) {
                // 进程被回收时恢复主界面；会员开通仍由服务器通知完成。
                startActivity(Intent(this, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                })
            }
        } finally {
            finish()
        }
    }

    override fun onReq(req: BaseReq?) = Unit

    override fun onResp(resp: BaseResp?) {
        if (resp is PayResp) MainActivity.activeWeChatPayBridge?.deliverResult(resp.errCode, resp.prepayId)
    }

    override fun onDestroy() {
        if (holdsCallback) AndroidPrivacyConsent.releaseWeChatPayCallback(this)
        super.onDestroy()
    }
}

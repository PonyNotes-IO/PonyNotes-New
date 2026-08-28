package com.postliu.douyin_login

import android.content.Context
import android.content.Intent
import android.util.Log
import com.bytedance.sdk.open.aweme.CommonConstants
import com.bytedance.sdk.open.aweme.authorize.model.Authorization
import com.bytedance.sdk.open.aweme.common.handler.IApiEventHandler
import com.bytedance.sdk.open.aweme.common.model.BaseReq
import com.bytedance.sdk.open.aweme.common.model.BaseResp
import com.bytedance.sdk.open.douyin.DouYinOpenApiFactory
import com.bytedance.sdk.open.douyin.DouYinOpenConfig
import com.bytedance.sdk.open.douyin.api.DouYinOpenApi
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

/** DouyinPlugin */
class DouyinPlugin : FlutterPlugin, MethodCallHandler, ActivityAware,
    PluginRegistry.NewIntentListener {

    companion object {
        private const val TAG = "DouyinPlugin"
        const val Init = "init"
        const val AuthorizedLogin = "AuthorizedLogin"
        const val OnAuthorCallback = "onAuthorCallback"
        const val CancelAuthor = "cancelAuthor"
        const val Error = "error"
    }

    private lateinit var channel: MethodChannel

    private lateinit var context: Context

    private lateinit var binding: ActivityPluginBinding

    private var douYinOpenApi: DouYinOpenApi? = null

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        this.binding = binding
        this.binding.addOnNewIntentListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        this.binding = binding
    }

    override fun onDetachedFromActivity() {
    }

    override fun onNewIntent(intent: Intent): Boolean {
        Log.i(TAG, "onNewIntent: $intent")
        val extra = DouyinCallbackActivity.extraCallback(intent)
        if (extra != null) {
            if (douYinOpenApi != null) {
                douYinOpenApi?.handleIntent(extra, iApiEventHandler)
            }
            return true
        }
        return false
    }

    private val iApiEventHandler = object : IApiEventHandler {
        override fun onReq(baseReq: BaseReq) {

        }

        override fun onResp(baseResp: BaseResp) {
            when (baseResp.type) {
                CommonConstants.ModeType.SEND_AUTH_RESPONSE -> {
                    if (baseResp is Authorization.Response) {
                        Log.i(TAG, "onResp: ${baseResp.authCode}")
                        val result = mapOf(
                            "code" to baseResp.errorCode,
                            "permission" to baseResp.grantedPermissions,
                            "authCode" to baseResp.authCode,
                        )
                        channel.invokeMethod(OnAuthorCallback, result)
//                        if (baseResp.isSuccess) {
//                            channel.invokeMethod(OnAuthorCallback, result)
//
//                        } else if (baseResp.isCancel) {
//                            channel.invokeMethod(CancelAuthor, result)
//                        } else {
//                            channel.invokeMethod(Error, result)
//                        }
                    }
                }
            }
        }

        override fun onErrorIntent(intent: Intent) {

        }
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "douyin")
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        Log.i(TAG, "onMethodCall: ${call.method}")
        when (call.method) {
            Init -> {
                handleInitCall(call, result)
            }

            AuthorizedLogin -> {
                handleAuthorCall(call, result)
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    private fun handleInitCall(
        call: MethodCall, result: Result
    ) {
        val state = kotlin.runCatching {
            val clientKey = call.argument<String>("apiKey")
            DouYinOpenApiFactory.init(DouYinOpenConfig(clientKey))
        }.onSuccess {
            Log.i(TAG, "handleInitCall: 初始化成功:$it")
        }.onFailure {
            Log.i(TAG, "handleInitCall: $it")
        }.getOrElse { false }
        result.success("success")
    }

    /**
     * 申请授权
     */
    private fun handleAuthorCall(call: MethodCall, result: Result) {
        if (douYinOpenApi == null) {
            douYinOpenApi = DouYinOpenApiFactory.create(binding.activity)
        }
        val scopeKey = call.argument<String>("scope")
        val request = Authorization.Request().apply {
            scope = scopeKey
            Log.i(TAG, "handleAuthorCall: ${context.packageName}")
            callerLocalEntry = "${context.packageName}.douyinapi.DouYinEntryActivity"
        }
        val author = douYinOpenApi?.authorize(request)
        Log.i(TAG, "handleAuthorCall: $author");
        result.success("success")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}

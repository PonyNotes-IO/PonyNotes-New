package com.xiaomabiji.app.note

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.util.Log

object AndroidPrivacyConsent {
    // Reuse the existing Flutter SharedPreferences key so upgrades retain consent.
    private const val PREFERENCES = "FlutterSharedPreferences"
    private const val ACCEPTED_KEY = "flutter.privacy_policy_accepted"
    private val weChatCallbackLeaseLock = Any()
    private var weChatCallbackLeaseCount = 0
    private var weChatCallbackDisablePending = false

    fun hasAccepted(context: Context): Boolean =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getBoolean(ACCEPTED_KEY, false)

    fun accept(context: Context): Boolean {
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        if (preferences.edit().putBoolean(ACCEPTED_KEY, true).commit()) {
            return true
        }
        // commit() updates the memory cache even when its disk write fails.
        preferences.edit().putBoolean(ACCEPTED_KEY, false).commit()
        return false
    }

    fun syncConsentControlledComponents(context: Context) {
        setAssociationComponentsEnabled(context, false)
        if (hasAccepted(context)) {
            AndroidReminderRestoreScheduler.sync(context)
        } else {
            setReminderRestoreEnabled(context, false)
        }
    }

    fun setAssociationFlowEnabled(context: Context, flow: String, enabled: Boolean): Boolean {
        if (enabled && !hasAccepted(context)) return false
        val components = associationComponents(context, flow) ?: return false
        if (flow == "wechatLogin") {
            return synchronized(weChatCallbackLeaseLock) {
                if (enabled) {
                    // A newer auth flow must not inherit an older callback's
                    // deferred disable request.
                    weChatCallbackDisablePending = false
                    components.forEach { setComponentEnabled(context, it, true) }
                } else if (weChatCallbackLeaseCount > 0) {
                    // Disabling an Activity while it is dispatching the WeChat
                    // response can make Android tear down the host task.
                    weChatCallbackDisablePending = true
                } else {
                    components.forEach { setComponentEnabled(context, it, false) }
                }
                true
            }
        }
        components.forEach { setComponentEnabled(context, it, enabled) }
        return true
    }

    /**
     * Keeps the WeChat callback component enabled until the active callback
     * Activity has finished. The component is still disabled before consent and
     * immediately after all non-callback cleanup paths.
     */
    fun acquireWeChatCallbackLease(context: Context): Boolean {
        if (!hasAccepted(context)) return false
        synchronized(weChatCallbackLeaseLock) {
            weChatCallbackLeaseCount += 1
            // A callback can outlive the Flutter host after process recovery.
            // Its own destruction must still close the temporary association.
            weChatCallbackDisablePending = true
        }
        return true
    }

    fun releaseWeChatCallbackLease(context: Context) {
        synchronized(weChatCallbackLeaseLock) {
            if (weChatCallbackLeaseCount > 0) {
                weChatCallbackLeaseCount -= 1
                if (weChatCallbackLeaseCount == 0 && weChatCallbackDisablePending) {
                    weChatCallbackDisablePending = false
                    // Keep the state transition under the same lock as a new auth
                    // flow. Otherwise an old callback can disable a newer flow's
                    // freshly enabled callback component.
                    associationComponents(context, "wechatLogin")
                        ?.forEach { setComponentEnabled(context, it, false) }
                }
            }
        }
    }

    fun setReminderRestoreEnabled(context: Context, enabled: Boolean) {
        if (enabled && hasAccepted(context)) {
            AndroidReminderRestoreScheduler.sync(context)
        } else {
            AndroidReminderRestoreScheduler.disable(context)
        }
    }

    private fun setAssociationComponentsEnabled(context: Context, enabled: Boolean) {
        listOf("wechatLogin", "douyinLogin", "alipay").forEach { flow ->
            setAssociationFlowEnabled(context, flow, enabled)
        }
    }

    private fun associationComponents(context: Context, flow: String): List<String>? {
        val packageName = context.packageName
        return when (flow) {
            "wechatLogin" -> listOf(
                "$packageName.wechat.WXEntryActivity",
                "$packageName.wxapi.WXEntryActivity",
            )
            "douyinLogin" -> listOf(
                "com.postliu.douyin_login.DouyinCallbackActivity",
                "$packageName.douyinapi.DouYinEntryActivity",
            )
            "alipay" -> listOf(
                "com.alipay.sdk.app.PayResultActivity",
                "com.alipay.sdk.app.AlipayResultActivity",
            )
            else -> null
        }
    }

    internal fun setComponentEnabled(context: Context, className: String, enabled: Boolean) {
        val state = if (enabled) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        } else {
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        }
        try {
            context.packageManager.setComponentEnabledSetting(
                ComponentName(context.packageName, className),
                state,
                PackageManager.DONT_KILL_APP,
            )
        } catch (error: IllegalArgumentException) {
            // Keep upgrades resilient if a third-party SDK renames or removes a component.
            Log.w("AndroidPrivacyConsent", "Component not present: $className", error)
        }
    }
}

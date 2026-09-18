package com.xiaomabiji.app.note

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.util.Log

object AndroidPrivacyConsent {
    // Reuse the existing Flutter SharedPreferences key so upgrades retain consent.
    private const val PREFERENCES = "FlutterSharedPreferences"
    private const val ACCEPTED_KEY = "flutter.privacy_policy_accepted"

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
        val packageName = context.packageName
        val components = when (flow) {
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
            else -> return false
        }
        components.forEach { setComponentEnabled(context, it, enabled) }
        return true
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

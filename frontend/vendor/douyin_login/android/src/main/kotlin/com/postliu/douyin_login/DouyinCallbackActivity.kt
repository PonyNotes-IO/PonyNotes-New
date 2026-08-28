package com.postliu.douyin_login

import android.app.Activity
import android.content.Intent
import android.os.Bundle

class DouyinCallbackActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent) {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        launchIntent?.putExtra(KEY_DOUYIN_CALLBACK, true)
        launchIntent?.putExtra(KEY_DOUYIN_EXTRA, intent)
        launchIntent?.flags = Intent.FLAG_ACTIVITY_CLEAR_TOP
        startActivity(launchIntent)
        finish()
    }

    companion object {
        private const val KEY_DOUYIN_CALLBACK = "douyin_callback"
        private const val KEY_DOUYIN_EXTRA = "douyin_extra"
        fun extraCallback(intent: Intent): Intent? {
            return if (intent.extras != null && intent.getBooleanExtra(
                    /* name = */ KEY_DOUYIN_CALLBACK,
                    /* defaultValue = */ false
                )
            ) {
                intent.getParcelableExtra(KEY_DOUYIN_EXTRA)
            } else null
        }
    }
}

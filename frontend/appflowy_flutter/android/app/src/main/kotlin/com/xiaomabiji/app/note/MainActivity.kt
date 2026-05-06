package com.xiaomabiji.app.note

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Prevent black screen by ensuring the window has a solid background
        // before Flutter renders the first frame
        window.setBackgroundDrawableResource(android.R.color.white)
        // Keep screen on during initial load to prevent display sleep issues
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun onResume() {
        super.onResume()
        // Ensure background is restored on resume (fixes black screen after backgrounding)
        window.setBackgroundDrawableResource(android.R.color.white)
        // Clear keep screen on flag once app is loaded
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
}

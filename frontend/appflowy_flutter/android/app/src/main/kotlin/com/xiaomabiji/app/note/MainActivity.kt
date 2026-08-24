package com.xiaomabiji.app.note

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import com.xiaomabiji.app.note.wechat.WeChatApi
import com.xiaomabiji.app.note.wechat.WeChatBridge

class MainActivity : FlutterActivity() {
    private val channelName = "com.xiaomabiji.app.note/open_url"
    private var weChatBridge: WeChatBridge? = null
    private var handwritingExportResult: MethodChannel.Result? = null
    private var handwritingExportBytes: ByteArray? = null

    companion object {
        private const val HANDWRITING_EXPORT_CHANNEL =
            "com.xiaomabiji.app.note/handwriting_export"
        private const val HANDWRITING_EXPORT_REQUEST_CODE = 42871

        /**
         * 当前活动的 [WeChatBridge] 实例，由 [WXEntryActivity] 在另一个独立 task
         * 拉起时通过这个静态引用把回调结果直接送回 [WeChatBridge.deliverResult]，
         * 不依赖 Broadcast。
         *
         * 注意：这里持有的是 *同进程* 的引用（`WXEntryActivity` 与 `MainActivity`
         * 都在 `:app` 进程里），所以静态字段是安全且即时的。
         */
        @Volatile
        var activeWeChatBridge: WeChatBridge? = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Keep the themed launch image behind Flutter during startup.
        window.setBackgroundDrawableResource(R.drawable.launch_background)
        // Keep screen on during initial load to prevent display sleep issues
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // Keep Flutter's generated plugin registration. In particular, the
        // QR login dialogs use flutter_inappwebview's platform view on Android.
        super.configureFlutterEngine(flutterEngine)
        // ═══════════════════════════════════════════════════════════════════
        // 兜底二次注册：Tobias 支付宝插件在部分国内定制 ROM 上可能因为
        // MultiDex / ClassLoader 时序导致 GeneratedPluginRegistrant 中的
        // "new com.jarvan.tobias.TobiasPlugin()" 虽然 class 已入 dex，但
        // 仍然抛出 NoClassDefFoundError / ClassNotFoundException，或者
        // 注册 try-catch 吞掉了异常。这里我们直接在 MainActivity 侧兜底：
        //   - 用反射解析出当前 engine 中已注册的所有插件
        //   - 若 TobiasPlugin 不在列表里，手动实例化并 attach
        //   - 每一步打印日志，方便通过 logcat 精确定位
        // ═══════════════════════════════════════════════════════════════════
        ensurePluginRegistered(
            engine = flutterEngine,
            tag = "TobiasPluginGuard",
            pluginClassName = "com.jarvan.tobias.TobiasPlugin",
            channelName = "com.jarvanmo/tobias",
        )
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HANDWRITING_EXPORT_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "saveFile") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (handwritingExportResult != null) {
                    result.error("ALREADY_ACTIVE", "A handwriting export is already active", null)
                    return@setMethodCallHandler
                }

                val fileName = call.argument<String>("fileName")
                val bytes = call.argument<ByteArray>("bytes")
                if (fileName.isNullOrBlank() || bytes == null) {
                    result.error("INVALID_ARGUMENT", "fileName and bytes are required", null)
                    return@setMethodCallHandler
                }

                handwritingExportResult = result
                handwritingExportBytes = bytes
                try {
                    startActivityForResult(
                        Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "application/x-ponynhw"
                            putExtra(Intent.EXTRA_TITLE, fileName)
                        },
                        HANDWRITING_EXPORT_REQUEST_CODE,
                    )
                } catch (e: Throwable) {
                    clearHandwritingExport()
                    result.error("SAVE_FILE_FAILED", e.message, null)
                }
            }

        // 微信登录 MethodChannel
        // 修复 Android 14/15 上腾讯 SDK 6.8.34 自带的 PendingIntent bug：
        // 不用腾讯 SDK 自带的 sendReq，自己构造 PendingIntent。
        val bridge = WeChatBridge(this)
        weChatBridge = bridge
        activeWeChatBridge = bridge
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WeChatBridge.CHANNEL_NAME)
            .setMethodCallHandler(bridge)
    }

    override fun onDestroy() {
        handwritingExportResult?.error("ACTIVITY_DESTROYED", "Export was interrupted", null)
        clearHandwritingExport()
        weChatBridge?.dispose()
        weChatBridge = null
        activeWeChatBridge = null
        super.onDestroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != HANDWRITING_EXPORT_REQUEST_CODE) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }

        val result = handwritingExportResult
        val bytes = handwritingExportBytes
        if (resultCode == Activity.RESULT_CANCELED) {
            clearHandwritingExport()
            result?.success(null)
            return
        }

        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || bytes == null) {
            clearHandwritingExport()
            result?.error("SAVE_FILE_FAILED", "No writable destination was returned", null)
            return
        }

        try {
            contentResolver.openOutputStream(uri, "wt")?.use { output ->
                output.write(bytes)
            } ?: error("Unable to open the selected destination")
            clearHandwritingExport()
            result?.success(uri.toString())
        } catch (e: Throwable) {
            clearHandwritingExport()
            result?.error("SAVE_FILE_FAILED", e.message, null)
        }
    }

    private fun clearHandwritingExport() {
        handwritingExportResult = null
        handwritingExportBytes = null
    }

    /**
     * 确保指定 Flutter 插件已经被 attach 到当前 [FlutterEngine] 上。
     *
     * 典型故障： GeneratedPluginRegistrant.java 里每一个插件注册都包了一层
     * `try/catch(Exception)`，catch 里只打 `Log.e("GeneratedPluginRegistrant", …)`。
     * 这意味着：
     *   - ClassNotFoundException / NoClassDefFoundError (MultiDex 时序)
     *   - ExceptionInInitializerError
     *   - onAttachedToEngine 内部抛异常
     *  都会被悄悄吞掉，Dart 侧只能看到 MissingPluginException，完全看不到
     *  Android 端真正的堆栈。
     *
     *  本函数显式做三件事并把详细日志打出来：
     *   1) 尝试 Class.forName(pluginClassName)，失败打印 ClassLoader 与多 dex 诊断
     *   2) 通过反射读取 flutterEngine.plugins 中已注册插件的类名集合
     *   3) 如果目标插件不在集合里，手动实例化 + onAttachedToEngine + add 到 plugins
     *
     * @param pluginClassName 完全限定名，例如 "com.jarvan.tobias.TobiasPlugin"
     * @param channelName     Dart 侧 invokeMethod 时使用的 channel 名，仅用于日志
     */
    private fun ensurePluginRegistered(
        engine: FlutterEngine,
        tag: String,
        pluginClassName: String,
        channelName: String,
    ) {
        val loader = Thread.currentThread().contextClassLoader ?: this@MainActivity.classLoader
        Log.i(
            tag,
            "ensurePluginRegistered: class=$pluginClassName channel=$channelName " +
                "classLoader=$loader"
        )

        // 1) 确认插件类能被 ClassLoader 找到
        val pluginClass: Class<*> = try {
            Class.forName(pluginClassName, false, loader)
        } catch (t: Throwable) {
            Log.e(tag, "ClassLoader 找不到插件类 $pluginClassName (dex 中是否存在？)", t)
            val classLoaderDexes = runCatching {
                loader.javaClass.getMethod("getDex").invoke(loader)?.toString()
                    ?: "<no-dex>"
            }.getOrDefault("<read-failed>")
            Log.e(
                tag,
                "ClassLoader hint: dex field=$classLoaderDexes; " +
                    "MultiDex.install 仅发生在 Application.attachBaseContext。" +
                    "若 minSdk<21 请在自定义 Application 中显式调用 MultiDex.install(base)。"
            )
            return
        }
        Log.i(tag, "Class.forName 成功：${pluginClass.name}")

        // 2) 检查 engine.plugins 中是否已经注册了该类的实例
        val pluginsContainer = engine.plugins
        val alreadyRegistered: Boolean = try {
            val pluginsField = pluginsContainer.javaClass.getDeclaredField("plugins")
            pluginsField.isAccessible = true
            val pluginsList = pluginsField.get(pluginsContainer) as? List<*> ?: emptyList<Any>()
            pluginsList.any { plugin ->
                plugin != null && pluginClassName == plugin.javaClass.name
            }
        } catch (t: Throwable) {
            Log.w(tag, "反射检查 plugins 集合失败，跳过已注册检测，直接走 attach。", t)
            false
        }
        if (alreadyRegistered) {
            Log.i(tag, "插件 $pluginClassName 已在 engine.plugins 中，无需重复注册。")
            return
        }
        Log.w(
            tag,
            "插件 $pluginClassName 未出现在 engine.plugins 中！GeneratedPluginRegistrant " +
                "很可能通过 catch 吞掉了注册异常。立即执行手动 attach..."
        )

        // 3) 手动实例化 + attach（不带 try/catch — 任何异常都要让开发者看见）
        val instance: FlutterPlugin = try {
            @Suppress("UNCHECKED_CAST")
            pluginClass.getDeclaredConstructor().newInstance() as FlutterPlugin
        } catch (t: Throwable) {
            Log.e(tag, "实例化插件 $pluginClassName 失败（构造函数/初始化异常）", t)
            return
        }
        Log.i(tag, "手动实例化成功: $instance")
        try {
            pluginsContainer.add(instance)
            Log.i(tag, "手动 register 成功: 插件 $pluginClassName → channel $channelName 已就绪")
        } catch (t: Throwable) {
            Log.e(tag, "engine.plugins.add(instance) 失败: onAttachedToEngine 内部抛异常？", t)
        }
    }

    /**
     * 标记上一次处理过的微信回调 Intent，用于去重（防止同一个回调触发多次 deliverResult）。
     *
     * 用 **errCode + code + state 组合** 作为唯一 key：
     * - 微信回调 Intent 的 action 通常是 null（SDK 走显式 Intent 启动 WXEntryActivity），
     *   dataString 也往往是 null，所以不能用 action/dataString 做 key。
     * - 组合三个业务字段能稳定区分两次不同的回调。
     */
    private var lastProcessedWxSignature: String? = null

    override fun onResume() {
        super.onResume()
        // Ensure background is restored on resume (fixes black screen after backgrounding)
        window.setBackgroundDrawableResource(android.R.color.white)
        // Clear keep screen on flag once app is loaded
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        // 检查是否有微信 SDK 的回调 intent。
        // 注意：用户从微信「允许」回到 MainActivity 时，getIntent() 拿到的是
        // 启动 MainActivity 那个原始 intent（通常是 launcher intent，没有 _wxapi 字段），
        // 真正的回调 Intent 在 WXEntryActivity 那侧。所以这条 onResume 路径主要捕获
        // 那些 PendingIntent 直接打到 MainActivity 的极端场景（比如 SDK fallback）。
        val intent = intent
        if (intent?.hasExtra("_wxapi_baseresp_errcode") == true) {
            val errCode = intent.getIntExtra("_wxapi_baseresp_errcode", -1)
            val code = intent.getStringExtra("_wxapi_sendauth_resp_state") ?: ""
                // 注意：实际 code 不在 _wxapi_sendauth_resp_state，
                // SDK 把它放在 _wxapi_sendauth_resp_code；用 SDK 的 handleIntent 解析最稳。
            val signature = "errCode=$errCode"
            android.util.Log.i(
                "WeChatBridge",
                "MainActivity.onResume: detected WeChat callback intent, signature=$signature",
            )
            if (signature != lastProcessedWxSignature) {
                lastProcessedWxSignature = signature
                val api = WeChatApi(this)
                api.handleWXEntryIntent(intent, object : WeChatApi.AuthCallback {
                    override fun onAuthResponse(errCode: Int, code: String?, state: String?) {
                        android.util.Log.i(
                            "WeChatBridge",
                            "MainActivity.onResume WeChat response: errCode=$errCode, code=${code?.take(8)}, state=$state",
                        )
                        activeWeChatBridge?.deliverResult(errCode, code, state)
                        // 重置标记，允许下次登录的回调被处理
                        lastProcessedWxSignature = null
                    }
                })
            } else {
                android.util.Log.i(
                    "WeChatBridge",
                    "MainActivity.onResume: skip duplicate WeChat callback (signature=$signature)",
                )
            }
        }

        // 清掉上次的 WeChat auth pending 状态 — 如果用户离开微信没回调就回主界面
        // pending 会一直卡住阻塞下次登录。
        android.util.Log.i(
            "WeChatBridge",
            "MainActivity.onResume, calling resetOnResume (pendingResult=${weChatBridge?.pendingResultForLog() ?: "no-bridge"})",
        )
        weChatBridge?.resetOnResume()
    }
}

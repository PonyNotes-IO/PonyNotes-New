import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import common from '@ohos.app.ability.common';

const MESSAGE_CHANNEL_NAME = "appflowy_backend";
const TAG: string = 'AppFlowyBackendPlugin';

/**
 * AppFlowy 后端插件的鸿蒙实现。
 *
 * 对齐 Android 版 AppFlowyBackendPlugin：注册 MethodChannel "appflowy_backend"。
 * 除了 getPlatformVersion，还提供 getFilesDir / getCacheDir / getTemporaryDir
 * 用于替代 path_provider（鸿蒙上 path_provider 无 ohos 实现）。
 * 实际的 Rust FFI 桥接在 Dart 侧通过 dart:ffi 完成。
 */
export default class AppFlowyBackendPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private context: common.Context | null = null;

  getUniqueClassName(): string {
    return "AppFlowyBackendPlugin"
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.context = binding.getApplicationContext();
    this.channel = new MethodChannel(binding.getBinaryMessenger(), MESSAGE_CHANNEL_NAME);
    this.channel.setMethodCallHandler(this)
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null)
    this.channel = null
    this.context = null
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case "getPlatformVersion":
        result.success("HarmonyOS");
        break;
      case "getFilesDir":
        // 应用文件目录（持久化存储）
        this.getPath(result, (ctx) => ctx.filesDir);
        break;
      case "getCacheDir":
        // 应用缓存目录
        this.getPath(result, (ctx) => ctx.cacheDir);
        break;
      case "getTemporaryDir":
        // 临时目录（等同 cacheDir）
        this.getPath(result, (ctx) => ctx.tempDir ?? ctx.cacheDir);
        break;
      case "getApplicationSupportDir":
        // 应用支持目录（等同 filesDir）
        this.getPath(result, (ctx) => ctx.filesDir);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  private getPath(result: MethodResult, getter: (ctx: common.Context) => string): void {
    try {
      if (this.context) {
        const dir = getter(this.context);
        result.success(dir);
      } else {
        result.error("NO_CONTEXT", "Application context is null", null);
      }
    } catch (e) {
      result.error("PATH_ERROR", `Failed to get path: ${e}`, null);
    }
  }
}

import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';

const MESSAGE_CHANNEL_NAME = "appflowy_backend";
const TAG: string = 'AppFlowyBackendPlugin';

/**
 * AppFlowy 后端插件的鸿蒙实现。
 *
 * 对齐 Android 版 AppFlowyBackendPlugin：注册 MethodChannel "appflowy_backend"，
 * 处理 getPlatformVersion，其余方法返回 notImplemented。
 * 实际的 Rust FFI 桥接在 Dart 侧通过 dart:ffi 完成，此插件仅做平台占位与版本查询。
 */
export default class AppFlowyBackendPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;

  getUniqueClassName(): string {
    return "AppFlowyBackendPlugin"
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), MESSAGE_CHANNEL_NAME);
    this.channel.setMethodCallHandler(this)
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null)
    this.channel = null
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case "getPlatformVersion":
        result.success("HarmonyOS");
        break;
      default:
        result.notImplemented();
        break;
    }
  }
}

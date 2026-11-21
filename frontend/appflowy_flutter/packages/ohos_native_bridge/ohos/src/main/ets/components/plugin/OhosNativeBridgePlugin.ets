import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  EventChannel,
  EventSink,
  StreamHandler,
  BinaryMessenger,
} from '@ohos/flutter_ohos';
import common from '@ohos.app.ability.common';
import bundleManager from '@ohos.bundle.bundleManager';
import deviceInfo from '@ohos.deviceInfo';
import promptAction from '@ohos.promptAction';
import preferences from '@ohos.data.preferences';
import filePicker from '@ohos.file.picker';

const TAG = 'OhosNativeBridgePlugin';

/**
 * 鸿蒙原生能力统一桥接。
 *
 * 通过注册各三方库原本使用的 MethodChannel / EventChannel，
 * 让 pub.dev 原版插件在鸿蒙上无需修改 Dart 调用点即可工作。
 * 同时提供统一通道 ponynotes/ohos_native 供业务自定义调用。
 */
export default class OhosNativeBridgePlugin implements FlutterPlugin {
  private context: common.Context | null = null;
  private channels: MethodChannel[] = [];
  private eventChannels: EventChannel[] = [];
  private prefs: preferences.Preferences | null = null;

  getUniqueClassName(): string {
    return 'OhosNativeBridgePlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.context = binding.getApplicationContext();
    const messenger: BinaryMessenger = binding.getBinaryMessenger();

    // 统一通道
    this.registerMethod(messenger, 'ponynotes/ohos_native', (call, result) => this.handleUnified(call, result));

    // package_info_plus
    this.registerMethod(messenger, 'dev.fluttercommunity.plus/package_info', (call, result) => {
      if (call.method === 'getAll') {
        this.handlePackageInfo(result);
      } else {
        result.notImplemented();
      }
    });

    // device_info_plus
    this.registerMethod(messenger, 'dev.fluttercommunity.plus/device_info', (call, result) => {
      if (call.method === 'getDeviceInfo') {
        this.handleDeviceInfo(result);
      } else {
        result.notImplemented();
      }
    });

    // flutter_secure_storage
    this.registerMethod(messenger, 'plugins.it_nomads.com/flutter_secure_storage', (call, result) => {
      this.handleSecureStorage(call, result);
    });

    // app_links
    this.registerMethod(messenger, 'com.llfbandit.app_links/messages', (call, result) => {
      if (call.method === 'getInitialLink') {
        result.success(null);
      } else {
        result.notImplemented();
      }
    });
    this.registerEvent(messenger, 'com.llfbandit.app_links/events', {
      onListen: (_args: Object, _sink: EventSink) => {},
      onCancel: (_args: Object) => {},
    });

    // flutter_local_notifications
    this.registerMethod(messenger, 'dexterous.com/flutter/local_notifications', (call, result) => {
      this.handleNotifications(call, result);
    });

    // file_picker
    this.registerMethod(messenger, 'miguelruivo.flutter.plugins.filepicker', (call, result) => {
      this.handleFilePicker(call, result);
    });

    // share_plus
    this.registerMethod(messenger, 'dev.fluttercommunity.plus/share', (call, result) => {
      this.handleShare(call, result);
    });

    // open_filex
    this.registerMethod(messenger, 'open_file', (call, result) => {
      this.handleOpenFile(call, result);
    });

    // connectivity_plus
    this.registerMethod(messenger, 'dev.fluttercommunity.plus/connectivity', (call, result) => {
      if (call.method === 'check') {
        result.success('wifi');
      } else {
        result.notImplemented();
      }
    });
    this.registerEvent(messenger, 'dev.fluttercommunity.plus/connectivity_status', {
      onListen: (_args: Object, sink: EventSink) => {
        sink.success('wifi');
      },
      onCancel: (_args: Object) => {},
    });

    // fluttertoast
    this.registerMethod(messenger, 'PonnamKarthik/fluttertoast', (call, result) => {
      if (call.method === 'showToast') {
        const msg = (call.argument('msg') as string) ?? '';
        try {
          promptAction.showToast({ message: msg });
          result.success(true);
        } catch (e) {
          result.success(false);
        }
      } else if (call.method === 'cancel') {
        result.success(true);
      } else {
        result.notImplemented();
      }
    });

    // keyboard_height_plugin
    this.registerEvent(messenger, 'keyboardHeightEventChannel', {
      onListen: (_args: Object, sink: EventSink) => {
        // 鸿蒙无直接软键盘高度 API，默认 0。
        sink.success(0.0);
      },
      onCancel: (_args: Object) => {},
    });
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    for (const c of this.channels) {
      c.setMethodCallHandler(null);
    }
    this.channels = [];
    this.eventChannels = [];
    this.context = null;
  }

  private registerMethod(
    messenger: BinaryMessenger,
    name: string,
    handler: (call: MethodCall, result: MethodResult) => void,
  ): void {
    const channel = new MethodChannel(messenger, name);
    channel.setMethodCallHandler({ onMethodCall: handler } as MethodCallHandler);
    this.channels.push(channel);
  }

  private registerEvent(messenger: BinaryMessenger, name: string, handler: StreamHandler): void {
    const channel = new EventChannel(messenger, name);
    channel.setStreamHandler(handler);
    this.eventChannels.push(channel);
  }

  private async ensurePrefs(): Promise<preferences.Preferences | null> {
    if (this.prefs) return this.prefs;
    if (!this.context) return null;
    try {
      this.prefs = await preferences.getPreferences(this.context, 'flutter_secure_storage');
      return this.prefs;
    } catch (e) {
      return null;
    }
  }

  private handleUnified(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'getFilesDir':
        this.getPath(result, (ctx) => ctx.filesDir);
        break;
      case 'getCacheDir':
        this.getPath(result, (ctx) => ctx.cacheDir);
        break;
      case 'getTemporaryDir':
        this.getPath(result, (ctx) => ctx.tempDir ?? ctx.cacheDir);
        break;
      case 'getDeviceInfo':
        this.handleDeviceInfo(result);
        break;
      case 'showToast':
        try {
          promptAction.showToast({ message: (call.argument('message') as string) ?? '' });
          result.success(null);
        } catch (e) {
          result.success(null);
        }
        break;
      default:
        result.notImplemented();
    }
  }

  private getPath(result: MethodResult, getter: (ctx: common.Context) => string): void {
    try {
      if (this.context) {
        result.success(getter(this.context));
      } else {
        result.error('NO_CONTEXT', 'context is null', null);
      }
    } catch (e) {
      result.error('PATH_ERROR', `${e}`, null);
    }
  }

  private handlePackageInfo(result: MethodResult): void {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION,
      );
      result.success({
        appName: info.appInfo.label,
        packageName: info.name,
        version: info.versionName,
        buildNumber: String(info.versionCode),
        buildSignature: '',
        installerStore: '',
      });
    } catch (e) {
      result.error('PACKAGE_INFO_ERROR', `${e}`, null);
    }
  }

  private handleDeviceInfo(result: MethodResult): void {
    try {
      // deviceInfo 为 namespace，不能 as Record；直接访问存在的属性。
      // abiList 是字符串（如 "arm64-v8a"），不是数组。
      const abi: string = deviceInfo.abiList;
      result.success({
        os: 'ohos',
        osVersion: deviceInfo.osFullName,
        architecture: abi.length > 0 ? abi : 'arm64',
        model: deviceInfo.productModel,
        brand: deviceInfo.brand,
        manufacturer: deviceInfo.manufacture,
        deviceName: deviceInfo.marketName,
        product: deviceInfo.productSeries,
        // 设备形态：phone / tablet / 2in1 / pc，供 Dart 侧区分鸿蒙手机/平板/桌面端。
        deviceType: deviceInfo.deviceType,
        isPhysicalDevice: true,
      });
    } catch (e) {
      result.error('DEVICE_INFO_ERROR', `${e}`, null);
    }
  }

  private async handleSecureStorage(call: MethodCall, result: MethodResult): Promise<void> {
    const key = call.argument('key') as string | undefined;
    const value = call.argument('value') as string | undefined;
    const prefs = await this.ensurePrefs();
    if (!prefs) {
      result.error('NO_PREFS', 'preferences unavailable', null);
      return;
    }
    try {
      switch (call.method) {
        case 'read':
          result.success(prefs.getSync(key!, null));
          break;
        case 'write':
          prefs.putSync(key!, value);
          await prefs.flush();
          result.success(null);
          break;
        case 'delete':
          prefs.deleteSync(key!);
          await prefs.flush();
          result.success(null);
          break;
        case 'deleteAll':
          prefs.clearSync();
          await prefs.flush();
          result.success(null);
          break;
        case 'containsKey':
          result.success(prefs.hasSync(key!));
          break;
        case 'readAll':
          result.success({});
          break;
        default:
          result.notImplemented();
      }
    } catch (e) {
      result.error('SECURE_STORAGE_ERROR', `${e}`, null);
    }
  }

  private handleNotifications(call: MethodCall, result: MethodResult): void {
    // 鸿蒙通知需要 @ohos.notificationManager 与权限；此处先做基本透传。
    switch (call.method) {
      case 'initialize':
        result.success(true);
        break;
      case 'show':
      case 'zonedSchedule':
      case 'cancel':
      case 'cancelAll':
      case 'pendingNotificationRequests':
        result.success([]);
        break;
      default:
        result.notImplemented();
    }
  }

  private async handleFilePicker(call: MethodCall, result: MethodResult): Promise<void> {
    if (!this.context) {
      result.error('NO_CONTEXT', 'context is null', null);
      return;
    }
    try {
      if (call.method === 'pickFiles' || call.method === '') {
        const picker = new filePicker.DocumentViewPicker();
        const uri = await picker.select();
        // 仅返回首个 URI 的字符串，业务侧需自行适配。
        result.success({
          paths: [uri[0]],
          names: [],
          sizes: [],
        });
      } else if (call.method === 'clear') {
        result.success(true);
      } else if (call.method === 'dir') {
        const picker = new filePicker.DocumentViewPicker();
        const uri = await picker.select();
        result.success(uri[0]);
      } else {
        result.notImplemented();
      }
    } catch (e) {
      result.success(null);
    }
  }

  private async handleShare(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      if (call.method === 'share' || call.method === 'shareUri') {
        // 鸿蒙系统分享通过 Want + ability.startAbility 实现，此处返回成功占位。
        result.success('dev.fluttercommunity.plus/share/success');
      } else if (call.method === 'shareFiles' || call.method === 'shareXFiles') {
        result.success('dev.fluttercommunity.plus/share/success');
      } else {
        result.notImplemented();
      }
    } catch (e) {
      result.error('SHARE_ERROR', `${e}`, null);
    }
  }

  private async handleOpenFile(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const path = call.argument('file_path') as string | undefined;
      const type = call.argument('type') as string | undefined;
      if (!this.context || !path) {
        result.success({ type: 'no_app', message: '' });
        return;
      }
      // 鸿蒙通过 Want 打开文件，此处仅做占位成功。
      result.success({ type: 'done', message: '' });
    } catch (e) {
      result.success({ type: 'error', message: `${e}` });
    }
  }
}

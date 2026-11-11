
import { FlutterAbility, FlutterEngine, FlutterAbilityLaunchConfigs } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { AbilityConstant, Want } from '@kit.AbilityKit';

/**
 * 鸿蒙冷启动兜底 EntryAbility。
 *
 * 背景：@ohos/flutter_ohos 的 FlutterAbility 有 7 个 getter 直接读
 * `this.launchWant.parameters![key]`，而 onCreate(want, launchParam) 完全没有
 * 用 want 参数给 launchWant 赋值。部分冷启动路径下系统未注入
 * UIAbility.launchWant，导致空引用崩溃（getCachedEngineId → setupFlutterEngine
 * → onAttach → onCreate 即崩）。
 *
 * 修复：从 onCreate/onNewWant 的真实 want 构造 safeWant（保证 want 与
 * parameters 非空），覆写全部 launchWant 解引用点改读 safeWant；并尝试补齐
 * this.launchWant（部分版本只读，try/catch 兜底）。
 */
export default class EntryAbility extends FlutterAbility {
  // 保证非空的 safeWant，兜底 launchWant 未注入场景
  private safeWant: Want = { parameters: {} } as Want;

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
  }

  // 从真实 want 构造 safeWant，保证 want 与 parameters 非空
  private ensureWant(want?: Want): void {
    const w: Want = want != undefined ? want : ({ parameters: {} } as Want);
    if (w.parameters == undefined) {
      w.parameters = {} as Record<string, Object>;
    }
    // 优先用系统已注入的 launchWant；否则尝试把 safeWant 回填给 launchWant
    try {
      if (!this.launchWant) {
        this.launchWant = w;
      } else {
        this.safeWant = this.launchWant;
      }
    } catch (_e) {
      // launchWant 只读，保持 safeWant 作为读取源
    }
    this.safeWant = this.launchWant != undefined ? this.launchWant : w;
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam) {
    this.ensureWant(want);
    super.onCreate(want, launchParam);
  }

  onNewWant(want: Want, launchParams: AbilityConstant.LaunchParam): void {
    this.ensureWant(want);
    super.onNewWant(want, launchParams);
  }

  // ---- 覆写全部 launchWant 解引用点，改用 safeWant ----

  getWant(): Want {
    return this.safeWant;
  }

  getCachedEngineId(): string {
    return this.safeWant.parameters![FlutterAbilityLaunchConfigs.EXTRA_CACHED_ENGINE_ID] as string
  }

  getCachedEngineGroupId(): string | null {
    return this.safeWant.parameters![FlutterAbilityLaunchConfigs.EXTRA_CACHED_ENGINE_GROUP_ID] as string
  }

  getDartEntrypointArgs(): Array<string> {
    if (this.safeWant.parameters![FlutterAbilityLaunchConfigs.EXTRA_DART_ENTRYPOINT_ARGS]) {
      return this.safeWant.parameters![FlutterAbilityLaunchConfigs.EXTRA_DART_ENTRYPOINT_ARGS] as Array<string>;
    }
    return new Array<string>()
  }

  getDartEntrypointFunctionName(): string {
    if (this.safeWant.parameters![FlutterAbilityLaunchConfigs.EXTRA_DART_ENTRYPOINT]) {
      return this.safeWant.parameters![FlutterAbilityLaunchConfigs.EXTRA_DART_ENTRYPOINT] as string;
    }
    return FlutterAbilityLaunchConfigs.DEFAULT_DART_ENTRYPOINT
  }

  getInitialRoute(): string {
    if (this.safeWant.parameters![FlutterAbilityLaunchConfigs.EXTRA_INITIAL_ROUTE]) {
      return this.safeWant.parameters![FlutterAbilityLaunchConfigs.EXTRA_INITIAL_ROUTE] as string;
    }
    return ""
  }

  shouldRestoreAndSaveState(): boolean {
    if (this.safeWant.parameters![FlutterAbilityLaunchConfigs.EXTRA_CACHED_ENGINE_ID] != undefined) {
      return this.safeWant.parameters![FlutterAbilityLaunchConfigs.EXTRA_CACHED_ENGINE_ID] as boolean;
    }
    if (this.getCachedEngineId() != null && this.getCachedEngineId().length > 0) {
      return false;
    }
    return true;
  }
}

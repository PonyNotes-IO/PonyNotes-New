import 'dart:async';
import 'dart:io';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/desktop_toolbar/desktop_floating_toolbar.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/desktop_toolbar/link/link_hover_menu.dart';
import 'package:appflowy/util/expand_views.dart';
import 'package:appflowy/workspace/application/settings/prelude.dart';
import 'package:appflowy_backend/appflowy_backend.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:synchronized/synchronized.dart';

import 'deps_resolver.dart';
import 'entry_point.dart';
import 'launch_configuration.dart';
import 'plugin/plugin.dart';
import 'tasks/af_navigator_observer.dart';
import 'tasks/baidu_cloud_task.dart';
import 'tasks/file_storage_task.dart';
import 'tasks/prelude.dart';

final getIt = GetIt.instance;

abstract class EntryPoint {
  Widget create(LaunchConfiguration config);
}

class FlowyRunnerContext {
  FlowyRunnerContext({required this.applicationDataDirectory});

  final Directory applicationDataDirectory;
}

// 防止 runAppFlowy 被并发调用的锁
final _runAppFlowyLock = Lock();

Future<void> runAppFlowy({bool isAnon = false}) async {
  // 使用锁确保同一时间只有一个 runAppFlowy 在执行
  return _runAppFlowyLock.synchronized(() async {
    Log.info('🟢 runAppFlowy: isAnon: $isAnon, acquiring lock...');
    await _runAppFlowyImpl(isAnon: isAnon);
    Log.info('🟢 runAppFlowy: completed and releasing lock');
  });
}

Future<void> _runAppFlowyImpl({bool isAnon = false}) async {
  Log.info('restart AppFlowy: isAnon: $isAnon');

  if (kReleaseMode) {
    await FlowyRunner.run(
      AppFlowyApplication(),
      integrationMode(),
      isAnon: isAnon,
    );
  } else {
    // When running the app in integration test mode, we need to
    // specify the mode to run the app again.
    await FlowyRunner.run(
      AppFlowyApplication(),
      FlowyRunner.currentMode,
      didInitGetItCallback: IntegrationTestHelper.didInitGetItCallback,
      rustEnvsBuilder: IntegrationTestHelper.rustEnvsBuilder,
      isAnon: isAnon,
    );
  }
}

class FlowyRunner {
  // This variable specifies the initial mode of the app when it is launched for the first time.
  // The same mode will be automatically applied in subsequent executions when the runAppFlowy()
  // method is called.
  static var currentMode = integrationMode();

  static Future<FlowyRunnerContext> run(
    EntryPoint f,
    IntegrationMode mode, {
    // This callback is triggered after the initialization of 'getIt',
    // which is used for dependency injection throughout the app.
    // If your functionality depends on 'getIt', ensure to register
    // your callback here to execute any necessary actions post-initialization.
    Future Function()? didInitGetItCallback,
    // Passing the envs to the backend
    Map<String, String> Function()? rustEnvsBuilder,
    // Indicate whether the app is running in anonymous mode.
    // Note: when the app is running in anonymous mode, the user no need to
    // sign in, and the app will only save the data in the local storage.
    bool isAnon = false,
  }) async {
    currentMode = mode;

    // Only set the mode when it's not release mode
    if (!kReleaseMode) {
      IntegrationTestHelper.didInitGetItCallback = didInitGetItCallback;
      IntegrationTestHelper.rustEnvsBuilder = rustEnvsBuilder;
    }

    // Disable the log in test mode
    Log.shared.disableLog = mode.isTest;

    // Clear and dispose tasks from previous AppLaunch
    if (getIt.isRegistered(instance: AppLauncher)) {
      await getIt<AppLauncher>().dispose();
    }

    // Clear all the states in case of rebuilding.
    await getIt.reset();

    final config = LaunchConfiguration(
      isAnon: isAnon,
      // Unit test can't use the package_info_plus plugin
      version: '1.0.0',
      rustEnvs: rustEnvsBuilder?.call() ?? {},
    );

    // Specify the env
    await initGetIt(getIt, mode, f, config);
    await didInitGetItCallback?.call();

    // 处理 Windows deep link（在 getIt 初始化完成后）
    if (Platform.isWindows && isAppFlowyCloudEnabled) {
      try {
        await getIt<AppFlowyCloudDeepLink>().processInitialDeepLink();
      } catch (e) {
        Log.error('Failed to process initial deep link: $e');
      }
    }

    // add task
    final launcher = getIt<AppLauncher>();
    launcher.addTasks(
      [
        // this task should be first task, for handling platform errors.
        // don't catch errors in test mode
        if (!mode.isUnitTest && !mode.isIntegrationTest)
          const PlatformErrorCatcherTask(),
        // this task should be after PlatformErrorCatcherTask, for handling keyboard state errors.
        // It suppresses the known Flutter bug about keyboard state synchronization.
        if (!mode.isUnitTest && !mode.isIntegrationTest)
          const KeyboardStateFixTask(),
        // this task should be second task, for handling memory leak.
        // there's a flag named _enable in memory_leak_detector.dart. If it's false, the task will be ignored.
        MemoryLeakDetectorTask(),
        DebugTask(),
        const FeatureFlagTask(),
        // init media_kit for video/audio playback
        const InitMediaKitTask(),

        // localization
        const InitLocalizationTask(),
        // init the app window
        InitAppWindowTask(),
        // Init Rust SDK
        InitRustSDKTask(),
        // Load Plugins, like document, grid ...
        const PluginLoadTask(),
        const FileStorageTask(),
        // Preload whiteboard resources (Excalidraw WebView)
        // This should be after PluginLoadTask to ensure whiteboard plugin is loaded
        // and before InitAppWidgetTask to preload resources before UI is shown
        const WhiteboardPreloadTask(),
        // Load Baidu Cloud configuration
        const BaiduCloudConfigTask(),
        
        // Initialize notification service and check permissions
        const NotificationServiceTask(),

        // init the app widget
        // ignore in test mode
        if (!mode.isUnitTest) ...[
          // The DeviceOrApplicationInfoTask should be placed before the AppWidgetTask to fetch the app information.
          // It is unable to get the device information from the test environment.
          const ApplicationInfoTask(),
          // The auto update task should be placed after the ApplicationInfoTask to fetch the latest version.
          if (!mode.isIntegrationTest) AutoUpdateTask(),
          const HotKeyTask(),
          if (isAppFlowyCloudEnabled) InitAppFlowyCloudTask(),
          const InitAppWidgetTask(),
          const InitPlatformServiceTask(),
          const RecentServiceTask(),
        ],
      ],
    );
    await launcher.launch(); // execute the tasks
    Directory applicationDataDirectory;
    try {
      final path = await getIt<ApplicationDataStorage>().getPath();
      applicationDataDirectory = Directory(path);
    } catch (e) {
      Log.error('Failed to get application data directory: $e');
      // 使用更可靠的默认路径
      if (Platform.isAndroid) {
        // 在Android上使用缓存目录作为默认路径
        applicationDataDirectory = Directory('/data/data/ioi.xiaomabiji.ponynotes/cache');
      } else {
        applicationDataDirectory = Directory('./data');
      }
    }

    return FlowyRunnerContext(
      applicationDataDirectory: applicationDataDirectory,
    );
  }
}

Future<void> initGetIt(
  GetIt getIt,
  IntegrationMode mode,
  EntryPoint f,
  LaunchConfiguration config,
) async {
  getIt.registerFactory<EntryPoint>(() => f);
  getIt.registerLazySingleton<FlowySDK>(
    () {
      return FlowySDK();
    },
    dispose: (sdk) async {
      await sdk.dispose();
    },
  );
  getIt.registerLazySingleton<AppLauncher>(
    () => AppLauncher(
      context: LaunchContext(
        getIt,
        mode,
        config,
      ),
    ),
    dispose: (launcher) async {
      await launcher.dispose();
    },
  );
  getIt.registerSingleton<PluginSandbox>(PluginSandbox());
  getIt.registerSingleton<ViewExpanderRegistry>(ViewExpanderRegistry());
  getIt.registerSingleton<LinkHoverTriggers>(LinkHoverTriggers());
  getIt.registerSingleton<AFNavigatorObserver>(AFNavigatorObserver());
  getIt.registerSingleton<FloatingToolbarController>(
    FloatingToolbarController(),
  );

  await DependencyResolver.resolve(getIt, mode);
}

class LaunchContext {
  LaunchContext(this.getIt, this.env, this.config);

  GetIt getIt;
  IntegrationMode env;
  LaunchConfiguration config;
}

enum LaunchTaskType {
  dataProcessing,
  appLauncher,
}

/// The interface of an app launch task, which will trigger
/// some nonresident indispensable task in app launching task.
class LaunchTask {
  const LaunchTask();

  LaunchTaskType get type => LaunchTaskType.dataProcessing;

  @mustCallSuper
  Future<void> initialize(LaunchContext context) async {
    Log.info('LaunchTask: $runtimeType initialize');
  }

  @mustCallSuper
  Future<void> dispose() async {
    Log.info('LaunchTask: $runtimeType dispose');
  }
}

class AppLauncher {
  AppLauncher({
    required this.context,
  });

  final LaunchContext context;
  final List<LaunchTask> tasks = [];
  final lock = Lock();

  void addTask(LaunchTask task) {
    lock.synchronized(() {
      Log.info('AppLauncher: adding task: $task');
      tasks.add(task);
    });
  }

  void addTasks(Iterable<LaunchTask> tasks) {
    lock.synchronized(() {
      Log.info('AppLauncher: adding tasks: ${tasks.map((e) => e.runtimeType)}');
      this.tasks.addAll(tasks);
    });
  }

  Future<void> launch() async {
    await lock.synchronized(() async {
      final startTime = Stopwatch()..start();
      Log.info('AppLauncher: start initializing tasks');

      for (final task in tasks) {
        final startTaskTime = Stopwatch()..start();
        await task.initialize(context);
        final endTaskTime = startTaskTime.elapsed.inMilliseconds;
        Log.info(
          'AppLauncher: task ${task.runtimeType} initialized in $endTaskTime ms',
        );
      }

      final endTime = startTime.elapsed.inMilliseconds;
      Log.info('AppLauncher: tasks initialized in $endTime ms');
    });
  }

  Future<void> dispose() async {
    await lock.synchronized(() async {
      Log.info('AppLauncher: start clearing tasks');

      for (final task in tasks) {
        await task.dispose();
      }

      tasks.clear();

      Log.info('AppLauncher: tasks cleared');
    });
  }
}

enum IntegrationMode {
  develop,
  release,
  unitTest,
  integrationTest;

  // test mode
  bool get isTest => isUnitTest || isIntegrationTest;

  bool get isUnitTest => this == IntegrationMode.unitTest;

  bool get isIntegrationTest => this == IntegrationMode.integrationTest;

  // release mode
  bool get isRelease => this == IntegrationMode.release;

  // develop mode
  bool get isDevelop => this == IntegrationMode.develop;
}

IntegrationMode integrationMode() {
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    return IntegrationMode.unitTest;
  }

  if (kReleaseMode) {
    return IntegrationMode.release;
  }

  return IntegrationMode.develop;
}

/// Only used for integration test
class IntegrationTestHelper {
  static Future Function()? didInitGetItCallback;
  static Map<String, String> Function()? rustEnvsBuilder;
}

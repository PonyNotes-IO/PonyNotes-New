import 'dart:async';
import 'dart:convert';

import 'package:appflowy/features/workspace/data/repositories/rust_workspace_repository_impl.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_exit_flush.dart';
import 'package:appflowy/startup/launch_configuration.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/prelude.dart';
import 'package:appflowy/startup/tasks/file_storage_task.dart';
import 'package:appflowy/startup/tasks/baidu_cloud_task.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/appflowy_backend.dart' show FlowySDK;
import 'package:appflowy_backend/document_sessions.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/workspace.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_backend/rust_stream.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:window_manager/window_manager.dart';

/// Secondary engines forward requests to the single Rust core in the main engine.
class PageWindows with WindowListener {
  static final _listener = PageWindows();
  static WindowController? _current;
  static String? _mainWindowId;
  static final _children = <String>{};
  bool _isClosing = false;

  Future<void> _close() async {
    if (_isClosing) return;
    _isClosing = true;
    if (_mainWindowId == null) await closeAll();
    await WhiteboardExitFlush.instance.flushAll();
    await DocumentBloc.flushPendingChanges();
    // Reply to the requesting engine before this engine is destroyed.
    Timer.run(() => unawaited(windowManager.destroy()));
  }

  @override
  void onWindowClose() => unawaited(_close());

  static Future<bool> initialize() async {
    final current = _current = await WindowController.fromCurrentEngine();
    final arguments = current.arguments.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(current.arguments) as Map<String, dynamic>;
    _mainWindowId = arguments['mainWindowId'] as String?;
    final mainId = _mainWindowId;
    await windowManager.ensureInitialized();
    windowManager.addListener(_listener);
    await windowManager.setPreventClose(true);

    if (mainId == null) {
      await current.setWindowMethodHandler((call) async {
        final data = call.arguments;
        switch (call.method) {
          case 'request':
            return Dispatch.sendRequestBytes(data as Uint8List);
          case 'retainDocument':
            await DocumentSessions.retain(
              data['documentId'],
              owner: data['owner'],
            );
            return null;
          case 'releaseDocument':
            return DocumentSessions.release(
              data['documentId'],
              owner: data['owner'],
            );
          case 'ready':
            _children.add(data as String);
            return null;
          case 'close':
            await closeAll();
            return null;
          default:
            throw MissingPluginException(call.method);
        }
      });
      RustStreamReceiver.listen((notification) {
        final bytes = notification.writeToBuffer();
        for (final id in _children.toList()) {
          unawaited(
            WindowController.fromWindowId(id)
                .invokeMethod<void>('notification', bytes)
                .catchError((Object error) {
              Log.warn('Page window notification failed: $error');
            }),
          );
        }
      });
      onWindowsChanged.listen((_) async {
        final windows = await WindowController.getAll();
        final existing = windows.map((window) => window.windowId).toSet();
        for (final id in _children.toList()) {
          if (existing.contains(id)) continue;
          _children.remove(id);
          for (final documentId in DocumentSessions.releaseOwner(id)) {
            await FolderEventCloseView(ViewIdPB(value: documentId)).send();
          }
        }
      });
      return false;
    }

    final main = WindowController.fromWindowId(mainId);
    Dispatch.requestProxy = (bytes) async =>
        (await main.invokeMethod<Uint8List>('request', bytes))!;
    DocumentSessions.remoteRetain = (id) async {
      await main.invokeMethod<void>('retainDocument', {
        'documentId': id,
        'owner': current.windowId,
      });
    };
    DocumentSessions.remoteRelease =
        (id) async => (await main.invokeMethod<bool>('releaseDocument', {
              'documentId': id,
              'owner': current.windowId,
            }))!;
    await current.setWindowMethodHandler((call) async {
      switch (call.method) {
        case 'notification':
          RustStreamReceiver.receiveFromMainWindow(call.arguments as Uint8List);
          return null;
        case 'close':
          await _listener._close();
          return null;
        default:
          throw MissingPluginException(call.method);
      }
    });
    await main.invokeMethod<void>('ready', current.windowId);

    final view = ViewPB.fromBuffer(base64Decode(arguments['view'] as String));
    const config = LaunchConfiguration(version: '1.0.0', rustEnvs: {});
    await initGetIt(
      getIt,
      integrationMode(),
      _PageWindowEntryPoint(view),
      config,
    );
    await getIt.unregister<FlowySDK>();
    getIt<AppLauncher>().addTasks([
      const FeatureFlagTask(),
      const WebView2InitTask(),
      const InitMediaKitTask(),
      const InitLocalizationTask(),
      const PluginLoadTask(),
      const FileStorageTask(),
      const BaiduCloudConfigTask(),
      const ApplicationInfoTask(),
      const InitAppWidgetTask(),
    ]);
    await getIt<AppLauncher>().launch();
    await windowManager.setMinimumSize(const Size(480, 320));
    await windowManager.setSize(const Size(1000, 760));
    await windowManager.setTitle('${view.nameOrDefault} — PonyNotes');
    await windowManager.center();
    await windowManager.show();
    await windowManager.focus();
    return true;
  }

  static Future<void> open(ViewPB view) async {
    final current = _current;
    if (current == null) throw StateError('Page windows are not initialized');
    await WindowController.create(
      WindowConfiguration(
        arguments: jsonEncode({
          'mainWindowId': _mainWindowId ?? current.windowId,
          'view': base64Encode(view.writeToBuffer()),
        }),
      ),
    );
  }

  static Future<void> closeAll() async {
    for (final id in _children.toList()) {
      try {
        await WindowController.fromWindowId(id).invokeMethod<void>('close');
      } catch (error) {
        Log.warn('Closing page window failed: $error');
      }
      _children.remove(id);
      for (final documentId in DocumentSessions.releaseOwner(id)) {
        await FolderEventCloseView(ViewIdPB(value: documentId)).send();
      }
    }
  }
}

class _PageWindowEntryPoint implements EntryPoint {
  _PageWindowEntryPoint(this.view);
  final ViewPB view;

  @override
  Widget create(LaunchConfiguration config) => _PageWindowScreen(view: view);
}

class _PageWindowScreen extends StatefulWidget {
  const _PageWindowScreen({required this.view});
  final ViewPB view;

  @override
  State<_PageWindowScreen> createState() => _PageWindowScreenState();
}

class _PageWindowScreenState extends State<_PageWindowScreen>
    implements HomeStackDelegate {
  late final _data = _load();

  Future<(UserProfilePB, WorkspaceLatestPB)> _load() async {
    final user = await getIt<AuthService>().getUser().getOrThrow();
    final workspace =
        await FolderEventGetCurrentWorkspaceSetting().send().getOrThrow();
    getIt<TabsBloc>().add(
      TabsEvent.openPlugin(
        plugin: widget.view.plugin(),
        view: widget.view,
        setLatest: false,
      ),
    );
    return (user, workspace);
  }

  @override
  void didDeleteStackWidget(ViewPB view, int? index) {
    unawaited(windowManager.close());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(UserProfilePB, WorkspaceLatestPB)>(
      future: _data,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Scaffold(
            body: Center(
              child: snapshot.hasError
                  ? Text(snapshot.error.toString())
                  : const CircularProgressIndicator(),
            ),
          );
        }
        final (user, workspace) = snapshot.data!;
        return MultiBlocProvider(
          providers: [
            BlocProvider.value(value: getIt<TabsBloc>()),
            BlocProvider(
              create: (_) => HomeSettingBloc(
                workspace,
                context.read<AppearanceSettingsCubit>(),
                MediaQuery.sizeOf(context).width,
              ),
            ),
            BlocProvider(
              create: (_) => UserWorkspaceBloc(
                userProfile: user,
                repository: RustWorkspaceRepositoryImpl(userId: user.id),
              )..add(UserWorkspaceEvent.initialize()),
            ),
          ],
          child: Scaffold(
            body: BlocBuilder<TabsBloc, TabsState>(
              builder: (context, state) => PageStack(
                pageManager: state.currentPageManager,
                delegate: this,
                userProfile: user,
              ),
            ),
          ),
        );
      },
    );
  }
}

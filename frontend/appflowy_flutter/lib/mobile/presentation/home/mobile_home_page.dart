import 'dart:async';

import 'package:appflowy/features/workspace/data/repositories/rust_workspace_repository_impl.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/home/mobile_home_page_header.dart';
import 'package:appflowy/mobile/presentation/home/tab/mobile_space_tab.dart';
import 'package:appflowy/mobile/presentation/home/tab/space_order_bloc.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/shared/loading.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy/user/application/reminder/reminder_bloc.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_bloc.dart';
import 'package:appflowy/workspace/application/favorite/favorite_bloc.dart';
import 'package:appflowy/workspace/application/menu/sidebar_sections_bloc.dart';
import 'package:appflowy/workspace/application/recent/cached_recent_service.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/user/user_workspace_bloc.dart';
import 'package:appflowy/workspace/presentation/home/errors/workspace_failed_screen.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/workspace/workspace_notifier.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy/util/performance_trace.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/workspace.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'mobile_home_workspace_listener_policy.dart';

class MobileHomeScreen extends StatelessWidget {
  const MobileHomeScreen({super.key});

  static const routeName = '/home';

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Future.wait([
        FolderEventGetCurrentWorkspaceSetting().send(),
        getIt<AuthService>().getUser(),
      ]),
      builder: (context, snapshots) {
        if (!snapshots.hasData) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }

        final workspaceLatest = snapshots.data?[0].fold(
          (workspaceLatestPB) {
            return workspaceLatestPB as WorkspaceLatestPB?;
          },
          (error) => null,
        );
        final userProfile = snapshots.data?[1].fold(
          (userProfilePB) {
            return userProfilePB as UserProfilePB?;
          },
          (error) => null,
        );

        // In the unlikely case either of the above is null, eg.
        // when a workspace is already open this can happen.
        if (workspaceLatest == null || userProfile == null) {
          return const WorkspaceFailedScreen();
        }

        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Provider.value(
              value: userProfile,
              child: MobileHomePage(
                userProfile: userProfile,
                workspaceLatest: workspaceLatest,
              ),
            ),
          ),
        );
      },
    );
  }
}

final PropertyValueNotifier<UserWorkspacePB?> mCurrentWorkspace =
    PropertyValueNotifier<UserWorkspacePB?>(null);

class MobileHomePage extends StatefulWidget {
  const MobileHomePage({
    super.key,
    required this.userProfile,
    required this.workspaceLatest,
  });

  final UserProfilePB userProfile;
  final WorkspaceLatestPB workspaceLatest;

  @override
  State<MobileHomePage> createState() => _MobileHomePageState();
}

class _MobileHomePageState extends State<MobileHomePage> {
  Loading? loadingIndicator;

  @override
  void initState() {
    super.initState();

    getIt<MenuSharedState>().addLatestViewListener(_onLatestViewChange);
    getIt<ReminderBloc>().add(const ReminderEvent.started());
  }

  @override
  void dispose() {
    getIt<MenuSharedState>().removeLatestViewListener(_onLatestViewChange);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => UserWorkspaceBloc(
            userProfile: widget.userProfile,
            repository: RustWorkspaceRepositoryImpl(
              userId: widget.userProfile.id,
            ),
          )..add(UserWorkspaceEvent.initialize()),
        ),
        BlocProvider(
          create: (context) =>
              FavoriteBloc()..add(const FavoriteEvent.initial()),
        ),
        BlocProvider.value(
          value: getIt<ReminderBloc>()..add(const ReminderEvent.started()),
        ),
      ],
      child: _HomePage(userProfile: widget.userProfile),
    );
  }

  void _onLatestViewChange() async {
    final id = getIt<MenuSharedState>().latestOpenView?.id;
    if (id == null || id.isEmpty) {
      return;
    }
    await FolderEventSetLatestView(ViewIdPB(value: id)).send();
  }
}

class _HomePage extends StatefulWidget {
  const _HomePage({required this.userProfile});

  final UserProfilePB userProfile;

  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> with WidgetsBindingObserver {
  Loading? loadingIndicator;
  DateTime? _lastRefreshTime;
  bool _homeReadyMarked = false;
  Timer? _invitationWorkspaceRetryTimer;
  String? _invitationWorkspaceRetryId;
  int _invitationWorkspaceRetryCount = 0;
  static const Duration _refreshDebounceDuration = Duration(seconds: 1);
  static const int _maxInvitationWorkspaceRetryCount = 5;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    openWorkspaceNotifier.addListener(_openWorkspaceFromInvitation);
    // 深链可能早于移动端首页挂载，初始化时消费尚未处理的通知。
    _openWorkspaceFromInvitation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _invitationWorkspaceRetryTimer?.cancel();
    openWorkspaceNotifier.removeListener(_openWorkspaceFromInvitation);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshWorkspaceList();
    }
  }

  void _refreshWorkspaceList() {
    final now = DateTime.now();
    if (_lastRefreshTime != null &&
        now.difference(_lastRefreshTime!) <= _refreshDebounceDuration) {
      return;
    }
    _lastRefreshTime = now;

    final workspaceBloc = context.read<UserWorkspaceBloc?>();
    if (workspaceBloc != null) {
      Log.info('MobileHomePage: page visible, fetchWorkspaces');
      workspaceBloc.add(UserWorkspaceEvent.fetchWorkspaces());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<UserWorkspaceBloc, UserWorkspaceState>(
          listenWhen: didMobileWorkspaceListChange,
          listener: (_, __) => _openWorkspaceFromInvitation(),
        ),
        BlocListener<UserWorkspaceBloc, UserWorkspaceState>(
          listenWhen: didMobileCurrentWorkspaceChange,
          listener: (context, state) {
            _openWorkspaceFromInvitation();
            getIt<CachedRecentService>().reset();
            if (FeatureFlag.search.isOn) {
              context.read<CommandPaletteBloc>().add(
                    CommandPaletteEvent.workspaceChanged(
                      workspaceId: state.currentWorkspace?.workspaceId,
                    ),
                  );
            }
          },
        ),
        BlocListener<UserWorkspaceBloc, UserWorkspaceState>(
          listenWhen: didMobileCurrentWorkspaceMetadataChange,
          listener: (context, state) {
            mCurrentWorkspace.value = state.currentWorkspace;
          },
        ),
        BlocListener<UserWorkspaceBloc, UserWorkspaceState>(
          listenWhen: didMobileWorkspaceActionResultChange,
          listener: (context, state) {
            Debounce.debounce(
              'workspace_action_result',
              const Duration(milliseconds: 150),
              () {
                _showResultDialog(context, state);
              },
            );
          },
        ),
      ],
      child: BlocBuilder<UserWorkspaceBloc, UserWorkspaceState>(
        buildWhen: didMobileCurrentWorkspaceChange,
        builder: (context, state) {
          if (state.currentWorkspace == null) {
            return const SizedBox.shrink();
          }

          _markHomeReady();

          final workspaceId = state.currentWorkspace!.workspaceId;

          return BlocProvider(
            create: (_) => SpaceBloc(
              userProfile: widget.userProfile,
              workspaceId: workspaceId,
            )..add(
                const SpaceEvent.initial(
                  openFirstPage: false,
                ),
              ),
            child: Column(
              key: ValueKey('mobile_home_page_$workspaceId'),
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.only(
                    left: HomeSpaceViewSizes.mHorizontalPadding,
                    right: 8.0,
                  ),
                  child: MobileHomePageHeader(
                    userProfile: widget.userProfile,
                  ),
                ),

                Expanded(
                  child: MultiBlocProvider(
                    providers: [
                      BlocProvider(
                        create: (_) => SpaceOrderBloc()
                          ..add(const SpaceOrderEvent.initial()),
                      ),
                      BlocProvider(
                        create: (_) => SidebarSectionsBloc()
                          ..add(
                            SidebarSectionsEvent.initial(
                              widget.userProfile,
                              workspaceId,
                            ),
                          ),
                      ),
                      BlocProvider(
                        create: (_) =>
                            FavoriteBloc()..add(const FavoriteEvent.initial()),
                      ),
                    ],
                    child: MobileHomePageTab(
                      userProfile: widget.userProfile,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openWorkspaceFromInvitation() {
    if (!mounted) {
      return;
    }

    final value = openWorkspaceNotifier.value;
    final workspaceId = value?.workspaceId;
    final email = value?.email;
    if (workspaceId == null || workspaceId.isEmpty) {
      return;
    }

    final workspaceBloc = context.read<UserWorkspaceBloc>();
    final state = workspaceBloc.state;
    if (email != null &&
        email.isNotEmpty &&
        email != widget.userProfile.email) {
      Log.info(
        '[Workspace] Mobile invitation email does not match current user: $email',
      );
      return;
    }

    if (state.currentWorkspace == null) {
      _scheduleInvitationWorkspaceRefresh(workspaceBloc, workspaceId);
      return;
    }

    if (state.currentWorkspace?.workspaceId == workspaceId) {
      Log.info(
        '[Workspace] Mobile invitation target is already open: $workspaceId',
      );
      _clearInvitationWorkspace(workspaceId);
      return;
    }

    UserWorkspacePB? workspace;
    for (final item in state.workspaces) {
      if (item.workspaceId == workspaceId) {
        workspace = item;
        break;
      }
    }

    if (workspace == null) {
      _scheduleInvitationWorkspaceRefresh(workspaceBloc, workspaceId);
      return;
    }

    Log.info('[Workspace] Mobile opening invitation workspace: $workspaceId');
    workspaceBloc.add(
      UserWorkspaceEvent.openWorkspace(
        workspaceId: workspaceId,
        workspaceType: workspace.workspaceType,
      ),
    );
    _clearInvitationWorkspace(workspaceId);
  }

  void _scheduleInvitationWorkspaceRefresh(
    UserWorkspaceBloc workspaceBloc,
    String workspaceId,
  ) {
    if (_invitationWorkspaceRetryId != workspaceId) {
      _invitationWorkspaceRetryId = workspaceId;
      _invitationWorkspaceRetryCount = 0;
      _invitationWorkspaceRetryTimer?.cancel();
      _invitationWorkspaceRetryTimer = null;
    }

    // 列表刷新可能仍在进行，等待列表监听或有限重试后再发起下一次请求。
    if (_invitationWorkspaceRetryTimer != null) {
      return;
    }

    Log.info(
      '[Workspace] Mobile invitation target not loaded, refreshing workspaces',
    );
    workspaceBloc.add(UserWorkspaceEvent.fetchWorkspaces());

    final delay = Duration(
      milliseconds: 250 + (_invitationWorkspaceRetryCount * 250),
    );
    _invitationWorkspaceRetryTimer = Timer(delay, () {
      _invitationWorkspaceRetryTimer = null;
      if (!mounted || openWorkspaceNotifier.value?.workspaceId != workspaceId) {
        return;
      }

      if (_invitationWorkspaceRetryCount >= _maxInvitationWorkspaceRetryCount) {
        Log.error(
          '[Workspace] Mobile failed to open invitation workspace: $workspaceId',
        );
        _clearInvitationWorkspace(workspaceId);
        return;
      }

      _invitationWorkspaceRetryCount++;
      _openWorkspaceFromInvitation();
    });
  }

  void _clearInvitationWorkspace(String workspaceId) {
    if (openWorkspaceNotifier.value?.workspaceId == workspaceId) {
      openWorkspaceNotifier.value = null;
    }
    _invitationWorkspaceRetryTimer?.cancel();
    _invitationWorkspaceRetryTimer = null;
    _invitationWorkspaceRetryId = null;
    _invitationWorkspaceRetryCount = 0;
  }

  void _markHomeReady() {
    if (_homeReadyMarked || !PerformanceTrace.enabled) {
      return;
    }

    _homeReadyMarked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        PerformanceTrace.mark('home_ready');
      }
    });
  }

  void _showResultDialog(BuildContext context, UserWorkspaceState state) {
    final actionResult = state.actionResult;
    if (actionResult == null) {
      return;
    }

    Log.info('workspace action result: $actionResult');

    final actionType = actionResult.actionType;
    final result = actionResult.result;
    final isLoading = actionResult.isLoading;

    if (isLoading) {
      loadingIndicator ??= Loading(context)..start();
      return;
    } else {
      loadingIndicator?.stop();
      loadingIndicator = null;
    }

    if (result == null) {
      return;
    }

    result.onFailure((f) {
      Log.error(
        '[Workspace] Failed to perform ${actionType.toString()} action: $f',
      );
    });

    final String? message;
    ToastificationType toastType = ToastificationType.success;
    switch (actionType) {
      case WorkspaceActionType.create:
        message = result.fold(
          (s) {
            toastType = ToastificationType.success;
            return LocaleKeys.workspace_createSuccess.tr();
          },
          (e) {
            toastType = ToastificationType.error;
            return '${LocaleKeys.workspace_createFailed.tr()}: ${e.msg}';
          },
        );
        break;
      case WorkspaceActionType.open:
        message = result.onFailure((e) {
          toastType = ToastificationType.error;
          return '${LocaleKeys.workspace_openFailed.tr()}: ${e.msg}';
        });
        break;
      case WorkspaceActionType.delete:
        message = result.fold(
          (s) {
            toastType = ToastificationType.success;
            return LocaleKeys.workspace_deleteSuccess.tr();
          },
          (e) {
            toastType = ToastificationType.error;
            return '${LocaleKeys.workspace_deleteFailed.tr()}: ${e.msg}';
          },
        );
        break;
      case WorkspaceActionType.leave:
        message = result.fold(
          (s) {
            toastType = ToastificationType.success;
            return LocaleKeys
                .settings_workspacePage_leaveWorkspacePrompt_success
                .tr();
          },
          (e) {
            toastType = ToastificationType.error;
            return '${LocaleKeys.settings_workspacePage_leaveWorkspacePrompt_fail.tr()}: ${e.msg}';
          },
        );
        break;
      case WorkspaceActionType.rename:
        message = result.fold(
          (s) {
            toastType = ToastificationType.success;
            return LocaleKeys.workspace_renameSuccess.tr();
          },
          (e) {
            toastType = ToastificationType.error;
            return '${LocaleKeys.workspace_renameFailed.tr()}: ${e.msg}';
          },
        );
        break;
      default:
        message = null;
        toastType = ToastificationType.error;
        break;
    }

    if (message != null) {
      showToastNotification(message: message, type: toastType);
    }
  }
}

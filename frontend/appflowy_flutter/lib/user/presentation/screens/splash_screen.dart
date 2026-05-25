import 'dart:async';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/app_widget.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy/user/application/splash_bloc.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/user/domain/auth_state.dart';
import 'package:appflowy/user/presentation/helpers/helpers.dart';
import 'package:appflowy/user/presentation/router.dart';
import 'package:appflowy/user/presentation/screens/screens.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/phone_bind_screen.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_platform/universal_platform.dart';

class SplashScreen extends StatefulWidget {
  /// Root page of the app.
  const SplashScreen({super.key, required this.isAnon});

  final bool isAnon;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _hasHandledAuth = false;

  @override
  Widget build(BuildContext context) {
    if (widget.isAnon) {
      return FutureBuilder<void>(
        future: _registerIfNeeded(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox.shrink();
          }
          return _buildChild();
        },
      );
    }

    return _buildChild();
  }

  Widget _buildChild() {
    return BlocProvider(
      create: (context) =>
          getIt<SplashBloc>()..add(const SplashEvent.getUser()),
      child: Scaffold(
        body: BlocListener<SplashBloc, SplashState>(
          listenWhen: (previous, current) => previous.auth != current.auth,
          listener: (context, state) {
            _handleAuthState(context, state.auth);
          },
          child: const Body(),
        ),
      ),
    );
  }

  void _handleAuthState(BuildContext context, AuthState auth) {
    if (_hasHandledAuth || !mounted || !context.mounted) {
      return;
    }

    auth.map(
      authenticated: (result) {
        _hasHandledAuth = true;
        _handleAuthenticated(context, result);
      },
      unauthenticated: (result) {
        _hasHandledAuth = true;
        _handleUnauthenticated(context, result);
      },
      initial: (_) {},
    );
  }

  /// Check the temporary user flag directly from SharedPreferences.
  /// 直接从 SharedPreferences 检查临时用户标记。
  Future<bool> _checkTempUserSave() async {
    try {
      Log.info('[SplashScreen] Start checking tempUserSave');
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString('tempUserSave');
      Log.info('[SplashScreen] tempUserSave raw value: $value');
      final tempUserSave = value == 'true';
      Log.info('[SplashScreen] tempUserSave result: $tempUserSave');
      return tempUserSave;
    } catch (e, stack) {
      Log.error('[SplashScreen] Failed to check tempUserSave: $e', stack);
      return false;
    }
  }

  Future<void> _registerIfNeeded() async {
    final result = await UserEventGetUserProfile().send();
    if (result.isFailure) {
      await getIt<AuthService>().signUpAsGuest();
    }
  }

  /// Handles the authentication flow once a user is authenticated.
  Future<void> _handleAuthenticated(
    BuildContext context,
    Authenticated authenticated,
  ) async {
    if (!mounted || !context.mounted) {
      return;
    }

    // Check whether a third-party login still needs phone binding before
    // entering the main workspace.
    // 在进入主界面前，先检查第三方登录用户是否仍需绑定手机号。
    if (isAppFlowyCloudEnabled) {
      try {
        final profileResult = await UserBackendService.getCurrentUserProfile();
        final profile = profileResult.fold(
          (profile) => profile,
          (error) {
            Log.error(
              '[SplashScreen] Failed to get user profile: ${error.msg}',
            );
            return null;
          },
        );

        if (profile != null && _needBindPhone(profile.phone)) {
          final rootContext = AppGlobals.rootNavKey.currentState?.context;
          if (rootContext != null && rootContext.mounted) {
            unawaited(
              Navigator.of(rootContext, rootNavigator: true).push(
                MaterialPageRoute(
                  builder: (context) => const PhoneBindScreen(
                    logoutOnBack: true,
                  ),
                ),
              ),
            );
            return;
          }

          Log.error(
            '[SplashScreen] Root context not available for PhoneBindScreen navigation',
          );
          try {
            await getIt<AuthService>().signOut();
            await runAppFlowy();
          } catch (e, stack) {
            Log.error('[SplashScreen] Failed to sign out: $e', stack);
          }
          return;
        }
      } catch (e, stack) {
        Log.error('[SplashScreen] Error checking phone binding: $e', stack);
      }
    }

    if (!mounted || !context.mounted) {
      return;
    }

    // Retry until Folder is fully initialized after app relaunch.
    // 应用重启后等待 Folder 初始化完成，避免首帧卡住。
    var retryCount = 0;
    const maxRetries = 30;
    const retryDelay = Duration(milliseconds: 500);

    while (retryCount < maxRetries) {
      final result = await FolderEventGetCurrentWorkspaceSetting().send();
      final success = result.fold(
        (workspaceSetting) {
          if (!mounted || !context.mounted) {
            return true;
          }
          getIt<SplashRouter>().goHomeScreen(context);
          return true;
        },
        (error) {
          if (!mounted || !context.mounted) {
            return true;
          }
          if (error.msg.contains('Folder not initialized') &&
              retryCount < maxRetries - 1) {
            return false;
          }
          handleOpenWorkspaceError(context, error);
          return true;
        },
      );

      if (success) {
        break;
      }

      retryCount++;
      await Future.delayed(retryDelay);
    }
  }

  // Only temporary phone numbers from third-party login need binding.
  // 只有第三方登录生成的临时手机号需要绑定。
  bool _needBindPhone(String? phone) {
    if (phone == null || phone.isEmpty) {
      return false;
    }
    return phone.startsWith('+86temp');
  }

  void _handleUnauthenticated(BuildContext context, Unauthenticated result) {
    if (!mounted || !context.mounted) {
      return;
    }

    if (isAuthEnabled || UniversalPlatform.isMobile) {
      context.go(SignInScreen.routeName);
    } else {
      context.go(SkipLogInScreen.routeName);
    }
  }
}

class Body extends StatelessWidget {
  const Body({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      child: UniversalPlatform.isMobile
          ? const FlowySvg(FlowySvgs.app_logo_xl, blendMode: null)
          : const _DesktopSplashBody(),
    );
  }
}

class _DesktopSplashBody extends StatelessWidget {
  const _DesktopSplashBody();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return SingleChildScrollView(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Image(
            fit: BoxFit.cover,
            width: size.width,
            height: size.height,
            image: const AssetImage(
              'assets/images/appflowy_launch_splash.jpg',
            ),
          ),
          const CircularProgressIndicator.adaptive(),
        ],
      ),
    );
  }
}

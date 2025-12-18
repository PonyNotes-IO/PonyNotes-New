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
import 'package:universal_platform/universal_platform.dart';

class SplashScreen extends StatefulWidget {
  /// Root Page of the app.
  const SplashScreen({super.key, required this.isAnon});

  final bool isAnon;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _hasHandledAuth = false; // 防止重复处理

  @override
  Widget build(BuildContext context) {
    if (widget.isAnon) {
      return FutureBuilder<void>(
        future: _registerIfNeeded(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox.shrink();
          }
          return _buildChild(context);
        },
      );
    } else {
      return _buildChild(context);
    }
  }

  BlocProvider<SplashBloc> _buildChild(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          getIt<SplashBloc>()..add(const SplashEvent.getUser()),
      child: Scaffold(
        body: BlocListener<SplashBloc, SplashState>(
          listenWhen: (previous, current) {
            // 只在状态变化时触发，但确保 authenticated 状态会被处理
            return previous.auth != current.auth;
          },
          listener: (context, state) {
            if (_hasHandledAuth) {
              Log.info('🔵 [SplashScreen] BlocListener: already handled auth, skipping');
              return;
            }
            Log.info('🔵 [SplashScreen] BlocListener triggered, auth state: ${state.auth}');
            state.auth.map(
              authenticated: (r) {
                Log.info('🔵 [SplashScreen] BlocListener: authenticated state detected');
                _hasHandledAuth = true;
                _handleAuthenticated(context, r);
              },
              unauthenticated: (r) {
                Log.info('🔵 [SplashScreen] BlocListener: unauthenticated state detected');
                _hasHandledAuth = true;
                _handleUnauthenticated(context, r);
              },
              initial: (r) {
                Log.info('🔵 [SplashScreen] BlocListener: initial state detected');
              },
            );
          },
          child: BlocBuilder<SplashBloc, SplashState>(
            builder: (context, state) {
              // 在首次 build 时也检查状态（如果已经是 authenticated）
              if (!_hasHandledAuth) {
                state.auth.map(
                  authenticated: (r) {
                    // 使用 WidgetsBinding.instance.addPostFrameCallback 确保在 build 完成后执行
                    // 只执行一次，避免重复调用
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      // 检查是否已经处理过（通过检查 context 是否仍然 mounted）
                      if (mounted && !_hasHandledAuth) {
                        Log.info('🔵 [SplashScreen] BlocBuilder: authenticated state detected in builder (first build)');
                        _hasHandledAuth = true;
                        _handleAuthenticated(context, r);
                      }
                    });
                  },
                  unauthenticated: (r) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && !_hasHandledAuth) {
                        Log.info('🔵 [SplashScreen] BlocBuilder: unauthenticated state detected in builder (first build)');
                        _hasHandledAuth = true;
                        _handleUnauthenticated(context, r);
                      }
                    });
                  },
                  initial: (r) {},
                );
              }
              return const Body();
            },
          ),
        ),
      ),
    );
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
    Log.info('🔵 [SplashScreen] _handleAuthenticated called');
    
    // 检查用户是否需要绑定手机号（第三方登录但未绑定手机号）
    // 必须在进入主界面之前检查
    if (isAppFlowyCloudEnabled) {
      try {
        Log.info('🔵 [SplashScreen] Checking phone binding requirement...');
        final profileResult = await UserBackendService.getCurrentUserProfile();
        final profile = profileResult.fold(
          (profile) {
            Log.info('🔵 [SplashScreen] Got user profile: email=${profile.email}, phone=${profile.phone}');
            return profile;
          },
          (error) {
            Log.error('🔵 [SplashScreen] Failed to get user profile: ${error.msg}');
            return null;
          },
        );
        
        if (profile != null) {
          // 检查是否需要绑定手机号
          final needBindPhone = _needBindPhone(profile.phone);
          Log.info('🔵 [SplashScreen] User phone: "${profile.phone}", needBindPhone: $needBindPhone');
          
          if (needBindPhone) {
            Log.info('🔵 [SplashScreen] User needs phone binding, navigating to PhoneBindScreen (blocking home screen)');
            // 用户需要绑定手机号，跳转到绑定手机号页面
            // 使用同步方式，确保在进入主界面之前执行
            final rootContext = AppGlobals.rootNavKey.currentState?.context;
            if (rootContext != null && rootContext.mounted) {
              Navigator.of(rootContext, rootNavigator: true).push(
                MaterialPageRoute(
                  builder: (context) => const PhoneBindScreen(
                    logoutOnBack: true,
                  ),
                ),
              );
              Log.info('🔵 [SplashScreen] PhoneBindScreen pushed, returning without going to home screen');
              // 不进入主界面
              return;
            } else {
              Log.error('🔵 [SplashScreen] Root context not available for PhoneBindScreen navigation');
              // 如果 context 不可用，退出登录并重启应用
              try {
                await getIt<AuthService>().signOut();
                await runAppFlowy();
              } catch (e, stack) {
                Log.error('🔵 [SplashScreen] Failed to sign out: $e', stack);
              }
              return;
            }
          } else {
            Log.info('🔵 [SplashScreen] User does not need phone binding, proceeding to home screen');
          }
        } else {
          Log.info('🔵 [SplashScreen] Profile is null, proceeding to home screen');
        }
      } catch (e, stack) {
        Log.error('🔵 [SplashScreen] Error checking phone binding: $e', stack);
        // 如果检查失败，继续正常流程
      }
    }
    
    Log.info('🔵 [SplashScreen] Proceeding to home screen...');
    
    // 🔧 修复登录后卡住问题：添加重试逻辑，等待 Folder 初始化完成
    // 原因：runAppFlowy() 重新初始化应用时，Folder 可能还未完全初始化
    int retryCount = 0;
    const maxRetries = 20; // 最多等待10秒（每次500ms）
    const retryDelay = Duration(milliseconds: 500);
    
    while (retryCount < maxRetries) {
      final result = await FolderEventGetCurrentWorkspaceSetting().send();
      
      final success = result.fold(
        (workspaceSetting) {
          // After login, replace Splash screen by corresponding home screen
          Log.info('🔵 [SplashScreen] Navigating to home screen');
          getIt<SplashRouter>().goHomeScreen(
            context,
          );
          return true;
        },
        (error) {
          // 如果是 "Folder not initialized" 错误，继续重试
          if (error.msg.contains('Folder not initialized') && retryCount < maxRetries - 1) {
            return false;
          }
          // 其他错误或重试次数耗尽，显示错误
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

  // 检查是否需要绑定手机号
  // 只有第三方登录（微信、抖音）的用户才有临时手机号（+86temp...），需要绑定
  // 邮箱注册的用户手机号为空，不需要绑定
  // 手机号注册的用户有正常手机号，不需要绑定
  bool _needBindPhone(String? phone) {
    if (phone == null) {
      Log.info('🔵 [SplashScreen] _needBindPhone: phone is null, returning false');
      return false;
    }
    if (phone.isEmpty) {
      Log.info('🔵 [SplashScreen] _needBindPhone: phone is empty, returning false');
      return false;
    }
    // 只有临时手机号（第三方登录）才需要绑定
    final result = phone.startsWith('+86temp');
    Log.info('🔵 [SplashScreen] _needBindPhone: phone="$phone", startsWith("+86temp")=$result');
    return result;
  }

  void _handleUnauthenticated(BuildContext context, Unauthenticated result) {
    // replace Splash screen as root page
    if (isAuthEnabled || UniversalPlatform.isMobile) {
      context.go(SignInScreen.routeName);
    } else {
      // if the env is not configured, we will skip to the 'skip login screen'.
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

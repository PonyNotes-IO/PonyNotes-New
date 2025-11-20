import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/sign_in_bloc.dart';
import 'package:appflowy/user/presentation/router.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/desktop_sign_in_screen.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/mobile_sign_in_screen.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:universal_platform/universal_platform.dart';

class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});

  static const routeName = '/SignInScreen';

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<SignInBloc>(),
      child: BlocConsumer<SignInBloc, SignInState>(
        listener: _showSignInError,
        builder: (context, state) {
          return UniversalPlatform.isDesktop
              ? const DesktopSignInScreen()
              : const MobileSignInScreen();
        },
      ),
    );
  }

  void _showSignInError(BuildContext context, SignInState state) {
    final successOrFail = state.successOrFail;
    if (successOrFail != null) {
      Log.info('🔵 [SignInScreen] successOrFail state received');
      successOrFail.fold(
        (userProfile) {
          Log.info('🔵 [SignInScreen] Login success! User: ${userProfile.email}');
          // 检查 context 是否仍然有效
          if (!context.mounted) {
            Log.error('🔵 [SignInScreen] context is not mounted');
            return;
          }
          // 使用根导航器确保导航不会因为 context 失效而失败
          final rootContext = Navigator.of(context, rootNavigator: true).context;
          if (rootContext.mounted) {
            Log.info('🔵 [SignInScreen] Calling AuthRouter.goHomeScreen');
            getIt<AuthRouter>().goHomeScreen(rootContext, userProfile);
          } else {
            Log.error('🔵 [SignInScreen] rootContext is not mounted');
          }
        },
        (error) {
          Log.error('Sign in error: $error');
        },
      );
    }
  }
}

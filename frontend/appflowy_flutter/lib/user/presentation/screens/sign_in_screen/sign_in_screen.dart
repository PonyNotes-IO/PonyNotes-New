import 'dart:async';

import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/sign_in_bloc.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/desktop_sign_in_screen.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/mobile_sign_in_screen.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flowy_infra/platform_extension.dart';

class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});

  static const routeName = '/SignInScreen';

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<SignInBloc>(),
      child: BlocConsumer<SignInBloc, SignInState>(
        listenWhen: (previous, current) =>
            previous.successOrFail == null && current.successOrFail != null,
        listener: _handleSignInResult,
        builder: (context, state) {
          return PlatformInfo.isDesktopOrTablet
              ? const DesktopSignInScreen()
              : const MobileSignInScreen();
        },
      ),
    );
  }

  void _handleSignInResult(BuildContext context, SignInState state) {
    final successOrFail = state.successOrFail;
    if (successOrFail != null) {
      successOrFail.fold(
        (_) => unawaited(_clearTempUserSave()),
        (error) {
          Log.error('Sign in error: $error');
        },
      );
    }
  }

  Future<void> _clearTempUserSave() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('tempUserSave');
      Log.info('[SignInScreen] Cleared tempUserSave after sign-in');
    } catch (error, stackTrace) {
      Log.error(
        '[SignInScreen] Failed to clear tempUserSave: $error',
        stackTrace,
      );
    }
  }
}

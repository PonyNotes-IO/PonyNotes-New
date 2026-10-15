import 'dart:async';

import 'package:appflowy/env/backend_env.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/appflowy_cloud_task.dart';
import 'package:appflowy/startup/tasks/deeplink/deeplink_handler.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy/user/application/password/password_http_service.dart';
import 'package:appflowy/user/application/sign_in_bloc.dart';
import 'package:appflowy/user/presentation/router.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/mobile_sign_in_screen.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/set_password_page.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/continue_with_magic_link_or_passcode_page.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/continue_with/mobile_continue_with_password_page.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widget_test/test_asset_bundle.dart';

class _AuthService extends Mock implements AuthService {}

class _PasswordService extends Mock implements PasswordHttpService {}

class _DeepLink extends Mock implements AppFlowyCloudDeepLink {}

class _AuthRouter extends Mock implements AuthRouter {}

class _BuildContext extends Mock implements BuildContext {}

void main() {
  const phone = '13800138000';
  late _AuthService auth;
  late _PasswordService password;
  late _DeepLink deepLink;
  late SignInBloc bloc;
  late ValueChanged<DeepLinkResult> onDeepLink;
  late Completer<FlowyResult<UserProfilePB, FlowyError>> completion;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    registerFallbackValue(GotrueTokenResponsePB());
    registerFallbackValue(UserProfilePB());
    registerFallbackValue(_BuildContext());
    registerFallbackValue((DeepLinkResult _) {});
    registerFallbackValue(
      Completer<FlowyResult<UserProfilePB, FlowyError>>(),
    );
  });

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    Log.shared.disableLog = true;
    auth = _AuthService();
    password = _PasswordService();
    deepLink = _DeepLink();
    getIt.registerSingleton<AppFlowyCloudSharedEnv>(
      AppFlowyCloudSharedEnv(
        authenticatorType: AuthenticatorType.appflowyCloud,
        appflowyCloudConfig: AppFlowyCloudConfiguration.defaultConfig(),
      ),
    );
    getIt.registerSingleton<AppFlowyCloudDeepLink>(deepLink);
    when(() => deepLink.subscribeDeepLinkLoadingState(any()))
        .thenAnswer((call) {
      onDeepLink =
          call.positionalArguments.first as ValueChanged<DeepLinkResult>;
      return () {};
    });
    when(() => deepLink.registerCompleter(any())).thenAnswer((call) {
      completion = call.positionalArguments.first
          as Completer<FlowyResult<UserProfilePB, FlowyError>>;
    });
    when(() => password.checkPasswordStatus(phone: phone))
        .thenAnswer((_) async => FlowyResult.success(true));
    bloc = SignInBloc(auth)..passwordService = password;
  });

  tearDown(() async {
    await bloc.close();
    await getIt.reset();
    debugDefaultTargetPlatformOverride = null;
    Log.shared.disableLog = false;
  });

  Widget passwordPage({Widget? home}) => EasyLocalization(
        supportedLocales: const [Locale('zh', 'CN')],
        path: 'assets/translations',
        saveLocale: false,
        assetLoader: const TestBundleAssetLoader(),
        child: Builder(
          builder: (context) => ToastificationWrapper(
            child: MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              builder: (_, child) => AppFlowyTheme(
                data: AppFlowyDefaultTheme().light(),
                child: child!,
              ),
              home: BlocProvider.value(
                value: bloc,
                child: home ??
                    MobileContinueWithPasswordPage(
                      email: phone,
                      backToLogin: () {},
                      onEnterPassword: (_) {},
                      onForgotPassword: () {},
                    ),
              ),
            ),
          ),
        ),
      );

  testWidgets('first SMS is sent before opening the countdown; taps are gated',
      (tester) async {
    final send = Completer<FlowyResult<bool, FlowyError>>();
    when(() => password.sendOtp(phone: phone)).thenAnswer((_) => send.future);
    await tester.pumpWidget(passwordPage());
    await tester.pumpAndSettle();
    expect(defaultTargetPlatform, TargetPlatform.android);
    await tester.tap(find.byType(OutlinedButton));
    await tester.pump();
    expect(find.byType(ContinueWithMagicLinkOrPasscodePage), findsNothing);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    verify(() => password.sendOtp(phone: phone)).called(1);

    send.complete(FlowyResult.success(true));
    await tester.pump();
    await tester.runAsync(() async => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(bloc.state.isSubmitting, isFalse, reason: 'send completed');
    expect(find.byType(ContinueWithMagicLinkOrPasscodePage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'send waiter observes a complete submitting cycle',
    () async {
      when(() => password.sendOtp(phone: phone))
          .thenAnswer((_) async => FlowyResult.success(true));
      final state = await waitSignInBlocSubmittingCycle(
        bloc,
        () => bloc.add(const SignInEvent.signInWithMagicLink(email: phone)),
      );
      expect(state.isSubmitting, isFalse);
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );

  testWidgets('failed first send stays on password page without a countdown',
      (tester) async {
    when(() => password.sendOtp(phone: phone)).thenAnswer(
      (_) async => FlowyResult.failure(FlowyError(msg: 'send failed')),
    );
    await tester.pumpWidget(passwordPage());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(OutlinedButton));
    await tester.runAsync(() async => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.byType(ContinueWithMagicLinkOrPasscodePage), findsNothing);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNotNull,
    );
    when(() => password.sendOtp(phone: phone))
        .thenAnswer((_) async => FlowyResult.success(true));
    await tester.tap(find.byType(OutlinedButton));
    await tester.runAsync(() async => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.byType(ContinueWithMagicLinkOrPasscodePage), findsOneWidget);
    verify(() => password.sendOtp(phone: phone)).called(2);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iOS keeps the existing switch behavior', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(passwordPage());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    expect(find.byType(ContinueWithMagicLinkOrPasscodePage), findsOneWidget);
    verifyNever(() => password.sendOtp(phone: phone));
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  test('Android publishes one success after session and password status finish',
      () async {
    final token = GotrueTokenResponsePB(accessToken: 'test-token');
    final profile = UserProfilePB(phone: phone);
    final passwordStatus = Completer<FlowyResult<bool, FlowyError>>();
    final sessionStarted = Completer<void>();
    final sessionReady = Completer<void>();
    when(() => auth.signInWithPasscode(email: phone, passcode: '123456'))
        .thenAnswer((_) async => FlowyResult.success(token));
    when(() => password.checkPasswordStatus(phone: phone))
        .thenAnswer((_) => passwordStatus.future);
    when(() => deepLink.passGotrueTokenResponse(token)).thenAnswer((_) async {
      onDeepLink(DeepLinkResult(state: DeepLinkState.loading));
      onDeepLink(
        DeepLinkResult(
          state: DeepLinkState.finish,
          result: FlowyResult.success(profile),
        ),
      );
      sessionStarted.complete();
      await sessionReady.future;
      completion.complete(FlowyResult.success(profile));
    });
    final states = <SignInState>[];
    final subscription = bloc.stream.listen(states.add);
    final finished = bloc.stream.firstWhere((s) => s.successOrFail != null);
    bloc.add(
      const SignInEvent.signInWithPasscode(
        email: phone,
        passcode: '123456',
      ),
    );
    await sessionStarted.future;
    verify(() => password.checkPasswordStatus(phone: phone)).called(1);
    await Future<void>.delayed(Duration.zero);
    expect(states.where((s) => s.successOrFail?.isSuccess == true), isEmpty);
    expect(bloc.state.isSubmitting, isTrue);
    passwordStatus.complete(FlowyResult.success(false));
    await Future<void>.delayed(Duration.zero);
    expect(states.where((s) => s.successOrFail?.isSuccess == true), isEmpty);
    sessionReady.complete();
    final state = await finished;
    await Future<void>.delayed(Duration.zero);
    expect(state.passwordIsSet, isFalse);
    expect(state.accessToken, 'test-token');
    expect(state.email, phone);
    expect(
      states.where((s) => s.successOrFail?.isSuccess == true),
      hasLength(1),
    );
    verifyNever(() => auth.getUser());
    await subscription.cancel();
  });

  test('failed session initialization never publishes login success', () async {
    final token = GotrueTokenResponsePB(accessToken: 'test-token');
    when(() => auth.signInWithPasscode(email: phone, passcode: '123456'))
        .thenAnswer((_) async => FlowyResult.success(token));
    when(() => deepLink.passGotrueTokenResponse(token)).thenAnswer((_) async {
      completion
          .complete(FlowyResult.failure(FlowyError(msg: 'session failed')));
    });
    final finished = bloc.stream.firstWhere((s) => s.successOrFail != null);
    bloc.add(
      const SignInEvent.signInWithPasscode(
        email: phone,
        passcode: '123456',
      ),
    );
    final state = await finished;
    expect(state.successOrFail?.isFailure, isTrue);
    expect(state.isSubmitting, isFalse);
    verifyNever(() => auth.getUser());
  });

  test('session exception releases completion and restores deep link updates',
      () async {
    final token = GotrueTokenResponsePB(accessToken: 'test-token');
    when(() => auth.signInWithPasscode(email: phone, passcode: '123456'))
        .thenAnswer((_) async => FlowyResult.success(token));
    when(() => deepLink.passGotrueTokenResponse(token))
        .thenThrow(StateError('session initialization failed'));
    final failed = bloc.stream.firstWhere((s) => s.successOrFail != null);
    bloc.add(
      const SignInEvent.signInWithPasscode(
        email: phone,
        passcode: '123456',
      ),
    );
    expect((await failed).successOrFail?.isFailure, isTrue);
    verify(() => deepLink.completer = null).called(1);
    final recovered =
        bloc.stream.firstWhere((s) => s.successOrFail?.isSuccess == true);
    onDeepLink(
      DeepLinkResult(
        state: DeepLinkState.finish,
        result: FlowyResult.success(UserProfilePB(phone: phone)),
      ),
    );
    expect((await recovered).isSubmitting, isFalse);
  });

  testWidgets(
      'Android verification page leaves success navigation to its owner',
      (tester) async {
    final token = GotrueTokenResponsePB(accessToken: 'test-token');
    when(() => auth.signInWithPasscode(email: phone, passcode: '123456'))
        .thenAnswer((_) async => FlowyResult.success(token));
    when(() => deepLink.passGotrueTokenResponse(token)).thenAnswer((_) async {
      completion.complete(FlowyResult.success(UserProfilePB(phone: phone)));
    });
    when(() => password.sendOtp(phone: phone))
        .thenAnswer((_) async => FlowyResult.success(true));
    await tester.pumpWidget(passwordPage());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(OutlinedButton));
    await tester.runAsync(() async => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(6));
    for (var i = 0; i < 6; i++) {
      await tester.enterText(fields.at(i), '${i + 1}');
    }
    await tester.tap(find.text('下一步'));
    await tester.runAsync(() async => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(bloc.state.successOrFail?.isSuccess, isTrue);
    expect(find.text('正在进入…'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
    expect(
      button.style?.backgroundColor?.resolve({WidgetState.disabled}),
      Theme.of(tester.element(find.byType(ElevatedButton))).colorScheme.primary,
    );
    expect(find.byType(ContinueWithMagicLinkOrPasscodePage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  for (final hasPassword in [true, false]) {
    testWidgets('Android keeps its running session, hasPassword=$hasPassword',
        (tester) async {
      final router = _AuthRouter();
      getIt.registerSingleton<AuthRouter>(router);
      final navigation = Completer<void>();
      when(() => router.goHomeScreen(any(), any()))
          .thenAnswer((_) => navigation.future);
      final token = GotrueTokenResponsePB(accessToken: 'test-token');
      final profile = UserProfilePB(phone: phone);
      when(() => auth.signInWithPasscode(email: phone, passcode: '123456'))
          .thenAnswer((_) async => FlowyResult.success(token));
      when(() => password.checkPasswordStatus(phone: phone))
          .thenAnswer((_) async => FlowyResult.success(hasPassword));
      when(() => deepLink.passGotrueTokenResponse(token)).thenAnswer((_) async {
        completion.complete(FlowyResult.success(profile));
      });
      final finished = bloc.stream.firstWhere((s) => s.successOrFail != null);
      await tester.pumpWidget(passwordPage(home: const MobileSignInScreen()));
      await tester.pumpAndSettle();
      bloc.add(
        const SignInEvent.signInWithPasscode(
          email: phone,
          passcode: '123456',
        ),
      );
      await tester.runAsync(() => finished);
      await tester.pumpAndSettle();
      if (hasPassword) {
        verify(() => router.goHomeScreen(any(), profile)).called(1);
      } else {
        expect(find.byType(SetPasswordPage), findsOneWidget);
        verifyNever(() => router.goHomeScreen(any(), any()));
        Navigator.of(tester.element(find.byType(SetPasswordPage))).pop();
        await tester.pumpAndSettle();
        expect(bloc.state.successOrFail, isNull);
      }
      expect(getIt<AppFlowyCloudDeepLink>(), same(deepLink));
      navigation.complete();
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    });
  }
}

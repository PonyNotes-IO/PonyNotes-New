import 'dart:async';

import 'package:appflowy/startup/android_privacy_consent.dart';
import 'package:appflowy/startup/android_privacy_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <String>[];
  final privacyCalls = <MethodCall>[];
  bool persisted = false;
  bool failWrite = false;
  Completer<void>? pendingWrite;

  setUp(() {
    calls.clear();
    privacyCalls.clear();
    persisted = false;
    failWrite = false;
    pendingWrite = null;
    AndroidPrivacyConsent.acceptedThisLaunch = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      AndroidPrivacyConsent.channel,
      (call) async {
        calls.add(call.method);
        privacyCalls.add(call);
        switch (call.method) {
          case 'hasAccepted':
            return persisted;
          case 'accept':
            if (failWrite) {
              throw PlatformException(code: 'CONSENT_WRITE_FAILED');
            }
            await pendingWrite?.future;
            persisted = true;
            return null;
          case 'initializePlugins':
            if (!persisted) throw PlatformException(code: 'CONSENT_REQUIRED');
            return null;
          case 'setReminderRestoreEnabled':
          case 'setAssociationFlowEnabled':
            return null;
          default:
            throw MissingPluginException(call.method);
        }
      },
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') calls.add('exit');
        return null;
      },
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      AndroidPrivacyConsent.channel,
      null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
    AndroidPrivacyConsent.acceptedThisLaunch = false;
  });

  Future<void> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    unawaited(() async {
      if (await AndroidPrivacyConsent.ensureAccepted()) {
        await AndroidPrivacyConsent.initializePlugins();
        calls.add('businessStartup');
      }
    }());
    await tester.pumpAndSettle();
  }

  testWidgets('blocks startup and outside taps until consent is persisted',
      (tester) async {
    pendingWrite = Completer<void>();
    await start(tester);
    expect(find.byType(AndroidPrivacyDialog), findsOneWidget);
    expect(calls, ['hasAccepted']);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(find.byType(AndroidPrivacyDialog), findsOneWidget);
    await tester.tap(find.text('同意'));
    await tester.pumpAndSettle();
    expect(calls, ['hasAccepted', 'accept']);
    pendingWrite!.complete();
    await tester.pumpAndSettle();
    expect(
      calls,
      ['hasAccepted', 'accept', 'initializePlugins', 'businessStartup'],
    );
    expect(AndroidPrivacyConsent.acceptedThisLaunch, isTrue);
  });

  testWidgets(
      'declining exits without registering plugins or starting business',
      (tester) async {
    await start(tester);
    await tester.tap(find.text('不同意'));
    await tester.pumpAndSettle();
    expect(calls, ['hasAccepted', 'exit']);
    expect(persisted, isFalse);
  });

  testWidgets('Android back exits without consent', (tester) async {
    await start(tester);
    await binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(calls, ['hasAccepted', 'exit']);
    expect(persisted, isFalse);
  });

  testWidgets('failed persistence stays blocked and allows retry',
      (tester) async {
    failWrite = true;
    await start(tester);
    await tester.tap(find.text('同意'));
    await tester.pumpAndSettle();
    expect(calls, ['hasAccepted', 'accept']);
    expect(find.byType(AndroidPrivacyDialog), findsOneWidget);
    expect(AndroidPrivacyConsent.acceptedThisLaunch, isFalse);
    failWrite = false;
    await tester.tap(find.text('同意'));
    await tester.pumpAndSettle();
    expect(calls, [
      'hasAccepted',
      'accept',
      'accept',
      'initializePlugins',
      'businessStartup',
    ]);
  });

  testWidgets('existing consent continues without another dialog',
      (tester) async {
    persisted = true;
    await start(tester);
    expect(find.byType(AndroidPrivacyDialog), findsNothing);
    expect(calls, ['hasAccepted', 'initializePlugins', 'businessStartup']);
    expect(AndroidPrivacyConsent.acceptedThisLaunch, isFalse);
  });

  test('forwards Android component gating arguments', () async {
    await AndroidPrivacyConsent.setReminderRestoreEnabled(true);
    await AndroidPrivacyConsent.setAssociationFlowEnabled(
      'douyinLogin',
      true,
    );

    expect(calls, [
      'setReminderRestoreEnabled',
      'setAssociationFlowEnabled',
    ]);
    expect(privacyCalls[0].arguments, {'enabled': true});
    expect(privacyCalls[1].arguments, {
      'flow': 'douyinLogin',
      'enabled': true,
    });
  });

  for (final size in [
    const Size(360, 640),
    const Size(390, 844),
    const Size(1280, 800),
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets('dialog fits $size in $brightness', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        binding.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(
          binding.platformDispatcher.clearPlatformBrightnessTestValue,
        );
        await tester.pumpWidget(AndroidPrivacyApp(onComplete: (_) {}));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final dialog = tester.getRect(find.byType(AlertDialog));
        expect(dialog.left, greaterThanOrEqualTo(0));
        expect(dialog.right, lessThanOrEqualTo(size.width));
        expect(dialog.top, greaterThanOrEqualTo(0));
        expect(dialog.bottom, lessThanOrEqualTo(size.height));
        expect(find.text(androidPrivacyPolicy), findsOneWidget);
        await tester.tap(find.text('不同意'));
        await tester.pumpAndSettle();
      });
    }
  }
}

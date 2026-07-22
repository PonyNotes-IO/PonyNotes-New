import 'package:appflowy/startup/tasks/windows.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(windowsSurfaceChannelName);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('synchronizes the Flutter surface through the native channel', () async {
    MethodCall? receivedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      receivedCall = call;
      return {
        'clientWidth': 1280,
        'clientHeight': 720,
        'childWidth': 1280,
        'childHeight': 720,
      };
    });

    final synchronizer = WindowsSurfaceSynchronizer(
      channel: channel,
      isWindows: () => true,
    );

    final dimensions = await synchronizer.synchronize();

    expect(receivedCall?.method, 'synchronizeSurface');
    expect(
      dimensions,
      const WindowsSurfaceDimensions(
        clientWidth: 1280,
        clientHeight: 720,
        childWidth: 1280,
        childHeight: 720,
      ),
    );
  });

  test('does not call the native channel outside Windows', () async {
    var didCallNative = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      didCallNative = true;
      return null;
    });

    final synchronizer = WindowsSurfaceSynchronizer(
      channel: channel,
      isWindows: () => false,
    );

    expect(await synchronizer.synchronize(), isNull);
    expect(didCallNative, isFalse);
  });

  test('rejects an incomplete native surface response', () {
    expect(
      () => WindowsSurfaceDimensions.fromMap({
        'clientWidth': 1280,
        'clientHeight': 720,
        'childWidth': 1280,
      }),
      throwsStateError,
    );
  });
}

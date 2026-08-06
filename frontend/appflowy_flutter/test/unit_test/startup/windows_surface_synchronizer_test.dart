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

  test('keeps the native geometry events for diagnostics', () {
    final dimensions = WindowsSurfaceDimensions.fromMap({
      'clientWidth': 1778,
      'clientHeight': 1024,
      'childWidth': 1778,
      'childHeight': 1024,
      'events': ['WM_SIZE wparam=0 client=1778x1024 child=1778x1024'],
    });

    expect(dimensions.events, [
      'WM_SIZE wparam=0 client=1778x1024 child=1778x1024',
    ]);
  });

  test('tolerates a native response without geometry events', () {
    final dimensions = WindowsSurfaceDimensions.fromMap({
      'clientWidth': 1778,
      'clientHeight': 1024,
      'childWidth': 1778,
      'childHeight': 1024,
    });

    expect(dimensions.events, isEmpty);
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

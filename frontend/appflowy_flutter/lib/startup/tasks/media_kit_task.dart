import 'package:media_kit/media_kit.dart';

import '../startup.dart';

class InitMediaKitTask extends LaunchTask {
  const InitMediaKitTask();

  @override
  Future<void> initialize(LaunchContext context) async {
    await super.initialize(context);
    // Initialize media_kit for video/audio playback support
    MediaKit.ensureInitialized();
  }

  @override
  Future<void> dispose() async {
    await super.dispose();
  }
}


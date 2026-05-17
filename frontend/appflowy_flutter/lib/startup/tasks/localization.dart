import 'package:easy_localization/easy_localization.dart';

import '../../util/log_utils.dart';
import '../startup.dart';

class InitLocalizationTask extends LaunchTask {
  const InitLocalizationTask();

  @override
  Future<void> initialize(LaunchContext context) async {
    try {
      await EasyLocalization.ensureInitialized();
      EasyLocalization.logger.enableBuildModes = [];
    } catch (e) {
      LogUtils.error(e.runtimeType);
    }

  }
}

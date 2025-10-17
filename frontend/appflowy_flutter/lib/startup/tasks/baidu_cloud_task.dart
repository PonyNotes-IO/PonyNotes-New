import 'package:appflowy/plugins/file_library/services/baidu_cloud_config_service.dart';
import 'package:appflowy/startup/startup.dart';

/// 百度网盘配置加载任务
class BaiduCloudConfigTask extends LaunchTask {
  const BaiduCloudConfigTask();

  @override
  LaunchTaskType get type => LaunchTaskType.dataProcessing;

  @override
  Future<void> initialize(LaunchContext context) async {
    await super.initialize(context);
    await BaiduCloudConfigService.instance.loadConfig();
  }
}


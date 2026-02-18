import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/startup/startup.dart';

class ShareConstants {
  static const String testBaseWebDomain = 'https://www.xiaomabiji.com';
  static const String defaultBaseWebDomain = 'https://www.xiaomabiji.com';

  static String buildNamespaceUrl({
    required String nameSpace,
    bool withHttps = false,
  }) {
    final baseShareDomain =
        getIt<AppFlowyCloudSharedEnv>().appflowyCloudConfig.base_web_domain;
    String url = baseShareDomain.addSchemaIfNeeded();
    if (!withHttps) {
      url = url.replaceFirst('https://', '');
    }
    return '$url/$nameSpace';
  }

  /// Builds the public URL for a published page.
  static String buildPublishUrl({
    required String workspaceId,
    required String viewId,
  }) {
    final baseShareDomain =
        getIt<AppFlowyCloudSharedEnv>().appflowyCloudConfig.base_web_domain;
    final host = baseShareDomain.addSchemaIfNeeded();
    final queryParams = <String, String>{
      'viewId': viewId,
      'type': 'publish', // 添加类型参数，标识这是发布链接
    };
    // 只有当 workspaceId 不为空时才添加到查询参数中
    if (workspaceId.isNotEmpty) {
      queryParams['workspaceId'] = workspaceId;
    }
    final query = Uri(queryParameters: queryParams).query;
    return '$host/share?$query';
  }

  static String buildShareUrl({
    required String workspaceId,
    required String viewId,
    String? blockId,
    int? permissionId, // 新增：权限参数，1=查看，2=评论，3=编辑，4=全部权限
  }) {
    final baseShareDomain =
        getIt<AppFlowyCloudSharedEnv>().appflowyCloudConfig.base_web_domain;
    final host = baseShareDomain.addSchemaIfNeeded();

    final query = Uri(
      queryParameters: <String, String>{
        'viewId': viewId,
        'workspaceId': workspaceId,
        'type': 'share', // 添加类型参数，标识这是分享链接
        if (blockId != null && blockId.isNotEmpty) 'blockId': blockId,
        if (permissionId != null) 'permission': permissionId.toString(), // 添加权限参数
      },
    ).query;

    return '$host/share?$query';
  }
}

extension on String {
  String addSchemaIfNeeded() {
    final schema = Uri.parse(this).scheme;
    // if the schema is empty, add https schema by default
    if (schema.isEmpty) {
      return 'https://$this';
    }
    return this;
  }
}

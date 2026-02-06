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

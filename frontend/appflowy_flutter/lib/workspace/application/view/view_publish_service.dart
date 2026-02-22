import 'dart:convert';

import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/shared/af_user_profile_extension.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

/// 接收发布文档的结果
class ReceivePublishedResult {
  final bool success;
  final String receivedViewId;
  final bool isReadonly;
  final String? error;

  ReceivePublishedResult({
    required this.success,
    required this.receivedViewId,
    required this.isReadonly,
    this.error,
  });
}

/// 视图发布状态服务
/// 用于检查视图是否已发布，以及管理发布状态
class ViewPublishService {
  static final ViewPublishService _instance = ViewPublishService._internal();
  factory ViewPublishService() => _instance;
  ViewPublishService._internal();

  // 缓存已发布视图的ID列表，避免重复查询
  final Set<String> _publishedViewIds = <String>{};
  bool _isInitialized = false;

  /// 初始化服务，加载已发布的视图列表
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      final result = await FolderEventListPublishedViews().send();
      result.fold(
        (response) {
          _publishedViewIds.clear();
          for (final item in response.items) {
            _publishedViewIds.add(item.info.viewId);
          }
          _isInitialized = true;
          Log.info('ViewPublishService initialized with ${_publishedViewIds.length} published views');
        },
        (error) {
          Log.error('Failed to initialize ViewPublishService: $error');
          _isInitialized = true; // 即使失败也标记为已初始化，避免重复尝试
        },
      );
    } catch (e) {
      Log.error('ViewPublishService initialization error: $e');
      _isInitialized = true;
    }
  }

  /// 检查视图是否已发布
  bool isViewPublished(String viewId) {
    return _publishedViewIds.contains(viewId);
  }

  /// 检查视图是否已发布（异步方式，更准确）
  Future<bool> isViewPublishedAsync(ViewPB view) async {
    try {
      final result = await ViewBackendService.getPublishInfo(view);
      return result.isSuccess;
    } catch (e) {
      Log.error('Failed to check publish status for view ${view.id}: $e');
      return false;
    }
  }

  /// 过滤掉已发布的视图
  List<ViewPB> filterOutPublishedViews(List<ViewPB> views) {
    return views.where((view) => !isViewPublished(view.id)).toList();
  }

  /// 只保留已发布的视图
  List<ViewPB> filterOnlyPublishedViews(List<ViewPB> views) {
    return views.where((view) => isViewPublished(view.id)).toList();
  }

  /// 标记视图为已发布
  void markViewAsPublished(String viewId) {
    _publishedViewIds.add(viewId);
  }

  /// 标记视图为未发布
  void markViewAsUnpublished(String viewId) {
    _publishedViewIds.remove(viewId);
  }

  /// 刷新已发布视图列表
  Future<void> refreshPublishedViews() async {
    _isInitialized = false;
    await initialize();
  }

  /// 获取已发布视图ID列表
  Set<String> get publishedViewIds => Set.from(_publishedViewIds);

  /// 清空缓存
  void clearCache() {
    _publishedViewIds.clear();
    _isInitialized = false;
  }

  /// 接收其他用户发布的文档（复制到当前用户工作区）
  /// [publishedViewId] 原始发布文档的 view_id
  /// [workspaceId] 当前用户的工作区 ID
  static Future<ReceivePublishedResult> receivePublishedCollab({
    required String publishedViewId,
    required String workspaceId,
  }) async {
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;

      if (baseUrl.isEmpty) {
        return ReceivePublishedResult(
          success: false,
          receivedViewId: publishedViewId,
          isReadonly: true,
          error: 'Base URL 为空',
        );
      }

      final uri = Uri.parse(baseUrl).replace(
        path: '/api/workspace/published/receive',
      );

      final authToken = await _getAuthToken();
      if (authToken == null || authToken.isEmpty) {
        return ReceivePublishedResult(
          success: false,
          receivedViewId: publishedViewId,
          isReadonly: true,
          error: 'Auth token 为空',
        );
      }

      final destViewId = const Uuid().v4();

      final requestBody = jsonEncode({
        'published_view_id': publishedViewId,
        'dest_workspace_id': workspaceId,
        'dest_view_id': destViewId,
      });

      Log.info('[ReceivePublish] 调用 receive API: publishedViewId=$publishedViewId, destViewId=$destViewId');

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: requestBody,
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('请求超时');
        },
      );

      Log.info('[ReceivePublish] 响应: HTTP ${response.statusCode}');

      if (response.body.isEmpty) {
        Log.error('[ReceivePublish] 服务器返回空响应体, statusCode=${response.statusCode}');
        return ReceivePublishedResult(
          success: false,
          receivedViewId: publishedViewId,
          isReadonly: true,
          error: '服务器返回空响应 (HTTP ${response.statusCode})',
        );
      }

      final responseBody = jsonDecode(response.body);

      if (response.statusCode == 200) {
        if (responseBody is Map<String, dynamic>) {
          final data = responseBody['data'];
          if (data is Map<String, dynamic>) {
            final viewId = data['view_id'] as String?;
            final isReadonly = data['is_readonly'] as bool? ?? true;
            return ReceivePublishedResult(
              success: true,
              receivedViewId: viewId ?? destViewId,
              isReadonly: isReadonly,
            );
          }
        }
        return ReceivePublishedResult(
          success: true,
          receivedViewId: destViewId,
          isReadonly: true,
        );
      } else if (response.statusCode == 400) {
        if (responseBody is Map<String, dynamic>) {
          final data = responseBody['data'];
          if (data is Map<String, dynamic>) {
            final viewId = data['view_id'] as String?;
            final isReadonly = data['is_readonly'] as bool? ?? true;
            return ReceivePublishedResult(
              success: true,
              receivedViewId: viewId ?? publishedViewId,
              isReadonly: isReadonly,
            );
          }
        }
        return ReceivePublishedResult(
          success: false,
          receivedViewId: publishedViewId,
          isReadonly: true,
          error: '已接收过但无法获取详情',
        );
      } else {
        final error = responseBody is Map<String, dynamic>
            ? (responseBody['error'] as String? ?? '未知错误')
            : '未知错误';
        return ReceivePublishedResult(
          success: false,
          receivedViewId: publishedViewId,
          isReadonly: true,
          error: error,
        );
      }
    } catch (e, stackTrace) {
      Log.error('[ReceivePublish] 调用 receive API 时出错: $e', stackTrace);
      return ReceivePublishedResult(
        success: false,
        receivedViewId: publishedViewId,
        isReadonly: true,
        error: e.toString(),
      );
    }
  }

  static Future<String?> _getAuthToken() async {
    try {
      final userResult = await UserBackendService.getCurrentUserProfile();
      return userResult.fold(
        (user) => user.authToken,
        (error) {
          Log.warn('[ReceivePublish] 获取用户信息失败: $error');
          return null;
        },
      );
    } catch (e) {
      Log.error('[ReceivePublish] 获取 token 时出错: $e');
      return null;
    }
  }
}

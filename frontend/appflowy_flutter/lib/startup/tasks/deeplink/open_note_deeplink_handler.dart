import 'dart:async';
import 'dart:convert';

import 'package:appflowy/shared/af_user_profile_extension.dart';
import 'package:appflowy/startup/tasks/deeplink/deeplink_handler.dart';
import 'package:appflowy/workspace/application/action_navigation/action_navigation_bloc.dart';
import 'package:appflowy/workspace/application/action_navigation/navigation_action.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/plugins/database/domain/database_view_service.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/workspace/presentation/panels/publish_notifier.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;

import '../../../env/cloud_env.dart';
import '../../../generated/locale_keys.g.dart';
import '../../../user/application/user_service.dart';
import '../../startup.dart';
import '../app_widget.dart';
import 'deeplink_loading_overlay.dart';

/// 处理打开笔记的深度链接
/// 支持的URI格式: ponynotes://note?viewId=xxx
/// 或者: ponynotes://open?viewId=xxx
class OpenNoteDeepLinkHandler extends DeepLinkHandler<void> {
  static const Duration _loadingDisplayDelay = Duration(milliseconds: 500);
  static const List<Duration> _databaseOpenRetryDelays = [
    Duration(milliseconds: 400),
    Duration(milliseconds: 800),
    Duration(milliseconds: 1500),
    Duration(seconds: 2),
    Duration(seconds: 3),
    Duration(seconds: 5),
  ];

  @override
  bool canHandle(Uri uri) {
    // 检查是否是打开笔记的深度链接（兼容 host 或 path 形式）
    final host = uri.host;
    final path = uri.path;

    // 原有格式: ponynotes://note?viewId=xxx 或 ponynotes://open?viewId=xxx
    final isNotePath =
        host == 'note' || host == 'open' || path == 'note' || path == 'open';

    // 新格式: https://www.xiaomabiji.com/share?viewId=xxx&type=publish|share
    final isSharePath = path == '/share' || path == 'share';
    final hasViewId = uri.queryParameters.containsKey('viewId');
    final linkType = uri.queryParameters['type'];
    final isPublishOrShareType = linkType == 'publish' || linkType == 'share';

    // 支持三种格式：
    // 1. ponynotes://note?viewId=xxx 或 ponynotes://open?viewId=xxx
    // 2. https://domain/share?viewId=xxx&type=publish
    // 3. https://domain/share?viewId=xxx&type=share
    return (isNotePath && hasViewId) ||
        (isSharePath && hasViewId && isPublishOrShareType);
  }

  @override
  Future<FlowyResult<void, FlowyError>> handle({
    required Uri uri,
    required DeepLinkStateHandler onStateChange,
  }) async {
    onStateChange(this, DeepLinkState.loading);
    await DeepLinkLoadingOverlay.showWhenReady(message: '正在打开共享内容...');
    await Future.delayed(_loadingDisplayDelay);

    try {
      // 从URI中获取参数
      final viewId = uri.queryParameters['viewId'];
      final targetWorkspaceId = uri.queryParameters['workspaceId'];
      final linkType = uri.queryParameters['type'];
      final permissionParam = uri.queryParameters['permission'];
      final layoutParam = uri.queryParameters['layout'];
      final permissionId =
          permissionParam != null ? int.tryParse(permissionParam) ?? 1 : 1;
      // 解析视图布局类型：0=Document, 1=Grid, 2=Board, 3=Calendar
      final viewLayoutValue =
          layoutParam != null ? int.tryParse(layoutParam) ?? 0 : 0;

      if (viewId == null || viewId.isEmpty) {
        Log.error('[OpenNoteDeepLinkHandler] viewId参数为空');
        onStateChange(this, DeepLinkState.error);
        return FlowyResult.failure(
          FlowyError()
            ..msg = 'viewId参数不能为空'
            ..code = ErrorCode.InvalidParams,
        );
      }

      // workspaceId 仅作为后端识别上下文的参数，前端不再主动切换工作区，
      // 由 Rust 侧的 open_document / view 服务自行处理跨工作区打开逻辑。
      final workspaceId = targetWorkspaceId;

      // 如果是分享链接（type=share），尝试将当前用户添加到协作中，
      // 具体权限与视图可见性仍由后端控制。
      if (linkType == 'share' &&
          workspaceId != null &&
          workspaceId.isNotEmpty) {
        await _addUserToCollaboration(
          workspaceId: workspaceId,
          viewId: viewId,
          permissionId: permissionId,
        );
      }

      // 如果是发布链接（type=publish），调用 receive API 接收文档
      String effectiveViewId = viewId;
      bool isReadonly = false;

      if (linkType == 'publish' &&
          workspaceId != null &&
          workspaceId.isNotEmpty) {
        Log.info(
            '[OpenNoteDeepLinkHandler] 处理发布链接: viewId=$viewId, workspaceId=$workspaceId');

        // 获取当前用户的工作区ID（而不是使用链接中的发布者工作区ID）
        final currentWorkspaceId = await _getCurrentWorkspaceId();
        if (currentWorkspaceId == null || currentWorkspaceId.isEmpty) {
          Log.warn('[OpenNoteDeepLinkHandler] 无法获取当前用户工作区，使用链接中的workspaceId');
          // 如果获取失败，尝试使用链接中的workspaceId（这可能会导致问题）
        }

        // 调用 receive API 接收发布的文档，使用当前用户的工作区ID
        final receiveResult = await _receivePublishedCollab(
          publishedViewId: viewId,
          workspaceId: currentWorkspaceId ?? workspaceId,
        );

        if (receiveResult.$1) {
          effectiveViewId = receiveResult.$3;
          isReadonly = receiveResult.$4;
          Log.info(
              '[OpenNoteDeepLinkHandler] 接收发布文档成功: receivedViewId=$effectiveViewId, isReadonly=$isReadonly');
          // 刷新侧边栏
          PublishRefresh.ping();
        } else {
          Log.warn(
              '[OpenNoteDeepLinkHandler] 接收发布文档失败: ${receiveResult.$2}，尝试使用原viewId打开');
          // 即使接收失败也继续打开，使用原始viewId
          effectiveViewId = viewId;
          isReadonly = true;
        }
      }

      // 对于 layout 参数缺失（=0）的情况，从服务端查询正确布局
      // 无论 linkType 和 workspaceId 是否存在，只要 layout=0 就尝试查询
      int effectiveLayout = viewLayoutValue;
      String? resolvedWorkspaceId = workspaceId;
      if (effectiveLayout == 0) {
        Log.info('[OpenNoteDeepLinkHandler] layout 缺失或为0，从服务端查询');
        // 先尝试通过 received 列表获取（如果已加入协作）
        final serverLayout = await _getViewLayoutFromInviteApi(viewId);
        if (serverLayout != null && serverLayout > 0) {
          effectiveLayout = serverLayout;
          Log.info('[OpenNoteDeepLinkHandler] 从 received 记录获取到 layout=$effectiveLayout');
        } else {
          // 再尝试通过邀请模板接口获取（不需要先接受邀请）
          final shareInfo = await _getShareInfoFromTemplate(viewId);
          if (shareInfo != null) {
            final templateLayout = shareInfo['view_layout'];
            if (templateLayout is int && templateLayout > 0) {
              effectiveLayout = templateLayout;
              Log.info('[OpenNoteDeepLinkHandler] 从邀请模板获取到 layout=$effectiveLayout');
            }
            // 如果 URL 没有 workspaceId，从模板中获取 owner_workspace_id
            if (resolvedWorkspaceId == null || resolvedWorkspaceId.isEmpty) {
              final ownerWsId = shareInfo['owner_workspace_id'];
              if (ownerWsId is String && ownerWsId.isNotEmpty) {
                resolvedWorkspaceId = ownerWsId;
                Log.info('[OpenNoteDeepLinkHandler] 从邀请模板获取到 workspaceId=$resolvedWorkspaceId');
              }
            }
          }
        }
        // 如果通过模板获取到了 workspaceId，补充调用 _addUserToCollaboration
        if (resolvedWorkspaceId != null &&
            resolvedWorkspaceId.isNotEmpty &&
            (linkType == null || linkType == 'share') &&
            workspaceId == null) {
          // 之前没有调用过 _addUserToCollaboration（因为 workspaceId 或 linkType 缺失），现在补充调用
          Log.info('[OpenNoteDeepLinkHandler] 补充调用 _addUserToCollaboration，workspaceId=$resolvedWorkspaceId');
          await _addUserToCollaboration(
            workspaceId: resolvedWorkspaceId,
            viewId: viewId,
            permissionId: permissionId,
          );
        }
      }

      final isDatabaseView = effectiveLayout >= 1 && effectiveLayout <= 3;
      final viewName = await _getViewName(viewId, resolvedWorkspaceId);

      // For share links, save shared view metadata to local DB BEFORE opening
      // This ensures get_view_pb() and database handler can find the view
      if (resolvedWorkspaceId != null && resolvedWorkspaceId.isNotEmpty) {
        Log.info(
            '[OpenNoteDeepLinkHandler] 保存共享视图元数据到本地: viewId=$effectiveViewId, layout=$effectiveLayout, name=$viewName');
        final savePayload = SaveSharedViewMetaPB()
          ..viewId = effectiveViewId
          ..workspaceId = resolvedWorkspaceId
          ..viewName = viewName
          ..viewLayout = effectiveLayout
          ..permissionId = permissionId;
        await FolderEventSaveSharedViewMeta(savePayload).send();
        // Also trigger background sync for sidebar updates
        FolderEventGetSharedViews().send();
      }

      if (!isDatabaseView) {
        bool documentOpened = false;
        try {
          final docResult = await DocumentService().openDocument(
            documentId: effectiveViewId,
          );
          await docResult.fold(
            (_) async {
              documentOpened = true;
              await Future.delayed(const Duration(milliseconds: 300));
            },
            (error) async {
              Log.warn(
                '📝 [OpenNoteDeepLinkHandler] open_document 失败: ${error.msg}',
              );
              documentOpened = false;
            },
          );
        } catch (e, stackTrace) {
          Log.error(
              '[OpenNoteDeepLinkHandler] 调用 open_document 时异常: $e', stackTrace);
          documentOpened = false;
        }

        if (!documentOpened) {
          Log.warn('📝 [OpenNoteDeepLinkHandler] 文档打开失败，无法显示视图');
          onStateChange(this, DeepLinkState.error);
          return FlowyResult.failure(
            FlowyError()
              ..msg = '文档打开失败，无法显示笔记'
              ..code = ErrorCode.Internal,
          );
        }
      } else {
        Log.info(
          '[OpenNoteDeepLinkHandler] 数据库类视图(layout=$effectiveLayout)，开始预热数据库对象',
        );
        final databaseReady = await _prepareDatabaseViewForOpening(
          viewId: effectiveViewId,
          workspaceId: resolvedWorkspaceId,
          viewName: viewName,
          viewLayout: effectiveLayout,
          permissionId: permissionId,
          linkType: linkType,
        );
        if (!databaseReady.$1) {
          onStateChange(this, DeepLinkState.error);
          return FlowyResult.failure(
            FlowyError()
              ..msg = databaseReady.$2
              ..code = databaseReady.$3,
          );
        }
      }

      // 根据 layout 值映射到 ViewLayoutPB
      ViewLayoutPB viewLayoutPB;
      switch (effectiveLayout) {
        case 1:
          viewLayoutPB = ViewLayoutPB.Grid;
          break;
        case 2:
          viewLayoutPB = ViewLayoutPB.Board;
          break;
        case 3:
          viewLayoutPB = ViewLayoutPB.Calendar;
          break;
        default:
          viewLayoutPB = ViewLayoutPB.Document;
      }

      final minimalView = ViewPB()
        ..id = effectiveViewId
        ..name = viewName
        ..layout = viewLayoutPB
        ..isLocked = isReadonly;

      // 等待应用初始化完成后再打开视图
      // 使用WidgetsBinding确保在UI线程中执行
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          // 获取TabsBloc实例
          final navContext = AppGlobals.rootNavKey.currentState?.context;
          if (navContext == null) {
            Log.error('[OpenNoteDeepLinkHandler] 无法获取BuildContext，应用可能未完全初始化');
            // 如果应用未初始化，延迟一段时间后重试
            await Future.delayed(const Duration(seconds: 1));
            final retryContext = AppGlobals.rootNavKey.currentState?.context;
            if (retryContext == null) {
              Log.error('[OpenNoteDeepLinkHandler] 重试后仍无法获取BuildContext');
              return;
            }
            _openView(retryContext, minimalView);
          } else {
            _openView(navContext, minimalView);
          }
        } catch (e, stackTrace) {
          Log.error('[OpenNoteDeepLinkHandler] 打开视图时出错: $e', stackTrace);
        }
      });

      onStateChange(this, DeepLinkState.finish);
      return FlowyResult.success(null);
    } catch (e, stackTrace) {
      Log.error('[OpenNoteDeepLinkHandler] 处理深度链接时出错: $e', stackTrace);
      onStateChange(this, DeepLinkState.error);
      return FlowyResult.failure(
        FlowyError()
          ..msg = '处理深度链接时出错: $e'
          ..code = ErrorCode.Internal,
      );
    } finally {
      DeepLinkLoadingOverlay.hide();
    }
  }

  Future<(bool, String, ErrorCode)> _prepareDatabaseViewForOpening({
    required String viewId,
    required String? workspaceId,
    required String viewName,
    required int viewLayout,
    required int permissionId,
    required String? linkType,
  }) async {
    final dbService = DatabaseViewBackendService(viewId: viewId);
    FlowyError? lastError;

    for (var i = 0; i < _databaseOpenRetryDelays.length; i++) {
      final attempt = i + 1;
      try {
        if (linkType == 'share' &&
            workspaceId != null &&
            workspaceId.isNotEmpty) {
          final savePayload = SaveSharedViewMetaPB()
            ..viewId = viewId
            ..workspaceId = workspaceId
            ..viewName = viewName
            ..viewLayout = viewLayout
            ..permissionId = permissionId;
          await FolderEventSaveSharedViewMeta(savePayload).send();
        }

        final databaseIdResult = await dbService.getDatabaseId();
        final databaseId = databaseIdResult.fold(
          (id) => id,
          (error) {
            lastError = error;
            return null;
          },
        );

        if (databaseId == null || databaseId.isEmpty) {
          Log.warn(
            '[OpenNoteDeepLinkHandler] 第$attempt次解析 databaseId 失败: '
            '${lastError?.msg ?? 'databaseId 为空'}',
          );
        } else {
          Log.info(
            '[OpenNoteDeepLinkHandler] 第$attempt次解析 databaseId 成功: $databaseId',
          );

          final openResult = await dbService.openDatabase();
          final openSucceeded = openResult.fold(
            (_) => true,
            (error) {
              lastError = error;
              return false;
            },
          );

          if (openSucceeded) {
            Log.info(
              '[OpenNoteDeepLinkHandler] 第$attempt次数据库预热成功: viewId=$viewId',
            );
            return (true, '', ErrorCode.Internal);
          }

          Log.warn(
            '[OpenNoteDeepLinkHandler] 第$attempt次数据库预热失败: '
            '${lastError?.msg ?? lastError?.code.toString() ?? '未知错误'}',
          );
        }
      } catch (e, stackTrace) {
        Log.error(
          '[OpenNoteDeepLinkHandler] 第$attempt次数据库预热异常: $e',
          stackTrace,
        );
      }

      FolderEventGetSharedViews().send();
      await Future.delayed(_databaseOpenRetryDelays[i]);
    }

    final code = lastError?.code ?? ErrorCode.RecordNotFound;
    final message = lastError?.msg.isNotEmpty == true
        ? lastError!.msg
        : '数据库视图尚未完成同步，请稍后重试打开';
    Log.error(
      '[OpenNoteDeepLinkHandler] 数据库视图预热失败: viewId=$viewId, code=$code, msg=$message',
    );
    return (false, message, code);
  }

  /// 打开视图
  void _openView(BuildContext context, ViewPB view) {
    try {
      // 通过 ActionNavigationBloc 触发打开逻辑，避免直接依赖 TabsBloc
      final actionBloc = context.read<ActionNavigationBloc?>();

      if (actionBloc != null) {
        actionBloc.add(
          ActionNavigationEvent.performAction(
            action: NavigationAction(
              objectId: view.id,
              arguments: {
                ActionArgumentKeys.view: view,
              },
            ),
            showErrorToast: true,
          ),
        );
      } else {
        // 兜底：如果 ActionNavigationBloc 不存在，再尝试直接使用 TabsBloc
        final tabsBloc = context.read<TabsBloc>();
        tabsBloc.openPlugin(view);
      }
    } catch (e, stackTrace) {
      Log.error('📝 [OpenNoteDeepLinkHandler] 打开视图时出错: $e', stackTrace);
    }
  }

  /// 将当前用户添加到协作中（用于分享链接）
  /// permissionId: 权限ID，1=查看，2=评论，3=编辑，4=全部权限
  Future<void> _addUserToCollaboration({
    required String workspaceId,
    required String viewId,
    int permissionId = 1, // 默认只读权限
  }) async {
    try {
      // 获取当前用户信息
      final userResult = await UserBackendService.getCurrentUserProfile();
      final userProfile = userResult.fold(
        (user) => user,
        (error) {
          Log.warn('📝 [OpenNoteDeepLinkHandler] 获取用户信息失败: $error');
          return null;
        },
      );

      if (userProfile == null) {
        Log.warn('📝 [OpenNoteDeepLinkHandler] 用户信息为空，跳过添加协作');
        return;
      }

      // 获取 auth token
      final authToken = userProfile.authToken;
      if (authToken == null || authToken.isEmpty) {
        Log.warn('📝 [OpenNoteDeepLinkHandler] Auth token 为空，跳过添加协作');
        return;
      }

      // 获取用户ID
      final userId = _getUserId(authToken);
      if (userId == null || userId.isEmpty) {
        Log.warn('📝 [OpenNoteDeepLinkHandler] 用户ID为空，跳过添加协作');
        return;
      }
      // 获取 base URL
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;

      if (baseUrl.isEmpty) {
        Log.warn('📝 [OpenNoteDeepLinkHandler] Base URL 为空，跳过添加协作');
        return;
      }

      // 构建 API URL: /api/workspace/{workspace_id}/collab/{object_id}/members/{member_user_id}
      final uri = Uri.parse(baseUrl).replace(
        path: '/api/workspace/$workspaceId/collab/$viewId/members/$userId',
      );

      // 发送 POST 请求，传递 permission_id 参数（默认只读权限 = 1）
      // 这样后端会正确创建 af_collab_member 和 af_collab_member_invite 记录
      final response = await http
          .post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${_extractAccessToken(authToken)}',
        },
        body: jsonEncode({
          'permission_id': permissionId, // 使用分享链接中的权限参数
        }),
      )
          .timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('请求超时');
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Success 刷新共享列表处理
        Log.info('[OpenNoteDeepLinkHandler] 添加协作成功');
      } else if (response.statusCode == 409) {
        // 409 表示用户已经在协作中，这是正常情况，不需要报错
      } else {
        Log.warn(
            '[OpenNoteDeepLinkHandler] 添加协作失败: HTTP ${response.statusCode}');
      }
    } catch (e, stackTrace) {
      // 添加协作失败不应该阻止打开笔记，只记录错误
      Log.error(
        '[OpenNoteDeepLinkHandler] 添加用户到协作时出错: $e',
        stackTrace,
      );
    }
  }

  String? _extractAccessToken(String? rawToken) {
    if (rawToken == null || rawToken.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(rawToken);
      if (decoded is Map<String, dynamic>) {
        final accessToken = decoded['access_token'] as String?;
        if (accessToken != null && accessToken.isNotEmpty) {
          return accessToken;
        }
      }
    } catch (_) {
      // 非 JSON，直接使用原始 token
      return rawToken;
    }
    return null;
  }

  String? _getUserId(String? rawToken) {
    if (rawToken == null || rawToken.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(rawToken);
      if (decoded is Map<String, dynamic>) {
        final user = decoded['user'];
        if (user is Map<String, dynamic>) {
          return user['id'];
        } else {
          return null;
        }
      }
    } catch (_) {
      // 非 JSON，直接使用原始 token
      return rawToken;
    }
    return null;
  }

  /// 获取视图名称
  /// 优先从发布元数据获取，如果是协作分享链接则通过 ViewBackendService 获取
  Future<String> _getViewName(String viewId, String? workspaceId) async {
    // 首先尝试从发布元数据获取名称
    final publishName = await _getViewNameFromPublishInfo(viewId);

    // 如果获取到的是空字符串（说明是协作分享链接），或者获取到的是默认名称，尝试通过 ViewBackendService 获取
    final defaultName = LocaleKeys.menuAppHeader_defaultNewNotebookName.tr();
    if (publishName.isEmpty || publishName == defaultName) {
      if (workspaceId != null && workspaceId.isNotEmpty) {
        return _getCollabViewName(viewId, workspaceId);
      }
    }

    // 如果获取到了有效的名称，直接返回
    if (publishName.isNotEmpty) {
      return publishName;
    }

    // 否则返回默认名称
    return defaultName;
  }

  /// 从发布元数据获取视图名称
  /// 如果获取失败，则使用默认名称
  Future<String> _getViewNameFromPublishInfo(String viewId) async {
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;

      if (baseUrl.isEmpty) {
        Log.warn('[OpenNoteDeepLinkHandler] Base URL 为空，使用默认名称');
        return LocaleKeys.menuAppHeader_defaultNewNotebookName.tr();
      }

      // 构建 API URL: /api/workspace/v1/published-info/{view_id}
      // 这个 API 不需要登录认证，可以公开访问
      final uri = Uri.parse(baseUrl).replace(
        path: '/api/workspace/v1/published-info/$viewId',
      );

      final response = await http.get(uri).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('请求超时');
        },
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) {
          final data = body['data'];
          if (data is Map<String, dynamic>) {
            final metadata = data['metadata'];
            if (metadata is Map<String, dynamic>) {
              // metadata 结构: { "view": { "name": "笔记名称", ... } }
              final view = metadata['view'];
              if (view is Map<String, dynamic>) {
                final name = view['name'] as String?;
                if (name != null && name.isNotEmpty) {
                  Log.info('[OpenNoteDeepLinkHandler] 从发布元数据获取到标题: $name');
                  return name;
                }
              }
            }
          }
        }
      } else if (response.statusCode == 404) {
        // 404 表示笔记未发布（可能是纯协作分享链接），返回空字符串表示需要使用其他方式获取
        Log.info('[OpenNoteDeepLinkHandler] 笔记未发布，将尝试其他方式获取名称');
        return '';
      } else {
        Log.warn(
            '[OpenNoteDeepLinkHandler] 获取发布信息失败: HTTP ${response.statusCode}');
      }
    } catch (e, stackTrace) {
      Log.error(
        '[OpenNoteDeepLinkHandler] 获取发布信息时出错: $e',
        stackTrace,
      );
    }

    // 获取失败时使用空字符串，由调用方决定是否使用默认名称
    return '';
  }

  /// 通过 ViewBackendService 获取协作文档的名称
  /// 用于协作分享链接（非发布文档）的场景
  /// 优先从本地 Folder 获取，如果失败则从服务端邀请记录获取
  Future<String> _getCollabViewName(String viewId, String workspaceId) async {
    // 1. 先尝试从本地 Folder 获取
    try {
      Log.info(
          '[OpenNoteDeepLinkHandler] 尝试通过 ViewBackendService 获取协作文档名称: viewId=$viewId');
      final result = await ViewBackendService.getView(viewId);
      final localName = result.fold(
        (view) => view.name.isNotEmpty ? view.name : null,
        (error) => null,
      );
      if (localName != null) {
        Log.info('[OpenNoteDeepLinkHandler] 从本地 Folder 获取到标题: $localName');
        return localName;
      }
    } catch (e) {
      Log.warn('[OpenNoteDeepLinkHandler] 本地获取视图名称失败: $e');
    }

    // 2. 本地没有，从服务端 /api/collab/me/received 获取邀请记录中的名称
    try {
      final name = await _getViewNameFromInviteApi(viewId);
      if (name != null && name.isNotEmpty) {
        Log.info('[OpenNoteDeepLinkHandler] 从服务端邀请记录获取到标题: $name');
        return name;
      }
    } catch (e) {
      Log.warn('[OpenNoteDeepLinkHandler] 从服务端邀请记录获取名称失败: $e');
    }

    return LocaleKeys.menuAppHeader_defaultNewNotebookName.tr();
  }

  /// 从服务端邀请记录 API 获取文档名称
  Future<String?> _getViewNameFromInviteApi(String viewId) async {
    final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
    final baseUrl = cloudEnv.appflowyCloudConfig.base_url;
    if (baseUrl.isEmpty) return null;

    final rawToken = await _getAuthTokenFromUserService();
    final accessToken = _extractAccessToken(rawToken);
    if (accessToken == null || accessToken.isEmpty) return null;

    final uri = Uri.parse(baseUrl).replace(path: '/api/collab/me/received');
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) return null;

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;

    final data = decoded['data'];
    if (data is! List) return null;

    for (final item in data) {
      if (item is Map<String, dynamic>) {
        final oid = (item['oid'] ?? '').toString();
        if (oid == viewId) {
          final name = (item['name'] ?? '').toString();
          return name.isNotEmpty ? name : null;
        }
      }
    }
    return null;
  }

  /// 调用 receive_published_collab API 接收发布的文档
  /// 返回 (是否成功, 错误信息, 接收后的viewId, 是否只读)
  Future<(bool, String, String, bool)> _receivePublishedCollab({
    required String publishedViewId,
    required String workspaceId,
  }) async {
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;

      if (baseUrl.isEmpty) {
        Log.warn('[OpenNoteDeepLinkHandler] Base URL 为空');
        return (false, 'Base URL 为空', publishedViewId, true);
      }

      // 构建 API URL: /api/workspace/published/receive
      // 注意：后端 API 是在 /api/workspace scope 下定义的
      final uri = Uri.parse(baseUrl).replace(
        path: '/api/workspace/published/receive',
      );

      // 获取 auth token
      final rawToken = await _getAuthTokenFromUserService();
      final authToken = _extractAccessToken(rawToken);
      if (authToken == null || authToken.isEmpty) {
        Log.warn('[OpenNoteDeepLinkHandler] Auth token 为空');
        return (false, 'Auth token 为空', publishedViewId, true);
      }

      final destViewId = _generateUuid();

      final requestBody = jsonEncode({
        'published_view_id': publishedViewId,
        'dest_workspace_id': workspaceId,
        'dest_view_id': destViewId,
      });

      Log.info('[OpenNoteDeepLinkHandler] 调用 receive API: $uri');
      Log.info('[OpenNoteDeepLinkHandler] 请求参数: $requestBody');

      final response = await http
          .post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: requestBody,
      )
          .timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('请求超时');
        },
      );

      Log.info(
          '[OpenNoteDeepLinkHandler] receive API 响应: HTTP ${response.statusCode}');

      if (response.body.isEmpty) {
        Log.error('[OpenNoteDeepLinkHandler] 服务器返回空响应体');
        return (
          false,
          '服务器返回空响应 (HTTP ${response.statusCode})',
          publishedViewId,
          true
        );
      }

      final responseBody = jsonDecode(response.body);
      Log.info('[OpenNoteDeepLinkHandler] receive API 响应体: $responseBody');

      if (response.statusCode == 200) {
        if (responseBody is Map<String, dynamic>) {
          final data = responseBody['data'];
          if (data is Map<String, dynamic>) {
            final viewId = data['view_id'] as String?;
            final isReadonly = data['is_readonly'] as bool? ?? true;
            Log.info(
                '[OpenNoteDeepLinkHandler] 接收成功: viewId=$viewId, isReadonly=$isReadonly');
            return (true, '', viewId ?? destViewId, isReadonly);
          }
        }
        return (true, '', destViewId, true);
      } else if (response.statusCode == 400) {
        // 可能已接收过，解析响应获取已接收的 view_id
        if (responseBody is Map<String, dynamic>) {
          final data = responseBody['data'];
          if (data is Map<String, dynamic>) {
            final viewId = data['view_id'] as String?;
            final isReadonly = data['is_readonly'] as bool? ?? true;
            return (true, '已接收过', viewId ?? publishedViewId, isReadonly);
          }
        }
        return (false, '已接收过', publishedViewId, true);
      } else {
        final error = responseBody is Map<String, dynamic>
            ? (responseBody['error'] as String? ?? '未知错误')
            : '未知错误';
        Log.warn('[OpenNoteDeepLinkHandler] 接收失败: $error');
        return (false, error, publishedViewId, true);
      }
    } catch (e, stackTrace) {
      Log.error('[OpenNoteDeepLinkHandler] 调用 receive API 时出错: $e', stackTrace);
      return (false, e.toString(), publishedViewId, true);
    }
  }

  /// 通过 Rust FFI 获取当前用户的工作区ID
  Future<String?> _getCurrentWorkspaceId() async {
    try {
      final result = await FolderEventGetCurrentWorkspaceSetting().send();
      return result.fold(
        (ws) {
          Log.info('[OpenNoteDeepLinkHandler] 获取到当前工作区: ${ws.workspaceId}');
          return ws.workspaceId.isEmpty ? null : ws.workspaceId;
        },
        (e) {
          Log.error('[OpenNoteDeepLinkHandler] 获取当前工作区失败: $e');
          return null;
        },
      );
    } catch (e, stackTrace) {
      Log.error('[OpenNoteDeepLinkHandler] 获取工作区信息时出错: $e', stackTrace);
    }
    return null;
  }

  /// 从用户服务获取 auth token
  Future<String?> _getAuthTokenFromUserService() async {
    try {
      final userResult = await UserBackendService.getCurrentUserProfile();
      return userResult.fold(
        (user) => user.authToken,
        (error) {
          Log.warn('[OpenNoteDeepLinkHandler] 获取用户信息失败: $error');
          return null;
        },
      );
    } catch (e) {
      Log.error('[OpenNoteDeepLinkHandler] 获取 token 时出错: $e');
      return null;
    }
  }

  /// 从服务端邀请记录获取视图的布局类型
  /// 返回 null 表示获取失败，0=Document, 1=Grid, 2=Board, 3=Calendar
  Future<int?> _getViewLayoutFromInviteApi(String viewId) async {
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;
      if (baseUrl.isEmpty) return null;

      final rawToken = await _getAuthTokenFromUserService();
      final accessToken = _extractAccessToken(rawToken);
      if (accessToken == null || accessToken.isEmpty) return null;

      final uri = Uri.parse(baseUrl).replace(path: '/api/collab/me/received');
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;

      final data = decoded['data'];
      if (data is! List) return null;

      for (final item in data) {
        if (item is Map<String, dynamic>) {
          final oid = (item['oid'] ?? '').toString();
          if (oid == viewId) {
            final viewLayout = item['view_layout'];
            if (viewLayout is int) return viewLayout;
            if (viewLayout is String) return int.tryParse(viewLayout);
          }
        }
      }
    } catch (e) {
      Log.warn('[OpenNoteDeepLinkHandler] 获取视图布局失败: $e');
    }
    return null;
  }

  /// 从服务端邀请模板接口获取分享信息（view_layout, owner_workspace_id, name）
  /// 不需要用户先接受邀请，适用于 URL 缺少 workspaceId 的情况
  /// 返回 null 表示获取失败或无邀请模板
  Future<Map<String, dynamic>?> _getShareInfoFromTemplate(String viewId) async {
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;
      if (baseUrl.isEmpty) return null;

      final rawToken = await _getAuthTokenFromUserService();
      final accessToken = _extractAccessToken(rawToken);
      if (accessToken == null || accessToken.isEmpty) return null;

      final uri = Uri.parse(baseUrl).replace(
        path: '/api/collab/share-info',
        queryParameters: {'view_id': viewId},
      );
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        Log.info('[OpenNoteDeepLinkHandler] 邀请模板接口返回 ${response.statusCode}，可能无邀请模板');
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;

      final data = decoded['data'];
      if (data is Map<String, dynamic>) return data;
    } catch (e) {
      Log.warn('[OpenNoteDeepLinkHandler] 获取邀请模板信息失败: $e');
    }
    return null;
  }

  /// 生成 UUID v4
  String _generateUuid() {
    return const Uuid().v4();
  }
}

import 'dart:async';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/startup/tasks/app_widget.dart';
import 'package:appflowy/startup/tasks/deeplink/deeplink_handler.dart';
import 'package:appflowy/workspace/application/action_navigation/action_navigation_bloc.dart';
import 'package:appflowy/workspace/application/action_navigation/navigation_action.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pbenum.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// 处理打开笔记的深度链接
/// 支持的URI格式: ponynotes://note?viewId=xxx
/// 或者: ponynotes://open?viewId=xxx
class OpenNoteDeepLinkHandler extends DeepLinkHandler<void> {
  @override
  bool canHandle(Uri uri) {
    // 检查是否是打开笔记的深度链接（兼容 host 或 path 形式）
    final host = uri.host;
    final path = uri.path;
    final isNotePath =
        host == 'note' || host == 'open' || path == 'note' || path == 'open';
    final hasViewId = uri.queryParameters.containsKey('viewId');
    
    return isNotePath && hasViewId;
  }

  @override
  Future<FlowyResult<void, FlowyError>> handle({
    required Uri uri,
    required DeepLinkStateHandler onStateChange,
  }) async {
    Log.info('📝 [OpenNoteDeepLinkHandler] 处理打开笔记深度链接: ${uri.toString()}');
    
    onStateChange(this, DeepLinkState.loading);

    try {
      // 从URI中获取参数
      final viewId = uri.queryParameters['viewId'];
      final targetWorkspaceId = uri.queryParameters['workspaceId'];
      
      if (viewId == null || viewId.isEmpty) {
        Log.error('📝 [OpenNoteDeepLinkHandler] viewId参数为空');
        onStateChange(this, DeepLinkState.error);
        return FlowyResult.failure(
          FlowyError()
            ..msg = 'viewId参数不能为空'
            ..code = ErrorCode.InvalidParams,
        );
      }

      Log.info('📝 [OpenNoteDeepLinkHandler] 准备打开笔记, viewId: $viewId, workspaceId: ${targetWorkspaceId ?? "(current)"}');

      // 如果带了 workspaceId，先切换到指定工作区，再获取视图信息
      if (targetWorkspaceId != null && targetWorkspaceId.isNotEmpty) {
        final rootContext = AppGlobals.rootNavKey.currentState?.context;
        UserWorkspaceBloc? userWorkspaceBloc;
        if (rootContext != null) {
          try {
            userWorkspaceBloc = rootContext.read<UserWorkspaceBloc>();
          } catch (e, stackTrace) {
            Log.warn(
              '📝 [OpenNoteDeepLinkHandler] 获取 UserWorkspaceBloc 失败，跳过工作区切换',
              e,
              stackTrace,
            );
          }
        }

        if (userWorkspaceBloc != null) {
          final current = userWorkspaceBloc.state.currentWorkspace?.workspaceId;
          if (current != targetWorkspaceId) {
            Log.info('📝 [OpenNoteDeepLinkHandler] 切换工作区到: $targetWorkspaceId');
            final workspaceType =
                userWorkspaceBloc.state.currentWorkspace?.workspaceType ??
                    WorkspaceTypePB.LocalW;
            userWorkspaceBloc.add(
              UserWorkspaceEvent.openWorkspace(
                workspaceId: targetWorkspaceId,
                workspaceType: workspaceType,
              ),
            );
            var retries = 10;
            while (retries-- > 0 &&
                userWorkspaceBloc.state.currentWorkspace?.workspaceId !=
                    targetWorkspaceId) {
              await Future.delayed(const Duration(milliseconds: 200));
            }
            Log.info('📝 [OpenNoteDeepLinkHandler] 工作区切换结果: ${userWorkspaceBloc.state.currentWorkspace?.workspaceId}');
          }
        } else {
          Log.warn(
            '📝 [OpenNoteDeepLinkHandler] 找不到 UserWorkspaceBloc，跳过工作区切换',
          );
        }
      }

      // 获取视图信息（在目标工作区环境下）
      final viewResult = await ViewBackendService.getView(viewId);
      
      return await viewResult.fold(
        (view) async {
          Log.info('📝 [OpenNoteDeepLinkHandler] 成功获取视图: ${view.name}');
          
          // 等待应用初始化完成后再打开视图
          // 使用WidgetsBinding确保在UI线程中执行
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            try {
              // 获取TabsBloc实例
              final navContext = AppGlobals.rootNavKey.currentState?.context;
              if (navContext == null) {
                Log.error('📝 [OpenNoteDeepLinkHandler] 无法获取BuildContext，应用可能未完全初始化');
                // 如果应用未初始化，延迟一段时间后重试
                await Future.delayed(const Duration(seconds: 1));
                final retryContext = AppGlobals.rootNavKey.currentState?.context;
                if (retryContext == null) {
                  Log.error('📝 [OpenNoteDeepLinkHandler] 重试后仍无法获取BuildContext');
                  return;
                }
                _openView(retryContext, view);
              } else {
                _openView(navContext, view);
              }
            } catch (e, stackTrace) {
              Log.error('📝 [OpenNoteDeepLinkHandler] 打开视图时出错: $e', stackTrace);
            }
          });
          
          onStateChange(this, DeepLinkState.finish);
          return FlowyResult.success(null);
        },
        (error) async {
          Log.error('📝 [OpenNoteDeepLinkHandler] 获取视图失败: ${error.msg}');
          onStateChange(this, DeepLinkState.error);
          return FlowyResult.failure(error);
        },
      );
    } catch (e, stackTrace) {
      Log.error('📝 [OpenNoteDeepLinkHandler] 处理深度链接时出错: $e', stackTrace);
      onStateChange(this, DeepLinkState.error);
      return FlowyResult.failure(
        FlowyError()
          ..msg = '处理深度链接时出错: $e'
          ..code = ErrorCode.Internal,
      );
    }
  }

  /// 打开视图
  void _openView(BuildContext context, ViewPB view) {
    try {
      Log.info('📝 [OpenNoteDeepLinkHandler] 开始打开视图: ${view.name} (${view.id})');

      // 通过 ActionNavigationBloc 触发打开逻辑，避免直接依赖 TabsBloc
      final actionBloc =
          context.read<ActionNavigationBloc?>();

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
        Log.info('📝 [OpenNoteDeepLinkHandler] 已通过 ActionNavigationBloc 发送打开请求');
      } else {
        // 兜底：如果 ActionNavigationBloc 不存在，再尝试直接使用 TabsBloc
        final tabsBloc = context.read<TabsBloc>();
        tabsBloc.openPlugin(view);
        Log.info('📝 [OpenNoteDeepLinkHandler] 通过 TabsBloc 打开视图');
      }
    } catch (e, stackTrace) {
      Log.error('📝 [OpenNoteDeepLinkHandler] 打开视图时出错: $e', stackTrace);
    }
  }
}


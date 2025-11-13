import 'dart:async';

import 'package:appflowy/startup/tasks/deeplink/deeplink_handler.dart';
import 'package:appflowy/startup/tasks/app_widget.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// 处理打开笔记的深度链接
/// 支持的URI格式: ponynotes://note?viewId=xxx
/// 或者: ponynotes://open?viewId=xxx
class OpenNoteDeepLinkHandler extends DeepLinkHandler<void> {
  @override
  bool canHandle(Uri uri) {
    // 检查是否是打开笔记的深度链接
    final path = uri.path;
    final isNotePath = path == 'note' || path == 'open' || path.isEmpty;
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
      // 从URI中获取viewId参数
      final viewId = uri.queryParameters['viewId'];
      
      if (viewId == null || viewId.isEmpty) {
        Log.error('📝 [OpenNoteDeepLinkHandler] viewId参数为空');
        onStateChange(this, DeepLinkState.error);
        return FlowyResult.failure(
          FlowyError()
            ..msg = 'viewId参数不能为空'
            ..code = ErrorCode.InvalidParams,
        );
      }

      Log.info('📝 [OpenNoteDeepLinkHandler] 准备打开笔记, viewId: $viewId');

      // 获取视图信息
      final viewResult = await ViewBackendService.getView(viewId);
      
      return await viewResult.fold(
        (view) async {
          Log.info('📝 [OpenNoteDeepLinkHandler] 成功获取视图: ${view.name}');
          
          // 等待应用初始化完成后再打开视图
          // 使用WidgetsBinding确保在UI线程中执行
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            try {
              // 获取TabsBloc实例
              final context = AppGlobals.rootNavKey.currentState?.context;
              if (context == null) {
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
                _openView(context, view);
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
      
      // 获取TabsBloc并打开视图
      final tabsBloc = context.read<TabsBloc>();
      
      // 使用ViewPB的plugin方法创建Plugin并打开视图
      tabsBloc.openPlugin(view);
      
      Log.info('📝 [OpenNoteDeepLinkHandler] 成功发送打开视图事件');
    } catch (e, stackTrace) {
      Log.error('📝 [OpenNoteDeepLinkHandler] 打开视图时出错: $e', stackTrace);
    }
  }
}


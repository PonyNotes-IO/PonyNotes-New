// Web-only implementation using `dart:html`.
import 'dart:convert';
import 'dart:html' as html;

import 'package:appflowy_backend/log.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/app_widget.dart';

/// Process pending invite stored in localStorage (web only).
Future<void> processPendingInvite() async {
  try {
    final pendingInviteCode = html.window.localStorage['pending_invite_code'];
    final pendingWorkspaceId = html.window.localStorage['pending_workspace_id'];
    final pendingInviteAction = html.window.localStorage['pending_invite_action'];

    if (pendingInviteCode != null &&
        pendingWorkspaceId != null &&
        pendingInviteAction == 'accept') {
      Log.info('🔵 [PendingInvite] Found pending invite: $pendingInviteCode for workspace $pendingWorkspaceId');

      // Clear pending state to avoid duplicate processing
      html.window.localStorage.remove('pending_invite_code');
      html.window.localStorage.remove('pending_workspace_id');
      html.window.localStorage.remove('pending_invite_action');

      final sharedEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = sharedEnv.appflowyCloudConfig.base_url;
      final url = '$baseUrl/api/workspace/$pendingWorkspaceId/invite-code/join';

      try {
        final response = await html.HttpRequest.request(
          url,
          method: 'POST',
          requestHeaders: {
            'Content-Type': 'application/json',
          },
          sendData: jsonEncode({'code': pendingInviteCode}),
        );

        if (response.status == 200) {
          Log.info('🔵 [PendingInvite] Successfully joined workspace via pending invite');
          final context = AppGlobals.rootNavKey.currentState?.context;
          if (context != null && context.mounted) {
            showToastNotification(
              message: '成功加入工作空间',
              type: ToastificationType.success,
            );
          }
        } else {
          Log.error('🔵 [PendingInvite] Failed to join workspace, HTTP status: ${response.status}');
          final context = AppGlobals.rootNavKey.currentState?.context;
          if (context != null && context.mounted) {
            showToastNotification(
              message: '加入工作空间失败，请稍后重试',
              type: ToastificationType.error,
            );
          }
        }
      } catch (httpError, stackTrace) {
        Log.error('🔵 [PendingInvite] HTTP request failed: $httpError', stackTrace);
        final context = AppGlobals.rootNavKey.currentState?.context;
        if (context != null && context.mounted) {
          showToastNotification(
            message: '加入工作空间失败，请稍后重试',
            type: ToastificationType.error,
          );
        }
      }
    }
  } catch (e, stackTrace) {
    Log.error('🔵 [PendingInvite] Error processing pending invite: $e', stackTrace);
  }
}



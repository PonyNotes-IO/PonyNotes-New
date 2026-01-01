// Web-only implementation using `dart:html`.
import 'dart:convert';
import 'dart:html' as html;

import 'package:appflowy_backend/log.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/app_widget.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';

/// Process pending invite stored in localStorage (web only).
Future<void> processPendingInvite() async {
  try {
    // First check if there is already a pending invite in localStorage
    String? pendingInviteCode = html.window.localStorage['pending_invite_code'];
    String? pendingWorkspaceId = html.window.localStorage['pending_workspace_id'];
    String? pendingInviteAction = html.window.localStorage['pending_invite_action'];

    // If not present in localStorage, try to parse from current URL
    // Format supported: /app/invited/{code}?ws={workspaceId}
    if ((pendingInviteCode == null || pendingWorkspaceId == null) &&
        html.window.location != null) {
      try {
        final loc = html.window.location;
        final path = loc.pathname ?? '';
        if (path.startsWith('/app/invited')) {
          // extract code from path segment
          final parts = path.split('/');
          if (parts.length >= 3) {
            final code = parts.lastWhere((p) => p.isNotEmpty, orElse: () => '');
            if (code.isNotEmpty) {
              pendingInviteCode ??= Uri.decodeComponent(code);
            }
          }
        }

        // try to parse workspace id from query param 'ws'
        final search = loc.search ?? '';
        if (search.isNotEmpty) {
          final params = Uri.splitQueryString(search.startsWith('?') ? search.substring(1) : search);
          final ws = params['ws'];
          if (ws != null && ws.isNotEmpty) {
            pendingWorkspaceId ??= Uri.decodeComponent(ws);
          }
        }

        // if we found a code but not workspace id, leave it to existing localStorage flow
        if (pendingInviteCode != null && pendingWorkspaceId != null) {
          pendingInviteAction ??= 'accept';
          // persist to localStorage so other parts can consume it consistently
          html.window.localStorage['pending_invite_code'] = pendingInviteCode;
          html.window.localStorage['pending_workspace_id'] = pendingWorkspaceId;
          html.window.localStorage['pending_invite_action'] = pendingInviteAction!;
        }
      } catch (e, st) {
        Log.error('Failed to parse invite from URL: $e\n$st');
      }
    }

    if (pendingInviteCode != null &&
        pendingWorkspaceId != null &&
        pendingInviteAction == 'accept') {
      Log.info('🔵 [PendingInvite] Found pending invite: $pendingInviteCode for workspace $pendingWorkspaceId');

      // Clear pending state to avoid duplicate processing
      html.window.localStorage.remove('pending_invite_code');
      html.window.localStorage.remove('pending_workspace_id');
      html.window.localStorage.remove('pending_invite_action');

      final sharedEnv = getIt.get<AppFlowyCloudSharedEnv>();
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
            Log.info('Context available; invite succeeded');
          }
          // Clear pending invite state after success
          html.window.localStorage.remove('pending_invite_code');
          html.window.localStorage.remove('pending_workspace_id');
          html.window.localStorage.remove('pending_invite_action');
        } else {
          Log.error('🔵 [PendingInvite] Failed to join workspace, HTTP status: ${response.status}');
          final context = AppGlobals.rootNavKey.currentState?.context;
          if (context != null && context.mounted) {
            Log.error('Context available; invite failed with status ${response.status}');
          }
        }
      } catch (httpError, stackTrace) {
        Log.error('🔵 [PendingInvite] HTTP request failed: $httpError', stackTrace);
        final context = AppGlobals.rootNavKey.currentState?.context;
        if (context != null && context.mounted) {
          Log.error('Context available; invite HTTP request failed: $httpError');
        }
      }
    }
  } catch (e, stackTrace) {
    Log.error('🔵 [PendingInvite] Error processing pending invite: $e', stackTrace);
  }
}



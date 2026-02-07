import 'dart:convert';

import 'package:appflowy/startup/tasks/deeplink/deeplink_handler.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:http/http.dart' as http;
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/startup/startup.dart' show getIt;
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/shared/settings/show_settings.dart' show showSettingsDialog;
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart' show WorkspaceTypePB;
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/clipboard_service.dart' show ClipboardService;
import 'package:appflowy/startup/tasks/app_widget.dart' show AppGlobals;
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart' show showToastNotification;
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart' show SettingsPage;
import 'package:appflowy/startup/tasks/appflowy_cloud_task.dart' show appflowyDeepLinkSchema;

/// Handles deep links like: appflowy://invite?code=...&ws=...
class AppflowyInviteDeepLinkHandler extends DeepLinkHandler<void> {
  static const inviteHost = 'invite';
  static const paramCode = 'code';
  static const paramWs = 'ws';

  @override
  bool canHandle(Uri uri) {
    // Check if the scheme is correct
    if (uri.scheme != appflowyDeepLinkSchema) {
      return false;
    }
    final hostMatch = uri.host == inviteHost;
    final pathMatch = uri.pathSegments.isNotEmpty && uri.pathSegments.first == inviteHost;
    final hasParams =
        uri.queryParameters.containsKey(paramCode) && uri.queryParameters.containsKey(paramWs);
    return (hostMatch || pathMatch) && hasParams;
  }

  @override
  Future<FlowyResult<void, FlowyError>> handle({
    required Uri uri,
    required DeepLinkStateHandler onStateChange,
  }) async {
    onStateChange(this, DeepLinkState.loading);
    try {
      final code = uri.queryParameters[paramCode];
      final ws = uri.queryParameters[paramWs];
      if (code == null || ws == null) {
        return FlowyResult.failure(FlowyError(msg: 'Missing code or ws'));
      }

      // Resolve base URL from DI
      final sharedEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = sharedEnv.appflowyCloudConfig.base_url;
      // backend exposes join-by-invite-code as /api/workspace/join-by-invite-code
      final url = Uri.parse('$baseUrl/api/workspace/join-by-invite-code');

      // Try to attach Authorization header if available
      final headers = <String, String>{'Content-Type': 'application/json'};
      try {
        final authService = getIt<AuthService>();
        final userRes = await authService.getUser();
        userRes.fold((userProfile) {
          final raw = userProfile.token;
          if (raw.isNotEmpty) {
            String? accessToken;
            try {
              final decoded = jsonDecode(raw);
              if (decoded is Map<String, dynamic>) {
                accessToken = decoded['access_token'] as String?;
              }
            } catch (_) {
              accessToken = raw;
            }
            if (accessToken != null && accessToken.isNotEmpty) {
              headers['Authorization'] = 'Bearer $accessToken';
            }
          }
        }, (err) {
          // ignore - no user available
        });
      } catch (_) {}

      final resp = await http
          .post(
            url,
            headers: headers,
            body: jsonEncode({'code': code}),
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        // try to extract returned workspace id
        String? joinedWorkspaceId;
        try {
          final decoded = jsonDecode(resp.body);
          if (decoded is Map) {
            joinedWorkspaceId = decoded['data']?['workspace_id'] ?? decoded['workspace_id'];
          }
        } catch (_) {}
        joinedWorkspaceId ??= ws;

        Log.info('[InviteDeepLink] Joined workspace $joinedWorkspaceId via invite $code');
        onStateChange(this, DeepLinkState.finish);

        final context = AppGlobals.rootNavKey.currentState?.context;
        if (context != null) {
          // show confirmation dialog
          await showDialog(
            context: context,
            builder: (dialogCtx) {
              return AlertDialog(
                title: const Text('已加入工作区'),
                content: Text('已成功加入工作区 $joinedWorkspaceId，是否前往查看？'),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(dialogCtx).pop();
                    },
                    child: const Text('稍后'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(dialogCtx).pop();
                      try {
                        context.read<UserWorkspaceBloc>().add(
                          UserWorkspaceEvent.openWorkspace(
                            workspaceId: joinedWorkspaceId!,
                            workspaceType: WorkspaceTypePB.ServerW,
                          ),
                        );
                      } catch (e) {
                        // ignore
                      }
                    },
                    child: const Text('前往查看'),
                  ),
                ],
              );
            },
          );
        }

        return FlowyResult.success(null);
      } else {
        final body = resp.body.isNotEmpty ? resp.body : '';
        Log.error('[InviteDeepLink] join workspace failed: status ${resp.statusCode}, body: $body');
        onStateChange(this, DeepLinkState.error);

        final context = AppGlobals.rootNavKey.currentState?.context;
        if (context != null) {
          // copy invite code helper
          await showDialog(
            context: context,
            builder: (dialogCtx) {
              return AlertDialog(
                title: const Text('加入失败'),
                content: Text('自动加入工作区失败：${resp.statusCode} ${body.isNotEmpty ? body : ''}'),
                actions: [
                  TextButton(
                    onPressed: () async {
                      await getIt<ClipboardService>().setPlainText(code!);
                      Navigator.of(dialogCtx).pop();
                      // show toast
                      showToastNotification(message: '邀请码已复制到剪贴板');
                    },
                    child: const Text('复制邀请码'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(dialogCtx).pop();
                      // open settings -> members page
                      try {
                        final userProfile = context.read<UserWorkspaceBloc>().state.userProfile;
                        showSettingsDialog(context, userProfile, context.read<UserWorkspaceBloc>(), SettingsPage.member);
                      } catch (e) {
                        // fallback: just open settings dialog
                        final maybeProfile = context.read<UserWorkspaceBloc>().state.userProfile;
                        showSettingsDialog(context, maybeProfile, context.read<UserWorkspaceBloc>(), SettingsPage.member);
                      }
                    },
                    child: const Text('去 人员管理'),
                  ),
                ],
              );
            },
          );
        }

        return FlowyResult.failure(FlowyError(msg: 'Join workspace failed: ${resp.statusCode}'));
      }
    } catch (e, st) {
      Log.error('[InviteDeepLink] Exception: $e', st);
      onStateChange(this, DeepLinkState.error);
      return FlowyResult.failure(FlowyError(msg: 'Exception: $e'));
    }
  }
}



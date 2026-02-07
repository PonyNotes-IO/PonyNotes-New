import 'dart:convert';

import 'package:appflowy/startup/tasks/deeplink/deeplink_handler.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:http/http.dart' as http;
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/startup/startup.dart' show getIt;
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart' show WorkspaceTypePB, UserProfilePB;
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/clipboard_service.dart' show ClipboardService;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:appflowy/startup/tasks/app_widget.dart' show AppGlobals;
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart' show showToastNotification;
import 'package:appflowy/shared/settings/show_settings.dart' show showSettingsDialog;
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart' show SettingsPage;

/// Very permissive fallback handler to catch invite deep links with unexpected URI shapes.
class AppflowyInviteFallbackDeepLinkHandler extends DeepLinkHandler<void> {
  @override
  bool canHandle(Uri uri) {
    final s = uri.toString().toLowerCase();
    return s.contains('invite') && s.contains('code=') && s.contains('ws=');
  }

  @override
  Future<FlowyResult<void, FlowyError>> handle({
    required Uri uri,
    required DeepLinkStateHandler onStateChange,
  }) async {
    onStateChange(this, DeepLinkState.loading);
    try {
      // Try to extract code and ws from query or path with simple parsing
      String? code = uri.queryParameters['code'];
      String? ws = uri.queryParameters['ws'];

      if ((code == null || ws == null) && uri.toString().contains('?')) {
        final q = uri.toString().split('?').last;
        final params = Uri.splitQueryString(q);
        code ??= params['code'];
        ws ??= params['ws'];
      }

      // fallback: try regex on entire uri
      if (code == null || ws == null) {
        final s = uri.toString();
        final codeMatch = RegExp(r'code=([^&/#]+)').firstMatch(s);
        final wsMatch = RegExp(r'ws=([^&/#]+)').firstMatch(s);
        if (codeMatch != null) code = Uri.decodeComponent(codeMatch.group(1)!);
        if (wsMatch != null) ws = Uri.decodeComponent(wsMatch.group(1)!);
      }

      if (code == null || ws == null) {
        Log.error('[InviteFallback] Could not extract code/ws from uri: ${uri.toString()}');
        onStateChange(this, DeepLinkState.error);
        return FlowyResult.failure(FlowyError(msg: 'Missing code or ws'));
      }

      final sharedEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = sharedEnv.appflowyCloudConfig.base_url;
      // backend exposes join-by-invite-code as /api/workspace/join-by-invite-code
      final url = Uri.parse('$baseUrl/api/workspace/join-by-invite-code');

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
        }, (err) {});
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

        Log.info('[InviteFallback] Joined workspace $joinedWorkspaceId via invite $code');
        onStateChange(this, DeepLinkState.finish);

        final context = AppGlobals.rootNavKey.currentState?.context;
        if (context != null) {
          showDialog(
            context: context,
            builder: (dialogCtx) {
              return AlertDialog(
                title: const Text('已加入工作区'),
                content: Text('已成功加入工作区 $joinedWorkspaceId，是否前往查看？'),
                actions: [
                  TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('稍后')),
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
                      } catch (_) {}
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
        Log.error('[InviteFallback] join workspace failed: status ${resp.statusCode}, body: ${resp.body}');
        onStateChange(this, DeepLinkState.error);

        final context = AppGlobals.rootNavKey.currentState?.context;
        if (context != null) {
          await showDialog(
            context: context,
            builder: (dialogCtx) {
              return AlertDialog(
                title: const Text('加入失败'),
                content: Text('自动加入工作区失败：${resp.statusCode} ${resp.body.isNotEmpty ? resp.body : ''}'),
                actions: [
                  TextButton(
                    onPressed: () async {
                      await getIt<ClipboardService>().setPlainText(code!);
                      Navigator.of(dialogCtx).pop();
                      showToastNotification(message: '邀请码已复制到剪贴板');
                    },
                    child: const Text('复制邀请码'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(dialogCtx).pop();
                      try {
                        final userProfile = context.read<UserWorkspaceBloc>().state.userProfile;
                        showSettingsDialog(context, userProfile, context.read<UserWorkspaceBloc>(), SettingsPage.member);
                      } catch (_) {
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
      Log.error('[InviteFallback] Exception: $e', st);
      onStateChange(this, DeepLinkState.error);
      return FlowyResult.failure(FlowyError(msg: 'Exception: $e'));
    }
  }
}



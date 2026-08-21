import 'dart:convert';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/features/share_tab/data/collab_view_mapper.dart';
import 'package:appflowy/features/share_tab/data/repositories/rust_share_with_user_repository_impl.dart';
import 'package:appflowy/features/share_tab/logic/share_tab_bloc.dart';
import 'package:appflowy/features/share_tab/presentation/share_tab.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/mobile/presentation/base/app_bar/mobile_app_bar.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:http/http.dart' as http;

class MobileSharingPage extends StatefulWidget {
  const MobileSharingPage({super.key, this.workspaceState});

  static const routeName = '/mobile-sharing';

  final Object? workspaceState;

  @override
  State<MobileSharingPage> createState() => _MobileSharingPageState();
}

class _MobileSharingPageState extends State<MobileSharingPage> {
  // 共享内容状态
  List<SharedCollabView> _sharedNotes = const [];
  bool _isLoadingShared = true;
  String? _sharedError;

  // 工作区类型
  WorkspaceTypePB _workspaceType = WorkspaceTypePB.LocalW;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadWorkspace();
      _loadSharedNotes();
    });
  }

  Future<void> _loadWorkspace() async {
    // 获取当前 workspace ID
    final latestResult = await FolderEventGetCurrentWorkspaceSetting().send();
    String wsId = '';
    latestResult.fold((latest) => wsId = latest.workspaceId, (_) {});

    if (wsId.isEmpty) {
      // Fallback: 通过 getCurrentWorkspace 获取 ID
      final wsResult = await UserBackendService.getCurrentWorkspace();
      wsResult.fold((ws) => wsId = ws.id, (_) {});
    }

    if (wsId.isEmpty) return;

    // 获取当前 workspace 的类型
    final workspaceResult = await UserBackendService.getWorkspaceById(wsId);
    final wsType = workspaceResult.fold(
      (ws) => ws.workspaceType,
      (_) => WorkspaceTypePB.LocalW,
    );

    if (mounted) {
      setState(() {
        _workspaceType = wsType;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MobileAppBar(
        title: '笔记共享',
      ),
      body: _buildSharedContent(),
    );
  }

  Widget _buildSharedContent() {
    final theme = AppFlowyTheme.of(context);
    if (_isLoadingShared) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (_sharedError != null && _sharedNotes.isEmpty) {
      return Center(
        child: FlowyText(
          '加载失败：$_sharedError',
          color: theme.textColorScheme.tertiary,
        ),
      );
    }
    if (_sharedNotes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FlowySvg(
              FlowySvgs.share_s,
              size: const Size(48, 48),
              color: theme.iconColorScheme.tertiary,
            ),
            const VSpace(12),
            FlowyText(
              '暂无共享内容',
              color: theme.textColorScheme.secondary,
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + 16,
      ),
      itemCount: _sharedNotes.length,
      itemBuilder: (context, index) =>
          _buildSharedListItem(_sharedNotes[index]),
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: theme.borderColorScheme.primary.withValues(alpha: 0.3),
      ),
    );
  }

  Widget _buildSharedListItem(SharedCollabView entry) {
    final view = entry.view;
    final title = view.name.isNotEmpty ? view.name : '无标题';
    final shareTime = _formatTimestamp(view.createTime.toInt());
    final theme = AppFlowyTheme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B35).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Icon(
                Icons.description_outlined,
                size: 20,
                color: Color(0xFFFF6B35),
              ),
            ),
          ),
          const HSpace(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FlowyText(
                  title,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: theme.textColorScheme.primary,
                  overflow: TextOverflow.ellipsis,
                ),
                const VSpace(4),
                FlowyText(
                  shareTime,
                  fontSize: 12,
                  color: theme.textColorScheme.secondary,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _showInviteMembersDialog(entry),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFF6B35),
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              '查看成员',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(
      timestamp * 1000,
      isUtc: true,
    ).toLocal();
    final two = (int v) => v.toString().padLeft(2, '0');
    return '${dt.year}年${dt.month}月${dt.day}日 ${two(dt.hour)}:${two(dt.minute)}';
  }

  Future<void> _showInviteMembersDialog(SharedCollabView entry) async {
    final view = entry.view;
    final ownerWorkspaceId = entry.ownerWorkspaceId;

    if (ownerWorkspaceId.isEmpty && _workspaceType == WorkspaceTypePB.LocalW) {
      showToastNotification(message: '当前工作区暂不支持共享权限管理');
      return;
    }

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return BlocProvider(
          create: (_) => ShareTabBloc(
            repository: RustShareWithUserRepositoryImpl(),
            pageId: view.id,
            workspaceId: ownerWorkspaceId,
          )..add(ShareTabEvent.initialize()),
          child: CollaboratorsDialog(
            workspaceId: ownerWorkspaceId,
            pageId: view.id,
          ),
        );
      },
    );
  }

  Future<void> _loadSharedNotes() async {
    setState(() {
      _isLoadingShared = true;
      _sharedError = null;
    });
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url.isNotEmpty
          ? cloudEnv.appflowyCloudConfig.base_url
          : 'http://localhost:8000';

      final profileResult = await UserBackendService.getCurrentUserProfile();
      final userProfile = profileResult.fold(
        (profile) => profile,
        (error) {
          throw Exception('获取用户信息失败: ${error.msg}');
        },
      );

      final token = userProfile.token;
      if (token.isEmpty) {
        Log.warn('Token is empty, user may be in offline mode');
        setState(() {
          _isLoadingShared = false;
          _sharedError = '需要登录才能查看共享笔记';
        });
        return;
      }

      final uri = Uri.parse(baseUrl).replace(path: '/api/collab/me/sent');
      final accessToken = _extractAccessToken(token);
      if (accessToken == null || accessToken.isEmpty) {
        Log.error('Failed to extract access_token from token');
        setState(() => _isLoadingShared = false);
        return;
      }

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 404) {
        if (!mounted) return;
        setState(() {
          _sharedNotes = const [];
          _isLoadingShared = false;
          _sharedError = null;
        });
        return;
      }

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      final views = _parseSharedNotesResponse(decoded);

      if (!mounted) return;
      setState(() {
        _sharedNotes = views;
        _isLoadingShared = false;
        _sharedError = null;
      });

      // 异步加载每个笔记的详细信息（包括标题）
      _loadViewDetails(views);
    } catch (e) {
      Log.error('load shared pages exception: $e');
      if (!mounted) return;
      setState(() {
        _sharedNotes = const [];
        _isLoadingShared = false;
        _sharedError = null;
      });
    }
  }

  String? _extractAccessToken(String token) {
    if (token.isEmpty) return null;
    final trimmedToken = token.trim();
    if (trimmedToken.startsWith('{')) {
      try {
        final tokenMap = jsonDecode(trimmedToken) as Map<String, dynamic>;
        return tokenMap['access_token'] as String?;
      } catch (e) {
        Log.error('Failed to parse token as JSON: $e');
        return null;
      }
    }
    return trimmedToken;
  }

  List<SharedCollabView> _parseSharedNotesResponse(dynamic decoded) {
    List<dynamic> items = const [];
    if (decoded is Map<String, dynamic>) {
      final code = decoded['code'];
      if (code is int && code != 0) {
        return [];
      }
      final data = decoded['data'];
      if (data is List<dynamic>) {
        items = data;
      } else if (data is Map<String, dynamic>) {
        final list = data['items'];
        if (list is List<dynamic>) {
          items = list;
        }
      }
    } else if (decoded is List<dynamic>) {
      items = decoded;
    }

    final views = <SharedCollabView>[];
    for (final entry in items) {
      if (entry is! Map<String, dynamic>) continue;

      final sharedView = sharedCollabViewFromJson(entry);
      if (sharedView != null) {
        views.add(sharedView);
      }
    }

    views.sort(
      (a, b) => a.view.createTime.toInt() - b.view.createTime.toInt(),
    );
    return views;
  }

  Future<void> _loadViewDetails(List<SharedCollabView> entries) async {
    if (entries.isEmpty || !mounted) return;

    final updatedViews = <SharedCollabView>[];
    bool hasUpdate = false;

    for (final entry in entries) {
      final view = entry.view;
      if (view.id.isEmpty) {
        updatedViews.add(entry);
        continue;
      }

      try {
        final viewResult = await ViewBackendService.getView(view.id);
        viewResult.fold(
          (detailedView) {
            if (detailedView.name.isNotEmpty) {
              updatedViews.add(entry.copyWith(view: detailedView));
              hasUpdate = true;
            } else {
              updatedViews.add(entry);
            }
          },
          (_) => updatedViews.add(entry),
        );
      } catch (e) {
        Log.error('Failed to load view details for ${view.id}: $e');
        updatedViews.add(entry);
      }
    }

    if (hasUpdate && mounted) {
      setState(() => _sharedNotes = updatedViews);
    }
  }
}

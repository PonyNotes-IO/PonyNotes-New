import 'dart:async';
import 'dart:convert';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/features/shared_section/data/repositories/rust_shared_pages_repository_impl.dart';
import 'package:appflowy/features/shared_section/logic/shared_section_bloc.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;

import '../../../../../application/menu/sidebar_sections_bloc.dart';

class SidebarShareButton extends StatefulWidget {
  const SidebarShareButton({super.key});

  @override
  State<SidebarShareButton> createState() => _SidebarShareButtonState();
}

class _SidebarShareButtonState extends State<SidebarShareButton>
    with WidgetsBindingObserver {
  bool _isExpanded = false;
  List<ViewPB> _userSharedNotes = [];
  bool _isLoading = false;
  late final SharedSectionBloc _sharedSectionBloc;
  String _workspaceId = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _workspaceId =
        context.read<UserWorkspaceBloc>().state.currentWorkspace?.workspaceId ??
            '';
    _sharedSectionBloc = _createSharedSectionBloc(_workspaceId);
    _loadUserSharedNotes();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sharedSectionBloc.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshSharedData();
    }
  }

  SharedSectionBloc _createSharedSectionBloc(String workspaceId) {
    return SharedSectionBloc(
      workspaceId: workspaceId,
      repository: RustSharePagesRepositoryImpl(),
      enablePolling: true,
    )..add(const SharedSectionInitEvent());
  }

  Future<void> _handleWorkspaceChanged(String? workspaceId) async {
    final newWorkspaceId = workspaceId ?? '';
    if (newWorkspaceId.isEmpty || newWorkspaceId == _workspaceId) {
      return;
    }

    await _sharedSectionBloc.close();
    if (!mounted) {
      return;
    }

    setState(() {
      _workspaceId = newWorkspaceId;
      _isExpanded = false;
      _isLoading = false;
      _userSharedNotes = [];
      _sharedSectionBloc = _createSharedSectionBloc(newWorkspaceId);
    });
    _refreshSharedData();
  }

  void _refreshSharedData() {
    _loadUserSharedNotes();
    _sharedSectionBloc.add(const SharedSectionRefreshEvent());
  }

  Future<void> _loadUserSharedNotes() async {
    setState(() => _isLoading = true);

    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl =
          cloudEnv.appflowyCloudConfig.base_url.isNotEmpty
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
        throw Exception('未找到用户凭证，请重新登录');
      }

      final sentNotes = await _fetchCollaborations(
        baseUrl: baseUrl,
        token: token,
        path: '/api/collab/me/sent',
      );
      final receivedNotes = await _fetchCollaborations(
        baseUrl: baseUrl,
        token: token,
        path: '/api/collab/me/received',
      );

      final Map<String, ViewPB> combinedMap = {};
      for (final view in [...sentNotes, ...receivedNotes]) {
        if (view.id.isEmpty) {
          continue;
        }
        combinedMap.putIfAbsent(view.id, () => view);
      }
      final combined = combinedMap.values.toList()
        ..sort((a, b) => b.createTime.toInt() - a.createTime.toInt());

      if (!mounted) {
        return;
      }

      setState(() {
        _userSharedNotes = combined;
        _isLoading = false;
      });
    } catch (e) {
      Log.error('Exception in _loadUserSharedNotes: $e');
      setState(() {
        _userSharedNotes = [];
        _isLoading = false;
      });
    }
  }

  Future<List<ViewPB>> _fetchCollaborations({
    required String baseUrl,
    required String token,
    required String path,
  }) async {
    try {
      final uri = Uri.parse(baseUrl).replace(path: path);
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('请求超时，请稍后重试');
        },
      );

      if (response.statusCode == 404) {
        return [];
      }

      if (response.statusCode != 200) {
        var message = '加载失败：HTTP ${response.statusCode}';
        final body = response.body;
        if (body.isNotEmpty) {
          try {
            final decoded = jsonDecode(body);
            if (decoded is Map<String, dynamic>) {
              final serverMsg = decoded['message']?.toString();
              if (serverMsg != null && serverMsg.isNotEmpty) {
                message = serverMsg;
              }
            }
          } catch (_) {}
        }
        throw Exception(message);
      }

      final decoded = jsonDecode(response.body);
      return _parseCollabViews(decoded);
    } catch (e) {
      Log.error('Failed to fetch $path: $e');
      rethrow;
    }
  }

  List<ViewPB> _parseCollabViews(dynamic decoded) {
    List<dynamic> items = const [];
    if (decoded is Map<String, dynamic>) {
      final code = decoded['code'];
      if (code is int && code != 0) {
        final message = decoded['message']?.toString() ?? '接口返回错误';
        throw Exception(message);
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
    } else {
      throw Exception('接口返回数据格式不正确');
    }

    final views = <ViewPB>[];
    for (final entry in items) {
      if (entry is! Map<String, dynamic>) {
        continue;
      }
      final viewInfo = (entry['view'] as Map<String, dynamic>?) ?? entry;
      var viewId = (viewInfo['objectId'] ??
              viewInfo['object_id'] ??
              viewInfo['viewId'] ??
              viewInfo['view_id'] ??
              viewInfo['id'] ??
              '')
          .toString();
      if (viewId.isEmpty && entry['objectId'] != null) {
        viewId = entry['objectId'].toString();
      }
      if (viewId.isEmpty) {
        continue;
      }

      final title = (viewInfo['title'] ??
              viewInfo['name'] ??
              viewInfo['object_name'] ??
              viewInfo['objectName'] ??
              '未命名笔记')
          .toString();

      final timestampRaw = entry['created_at'] ??
          entry['createdAt'] ??
          entry['create_time'] ??
          entry['createTime'] ??
          viewInfo['created_at'] ??
          viewInfo['createdAt'] ??
          viewInfo['create_time'] ??
          viewInfo['createTime'];
      final createdSeconds = _parseTimestampSeconds(timestampRaw);

      final view = ViewPB()
        ..id = viewId
        ..name = title
        ..createTime = fixnum.Int64(createdSeconds);
      views.add(view);
    }

    return views;
  }

  int _parseTimestampSeconds(dynamic raw) {
    if (raw == null) {
      return DateTime.now().millisecondsSinceEpoch ~/ 1000;
    }
    if (raw is int) {
      return raw > 1000000000000 ? raw ~/ 1000 : raw;
    }
    if (raw is double) {
      final value = raw.toInt();
      return value > 1000000000000 ? value ~/ 1000 : value;
    }
    if (raw is String && raw.isNotEmpty) {
      final parsedDate = DateTime.tryParse(raw);
      if (parsedDate != null) {
        return parsedDate.millisecondsSinceEpoch ~/ 1000;
      }
      final parsedInt = int.tryParse(raw);
      if (parsedInt != null) {
        return parsedInt > 1000000000000 ? parsedInt ~/ 1000 : parsedInt;
      }
    }
    return DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return BlocProvider.value(
      value: _sharedSectionBloc,
      child: BlocListener<UserWorkspaceBloc, UserWorkspaceState>(
        listenWhen: (previous, current) =>
            previous.currentWorkspace?.workspaceId !=
            current.currentWorkspace?.workspaceId,
        listener: (context, state) async {
          await _handleWorkspaceChanged(state.currentWorkspace?.workspaceId);
        },
        child: BlocListener<SidebarSectionsBloc, SidebarSectionsState>(
          listenWhen: (prev, curr) =>
              prev.section.privateViews.length !=
              curr.section.privateViews.length,
          listener: (context, state) {
            _refreshSharedData();
          },
          child: BlocBuilder<SharedSectionBloc, SharedSectionState>(
            builder: (context, state) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(theme.borderRadius.s),
                      onTap: () {
                        setState(() => _isExpanded = !_isExpanded);
                        if (_isExpanded) {
                          _loadUserSharedNotes(); // Refresh when expanding
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            FlowySvg(
                              FlowySvgs.shared_section_icon_m,
                              size: const Size.square(16.0),
                              color:
                                  Theme.of(context).textTheme.bodyMedium?.color,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FlowyText.medium(
                                '共享',
                                fontSize: 14.0,
                                figmaLineHeight: 17.0,
                                color: AppFlowyTheme.of(context)
                                    .textColorScheme
                                    .primary,
                              ),
                            ),
                            Icon(
                              _isExpanded
                                  ? Icons.keyboard_arrow_down
                                  : Icons.keyboard_arrow_right,
                              size: 16,
                              color:
                                  Theme.of(context).textTheme.bodyMedium?.color,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_isExpanded)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 8.0,
                        right: 8.0,
                        bottom: 4.0,
                      ),
                      child: _buildUserSharedNotesList(context),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildUserSharedNotesList(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Center(child: CircularProgressIndicator.adaptive()),
      );
    }
    
    if (_userSharedNotes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(left: 20.0, right: 8.0, top: 6.0, bottom: 6.0),
        child: FlowyText.small(
          '暂无分享的笔记',
          color: Theme.of(context).colorScheme.outline,
        ),
      );
    }
    
    return Column(
      children: _userSharedNotes.map((view) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.0),
          child: InkWell(
            borderRadius: BorderRadius.circular(6.0),
            onTap: () {
              context.read<TabsBloc>().openPlugin(view);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              child: Row(
                children: [
                  FlowySvg(
                    FlowySvgs.document_s,
                    size: const Size.square(16.0),
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FlowyText.medium(
                      view.name,
                      fontSize: 13.0,
                      figmaLineHeight: 16.0,
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

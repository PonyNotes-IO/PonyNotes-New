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
import 'package:appflowy/workspace/application/view/view_service.dart';
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
  bool _isRefreshing = false;
  late SharedSectionBloc _sharedSectionBloc;
  String _workspaceId = '';
  DateTime _lastRefreshTime = DateTime.now();
  final Duration _minRefreshInterval = const Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _workspaceId = 
        context.read<UserWorkspaceBloc>().state.currentWorkspace?.workspaceId ??
            '';
    _sharedSectionBloc = _createSharedSectionBloc(_workspaceId);
    // 初始化时不显示加载状态，直接加载数据
    _loadUserSharedNotes(showLoading: false);
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
      _isRefreshing = false;
      _userSharedNotes = [];
      _sharedSectionBloc = _createSharedSectionBloc(newWorkspaceId);
    });
    _refreshSharedData();
  }

  void _refreshSharedData() {
    // 限流：避免短时间内频繁刷新
    final now = DateTime.now();
    if (now.difference(_lastRefreshTime) < _minRefreshInterval) {
      return;
    }
    _lastRefreshTime = now;
    
    // 只有在展开状态时才刷新数据，避免不必要的网络请求
    if (_isExpanded) {
      _loadUserSharedNotes(showLoading: false);
    }
    _sharedSectionBloc.add(const SharedSectionRefreshEvent());
  }

  Future<void> _loadUserSharedNotes({bool showLoading = true}) async {
    // 避免重复加载
    if (_isLoading || _isRefreshing) {
      return;
    }

    if (showLoading) {
      setState(() => _isLoading = true);
    } else {
      setState(() => _isRefreshing = true);
    }
    
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

      // 提取 access_token（可能是 JSON 格式）
      final accessToken = _extractAccessToken(token);
      if (accessToken == null || accessToken.isEmpty) {
        Log.error('Failed to extract access_token from token');
        return;
      }
      
      List<ViewPB> sentNotes = [];
      try {
        sentNotes = await _fetchCollaborations(
          baseUrl: baseUrl,
          token: accessToken,
          path: '/api/collab/me/sent',
        );
      } catch (e) {
        Log.warn('fetch sent collaborations failed (non-fatal): $e');
      }
      List<ViewPB> receivedNotes = [];
      try {
        receivedNotes = await _fetchCollaborations(
          baseUrl: baseUrl,
          token: accessToken,
          path: '/api/collab/me/received',
        );
      } catch (e) {
        Log.warn('fetch received collaborations failed (non-fatal): $e');
      }

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

      // 加载详细信息（包括标题）
      final updatedViews = await _loadViewDetails(combined);
      
      if (!mounted) {
        return;
      }
      
      setState(() {
        _userSharedNotes = updatedViews;
        _isLoading = false;
        _isRefreshing = false;
      });
    } catch (e) {
      Log.error('Exception in _loadUserSharedNotes: $e');
      setState(() {
        _userSharedNotes = [];
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  /// 从 token 字段中提取 access_token
  /// 如果 token 是 JSON 格式，则解析并提取 access_token
  /// 否则直接返回 token
  String? _extractAccessToken(String token) {
    if (token.isEmpty) {
      return null;
    }

    final trimmedToken = token.trim();

    // 检查是否是 JSON 格式（以 { 开头）
    if (trimmedToken.startsWith('{')) {
      try {
        final tokenMap = jsonDecode(trimmedToken) as Map<String, dynamic>;
        final accessToken = tokenMap['access_token'] as String?;
        if (accessToken != null && accessToken.isNotEmpty) {
          Log.info('Extracted access_token from JSON token');
          return accessToken;
        } else {
          Log.error('access_token not found in JSON token');
          return null;
        }
      } catch (e) {
        Log.error('Failed to parse token as JSON: $e');
        return null;
      }
    }

    // 如果不是 JSON，直接返回 token
    return trimmedToken;
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

      // 根据新的 API 响应结构，使用 oid 作为 viewId
      final oid = (entry['oid'] ?? entry['object_id'] ?? entry['objectId'] ?? '')
          .toString();
      if (oid.isEmpty) {
        continue;
      }

      // 解析创建时间
      final timestampRaw = entry['created_at'] ?? entry['createdAt'];
      final createdSeconds = _parseTimestampSeconds(timestampRaw);

      // 获取视图名称，如果 API 返回了 name 字段则使用，否则使用临时标题
      final name = (entry['name'] ?? '').toString();
      final displayName = name.isNotEmpty ? name : '加载中...';

      // 创建基本的 ViewPB
      final view = ViewPB()
        ..id = oid
        ..name = displayName
        ..createTime = fixnum.Int64(createdSeconds);
      views.add(view);
    }

    return views;
  }

  /// 异步加载笔记的详细信息（包括标题）
  Future<List<ViewPB>> _loadViewDetails(List<ViewPB> views) async {
    if (views.isEmpty) {
      return views;
    }

    final updatedViews = <ViewPB>[];

    for (final view in views) {
      if (view.id.isEmpty) {
        updatedViews.add(view);
        continue;
      }

      try {
        // 尝试通过 ViewBackendService 获取笔记详细信息
        final viewResult = await ViewBackendService.getView(view.id);
        viewResult.fold(
          (detailedView) {
            // 如果成功获取到详细信息，使用真实的标题
            if (detailedView.name.isNotEmpty) {
              updatedViews.add(detailedView);
            } else {
              // 如果标题为空，保持原视图
              updatedViews.add(view);
            }
          },
          (error) {
            // 如果获取失败，保持原视图（使用临时标题）
            updatedViews.add(view);
          },
        );
      } catch (e) {
        Log.error('Failed to load view details for ${view.id}: $e');
        updatedViews.add(view);
      }
    }

    return updatedViews;
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
                    child: SizedBox(
                      height: 44,
                      child: Stack(
                        children: [
                          AFGhostIconTextButton.primary(
                            text: '共享',
                            mainAxisAlignment: MainAxisAlignment.start,
                            size: AFButtonSize.l,
                            onTap: () {
                              setState(() => _isExpanded = !_isExpanded);
                              if (_isExpanded) {
                                // 展开时加载数据，但不显示加载状态
                                _loadUserSharedNotes(showLoading: false);
                              }
                            },
                            padding: const EdgeInsets.symmetric(
                              vertical: 10,
                            ),
                            borderRadius: theme.borderRadius.s,
                            iconBuilder: (context, isHover, disabled) => SizedBox.shrink()
                          ),
                          Positioned(
                            right: 12,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: Icon(
                                _isExpanded
                                    ? Icons.keyboard_arrow_down
                                    : Icons.keyboard_arrow_right,
                                size: 16,
                                color: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.color,
                              ),
                            ),
                          ),
                        ],
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
    // 始终显示笔记列表，即使正在加载数据，避免 UI 闪烁
    // 只有在首次加载且数据为空时才显示加载指示器
    if (_isLoading && _userSharedNotes.isEmpty) {
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

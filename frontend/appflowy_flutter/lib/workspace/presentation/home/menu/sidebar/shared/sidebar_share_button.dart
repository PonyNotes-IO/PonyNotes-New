import 'dart:async';
import 'dart:convert';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/features/share_tab/data/repositories/rust_share_with_user_repository_impl.dart';
import 'package:appflowy/features/share_tab/logic/share_section_refresh_notifier.dart';
import 'package:appflowy/features/share_tab/logic/share_tab_bloc.dart';
import 'package:appflowy/features/shared_section/data/repositories/rust_shared_pages_repository_impl.dart';
import 'package:appflowy/features/shared_section/logic/shared_section_bloc.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/database/application/tab_bar_bloc.dart';
import 'package:appflowy/plugins/database/calendar/application/calendar_unsaved_guard.dart';
import 'package:appflowy/plugins/shared/share/_shared.dart';
import 'package:appflowy/plugins/shared/share/share_bloc.dart';
import 'package:appflowy/plugins/shared/share/share_menu.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
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
  bool _isDragHovering = false;
  List<ViewPB> _userSharedNotes = [];
  bool _isLoading = false;
  bool _isRefreshing = false;
  late SharedSectionBloc _sharedSectionBloc;
  String _workspaceId = '';
  DateTime _lastRefreshTime = DateTime.now();
  final Duration _minRefreshInterval = const Duration(seconds: 2);
  StreamSubscription<void>? _shareSectionRefreshSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _workspaceId =
        context.read<UserWorkspaceBloc>().state.currentWorkspace?.workspaceId ??
            '';
    _sharedSectionBloc = _createSharedSectionBloc(_workspaceId);
    _loadUserSharedNotes(showLoading: false);
    _shareSectionRefreshSub = ShareSectionRefreshNotifier.stream.listen((_) {
      _loadUserSharedNotes(showLoading: false);
    });
  }

  @override
  void dispose() {
    _shareSectionRefreshSub?.cancel();
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
      _isDragHovering = false;
      _isLoading = false;
      _isRefreshing = false;
      _userSharedNotes = [];
      _sharedSectionBloc = _createSharedSectionBloc(newWorkspaceId);
    });
    _refreshSharedData();
  }

  void _refreshSharedData() {
    final now = DateTime.now();
    if (now.difference(_lastRefreshTime) < _minRefreshInterval) {
      return;
    }
    _lastRefreshTime = now;

    if (_isExpanded) {
      _loadUserSharedNotes(showLoading: false);
    }
    _sharedSectionBloc.add(const SharedSectionRefreshEvent());
  }

  Future<void> _loadUserSharedNotes({bool showLoading = true}) async {
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
        Log.warn(
          '[_loadUserSharedNotes] Token is empty, user may be in offline mode',
        );
        if (!showLoading) {
          setState(() => _isRefreshing = false);
        }
        setState(() => _isLoading = false);
        return;
      }

      final accessToken = _extractAccessToken(token);
      if (accessToken == null || accessToken.isEmpty) {
        Log.error('Failed to extract access_token from token');
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
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

      final combinedMap = <String, ViewPB>{};
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

      final updatedViews = await _loadViewDetails(combined);
      if (!mounted) {
        return;
      }

      final enrichedViews = await _enrichViewLayouts(
        updatedViews,
        baseUrl,
        accessToken,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _userSharedNotes = enrichedViews;
        _isLoading = false;
        _isRefreshing = false;
      });
    } catch (e) {
      Log.error('Exception in _loadUserSharedNotes: $e');
      if (!mounted) {
        return;
      }
      setState(() {
        _userSharedNotes = [];
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  String? _extractAccessToken(String token) {
    if (token.isEmpty) {
      return null;
    }

    final trimmedToken = token.trim();
    if (trimmedToken.startsWith('{')) {
      try {
        final tokenMap = jsonDecode(trimmedToken) as Map<String, dynamic>;
        final accessToken = tokenMap['access_token'] as String?;
        if (accessToken != null && accessToken.isNotEmpty) {
          return accessToken;
        }
        Log.error('access_token not found in JSON token');
        return null;
      } catch (e) {
        Log.error('Failed to parse token as JSON: $e');
        return null;
      }
    }

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
        var message = '加载失败: HTTP ${response.statusCode}';
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

      final oid =
          (entry['oid'] ?? entry['object_id'] ?? entry['objectId'] ?? '')
              .toString();
      if (oid.isEmpty) {
        continue;
      }

      final timestampRaw = entry['created_at'] ?? entry['createdAt'];
      final createdSeconds = _parseTimestampSeconds(timestampRaw);
      final name = (entry['name'] ?? '').toString();
      final displayName = name.isNotEmpty ? name : '加载中...';

      final viewLayoutRaw = entry['view_layout'] ?? entry['viewLayout'] ?? 0;
      final viewLayoutInt = viewLayoutRaw is int
          ? viewLayoutRaw
          : (int.tryParse(viewLayoutRaw.toString()) ?? 0);

      final viewLayout = switch (viewLayoutInt) {
        1 => ViewLayoutPB.Grid,
        2 => ViewLayoutPB.Board,
        3 => ViewLayoutPB.Calendar,
        _ => ViewLayoutPB.Document,
      };

      final view = ViewPB()
        ..id = oid
        ..name = displayName
        ..layout = viewLayout
        ..createTime = fixnum.Int64(createdSeconds);
      views.add(view);
    }

    return views;
  }

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
        final viewResult = await ViewBackendService.getView(view.id);
        viewResult.fold(
          (detailedView) {
            if (detailedView.name.isNotEmpty) {
              final enriched = ViewPB()
                ..id = view.id
                ..name = detailedView.name
                ..layout = view.layout
                ..createTime = view.createTime;
              updatedViews.add(enriched);
            } else {
              updatedViews.add(view);
            }
          },
          (_) {
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

  Future<List<ViewPB>> _enrichViewLayouts(
    List<ViewPB> views,
    String baseUrl,
    String accessToken,
  ) async {
    final result = <ViewPB>[];
    for (final view in views) {
      if (view.layout != ViewLayoutPB.Document) {
        result.add(view);
        continue;
      }

      try {
        final uri = Uri.parse(baseUrl).replace(
          path: '/api/collab/share-info',
          queryParameters: {'view_id': view.id},
        );
        final response = await http.get(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            final data = decoded['data'];
            if (data is Map<String, dynamic>) {
              final layoutRaw = data['view_layout'];
              final layoutInt = layoutRaw is int
                  ? layoutRaw
                  : (int.tryParse(layoutRaw.toString()) ?? 0);
              if (layoutInt > 0) {
                final correctedLayout = switch (layoutInt) {
                  1 => ViewLayoutPB.Grid,
                  2 => ViewLayoutPB.Board,
                  3 => ViewLayoutPB.Calendar,
                  _ => ViewLayoutPB.Document,
                };
                final corrected = ViewPB()
                  ..id = view.id
                  ..name = view.name
                  ..layout = correctedLayout
                  ..createTime = view.createTime;
                result.add(corrected);
                continue;
              }
            }
          }
        }
      } catch (e) {
        Log.warn('Failed to enrich layout for ${view.id}: $e');
      }

      result.add(view);
    }

    return result;
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

  bool _canAcceptDraggedView(ViewPB view) {
    return !view.isSpace;
  }

  Future<void> _openSharePanelForView(ViewPB view) async {
    final userWorkspaceBloc = context.read<UserWorkspaceBloc>();
    final workspace = userWorkspaceBloc.state.currentWorkspace;
    final workspaceId = workspace?.workspaceId ?? '';
    final workspaceType = workspace?.workspaceType;
    final shareBloc = getIt<ShareBloc>(param1: view)
      ..add(const ShareEvent.initial());
    final shareTabBloc = ShareTabBloc(
      repository: RustShareWithUserRepositoryImpl(),
      pageId: view.id,
      workspaceId: workspaceId,
    );
    DatabaseTabBarBloc? databaseBloc;

    if (workspaceType != WorkspaceTypePB.LocalW) {
      shareTabBloc.add(ShareTabEvent.initialize());
    }

    if (view.layout.isDatabaseView) {
      databaseBloc = DatabaseTabBarBloc(
        view: view,
        compactModeId: view.id,
        enableCompactMode: false,
      )..add(const DatabaseTabBarEvent.initial());
    }

    try {
      final tabs = await _buildShareTabsForView(
        view: view,
        workspaceType: workspaceType,
      );
      if (!mounted) {
        return;
      }

      await openShareSettingsDialog(
        context: context,
        tabs: tabs,
        shareBloc: shareBloc,
        userWorkspaceBloc: userWorkspaceBloc,
        shareWithUserBloc: shareTabBloc,
        databaseBloc: databaseBloc,
      );
    } finally {
      await databaseBloc?.close();
      await shareTabBloc.close();
      await shareBloc.close();
    }
  }

  Future<List<ShareMenuTab>> _buildShareTabsForView({
    required ViewPB view,
    required WorkspaceTypePB? workspaceType,
  }) async {
    if (workspaceType == WorkspaceTypePB.LocalW) {
      return const [];
    }

    final spacePermission = await _getSpacePermission(view);
    final tabs = <ShareMenuTab>[];
    if (spacePermission != SpacePermission.private) {
      tabs.add(ShareMenuTab.share);
    }
    return tabs;
  }

  Future<SpacePermission> _getSpacePermission(ViewPB view) async {
    try {
      if (view.isSpace) {
        return view.spacePermission;
      }

      final ancestorsResult =
          await ViewBackendService.getViewAncestors(view.id);
      return ancestorsResult.fold(
        (ancestors) {
          for (final ancestor in ancestors.items) {
            if (ancestor.isSpace) {
              return ancestor.spacePermission;
            }
          }
          return SpacePermission.publicToAll;
        },
        (_) => SpacePermission.publicToAll,
      );
    } catch (e) {
      Log.error('Failed to resolve share space permission for ${view.id}: $e');
      return SpacePermission.publicToAll;
    }
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
                    child: DragTarget<ViewPB>(
                      onWillAcceptWithDetails: (details) {
                        final canAccept = _canAcceptDraggedView(details.data);
                        if (canAccept && !_isDragHovering) {
                          setState(() => _isDragHovering = true);
                        }
                        return canAccept;
                      },
                      onLeave: (_) {
                        if (_isDragHovering) {
                          setState(() => _isDragHovering = false);
                        }
                      },
                      onAcceptWithDetails: (details) async {
                        setState(() {
                          _isDragHovering = false;
                          _isExpanded = true;
                        });
                        unawaited(_loadUserSharedNotes(showLoading: false));
                        await _openSharePanelForView(details.data);
                      },
                      builder: (context, candidateData, rejectedData) {
                        final isActive =
                            _isDragHovering || candidateData.isNotEmpty;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          height: 44,
                          decoration: BoxDecoration(
                            color: isActive
                                ? Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.10)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(
                              theme.borderRadius.s,
                            ),
                          ),
                          child: AFGhostIconTextButton.primary(
                            text: '共享',
                            mainAxisAlignment: MainAxisAlignment.start,
                            size: AFButtonSize.l,
                            onTap: () {
                              setState(() => _isExpanded = !_isExpanded);
                              if (_isExpanded) {
                                _loadUserSharedNotes(showLoading: false);
                              }
                            },
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            borderRadius: theme.borderRadius.s,
                            iconBuilder: (context, isHover, disabled) =>
                                const SizedBox.shrink(),
                            showExpandArrow: true,
                            isExpanded: _isExpanded,
                          ),
                        );
                      },
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
    if (_isLoading && _userSharedNotes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Center(child: CircularProgressIndicator.adaptive()),
      );
    }

    if (_userSharedNotes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(
          left: 20.0,
          right: 8.0,
          top: 6.0,
          bottom: 6.0,
        ),
        child: FlowyText.small(
          '暂无共享的笔记',
          color: Theme.of(context).colorScheme.outline,
        ),
      );
    }

    return Column(
      children: _userSharedNotes.map((view) {
        final iconData = switch (view.layout) {
          ViewLayoutPB.Grid => FlowySvgs.grid_s,
          ViewLayoutPB.Board => FlowySvgs.board_s,
          ViewLayoutPB.Calendar => FlowySvgs.date_s,
          _ => FlowySvgs.document_s,
        };

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.0),
          child: InkWell(
            borderRadius: BorderRadius.circular(6.0),
            onTap: () {
              CalendarUnsavedGuard.instance.maybeConfirmLeave(
                context,
                () => context.read<TabsBloc>().openTab(view),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 8.0,
              ),
              child: Row(
                children: [
                  FlowySvg(
                    iconData,
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

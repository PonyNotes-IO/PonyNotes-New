import 'dart:convert';

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/features/share_tab/data/models/share_section_type.dart';
import 'package:appflowy/features/share_tab/data/repositories/rust_share_with_user_repository_impl.dart';
import 'package:appflowy/features/share_tab/logic/share_tab_bloc.dart';
import 'package:appflowy/features/share_tab/presentation/widgets/access_level_list_widget.dart';
import 'package:appflowy/features/share_tab/presentation/widgets/shared_user_widget.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/shared/share/constants.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/view/view_publish_service.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/panels/publish_notifier.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_body.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:collection/collection.dart';
import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:http/http.dart' as http;

import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pbenum.dart';

class SettingsSharingView extends StatefulWidget {
  const SettingsSharingView({
    super.key,
    required this.userProfile,
  });

  final UserProfilePB userProfile;

  @override
  State<SettingsSharingView> createState() => _SettingsSharingViewState();
}

class _SettingsSharingViewState extends State<SettingsSharingView> {
  final List<String> _tabs = ['共享', '发布'];
  int _currentTab = 0;

  // 发布内容状态
  List<PublishInfoViewPB> _publishedViews = const [];
  bool _isLoadingPublished = true;
  String? _loadError;

  // 共享内容状态
  List<ViewPB> _sharedNotes = const [];
  bool _isLoadingShared = true;
  String? _sharedError;

  @override
  void initState() {
    super.initState();
    PublishRefresh.notifier.addListener(_onPublishPing);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSharedNotes();
      _loadPublishedViews();
    });
  }

  @override
  void dispose() {
    PublishRefresh.notifier.removeListener(_onPublishPing);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 判断是否是免费套餐（plan.value == 0 表示免费版）
    final subscriptionInfo =
        context.read<UserWorkspaceBloc>().state.workspaceSubscriptionInfo;
    final isFree = subscriptionInfo == null || subscriptionInfo.plan.value == 0;

    return SettingsBody(
      title: '共享发布',
      description: '',
      autoSeparate: false,
      children: [
        if (isFree)
          _buildUpgradePrompt(context)
        else ...[
          _buildTabSection(),
          const VSpace(8),
          _buildTabContent(),
        ],
      ],
    );
  }

  Widget _buildUpgradePrompt(BuildContext context) {
    return SizedBox(
      height: 340,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0E2),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Center(
                child: Icon(
                  Icons.lock_outline_rounded,
                  size: 36,
                  color: Color(0xFFFF6B35),
                ),
              ),
            ),
            const VSpace(20),
            const FlowyText(
              '升级会员解锁共享发布功能',
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            const VSpace(10),
            FlowyText(
              '升级到标准版及以上套餐，即可共享笔记给他人协作，\n并将笔记发布为公开网页。',
              fontSize: 13,
              color: Colors.grey[500],
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
            const VSpace(28),
            SizedBox(
              height: 40,
              child: ElevatedButton(
                onPressed: () {
                  context.read<SettingsDialogBloc>().add(
                        const SettingsDialogEvent.setSelectedPage(
                          SettingsPage.accountManagement,
                        ),
                      );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B35),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const FlowyText(
                  '立即升级会员',
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onPublishPing() {
    if (_isLoadingPublished) {
      return;
    }
    _loadPublishedViews();
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
        throw Exception('未找到用户凭证，请重新登录');
      }

      final uri = Uri.parse(baseUrl).replace(
        path: '/api/collab/me/sent',
      );

      // 提取 access_token（可能是 JSON 格式）
      final accessToken = _extractAccessToken(token);
      if (accessToken == null || accessToken.isEmpty) {
        Log.error('Failed to extract access_token from token');
        return;
      }

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('请求超时，请稍后重试');
        },
      );

      if (response.statusCode == 404) {
        // 后端返回 404（例如订阅信息不存在），默认展示空列表，不提示错误
        if (!mounted) {
          return;
        }
        setState(() {
          _sharedNotes = const [];
          _isLoadingShared = false;
          _sharedError = null;
        });
        return;
      }

      if (response.statusCode != 200) {
        final body = response.body;
        String message = '加载失败：HTTP ${response.statusCode}';
        if (body.isNotEmpty) {
          try {
            final decoded = jsonDecode(body);
            if (decoded is Map<String, dynamic>) {
              final serverMsg = decoded['message']?.toString();
              if (serverMsg != null && serverMsg.isNotEmpty) {
                message = serverMsg;
              }
            }
          } catch (e) {
            // ignore parse error
          }
        }
        throw Exception(message);
      }

      final decoded = jsonDecode(response.body);
      final views = _parseSharedNotesResponse(decoded);

      if (!mounted) {
        return;
      }

      setState(() {
        _sharedNotes = views;
        _isLoadingShared = false;
        _sharedError = null;
      });

      // 异步加载每个笔记的详细信息（包括标题）
      _loadViewDetails(views);
    } catch (e) {
      Log.error('load shared pages exception: $e');
      if (!mounted) {
        return;
      }
      setState(() {
        _sharedNotes = const [];
        _isLoadingShared = false;
        // 默认失败展示空列表，不显示错误文案
        _sharedError = null;
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

  List<ViewPB> _parseSharedNotesResponse(dynamic decoded) {
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
      final oid =
          (entry['oid'] ?? entry['object_id'] ?? entry['objectId'] ?? '')
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

    views.sort((a, b) => b.createTime.toInt() - a.createTime.toInt());
    return views;
  }

  /// 异步加载笔记的详细信息（包括标题）
  Future<void> _loadViewDetails(List<ViewPB> views) async {
    if (views.isEmpty || !mounted) {
      return;
    }

    final updatedViews = <ViewPB>[];
    bool hasUpdate = false;

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
              hasUpdate = true;
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

    // 如果有更新，更新 UI
    if (hasUpdate && mounted) {
      setState(() {
        _sharedNotes = updatedViews;
      });
    }
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

  Future<void> _loadPublishedViews() async {
    // 快速进入 / 本地用户不支持发布站点，这里直接展示空列表即可，不显示错误
    if (widget.userProfile.userAuthType != AuthTypePB.Server) {
      if (!mounted) return;
      setState(() {
        _publishedViews = const [];
        _isLoadingPublished = false;
        _loadError = null;
      });
      return;
    }

    setState(() {
      _isLoadingPublished = true;
      _loadError = null;
    });
    try {
      // 与 SidebarPublishButton 保持一致的刷新逻辑
      await ViewPublishService().refreshPublishedViews();
      final result = await FolderEventListPublishedViews().send();
      final items = result.fold((s) {
        final views = List<PublishInfoViewPB>.from(s.items);
        // 按发布时间倒序
        views.sort((a, b) =>
            b.info.publishTimestampSec.toInt() -
            a.info.publishTimestampSec.toInt());
        return views;
      }, (f) {
        Log.error('load published views failed: $f');
        _loadError = f.msg;
        return <PublishInfoViewPB>[];
      });
      if (!mounted) return;
      setState(() {
        _publishedViews = items;
        _isLoadingPublished = false;
      });
    } catch (e) {
      Log.error('load published views exception: $e');
      if (!mounted) return;
      setState(() {
        _publishedViews = const [];
        _isLoadingPublished = false;
        _loadError = '加载失败';
      });
    }
  }

  Widget _buildTabSection() {
    return Row(
      children: _tabs.asMap().entries.map((entry) {
        int index = entry.key;
        String tab = entry.value;
        bool isSelected = _currentTab == index;

        return GestureDetector(
          onTap: () {
            if (_currentTab != index) {
              setState(() {
                _currentTab = index;
              });
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFFF6B35) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: isSelected ? null : Border.all(color: Colors.grey[300]!),
            ),
            child: FlowyText(
              tab,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isSelected ? Colors.white : Colors.grey[600],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTabContent() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      child: _currentTab == 0
          ? KeyedSubtree(
              key: const ValueKey('shared_tab'),
              child: _buildSharedContent(),
            )
          : KeyedSubtree(
              key: const ValueKey('publish_tab'),
              child: _buildPublishedContent(),
            ),
    );
  }

  Widget _buildSharedContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        _buildSharedHeader(),
        const Divider(height: 1),
        _buildSharedListBody(),
      ],
    );
  }

  Widget _buildPublishedContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FlowyText(
          '我发布的网站',
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.grey[600],
        ),
        _buildPublishedListBody(),
      ],
    );
  }

  Widget _buildSharedHeader() {
    final theme = AppFlowyTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: FlowyText(
              '文件标题名称',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: theme.textColorScheme.secondary,
            ),
          ),
          Expanded(
            flex: 3,
            child: FlowyText(
              '时间',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: theme.textColorScheme.secondary,
            ),
          ),
          Expanded(
            flex: 1,
            child: FlowyText(
              '访问权限',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: theme.textColorScheme.secondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSharedListBody() {
    if (_isLoadingShared) {
      return SizedBox(
        height: 240,
        child: const Center(
          child: CircularProgressIndicator.adaptive(),
        ),
      );
    }
    if (_sharedError != null && _sharedNotes.isEmpty) {
      return SizedBox(
        height: 240,
        child: Center(
          child: FlowyText(
            '加载失败：$_sharedError',
            color: Colors.red,
          ),
        ),
      );
    }
    if (_sharedNotes.isEmpty) {
      return SizedBox(
        height: 240,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FlowySvg(
                FlowySvgs.share_s,
                size: const Size(48, 48),
                color: Colors.grey[400],
              ),
              const VSpace(12),
              FlowyText(
                '暂无共享内容',
                color: Colors.grey[500],
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        for (int index = 0; index < _sharedNotes.length; index++) ...[
          _buildSharedListItem(_sharedNotes[index]),
          if (index != _sharedNotes.length - 1)
            Divider(height: 1, color: Colors.grey[200]),
        ],
      ],
    );
  }

  Widget _buildSharedListItem(ViewPB view) {
    final title = view.name.isNotEmpty ? view.name : '无标题';
    final shareTime = _formatTimestamp(view.createTime.toInt());
    const accessLabel = '已共享';
    final theme = AppFlowyTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: FlowyText(
              title,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: theme.textColorScheme.primary,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 3,
            child: FlowyText(
              shareTime,
              fontSize: 14,
              fontWeight: FontWeight.normal,
              color: theme.textColorScheme.primary,
            ),
          ),
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FlowyText.small(
                  accessLabel,
                  color: theme.textColorScheme.secondary,
                ),
                TextButton(
                  onPressed: () {
                    Log.debug('查看邀请成员: ${view.id}');
                    _showInviteMembersDialog(view);
                  },
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 24),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: const Color(0xFFFF6B35),
                  ),
                  child: const Text('查看邀请成员'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPublishedListBody() {
    if (_isLoadingPublished) {
      return SizedBox(
        height: 320,
        child: const Center(
          child: CircularProgressIndicator.adaptive(),
        ),
      );
    }
    if (_loadError != null && _publishedViews.isEmpty) {
      return SizedBox(
        height: 320,
        child: Center(
          child: FlowyText(
            '加载失败：$_loadError',
            color: Colors.red,
          ),
        ),
      );
    }
    if (_publishedViews.isEmpty) {
      return SizedBox(
        height: 320,
        child: Center(
          child: FlowyText(
            '暂无发布',
            color: Colors.grey[600],
          ),
        ),
      );
    }
    return Column(
      children: [
        for (int index = 0; index < _publishedViews.length; index++) ...[
          _buildPublishListItem(_publishedViews[index]),
          if (index != _publishedViews.length - 1)
            Divider(height: 1, color: Colors.grey[200]),
        ],
      ],
    );
  }

  String _formatTimestamp(int secondsSinceEpoch) {
    final dt = DateTime.fromMillisecondsSinceEpoch(
      secondsSinceEpoch * 1000,
      isUtc: true,
    ).toLocal();
    final two = (int v) => v.toString().padLeft(2, '0');
    return '${dt.year}年${dt.month}月${dt.day}日 ${two(dt.hour)}:${two(dt.minute)}';
  }

  Widget _buildPublishListItem(PublishInfoViewPB item) {
    final String title =
        item.view.name.isNotEmpty ? item.view.name : item.info.publishName;
    final String publishTime = _formatPublishTime(
      item.info.publishTimestampSec.toInt(),
    );
    // 获取当前工作区ID
    final workspaceId =
        context.read<UserWorkspaceBloc>().state.currentWorkspace?.workspaceId ??
            '';
    final String publishUrl = ShareConstants.buildPublishUrl(
      workspaceId: workspaceId,
      viewId: item.info.viewId,
    );

    final theme = AppFlowyTheme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0E2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: FlowySvg(
                      FlowySvgs.share_publish_s,
                      size: const Size.square(18),
                      color: const Color(0xFFFF6B35),
                    ),
                  ),
                ),
                const HSpace(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FlowyText(
                        title.isEmpty ? '无标题' : title,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: theme.textColorScheme.primary,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const VSpace(4),
                      GestureDetector(
                        onTap: () => _openPublishUrl(publishUrl),
                        child: FlowyText.small(
                          publishUrl,
                          color: const Color(0xFF2563EB),
                          overflow: TextOverflow.ellipsis,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: FlowyText(
              publishTime,
              fontSize: 14,
              fontWeight: FontWeight.normal,
              color: theme.textColorScheme.primary,
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _openPublishUrl(publishUrl),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFF6B35),
                ),
                child: const Text('打开网址'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPublishUrl(String url) async {
    await afLaunchUrlString(url);
  }

  Future<void> _showInviteMembersDialog(ViewPB view) async {
    final workspaceState = context.read<UserWorkspaceBloc>().state;
    final workspace = workspaceState.currentWorkspace;

    if (workspace == null) {
      showToastNotification(message: '未找到工作区');
      return;
    }

    if (workspace.workspaceType == WorkspaceTypePB.LocalW) {
      showToastNotification(message: '当前工作区暂不支持共享权限管理');
      return;
    }

    final workspaceId = workspace.workspaceId;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return BlocProvider(
          create: (_) => ShareTabBloc(
            repository: RustShareWithUserRepositoryImpl(),
            pageId: view.id,
            workspaceId: workspaceId,
          )..add(ShareTabEvent.initialize()),
          child: _ViewInviteMembersDialog(
            view: view,
          ),
        );
      },
    );
  }

  String _formatPublishTime(int secondsSinceEpoch) {
    // 后端时间单位是秒
    final dt = DateTime.fromMillisecondsSinceEpoch(secondsSinceEpoch * 1000,
            isUtc: true)
        .toLocal();
    final two = (int v) => v.toString().padLeft(2, '0');
    return '${dt.year}年${dt.month}月${dt.day}日 ${two(dt.hour)}:${two(dt.minute)}';
  }
}

// 旧的占位模型已移除，改为直接使用 PublishInfoViewPB

class _ViewInviteMembersDialog extends StatefulWidget {
  const _ViewInviteMembersDialog({
    required this.view,
  });

  final ViewPB view;

  @override
  State<_ViewInviteMembersDialog> createState() =>
      _ViewInviteMembersDialogState();
}

class _ViewInviteMembersDialogState extends State<_ViewInviteMembersDialog> {
  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ShareTabBloc, ShareTabState>(
      listener: _onShareStateChanged,
      builder: (context, state) {
        final sharedUsers = state.users;
        final currentSharedUser = sharedUsers.firstWhereOrNull(
          (user) => user.userId == state.currentUser?.id.toString(),
        );
        final isInitialLoading = sharedUsers.isEmpty &&
            state.errorMessage.isEmpty &&
            state.currentUser == null;

        return Dialog(
          insetPadding: const EdgeInsets.all(24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context),
                  const Divider(height: 24),
                  if (isInitialLoading)
                    SizedBox(
                      height: 220,
                      child: const Center(
                        child: CircularProgressIndicator.adaptive(),
                      ),
                    )
                  else if (state.errorMessage.isNotEmpty && sharedUsers.isEmpty)
                    SizedBox(
                      height: 220,
                      child: Center(
                        child: FlowyText(
                          '加载失败：${state.errorMessage}',
                          color: Colors.red,
                        ),
                      ),
                    )
                  else if (sharedUsers.isEmpty)
                    SizedBox(
                      height: 220,
                      child: Center(
                        child: FlowyText(
                          '暂无邀请成员',
                          color: Colors.grey[600],
                        ),
                      ),
                    )
                  else if (currentSharedUser == null)
                    SizedBox(
                      height: 220,
                      child: Center(
                        child: FlowyText(
                          '无法获取当前成员信息',
                          color: Colors.red,
                        ),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: Scrollbar(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: sharedUsers.length,
                          separatorBuilder: (_, __) =>
                              Divider(height: 1, color: Colors.grey[200]),
                          itemBuilder: (context, index) {
                            final user = sharedUsers[index];
                            return SharedUserWidget(
                              user: user,
                              currentUser: currentSharedUser,
                              isInPublicPage:
                                  state.sectionType == SharedSectionType.public,
                              callbacks: AccessLevelListCallbacks(
                                onSelectAccessLevel: (accessLevel) {
                                  context.read<ShareTabBloc>().add(
                                        ShareTabEvent.updateUserAccessLevel(
                                          email: user.email,
                                          accessLevel: accessLevel,
                                        ),
                                      );
                                },
                                onTurnIntoMember: () {
                                  context.read<ShareTabBloc>().add(
                                        ShareTabEvent.convertToMember(
                                          email: user.email,
                                        ),
                                      );
                                },
                                onRemoveAccess: () {
                                  context.read<ShareTabBloc>().add(
                                        ShareTabEvent.removeUsers(
                                          emails: [user.email],
                                        ),
                                      );
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('关闭'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final viewTitle = widget.view.name.isNotEmpty ? widget.view.name : '无标题';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FlowyText(
                '查看邀请成员',
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              const VSpace(4),
              FlowyText(
                viewTitle,
                fontSize: 14,
                color: Colors.grey[600],
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
          visualDensity: VisualDensity.compact,
          splashRadius: 20,
        ),
      ],
    );
  }

  void _onShareStateChanged(BuildContext context, ShareTabState state) {
    final shareResult = state.shareResult;
    if (shareResult != null) {
      shareResult.fold(
        (_) => showToastNotification(message: '邀请已发送'),
        (error) => showToastNotification(
          message: error.msg,
          type: ToastificationType.error,
        ),
      );
    }

    final removeResult = state.removeResult;
    if (removeResult != null) {
      removeResult.fold(
        (_) => showToastNotification(message: '已移除成员'),
        (error) => showToastNotification(
          message: error.msg,
          type: ToastificationType.error,
        ),
      );
    }

    final updateAccessLevelResult = state.updateAccessLevelResult;
    if (updateAccessLevelResult != null) {
      updateAccessLevelResult.fold(
        (_) => showToastNotification(message: '权限已更新'),
        (error) => showToastNotification(
          message: error.msg,
          type: ToastificationType.error,
        ),
      );
    }

    final turnIntoMemberResult = state.turnIntoMemberResult;
    if (turnIntoMemberResult != null) {
      turnIntoMemberResult.fold(
        (_) => showToastNotification(message: '已升级为成员'),
        (error) => showToastNotification(
          message: error.msg,
          type: ToastificationType.error,
        ),
      );
    }
  }
}

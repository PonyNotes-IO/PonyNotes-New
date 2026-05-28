import 'dart:convert';

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/mobile/presentation/base/app_bar/mobile_app_bar.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/view/view_publish_service.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:http/http.dart' as http;
import 'package:fixnum/fixnum.dart' as fixnum;

class MobileSharingPage extends StatefulWidget {
  const MobileSharingPage({super.key});

  static const routeName = '/mobile-sharing';

  @override
  State<MobileSharingPage> createState() => _MobileSharingPageState();
}

class _MobileSharingPageState extends State<MobileSharingPage> {
  final List<String> _tabs = ['共享', '发布'];
  int _currentTab = 0;

  // 共享内容状态
  List<ViewPB> _sharedNotes = const [];
  bool _isLoadingShared = true;
  String? _sharedError;

  // 发布内容状态
  List<PublishInfoViewPB> _publishedViews = const [];
  bool _isLoadingPublished = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSharedNotes();
      _loadPublishedViews();
    });
  }

  @override
  Widget build(BuildContext context) {
    final subscriptionInfo =
        context.read<UserWorkspaceBloc>().state.workspaceSubscriptionInfo;
    final isFree = subscriptionInfo == null || subscriptionInfo.plan.value == 0;

    return Scaffold(
      appBar: MobileAppBar(
        title: '共享发布',
      ),
      body: isFree
          ? _buildUpgradePrompt()
          : Column(
              children: [
                _buildTabSection(),
                Expanded(
                  child: _buildTabContent(),
                ),
              ],
            ),
    );
  }

  Widget _buildUpgradePrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
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
              '升级到标准版及以上套餐，即可共享笔记给他人协作，并将笔记发布为公开网页。',
              fontSize: 13,
              color: Colors.grey[500],
              textAlign: TextAlign.center,
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabSection() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: _tabs.asMap().entries.map((entry) {
          int index = entry.key;
          String tab = entry.value;
          bool isSelected = _currentTab == index;

          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (_currentTab != index) {
                  setState(() {
                    _currentTab = index;
                  });
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFFF6B35) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: isSelected
                      ? null
                      : Border.all(color: Colors.grey[300]!),
                ),
                alignment: Alignment.center,
                child: FlowyText(
                  tab,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? Colors.white : Colors.grey[600],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTabContent() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
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
    if (_isLoadingShared) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (_sharedError != null && _sharedNotes.isEmpty) {
      return Center(
        child: FlowyText(
          '加载失败：$_sharedError',
          color: Colors.red,
        ),
      );
    }
    if (_sharedNotes.isEmpty) {
      return _buildEmptyState(
        icon: FlowySvgs.share_s,
        message: '暂无共享内容',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _sharedNotes.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        color: Colors.grey[200],
      ),
      itemBuilder: (context, index) {
        final view = _sharedNotes[index];
        return _buildSharedListItem(view);
      },
    );
  }

  Widget _buildPublishedContent() {
    if (_isLoadingPublished) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (_loadError != null && _publishedViews.isEmpty) {
      return Center(
        child: FlowyText(
          '加载失败：$_loadError',
          color: Colors.red,
        ),
      );
    }
    if (_publishedViews.isEmpty) {
      return _buildEmptyState(
        icon: FlowySvgs.m_publish_s,
        message: '暂无发布内容',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _publishedViews.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        color: Colors.grey[200],
      ),
      itemBuilder: (context, index) {
        final view = _publishedViews[index];
        return _buildPublishedListItem(view);
      },
    );
  }

  Widget _buildEmptyState({
    required FlowySvgData icon,
    required String message,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FlowySvg(
            icon,
            size: const Size(48, 48),
            color: Colors.grey[400],
          ),
          const VSpace(12),
          FlowyText(
            message,
            color: Colors.grey[500],
          ),
        ],
      ),
    );
  }

  Widget _buildSharedListItem(ViewPB view) {
    final title = view.name.isNotEmpty ? view.name : '无标题';
    final shareTime = _formatTimestamp(view.createTime.toInt());
    final theme = AppFlowyTheme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
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
                  '$shareTime · 已共享',
                  fontSize: 12,
                  color: theme.textColorScheme.secondary,
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            color: Colors.grey[400],
          ),
        ],
      ),
    );
  }

  Widget _buildPublishedListItem(PublishInfoViewPB view) {
    final title = view.view.name.isNotEmpty ? view.view.name : '无标题';
    final publishTime = view.info.publishTimestampSec.toInt() > 0
        ? _formatTimestamp(view.info.publishTimestampSec.toInt())
        : '未知';
    final theme = AppFlowyTheme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Icon(
                Icons.public_outlined,
                size: 20,
                color: Color(0xFF4CAF50),
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
                  '$publishTime · 已发布',
                  fontSize: 12,
                  color: theme.textColorScheme.secondary,
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            color: Colors.grey[400],
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return DateFormat('yyyy-MM-dd').format(date);
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

  Future<void> _loadPublishedViews() async {
    if (!mounted) return;

    setState(() {
      _isLoadingPublished = true;
      _loadError = null;
    });
    try {
      await ViewPublishService().refreshPublishedViews();
      final result = await FolderEventListPublishedViews().send();
      final items = result.fold((s) {
        final views = List<PublishInfoViewPB>.from(s.items);
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
        _loadError = null;
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

  List<ViewPB> _parseSharedNotesResponse(dynamic decoded) {
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

    final views = <ViewPB>[];
    for (final entry in items) {
      if (entry is! Map<String, dynamic>) continue;

      final viewId = entry['view_id']?.toString() ?? '';
      final name = entry['name']?.toString() ?? '无标题';
      final createTime = entry['create_time'];
      int timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (createTime is int) {
        timestamp = createTime;
      } else if (createTime is String) {
        try {
          timestamp = int.parse(createTime);
        } catch (_) {}
      }

      final view = ViewPB()
        ..id = viewId
        ..name = name
        ..createTime = fixnum.Int64(timestamp);
      views.add(view);
    }
    return views;
  }
}

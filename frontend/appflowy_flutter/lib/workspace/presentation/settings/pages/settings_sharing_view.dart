import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/shared/share/constants.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_body.dart';

import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy/workspace/application/view/view_publish_service.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy/workspace/presentation/panels/publish_notifier.dart';

import 'package:appflowy/features/shared_section/models/shared_page.dart';
import 'package:appflowy/features/util/extensions.dart';
import 'package:appflowy/features/share_tab/data/models/share_access_level.dart';

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
  List<SharedPage> _sharedPages = const [];
  bool _isLoadingShared = true;
  String? _sharedError;

  @override
  void initState() {
    super.initState();
    PublishRefresh.notifier.addListener(_onPublishPing);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSharedPages();
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
    return SettingsBody(
      title: '共享发布',
      description: '',
      autoSeparate: false,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: _buildTabSection(),
        ),
        const VSpace(8),
        _buildTabContent(),
      ],
    );
  }

  void _onPublishPing() {
    if (_isLoadingPublished) {
      return;
    }
    _loadPublishedViews();
  }

  Future<void> _loadSharedPages() async {
    setState(() {
      _isLoadingShared = true;
      _sharedError = null;
    });
    try {
      final result = await FolderEventGetSharedViews().send();
      final pages = result.fold(
        (success) {
          final sharedPages = List<SharedPage>.from(success.sharedPages);
          sharedPages.sort(
            (a, b) =>
                b.view.createTime.toInt() - a.view.createTime.toInt(),
          );
          return sharedPages;
        },
        (failure) {
          Log.error('load shared pages failed: $failure');
          _sharedError = failure.msg;
          return <SharedPage>[];
        },
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _sharedPages = pages;
        _isLoadingShared = false;
      });
    } catch (e) {
      Log.error('load shared pages exception: $e');
      if (!mounted) {
        return;
      }
      setState(() {
        _sharedPages = const [];
        _isLoadingShared = false;
        _sharedError = '加载失败';
      });
    }
  }

  Future<void> _loadPublishedViews() async {
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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: FlowyText(
                  '我发布的网站',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
          ),
        _buildPublishedListBody(),
      ],
    );
  }

  Widget _buildSharedHeader() {
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
              color: Colors.grey[600],
            ),
          ),
          Expanded(
            flex: 3,
            child: FlowyText(
              '时间',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
          Expanded(
            flex: 1,
            child: FlowyText(
              '访问权限',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
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
    if (_sharedPages.isEmpty) {
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
        for (int index = 0; index < _sharedPages.length; index++) ...[
          _buildSharedListItem(_sharedPages[index]),
          if (index != _sharedPages.length - 1)
            Divider(height: 1, color: Colors.grey[200]),
        ],
      ],
    );
  }

  Widget _buildSharedListItem(SharedPage page) {
    final view = page.view;
    final title = view.name.isNotEmpty ? view.name : '无标题';
    final shareTime = _formatShareTime(view.createTime.toInt());
    final accessLabel = _mapAccessLevel(page.accessLevel);

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
              color: Colors.black87,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 3,
            child: FlowyText(
              shareTime,
              fontSize: 14,
              fontWeight: FontWeight.normal,
              color: Colors.black87,
            ),
          ),
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FlowyText.small(
                  accessLabel,
                  color: Colors.grey[600],
                ),
                TextButton(
                  onPressed: () {
                    Log.debug('查看邀请成员: ${view.id}');
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

  String _mapAccessLevel(ShareAccessLevel level) {
    switch (level) {
      case ShareAccessLevel.readOnly:
        return '仅查看';
      case ShareAccessLevel.readAndComment:
        return '可评论';
      case ShareAccessLevel.readAndWrite:
        return '可编辑';
      case ShareAccessLevel.fullAccess:
        return '完全访问';
    }
  }

  String _formatShareTime(int secondsSinceEpoch) {
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
    final String publishUrl = ShareConstants.buildPublishUrl(
      nameSpace: item.info.namespace,
      publishName: item.info.publishName,
    );

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
                        color: Colors.black87,
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
              color: Colors.black87,
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

  String _formatPublishTime(int secondsSinceEpoch) {
    // 后端时间单位是秒
    final dt =
        DateTime.fromMillisecondsSinceEpoch(secondsSinceEpoch * 1000, isUtc: true)
            .toLocal();
    final two = (int v) => v.toString().padLeft(2, '0');
    return '${dt.year}年${dt.month}月${dt.day}日 ${two(dt.hour)}:${two(dt.minute)}';
  }
}

// 旧的占位模型已移除，改为直接使用 PublishInfoViewPB




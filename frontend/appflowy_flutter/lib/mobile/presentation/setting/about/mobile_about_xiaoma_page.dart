import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/base/app_bar/mobile_app_bar.dart';
import 'package:appflowy/mobile/presentation/setting/widgets/mobile_setting_group_widget.dart';
import 'package:appflowy/mobile/presentation/setting/widgets/mobile_setting_item_widget.dart';
import 'package:appflowy/mobile/presentation/setting/widgets/mobile_setting_trailing.dart';
import 'package:appflowy/startup/tasks/device_info_task.dart';
import 'package:appflowy/user/presentation/screens/legal_document_screen.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class MobileAboutXiaomaPage extends StatelessWidget {
  const MobileAboutXiaomaPage({super.key});

  static const routeName = '/settings/about-xiaoma';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MobileAppBar(
        title: '关于小马',
        showBackButton: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 24),
              // Logo
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    'assets/images/about_logo.png',
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // 应用名称
          Text(
            "小马笔记",
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
              const SizedBox(height: 32),
              // 功能列表
              MobileSettingGroup(
                groupTitle: '',
                wrapInCard: true,
                showDivider: false,
                showItemDivider: false,
                settingItemList: [
                  MobileSettingItem(
                    name: '订阅详情',
                    trailing: const MobileSettingTrailing(
                      text: '',
                      showArrow: true,
                    ),
                    onTap: () => _showSubscriptionDetailsDialog(context),
                  ),
                  MobileSettingItem(
                    name: '法律条款',
                    trailing: const MobileSettingTrailing(
                      text: '',
                      showArrow: true,
                    ),
                    onTap: () => _showLegalTermsDialog(context),
                  ),
                  MobileSettingItem(
                    name: '版本更新',
                    trailing: MobileSettingTrailing(
                      text: 'V${ApplicationInfo.applicationVersion}',
                      showArrow: false,
                    ),
                    onTap: () {},
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSubscriptionDetailsDialog(BuildContext context) {
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题栏
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '订阅详情',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 16),
              Text(
                '支付',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '确认购买后，你的 iTunes 账户将会进行付款。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '付费账户在当前订购周期结束时将自动续订，你的iTunes 账户会再一次进行付款。同时，你可以在当前付费周期结束前至少 24 个小时取消自动续订。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '订购后，你随时可以在 AppleID 账户设置中管理或者关闭自动续订。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  void _showLegalTermsDialog(BuildContext context) {
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题栏
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '法律条款',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),
              _buildLegalMenuItem(
                context: context,
                ctx: ctx,
                title: '版权声明',
                onTap: () {
                  Navigator.pop(ctx);
                  _navigateToCopyrightStatement(context);
                },
              ),
              _buildLegalMenuItem(
                context: context,
                ctx: ctx,
                title: '服务条款',
                onTap: () {
                  Navigator.pop(ctx);
                  _navigateToServiceTerms(context);
                },
              ),
              _buildLegalMenuItem(
                context: context,
                ctx: ctx,
                title: '隐私条款',
                onTap: () {
                  Navigator.pop(ctx);
                  _navigateToPrivacyPolicy(context);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLegalMenuItem({
    required BuildContext context,
    required BuildContext ctx,
    required String title,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: theme.iconTheme.color?.withOpacity(0.6),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToCopyrightStatement(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => LegalDocumentScreen(
          title: LocaleKeys.legal_copyrightStatement.tr(),
          content: LocaleKeys.legal_copyrightStatementContent.tr(),
        ),
      ),
    );
  }

  void _navigateToServiceTerms(BuildContext context) {
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseWebDomain = cloudEnv.appflowyCloudConfig.base_web_domain;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => LegalDocumentScreen(
            title: LocaleKeys.legal_serviceTerms.tr(),
            url: "$baseWebDomain/agreement",
          ),
        ),
      );
    } catch (e) {
      // 如果获取环境配置失败，使用默认 URL
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => LegalDocumentScreen(
            title: LocaleKeys.legal_serviceTerms.tr(),
            content: '服务条款内容加载失败',
          ),
        ),
      );
    }
  }

  void _navigateToPrivacyPolicy(BuildContext context) {
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseWebDomain = cloudEnv.appflowyCloudConfig.base_web_domain;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => LegalDocumentScreen(
            title: LocaleKeys.legal_privacyPolicy.tr(),
            url: "$baseWebDomain/privacy",
          ),
        ),
      );
    } catch (e) {
      // 如果获取环境配置失败，使用默认 URL
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => LegalDocumentScreen(
            title: LocaleKeys.legal_privacyPolicy.tr(),
            content: '隐私条款内容加载失败',
          ),
        ),
      );
    }
  }
}

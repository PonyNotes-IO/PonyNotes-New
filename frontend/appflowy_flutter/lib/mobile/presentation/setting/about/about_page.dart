import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/base/app_bar/mobile_app_bar.dart';
import 'package:appflowy/startup/tasks/device_info_task.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/feature_flags/mobile_feature_flag_screen.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const routeName = '/settings/about';

  @override
  Widget build(BuildContext context) {
    return const _AboutPageContent();
  }
}

class _AboutPageContent extends StatelessWidget {
  const _AboutPageContent();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MobileAppBar(
        title: '关于',
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '版本信息',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.secondary,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                '${ApplicationInfo.applicationVersion} (${ApplicationInfo.buildNumber})',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              if (kDebugMode) ...[
                ListTile(
                  title: Text(LocaleKeys.settings_menu_featureFlags.tr()),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(FeatureFlagScreen.routeName),
                ),
                const SizedBox(height: 16),
              ],
              Center(
                child: Column(
                  children: [
                    const FlutterLogo(size: 48),
                    const SizedBox(height: 8),
                    Text(
                      'PonyNotes',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'Powered by AppFlowy',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

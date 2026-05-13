import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/features/settings/data/repositories/rust_settings_repository_impl.dart';
import 'package:appflowy/features/settings/logic/data_location_bloc.dart';
import 'package:appflowy/features/settings/logic/data_location_event.dart';
import 'package:appflowy/features/settings/logic/data_location_state.dart';
import 'package:appflowy/mobile/presentation/setting/widgets/mobile_setting_group_widget.dart';
import 'package:appflowy/mobile/presentation/setting/widgets/mobile_setting_item_widget.dart';
import 'package:appflowy/mobile/presentation/setting/widgets/mobile_setting_trailing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class StorageSettingGroup extends StatelessWidget {
  const StorageSettingGroup({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<DataLocationBloc>(
      create: (_) => DataLocationBloc(
        repository: const RustSettingsRepositoryImpl(),
      )..add(DataLocationEvent.initial()),
      child: BlocBuilder<DataLocationBloc, DataLocationState>(
        builder: (context, state) {
          final path = state.userDataLocation?.path;
          return MobileSettingGroup(
            groupTitle: '存储设置',
            settingItemList: [
              MobileSettingItem(
                name: '存储路径',
                trailing: MobileSettingTrailing(
                  text: path == null
                      ? '...'
                      : (path.length > 20
                          ? '...${path.substring(path.length - 20)}'
                          : path),
                  showArrow: false,
                ),
                onTap: () => _showStoragePathDialog(context, path),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showStoragePathDialog(BuildContext context, String? path) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('存储路径'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              path ?? '...',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text(
              '点击打开文件夹以查看存储位置',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.secondary,
                  ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          if (path != null)
            TextButton(
              onPressed: () {
                afLaunchUri(Uri.file(path));
                Navigator.pop(context);
              },
              child: const Text('打开文件夹'),
            ),
        ],
      ),
    );
  }
}

import 'dart:async' show unawaited;

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/features/settings/data/repositories/rust_settings_repository_impl.dart';
import 'package:appflowy/features/settings/logic/data_location_bloc.dart';
import 'package:appflowy/features/settings/logic/data_location_event.dart';
import 'package:appflowy/features/settings/logic/data_location_state.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/mobile/presentation/setting/widgets/mobile_setting_group_widget.dart';
import 'package:appflowy/mobile/presentation/setting/widgets/mobile_setting_item_widget.dart';
import 'package:appflowy/mobile/presentation/setting/widgets/mobile_setting_trailing.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
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
      child: BlocConsumer<DataLocationBloc, DataLocationState>(
        listenWhen: (previous, current) =>
            previous.userDataLocation != null &&
            previous.userDataLocation != current.userDataLocation,
        listener: (context, state) {
          unawaited(runAppFlowy(isAnon: true));
        },
        builder: (context, state) {
          final path = state.userDataLocation?.path;
          return MobileSettingGroup(
            groupTitle: '存储设置',
            wrapInCard: true,
            showDivider: false,
            showItemDivider: false,
            settingItemList: [
              MobileSettingItem(
                name: '存储路径',
                trailing: MobileSettingTrailing(
                  text: '',
                ),
                onTap: () => _showStoragePathBottomSheet(context, state),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showStoragePathBottomSheet(
    BuildContext context,
    DataLocationState state,
  ) {
    final path = state.userDataLocation?.path;
    final theme = Theme.of(context);
    final afTheme = AppFlowyTheme.of(context);

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
                    '本地默认存储路径',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: theme.colorScheme.onSurface),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // 存储路径
              Text(
                '当前路径',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: afTheme.surfaceColorScheme.layer01,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  path ?? '加载中...',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // 按钮区域
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: path != null
                          ? () async {
                              // Close the sheet before handing the directory to
                              // the platform so a failure toast is visible.
                              Navigator.of(ctx).pop();
                              await afLaunchUri(
                                Uri.file(path),
                                context: context,
                              );
                            }
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color:
                              theme.colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '打开文件夹',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: path != null
                          ? () async {
                              final newPath = await getIt<FilePickerService>()
                                  .getDirectoryPath();
                              if (!context.mounted ||
                                  !ctx.mounted ||
                                  newPath == null ||
                                  newPath == path) {
                                return;
                              }
                              Navigator.pop(ctx);
                              _showConfirmDialog(context, newPath);
                            }
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color:
                              theme.colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '修改路径',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  void _showConfirmDialog(BuildContext context, String newPath) {
    final theme = AppFlowyTheme.of(context);
    showDialog(
      context: context,
      barrierColor: theme.surfaceColorScheme.overlay,
      builder: (ctx) => AFModal(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AFModalHeader(
              leading: const Text('确认修改存储路径'),
              trailing: [
                AFGhostButton.normal(
                  onTap: () => Navigator.of(ctx).pop(),
                  padding: EdgeInsets.all(theme.spacing.xs),
                  builder: (context, isHovering, disabled) {
                    return FlowySvg(
                      FlowySvgs.toast_close_s,
                      size: const Size.square(20),
                    );
                  },
                ),
              ],
            ),
            AFModalBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '您确定要将存储路径修改为：',
                    style: theme.textStyle.body.standard(
                      color: theme.textColorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.surfaceColorScheme.layer01,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      newPath,
                      style: theme.textStyle.caption.standard(
                        color: theme.textColorScheme.secondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '这将会移动您的数据到新位置。',
                    style: theme.textStyle.body.standard(
                      color: theme.textColorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            AFModalFooter(
              trailing: [
                AFOutlinedTextButton.normal(
                  text: '取消',
                  onTap: () => Navigator.of(ctx).pop(),
                ),
                const SizedBox(width: 8),
                AFFilledTextButton.primary(
                  text: '确认',
                  onTap: () {
                    context
                        .read<DataLocationBloc>()
                        .add(DataLocationEvent.setCustomPath(newPath));
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

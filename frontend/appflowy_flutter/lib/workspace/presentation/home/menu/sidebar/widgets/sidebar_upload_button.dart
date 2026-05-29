import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:flowy_svg/flowy_svg.dart';
import 'package:flutter/material.dart';
import 'package:appflowy_ui/appflowy_ui.dart';

class SidebarUploadButton extends StatefulWidget {
  const SidebarUploadButton({
    super.key,
    this.isHover = false,
    this.useHighContrastForeground = false,
    this.foregroundColorOverride,
    this.onBeforeAction,
    this.buttonSize = 28.0,
    this.iconSize = 24.0,
  });

  final bool isHover;
  final bool useHighContrastForeground;
  final Color? foregroundColorOverride;
  final VoidCallback? onBeforeAction;
  final double buttonSize;
  final double iconSize;

  @override
  State<SidebarUploadButton> createState() => _SidebarUploadButtonState();
}

class _SidebarUploadButtonState extends State<SidebarUploadButton> {
  @override
  Widget build(BuildContext context) {
    return _buildUploadIcon(
      context,
      () {
        widget.onBeforeAction?.call();
        _openImportPage(context);
      },
    );
  }

  void _openImportPage(BuildContext context) {
    try {
      // 创建导入页面插件
      final importPagePlugin = makePlugin(
        pluginType: PluginType.importPage,
      );

      // 在新标签页中打开导入页面
      getIt<TabsBloc>().add(
        TabsEvent.openPlugin(
          plugin: importPagePlugin,
        ),
      );
    } catch (e) {
      _showMessage('打开导入页面时发生错误: $e');
    }
  }

  void _showMessage(String message) {
    showToastNotification(message: message);
  }

  Widget _buildUploadIcon(
    BuildContext context,
    VoidCallback onTap,
  ) {
    return SizedBox.square(
      dimension: widget.buttonSize,
      child: FlowyButton(
        useIntrinsicWidth: true,
        margin: EdgeInsets.zero,
        text: SvgPicture.asset(
          'assets/images/icons/sidebar_upload_custom.svg',
          width: widget.iconSize,
          height: widget.iconSize,
          colorFilter: widget.foregroundColorOverride != null
              ? ColorFilter.mode(
                  widget.foregroundColorOverride!,
                  BlendMode.srcIn,
                )
              : widget.useHighContrastForeground
                  ? ColorFilter.mode(
                      Theme.of(context).colorScheme.onSurface,
                      BlendMode.srcIn,
                    )
                  : widget.isHover
                      ? ColorFilter.mode(
                          Colors.white,
                          BlendMode.srcIn,
                        )
                      : null,
        ),
        onTap: onTap,
      ),
    );
  }
}

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:flutter/material.dart';
import 'package:appflowy_ui/appflowy_ui.dart';

class SidebarUploadButton extends StatefulWidget {
  const SidebarUploadButton({
    super.key,
    this.isHover = false,
  });

  final bool isHover;

  @override
  State<SidebarUploadButton> createState() => _SidebarUploadButtonState();
}

class _SidebarUploadButtonState extends State<SidebarUploadButton> {
  @override
  Widget build(BuildContext context) {
    return _buildUploadIcon(
      context,
      () => _openImportPage(context),
    );
  }

  void _openImportPage(BuildContext context) {
    try {
      // 创建导入页面插件
      final importPagePlugin = makePlugin(
        pluginType: PluginType.importPage,
        data: null,
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
      dimension: 28.0,
      child: FlowyButton(
        useIntrinsicWidth: true,
        margin: EdgeInsets.zero,
        text: FlowySvg(
          FlowySvgs.icon_upload_s,
          color:
              widget.isHover ? Theme.of(context).colorScheme.onSurface : null,
          opacity: 0.7,
        ),
        onTap: onTap,
      ),
    );
  }
}

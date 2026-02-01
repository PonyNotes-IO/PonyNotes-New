import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_action_type.dart';
import 'package:appflowy_backend/log.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:get_it/get_it.dart';
import 'package:flutter/material.dart';

/// 白板专用的导出操作组件
class WhiteboardExportAction extends StatelessWidget {
  const WhiteboardExportAction({
    super.key,
    required this.view,
  });

  final ViewPB view;

  @override
  Widget build(BuildContext context) {
    return AppFlowyPopover(
      direction: PopoverDirection.leftWithTopAligned,
      constraints: const BoxConstraints(
        maxWidth: 220,
        maxHeight: 180,
      ),
      margin: const EdgeInsets.symmetric(
        horizontal: 14.0,
        vertical: 12.0,
      ),
      clickHandler: PopoverClickHandler.gestureDetector,
      offset: const Offset(-10, 0),
      popupBuilder: (_) => _buildExportMenu(context),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(vertical: 2.0),
        child: FlowyIconTextButton(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          leftIconBuilder: (_) => const Icon(
            Icons.file_download_outlined,
            size: 16,
          ),
          iconPadding: 10.0,
          textBuilder: (_) => FlowyText.regular(
            '导出'.tr(),
            fontSize: 14.0,
            lineHeight: 1.0,
            figmaLineHeight: 18.0,
          ),
        ),
      ),
    );
  }

  Widget _buildExportMenu(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildExportOption(
          context,
          label: '导出ponynotes文件',
          icon: Icons.save_alt,
          onTap: () => _exportAsPonynotes(context),
        ),
        const VSpace(4),
        _buildExportOption(
          context,
          label: '导出为 PNG 图片',
          icon: Icons.image,
          onTap: () => _exportAsPng(context),
        ),
        const VSpace(4),
        _buildExportOption(
          context,
          label: '导出为 SVG 图片',
          icon: Icons.broken_image,
          onTap: () => _exportAsSvg(context),
        ),
      ],
    );
  }

  Widget _buildExportOption(
    BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: FlowyButton(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        onTap: onTap,
        leftIcon: Icon(
          icon,
          size: 16,
          color: Theme.of(context).iconTheme.color,
        ),
        iconPadding: 10.0,
        text: FlowyText.regular(
          label,
          fontSize: 14.0,
          lineHeight: 1.0,
          figmaLineHeight: 18.0,
        ),
      ),
    );
  }

  Future<void> _exportAsPonynotes(BuildContext context) async {
    Log.info('[WhiteboardExport] 导出为 ponynotes 格式');
    // 发送导出事件
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('导出功能需要通过 WebView 实现'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _exportAsPng(BuildContext context) async {
    Log.info('[WhiteboardExport] 导出为 PNG');
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('导出 PNG 功能需要通过 WebView 实现'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _exportAsSvg(BuildContext context) async {
    Log.info('[WhiteboardExport] 导出为 SVG');
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('导出 SVG 功能需要通过 WebView 实现'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

/// 白板专用的导入操作组件
class WhiteboardImportAction extends StatelessWidget {
  const WhiteboardImportAction({
    super.key,
    required this.view,
  });

  final ViewPB view;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: FlowyButton(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        onTap: () => _importWhiteboard(context),
        leftIcon: Icon(
          Icons.file_upload_outlined,
          size: 16,
          color: Theme.of(context).iconTheme.color,
        ),
        iconPadding: 10.0,
        text: FlowyText.regular(
          '导入 Excalidraw 文件'.tr(),
          fontSize: 14.0,
          lineHeight: 1.0,
          figmaLineHeight: 18.0,
        ),
      ),
    );
  }

  Future<void> _importWhiteboard(BuildContext context) async {
    Log.info('[WhiteboardImport] 开始导入 Excalidraw 文件');

    try {
      final filePicker = GetIt.instance<FilePickerService>();
      final result = await filePicker.pickFiles(
        dialogTitle: '选择 Excalidraw 文件',
        type: FileType.custom,
        allowedExtensions: ['excalidraw', 'json'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        Log.info('[WhiteboardImport] 用户取消选择');
        return;
      }

      final filePath = result.files.first.path;
      if (filePath == null) {
        _showError(context, '导入失败：无法获取文件路径');
        return;
      }

      Log.info('[WhiteboardImport] 选择文件: $filePath');

      // 发送导入事件
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('导入功能需要通过 WebView 实现'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e, stackTrace) {
      Log.error('[WhiteboardImport] 导入失败: $e');
      Log.error('[WhiteboardImport] 堆栈: $stackTrace');
      _showError(context, '导入失败：$e');
    }
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

/// 检查视图是否为白板类型
bool isWhiteboardView(ViewPB view) {
  return view.layout == ViewLayoutPB.Whiteboard;
}


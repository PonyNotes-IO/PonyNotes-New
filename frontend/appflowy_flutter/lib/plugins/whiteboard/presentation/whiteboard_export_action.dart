import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_action_type.dart';
import 'package:appflowy_backend/log.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:get_it/get_it.dart';
import 'package:flutter/material.dart';

/// 白板导出控制器 - 用于在不同组件间协调导出操作
class WhiteboardExportController {
  final String viewId;
  final Function(String format) exportCallback;

  WhiteboardExportController({
    required this.viewId,
    required this.exportCallback,
  });

  void export(String format) {
    exportCallback(format);
  }
}

/// 白板导入控制器 - 用于在不同组件间协调导入操作
class WhiteboardImportController {
  final String viewId;
  final Function(String filePath) importCallback;

  WhiteboardImportController({
    required this.viewId,
    required this.importCallback,
  });

  void importFile(String filePath) {
    importCallback(filePath);
  }
}

/// 白板专用的导出操作组件
/// 通过 GetIt 获取当前白板的导出控制器来执行实际的 WebView 导出操作
class WhiteboardExportAction extends StatefulWidget {
  const WhiteboardExportAction({
    super.key,
    required this.view,
    this.onExport,
  });

  final ViewPB view;
  final void Function(String format)? onExport;

  @override
  State<WhiteboardExportAction> createState() => _WhiteboardExportActionState();
}

class _WhiteboardExportActionState extends State<WhiteboardExportAction> {
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
    _performExport(context, 'ponynotes');
    _closePopover(context);
  }

  Future<void> _exportAsPng(BuildContext context) async {
    Log.info('[WhiteboardExport] 导出为 PNG');
    _performExport(context, 'png');
    _closePopover(context);
  }

  Future<void> _exportAsSvg(BuildContext context) async {
    Log.info('[WhiteboardExport] 导出为 SVG');
    _performExport(context, 'svg');
    _closePopover(context);
  }

  void _performExport(BuildContext context, String format) {
    // 首先尝试使用回调
    widget.onExport?.call(format);

    // 尝试从 GetIt 获取导出控制器
    try {
      final getIt = GetIt.instance;
      if (getIt.isRegistered<WhiteboardExportController>(
          instanceName: '${widget.view.id}_export')) {
        final controller =
            getIt.get<WhiteboardExportController>(instanceName: '${widget.view.id}_export');
        controller.export(format);
        Log.info('[WhiteboardExport] 通过 GetIt 调用导出: $format');
        return;
      }
    } catch (e) {
      Log.warn('[WhiteboardExport] GetIt 中未找到导出控制器: $e');
    }

    // 如果都不可用，显示提示
    if (widget.onExport == null) {
      Log.warn('[WhiteboardExport] 无法执行导出: 白板视图可能未打开');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先打开白板视图后再导出'),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _closePopover(BuildContext context) {
    PopoverContainer.maybeOf(context)?.close();
  }
}

/// 白板专用的导入操作组件
/// 通过 GetIt 获取当前白板的导入控制器来执行实际的 WebView 导入操作
class WhiteboardImportAction extends StatefulWidget {
  const WhiteboardImportAction({
    super.key,
    required this.view,
  });

  final ViewPB view;

  @override
  State<WhiteboardImportAction> createState() => _WhiteboardImportActionState();
}

class _WhiteboardImportActionState extends State<WhiteboardImportAction> {
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
          '导入 ponynotes 源文件'.tr(),
          fontSize: 14.0,
          lineHeight: 1.0,
          figmaLineHeight: 18.0,
        ),
      ),
    );
  }

  Future<void> _importWhiteboard(BuildContext context) async {
    Log.info('[WhiteboardImport] 开始导入 ponynotes 源文件');

    try {
      final filePicker = GetIt.instance<FilePickerService>();
      final result = await filePicker.pickFiles(
        dialogTitle: '选择 ponynotes 源文件',
        type: FileType.custom,
        allowedExtensions: ['ponynotes', 'excalidraw', 'json'],
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

      // 通过 GetIt 获取导入控制器来执行导入
      _performImport(context, filePath);
    } catch (e, stackTrace) {
      Log.error('[WhiteboardImport] 导入失败: $e');
      Log.error('[WhiteboardImport] 堆栈: $stackTrace');
      _showError(context, '导入失败：$e');
    }
  }

  void _performImport(BuildContext context, String filePath) {
    // 尝试从 GetIt 获取导入控制器
    try {
      final getIt = GetIt.instance;
      if (getIt.isRegistered<WhiteboardImportController>(
          instanceName: '${widget.view.id}_import')) {
        final controller =
            getIt.get<WhiteboardImportController>(instanceName: '${widget.view.id}_import');
        controller.importFile(filePath);
        Log.info('[WhiteboardImport] 通过 GetIt 调用导入');
        return;
      }
    } catch (e) {
      Log.warn('[WhiteboardImport] GetIt 中未找到导入控制器: $e');
    }

    // 如果不可用，显示提示
    Log.warn('[WhiteboardImport] 无法执行导入: 白板视图可能未打开');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('请先打开白板视图后再导入'),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.orange,
      ),
    );
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


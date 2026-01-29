import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/plugins/handwriting_saber/application/handwriting_saber_data_service.dart';
import 'package:appflowy/plugins/handwriting_saber/services/editor_exporter.dart';
import 'package:appflowy/plugins/handwriting_saber/third_party/saber_core/data/editor/editor_core_info.dart';
import 'package:appflowy/plugins/handwriting_saber/third_party/saber_core/data/editor/page.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_action_type.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:archive/archive_io.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

/// 手写笔记专用的导出操作组件
/// 提供 "导出为PDF" 和 "导出为源文件(.ponynhw)" 选项
class HandwritingExportAction extends StatelessWidget {
  const HandwritingExportAction({
    super.key,
    required this.view,
  });

  final ViewPB view;
  
  /// .ponynhw 文件扩展名
  static const String ponynhwExtension = '.ponynhw';
  
  /// .ponynhw 文件格式版本
  static const int ponynhwVersion = 1;

  @override
  Widget build(BuildContext context) {
    return AppFlowyPopover(
      direction: PopoverDirection.leftWithTopAligned,
      constraints: const BoxConstraints(
        maxWidth: 220,
        maxHeight: 120,
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
          textBuilder: (_) => const FlowyText.regular(
            '导出',
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
          label: '导出为源文件(.ponynhw)',
          icon: Icons.save_alt,
          onTap: () => _exportAsPonynhw(context),
        ),
        const VSpace(4),
        _buildExportOption(
          context,
          label: '导出为 PDF',
          icon: Icons.picture_as_pdf,
          onTap: () => _exportAsPdf(context),
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

  /// 导出为 .ponynhw 源文件（类似Saber的.sba格式）
  Future<void> _exportAsPonynhw(BuildContext context) async {
    try {
      Log.info('[HandwritingExport] 开始导出为 .ponynhw 格式...');
      
      // 加载手写笔记数据
      final dataService = HandwritingSaberDataService();
      final sbnData = await dataService.loadHandwritingSaberData(view.id);
      
      if (sbnData.isEmpty) {
        Log.error('[HandwritingExport] 手写笔记数据为空');
        if (context.mounted) {
          _showError(context, '导出失败：手写笔记内容为空');
        }
        return;
      }
      
      // 创建 .ponynhw 压缩包
      Log.info('[HandwritingExport] 创建 .ponynhw 压缩包，数据大小: ${sbnData.length} 字节');
      final ponynhwBytes = await _createPonynhwArchive(sbnData);
      
      if (ponynhwBytes.isEmpty) {
        Log.error('[HandwritingExport] 创建压缩包失败');
        if (context.mounted) {
          _showError(context, '导出失败：无法创建压缩包');
        }
        return;
      }
      
      // 保存文件
      final fileName = '${view.name.isNotEmpty ? view.name : "手写笔记"}$ponynhwExtension';
      final filePicker = GetIt.instance<FilePickerService>();
      
      final savePath = await filePicker.saveFile(
        dialogTitle: '保存手写笔记源文件',
        fileName: fileName,
        type: FileType.any,
      );
      
      if (savePath == null) {
        Log.info('[HandwritingExport] 用户取消保存');
        return;
      }
      
      // 确保文件名有正确的扩展名
      final finalPath = savePath.endsWith(ponynhwExtension) 
          ? savePath 
          : '$savePath$ponynhwExtension';
      
      final file = File(finalPath);
      await file.writeAsBytes(ponynhwBytes);
      
      Log.info('[HandwritingExport] .ponynhw 文件保存成功: $finalPath');
      
      if (context.mounted) {
        _showSuccess(context, '手写笔记源文件已保存');
      }
    } catch (e, stackTrace) {
      Log.error('[HandwritingExport] 导出 .ponynhw 失败: $e');
      Log.error('[HandwritingExport] 堆栈: $stackTrace');
      if (context.mounted) {
        _showError(context, '导出失败：$e');
      }
    }
  }
  
  /// 创建 .ponynhw 压缩包
  /// 格式说明：
  /// - main.sbn2: 主数据文件（与内部存储格式相同）
  /// - meta.json: 元数据文件（包含版本、名称等信息）
  Future<List<int>> _createPonynhwArchive(List<int> sbnData) async {
    final archive = Archive();
    
    // 添加主数据文件
    archive.addFile(ArchiveFile('main.sbn2', sbnData.length, sbnData));
    
    // 创建元数据
    final meta = {
      'version': ponynhwVersion,
      'format': 'ponynhw',
      'name': view.name,
      'createdAt': DateTime.now().toIso8601String(),
      'exportedFrom': 'PonyNotes',
    };
    final metaJson = jsonEncode(meta);
    final metaBytes = utf8.encode(metaJson);
    archive.addFile(ArchiveFile('meta.json', metaBytes.length, metaBytes));
    
    // 压缩并返回
    final encoded = ZipEncoder().encode(archive);
    return encoded ?? [];
  }

  /// 导出为 PDF
  Future<void> _exportAsPdf(BuildContext context) async {
    try {
      Log.info('[HandwritingExport] 开始导出为 PDF...');
      
      // 加载手写笔记数据
      final dataService = HandwritingSaberDataService();
      final sbnData = await dataService.loadHandwritingSaberData(view.id);
      
      if (sbnData.isEmpty) {
        Log.error('[HandwritingExport] 手写笔记数据为空');
        if (context.mounted) {
          _showError(context, '导出失败：手写笔记内容为空');
        }
        return;
      }
      
      // 解析 EditorCoreInfo
      Log.info('[HandwritingExport] 解析手写笔记数据...');
      final coreInfo = _parseEditorCoreInfo(sbnData);
      
      if (coreInfo.pages.isEmpty) {
        Log.error('[HandwritingExport] 手写笔记没有页面');
        if (context.mounted) {
          _showError(context, '导出失败：手写笔记没有页面');
        }
        return;
      }
      
      // 显示加载提示
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('正在生成 PDF...'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      
      // 使用 EditorExporter 生成 PDF
      Log.info('[HandwritingExport] 生成 PDF，共 ${coreInfo.pages.length} 页');
      final pdf = await EditorExporter.generatePdf(coreInfo, context);
      final pdfBytes = await pdf.save();
      
      Log.info('[HandwritingExport] PDF 生成成功，大小: ${pdfBytes.length} 字节');
      
      // 保存文件
      final fileName = '${view.name.isNotEmpty ? view.name : "手写笔记"}.pdf';
      final filePicker = GetIt.instance<FilePickerService>();
      
      final savePath = await filePicker.saveFile(
        dialogTitle: '保存 PDF 文件',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      
      if (savePath == null) {
        Log.info('[HandwritingExport] 用户取消保存');
        return;
      }
      
      final finalPath = savePath.endsWith('.pdf') ? savePath : '$savePath.pdf';
      final file = File(finalPath);
      await file.writeAsBytes(pdfBytes);
      
      Log.info('[HandwritingExport] PDF 文件保存成功: $finalPath');
      
      if (context.mounted) {
        _showSuccess(context, 'PDF 文件已保存');
      }
    } catch (e, stackTrace) {
      Log.error('[HandwritingExport] 导出 PDF 失败: $e');
      Log.error('[HandwritingExport] 堆栈: $stackTrace');
      if (context.mounted) {
        _showError(context, '导出失败：$e');
      }
    }
  }
  
  /// 解析 EditorCoreInfo 数据
  EditorCoreInfo _parseEditorCoreInfo(List<int> sbnData) {
    try {
      // 尝试解析为 JSON 格式（当前 PoC 阶段使用 JSON）
      final jsonString = utf8.decode(sbnData);
      return EditorCoreInfo.fromJsonString(jsonString);
    } catch (e) {
      Log.warn('[HandwritingExport] JSON 解析失败，尝试其他格式: $e');
      // 如果 JSON 解析失败，返回空的 EditorCoreInfo
      return EditorCoreInfo.empty();
    }
  }

  void _showSuccess(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
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

/// 检查视图是否为手写笔记类型
bool isHandwritingNote(ViewPB view) {
  try {
    if (view.extra.isEmpty) return false;
    final extra = jsonDecode(view.extra) as Map<String, dynamic>;
    return extra['view_type'] == 'handwriting_saber';
  } catch (e) {
    return false;
  }
}

/// 手写笔记导入操作组件
/// 提供 "导入源文件(.ponynhw)" 选项
class HandwritingImportAction extends StatelessWidget {
  const HandwritingImportAction({
    super.key,
    required this.view,
    this.onImportSuccess,
  });

  final ViewPB view;
  
  /// 导入成功后的回调
  final VoidCallback? onImportSuccess;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: FlowyButton(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        onTap: () => _importPonynhw(context),
        leftIcon: Icon(
          Icons.file_upload_outlined,
          size: 16,
          color: Theme.of(context).iconTheme.color,
        ),
        iconPadding: 10.0,
        text: const FlowyText.regular(
          '导入源文件(.ponynhw)',
          fontSize: 14.0,
          lineHeight: 1.0,
          figmaLineHeight: 18.0,
        ),
      ),
    );
  }

  /// 导入 .ponynhw 源文件
  Future<void> _importPonynhw(BuildContext context) async {
    try {
      Log.info('[HandwritingImport] 开始导入 .ponynhw 文件...');
      
      // 选择文件
      final filePicker = GetIt.instance<FilePickerService>();
      final result = await filePicker.pickFiles(
        dialogTitle: '选择手写笔记源文件',
        type: FileType.any,
        allowMultiple: false,
      );
      
      if (result == null || result.files.isEmpty) {
        Log.info('[HandwritingImport] 用户取消选择');
        return;
      }
      
      final filePath = result.files.first.path;
      if (filePath == null) {
        if (context.mounted) {
          _showError(context, '导入失败：无法获取文件路径');
        }
        return;
      }
      
      // 检查文件扩展名
      if (!filePath.toLowerCase().endsWith('.ponynhw')) {
        if (context.mounted) {
          _showError(context, '导入失败：请选择 .ponynhw 格式的文件');
        }
        return;
      }
      
      // 读取文件
      final file = File(filePath);
      if (!await file.exists()) {
        if (context.mounted) {
          _showError(context, '导入失败：文件不存在');
        }
        return;
      }
      
      final fileBytes = await file.readAsBytes();
      Log.info('[HandwritingImport] 读取文件成功，大小: ${fileBytes.length} 字节');
      
      // 解压 .ponynhw 文件
      final sbnData = await _extractPonynhwArchive(fileBytes);
      
      if (sbnData == null || sbnData.isEmpty) {
        if (context.mounted) {
          _showError(context, '导入失败：无效的 .ponynhw 文件');
        }
        return;
      }
      
      Log.info('[HandwritingImport] 解压成功，数据大小: ${sbnData.length} 字节');
      
      // 保存到当前视图
      final dataService = HandwritingSaberDataService();
      final success = await dataService.saveHandwritingSaberData(view.id, sbnData);
      
      if (success) {
        Log.info('[HandwritingImport] 导入成功');
        if (context.mounted) {
          _showSuccess(context, '手写笔记导入成功，请刷新页面');
        }
        onImportSuccess?.call();
      } else {
        Log.error('[HandwritingImport] 保存数据失败');
        if (context.mounted) {
          _showError(context, '导入失败：无法保存数据');
        }
      }
    } catch (e, stackTrace) {
      Log.error('[HandwritingImport] 导入失败: $e');
      Log.error('[HandwritingImport] 堆栈: $stackTrace');
      if (context.mounted) {
        _showError(context, '导入失败：$e');
      }
    }
  }
  
  /// 解压 .ponynhw 文件，提取主数据
  Future<List<int>?> _extractPonynhwArchive(List<int> archiveBytes) async {
    try {
      final archive = ZipDecoder().decodeBytes(archiveBytes);
      
      // 查找 main.sbn2 文件
      for (final file in archive) {
        if (file.name == 'main.sbn2') {
          return file.content as List<int>;
        }
      }
      
      Log.warn('[HandwritingImport] 未找到 main.sbn2 文件');
      return null;
    } catch (e) {
      Log.error('[HandwritingImport] 解压失败: $e');
      return null;
    }
  }

  void _showSuccess(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
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

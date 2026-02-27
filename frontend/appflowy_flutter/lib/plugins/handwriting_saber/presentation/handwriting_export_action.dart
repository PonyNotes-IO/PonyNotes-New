import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/plugins/handwriting_saber/application/handwriting_saber_data_service.dart';
import 'package:appflowy/plugins/handwriting_saber/services/editor_exporter.dart';
import 'package:appflowy/plugins/handwriting_saber/third_party/saber_core/data/editor/editor_core_info.dart';
import 'package:appflowy/plugins/handwriting_saber/third_party/saber_core/data/editor/page.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_action_type.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:archive/archive_io.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

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

      final dataService = HandwritingSaberDataService();
      final sbnData = await dataService.loadHandwritingSaberData(view.id);

      if (sbnData.isEmpty) {
        Log.error('[HandwritingExport] 手写笔记数据为空');
        if (context.mounted) {
          _showError(context, '导出失败：手写笔记内容为空');
        }
        return;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('正在准备导出，可能需要下载PDF资源...'),
            duration: Duration(seconds: 3),
          ),
        );
      }

      // 解析 JSON 获取所有 PDF 路径
      final jsonString = utf8.decode(sbnData);
      final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
      final pages = jsonMap['pages'] as List<dynamic>? ?? [];

      // 收集所有唯一的 PDF 路径（可能是URL或本地路径）
      final pdfPathSet = <String>{};
      for (final page in pages) {
        if (page is Map<String, dynamic> && page.containsKey('backgroundImage')) {
          final bg = page['backgroundImage'] as Map<String, dynamic>?;
          if (bg != null) {
            final path = bg['pdfFilePath'] as String?;
            final url = bg['pdfUrl'] as String?;
            if (path != null && path.isNotEmpty) pdfPathSet.add(path);
            if (url != null && url.isNotEmpty) pdfPathSet.add(url);
          }
        }
      }

      Log.info('[HandwritingExport] 找到 ${pdfPathSet.length} 个唯一PDF路径');

      // 下载/读取所有 PDF 并按内容去重
      final Map<String, List<int>> downloadedBytes = {};
      for (final path in pdfPathSet) {
        try {
          List<int>? bytes;
          if (path.startsWith('http')) {
            bytes = await _downloadPdfFromUrl(path);
          } else {
            final file = File(path);
            if (await file.exists()) bytes = await file.readAsBytes();
          }
          if (bytes != null && bytes.isNotEmpty) {
            downloadedBytes[path] = bytes;
          } else {
            Log.warn('[HandwritingExport] PDF 获取失败: $path');
          }
        } catch (e) {
          Log.error('[HandwritingExport] PDF 获取异常: $path, $e');
        }
      }

      // 按内容去重：相同内容的PDF只保留一份
      final Map<String, String> pathToArchiveName = {};
      final Map<String, List<int>> archiveFiles = {};
      int pdfCounter = 0;

      for (final entry in downloadedBytes.entries) {
        String? existingName;
        for (final archiveEntry in archiveFiles.entries) {
          if (archiveEntry.value.length == entry.value.length &&
              _bytesEqual(archiveEntry.value, entry.value)) {
            existingName = archiveEntry.key;
            break;
          }
        }

        if (existingName != null) {
          pathToArchiveName[entry.key] = existingName;
        } else {
          final archiveName = 'pdf_$pdfCounter.pdf';
          pdfCounter++;
          archiveFiles[archiveName] = entry.value;
          pathToArchiveName[entry.key] = archiveName;
          Log.info('[HandwritingExport] 添加PDF资源: $archiveName (${entry.value.length} bytes)');
        }
      }

      Log.info('[HandwritingExport] 去重后共 ${archiveFiles.length} 个PDF文件');

      // 更新 JSON 中的 PDF 路径为归档文件名
      for (final page in pages) {
        if (page is Map<String, dynamic> && page.containsKey('backgroundImage')) {
          final bg = page['backgroundImage'] as Map<String, dynamic>?;
          if (bg != null) {
            final path = bg['pdfFilePath'] as String?;
            final url = bg['pdfUrl'] as String?;
            final archiveName = pathToArchiveName[path] ??
                pathToArchiveName[url];
            if (archiveName != null) {
              bg['pdfFilePath'] = archiveName;
              bg['pdfUrl'] = null;
            }
          }
        }
      }

      final modifiedSbnData = utf8.encode(jsonEncode(jsonMap));

      // 创建 .ponynhw 压缩包
      final ponynhwBytes = _createPonynhwArchive(modifiedSbnData, archiveFiles);

      if (ponynhwBytes.isEmpty) {
        Log.error('[HandwritingExport] 创建压缩包失败');
        if (context.mounted) {
          _showError(context, '导出失败：无法创建压缩包');
        }
        return;
      }

      // 保存文件
      final fileName =
          '${view.name.isNotEmpty ? view.name : "手写笔记"}$ponynhwExtension';
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

  /// 从云端URL下载PDF
  Future<List<int>?> _downloadPdfFromUrl(String url) async {
    try {
      Log.info('[HandwritingExport] 下载PDF: $url');
      final userResult = await UserBackendService.getCurrentUserProfile();
      final rawToken = userResult.fold((u) => u.token, (_) => '');
      final token = _normalizeExportToken(rawToken);

      final response = await http.get(
        Uri.parse(url),
        headers: token.isNotEmpty ? {'Authorization': 'Bearer $token'} : {},
      );

      if (response.statusCode == 200) {
        Log.info('[HandwritingExport] PDF下载成功: ${response.bodyBytes.length} bytes');
        return response.bodyBytes;
      } else {
        Log.error('[HandwritingExport] PDF下载失败: HTTP ${response.statusCode}');
        return null;
      }
    } catch (e) {
      Log.error('[HandwritingExport] PDF下载异常: $e');
      return null;
    }
  }

  static String _normalizeExportToken(String token) {
    if (token.isEmpty) return token;
    if (token.trim().startsWith('{')) {
      try {
        final map = jsonDecode(token);
        if (map is Map && map['access_token'] is String) {
          return map['access_token'] as String;
        }
      } catch (_) {}
    }
    return token;
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 创建 .ponynhw 压缩包
  List<int> _createPonynhwArchive(
      List<int> sbnData, Map<String, List<int>> pdfFiles) {
    final archive = Archive();

    archive.addFile(ArchiveFile('main.sbn2', sbnData.length, sbnData));

    for (final entry in pdfFiles.entries) {
      archive.addFile(
        ArchiveFile('assets/${entry.key}', entry.value.length, entry.value),
      );
    }

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
      final extracted = await _extractPonynhwArchive(fileBytes);

      if (extracted.sbnData.isEmpty) {
        if (context.mounted) {
          _showError(context, '导入失败：无效的 .ponynhw 文件');
        }
        return;
      }

      Log.info(
          '[HandwritingImport] 解压成功，数据大小: ${extracted.sbnData.length} 字节, 资源数量: ${extracted.assets.length}');

      // ✅ 处理 PDF 资源并重定向路径
      var sbnData = extracted.sbnData;
      if (extracted.assets.isNotEmpty) {
        sbnData =
            await _processImportedAssets(extracted.sbnData, extracted.assets);
      }

      // 保存到当前视图
      final dataService = HandwritingSaberDataService();
      final success =
          await dataService.saveHandwritingSaberData(view.id, sbnData);

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

  /// 解压 .ponynhw 文件，提取主数据和资源
  Future<({List<int> sbnData, Map<String, List<int>> assets})>
      _extractPonynhwArchive(List<int> archiveBytes) async {
    final archive = ZipDecoder().decodeBytes(archiveBytes);
    List<int> sbnData = [];
    final assets = <String, List<int>>{};

    for (final file in archive) {
      if (file.name == 'main.sbn2') {
        sbnData = file.content as List<int>;
      } else if (file.name.startsWith('assets/')) {
        final fileName = p.basename(file.name);
        if (fileName.isNotEmpty) {
          assets[fileName] = file.content as List<int>;
        }
      }
    }

    return (sbnData: sbnData, assets: assets);
  }

  /// 处理导入的资源：保存到本地并更新 JSON 路径
  Future<List<int>> _processImportedAssets(
      List<int> sbnData, Map<String, List<int>> assets) async {
    try {
      final jsonString = utf8.decode(sbnData);
      final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;

      if (!jsonMap.containsKey('pages')) return sbnData;

      final pages = jsonMap['pages'] as List<dynamic>;
      bool modified = false;

      // 获取手写笔记数据目录
      final dataService = HandwritingSaberDataService();
      final samplePath =
          await dataService.getHandwritingSaberFilePathForDebug('dummy');
      final targetDir = p.dirname(samplePath);

      // 确保目标目录存在
      final dir = Directory(targetDir);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      // 先将所有资源保存到本地，建立文件名->本地路径的映射
      final Map<String, String> assetToLocalPath = {};
      for (final entry in assets.entries) {
        final newPath = p.join(targetDir, entry.key);
        final file = File(newPath);
        await file.writeAsBytes(entry.value);
        assetToLocalPath[entry.key] = newPath;
        Log.info('[HandwritingImport] 已保存资源到本地: $newPath (${entry.value.length} bytes)');
      }

      // 遍历页面查找 PDF 背景并更新路径
      for (final page in pages) {
        if (page is Map<String, dynamic> &&
            page.containsKey('backgroundImage')) {
          final bg = page['backgroundImage'] as Map<String, dynamic>?;
          if (bg == null) continue;

          final oldPath = bg['pdfFilePath'] as String?;
          if (oldPath == null || oldPath.isEmpty) continue;

          // 尝试直接匹配文件名（新格式：pdf_0.pdf 等）
          final fileName = p.basename(oldPath);
          String? localPath = assetToLocalPath[fileName];

          // 如果直接匹配失败，尝试遍历所有资源查找
          if (localPath == null) {
            for (final assetName in assetToLocalPath.keys) {
              if (fileName == assetName || oldPath.endsWith(assetName)) {
                localPath = assetToLocalPath[assetName];
                break;
              }
            }
          }

          if (localPath != null) {
            bg['pdfFilePath'] = localPath;
            bg['pdfUrl'] = null;
            modified = true;
            Log.info('[HandwritingImport] 更新PDF路径: $oldPath -> $localPath');
          } else {
            Log.warn('[HandwritingImport] 未找到匹配的PDF资源: $oldPath');
          }
        }
      }

      return modified ? utf8.encode(jsonEncode(jsonMap)) : sbnData;
    } catch (e) {
      Log.error('[HandwritingImport] 处理资源失败: $e');
      return sbnData;
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

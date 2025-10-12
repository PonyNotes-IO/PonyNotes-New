import 'dart:io';
import 'package:appflowy_backend/protobuf/flowy-database2/file_entities.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/media_entities.pb.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:flowy_infra/uuid.dart';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import 'package:appflowy/startup/startup.dart';

import 'file_library_models.dart';

class FileLibraryService {
  static const String _fileLibraryDir = 'file_library';
  
  /// 获取文件库目录路径
  Future<String> get _fileLibraryPath async {
    final appDataPath = await getIt<ApplicationDataStorage>().getPath();
    return p.join(appDataPath, _fileLibraryDir);
  }

  /// 获取所有文件（只返回真实上传的文件）
  Future<List<FileLibraryItem>> getAllFiles() async {
    final libraryPath = await _fileLibraryPath;
    final directory = Directory(libraryPath);
    
    if (!directory.existsSync()) {
      return []; // 如果目录不存在，返回空列表
    }
    
    final files = <FileLibraryItem>[];
    
    // 扫描文件库目录中的所有文件
    await for (final entity in directory.list()) {
      if (entity is File) {
        final file = await _createFileLibraryItemFromFile(entity);
        if (file != null) {
          files.add(file);
        }
      }
    }
    
    // 按创建时间倒序排列
    files.sort((a, b) => (b.createdAt ?? DateTime.now()).compareTo(a.createdAt ?? DateTime.now()));
    
    return files;
  }

  /// 导入文件到文件库
  Future<FileLibraryItem?> importPdfFile() async {
    // 使用文件选择器选择任意类型文件
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    
    if (result == null || result.files.isEmpty) {
      return null; // 用户取消选择
    }
    
    final platformFile = result.files.first;
    if (platformFile.path == null) {
      throw Exception('无法获取文件路径');
    }
    
    final sourceFile = File(platformFile.path!);
    if (!sourceFile.existsSync()) {
      throw Exception('源文件不存在');
    }
    
    // 确保文件库目录存在
    final libraryPath = await _fileLibraryPath;
    final directory = Directory(libraryPath);
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    
    // 生成UUID作为文件ID
    final fileId = uuid();
    
    // 生成新的文件名（保持原始名称，添加UUID避免冲突）
    final originalName = platformFile.name;
    final extension = p.extension(originalName);
    final nameWithoutExt = p.basenameWithoutExtension(originalName);
    final newFileName = '${nameWithoutExt}_$fileId$extension';
    final targetPath = p.join(libraryPath, newFileName);
    
    // 复制文件到文件库
    final targetFile = await sourceFile.copy(targetPath);
    
    // 创建文件库项目，使用相同的fileId
    final fileItem = await _createFileLibraryItemFromFile(targetFile, originalName: originalName, fileId: fileId);
    
    return fileItem;
  }

  /// 删除文件
  Future<void> deleteFile(String fileId) async {
    final libraryPath = await _fileLibraryPath;
    final directory = Directory(libraryPath);
    
    if (!directory.existsSync()) {
      return;
    }
    
    // 查找并删除对应的文件
    await for (final entity in directory.list()) {
      if (entity is File) {
        final fileName = p.basename(entity.path);
        if (fileName.contains(fileId) || fileId.contains(fileName)) {
          await entity.delete();
          break;
        }
      }
    }
  }

  /// 打开文件
  Future<void> openPdfFile(FileLibraryItem item) async {
    if (item.uploadType == FileUploadTypePB.LocalFile) {
      // 本地文件，直接使用系统默认程序打开
      final file = File(item.url);
      if (file.existsSync()) {
        await afLaunchUrlString(item.url);
      } else {
        throw Exception('文件不存在：${item.url}');
      }
    } else {
      // 网络文件，使用浏览器打开
      await afLaunchUrlString(item.url);
    }
  }

  /// 从文件创建FileLibraryItem
  Future<FileLibraryItem?> _createFileLibraryItemFromFile(
    File file, {
    String? originalName,
    String? fileId,
  }) async {
    try {
      final fileName = originalName ?? p.basename(file.path);
      final extension = p.extension(fileName).toLowerCase();
      final stat = await file.stat();
      
      // 如果没有提供fileId，尝试从文件名中提取
      String id;
      if (fileId != null) {
        id = fileId;
      } else {
        // 从文件名中提取UUID（格式：name_uuid.ext）
        final baseName = p.basenameWithoutExtension(file.path);
        final parts = baseName.split('_');
        if (parts.length >= 2) {
          id = parts.last; // 最后一部分应该是UUID
        } else {
          id = uuid(); // 如果无法提取，生成新的
        }
      }
      
      // 根据扩展名确定文件类型
      MediaFileTypePB fileType;
      switch (extension) {
        // 文档类型
        case '.pdf':
        case '.doc':
        case '.docx':
        case '.ppt':
        case '.pptx':
        case '.xls':
        case '.xlsx':
          fileType = MediaFileTypePB.Document;
          break;
        // 图片类型
        case '.jpg':
        case '.jpeg':
        case '.png':
        case '.gif':
        case '.bmp':
        case '.webp':
        case '.svg':
        case '.ico':
        case '.tiff':
        case '.tif':
          fileType = MediaFileTypePB.Image;
          break;
        // 视频类型
        case '.mp4':
        case '.avi':
        case '.mov':
        case '.wmv':
        case '.flv':
        case '.mkv':
        case '.webm':
        case '.m4v':
        case '.3gp':
          fileType = MediaFileTypePB.Video;
          break;
        // 音频类型
        case '.mp3':
        case '.wav':
        case '.aac':
        case '.flac':
        case '.ogg':
        case '.m4a':
        case '.wma':
        case '.opus':
          fileType = MediaFileTypePB.Audio;
          break;
        // 压缩文件类型
        case '.zip':
        case '.rar':
        case '.7z':
        case '.tar':
        case '.gz':
        case '.bz2':
        case '.xz':
        case '.iso':
          fileType = MediaFileTypePB.Archive;
          break;
        // 文本类型
        case '.txt':
        case '.md':
        case '.json':
        case '.xml':
        case '.csv':
        case '.log':
        case '.rtf':
          fileType = MediaFileTypePB.Text;
          break;
        // 其他类型
        default:
          fileType = MediaFileTypePB.Other;
      }
      
      return FileLibraryItem(
        id: id,
        name: fileName,
        url: file.path, // 使用本地文件路径
        fileType: fileType,
        uploadType: FileUploadTypePB.LocalFile,
        source: '文件库导入',
        createdAt: stat.changed,
        size: stat.size,
      );
    } catch (e) {
      return null; // 如果处理失败，返回null
    }
  }

}


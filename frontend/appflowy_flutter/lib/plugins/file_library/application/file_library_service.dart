import 'dart:io';
import 'dart:async';
import 'package:appflowy_backend/protobuf/flowy-database2/file_entities.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/media_entities.pb.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:flowy_infra/uuid.dart';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:media_kit/media_kit.dart';

import 'file_library_models.dart';
import '../services/baidu_cloud_service.dart';
import '../services/baidu_cloud_config_service.dart';

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

  /// 从百度网盘导入文件
  Future<List<FileLibraryItem>> importFromBaiduCloud() async {
    // 检查配置是否有效
    final configService = BaiduCloudConfigService.instance;
    if (!configService.hasValidConfig) {
      throw Exception('百度网盘配置无效，请检查.env.baidu文件');
    }
    
    // 导入百度网盘服务
    final baiduService = BaiduCloudService();
    
    // 检查是否已授权
    if (!await baiduService.isAuthorized()) {
      throw Exception('请先授权访问百度网盘');
    }
    
    // 文件选择现在在UI层处理，这里直接返回空列表
    // 实际的导入逻辑在 importBaiduCloudFile 方法中
    return [];
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

  /// 根据文件扩展名获取文件类型
  MediaFileTypePB _getFileTypeFromExtension(String extension) {
    final ext = extension.toLowerCase();
    
    // 图片文件
    if (['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.svg', '.ico'].contains(ext)) {
      return MediaFileTypePB.Image;
    }
    
    // 视频文件
    if (['.mp4', '.avi', '.mov', '.wmv', '.flv', '.webm', '.mkv', '.m4v'].contains(ext)) {
      return MediaFileTypePB.Video;
    }
    
    // 音频文件
    if (['.mp3', '.wav', '.flac', '.aac', '.ogg', '.wma', '.m4a'].contains(ext)) {
      return MediaFileTypePB.Audio;
    }
    
    // 文档文件
    if (['.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx'].contains(ext)) {
      return MediaFileTypePB.Document;
    }
    
    // 文本文件
    if (['.txt', '.md', '.json', '.xml', '.csv', '.log'].contains(ext)) {
      return MediaFileTypePB.Text;
    }
    
    // 压缩文件
    if (['.zip', '.rar', '.7z', '.tar', '.gz'].contains(ext)) {
      return MediaFileTypePB.Archive;
    }
    
    // 其他文件
    return MediaFileTypePB.Other;
  }

  /// 获取视频或音频文件的时长（秒）
  /// 使用 media_kit 支持所有平台（包括 Windows）
  Future<int?> _getMediaDuration(File file, MediaFileTypePB fileType) async {
    if (fileType != MediaFileTypePB.Video && fileType != MediaFileTypePB.Audio) {
      return null;
    }

    try {
      // 使用 media_kit 创建播放器
      final player = Player();
      
      try {
        // 打开媒体文件
        await player.open(Media(file.path));
        
        // 等待时长信息加载
        // media_kit 的 duration 是一个 Stream，我们需要等待第一个非零值
        final duration = await player.stream.duration.firstWhere(
          (d) => d.inSeconds > 0,
          orElse: () => Duration.zero,
        ).timeout(
          const Duration(seconds: 10),
          onTimeout: () => Duration.zero,
        );
        
        return duration.inSeconds > 0 ? duration.inSeconds : null;
      } finally {
        // 确保播放器资源被释放
        await player.dispose();
      }
    } catch (e) {
      // 如果无法获取时长，返回 null
      return null;
    }
  }

  /// 从文件创建FileLibraryItem
  Future<FileLibraryItem?> _createFileLibraryItemFromFile(
    File file, {
    String? originalName,
    String? fileId,
    String? source,
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
      
      // 对于视频和音频文件，尝试获取时长
      int? duration;
      if (fileType == MediaFileTypePB.Video || fileType == MediaFileTypePB.Audio) {
        duration = await _getMediaDuration(file, fileType);
      }
      
      return FileLibraryItem(
        id: id,
        name: fileName,
        url: file.path, // 使用本地文件路径
        fileType: fileType,
        uploadType: FileUploadTypePB.LocalFile,
        source: source ?? '文件库导入',
        createdAt: stat.changed,
        size: stat.size,
        duration: duration,
      );
    } catch (e) {
      return null; // 如果处理失败，返回null
    }
  }

  /// 导入百度网盘文件
  Future<FileLibraryItem?> importBaiduCloudFile(BaiduCloudFile baiduFile) async {
    try {
      final baiduService = BaiduCloudService();
      
      // 下载文件到本地
      final downloadUrl = await baiduService.getFileDownloadUrl(baiduFile.fsId);
      if (downloadUrl == null) {
        return null;
      }
      
      final tempFile = File('${Directory.systemTemp.path}/${baiduFile.serverFilename}');
      final localFile = await baiduService.downloadFile(downloadUrl, tempFile.path);
      if (localFile == null) {
        return null;
      }
      
      // 将文件复制到文件库目录
      final fileLibraryPath = await _fileLibraryPath;
      final fileName = baiduFile.serverFilename;
      final targetFile = File('$fileLibraryPath/$fileName');
      
      // 确保目标目录存在
      await targetFile.parent.create(recursive: true);
      
      // 复制文件
      await localFile.copy(targetFile.path);
      
      // 创建FileLibraryItem
      final fileType = _getFileTypeFromExtension(baiduFile.fileExtension);
      int? duration;
      if (fileType == MediaFileTypePB.Video || fileType == MediaFileTypePB.Audio) {
        duration = await _getMediaDuration(targetFile, fileType);
      }
      
      return FileLibraryItem(
        id: baiduFile.fsId,
        name: baiduFile.serverFilename,
        url: targetFile.path,
        fileType: fileType,
        uploadType: FileUploadTypePB.LocalFile,
        source: '百度网盘导入',
        createdAt: DateTime.fromMillisecondsSinceEpoch(baiduFile.serverMtime * 1000),
        size: baiduFile.size,
        duration: duration,
      );
    } catch (e) {
      return null;
    }
  }

}



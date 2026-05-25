/// 百度网盘文件模型
class BaiduCloudFile {
  final String fsId;
  final String name;
  final String displayName;
  final String fileExtension;
  final int size;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final String path;
  final bool isDir;
  final String? thumbnail;

  const BaiduCloudFile({
    required this.fsId,
    required this.name,
    required this.displayName,
    required this.fileExtension,
    required this.size,
    required this.createdAt,
    required this.modifiedAt,
    required this.path,
    required this.isDir,
    this.thumbnail,
  });

  factory BaiduCloudFile.fromJson(Map<String, dynamic> json) {
    return BaiduCloudFile(
      fsId: json['fs_id']?.toString() ?? '',
      name: json['server_filename'] ?? '',
      displayName: json['server_filename'] ?? '',
      fileExtension: _getFileExtension(json['server_filename'] ?? ''),
      size: json['size'] ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['server_ctime'] * 1000),
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(json['server_mtime'] * 1000),
      path: json['path'] ?? '',
      isDir: json['isdir'] == 1,
      thumbnail: json['thumbs']?['url1'],
    );
  }

  static String _getFileExtension(String fileName) {
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot == -1) return '';
    return fileName.substring(lastDot);
  }

  /// 获取格式化的文件大小
  String get fileSize {
    if (size < 1024) return '${size}B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)}KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  /// 是否为目录
  bool get isDirectory => isDir;

  Map<String, dynamic> toJson() {
    return {
      'fs_id': fsId,
      'server_filename': name,
      'size': size,
      'server_ctime': createdAt.millisecondsSinceEpoch ~/ 1000,
      'server_mtime': modifiedAt.millisecondsSinceEpoch ~/ 1000,
      'path': path,
      'isdir': isDir ? 1 : 0,
      'thumbs': thumbnail != null ? {'url1': thumbnail} : null,
    };
  }
}

/// 百度网盘目录模型
class BaiduCloudDirectory {
  final String fsId;
  final String name;
  final String path;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final List<BaiduCloudFile> files;

  const BaiduCloudDirectory({
    required this.fsId,
    required this.name,
    required this.path,
    required this.createdAt,
    required this.modifiedAt,
    required this.files,
  });

  factory BaiduCloudDirectory.fromJson(Map<String, dynamic> json) {
    final files = <BaiduCloudFile>[];
    if (json['list'] != null) {
      for (final fileJson in json['list']) {
        files.add(BaiduCloudFile.fromJson(fileJson));
      }
    }

    return BaiduCloudDirectory(
      fsId: json['fs_id']?.toString() ?? '',
      name: json['server_filename'] ?? '',
      path: json['path'] ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['server_ctime'] * 1000),
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(json['server_mtime'] * 1000),
      files: files,
    );
  }
}

/// 百度网盘用户信息模型
class BaiduCloudUser {
  final String userId;
  final String userName;
  final String avatarUrl;
  final int totalSpace;
  final int usedSpace;
  final int freeSpace;

  const BaiduCloudUser({
    required this.userId,
    required this.userName,
    required this.avatarUrl,
    required this.totalSpace,
    required this.usedSpace,
    required this.freeSpace,
  });

  factory BaiduCloudUser.fromJson(Map<String, dynamic> json) {
    return BaiduCloudUser(
      userId: json['user_id']?.toString() ?? '',
      userName: json['user_name'] ?? '',
      avatarUrl: json['avatar_url'] ?? '',
      totalSpace: json['total_space'] ?? 0,
      usedSpace: json['used_space'] ?? 0,
      freeSpace: json['free_space'] ?? 0,
    );
  }
}

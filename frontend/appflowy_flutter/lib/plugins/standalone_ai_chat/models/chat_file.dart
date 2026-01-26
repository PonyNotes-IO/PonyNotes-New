import 'dart:io';
import 'dart:typed_data';

/// AI聊天中的文件附件模型
class ChatFile {
  final String id;
  final String? filePath;
  final Uint8List? bytes;
  final String? url;
  final String name;
  final int fileSize;
  final DateTime timestamp;
  final ChatFileType type;
  final String? mimeType;
  final String fileExtension;

  const ChatFile({
    required this.id,
    this.filePath,
    this.bytes,
    this.url,
    required this.name,
    required this.fileSize,
    required this.timestamp,
    required this.type,
    this.mimeType,
    required this.fileExtension,
  });

  /// 从本地文件创建
  static Future<ChatFile> fromFile(File file) async {
    final bytes = await file.readAsBytes();
    final fileName = file.path.split('/').last;
    final extension = _getFileExtension(fileName);
    
    return ChatFile(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      filePath: file.path,
      bytes: bytes,
      name: fileName,
      fileSize: bytes.length,
      timestamp: DateTime.now(),
      type: ChatFileType.local,
      mimeType: _getMimeType(extension),
      fileExtension: extension,
    );
  }

  /// 从字节数据创建
  static ChatFile fromBytes(Uint8List bytes, {required String name}) {
    final extension = _getFileExtension(name);
    
    return ChatFile(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      bytes: bytes,
      name: name,
      fileSize: bytes.length,
      timestamp: DateTime.now(),
      type: ChatFileType.clipboard,
      mimeType: _getMimeType(extension),
      fileExtension: extension,
    );
  }

  /// 从网络URL创建
  static ChatFile fromUrl(String url, {String? name}) {
    final fileName = name ?? url.split('/').last;
    final extension = _getFileExtension(fileName);
    
    return ChatFile(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      url: url,
      name: fileName,
      fileSize: 0, // URL文件大小未知
      timestamp: DateTime.now(),
      type: ChatFileType.network,
      mimeType: _getMimeType(extension),
      fileExtension: extension,
    );
  }

  /// 获取文件数据
  Future<Uint8List?> getData() async {
    if (bytes != null) {
      return bytes!;
    }
    if (filePath != null) {
      return await File(filePath!).readAsBytes();
    }
    return null;
  }

  /// 获取文件扩展名
  static String _getFileExtension(String filename) {
    final parts = filename.split('.');
    if (parts.length > 1) {
      return parts.last.toLowerCase();
    }
    return 'unknown';
  }

  /// 根据扩展名获取MIME类型
  static String? _getMimeType(String extension) {
    const mimeTypes = {
      // 文本文件
      'txt': 'text/plain',
      'md': 'text/markdown',
      'json': 'application/json',
      'xml': 'application/xml',
      'html': 'text/html',
      'css': 'text/css',
      
      // 代码文件
      'js': 'application/javascript',
      'ts': 'application/typescript',
      'py': 'text/x-python',
      'rs': 'text/x-rust',
      'go': 'text/x-go',
      'java': 'text/x-java',
      'c': 'text/x-c',
      'cpp': 'text/x-c++',
      'h': 'text/x-h',
      
      // 文档文件
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt': 'application/vnd.ms-powerpoint',
      'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      
      // 其他
      'csv': 'text/csv',
      'yaml': 'application/x-yaml',
      'yml': 'application/x-yaml',
      'toml': 'application/toml',
    };
    
    return mimeTypes[extension.toLowerCase()];
  }

  /// 判断是否是文本文件
  bool get isTextFile {
    const textExtensions = [
      'txt', 'md', 'markdown', 'json', 'xml', 'html', 'css',
      'js', 'ts', 'jsx', 'tsx', 'py', 'rs', 'go', 'java',
      'c', 'cpp', 'h', 'hpp', 'sh', 'bash', 'yaml', 'yml',
      'toml', 'ini', 'log', 'csv', 'sql'
    ];
    return textExtensions.contains(fileExtension);
  }

  /// 判断是否是文档文件
  bool get isDocumentFile {
    const docExtensions = ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx'];
    return docExtensions.contains(fileExtension);
  }

  /// 获取文件图标
  String get iconEmoji {
    if (isTextFile) return '📄';
    if (isDocumentFile) {
      if (fileExtension == 'pdf') return '📕';
      if (fileExtension.startsWith('xls')) return '📊';
      if (fileExtension.startsWith('ppt')) return '📊';
      return '📝';
    }
    return '📎';
  }

  /// 格式化文件大小
  String get formattedSize {
    if (fileSize < 1024) {
      return '$fileSize B';
    } else if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }
}

/// 文件类型枚举
enum ChatFileType {
  local,      // 本地文件
  clipboard,  // 剪贴板文件
  network,    // 网络文件
}




















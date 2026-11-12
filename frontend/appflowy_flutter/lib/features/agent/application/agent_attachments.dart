import 'package:file_picker/file_picker.dart';

/// Kept aligned with Cloud's session attachment adapter.
const agentAttachmentExtensions = [
  'pdf',
  'doc',
  'docx',
  'xls',
  'xlsx',
  'ppt',
  'pptx',
  'txt',
  'text',
  'md',
  'markdown',
  'csv',
  'json',
  'xml',
  'yaml',
  'yml',
  'log',
  'html',
  'htm',
  'mhtml',
  'epub',
  'xmind',
  'png',
  'jpg',
  'jpeg',
  'webp',
  'gif',
  'bmp',
  'tif',
  'tiff',
  'dart',
  'rs',
  'js',
  'jsx',
  'ts',
  'tsx',
  'py',
  'java',
  'kt',
  'kts',
  'swift',
  'go',
  'c',
  'h',
  'cpp',
  'hpp',
  'cs',
  'php',
  'rb',
  'sql',
  'sh',
  'bash',
  'ps1',
  'css',
  'scss',
  'vue',
  'svelte',
  'toml',
  'ini',
  'cfg',
];

void validateAgentAttachments(List<PlatformFile> files) {
  if (files.length > 4) throw StateError('最多添加 4 个附件');
  for (final file in files) {
    if (!agentAttachmentExtensions
        .contains((file.extension ?? '').toLowerCase())) {
      throw StateError('暂不支持 ${file.name}，请选择图片、文档、表格、演示文稿或文本代码文件');
    }
    if (file.bytes == null ||
        file.size == 0 ||
        file.size > 5 * 1024 * 1024 ||
        file.bytes!.length != file.size) {
      throw StateError('${file.name} 无法读取或大小无效，每个附件需为 1 字节至 5 MB');
    }
  }
}

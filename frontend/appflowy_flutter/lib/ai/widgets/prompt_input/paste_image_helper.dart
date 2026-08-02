import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/clipboard_service.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_backend/log.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 把剪贴板里的图片落成临时文件，供 AI 输入框以「附件」形式带上。
///
/// 为什么要落成文件：AI 输入框的图片通道复用既有的附件机制 ——
/// [AIPromptInputBloc.consumeMetadata] 会挑出附件里扩展名为 jpg/jpeg/png 的项，
/// 读成 base64 塞进 `metadata['images']`。也就是说「选图片文件」本来就能用，
/// 唯独没人接粘贴。这里只补这一环，不新建平行通道。
///
/// 扩展名必须落在 jpg/jpeg/png 之内，否则会被当成普通文件走 RAG 而不是图片分析。
///
/// 返回 `null` 表示剪贴板里没有可用图片（例如只复制了文字），调用方应放行默认的
/// 文本粘贴行为。
Future<({String path, String name})?> readClipboardImageToTempFile() async {
  try {
    final data = await getIt<ClipboardService>().getData();
    final image = data.image;
    Log.info(
      '[AIPaste] 读取剪贴板：image=${image != null}, '
      'plainText=${data.plainText?.isNotEmpty ?? false}, '
      'html=${data.html?.isNotEmpty ?? false}',
    );
    if (image == null) {
      return null;
    }

    final (format, bytes) = image;
    if (bytes == null || bytes.isEmpty) {
      return null;
    }

    // super_clipboard 给出的 format 形如 'png' / 'jpeg' / 'image/png'，
    // 统一归一化；无法识别时按 png 处理（PNG 是剪贴板位图最常见的格式，
    // 且服务端按内容而非扩展名解码，扩展名只用于本地那道图片判定）。
    final normalized = format.toLowerCase();
    final ext = normalized.contains('jpeg') || normalized.contains('jpg')
        ? 'jpg'
        : 'png';

    final dir = await getTemporaryDirectory();
    final pasteDir = Directory(p.join(dir.path, 'ai_pasted_images'));
    if (!pasteDir.existsSync()) {
      await pasteDir.create(recursive: true);
    }

    // 用毫秒时间戳命名，避免连续粘贴互相覆盖。
    final name = 'pasted_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final file = File(p.join(pasteDir.path, name));
    await file.writeAsBytes(bytes);

    Log.info('[AIPaste] 剪贴板图片已落盘: $name (${bytes.length} 字节, 源格式 $format)');
    return (path: file.path, name: name);
  } catch (e) {
    // 粘贴是高频操作，任何异常都不应打断用户输入 —— 静默放行文本粘贴即可。
    Log.warn('[AIPaste] 读取剪贴板图片失败，按无图片处理: $e');
    return null;
  }
}

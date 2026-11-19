import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/custom_image_block_component/custom_image_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/multi_image_block_component/multi_image_block_component.dart';
import 'package:appflowy/shared/markdown_to_document.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/widgets/pdf_html_encoder_wrapper.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:pdf/widgets.dart' as pw;

class DocumentPdfExporter {
  static Future<Uint8List> render(Document document,
      {required String title}) async {
    final temp = await Directory.systemTemp.createTemp('ponynotes_pdf_export_');
    try {
      // Rendering can rewrite image URLs. Keep the in-memory editor document intact.
      final rendering = Document.fromJson(document.toJson());
      await _downloadNetworkImagesInNode(rendering.root, temp);
      final markdown = await customDocumentToMarkdown(
        rendering,
        useSimpleImageParser: true,
      );
      if (markdown.isEmpty) throw StateError('文档内容为空');

      // 加载支持中文的字体
      Log.info('开始加载中文字体...');
      pw.Font? chineseFont;
      pw.Font? mobileLatinFont;
      List<pw.Font> fontFallbackList = [];
      try {
        // 尝试从系统字体路径加载中文字体
        if (Platform.isMacOS) {
          // macOS 系统字体路径（只使用 TTF 格式，避免 TTC 格式的问题）
          final fontPaths = [
            '/System/Library/Fonts/Supplemental/Arial Unicode.ttf', // Arial Unicode 支持中文
            '/Library/Fonts/Arial Unicode.ttf', // 符号链接到上面的路径
            '/Library/Fonts/Microsoft/SimHei.ttf', // 如果安装了 Microsoft 字体
          ];

          for (final fontPath in fontPaths) {
            try {
              final fontFile = File(fontPath);
              if (fontFile.existsSync()) {
                Log.info('尝试加载字体: $fontPath');
                final fontData = await fontFile.readAsBytes();
                try {
                  if (fontPath.endsWith('.ttf')) {
                    chineseFont = pw.Font.ttf(ByteData.view(fontData.buffer));
                    Log.info('✅ 成功加载中文字体 (TTF): $fontPath');
                    break;
                  }
                } catch (e) {
                  Log.warn('⚠️ 加载字体失败 $fontPath: $e');
                  continue;
                }
              } else {
                Log.debug('字体文件不存在: $fontPath');
              }
            } catch (e) {
              Log.warn('⚠️ 读取字体文件失败 $fontPath: $e');
              continue;
            }
          }
        } else if (Platform.isWindows) {
          // Windows 系统字体路径（只使用 TTF 格式）
          final fontPaths = [
            'C:\\Windows\\Fonts\\simhei.ttf', // 黑体
            'C:\\Windows\\Fonts\\msyh.ttf', // 微软雅黑
          ];

          for (final fontPath in fontPaths) {
            try {
              final fontFile = File(fontPath);
              if (fontFile.existsSync()) {
                Log.info('尝试加载字体: $fontPath');
                final fontData = await fontFile.readAsBytes();
                try {
                  if (fontPath.endsWith('.ttf')) {
                    chineseFont = pw.Font.ttf(ByteData.view(fontData.buffer));
                    Log.info('✅ 成功加载中文字体 (TTF): $fontPath');
                    break;
                  }
                } catch (e) {
                  Log.warn('⚠️ 加载字体失败 $fontPath: $e');
                  continue;
                }
              }
            } catch (e) {
              Log.warn('⚠️ 读取字体文件失败 $fontPath: $e');
              continue;
            }
          }
        }
      } catch (e) {
        Log.error('❌ 加载系统字体失败: $e');
      }

      // 移动端使用应用内字体，避免依赖 Android/iOS 不同的系统字体格式。
      if (chineseFont == null && (Platform.isAndroid || Platform.isIOS)) {
        try {
          final fontData = await rootBundle.load('assets/fonts/chinese.ttf');
          chineseFont = pw.Font.ttf(fontData);
          final latinFontData = await rootBundle.load(
            'assets/google_fonts/Poppins/Poppins-Regular.ttf',
          );
          mobileLatinFont = pw.Font.ttf(latinFontData);
          Log.info('✅ 成功加载移动端 PDF 字体');
        } catch (e) {
          Log.warn('⚠️ 加载移动端 PDF 字体失败: $e');
        }
      }

      // 如果仍然没有字体，记录警告但继续执行
      if (chineseFont == null) {
        Log.error('❌ 无法加载中文字体，PDF 中的中文可能显示为占位符（如 X）');
        Log.error('建议：添加支持中文的 TTF 字体文件到 assets/fonts/ 目录');
        Log.error('或者确保系统中有 Arial Unicode.ttf 字体');
      } else {
        Log.info('✅ 中文字体加载成功，PDF 中文显示应该正常');
        // 将中文字体添加到fontFallback
        fontFallbackList.add(chineseFont);
      }
      final encoder = PdfHTMLEncoderWrapper(
        font: mobileLatinFont ?? chineseFont,
        fontFallback: fontFallbackList,
      );
      final pdf = await encoder.convert('# $title\n\n$markdown');
      return await pdf.save();
    } finally {
      try {
        await temp.delete(recursive: true);
      } on FileSystemException {
        Log.warn('PDF 导出临时文件清理失败');
      }
    }
  }

  /// 递归遍历节点，下载网络图片
  static Future<void> _downloadNetworkImagesInNode(
      Node node, Directory tempDir) async {
    Log.info('遍历节点: type=${node.type}, id=${node.id}');

    // 处理单图片节点
    if (node.type == CustomImageBlockKeys.type) {
      Log.info('找到单图片节点: ${node.type}');
      await _downloadImageForNode(node, CustomImageBlockKeys.url, tempDir);
    }
    // 处理多图片节点
    else if (node.type == MultiImageBlockKeys.type) {
      Log.info('找到多图片节点: ${node.type}');
      final currentAttributes = node.attributes;
      final images = currentAttributes[MultiImageBlockKeys.images] as List?;
      if (images != null) {
        Log.info('多图片节点包含 ${images.length} 张图片');
        bool updated = false;
        final List<dynamic> newImages = List.from(images);

        for (int i = 0; i < newImages.length; i++) {
          final image = newImages[i] as Map<String, dynamic>?;
          if (image != null) {
            final url = image['url'] as String?;
            final type = image['type'] as int?;
            Log.info('检查图片 $i: url=$url, type=$type');
            if (url != null && type != null) {
              final imageType = CustomImageType.fromIntValue(type);
              if (imageType == CustomImageType.internal ||
                  imageType == CustomImageType.external) {
                Log.info('下载网络图片: $url');
                final localPath =
                    await _downloadImage(url, tempDir, 'multi_image_$i');
                if (localPath != null) {
                  // 更新图片URL为本地路径
                  newImages[i] = {
                    ...image,
                    'url': localPath,
                    'type': CustomImageType.local.toIntValue()
                  };
                  updated = true;
                  Log.info('图片已下载: $url -> $localPath');
                }
              }
            }
          }
        }

        // 使用 updateAttributes 更新节点属性
        if (updated) {
          node.updateAttributes({
            MultiImageBlockKeys.images: newImages,
          });
          Log.info('多图片节点属性已更新');
        }
      }
    }

    // 递归处理子节点
    for (final child in node.children) {
      await _downloadNetworkImagesInNode(child, tempDir);
    }
  }

  /// 下载单个图片节点的网络图片
  static Future<void> _downloadImageForNode(
      Node node, String urlKey, Directory tempDir) async {
    final currentAttributes = node.attributes;
    final url = currentAttributes[urlKey] as String?;
    final type = currentAttributes['image_type'] as int?;

    Log.info('检查图片节点: url=$url, type=$type, urlKey=$urlKey');
    Log.info('节点属性: $currentAttributes');

    if (url == null || type == null) {
      Log.info('跳过图片节点: url或type为空');
      return;
    }

    final imageType = CustomImageType.fromIntValue(type);
    Log.info('图片类型: $imageType');

    // 只处理网络图片（internal 或 external）
    if (imageType == CustomImageType.internal ||
        imageType == CustomImageType.external) {
      Log.info('开始下载网络图片: $url');
      final localPath = await _downloadImage(url, tempDir, 'image');
      if (localPath != null) {
        // 使用 updateAttributes 更新节点属性
        node.updateAttributes({
          urlKey: localPath,
          'image_type': CustomImageType.local.toIntValue(),
        });
        Log.info('已将网络图片下载到本地: $url -> $localPath');
        Log.info('更新后的节点属性: ${node.attributes}');
      }
    } else {
      Log.info('跳过非网络图片: $imageType');
    }
  }

  /// 下载图片并保存到临时目录
  static Future<String?> _downloadImage(
      String url, Directory tempDir, String prefix) async {
    try {
      Log.info('开始下载网络图片: $url');

      // 根据URL生成文件名
      final uri = Uri.parse(url);
      final extension =
          p.extension(uri.path).isNotEmpty ? p.extension(uri.path) : '.jpg';
      final fileName =
          '${prefix}_${DateTime.now().millisecondsSinceEpoch}$extension';
      final localPath = p.join(tempDir.path, fileName);

      // 下载图片
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final file = File(localPath);
        await file.writeAsBytes(response.bodyBytes);
        Log.info('图片下载成功: $localPath (${response.bodyBytes.length} 字节)');
        return localPath;
      } else {
        Log.warn('图片下载失败，状态码: ${response.statusCode}, URL: $url');
        return null;
      }
    } catch (e) {
      Log.error('下载图片时出错: $url, 错误: $e');
      return null;
    }
  }
}

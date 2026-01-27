import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy_backend/log.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' show parse;
import 'package:http/http.dart' as http;
import 'package:markdown/markdown.dart' as md;
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:appflowy_editor/src/plugins/pdf/html_to_pdf_encoder.dart' as original;

/// 包装类，确保代码块（pre标签）被正确处理
class PdfHTMLEncoderWrapper {
  final pw.Font? font;
  final List<pw.Font> fontFallback;
  final original.PdfHTMLEncoder _originalEncoder;

  PdfHTMLEncoderWrapper({
    this.font,
    required this.fontFallback,
  }) : _originalEncoder = original.PdfHTMLEncoder(
          font: font,
          fontFallback: fontFallback,
        );

  Future<pw.Document> convert(String input) async {
    Log.info('🔍 PdfHTMLEncoderWrapper.convert: 开始转换，输入长度: ${input.length}');
    
    // 先转换为HTML，检查是否有pre标签
    final htmlx = md.markdownToHtml(
      input,
      extensionSet: md.ExtensionSet.gitHubFlavored,
    );
    
    Log.info('🔍 PdfHTMLEncoderWrapper.convert: HTML转换完成，长度: ${htmlx.length}');
    
    // 检查是否有pre标签
    final hasPreTags = htmlx.contains('<pre') || htmlx.contains('</pre>');
    if (hasPreTags) {
      Log.info('✅ PdfHTMLEncoderWrapper.convert: HTML中包含pre标签');
      
      // 解析HTML，手动处理pre标签
      final document = parse(htmlx);
      final body = document.body;
      if (body == null) {
        final blank = pw.Document();
        blank.addPage(
          pw.Page(
            build: (pw.Context context) {
              return pw.Column(children: [pw.SizedBox.shrink()]);
            },
          ),
        );
        return blank;
      }
      
      // 手动构建PDF，确保pre标签被正确处理
      final nodes = await _parseBody(body);
      final newPdf = pw.Document();
      newPdf.addPage(
        pw.MultiPage(build: (pw.Context context) => nodes.toList()),
      );
      return newPdf;
    } else {
      // 没有pre标签，直接使用原始encoder
      Log.info('ℹ️ PdfHTMLEncoderWrapper.convert: HTML中无pre标签，使用原始encoder');
      return await _originalEncoder.convert(input);
    }
  }

  /// 解析body节点，手动处理pre标签
  Future<List<pw.Widget>> _parseBody(dom.Element body) async {
    final nodes = <pw.Widget>[];
    
    for (final node in body.nodes) {
      if (node is dom.Element) {
        if (node.localName == 'pre') {
          // 手动处理pre标签
          final preWidget = await _parsePreElement(node);
          nodes.add(preWidget);
        } else if (node.localName == 'h1' || node.localName == 'h2' || node.localName == 'h3' ||
                   node.localName == 'h4' || node.localName == 'h5' || node.localName == 'h6') {
          // 处理标题
          final levelStr = node.localName;
          final level = levelStr != null && levelStr.length > 1 
              ? int.tryParse(levelStr.substring(1)) ?? 1 
              : 1;
          nodes.add(
            pw.Text(
              node.text,
              style: pw.TextStyle(
                font: font,
                fontFallback: fontFallback,
                fontSize: 24 - (level - 1) * 2,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          );
        } else if (node.localName == 'p') {
          // 处理段落（可能包含图片）
          final paragraphNodes = await _parseElement(node);
          if (paragraphNodes.isNotEmpty) {
            nodes.add(
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: paragraphNodes,
                ),
              ),
            );
          }
        } else if (node.localName == 'img') {
          // 处理图片
          final imageWidget = await _parseImageElement(node);
          if (imageWidget != null) {
            nodes.add(imageWidget);
          }
        } else {
          // 其他元素，递归处理
          final childNodes = await _parseElement(node);
          nodes.addAll(childNodes);
        }
      } else if (node is dom.Text) {
        if (node.text.trim().isNotEmpty) {
          nodes.add(
            pw.Text(
              node.text,
              style: pw.TextStyle(
                font: font,
                fontFallback: fontFallback,
                fontSize: 12,
              ),
            ),
          );
        }
      }
    }
    
    return nodes;
  }

  /// 解析元素节点
  Future<List<pw.Widget>> _parseElement(dom.Element element) async {
    final nodes = <pw.Widget>[];
    
    if (element.localName == 'pre') {
      final preWidget = await _parsePreElement(element);
      nodes.add(preWidget);
    } else if (element.localName == 'img') {
      // 处理图片
      final imageWidget = await _parseImageElement(element);
      if (imageWidget != null) {
        nodes.add(imageWidget);
      }
    } else {
      // 处理其他元素
      for (final child in element.nodes) {
        if (child is dom.Element) {
          final childNodes = await _parseElement(child);
          nodes.addAll(childNodes);
        } else if (child is dom.Text) {
          if (child.text.trim().isNotEmpty) {
            nodes.add(
              pw.Text(
                child.text,
                style: pw.TextStyle(
                  font: font,
                  fontFallback: fontFallback,
                  fontSize: 12,
                ),
              ),
            );
          }
        }
      }
    }
    
    return nodes;
  }

  /// 解析图片元素
  Future<pw.Widget?> _parseImageElement(dom.Element element) async {
    final src = element.attributes['src'];
    if (src == null || src.isEmpty) {
      return null;
    }
    
    try {
      Uint8List imageBytes;
      
      if (src.startsWith('http://') || src.startsWith('https://')) {
        // 网络图片
        Log.info('🔍 PdfHTMLEncoderWrapper: 加载网络图片: $src');
        final response = await http.get(Uri.parse(src));
        if (response.statusCode == 200) {
          imageBytes = response.bodyBytes;
        } else {
          Log.warn('⚠️ PdfHTMLEncoderWrapper: 图片加载失败，状态码: ${response.statusCode}');
          return pw.Text('[图片加载失败: $src]');
        }
      } else {
        // 本地图片
        Log.info('🔍 PdfHTMLEncoderWrapper: 加载本地图片: $src');
        final file = File(src);
        if (await file.exists()) {
          imageBytes = await file.readAsBytes();
        } else {
          Log.warn('⚠️ PdfHTMLEncoderWrapper: 图片文件不存在: $src');
          return pw.Text('[图片文件不存在: $src]');
        }
      }
      
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Image(
          pw.MemoryImage(imageBytes),
          fit: pw.BoxFit.contain,
        ),
      );
    } catch (e) {
      Log.error('❌ PdfHTMLEncoderWrapper: 图片处理失败: $e');
      return pw.Text('[图片处理失败: $e]');
    }
  }

  /// 手动解析pre元素
  Future<pw.Widget> _parsePreElement(dom.Element element) async {
    Log.info('🔍 PdfHTMLEncoderWrapper._parsePreElement: 开始解析pre元素');
    String codeText = '';
    
    // 查找<code>标签，如果存在则提取其内容
    final codeElement = element.querySelector('code');
    if (codeElement != null) {
      Log.info('  ✅ 找到code子元素');
      codeText = codeElement.text;
      Log.info('  📝 code.text长度: ${codeText.length}');
      
      if (codeText.isEmpty) {
        // 递归提取所有文本节点
        final buffer = StringBuffer();
        for (final node in codeElement.nodes) {
          if (node is dom.Text) {
            buffer.write(node.text);
          } else if (node is dom.Element) {
            buffer.write(node.text);
          }
        }
        codeText = buffer.toString();
        Log.info('  📝 递归提取长度: ${codeText.length}');
      }
    } else {
      Log.info('  ⚠️ 未找到code子元素，直接使用pre的文本');
      codeText = element.text;
      Log.info('  📝 pre.text长度: ${codeText.length}');
      
      if (codeText.isEmpty) {
        final buffer = StringBuffer();
        for (final node in element.nodes) {
          if (node is dom.Text) {
            buffer.write(node.text);
          } else if (node is dom.Element) {
            buffer.write(node.text);
          }
        }
        codeText = buffer.toString();
        Log.info('  📝 递归提取长度: ${codeText.length}');
      }
    }
    
    // 移除首尾空白，但保留内部格式（保留换行）
    codeText = codeText.trim();
    Log.info('  ✅ 最终代码文本长度: ${codeText.length}');
    
    // 如果代码为空，返回一个占位符
    if (codeText.isEmpty) {
      Log.warn('  ⚠️ 代码文本为空，返回占位符');
      return pw.Container(
        padding: const pw.EdgeInsets.all(12),
        margin: const pw.EdgeInsets.only(bottom: 8),
        decoration: pw.BoxDecoration(
          color: pdf.PdfColors.grey200,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        width: double.infinity,
        child: pw.Text(
          '[代码块内容为空]',
          style: pw.TextStyle(
            font: font,
            fontFallback: fontFallback,
            fontSize: 10,
            fontStyle: pw.FontStyle.italic,
            color: pdf.PdfColors.grey600,
          ),
        ),
      );
    }
    
    Log.info('  ✅ 代码块解析成功，返回可跨页的代码块');
    // 将代码块文本按行分割，每行使用单独的 Text widget
    // 这样 pw.MultiPage 可以自动处理分页
    final codeLines = codeText.split('\n');
    final codeWidgets = <pw.Widget>[];
    
    // 添加顶部padding和背景
    codeWidgets.add(
      pw.Container(
        padding: const pw.EdgeInsets.only(top: 12, left: 12, right: 12),
        decoration: const pw.BoxDecoration(
          color: pdf.PdfColors.grey200,
          borderRadius: pw.BorderRadius.only(
            topLeft: pw.Radius.circular(4),
            topRight: pw.Radius.circular(4),
          ),
        ),
        width: double.infinity,
        child: pw.SizedBox.shrink(),
      ),
    );
    
    // 添加每一行代码
    for (int i = 0; i < codeLines.length; i++) {
      final line = codeLines[i];
      final isLastLine = i == codeLines.length - 1;
      
      codeWidgets.add(
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 12),
          decoration: isLastLine
              ? pw.BoxDecoration(
                  color: pdf.PdfColors.grey200,
                  borderRadius: const pw.BorderRadius.only(
                    bottomLeft: pw.Radius.circular(4),
                    bottomRight: pw.Radius.circular(4),
                  ),
                )
              : pw.BoxDecoration(
                  color: pdf.PdfColors.grey200,
                ),
          width: double.infinity,
          child: pw.Text(
            line.isEmpty ? ' ' : line, // 空行用空格代替，保持格式
            style: pw.TextStyle(
              // 代码块优先使用fontFallback支持emoji，如果没有fontFallback则使用主字体
              font: fontFallback.isNotEmpty ? null : font, // 如果有fontFallback，不设置主字体，让系统使用fontFallback
              fontFallback: fontFallback.isNotEmpty 
                  ? fontFallback 
                  : (font != null ? [font!] : []), // 优先使用fontFallback支持emoji，确保不包含null
              fontSize: 10,
            ),
          ),
        ),
      );
    }
    
    // 添加底部padding和margin
    codeWidgets.add(
      pw.SizedBox(height: 8),
    );
    
    // 使用 Column 包裹所有行，让 MultiPage 自动分页
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: codeWidgets,
    );
  }
}


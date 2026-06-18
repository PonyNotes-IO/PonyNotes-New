import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy_backend/log.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' show parse;
import 'package:http/http.dart' as http;
import 'package:markdown/markdown.dart' as md;
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;

/// 包装类，将 Markdown 转换为 HTML 再解析为 PDF。
/// 始终手动解析 HTML DOM，确保图片、代码块、列表等元素被正确处理。
class PdfHTMLEncoderWrapper {
  final pw.Font? font;
  final List<pw.Font> fontFallback;
  int _checkboxCounter = 0;

  PdfHTMLEncoderWrapper({
    this.font,
    required this.fontFallback,
  });

  Future<pw.Document> convert(String input) async {
    Log.info('🔍 PdfHTMLEncoderWrapper.convert: 开始转换，输入长度: ${input.length}');

    // 始终使用手动HTML解析，确保图片和代码块都能正确处理。
    // 原始 encoder 的 _parseImageElement 存在图片无法嵌入的问题。
    final htmlx = md.markdownToHtml(
      input,
      extensionSet: md.ExtensionSet.gitHubFlavored,
    );

    Log.info('🔍 PdfHTMLEncoderWrapper.convert: HTML转换完成，长度: ${htmlx.length}');

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

    // 手动解析HTML DOM，确保pre标签和图片都被正确处理
    final nodes = await _parseBody(body);
    final newPdf = pw.Document();
    newPdf.addPage(
      pw.MultiPage(build: (pw.Context context) => nodes.toList()),
    );
    return newPdf;
  }

  /// 解析body节点
  Future<List<pw.Widget>> _parseBody(dom.Element body) async {
    final nodes = <pw.Widget>[];

    for (final node in body.nodes) {
      if (node is dom.Element) {
        if (node.localName == 'pre') {
          final preWidget = await _parsePreElement(node);
          nodes.add(preWidget);
        } else if (node.localName == 'h1' || node.localName == 'h2' || node.localName == 'h3' ||
                   node.localName == 'h4' || node.localName == 'h5' || node.localName == 'h6') {
          final levelStr = node.localName ?? 'h1';
          final level = levelStr.length > 1
              ? int.tryParse(levelStr.substring(1)) ?? 1
              : 1;
          nodes.add(
            pw.Header(
              level: level,
              child: pw.Text(
                node.text,
                style: pw.TextStyle(
                  font: font,
                  fontFallback: fontFallback,
                  fontSize: 24 - (level - 1) * 2,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          );
        } else if (node.localName == 'p') {
          final paragraphNodes = await _parseElement(node);
          if (paragraphNodes.isNotEmpty) {
            nodes.add(
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Wrap(children: paragraphNodes),
              ),
            );
          }
        } else if (node.localName == 'img') {
          final imageWidget = await _parseImageElement(node);
          if (imageWidget != null) {
            nodes.add(imageWidget);
          }
        } else if (node.localName == 'ul' || node.localName == 'ol') {
          final listNodes = await _parseListElement(node, ordered: node.localName == 'ol');
          nodes.addAll(listNodes);
        } else if (node.localName == 'blockquote') {
          final quoteNodes = await _parseBlockquoteElement(node);
          nodes.addAll(quoteNodes);
        } else if (node.localName == 'table') {
          final tableWidget = _parseTableElement(node);
          nodes.add(tableWidget);
        } else if (node.localName == 'hr') {
          nodes.add(pw.Divider());
        } else {
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
      final imageWidget = await _parseImageElement(element);
      if (imageWidget != null) {
        nodes.add(imageWidget);
      }
    } else if (element.localName == 'input') {
      // 处理 checkbox（markdown 任务列表生成的 <input type="checkbox">）
      final type = element.attributes['type'];
      if (type == 'checkbox') {
        final isChecked = element.attributes.containsKey('checked');
        nodes.add(
          pw.Checkbox(
            name: 'cb_${_checkboxCounter++}',
            value: isChecked,
            width: 13,
            height: 13,
          ),
        );
      }
    } else {
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
      // markdown 库的 normalizeLinkDestination() 会通过 Uri.encodeFull() 将
      // Windows 反斜杠 \ 编码为 %5C，需要先解码还原真实路径。
      final decodedSrc = Uri.decodeComponent(src);
      Uint8List imageBytes;

      if (decodedSrc.startsWith('http://') || decodedSrc.startsWith('https://')) {
        // 网络图片
        Log.info('🔍 PdfHTMLEncoderWrapper: 加载网络图片: $decodedSrc');
        final response = await http.get(Uri.parse(decodedSrc));
        if (response.statusCode == 200) {
          imageBytes = response.bodyBytes;
        } else {
          Log.warn('⚠️ PdfHTMLEncoderWrapper: 图片加载失败，状态码: ${response.statusCode}');
          return pw.Text('[图片加载失败: $decodedSrc]');
        }
      } else {
        // 本地图片
        Log.info('🔍 PdfHTMLEncoderWrapper: 加载本地图片: $decodedSrc');
        final file = File(decodedSrc);
        if (await file.exists()) {
          imageBytes = await file.readAsBytes();
          Log.info('✅ PdfHTMLEncoderWrapper: 本地图片读取成功，大小: ${imageBytes.length} 字节');
        } else {
          Log.warn('⚠️ PdfHTMLEncoderWrapper: 图片文件不存在: $decodedSrc');
          return pw.Text('[图片文件不存在: $decodedSrc]');
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

  /// 解析列表元素（ul/ol），支持任务列表 checkbox
  Future<List<pw.Widget>> _parseListElement(
    dom.Element element, {
    bool ordered = false,
  }) async {
    final items = <pw.Widget>[];
    int index = 1;
    for (final child in element.children) {
      if (child.localName == 'li') {
        // 检测是否为任务列表项（包含 <input type="checkbox">）
        final checkbox = child.querySelector('input[type="checkbox"]');
        final isTaskItem = checkbox != null;
        final isChecked = isTaskItem && checkbox.attributes.containsKey('checked');

        // 对于任务列表项，先移除 checkbox 元素再提取文本，
        // 避免 _parseElement 重复渲染 checkbox。
        List<pw.Widget> childNodes;
        if (isTaskItem) {
          final cloned = dom.Element.html('<div>${child.innerHtml}</div>');
          final inputs = cloned.querySelectorAll('input[type="checkbox"]');
          for (final inp in inputs) {
            inp.remove();
          }
          childNodes = await _parseElement(cloned);
        } else {
          childNodes = await _parseElement(child);
        }

        items.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 16, bottom: 4),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (isTaskItem)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(right: 4),
                    child: pw.Checkbox(
                      name: 'cb_${_checkboxCounter++}',
                      value: isChecked,
                      width: 13,
                      height: 13,
                    ),
                  )
                else
                  pw.SizedBox(
                    width: 24,
                    child: pw.Text(
                      ordered ? '$index. ' : '• ',
                      style: pw.TextStyle(font: font, fontFallback: fontFallback),
                    ),
                  ),
                pw.Expanded(
                  child: pw.Wrap(children: childNodes),
                ),
              ],
            ),
          ),
        );
        if (ordered) index++;
      }
    }
    return items;
  }

  /// 解析引用块元素
  Future<List<pw.Widget>> _parseBlockquoteElement(dom.Element element) async {
    final childNodes = await _parseElement(element);
    return [
      pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 8),
        padding: const pw.EdgeInsets.only(left: 12),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            left: pw.BorderSide(color: pdf.PdfColors.grey400, width: 3),
          ),
        ),
        child: pw.Wrap(children: childNodes),
      ),
    ];
  }

  /// 解析表格元素
  pw.Widget _parseTableElement(dom.Element element) {
    final rows = element.querySelectorAll('tr');
    final tableRows = <pw.TableRow>[];

    for (final row in rows) {
      final cells = <pw.Widget>[];
      for (final cell in row.children) {
        if (cell.localName == 'td' || cell.localName == 'th') {
          cells.add(
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text(
                cell.text,
                style: pw.TextStyle(
                  font: font,
                  fontFallback: fontFallback,
                  fontWeight: cell.localName == 'th'
                      ? pw.FontWeight.bold
                      : pw.FontWeight.normal,
                ),
              ),
            ),
          );
        }
      }
      tableRows.add(pw.TableRow(children: cells));
    }

    return pw.Table(
      border: pw.TableBorder.all(color: pdf.PdfColors.grey300),
      children: tableRows,
    );
  }
}


import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// Quill 编辑器结构体，管理富文本编辑状态
/// 
/// 用于手写笔记中的文本编辑功能
class QuillStruct {
  QuillStruct({
    required this.controller,
    required this.focusNode,
  });

  /// Quill 文档控制器
  final QuillController controller;
  
  /// 焦点节点
  final FocusNode focusNode;

  /// ✅ 创建安全的 QuillController 配置
  /// 禁用富文本粘贴，只允许纯文本粘贴，避免断言错误
  static QuillControllerConfig _createSafeConfig() {
    return QuillControllerConfig(
      clipboardConfig: QuillClipboardConfig(
        // ✅ 禁用富文本粘贴，避免格式转换导致的断言错误
        enableExternalRichPaste: false,
        // ✅ 自定义纯文本粘贴处理，清理特殊字符
        onPlainTextPaste: (plainText) async {
          // 清理可能导致问题的字符
          String sanitized = plainText
            .replaceAll('\r\n', '\n')
            .replaceAll('\r', '\n')
            .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '')
            .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF\u2060]'), '')
            .replaceAll(RegExp(r'[\uD800-\uDFFF]'), '');
          // 移除末尾换行符（可能导致行末格式应用问题）
          while (sanitized.endsWith('\n')) {
            sanitized = sanitized.substring(0, sanitized.length - 1);
          }
          return sanitized.isEmpty ? null : sanitized;
        },
      ),
    );
  }

  /// 创建默认的 QuillStruct 实例
  factory QuillStruct.createDefault() {
    final controller = QuillController.basic(
      config: _createSafeConfig(),
    );
    final focusNode = FocusNode();
    return QuillStruct(
      controller: controller,
      focusNode: focusNode,
    );
  }

  /// 从 JSON 数据创建 QuillStruct 实例
  factory QuillStruct.fromJson(Map<String, dynamic> json) {
    try {
      final controller = QuillController(
        document: Document.fromJson(json['document'] ?? []),
        selection: const TextSelection.collapsed(offset: 0),
        config: _createSafeConfig(),
      );
      final focusNode = FocusNode();
      return QuillStruct(
        controller: controller,
        focusNode: focusNode,
      );
    } catch (e) {
      // 如果解析失败，返回空文档
      return QuillStruct.createDefault();
    }
  }

  /// 转换为 JSON 数据
  Map<String, dynamic> toJson() {
    return {
      'document': controller.document.toDelta().toJson(),
    };
  }

  /// 释放资源
  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }

  /// 获取纯文本内容
  String get plainText {
    return controller.document.toPlainText();
  }

  /// 清空内容
  void clear() {
    controller.clear();
  }

  /// 插入文本
  void insertText(String text) {
    final selection = controller.selection;
    controller.replaceText(
      selection.start,
      selection.end - selection.start,
      text,
      TextSelection.collapsed(offset: selection.start + text.length),
    );
  }
  
  /// ✅ 设置字体大小（显式设置 Quill Document 的 size 属性）
  /// 注意：flutter_quill 的 getFontSize 函数只支持以下格式：
  /// - 'small', 'normal', 'large', 'huge' 字符串
  /// - 纯数字字符串如 "18"（不能带 px 后缀！）
  /// - double 或 int 类型
  void setFontSize(double fontSize) {
    final selection = controller.selection;
    // ✅ 修复：使用纯数字字符串，不要带 px 后缀
    // flutter_quill 的 getFontSize 无法解析 "18px" 格式
    final sizeValue = fontSize.toStringAsFixed(0);
    if (selection.isValid) {
      // 格式化当前选中的文本，设置字体大小
      controller.formatText(
        selection.start,
        selection.end - selection.start,
        SizeAttribute(sizeValue),
      );
    } else {
      // 如果没有选中文本，格式化整个文档
      final document = controller.document;
      if (document.length > 0) {
        controller.formatText(
          0,
          document.length - 1,
          SizeAttribute(sizeValue),
        );
      }
    }
  }
  
  /// ✅ 确保整个文档使用指定的字体大小
  /// 如果没有 size 属性，为整个文档设置字体大小
  void ensureFontSize(double fontSize) {
    final document = controller.document;
    if (document.length == 0) return;
    
    // 检查文档中是否已经有 size 属性
    bool hasSizeAttribute = false;
    for (final node in document.root.children) {
      final delta = node.toDelta();
      for (final op in delta.toList()) {
        if (op.attributes != null && op.attributes!['size'] != null) {
          hasSizeAttribute = true;
          break;
        }
      }
      if (hasSizeAttribute) break;
    }
    
    // 如果没有 size 属性，为整个文档设置字体大小
    // ✅ 修复：使用纯数字字符串，不要带 px 后缀
    // flutter_quill 的 getFontSize 无法解析 "18px" 格式
    if (!hasSizeAttribute) {
      final sizeValue = fontSize.toStringAsFixed(0);
      controller.formatText(
        0,
        document.length - 1,
        SizeAttribute(sizeValue),
      );
    }
  }
  
  /// ✅ 将 Quill Document 转换为 TextSpan（用于在 Canvas 上绘制）
  TextSpan toTextSpan({TextStyle? baseStyle}) {
    final document = controller.document;
    final List<InlineSpan> children = [];
    
    // 默认基础样式
    final defaultBaseStyle = baseStyle ?? const TextStyle(
      fontSize: 16,
      color: Colors.black,
    );
    
    // 遍历文档的所有节点
    for (final node in document.root.children) {
      // 获取节点的 Delta
      final delta = node.toDelta();
      
      // 遍历 Delta 中的每个操作（使用 toList() 获取操作列表）
      for (final op in delta.toList()) {
        if (op.data is! String) continue;
        
        final text = op.data as String;
        final attributes = op.attributes;
        
        // ✅ 构建文本样式：优先使用 baseStyle，确保字体大小一致
        // 关键修复：如果没有显式的 size 属性，使用 baseStyle 的字体大小
        // 这样确保编辑时和渲染时使用相同的字体大小
        TextStyle style = defaultBaseStyle;
        
        if (attributes != null) {
          // ✅ 粗体
          if (attributes['bold'] == true) {
            style = style.copyWith(fontWeight: FontWeight.bold);
          }
          
          // ✅ 斜体
          if (attributes['italic'] == true) {
            style = style.copyWith(fontStyle: FontStyle.italic);
          }
          
          // ✅ 下划线
          if (attributes['underline'] == true) {
            style = style.copyWith(decoration: TextDecoration.underline);
          }
          
          // ✅ 删除线
          if (attributes['strike'] == true) {
            style = style.copyWith(
              decoration: style.decoration != null
                  ? TextDecoration.combine([
                      style.decoration!,
                      TextDecoration.lineThrough,
                    ])
                  : TextDecoration.lineThrough,
            );
          }
          
          // ✅ 文字颜色
          if (attributes['color'] != null) {
            try {
              final colorValue = attributes['color'] as String;
              // Quill 使用 CSS 颜色格式，如 "#FF0000" 或 "rgb(255,0,0)"
              if (colorValue.startsWith('#')) {
                final hexColor = colorValue.substring(1);
                final intColor = int.parse('FF$hexColor', radix: 16);
                style = style.copyWith(color: Color(intColor));
              }
            } catch (e) {
              // 颜色解析失败，使用默认颜色
            }
          }
          
          // ✅ 背景颜色
          if (attributes['background'] != null) {
            try {
              final bgColorValue = attributes['background'] as String;
              if (bgColorValue.startsWith('#')) {
                final hexColor = bgColorValue.substring(1);
                final intColor = int.parse('FF$hexColor', radix: 16);
                style = style.copyWith(backgroundColor: Color(intColor));
              }
            } catch (e) {
              // 背景色解析失败，忽略
            }
          }
          
          // ✅ 字体大小
          if (attributes['size'] != null) {
            try {
              final sizeValue = attributes['size'];
              double? fontSize;
              if (sizeValue is String) {
                // Quill 使用字符串如 "18px" 或相对大小如 "small", "large"
                if (sizeValue.endsWith('px')) {
                  fontSize = double.tryParse(sizeValue.replaceAll('px', ''));
                } else {
                  // 相对大小映射
                  final sizeMap = {
                    'small': 12.0,
                    'large': 20.0,
                    'huge': 24.0,
                  };
                  fontSize = sizeMap[sizeValue];
                }
              } else if (sizeValue is num) {
                fontSize = sizeValue.toDouble();
              }
              if (fontSize != null) {
                style = style.copyWith(fontSize: fontSize);
              }
            } catch (e) {
              // 字体大小解析失败，使用默认大小
            }
          }
          
          // ✅ 上标/下标
          if (attributes['script'] != null) {
            final scriptValue = attributes['script'];
            if (scriptValue == 'super') {
              // 上标：缩小字体并提升基线
              style = style.copyWith(
                fontSize: (style.fontSize ?? 16) * 0.7,
                height: 0.5,
              );
            } else if (scriptValue == 'sub') {
              // 下标：缩小字体并降低基线
              style = style.copyWith(
                fontSize: (style.fontSize ?? 16) * 0.7,
                height: 1.5,
              );
            }
          }
        }
        
        children.add(TextSpan(text: text, style: style));
      }
    }
    
    // 如果没有内容，返回空的 TextSpan
    if (children.isEmpty) {
      return TextSpan(text: '', style: defaultBaseStyle);
    }
    
    return TextSpan(children: children, style: defaultBaseStyle);
  }
}


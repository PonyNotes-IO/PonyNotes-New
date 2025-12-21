import 'package:flutter/material.dart';

/// ✅ 文本框类型枚举
enum TextBoxType {
  normal,      // 普通文本
  heading1,    // 一级标题
  heading2,    // 二级标题
  heading3,    // 三级标题
  paragraph,   // 正文
}

/// ✅ 文本框数据模型
class TextBox {
  TextBox({
    required this.id,
    required this.position,
    required this.size,
    required this.text,
    this.textStyle,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 0,
    this.textBoxType = TextBoxType.normal, // ✅ 文本框类型
  });

  /// 唯一标识符
  final String id;

  /// 位置（左上角坐标）
  Offset position;

  /// 大小
  Size size;

  /// 文本内容
  String text;

  /// 文本样式
  TextStyle? textStyle;

  /// 背景颜色（可选）
  Color? backgroundColor;

  /// 边框颜色（可选）
  Color? borderColor;

  /// 边框宽度
  double borderWidth;
  
  /// ✅ 文本框类型
  TextBoxType textBoxType;
  
  /// ✅ 获取标题样式（根据类型自动应用）
  TextStyle getHeadingStyle(Color baseColor) {
    final baseStyle = TextStyle(color: baseColor);
    switch (textBoxType) {
      case TextBoxType.heading1:
        return baseStyle.copyWith(
          fontSize: 32,
          fontWeight: FontWeight.bold,
        );
      case TextBoxType.heading2:
        return baseStyle.copyWith(
          fontSize: 24,
          fontWeight: FontWeight.bold,
        );
      case TextBoxType.heading3:
        return baseStyle.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w600,
        );
      case TextBoxType.paragraph:
        return baseStyle.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.normal,
        );
      case TextBoxType.normal:
        return baseStyle.copyWith(
          fontSize: 16,
        );
    }
  }

  /// 获取边界矩形
  Rect get rect => Rect.fromLTWH(position.dx, position.dy, size.width, size.height);

  /// 移动文本框
  void move(Offset offset) {
    position = position + offset;
  }

  /// 调整大小
  void resize(Size newSize) {
    size = newSize;
  }

  /// 序列化为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'position': {'x': position.dx, 'y': position.dy},
      'size': {'width': size.width, 'height': size.height},
      'text': text,
      'textStyle': textStyle != null
          ? {
              'fontSize': textStyle!.fontSize,
              'fontWeight': textStyle!.fontWeight?.index,
              'fontStyle': textStyle!.fontStyle?.index,
              'color': textStyle!.color?.value,
              'decoration': textStyle!.decoration != null ? _textDecorationToInt(textStyle!.decoration!) : null,
              'decorationColor': textStyle!.decorationColor?.value,
              'decorationStyle': textStyle!.decorationStyle?.index,
              'decorationThickness': textStyle!.decorationThickness,
            }
          : null,
      'backgroundColor': backgroundColor?.value,
      'borderColor': borderColor?.value,
      'borderWidth': borderWidth,
      'textBoxType': textBoxType.name, // ✅ 保存文本框类型
    };
  }

  /// 从JSON反序列化
  factory TextBox.fromJson(Map<String, dynamic> json) {
    final positionJson = json['position'] as Map<String, dynamic>;
    final sizeJson = json['size'] as Map<String, dynamic>;
    final textStyleJson = json['textStyle'] as Map<String, dynamic>?;

    TextStyle? textStyle;
    if (textStyleJson != null) {
      textStyle = TextStyle(
        fontSize: (textStyleJson['fontSize'] as num?)?.toDouble(),
        fontWeight: textStyleJson['fontWeight'] != null
            ? FontWeight.values[textStyleJson['fontWeight'] as int]
            : null,
        fontStyle: textStyleJson['fontStyle'] != null
            ? FontStyle.values[textStyleJson['fontStyle'] as int]
            : null,
        color: textStyleJson['color'] != null
            ? Color(textStyleJson['color'] as int)
            : null,
        decoration: textStyleJson['decoration'] != null
            ? _intToTextDecoration(textStyleJson['decoration'] as int)
            : null,
        decorationColor: textStyleJson['decorationColor'] != null
            ? Color(textStyleJson['decorationColor'] as int)
            : null,
        decorationStyle: textStyleJson['decorationStyle'] != null
            ? TextDecorationStyle.values[textStyleJson['decorationStyle'] as int]
            : null,
        decorationThickness: (textStyleJson['decorationThickness'] as num?)?.toDouble(),
      );
    }

    return TextBox(
      id: json['id'] as String,
      position: Offset(
        (positionJson['x'] as num).toDouble(),
        (positionJson['y'] as num).toDouble(),
      ),
      size: Size(
        (sizeJson['width'] as num).toDouble(),
        (sizeJson['height'] as num).toDouble(),
      ),
      text: json['text'] as String? ?? '',
      textStyle: textStyle,
      backgroundColor: json['backgroundColor'] != null
          ? Color(json['backgroundColor'] as int)
          : null,
      borderColor: json['borderColor'] != null
          ? Color(json['borderColor'] as int)
          : null,
      borderWidth: (json['borderWidth'] as num?)?.toDouble() ?? 0,
      textBoxType: json['textBoxType'] != null
          ? TextBoxType.values.firstWhere(
              (t) => t.name == json['textBoxType'],
              orElse: () => TextBoxType.normal,
            )
          : TextBoxType.normal, // ✅ 读取文本框类型
    );
  }

  /// 将TextDecoration转换为int
  static int _textDecorationToInt(TextDecoration decoration) {
    if (decoration == TextDecoration.underline) return 1;
    if (decoration == TextDecoration.overline) return 2;
    if (decoration == TextDecoration.lineThrough) return 4;
    if (decoration == TextDecoration.combine([TextDecoration.underline, TextDecoration.lineThrough])) return 5;
    return 0;
  }

  /// 将int转换为TextDecoration
  static TextDecoration? _intToTextDecoration(int value) {
    switch (value) {
      case 1:
        return TextDecoration.underline;
      case 2:
        return TextDecoration.overline;
      case 4:
        return TextDecoration.lineThrough;
      case 5:
        return TextDecoration.combine([TextDecoration.underline, TextDecoration.lineThrough]);
      default:
        return null;
    }
  }

  /// 复制并修改
  TextBox copyWith({
    String? id,
    Offset? position,
    Size? size,
    String? text,
    TextStyle? textStyle,
    Color? backgroundColor,
    Color? borderColor,
    double? borderWidth,
    TextBoxType? textBoxType,
  }) {
    return TextBox(
      id: id ?? this.id,
      position: position ?? this.position,
      size: size ?? this.size,
      text: text ?? this.text,
      textStyle: textStyle ?? this.textStyle,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      borderColor: borderColor ?? this.borderColor,
      borderWidth: borderWidth ?? this.borderWidth,
      textBoxType: textBoxType ?? this.textBoxType,
    );
  }
}

/// ✅ 文本样式扩展（用于格式化）
class TextFormatting {
  const TextFormatting({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.superscript = false,
    this.subscript = false,
  });

  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;
  final bool superscript;
  final bool subscript;

  /// 应用到TextStyle
  TextStyle applyTo(TextStyle baseStyle) {
    return baseStyle.copyWith(
      fontWeight: bold ? FontWeight.bold : baseStyle.fontWeight,
      fontStyle: italic ? FontStyle.italic : baseStyle.fontStyle,
      decoration: _getDecoration(),
      decorationColor: (underline || strikethrough) ? baseStyle.color : null,
      decorationThickness: (underline || strikethrough) ? 1.0 : null,
    );
  }

  TextDecoration? _getDecoration() {
    if (underline && strikethrough) {
      return TextDecoration.combine([
        TextDecoration.underline,
        TextDecoration.lineThrough,
      ]);
    } else if (underline) {
      return TextDecoration.underline;
    } else if (strikethrough) {
      return TextDecoration.lineThrough;
    }
    return null;
  }

  /// 复制并修改
  TextFormatting copyWith({
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strikethrough,
    bool? superscript,
    bool? subscript,
  }) {
    return TextFormatting(
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
      strikethrough: strikethrough ?? this.strikethrough,
      superscript: superscript ?? this.superscript,
      subscript: subscript ?? this.subscript,
    );
  }
}


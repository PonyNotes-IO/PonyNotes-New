import 'package:characters/characters.dart';
import 'package:flutter/services.dart';

/// 与后端 flowy-folder view_name 解析器一致：笔记标题最大 256 个字形（graphemes）
const int kMaxViewNameGraphemeLength = 256;

/// 按字形数限制的输入格式化器，与后端 ViewName::parse 的 256 字形限制一致
class ViewNameLengthLimitingFormatter extends TextInputFormatter {
  ViewNameLengthLimitingFormatter(this.maxGraphemes);

  final int maxGraphemes;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final newText = newValue.text;
    if (newText.characters.length <= maxGraphemes) {
      return newValue;
    }
    final truncated = newText.characters.take(maxGraphemes).string;
    return TextEditingValue(
      text: truncated,
      selection: TextSelection.collapsed(offset: truncated.length),
    );
  }
}

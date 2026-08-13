import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:appflowy/workspace/presentation/widgets/more_view_actions/widgets/pdf_html_encoder_wrapper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('mobile PDF encoder renders mixed Chinese document content', () async {
    final chineseFontData = await rootBundle.load('assets/fonts/chinese.ttf');
    final latinFontData = await rootBundle.load(
      'assets/google_fonts/Poppins/Poppins-Regular.ttf',
    );
    expect(chineseFontData.lengthInBytes, lessThan(5 * 1024 * 1024));

    final chineseFont = pw.Font.ttf(chineseFontData);
    final document = await PdfHTMLEncoderWrapper(
      font: pw.Font.ttf(latinFontData),
      fontFallback: [chineseFont],
    ).convert('''
# 中文标题 PDF Export

移动端正文、繁體中文 English 123

- 中文列表一
- 中文列表二

| 名称 | 状态 |
| --- | --- |
| 文档 | 正常 |
''');

    final bytes = await document.save();
    expect(bytes, isNotEmpty);
  });
}

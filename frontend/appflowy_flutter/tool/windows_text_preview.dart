// Render with flutter_tester without --use-test-fonts so Windows supplies
// the real system fonts. See ckdocs/WINDOWS_TEXT_CLARITY.md for commands.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy_ui/platform_font.dart';

Future<void> main() async {
  if (!Platform.isWindows) {
    throw UnsupportedError('This comparison requires Windows system fonts.');
  }
  final output = Directory('build/font_clarity')..createSync(recursive: true);
  for (final dpr in [1.0, 1.25, 1.5]) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(dpr);
    canvas.drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
    _draw(
      canvas,
      'Windows text comparison / ${(dpr * 100).round()}% DPR',
      32,
      24,
      size: 24,
    );
    _draw(
      canvas,
      'Same logical font size, regular weight, color and content.',
      32,
      62,
      size: 14,
    );
    _draw(canvas, 'Baseline', 32, 108, size: 20);
    _draw(canvas, 'Optimized', 736, 108, size: 20);

    final samples = [
      ('Document default / 16px', '', 16.0),
      ('Settings menu / 14px', 'SimHei', 14.0),
      ('Latin font with Chinese / 16px', 'Arial', 16.0),
      ('Explicit Microsoft YaHei / 16px', 'Microsoft YaHei', 16.0),
    ];
    for (var i = 0; i < samples.length; i++) {
      final (label, oldFamily, size) = samples[i];
      final y = 156.0 + i * 132;
      final newFamily = i == 1
          ? resolvePlatformFontFamily('')
          : resolvePlatformFontFamily(oldFamily);
      for (final x in [32.0, 736.0]) {
        _draw(canvas, label, x, y, size: 13, muted: true);
      }
      const content = '小马笔记：让知识清晰可见，记录每一次思考。\n'
          '窗口缩放、中文笔画、标点符号；PonyNotes 0123456789。';
      _draw(canvas, content, 32, y + 28, size: size, family: oldFamily);
      _draw(
        canvas,
        content,
        736,
        y + 28,
        size: size,
        family: newFamily,
        fallback: platformFontFamilyFallback,
      );
    }
    _draw(
      canvas,
      'This isolates font selection. It does not simulate ClearType '
      'or an engine hinting change.',
      32,
      708,
      size: 13,
      muted: true,
    );
    _draw(
      canvas,
      'Open at 100% image zoom to compare physical pixels. '
      'Existing Microsoft YaHei may look the same.',
      32,
      736,
      size: 13,
      muted: true,
    );

    final picture = recorder.endRecording();
    final image =
        await picture.toImage((1440 * dpr).round(), (784 * dpr).round());
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final path = '${output.path}/text-${(dpr * 100).round()}.png';
    await File(path).writeAsBytes(png!.buffer.asUint8List());
    stdout.writeln(File(path).absolute.path);
    image.dispose();
    picture.dispose();
  }
  exit(0);
}

void _draw(
  ui.Canvas canvas,
  String text,
  double x,
  double y, {
  double size = 16,
  String family = 'Segoe UI',
  List<String>? fallback,
  bool muted = false,
}) {
  final builder = ui.ParagraphBuilder(
    ui.ParagraphStyle(textDirection: ui.TextDirection.ltr, height: 1.7),
  )
    ..pushStyle(
      ui.TextStyle(
        fontFamily: family,
        fontFamilyFallback: fallback,
        fontSize: size,
        fontWeight: ui.FontWeight.w400,
        color: ui.Color(muted ? 0xFF666666 : 0xFF2F3030),
      ),
    )
    ..addText(text);
  final paragraph = builder.build()
    ..layout(const ui.ParagraphConstraints(width: 660));
  canvas.drawParagraph(paragraph, ui.Offset(x, y));
  paragraph.dispose();
}

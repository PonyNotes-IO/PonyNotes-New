import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:appflowy/features/agent/application/agent_artifact_preview.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List office(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  test(
      'Office previews preserve Chinese text, spreadsheet references and slide order',
      () {
    expect(
      extractOfficeArtifact(
        (
          office({
            'word/document.xml':
                '<w:document xmlns:w="word"><w:p><w:r><w:t>会议纪要</w:t></w:r></w:p><w:p><w:r><w:t>周五交付</w:t></w:r></w:p></w:document>',
          }),
          '.docx'
        ),
      ),
      '会议纪要\n周五交付',
    );
    final sheet = extractOfficeArtifact(
      (
        office({
          'xl/sharedStrings.xml': '<sst><si><t>项目</t></si></sst>',
          'xl/worksheets/sheet1.xml':
              '<worksheet><row><c r="A1" t="s"><v>0</v></c><c r="C1"><v>42</v></c><c r="D1" t="inlineStr"><is><t>完成</t></is></c></row></worksheet>',
        }),
        '.xlsx'
      ),
    );
    expect(sheet, contains('A1: 项目    C1: 42    D1: 完成'));
    final slides = extractOfficeArtifact(
      (
        office({
          'ppt/slides/slide10.xml': '<slide><p><t>第十页</t></p></slide>',
          'ppt/slides/slide2.xml': '<slide><p><t>第二页</t></p></slide>',
        }),
        '.pptx'
      ),
    );
    expect(slides.indexOf('第二页'), lessThan(slides.indexOf('第十页')));
  });
  test('large document parts and invalid office files report preview failure',
      () {
    expect(
      () => extractOfficeArtifact(
        (office({'word/document.xml': 'x' * (8 * 1024 * 1024 + 1)}), '.docx'),
      ),
      throwsFormatException,
    );
    expect(
      () => extractOfficeArtifact(
        (office({'irrelevant.xml': '<empty/>'}), '.docx'),
      ),
      throwsFormatException,
    );
  });
  test(
      'text preview reads a bounded prefix while leaving original bytes intact',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('artifact-preview-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/report.txt');
    await file.writeAsString('本地文件');
    expect(await readArtifactText(file), '本地文件');
    await file.writeAsString('a' * (300 * 1024));
    expect(await readArtifactText(file), contains('仅预览前 256 KB'));
    expect(await file.length(), 300 * 1024);
  });
}

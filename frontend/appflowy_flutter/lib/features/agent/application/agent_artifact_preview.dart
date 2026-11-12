import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

const artifactTextExtensions = {
  '.txt',
  '.md',
  '.markdown',
  '.json',
  '.csv',
  '.tsv',
  '.log',
  '.yaml',
  '.yml',
  '.xml',
  '.html',
  '.css',
  '.js',
  '.ts',
  '.dart',
  '.rs',
  '.py',
  '.sh',
  '.sql',
  '.toml',
};
const artifactOfficeExtensions = {'.docx', '.xlsx', '.pptx'};

Future<String> readArtifactText(File file) async {
  final extension = p.extension(file.path).toLowerCase();
  if (artifactOfficeExtensions.contains(extension)) {
    if (await file.length() > 16 * 1024 * 1024) {
      throw const FormatException('文件较大，请使用外部应用打开');
    }
    return compute(
      extractOfficeArtifact,
      (await file.readAsBytes(), extension),
    );
  }
  const limit = 256 * 1024;
  final bytes = <int>[];
  await for (final chunk in file.openRead(0, limit)) {
    bytes.addAll(chunk);
  }
  var text = utf8.decode(bytes, allowMalformed: true);
  if (await file.length() > limit) text += '\n\n… 仅预览前 256 KB，完整内容请打开文件。';
  return text;
}

/// Office preview reads document text only; macros, links and embedded objects never run.
String extractOfficeArtifact((Uint8List, String) input) {
  final archive = ZipDecoder().decodeBytes(input.$1);
  var budget = 16 * 1024 * 1024;
  XmlDocument xml(ArchiveFile entry) {
    budget -= entry.size;
    if (entry.size > 8 * 1024 * 1024 || budget < 0) {
      throw const FormatException('文件较复杂，请使用外部应用打开');
    }
    return XmlDocument.parse(utf8.decode(entry.content as List<int>));
  }

  final output = StringBuffer();
  if (input.$2 == '.xlsx') {
    final strings = <String>[];
    final shared = archive.findFile('xl/sharedStrings.xml');
    if (shared != null) {
      for (final node in xml(shared)
          .descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'si')) {
        strings.add(
          node.descendants
              .whereType<XmlElement>()
              .where((e) => e.name.local == 't')
              .map((e) => e.innerText)
              .join(),
        );
      }
    }
    final sheets = archive.files
        .where((e) => RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(e.name))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    for (final sheet in sheets) {
      output.writeln(p.basenameWithoutExtension(sheet.name));
      for (final row in xml(sheet)
          .descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'row')) {
        final cells = <String>[];
        for (final cell
            in row.childElements.where((e) => e.name.local == 'c')) {
          final values = cell.descendants
              .whereType<XmlElement>()
              .where((e) => e.name.local == 'v' || e.name.local == 't');
          var value = values.map((e) => e.innerText).join();
          if (cell.getAttribute('t') == 's') {
            final index = int.tryParse(value);
            if (index != null && index >= 0 && index < strings.length) {
              value = strings[index];
            }
          }
          cells.add('${cell.getAttribute('r') ?? ''}: $value');
        }
        output.writeln(cells.join('    '));
        if (output.length > 256 * 1024) break;
      }
      output.writeln();
      if (output.length > 256 * 1024) break;
    }
  } else {
    final entries = archive.files
        .where(
          (e) => input.$2 == '.docx'
              ? e.name == 'word/document.xml'
              : RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(e.name),
        )
        .toList()
      ..sort((a, b) => _partNumber(a.name).compareTo(_partNumber(b.name)));
    for (final entry in entries) {
      if (input.$2 == '.pptx') {
        output.writeln('幻灯片 ${_partNumber(entry.name)}\n');
      }
      for (final paragraph in xml(entry)
          .descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'p')) {
        output.writeln(
          paragraph.descendants
              .whereType<XmlElement>()
              .where((e) => e.name.local == 't')
              .map((e) => e.innerText)
              .join(),
        );
        if (output.length > 256 * 1024) break;
      }
      output.writeln();
      if (output.length > 256 * 1024) break;
    }
  }
  final text = output.toString().trim();
  if (text.isEmpty) throw const FormatException('未提取到可预览的文字，请使用外部应用打开');
  return text.length > 256 * 1024
      ? '${text.substring(0, 256 * 1024)}\n\n… 更多内容请打开文件。'
      : text;
}

int _partNumber(String name) =>
    int.tryParse(RegExp(r'(\d+)\.xml$').firstMatch(name)?.group(1) ?? '') ?? 0;

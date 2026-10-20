import 'dart:convert';
import 'dart:io';

import 'package:appflowy/plugins/handwriting_saber/application/handwriting_file_store.dart';
import 'package:appflowy/plugins/handwriting_saber/application/handwriting_saber_data_service.dart';
import 'package:appflowy/plugins/handwriting_saber/third_party/saber_core/data/editor/editor_core_info.dart';
import 'package:appflowy/plugins/handwriting_saber/third_party/saber_core/data/editor/page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy page and identical stroke IDs are deterministic and distinct',
      () {
    final data = utf8.encode(jsonEncode({
      'pages': [
        {
          'strokes': [
            {'points': []},
            {'points': []}
          ]
        },
        {
          'strokes': [
            {'points': []}
          ]
        },
      ],
    }));
    final first = HandwritingSaberDataService.normalizeLegacy('note', data);
    expect(HandwritingSaberDataService.normalizeLegacy('note', data), first);
    final doc = jsonDecode(utf8.decode(first));
    expect(doc['pages'][0]['id'], isNot(doc['pages'][1]['id']));
    final ids = [
      for (final page in doc['pages'])
        for (final stroke in page['strokes']) stroke['id']
    ];
    expect(ids.toSet().length, 3);
  });

  test('shape IDs and fields survive editor roundtrip and page reconstruction',
      () {
    final document = EditorCoreInfo.fromJson({
      'future': {'keep': true},
      'pages': [
        {
          'id': 'page',
          'width': 595,
          'height': 842,
          '_syncOrder': '8000',
          'futurePage': 123,
          'webViews': [
            {'id': 42, 'url': 'https://example.com', 'i': 0}
          ],
          'strokes': [
            for (final shape in [
              'line',
              'arrowLine',
              'rectangle',
              'circle',
              'triangle',
              'diamond',
              'freePolygon'
            ])
              {
                'id': shape,
                'shape': shape,
                'points': [
                  {'x': 10, 'y': 10},
                  {'x': 40, 'y': 40}
                ],
                'color': 0xff123456,
                'strokeWidth': 2,
                'futureStroke': true
              },
          ],
          'images': [
            {
              'id': 'image',
              'type': 'image',
              'imageBytes': [1, 2, 3],
              'extension': '.png',
              'pageIndex': 0,
              'pageSize': {'width': 595, 'height': 842},
              'dstRect': {'left': 0, 'top': 0, 'width': 100, 'height': 100},
            }
          ],
        }
      ],
    });
    final page = document.pages.single;
    final updated = page.copyWith(textBoxes: []);
    expect(updated.id, 'page');
    expect(updated.images, same(page.images));
    expect(updated.webViews, same(page.webViews));
    expect(updated.quill, same(page.quill));
    final roundtrip = EditorCoreInfo.fromJsonString(document.toJsonString());
    expect(roundtrip.extra['future'], {'keep': true});
    expect(roundtrip.pages.single.extra['futurePage'], 123);
    expect(roundtrip.pages.single.webViews.single.id, 42);
    for (final stroke in roundtrip.pages.single.strokes) {
      expect(stroke.toJson()['shape'], stroke.id);
      expect(stroke.toJson()['futureStroke'], true);
    }
    for (final doc in [document, roundtrip]) {
      for (final page in doc.pages) {
        page.quill.dispose();
        for (final web in page.webViews) {
          web.dispose();
        }
        for (final image in page.images) {
          image.dispose();
        }
      }
    }
  });

  test('queued file commits keep latest content and original recovery copies',
      () async {
    final directory =
        Directory.systemTemp.createTempSync('handwriting-storage-');
    try {
      final path = '${directory.path}/note.sbn2';
      await HandwritingFileStore.write(path, [1]);
      final first = HandwritingFileStore.write(path, [2]);
      final latest = HandwritingFileStore.write(path, [3]);
      await Future.wait([first, latest]);
      expect(await HandwritingFileStore.read(path), [3]);
      expect(await File('$path.previous').readAsBytes(), [2]);
      expect(await File('$path.legacy').readAsBytes(), [1]);
      expect(
          directory.listSync().where((f) => f.path.endsWith('.tmp')), isEmpty);
    } finally {
      directory.deleteSync(recursive: true);
    }
  });

  test('page copying retains all preexisting fields', () {
    final page = EditorPage(size: const Size(595, 842), extra: {'future': 1});
    final copy = page.copyWith(size: const Size(600, 800));
    expect(copy.id, page.id);
    expect(copy.extra, page.extra);
    expect(copy.size, const Size(600, 800));
    page.quill.dispose();
  });
  test('page duplicate rekeys every entity and retains shapes and attachments',
      () {
    final source = {
      'id': 'page',
      'width': 595,
      'height': 842,
      'strokes': [
        {'id': 'stroke', 'shape': 'circle', 'points': []}
      ],
      'images': [
        {'id': 'image', 'imageBase64': 'aW1hZ2U='}
      ],
      'webViews': [
        {'id': 'web', 'url': 'https://example.com'}
      ],
      'textBoxes': [
        {'id': 'text', 'text': 'hello'}
      ],
      'listBoxes': [
        {'id': 'list', 'items': []}
      ],
      'taskListBoxes': [
        {'id': 'task', 'items': []}
      ],
      'backgroundImage': {'pdfFilePath': '/original.pdf', 'pdfPageIndex': 2},
      'quill': {
        'document': [
          {'insert': 'hello\n'}
        ]
      },
    };
    final copied = jsonDecode(jsonEncode(source)) as Map<String, dynamic>;
    HandwritingSaberDataService.assignNewPageIds(copied);
    expect(copied['id'], isNot(source['id']));
    for (final kind in [
      'strokes',
      'images',
      'webViews',
      'textBoxes',
      'listBoxes',
      'taskListBoxes'
    ]) {
      final original = (source[kind] as List).single;
      final actual = copied[kind][0];
      expect(actual['id'], isNot(original['id']));
      for (final entry in (original as Map).entries) {
        if (entry.key != 'id') expect(actual[entry.key], entry.value);
      }
    }
    expect(copied['backgroundImage'], source['backgroundImage']);
    expect(copied['quill'], source['quill']);
  });
  test('legacy PDF metadata survives when optional natural size was absent',
      () {
    final page = EditorPage.fromJson({
      'id': 'page',
      'width': 595,
      'height': 842,
      'backgroundImage': {
        'pdfFilePath': '/original.pdf',
        'pdfPageIndex': 2,
        'futurePdf': 123
      },
    });
    expect(page.backgroundImage?.pdfFilePath, '/original.pdf');
    expect(page.backgroundImage?.naturalSize, const Size(595, 842));
    expect(page.toJson()['backgroundImage']['futurePdf'], 123);
    page.backgroundImage?.dispose();
    page.quill.dispose();
  });
  test('legacy numeric and missing WebView IDs stay valid for the editor', () {
    final normalized = HandwritingSaberDataService.normalizeLegacy(
        'note',
        utf8.encode(jsonEncode({
          'pages': [
            {
              'webViews': [
                {'id': 42, 'url': 'https://example.com'},
                {'url': 'https://example.org'}
              ]
            }
          ],
        })));
    final doc = jsonDecode(utf8.decode(normalized));
    expect(doc['pages'][0]['webViews'][0]['id'], 42);
    expect(doc['pages'][0]['webViews'][1]['id'], isA<int>());
    expect(HandwritingSaberDataService.normalizeLegacy('note', normalized),
        normalized);
    final ids = {
      for (var i = 0; i < 100; i++) HandwritingSaberDataService.newWebViewId()
    };
    expect(ids.length, 100);
  });
}

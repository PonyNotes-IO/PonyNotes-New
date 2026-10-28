import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/plugins/handwriting_saber/application/handwriting_pdf_cache_service.dart';
import 'package:appflowy/plugins/handwriting_saber/third_party/saber_core/components/canvas/image/pdf_editor_image.dart';
import 'package:appflowy/plugins/handwriting_saber/third_party/saber_core/data/editor/page.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pdfrx/pdfrx.dart';

class _PdfEntryFunctions extends Mock implements PdfrxEntryFunctions {}

class _PdfDocument extends Mock implements PdfDocument {}

class _PdfPage extends Mock implements PdfPage {}

class _RecoverablePdfImage extends PdfEditorImage {
  _RecoverablePdfImage(String localPath)
      : super(
          pdfFilePath: localPath,
          pdfUrl: 'https://example.com/blob/test.pdf',
          pdfPageIndex: 0,
          naturalSize: const Size(595, 842),
        );

  int refreshes = 0;

  @override
  Future<void> downloadFromCloud({bool forceDownload = false}) async {
    expect(forceDownload, isTrue);
    refreshes++;
    pdfBytes = Uint8List.fromList(utf8.encode('%PDF-1.7\nrepaired'));
  }
}

class _DownloadingPdfImage extends PdfEditorImage {
  _DownloadingPdfImage()
      : super(
          pdfFilePath: 'https://example.com/pending.pdf',
          pdfPageIndex: 0,
          naturalSize: const Size(595, 842),
        );

  final downloadedPath = Completer<String>();

  @override
  Future<void> downloadFromCloud({bool forceDownload = false}) async {
    pdfFilePath = await downloadedPath.future;
  }
}

void main() {
  final manager = PdfDocumentCacheManager();
  final images = <PdfEditorImage>[];
  late Directory directory;
  late PdfrxEntryFunctions originalEntryFunctions;
  late _PdfEntryFunctions entryFunctions;

  PdfDocument document({int pageCount = 1}) {
    final result = _PdfDocument();
    when(() => result.pages)
        .thenReturn(List.generate(pageCount, (_) => _PdfPage()));
    when(result.dispose).thenAnswer((_) async {});
    return result;
  }

  PdfEditorImage image(String path, {Uint8List? bytes}) {
    final result = PdfEditorImage(
      pdfFilePath: path,
      pdfPageIndex: 0,
      naturalSize: const Size(595, 842),
      pdfBytes: bytes,
    );
    images.add(result);
    return result;
  }

  setUpAll(() {
    Log.shared.disableLog = true;
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    directory = Directory.systemTemp.createTempSync('ponynotes-pdf-test-');
    originalEntryFunctions = PdfrxEntryFunctions.instance;
    entryFunctions = _PdfEntryFunctions();
    PdfrxEntryFunctions.instance = entryFunctions;
  });

  tearDown(() async {
    for (final item in images) {
      item.dispose();
    }
    images.clear();
    manager.clearAllCache();
    PdfrxEntryFunctions.instance = originalEntryFunctions;
    await directory.delete(recursive: true);
  });

  tearDownAll(() {
    manager.dispose();
    Log.shared.disableLog = false;
  });

  group('PDF document lifecycle', () {
    test('missing file can be opened after it becomes available', () async {
      final file = File('${directory.path}/recovered.pdf');
      await expectLater(
        manager.load(file.path),
        throwsA(isA<FileSystemException>()),
      );
      file.writeAsStringSync('%PDF-1.7');
      final recovered = document();
      when(() => entryFunctions.openFile(file.path))
          .thenAnswer((_) async => recovered);

      expect(await manager.load(file.path), same(recovered));
      verify(() => entryFunctions.openFile(file.path)).called(1);
    });

    test('release removes completed document before reopening', () async {
      final file = File('${directory.path}/reopen.pdf')
        ..writeAsStringSync('%PDF-1.7');
      final first = document();
      final second = document();
      var opens = 0;
      when(() => entryFunctions.openFile(file.path))
          .thenAnswer((_) async => opens++ == 0 ? first : second);

      expect(await manager.load(file.path), same(first));
      manager.releaseDocument(file.path);
      expect(await manager.load(file.path), same(second));
      verify(first.dispose).called(1);
    });

    test('invalidated pending load cannot replace a newer document', () async {
      final file = File('${directory.path}/late.pdf')
        ..writeAsStringSync('%PDF-1.7');
      final oldResult = Completer<PdfDocument>();
      final newResult = Completer<PdfDocument>();
      var opens = 0;
      when(() => entryFunctions.openFile(file.path)).thenAnswer(
        (_) => opens++ == 0 ? oldResult.future : newResult.future,
      );

      final oldLoad = manager.load(file.path);
      final oldFailure = expectLater(oldLoad, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      manager.invalidate(file.path);
      final newLoad = manager.load(file.path);
      final current = document();
      newResult.complete(current);
      expect(await newLoad, same(current));

      final outdated = document();
      oldResult.complete(outdated);
      await oldFailure;
      expect(await manager.load(file.path), same(current));
      verify(outdated.dispose).called(1);
    });

    test('capacity cleanup keeps documents retained by active pages', () async {
      final documents = <PdfDocument>[];
      final paths = <String>[];
      final owners = <Object>[];
      for (var i = 0; i < PdfDocumentCacheManager.maxCacheSize + 2; i++) {
        final file = File('${directory.path}/active_$i.pdf')
          ..writeAsStringSync('%PDF-1.7');
        final opened = document();
        documents.add(opened);
        paths.add(file.path);
        when(() => entryFunctions.openFile(file.path))
            .thenAnswer((_) async => opened);
        final owner = Object();
        owners.add(owner);
        manager.retainDocument(file.path, owner);
        await manager.load(file.path);
      }
      for (final opened in documents) {
        verifyNever(opened.dispose);
      }
      for (var i = 0; i < paths.length; i++) {
        manager.releaseDocumentUsage(paths[i], owners[i]);
      }
      expect(
        manager.getCacheStats()['completedDocuments'],
        PdfDocumentCacheManager.maxCacheSize,
      );
      verify(documents.first.dispose).called(1);
    });
  });

  group('PDF page reopening', () {
    testWidgets('云地址尚未同步时显示同步中，不解析源设备路径或提前报错', (tester) async {
      final missingPath = '${directory.path}/source-device.pdf';
      final original = image(missingPath);
      final sourcePage = EditorPage(
        size: const Size(595, 842),
        backgroundImage: original,
      );
      addTearDown(sourcePage.quill.dispose);
      final received = EditorPage.fromJson(sourcePage.toJson(forCollab: true));
      addTearDown(received.quill.dispose);
      final pending = received.backgroundImage!;
      images.add(pending);
      await pending.loadPdfDocument();
      expect(pending.loadState, PdfLoadState.waitingForSync);
      expect(pending.isFailed, isFalse);
      expect(pending.loadError, isNull);

      await tester.pumpWidget(
        MaterialApp(
          home: pending.buildPdfPageWidget(boxFit: BoxFit.contain),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        find.text(LocaleKeys.newSettings_syncState_syncing),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.error_outline), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      expect(pending.loadState, PdfLoadState.waitingForSync);
      expect(manager.getCacheStats()['cachedDocuments'], 0);
      verifyNever(() => entryFunctions.openFile(any()));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    test('云地址后续到达可从等待同步继续加载，页面引用不被修改', () async {
      final original = image('${directory.path}/source-device.pdf');
      final sourcePage = EditorPage(
        size: const Size(595, 842),
        backgroundImage: original,
      );
      addTearDown(sourcePage.quill.dispose);
      final beforeUpload = sourcePage.toJson(forCollab: true);
      final received = EditorPage.fromJson(beforeUpload);
      addTearDown(received.quill.dispose);
      final pending = received.backgroundImage!;
      images.add(pending);
      await pending.loadPdfDocument();
      expect(pending.loadState, PdfLoadState.waitingForSync);
      expect(received.toJson(forCollab: true), beforeUpload);

      original.pdfUrl = 'https://example.com/synced.pdf';
      final updated = EditorPage.fromJson(sourcePage.toJson(forCollab: true));
      addTearDown(updated.quill.dispose);
      final ready = updated.backgroundImage!;
      images.add(ready);
      final downloaded = File('${directory.path}/downloaded.pdf')
        ..writeAsStringSync('%PDF-1.7');
      // 模拟现有磁盘缓存已准备好，真实下载由独立流测试覆盖。
      ready.pdfFilePath = downloaded.path;
      final opened = document();
      when(() => entryFunctions.openFile(downloaded.path))
          .thenAnswer((_) async => opened);
      await ready.loadPdfDocument();
      expect(ready.loadState, PdfLoadState.loaded);
      expect(ready.synchronousPdfDocument, same(opened));
      expect(updated.id, received.id);
      expect(ready.pdfPageIndex, pending.pdfPageIndex);
    });

    testWidgets('真正下载期间显示加载中，下载完成后可正常解析', (tester) async {
      final page = _DownloadingPdfImage();
      images.add(page);
      final load = page.loadPdfDocument();
      expect(page.loadState, PdfLoadState.loading);
      await tester.pumpWidget(
        MaterialApp(
          home: page.buildPdfPageWidget(boxFit: BoxFit.contain),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(LocaleKeys.editor_loading), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);
      await tester.pump(const Duration(seconds: 10));
      expect(page.loadState, PdfLoadState.loading);
      await tester.pumpWidget(const SizedBox.shrink());
      final file = File('${directory.path}/cloud.pdf')
        ..writeAsStringSync('%PDF-1.7');
      final opened = document();
      when(() => entryFunctions.openFile(file.path))
          .thenAnswer((_) async => opened);
      page.downloadedPath.complete(file.path);
      await load;
      expect(page.loadState, PdfLoadState.loaded);
    });

    testWidgets('空引用仍显示失败，不会被无限归入等待同步', (tester) async {
      final page = image('');
      await page.loadPdfDocument();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(page.loadState, PdfLoadState.failed);
      expect(page.loadError, contains('PDF file path is empty'));
    });

    test('没有本地文件时保留内存解析所需的完整字节', () async {
      final bytes = Uint8List.fromList(utf8.encode('%PDF-1.7\nmemory only'));
      final opened = document();
      when(() => entryFunctions.openData(bytes, sourceName: 'memory:only'))
          .thenAnswer((_) async => opened);
      final page = image('memory:only', bytes: bytes);
      await page.loadPdfDocument();
      expect(page.isLoaded, isTrue);
      expect(page.pdfBytes, same(bytes));
      expect(page.synchronousPdfDocument, same(opened));
    });

    test('300页共用一次文件解析，打开后释放额外的整份字节', () async {
      final bytes = Uint8List.fromList(utf8.encode('%PDF-1.7\n300 pages'));
      final file = File('${directory.path}/300pages.pdf')
        ..writeAsBytesSync(bytes);
      final opened = document(pageCount: 300);
      when(() => entryFunctions.openFile(file.path))
          .thenAnswer((_) async => opened);
      final pages = List.generate(
        300,
        (index) => PdfEditorImage(
          pdfFilePath: file.path,
          pdfPageIndex: index,
          naturalSize: const Size(595, 842),
          pdfBytes: bytes,
        ),
      );
      images.addAll(pages);
      await Future.wait(pages.map((page) => page.loadPdfDocument()));
      expect(pages.every((page) => page.isLoaded), isTrue);
      expect(pages.every((page) => page.pdfBytes == null), isTrue);
      expect(
        pages.every((page) => page.synchronousPdfDocument == opened),
        isTrue,
      );
      verify(() => entryFunctions.openFile(file.path)).called(1);
    });

    test('overlapping preload and reset share one open task', () async {
      final file = File('${directory.path}/shared.pdf')
        ..writeAsStringSync('%PDF-1.7');
      final pending = Completer<PdfDocument>();
      when(() => entryFunctions.openFile(file.path))
          .thenAnswer((_) => pending.future);
      final page = image(file.path);
      page.preloadPdfDocument();
      page.resetLoadStateAndPreload();
      final load = page.loadPdfDocument();
      final opened = document();
      pending.complete(opened);
      await load;

      expect(page.loadState, PdfLoadState.loaded);
      expect(await page.cachedPdfDocument, same(opened));
      page.resetLoadStateAndPreload();
      expect(page.synchronousPdfDocument, same(opened));
      verify(() => entryFunctions.openFile(file.path)).called(1);
    });

    test('unparseable cached PDF is refreshed from cloud once', () async {
      final file = File('${directory.path}/broken.pdf')
        ..writeAsStringSync('%PDF-truncated');
      final repaired = document();
      var opens = 0;
      when(() => entryFunctions.openFile(file.path)).thenAnswer((_) async {
        if (opens++ == 0) throw const FormatException('truncated PDF');
        return repaired;
      });
      final page = _RecoverablePdfImage(file.path);
      images.add(page);

      await page.loadPdfDocument();
      expect(page.loadState, PdfLoadState.loaded);
      expect(page.refreshes, 1);
      expect(page.synchronousPdfDocument, same(repaired));
      expect(file.readAsStringSync(), '%PDF-truncated');
      verify(() => entryFunctions.openFile(file.path)).called(2);
    });

    testWidgets('automatic retries stop after two additional attempts',
        (tester) async {
      final bytes = Uint8List.fromList(utf8.encode('%PDF-invalid'));
      when(() => entryFunctions.openData(any(), sourceName: 'memory:invalid'))
          .thenAnswer((_) async => throw const FormatException('invalid PDF'));
      final page = image('memory:invalid', bytes: bytes);
      await page.loadPdfDocument();
      expect(page.loadState, PdfLoadState.loading);
      await tester.pumpWidget(
        MaterialApp(
          home: page.buildPdfPageWidget(boxFit: BoxFit.contain),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(page.loadState, PdfLoadState.loading);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 5));

      expect(page.loadState, PdfLoadState.failed);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      verify(() => entryFunctions.openData(any(), sourceName: 'memory:invalid'))
          .called(3);
      await tester.pumpWidget(const SizedBox.shrink());
      page.dispose();
    });

    test('dispose while opening ignores the late result', () async {
      final file = File('${directory.path}/dispose.pdf')
        ..writeAsStringSync('%PDF-1.7');
      final pending = Completer<PdfDocument>();
      when(() => entryFunctions.openFile(file.path))
          .thenAnswer((_) => pending.future);
      final page = image(file.path);
      final load = page.loadPdfDocument();
      page.dispose();
      pending.complete(document());
      await load;
      expect(page.synchronousPdfDocument, isNull);
    });

    testWidgets('open timeout stops retrying and disposes its late result',
        (tester) async {
      final pending = Completer<PdfDocument>();
      when(() => entryFunctions.openData(any(), sourceName: 'memory:timeout'))
          .thenAnswer((_) => pending.future);
      final page = image(
        'memory:timeout',
        bytes: Uint8List.fromList(utf8.encode('%PDF-1.7')),
      );
      final load = page.loadPdfDocument();
      await tester.pump();
      await tester.pump(const Duration(seconds: 60));
      await load;
      expect(page.loadState, PdfLoadState.failed);
      expect(page.loadError, contains('TimeoutException'));
      await tester.pump(const Duration(seconds: 5));
      verify(() => entryFunctions.openData(any(), sourceName: 'memory:timeout'))
          .called(1);
      final outdated = document();
      pending.complete(outdated);
      await tester.pump();
      verify(outdated.dispose).called(1);
      page.dispose();
    });

    test('legacy cloud path is recognized without separate pdfUrl', () {
      const url = 'https://example.com/blob/legacy.pdf';
      expect(image(url).pdfUrl, url);
      final legacy = PdfEditorImage(
        pdfFilePath: url,
        pdfUrl: '',
        pdfPageIndex: 0,
        naturalSize: const Size(595, 842),
      );
      images.add(legacy);
      expect(legacy.pdfUrl, url);
    });

    test('local page serialization preserves the imported file reference', () {
      final original = image('${directory.path}/imported.pdf');
      original.pdfUrl = 'https://example.com/blob/uploaded.pdf';
      final page =
          EditorPage(size: const Size(595, 842), backgroundImage: original);
      final reopened = EditorPage.fromJson(page.toJson()).backgroundImage!;
      images.add(reopened);
      expect(reopened.pdfFilePath, original.pdfFilePath);
      expect(reopened.pdfUrl, original.pdfUrl);
      final synced =
          EditorPage.fromJson(page.toJson(forCollab: true)).backgroundImage!;
      images.add(synced);
      expect(synced.pdfFilePath, original.pdfUrl);
    });

    test('a newer cloud URL takes precedence over a stale cloud path', () {
      final original = image('https://example.com/blob/old.pdf');
      original.pdfUrl = 'https://example.com/blob/new.pdf';
      final page = EditorPage(
        size: const Size(595, 842),
        backgroundImage: original,
      );
      final reopened = EditorPage.fromJson(page.toJson()).backgroundImage!;
      images.add(reopened);
      expect(reopened.pdfFilePath, original.pdfUrl);
    });
  });

  group('PDF disk cache recovery', () {
    late HandwritingPdfCacheService cache;
    const url = 'https://example.com/blob/cache.pdf';
    final bytes = Uint8List.fromList(utf8.encode('%PDF-1.7\ncomplete'));

    setUp(() => cache = HandwritingPdfCacheService.forTesting(directory.path));

    test('same filename in different cloud paths has isolated cache entries',
        () async {
      const first = 'https://example.com/workspace-a/file.pdf';
      const second = 'https://example.com/workspace-b/file.pdf';
      final a = await cache.put(first, bytes);
      final bBytes = Uint8List.fromList(utf8.encode('%PDF-1.7\nother'));
      final b = await cache.put(second, bBytes);
      expect(a, isNot(b));
      expect(await File(a!).readAsBytes(), bytes);
      expect(await File(b!).readAsBytes(), bBytes);
      expect(await cache.resolvedPath('$first?temporary=1'), a);
    });

    test('legacy cache remains readable without deleting the only old copy',
        () async {
      final legacy = File('${directory.path}/cache.pdf')
        ..writeAsBytesSync(bytes);
      final migrated = await cache.cachedPathIfExists(url);
      expect(migrated, isNotNull);
      expect(migrated, isNot(legacy.path));
      expect(await File(migrated!).readAsBytes(), bytes);
      expect(await legacy.readAsBytes(), bytes);
    });

    test('LRU evicts downloads while imported originals and old files survive',
        () async {
      final original = await cache.cacheImportedPdf(bytes);
      final old = File('${directory.path}/old-original.pdf')
        ..writeAsBytesSync(bytes);
      final expired =
          File((await cache.resolvedPath('https://example.com/expired.pdf')));
      final sparse = expired.openSync(mode: FileMode.write);
      sparse.truncateSync(HandwritingPdfCacheService.maxCacheBytes + 1);
      sparse.closeSync();
      await expired.setLastModified(DateTime(2000));
      await cache.put(url, bytes);
      for (var i = 0; i < 100 && await expired.exists(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(await expired.exists(), isFalse);
      expect(await File(original).readAsBytes(), bytes);
      expect(await old.readAsBytes(), bytes);
    });

    test('concurrent pages share a complete download', () async {
      var downloads = 0;
      final pending = Completer<Uint8List>();
      final loads = List.generate(
        12,
        (_) => cache.load(
          url,
          download: () {
            downloads++;
            return pending.future;
          },
        ),
      );
      pending.complete(bytes);
      final results = await Future.wait(loads);
      expect(downloads, 1);
      for (final entry in results) {
        expect(await File(entry.path!).readAsBytes(), bytes);
      }
      expect(
        directory.listSync().where((file) => file.path.endsWith('.tmp')),
        isEmpty,
      );
    });

    test('correct bytes replace equally sized damaged cache', () async {
      final path = await cache.resolvedPath(url);
      File(path).writeAsBytesSync(List.filled(bytes.length, 0x78));
      expect(await cache.put(url, bytes), path);
      expect(await File(path).readAsBytes(), bytes);
    });

    test('disk cache is reused after recreating the service', () async {
      final path = await cache.put(url, bytes);
      final reopened = HandwritingPdfCacheService.forTesting(directory.path);
      final entry = await reopened.load(
        url,
        download: () async {
          fail('A valid disk cache must not require network access');
        },
      );
      expect(entry.path, path);
    });

    test('failed refresh preserves the previous file and allows retry',
        () async {
      final path = (await cache.put(url, bytes))!;
      await expectLater(
        cache.load(
          url,
          forceDownload: true,
          download: () async {
            throw const HttpException('HTTP 503');
          },
        ),
        throwsA(isA<HttpException>()),
      );
      expect(await File(path).readAsBytes(), bytes);
      final updated = Uint8List.fromList(utf8.encode('%PDF-1.7\nupdated'));
      await cache.load(url, forceDownload: true, download: () async => updated);
      expect(await File(path).readAsBytes(), updated);
    });

    test('invalid cache falls back to downloading a PDF', () async {
      final path = await cache.resolvedPath(url);
      File(path).writeAsStringSync('<html>expired</html>');
      var downloads = 0;
      final entry = await cache.load(
        url,
        download: () async {
          downloads++;
          return bytes;
        },
      );
      expect(downloads, 1);
      expect(await File(entry.path!).readAsBytes(), bytes);
    });

    test('HTML response cannot replace a valid cached PDF', () async {
      final path = (await cache.put(url, bytes))!;
      await expectLater(
        cache.load(
          url,
          forceDownload: true,
          download: () async {
            return Uint8List.fromList(utf8.encode('<html>error</html>'));
          },
        ),
        throwsFormatException,
      );
      expect(await File(path).readAsBytes(), bytes);
    });
  });
}

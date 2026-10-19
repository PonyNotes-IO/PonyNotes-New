import 'dart:async';
import 'dart:io';

import 'package:appflowy/plugins/handwriting_saber/application/handwriting_pdf_asset_uploader.dart';
import 'package:appflowy/plugins/handwriting_saber/third_party/saber_core/components/canvas/image/pdf_editor_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _UploadImage extends PdfEditorImage {
  _UploadImage(String path, int index, this.upload)
      : super(
          pdfFilePath: path,
          pdfPageIndex: index,
          naturalSize: const Size(595, 842),
        );

  final Future<String?> Function() upload;

  @override
  Future<String?> uploadToCloud() => upload();
}

void main() {
  late Directory directory;
  final images = <PdfEditorImage>[];

  setUp(() {
    directory = Directory.systemTemp.createTempSync('ponynotes-pdf-upload-');
  });
  tearDown(() {
    for (final image in images) {
      image.dispose();
    }
    images.clear();
    directory.deleteSync(recursive: true);
  });

  String file(String name) {
    final result = File('${directory.path}/$name.pdf')
      ..writeAsStringSync('%PDF');
    return result.path;
  }

  List<PdfEditorImage> pages(
    String path,
    Future<String?> Function() upload, {
    int count = 15,
  }) {
    final result = List.generate(count, (i) => _UploadImage(path, i, upload));
    images.addAll(result);
    return result;
  }

  test('15页与并发保存只上传同一份PDF一次，且页码保持完整', () async {
    final uploader = HandwritingPdfAssetUploader();
    final response = Completer<String>();
    var calls = 0;
    final backgrounds = pages(file('shared'), () {
      calls++;
      return response.future;
    });

    final first = uploader.upload(backgrounds);
    final second = uploader.upload(backgrounds);
    expect(calls, 1);
    response.complete('https://example.com/shared.pdf');
    await Future.wait([first, second]);

    expect(calls, 1);
    expect(
      backgrounds.map((image) => image.pdfUrl).toSet(),
      {'https://example.com/shared.pdf'},
    );
    expect(
      backgrounds.map((image) => image.pdfPageIndex),
      List.generate(15, (i) => i),
    );
  });

  test('同文件已有云地址时回填其余页面，不重新上传', () async {
    var calls = 0;
    final backgrounds = pages(file('uploaded'), () async {
      calls++;
      return null;
    });
    backgrounds.last.pdfUrl = 'https://example.com/existing.pdf';

    await HandwritingPdfAssetUploader().upload(backgrounds);
    expect(calls, 0);
    expect(
      backgrounds.map((image) => image.pdfUrl).toSet(),
      {'https://example.com/existing.pdf'},
    );
  });

  test('同路径页面已有不同云地址时保留原引用，只回填缺失地址', () async {
    var calls = 0;
    final backgrounds = pages(file('legacy'), () async {
      calls++;
      return null;
    });
    backgrounds.first.pdfUrl = 'https://example.com/first.pdf';
    backgrounds.last.pdfUrl = 'https://example.com/last.pdf';
    await HandwritingPdfAssetUploader().upload(backgrounds);
    expect(calls, 0);
    expect(backgrounds.first.pdfUrl, 'https://example.com/first.pdf');
    expect(backgrounds.last.pdfUrl, 'https://example.com/last.pdf');
    expect(backgrounds[7].pdfUrl, backgrounds.first.pdfUrl);
  });

  test('失败按文件最多重试一次，后续保存仍可恢复且不同文件不混用地址', () async {
    final uploader = HandwritingPdfAssetUploader();
    var sharedCalls = 0;
    final shared = pages(file('retry'), () async {
      sharedCalls++;
      return sharedCalls <= 2 ? null : 'https://example.com/retry.pdf';
    });
    await uploader.upload(shared);
    expect(sharedCalls, 2);
    expect(shared.every((image) => image.pdfUrl == null), isTrue);

    var otherCalls = 0;
    final other = pages(file('other'), () async {
      otherCalls++;
      return 'https://example.com/other.pdf';
    });
    await uploader.upload([...shared, ...other]);
    expect(sharedCalls, 3);
    expect(otherCalls, 1);
    expect(
      shared.map((image) => image.pdfUrl).toSet(),
      {'https://example.com/retry.pdf'},
    );
    expect(
      other.map((image) => image.pdfUrl).toSet(),
      {'https://example.com/other.pdf'},
    );
  });

  test('异常不会阻断排队中的下一次上传', () async {
    final uploader = HandwritingPdfAssetUploader();
    var calls = 0;
    final backgrounds = pages(file('recover'), () async {
      if (++calls == 1) throw StateError('temporary failure');
      return 'https://example.com/recovered.pdf';
    });
    final first = uploader.upload(backgrounds);
    final firstFailure = expectLater(first, throwsStateError);
    final second = uploader.upload(backgrounds);
    await firstFailure;
    await second;
    expect(calls, 2);
    expect(backgrounds.every((image) => image.pdfUrl != null), isTrue);
  });
}

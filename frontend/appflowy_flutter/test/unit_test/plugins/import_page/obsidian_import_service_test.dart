import 'dart:io';

import 'package:appflowy/plugins/import_page/obsidian_import_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('vault import preserves parents, duplicate titles and partial failures',
      () async {
    final vault = await Directory('.dart_tool').createTemp('obsidian-import-');
    expect(p.isWithin(Directory.current.path, vault.absolute.path), isTrue);
    addTearDown(() => vault.delete(recursive: true));
    Future<void> note(String path, String text) async {
      final file = File(p.join(vault.path, path));
      await file.parent.create(recursive: true);
      await file.writeAsString(text);
    }

    await note('首页.md', '# 你好');
    await note('Projects/Plan.md', '# 项目计划');
    await note('Projects/2026/Plan.MD', '# 年度计划');
    await note('Archive/Plan.markdown', '# 归档计划');
    await note('Empty.md', '');
    await note('.obsidian/settings.md', 'ignore');
    await note('.trash/deleted.md', 'ignore');
    await note('attachments/manual.pdf', 'ignore');
    final pages = <String, ({String parent, String name, String? content})>{};
    final progress = <(int, int)>[];
    final count = await importObsidianVault(
      vault,
      parentViewId: 'external-space',
      createPage: (parent, name, content) async {
        expect(parent == 'external-space' || pages.containsKey(parent), isTrue);
        final id = 'page-${pages.length}';
        pages[id] = (parent: parent, name: name, content: content);
        return id;
      },
      onProgress: (completed, total) => progress.add((completed, total)),
    );
    String id(String name) =>
        pages.entries.singleWhere((entry) => entry.value.name == name).key;
    final root = id(p.basename(vault.path));
    expect(count, 5);
    expect(pages[root]!.parent, 'external-space');
    expect(pages[id('Projects')]!.parent, root);
    expect(pages[id('2026')]!.parent, id('Projects'));
    expect(pages[id('Archive')]!.parent, root);
    expect(pages[id('首页')]!.content, '# 你好');
    expect(pages[id('Empty')]!.content, '');
    final plans = pages.values.where((page) => page.name == 'Plan').toList();
    expect(
      plans.map((page) => page.parent).toSet(),
      {id('Projects'), id('2026'), id('Archive')},
    );
    expect(pages.values.any((page) => page.name == 'attachments'), isFalse);
    expect(pages.values.any((page) => page.content == 'ignore'), isFalse);
    expect(progress.last, (9, 9));

    // A failed parent must never cause its children to be flattened at the root.
    final attempted = <String>[];
    await expectLater(
      importObsidianVault(
        vault,
        parentViewId: 'external-space',
        createPage: (parent, name, content) async {
          attempted.add(name);
          if (name == 'Projects') throw StateError('disk full');
          return name;
        },
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'partial import report',
          allOf(contains('Projects'), contains('已创建'), contains('disk full')),
        ),
      ),
    );
    expect(attempted, isNot(contains('2026')));
    expect(await File(p.join(vault.path, '首页.md')).readAsString(), '# 你好');

    final empty = await vault.createTemp('empty-');
    await expectLater(
      importObsidianVault(
        empty,
        parentViewId: 'external-space',
        createPage: (_, __, ___) => throw StateError('must not create pages'),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'empty vault report',
          contains('没有 Markdown'),
        ),
      ),
    );
  });
}

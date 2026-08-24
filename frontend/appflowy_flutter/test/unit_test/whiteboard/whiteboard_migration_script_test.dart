import 'package:appflowy/plugins/whiteboard/presentation/whiteboard_migration_script.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('迁移脚本覆盖全部场景写入路径且不误伤文件接口', () {
    final pattern = RegExp(whiteboardMigrationScenePostPattern);

    for (final path in <String>[
      '/api/scenes',
      '/api/scenes/',
      '/api/scenes?source=migration',
      '/api/scenes/room_123',
      '/api/scenes/v2',
      '/api/scenes/v2/',
      '/api/scenes/v2/post',
      '/api/scenes/v2/post/',
      'https://xm-arts.xiaomabiji.com/api/scenes/v2/post/',
    ]) {
      expect(pattern.hasMatch(path), isTrue, reason: path);
    }

    for (final path in <String>[
      '/api/scenes/files/hash/file-id',
      '/api/scenes/v2/room-id',
      '/api/scenes/v2/post/file-id',
      '/api/other',
    ]) {
      expect(pattern.hasMatch(path), isFalse, reason: path);
    }

    expect(
      whiteboardMigrationScript,
      contains('/$whiteboardMigrationScenePostPattern/.test(url)'),
    );
  });
}

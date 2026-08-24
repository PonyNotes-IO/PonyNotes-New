import 'package:appflowy/plugins/whiteboard/application/whiteboard_migration_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('协作白板迁回私有空间的旧原生库兼容写入', () {
    test('为目标场景已删除的历史元素生成墓碑', () {
      final payload =
          WhiteboardMigrationService.buildCompatibleReplacementPayload(
        current: {
          'elements': [
            {'id': 'keep', 'version': 2, 'isDeleted': false},
            {'id': 'stale', 'version': 7, 'isDeleted': false},
          ],
        },
        replacement: {
          'type': 'excalidraw',
          'elements': [
            {'id': 'keep', 'version': 3, 'isDeleted': false},
          ],
          'files': <String, dynamic>{},
        },
      );

      final elements = payload['elements'] as List<dynamic>;
      expect(elements, hasLength(2));
      expect(
        elements.singleWhere((e) => e['id'] == 'stale'),
        containsPair('isDeleted', true),
      );
      expect(
        elements.singleWhere((e) => e['id'] == 'stale')['version'],
        8,
      );
    });

    test('本地同 id 版本更高时抬高目标元素版本以保证覆盖', () {
      final payload =
          WhiteboardMigrationService.buildCompatibleReplacementPayload(
        current: {
          'elements': [
            {'id': 'same', 'version': 12, 'text': '旧内容'},
          ],
        },
        replacement: {
          'elements': [
            {'id': 'same', 'version': 4, 'text': '协作区最新内容'},
          ],
        },
      );

      final element = (payload['elements'] as List<dynamic>).single;
      expect(element['version'], 13);
      expect(element['text'], '协作区最新内容');
    });

    test('空白目标场景会删除全部历史元素且不携带 room 凭据', () {
      final payload =
          WhiteboardMigrationService.buildCompatibleReplacementPayload(
        current: {
          'roomId': 'old-room',
          'roomKey': 'old-key',
          'elements': [
            {'id': 'old', 'version': 1},
          ],
        },
        replacement: {
          'type': 'excalidraw',
          'version': 2,
          'elements': <dynamic>[],
          'files': <String, dynamic>{},
        },
      );

      expect(payload, isNot(contains('roomId')));
      expect(payload, isNot(contains('roomKey')));
      expect(
        (payload['elements'] as List<dynamic>).single,
        containsPair('isDeleted', true),
      );
    });
  });
}

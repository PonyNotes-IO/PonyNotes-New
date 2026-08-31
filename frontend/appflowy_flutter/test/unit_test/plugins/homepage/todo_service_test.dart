import 'package:appflowy/plugins/homepage/application/todo_service.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('calendar event identity removes linked-view duplicates', () {
    final seen = <String>{};
    final event = CalendarEventPB(
      rowMeta: RowMetaPB(id: 'row-1'),
      dateFieldId: 'date-1',
    );

    // 首次见到 row-1，应该是新事件
    expect(isNewCalendarEvent(seen, event), isTrue);

    // 同一个 row-1，同一个 dateFieldId，应该被去重
    expect(
      isNewCalendarEvent(
        seen,
        CalendarEventPB(
          rowMeta: RowMetaPB(id: 'row-1'),
          dateFieldId: 'date-1',
        ),
      ),
      isFalse,
    );

    // 同一个 row-1，不同 dateFieldId（跨 Calendar 视图），也应该被去重
    // 这修复了多个 Calendar 视图引用同一 row 时主页重复展示的问题
    expect(
      isNewCalendarEvent(
        seen,
        CalendarEventPB(
          rowMeta: RowMetaPB(id: 'row-1'),
          dateFieldId: 'date-2',
        ),
      ),
      isFalse,
    );

    // 不同 row-2，即使 dateFieldId 相同，也应该是新事件
    expect(
      isNewCalendarEvent(
        seen,
        CalendarEventPB(
          rowMeta: RowMetaPB(id: 'row-2'),
          dateFieldId: 'date-1',
        ),
      ),
      isTrue,
    );
  });
}

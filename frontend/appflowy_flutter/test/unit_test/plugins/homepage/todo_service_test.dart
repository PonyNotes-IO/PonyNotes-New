import 'package:appflowy/plugins/homepage/application/todo_service.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('calendar event identity removes linked-view duplicates', () {
    final seen = <(String, String)>{};
    final event = CalendarEventPB(
      rowMeta: RowMetaPB(id: 'row-1'),
      dateFieldId: 'date-1',
    );

    expect(isNewCalendarEvent(seen, event), isTrue);
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
    expect(
      isNewCalendarEvent(
        seen,
        CalendarEventPB(
          rowMeta: RowMetaPB(id: 'row-1'),
          dateFieldId: 'date-2',
        ),
      ),
      isTrue,
    );
  });
}

import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/cell_entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/date_entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';

final class DateCellBackendService {
  DateCellBackendService({
    required String viewId,
    required String fieldId,
    required String rowId,
  }) : cellId = CellIdPB()
          ..viewId = viewId
          ..fieldId = fieldId
          ..rowId = rowId;

  final CellIdPB cellId;

  Future<FlowyResult<void, FlowyError>> update({
    bool? includeTime,
    bool? isRange,
    DateTime? date,
    DateTime? endDate,
    String? reminderId,
    int? repeatType,
    String? repeatRuleJson,
  }) {
    final payload = DateCellChangesetPB()..cellId = cellId;

    // 只在调试模式下打印详细日志
    if (kDebugMode) {
      print('📝 [DateCellBackendService] update 调用参数:');
      print('  - includeTime: $includeTime');
      print('  - isRange: $isRange');
      print('  - date: $date');
      print('  - endDate: $endDate');
      print('  - reminderId: $reminderId');
      print('  - repeatType: $repeatType');
      print('  - repeatRuleJson: $repeatRuleJson');
    }

    if (includeTime != null) {
      payload.includeTime = includeTime;
    }
    if (isRange != null) {
      payload.isRange = isRange;
    }
    if (date != null) {
      final dateTimestamp = date.millisecondsSinceEpoch ~/ 1000;
      payload.timestamp = Int64(dateTimestamp);
    }
    if (endDate != null) {
      final dateTimestamp = endDate.millisecondsSinceEpoch ~/ 1000;
      payload.endTimestamp = Int64(dateTimestamp);
    }
    if (reminderId != null) {
      payload.reminderId = reminderId;
    }
    
    if (repeatType != null) {
      payload.repeatType = repeatType;
    }

    if (repeatRuleJson != null) {
      payload.repeatRuleJson = repeatRuleJson;
    }
    return DatabaseEventUpdateDateCell(payload).send();
  }

  Future<FlowyResult<void, FlowyError>> clear() {
    final payload = DateCellChangesetPB()
      ..cellId = cellId
      ..clearFlag = true;

    return DatabaseEventUpdateDateCell(payload).send();
  }
}

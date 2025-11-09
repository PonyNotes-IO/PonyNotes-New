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
    
    // 注意：repeatType 和 repeatRuleJson 是 one_of 字段
    // 必须显式设置，即使值是 0 或空字符串，也要设置，以便在查询时能够正确读取
    // 如果不设置，protobuf 可能不会序列化这些字段，导致查询时 hasRepeatType() 返回 false
    // 重要：对于 one_of 字段，即使值是默认值，也要显式设置，确保 Protobuf 会序列化该字段
    final finalRepeatType = repeatType ?? 0;
    final finalRepeatRuleJson = repeatRuleJson ?? '';
    
    // 总是设置 repeatType，即使值是 0（默认值）
    payload.repeatType = finalRepeatType;
    if (kDebugMode) {
      print('  ✅ [DateCellBackendService] 设置 repeatType: $finalRepeatType (原始值: $repeatType)');
    }
    
    // 总是设置 repeatRuleJson，即使值是空字符串（默认值）
    payload.repeatRuleJson = finalRepeatRuleJson;
    if (kDebugMode) {
      print('  ✅ [DateCellBackendService] 设置 repeatRuleJson: "$finalRepeatRuleJson" (原始值: $repeatRuleJson)');
    }
    
    if (kDebugMode) {
      print('📤 [DateCellBackendService] 发送 DateCellChangesetPB:');
      print('  - hasRepeatType: ${payload.hasRepeatType()}');
      print('  - repeatType: ${payload.repeatType}');
      print('  - hasRepeatRuleJson: ${payload.hasRepeatRuleJson()}');
      print('  - repeatRuleJson: ${payload.repeatRuleJson}');
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

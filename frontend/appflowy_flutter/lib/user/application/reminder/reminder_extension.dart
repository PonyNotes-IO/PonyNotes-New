import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';

class ReminderMetaKeys {
  static String includeTime = "include_time";
  static String blockId = "block_id";
  static String rowId = "row_id";
  static String createdAt = "created_at";
  static String isArchived = "is_archived";
  static String date = "date";
  static String notificationType = "notification_type";
  static String isRecurring = "is_recurring";
  static String recurrenceInstanceId = "recurrence_instance_id";
}

enum ReminderType {
  past,
  today,
  other,
}

extension ReminderExtension on ReminderPB {
  bool? get includeTime {
    final String? includeTimeStr = meta[ReminderMetaKeys.includeTime];

    return includeTimeStr != null ? includeTimeStr == true.toString() : null;
  }

  String? get blockId => meta[ReminderMetaKeys.blockId];

  String? get rowId => meta[ReminderMetaKeys.rowId];

  int? get createdAt {
    final t = meta[ReminderMetaKeys.createdAt];
    return t != null ? int.tryParse(t) : null;
  }

  bool get isArchived {
    final t = meta[ReminderMetaKeys.isArchived];
    return t != null ? t == true.toString() : false;
  }

  DateTime? get date {
    final t = meta[ReminderMetaKeys.date];
    return t != null ? DateTime.fromMillisecondsSinceEpoch(int.parse(t)) : null;
  }

  ReminderType get type {
    final date = this.date?.millisecondsSinceEpoch;

    if (date == null) {
      return ReminderType.other;
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    if (date < now) {
      return ReminderType.past;
    }

    final difference = date - now;
    const oneDayInMilliseconds = 24 * 60 * 60 * 1000;

    if (difference < oneDayInMilliseconds) {
      return ReminderType.today;
    }

    return ReminderType.other;
  }

  /// Get notification type from meta, with fallback to message content analysis
  /// Returns null if type cannot be determined
  String? get notificationType {
    final typeStr = meta[ReminderMetaKeys.notificationType];
    if (typeStr != null && typeStr.isNotEmpty) {
      return typeStr;
    }
    
    // Fallback to message content analysis for backward compatibility
    if (message.contains('@')) {
      return 'mention';
    } else if (message.contains('剪藏') || message.contains('Clip')) {
      return 'clip';
    } else if (message.contains('提醒') || message.contains('Reminder')) {
      return 'reminder';
    } else {
      return 'system';
    }
  }
}

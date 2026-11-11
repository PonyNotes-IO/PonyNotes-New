import 'dart:convert';

// 重复规则处理类
class RecurrenceRule {
  RecurrenceRule({
    required this.repeatType,
    this.repeatRuleJson,
    required this.startDate,
    this.endDate,
  });

  final int repeatType; // 0=无 1=每天 2=每周 3=每年 4=法定工作日 99=自定义
  final String? repeatRuleJson; // 自定义规则JSON
  final DateTime startDate; // 原始开始日期
  /// 勿将日程单次结束时间当作重复截止；仅 JSON 中 until/endDate 表示「重复截止到某日」
  final DateTime? endDate;

  // 判断某个日期是否匹配重复规则
  bool matchesDate(DateTime date) {
    if (repeatType == 0) {
      return false;
    }

    final dateOnly = _getDateOnly(date);
    final startDateOnly = _getDateOnly(startDate);
    // 仅使用重复规则 JSON 里的截止日期；不用日程 endTime（跨天日程的结束日会错误截断整段重复）
    final repeatUntil = _getRuleEndDate();

    // 如果日期在原始日期之前，不匹配（所有重复类型都允许匹配过去日期）

    if (repeatUntil != null && dateOnly.isAfter(_getDateOnly(repeatUntil))) {
      return false;
    }

    switch (repeatType) {
      case 1: // 每天
        return true;

      case 2: // 每周：仅「周期锚点日」（与开始日同一星期几），且与开始日相差整周
        if (repeatRuleJson != null && repeatRuleJson!.isNotEmpty) {
          try {
            final rule = jsonDecode(repeatRuleJson!) as Map<String, dynamic>;
            final weekdays = rule['weekdays'] as List<dynamic>?;
            if (weekdays != null && weekdays.isNotEmpty) {
              final weekdayList = weekdays.map((e) => (e as int) + 1).toList();
              if (!weekdayList.contains(date.weekday)) return false;
              final diff = dateOnly.difference(startDateOnly).inDays;
              return diff % 7 == 0;
            }
          } catch (_) {}
        }
        if (date.weekday != startDate.weekday) return false;
        final d = dateOnly.difference(startDateOnly).inDays;
        return d % 7 == 0;

      case 3: // 每年
        return date.month == startDate.month && date.day == startDate.day;

      case 4: // 法定工作日（需要节假日库）
        if (date.weekday == 6 || date.weekday == 7) {
          return false;
        }
        return true;

      case 99: // 自定义
        return _matchesCustomRule(date);

      default:
        return false;
    }
  }

  // 解析自定义规则（如"每1周的周一"）
  bool _matchesCustomRule(DateTime date) {
    if (repeatRuleJson == null || repeatRuleJson!.isEmpty) {
      return false;
    }

    try {
      // 解析规则：如"每1周的周一、周三" -> {"unit": 1, "interval": 1, "weekdays": [1, 3]}
      final rule = jsonDecode(repeatRuleJson!);
      final unit = rule['unit'] ?? 1; // 0=天 1=周 2=月 3=年
      final interval = rule['interval'] ?? 1;
      final weekdays = rule['weekdays'] as List<dynamic>?;

      final dateOnly = _getDateOnly(date);
      final startDateOnly = _getDateOnly(startDate);
      final daysDiff = dateOnly.difference(startDateOnly).inDays;

      switch (unit) {
        case 0: // 每 N 天
          // 每 interval 天重复一次
          return daysDiff >= 0 && daysDiff % interval == 0;

        case 1: // 每 N 周的特定星期几
          if (weekdays == null || weekdays.isEmpty) {
            return false;
          }
          // 自定义对话框保存的 weekday 索引为 0..6（周一..周日），
          // 而 DateTime.weekday 为 1..7（周一..周日）。需要做 +1 映射。
          final weekdayList = weekdays.map((e) => (e as int) + 1).toList();
          if (!weekdayList.contains(date.weekday)) {
            return false;
          }

          // 计算从开始日期所在周（周一为起点）到目标日期所在周的天数
          // 先把两个日期都对齐到各自的周一
          final startWeekday = startDateOnly.weekday; // 1=周一
          final dateWeekday = dateOnly.weekday; // 1=周一
          final daysToStartMonday = startDateOnly.day - startWeekday;
          final daysToDateMonday = dateOnly.day - dateWeekday;
          final startMonday =
              startDateOnly.subtract(Duration(days: daysToStartMonday));
          final dateMonday =
              dateOnly.subtract(Duration(days: daysToDateMonday));
          // 两个周一之间的天数差，再除以7得到周数差
          final weeksDiff = dateMonday.difference(startMonday).inDays ~/ 7;

          return weeksDiff >= 0 && weeksDiff % interval == 0;

        case 2: // 每 N 月
          // 计算月份差
          final monthsDiff = (date.year - startDate.year) * 12 +
              (date.month - startDate.month);
          if (monthsDiff < 0 || monthsDiff % interval != 0) {
            return false;
          }
          // 在同一个月内，日期应该相同或接近（处理月末情况）
          // 如果开始日期是月末（如31日），目标月份可能没有31日，则使用该月最后一天
          final targetDay =
              _getDayInMonth(date.year, date.month, startDate.day);
          return date.day == targetDay;

        case 3: // 每 N 年
          // 计算年份差
          final yearsDiff = date.year - startDate.year;
          if (yearsDiff < 0 || yearsDiff % interval != 0) {
            return false;
          }
          // 在同一年内，月份和日期应该相同
          // 处理闰年2月29日的情况：如果开始日期是2月29日，目标年份不是闰年，则使用2月28日
          if (startDate.month == 2 && startDate.day == 29) {
            // 闰年2月29日的情况
            final isLeapYear = _isLeapYear(date.year);
            if (isLeapYear) {
              return date.month == 2 && date.day == 29;
            } else {
              return date.month == 2 && date.day == 28;
            }
          }
          return date.month == startDate.month && date.day == startDate.day;

        default:
          return false;
      }
    } catch (e) {
      print('⚠️ [RecurrenceRule] 解析自定义规则失败: $e');
      return false;
    }
  }

  DateTime? _getRuleEndDate() {
    if (repeatRuleJson == null || repeatRuleJson!.isEmpty) {
      return null;
    }
    try {
      final rule = jsonDecode(repeatRuleJson!);
      if (rule is! Map<String, dynamic>) {
        return null;
      }
      final raw = rule['endDate'] ??
          rule['until'] ??
          rule['untilDate'] ??
          rule['end_at'] ??
          rule['endTimestamp'];
      if (raw == null) {
        return null;
      }
      if (raw is int) {
        final millis = raw > 1000000000000 ? raw : raw * 1000;
        return DateTime.fromMillisecondsSinceEpoch(millis);
      }
      if (raw is String && raw.isNotEmpty) {
        final asInt = int.tryParse(raw);
        if (asInt != null) {
          final millis = asInt > 1000000000000 ? asInt : asInt * 1000;
          return DateTime.fromMillisecondsSinceEpoch(millis);
        }
        return DateTime.tryParse(raw);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // 获取日期部分（去除时分秒）
  DateTime _getDateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  // 获取月份中的有效日期（处理月末情况）
  int _getDayInMonth(int year, int month, int day) {
    // 获取该月的最大天数
    final daysInMonth = DateTime(year, month + 1, 0).day;
    // 如果指定的日期超过该月的最大天数，返回该月的最后一天
    return day > daysInMonth ? daysInMonth : day;
  }

  // 判断是否为闰年
  bool _isLeapYear(int year) {
    return (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
  }
}

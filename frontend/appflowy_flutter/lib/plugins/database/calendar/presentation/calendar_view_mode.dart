/// 日历视图模式枚举
enum CalendarViewMode {
  day, // 日视图：单日时间轴
  week, // 周视图：周一到周日 + 时间轴
  month, // 月视图：日期网格
}

extension CalendarViewModeX on CalendarViewMode {
  String get label {
    switch (this) {
      case CalendarViewMode.day:
        return '日';
      case CalendarViewMode.week:
        return '周';
      case CalendarViewMode.month:
        return '月';
    }
  }
}

import 'package:appflowy_backend/protobuf/flowy-user/date_time.pbenum.dart';
import 'package:easy_localization/easy_localization.dart';

const _localFmt = 'MM/dd/y';
const _usFmt = 'y/MM/dd';
const _isoFmt = 'y-MM-dd';
const _friendlyFmt = 'MMM dd, y';
const _dmyFmt = 'dd/MM/y';

extension DateFormatter on UserDateFormatPB {
  DateFormat get toFormat {
    try {
      return DateFormat(_toFormat[this] ?? _friendlyFmt);
    } catch (_) {
      // fallback to en-US
      return DateFormat(_toFormat[this] ?? _friendlyFmt, 'en-US');
    }
  }

  String formatDate(
    DateTime date,
    bool includeTime, [
    UserTimeFormatPB? timeFormat,
  ]) {
    final format = toFormat;

    if (includeTime) {
      switch (timeFormat) {
        case UserTimeFormatPB.TwentyFourHour:
          return format.add_Hm().format(date);
        case UserTimeFormatPB.TwelveHour:
          // 在 zh_CN 等 locale 下 add_jm() 会输出 24 小时制，用显式 12h 模式并沿用当前 locale 的上午/下午
          final time12 = DateFormat('h:mm a').format(date);
          return '${format.format(date)} $time12';
        default:
          return format.format(date);
      }
    }

    return format.format(date);
  }
}

final _toFormat = {
  UserDateFormatPB.Locally: _localFmt,
  UserDateFormatPB.US: _usFmt,
  UserDateFormatPB.ISO: _isoFmt,
  UserDateFormatPB.Friendly: _friendlyFmt,
  UserDateFormatPB.DayMonthYear: _dmyFmt,
};

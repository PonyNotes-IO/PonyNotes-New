import 'package:fixnum/fixnum.dart' as $fixnum;

extension DateConversion on $fixnum.Int64 {
  DateTime toDateTime() {
    final raw = toInt();
    if (raw <= 0) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    // Normalize mixed backend timestamp units:
    // - seconds (10 digits)
    // - milliseconds (13 digits)
    // - microseconds (16 digits)
    final normalizedMillis = switch (raw) {
      >= 1000000000000000 => raw ~/ 1000, // microseconds -> milliseconds
      >= 1000000000000 => raw, // already milliseconds
      _ => raw * 1000, // seconds -> milliseconds
    };
    return DateTime.fromMillisecondsSinceEpoch(normalizedMillis);
  }
}

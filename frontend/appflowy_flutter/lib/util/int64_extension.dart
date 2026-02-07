import 'package:fixnum/fixnum.dart' as $fixnum;

extension DateConversion on $fixnum.Int64 {
  DateTime toDateTime() => DateTime.fromMillisecondsSinceEpoch(toInt());
}

import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:intl/intl.dart';

final _storageNumberFormat = NumberFormat()
  ..maximumFractionDigits = 2
  ..minimumFractionDigits = 0;

extension PresentableUsage on WorkspaceUsagePB {
  /// 总空间（GB 显示）。当限额为 0 时返回 '0'；不限时调用方应自行判断
  /// [storageBytesUnlimited]，本方法按限额实际数值输出。
  String get totalBlobInGb {
    if (storageBytesLimit == 0) {
      return '0';
    }
    return _storageNumberFormat
        .format(storageBytesLimit.toInt() / (1024 * 1024 * 1024));
  }

  /// 剩余空间（GB 显示）。剩余为 0 或负数时返回 '0'；调用方应自行判断
  /// [storageBytesUnlimited] 走「不限」分支。
  String get remainingBlobInGb {
    if (storageBytesLimit == 0) {
      return '0';
    }
    final remaining = storageBytesLimit.toInt() - storageBytes.toInt();
    if (remaining <= 0) {
      return '0';
    }
    return _storageNumberFormat.format(remaining / (1024 * 1024 * 1024));
  }

  /// We use [NumberFormat] to format the current blob in GB.
  ///
  /// Where the [totalBlobBytes] is the total blob bytes in bytes.
  /// And [NumberFormat.maximumFractionDigits] is set to 2.
  /// And [NumberFormat.minimumFractionDigits] is set to 0.
  ///
  String get currentBlobInGb =>
      _storageNumberFormat.format(storageBytes.toInt() / 1024 / 1024 / 1024);
}

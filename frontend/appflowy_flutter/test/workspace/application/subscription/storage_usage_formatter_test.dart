import 'package:appflowy/workspace/application/subscription/storage_usage_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatRemainingStorageUsage', () {
    test('电脑端和移动端使用相同的剩余空间数值', () {
      expect(
        formatRemainingStorageUsage(usedGb: 1, totalGb: 50),
        '49G/50G',
      );
      expect(
        formatRemainingStorageUsage(
          usedGb: 1,
          totalGb: 50,
          gbUnit: 'GB',
          mbUnit: 'MB',
          separator: ' / ',
        ),
        '49GB / 50GB',
      );
    });

    test('剩余不足 1GB 时转换为 MB', () {
      expect(
        formatRemainingStorageUsage(usedGb: 49.5, totalGb: 50),
        '512M/50G',
      );
    });

    test('已用空间超过总量时剩余空间不小于零', () {
      expect(
        formatRemainingStorageUsage(usedGb: 51, totalGb: 50),
        '0M/50G',
      );
    });
  });
}

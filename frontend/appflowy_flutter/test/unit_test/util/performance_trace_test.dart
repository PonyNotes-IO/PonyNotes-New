import 'package:appflowy/util/performance_trace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('performance budgets warn only after their target', () {
    expect(
      PerformanceBudget.shouldWarn(
        'first_frame',
        PerformanceBudget.firstFrameTargetMs,
      ),
      isFalse,
    );
    expect(
      PerformanceBudget.shouldWarn(
        'first_frame',
        PerformanceBudget.firstFrameTargetMs + 1,
      ),
      isTrue,
    );
    expect(
      PerformanceBudget.shouldWarn(
        'startup_task_end',
        PerformanceBudget.startupTaskWarningMs,
      ),
      isFalse,
    );
  });
}

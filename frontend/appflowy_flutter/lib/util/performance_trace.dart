import 'dart:developer' as developer;

import 'package:appflowy/util/diagnostic_build.dart';

/// Enables performance markers without changing app behavior or sending user
/// content anywhere. Keep this off for normal builds.
const bool ponyNotesPerformanceTraceEnabled = bool.fromEnvironment(
  'PONYNOTES_PERFORMANCE_TRACE',
);

class PerformanceBudget {
  const PerformanceBudget._();

  static const firstFrameTargetMs = 1000;
  static const startupTaskWarningMs = 500;

  static bool shouldWarn(String stage, int durationMs) {
    switch (stage) {
      case 'first_frame':
        return durationMs > firstFrameTargetMs;
      case 'startup_task_end':
        return durationMs > startupTaskWarningMs;
      default:
        return false;
    }
  }
}

class PerformanceTrace {
  PerformanceTrace._();

  static final Stopwatch _clock = Stopwatch()..start();
  static final Map<String, int> _taskStartTimes = {};

  static bool get enabled =>
      ponyNotesPerformanceTraceEnabled || ponyNotesDiagnosticBuildEnabled;

  static void mark(
    String stage, {
    Map<String, Object?> fields = const {},
    int? durationMs,
  }) {
    if (!enabled) {
      return;
    }

    final elapsedMs = _clock.elapsedMilliseconds;
    final timelineFields = <String, dynamic>{
      'elapsedMs': elapsedMs,
      ...fields,
    };
    if (durationMs != null) {
      timelineFields['durationMs'] = durationMs;
    }
    developer.Timeline.instantSync(
      'PonyNotes.$stage',
      arguments: timelineFields,
    );
    logDiagnosticEvent(
      'performance',
      stage,
      timelineFields,
      warning: PerformanceBudget.shouldWarn(
        stage,
        durationMs ?? elapsedMs,
      ),
    );
  }

  static void startupTaskStart(String key, String taskName) {
    if (!enabled) {
      return;
    }

    _taskStartTimes[key] = _clock.elapsedMilliseconds;
    mark('startup_task_start', fields: {'task': taskName});
  }

  static void startupTaskEnd(
    String key,
    String taskName, {
    required bool success,
    Object? error,
  }) {
    if (!enabled) {
      return;
    }

    final startedAt = _taskStartTimes.remove(key);
    final durationMs =
        startedAt == null ? null : _clock.elapsedMilliseconds - startedAt;
    mark(
      'startup_task_end',
      fields: {
        'task': taskName,
        'success': success,
        if (error != null) 'errorType': error.runtimeType.toString(),
      },
      durationMs: durationMs,
    );
  }
}

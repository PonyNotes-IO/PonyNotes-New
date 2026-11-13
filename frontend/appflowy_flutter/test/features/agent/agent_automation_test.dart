import 'package:appflowy/features/agent/application/agent_automation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the fields Cloud exposes for a scheduled run', () {
    final automation = AgentAutomation.fromJson({
      'id': 'a1',
      'name': '每日汇总',
      'description': '汇总昨日笔记',
      'enabled': true,
      'instruction': '总结昨天的笔记',
      'model_id': 'm1',
      'trigger': {'type': 'cron', 'expr': '0 9 * * *', 'timezone': 'Asia/Shanghai'},
      'session_mode': 'persistent',
      'misfire_policy': 'run_once',
      'overlap_policy': 'queue',
      'limits': {'max_duration_minutes': 30},
      'notify_on_success': false,
      'next_run_at': '2026-11-14T01:00:00Z',
      'last_run_status': 'failed',
      'consecutive_failures': 2,
    });

    expect(automation.id, 'a1');
    expect(automation.name, '每日汇总');
    expect(automation.triggerType, 'cron');
    expect(automation.triggerExpr, '0 9 * * *');
    expect(automation.sessionMode, 'persistent');
    expect(automation.overlapPolicy, 'queue');
    expect(automation.maxDurationMinutes, 30);
    expect(automation.notifyOnSuccess, false);
    expect(automation.lastRunStatus, 'failed');
    expect(automation.consecutiveFailures, 2);
    expect(automation.scheduleLabel, '0 9 * * *');
  });

  test('saves the whole editable record so a toggle can omit the model', () {
    final automation = AgentAutomation.fromJson({
      'id': 'a1',
      'name': '汇总',
      'instruction': '总结',
      'trigger': {'type': 'cron', 'expr': '0 9 * * *', 'timezone': 'UTC'},
      'session_mode': 'per_run',
      'misfire_policy': 'skip',
      'overlap_policy': 'skip',
      'enabled': true,
    });

    final body = automation.toSaveBody(enabledOverride: false);

    expect(body['enabled'], false);
    expect(body['name'], '汇总');
    expect(body['instruction'], '总结');
    expect(body['session_mode'], 'per_run');
    expect(body['trigger'], {
      'type': 'cron',
      'expr': '0 9 * * *',
      'timezone': 'UTC',
    });
    expect(body.containsKey('model'), false);
  });

  test('labels run statuses and keeps cancellable ones', () {
    final run = AgentAutomationRun.fromJson({
      'id': 'r1',
      'status': 'running',
      'scheduled_at': '2026-11-14T01:00:00Z',
      'started_at': '2026-11-14T01:00:05Z',
      'finished_at': '2026-11-14T01:02:05Z',
    });

    expect(run.statusLabel, '运行中');
    expect(run.cancellable, true);
    expect(run.durationLabel, '2m0s');
    expect(AgentAutomationRun.labelOf('needs_attention'), '需要处理');
    expect(AgentAutomationRun.labelOf('unknown'), 'unknown');
  });
}

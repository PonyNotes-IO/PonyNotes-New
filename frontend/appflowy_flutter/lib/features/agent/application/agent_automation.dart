/// Automations are scheduled and executed by WeKnora; Cloud scopes them to a
/// workspace and owns the model credentials, so these models mirror the subset
/// of fields the client is allowed to see and set.
class AgentAutomation {
  const AgentAutomation({
    required this.id,
    required this.name,
    this.description = '',
    this.enabled = true,
    this.instruction = '',
    this.modelId = '',
    this.triggerType = 'cron',
    this.triggerExpr = '',
    this.triggerAt = '',
    this.timezone = 'Asia/Shanghai',
    this.sessionMode = 'per_run',
    this.carryLastResult = false,
    this.misfirePolicy = 'skip',
    this.overlapPolicy = 'skip',
    this.approvalTimeoutMinutes,
    this.maxDurationMinutes,
    this.notifyOnSuccess = true,
    this.nextRunAt,
    this.lastRunAt,
    this.lastRunStatus,
    this.activeRunStatus,
    this.consecutiveFailures = 0,
    this.pausedReason,
  });

  factory AgentAutomation.fromJson(Map value) {
    final trigger = value['trigger'] is Map ? value['trigger'] as Map : const {};
    final limits = value['limits'] is Map ? value['limits'] as Map : const {};
    final runtime = value['runtime'] is Map ? value['runtime'] as Map : const {};
    return AgentAutomation(
      id: value['id'] as String,
      name: (value['name'] as String?) ?? '',
      description: (value['description'] as String?) ?? '',
      enabled: value['enabled'] != false,
      instruction: (value['instruction'] as String?) ?? '',
      modelId: (value['model_id'] as String?) ?? '',
      triggerType: (trigger['type'] as String?) ?? 'cron',
      triggerExpr: (trigger['expr'] as String?) ?? '',
      triggerAt: (trigger['at'] as String?) ?? '',
      timezone: (trigger['timezone'] as String?) ?? 'Asia/Shanghai',
      sessionMode: (value['session_mode'] as String?) ?? 'per_run',
      carryLastResult: value['carry_last_result'] == true,
      misfirePolicy: (value['misfire_policy'] as String?) ?? 'skip',
      overlapPolicy: (value['overlap_policy'] as String?) ?? 'skip',
      approvalTimeoutMinutes: (value['approval_timeout_minutes'] as num?)?.toInt(),
      maxDurationMinutes: (limits['max_duration_minutes'] as num?)?.toInt() ??
          (runtime['max_duration_minutes'] as num?)?.toInt(),
      notifyOnSuccess: value['notify_on_success'] != false,
      nextRunAt: value['next_run_at'] as String?,
      lastRunAt: value['last_run_at'] as String?,
      lastRunStatus: value['last_run_status'] as String?,
      activeRunStatus: value['active_run_status'] as String?,
      consecutiveFailures: (value['consecutive_failures'] as num?)?.toInt() ?? 0,
      pausedReason: value['paused_reason'] as String?,
    );
  }

  final String id;
  final String name;
  final String description;
  final bool enabled;
  final String instruction;
  final String modelId;
  final String triggerType;
  final String triggerExpr;
  final String triggerAt;
  final String timezone;
  final String sessionMode;
  final bool carryLastResult;
  final String misfirePolicy;
  final String overlapPolicy;
  final int? approvalTimeoutMinutes;
  final int? maxDurationMinutes;
  final bool notifyOnSuccess;
  final String? nextRunAt;
  final String? lastRunAt;
  final String? lastRunStatus;
  final String? activeRunStatus;
  final int consecutiveFailures;
  final String? pausedReason;

  Map<String, dynamic> get trigger => {
        'type': triggerType,
        if (triggerType == 'cron') 'expr': triggerExpr,
        if (triggerType == 'once') 'at': triggerAt,
        'timezone': timezone,
      };

  /// Cloud requires the whole editable record on every save; model credentials
  /// stay server-side and are omitted unless the editor supplies new ones.
  Map<String, dynamic> toSaveBody({bool? enabledOverride}) => {        'name': name,
        'description': description,
        'instruction': instruction,
        'trigger': trigger,
        'session_mode': sessionMode,
        'carry_last_result': carryLastResult,
        'misfire_policy': misfirePolicy,
        'overlap_policy': overlapPolicy,
        if (approvalTimeoutMinutes != null)
          'approval_timeout_minutes': approvalTimeoutMinutes,
        if (maxDurationMinutes != null)
          'limits': {'max_duration_minutes': maxDurationMinutes},
        'notify_on_success': notifyOnSuccess,
        'enabled': enabledOverride ?? enabled,
      };

  String get scheduleLabel {
    if (triggerType == 'once') {
      return triggerAt.isEmpty ? '仅一次' : '一次 · ${_local(triggerAt)}';
    }
    return triggerExpr.isEmpty ? '未设置' : triggerExpr;
  }

  String get nextRunLabel =>
      nextRunAt == null ? '尚未排期' : '下次 ${_local(nextRunAt!)}';

  String get lastRunLabel =>
      lastRunAt == null ? '从未运行' : '上次 ${_local(lastRunAt!)}';

  static String _local(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    final local = parsed.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class AgentAutomationRun {
  const AgentAutomationRun({
    required this.id,
    required this.status,
    this.scheduledAt,
    this.triggerKind,
    this.startedAt,
    this.finishedAt,
    this.answer = '',
    this.error = '',
    this.sessionId,
  });

  factory AgentAutomationRun.fromJson(Map value) => AgentAutomationRun(
        id: value['id'] as String,
        status: (value['status'] as String?) ?? 'unknown',
        scheduledAt: value['scheduled_at'] as String?,
        triggerKind: value['trigger_kind'] as String?,
        startedAt: value['started_at'] as String?,
        finishedAt: value['finished_at'] as String?,
        answer: (value['answer'] as String?) ?? '',
        error: (value['error'] as String?) ?? '',
        sessionId: value['session_id'] as String?,
      );

  final String id;
  final String status;
  final String? scheduledAt;
  final String? triggerKind;
  final String? startedAt;
  final String? finishedAt;
  final String answer;
  final String error;
  final String? sessionId;

  static const statusLabels = {
    'queued': '排队中',
    'running': '运行中',
    'awaiting_approval': '待审批',
    'succeeded': '成功',
    'failed': '失败',
    'cancelled': '已取消',
    'skipped': '已跳过',
    'needs_attention': '需要处理',
  };

  String get statusLabel => statusLabels[status] ?? status;

  static String labelOf(String status) => statusLabels[status] ?? status;

  bool get cancellable => status == 'queued' || status == 'running';

  String get startedLabel => AgentAutomation._local(
        scheduledAt ?? startedAt ?? '',
      );

  String get durationLabel {
    final start = DateTime.tryParse(startedAt ?? '');
    final end = DateTime.tryParse(finishedAt ?? '');
    if (start == null || end == null) return '';
    final seconds = end.difference(start).inSeconds;
    if (seconds < 60) return '${seconds}s';
    return '${seconds ~/ 60}m${seconds % 60}s';
  }
}

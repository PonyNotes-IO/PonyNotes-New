import 'package:appflowy/features/ai_internal/application/ai_provider_config.dart';
import 'package:flutter/material.dart';

import '../application/agent_automation.dart';
import '../application/agent_automation_service.dart';
import '../application/agent_internal_service.dart';

const _timezones = [
  'Asia/Shanghai',
  'Asia/Hong_Kong',
  'Asia/Taipei',
  'Asia/Tokyo',
  'Asia/Singapore',
  'UTC',
  'Europe/London',
  'America/New_York',
  'America/Los_Angeles',
];

const _cronPresets = {
  '每天 09:00': '0 9 * * *',
  '每天 18:00': '0 18 * * *',
  '工作日 09:00': '0 9 * * 1-5',
  '每周一 09:00': '0 9 * * 1',
  '每小时': '0 * * * *',
};

class AgentAutomationEditor extends StatefulWidget {
  const AgentAutomationEditor({
    super.key,
    required this.service,
    required this.workspace,
    this.automation,
    this.models,
  });

  final AgentAutomationService service;
  final Future<String> Function() workspace;
  final AgentAutomation? automation;

  /// Injectable for tests; defaults to the Cloud model catalogue.
  final Future<List<AiProviderConfig>> Function()? models;

  @override
  State<AgentAutomationEditor> createState() => _AgentAutomationEditorState();
}

class _AgentAutomationEditorState extends State<AgentAutomationEditor> {
  late final name = TextEditingController(text: widget.automation?.name ?? '');
  late final description =
      TextEditingController(text: widget.automation?.description ?? '');
  late final instruction =
      TextEditingController(text: widget.automation?.instruction ?? '');
  late final cron = TextEditingController(
    text: widget.automation?.triggerExpr ?? _cronPresets.values.first,
  );

  late String triggerType = widget.automation?.triggerType ?? 'cron';
  late String timezone = widget.automation?.timezone ?? _timezones.first;
  late String sessionMode = widget.automation?.sessionMode ?? 'per_run';
  late bool notifyOnSuccess = widget.automation?.notifyOnSuccess ?? true;
  DateTime? onceAt;

  List<AiProviderConfig> models = const [];
  AiProviderConfig? model;
  bool loadingModels = true;
  bool saving = false;
  String? error;
  List<String> preview = const [];

  bool get editing => widget.automation != null;

  @override
  void initState() {
    super.initState();
    onceAt = DateTime.tryParse(widget.automation?.triggerAt ?? '');
    _loadModels();
  }

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    instruction.dispose();
    cron.dispose();
    super.dispose();
  }

  Future<void> _loadModels() async {
    try {
      final loader = widget.models ?? AgentInternalService().models;
      final loaded = await loader();
      if (!mounted) return;
      setState(() {
        models = loaded;
        model = loaded.isEmpty ? null : loaded.first;
        loadingModels = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loadingModels = false;
        error = '$e'.replaceFirst('Bad state: ', '');
      });
    }
  }

  Map<String, dynamic> _trigger() => triggerType == 'cron'
      ? {
          'type': 'cron',
          'expr': cron.text.trim(),
          'timezone': timezone,
        }
      : {
          'type': 'once',
          'at': (onceAt ?? DateTime.now().add(const Duration(days: 1)))
              .toUtc()
              .toIso8601String(),
          'timezone': timezone,
        };

  String? _validate() {
    if (name.text.trim().isEmpty) return '请填写自动化名称';
    if (instruction.text.trim().isEmpty) return '请填写指令';
    if (triggerType == 'cron' && cron.text.trim().isEmpty) {
      return '请填写 cron 表达式';
    }
    if (!editing && model == null) return '请选择模型';
    return null;
  }

  Future<void> _checkTrigger() async {
    setState(() => error = null);
    try {
      final next = await widget.service.validateTrigger(
        await widget.workspace(),
        _trigger(),
      );
      if (!mounted) return;
      setState(() => preview = next);
    } catch (e) {
      if (!mounted) return;
      setState(() => error = '$e'.replaceFirst('Bad state: ', ''));
    }
  }

  Future<void> _save() async {
    final invalid = _validate();
    if (invalid != null) {
      setState(() => error = invalid);
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final body = _automationBody();
      final workspace = await widget.workspace();
      final selected = model;
      if (selected != null) {
        body['model'] = {
          'model_name': selected.modelName,
          'is_internal': selected.isInternal,
          'base_url': selected.baseUrl,
          'api_key': selected.apiKey,
          'supports_reasoning': selected.supportsReasoning,
        };
      }
      if (editing) {
        await widget.service.update(workspace, widget.automation!.id, body);
      } else {
        await widget.service.create(workspace, body);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = '$e'.replaceFirst('Bad state: ', '');
      });
    }
  }

  Map<String, dynamic> _automationBody() => {
        'name': name.text.trim(),
        'description': description.text.trim(),
        'instruction': instruction.text.trim(),
        'trigger': _trigger(),
        'session_mode': sessionMode,
        'carry_last_result': widget.automation?.carryLastResult ?? false,
        'misfire_policy': widget.automation?.misfirePolicy ?? 'skip',
        'overlap_policy': widget.automation?.overlapPolicy ?? 'skip',
        'notify_on_success': notifyOnSuccess,
        'enabled': widget.automation?.enabled ?? true,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? '编辑自动化' : '新建自动化'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: FilledButton(
              onPressed: saving ? null : _save,
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          if (error != null) ...[
            _banner(context, error!),
            const SizedBox(height: 12),
          ],
          _field(
            label: '名称',
            child: TextField(
              controller: name,
              maxLength: 100,
              decoration: const InputDecoration(
                hintText: '例如：每天汇总昨日笔记',
                counterText: '',
              ),
            ),
          ),
          _field(
            label: '描述',
            child: TextField(
              controller: description,
              maxLines: 2,
              maxLength: 500,
              decoration: const InputDecoration(
                hintText: '说明这个任务做什么（可选）',
                counterText: '',
              ),
            ),
          ),
          _field(
            label: '指令',
            child: TextField(
              controller: instruction,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: '告诉 Agent 每次运行时具体要做什么',
                alignLabelWithHint: true,
              ),
            ),
          ),
          _field(
            label: '触发方式',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'cron', label: Text('按计划')),
                    ButtonSegment(value: 'once', label: Text('仅一次')),
                  ],
                  selected: {triggerType},
                  onSelectionChanged: (value) {
                    setState(() {
                      triggerType = value.first;
                      preview = const [];
                    });
                  },
                ),
                const SizedBox(height: 10),
                if (triggerType == 'cron') ...[
                  TextField(
                    controller: cron,
                    decoration: const InputDecoration(
                      labelText: 'cron 表达式',
                      helperText: '六段格式支持秒级；最小间隔由服务端限制',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final entry in _cronPresets.entries)
                        ActionChip(
                          label: Text(entry.key),
                          onPressed: () => setState(() {
                            cron.text = entry.value;
                            preview = const [];
                          }),
                        ),
                    ],
                  ),
                ] else
                  OutlinedButton.icon(
                    onPressed: _pickOnce,
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text(
                      onceAt == null
                          ? '选择运行时间'
                          : '运行时间 · ${_formatLocal(onceAt!)}',
                    ),
                  ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: timezone,
                  decoration: const InputDecoration(labelText: '时区'),
                  items: [
                    for (final zone in _timezones)
                      DropdownMenuItem(value: zone, child: Text(zone)),
                  ],
                  onChanged: (value) =>
                      setState(() => timezone = value ?? timezone),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _checkTrigger,
                      icon: const Icon(Icons.event_repeat, size: 18),
                      label: const Text('校验并预览'),
                    ),
                    const SizedBox(width: 12),
                    if (preview.isNotEmpty)
                      Expanded(
                        child: Text(
                          '接下来：${preview.map(_formatUtc).join('、')}',
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          _field(
            label: '模型',
            child: loadingModels
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(),
                  )
                : DropdownButtonFormField<String>(
                    initialValue: model?.modelName,
                    decoration: InputDecoration(
                      hintText: editing ? '保持不变' : '请选择模型',
                      helperText: editing
                          ? '不重新选择时沿用上次保存的模型配置'
                          : null,
                    ),
                    items: [
                      for (final config in models)
                        DropdownMenuItem(
                          value: config.modelName,
                          child: Text(
                            config.modelName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(
                      () => model = models
                          .where((config) => config.modelName == value)
                          .firstOrNull,
                    ),
                  ),
          ),
          _field(
            label: '会话',
            child: DropdownButtonFormField<String>(
              initialValue: sessionMode,
              items: const [
                DropdownMenuItem(value: 'per_run', child: Text('每次新建会话')),
                DropdownMenuItem(value: 'persistent', child: Text('沿用同一会话')),
              ],
              onChanged: (value) =>
                  setState(() => sessionMode = value ?? sessionMode),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('运行结束发送通知'),
            value: notifyOnSuccess,
            onChanged: (value) => setState(() => notifyOnSuccess = value),
          ),
        ],
      ),
    );
  }

  Future<void> _pickOnce() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: onceAt ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(onceAt ?? now),
    );
    if (time == null) return;
    setState(() {
      onceAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      preview = const [];
    });
  }

  static String _formatLocal(DateTime value) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  static String _formatUtc(String value) {
    final parsed = DateTime.tryParse(value);
    return parsed == null ? value : _formatLocal(parsed.toLocal());
  }

  Widget _field({required String label, required Widget child}) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            child,
          ],
        ),
      );

  Widget _banner(BuildContext context, String message) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          message,
          style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
        ),
      );
}

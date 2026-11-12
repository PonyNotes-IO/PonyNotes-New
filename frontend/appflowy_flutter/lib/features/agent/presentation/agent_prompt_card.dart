import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../application/agent_prompt.dart';

class AgentPromptCard extends StatefulWidget {
  const AgentPromptCard({
    super.key,
    required this.prompt,
    required this.onAnswer,
    this.onStop,
  });
  final AgentPrompt prompt;
  final Future<void> Function(Map<String, dynamic>) onAnswer;
  final Future<void> Function()? onStop;

  @override
  State<AgentPromptCard> createState() => _AgentPromptCardState();
}

class _AgentPromptCardState extends State<AgentPromptCard> {
  final form = GlobalKey<FormState>();
  final text = TextEditingController();
  final selected = <String>{};
  final values = <String, dynamic>{};
  Timer? clock;
  bool attempted = false;
  AgentPrompt get prompt => widget.prompt;
  Map<String, dynamic> get question => prompt.request;
  List<String> get options =>
      (question['options'] as List? ?? []).whereType<String>().toList();
  List<Map> get fields =>
      (question['fields'] as List? ?? []).whereType<Map>().toList();
  bool get acceptsText =>
      question['allow_free_text'] == true ||
      (options.isEmpty && fields.isEmpty);

  @override
  void initState() {
    super.initState();
    if (prompt.expiresAt != null) {
      clock = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
        if (prompt.expired) clock?.cancel();
      });
    }
  }

  @override
  void dispose() {
    clock?.cancel();
    text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => attempted = true);
    if (!form.currentState!.validate()) return;
    if (options.isNotEmpty && selected.isEmpty && text.text.trim().isEmpty) {
      return;
    }
    await widget.onAnswer({
      if (selected.isNotEmpty) 'selected': selected.toList(),
      if (values.isNotEmpty) 'values': values,
      if (text.text.trim().isNotEmpty) 'text': text.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = prompt.open && !prompt.expired && !prompt.submitting;
    final ask = prompt.kind == 'ask_user';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Form(
        key: form,
        autovalidateMode: attempted
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                ask ? '${question['question'] ?? ''}' : '确认这次操作',
                style: theme.textTheme.titleMedium?.copyWith(height: 1.5),
              ),
            ),
            if (!ask) ...[
              const SizedBox(height: 8),
              Text(
                '${question['description'] ?? question['mcp_tool_name'] ?? '执行工具操作'}',
                style: theme.textTheme.titleMedium,
              ),
              if (question['service_name'] is String)
                Text(
                  '${question['service_name']}',
                  style: theme.textTheme.bodyMedium,
                ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('查看操作详情'),
                children: [
                  SelectableText(
                    const JsonEncoder.withIndent('  ').convert(
                      question['args'] ?? question['arguments'] ?? {},
                    ),
                  ),
                ],
              ),
            ],
            if (ask)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .35,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (options.isNotEmpty)
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              for (final option in options)
                                FilterChip(
                                  label: Text(option, softWrap: true),
                                  selected: selected.contains(option),
                                  onSelected: !enabled
                                      ? null
                                      : (value) => setState(() {
                                            if (question['multi_select'] !=
                                                true) {
                                              selected.clear();
                                            }
                                            if (value) {
                                              selected.add(option);
                                            } else {
                                              selected.remove(option);
                                            }
                                          }),
                                ),
                            ],
                          ),
                        if (attempted &&
                            options.isNotEmpty &&
                            selected.isEmpty &&
                            text.text.trim().isEmpty)
                          Text(
                            '请选择一项${acceptsText ? '或填写你的想法' : ''}',
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        for (final field in fields)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _field(field, enabled),
                          ),
                        if (acceptsText)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: TextFormField(
                              controller: text,
                              enabled: enabled,
                              minLines: 1,
                              maxLines: 4,
                              maxLength: 4000,
                              decoration: InputDecoration(
                                labelText: options.isEmpty && fields.isEmpty
                                    ? '你的回答'
                                    : '补充你的想法（可选）',
                                counterText: '',
                              ),
                              validator: (value) => options.isEmpty &&
                                      fields.isEmpty &&
                                      (value?.trim().isEmpty ?? true)
                                  ? '请填写回答'
                                  : null,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            if (prompt.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  prompt.error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 12),
            if (prompt.expired) const Text('此问题已过期，请重新打开对话或重新提问'),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (widget.onStop != null) ...[
                  TextButton(
                    onPressed: prompt.submitting ? null : widget.onStop,
                    child: const Text('停止任务'),
                  ),
                  const Spacer(),
                ],
                TextButton(
                  onPressed: enabled
                      ? () => widget.onAnswer(
                            ask ? {'declined': true} : {'approved': false},
                          )
                      : null,
                  child: Text(ask ? '暂不回答' : '拒绝'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: !enabled
                      ? null
                      : ask
                          ? _submit
                          : () => widget.onAnswer({'approved': true}),
                  child: Text(
                    prompt.submitting
                        ? '正在提交…'
                        : ask
                            ? '继续'
                            : '允许这次',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(Map field, bool enabled) {
    final name = '${field['name']}';
    final label =
        '${field['label'] ?? name}${field['required'] == true ? ' *' : ''}';
    final choices =
        (field['options'] as List? ?? []).whereType<String>().toList();
    String? validate(dynamic value) => field['required'] == true &&
            (value == null ||
                value is String && value.trim().isEmpty ||
                value is List && value.isEmpty)
        ? '请填写${field['label'] ?? name}'
        : null;
    if (field['type'] == 'multiselect') {
      return FormField<List<String>>(
        initialValue: const [],
        validator: validate,
        builder: (state) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            Wrap(
              spacing: 8,
              children: [
                for (final choice in choices)
                  FilterChip(
                    label: Text(choice),
                    selected: (state.value ?? []).contains(choice),
                    onSelected: !enabled
                        ? null
                        : (selected) {
                            final next = [...state.value ?? <String>[]];
                            if (selected) {
                              next.add(choice);
                            } else {
                              next.remove(choice);
                            }
                            values[name] = next;
                            state.didChange(next);
                          },
                  ),
              ],
            ),
            if (state.errorText != null)
              Text(
                state.errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      );
    }
    if (field['type'] == 'select') {
      return DropdownButtonFormField<String>(
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: choices
            .map(
              (choice) => DropdownMenuItem(value: choice, child: Text(choice)),
            )
            .toList(),
        onChanged: !enabled ? null : (value) => values[name] = value,
        validator: validate,
      );
    }
    final number = field['type'] == 'number';
    return TextFormField(
      enabled: enabled,
      maxLength: 4000,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      decoration: InputDecoration(labelText: label, counterText: ''),
      onChanged: (value) {
        if (value.trim().isEmpty) {
          values.remove(name);
        } else {
          values[name] = number ? num.tryParse(value) : value;
        }
      },
      validator: (value) =>
          validate(value) ??
          (number &&
                  value!.isNotEmpty &&
                  (num.tryParse(value)?.isFinite != true)
              ? '请输入有效数字'
              : null),
    );
  }
}

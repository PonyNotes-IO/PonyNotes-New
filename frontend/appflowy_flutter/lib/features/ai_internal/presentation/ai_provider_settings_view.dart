import 'dart:async';

import 'package:appflowy/features/ai_internal/application/ai_provider_config.dart';
import 'package:appflowy/features/ai_internal/application/internal_ai_service.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_body.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

/// 内部 AI 的模型配置页：模型地址、模型名称、API Key。
///
/// 与「AI 接入 (MCP)」是两个方向：
/// MCP 是外部 Agent 访问小马，这里是 小马访问用户自己的模型服务。
class AiProviderSettingsView extends StatefulWidget {
  const AiProviderSettingsView({super.key});

  @override
  State<AiProviderSettingsView> createState() => _AiProviderSettingsViewState();
}

class _AiProviderSettingsViewState extends State<AiProviderSettingsView> {
  final _serverUrlController = TextEditingController();
  final _modelController = TextEditingController();
  final _apiKeyController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  bool _obscureKey = true;

  /// 连通性测试的结果，null 表示还没测过。
  String? _testMessage;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _modelController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await const AiProviderConfigStorage().load();
    _serverUrlController.text = config.baseUrl;
    _modelController.text = config.modelName;
    _apiKeyController.text = config.apiKey;
    if (mounted) setState(() => _loading = false);
  }

  AiProviderConfig _currentConfig() => AiProviderConfig(
        baseUrl: _serverUrlController.text.trim(),
        modelName: _modelController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
      );

  Future<void> _save() async {
    setState(() => _saving = true);
    await const AiProviderConfigStorage().save(_currentConfig());
    if (!mounted) return;
    setState(() {
      _saving = false;
      _testOk = true;
      _testMessage = '已保存';
    });
  }

  /// 用当前填写的配置发一次最小请求，只验证通路与鉴权，不实际生成笔记操作。
  Future<void> _testConnection() async {
    if (_testing) return;
    setState(() {
      _testing = true;
      _testMessage = null;
    });

    final config = _currentConfig();

    final service = InternalAiService();
    try {
      if (!service.isConfigured(config)) {
        setState(() {
          _testOk = false;
          _testMessage = '地址、模型名称和 API Key 都需要填写。';
        });
        return;
      }
      // 直接问一句最轻量的话，不触发任何工具。用未保存的表单值，便于先测后存。
      await service.ask(question: '你好', configOverride: config);
      if (mounted) {
        setState(() {
          _testOk = true;
          _testMessage = '连接成功。';
        });
      }
    } on InternalAiException catch (e) {
      if (mounted) {
        setState(() {
          _testOk = false;
          _testMessage = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _testOk = false;
          _testMessage = '测试失败：$e';
        });
      }
    } finally {
      service.dispose();
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SettingsBody(
        title: '内部 AI 模型',
        autoSeparate: false,
        children: [VSpace(20), Center(child: CircularProgressIndicator())],
      );
    }

    return SettingsBody(
      title: '内部 AI 模型',
      description: '配置你自己拥有的模型服务（OpenAI 兼容接口）。'
          '小马会用它理解你的意图，并通过本地工具读取和修改笔记。'
          '模型调用产生的费用由你的账号自行承担，与 MCP Token 分别管理。'
          '这组配置单独保存，与「Ollama」设置互不覆盖。',
      autoSeparate: false,
      children: [
        _buildField(
          context,
          label: '模型地址',
          hint: 'https://api.deepseek.com 或 https://api.openai.com/v1',
          controller: _serverUrlController,
        ),
        const VSpace(12),
        _buildField(
          context,
          label: '模型名称',
          hint: 'deepseek-chat、gpt-4o-mini 等',
          controller: _modelController,
        ),
        const VSpace(12),
        _buildApiKeyField(context),
        if (_testMessage != null) ...[
          const VSpace(12),
          FlowyText(
            _testMessage!,
            fontSize: 13,
            color: _testOk
                ? AppFlowyTheme.of(context).textColorScheme.primary
                : Theme.of(context).colorScheme.error,
          ),
        ],
        const VSpace(20),
        Row(
          children: [
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '保存中…' : '保存'),
            ),
            const HSpace(12),
            OutlinedButton(
              onPressed: _testing ? null : _testConnection,
              child: Text(_testing ? '测试中…' : '测试连接'),
            ),
          ],
        ),
        const VSpace(20),
        _buildNotice(context),
      ],
    );
  }

  Widget _buildField(
    BuildContext context, {
    required String label,
    required String hint,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FlowyText(
          label,
          fontSize: 14,
          color: AppFlowyTheme.of(context).textColorScheme.primary,
        ),
        const VSpace(6),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildApiKeyField(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FlowyText(
          'API Key',
          fontSize: 14,
          color: AppFlowyTheme.of(context).textColorScheme.primary,
        ),
        const VSpace(6),
        TextField(
          controller: _apiKeyController,
          obscureText: _obscureKey,
          decoration: InputDecoration(
            hintText: 'sk-…',
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: IconButton(
              icon: Icon(_obscureKey ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscureKey = !_obscureKey),
            ),
          ),
        ),
        const VSpace(4),
        FlowyText(
          '密钥保存在本机，不会上传，也不会写入日志。',
          fontSize: 12,
          color: AppFlowyTheme.of(context).textColorScheme.secondary,
        ),
      ],
    );
  }

  Widget _buildNotice(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppFlowyTheme.of(context).surfaceColorScheme.layer01,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FlowyText(
            '关于写操作',
            fontSize: 13,
            color: AppFlowyTheme.of(context).textColorScheme.primary,
          ),
          const VSpace(4),
          FlowyText(
            'AI 具备创建页面、追加内容、修改和删除块的能力。'
            '涉及写入的操作会先征求你的确认，确认前不会执行。',
            fontSize: 12,
            color: AppFlowyTheme.of(context).textColorScheme.secondary,
          ),
        ],
      ),
    );
  }
}

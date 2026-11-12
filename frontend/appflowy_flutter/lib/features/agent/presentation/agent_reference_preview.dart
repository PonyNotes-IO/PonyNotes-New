import 'dart:async';
import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';
import '../application/agent_controller.dart';

class AgentReferencePreview extends StatefulWidget {
  const AgentReferencePreview({super.key, required this.load});
  final Future<Map<String, dynamic>> Function(int page) load;
  @override
  State<AgentReferencePreview> createState() => _AgentReferencePreviewState();
}

class _AgentReferencePreviewState extends State<AgentReferencePreview> {
  Map<String, dynamic>? _data;
  String? _error;
  int _page = 1;
  int _generation = 0;
  bool _revoked = false;
  @override
  void initState() {
    super.initState();
    AgentController.accountClearance.addListener(_revoke);
    unawaited(_load());
  }

  void _revoke() {
    ++_generation;
    setState(() {
      _revoked = true;
      _data = null;
      _error = '账号或工作区已切换，请关闭后重新打开';
    });
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _data = null;
      _error = null;
    });
    try {
      final data = await widget.load(_page);
      if (mounted && generation == _generation) setState(() => _data = data);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '文件内容暂时无法读取，请重试');
      }
    }
  }

  @override
  void dispose() {
    ++_generation;
    AgentController.accountClearance.removeListener(_revoke);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chunks = (_data?['chunks'] as List? ?? []).whereType<Map>().toList();
    return Dialog(
      child: SizedBox(
        width: 760,
        height: MediaQuery.sizeOf(context).height * .75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_data?['title'] ?? '引用文件'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭文件预览',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!),
                          if (!_revoked)
                            TextButton(
                              onPressed: _load,
                              child: const Text('重试'),
                            ),
                        ],
                      ),
                    )
                  : _data == null
                      ? const Center(child: CircularProgressIndicator())
                      : chunks.isEmpty
                          ? const Center(child: Text('文件暂无已解析的正文'))
                          : ListView(
                              padding: const EdgeInsets.all(20),
                              children: [
                                for (final chunk in chunks)
                                  MarkdownWidget(
                                    data: '${chunk['content'] ?? ''}',
                                    shrinkWrap: true,
                                  ),
                              ],
                            ),
            ),
            if (_data != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _page > 1
                          ? () {
                              _page--;
                              unawaited(_load());
                            }
                          : null,
                      child: const Text('上一页'),
                    ),
                    Text('第 $_page 页'),
                    TextButton(
                      onPressed: _page * 25 < (_data?['total'] as int? ?? 0)
                          ? () {
                              _page++;
                              unawaited(_load());
                            }
                          : null,
                      child: const Text('下一页'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

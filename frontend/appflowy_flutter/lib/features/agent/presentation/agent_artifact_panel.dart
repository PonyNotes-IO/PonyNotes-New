import 'dart:io';
import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import '../application/agent_artifacts.dart';
import '../application/agent_artifact_preview.dart';

class AgentArtifactPanel extends StatefulWidget {
  const AgentArtifactPanel({
    super.key,
    required this.artifacts,
    this.onClose,
    this.onRefresh,
    this.initialKey,
    this.library = false,
    this.onSource,
  });
  final List<AgentArtifact> artifacts;
  final VoidCallback? onClose;
  final VoidCallback? onRefresh;
  final String? initialKey;
  final bool library;
  final Future<void> Function(AgentArtifact)? onSource;
  @override
  State<AgentArtifactPanel> createState() => _AgentArtifactPanelState();
}

class _AgentArtifactPanelState extends State<AgentArtifactPanel> {
  String? selectedKey;
  String search = '';
  @override
  void initState() {
    super.initState();
    selectedKey = widget.initialKey;
  }

  @override
  void didUpdateWidget(AgentArtifactPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialKey != widget.initialKey) {
      selectedKey = widget.initialKey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.artifacts
        .where(
          (a) => '${a.name} ${a.documentName}'.toLowerCase().contains(search),
        )
        .toList();
    final selected = entries.where((a) => a.key == selectedKey).firstOrNull ??
        entries.firstOrNull;
    return Material(
      color: AppFlowyTheme.maybeOf(context)?.surfaceColorScheme.primary ??
          Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.library ? '全部产物' : '会话产物'} · ${widget.artifacts.length}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (widget.onRefresh != null)
                  IconButton(
                    tooltip: '刷新产物',
                    onPressed: widget.onRefresh,
                    icon: const Icon(Icons.refresh, size: 20),
                  ),
                if (widget.onClose != null)
                  IconButton(
                    tooltip: widget.library ? '返回问 AI' : '关闭产物侧边栏',
                    onPressed: widget.onClose,
                    icon: Icon(
                      widget.library ? Icons.arrow_back : Icons.close,
                      size: 20,
                    ),
                  ),
              ],
            ),
          ),
          if (widget.library)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: '搜索文件或对话',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) =>
                    setState(() => search = value.trim().toLowerCase()),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.folder_open_outlined, size: 32),
                          const SizedBox(height: 12),
                          Text(
                            search.isNotEmpty ? '没有匹配的产物' : '还没有文件产物',
                            style: const TextStyle(fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            search.isNotEmpty
                                ? '试试其他文件名或对话名称'
                                : 'AI 生成的文件保存后会出现在这里',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final horizontal =
                          widget.library && constraints.maxWidth >= 760;
                      final list = ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: entries.length,
                        itemBuilder: (context, i) {
                          final item = entries[i];
                          return ListTile(
                            selected: item.key == selected?.key,
                            selectedTileColor: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: .08),
                            leading: Icon(artifactIcon(item.name)),
                            title: Tooltip(
                              message: item.name,
                              child: Text(
                                item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                            subtitle: Text(
                              '${artifactSize(item.size)} · ${widget.library && item.documentName.isNotEmpty ? item.documentName : '本地已保存'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => setState(() => selectedKey = item.key),
                          );
                        },
                      );
                      final preview = AgentArtifactPreview(
                        key: ValueKey(selected!.key),
                        artifact: selected,
                        onSource: widget.onSource,
                      );
                      if (horizontal) {
                        return Row(
                          children: [
                            SizedBox(width: 280, child: list),
                            const VerticalDivider(width: 1),
                            Expanded(child: preview),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          SizedBox(
                            height: entries.length == 1
                                ? 80
                                : constraints.maxHeight * .27,
                            child: list,
                          ),
                          const Divider(height: 1),
                          Expanded(child: preview),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class AgentArtifactPreview extends StatefulWidget {
  const AgentArtifactPreview({
    super.key,
    required this.artifact,
    this.onSource,
  });
  final AgentArtifact artifact;
  final Future<void> Function(AgentArtifact)? onSource;
  @override
  State<AgentArtifactPreview> createState() => _AgentArtifactPreviewState();
}

class _AgentArtifactPreviewState extends State<AgentArtifactPreview> {
  late Future<bool> exists = widget.artifact.file.exists();
  late Future<String> text = readArtifactText(widget.artifact.file);
  String? error;
  bool saving = false;

  Future<void> _action(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = '操作失败：$e');
    }
  }

  Future<void> _saveAs() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final file = widget.artifact.file;
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '另存为',
        fileName: p.basename(widget.artifact.name),
        bytes: Platform.isAndroid || Platform.isIOS
            ? await file.readAsBytes()
            : null,
      );
      if (path != null &&
          !Platform.isAndroid &&
          !Platform.isIOS &&
          p.normalize(path) != p.normalize(file.path)) {
        await file.copy(path);
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final artifact = widget.artifact;
    final extension = p.extension(artifact.name).toLowerCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            artifact.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '${artifactSize(artifact.size)} · ${artifactOfficeExtensions.contains(extension) ? '文字预览' : '本地文件'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Wrap(
            children: [
              TextButton.icon(
                onPressed: () => _action(() async {
                  if (!await afLaunchUri(
                    Uri.file(artifact.file.path),
                    context: context,
                  )) {
                    throw StateError('无法打开文件，请检查关联应用');
                  }
                }),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('打开'),
              ),
              TextButton.icon(
                onPressed: saving ? null : () => _action(_saveAs),
                icon: const Icon(Icons.save_alt, size: 16),
                label: Text(saving ? '正在保存…' : '另存为'),
              ),
              if (widget.onSource != null)
                TextButton.icon(
                  onPressed: () => _action(() => widget.onSource!(artifact)),
                  icon: const Icon(Icons.chat_bubble_outline, size: 16),
                  label: const Text('来源对话'),
                ),
            ],
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder<bool>(
            future: exists,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.data != true) {
                return _notice('本地文件已移走或删除，请回到来源对话重新下载');
              }
              if ({'.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp'}
                  .contains(extension)) {
                return InteractiveViewer(
                  minScale: .5,
                  maxScale: 5,
                  child: Center(
                    child: Image.file(
                      artifact.file,
                      cacheWidth: 1600,
                      errorBuilder: (_, __, ___) => _notice('图片无法预览，请使用外部应用打开'),
                    ),
                  ),
                );
              }
              if (extension == '.pdf') {
                return PdfViewer.file(artifact.file.path);
              }
              if (artifactTextExtensions.contains(extension) ||
                  artifactOfficeExtensions.contains(extension)) {
                return FutureBuilder<String>(
                  future: text,
                  builder: (context, data) {
                    if (data.connectionState != ConnectionState.done) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }
                    if (data.hasError) return _notice('无法读取预览，请使用外部应用打开');
                    if (extension == '.md' || extension == '.markdown') {
                      return MarkdownWidget(
                        data: data.data!,
                        padding: const EdgeInsets.all(20),
                        config: MarkdownConfig(
                          configs: [
                            PConfig(
                              textStyle: TextStyle(
                                fontSize: 14,
                                height: 1.65,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            ImgConfig(
                              builder: (_, attributes) =>
                                  Text(attributes['alt'] ?? '图片引用'),
                            ),
                            LinkConfig(
                              onTap: (url) {
                                final uri = Uri.tryParse(url);
                                if (uri != null &&
                                    ['https', 'http'].contains(uri.scheme)) {
                                  _action(() async {
                                    await afLaunchUri(uri);
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                      );
                    }
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: SizedBox(
                        width: double.infinity,
                        child: SelectableText(
                          data.data!.isEmpty ? '文件内容为空' : data.data!,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.65,
                          ),
                        ),
                      ),
                    );
                  },
                );
              }
              return _notice('此格式可用关联应用打开，原始文件已保存在本地');
            },
          ),
        ),
      ],
    );
  }

  Widget _notice(String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message, textAlign: TextAlign.center),
        ),
      );
}

IconData artifactIcon(String name) => switch (p.extension(name).toLowerCase()) {
      '.png' || '.jpg' || '.jpeg' || '.webp' || '.gif' => Icons.image_outlined,
      '.pdf' => Icons.picture_as_pdf_outlined,
      '.xlsx' || '.csv' || '.tsv' => Icons.table_chart_outlined,
      '.pptx' => Icons.slideshow_outlined,
      '.md' || '.txt' || '.docx' => Icons.description_outlined,
      _ => Icons.insert_drive_file_outlined,
    };

String artifactSize(int bytes) => bytes >= 1024 * 1024
    ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
    : bytes >= 1024
        ? '${(bytes / 1024).toStringAsFixed(1)} KB'
        : '$bytes B';

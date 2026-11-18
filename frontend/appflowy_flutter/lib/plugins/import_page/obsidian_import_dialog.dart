import 'dart:io';

import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/share/external_import_space_service.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flutter/material.dart';

import 'obsidian_import_service.dart';

class ObsidianImportDialog extends StatefulWidget {
  const ObsidianImportDialog({super.key});

  @override
  State<ObsidianImportDialog> createState() => _ObsidianImportDialogState();
}

class _ObsidianImportDialogState extends State<ObsidianImportDialog> {
  bool _importing = false;
  String? _error;
  int _completed = 0;
  int _total = 0;

  Future<void> _import() async {
    setState(() {
      _importing = true;
      _error = null;
      _completed = _total = 0;
    });
    try {
      final path = await getIt<FilePickerService>().getDirectoryPath();
      if (path == null || path.trim().isEmpty || !mounted) return;
      final result = await FolderEventReadCurrentWorkspace().send();
      final workspace = result.fold(
        (value) => value,
        (error) => throw StateError(error.msg),
      );
      final space = await ExternalImportSpaceService.getOrCreate(workspace.id);
      final count = await importObsidianVault(
        Directory(path),
        parentViewId: space.id,
        onProgress: (completed, total) {
          if (mounted) {
            setState(() {
              _completed = completed;
              _total = total;
            });
          }
        },
      );
      if (mounted) {
        setState(() => _importing = false);
        Navigator.of(context).pop(count);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_importing,
        child: AlertDialog(
          title: const Text('导入 Obsidian'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('选择 Vault（仓库）根文件夹，导入全部 Markdown 笔记，'
                      '并将原文件夹层级保留为父子页面。'),
                  const SizedBox(height: 12),
                  const Text('导入结果位于「外部导入 → 仓库名称」，原文件不会更改。'
                      '附件复制和 [[双链]] 转换暂不包含。'),
                  if (_importing) ...[
                    const SizedBox(height: 20),
                    LinearProgressIndicator(
                      value: _total == 0 ? null : _completed / _total,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _total == 0
                          ? '正在读取笔记…'
                          : '正在导入：$_completed / $_total 个页面',
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _importing ? null : () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
            FilledButton(
              onPressed: _importing ? null : _import,
              child: const Text('选择仓库文件夹'),
            ),
          ],
        ),
      );
}

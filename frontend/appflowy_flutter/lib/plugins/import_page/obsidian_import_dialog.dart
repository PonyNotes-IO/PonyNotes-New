import 'dart:io';

import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/share/external_import_space_service.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flutter/material.dart';

import 'import_source_dialog.dart';
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

  String _text(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return PopScope(
      canPop: !_importing,
      child: ImportSourceDialog(
        title: _text('从 Obsidian 导入', 'Import from Obsidian'),
        description: _text(
          '导入 Markdown 笔记，保留原有文件夹层级',
          'Import Markdown notes and keep the original folder hierarchy',
        ),
        picker: ImportSourcePicker(
          icon: Icons.folder_open_outlined,
          label: Text(
            _text('选择仓库文件夹', 'Choose a vault folder'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          hint: _text(
            '请选择 Vault（仓库）的根文件夹',
            'Select the root folder of your vault',
          ),
          onPressed: _importing ? null : _import,
        ),
        status: _importing
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LinearProgressIndicator(
                    value: _total == 0 ? null : _completed / _total,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _total == 0
                        ? _text('正在读取笔记…', 'Reading notes…')
                        : _text(
                            '正在导入：$_completed / $_total 个页面',
                            'Importing $_completed / $_total pages',
                          ),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              )
            : _error == null
                ? null
                : Text(_error!, style: TextStyle(color: colors.error)),
        instructions: _text(
          '导入位置为「外部导入 → 仓库名称」，原文件不会更改。\n附件复制和 [[双链]] 转换暂不包含。',
          'Find your vault under External Import. The original files stay intact.\nAttachments and [[wikilinks]] are not migrated.',
        ),
        cancelLabel: _text('取消', 'Cancel'),
        onCancel: _importing ? null : () => Navigator.of(context).pop(),
      ),
    );
  }
}

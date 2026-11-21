import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'import_source_dialog.dart';

class NotionImportDialog extends StatefulWidget {
  const NotionImportDialog({super.key, required this.pickZipPath});

  final Future<String?> Function() pickZipPath;

  @override
  State<NotionImportDialog> createState() => _NotionImportDialogState();
}

class _NotionImportDialogState extends State<NotionImportDialog> {
  bool _isDragging = false;
  bool _isSelecting = false;
  String? _error;

  bool get _isCurrent => mounted && ModalRoute.of(context)?.isCurrent == true;

  String _text(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  Future<void> _selectZip(Future<String?> Function() select) async {
    if (_isSelecting || !_isCurrent) return;
    setState(() {
      _isSelecting = true;
      _isDragging = false;
      _error = null;
    });
    try {
      final path = await select();
      if (!mounted) return;
      if (!_isCurrent || path == null) {
        setState(() => _isSelecting = false);
      } else if (p.extension(path).toLowerCase() == '.zip' &&
          await File(path).exists()) {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          Navigator.of(context).pop(path);
        }
      } else if (_isCurrent) {
        _showError(_text('请选择一个有效的 ZIP 文件。', 'Choose a valid ZIP file.'));
      }
    } catch (_) {
      if (_isCurrent) {
        _showError(_text('无法打开文件，请重试。', 'Could not open the file. Try again.'));
      }
    }
  }

  void _showError(String message) {
    setState(() {
      _isDragging = false;
      _isSelecting = false;
      _error = message;
    });
  }

  void _onDrop(DropDoneDetails details) {
    if (_isSelecting || !_isCurrent) return;
    if (details.files.length != 1) {
      _showError(_text('请一次拖入一个 ZIP 文件。', 'Drop one ZIP file at a time.'));
      return;
    }
    _selectZip(() async => details.files.single.path);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final supportsDrop = !kIsWeb &&
        switch (theme.platform) {
          TargetPlatform.windows ||
          TargetPlatform.macOS ||
          TargetPlatform.linux =>
            true,
          _ => false,
        };
    final uploadArea = ImportSourcePicker(
      icon: Icons.file_upload_outlined,
      highlighted: _isDragging,
      onPressed: _isSelecting ? null : () => _selectZip(widget.pickZipPath),
      label: _isDragging
          ? Text(_text('松开鼠标以导入 ZIP', 'Drop to import the ZIP'))
          : Text.rich(
              TextSpan(
                children: [
                  if (supportsDrop)
                    TextSpan(
                      text: _text('将 ZIP 文件拖到此处，或 ', 'Drag a ZIP here or '),
                      style: TextStyle(color: colors.onSurface),
                    ),
                  TextSpan(
                    text: _text('选择文件', 'Choose a file'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
      hint: _text(
        '请上传完整压缩包，无需解压',
        'Upload the full ZIP without extracting it',
      ),
    );

    return ImportSourceDialog(
      title: _text('从 Notion 导入', 'Import from Notion'),
      description: _text(
        '在当前工作区创建私有空间，保留父子页面层级',
        'Keep your page hierarchy in a private space in this workspace',
      ),
      picker: supportsDrop
          ? DropTarget(
              onDragEntered: (_) {
                if (!_isSelecting && _isCurrent) {
                  setState(() => _isDragging = true);
                }
              },
              onDragExited: (_) => setState(() => _isDragging = false),
              onDragDone: _onDrop,
              child: uploadArea,
            )
          : uploadArea,
      status: _error == null
          ? null
          : Text(_error!, style: TextStyle(color: colors.error)),
      instructions: _text(
        '在 Notion 中导出为「Markdown 与 CSV」，并勾选「包含子页面」。\n导入需要连接云端。',
        'In Notion, export as Markdown & CSV with Include subpages enabled.\nImport requires a cloud connection.',
      ),
      cancelLabel: _text('取消', 'Cancel'),
      onCancel: () => Navigator.of(context).pop(),
    );
  }
}

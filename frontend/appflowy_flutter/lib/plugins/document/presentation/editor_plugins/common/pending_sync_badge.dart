import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/file_storage_task.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// 「待同步」角标：附件（图片/文件）已存在本地、但尚未上传到云端时展示。
///
/// 【离线上传支持 2026-07-19】断网时插入的图片/文件会先落本地缓存并进入上传队列，
/// 联网后由 uploader 自动续传。此角标用于让用户知晓"内容已保存在本地、稍后会同步"，
/// 避免误以为丢失。
///
/// 设计要点：
/// - **纯附加组件**，不介入宿主的任何布局与渲染逻辑，最大限度避免影响既有显示；
/// - 上传完成（progress >= 1.0）后自动隐藏，不占位；
/// - 无法判定状态时**默认不展示**，宁可不提示也不误报（错误的"待同步"比没有更糟）。
class PendingSyncBadge extends StatefulWidget {
  const PendingSyncBadge({
    super.key,
    required this.fileUrl,
    this.compact = false,
  });

  /// 附件的云端 URL（即上传记录的键）。
  final String fileUrl;

  /// 紧凑模式：仅显示图标，用于空间受限处（如文件块行内）。
  final bool compact;

  @override
  State<PendingSyncBadge> createState() => _PendingSyncBadgeState();
}

class _PendingSyncBadgeState extends State<PendingSyncBadge> {
  AutoRemoveNotifier<FileProgress>? _notifier;

  /// 是否待同步。初始为 false —— 未确认前不展示，避免误报。
  bool _pending = false;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(covariant PendingSyncBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fileUrl != widget.fileUrl) {
      _unbind();
      _pending = false;
      _bind();
    }
  }

  @override
  void dispose() {
    _unbind();
    super.dispose();
  }

  void _bind() {
    final url = widget.fileUrl;
    if (url.isEmpty) return;

    // 本地文件（非云端 URL）不涉及同步，直接不展示。
    if (!url.startsWith('http')) return;

    final service = getIt<FileStorageService>();

    final notifier = service.onFileProgress(fileUrl: url);
    _notifier = notifier;
    notifier.addListener(_onProgress);
  }

  void _unbind() {
    _notifier?.removeListener(_onProgress);
    _notifier?.dispose();
    _notifier = null;
  }

  void _onProgress() {
    final progress = _notifier?.value;
    if (progress == null) return;

    _setPending(progress.error == null && progress.progress == 0);
  }

  void _setPending(bool value) {
    if (!mounted || _pending == value) return;
    setState(() => _pending = value);
  }

  @override
  Widget build(BuildContext context) {
    if (!_pending) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final label = LocaleKeys.document_plugins_pendingSync.tr();

    if (widget.compact) {
      return Tooltip(
        message: label,
        child: Icon(Icons.cloud_upload_outlined, size: 14, color: color),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_upload_outlined, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

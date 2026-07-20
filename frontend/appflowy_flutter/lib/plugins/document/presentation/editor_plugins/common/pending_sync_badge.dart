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

    // 先查一次当前状态：未完成则展示「待同步」。
    //
    // 这一步覆盖"重开文档"的场景：断网期间插入的附件此时既没有进行中的进度事件、
    // 也还没触发新的错误，仅靠 onFileProgress 无法得知它仍未上传。
    service.getFileState(url).then((result) {
      if (!mounted) return;
      result.fold(
        (state) => _setPending(!state.isFinish),
        // 查询失败时不展示，避免误报（错误的「待同步」比不提示更糟）。
        (_) {},
      );
    });

    final notifier = service.onFileProgress(fileUrl: url);
    _notifier = notifier;
    notifier.addListener(_onProgress);
  }

  void _unbind() {
    _notifier?.removeListener(_onProgress);
    // 注意：notifier 由 FileStorageService 统一管理生命周期（AutoRemoveNotifier），
    // 此处只移除监听，不能 dispose，否则会影响其它监听方。
    _notifier = null;
  }

  void _onProgress() {
    final progress = _notifier?.value;
    if (progress == null) return;

    // 已完成 → 一律隐藏。
    if (progress.progress >= 1.0) {
      _setPending(false);
      return;
    }

    // 【避免与既有进度条重复】文件块自带 LinearProgressIndicator，
    // 但其 `_isUploading` 在 `error != null` 时返回 false —— 也就是说
    // **断网报错后进度条会消失，此时没有任何状态提示**，正是本角标要补的空缺。
    //
    // 因此：正在正常上传（无错误、进度推进中）时交给进度条，本角标不展示；
    // 一旦出现错误（断网/失败待重试），才展示「待同步」。
    final hasError = progress.error != null && progress.error!.isNotEmpty;
    _setPending(hasError);
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

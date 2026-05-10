import 'dart:io';

import 'package:flutter/material.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/bottom_sheet.dart';
import 'package:appflowy/mobile/presentation/widgets/widgets.dart';
import 'package:appflowy/plugins/file_library/application/file_library_bloc.dart';
import 'package:appflowy/plugins/file_library/application/file_library_models.dart';
import 'package:appflowy/plugins/file_library/application/file_library_service.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/media_entities.pbenum.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:intl/intl.dart';
import 'package:fluttertoast/fluttertoast.dart';

class MobileFileLibraryPage extends StatefulWidget {
  const MobileFileLibraryPage({super.key});

  static const routeName = '/file-library';

  @override
  State<MobileFileLibraryPage> createState() => _MobileFileLibraryPageState();
}

class _MobileFileLibraryPageState extends State<MobileFileLibraryPage> {
  late FileLibraryBloc _bloc;
  FileLibraryCategory _selectedCategory = FileLibraryCategory.all;

  @override
  void initState() {
    super.initState();
    _bloc = FileLibraryBloc();
    _bloc.add(const FileLibraryEvent.started());
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _bloc,
      child: BlocListener<FileLibraryBloc, FileLibraryState>(
        listener: (context, state) {
          if (state.error != null) {
            Fluttertoast.showToast(
              msg: state.error!,
              gravity: ToastGravity.BOTTOM,
              backgroundColor: Colors.red.shade600,
              textColor: Colors.white,
            );
          }
        },
        child: Scaffold(
          appBar: AppBar(
            leading: const AppBarBackButton(),
            title: const Text('文件库'),
            centerTitle: true,
            actions: [
              BlocBuilder<FileLibraryBloc, FileLibraryState>(
                builder: (context, state) {
                  return IconButton(
                    splashRadius: 20,
                    icon: const Icon(Icons.add),
                    onPressed: state.isImporting
                        ? null
                        : () {
                            _bloc.add(const FileLibraryEvent.importPdfFile());
                          },
                    tooltip: '上传文件',
                  );
                },
              ),
            ],
          ),
          body: Column(
            children: [
              _buildCategoryTabs(),
              Expanded(
                child: _buildFileList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryTabs() {
    final categories = [
      (FileLibraryCategory.all, '全部'),
      (FileLibraryCategory.image, '图片'),
      (FileLibraryCategory.document, '文档'),
      (FileLibraryCategory.audio, '音频'),
      (FileLibraryCategory.video, '视频'),
    ];

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 0.5,
          ),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (category, label) = categories[index];
          final isSelected = _selectedCategory == category;
          return Center(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedCategory = category;
                });
                _bloc.add(FileLibraryEvent.categoryChanged(category));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected
                        ? Theme.of(context).colorScheme.onPrimary
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFileList() {
    return BlocBuilder<FileLibraryBloc, FileLibraryState>(
      builder: (context, state) {
        if (state.isLoading) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        if (state.filteredFiles.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FlowySvg(
                  FlowySvgs.open_folder_lg,
                  size: const Size.square(64),
                  color: Theme.of(context).hintColor,
                ),
                const SizedBox(height: 16),
                FlowyText.medium(
                  '暂无文件',
                  fontSize: 18,
                  color: Theme.of(context).hintColor,
                ),
                const SizedBox(height: 8),
                FlowyText.regular(
                  '点击右上角 + 按钮上传文件',
                  fontSize: 14,
                  color: Theme.of(context).hintColor,
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            _bloc.add(const FileLibraryEvent.refreshFiles());
          },
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: state.filteredFiles.length,
            itemBuilder: (context, index) {
              final file = state.filteredFiles[index];
              return _buildFileItem(file);
            },
          ),
        );
      },
    );
  }

  Widget _buildFileItem(FileLibraryItem file) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () {
        _showFileActionsSheet(file);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: theme.dividerColor,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            _FileTypeIcon(file: file),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        _formatDate(file.createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatFileSize(file.size),
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                      if (file.duration != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          _formatDuration(file.duration!),
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              Icons.more_horiz,
              size: 20,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  void _showFileActionsSheet(FileLibraryItem file) {
    showMobileBottomSheet(
      context,
      showHeader: true,
      showCloseButton: true,
      showDragHandle: true,
      title: file.name,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BottomSheetActionWidget(
            svg: FlowySvgs.m_home_search_icon_m,
            text: '打开文件',
            onTap: () {
              Navigator.of(context).pop();
              _bloc.add(FileLibraryEvent.openFile(file));
            },
          ),
          const SizedBox(height: 8),
          BottomSheetActionWidget(
            svg: FlowySvgs.trash_s,
            text: '删除',
            onTap: () {
              Navigator.of(context).pop();
              _confirmDeleteFile(file);
            },
          ),
        ],
      ),
    );
  }

  void _confirmDeleteFile(FileLibraryItem file) {
    showFlowyMobileConfirmDialog(
      context,
      title: const FlowyText('删除文件'),
      content: FlowyText('确定要删除 "${file.name}" 吗？此操作不可恢复。'),
      actionButtonTitle: '删除',
      actionButtonColor: Theme.of(context).colorScheme.error,
      cancelButtonTitle: '取消',
      onActionButtonPressed: () {
        _bloc.add(FileLibraryEvent.deleteFile(file.id));
        Fluttertoast.showToast(
          msg: '文件已删除',
          gravity: ToastGravity.BOTTOM,
        );
      },
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '未知';
    return DateFormat('yyyy/MM/dd').format(date);
  }

  String _formatFileSize(int? size) {
    if (size == null) return '未知';
    if (size < 1024) return '${size}B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)}KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }
}

class _FileTypeIcon extends StatelessWidget {
  const _FileTypeIcon({required this.file});

  final FileLibraryItem file;

  @override
  Widget build(BuildContext context) {
    final color = _getFileTypeColor(file.fileType);
    final icon = _getFileTypeIcon(file.fileType);

    if (file.fileType == MediaFileTypePB.Image) {
      final imageFile = File(file.url);
      if (imageFile.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.file(
            imageFile,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildPlaceholder(color, icon),
          ),
        );
      }
    }

    return _buildPlaceholder(color, icon);
  }

  Widget _buildPlaceholder(Color color, IconData icon) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
        ),
      ),
      child: Icon(
        icon,
        color: color,
        size: 24,
      ),
    );
  }

  Color _getFileTypeColor(MediaFileTypePB fileType) {
    switch (fileType) {
      case MediaFileTypePB.Document:
        return Colors.red;
      case MediaFileTypePB.Image:
        return Colors.blue;
      case MediaFileTypePB.Video:
        return Colors.purple;
      case MediaFileTypePB.Audio:
        return Colors.orange;
      case MediaFileTypePB.Archive:
        return Colors.brown;
      case MediaFileTypePB.Text:
        return Colors.green;
      case MediaFileTypePB.Other:
      default:
        return Colors.grey;
    }
  }

  IconData _getFileTypeIcon(MediaFileTypePB fileType) {
    switch (fileType) {
      case MediaFileTypePB.Document:
        return Icons.picture_as_pdf;
      case MediaFileTypePB.Image:
        return Icons.image;
      case MediaFileTypePB.Video:
        return Icons.play_arrow;
      case MediaFileTypePB.Audio:
        return Icons.audiotrack;
      case MediaFileTypePB.Archive:
        return Icons.archive;
      case MediaFileTypePB.Text:
        return Icons.description;
      case MediaFileTypePB.Other:
      default:
        return Icons.insert_drive_file;
    }
  }
}

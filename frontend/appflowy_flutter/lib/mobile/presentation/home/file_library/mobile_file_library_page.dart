import 'dart:io';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/bottom_sheet.dart';
import 'package:appflowy/mobile/presentation/widgets/widgets.dart';
import 'package:appflowy/plugins/file_library/application/file_library_bloc.dart';
import 'package:appflowy/plugins/file_library/application/file_library_models.dart';
import 'package:appflowy/plugins/file_library/application/file_library_service.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/media_entities.pbenum.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSelectMode = false;
  final Set<String> _selectedFileIds = {};

  @override
  void initState() {
    super.initState();
    _bloc = FileLibraryBloc();
    _bloc.add(const FileLibraryEvent.started());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _bloc.close();
    super.dispose();
  }

  void _toggleSelectMode() {
    setState(() {
      _isSelectMode = !_isSelectMode;
      if (!_isSelectMode) {
        _selectedFileIds.clear();
      }
    });
  }

  void _toggleFileSelection(String fileId) {
    setState(() {
      if (_selectedFileIds.contains(fileId)) {
        _selectedFileIds.remove(fileId);
      } else {
        _selectedFileIds.add(fileId);
      }
      if (_selectedFileIds.isEmpty) {
        _isSelectMode = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final afTheme = AppFlowyTheme.of(context);
    final theme = Theme.of(context);

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
          backgroundColor: theme.scaffoldBackgroundColor,
          body: SafeArea(
            child: Column(
              children: [
                _buildAppBar(context, afTheme, theme),
                _buildSearchBar(afTheme, theme),
                _buildCategoryTabs(afTheme, theme),
                Expanded(
                  child: _buildFileList(afTheme, theme),
                ),
              ],
            ),
          ),
          floatingActionButton: _buildFab(afTheme),
        ),
      ),
    );
  }

  Widget _buildAppBar(
    BuildContext context,
    AppFlowyThemeData afTheme,
    ThemeData theme,
  ) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: FlowySvg(
              FlowySvgs.m_app_bar_back_s,
              size: const Size(7, 12),
              color: afTheme.iconColorScheme.primary,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '文件库',
              style: afTheme.textStyle.heading4.standard(
                color: afTheme.textColorScheme.primary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          TextButton(
            onPressed: _toggleSelectMode,
            child: FlowyText(
              _isSelectMode ? '取消' : '选择',
              fontSize: 16,
              color: afTheme.textColorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(AppFlowyThemeData afTheme, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
        decoration: InputDecoration(
          hintText: '搜索文件',
          isDense: true,
          prefixIconConstraints:
              const BoxConstraints(minWidth: 38, minHeight: 40),
          prefixIcon: Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
            child: FlowySvg(
              FlowySvgs.m_home_search_icon_m,
              color: afTheme.iconColorScheme.secondary,
              size: const Size.square(20),
            ),
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 10, 8, 10),
                    child: FlowySvg(
                      FlowySvgs.search_clear_m,
                      color: afTheme.iconColorScheme.tertiary,
                      size: const Size.square(20),
                    ),
                  ),
                )
              : null,
          contentPadding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
          filled: true,
          fillColor: const Color(0xFFF5F5F5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryTabs(AppFlowyThemeData afTheme, ThemeData theme) {
    final categories = [
      (FileLibraryCategory.all, '全部'),
      (FileLibraryCategory.image, '图片'),
      (FileLibraryCategory.document, '文档'),
      (FileLibraryCategory.audio, '音频'),
      (FileLibraryCategory.video, '视频'),
    ];

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                final (category, label) = categories[index];
                final isSelected = _selectedCategory == category;
                return _CategoryTabItem(
                  label: label,
                  isSelected: isSelected,
                  onTap: () {
                    setState(() {
                      _selectedCategory = category;
                    });
                    _bloc.add(FileLibraryEvent.categoryChanged(category));
                  },
                );
              },
            ),
          ),
          _buildSortSection(afTheme, theme),
        ],
      ),
    );
  }

  Widget _buildSortSection(AppFlowyThemeData afTheme, ThemeData theme) {
    return BlocBuilder<FileLibraryBloc, FileLibraryState>(
      builder: (context, state) {
        return GestureDetector(
          onTap: () => _showSortMenu(context, afTheme, state.sortBy),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FlowyText(
                  state.sortBy,
                  fontSize: 13,
                  color: afTheme.textColorScheme.secondary,
                ),
                const SizedBox(width: 4),
                FlowySvg(
                  FlowySvgs.arrow_down_s,
                  size: const Size.square(14),
                  color: afTheme.iconColorScheme.secondary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSortMenu(
      BuildContext context, AppFlowyThemeData afTheme, String currentSort) {
    final sortOptions = ['添加日期', '标题名称', '文件大小'];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FlowyText.semibold(
                '排序方式',
                fontSize: 16,
                color: afTheme.textColorScheme.primary,
              ),
            ),
            ...sortOptions.map((option) {
              final isSelected = option == currentSort;
              return ListTile(
                title: FlowyText(
                  option,
                  fontSize: 15,
                  color: isSelected
                      ? afTheme.textColorScheme.primary
                      : afTheme.textColorScheme.secondary,
                ),
                trailing: isSelected
                    ? FlowySvg(
                        FlowySvgs.check_s,
                        size: const Size.square(16),
                        color: afTheme.iconColorScheme.primary,
                      )
                    : null,
                onTap: () {
                  _bloc.add(FileLibraryEvent.sortChanged(option));
                  Navigator.pop(ctx);
                },
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildFileList(AppFlowyThemeData afTheme, ThemeData theme) {
    return BlocBuilder<FileLibraryBloc, FileLibraryState>(
      builder: (context, state) {
        if (state.isLoading) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        // Filter by search query
        final filteredFiles = _searchQuery.isEmpty
            ? state.filteredFiles
            : state.filteredFiles
                .where((f) =>
                    f.name.toLowerCase().contains(_searchQuery.toLowerCase()))
                .toList();

        if (filteredFiles.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FlowySvg(
                  FlowySvgs.open_folder_lg,
                  size: const Size.square(64),
                  color: theme.hintColor,
                ),
                const SizedBox(height: 16),
                FlowyText.medium(
                  '暂无文件',
                  fontSize: 18,
                  color: theme.hintColor,
                ),
                const SizedBox(height: 8),
                FlowyText.regular(
                  '点击右下角 + 按钮上传文件',
                  fontSize: 14,
                  color: theme.hintColor,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 80),
          itemCount: filteredFiles.length,
          itemBuilder: (context, index) {
            final file = filteredFiles[index];
            return _buildFileItem(file, afTheme, theme);
          },
        );
      },
    );
  }

  Widget _buildFileItem(
      FileLibraryItem file, AppFlowyThemeData afTheme, ThemeData theme) {
    final isSelected = _selectedFileIds.contains(file.id);
    return InkWell(
      onTap: () {
        if (_isSelectMode) {
          _toggleFileSelection(file.id);
        } else {
          _showFileActionsSheet(file);
        }
      },
      onLongPress: () {
        if (!_isSelectMode) {
          setState(() {
            _isSelectMode = true;
            _selectedFileIds.add(file.id);
          });
        }
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
            if (_isSelectMode) ...[
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color:
                      isSelected ? const Color(0xFFFF6B35) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? const Color(0xFFFF6B35) : Colors.grey,
                    width: 1.5,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),
            ],
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
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatFileSize(file.size),
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5),
                        ),
                      ),
                      if (file.duration != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          _formatDuration(file.duration!),
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (!_isSelectMode)
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

  Widget _buildFab(AppFlowyThemeData afTheme) {
    return BlocBuilder<FileLibraryBloc, FileLibraryState>(
      builder: (context, state) {
        return FloatingActionButton(
          onPressed: state.isImporting
              ? null
              : () {
                  _bloc.add(const FileLibraryEvent.importPdfFile());
                },
          backgroundColor: const Color(0xFFFF6B35),
          elevation: 4,
          child: state.isImporting
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Icon(Icons.add, color: Colors.white, size: 28),
        );
      },
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

class _CategoryTabItem extends StatelessWidget {
  const _CategoryTabItem({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected
                  ? const Color(0xFFFF6B35)
                  : theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 2,
            width: label.length * 14.0,
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFFF6B35) : Colors.transparent,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ),
    );
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

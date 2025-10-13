import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:intl/intl.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/media_entities.pbenum.dart';
import 'package:appflowy_popover/appflowy_popover.dart';

import '../application/file_library_bloc.dart';
import '../application/file_library_models.dart';
import 'file_preview_thumbnail.dart';

class FileLibraryPage extends StatefulWidget {
  const FileLibraryPage({super.key});

  @override
  State<FileLibraryPage> createState() => _FileLibraryPageState();
}

class _FileLibraryPageState extends State<FileLibraryPage> {
  late FileLibraryBloc _bloc;
  FileLibraryCategory _selectedCategory = FileLibraryCategory.all;
  
  // Popover 控制器
  final PopoverController _sortPopoverController = PopoverController();
  final Map<String, PopoverController> _fileMenuControllers = {};

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
          // 显示消息提示
          if (state.error != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.error!),
                backgroundColor: Colors.red,
              ),
            );
          }
          // 移除成功和信息提示，只保留错误提示
        },
        child: Container(
          width: double.infinity,
          height: double.infinity,
          child: Row(
            children: [
              // 左侧文件分类侧边栏
              Container(
                width: 250,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                clipBehavior: Clip.hardEdge,
                child: Column(
                  children: [
                    // 顶部标题
                    Container(
                      height: 50,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: Theme.of(context).dividerColor,
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Text(
                            '文件库',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          BlocBuilder<FileLibraryBloc, FileLibraryState>(
                            builder: (context, state) {
                              return FlowyIconButton(
                                icon: const FlowySvg(
                                  FlowySvgs.fl_upload_m,
                                  size: Size.square(18),
                                ),
                                onPressed: state.isImporting
                                    ? null
                                    : () {
                                        _bloc.add(const FileLibraryEvent.importPdfFile());
                                      },
                                tooltipText: '上传文件',
                                hoverColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    // 分类列表
                    Expanded(
                      child: _buildCategoryList(),
                    ),
                  ],
                ),
              ),
              // 右侧文件列表区域
              Expanded(
                child: Container(
                  width: double.infinity,
                  height: double.infinity,
                  color: Theme.of(context).colorScheme.surface,
                  child: _buildMainContent(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryList() {
    return BlocBuilder<FileLibraryBloc, FileLibraryState>(
      builder: (context, state) {
        final categories = [
          {'category': FileLibraryCategory.all, 'name': '全部文件', 'icon': FlowySvgs.dl_folder_s},
          {'category': FileLibraryCategory.image, 'name': '图片文件', 'icon': FlowySvgs.dl_image_s},
          {'category': FileLibraryCategory.document, 'name': '文档文件', 'icon': FlowySvgs.dl_document_s},
          {'category': FileLibraryCategory.audio, 'name': '音频文件', 'icon': FlowySvgs.dl_audio_s},
          {'category': FileLibraryCategory.video, 'name': '视频文件', 'icon': FlowySvgs.dl_video_s},
          {'category': FileLibraryCategory.archive, 'name': '百度云盘', 'icon': FlowySvgs.baidu_cloud_disk_s},
          {'category': FileLibraryCategory.text, 'name': '阿里云盘', 'icon': FlowySvgs.aliyun_drive_s},
          {'category': FileLibraryCategory.other, 'name': '坚果云云盘', 'icon': FlowySvgs.nuts_cloud_disk_s},
        ];

        // 分离本地文件类型和云盘类型
        final localCategories = categories.take(5).toList(); // 全部文件到视频文件
        final cloudCategories = categories.skip(5).toList(); // 百度云盘到坚果云云盘

        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            // 本地文件分类
            ...localCategories.map((categoryData) {
              final category = categoryData['category'] as FileLibraryCategory;
              return _buildCategoryItem(
                category,
                categoryData['name'] as String,
                categoryData['icon'] as FlowySvgData,
              );
            }),
            // 分割线
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              height: 1,
              color: Theme.of(context).dividerColor.withOpacity(0.8),
            ),
            // 云盘分类
            ...cloudCategories.map((categoryData) {
              final category = categoryData['category'] as FileLibraryCategory;
              return _buildCategoryItem(
                category,
                categoryData['name'] as String,
                categoryData['icon'] as FlowySvgData,
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildCategoryItem(FileLibraryCategory category, String name, FlowySvgData icon) {
    final isSelected = _selectedCategory == category;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected 
            ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
            : null,
        borderRadius: BorderRadius.circular(8),
        border: isSelected 
            ? Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: 1,
              )
            : null,
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedCategory = category;
          });
          _bloc.add(FileLibraryEvent.categoryChanged(category));
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              FlowySvg(
                icon,
                size: const Size.square(16),
                color: Theme.of(context).iconTheme.color,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                    color: isSelected 
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return Column(
      children: [
        // 工具栏
        _buildToolbar(),
        // 排序区域
        _buildSortSection(),
        // 文件列表
        Expanded(
          child: _buildFileList(),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Row(
        children: [
          Text(
            _selectedCategory.displayName,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortSection() {
    return BlocBuilder<FileLibraryBloc, FileLibraryState>(
      builder: (context, state) {
        return Container(
          padding: const EdgeInsets.fromLTRB(24.0, 0, 24.0, 12.0),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              // 排序下拉菜单
              AppFlowyPopover(
                controller: _sortPopoverController,
                direction: PopoverDirection.bottomWithLeftAligned,
                popupBuilder: (context) => _buildSortMenu(state.sortBy),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      state.sortBy,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    FlowySvg(
                      FlowySvgs.arrow_down_s,
                      size: const Size.square(16),
                      color: Theme.of(context).hintColor,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.folder_open, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  '暂无文件',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '点击左上角的上传按钮导入文件',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          );
        }

        // 如果按日期排序，需要分组显示
        if (state.sortBy == '添加日期') {
          return _buildGroupedFileList(state.filteredFiles);
        }

        return ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: state.filteredFiles.length,
          itemBuilder: (context, index) {
            final file = state.filteredFiles[index];
            return _buildFileItem(file);
          },
        );
      },
    );
  }

  // 按日期分组显示文件列表
  Widget _buildGroupedFileList(List<FileLibraryItem> files) {
    // 按日期分组
    final Map<String, List<FileLibraryItem>> groupedFiles = {};
    
    for (final file in files) {
      // 如果没有创建时间，使用一个默认分组
      final dateTime = file.createdAt ?? DateTime.now();
      final date = DateFormat('yyyy年M月d日').format(dateTime);
      if (!groupedFiles.containsKey(date)) {
        groupedFiles[date] = [];
      }
      groupedFiles[date]!.add(file);
    }

    // 获取排序后的日期列表
    final sortedDates = groupedFiles.keys.toList()
      ..sort((a, b) {
        // 解析日期进行比较
        final dateA = groupedFiles[a]!.first.createdAt ?? DateTime.now();
        final dateB = groupedFiles[b]!.first.createdAt ?? DateTime.now();
        return dateB.compareTo(dateA); // 降序排列，最新的在前面
      });

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: sortedDates.length,
      itemBuilder: (context, groupIndex) {
        final date = sortedDates[groupIndex];
        final groupFiles = groupedFiles[date]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 如果不是第一个分组，添加分割线
            if (groupIndex > 0)
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 8),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context).dividerColor,
                      width: 0.5,
                    ),
                  ),
                ),
              ),
            // 日期分组头
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                date,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.6),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            // 该日期下的所有文件
            ...groupFiles.map((file) => _buildFileItem(file)),
          ],
        );
      },
    );
  }

  Widget _buildFileItem(FileLibraryItem file) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.5),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          // 可点击区域（文件预览和信息）
          Expanded(
            child: InkWell(
              onTap: () {
                // 点击打开文件
                _bloc.add(FileLibraryEvent.openFile(file));
              },
              child: Row(
                children: [
                  // 文件预览缩略图
                  FilePreviewThumbnail(
                    key: ValueKey(file.url), // 使用文件 URL 作为唯一 key
                    file: file,
                    size: 48,
                  ),
                  const SizedBox(width: 12),
                  // 文件信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          file.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
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
                                color: Theme.of(context).textTheme.bodySmall?.color,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _formatFileSize(file.size),
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).textTheme.bodySmall?.color,
                              ),
                            ),
                            // 对于视频和音频文件，显示时长
                            if (file.fileType == MediaFileTypePB.Video || 
                                file.fileType == MediaFileTypePB.Audio) ...[
                              const SizedBox(width: 12),
                              Text(
                                _formatDuration(file.duration),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).textTheme.bodySmall?.color,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 操作按钮（独立，不在 InkWell 内）
          AppFlowyPopover(
            controller: _fileMenuControllers.putIfAbsent(
              file.id,
              () => PopoverController(),
            ),
            direction: PopoverDirection.bottomWithRightAligned,
            popupBuilder: (context) => _buildFileMenu(file),
            child: const Icon(
              Icons.more_horiz,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  // 构建排序菜单
  Widget _buildSortMenu(String currentSortBy) {
    return Container(
      width: 120,
      padding: const EdgeInsets.all(4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSortMenuItem('标题名称', currentSortBy),
          _buildSortMenuItem('大小', currentSortBy),
          _buildSortMenuItem('添加日期', currentSortBy),
        ],
      ),
    );
  }

  // 构建排序菜单项
  Widget _buildSortMenuItem(String text, String currentSortBy) {
    final isSelected = currentSortBy == text;
    return InkWell(
      onTap: () {
        _sortPopoverController.close();
        _bloc.add(FileLibraryEvent.sortChanged(text));
      },
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }

  // 构建文件操作菜单
  Widget _buildFileMenu(FileLibraryItem file) {
    return Container(
      width: 100,
      padding: const EdgeInsets.all(4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () {
              _fileMenuControllers[file.id]?.close();
              _bloc.add(FileLibraryEvent.openFile(file));
            },
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Icon(Icons.open_in_new, size: 18),
                  SizedBox(width: 8),
                  Text('打开', style: TextStyle(fontSize: 14)),
                ],
              ),
            ),
          ),
          InkWell(
            onTap: () {
              _fileMenuControllers[file.id]?.close();
              _bloc.add(FileLibraryEvent.deleteFile(file.id));
            },
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  SizedBox(width: 8),
                  Text(
                    '删除',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 辅助方法
  String _formatDate(DateTime? date) {
    if (date == null) return '未知';
    return DateFormat('yyyy/MM/dd').format(date);
  }

  String _formatFileSize(int? size) {
    if (size == null) return '未知';
    if (size < 1024) return '${size}B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)}KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  String _formatDuration(int? seconds) {
    if (seconds == null) return '未知';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    
    if (hours > 0) {
      return '${hours}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    } else {
      return '${minutes}:${secs.toString().padLeft(2, '0')}';
    }
  }
}


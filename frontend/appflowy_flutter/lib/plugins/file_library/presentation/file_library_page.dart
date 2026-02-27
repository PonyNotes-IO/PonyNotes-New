import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/media_entities.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_popover/appflowy_popover.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/workspace/workspace_service.dart';
import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_block.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/custom_image_block_component/custom_image_block_component.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/presentation/home/full_window_controller.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';

import '../application/file_library_bloc.dart';
import '../application/file_library_models.dart';
import '../application/file_library_service.dart';
import '../services/baidu_cloud_service.dart';
import '../presentation/baidu_cloud_file_picker.dart';
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
        child: ValueListenableBuilder<bool>(
          valueListenable: FullWindowController.isFullWindow,
          builder: (context, isFullWindow, _) {
            final menuStatus = context.select<HomeSettingBloc, MenuStatus>(
              (bloc) => bloc.state.menuStatus,
            );
            final shouldApplyTopPadding =
                !isFullWindow && menuStatus != MenuStatus.expanded;
            final contentTopPadding = shouldApplyTopPadding
                ? HomeSizes.topBarHeight + HomeInsets.topBarTitleVerticalPadding
                : 0.0;

            return Container(
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
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Visibility(
                          visible: shouldApplyTopPadding,
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: FlowyIconButton(
                              width: 24,
                              tooltipText: LocaleKeys.sideBar_openSidebar.tr(),
                              radius: const BorderRadius.all(Radius.circular(8.0)),
                              icon: const FlowySvg(
                                FlowySvgs.show_menu_s,
                                size: Size.square(16),
                              ),
                              onPressed: () {
                                if (FullWindowController.isFullWindow.value) {
                                  FullWindowController.exit();
                                }
                                context.read<HomeSettingBloc>().add(
                                  HomeSettingEvent.changeMenuStatus(MenuStatus.expanded),
                                );
                              },
                            ),
                          ),
                        ),
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
                    child: Padding(
                      padding: EdgeInsets.only(top: contentTopPadding),
                      child: Container(
                        width: double.infinity,
                        height: double.infinity,
                        color: Theme.of(context).colorScheme.surface,
                        child: _buildMainContent(),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCategoryList() {
    return BlocBuilder<FileLibraryBloc, FileLibraryState>(
      builder: (context, state) {
        final localCategories = [
          {'category': FileLibraryCategory.all, 'name': '全部文件', 'icon': FlowySvgs.dl_folder_s},
          {'category': FileLibraryCategory.image, 'name': '图片文件', 'icon': FlowySvgs.dl_image_s},
          {'category': FileLibraryCategory.document, 'name': '文档文件', 'icon': FlowySvgs.dl_document_s},
          {'category': FileLibraryCategory.audio, 'name': '音频文件', 'icon': FlowySvgs.dl_audio_s},
          {'category': FileLibraryCategory.video, 'name': '视频文件', 'icon': FlowySvgs.dl_video_s},
        ];

        // final cloudDrives = [
        //   {'name': '百度云盘', 'icon': FlowySvgs.baidu_cloud_disk_s},
        //   {'name': '阿里云盘', 'icon': FlowySvgs.aliyun_drive_s},
        //   {'name': '坚果云云盘', 'icon': FlowySvgs.nuts_cloud_disk_s},
        // ];

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
            // Container(
            //   margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            //   height: 1,
            //   color: Theme.of(context).dividerColor.withOpacity(0.8),
            // ),
            // 云盘分类（点击弹出对话框）
            // ...cloudDrives.map((driveData) {
            //   return _buildCloudDriveItem(
            //     driveData['name'] as String,
            //     driveData['icon'] as FlowySvgData,
            //   );
            // }),
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

  // 构建云盘项目（点击弹出对话框）
  Widget _buildCloudDriveItem(String name, FlowySvgData icon) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: () => _showCloudDriveDialog(name),
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
                    fontWeight: FontWeight.normal,
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 显示云盘对话框
  void _showCloudDriveDialog(String driveName) {
    if (driveName == '百度云盘') {
      _showBaiduCloudFileSelector();
    } else {
      // 其他云盘的简单确认对话框
      showDialog(
        context: context,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: Container(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 标题和提示信息区域
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(top: 24.0, left: 24.0, right: 24.0, bottom: 16.0),
                  child: Column(
                    children: [
                      Text(
                        '打开"$driveName"?',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '若要浏览和添加文件，请打开$driveName。',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                // 底部操作区域前的间距
                const SizedBox(height: 8),
                // 分割线
                Container(
                  width: double.infinity,
                  height: 1,
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                ),
                // 底部操作区域
                Container(
                  width: double.infinity,
                  height: 56,
                  child: Row(
                    children: [
                      // 取消区域
                      Expanded(
                        child: InkWell(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            alignment: Alignment.center,
                            child: Text(
                              '取消',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 垂直分割线
                      Container(
                        width: 1,
                        height: double.infinity,
                        color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                      ),
                      // 打开区域
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            Navigator.of(context).pop();
                            // 根据云盘名称调用相应的导入功能
                            if (driveName == '阿里云盘') {
                              // TODO: 实现阿里云盘导入
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('阿里云盘导入功能暂未实现'),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                            } else if (driveName == '坚果云云盘') {
                              // TODO: 实现坚果云导入
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('坚果云导入功能暂未实现'),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                            }
                          },
                          child: Container(
                            alignment: Alignment.center,
                            child: Text(
                              '打开',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  // 显示百度网盘文件选择器
  void _showBaiduCloudFileSelector() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Container(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题和提示信息区域
              Container(
                width: double.infinity,
                padding: const EdgeInsets.only(top: 24.0, left: 24.0, right: 24.0, bottom: 16.0),
                child: Column(
                  children: [
                    Text(
                      '打开"百度网盘"?',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '若要浏览和添加文件，请打开百度网盘。',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              // 底部操作区域前的间距
              const SizedBox(height: 8),
              // 分割线
              Container(
                width: double.infinity,
                height: 1,
                color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
              ),
              // 底部操作区域
              Container(
                width: double.infinity,
                height: 56,
                child: Row(
                  children: [
                    // 取消区域
                    Expanded(
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          alignment: Alignment.center,
                          child: Text(
                            '取消',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 垂直分割线
                    Container(
                      width: 1,
                      height: double.infinity,
                      color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                    ),
                    // 打开区域
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).pop();
                          // 打开百度网盘文件选择器
                          _openBaiduCloudPicker();
                        },
                        child: Container(
                          alignment: Alignment.center,
                          child: Text(
                            '打开',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 打开百度网盘文件选择器
  void _openBaiduCloudPicker() {
    showDialog(
      context: context,
      builder: (context) => BaiduCloudFilePickerDialog(
        onFilesSelected: (files) async {
          Navigator.of(context).pop();
          if (files.isNotEmpty) {
            await _importBaiduCloudFiles(files);
          }
        },
      ),
    );
  }

  // 导入百度网盘文件
  Future<void> _importBaiduCloudFiles(List<BaiduCloudFile> files) async {
    try {
      // 显示进度对话框
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('正在导入 ${files.length} 个文件...'),
            ],
          ),
        ),
      );

      // 调用服务导入文件
      final service = FileLibraryService();
      int successCount = 0;
      
      for (final file in files) {
        final result = await service.importBaiduCloudFile(file);
        if (result != null) {
          successCount++;
        }
      }

      // 关闭进度对话框
      Navigator.of(context).pop();

      // 显示结果
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('成功导入 $successCount/${files.length} 个文件'),
          backgroundColor: successCount == files.length 
              ? Colors.green 
              : Colors.orange,
        ),
      );

      // 刷新文件列表
      context.read<FileLibraryBloc>().add(const FileLibraryEvent.refreshFiles());
      
    } catch (e) {
      // 关闭进度对话框
      Navigator.of(context).pop();
      
      // 显示错误
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('导入失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
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
      width: 160,
      padding: const EdgeInsets.all(4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () {
              _fileMenuControllers[file.id]?.close();
              _createNoteWithFile(file);
            },
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('用文件创建笔记', style: TextStyle(fontSize: 14)),
              ),
            ),
          ),
          InkWell(
            onTap: () {
              _fileMenuControllers[file.id]?.close();
              _showFileDetailsDialog(file);
            },
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('详情', style: TextStyle(fontSize: 14)),
              ),
            ),
          ),
          Divider(height: 1, thickness: 1),
          InkWell(
            onTap: () {
              _fileMenuControllers[file.id]?.close();
              _bloc.add(FileLibraryEvent.deleteFile(file.id));
            },
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '删除',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
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

  String _getFileTypeText(MediaFileTypePB fileType) {
    switch (fileType) {
      case MediaFileTypePB.Image:
        return '图片';
      case MediaFileTypePB.Video:
        return '视频';
      case MediaFileTypePB.Audio:
        return '音频';
      case MediaFileTypePB.Document:
        return '文档';
      case MediaFileTypePB.Archive:
        return '压缩文件';
      case MediaFileTypePB.Other:
        return '其他';
      default:
        return '未知';
    }
  }

  // 显示文件详情对话框
  void _showFileDetailsDialog(FileLibraryItem file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('文件详情'),
        content: Container(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('文件名', file.name),
              SizedBox(height: 12),
              _buildDetailRow('文件类型', _getFileTypeText(file.fileType)),
              SizedBox(height: 12),
              _buildDetailRow('文件大小', _formatFileSize(file.size)),
              SizedBox(height: 12),
              _buildDetailRow('创建时间', _formatDate(file.createdAt)),
              if (file.duration != null) ...[
                SizedBox(height: 12),
                _buildDetailRow('时长', _formatDuration(file.duration)),
              ],
              SizedBox(height: 12),
              _buildDetailRow('来源', file.source),
              SizedBox(height: 12),
              _buildDetailRow('文件路径', file.url, isPath: true),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isPath = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 4),
        isPath
            ? SelectableText(
                value,
                style: TextStyle(fontSize: 14),
              )
            : Text(
                value,
                style: TextStyle(fontSize: 14),
              ),
      ],
    );
  }

  // 用文件创建笔记
  Future<void> _createNoteWithFile(FileLibraryItem file) async {
    try {
      // 1. 获取当前用户和工作空间信息
      final userProfileResult = await UserEventGetUserProfile().send();
      final userProfile = userProfileResult.fold(
        (profile) => profile,
        (error) => null,
      );
      
      if (userProfile == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('无法获取用户信息'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      
      final workspaceResult = await FolderEventGetCurrentWorkspaceSetting().send();
      
      final workspaceId = workspaceResult.fold(
        (workspace) => workspace.workspaceId,
        (error) => null,
      );
      
      if (workspaceId == null || workspaceId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('无法获取当前工作空间'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      
      // 2. 获取或创建私有空间（"我的空间"）
      final workspaceService = WorkspaceService(
        workspaceId: workspaceId,
        userId: userProfile.id,
      );
      
      // 先尝试获取所有公共和私有视图
      final publicViewsResult = await workspaceService.getPublicViews();
      final privateViewsResult = await workspaceService.getPrivateViews();
      
      final publicViews = publicViewsResult.fold(
        (views) => views,
        (error) => <ViewPB>[],
      );
      
      final privateViews = privateViewsResult.fold(
        (views) => views,
        (error) => <ViewPB>[],
      );
      
      final allViews = [...publicViews, ...privateViews];
      
      // 查找私有空间
      ViewPB? privateSpace = allViews.firstWhereOrNull(
        (view) => view.isSpace && view.spacePermission == SpacePermission.private,
      );
      
      // 如果没有找到私有空间，创建一个
      if (privateSpace == null) {
        final createResult = await workspaceService.createView(
          name: '我的空间',
          viewSection: ViewSectionPB.Private,
          extra: jsonEncode({
            ViewExtKeys.isSpaceKey: true,
            ViewExtKeys.spaceIconKey: '🏠',
            ViewExtKeys.spaceIconColorKey: 'blue',
            ViewExtKeys.spacePermissionKey: SpacePermission.private.index,
            ViewExtKeys.spaceCreatedAtKey: DateTime.now().millisecondsSinceEpoch,
          }),
        );
        
        privateSpace = createResult.fold(
          (space) => space,
          (error) => null,
        );
        
        if (privateSpace == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('无法创建"我的空间"'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }
      
      // 3. 在"我的空间"（私有空间）下创建文档
      // 注意：使用私有空间的ID作为parentViewId，section设为Private
      final result = await ViewBackendService.createView(
        layoutType: ViewLayoutPB.Document,
        parentViewId: privateSpace.id, // 使用私有空间ID作为parentViewId
        name: '', // 空标题，会显示为"未命名页面"
        openAfterCreate: false, // 先不自动打开，我们手动打开
        index: 0,
        section: ViewSectionPB.Private, // 放在"我的空间"（Private区域）
      );
      
      final createdView = result.fold(
        (view) => view,
        (error) => null,
      );
      
      if (createdView == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('创建笔记失败'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      
      // 4. 使用 TabsBloc 打开文档
      getIt<TabsBloc>().openPlugin(createdView);
      
      // 5. 等待文档打开并获取 EditorState
      // 尝试多次获取 DocumentBloc，因为文档可能需要时间初始化
      DocumentBloc? documentBloc;
      for (int i = 0; i < 15; i++) {
        await Future.delayed(const Duration(milliseconds: 300));
        documentBloc = DocumentBloc.findOpen(createdView.id);
        if (documentBloc != null && documentBloc.state.editorState != null) {
          break;
        }
      }
      
      if (documentBloc == null || documentBloc.state.editorState == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('无法访问文档编辑器，请手动插入文件'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
      
      final editorState = documentBloc.state.editorState!;
      
      // 6. 在文档中插入文件或图片
      final transaction = editorState.transaction;
      
      // 判断是否为图片文件
      final isImage = _isImageFile(file.name);
      
      if (isImage) {
        // 如果是图片，插入图片节点
        transaction.insertNode(
          [0],
          customImageNode(
            url: file.url,
            type: CustomImageType.local,
          ),
        );
      } else {
        // 如果是其他文件，插入文件节点
        transaction.insertNode(
          [0],
          fileNode(
            url: file.url,
            type: FileUrlType.local,
            name: file.name,
          ),
        );
      }
      
      await editorState.apply(transaction);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('笔记创建成功'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('创建笔记时发生错误: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 判断文件是否为图片
  bool _isImageFile(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    const imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg'];
    return imageExtensions.contains(extension);
  }
}



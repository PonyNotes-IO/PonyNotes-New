import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/widgets/date_picker/widgets/date_picker.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/text.dart';
import 'package:flowy_infra_ui/style_widget/hover.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/workspace/workspace_service.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy/plugins/document/document_page.dart';
import 'package:appflowy/workspace/application/view_info/view_info_bloc.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'widgets/schedule_sidebar.dart';
import 'package:flowy_infra/uuid.dart';
import 'package:nanoid/nanoid.dart';
import '../../../features/page_access_level/logic/page_access_level_bloc.dart';
import 'presentation/new_event_page.dart';
import 'presentation/edit_event_page.dart';
import 'widgets/schedule_sidebar.dart';
import 'models/schedule_model.dart';
import 'dart:ui' as ui;
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_backend/protobuf/flowy-error/protobuf.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy/plugins/document/presentation/editor_page.dart';
import 'package:appflowy/plugins/document/presentation/editor_style.dart';

// 添加日历事件类
class CalendarEvent {
  final String id;
  final DateTime date;
  final String title;
  final String description;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final bool isAllDay;
  final bool isImportant;
  final bool isRepeat;
  final String calendar;

  CalendarEvent({
    required this.id,
    required this.date,
    required this.title,
    required this.description,
    required this.startTime,
    required this.endTime,
    required this.isAllDay,
    required this.isImportant,
    required this.isRepeat,
    required this.calendar,
  });
}

class CalendarPluginBuilder extends PluginBuilder {
  @override
  Plugin build(dynamic data) {
    if (data is ViewPB) {
      return DatabaseTabBarViewPlugin(pluginType: pluginType, view: data);
    } else {
      // 支持无data时返回主日历页面
      return CalendarMainPlugin();
    }
  }

  @override
  String get menuName => LocaleKeys.calendar_menuName.tr();

  @override
  FlowySvgData get icon => FlowySvgs.icon_calendar_m;

  @override
  PluginType get pluginType => PluginType.calendar;

  @override
  ViewLayoutPB get layoutType => ViewLayoutPB.Calendar;
}

// 新增主日历插件
class CalendarMainPlugin extends Plugin {
  @override
  PluginType get pluginType => PluginType.calendar;

  @override
  PluginWidgetBuilder get widgetBuilder => CalendarMainWidgetBuilder();

  @override
  PluginId get id =>
      fixedUuid(12345, UuidType.privateSpace); // 使用与ScheduleModel相同的固定ID
}

class CalendarMainWidgetBuilder extends PluginWidgetBuilder {
  @override
  String? get viewName => '日历'; // 显示标题

  @override
  Widget get leftBarItem => const FlowyText.medium('日历'); // 显示左侧标题

  @override
  Widget? get rightBarItem => null;

  @override
  Widget tabBarItem(String pluginId, [bool shortForm = false]) =>
      leftBarItem; // 显示标签栏标题

  @override
  List<NavigationItem> get navigationItems => [this];

  @override
  EdgeInsets get contentPadding => EdgeInsets.zero; // 去除所有留白

  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) {
    // 不依赖context.userProfile，避免触发GET_VIEW_PB查询
    // 直接返回日历面板，避免视图查找错误
    return CalendarMainPanel();
  }
}

// 主日历面板骨架
class CalendarMainPanel extends StatefulWidget {
  @override
  State<CalendarMainPanel> createState() => _CalendarMainPanelState();
}

class _CalendarMainPanelState extends State<CalendarMainPanel> {
  late DateTime _focusedDay;
  late DateTime? _selectedDay;
  late DateTime _firstDay;
  late DateTime _lastDay;
  late int _currentMonthIndex;
  late int _currentYear;
  late List<CalendarEvent> _events;
  late bool _showNewEventPage;
  late bool _showEditEventPage; // 显示编辑日程页面
  late ScheduleItem? _editingSchedule; // 正在编辑的日程
  late Function()? _saveEventCallback;
  late String? _currentViewId; // 添加当前视图ID
  late bool _isSidebarExpanded;
  late PopoverController _settingsPopoverController;
  late PopoverController _addPopoverController;
  late ViewPB? _selectedNote; // 添加选中的笔记
  late GlobalKey<_CalendarContentState>
      _calendarContentKey; // 添加CalendarContent的key

  @override
  void initState() {
    super.initState();
    _focusedDay = DateTime.now();
    _selectedDay = DateTime.now();
    _firstDay = DateTime.now().subtract(Duration(days: 365));
    _lastDay = DateTime.now().add(Duration(days: 365));
    _currentMonthIndex = DateTime.now().month;
    _currentYear = DateTime.now().year;
    _events = [];
    _showNewEventPage = false;
    _showEditEventPage = false;
    _editingSchedule = null;
    _saveEventCallback = null;
    _currentViewId = null;
    _isSidebarExpanded = true;
    _settingsPopoverController = PopoverController();
    _addPopoverController = PopoverController();
    _selectedNote = null;
    _calendarContentKey = GlobalKey<_CalendarContentState>();
    
    // 初始化时尝试创建或获取日历视图
    _initializeCalendarView();
  }

  // 初始化日历视图
  Future<void> _initializeCalendarView() async {
    try {
      // 使用与ScheduleModel相同的固定ViewId
      final String fixedViewId =
          fixedUuid(12345, UuidType.privateSpace); // 使用与ScheduleModel相同的固定ID
      
      // 先检查视图是否已存在
      final result = await ViewBackendService.getView(fixedViewId);
      
      await result.fold(
        (view) async {
          // 视图已存在，直接使用
          setState(() {
            _currentViewId = view.id;
          });
        },
        (error) async {
          // 视图不存在，创建新视图
          
          final createResult = await ViewBackendService.createOrphanView(
            viewId: fixedViewId,
            name: '日历视图',
            layoutType: ViewLayoutPB.Calendar,
          );
          
          createResult.fold(
            (view) {
              setState(() {
                _currentViewId = view.id;
              });
            },
            (createError) {
              // 如果创建失败，使用固定ID作为后备
              setState(() {
                _currentViewId = fixedViewId;
              });
            },
          );
        },
      );
      
      // 初始化完成后，等待一下让数据库初始化完成，然后刷新数据
      Future.delayed(Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {}); // 触发重建以加载真实数据
        }
      });
    } catch (e) {
      // 使用固定ID作为后备
      setState(() {
        _currentViewId = fixedUuid(12345, UuidType.privateSpace);
      });
    }
  }

  // 等待系统初始化完成
  Future<void> _waitForSystemInitialization() async {
    int maxRetries = 10;
    int retryCount = 0;

    while (retryCount < maxRetries) {
      try {
        // 尝试获取所有视图来检查系统是否已初始化
        final result = await ViewBackendService.getAllViews();

        await result.fold(
          (views) async {
            // 系统已初始化，可以继续
            return;
          },
          (error) async {
            // 如果系统未初始化，等待一段时间后重试
            if (error.msg.contains('Folder not initialized') ||
                error.msg.contains('not initialized')) {
              await Future.delayed(Duration(milliseconds: 500));
              retryCount++;
              if (retryCount < maxRetries) {
                await _waitForSystemInitialization();
              } else {
                throw Exception('系统初始化超时，请稍后重试');
              }
            } else {
              throw Exception('系统初始化失败: ${error.msg}');
            }
          },
        );
        break; // 成功则跳出循环
      } catch (e) {
        if (retryCount >= maxRetries - 1) {
          throw Exception('系统初始化失败: $e');
        }
        await Future.delayed(Duration(milliseconds: 500));
        retryCount++;
      }
    }
  }

  void _showCreateDocumentDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        String documentTitle = '';
        bool isCreating = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
        return AlertDialog(
          title: Text('新建日记页'),
          content: TextField(
            onChanged: (value) {
              documentTitle = value;
            },
            decoration: InputDecoration(
              hintText: '输入日记标题',
              border: OutlineInputBorder(),
            ),
                enabled: !isCreating,
          ),
          actions: [
            TextButton(
                  onPressed: isCreating
                      ? null
                      : () {
                Navigator.of(context).pop();
              },
              child: Text('取消'),
            ),
            TextButton(
                  onPressed: isCreating
                      ? null
                      : () async {
                          if (documentTitle.trim().isNotEmpty) {
                            setDialogState(() {
                              isCreating = true;
                            });

                            try {
                              // 验证标题长度
                              if (documentTitle.length > 256) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('日记标题过长，请控制在256个字符以内'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                setDialogState(() {
                                  isCreating = false;
                                });
                                return;
                              }

                              // 等待系统初始化完成
                              await _waitForSystemInitialization();

                              // 获取当前用户和工作空间信息
                              final userResult = await UserBackendService
                                  .getCurrentUserProfile();
                              final workspaceResult =
                                  await FolderEventGetCurrentWorkspaceSetting()
                                      .send();

                              final userProfile = userResult.fold(
                                  (user) => user, (error) => null);
                              final workspaceId = workspaceResult.fold(
                                (setting) => setting.workspaceId,
                                (error) => null,
                              );

                              if (userProfile == null ||
                                  workspaceId == null ||
                                  workspaceId.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('无法获取当前用户或工作空间信息'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                setDialogState(() {
                                  isCreating = false;
                                });
                                return;
                              }

                              // 使用WorkspaceService创建文档视图
                              final workspaceService = WorkspaceService(
                                workspaceId: workspaceId,
                                userId: userProfile.id,
                              );

                              // 创建Document类型的视图
                              final result = await workspaceService.createView(
                                name: documentTitle.trim(),
                                viewSection: ViewSectionPB.Public, // 创建在公共区域
                                layout: ViewLayoutPB.Document, // 使用Document类型
                                setAsCurrent: true,
                    );
                    
                    result.fold(
                      (view) {
                                  // 重置创建状态
                                  setDialogState(() {
                                    isCreating = false;
                                  });

                                  // 显示成功提示
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('日记创建成功: ${view.name}'),
                                      backgroundColor: Colors.green,
                                      duration: Duration(seconds: 2),
                                    ),
                                  );

                                  // 关闭对话框
                                  Navigator.of(context).pop();

                                  // 不自动打开新文档，避免TabBloc问题
                                  // 用户可以通过点击日历中的日记来打开

                                  // 刷新日历内容以显示新创建的日记
                                  if (mounted) {
                                    // 延迟刷新，确保数据库操作完成
                                    Future.delayed(Duration(milliseconds: 1000),
                                        () {
                                      if (mounted) {
                                        _calendarContentKey.currentState
                                            ?.refreshData();
                                      }
                                    });
                                  }
                      },
                      (error) {
                                  setDialogState(() {
                                    isCreating = false;
                                  });

                                  // 处理错误，提供更详细的错误信息
                                  String errorMsg = '创建日记失败';
                                  String debugInfo = '';

                                  if (error.msg.contains('InvalidParams')) {
                                    errorMsg = '参数无效，请检查标题格式';
                                    debugInfo =
                                        '错误代码: ${error.code}, 消息: ${error.msg}';
                                  } else if (error.msg
                                      .contains('ViewIdIsInvalid')) {
                                    errorMsg = '视图ID无效';
                                    debugInfo = '错误: ${error.msg}';
                                  } else if (error.msg
                                      .contains('ViewNameTooLong')) {
                                    errorMsg = '日记标题过长';
                                    debugInfo = '标题长度: ${documentTitle.length}';
                                  } else if (error.msg
                                      .contains('Folder not initialized')) {
                                    errorMsg = '系统未完全初始化，请稍后重试';
                                    debugInfo = '请等待系统完全启动后再创建日记';
                                  } else {
                                    errorMsg = '创建日记失败: ${error.msg}';
                                    debugInfo = '错误代码: ${error.code}';
                                  }

                                  // 打印调试信息到控制台
                                  print('日记创建失败: $errorMsg');
                                  print('调试信息: $debugInfo');
                                  print(
                                      '使用的参数: name=${documentTitle.trim()}, layoutType=Document');

                        ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(errorMsg),
                                      backgroundColor: Colors.red,
                                      duration: Duration(seconds: 6),
                                      action: SnackBarAction(
                                        label: '详情',
                                        onPressed: () {
                                          showDialog(
                                            context: context,
                                            builder: (context) => AlertDialog(
                                              title: Text('错误详情'),
                                              content: Text(
                                                  '$errorMsg\n\n$debugInfo'),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.of(context)
                                                          .pop(),
                                                  child: Text('确定'),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                        );
                      },
                    );
                  } catch (e) {
                              setDialogState(() {
                                isCreating = false;
                              });
                    ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('创建日记失败: $e'),
                                  backgroundColor: Colors.red,
                                  duration: Duration(seconds: 4),
                                ),
                              );
                            }
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('请输入日记标题'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }
              },
              child: Text('创建'),
            ),
          ],
            );
          },
        );
      },
    );
  }

  void _showCreateScheduleDialog() {
    setState(() {
      _showNewEventPage = true;
      _selectedNote = null; // 清除当前选中的笔记
      _showEditEventPage = false; // 确保编辑日程页面关闭
      _editingSchedule = null; // 清除编辑中的日程
    });
  }

  void _hideNewEventPage() {
    setState(() {
      _showNewEventPage = false;
    });
  }

  // 处理点击日程
  void _onScheduleTap(ScheduleItem schedule) {
    setState(() {
      _showEditEventPage = true;
      _editingSchedule = schedule;
      _showNewEventPage = false; // 确保新建页面关闭
      _selectedNote = null; // 清除选中的笔记
    });
  }

  // 处理点击笔记
  void _onNoteTap(ViewPB note) {
    setState(() {
      // 如果点击的是当前选中的笔记，则取消选中
      if (_selectedNote?.id == note.id) {
        _selectedNote = null;
      } else {
        // 否则选中新笔记
      _selectedNote = note;
      }
      _showNewEventPage = false;
      _showEditEventPage = false;
    });
  }

  void _hideEditEventPage() {
    setState(() {
      _showEditEventPage = false;
      _editingSchedule = null;
    });
  }

  void _onEventCreated(Map<String, dynamic> eventData) {
    // 日程已通过 ScheduleModel 保存到数据库
    // 这里只需要刷新日历显示和显示成功提示
    
    final description = eventData['description'] as String;
    final isAllDay = eventData['isAllDay'] as bool;
    final startTime = eventData['startTime'] as TimeOfDay;
    final endTime = eventData['endTime'] as TimeOfDay;
    final eventId = eventData['id'] as String?;
    
    print('📅 日程创建回调被调用:');
    print('  - 描述: $description');
    print('  - ID: $eventId');
    print('  - 全天: $isAllDay');
    print('  - 开始时间: $startTime');
    print('  - 结束时间: $endTime');
    
    // 检查是否有有效的ID
    if (eventId == null || eventId.isEmpty) {
      print('❌ 错误: 日程ID为空，保存可能失败');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ 日程创建失败：未返回有效ID'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    
    // 刷新日历内容以显示新创建的日程
    print('🔄 刷新日历内容...');
    _calendarContentKey.currentState?.refreshData();
    
    // 刷新日程列表以显示新创建的日程
    // 通过 ScheduleModel 的全局实例来刷新
    // _scheduleSidebarKey.currentState?.refreshData();
    
    // 显示成功提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ 日程创建成功: $description'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
    
    // 隐藏新建日程界面
    _hideNewEventPage();
  }

  void _onEventUpdated(Map<String, dynamic> eventData) {
    final description = eventData['description'] as String;
    
    // 刷新日历内容以显示更新的日程
    _calendarContentKey.currentState?.refreshData();
    
    // 刷新日程列表以显示更新的日程
    // 通过 ScheduleModel 的全局实例来刷新
    // _scheduleSidebarKey.currentState?.refreshData();
    
    // 显示成功提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('日程更新成功: $description'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
    
    // 隐藏编辑日程界面
    _hideEditEventPage();
  }

  void _onEventDeleted(String scheduleId) {
    // 刷新日历内容以移除已删除的日程
    _calendarContentKey.currentState?.refreshData();
    
    // 刷新日程列表以移除已删除的日程
    // 通过 ScheduleModel 的全局实例来刷新
    // _scheduleSidebarKey.currentState?.refreshData();
    
    // 显示成功提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('日程已删除'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
    
    // 隐藏编辑日程界面
    _hideEditEventPage();
  }

  Widget _buildAddMenu() {
    return Container(
      width: 140,
      padding: EdgeInsets.all(4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () {
              _addPopoverController.close();
              _showCreateDocumentDialog();
            },
            child: Container(
              height: 38,
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Icon(Icons.book, size: 18),
                  SizedBox(width: 8),
                  Text('新建日记页', style: TextStyle(fontSize: 14)),
                ],
              ),
            ),
          ),
          InkWell(
            onTap: () {
              _addPopoverController.close();
              _showCreateScheduleDialog();
            },
            child: Container(
              height: 38,
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Icon(Icons.event, size: 18),
                  SizedBox(width: 8),
                  Text('新建日程', style: TextStyle(fontSize: 14)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsMenu() {
    return Container(
      width: 350,
      padding: EdgeInsets.all(4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              '日历显示设置',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          // 订阅系统日历
          InkWell(
            onTap: () {
              _settingsPopoverController.close();
              // TODO: 切换订阅系统日历
            },
            child: Container(
              height: 42,
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(Icons.calendar_month_outlined, size: 18),
                  SizedBox(width: 10),
                  Text('订阅系统日历', style: TextStyle(fontSize: 14)),
                  Spacer(),
                  Container(
                    width: 36,
                    height: 20,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        width: 18,
                        height: 18,
                        margin: EdgeInsets.only(right: 1),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 日记模式
          InkWell(
            onTap: () {
              _settingsPopoverController.close();
              // TODO: 切换日记模式
            },
            child: Container(
              height: 42,
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(Icons.edit_note, size: 18),
                  SizedBox(width: 10),
                  Text('日记模式', style: TextStyle(fontSize: 14)),
                  Spacer(),
                  Text(
                    '默认',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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

  @override
  Widget build(BuildContext context) {
    return Row(
                  children: [
            // 左侧日历导航区
            AnimatedContainer(
              duration: Duration(milliseconds: 300),
              width: _isSidebarExpanded ? 300 : 60,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              clipBehavior: Clip.hardEdge,
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: 0,
                maxWidth: _isSidebarExpanded ? 300 : 60,
                child: Column(
                children: [
                  // 顶部工具栏，包含收起/展开按钮和其他操作按钮
                  Container(
                    height: 50,
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Theme.of(context).dividerColor,
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: ClipRect(
                      child: _isSidebarExpanded 
                        ? Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(left: 8),
                                  child: Text(
                                    '日历',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              // 添加按钮
                              SizedBox(
                                width: 32,
                                height: 32,
                                child: AppFlowyPopover(
                                  controller: _addPopoverController,
                                  direction: PopoverDirection
                                      .bottomWithCenterAligned,
                                  child: IconButton(
                                    icon: Icon(Icons.add, size: 18),
                                    onPressed: () =>
                                        _addPopoverController.show(),
                                    tooltip: '添加新内容',
                                    padding: EdgeInsets.zero,
                                    constraints: BoxConstraints.tightFor(
                                        width: 32, height: 32),
                                  ),
                                  popupBuilder: (context) => _buildAddMenu(),
                                ),
                              ),
                              SizedBox(width: 4),
                              // 更多选项按钮
                              SizedBox(
                                width: 32,
                                height: 32,
                                child: AppFlowyPopover(
                                  controller: _settingsPopoverController,
                                  direction: PopoverDirection
                                      .bottomWithCenterAligned,
                                  child: IconButton(
                                    icon: Icon(Icons.more_horiz, size: 18),
                                    onPressed: () =>
                                        _settingsPopoverController.show(),
                                    tooltip: '更多选项',
                                    padding: EdgeInsets.zero,
                                    constraints: BoxConstraints.tightFor(
                                        width: 32, height: 32),
                                  ),
                                  popupBuilder: (context) =>
                                      _buildSettingsMenu(),
                                ),
                              ),
                              SizedBox(width: 4),
                              // 收起/展开按钮 (使用双箭头图标)
                              SizedBox(
                                width: 32,
                                height: 32,
                                child: IconButton(
                                  icon: Icon(Icons.keyboard_double_arrow_left,
                                      size: 18),
                                  onPressed: () {
                                    setState(() {
                                      _isSidebarExpanded =
                                          !_isSidebarExpanded;
                                    });
                                  },
                                  tooltip: '收起侧边栏',
                                  padding: EdgeInsets.zero,
                                  constraints: BoxConstraints.tightFor(
                                      width: 32, height: 32),
                                ),
                              ),
                              SizedBox(width: 4),
                            ],
                          )
                        : Center(
                            child: IconButton(
                              icon: Icon(Icons.keyboard_double_arrow_right,
                                  size: 22),
                              onPressed: () {
                                setState(() {
                                  _isSidebarExpanded = !_isSidebarExpanded;
                                });
                              },
                              tooltip: '展开侧边栏',
                            ),
                          ),
                    ),
                  ),
                  // 右侧工具栏 - 已移除三个按钮
                  // 侧边栏内容
                  Expanded(
                  child: _isSidebarExpanded
                      ? _buildExpandedSidebar()
                      : _buildCollapsedSidebar(),
                  ),
                ],
                ),
              ),
            ),
        // 右侧详情区 - 分为日历视图和编辑区域
            Expanded(
          child: _selectedNote != null || _showNewEventPage || _showEditEventPage ? Container(
                width: double.infinity,
                height: double.infinity,
                margin: EdgeInsets.only(left: 1,right: 1,bottom: 1),
                color:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                child: _showNewEventPage 
                  ? _buildNewEventView()
                  : _showEditEventPage && _editingSchedule != null
                    ? _buildEditEventView()
                    : _selectedNote != null
                            ? _buildNoteEditArea()
                            : Container(),
              ) :
              _buildDefaultView(),
            ),
      ],
          );
    }

  Widget _buildExpandedSidebar() {
    return Column(
      children: [
        // 日历组件 - 使用紧凑的固定高度
        Container(
          height: 280, // 紧凑的固定高度，减少留白
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ClipRect(
            child: DatePicker(
              isRange: false,
              focusedDay: _focusedDay,
              selectedDay: _selectedDay,
              onDaySelected: (selected, focused) {
                setState(() {
                  _selectedDay = selected;
                  _focusedDay = focused;
                  // 切换日期时清空右侧区域
                  _selectedNote = null;
                  _showNewEventPage = false;
                  _showEditEventPage = false;
                  _editingSchedule = null;
                });
              },
              onPageChanged: (focusedDay) {
                setState(() {
                  _focusedDay = focusedDay;
                });
              },
            ),
          ),
        ),
        // 分隔线
        Container(
          height: 1,
          margin: EdgeInsets.symmetric(horizontal: 16),
          color: Theme.of(context).dividerColor,
        ),
        SizedBox(height: 8),
        // 统一的日记和日程展示组件 - 使用Expanded让其占据剩余空间
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16), // 确保内容与侧边栏边缘有距离
            child: CalendarContent(
              key: _calendarContentKey,
              // 添加key以便调用刷新方法
              selectedDate: _selectedDay ?? _focusedDay,
              viewId: _currentViewId,
              // 传递视图ID
              onScheduleTap: _onScheduleTap,
              // 传递点击回调
              onNoteTap: _onNoteTap, // 传递笔记点击回调
              selectedNoteId: _selectedNote?.id, // 传递当前选中的笔记ID
            ),
          ),
        ),
      ],
    );
  }

    Widget _buildCollapsedSidebar() {
    return const SizedBox.shrink();
  }

  Widget _buildDefaultView() {
    return Container();
  }

  Widget _buildNewEventView() {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          // 新建日程顶部工具栏
          Container(
            height: 56,
            padding: EdgeInsets.symmetric(horizontal: 16),
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
                Expanded(
                  child: Text(
                    '新建日程',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // 取消按钮
                TextButton(
                  onPressed: _hideNewEventPage,
                  child: Text(
                    '取消',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                // 保存按钮
                ElevatedButton(
                  onPressed: () {
                    // 调用保存回调函数
                    if (_saveEventCallback != null && _saveEventCallback!()) {
                      _hideNewEventPage();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  child: Text(
                    '保存',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
          // 新建日程内容
          Expanded(
            child: NewEventPage(
              selectedDate: _selectedDay ?? _focusedDay,
              onEventCreated: _onEventCreated,
              onCancel: _hideNewEventPage,
              onSaveRequested: (saveCallback) {
                _saveEventCallback = saveCallback;
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditEventView() {
    if (_editingSchedule == null) return _buildDefaultView();
    
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          // 编辑日程顶部工具栏
          Container(
            height: 56,
            padding: EdgeInsets.symmetric(horizontal: 16),
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
                Expanded(
                  child: Text(
                    '编辑日程',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // 取消按钮
                TextButton(
                  onPressed: _hideEditEventPage,
                  child: Text(
                    '取消',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                // 保存按钮
                ElevatedButton(
                  onPressed: () {
                    // 调用保存回调函数
                    if (_saveEventCallback != null && _saveEventCallback!()) {
                      _hideEditEventPage();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  child: Text(
                    '保存',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
          // 编辑日程内容
          Expanded(
            child: EditEventPage(
              schedule: _editingSchedule!,
              onEventUpdated: _onEventUpdated,
              onEventDeleted: _onEventDeleted,
              onCancel: _hideEditEventPage,
              onSaveRequested: (saveCallback) {
                _saveEventCallback = saveCallback;
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoteEditArea() {
    if (_selectedNote == null) {
      return Container();
    }

    return Column(
      children: [
        // 编辑区域标题栏
        Container(
          height: 50,
          padding: EdgeInsets.symmetric(horizontal: 16),
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
              Expanded(
                child: Text(
                  '编辑日记: ${_selectedNote!.name}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, size: 18),
                onPressed: () {
                  setState(() {
                    _selectedNote = null;
                  });
                },
                tooltip: '关闭编辑',
                padding: EdgeInsets.zero,
                constraints: BoxConstraints.tightFor(width: 32, height: 32),
              ),
            ],
          ),
        ),
        // 编辑内容区域 - 使用文档编辑页面
        Expanded(
          child: MultiBlocProvider(
            key: ValueKey('bloc_provider_${_selectedNote!.id}'), // 添加key强制重建
            providers: [
              BlocProvider<PageAccessLevelBloc>(
                create: (context) => PageAccessLevelBloc(view: _selectedNote!)
                  ..add(const PageAccessLevelEvent.initial()),
              ),
              BlocProvider<ViewInfoBloc>(
                create: (context) => ViewInfoBloc(view: _selectedNote!)
                  ..add(const ViewInfoEvent.started()),
              ),
            ],
            child: DocumentPage(
              key: ValueKey(_selectedNote!.id), // 添加key强制重建
              view: _selectedNote!,
              onDeleted: () {
                // 当文档被删除时，关闭编辑区域
                setState(() {
                  _selectedNote = null;
                });
              },
              tabs: [], // 空的tabs列表
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNoteContentView() {
    if (_selectedNote == null) {
      return _buildDefaultView();
    }

    // 直接显示笔记内容，类似回收站的做法
    return CalendarDocumentView(view: _selectedNote!);
  }
}

// 统一的日记和日程展示组件
class CalendarContent extends StatefulWidget {
  final DateTime selectedDate;
  final String? viewId;
  final Function(ScheduleItem)? onScheduleTap; // 点击日程的回调
  final Function(ViewPB)? onNoteTap; // 点击笔记的回调
  final String? selectedNoteId; // 当前选中的笔记ID

  const CalendarContent({
    Key? key,
    required this.selectedDate,
    this.viewId,
    this.onScheduleTap,
    this.onNoteTap,
    this.selectedNoteId,
  }) : super(key: key);

  @override
  State<CalendarContent> createState() => _CalendarContentState();
}

class _CalendarContentState extends State<CalendarContent> {
  List<ViewPB> _realNotes = [];
  bool _isLoading = false;
  ViewListener? _viewListener;

  // 公共方法：手动刷新数据
  void refreshData() {
    _loadNotesForDate();
  }

  @override
  void initState() {
    super.initState();
    _loadNotesForDate();
    _setupViewListener();
  }

  // 设置视图监听器，监听视图变化
  void _setupViewListener() {
    // 监听工作空间级别的视图变化
    _viewListener = ViewListener(viewId: 'workspace');
    _viewListener?.start(
      onViewUpdated: (view) {
        // 当视图更新时，刷新日历数据
        if (mounted) {
          _loadNotesForDate();
        }
      },
      onViewChildViewsUpdated: (childViews) {
        // 当子视图更新时，刷新日历数据
        if (mounted) {
          _loadNotesForDate();
        }
      },
      onViewDeleted: (view) {
        // 当视图删除时，刷新日历数据
        if (mounted) {
          _loadNotesForDate();
        }
      },
      onViewRestored: (view) {
        // 当视图恢复时，刷新日历数据
        if (mounted) {
          _loadNotesForDate();
        }
      },
    );
  }

  @override
  void didUpdateWidget(CalendarContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate != widget.selectedDate) {
      _loadNotesForDate();
    }
    // 如果视图ID发生变化，也重新加载数据
    if (oldWidget.viewId != widget.viewId) {
      _loadNotesForDate();
    }
  }

  @override
  void dispose() {
    _viewListener?.stop();
    super.dispose();
  }

  // 判断是否为系统视图
  bool _isSystemView(String viewName) {
    // 系统视图名称列表
    final systemViewNames = [
      'Workspace',
      'workspace',
      'Workspace Settings',
      'Getting Started',
      'Welcome',
      'Home',
      'Inbox',
      'Favorites',
      'Trash',
      'Settings',
      'Preferences',
      'Help',
      'About',
    ];

    return systemViewNames.contains(viewName) ||
        viewName.toLowerCase().contains('workspace') ||
        viewName.toLowerCase().contains('system') ||
        viewName.toLowerCase().contains('setting');
  }

  Future<void> _loadNotesForDate() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 获取所有视图
      final allViewsResult = await ViewBackendService.getAllViews();
      
      await allViewsResult.fold(
        (allViews) async {
          // 过滤出文档类型的视图（笔记），包括"我的空间"中的日记
          // 显示所有Document类型的视图，包括孤儿视图和我的空间中的文档
          final documentViews = allViews.items
              .where((view) => 
                view.layout == ViewLayoutPB.Document && 
                  // 显示所有文档，包括有父视图的（我的空间）和孤儿视图（日历创建）
                  view.name.isNotEmpty && // 只过滤掉名称为空的文档
                  // 排除系统视图，如"Workspace"等
                  !_isSystemView(view.name)) // 排除系统视图
              .toList();

          // 根据选中日期过滤笔记
          final selectedDateStart = DateTime(
            widget.selectedDate.year,
            widget.selectedDate.month,
            widget.selectedDate.day,
          );
          final selectedDateEnd = selectedDateStart.add(Duration(days: 1));

          // 过滤当天创建的笔记
          final notesForDate = documentViews.where((view) {
            final createTime = DateTime.fromMillisecondsSinceEpoch(
              view.createTime.toInt() * 1000,
            );
            return createTime.isAfter(selectedDateStart) && 
                   createTime.isBefore(selectedDateEnd);
          }).toList();

          setState(() {
            _realNotes = notesForDate;
            _isLoading = false;
          });
        },
        (error) {
          setState(() {
            _realNotes = [];
            _isLoading = false;
          });
        },
      );
    } catch (e) {
      setState(() {
        _realNotes = [];
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 动态日期标题 - 根据选中的日期显示
          Text(
            '${widget.selectedDate.year}年${widget.selectedDate.month}月${widget.selectedDate.day}日',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          
          // 显示加载状态
          if (_isLoading) ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              ),
            ),
          ]
          // 真实的笔记内容
          else if (_realNotes.isNotEmpty) ...[
            ...(_realNotes.map((note) => _buildNoteItem(note))),
            const SizedBox(height: 16),
          ]
          // 如果当天没有笔记，显示提示
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                '当天暂无笔记',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.6),
                ),
              ),
            ),
          ],
          
          // 日程集成部分
          if (widget.viewId != null) ...[
            ScheduleSidebarContent(
              databaseViewId: widget.viewId,
              onScheduleTap: widget.onScheduleTap,
            ),
          ],
          // 移除else部分，不显示"暂无日程数据"提示
        ],
      ),
    );
  }

  Widget _buildNoteItem(ViewPB note) {
    final isSelected = widget.selectedNoteId == note.id;
    
    return FlowyHover(
      style: HoverStyle(hoverColor: Theme.of(context).colorScheme.secondary),
      builder: (_, onHover) => GestureDetector(
        onTap: () {
          // 点击笔记时调用回调函数
          if (widget.onNoteTap != null) {
            widget.onNoteTap!(note);
          }
        },
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected 
                ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: isSelected 
                ? Border.all(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                    width: 1,
                  )
                : null,
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.description : Icons.description_outlined,
                size: 16,
                color: isSelected 
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  note.name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected 
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _formatCreateTime(note.createTime.toInt()),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isSelected 
                          ? Theme.of(context).colorScheme.primary.withOpacity(0.7)
                          : Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.5),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatCreateTime(int timestamp) {
    final createTime = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final createDate =
        DateTime(createTime.year, createTime.month, createTime.day);
    
    if (createDate == today) {
      return '${createTime.hour.toString().padLeft(2, '0')}:${createTime.minute.toString().padLeft(2, '0')}';
    } else {
      return '${createTime.month}/${createTime.day}';
    }
  }
}

class CalendarPluginConfig implements PluginConfig {
  @override
  bool get creatable => true;
}

// 日历文档视图组件 - 参考回收站的实现
class CalendarDocumentView extends StatefulWidget {
  const CalendarDocumentView({
    super.key,
    required this.view,
  });

  final ViewPB view;

  @override
  State<CalendarDocumentView> createState() => _CalendarDocumentViewState();
}

class _CalendarDocumentViewState extends State<CalendarDocumentView> {
  late DocumentBloc _documentBloc;
  late ViewBloc _viewBloc;
  int _retryCount = 0;
  static const int _maxRetries = 3;

  @override
  void initState() {
    super.initState();
    _initializeBlocs();
  }

  @override
  void didUpdateWidget(CalendarDocumentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当view改变时，重新初始化blocs
    if (oldWidget.view.id != widget.view.id) {
      _disposeBlocs();
      _initializeBlocs();
    }
  }

  void _initializeBlocs() {
    _documentBloc = DocumentBloc(documentId: widget.view.id);
    _viewBloc = ViewBloc(view: widget.view);

    // 延迟初始化，确保系统完全准备好
    _retryInitialization();
  }

  void _retryInitialization() {
    Future.delayed(Duration(milliseconds: 200 * (_retryCount + 1)), () {
      if (mounted) {
        _documentBloc.add(const DocumentEvent.initial());
        _viewBloc.add(const ViewEvent.initial());

        // 确保编辑器状态是可编辑的
        Future.delayed(Duration(milliseconds: 100), () {
          if (mounted && _documentBloc.state.editorState != null) {
            _documentBloc.state.editorState!.editable = true;
          }
        });
      }
    });
  }

  void _disposeBlocs() {
    _documentBloc.close();
    _viewBloc.close();
  }

  @override
  void dispose() {
    _disposeBlocs();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _documentBloc),
        BlocProvider.value(value: _viewBloc),
      ],
      child: BlocBuilder<DocumentBloc, DocumentState>(
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(
              child: CircularProgressIndicator.adaptive(),
            );
          }

          final editorState = state.editorState;
          final error = state.error;
          if (error != null || editorState == null) {
            return _buildErrorView(context, error);
          }

          // 确保编辑器状态是可编辑的
          editorState.editable = true;

          return _buildDocumentView(context, editorState);
        },
      ),
    );
  }

  Widget _buildErrorView(BuildContext context, FlowyError? error) {
    return Container(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const SizedBox(height: 24),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '无法加载文档内容',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '此文档可能已被删除或损坏',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.5),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .errorContainer
                            .withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .error
                              .withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        '错误信息: ${error.msg}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_retryCount < _maxRetries)
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _retryCount++;
                          });
                          _retryInitialization();
                        },
                        icon: Icon(Icons.refresh),
                        label: Text('重试 (${_retryCount + 1}/$_maxRetries)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          foregroundColor:
                              Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentView(BuildContext context, EditorState editorState) {
    // 检查文档是否为空或只有空内容
    final hasContent = editorState.document.root.children.any((node) {
      final text = node.delta?.toPlainText() ?? '';
      return text.trim().isNotEmpty;
    });
    
    // 强制设置编辑器为可编辑状态
    editorState.editable = true;

    // 确保编辑器能够接收焦点
    editorState.selection ??= Selection.collapsed(
      Position(path: [0], offset: 0),
    );
    
    return Column(
      children: [
        _buildHeader(context),
        const SizedBox(height: 16),
        Expanded(
          child: _buildAppFlowyEditor(context, editorState),
        ),
      ],
    );
  }

  Widget _buildAppFlowyEditor(BuildContext context, EditorState editorState) {
    final isRTL =
        context.read<AppearanceSettingsCubit>().state.layoutDirection ==
        LayoutDirection.rtlLayout;
    final textDirection = isRTL ? ui.TextDirection.rtl : ui.TextDirection.ltr;

    return Directionality(
      textDirection: textDirection,
      child: AppFlowyEditorPage(
        editorState: editorState,
        autoFocus: true,
        // 启用自动焦点
        useViewInfoBloc: false,
        styleCustomizer: EditorStyleCustomizer(
          context: context,
          width: MediaQuery.of(context).size.width,
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          editorState: editorState,
        ),
        placeholderText: (node) {
          // 为空的段落节点提供占位符文本
          if (node.type == ParagraphBlockKeys.type && 
              (node.delta?.toPlainText() ?? '').trim().isEmpty) {
            return '此文档暂无内容，点击编辑按钮开始添加内容';
          }
          return '';
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Text(
            widget.view.name.isEmpty ? '无标题笔记' : widget.view.name,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          // 创建时间
          Text(
            '创建时间：${_formatCreateTime(widget.view.createTime.toInt())}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  String _formatCreateTime(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return DateFormat('yyyy/MM/dd HH:mm').format(date);
  }
}

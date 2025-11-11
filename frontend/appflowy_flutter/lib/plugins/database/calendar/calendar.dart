import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/database/calendar/presentation/widgets/calendar_content_widget.dart';
import 'package:appflowy/shared/permission/permission_checker.dart';
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
import 'package:appflowy/workspace/application/workspace/workspace_service.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy/plugins/document/document_page.dart';
import 'package:appflowy/workspace/application/view_info/view_info_bloc.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../workspace/presentation/widgets/toggle/toggle.dart';
import 'presentation/widgets/schedule_sidebar_content.dart';
import 'package:flowy_infra/uuid.dart';
import '../../../features/page_access_level/logic/page_access_level_bloc.dart';
import 'presentation/new_event_page.dart';
import 'presentation/edit_event_page.dart';
import 'models/schedule_model.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_backend/protobuf/flowy-error/protobuf.dart';
import 'package:appflowy/plugins/document/presentation/editor_page.dart';
import 'package:appflowy/plugins/document/presentation/editor_style.dart';
import 'application/calendar_content_cubit.dart';

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
  String get menuName => "日历";

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
    return BlocProvider<CalendarContentCubit>(
      create: (_) => CalendarContentCubit(),
      child: CalendarMainPanel(),
    );
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
  late bool _showNewEventPage;
  late bool _showEditEventPage; // 显示编辑日程页面
  late ScheduleModel _scheduleModel; // 添加日程模型
  late ScheduleItem? _editingSchedule; // 正在编辑的日程
  late Function()? _saveEventCallback;
  late String? _currentViewId; // 添加当前视图ID
  late bool _isSidebarExpanded;
  late PopoverController _settingsPopoverController;
  late PopoverController _addPopoverController;
  late ViewPB? _selectedNote; // 添加选中的笔记
  // 通过Bloc触发子组件刷新
  bool _isSubscribeSystemCalendar = false;

  // 添加状态管理变量
  late bool _isLoadingContent;
  late Map<String, dynamic>? _cachedContent;
  late DateTime? _lastLoadedDate;

  @override
  void initState() {
    super.initState();
    _focusedDay = DateTime.now();
    _selectedDay = DateTime.now();
    _firstDay = DateTime.now().subtract(Duration(days: 365));
    _lastDay = DateTime.now().add(Duration(days: 365));
    _showNewEventPage = false;
    _showEditEventPage = false;
    _editingSchedule = null;
    _saveEventCallback = null;
    _currentViewId = null;
    _isSidebarExpanded = true;
    _settingsPopoverController = PopoverController();
    _addPopoverController = PopoverController();
    _selectedNote = null;
    // 初始化日程模型
    _scheduleModel = ScheduleModel();

    // 初始化新的状态变量
    _isLoadingContent = false;
    _cachedContent = null;
    _lastLoadedDate = null;

    // 初始化时尝试创建或获取日历视图
    _initializeCalendarView();

    // 调试：打印初始状态
    print('日历组件初始化，订阅状态: $_isSubscribeSystemCalendar');
  }

  // 月份切换：delta为-1上一月，1下一月
  void _changeMonth(int delta) {
    // 切换到目标月份的1号，防止跨月天数差异导致越界
    DateTime candidate = DateTime(_focusedDay.year, _focusedDay.month + delta, 1);
    // 边界限制在允许范围内
    final first = DateTime(_firstDay.year, _firstDay.month, 1);
    final last = DateTime(_lastDay.year, _lastDay.month, 1);
    if (candidate.isBefore(first)) {
      candidate = first;
    } else if (candidate.isAfter(last)) {
      candidate = last;
    }

    setState(() {
      _focusedDay = candidate;
      // 不改变已选日期，仅改变聚焦月份
    });
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
                                        setState(() {

                                        });
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
      _saveEventCallback = null; // 重置保存回调，避免使用上一次的引用
    });
  }

  void _hideNewEventPage() {
    setState(() {
      _showNewEventPage = false;
      _saveEventCallback = null; // 关闭时重置回调
    });
  }

  // 处理点击日程
  void _onScheduleTap(ScheduleItem schedule) {
    print('🖱️ [Calendar] _onScheduleTap 被调用: schedule.id=${schedule.id}, schedule.title=${schedule.title}');
    print('  - 当前 _editingSchedule: ${_editingSchedule?.id}');
    print('  - 当前 _showEditEventPage: $_showEditEventPage');
    
    setState(() {
      _showEditEventPage = true;
      _editingSchedule = schedule;
      _showNewEventPage = false; // 确保新建页面关闭
      _selectedNote = null; // 清除选中的笔记
    });
    
    print('  - 更新后 _editingSchedule: ${_editingSchedule?.id}');
    print('  - 更新后 _showEditEventPage: $_showEditEventPage');
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
      _saveEventCallback = null; // 关闭时重置回调
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
    context.read<CalendarContentCubit>().refresh();

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
    context.read<CalendarContentCubit>().refresh();

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
    context.read<CalendarContentCubit>().refresh();

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
    print('_buildSettingsMenu 被调用，当前订阅状态: $_isSubscribeSystemCalendar');

    return StatefulBuilder(
      builder: (context, setPopupState) => Container(
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
          Container(
              height: 42,
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(Icons.calendar_month_outlined, size: 18),
                  SizedBox(width: 10),
                  Text('订阅系统日历', style: TextStyle(fontSize: 14)),
                  Spacer(),
                Toggle(
                  value: _isSubscribeSystemCalendar,
                  onChanged: (value) {
                    // 更新弹层内视图
                    setPopupState(() {
                      _isSubscribeSystemCalendar = value;
                    });
                    // 同步更新父级（外层可能依赖该状态）
                    if (mounted) {
                      setState(() {});
                    }
                    // 执行业务逻辑（订阅/取消订阅 + 刷新）
                    _toggleSystemCalendarSubscription(value);
                  },
                  style: const ToggleStyle.mobile(),
                  activeBackgroundColor: Color(0xFFF89575),
                  padding: EdgeInsets.zero,
                ),
              ],
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
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ));
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
                _buildTopWidget(),
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
          child: _selectedNote != null ||
                  _showNewEventPage ||
                  _showEditEventPage
              ? Container(
                  width: double.infinity,
                  height: double.infinity,
                  margin: EdgeInsets.only(left: 1, right: 1, bottom: 1),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: _showNewEventPage
                      ? _buildNewEventView()
                      : _showEditEventPage && _editingSchedule != null
                          ? _buildEditEventView()
                          : _selectedNote != null
                              ? _buildNoteEditArea()
                              : Container(),
                )
              : _buildDefaultView(),
        ),
      ],
    );
  }

  Widget _buildExpandedSidebar() {
    return Column(
      children: [
        // 顶部月份标题与左右切换箭头
        Container(
          width: double.infinity,
          padding: EdgeInsets.only(left: 16, right: 8, top: 8, bottom: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_focusedDay.year}年${_focusedDay.month}月',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w400,
                    fontSize: 16
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: 28,
                height: 28,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints.tightFor(width: 28, height: 28),
                  icon: Icon(Icons.chevron_left, size: 18),
                  onPressed: () => _changeMonth(-1),
                  tooltip: '上一月',
                ),
              ),
              SizedBox(width: 4),
              SizedBox(
                width: 28,
                height: 28,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints.tightFor(width: 28, height: 28),
                  icon: Icon(Icons.chevron_right, size: 18),
                  onPressed: () => _changeMonth(1),
                  tooltip: '下一月',
                ),
              ),
            ],
          ),
        ),

        // 日历组件 - 使用紧凑的固定高度
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: ClipRect(
            child: DatePicker(
              isRange: false,
              focusedDay: _focusedDay,
              selectedDay: _selectedDay,
              onDaySelected: (selected, focused) {
                setState(() {
                  _selectedDay = selected;
                  _focusedDay = focused;
                  // 切换日期时清空右侧区域，让_buildDefaultView自动选择内容
                  _selectedNote = null;
                  _showNewEventPage = false;
                  _showEditEventPage = false;
                  _editingSchedule = null;
                  // 清除缓存，强制重新加载新日期的内容
                  _cachedContent = null;
                  _lastLoadedDate = null;
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
          margin: EdgeInsets.only(top: 12),
          color: Theme.of(context).dividerColor,
        ),
        SizedBox(height: 8),
        // 统一的日记和日程展示组件 - 使用Expanded让其占据剩余空间
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16), // 确保内容与侧边栏边缘有距离
              child: CalendarContent(
                selectedDate: _selectedDay ?? _focusedDay,
                viewId: _currentViewId,
                onScheduleTap: _onScheduleTap,
                onNoteTap: _onNoteTap,
                selectedNoteId: _selectedNote?.id,
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
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: _buildContentBasedOnDate(),
    );
  }

  Widget _buildContentBasedOnDate() {
    final selectedDate = _selectedDay ?? _focusedDay;

    // 检查是否需要重新加载数据
    if (_lastLoadedDate == null ||
        !_isSameDay(_lastLoadedDate!, selectedDate) ||
        _cachedContent == null) {
      _loadContentForDate(selectedDate);
    }

    if (_isLoadingContent) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    final data = _cachedContent ?? {};
    final notes = data['notes'] as List<ViewPB>? ?? [];
    final schedules = data['schedules'] as List<ScheduleItem>? ?? [];

    // 如果有笔记，默认显示第一条笔记
    if (notes.isNotEmpty) {
      return _buildNoteEditAreaForNote(notes.first);
    }

    // 如果有日程没有笔记，显示第一条日程
    if (schedules.isNotEmpty) {
      return _buildScheduleEditArea(schedules.first);
    }

    // 如果既没有笔记也没有日程，显示空状态
    return _buildEmptyState();
  }

  // 异步加载内容数据
  Future<void> _loadContentForDate(DateTime date) async {
    if (_isLoadingContent) return; // 防止重复加载

    setState(() {
      _isLoadingContent = true;
    });

    try {
      // 获取笔记数据
      final notes = await _getNotesForDate(date);

      // 获取日程数据
      final schedules = await _getSchedulesForDate(date);

      if (mounted) {
        setState(() {
          _cachedContent = {
            'notes': notes,
            'schedules': schedules,
          };
          _lastLoadedDate = date;
          _isLoadingContent = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cachedContent = {
            'notes': <ViewPB>[],
            'schedules': <ScheduleItem>[],
          };
          _lastLoadedDate = date;
          _isLoadingContent = false;
        });
      }
    }
  }

  // 比较两个日期是否为同一天
  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  // 切换系统日历订阅状态
  Future<void> _toggleSystemCalendarSubscription(bool value) async {
    print('开始执行系统日历订阅操作: $value');

    try {
      // 订阅时先做权限检查与平台支持判断
      if (value) {
        // 尝试订阅系统日历
        print('尝试订阅系统日历...');

        final hasPermission = await PermissionChecker.checkCalendarPermission(context);
        if (!hasPermission) {
          // 恢复状态并提示不支持/未授权
          if (mounted) {
            setState(() {
              _isSubscribeSystemCalendar = false;
            });
          }
          _showClientNotSupportedMessage();
          return;
        }

        await _subscribeToSystemCalendar();
      } else {
        // 取消订阅系统日历
        print('取消订阅系统日历...');
        await _unsubscribeFromSystemCalendar();
      }

      print('系统日历操作完成: $value');

      // 刷新相关数据
      await _refreshCalendarData();

      // 显示成功提示
      _showToggleSuccessMessage(value);

      print('系统日历订阅状态切换成功: $value');

    } catch (e) {
      print('切换系统日历订阅状态失败: $e');

      // 如果是权限插件错误，显示提示信息
      if (e.toString().contains('MissingPluginException')) {
        // 恢复状态并提示不支持
        if (mounted) {
          setState(() {
            _isSubscribeSystemCalendar = !value;
          });
        }
        _showClientNotSupportedMessage();
        return;
      }

      // 其他错误，回滚状态
      setState(() {
        _isSubscribeSystemCalendar = !value;
      });

      // 显示错误提示
      _showToggleErrorMessage();
    }
  }

  // 订阅系统日历
  Future<void> _subscribeToSystemCalendar() async {
    try {
      // TODO: 实现系统日历订阅逻辑
      // 这里可以调用系统日历API来获取事件
      print('订阅系统日历');

      // 模拟获取系统日历事件
      // 在实际实现中，这里应该调用系统日历API

      // 模拟延迟，确保操作完成
      await Future.delayed(Duration(milliseconds: 100));

    } catch (e) {
      print('订阅系统日历失败: $e');
      rethrow;
    }
  }

  // 取消订阅系统日历
  Future<void> _unsubscribeFromSystemCalendar() async {
    try {
      // TODO: 实现取消系统日历订阅逻辑
      print('取消订阅系统日历');

      // 模拟延迟，确保操作完成
      await Future.delayed(Duration(milliseconds: 100));

    } catch (e) {
      print('取消订阅系统日历失败: $e');
      // 抛出异常，让上层处理
      rethrow;
    }
  }

  // 刷新日历数据
  Future<void> _refreshCalendarData() async {
    // 清除缓存，强制重新加载数据
    _cachedContent = null;
    _lastLoadedDate = null;
    context.read<CalendarContentCubit>().refresh();
    // 重新加载当前日期的内容
    final selectedDate = _selectedDay ?? _focusedDay;
    await _loadContentForDate(selectedDate);

    // 触发UI更新
    if (mounted) {
      setState(() {});
    }
  }

  // 显示权限插件错误提示
  void _showPermissionPluginError() {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('功能暂不可用'),
        content: Text(
          '系统日历权限功能在当前平台暂不可用。\n\n'
          '请确保：\n'
          '1. 应用已正确配置权限插件\n'
          '2. 在支持的平台上运行（iOS/Android）\n'
          '3. 已重新构建应用',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showClientNotSupportedMessage() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('当前客户端不支持或未授予日历权限'),
        duration: const Duration(seconds: 2),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  // 显示Toggle成功提示
  void _showToggleSuccessMessage(bool isSubscribed) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isSubscribed ? '已订阅系统日历' : '已取消订阅系统日历',
        ),
        duration: Duration(seconds: 2),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  // 显示Toggle错误提示
  void _showToggleErrorMessage() {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('操作失败，请重试'),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<List<ViewPB>> _getNotesForDate(DateTime date) async {
    try {
      final allViewsResult = await ViewBackendService.getAllViews();

      return await allViewsResult.fold(
        (allViews) async {
          final documentViews = allViews.items
              .where((view) =>
                  view.layout == ViewLayoutPB.Document &&
                  view.name.isNotEmpty &&
                  !_isSystemView(view.name))
              .toList();

          final selectedDateStart = DateTime(date.year, date.month, date.day);
          final selectedDateEnd = selectedDateStart.add(Duration(days: 1));

          return documentViews.where((view) {
            final createTime = DateTime.fromMillisecondsSinceEpoch(
              view.createTime.toInt() * 1000,
            );
            return createTime.isAfter(selectedDateStart) &&
                createTime.isBefore(selectedDateEnd);
          }).toList();
        },
        (error) async => [],
      );
    } catch (e) {
      return [];
    }
  }

  Future<List<ScheduleItem>> _getSchedulesForDate(DateTime date) async {
    try {
      // 确保视图ID已设置（只在未设置时设置一次，避免重复触发刷新）
      if (_currentViewId != null && _scheduleModel.currentViewId != _currentViewId) {
        _scheduleModel.setViewId(_currentViewId!);
        // setViewId 内部会异步刷新，这里不等待，直接使用当前内存数据
      }

      // 使用 ScheduleModel.getSchedulesForDate 方法，该方法会自动展开重复日程
      // 数据库回调（onRowsUpdated/onRowsCreated/onRowsDeleted）会自动保持数据同步
      return _scheduleModel.getSchedulesForDate(date);
    } catch (e) {
      print('⚠️ [Calendar] _getSchedulesForDate 异常: $e');
      return [];
    }
  }

  bool _isSystemView(String viewName) {
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 使用现有的空页面SVG图标
          FlowySvg(
            FlowySvgs.m_empty_page_xl,
            size: const Size(120, 120),
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
          ),
          const SizedBox(height: 24),
          // 提示文字
          Text(
            '暂无日记与日程，赶紧创建吧~',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoteEditAreaForNote(ViewPB note) {
    return MultiBlocProvider(
      key: ValueKey('bloc_provider_${note.id}'),
      providers: [
        BlocProvider<PageAccessLevelBloc>(
          create: (context) => PageAccessLevelBloc(view: note)
            ..add(const PageAccessLevelEvent.initial()),
        ),
        BlocProvider<ViewInfoBloc>(
          create: (context) => ViewInfoBloc(view: note)
            ..add(const ViewInfoEvent.started()),
        ),
      ],
      child: DocumentPage(
        key: ValueKey(note.id),
        view: note,
        onDeleted: () {
          // 当文档被删除时，刷新默认视图
          setState(() {});
        },
        tabs: [],
      ),
    );
  }

  Widget _buildScheduleEditArea(ScheduleItem schedule) {
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
                  '编辑日程: ${schedule.description}',
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
                    _editingSchedule = null;
                  });
                },
                tooltip: '关闭编辑',
                padding: EdgeInsets.zero,
                constraints: BoxConstraints.tightFor(width: 32, height: 32),
              ),
            ],
          ),
        ),
        // 编辑内容区域
        Expanded(
          child: EditEventPage(
            key: ValueKey(schedule.id), // 使用 schedule.id 作为 key，确保切换日程时重建 widget
            schedule: schedule,
            scheduleModel: _scheduleModel,
            onEventUpdated: _onEventUpdated,
            onEventDeleted: _onEventDeleted,
            onCancel: () {
              setState(() {
                _editingSchedule = null;
              });
            },
            onSaveRequested: (saveCallback) {
              _saveEventCallback = saveCallback;
            },
          ),
        ),
      ],
    );
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
                    // 调用保存回调函数；是否关闭由保存结果回调决定
                    if (_saveEventCallback != null) {
                      _saveEventCallback!();
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
              scheduleModel: _scheduleModel,
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
    if (_editingSchedule == null) {
      print('⚠️ [Calendar] _buildEditEventView: _editingSchedule 为 null');
      return _buildDefaultView();
    }

    print('📝 [Calendar] _buildEditEventView: 构建编辑页面，schedule.id=${_editingSchedule!.id}, schedule.title=${_editingSchedule!.title}');
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
                    // 调用保存回调函数；是否关闭由更新结果回调决定
                    if (_saveEventCallback != null) {
                      _saveEventCallback!();
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
              key: ValueKey(_editingSchedule!.id), // 使用 schedule.id 作为 key，确保切换日程时重建 widget
              scheduleModel: _scheduleModel,
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

    return MultiBlocProvider(
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
    );
  }

  Widget _buildTopWidget() {
    return Container(
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
            // 收起/展开按钮 (使用双箭头图标)
            SizedBox(
              width: 32,
              height: 32,
              child: IconButton(
                icon: Icon(Icons.keyboard_double_arrow_left,
                    size: 18),
                onPressed: () {
                  setState(() {
                    _isSidebarExpanded = !_isSidebarExpanded;
                  });
                },
                tooltip: '收起侧边栏',
                padding: EdgeInsets.zero,
                constraints: BoxConstraints.tightFor(
                    width: 32, height: 32),
              ),
            ),
            // 添加按钮
            SizedBox(
              width: 32,
              height: 32,
              child: AppFlowyPopover(
                controller: _addPopoverController,
                direction:
                PopoverDirection.bottomWithCenterAligned,
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
            // 更多选项按钮
            SizedBox(
              width: 32,
              height: 32,
              child: AppFlowyPopover(
                controller: _settingsPopoverController,
                direction:
                PopoverDirection.bottomWithCenterAligned,
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
    );
  }

  @override
  void dispose() {
    super.dispose();
    // 确保释放资源
    _scheduleModel.dispose();

  }
}

class CalendarPluginConfig implements PluginConfig {
  @override
  bool get creatable => true;
}


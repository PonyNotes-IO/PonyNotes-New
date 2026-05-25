import 'package:any_date/any_date.dart';
import 'package:appflowy/plugins/database/widgets/cell/editable_cell_skeleton/date.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/date_entities.pbenum.dart';
import 'package:appflowy_popover/appflowy_popover.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/size.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../desktop_date_picker.dart';
import 'date_picker.dart';

class DateTimeTextField extends StatefulWidget {
  const DateTimeTextField({
    super.key,
    required this.dateTime,
    required this.includeTime,
    required this.dateFormat,
    this.timeFormat,
    this.onSubmitted,
    this.onChanged,
    this.popoverMutex,
    this.isTabPressed,
    this.refreshTextController,
    required this.showHint,
  }) : assert(includeTime && timeFormat != null || !includeTime);

  final DateTime? dateTime;
  final bool includeTime;
  final void Function(DateTime dateTime)? onSubmitted;
  final void Function(DateTime dateTime)? onChanged;
  final DateFormatPB dateFormat;
  final TimeFormatPB? timeFormat;
  final PopoverMutex? popoverMutex;
  final ValueNotifier<bool>? isTabPressed;
  final RefreshDateTimeTextFieldController? refreshTextController;
  final bool showHint;

  @override
  State<DateTimeTextField> createState() => _DateTimeTextFieldState();
}

class _DateTimeTextFieldState extends State<DateTimeTextField> {
  late final FocusNode focusNode;
  late final FocusNode dateFocusNode;
  late final FocusNode timeFocusNode;

  final dateTextController = TextEditingController();
  final timeTextController = TextEditingController();

  final statesController = WidgetStatesController();

  bool justSubmitted = false;

  DateFormat get dateFormat => DateFormat(widget.dateFormat.pattern);
  DateFormat get timeFormat => DateFormat(widget.timeFormat?.pattern);

  @override
  void initState() {
    super.initState();
    updateTextControllers();

    focusNode = FocusNode()..addListener(focusNodeListener);
    dateFocusNode = FocusNode(onKeyEvent: textFieldOnKeyEvent)
      ..addListener(dateFocusNodeListener);
    timeFocusNode = FocusNode(onKeyEvent: textFieldOnKeyEvent)
      ..addListener(timeFocusNodeListener);
    widget.isTabPressed?.addListener(isTabPressedListener);
    widget.refreshTextController?.addListener(updateTextControllers);
    widget.popoverMutex?.addPopoverListener(popoverListener);
  }

  @override
  void didUpdateWidget(covariant oldWidget) {
    if (oldWidget.dateTime != widget.dateTime ||
        oldWidget.dateFormat != widget.dateFormat ||
        oldWidget.timeFormat != widget.timeFormat) {
      statesController.update(WidgetState.error, false);
      updateTextControllers();
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    dateTextController.dispose();
    timeTextController.dispose();
    widget.popoverMutex?.removePopoverListener(popoverListener);
    widget.isTabPressed?.removeListener(isTabPressedListener);
    widget.refreshTextController?.removeListener(updateTextControllers);
    dateFocusNode
      ..removeListener(dateFocusNodeListener)
      ..dispose();
    timeFocusNode
      ..removeListener(timeFocusNodeListener)
      ..dispose();
    focusNode
      ..removeListener(focusNodeListener)
      ..dispose();
    statesController.dispose();
    super.dispose();
  }

  void focusNodeListener() {
    if (focusNode.hasFocus) {
      statesController.update(WidgetState.focused, true);
      widget.popoverMutex?.close();
    } else {
      statesController.update(WidgetState.focused, false);
    }
  }

  void isTabPressedListener() {
    if (!dateFocusNode.hasFocus && !timeFocusNode.hasFocus) {
      return;
    }
    final controller =
        dateFocusNode.hasFocus ? dateTextController : timeTextController;
    if (widget.isTabPressed != null && widget.isTabPressed!.value) {
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.characters.length,
      );
      widget.isTabPressed?.value = false;
    }
  }

  KeyEventResult textFieldOnKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent && event.logicalKey == LogicalKeyboardKey.tab) {
      widget.isTabPressed?.value = true;
    }
    return KeyEventResult.ignored;
  }

  void dateFocusNodeListener() {
    if (dateFocusNode.hasFocus) {
      return;
    }

    final expected = widget.dateTime == null
        ? ""
        : DateFormat(widget.dateFormat.pattern).format(widget.dateTime!);
    if (expected != dateTextController.text.trim()) {
      onDateTextFieldSubmitted();
    }
    justSubmitted = false;
  }

  void timeFocusNodeListener() {
    if (timeFocusNode.hasFocus || widget.timeFormat == null) {
      return;
    }

    final expected = widget.dateTime == null
        ? ""
        : DateFormat(widget.timeFormat!.pattern).format(widget.dateTime!);
    if (expected != timeTextController.text.trim()) {
      onTimeTextFieldSubmitted();
    }
    justSubmitted = false;
  }

  void popoverListener() {
    if (focusNode.hasFocus) {
      focusNode.unfocus();
    }
  }

  void updateTextControllers() {
    if (widget.dateTime == null) {
      dateTextController.clear();
      timeTextController.clear();
      return;
    }

    dateTextController.text = dateFormat.format(widget.dateTime!);
    timeTextController.text = timeFormat.format(widget.dateTime!);
  }

  void onDateTextFieldSubmitted() {
    DateTime? dateTime = parseDateTimeStr(dateTextController.text.trim());
    if (dateTime == null) {
      statesController.update(WidgetState.error, true);
      return;
    }
    statesController.update(WidgetState.error, false);
    if (widget.dateTime != null) {
      final timeComponent = Duration(
        hours: widget.dateTime!.hour,
        minutes: widget.dateTime!.minute,
        seconds: widget.dateTime!.second,
      );
      dateTime = DateTime(
        dateTime.year,
        dateTime.month,
        dateTime.day,
      ).add(timeComponent);
    }
    justSubmitted = true;
    widget.onSubmitted?.call(dateTime);
  }

  void onTimeTextFieldSubmitted() {
    // this happens in the middle of a date range selection
    if (widget.dateTime == null) {
      widget.refreshTextController?.refresh();
      statesController.update(WidgetState.error, true);
      return;
    }
    
    final timeStr = timeTextController.text.trim();
    final timeParts = timeStr.split(':');
    
    // 检查时间格式是否正确
    if (timeParts.length >= 2) {
      final hour = int.tryParse(timeParts[0]);
      final minute = int.tryParse(timeParts[1]);
      
      // 检查时和分是否在有效范围内
      if (hour == null || minute == null || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
        // 如果时间无效，还原到00:00
        timeTextController.text = "09:00";
        statesController.update(WidgetState.error, true);
        
        // 使用00:00作为时间
        final date = widget.dateTime!;
        final newDateTime = DateTime(
          date.year,
          date.month,
          date.day,
          9,
          0,
          date.second,
          date.millisecond,
          date.microsecond,
        );
        
        justSubmitted = true;
        widget.onSubmitted?.call(newDateTime);
        return;
      }
    }
    
    final adjustedTimeStr = "${dateTextController.text} ${timeTextController.text.trim()}";
    final dateTime = parseDateTimeStr(adjustedTimeStr);

    if (dateTime == null) {
      // 如果解析失败，还原到00:00
      timeTextController.text = "09:00";
      statesController.update(WidgetState.error, true);
      
      // 使用00:00作为时间
      final date = widget.dateTime!;
      final newDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        9,
        0,
        date.second,
        date.millisecond,
        date.microsecond,
      );
      
      justSubmitted = true;
      widget.onSubmitted?.call(newDateTime);
      return;
    }
    
    statesController.update(WidgetState.error, false);
    justSubmitted = true;
    widget.onSubmitted?.call(dateTime);
  }

  DateTime? parseDateTimeStr(String string) {
    final locale = context.locale.toLanguageTag();
    final parser = AnyDate.fromLocale(locale);
    final result = parser.tryParse(string);
    if (result == null ||
        result.isBefore(kFirstDay) ||
        result.isAfter(kLastDay)) {
      return null;
    }
    return result;
  }

  late final WidgetStateProperty<Color?> borderColor =
      WidgetStateProperty.resolveWith(
    (states) {
      if (states.contains(WidgetState.error)) {
        return Theme.of(context).colorScheme.errorContainer;
      }
      if (states.contains(WidgetState.focused)) {
        return Theme.of(context).colorScheme.primary;
      }
      return Theme.of(context).colorScheme.outline;
    },
  );

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final hintDate = DateTime(now.year, now.month, 1, 9);

    return Focus(
      focusNode: focusNode,
      skipTraversal: true,
      child: wrapWithGestures(
        child: ListenableBuilder(
          listenable: statesController,
          builder: (context, child) {
            final resolved = borderColor.resolve(statesController.value);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18.0),
              child: Container(
                constraints: const BoxConstraints.tightFor(height: 32),
                decoration: BoxDecoration(
                  border: Border.fromBorderSide(
                    BorderSide(
                      color: resolved ?? Colors.transparent,
                    ),
                  ),
                  borderRadius: Corners.s8Border,
                ),
                child: child,
              ),
            );
          },
          child: widget.includeTime
              ? Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('date_time_text_field_date'),
                        focusNode: dateFocusNode,
                        controller: dateTextController,
                        style: Theme.of(context).textTheme.bodyMedium,
                        decoration: getInputDecoration(
                          const EdgeInsetsDirectional.fromSTEB(12, 6, 6, 6),
                          dateFormat.format(hintDate),
                        ),
                        // 禁用日期输入，只能通过下方日历修改
                        readOnly: true,
                        onTap: () {
                          // 点击日期输入框时，不做任何操作，让用户通过下方日历选择
                        },
                      ),
                    ),
                    VerticalDivider(
                      indent: 4,
                      endIndent: 4,
                      width: 1,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('date_time_text_field_time'),
                        focusNode: timeFocusNode,
                        controller: timeTextController,
                        style: Theme.of(context).textTheme.bodyMedium,
                        maxLength: widget.timeFormat == TimeFormatPB.TwelveHour
                            ? 8 // 12:34 PM = 8 characters
                            : 5, // 12:34 = 5 characters
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp('[0-9:AaPpMm]'),
                          ),
                        ],
                        decoration: getInputDecoration(
                          const EdgeInsetsDirectional.fromSTEB(6, 6, 12, 6),
                          timeFormat.format(hintDate),
                        ),
                        onChanged: (value) {
                          // 实时解析用户输入并更新页面显示
                          if (widget.dateTime != null) {
                            // 直接使用 widget.dateTime 的日期部分，只修改时间部分
                            final date = widget.dateTime!;
                            final timeParts = value.trim().split(':');
                            
                            // 只有当分钟部分有至少两位数字时才更新，确保用户能够完整输入
                            if (timeParts.length >= 2 && timeParts[1].length >= 2) {
                              final hour = int.tryParse(timeParts[0]);
                              final minute = int.tryParse(timeParts[1]);
                              if (hour != null && minute != null && hour >= 0 && hour < 24 && minute >= 0 && minute < 60) {
                                final newDateTime = DateTime(
                                  date.year,
                                  date.month,
                                  date.day,
                                  hour,
                                  minute,
                                  date.second,
                                  date.millisecond,
                                  date.microsecond,
                                );
                                statesController.update(WidgetState.error, false);
                                widget.onChanged?.call(newDateTime);
                                return;
                              } else {
                                // 时间无效，显示错误状态
                                statesController.update(WidgetState.error, true);
                                return;
                              }
                            }
                            
                            // 如果时间格式不完整，不更新，让用户继续输入
                            if (timeParts.length < 2 || timeParts[1].length < 2) {
                              statesController.update(WidgetState.error, false);
                              return;
                            }
                            
                            // 如果解析失败，尝试使用完整的日期时间字符串
                            final adjustedTimeStr = "${dateTextController.text} ${value.trim()}";
                            final dateTime = parseDateTimeStr(adjustedTimeStr);
                            if (dateTime != null) {
                              statesController.update(WidgetState.error, false);
                              widget.onChanged?.call(dateTime);
                            } else {
                              statesController.update(WidgetState.error, true);
                            }
                          }
                        },
                        onSubmitted: (value) {
                          justSubmitted = true;
                          onTimeTextFieldSubmitted();
                        },
                      ),
                    ),
                  ],
                )
              : Center(
                  child: TextField(
                    key: const ValueKey('date_time_text_field_date'),
                    focusNode: dateFocusNode,
                    controller: dateTextController,
                    style: Theme.of(context).textTheme.bodyMedium,
                    decoration: getInputDecoration(
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      dateFormat.format(hintDate),
                    ),
                    // 禁用日期输入，只能通过下方日历修改
                    readOnly: true,
                    onTap: () {
                      // 点击日期输入框时，不做任何操作，让用户通过下方日历选择
                    },
                  ),
                ),
        ),
      ),
    );
  }

  Widget wrapWithGestures({required Widget child}) {
    return GestureDetector(
      onTapDown: (_) {
        statesController.update(WidgetState.pressed, true);
      },
      onTapCancel: () {
        statesController.update(WidgetState.pressed, false);
      },
      onTap: () {
        statesController.update(WidgetState.pressed, false);
        // 点击输入框容器时，将焦点设置到日期输入框
        dateFocusNode.requestFocus();
      },
      child: child,
    );
  }

  InputDecoration getInputDecoration(
    EdgeInsetsGeometry padding,
    String? hintText,
  ) {
    return InputDecoration(
      border: InputBorder.none,
      contentPadding: padding,
      isCollapsed: true,
      isDense: true,
      hintText: widget.showHint ? hintText : null,
      counterText: "",
      hintStyle: Theme.of(context)
          .textTheme
          .bodyMedium
          ?.copyWith(color: Theme.of(context).hintColor),
    );
  }
}

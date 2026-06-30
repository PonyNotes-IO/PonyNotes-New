import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/notifications/widgets/empty.dart';
import 'package:appflowy/shared/list_extension.dart';
import 'package:appflowy/user/application/reminder/reminder_bloc.dart';
import 'package:appflowy/user/application/reminder/reminder_extension.dart';
import 'package:appflowy/util/int64_extension.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/appflowy_backend.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:custom_refresh_indicator/custom_refresh_indicator.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'notification_item_v2.dart';
import 'notification_tab_bar.dart';

class NotificationTab extends StatefulWidget {
  const NotificationTab({
    super.key,
    this.tabType,
  });

  final NotificationTabType? tabType;

  @override
  State<NotificationTab> createState() => _NotificationTabState();
}

class _NotificationTabState extends State<NotificationTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return CustomMaterialIndicator(
      onRefresh: () => _onRefresh(context),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      indicatorBuilder: (context, controller) {
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            value: controller.state.isLoading ? null : controller.value.clamp(0.0, 1.0),
          ),
        );
      },
      child: BlocBuilder<ReminderBloc, ReminderState>(
        builder: (context, state) {
          final reminders = _filterReminders(state.reminders, state.archivedReminders);

          if (reminders.isEmpty) {
            return EmptyNotification(type: widget.tabType);
          }

          return _buildReminderList(reminders);
        },
      ),
    );
  }

  Widget _buildReminderList(List<ReminderPB> reminders) {
    final todayReminders = _filterByToday(reminders);
    final olderReminders = _filterByOlder(reminders);

    final items = <_ListItem>[];
    if (todayReminders.isNotEmpty) {
      items.add(_ListItem.header(LocaleKeys.notificationHub_today.tr()));
      items.addAll(todayReminders.map((r) => _ListItem.reminder(r)));
    }
    if (olderReminders.isNotEmpty) {
      items.add(_ListItem.header(LocaleKeys.notificationHub_older.tr()));
      items.addAll(olderReminders.map((r) => _ListItem.reminder(r)));
    }

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.zero,
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        if (item is _HeaderItem) {
          return _buildHeader(item.title);
        } else if (item is _ReminderItem) {
          return NotificationItemV2(
            key: ValueKey('${widget.tabType}_${item.reminder.id}'),
            tabType: widget.tabType,
            reminder: item.reminder,
          );
        }
        return null;
      },
    );
  }

  Widget _buildHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: FlowyText.regular(
        title,
        fontSize: 14,
        figmaLineHeight: 18,
      ),
    );
  }

  List<ReminderPB> _filterByToday(List<ReminderPB> reminders) {
    final dateTimeNow = DateTime.now();
    return reminders.where((reminder) {
      final scheduledAt = reminder.scheduledAt.toDateTime();
      return dateTimeNow.difference(scheduledAt).inDays < 1;
    }).toList();
  }

  List<ReminderPB> _filterByOlder(List<ReminderPB> reminders) {
    final dateTimeNow = DateTime.now();
    return reminders.where((reminder) {
      final scheduledAt = reminder.scheduledAt.toDateTime();
      return dateTimeNow.difference(scheduledAt).inDays >= 1;
    }).toList();
  }

  Future<void> _onRefresh(BuildContext context) async {
    context.read<ReminderBloc>().add(const ReminderEvent.refresh());
    await context.read<ReminderBloc>().stream.firstOrNull;
    if (context.mounted) {
      showToastNotification(
        message: LocaleKeys.settings_notifications_refreshSuccess.tr(),
      );
    }
  }

  List<ReminderPB> _filterReminders(
    List<ReminderPB> reminders,
    List<ReminderPB> archivedReminders,
  ) {
    if (widget.tabType == NotificationTabType.archived) {
      return archivedReminders.reversed.toList().unique((reminder) => reminder.id);
    }
    if (widget.tabType == null) {
      return reminders.reversed
          .where((reminder) => !reminder.isArchived)
          .toList()
          .unique((reminder) => reminder.id);
    }
    final targetType = widget.tabType!.value;
    return reminders.reversed
        .where((reminder) {
          if (reminder.isArchived) return false;
          final notificationType = reminder.notificationType;
          return notificationType == targetType;
        })
        .toList()
        .unique((reminder) => reminder.id);
  }
}

sealed class _ListItem {
  const _ListItem();

  factory _ListItem.header(String title) = _HeaderItem;
  factory _ListItem.reminder(ReminderPB reminder) = _ReminderItem;

  bool get isHeader => this is _HeaderItem;
  bool get isReminder => this is _ReminderItem;
}

class _HeaderItem extends _ListItem {
  const _HeaderItem(this.title);
  final String title;
}

class _ReminderItem extends _ListItem {
  const _ReminderItem(this.reminder);
  final ReminderPB reminder;
}
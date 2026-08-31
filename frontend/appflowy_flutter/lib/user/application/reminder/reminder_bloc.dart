import 'dart:async';
import 'dart:convert';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/plugins/inbox/application/inbox_service.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/mention/mention_block.dart';
import 'package:appflowy/shared/list_extension.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/reminder/notification_service.dart';
import 'package:appflowy/user/application/reminder/reminder_extension.dart';
import 'package:appflowy/user/application/reminder/reminder_listener.dart';
import 'package:appflowy/user/application/reminder/reminder_service.dart';
import 'package:appflowy/util/int64_extension.dart';
import 'package:appflowy/workspace/application/action_navigation/action_navigation_bloc.dart';
import 'package:appflowy/workspace/application/action_navigation/navigation_action.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:bloc/bloc.dart';
import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:protobuf/protobuf.dart';

part 'reminder_bloc.freezed.dart';

class ReminderBloc extends Bloc<ReminderEvent, ReminderState> {
  ReminderBloc() : super(ReminderState()) {
    Log.info('ReminderBloc created');

    _actionBloc = getIt<ActionNavigationBloc>();
    _reminderService = const ReminderService();
    timer = _periodicCheck();
    _listener = AppLifecycleListener(
      onResume: () {
        if (!isClosed) {
          add(const ReminderEvent.resetTimer());
        }
      },
    );

    // Listen for real-time reminder pushes from Rust (system notifications
    // delivered over WebSocket). The fixed key "user_reminder" matches what
    // Rust sends via send_notification("user_reminder", DidUpdateReminder).
    // Use refresh() instead of add() to avoid a duplicate backend write —
    // the reminder was already stored by Rust before the push was sent.
    _awarenessListener = UserAwarenessListener(workspaceId: 'user_reminder')
      ..start(
        onDidUpdateReminder: (reminder) {
          if (!_seenCloudPushIds.add(reminder.id)) return;
          Log.info(
            'ReminderBloc: received real-time reminder push: ${reminder.id}',
          );
          _cloudRefreshDebounce?.cancel();
          _cloudRefreshDebounce = Timer(
            const Duration(milliseconds: 300),
            () {
              if (!isClosed) add(const ReminderEvent.refresh());
            },
          );
        },
      );

    _dispatch();
  }

  late final ActionNavigationBloc _actionBloc;
  late final ReminderService _reminderService;
  Timer? timer;
  Timer? _cloudRefreshDebounce;
  late final AppLifecycleListener _listener;
  late final UserAwarenessListener _awarenessListener;
  final _deepEquality = DeepCollectionEquality();
  final Set<String> _seenCloudPushIds = {};
  bool _started = false;

  bool hasReminder(String reminderId) =>
      state.allReminders.where((e) => e.id == reminderId).firstOrNull != null;

  final List<ViewPB> _allViews = [];

  /// 【全局通知】账号级云端通知缓存（来自 /api/user/notifications，跨所有工作区）。
  /// 拉取失败（离线等）时沿用上一次的缓存，避免通知列表被清空。
  List<ReminderPB> _cloudReminders = [];

  /// 云端系统/协作通知的元数据 key（Rust 转发与服务端转换共用同一约定）
  static const _cloudNotificationTypeKey = 'cloud_notification_type';
  static const _cloudPayloadKey = 'payload';

  /// 是否为云端通知（区别于用户自设的日程提醒）。
  /// 兼容历史遗留：早期版本把云通知副本写入了各工作区的 reminder 存储，
  /// 这些副本带有 payload/cloud_notification_type 元数据，一并识别为云通知。
  static bool _isCloudNotification(ReminderPB reminder) =>
      (reminder.meta[_cloudNotificationTypeKey]?.isNotEmpty ?? false) ||
      reminder.meta.containsKey(_cloudPayloadKey);

  /// 把服务端账号级通知转换为通知面板使用的 ReminderPB。
  /// 字段映射与 Rust 侧此前的转换逻辑保持一致（meta 键、时间单位为秒）。
  ReminderPB _cloudNotificationToReminder(Map<String, dynamic> n) {
    final type = (n['notification_type'] as String?) ?? 'system';
    final payload = n['payload'] as Map<String, dynamic>? ?? {};
    final isArchived = (n['is_archived'] as bool?) ?? false;

    int createdAtSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final createdAtStr = n['created_at'] as String?;
    if (createdAtStr != null) {
      final parsed = DateTime.tryParse(createdAtStr);
      if (parsed != null) {
        createdAtSeconds = parsed.millisecondsSinceEpoch ~/ 1000;
      }
    }

    final meta = <String, String>{
      ReminderMetaKeys.notificationType:
          type == 'mention' ? 'mention' : 'system',
      _cloudNotificationTypeKey: type,
      _cloudPayloadKey: jsonEncode(payload),
      ReminderMetaKeys.createdAt: createdAtSeconds.toString(),
      if (isArchived) ReminderMetaKeys.isArchived: true.toString(),
    };

    return ReminderPB(
      id: (n['id'] as String?) ?? '',
      objectId: (n['workspace_id'] as String?) ?? '',
      scheduledAt: Int64(createdAtSeconds),
      isAck: true,
      isRead: (n['is_read'] as bool?) ?? false,
      title:
          (payload['title'] as String?) ?? InboxService.defaultTitleFor(type),
      message: (payload['message'] as String?) ?? '',
      meta: meta,
    );
  }

  /// 同步本地缓存中云端通知的已读/归档状态（服务端写入是异步的，
  /// 先行更新缓存保证下一次 emit 前状态一致）。
  void _updateCloudReminderCache(
    String reminderId, {
    bool? isRead,
    bool? isArchived,
  }) {
    final index = _cloudReminders.indexWhere((r) => r.id == reminderId);
    if (index == -1) {
      return;
    }
    final item = _cloudReminders[index];
    item.freeze();
    _cloudReminders[index] = item.rebuild((update) {
      if (isRead != null) {
        update.isRead = isRead;
      }
      if (isArchived != null) {
        update.meta[ReminderMetaKeys.isArchived] = isArchived.toString();
      }
    });
  }

  void _dispatch() {
    on<ReminderEvent>(
      (event, emit) async {
        await event.when(
          started: () async {
            if (_started) return;
            _started = true;
            add(const ReminderEvent.refresh());
          },
          refresh: () async {
            final result = await _reminderService.fetchReminders();

            // 【全局通知】从服务端拉取账号级通知（跨所有工作区）。
            // 通知的唯一权威源是服务端 af_notification；本地按工作区隔离的
            // reminder 存储只保留"用户自设的日程提醒"职责。
            final cloudRaw = await InboxService().loadNotificationsRaw();
            if (cloudRaw != null) {
              _cloudReminders = cloudRaw
                  .map(_cloudNotificationToReminder)
                  .where((r) => r.id.isNotEmpty)
                  .toList();
            }

            final views = await ViewBackendService.getAllViews();
            views.onSuccess((views) {
              _allViews.clear();
              _allViews.addAll(views.items);
            });

            await result.fold(
              (localReminders) async {
                // 本地存储只保留日程提醒；历史版本写入的云通知副本
                // （按工作区隔离、时有时无的根源）一律丢弃，以服务端全局列表为准
                final scheduleReminders = localReminders
                    .where((r) => !_isCloudNotification(r))
                    .toList();
                final reminders = [..._cloudReminders, ...scheduleReminders];

                // 提醒通过协作数据同步到其他设备后，必须在该设备本机注册
                // 系统定时通知；否则只有创建日程的设备会响。
                await NotificationService()
                    .synchronizeReminderNotifications(scheduleReminders);

                final availableReminders =
                    await filterAvailableReminders(reminders);
                // Separate archived reminders
                // 云通知同样可归档，此处不得按来源过滤
                final archived =
                    reminders.where((reminder) => reminder.isArchived).toList();

                // only print the reminder ids are not the same as the previous ones
                final previousReminderIds =
                    state.reminders.map((e) => e.id).toSet();
                final newReminderIds =
                    availableReminders.map((e) => e.id).toSet();
                final diff = _deepEquality.equals(
                  previousReminderIds,
                  newReminderIds,
                );
                if (!diff) {
                  Log.info(
                    'Fetched reminders on refresh: ${availableReminders.length}',
                  );
                }
                if (!isClosed && !emit.isDone) {
                  emit(
                    state.copyWith(
                      reminders: availableReminders,
                      serverReminders: reminders,
                      archivedReminders: archived,
                    ),
                  );
                }
              },
              (error) {
                Log.error('Failed to fetch reminders: $error');
                // 拉取失败时保留当前列表，_cloudReminders 缓存已在上方沿用
              },
            );
          },
          removeReminder: (reminderId) async {
            final result = await _reminderService.removeReminder(
              reminderId: reminderId,
            );

            result.fold(
              (_) {
                Log.info('Removed reminder: $reminderId');
                unawaited(
                  NotificationService().cancelReminderNotification(reminderId),
                );
                final reminders = List.of(state.reminders);
                final index = reminders
                    .indexWhere((reminder) => reminder.id == reminderId);
                if (index != -1) {
                  reminders.removeAt(index);
                  emit(state.copyWith(reminders: reminders));
                }
              },
              (error) => Log.error(
                'Failed to remove reminder($reminderId): $error',
              ),
            );
          },
          removeReminders: (reminderIds) async {
            Log.info('Remove reminders: $reminderIds');
            final removedIds = <String>{};
            for (final reminderId in reminderIds) {
              final result = await _reminderService.removeReminder(
                reminderId: reminderId,
              );
              if (result.isSuccess) {
                Log.info('Removed reminder: $reminderId');
                await NotificationService()
                    .cancelReminderNotification(reminderId);
                removedIds.add(reminderId);
              } else {
                Log.error('Failed to remove reminder: $reminderId');
              }
            }
            emit(
              state.copyWith(
                reminders: state.reminders
                    .where((reminder) => !removedIds.contains(reminder.id))
                    .toList(),
              ),
            );
          },
          add: (reminder) async {
            // check the timestamp in the reminder
            if (reminder.createdAt == null) {
              reminder.freeze();
              reminder = reminder.rebuild((update) {
                update.meta[ReminderMetaKeys.createdAt] =
                    DateTime.now().millisecondsSinceEpoch.toString();
              });
            }
            if (hasReminder(reminder.id)) {
              Log.error('Reminder: ${reminder.id} failed to be added again');
              return;
            }

            final result = await _reminderService.addReminder(
              reminder: reminder,
            );

            return result.fold(
              (_) async {
                Log.info('Added reminder: ${reminder.id}');
                Log.info('Before adding reminder: ${state.reminders.length}');
                final showRightNow = !DateTime.now()
                        .isBefore(reminder.scheduledAt.toDateTime()) &&
                    !reminder.isRead;

                if (showRightNow) {
                  final reminders = [...state.reminders, reminder];
                  Log.info('After adding reminder: ${reminders.length}');
                  emit(state.copyWith(reminders: reminders));
                }

                // Only schedule future unread reminders for system notifications.
                if (NotificationService.isSchedulableReminder(reminder)) {
                  await NotificationService()
                      .scheduleReminderNotification(reminder);
                }
              },
              (error) {
                Log.error('Failed to add reminder: $error');
              },
            );
          },
          addById: (reminderId, objectId, scheduledAt, meta) async => add(
            ReminderEvent.add(
              reminder: ReminderPB(
                id: reminderId,
                objectId: objectId,
                title: LocaleKeys.reminderNotification_title.tr(),
                message: LocaleKeys.reminderNotification_message.tr(),
                scheduledAt: scheduledAt,
                isAck: scheduledAt.toDateTime().isBefore(DateTime.now()),
                meta: meta,
              ),
            ),
          ),
          update: (updateObject) async {
            final reminder = state.allReminders.firstWhereOrNull(
              (r) => r.id == updateObject.id,
            );

            if (reminder == null) {
              return;
            }

            final newReminder = updateObject.merge(a: reminder);

            // 【全局通知】云端通知的状态变更持久化到服务端（账号级、跨工作区
            // 一致），不写本地 reminder 存储（云通知已不在本地存储中）。
            final FlowyResult<void, FlowyError> failureOrUnit;
            if (_isCloudNotification(reminder)) {
              if (updateObject.isArchived != null) {
                unawaited(
                  updateObject.isArchived!
                      ? InboxService().archive(reminder.id)
                      : InboxService().unarchive(reminder.id),
                );
              }
              // 归档同时置已读（服务端同语义）；单独标记已读也同步服务端
              if (updateObject.isRead == true ||
                  updateObject.isArchived == true) {
                unawaited(InboxService().markAsRead(reminder.id));
              }
              _updateCloudReminderCache(
                reminder.id,
                isRead: newReminder.isRead,
                isArchived: updateObject.isArchived,
              );
              failureOrUnit = FlowyResult.success(null);
            } else {
              failureOrUnit = await _reminderService.updateReminder(
                reminder: newReminder,
              );
            }

            Log.info('Updating reminder: ${newReminder.id}');

            await failureOrUnit.fold((_) async {
              Log.info('Updated reminder: ${newReminder.id}');

              if (_isCloudNotification(newReminder)) {
                await NotificationService()
                    .cancelReminderNotification(newReminder.id);
              } else if (NotificationService.isSchedulableReminder(
                newReminder,
              )) {
                await NotificationService()
                    .scheduleReminderNotification(newReminder);
              } else {
                await NotificationService()
                    .cancelReminderNotification(newReminder.id);
              }

              // Synchronously update archivedReminders when isArchived changes
              var archivedReminders = [...state.archivedReminders];
              final wasArchived =
                  archivedReminders.any((r) => r.id == newReminder.id);
              // Use meta directly since ReminderPB has no isArchived protobuf field
              final isNowArchived =
                  newReminder.meta[ReminderMetaKeys.isArchived] ==
                      true.toString();
              if (isNowArchived && !wasArchived) {
                archivedReminders = [...archivedReminders, newReminder];
              } else if (!isNowArchived && wasArchived) {
                archivedReminders = archivedReminders
                    .where((r) => r.id != newReminder.id)
                    .toList();
              }

              // Also keep serverReminders in sync so allReminders reflects the change
              var serverReminders = [...state.serverReminders];
              final serverIdx =
                  serverReminders.indexWhere((r) => r.id == newReminder.id);
              if (serverIdx != -1) {
                serverReminders
                    .replaceRange(serverIdx, serverIdx + 1, [newReminder]);
              } else {
                serverReminders = [...serverReminders, newReminder];
              }

              final index =
                  state.reminders.indexWhere((r) => r.id == newReminder.id);
              if (index == -1) {
                if (await checkReminderAvailable(
                  newReminder,
                  state.allReminders.map((e) => e.id).toSet(),
                )) {
                  emit(
                    state.copyWith(
                      reminders: [...state.reminders, newReminder],
                      archivedReminders: archivedReminders,
                      serverReminders: serverReminders,
                    ),
                  );
                } else {
                  emit(
                    state.copyWith(
                      archivedReminders: archivedReminders,
                      serverReminders: serverReminders,
                    ),
                  );
                }
                return;
              }
              final reminders = [...state.reminders];
              if (await checkReminderAvailable(
                newReminder,
                state.allReminders.map((e) => e.id).toSet(),
              )) {
                reminders.replaceRange(index, index + 1, [newReminder]);
                emit(
                  state.copyWith(
                    reminders: reminders,
                    archivedReminders: archivedReminders,
                    serverReminders: serverReminders,
                  ),
                );
              } else {
                reminders.removeAt(index);
                emit(
                  state.copyWith(
                    reminders: reminders,
                    archivedReminders: archivedReminders,
                    serverReminders: serverReminders,
                  ),
                );
              }
            }, (error) {
              Log.error(
                'Failed to update reminder(${newReminder.id}): $error',
              );
            });
          },
          pressReminder: (reminderId, path, view) {
            final reminder =
                state.reminders.firstWhereOrNull((r) => r.id == reminderId);

            if (reminder == null) {
              return;
            }

            add(
              ReminderEvent.update(
                ReminderUpdate(
                  id: reminderId,
                  isRead: state.pastReminders.contains(reminder),
                ),
              ),
            );

            String? rowId;
            if (view?.layout != ViewLayoutPB.Document) {
              rowId = reminder.meta[ReminderMetaKeys.rowId];
            }

            final action = NavigationAction(
              objectId: reminder.objectId,
              arguments: {
                ActionArgumentKeys.view: view,
                ActionArgumentKeys.nodePath: path,
                ActionArgumentKeys.rowId: rowId,
              },
            );

            if (!isClosed) {
              _actionBloc.add(
                ActionNavigationEvent.performAction(
                  action: action,
                  nextActions: [
                    action.copyWith(
                      type: rowId != null
                          ? ActionType.openRow
                          : ActionType.jumpToBlock,
                    ),
                  ],
                ),
              );
            }
          },
          markAsRead: (reminderIds) async {
            final updated = await _onMarkAsRead(reminderIds: reminderIds);

            await NotificationService()
                .synchronizeReminderNotifications(updated);

            Log.info('Marked reminders as read: $reminderIds');

            emit(state.copyWith(reminders: updated));
          },
          archive: (reminderIds) async {
            final reminders = await _onArchived(
              isArchived: true,
              reminderIds: reminderIds,
            );

            await NotificationService()
                .synchronizeReminderNotifications(reminders);

            Log.info('Archived reminders: $reminderIds');

            emit(
              state.copyWith(
                reminders: reminders,
                archivedReminders:
                    state.serverReminders.where((r) => r.isArchived).toList(),
              ),
            );
          },
          markAllRead: () async {
            final updated = await _onMarkAsRead();

            await NotificationService()
                .synchronizeReminderNotifications(updated);

            Log.info('Marked all reminders as read');

            emit(state.copyWith(reminders: updated));
          },
          archiveAll: () async {
            final reminders = await _onArchived(isArchived: true);

            await NotificationService()
                .synchronizeReminderNotifications(reminders);

            Log.info('Archived all reminders');

            emit(
              state.copyWith(
                reminders: reminders,
                archivedReminders:
                    state.serverReminders.where((r) => r.isArchived).toList(),
              ),
            );
          },
          unarchiveAll: () async {
            final reminders = await _onArchived(isArchived: false);
            await NotificationService()
                .synchronizeReminderNotifications(reminders);
            emit(
              state.copyWith(
                reminders: reminders,
                archivedReminders:
                    state.serverReminders.where((r) => r.isArchived).toList(),
              ),
            );
          },
          resetTimer: () {
            timer?.cancel();
            timer = _periodicCheck();
          },
        );
      },
    );
  }

  @override
  Future<void> close() async {
    Log.info('ReminderBloc closed');
    _listener.dispose();
    _awarenessListener.stop();
    _cloudRefreshDebounce?.cancel();
    timer?.cancel();
    await super.close();
  }

  /// Mark the reminder as read
  ///
  /// If the [reminderIds] is null, all unread reminders will be marked as read
  /// Otherwise, only the reminders with the given IDs will be marked as read
  Future<List<ReminderPB>> _onMarkAsRead({
    List<String>? reminderIds,
  }) async {
    // 【修复通知全丢 2026-07-30】此处原先另有一条 globalReminders 分支，
    // 因该列表从未被填充而始终空转；云通知的已读实际由下方
    // _isCloudNotification 分支处理（写服务端），故一并删除，避免二义。
    final allReminders = state.reminders;

    final Iterable<ReminderPB> remindersToUpdate;

    if (reminderIds != null) {
      remindersToUpdate = allReminders.where(
        (reminder) => reminderIds.contains(reminder.id) && !reminder.isRead,
      );
    } else {
      // Get all reminders that are not matching the isArchived flag
      remindersToUpdate = allReminders.where(
        (reminder) => !reminder.isRead,
      );
    }

    // 【全局通知】云端通知的已读只持久化到服务端（账号级唯一真相），
    // 本地日程提醒仍写 Rust reminder 存储。全量标记时用批量接口减少请求。
    final cloudToUpdate =
        remindersToUpdate.where(_isCloudNotification).toList();
    if (reminderIds == null && cloudToUpdate.isNotEmpty) {
      unawaited(InboxService().markAllAsRead());
    } else {
      for (final reminder in cloudToUpdate) {
        unawaited(InboxService().markAsRead(reminder.id));
      }
    }

    for (final reminder in remindersToUpdate) {
      if (_isCloudNotification(reminder)) {
        _updateCloudReminderCache(reminder.id, isRead: true);
        Log.info('Mark cloud notification ${reminder.id} as read');
        continue;
      }
      reminder.isRead = true;
      await _reminderService.updateReminder(reminder: reminder);
      Log.info('Mark reminder ${reminder.id} as read');
    }

    return allReminders.map((e) {
      if (reminderIds != null && !reminderIds.contains(e.id)) {
        return e;
      }

      if (e.isRead) {
        return e;
      }

      e.freeze();
      return e.rebuild((update) {
        update.isRead = true;
      });
    }).toList();
  }

  /// Archive or unarchive reminders
  ///
  /// If the [reminderIds] is null, all reminders will be archived
  /// Otherwise, only the reminders with the given IDs will be archived or unarchived
  Future<List<ReminderPB>> _onArchived({
    required bool isArchived,
    List<String>? reminderIds,
  }) async {
    // 云通知与日程提醒同在一个列表，归档对两者一视同仁；
    // 差别只在"归档状态写到哪里"（见下方 _isCloudNotification 分支）。
    final allReminders = state.reminders;

    final Iterable<ReminderPB> remindersToUpdate;

    if (reminderIds != null) {
      remindersToUpdate = allReminders.where(
        (reminder) =>
            reminderIds.contains(reminder.id) &&
            reminder.isArchived != isArchived,
      );
    } else {
      // Get all reminders that are not matching the isArchived flag
      remindersToUpdate = allReminders.where(
        (reminder) => reminder.isArchived != isArchived,
      );
    }

    // 【全局通知】云端通知的归档持久化到服务端（账号级，跨工作区/设备一致），
    // 本地日程提醒仍写 Rust reminder 存储。全量操作时用批量接口。
    final cloudToUpdate =
        remindersToUpdate.where(_isCloudNotification).toList();
    if (reminderIds == null && cloudToUpdate.isNotEmpty) {
      unawaited(
        isArchived
            ? InboxService().archiveAll()
            : InboxService().unarchiveAll(),
      );
    } else {
      for (final reminder in cloudToUpdate) {
        unawaited(
          isArchived
              ? InboxService().archive(reminder.id)
              : InboxService().unarchive(reminder.id),
        );
      }
    }

    for (final reminder in remindersToUpdate) {
      if (_isCloudNotification(reminder)) {
        _updateCloudReminderCache(
          reminder.id,
          isRead: isArchived ? true : null,
          isArchived: isArchived,
        );
        Log.info('Cloud notification ${reminder.id} is archived: $isArchived');
        continue;
      }
      reminder.isRead = isArchived;
      reminder.meta[ReminderMetaKeys.isArchived] = isArchived.toString();
      await _reminderService.updateReminder(reminder: reminder);
      Log.info('Reminder ${reminder.id} is archived: $isArchived');
    }

    return allReminders.map((e) {
      if (reminderIds != null && !reminderIds.contains(e.id)) {
        return e;
      }

      if (e.isArchived == isArchived) {
        return e;
      }

      e.freeze();
      return e.rebuild((update) {
        update.isRead = isArchived;
        update.meta[ReminderMetaKeys.isArchived] = isArchived.toString();
      });
    }).toList();
  }

  Timer _periodicCheck() {
    return Timer.periodic(
      const Duration(seconds: 30),
      (_) async {
        if (!isClosed) add(const ReminderEvent.refresh());
      },
    );
  }

  bool _isGlobalNotification(ReminderPB reminder) {
    final cloudType = reminder.meta['cloud_notification_type'];
    return cloudType != null && cloudType.isNotEmpty;
  }

  Future<bool> checkReminderAvailable(
    ReminderPB reminder,
    Set<String> reminderIds, {
    Set<String> removeIds = const {},
  }) async {
    /// check if schedule time is coming
    final scheduledAt = reminder.scheduledAt.toDateTime();

    // Only show reminders that have reached their scheduled time.
    if (!DateTime.now().isAfter(scheduledAt)) {
      return false;
    }

    // Archived reminders should not be shown in the notification list.
    if (reminder.isArchived) {
      return false;
    }

    // Cloud notifications (from server) don't need a local view — they have
    // 'payload' in meta which local reminders never have.
    if (reminder.meta.containsKey('payload')) {
      return true;
    }

    /// check if view is not null
    final viewId = reminder.objectId;
    final view = _allViews.firstWhereOrNull((e) => e.id == viewId);
    if (view == null) {
      removeIds.add(reminder.id);
      return false;
    }

    if (view.isDatabase) {
      return true;
    } else {
      /// blockId is null means no node
      final blockId = reminder.meta[ReminderMetaKeys.blockId];
      if (blockId == null) {
        removeIds.add(reminder.id);
        return false;
      }

      /// check if document is not null
      final document = await DocumentService()
          .openDocument(documentId: viewId)
          .fold((s) => s.toDocument(), (_) => null);
      if (document == null) {
        removeIds.add(reminder.id);
        return false;
      }
      Node? searchById(Node current, String id) {
        if (current.id == id) {
          return current;
        }
        if (current.children.isNotEmpty) {
          for (final child in current.children) {
            final node = searchById(child, id);

            if (node != null) {
              return node;
            }
          }
        }
        return null;
      }

      /// check if node is not null
      final node = searchById(document.root, blockId);
      if (node == null) {
        removeIds.add(reminder.id);
        return false;
      }
      final textInserts = node.delta?.whereType<TextInsert>();
      if (textInserts == null) return false;
      for (final text in textInserts) {
        final mention =
            text.attributes?[MentionBlockKeys.mention] as Map<String, dynamic>?;
        final reminderId = mention?[MentionBlockKeys.reminderId] as String?;
        if (reminderIds.contains(reminderId)) {
          return true;
        }
      }
      removeIds.add(reminder.id);
      return false;
    }
  }

  Future<List<ReminderPB>> filterAvailableReminders(
    List<ReminderPB> reminders, {
    bool removeUnavailableReminder = false,
  }) async {
    final List<ReminderPB> availableReminders = [];
    final reminderIds = reminders.map((e) => e.id).toSet();
    final removeIds = <String>{};

    for (final r in reminders) {
      if (await checkReminderAvailable(r, reminderIds, removeIds: removeIds)) {
        availableReminders.add(r);
      }
    }

    if (removeUnavailableReminder) {
      Log.info('Remove unavailable reminder: $removeIds');
      add(ReminderEvent.removeReminders(removeIds));
    }

    return availableReminders;
  }
}

@freezed
class ReminderEvent with _$ReminderEvent {
  // On startup we fetch all reminders and upcoming ones
  const factory ReminderEvent.started() = _Started;

  // Remove a reminder
  const factory ReminderEvent.removeReminder({required String reminderId}) =
      _RemoveReminder;

  // Remove reminders
  const factory ReminderEvent.removeReminders(Set<String> reminderIds) =
      _RemoveReminders;

  // Add a reminder
  const factory ReminderEvent.add({required ReminderPB reminder}) = _Add;

  // Add a reminder
  const factory ReminderEvent.addById({
    required String reminderId,
    required String objectId,
    required Int64 scheduledAt,
    @Default(null) Map<String, String>? meta,
  }) = _AddById;

  // Update a reminder (eg. isAck, isRead, etc.)
  const factory ReminderEvent.update(ReminderUpdate update) = _Update;

  // Event to mark specific reminders as read, takes a list of reminder IDs
  const factory ReminderEvent.markAsRead(List<String> reminderIds) =
      _MarkAsRead;

  // Event to mark all unread reminders as read
  const factory ReminderEvent.markAllRead() = _MarkAllRead;

  // Event to archive specific reminders, takes a list of reminder IDs
  const factory ReminderEvent.archive(List<String> reminderIds) = _Archive;

  // Event to archive all reminders
  const factory ReminderEvent.archiveAll() = _ArchiveAll;

  // Event to unarchive all reminders
  const factory ReminderEvent.unarchiveAll() = _UnarchiveAll;

  // Event to handle reminder press action
  const factory ReminderEvent.pressReminder({
    required String reminderId,
    @Default(null) int? path,
    @Default(null) ViewPB? view,
  }) = _PressReminder;

  // Event to refresh reminders
  const factory ReminderEvent.refresh() = _Refresh;
  const factory ReminderEvent.resetTimer() = _ResetTimer;
}

/// Object used to merge updates with
/// a [ReminderPB]
///
class ReminderUpdate {
  ReminderUpdate({
    required this.id,
    this.isAck,
    this.isRead,
    this.scheduledAt,
    this.includeTime,
    this.isArchived,
    this.date,
  });

  final String id;
  final bool? isAck;
  final bool? isRead;
  final DateTime? scheduledAt;
  final bool? includeTime;
  final bool? isArchived;
  final DateTime? date;

  ReminderPB merge({required ReminderPB a}) {
    final isAcknowledged = isAck == null && scheduledAt != null
        ? scheduledAt!.isBefore(DateTime.now())
        : a.isAck;
    final isReadValue = switch (isRead) {
      bool value => value,
      null => scheduledAt != null && !scheduledAt!.isAfter(DateTime.now())
          ? true
          : a.isRead,
    };

    final metaMap = {...a.meta};
    if (includeTime != a.includeTime) {
      metaMap[ReminderMetaKeys.includeTime] = includeTime.toString();
    }

    if (isArchived != a.isArchived) {
      metaMap[ReminderMetaKeys.isArchived] = isArchived.toString();
    }

    if (date != a.date && date != null) {
      metaMap[ReminderMetaKeys.date] = date!.millisecondsSinceEpoch.toString();
    }

    return ReminderPB(
      id: a.id,
      objectId: a.objectId,
      scheduledAt: scheduledAt != null
          ? Int64(scheduledAt!.millisecondsSinceEpoch)
          : a.scheduledAt,
      isAck: isAcknowledged,
      isRead: isReadValue,
      title: a.title,
      message: a.message,
      meta: metaMap,
    );
  }
}

class ReminderState {
  ReminderState({
    List<ReminderPB>? reminders,
    this.serverReminders = const [],
    List<ReminderPB>? archivedReminders,
  }) {
    // 【修复通知全丢 2026-07-30】此处原有 `!_isGlobalReminder(...)` 过滤。
    // 云通知同样可以被归档，归档页必须能看到它们。详见 reminders getter 的注释。
    _archivedReminders = archivedReminders ?? [];

    if (reminders?.isEmpty ?? true) {
      return;
    }

    final now = DateTime.now();

    for (final ReminderPB reminder in reminders ?? []) {
      final scheduledDate = reminder.scheduledAt.toDateTime();

      if (scheduledDate.isBefore(now)) {
        pastReminders.add(reminder);
      } else {
        upcomingReminders.add(reminder);
      }
    }

    pastReminders.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    upcomingReminders.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    _reminders
        .addAll([...List.of(pastReminders), ...List.of(upcomingReminders)]);
  }

  final List<ReminderPB> _reminders = [];

  /// 面板展示用的全部提醒：**既包含**服务端账号级云通知（分享/邀请/权限变更），
  /// **也包含**本地日程提醒。二者由 ReminderBloc 的 refresh 处理器合并后传入
  /// （`[..._cloudReminders, ...scheduleReminders]`），此处不得再做来源过滤。
  ///
  /// 【修复通知全丢 2026-07-30】此前这里是一套 workspaceReminders/globalReminders
  /// 双列表：workspaceReminders 用 `!_isGlobalReminder(...)` 把云通知全部滤掉，
  /// 本应接住它们的 globalReminders 却从未被填充（其唯一数据源
  /// InboxService.loadGlobalReminders 全仓零调用），导致分享/邀请通知一条都不显示。
  ///
  /// 成因：07-13 引入双列表时是自洽的；07-14 把生产端改为 _cloudReminders 统一合并，
  /// 却没有同步删除这里的旧过滤器，于是它变成了一台静默丢弃机。
  /// 单元测试因构造的是已废弃的 globalReminders 入参而全绿，未能拦截。
  ///
  /// **不要再按"来源"拆分列表**——是否为云通知只应影响"已读写到哪里"
  /// （见 _onMarkAsRead 中的 _isCloudNotification 分支），不应影响"是否展示"。
  List<ReminderPB> get reminders => _reminders.unique((e) => e.id);
  List<ReminderPB> get allReminders =>
      [...serverReminders, ..._reminders].unique((e) => e.id);

  List<ReminderPB> pastReminders = [];
  List<ReminderPB> upcomingReminders = [];
  final List<ReminderPB> serverReminders;

  List<ReminderPB> _archivedReminders = [];
  List<ReminderPB> get archivedReminders =>
      _archivedReminders.unique((e) => e.id);

  ReminderState copyWith({
    List<ReminderPB>? reminders,
    List<ReminderPB>? serverReminders,
    List<ReminderPB>? archivedReminders,
  }) =>
      ReminderState(
        reminders: reminders ?? _reminders,
        serverReminders: serverReminders ?? this.serverReminders,
        archivedReminders: archivedReminders ?? _archivedReminders,
      );
}

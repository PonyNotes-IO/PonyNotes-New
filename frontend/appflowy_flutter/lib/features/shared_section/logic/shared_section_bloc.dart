import 'dart:async';

import 'package:appflowy/core/notification/folder_notification.dart';
import 'package:appflowy/features/shared_section/data/repositories/shared_pages_repository.dart';
import 'package:appflowy/features/shared_section/logic/shared_section_event.dart';
import 'package:appflowy/features/shared_section/logic/shared_section_state.dart';
import 'package:appflowy/features/util/extensions.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:bloc/bloc.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

export 'shared_section_event.dart';
export 'shared_section_state.dart';

class SharedSectionBloc extends Bloc<SharedSectionEvent, SharedSectionState> {
  SharedSectionBloc({
    required this.repository,
    required this.workspaceId,
    this.enablePolling = false,
    this.pollingIntervalSeconds = 30,
  }) : super(SharedSectionState.initial()) {
    on<SharedSectionInitEvent>(_onInit);
    on<SharedSectionRefreshEvent>(_onRefresh);
    on<SharedSectionUpdateSharedPagesEvent>(_onUpdateSharedPages);
    on<SharedSectionToggleExpandedEvent>(_onToggleExpanded);
    on<SharedSectionLeaveSharedPageEvent>(_onLeaveSharedPage);
  }

  final String workspaceId;

  // The repository to fetch the shared views.
  // If you need to test this bloc, you can add your own repository implementation.
  final SharedPagesRepository repository;

  // Used to listen for shared view updates.
  FolderNotificationListener? _folderNotificationListener;

  // Since the backend doesn't provide a way to listen for shared view updates (websocket with shared view updates is not implemented yet),
  // we need to poll the shared views periodically.
  final bool enablePolling;

  // The interval of polling the shared views.
  final int pollingIntervalSeconds;

  Timer? _pollingTimer;

  // 防抖标志，避免重复触发刷新
  bool _isRefreshing = false;

  @override
  Future<void> close() async {
    await _folderNotificationListener?.stop();
    _folderNotificationListener = null;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    await super.close();
  }

  Future<void> _onInit(
    SharedSectionInitEvent event,
    Emitter<SharedSectionState> emit,
  ) async {
    _initFolderNotificationListener();
    _startPollingIfNeeded();

    emit(
      state.copyWith(
        isLoading: true,
        errorMessage: '',
      ),
    );
    final result = await repository.getSharedPages();
    result.fold(
      (pages) {
        emit(
          state.copyWith(
            sharedPages: pages,
            isLoading: false,
          ),
        );
      },
      (error) {
        emit(
          state.copyWith(
            errorMessage: error.msg,
            isLoading: false,
          ),
        );
      },
    );
  }

  Future<void> _onRefresh(
    SharedSectionRefreshEvent event,
    Emitter<SharedSectionState> emit,
  ) async {
    // 如果正在加载中，跳过本次刷新
    if (state.isLoading) {
      return;
    }

    // 使用 compute-style 防抖：如果在等待中，不重复触发
    if (_isRefreshing) {
      return;
    }
    _isRefreshing = true;

    try {
      final result = await repository.getSharedPages();

      result.fold(
        (pages) {
          emit(
            state.copyWith(
              sharedPages: pages,
            ),
          );
        },
        (error) {
          emit(
            state.copyWith(
              errorMessage: error.msg,
            ),
          );
        },
      );
    } finally {
      _isRefreshing = false;
    }
  }

  void _onUpdateSharedPages(
    SharedSectionUpdateSharedPagesEvent event,
    Emitter<SharedSectionState> emit,
  ) {
    emit(
      state.copyWith(
        sharedPages: event.sharedPages,
      ),
    );
  }

  void _onToggleExpanded(
    SharedSectionToggleExpandedEvent event,
    Emitter<SharedSectionState> emit,
  ) {
    emit(
      state.copyWith(
        isExpanded: !state.isExpanded,
      ),
    );
  }

  void _initFolderNotificationListener() {
    _folderNotificationListener = FolderNotificationListener(
      objectId: workspaceId,
      handler: (notification, result) {
        // 检查bloc是否已关闭，避免在dispose后调用add()
        if (isClosed) {
          return;
        }

        if (notification == FolderNotification.DidUpdateSharedViews) {
          if (!isClosed) {
            // The notification payload comes from the legacy local cache and
            // can be incomplete. Re-fetch through the repository so mobile
            // keeps the same sent + received dataset as desktop.
            add(const SharedSectionEvent.refresh());
          }
        }
      },
    );
  }

  void _onLeaveSharedPage(
    SharedSectionLeaveSharedPageEvent event,
    Emitter<SharedSectionState> emit,
  ) async {
    final result = await repository.leaveSharedPage(event.pageId);

    // 检查bloc是否已关闭，避免在dispose后调用add()或emit()
    if (isClosed) {
      return;
    }

    result.fold(
      (success) {
        if (!isClosed) {
          add(
            SharedSectionEvent.updateSharedPages(
              sharedPages: state.sharedPages
                ..removeWhere(
                  (page) => page.view.id == event.pageId,
                ),
            ),
          );
        }
      },
      (error) {
        if (!isClosed) {
          emit(state.copyWith(errorMessage: error.msg));
        }
      },
    );
  }

  void _startPollingIfNeeded() {
    _pollingTimer?.cancel();
    if (enablePolling && pollingIntervalSeconds > 0) {
      _pollingTimer = Timer.periodic(
        Duration(seconds: pollingIntervalSeconds),
        (_) {
          // 检查bloc是否已关闭，避免在dispose后调用add()
          if (isClosed) {
            _pollingTimer?.cancel();
            _pollingTimer = null;
            return;
          }

          add(const SharedSectionEvent.refresh());
        },
      );
    }
  }
}

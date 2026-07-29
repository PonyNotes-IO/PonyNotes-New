import 'dart:async';
import 'dart:typed_data';

import 'package:appflowy/core/notification/folder_notification.dart';
import 'package:appflowy/features/page_access_level/data/repositories/page_access_level_repository.dart';
import 'package:appflowy/features/page_access_level/data/repositories/rust_page_access_level_repository_impl.dart';
import 'package:appflowy/features/page_access_level/logic/page_access_level_event.dart';
import 'package:appflowy/features/page_access_level/logic/page_access_level_state.dart';
import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy/features/share_tab/logic/share_section_refresh_notifier.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/notification.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:bloc/bloc.dart';
import 'package:protobuf/protobuf.dart';

export 'page_access_level_event.dart';
export 'page_access_level_state.dart';

class PageAccessLevelBloc
    extends Bloc<PageAccessLevelEvent, PageAccessLevelState> {
  PageAccessLevelBloc({
    required this.view,
    this.ignorePageAccessLevel = false,
    PageAccessLevelRepository? repository,
  })  : repository = repository ?? RustPageAccessLevelRepositoryImpl(),
        listener = ViewListener(viewId: view.id),
        super(PageAccessLevelState.initial(view)) {
    on<PageAccessLevelInitialEvent>(_onInitial);
    on<PageAccessLevelLockEvent>(_onLock);
    on<PageAccessLevelUnlockEvent>(_onUnlock);
    on<PageAccessLevelUpdateLockStatusEvent>(_onUpdateLockStatus);
    on<PageAccessLevelUpdateSectionTypeEvent>(_onUpdateSectionType);
    on<PageAccessLevelRefreshAccessLevelEvent>(_onRefreshAccessLevel);
  }

  final ViewPB view;

  // The repository to manage view lock status.
  // If you need to test this bloc, you can add your own repository implementation.
  final PageAccessLevelRepository repository;

  // Used to listen for view updates.
  late final ViewListener listener;

  // Used to listen for shared users update notifications.
  FolderNotificationListener? _sharedUsersListener;

  // should ignore the page access level
  // in the row details page, we don't need to check the page access level
  final bool ignorePageAccessLevel;

  // 定时轮询定时器：定期刷新权限状态，确保权限变更能及时生效
  // 解决后端通知可能丢失的问题，提供兜底机制
  Timer? _permissionPollingTimer;

  // 监听 ShareSectionRefreshNotifier 信号，权限变更后立即刷新
  StreamSubscription<void>? _shareSectionRefreshSub;

  // DidUpdateSharedUsers 节流：避免短时间内重复刷新访问级别。
  // 协作场景下权限变更需要尽快生效（如从可编辑改为只读），降级窗口越小，
  // 只读用户能误编辑、进而在重新授权时回放到他人页面的内容就越少，因此把节流
  // 收紧到 150ms：既能防止通知风暴导致的重复请求，又能让权限改动近乎实时
  // 反映到编辑器（editable=false），尽快关闭“可写窗口”。
  DateTime? _lastRefreshAccessLevelTime;
  static const Duration _refreshAccessLevelThrottle =
      Duration(milliseconds: 150);
  bool _isRefreshingAccessLevel = false;
  bool _refreshAccessLevelAgain = false;

  @override
  Future<void> close() async {
    _permissionPollingTimer?.cancel();
    await _shareSectionRefreshSub?.cancel();
    await listener.stop();
    await _sharedUsersListener?.stop();
    return super.close();
  }

  Future<void> _onInitial(
    PageAccessLevelInitialEvent event,
    Emitter<PageAccessLevelState> emit,
  ) async {
    // lock status
    listener.start(
      onViewUpdated: (view) async {
        if (isClosed) return;
        add(PageAccessLevelEvent.updateLockStatus(view.isLocked));
      },
    );

    // Listen for shared users updates so we can re-check access level
    // when the cloud fetches the latest permissions from the backend.
    _sharedUsersListener = FolderNotificationListener(
      objectId: view.id,
      handler: (FolderNotification ty, FlowyResult<Uint8List, FlowyError> _) {
        if (ty == FolderNotification.DidUpdateSharedUsers) {
          final now = DateTime.now();
          if (_lastRefreshAccessLevelTime == null ||
              now.difference(_lastRefreshAccessLevelTime!) >
                  _refreshAccessLevelThrottle) {
            _lastRefreshAccessLevelTime = now;
            if (isClosed) return;
            add(const PageAccessLevelEvent.refreshAccessLevel());
          }
        }
      },
    );

    // section type
    final sectionTypeResult = await repository.getSectionType(view.id);
    final sectionType = sectionTypeResult.fold(
      (sectionType) => sectionType,
      (_) => SharedSectionType.unknown,
    );

    if (ignorePageAccessLevel) {
      emit(
        state.copyWith(
          view: view,
          isLocked: view.isLocked,
          isLoadingLockStatus: false,
          accessLevel: ShareAccessLevel.fullAccess,
          sectionType: sectionType,
        ),
      );
      return;
    }

    final result = await repository.getView(view.id);
    final accessLevel = await repository.getAccessLevel(view.id);
    final latestView = result.fold(
      (view) => view,
      (_) => view,
    );
    emit(
      state.copyWith(
        view: latestView,
        isLocked: latestView.isLocked,
        isLoadingLockStatus: false,
        accessLevel: accessLevel.fold(
          (accessLevel) => accessLevel,
          (_) => ShareAccessLevel.readOnly,
        ),
        sectionType: sectionType,
      ),
    );

    // Poll the authoritative document endpoint. FFI's current-workspace cache
    // is not consulted to decide whether polling is necessary: it can be empty
    // for a valid cross-workspace share and must never become a permission fact.
    _permissionPollingTimer?.cancel();
    _permissionPollingTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) {
        if (isClosed) return;
        add(const PageAccessLevelEvent.refreshAccessLevel());
      },
    );

    // 监听 ShareSectionRefreshNotifier 信号
    // 当 ShareTabBloc 修改权限或移除协作者后会调用 notify()，
    // 收到信号后立即刷新权限，确保编辑器实时反映权限变更。
    await _shareSectionRefreshSub?.cancel();
    _shareSectionRefreshSub = ShareSectionRefreshNotifier.stream.listen((_) {
      if (isClosed) return;
      add(const PageAccessLevelEvent.refreshAccessLevel());
    });
  }

  Future<void> _onLock(
    PageAccessLevelLockEvent event,
    Emitter<PageAccessLevelState> emit,
  ) async {
    final result = await repository.lockView(view.id);
    final isLocked = result.fold(
      (_) => true,
      (_) => false,
    );
    add(
      PageAccessLevelEvent.updateLockStatus(
        isLocked,
      ),
    );
  }

  Future<void> _onUnlock(
    PageAccessLevelUnlockEvent event,
    Emitter<PageAccessLevelState> emit,
  ) async {
    final result = await repository.unlockView(view.id);
    final isLocked = result.fold(
      (_) => false,
      (_) => true,
    );
    add(
      PageAccessLevelEvent.updateLockStatus(
        isLocked,
        lockCounter: state.lockCounter + 1,
      ),
    );
  }

  void _onUpdateLockStatus(
    PageAccessLevelUpdateLockStatusEvent event,
    Emitter<PageAccessLevelState> emit,
  ) {
    state.view.freeze();
    final updatedView = state.view.rebuild(
      (update) => update.isLocked = event.isLocked,
    );
    emit(
      state.copyWith(
        view: updatedView,
        isLocked: event.isLocked,
        lockCounter: event.lockCounter ?? state.lockCounter,
      ),
    );
  }

  void _onUpdateSectionType(
    PageAccessLevelUpdateSectionTypeEvent event,
    Emitter<PageAccessLevelState> emit,
  ) {
    emit(
      state.copyWith(
        sectionType: event.sectionType,
      ),
    );
  }

  Future<void> _onRefreshAccessLevel(
    PageAccessLevelRefreshAccessLevelEvent event,
    Emitter<PageAccessLevelState> emit,
  ) async {
    if (ignorePageAccessLevel) {
      return;
    }

    if (_isRefreshingAccessLevel) {
      _refreshAccessLevelAgain = true;
      return;
    }

    _isRefreshingAccessLevel = true;
    try {
      do {
        _refreshAccessLevelAgain = false;
        final accessLevel = await repository.getAccessLevel(view.id);
        if (isClosed) {
          return;
        }

        final newAccessLevel = accessLevel.fold(
          (accessLevel) => accessLevel,
          (error) {
            Log.warn('[PageAccessLevel] getAccessLevel failed: $error');
            return ShareAccessLevel.readOnly;
          },
        );

        Log.debug(
          '[PageAccessLevel] polling refresh: '
          'viewId=${view.id}, '
          'current=${state.accessLevel}, '
          'new=$newAccessLevel, '
          'changed=${newAccessLevel != state.accessLevel}',
        );

        // 只在权限真正变化时才 emit，避免不必要的 UI 重建
        if (newAccessLevel != state.accessLevel) {
          Log.debug(
              '[PageAccessLevel] access level changed: ${state.accessLevel} -> $newAccessLevel');
          emit(
            state.copyWith(
              accessLevel: newAccessLevel,
            ),
          );
        }
      } while (_refreshAccessLevelAgain && !isClosed);
    } finally {
      _isRefreshingAccessLevel = false;
      _refreshAccessLevelAgain = false;
    }
  }
}

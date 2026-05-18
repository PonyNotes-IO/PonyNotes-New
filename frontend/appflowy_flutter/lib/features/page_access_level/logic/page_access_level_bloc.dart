import 'dart:async';
import 'dart:typed_data';

import 'package:appflowy/core/notification/folder_notification.dart';
import 'package:appflowy/features/page_access_level/data/repositories/page_access_level_repository.dart';
import 'package:appflowy/features/page_access_level/data/repositories/rust_page_access_level_repository_impl.dart';
import 'package:appflowy/features/page_access_level/logic/page_access_level_event.dart';
import 'package:appflowy/features/page_access_level/logic/page_access_level_state.dart';
import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
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

  // DidUpdateSharedUsers 节流：最多每 5 分钟刷新一次访问级别
  DateTime? _lastRefreshAccessLevelTime;
  static const Duration _refreshAccessLevelThrottle = Duration(minutes: 5);

  @override
  Future<void> close() async {
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
            add(const PageAccessLevelEvent.refreshAccessLevel());
          }
        }
      },
    );

    // section type
    final sectionTypeResult = await repository.getSectionType(view.id);
    final sectionType = sectionTypeResult.fold(
      (sectionType) => sectionType,
      (_) => SharedSectionType.public,
    );

    if (!FeatureFlag.sharedSection.isOn || ignorePageAccessLevel) {
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
    if (!FeatureFlag.sharedSection.isOn || ignorePageAccessLevel) {
      return;
    }

    final accessLevel = await repository.getAccessLevel(view.id);
    emit(
      state.copyWith(
        accessLevel: accessLevel.fold(
          (accessLevel) => accessLevel,
          (_) => ShareAccessLevel.readOnly,
        ),
      ),
    );
  }
}

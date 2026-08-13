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
import 'package:appflowy_backend/dispatch/dispatch.dart';
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
      (_) => SharedSectionType.public,
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
    final accessLevel = await repository.getAccessLevel(
      view.id,
      workspaceId: view.hasWorkspaceId() ? view.workspaceId : null,
    );
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

    // #4 非共享文档(无协作者)无需兜底轮询：权限不会变化，轮询纯浪费。
    // 若之后被分享，DidUpdateSharedUsers 通知与 ShareSectionRefreshNotifier
    // 仍会触发刷新，因此跳过轮询是安全的。查询失败时保守起见仍启用轮询。
    var hasSharedUsers = true;
    try {
      final sharedResult = await FolderEventGetSharedUsers(
        GetSharedUsersPayloadPB(viewId: view.id),
      ).send();
      hasSharedUsers = sharedResult.fold(
        (success) => success.items.isNotEmpty,
        (_) => true,
      );
    } catch (_) {
      hasSharedUsers = true;
    }

    // 启动兜底轮询（每 10 秒刷新一次权限状态）
    // 确保权限变更能及时生效，即使后端通知丢失也能通过轮询更新。
    // 这是 DidUpdateSharedUsers 通知丢失时的唯一兜底：间隔越短，被降级为只读的
    // 用户能继续误编辑的窗口越小，从而减少重新授权时回放到他人页面的内容。
    // 10s 是“及时性”与“每个打开的协作文档的权限查询请求量”的折中。
    _permissionPollingTimer?.cancel();
    if (hasSharedUsers) {
      _permissionPollingTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) {
          if (isClosed) return;
          add(const PageAccessLevelEvent.refreshAccessLevel());
        },
      );
    } else {
      Log.debug('[PageAccessLevel] 非共享文档，跳过权限轮询. page: ${view.id}');
    }

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
      // 【2026-08-13 修复：本地 SQLite 连接池被打满导致整个客户端卡死】
      //
      // 这个 do/while 的本意是「合并并发刷新请求」：刷新期间又来请求就置位
      // _refreshAccessLevelAgain，本轮结束后补跑一轮。问题是它没有任何上限 ——
      // 只要刷新事件到达的频率不低于单轮耗时，标志位就会一直被重新置位，循环
      // 永不退出。
      //
      // 而 getAccessLevel 每一轮开头都会 getCurrentUserProfile()（走 GET_PROFILE
      // 事件 → Rust 侧 UserDB::get_connection 取一个 SQLite 连接）。断网或后端
      // 不可用时，getAccessLevel 是【快速失败】返回的，单轮耗时极短，于是这里
      // 变成高频空转：实测 2026-08-13 日志中 ws 断开的 13 分钟里空转 2170 次
      // （约 2.8 次/秒），把 max_size=10 的连接池打满。
      //
      // 后果远不止本模块：连接池耗尽后所有取连接的操作都卡在
      // r2d2::Pool::get_timeout（10 秒），而 FFI 请求跑在 lib_dispatch 的
      // LocalSet【单线程】执行器上，一旦阻塞，整个 Dart↔Rust 通道全部排队 ——
      // 表现为中间栏一直转圈、断网也无法恢复、连本地私有空间都打不开。
      // sample 采样已确认卡点：
      //   get_view_pb → get_active_user_workspace → UserDB::get_connection
      //   → r2d2::Pool::get_timeout → __psynch_cvwait
      //
      // 修复：给补跑加上限，且失败时直接结束本次刷新。
      // 失败说明网络/后端此刻不可用，立刻重试没有意义，只会空转；等下一次
      // 刷新事件（外部有轮询与通知驱动）再来即可，不会漏掉权限变更。
      const maxCoalescedRounds = 3;
      var rounds = 0;
      var lastRoundFailed = false;

      do {
        _refreshAccessLevelAgain = false;
        rounds++;
        final accessLevel = await repository.getAccessLevel(
      view.id,
      workspaceId: view.hasWorkspaceId() ? view.workspaceId : null,
    );
        if (isClosed) {
          return;
        }

        lastRoundFailed = false;
        final newAccessLevel = accessLevel.fold(
          (accessLevel) => accessLevel,
          (error) {
            Log.warn('[PageAccessLevel] getAccessLevel failed: $error');
            lastRoundFailed = true;
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
        if (lastRoundFailed) {
          // 本轮失败：不再补跑。丢弃已排队的合并标记，等下一次刷新事件。
          if (_refreshAccessLevelAgain) {
            Log.warn(
              '[PageAccessLevel] 本轮获取失败，放弃本次合并补跑，'
              '等待下一次刷新事件（避免离线时高频空转耗尽数据库连接池）',
            );
          }
          break;
        }

        if (rounds >= maxCoalescedRounds && _refreshAccessLevelAgain) {
          // 达到补跑上限仍有新请求积压：说明刷新事件到达频率高于处理速度，
          // 继续补跑只会无限循环。留到下一次事件处理。
          Log.warn(
            '[PageAccessLevel] 合并补跑达到上限($maxCoalescedRounds)，'
            '本次结束，剩余请求留待下一次刷新事件',
          );
          break;
        }
      } while (_refreshAccessLevelAgain && !isClosed);
    } finally {
      _isRefreshingAccessLevel = false;
      _refreshAccessLevelAgain = false;
    }
  }
}

import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy/plugins/util.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_room_service.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_data_service.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_mirror_service.dart';
import 'package:appflowy/plugins/whiteboard/application/whiteboard_space_util.dart';
import 'package:appflowy/plugins/whiteboard/presentation/offline_whiteboard_mirror_page.dart';
import 'package:appflowy/plugins/whiteboard/presentation/remote_whiteboard_page.dart';
import 'package:appflowy/plugins/whiteboard/whiteboard.dart';
import 'package:appflowy/workspace/presentation/home/page_stack_visibility.dart';

/// 协作白板 room 服务（xm-arts）主机，用于离线可达性轻量探测。
const String _kRoomHost = 'https://xm-arts.xiaomabiji.com/';

class WhiteboardRouter extends StatefulWidget {
  const WhiteboardRouter({
    super.key,
    required this.notifier,
    required this.onViewChanged,
  });

  final ViewPluginNotifier notifier;
  final Function(ViewPB) onViewChanged;

  /// 使某个白板的空间归属缓存失效。**跨私有↔协作移动后必须调用**，
  /// 说明见 [_WhiteboardRouterState.invalidateSpaceTypeCache]。
  static void invalidateSpaceTypeCache(String viewId) =>
      _WhiteboardRouterState.invalidateSpaceTypeCache(viewId);

  @override
  State<WhiteboardRouter> createState() => _WhiteboardRouterState();
}

class _WhiteboardRouterState extends State<WhiteboardRouter> {
  String? _roomId;
  String? _roomKey;
  bool _isFetching = false;
  // 是否属于私有空间：
  // - true  私有空间白板 -> 始终走 B 套本地 collab（本地权威 + 静默云备份），忽略 room；
  // - false 协作空间白板 -> 维持现状（有 room 走 RemoteWhiteboardPage）；
  // - null  尚未判定完成（判定完成前先渲染 B 套占位，避免空白转圈）。
  bool? _isPrivateSpace;

  // room 服务（xm-arts）是否可达：
  // - null  尚未探测完成（协作空间下探测完成前先渲染 B 套占位）；
  // - true  可达 -> 走现状 A 套 room（可编辑），在线协作零改动；
  // - false 不可达 -> 若有本地镜像则走离线只读镜像页，否则仍尝试在线（不误判）。
  bool? _roomReachable;
  // 断网时本地是否存在可用镜像（决定是否切「离线只读」）。
  bool _hasMirror = false;

  // 空间归属本地缓存，避免每次打开白板重新查询
  static final Map<String, bool> _spaceTypeCache = {};

  /// 使某个白板的空间归属缓存失效。**跨私有↔协作移动后必须调用。**
  ///
  /// 这份缓存只写不删会造成一个很隐蔽的故障：把白板从私有区移到协作区后，
  /// 操作者本机的缓存仍是「私有」，路由于是继续渲染 B 套本地页 —— 他之后的
  /// 笔迹写进本地 collab，而不是 room；另一端没有这份缓存，解析出「协作」并
  /// 走 RemoteWhiteboardPage，只看得到迁移时推进 room 的那批初始内容。
  ///
  /// 表现就是「双方都能看到初始内容，但后续新增彼此都看不见」——两边各写各的
  /// 存储，看起来像实时协作坏了，实际是操作者压根没挂上 room。
  static void invalidateSpaceTypeCache(String viewId) {
    if (_spaceTypeCache.remove(viewId) != null) {
      Log.info('🧹 [WhiteboardRouter] 已清除空间归属缓存: $viewId');
    }
  }

  // room 可达性探测结果缓存（30s TTL）
  static bool? _cachedRoomReachable;
  static DateTime? _cachedRoomReachableTime;
  static const Duration _roomReachableCacheTtl = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    Log.info(
        '🚀 [WhiteboardRouter] initState called for view: ${widget.notifier.view.id}');
    _resolveSpaceThenFetch(widget.notifier.view);
  }

  @override
  void dispose() {
    Log.info(
        '💀 [WhiteboardRouter] dispose called for view: ${widget.notifier.view.id}');
    Log.info(
        '💀 [WhiteboardRouter] Disposing with roomId: $_roomId, roomKey: $_roomKey');
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant WhiteboardRouter oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 【卡顿修复 2026-07-18】此处原有一条无条件 Log.info。白板页在绘制期间会被父级
    // 频繁重建（日志实测 188 次/会话，且 oldView==newView 即视图并未变化），每条日志
    // 都要经 FFI 转到 Rust 并落盘，白白占用绘制帧时间。改为只在视图真正切换时记录。
    if (oldWidget.notifier.view.id != widget.notifier.view.id) {
      Log.info(
        '🔄 [WhiteboardRouter] View changed, resetting roomId/roomKey: '
        '${oldWidget.notifier.view.id} → ${widget.notifier.view.id}',
      );
      _roomId = null;
      _roomKey = null;
      _isPrivateSpace = null;
      _roomReachable = null;
      _hasMirror = false;
      _resolveSpaceThenFetch(widget.notifier.view);
    }
  }

  /// 先判定白板所属空间，再决定是否拉取/生成 room。
  ///
  /// 私有空间白板：始终走 B 套本地 collab（本地权威 + 静默云备份），
  /// 不建 room、不连 xm-arts，因此完全跳过 room 拉取与自动生成逻辑。
  /// 协作空间白板：维持现状，正常拉取/生成 room。
  Future<void> _resolveSpaceThenFetch(ViewPB view) async {
    // 优先查本地缓存，避免每次打开白板重新执行空间归属查询
    final cachedPrivate = _spaceTypeCache[view.id];
    if (cachedPrivate != null) {
      if (!mounted) return;
      setState(() => _isPrivateSpace = cachedPrivate);

      if (cachedPrivate) {
        Log.info('🔒 [WhiteboardRouter] 私有空间白板（缓存命中），立即渲染 B 套: ${view.id}');
        return;
      }
      // 协作空间：跳过空间判定直接拉 room
      Log.info('🤝 [WhiteboardRouter] 协作空间白板（缓存命中），直接拉取 room: ${view.id}');
      await _tryFetchRoomInfo(view);
      await _resolveRoomReachability(view);
      return;
    }

    bool isPrivate = false;
    try {
      isPrivate = await isViewInPrivateSpace(view);
    } catch (e) {
      Log.warn('⚠️ [WhiteboardRouter] 判定空间失败，按协作空间处理: $e');
      isPrivate = false;
    }

    // 写入缓存
    _spaceTypeCache[view.id] = isPrivate;

    if (!mounted) return;
    setState(() => _isPrivateSpace = isPrivate);

    if (isPrivate) {
      Log.info(
        '🔒 [WhiteboardRouter] 私有空间白板，走本地 collab（B 套），忽略 room: ${view.id}',
      );
      return;
    }

    Log.info(
      '🤝 [WhiteboardRouter] 协作空间白板，维持 room 流程: ${view.id}',
    );
    await _tryFetchRoomInfo(view);
    await _resolveRoomReachability(view);
  }

  /// 探测 room 服务可达性 + 本地镜像可用性，决定协作白板的渲染分支。
  ///
  /// 可达 -> A 套 room（可编辑，在线协作零改动）；
  /// 不可达且有镜像 -> 离线只读镜像页；
  /// 不可达且无镜像 -> 仍尝试在线（不误判）。
  Future<void> _resolveRoomReachability(ViewPB view) async {
    // 优先使用缓存结果，避免频繁切换白板时重复 3s 探测
    final cachedResult = _validCachedReachability();
    if (cachedResult != null) {
      if (!mounted) return;
      setState(() => _roomReachable = cachedResult);
      Log.info(
          '📶 [WhiteboardRouter] room 可达性（缓存命中）=$cachedResult, view=${view.id}');
      return;
    }

    final reachable = await _probeRoomReachable();
    // 缓存探测结果
    _cachedRoomReachable = reachable;
    _cachedRoomReachableTime = DateTime.now();

    // 仅在不可达时才检查本地镜像，节省 IO。
    final hasMirror =
        reachable ? false : await WhiteboardMirrorService().hasMirror(view.id);

    if (!mounted) return;
    setState(() {
      _roomReachable = reachable;
      _hasMirror = hasMirror;
    });
    Log.info(
      '📶 [WhiteboardRouter] room 可达性=$reachable, 本地镜像=$hasMirror, view=${view.id}',
    );
  }

  /// 返回 TTL 内有效的缓存可达性结果；过期返回 null。
  static bool? _validCachedReachability() {
    if (_cachedRoomReachable == null || _cachedRoomReachableTime == null) {
      return null;
    }
    if (DateTime.now().difference(_cachedRoomReachableTime!) >
        _roomReachableCacheTtl) {
      _cachedRoomReachable = null;
      _cachedRoomReachableTime = null;
      return null;
    }
    return _cachedRoomReachable;
  }

  /// 轻量探测 room 服务（xm-arts）是否可达。
  ///
  /// 先看系统连通性（none 直接判离线），再对 room 主机发一次带超时的 HEAD，
  /// 任何 HTTP 响应（含 4xx/5xx）都视为「服务可达」；超时/连接错误视为「离线」。
  /// 探测是只读的旁路操作，绝不触碰 room 数据。
  Future<bool> _probeRoomReachable() async {
    try {
      final conn = await Connectivity().checkConnectivity();
      if (conn == ConnectivityResult.none) {
        Log.info('[WhiteboardRouter] connectivity=none，判定 room 离线');
        return false;
      }
    } catch (e) {
      Log.warn('[WhiteboardRouter] connectivity 检查异常(忽略): $e');
    }

    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
      final request = await client
          .headUrl(Uri.parse(_kRoomHost))
          .timeout(const Duration(seconds: 3));
      final response =
          await request.close().timeout(const Duration(seconds: 3));
      await response.drain<void>();
      return true;
    } catch (e) {
      Log.info('[WhiteboardRouter] xm-arts 探测失败，判定离线: $e');
      return false;
    } finally {
      client?.close(force: true);
    }
  }

  /// 后台对账：确认服务端也存有本地这份 room，缺失则补写。
  ///
  /// 创建白板时那次写入可能因断网/超时失败。失败后本地仍有 room，之后每次打开
  /// 都走本地命中直接返回，服务端便永远是空的 —— 其他协作者取不到 room，只能
  /// 各自新建房间，表现为「各看各的」。这里在快路径之外补上一次修复机会。
  ///
  /// 只在服务端确实缺失时才写，不会覆盖别人已经写好的 room。
  Future<void> _reconcileRoomToServer(
    String viewId,
    String roomId,
    String roomKey,
  ) async {
    try {
      final data = await WhiteboardDataService().loadWhiteboardData(viewId);
      final existingId = data['roomId']?.toString() ?? '';
      if (existingId.isNotEmpty) {
        return;
      }
      final saved = await WhiteboardDataService().saveWhiteboardData(
        viewId,
        {'roomId': roomId, 'roomKey': roomKey},
        source: 'room-reconcile',
      );
      Log.info(
        '🔧 [WhiteboardRouter] 服务端缺 room，已补写 roomId=$roomId, view=$viewId, saved=$saved',
      );
    } catch (e) {
      Log.warn('⚠️ [WhiteboardRouter] room 对账失败（不影响本次渲染）: $e');
    }
  }

  Future<void> _tryFetchRoomInfo(ViewPB view) async {
    Log.debug('🔍 [WhiteboardRouter] Initial view: id=${view.id}');

    if (_isFetching) return;
    setState(() => _isFetching = true);

    try {
      final room = await WhiteboardRoomService.getRoom(view.id);

      if (room != null) {
        Log.debug(
            '🟢 [WhiteboardRouter] Found room in local storage: roomId=${room.roomId}');
        setState(() {
          _roomId = room.roomId;
          _roomKey = room.roomKey;
        });
        // 本地命中即刻渲染（快路径不变），同时在后台确认服务端也有这份 room。
        // 创建时那次写入若失败过，这里补写 —— 否则其他协作者永远取不到，
        // 会各自开出新房间。不阻塞渲染。
        unawaited(_reconcileRoomToServer(view.id, room.roomId, room.roomKey));
        return;
      }

      // 本地没有 room 时，**必须先问服务端**，不能直接生成新的。
      //
      // roomId/roomKey 是协作双方唯一的共同凭据（xm-arts 的
      // #room=<roomId>,<roomKey>）。它只在创建者本机有一份，其他协作者本地
      // 一定是空的 —— 只能从服务端取。若跳过这一步直接生成新 room，
      // 每个协作者都会开出各自的房间，表现为「只看得到自己的内容」。
      final whiteboardData =
          await WhiteboardDataService().loadWhiteboardData(view.id);
      final serverRoomId = whiteboardData['roomId']?.toString() ?? '';
      final serverRoomKey = whiteboardData['roomKey']?.toString() ?? '';

      if (serverRoomId.isNotEmpty && serverRoomKey.isNotEmpty) {
        Log.info(
          '🟢 [WhiteboardRouter] 从服务端取到 room: roomId=$serverRoomId, view=${view.id}',
        );
        // 落到本地，下次直接命中，省去一次网络往返。
        await WhiteboardRoomService.saveRoom(
          view.id,
          serverRoomId,
          serverRoomKey,
        );
        if (!mounted) return;
        setState(() {
          _roomId = serverRoomId;
          _roomKey = serverRoomKey;
        });
        return;
      }

      // 本地和服务端都没有 —— 这才是真正的新白板，由本端创建 room。
      Log.debug(
          '🟡 [WhiteboardRouter] No room found for view ${view.id}, generating new one');
      final newRoomId = WhiteboardRoomService.generateRoomId();
      final newRoomKey = WhiteboardRoomService.generateRoomKey();

      Log.info(
          '🆕 [WhiteboardRouter] Generated NEW roomId=$newRoomId, roomKey=$newRoomKey for view ${view.id}');

      await WhiteboardRoomService.saveRoom(view.id, newRoomId, newRoomKey);
      Log.info(
          '✅ [WhiteboardRouter] Saved room to local storage: viewId=${view.id}, roomId=$newRoomId');

      // room 必须落到服务端 —— 这是其他协作者唯一能拿到它的地方。
      // 这里**等待写入完成**：它每个白板只发生一次（创建时），不影响后续打开
      // 的速度；而写丢一次的代价是这个白板从此无法协作。
      final saved = await WhiteboardDataService().saveWhiteboardData(
        view.id,
        {
          'roomId': newRoomId,
          'roomKey': newRoomKey,
        },
        source: 'room-init',
      );
      if (saved) {
        Log.info(
            '✅ [WhiteboardRouter] Room info synced to server: roomId=$newRoomId');
      } else {
        Log.error(
          '❌ [WhiteboardRouter] room 未能写入服务端，其他协作者将取不到该白板的 room：view=${view.id}。'
          '下次打开会由 _reconcileRoomToServer 补写。',
        );
      }

      if (!mounted) return;
      setState(() {
        _roomId = newRoomId;
        _roomKey = newRoomKey;
      });
    } catch (e) {
      Log.error('❌ [WhiteboardRouter] Error fetching/generating room: $e');
    } finally {
      setState(() => _isFetching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 【D3D 资源累积根因修复 2026-07-20】本标签转入后台（IndexedStack 非激活项）时，
    // 主动卸载整个白板子树，释放 WebView2 宿主与其独占的 D3D11 设备。
    //
    // 背景：HomeStack 对所有标签 wantKeepAlive，后台白板的 WebView 不销毁；
    // 崩溃转储（PonyNotes.exe.28208.dmp，2026-07-20 闪退）实测十几个后台白板
    // 累积出 108 条显卡驱动线程（全进程 244 线程），并扩大了引擎光栅线程
    // ExternalTextureD3d::PopulateTexture 的销毁竞态窗口（0xC0000409/0x7 闪退）。
    //
    // 数据安全：TabsBloc 在 selectTab 等事件 emit 之前已 await
    // WhiteboardExitFlush.flushAll()（见 tabs_bloc.dart），协作白板的最后编辑
    // 在卸载前已推送；本地（B 套）白板由 collab 随编辑持续落盘，卸载即安全。
    // 代价：切回该标签时白板重新加载（走既有 initData 链路，与重新打开文档一致）。
    if (!PageStackVisibility.of(context)) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<ViewPB>(
      valueListenable: widget.notifier.viewNotifier,
      builder: (context, view, child) {
        final placeholderColor = Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF121212)
            : Colors.white;
        // 空间归属未判定完 —— 此时**还不知道**该挂哪一套，只能渲染中性占位。
        //
        // 曾经这里对 `_isPrivateSpace == null` 也直接渲染 B 套本地页以避免
        // 空白转圈，但 B 套是本地 collab、不是协作 room：协作空间白板一旦在
        // 判定窗口内被挂上 B 套，用户这段时间的笔迹就落进本地，进不了 room，
        // 别人自然看不到。渐进渲染不能以「可能挂错套」为代价。
        //
        // 空间归属有 _spaceTypeCache，重复打开时是同步命中的，占位窗口极短。
        if (_isPrivateSpace == null) {
          return ColoredBox(
            color: placeholderColor,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        // 协作空间白板：room 可达性探测完成前同样只渲染占位，绝不先挂 B 套。
        if (_isPrivateSpace == false && _roomReachable == null) {
          Log.debug(
            '⏳ [WhiteboardRouter] 协作空间等待 room 可达性探测: view=${view.id}',
          );
          return ColoredBox(
            color: placeholderColor,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        // 私有空间白板：始终渲染 B 套 WhiteboardPage（本地 collab + 静默云备份），忽略 room。
        if (_isPrivateSpace == true) {
          Log.debug(
              '🔒 [WhiteboardRouter] 私有空间，使用本地 WhiteboardPage（B 套）: ${view.id}');
          return WhiteboardPage(
            key: ValueKey('whiteboard_page_${view.id}'),
            view: view,
            onViewChanged: widget.onViewChanged,
          );
        }
        // 断网且本地有镜像：切「离线只读镜像」页（禁止编辑，仅浏览）。
        // 本页无任何写回路径，镜像绝不上传/覆盖 room。
        if (_roomReachable == false && _hasMirror) {
          Log.info(
            '📴 [WhiteboardRouter] room 不可达且有本地镜像，进入离线只读: ${view.id}',
          );
          return OfflineWhiteboardMirrorPage(
            key: ValueKey('offline_mirror_${view.id}'),
            view: view,
          );
        }
        // 可达（或离线但无镜像，不误判）：维持现状 A 套 room。
        // 有 room 走 RemoteWhiteboardPage（A 套），否则回退 B 套。
        if (_roomId != null && _roomKey != null) {
          Log.debug(
              '🟢 [WhiteboardRouter] Using RemoteWhiteboardPage: roomId=$_roomId, roomKey=$_roomKey');
          return RemoteWhiteboardPage(
            key: ValueKey('remote_whiteboard_page_${view.id}'),
            view: view,
            roomId: _roomId!,
            roomKey: _roomKey!,
          );
        } else {
          Log.debug(
              '🔵 [WhiteboardRouter] Using WhiteboardPage: roomId=$_roomId, roomKey=$_roomKey');
          return WhiteboardPage(
            key: ValueKey('whiteboard_page_${view.id}'),
            view: view,
            onViewChanged: widget.onViewChanged,
          );
        }
      },
    );
  }
}

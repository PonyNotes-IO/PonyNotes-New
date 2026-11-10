import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Transport carries pi events unchanged; the SDK remains authoritative for context.
class AgentTransport {
  final _records = StreamController<Map<String, dynamic>>.broadcast();
  Process? _process;
  WebSocket? _socket;
  bool _closing = false;
  int _generation = 0;
  Stream<Map<String, dynamic>> get records => _records.stream;

  Future<void> connect({
    required String dataDirectory,
    String? artifactDirectory,
    String remoteUrl = '',
    String token = '',
  }) async {
    _closing = false;
    final generation = ++_generation;
    void fail(Object error) {
      if (generation == _generation) _failed(error);
    }

    void read(String record) {
      if (generation == _generation) _read(record);
    }

    if (remoteUrl.isNotEmpty) {
      final uri = Uri.parse(remoteUrl);
      if (uri.scheme != 'wss' &&
          !(uri.scheme == 'ws' &&
              ['127.0.0.1', 'localhost', '::1'].contains(uri.host))) {
        throw StateError('远端执行器必须使用 wss://，本机调试可使用 ws://localhost');
      }
      _socket = await WebSocket.connect(
        remoteUrl,
        headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
      ).then((socket) {
        if (generation != _generation) {
          unawaited(socket.close());
          throw StateError('连接已取消');
        }
        return socket;
      }).timeout(const Duration(seconds: 15));
      _socket!.pingInterval = const Duration(seconds: 15);
      _socket!.listen(
        (data) => read(data as String),
        onError: fail,
        onDone: () => fail(StateError('执行器连接已断开；请确认已提交操作的结果')),
      );
      return;
    }
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      throw StateError('请在 Agent 设置中配置远端执行器');
    }
    final executableDir = p.dirname(Platform.resolvedExecutable);
    final candidates = [
      p.join(executableDir, 'agent-runtime'),
      p.join(executableDir, 'data', 'agent-runtime'),
      p.normalize(p.join(executableDir, '..', 'Resources', 'agent-runtime')),
      p.normalize(p.join(Directory.current.path, '..', 'agent-runtime')),
    ];
    String? runtime;
    for (final candidate in candidates) {
      if (await File(p.join(candidate, 'src', 'stdio.mjs')).exists()) {
        runtime = candidate;
        break;
      }
    }
    if (runtime == null) throw StateError('安装包缺少 Agent 运行时，请重新安装包含 Agent 的版本');
    final bundledNode =
        p.join(runtime, Platform.isWindows ? 'node.exe' : 'node');
    final node = await File(bundledNode).exists() ? bundledNode : 'node';
    _process = await Process.start(
      node,
      [
        p.join(runtime, 'src', 'stdio.mjs'),
        dataDirectory,
        if (artifactDirectory != null) artifactDirectory,
      ],
      workingDirectory: runtime,
    );
    _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(read, onError: fail);
    // Diagnostics are deliberately not included in the transcript: providers can echo credentials.
    unawaited(_process!.stderr.drain<void>());
    unawaited(
      _process!.exitCode.then((_) => fail(StateError('本机 Agent 已退出，请重新连接'))),
    );
  }

  void _read(String value) {
    if (_closing || _records.isClosed) return;
    try {
      _records.add(Map<String, dynamic>.from(jsonDecode(value) as Map));
    } catch (e) {
      _failed(StateError('执行器返回了无效的数据：$e'));
    }
  }

  void _failed(Object error) {
    if (!_closing && !_records.isClosed) _records.addError(error);
  }

  void send(Map<String, dynamic> record) {
    final encoded = jsonEncode(record);
    if (_socket != null) {
      _socket!.add(encoded);
    } else if (_process != null) {
      _process!.stdin.writeln(encoded);
    } else {
      throw StateError('Agent 尚未连接');
    }
  }

  Future<void> close() async {
    _closing = true;
    ++_generation;
    final socket = _socket;
    _socket = null;
    final process = _process;
    _process = null;
    try {
      await socket?.close().timeout(const Duration(seconds: 3));
    } catch (_) {/* A disconnected peer cannot acknowledge shutdown. */}
    if (process != null) {
      try {
        await process.stdin.close();
      } catch (_) {/* The child may already have exited. */}
      try {
        await process.exitCode.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        if (Platform.isWindows) {
          await Process.run(
            'taskkill.exe',
            ['/PID', '${process.pid}', '/T', '/F'],
          );
        } else {
          process.kill();
        }
      }
    }
  }

  Future<void> dispose() async {
    await close();
    await _records.close();
  }
}

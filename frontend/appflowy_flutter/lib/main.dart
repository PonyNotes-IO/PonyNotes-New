import 'dart:async';
import 'dart:io';
import 'package:scaled_app/scaled_app.dart';
import 'package:appflowy_backend/log.dart';

import 'startup/startup.dart';

// 全局变量用于存储初始 deep link
String? _initialDeepLink;

// 单实例锁文件路径
String get _lockFilePath {
  final appData = Platform.environment['APPDATA'] ?? 
                  Platform.environment['LOCALAPPDATA'] ?? 
                  '.';
  return '$appData\\PonyNotes\\instance.lock';
}

// 传递 deep link 的文件路径
String get _deepLinkPipePath {
  final appData = Platform.environment['APPDATA'] ?? 
                  Platform.environment['LOCALAPPDATA'] ?? 
                  '.';
  return '$appData\\PonyNotes\\deep_link.txt';
}

// 检查是否已有实例运行
Future<bool> _checkSingleInstance() async {
  final lockFile = File(_lockFilePath);
  final dir = lockFile.parent;
  
  // 确保目录存在
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  
  try {
    // 检查锁文件是否存在
    if (await lockFile.exists()) {
      Log.info('Single instance: Another instance is running (lock file exists)');
      return false;
    }
    
    // 创建锁文件
    await lockFile.writeAsString(DateTime.now().millisecondsSinceEpoch.toString());
    Log.info('Single instance: Created lock file');
    return true;
  } catch (e) {
    // 锁文件创建失败，说明有其他实例在运行
    Log.info('Single instance: Another instance is running (error: $e)');
    return false;
  }
}

// 将 deep link 传递给已运行的实例
Future<void> _passDeepLinkToRunningInstance(String url) async {
  final pipeFile = File(_deepLinkPipePath);
  final dir = pipeFile.parent;
  
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  
  // 写入 deep link URL
  await pipeFile.writeAsString(url);
  Log.info('Single instance: Wrote deep link to pipe: $url');
  
  // 尝试通过 Windows 消息通知已运行的实例
  // 这里使用简单的轮询机制
}

// 检查是否有待处理的 deep link（用于已运行的实例）
Future<String?> _checkForPendingDeepLink() async {
  final pipeFile = File(_deepLinkPipePath);
  
  if (await pipeFile.exists()) {
    try {
      final content = await pipeFile.readAsString();
      if (content.startsWith('ponynotes://')) {
        Log.info('Single instance: Found pending deep link: $content');
        // 清空文件
        await pipeFile.writeAsString('');
        return content;
      }
    } catch (e) {
      Log.error('Single instance: Error reading pipe file: $e');
    }
  }
  return null;
}

// 清理锁文件
Future<void> _cleanupLockFile() async {
  final lockFile = File(_lockFilePath);
  try {
    if (await lockFile.exists()) {
      await lockFile.delete();
      Log.info('Single instance: Deleted lock file');
    }
  } catch (e) {
    Log.error('Single instance: Error deleting lock file: $e');
  }
}

Future<void> main(List<String> args) async {
  // Windows 单实例检测 - 先打印收到的参数
  if (Platform.isWindows) {
    Log.info('DeepLink: ==== App started with args: $args ====');
    
    // Windows 上可能通过 Windows 消息传递 URL，不在命令行参数中
    // 尝试从环境变量获取（某些情况下会设置）
    final envUrl = Platform.environment['APP_URI'];
    if (envUrl != null) {
      Log.info('DeepLink: Got URL from environment: $envUrl');
    }
    
    final isFirstInstance = await _checkSingleInstance();
    
    if (!isFirstInstance) {
      // 已有实例在运行，将 deep link 传递给它，然后退出
      if (args.isNotEmpty) {
        final url = args.first;
        if (url.startsWith('ponynotes://')) {
          await _passDeepLinkToRunningInstance(url);
        }
      }
      
      // 等待一下让主实例处理
      await Future.delayed(const Duration(milliseconds: 500));
      Log.info('Single instance: Exiting, deep link passed to running instance');
      exit(0);
    }
    
    // 第一个实例：检查是否有待处理的 deep link
    final pendingUrl = await _checkForPendingDeepLink();
    if (pendingUrl != null) {
      // 通过全局变量传递给 deep link 处理
      _initialDeepLink = pendingUrl;
    }
  }

  ScaledWidgetsFlutterBinding.ensureInitialized(
    scaleFactor: (_) => 1.0,
  );

  // 注意：已移除RawKeyboard诊断代码
  // RawKeyboard API已被Flutter弃用，与新的HardwareKeyboard系统冲突
  // 会导致键盘事件状态不同步，出现"KeyDownEvent but key already pressed"错误

  // 处理 deep link 命令行参数（Windows URL 协议启动时传入）
  if (args.isNotEmpty) {
    final url = args.first;
    if (url.startsWith('ponynotes://')) {
      Log.info('DeepLink: Received initial URL from command line: $url');
      // 通过全局变量传递，供 AppFlowyCloudDeepLink 读取
      _initialDeepLink = url;
    }
  }

  await runAppFlowy();
  
  // 应用退出时清理锁文件
  await _cleanupLockFile();
}

// 获取初始 deep link 的全局函数
String? getInitialDeepLink() => _initialDeepLink;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-storage/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fixnum/fixnum.dart';

import '../startup.dart';

class FileStorageTask extends LaunchTask {
  const FileStorageTask();

  @override
  Future<void> initialize(LaunchContext context) async {
    await super.initialize(context);

    context.getIt.registerSingleton(
      FileStorageService(),
      dispose: (service) async => service.dispose(),
    );
  }
}

class FileStorageService {
  FileStorageService() {
    _port.handler = _controller.add;
    _subscription = _controller.stream.listen(
      (event) {
        final fileProgress = FileProgress.fromJsonString(event);
        if (fileProgress != null) {
          Log.debug(
            "FileStorageService upload file: ${fileProgress.fileUrl} ${fileProgress.progress}",
          );

          if (fileProgress.error != null) {
            _showUploadErrorToast(fileProgress.error!);
          }

          final notifier = _notifierList[fileProgress.fileUrl];
          if (notifier != null) {
            notifier.value = fileProgress;
          }
        }
      },
    );

    if (!integrationMode().isTest) {
      final payload = RegisterStreamPB()
        ..port = Int64(_port.sendPort.nativePort);
      FileStorageEventRegisterStream(payload).send();
    }
  }

  final Map<String, AutoRemoveNotifier<FileProgress>> _notifierList = {};
  final RawReceivePort _port = RawReceivePort();
  final StreamController<String> _controller = StreamController.broadcast();
  late StreamSubscription<String> _subscription;
  DateTime? _lastErrorToastTime;

  void _showUploadErrorToast(String errorMsg) {
    final now = DateTime.now();
    if (_lastErrorToastTime != null &&
        now.difference(_lastErrorToastTime!).inSeconds < 5) {
      return;
    }
    _lastErrorToastTime = now;

    final String displayMessage;
    final lowerMsg = errorMsg.toLowerCase();
    if (lowerMsg.contains('single upload limit') ||
        lowerMsg.contains('single file size') ||
        lowerMsg.contains('exceeds single')) {
      displayMessage =
          LocaleKeys.sideBar_singleFileSizeLimitExceeded.tr();
    } else if (lowerMsg.contains('storage limit') ||
        lowerMsg.contains('plan limit') ||
        lowerMsg.contains('total storage')) {
      displayMessage =
          LocaleKeys.sideBar_storageLimitDialogTitle.tr();
    } else {
      displayMessage =
          '${LocaleKeys.button_uploadFailed.tr()}: $errorMsg';
    }

    Log.error('[FileUpload] upload error: $errorMsg');
    showToastNotification(
      message: displayMessage,
      type: ToastificationType.error,
    );
  }

  AutoRemoveNotifier<FileProgress> onFileProgress({required String fileUrl}) {
    _notifierList.remove(fileUrl)?.dispose();

    final notifier = AutoRemoveNotifier<FileProgress>(
      FileProgress(fileUrl: fileUrl, progress: 0),
      notifierList: _notifierList,
      fileId: fileUrl,
    );
    _notifierList[fileUrl] = notifier;

    // Trigger the initial file state and sync it back to notifier immediately.
    // This avoids UI being stuck at 0 when stream events are missed.
    getFileState(fileUrl).then((result) {
      result.fold(
        (state) {
          final currentNotifier = _notifierList[fileUrl];
          if (currentNotifier != null) {
            currentNotifier.value = FileProgress(
              fileUrl: fileUrl,
              progress: state.isFinish ? 1.0 : 0.0,
            );
          }
        },
        (_) {},
      );
    });

    return notifier;
  }

  Future<FlowyResult<FileStatePB, FlowyError>> getFileState(String url) {
    final payload = QueryFilePB()..url = url;
    return FileStorageEventQueryFile(payload).send();
  }

  Future<void> dispose() async {
    // Copy first because each notifier dispose removes itself from the map.
    for (final notifier in _notifierList.values.toList()) {
      notifier.dispose();
    }

    await _controller.close();
    await _subscription.cancel();
    _port.close();
  }
}

class FileProgress {
  FileProgress({
    required this.fileUrl,
    required this.progress,
    this.error,
  });

  static FileProgress? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }

    try {
      if (json.containsKey('file_url') && json.containsKey('progress')) {
        return FileProgress(
          fileUrl: json['file_url'] as String,
          progress: (json['progress'] as num).toDouble(),
          error: json['error'] as String?,
        );
      }
    } catch (e) {
      Log.error('unable to parse file progress: $e');
    }
    return null;
  }

  // Method to parse a JSON string and return a FileProgress object or null
  static FileProgress? fromJsonString(String jsonString) {
    try {
      final Map<String, dynamic> jsonMap = jsonDecode(jsonString);
      return FileProgress.fromJson(jsonMap);
    } catch (e) {
      return null;
    }
  }

  final double progress;
  final String fileUrl;
  final String? error;
}

class AutoRemoveNotifier<T> extends ValueNotifier<T> {
  AutoRemoveNotifier(
    super.value, {
    required this.fileId,
    required Map<String, AutoRemoveNotifier<FileProgress>> notifierList,
  }) : _notifierList = notifierList;

  final String fileId;
  final Map<String, AutoRemoveNotifier<FileProgress>> _notifierList;

  @override
  void dispose() {
    _notifierList.remove(fileId);
    super.dispose();
  }
}

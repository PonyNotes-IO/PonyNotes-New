import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pb.dart';
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
            Log.error('[FileUpload] upload error: ${fileProgress.error}');
            showToastNotification(
              message: uploadFailureMessage(
                fileProgress.errorCode,
                fileProgress.error!,
              ),
              type: ToastificationType.error,
            );
          }

          for (final notifier
              in _notifierList[fileProgress.fileUrl]?.toList() ??
                  const <AutoRemoveNotifier<FileProgress>>[]) {
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

  final _notifierList = <String, Set<AutoRemoveNotifier<FileProgress>>>{};
  final RawReceivePort _port = RawReceivePort();
  final StreamController<String> _controller = StreamController.broadcast();
  late StreamSubscription<String> _subscription;

  AutoRemoveNotifier<FileProgress> onFileProgress({required String fileUrl}) {
    final initial = FileProgress(fileUrl: fileUrl, progress: -1);
    final notifier = AutoRemoveNotifier<FileProgress>(
      initial,
      fileId: fileUrl,
      notifierList: _notifierList,
    );
    (_notifierList[fileUrl] ??= {}).add(notifier);
    refreshFileProgress(notifier);
    return notifier;
  }

  Future<void> refreshFileProgress(
    AutoRemoveNotifier<FileProgress> notifier,
  ) async {
    final previous = notifier.value;
    final url = previous.fileUrl;
    final result = await getFileState(url);
    if (_notifierList[url]?.contains(notifier) != true ||
        !identical(notifier.value, previous)) {
      return;
    }
    notifier.value = result.fold(
      (state) => FileProgress(
        fileUrl: url,
        progress: state.isFinish
            ? 1
            : state.errorCode != 0 || state.errorMessage.isNotEmpty
                ? -1
                : 0,
        error: state.errorMessage.isEmpty ? null : state.errorMessage,
        errorCode: state.errorCode == 0 ? null : state.errorCode,
        uploadFailed: state.uploadFailed,
      ),
      (_) => FileProgress(
        fileUrl: url,
        progress: -1,
        errorCode: ErrorCode.NetworkError.value,
      ),
    );
  }

  Future<FlowyResult<FileStatePB, FlowyError>> getFileState(String url) {
    final payload = QueryFilePB()..url = url;
    return FileStorageEventQueryFile(payload).send();
  }

  Future<void> dispose() async {
    // Copy first because each notifier dispose removes itself from the map.
    for (final notifier in _notifierList.values.expand((set) => set).toList()) {
      notifier.dispose();
    }

    await _controller.close();
    await _subscription.cancel();
    _port.close();
  }
}

String uploadFailureMessage(int? code, String message) {
  if (code == ErrorCode.FileStorageLimitExceeded.value) {
    return 'document.plugins.file.uploadQuotaExceeded'.tr();
  }
  final lower = message.toLowerCase();
  if (code == ErrorCode.SingleUploadLimitExceeded.value ||
      lower.contains('exceeds single upload limit')) {
    final limit =
        RegExp(r'single upload limit\s+([0-9]+(?:\.[0-9]+)?)\s*(bytes|mb)')
            .firstMatch(lower);
    final amount = double.tryParse(limit?.group(1) ?? '');
    if (amount == null) {
      return 'document.plugins.file.uploadSizeUnknown'.tr();
    }
    final mib = limit?.group(2) == 'mb' ? amount : amount / (1024 * 1024);
    final value = mib >= 1024 ? mib / 1024 : mib;
    final number =
        value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1);
    return 'document.plugins.file.uploadSizeLimit'.tr(
      args: ['$number ${mib >= 1024 ? 'GB' : 'MB'}'],
    );
  }
  if (code == ErrorCode.PlanLimitExceeded.value ||
      lower.contains('storage limit')) {
    return 'document.plugins.file.uploadQuotaExceeded'.tr();
  }
  if (code == ErrorCode.NotEnoughPermissions.value ||
      code == ErrorCode.UserUnauthorized.value) {
    return 'document.plugins.file.uploadNoPermission'.tr();
  }
  if (code == ErrorCode.RecordNotFound.value) {
    return 'document.plugins.file.uploadUnavailable'.tr();
  }
  if (message == 'Local upload file is missing') {
    return 'document.plugins.file.uploadSourceMissing'.tr();
  }
  return LocaleKeys.button_uploadFailed.tr();
}

class FileProgress {
  FileProgress({
    required this.fileUrl,
    required this.progress,
    this.error,
    this.errorCode,
    this.uploadFailed = false,
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
          errorCode: json['error_code'] as int?,
          uploadFailed: json['error'] != null,
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
  final int? errorCode;
  final bool uploadFailed;

  bool get isReady => error == null && progress >= 1;
  bool get isWaitingForNetwork => errorCode == ErrorCode.NetworkError.value;
  bool get isMissing => errorCode == ErrorCode.RecordNotFound.value;
}

class AutoRemoveNotifier<T> extends ValueNotifier<T> {
  AutoRemoveNotifier(
    super.value, {
    required this.fileId,
    required Map<String, Set<AutoRemoveNotifier<T>>> notifierList,
  }) : _notifierList = notifierList;

  final String fileId;
  final Map<String, Set<AutoRemoveNotifier<T>>> _notifierList;

  @override
  void dispose() {
    final notifiers = _notifierList[fileId];
    notifiers?.remove(this);
    if (notifiers?.isEmpty == true) _notifierList.remove(fileId);
    super.dispose();
  }
}

import 'dart:math';

import 'package:appflowy_backend/log.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

const bool ponyNotesAutoExportDebugLogs = bool.fromEnvironment(
  'PONYNOTES_AUTO_EXPORT_DEBUG_LOGS',
);
const String _ponyNotesDiagnosticBuildLabel = String.fromEnvironment(
  'PONYNOTES_DIAGNOSTIC_BUILD_LABEL',
);
const String ponyNotesDebugLogExportDir = String.fromEnvironment(
  'PONYNOTES_DEBUG_LOG_EXPORT_DIR',
);

bool get ponyNotesDiagnosticBuildEnabled =>
    ponyNotesAutoExportDebugLogs || _ponyNotesDiagnosticBuildLabel.isNotEmpty;

String get ponyNotesDiagnosticBuildLabel =>
    _ponyNotesDiagnosticBuildLabel.isEmpty
        ? 'auto-export'
        : _ponyNotesDiagnosticBuildLabel;

void logDiagnosticMessage(String tag, String message) {
  if (!ponyNotesDiagnosticBuildEnabled) {
    return;
  }

  Log.info('[PonyNotesDiag][$tag] $message');
}

String? ponyNotesDiagnosticModuleFromMessage(String message) {
  final match = RegExp(r'\[PonyNotesDiag\]\[([^\]]+)\]').firstMatch(message);
  if (match == null) {
    return null;
  }

  return ponyNotesDiagnosticModuleFromIdentifier(match.group(1));
}

String? ponyNotesDiagnosticModuleFromIdentifier(String? identifier) {
  if (identifier == null || identifier.trim().isEmpty) {
    return null;
  }

  final normalized = identifier.trim().toLowerCase();
  if (normalized.contains('whiteboard') ||
      normalized.contains('excalidraw') ||
      normalized.contains('assetserver')) {
    return 'whiteboard';
  }

  if (normalized.contains('gridrefresh') ||
      normalized.contains('simple_table') ||
      normalized.contains('simpletable') ||
      normalized.contains('table') ||
      normalized.contains('database') ||
      normalized.contains('grid')) {
    return 'table';
  }

  if (normalized.contains('document')) {
    return 'document';
  }

  if (normalized.contains('image')) {
    return 'image';
  }

  if (normalized.contains('sync')) {
    return 'sync';
  }

  return null;
}

String ponyNotesDiagTraceId(String scene, [String? seed]) {
  final now = DateTime.now().microsecondsSinceEpoch;
  final random = Random().nextInt(0xFFFFF).toRadixString(16);
  final seedHash = seed == null ? '' : '-${seed.hashCode.toRadixString(16)}';
  return '$scene-$now-$random$seedHash';
}

String diagnosticRedactedUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) {
    return url;
  }

  final text = uri.toString();
  final queryIndex = text.indexOf('?');
  final fragmentIndex = text.indexOf('#');
  var cutIndex = text.length;
  if (queryIndex >= 0 && queryIndex < cutIndex) {
    cutIndex = queryIndex;
  }
  if (fragmentIndex >= 0 && fragmentIndex < cutIndex) {
    cutIndex = fragmentIndex;
  }

  return text.substring(0, cutIndex);
}

Map<String, Object?> diagnosticImageErrorFields(
  String location, {
  required String source,
  required Object error,
  StackTrace? stackTrace,
  bool isLocalPath = false,
}) {
  final fields = <String, Object?>{
    'source': source,
    if (isLocalPath)
      'requestPath': location
    else
      'requestUrl': diagnosticRedactedUrl(location),
    if (!isLocalPath) ...diagnosticSafeUrlFields(location),
    'errorType': error.runtimeType.toString(),
    'errorMessage': error.toString(),
  };

  final httpStatus = _diagnosticHttpStatusCode(error);
  if (httpStatus != null) {
    fields['httpStatus'] = httpStatus;
  }

  final errorUri = _diagnosticErrorUri(error);
  if (errorUri != null) {
    fields['errorUri'] = diagnosticRedactedUrl(errorUri.toString());
  }

  if (stackTrace != null) {
    fields['hasStackTrace'] = true;
  }

  return fields;
}

void logDiagnosticEvent(
  String scene,
  String stage,
  Map<String, Object?> fields, {
  bool warning = false,
  Object? error,
  StackTrace? stackTrace,
}) {
  if (!ponyNotesDiagnosticBuildEnabled) {
    return;
  }

  final fieldText = fields.entries
      .where((entry) => entry.value != null)
      .map((entry) => '${entry.key}=${_diagnosticValue(entry.value)}')
      .join(' ');
  final message = '[PonyNotesDiag][$scene] stage=$stage $fieldText';

  if (error != null) {
    Log.error(message, error, stackTrace);
  } else if (warning) {
    Log.warn(message);
  } else {
    Log.info(message);
  }
}

Map<String, Object?> diagnosticSafeUrlFields(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) {
    return const {
      'urlParseOk': false,
    };
  }

  return {
    'urlParseOk': true,
    'urlScheme': uri.scheme,
    'urlHost': uri.host,
    'urlPath': uri.path,
    'isFileStorage': uri.path.contains('/file_storage/'),
  };
}

int? _diagnosticHttpStatusCode(Object error) {
  if (error is HttpExceptionWithStatus) {
    return error.statusCode;
  }
  if (error is NetworkImageLoadException) {
    return error.statusCode;
  }
  return null;
}

Uri? _diagnosticErrorUri(Object error) {
  if (error is HttpExceptionWithStatus) {
    return error.uri;
  }
  if (error is NetworkImageLoadException) {
    return error.uri;
  }
  return null;
}

Object _diagnosticValue(Object? value) {
  if (value is String) {
    return value.replaceAll(RegExp(r'\s+'), '_');
  }
  return value ?? '';
}

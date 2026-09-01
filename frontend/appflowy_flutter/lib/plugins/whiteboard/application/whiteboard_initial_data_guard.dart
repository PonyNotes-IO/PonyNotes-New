import 'dart:convert';

class WhiteboardInitialDataGuard {
  const WhiteboardInitialDataGuard._();

  static bool isBlankScene(Map<String, dynamic> data) {
    return !_hasEntries(data['elements']) && !_hasEntries(data['files']);
  }

  static bool hasMeaningfulSceneChange(Map<String, dynamic> data) {
    return _hasEntries(data['elements']) || _hasEntries(data['files']);
  }

  static bool _hasEntries(dynamic value) {
    final decoded = _decodeJsonCollection(value);
    if (decoded is List) {
      return decoded.isNotEmpty;
    }
    if (decoded is Map) {
      return decoded.isNotEmpty;
    }
    return decoded != null;
  }

  static dynamic _decodeJsonCollection(dynamic value) {
    if (value is! String) {
      return value;
    }
    try {
      return jsonDecode(value);
    } catch (_) {
      return value.isEmpty ? null : value;
    }
  }
}

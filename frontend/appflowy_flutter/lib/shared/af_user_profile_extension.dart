import 'dart:convert';

import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';

extension UserProfilePBExtension on UserProfilePB {
  String? get authToken {
    return token.isEmpty ? null : token;
  }

  String? get authorizationAccessToken {
    return _normalizeAuthorizationAccessToken(token);
  }

  String get authorizationAccessTokenSource {
    return _detectAuthorizationAccessTokenSource(token);
  }
}

String? _normalizeAuthorizationAccessToken(String rawToken) {
  final normalized = _stripBearerPrefixAndQuotes(rawToken);
  if (normalized.isEmpty) {
    return null;
  }

  if (!normalized.startsWith('{')) {
    return normalized;
  }

  try {
    final decoded = jsonDecode(normalized);
    final accessToken = _extractAccessTokenFromEnvelope(decoded);
    if (accessToken == null || accessToken.isEmpty) {
      return null;
    }
    return _normalizeAuthorizationAccessToken(accessToken);
  } catch (_) {
    return null;
  }
}

String _detectAuthorizationAccessTokenSource(String rawToken) {
  final trimmed = rawToken.trim();
  if (trimmed.isEmpty) {
    return 'empty';
  }

  final normalized = _stripBearerPrefixAndQuotes(rawToken);
  if (!normalized.startsWith('{')) {
    if (trimmed.toLowerCase().startsWith('bearer ')) {
      return 'bearer_prefixed';
    }
    if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
      return 'quoted_raw';
    }
    return 'raw';
  }

  try {
    final decoded = jsonDecode(normalized);
    if (decoded is Map) {
      if (decoded['access_token'] is String) {
        return 'json.access_token';
      }

      final auth = decoded['auth'];
      if (auth is Map && auth['access_token'] is String) {
        return 'json.auth.access_token';
      }
    }
    return 'json.unknown';
  } catch (_) {
    return 'json.invalid';
  }
}

String? _extractAccessTokenFromEnvelope(dynamic value) {
  if (value is! Map) {
    return null;
  }

  final directAccessToken = value['access_token'];
  if (directAccessToken is String && directAccessToken.trim().isNotEmpty) {
    return directAccessToken;
  }

  final auth = value['auth'];
  if (auth is Map) {
    final nestedAccessToken = auth['access_token'];
    if (nestedAccessToken is String && nestedAccessToken.trim().isNotEmpty) {
      return nestedAccessToken;
    }
  }

  return null;
}

String _stripBearerPrefixAndQuotes(String token) {
  var normalized = token.trim();
  if (normalized.toLowerCase().startsWith('bearer ')) {
    normalized = normalized.substring(7).trim();
  }

  if (normalized.length >= 2 &&
      normalized.startsWith('"') &&
      normalized.endsWith('"')) {
    normalized = normalized.substring(1, normalized.length - 1).trim();
  }

  return normalized;
}

import 'dart:io';
import 'dart:typed_data';
import 'package:appflowy_backend/log.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/env/env.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';

/// File upload service for AppFlowy Cloud storage
class FileUploadService {
  static String? _cachedAccessToken;
  static int? _tokenExpiresAt;
  
  /// Upload file to AppFlowy Cloud storage and get URL
  /// Requires user to be logged in to AppFlowy Cloud
  /// Maximum file size: 50MB
  static Future<String> uploadFile(Uint8List fileBytes, String fileName) async {
    try {
      Log.info('Uploading file to AppFlowy Cloud: $fileName (${getFileSizeString(fileBytes.length)})');
      
      // Check file size first - maximum 50MB
      if (!isFileSizeValid(fileBytes.length)) {
        throw Exception('文件大小超过限制（最大50MB），当前文件大小：${getFileSizeString(fileBytes.length)}');
      }
      
      // Check if user is logged in first - required for file upload
      try {
        await _getAuthToken();
        Log.info('User is logged in, proceeding with file upload');
      } catch (e) {
        Log.error('User not logged in: $e');
        throw Exception('请先登录AppFlowy Cloud后再使用文件上传功能');
      }
      
      // Get current workspace
      final workspaceResult = await UserBackendService.getCurrentWorkspace();
      final workspace = workspaceResult.fold(
        (workspace) => workspace,
        (error) => throw Exception('无法获取当前工作区: $error'),
      );
      
      // Get AppFlowy Cloud base URL from DI container (includes port for dev environments)
      final baseUrl = _getCloudBaseUrl();
      final uri = Uri.parse(baseUrl);
      final String baseOrigin = _buildBaseOrigin(uri);
      
      // Use PUT method directly: PUT /api/file_storage/{workspace_id}/blob/{file_id}
      final workspaceId = workspace.id;
      final fileId = Uri.encodeComponent(fileName);
      final putUrl = '$baseOrigin/api/file_storage/$workspaceId/blob/$fileId';
      
      Log.info('Uploading file using PUT method: $putUrl');
      Log.info('Workspace ID: $workspaceId, File ID: $fileId');
      
      // Use PUT method to upload file
      final putReq = http.Request('PUT', Uri.parse(putUrl));
      putReq.headers.addAll({
        'Authorization': 'Bearer ${await _getAuthToken()}',
        'Content-Type': 'application/octet-stream',
        'Accept': 'application/json',
      });
      putReq.bodyBytes = fileBytes;
      
      final putResp = await _sendWithRetry(() => putReq.send(), onBeforeRetry: (attempt, code, body) {
        Log.warn('File upload (PUT) retry#$attempt due to ${code ?? 'network'} - ${body ?? ''}');
      });
      
      final putBody = await putResp.stream.bytesToString();
      Log.info('File upload (PUT) response: ${putResp.statusCode} - $putBody');
      
      if (putResp.statusCode == 200 || putResp.statusCode == 201) {
        // 检查响应体中是否包含错误信息
        if (putBody.isNotEmpty) {
          try {
            final data = jsonDecode(putBody);
            if (data is Map) {
              // 检查是否有错误代码
              // 后端返回的数字错误代码：1028 (FileStorageLimitExceeded), 1072 (PlanLimitExceeded)
              // 也可能返回字符串形式的错误代码
              final dynamic codeValue = data['code'];
              final errorMessage = data['message'] as String?;
              
              bool isStorageError = false;
              String? errorCodeStr;
              
              if (codeValue is int) {
                // 数字形式的错误代码
                errorCodeStr = codeValue.toString();
                if (codeValue == 1028 || codeValue == 1072) {
                  isStorageError = true;
                }
              } else if (codeValue is String) {
                // 字符串形式的错误代码
                errorCodeStr = codeValue;
                if (codeValue == 'PlanLimitExceeded' || codeValue == 'FileStorageLimitExceeded') {
                  isStorageError = true;
                }
              }
              
              if (isStorageError) {
                Log.error('File upload failed: Storage limit exceeded - $errorMessage');
                throw Exception('云空间容量不足: $errorMessage');
              } else if (errorCodeStr != null && errorCodeStr != 'ok' && errorCodeStr != 'success' && errorCodeStr != '0') {
                // 其他错误（code=0 是成功，AppFlowy Cloud API 约定 0 = Ok）
                Log.error('File upload returned error: $errorCodeStr - $errorMessage');
                throw Exception('文件上传失败: $errorMessage (code: $errorCodeStr)');
              }
              
              // 尝试获取文件 URL
              final fileUrl = data['url'] as String? ?? data['file_url'] as String? ?? data['link'] as String?;
              if (fileUrl != null && fileUrl.isNotEmpty) {
                Log.info('File uploaded successfully: $fileUrl');
                return fileUrl;
              }
            }
          } catch (e) {
            if (e.toString().contains('文件上传失败')) {
              rethrow;
            }
            // 如果解析失败，继续尝试构造 URL
          }
        }
        
        // Construct accessible URL (same as upload endpoint)
        final constructed = '$baseOrigin/api/file_storage/$workspaceId/blob/$fileId';
        Log.info('File uploaded successfully (constructed URL): $constructed');
        return constructed;
      }
      
      // 即使是非200/201状态码，也检查是否是存储限制错误
      if (putBody.isNotEmpty) {
        try {
          final data = jsonDecode(putBody);
          if (data is Map) {
            final dynamic codeValue = data['code'];
            final errorMessage = data['message'] as String?;
            
            bool isStorageError = false;
            if (codeValue is int && (codeValue == 1028 || codeValue == 1072)) {
              isStorageError = true;
            } else if (codeValue is String && 
                (codeValue == 'PlanLimitExceeded' || codeValue == 'FileStorageLimitExceeded')) {
              isStorageError = true;
            }
            
            if (isStorageError) {
              Log.error('File upload failed: Storage limit exceeded (status ${putResp.statusCode}) - $errorMessage');
              throw Exception('云空间容量不足: $errorMessage');
            }
          }
        } catch (e) {
          if (e.toString().contains('云空间容量不足')) {
            rethrow;
          }
        }
      }
      
      _throwClassifiedUploadError(putResp.statusCode, putBody);
      
    } catch (e) {
      Log.error('File upload failed: $e');
      if (e.toString().contains('文件上传失败') || e.toString().contains('AppFlowy Cloud')) {
        rethrow;
      }
      throw Exception('文件上传失败: $e');
    }
  }

  /// Send request with exponential backoff retry for transient errors
  static Future<http.StreamedResponse> _sendWithRetry(
    Future<http.StreamedResponse> Function() sender, {
    void Function(int attempt, int? statusCode, String? body)? onBeforeRetry,
    int maxAttempts = 4,
  }) async {
    int attempt = 0;
    while (true) {
      attempt++;
      try {
        final response = await sender();
        final status = response.statusCode;
        if (status >= 500 && status < 600) {
          // server error => retry
            if (attempt < maxAttempts) {
              final body = await response.stream.bytesToString();
              onBeforeRetry?.call(attempt, status, body);
              final delayMs = (300 * (1 << (attempt - 1))).clamp(300, 3000);
              await Future.delayed(Duration(milliseconds: delayMs));
              continue;
            }
        }
        return response;
      } catch (e) {
        if (attempt < maxAttempts) {
          onBeforeRetry?.call(attempt, null, e.toString());
          final delayMs = (300 * (1 << (attempt - 1))).clamp(300, 3000);
          await Future.delayed(Duration(milliseconds: delayMs));
          continue;
        }
        rethrow;
      }
    }
  }

  /// Classify common upload errors and throw actionable messages
  static Never _throwClassifiedUploadError(int statusCode, String responseBody, {String? context}) {
    final prefix = context != null ? '$context: ' : '';
    if (statusCode == 401) {
      throw Exception('${prefix}未授权 (401)，请登录 AppFlowy Cloud 后重试');
    }
    if (statusCode == 403) {
      throw Exception('${prefix}权限不足 (403)，请确认 token 有效、反向代理放行 Authorization 头');
    }
    if (statusCode == 413) {
      throw Exception('${prefix}请求体过大 (413)，请减小文件或检查反代的 client_max_body_size');
    }
    if (statusCode >= 500 && statusCode < 600) {
      throw Exception('${prefix}服务器错误 ($statusCode)，稍后重试；详情：$responseBody');
    }
    throw Exception('${prefix}AppFlowy Cloud上传失败: $statusCode - $responseBody');
  }

  /// Get cloud base URL from DI container's AppFlowyCloudSharedEnv.
  /// This returns the correct URL including port for dev environments
  /// (e.g. http://8.152.101.166:8000 instead of http://8.152.101.166).
  static String _getCloudBaseUrl() {
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final configBaseUrl = cloudEnv.appflowyCloudConfig.base_url;
      if (configBaseUrl.isNotEmpty) {
        Log.info('[FileUploadService] Using cloud config base_url: $configBaseUrl');
        return configBaseUrl;
      }
    } catch (e) {
      Log.warn('[FileUploadService] Failed to get cloud config, falling back: $e');
    }
    return Env.afCloudUrl.isNotEmpty ? Env.afCloudUrl : kAppflowyCloudUrl;
  }

  /// Build base origin without appending invalid default ports
  static String _buildBaseOrigin(Uri uri) {
    final bool isDefaultPort =
        (uri.scheme == 'https' && (uri.hasPort ? uri.port == 443 : true)) ||
        (uri.scheme == 'http' && (uri.hasPort ? uri.port == 80 : true));
    if (!uri.hasPort || isDefaultPort || uri.port == 0) {
      return '${uri.scheme}://${uri.host}';
    }
    return '${uri.scheme}://${uri.host}:${uri.port}';
  }
  
  /// Check if file size is within limits
  /// Maximum file size: 50MB
  static bool isFileSizeValid(int fileSizeInBytes) {
    const int maxFileSize = 50 * 1024 * 1024; // 50MB
    return fileSizeInBytes <= maxFileSize;
  }
  
  /// Get human readable file size string
  static String getFileSizeString(int fileSizeInBytes) {
    if (fileSizeInBytes < 1024) {
      return '${fileSizeInBytes}B';
    } else if (fileSizeInBytes < 1024 * 1024) {
      return '${(fileSizeInBytes / 1024).toStringAsFixed(1)}KB';
    } else if (fileSizeInBytes < 1024 * 1024 * 1024) {
      return '${(fileSizeInBytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    } else {
      return '${(fileSizeInBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
    }
  }
  
  /// Check if PDF page count is within limits
  static bool isPageCountValid(int pageCount) {
    const int maxPageCount = 600; // 600 pages
    return pageCount <= maxPageCount;
  }
  
  /// Get page count validation message
  static String getPageCountValidationMessage(int pageCount) {
    if (pageCount > 600) {
      return 'PDF页数超过限制：$pageCount页（最大600页）';
    }
    return '';
  }
  
  /// Get authentication token with automatic refresh
  static Future<String> _getAuthToken({bool forceRefresh = false}) async {
    try {
      if (!forceRefresh && _cachedAccessToken != null && _tokenExpiresAt != null) {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        if (now < _tokenExpiresAt! - 60) {
          return _cachedAccessToken!;
        }
        Log.info('[FileUploadService] Token expired or near expiry, refreshing...');
      }

      final userResult = await UserBackendService.getCurrentUserProfile();
      final user = userResult.fold(
        (user) => user,
        (error) => throw Exception('用户未登录或登录已过期，请重新登录'),
      );
      
      if (user.token.isEmpty) {
        throw Exception('用户未登录，token为空');
      }
      
      final accessToken = _normalizeToken(user.token);
      
      if (accessToken.isEmpty) {
        throw Exception('用户token为空，请重新登录');
      }

      _cachedAccessToken = accessToken;
      _tokenExpiresAt = _extractTokenExpiry(accessToken);
      
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (_tokenExpiresAt != null && now >= _tokenExpiresAt! - 60) {
        Log.info('[FileUploadService] Token expired, attempting refresh...');
        final refreshed = await _tryRefreshToken();
        if (refreshed != null) {
          return refreshed;
        }
      }
      
      Log.info('[FileUploadService] Got valid access token (length: ${accessToken.length})');
      return accessToken;
    } catch (e) {
      Log.error('[FileUploadService] Failed to get auth token: $e');
      if (e.toString().contains('未登录') || e.toString().contains('token')) {
        throw Exception('用户未登录或登录已过期，请先登录AppFlowy Cloud');
      }
      throw Exception('无法获取认证token: $e');
    }
  }

  /// Try to refresh the access token using the AuthService
  static Future<String?> _tryRefreshToken() async {
    try {
      final authService = getIt<AuthService>();
      final result = await authService.refreshToken();
      return result.fold(
        (tokenResponse) {
          final newToken = tokenResponse.accessToken;
          if (newToken.isNotEmpty) {
            _cachedAccessToken = newToken;
            _tokenExpiresAt = tokenResponse.expiresAt.toInt();
            Log.info('[FileUploadService] ✅ Token refreshed successfully');
            return newToken;
          }
          return null;
        },
        (error) {
          Log.error('[FileUploadService] ❌ Token refresh failed: ${error.msg}');
          return null;
        },
      );
    } catch (e) {
      Log.error('[FileUploadService] ❌ Token refresh error: $e');
      return null;
    }
  }

  /// Extract expiry from JWT token (decode payload without verification)
  static int? _extractTokenExpiry(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      String payload = parts[1];
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      final decoded = utf8.decode(base64Url.decode(payload));
      final map = jsonDecode(decoded) as Map<String, dynamic>;
      return (map['exp'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  /// Get a valid access token, refreshing if necessary. Public for use by other services.
  static Future<String> getValidAccessToken() async {
    return _getAuthToken();
  }

  /// Force refresh and return a new token. Public for retry-on-401 pattern.
  static Future<String?> forceRefreshAccessToken() async {
    _cachedAccessToken = null;
    _tokenExpiresAt = null;
    return _tryRefreshToken() ?? _getAuthToken(forceRefresh: true).then((t) => t);
  }
  
  /// ✅ 归一化token：如果是JSON字符串则提取access_token，否则直接返回
  static String _normalizeToken(String token) {
    if (token.isEmpty) return token;
    if (token.trim().startsWith('{')) {
      try {
        final map = jsonDecode(token);
        if (map is Map && map['access_token'] is String) {
          return map['access_token'] as String;
        }
      } catch (_) {}
    }
    return token;
  }
  
  
  /// Upload file from File object
  static Future<String> uploadFileFromFile(File file) async {
    final bytes = await file.readAsBytes();
    final fileName = file.path.split('/').last;
    return uploadFile(bytes, fileName);
  }
  
  /// Check if upload service is available
  static Future<bool> isUploadServiceAvailable() async {
    try {
      // Test with a small dummy file
      final testBytes = Uint8List.fromList('test'.codeUnits);
      await uploadFile(testBytes, 'test.txt');
      return true;
    } catch (e) {
      Log.error('Upload service check failed: $e');
      return false;
    }
  }
  
  
  /// Get supported file types
  static List<String> getSupportedFileTypes() {
    return [
      'pdf', 'doc', 'docx', 'txt', 'rtf', 'odt',
      'jpg', 'jpeg', 'png', 'gif', 'bmp', 'tiff',
      'xls', 'xlsx', 'csv', 'ppt', 'pptx',
    ];
  }

}


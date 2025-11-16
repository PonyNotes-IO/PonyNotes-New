import 'dart:io';
import 'dart:typed_data';
import 'package:appflowy_backend/log.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/user/application/user_service.dart';

/// File upload service for AppFlowy Cloud storage
class FileUploadService {
  
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
      
      // Get AppFlowy Cloud base URL
      final baseUrl = await getAppFlowyCloudUrl();
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
        // Try to parse URL from response
        try {
          if (putBody.isNotEmpty) {
            final data = jsonDecode(putBody);
            final fileUrl = (data is Map)
                ? (data['url'] as String? ?? data['file_url'] as String? ?? data['link'] as String?)
                : null;
            if (fileUrl != null && fileUrl.isNotEmpty) {
              Log.info('File uploaded successfully: $fileUrl');
              return fileUrl;
            }
          }
        } catch (_) {
          // If parsing fails, construct URL from endpoint
        }
        
        // Construct accessible URL (same as upload endpoint)
        final constructed = '$baseOrigin/api/file_storage/$workspaceId/blob/$fileId';
        Log.info('File uploaded successfully (constructed URL): $constructed');
        return constructed;
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
  
  
  /// Direct upload for small files
  /// @deprecated This method is no longer used. Use uploadFile() instead which directly uses PUT method.
  @Deprecated('Use uploadFile() instead')
  static Future<String> _uploadToAppFlowyCloudDirect(Uint8List fileBytes, String fileName) async {
    try {
      // Get current workspace
      final workspaceResult = await UserBackendService.getCurrentWorkspace();
      final workspace = workspaceResult.fold(
        (workspace) => workspace,
        (error) => throw Exception('无法获取当前工作区: $error'),
      );
      
      // Get AppFlowy Cloud base URL
      final baseUrl = await getAppFlowyCloudUrl();
      final uri = Uri.parse(baseUrl);
      final String baseOrigin = _buildBaseOrigin(uri);
      
      // Use the API endpoint with workspace ID and parent directory
      final workspaceId = workspace.id;
      final parentDir = 'temp'; // 使用temp作为临时文件目录
      final multipartUrl = '$baseOrigin/api/file_storage/$workspaceId/v1/blob/$parentDir';
      final putUrl = '$baseOrigin/api/file_storage/$workspaceId/v1/blob/$parentDir/${Uri.encodeComponent(fileName)}';

      Log.info('Direct uploading to AppFlowy Cloud (multipart first): $multipartUrl');
      Log.info('Workspace ID: $workspaceId, Parent Dir: $parentDir');

      // Attempt 1: multipart POST
      try {
        final url = Uri.parse(multipartUrl);
        final request = http.MultipartRequest('POST', url);
        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            fileBytes,
            filename: fileName,
            contentType: MediaType('application', 'pdf'),
          ),
        );
        request.headers.addAll({
          'Authorization': 'Bearer ${await _getAuthToken()}',
          'Accept': 'application/json',
        });

        final response = await _sendWithRetry(() => request.send(),
            onBeforeRetry: (attempt, code, body) {
          Log.warn('Direct upload (multipart) retry#$attempt due to ${code ?? 'network'} - ${body ?? ''}');
        });
        final responseBody = await response.stream.bytesToString();
        Log.info('Direct upload (multipart) response: ${response.statusCode} - $responseBody');

        if (response.statusCode == 200 || response.statusCode == 201) {
          try {
            final data = jsonDecode(responseBody);
            final fileUrl = data['url'] as String? ?? data['file_url'] as String? ?? data['link'] as String?;
            if (fileUrl != null) {
              Log.info('File uploaded (multipart) successfully: $fileUrl');
              return fileUrl;
            }
          } catch (_) {
            // ignore and try PUT
          }
          // 如果未能解析出链接，尝试备用 PUT 方式
          Log.warn('Direct upload (multipart) succeeded but no URL, fallback to PUT');
        } else {
          // 对于 403/404/405 切换到 PUT 尝试
          if (response.statusCode != 403 && response.statusCode != 404 && response.statusCode != 405) {
            _throwClassifiedUploadError(response.statusCode, responseBody);
          }
        }
      } catch (e) {
        Log.warn('Direct upload (multipart) failed: $e, fallback to PUT');
      }

      // Attempt 2: PUT application/octet-stream with file name
      Log.info('Direct uploading to AppFlowy Cloud (PUT): $putUrl');
      final putReq = http.Request('PUT', Uri.parse(putUrl));
      putReq.headers.addAll({
        'Authorization': 'Bearer ${await _getAuthToken()}',
        'Content-Type': 'application/octet-stream',
        'Accept': 'application/json',
      });
      putReq.bodyBytes = fileBytes;
      final putResp = await _sendWithRetry(() => putReq.send(), onBeforeRetry: (attempt, code, body) {
        Log.warn('Direct upload (PUT) retry#$attempt due to ${code ?? 'network'} - ${body ?? ''}');
      });
      final putBody = await putResp.stream.bytesToString();
      Log.info('Direct upload (PUT) response: ${putResp.statusCode} - $putBody');

      if (putResp.statusCode == 200 || putResp.statusCode == 201) {
        // 有的实现不返回 JSON，直接返回 201
        try {
          final data = putBody.isNotEmpty ? jsonDecode(putBody) : null;
          final fileUrl = (data is Map)
              ? (data['url'] as String? ?? data['file_url'] as String? ?? data['link'] as String?)
              : null;
          if (fileUrl != null) {
            return fileUrl;
          }
        } catch (_) {}
        // 构造可访问 URL（与 blob v1 一致）
        final constructed = '$baseOrigin/api/file_storage/$workspaceId/v1/blob/$parentDir/${Uri.encodeComponent(fileName)}';
        return constructed;
      }

      _throwClassifiedUploadError(putResp.statusCode, putBody);
    
    } catch (e) {
      Log.error('AppFlowy Cloud direct upload error: $e');
      throw Exception('AppFlowy Cloud直接上传失败: $e');
    }
  }
  
  /// Chunked upload for large files (>5MB)
  /// @deprecated This method is no longer used. Use uploadFile() instead which directly uses PUT method.
  @Deprecated('Use uploadFile() instead')
  static Future<String> _uploadToAppFlowyCloudChunked(Uint8List fileBytes, String fileName) async {
    try {
      // Get current workspace
      final workspaceResult = await UserBackendService.getCurrentWorkspace();
      final workspace = workspaceResult.fold(
        (workspace) => workspace,
        (error) => throw Exception('无法获取当前工作区: $error'),
      );
      
      // Get AppFlowy Cloud base URL
      final baseUrl = await getAppFlowyCloudUrl();
      final uri = Uri.parse(baseUrl);
      final String baseOrigin = _buildBaseOrigin(uri);
      
      final workspaceId = workspace.id;
      final parentDir = 'temp';
      final fileId = DateTime.now().millisecondsSinceEpoch.toString();

      // Initiate multipart upload to get server-side uploadId
      final uploadId = await _initiateMultipartUpload(
        baseOrigin: baseOrigin,
        workspaceId: workspaceId,
        parentDir: parentDir,
        fileId: fileId,
        fileSize: fileBytes.length,
        contentType: 'application/pdf',
      );

      Log.info('Starting chunked upload for file: $fileName');
      Log.info('File size: ${getFileSizeString(fileBytes.length)}');
      Log.info('Workspace ID: $workspaceId, File ID: $fileId, Upload ID: $uploadId');
      
      // Split file into chunks (2MB each to match cloud upload limit)
      const int chunkSize = 2 * 1024 * 1024; // 2MB chunks
      final chunks = _splitIntoChunks(fileBytes, chunkSize);
      
      Log.info('File split into ${chunks.length} chunks');
      
      // Upload each chunk and collect ETags
      final List<Map<String, dynamic>> uploadedParts = [];
      for (int i = 0; i < chunks.length; i++) {
        final chunk = chunks[i];
        final partNumber = i + 1;
        
        Log.info('Uploading chunk $partNumber/${chunks.length}');
        
        // Use the API format: /api/file_storage/{workspace_id}/upload/{parent_dir}/{file_id}?upload_id={upload_id}&part_number={part_number}
        final uploadUrl = '$baseOrigin/api/file_storage/$workspaceId/upload/$parentDir/$fileId?upload_id=$uploadId&part_number=$partNumber';
        
        Log.info('Upload URL: $uploadUrl');
        
        final request = http.Request('PUT', Uri.parse(uploadUrl));
        request.headers.addAll({
          'Content-Type': 'application/octet-stream',
          'Authorization': 'Bearer ${await _getAuthToken()}',
          'Accept': 'application/json',
        });
        
        request.bodyBytes = chunk;
        
        final response = await _sendWithRetry(() => request.send(),
            onBeforeRetry: (attempt, code, body) {
          Log.warn('Chunk $partNumber retry#$attempt due to ${code ?? 'network'} - ${body ?? ''}');
        });
        final responseBody = await response.stream.bytesToString();
        
        Log.info('Chunk $partNumber upload response: ${response.statusCode} - $responseBody');
        
        if (response.statusCode != 200 && response.statusCode != 201) {
          _throwClassifiedUploadError(response.statusCode, responseBody,
              context: '上传分片 $partNumber 失败');
        }

        // Try to parse ETag from response for complete step
        try {
          final data = responseBody.isNotEmpty ? jsonDecode(responseBody) : null;
          String? etag;
          if (data is Map<String, dynamic>) {
            etag = (data['e_tag'] as String?) ?? (data['etag'] as String?) ?? (data['ETag'] as String?);
          }
          if (etag != null && etag.isNotEmpty) {
            uploadedParts.add({'part_number': partNumber, 'e_tag': etag});
          }
        } catch (_) {}
      }
      
      // Complete multipart upload (with parts when available)
      await _completeMultipartUpload(
        baseOrigin: baseOrigin,
        workspaceId: workspaceId,
        parentDir: parentDir,
        fileId: fileId,
        uploadId: uploadId,
        parts: uploadedParts,
      );
      
      // After all chunks are uploaded, construct the final file URL
      final fileUrl = '$baseOrigin/api/file_storage/$workspaceId/v1/blob/$parentDir/$fileId';
      
      Log.info('Chunked upload completed successfully: $fileUrl');
      return fileUrl;
      
    } catch (e) {
      Log.error('AppFlowy Cloud chunked upload error: $e');
      throw Exception('AppFlowy Cloud分片上传失败: $e');
    }
  }

  /// Try multiple patterns to initiate multipart upload and return upload_id
  static Future<String> _initiateMultipartUpload({
    required String baseOrigin,
    required String workspaceId,
    required String parentDir,
    required String fileId,
    required int fileSize,
    required String contentType,
  }) async {
    final token = await _getAuthToken();
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    };

    final body = jsonEncode({
      'parent_dir': parentDir,
      'file_id': fileId,
      'content_type': contentType,
      'file_size': fileSize,
    });

    final url1 = Uri.parse('$baseOrigin/api/file_storage/$workspaceId/uploads');
    final url2 = Uri.parse('$baseOrigin/api/file_storage/$workspaceId/upload/$parentDir/$fileId/create');

    for (final url in [url1, url2]) {
      try {
        Log.info('Initiate multipart upload: $url');
        final resp = await http.post(url, headers: headers, body: body);
        if (resp.statusCode == 200 || resp.statusCode == 201) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final uploadId = data['upload_id'] as String? ?? data['data']?['upload_id'] as String?;
          if (uploadId != null && uploadId.isNotEmpty) {
            Log.info('Initiated upload_id: $uploadId');
            return uploadId;
          }
          throw Exception('创建上传成功但未返回 upload_id');
        }
        if (resp.statusCode == 404 || resp.statusCode == 405) {
          continue;
        }
        _throwClassifiedUploadError(resp.statusCode, resp.body, context: '创建分片上传失败');
      } catch (e) {
        Log.warn('Initiate upload failed on $url: $e');
        continue;
      }
    }

    throw Exception('无法创建分片上传，会导致后续分片上传失败');
  }

  /// Try multiple patterns to complete multipart upload
  static Future<void> _completeMultipartUpload({
    required String baseOrigin,
    required String workspaceId,
    required String parentDir,
    required String fileId,
    required String uploadId,
    List<Map<String, dynamic>>? parts,
  }) async {
    final token = await _getAuthToken();
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    };

    final body = jsonEncode({
      'upload_id': uploadId,
      'parent_dir': parentDir,
      'file_id': fileId,
      'parts': parts,
    });

    final url1 = Uri.parse('$baseOrigin/api/file_storage/$workspaceId/uploads/$uploadId/complete');
    final url2 = Uri.parse('$baseOrigin/api/file_storage/$workspaceId/upload/$parentDir/$fileId/complete?upload_id=$uploadId');

    for (final url in [url1, url2]) {
      try {
        Log.info('Complete multipart upload: $url');
        final resp = await http.post(url, headers: headers, body: body);
        if (resp.statusCode == 200 || resp.statusCode == 201 || resp.statusCode == 204) {
          Log.info('Complete upload succeeded');
          return;
        }
        if (resp.statusCode == 404 || resp.statusCode == 405) {
          continue;
        }
        _throwClassifiedUploadError(resp.statusCode, resp.body, context: '完成分片上传失败');
      } catch (e) {
        Log.warn('Complete upload failed on $url: $e');
        continue;
      }
    }

    throw Exception('无法完成分片上传，文件可能不可访问');
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
  
  /// Split file into chunks
  static List<Uint8List> _splitIntoChunks(Uint8List data, int chunkSize) {
    final chunks = <Uint8List>[];
    for (int i = 0; i < data.length; i += chunkSize) {
      final end = (i + chunkSize < data.length) ? i + chunkSize : data.length;
      chunks.add(data.sublist(i, end));
    }
    return chunks;
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
  
  /// Get authentication token
  static Future<String> _getAuthToken() async {
    try {
      // Get current user profile to get token
      final userResult = await UserBackendService.getCurrentUserProfile();
      final user = userResult.fold(
        (user) => user,
        (error) => throw Exception('用户未登录或登录已过期，请重新登录'),
      );
      
      // Check if user token is empty or null
      if (user.token.isEmpty) {
        throw Exception('用户未登录，token为空');
      }
      
      // Parse the token JSON to get access_token
      Map<String, dynamic> tokenMap;
      try {
        tokenMap = jsonDecode(user.token) as Map<String, dynamic>;
      } catch (e) {
        Log.error('Failed to parse user token JSON: $e');
        throw Exception('用户token格式错误，请重新登录');
      }
      
      final accessToken = tokenMap['access_token'] as String?;
      
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('用户token中缺少access_token，请重新登录');
      }
      
      Log.info('Successfully retrieved access token');
      return accessToken;
    } catch (e) {
      Log.error('Failed to get auth token: $e');
      if (e.toString().contains('未登录') || e.toString().contains('token')) {
        throw Exception('用户未登录或登录已过期，请先登录AppFlowy Cloud');
      }
      throw Exception('无法获取认证token: $e');
    }
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
  
  /// Get maximum file size (in bytes)
  static int getMaxFileSize() {
    return 50 * 1024 * 1024; // 50MB
  }
}


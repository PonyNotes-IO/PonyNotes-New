import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'baidu_cloud_config_service.dart';

/// 百度网盘API服务类
class BaiduCloudService {
  static const String _accessTokenKey = 'baidu_cloud_access_token';
  static const String _refreshTokenKey = 'baidu_cloud_refresh_token';
  static const String _expiresAtKey = 'baidu_cloud_expires_at';
  
  final BaiduCloudConfigService _configService = BaiduCloudConfigService.instance;
  
  BaiduCloudConfig get _config => _configService.getConfig();

  /// 获取授权URL
  String getAuthorizationUrl() {
    final config = _config;
    if (!config.isValid) {
      throw Exception('百度网盘配置无效，请检查.env.baidu文件');
    }
    
    final params = {
      'response_type': 'code',
      'client_id': config.appKey,
      'redirect_uri': config.redirectUri,
      'scope': 'basic netdisk',
      'state': 'baidu_cloud_auth',
    };
    
    final queryString = params.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    
    return 'https://openapi.baidu.com/oauth/2.0/authorize?$queryString';
  }

  /// 使用授权码获取访问令牌
  Future<bool> exchangeCodeForToken(String code) async {
    try {
      final config = _config;
      if (!config.isValid) {
        throw Exception('百度网盘配置无效，请检查.env.baidu文件');
      }
      
      final response = await http.post(
        Uri.parse('https://openapi.baidu.com/oauth/2.0/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'authorization_code',
          'code': code,
          'client_id': config.appKey,
          'client_secret': config.secretKey,
          'redirect_uri': config.redirectUri,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['access_token'] != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_accessTokenKey, data['access_token']);
          await prefs.setString(_refreshTokenKey, data['refresh_token'] ?? '');
          
          // 计算过期时间
          final expiresIn = data['expires_in'] ?? 3600;
          final expiresAt = DateTime.now().add(Duration(seconds: expiresIn));
          await prefs.setString(_expiresAtKey, expiresAt.toIso8601String());
          
          return true;
        }
      }
      
      print('Token exchange failed: ${response.body}');
      return false;
    } catch (e) {
      print('Error exchanging code for token: $e');
      return false;
    }
  }

  /// 检查是否已授权
  Future<bool> isAuthorized() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString(_accessTokenKey);
    final expiresAtStr = prefs.getString(_expiresAtKey);
    
    if (accessToken == null || expiresAtStr == null) {
      return false;
    }
    
    final expiresAt = DateTime.parse(expiresAtStr);
    return DateTime.now().isBefore(expiresAt);
  }

  /// 获取有效的访问令牌
  Future<String?> getValidAccessToken() async {
    if (await isAuthorized()) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_accessTokenKey);
    }
    
    // 尝试刷新令牌
    if (await refreshAccessToken()) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_accessTokenKey);
    }
    
    return null;
  }

  /// 刷新访问令牌
  Future<bool> refreshAccessToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final refreshToken = prefs.getString(_refreshTokenKey);
      
      if (refreshToken == null) {
        return false;
      }
      
      final config = _config;
      final response = await http.post(
        Uri.parse('https://openapi.baidu.com/oauth/2.0/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
          'client_id': config.appKey,
          'client_secret': config.secretKey,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['access_token'] != null) {
          await prefs.setString(_accessTokenKey, data['access_token']);
          
          if (data['refresh_token'] != null) {
            await prefs.setString(_refreshTokenKey, data['refresh_token']);
          }
          
          final expiresIn = data['expires_in'] ?? 3600;
          final expiresAt = DateTime.now().add(Duration(seconds: expiresIn));
          await prefs.setString(_expiresAtKey, expiresAt.toIso8601String());
          
          return true;
        }
      }
      
      return false;
    } catch (e) {
      print('Error refreshing token: $e');
      return false;
    }
  }

  /// 获取用户信息
  Future<Map<String, dynamic>?> getUserInfo() async {
    final accessToken = await getValidAccessToken();
    if (accessToken == null) return null;

    try {
      final config = _config;
      final response = await http.get(
        Uri.parse('${config.apiBase}/xpan/nas?method=uinfo&access_token=$accessToken'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['errno'] == 0) {
          return data;
        }
      }
      
      return null;
    } catch (e) {
      print('Error getting user info: $e');
      return null;
    }
  }

  /// 获取文件列表
  Future<List<BaiduCloudFile>> getFileList({
    String dir = '/',
    int start = 0,
    int limit = 100,
  }) async {
    final accessToken = await getValidAccessToken();
    if (accessToken == null) return [];

    try {
      final params = {
        'method': 'list',
        'dir': dir,
        'start': start.toString(),
        'limit': limit.toString(),
        'access_token': accessToken,
      };

      final queryString = params.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');

      final config = _config;
      final response = await http.get(
        Uri.parse('${config.apiBase}/xpan/file?$queryString'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['errno'] == 0 && data['list'] != null) {
          return (data['list'] as List)
              .map((item) => BaiduCloudFile.fromJson(item))
              .toList();
        }
      }
      
      return [];
    } catch (e) {
      print('Error getting file list: $e');
      return [];
    }
  }

  /// 获取文件下载链接
  Future<String?> getFileDownloadUrl(String fsId) async {
    final accessToken = await getValidAccessToken();
    if (accessToken == null) return null;

    try {
      final config = _config;
      final response = await http.post(
        Uri.parse('${config.apiBase}/xpan/file?method=download&access_token=$accessToken'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'fidlist': '[$fsId]'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['errno'] == 0 && data['dlink'] != null) {
          return data['dlink'][0]['dlink'];
        }
      }
      
      return null;
    } catch (e) {
      print('Error getting download URL: $e');
      return null;
    }
  }

  /// 下载文件
  Future<File?> downloadFile(String downloadUrl, String savePath) async {
    try {
      final response = await http.get(Uri.parse(downloadUrl));
      
      if (response.statusCode == 200) {
        final file = File(savePath);
        await file.writeAsBytes(response.bodyBytes);
        return file;
      }
      
      return null;
    } catch (e) {
      print('Error downloading file: $e');
      return null;
    }
  }

  /// 登出
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_expiresAtKey);
  }
}

/// 百度网盘文件模型
class BaiduCloudFile {
  final String fsId;
  final String path;
  final String serverFilename;
  final int size;
  final int serverMtime;
  final int localMtime;
  final int isDir;
  final int category;
  final String md5;

  BaiduCloudFile({
    required this.fsId,
    required this.path,
    required this.serverFilename,
    required this.size,
    required this.serverMtime,
    required this.localMtime,
    required this.isDir,
    required this.category,
    required this.md5,
  });

  factory BaiduCloudFile.fromJson(Map<String, dynamic> json) {
    return BaiduCloudFile(
      fsId: json['fs_id']?.toString() ?? '',
      path: json['path'] ?? '',
      serverFilename: json['server_filename'] ?? '',
      size: json['size'] ?? 0,
      serverMtime: json['server_mtime'] ?? 0,
      localMtime: json['local_mtime'] ?? 0,
      isDir: json['isdir'] ?? 0,
      category: json['category'] ?? 0,
      md5: json['md5'] ?? '',
    );
  }

  bool get isDirectory => isDir == 1;
  
  String get displayName => serverFilename;
  
  String get fileSize {
    if (size < 1024) return '${size}B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)}KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }
  
  String get fileExtension {
    final parts = serverFilename.split('.');
    return parts.length > 1 ? '.${parts.last.toLowerCase()}' : '';
  }
}

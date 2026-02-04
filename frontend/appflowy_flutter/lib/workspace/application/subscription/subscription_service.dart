import 'dart:async';
import 'dart:convert';

import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:universal_platform/universal_platform.dart';

import '../../../env/cloud_env.dart';
import '../../../startup/startup.dart';
import '../settings/settings_dialog_bloc.dart';

/// 订阅服务，统一管理会员订阅信息的获取和更新
class SubscriptionService {
  static final SubscriptionService _instance = SubscriptionService._internal();
  factory SubscriptionService() => _instance;

  SubscriptionService._internal();

  // 缓存的订阅信息
  CurrentSubscription? _cachedSubscription;
  WorkspaceSubscriptionInfoPB? _cachedWorkspaceSubscriptionInfo;
  DateTime? _lastFetchTime;

  // 缓存过期时间（10分钟）
  static const Duration _cacheExpiry = Duration(minutes: 10);

  // 最大重试次数
  static const int _maxRetries = 3;

  // 重试延迟时间
  static const Duration _retryDelay = Duration(seconds: 1);

  /// 获取当前订阅信息（包含使用量）
  /// 
  /// [userProfile] 用户信息
  /// [forceRefresh] 是否强制刷新，忽略缓存
  Future<CurrentSubscription?> getCurrentSubscription({
    required UserProfilePB userProfile,
    bool forceRefresh = false,
  }) async {
    // 检查缓存是否有效
    if (!forceRefresh && _isCacheValid()) {
      Log.info('Using cached subscription info');
      return _cachedSubscription;
    }

    Log.info('Fetching current subscription info');
    
    // 尝试获取订阅信息，带重试机制
    CurrentSubscription? subscription;
    for (int attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        subscription = await _fetchCurrentSubscriptionData(userProfile);
        if (subscription != null) {
          break;
        }
      } catch (e) {
        Log.error('Attempt $attempt failed to fetch subscription info: $e');
        if (attempt < _maxRetries) {
          Log.info('Retrying in $_retryDelay...');
          await Future.delayed(_retryDelay);
        }
      }
    }

    // 更新缓存，即使获取失败也更新缓存时间，避免频繁重试
    _lastFetchTime = DateTime.now();
    if (subscription != null) {
      _cachedSubscription = subscription;
      Log.info('Successfully fetched subscription info');
    } else {
      Log.warn('Failed to fetch subscription info, using cached value if available');
    }

    return subscription;
  }

  /// 获取工作区订阅信息
  /// 
  /// [workspaceId] 工作区ID
  /// [forceRefresh] 是否强制刷新，忽略缓存
  Future<WorkspaceSubscriptionInfoPB?> getWorkspaceSubscriptionInfo({
    required String workspaceId,
    bool forceRefresh = false,
  }) async {
    // 检查缓存是否有效
    if (!forceRefresh && _isCacheValid() && _cachedWorkspaceSubscriptionInfo != null) {
      Log.info('Using cached workspace subscription info');
      return _cachedWorkspaceSubscriptionInfo;
    }

    Log.info('Fetching workspace subscription info for workspace: $workspaceId');
    
    // 尝试获取工作区订阅信息，带重试机制
    WorkspaceSubscriptionInfoPB? subscriptionInfo;
    for (int attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        final result = await UserBackendService.getWorkspaceSubscriptionInfo(workspaceId);
        subscriptionInfo = result.fold(
          (info) => info,
          (error) {
            Log.error('Failed to fetch workspace subscription info: ${error.msg}');
            return null;
          },
        );
        if (subscriptionInfo != null) {
          break;
        }
      } catch (e) {
        Log.error('Attempt $attempt failed to fetch workspace subscription info: $e');
        if (attempt < _maxRetries) {
          Log.info('Retrying in $_retryDelay...');
          await Future.delayed(_retryDelay);
        }
      }
    }

    // 更新缓存
    if (subscriptionInfo != null) {
      _cachedWorkspaceSubscriptionInfo = subscriptionInfo;
      _lastFetchTime = DateTime.now();
      Log.info('Successfully fetched workspace subscription info');
    }

    return subscriptionInfo;
  }

  /// 刷新所有订阅信息
  Future<void> refreshAllSubscriptionInfo({
    required UserProfilePB userProfile,
    String? workspaceId,
  }) async {
    Log.info('Refreshing all subscription info');
    
    // 并行获取订阅信息
    final futures = <Future>[];
    
    futures.add(getCurrentSubscription(
      userProfile: userProfile,
      forceRefresh: true,
    ));
    
    if (workspaceId != null) {
      futures.add(getWorkspaceSubscriptionInfo(
        workspaceId: workspaceId,
        forceRefresh: true,
      ));
    }
    
    await Future.wait(futures);
    
    Log.info('All subscription info refreshed');
  }

  /// 检查缓存是否有效
  bool _isCacheValid() {
    if (_lastFetchTime == null) {
      return false;
    }
    return DateTime.now().difference(_lastFetchTime!) < _cacheExpiry;
  }

  /// 从后端获取当前订阅信息
  Future<CurrentSubscription?> _fetchCurrentSubscriptionData(UserProfilePB userProfile) async {
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;
      if (baseUrl.isEmpty) {
        Log.warn('Cloud base URL is empty');
        return null;
      }

      final accessToken = _extractAccessToken(userProfile.token);
      if (accessToken == null || accessToken.isEmpty) {
        Log.warn('Access token is empty');
        return null;
      }

      final uri = Uri.parse(baseUrl).replace(path: '/api/subscription/current');
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          Log.warn('Fetching subscription info timed out');
          return http.Response('', 408);
        },
      );

      // 处理超时情况
      if (response.statusCode == 408) {
        Log.warn('Fetching subscription info timed out');
        return null;
      }

      // 处理 404 情况
      if (response.statusCode == 404) {
        Log.info('Subscription info not found (404)');
        return null;
      }

      // 处理其他错误
      if (response.statusCode != 200) {
        Log.error('Failed to fetch subscription info: ${response.statusCode}, ${response.body}');
        return null;
      }

      // 解析响应
      final json = jsonDecode(response.body);
      final subscription = CurrentSubscription.fromJson(json['data']);
      return subscription;
    } catch (e, stackTrace) {
      Log.error('Error fetching subscription info: $e', stackTrace);
      return null;
    }
  }

  /// 从用户 token 中提取 access token
  String? _extractAccessToken(String token) {
    try {
      // 尝试解析 token 为 JSON
      final json = jsonDecode(token);
      if (json is Map && json.containsKey('access_token')) {
        return json['access_token'] as String;
      }
      // 如果不是 JSON，直接返回 token
      return token;
    } catch (e) {
      // 如果解析失败，直接返回 token
      return token;
    }
  }

  /// 清除缓存
  void clearCache() {
    _cachedSubscription = null;
    _cachedWorkspaceSubscriptionInfo = null;
    _lastFetchTime = null;
    Log.info('Subscription info cache cleared');
  }
}

/// 扩展方法，方便在需要的地方使用订阅服务
extension SubscriptionServiceExtension on BuildContext {
  /// 获取订阅服务
  SubscriptionService get subscriptionService => SubscriptionService();
}

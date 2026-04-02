import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// 联系方式绑定服务
class ContactBindingService {

  /// 检测邮箱是否已被其他账号注册
  /// 返回 success(null) 表示未注册，可继续发验证码
  /// 返回 failure 表示已被注册
  static Future<FlowyResult<void, FlowyError>> checkEmailRegistered(
    String email,
  ) async {
    try {
      final cloudConfigResult = await UserEventGetCloudConfig().send();
      final cloudConfig = cloudConfigResult.fold(
        (config) => config,
        (error) => throw error,
      );

      final userProfileResult = await UserBackendService.getCurrentUserProfile();
      final userProfile = userProfileResult.fold(
        (profile) => profile,
        (error) => throw error,
      );

      final baseUrl = cloudConfig.serverUrl;
      final rawToken = _normalizeToken(userProfile.token);
      if (baseUrl.isEmpty || rawToken.isEmpty) {
        return FlowyResult.failure(
          FlowyError.create()
            ..code = ErrorCode.Internal
            ..msg = 'Missing server URL or auth token',
        );
      }

      // 调用 AppFlowy Cloud /api/user/check-email-registered 接口检测邮箱是否已注册
      final uri = Uri.parse('$baseUrl/api/user/check-email-registered');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $rawToken',
        },
        body: jsonEncode({'email': email}),
      );

      if (response.statusCode == 200) {
        try {
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          if (json['email_exists'] == true) {
            return FlowyResult.failure(
              FlowyError.create()
                ..msg = '该邮箱已被其他账号注册',
            );
          }
        } catch (_) {}
        return FlowyResult.success(null);
      } else {
        String errorMsg = '检测邮箱注册状态失败 (HTTP ${response.statusCode})';
        if (response.body.isNotEmpty) {
          try {
            final json = jsonDecode(response.body) as Map<String, dynamic>;
            errorMsg = json['message'] as String? ?? json['msg'] as String? ?? errorMsg;
          } catch (_) {}
        }
        return FlowyResult.failure(
          FlowyError.create()
            ..code = ErrorCode.Internal
            ..msg = errorMsg,
        );
      }
    } catch (e) {
      return FlowyResult.failure(
        FlowyError.create()
          ..msg = "检测邮箱注册状态失败: $e",
      );
    }
  }

  /// 发送手机验证码（用于换绑手机号）
  ///
  /// 使用 GoTrue 的标准手机号变更流程（需要登录）
  /// 调用云端 API /api/user/send-phone-otp
  /// 若手机号已被其他账号注册，后端返回 phone_exists=true，此时直接拒绝
  static Future<FlowyResult<void, FlowyError>> sendPhoneVerificationCode(
    String phoneNumber,
  ) async {
    try {
      final cloudConfigResult = await UserEventGetCloudConfig().send();
      final cloudConfig = cloudConfigResult.fold(
        (config) => config,
        (error) => throw error,
      );

      final userProfileResult = await UserBackendService.getCurrentUserProfile();
      final userProfile = userProfileResult.fold(
        (profile) => profile,
        (error) => throw error,
      );

      final baseUrl = cloudConfig.serverUrl;
      final rawToken = _normalizeToken(userProfile.token);
      if (baseUrl.isEmpty || rawToken.isEmpty) {
        return FlowyResult.failure(
          FlowyError.create()
            ..code = ErrorCode.Internal
            ..msg = 'Missing server URL or auth token',
        );
      }

      final uri = Uri.parse('$baseUrl/api/user/send-phone-otp');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $rawToken',
        },
        body: jsonEncode({'phone': phoneNumber}),
      );

      if (response.statusCode == 200) {
        try {
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          // phone_exists=true → 手机号已被其他账号注册
          if (json['phone_exists'] == true) {
            return FlowyResult.failure(
              FlowyError.create()
                ..code = ErrorCode.Internal
                ..msg = '该手机号已被其他账号注册',
            );
          }
          // 即使 HTTP 200，GoTrue 也可能在 body 里返回 error（code != 0）
          if (json.containsKey('code') && json['code'] != 0) {
            final errorMsg =
                json['message'] as String? ?? json['msg'] as String? ?? '发送验证码失败';
            return FlowyResult.failure(
              FlowyError.create()
                ..code = ErrorCode.Internal
                ..msg = errorMsg,
            );
          }
        } catch (_) {
          // 解析失败，当作成功
        }
        return FlowyResult.success(null);
      } else {
        String errorMsg = '发送手机验证码失败 (HTTP ${response.statusCode})';
        if (response.body.isNotEmpty) {
          try {
            final json = jsonDecode(response.body) as Map<String, dynamic>;
            errorMsg = json['message'] as String? ?? json['msg'] as String? ?? errorMsg;
          } catch (_) {}
        }
        return FlowyResult.failure(
          FlowyError.create()
            ..code = ErrorCode.Internal
            ..msg = errorMsg,
        );
      }
    } catch (e) {
      return FlowyResult.failure(
        FlowyError.create()
          ..msg = "发送手机验证码失败: $e",
      );
    }
  }

  static String _normalizeToken(String token) {
    if (token.isEmpty) return token;
    if (token.trim().startsWith('{')) {
      try {
        final map = jsonDecode(token) as Map<String, dynamic>;
        if (map['access_token'] is String) {
          return map['access_token'] as String;
        }
      } catch (_) {}
    }
    return token;
  }

  /// 发送邮箱验证码
  static Future<FlowyResult<void, FlowyError>> sendEmailVerificationCode(
    String email,
  ) async {
    try {
      // 调用云端API发送邮箱验证码
      // 使用GoTrue的/otp端点发送验证码
      final result = await UserBackendService.signInWithMagicLink(email, '');

      return result.fold(
        (_) => FlowyResult.success(null),
        (error) => FlowyResult.failure(error),
      );
    } catch (e) {
      return FlowyResult.failure(
        FlowyError.create()
          ..msg = "发送邮箱验证码失败: $e",
      );
    }
  }

  /// 验证手机号并绑定
  /// 
  /// 调用云端 API /api/user/verify-phone 来验证验证码并绑定手机号
  static Future<FlowyResult<void, FlowyError>> bindPhoneNumber(
    String phoneNumber,
    String verificationCode,
  ) async {
    try {
      // 验证验证码格式
      if (verificationCode.length != 6) {
        return FlowyResult.failure(
          FlowyError.create()
            ..msg = "请输入6位验证码",
        );
      }
      
      // 调用新的 API 端点验证验证码并绑定手机号
      final result = await UserBackendService.verifyAndBindPhone(
        phoneNumber,
        verificationCode,
      );
      
      return result.fold(
        (_) => FlowyResult.success(null),
        (error) => FlowyResult.failure(error),
      );
    } catch (e) {
      return FlowyResult.failure(
        FlowyError.create()
          ..msg = "绑定手机号失败: $e",
      );
    }
  }

  /// 验证邮箱并绑定
  static Future<FlowyResult<void, FlowyError>> bindEmail(
    String email,
    String verificationCode,
  ) async {
    try {
      // 步骤1: 使用验证码登录来验证验证码是否正确
      final verifyResult = await UserBackendService.signInWithPasscode(
        email,
        verificationCode,
      );

      // 检查验证是否成功
      final verifySuccess = verifyResult.fold(
        (_) => true,
        (_) => false,
      );

      if (!verifySuccess) {
        return FlowyResult.failure(
          FlowyError.create()
            ..msg = "验证码错误，请检查后重试",
        );
      }

      // 步骤2: 验证成功后，更新用户邮箱
      final userProfileResult = await UserBackendService.getCurrentUserProfile();
      final userProfile = userProfileResult.fold(
        (profile) => profile,
        (error) => throw error,
      );

      final userService = UserBackendService(userId: userProfile.id);
      final result = await userService.updateUserProfile(email: email);

      return result.fold(
        (_) => FlowyResult.success(null),
        (error) => FlowyResult.failure(error),
      );
    } catch (e) {
      return FlowyResult.failure(
        FlowyError.create()
          ..msg = "绑定邮箱失败: $e",
      );
    }
  }

  /// 邮箱重认证验证码发送
  /// 用于在身份验证对话框中切换到邮箱验证方式
  static Future<FlowyResult<void, FlowyError>> sendEmailReauthenticationCode(
    String email,
  ) async {
    try {
      final result = await UserBackendService.signInWithMagicLink(email, '');
      return result.fold(
        (_) => FlowyResult.success(null),
        (error) => FlowyResult.failure(error),
      );
    } catch (e) {
      return FlowyResult.failure(
        FlowyError.create()
          ..msg = "发送邮箱验证码失败: $e",
      );
    }
  }

  /// 验证邮箱重认证验证码（用于身份验证，不绑定邮箱）
  /// 通过 signInWithPasscode 验证邮箱 OTP，验证成功即完成身份验证
  static Future<FlowyResult<void, FlowyError>> verifyEmailReauthentication(
    String email,
    String otp,
  ) async {
    try {
      final result = await UserBackendService.signInWithPasscode(email, otp);
      return result.fold(
        (_) => FlowyResult.success(null),
        (error) => FlowyResult.failure(error),
      );
    } catch (e) {
      return FlowyResult.failure(
        FlowyError.create()
          ..msg = "验证失败: $e",
      );
    }
  }

  /// 解绑手机号
  static Future<FlowyResult<void, FlowyError>> unbindPhoneNumber() async {
    try {
      // 获取当前用户信息
      final userProfileResult = await UserBackendService.getCurrentUserProfile();
      final userProfile = userProfileResult.fold(
        (profile) => profile,
        (error) => throw error,
      );
      
      // 调用云端API清空用户手机号
      final userService = UserBackendService(userId: userProfile.id);
      final result = await userService.updateUserProfile(phone: "");
      
      return result.fold(
        (_) => FlowyResult.success(null),
        (error) => FlowyResult.failure(error),
      );
    } catch (e) {
      return FlowyResult.failure(
        FlowyError.create()
          ..msg = "解绑手机号失败: $e",
      );
    }
  }

  /// 解绑邮箱
  static Future<FlowyResult<void, FlowyError>> unbindEmail() async {
    try {
      // 获取当前用户信息
      final userProfileResult = await UserBackendService.getCurrentUserProfile();
      final userProfile = userProfileResult.fold(
        (profile) => profile,
        (error) => throw error,
      );
      
      // 调用云端API清空用户邮箱
      final userService = UserBackendService(userId: userProfile.id);
      final result = await userService.updateUserProfile(email: "");
      
      return result.fold(
        (_) => FlowyResult.success(null),
        (error) => FlowyResult.failure(error),
      );
    } catch (e) {
      return FlowyResult.failure(
        FlowyError.create()
          ..msg = "解绑邮箱失败: $e",
      );
    }
  }
}

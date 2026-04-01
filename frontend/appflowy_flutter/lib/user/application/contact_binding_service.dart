import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';

/// 联系方式绑定服务
class ContactBindingService {
  
  /// 发送手机验证码（用于换绑手机号）
  /// 
  /// 使用 GoTrue 的标准手机号变更流程（需要登录）
  /// 调用云端 API，云端会调用 GoTrue 的 update_user 来发送 OTP
  static Future<FlowyResult<void, FlowyError>> sendPhoneVerificationCode(
    String phoneNumber,
  ) async {
    try {
      // 调用云端 API 发送验证码（GoTrue 标准手机号变更流程）
      // 这个方法需要用户登录，会调用 GoTrue 的 update_user API
      final result = await UserBackendService.sendPhoneOTP(phoneNumber);
      
      return result.fold(
        (_) => FlowyResult.success(null),
        (error) => FlowyResult.failure(error),
      );
    } catch (e) {
      return FlowyResult.failure(
        FlowyError.create()
          ..msg = "发送手机验证码失败: $e",
      );
    }
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

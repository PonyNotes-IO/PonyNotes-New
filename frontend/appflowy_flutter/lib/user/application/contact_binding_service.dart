import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';

/// 联系方式绑定服务
class ContactBindingService {
  
  /// 发送手机验证码
  static Future<FlowyResult<void, FlowyError>> sendPhoneVerificationCode(
    String phoneNumber,
  ) async {
    try {
      // TODO: 这里需要调用真正的发送短信验证码API
      // 目前使用模拟实现，因为signInWithMagicLink是登录接口，不是发送验证码接口
      
      // 模拟API调用延迟
      await Future.delayed(const Duration(seconds: 1));
      
      // 模拟成功发送（实际项目中需要替换为真实的短信API）
      return FlowyResult.success(null);
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
      // TODO: 这里需要调用真正的发送邮箱验证码API
      // 目前使用模拟实现，因为signInWithMagicLink是登录接口，不是发送验证码接口
      
      // 模拟API调用延迟
      await Future.delayed(const Duration(seconds: 1));
      
      // 模拟成功发送（实际项目中需要替换为真实的邮箱API）
      return FlowyResult.success(null);
    } catch (e) {
      return FlowyResult.failure(
        FlowyError.create()
          ..msg = "发送邮箱验证码失败: $e",
      );
    }
  }

  /// 验证手机号并绑定
  static Future<FlowyResult<void, FlowyError>> bindPhoneNumber(
    String phoneNumber,
    String verificationCode,
  ) async {
    try {
      // TODO: 这里需要调用真正的验证码验证API
      // 目前使用模拟验证：验证码为 "123456" 时验证成功
      
      await Future.delayed(const Duration(seconds: 1));
      
      if (verificationCode == "123456") {
        // 模拟验证成功，更新用户资料
        final userProfileResult = await UserBackendService.getCurrentUserProfile();
        final userProfile = userProfileResult.fold(
          (profile) => profile,
          (error) => throw error,
        );
        
        // 调用云端API更新用户邮箱字段（用于存储手机号）
        // 注意：由于protobuf中没有phone字段，这里使用email字段存储手机号
        final userService = UserBackendService(userId: userProfile.id);
        final result = await userService.updateUserProfile(email: phoneNumber);
        
        return result.fold(
          (_) => FlowyResult.success(null),
          (error) => FlowyResult.failure(error),
        );
      } else {
        return FlowyResult.failure(
          FlowyError.create()
            ..msg = "验证码错误，请输入 123456 进行测试",
        );
      }
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
      // TODO: 这里需要调用真正的验证码验证API
      // 目前使用模拟验证：验证码为 "123456" 时验证成功
      
      await Future.delayed(const Duration(seconds: 1));
      
      if (verificationCode == "123456") {
        // 模拟验证成功，更新用户资料
        final userProfileResult = await UserBackendService.getCurrentUserProfile();
        final userProfile = userProfileResult.fold(
          (profile) => profile,
          (error) => throw error,
        );
        
        // 调用云端API更新用户邮箱
        final userService = UserBackendService(userId: userProfile.id);
        final result = await userService.updateUserProfile(email: email);
        
        return result.fold(
          (_) => FlowyResult.success(null),
          (error) => FlowyResult.failure(error),
        );
      } else {
        return FlowyResult.failure(
          FlowyError.create()
            ..msg = "验证码错误，请输入 123456 进行测试",
        );
      }
    } catch (e) {
      return FlowyResult.failure(
        FlowyError.create()
          ..msg = "绑定邮箱失败: $e",
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

import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/settings/account/account_management_bloc.dart';
import 'package:appflowy/workspace/application/subscription/subscription_service.dart';
import 'package:appflowy/workspace/presentation/settings/pages/account_management_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../features/workspace/logic/workspace_bloc.dart';
import '../../../shared/settings/show_settings.dart';
import '../../presentation/widgets/dialogs.dart';
import 'package:appflowy/workspace/presentation/settings/settings_dialog.dart' as setting;

import '../settings/settings_dialog_bloc.dart';


/// 会员状态枚举
enum MembershipStatus {
  active, // 会员有效
  expired, // 会员已过期
  notSubscribed, // 未订阅
  storageFull, // 存储空间已满
}

/// 付费功能枚举
enum PremiumFeature {
  cloudSync, // 云同步
  // fileUpload, // 文件上传
  // multiDeviceSync, // 多设备同步
  aiFeatures, // AI 功能
  versionHistory, // 版本历史
  // shareLinks, // 分享链接
  // publish, // 发布功能
  workspaceMembers, // 工作区成员管理
  workspaceCreate //工作区创建
}

/// 会员状态检查服务
/// 
/// 用于检查会员状态，判断用户是否有权限使用付费功能，
/// 以及在会员到期或免费版使用付费功能时跳转到会员升级页面
class MembershipCheckerService {
  static final MembershipCheckerService _instance = MembershipCheckerService._internal();
  factory MembershipCheckerService() => _instance;

  MembershipCheckerService._internal();

  /// 检查会员状态是否过期
  Future<bool> checkMembershipStatus({required UserProfilePB userProfile, required BuildContext context, String? workspaceId}) async {
    try {
      final subscriptionService = SubscriptionService();
      final currentSubscription = await subscriptionService.getCurrentSubscription(
        userProfile: userProfile,
        caller: 'MembershipCheckerService.checkMembershipStatus',
      );

      final subscription = currentSubscription?.subscription;
      final usage = currentSubscription?.usage;

      // 检查是否已到期
      final endDate = subscription?.endDate;
      if (endDate != null && endDate.isBefore(DateTime.now())) {
          // 跳转到升级页面
          await navigateToUpgradePage(
            context,
            userProfile: userProfile,
            workspaceId: workspaceId,
            featureName: '创建工作区',
          );
          return false;
      }
      return true;
    } catch (e) {
      Log.error('Failed to check membership status: $e');
      return false;
    }
  }

  /// 检查存储限制
  /// 
  /// [userProfile] 用户信息
  /// [requiredStorageMB] 所需存储空间（MB）
  /// 
  /// 返回 true 表示有足够空间，false 表示空间不足
  Future<bool> checkStorageLimit({
    required UserProfilePB userProfile,
    required int requiredStorageMB,
  }) async {
    try {
      final subscriptionService = SubscriptionService();
      final currentSubscription = await subscriptionService.getCurrentSubscription(
        userProfile: userProfile,
        caller: 'MembershipCheckerService.checkStorageLimit',
      );

      final storageUsedGb = currentSubscription?.usage?.storageUsedGb ?? 0;
      final storageTotalGb = currentSubscription?.usage?.storageTotalGb ?? 0;
      final requiredStorageGb = requiredStorageMB / 1024;
      
      return (storageUsedGb + requiredStorageGb) < storageTotalGb;
    } catch (e) {
      Log.error('Failed to check storage limit: $e');
      return false;
    }
  }

  /// 检查工作区限制
  /// 
  /// [userProfile] 用户信息
  /// [currentWorkspaceCount] 当前工作区数量
  /// [additionalWorkspaces] 要添加的工作区数量
  /// 
  /// 返回 true 表示可以创建，false 表示达到限制
  Future<bool> checkWorkspaceLimit({
    required UserProfilePB userProfile,
    required int currentWorkspaceCount,
  }) async {
    try {
      // 由于当前没有从订阅信息中获取工作区限制的字段，暂时返回true
      final subscriptionService = SubscriptionService();
      final currentSubscription = await subscriptionService.getCurrentSubscription(
        userProfile: userProfile,
        caller: 'MembershipCheckerService.checkStorageLimit',
      );
      // 实际限制检查应该在后端进行
      final collaborativeWorkspaceLimit = currentSubscription?.planDetails?.collaborativeWorkspaceLimit ?? 0;
      return currentWorkspaceCount < collaborativeWorkspaceLimit;
    } catch (e) {
      Log.error('Failed to check workspace limit: $e');
      return true;
    }
  }

  /// 检查AI对话限制
  /// 
  /// [userProfile] 用户信息
  /// [additionalChats] 要添加的对话次数
  /// 
  /// 返回 true 表示可以使用，false 表示达到限制
  Future<bool> checkAIChatLimit({
    required UserProfilePB userProfile,
    int additionalChats = 1,
  }) async {
    try {
      final subscriptionService = SubscriptionService();
      final currentSubscription = await subscriptionService.getCurrentSubscription(
        userProfile: userProfile,
        caller: 'MembershipCheckerService.checkAIChatLimit',
      );

      final aiChatRemaining = currentSubscription?.usage?.aiChatRemaining ?? 0;
      
      return aiChatRemaining > 0;
    } catch (e) {
      Log.error('Failed to check AI chat limit: $e');
      return false;
    }
  }

  /// 检查用户是否有权限使用付费功能
  Future<bool> hasPermissionForFeature({
    required UserProfilePB userProfile,
    required PremiumFeature feature,
    int? spaceNum,
  }) async {
    try {
      // 检查具体功能权限
      switch (feature) {
        case PremiumFeature.cloudSync:
          return true; // 所有付费会员都可以使用云同步
        case PremiumFeature.aiFeatures:
          return await checkAIChatLimit(userProfile: userProfile);
        case PremiumFeature.versionHistory:
          return true; // 所有付费会员都可以使用版本历史
        case PremiumFeature.workspaceMembers:
          return true; // 所有付费会员都可以使用工作区成员管理
        case PremiumFeature.workspaceCreate:
          return await checkWorkspaceLimit(userProfile: userProfile, currentWorkspaceCount: spaceNum ?? 0);
      }
    } catch (e) {
      Log.error('Failed to check feature permission: $e');
      return false;
    }
  }

  /// 跳转到会员升级页面
  Future<void> navigateToUpgradePage(BuildContext context, {
    required UserProfilePB userProfile,
    String? workspaceId,
    String? featureName,
  }) async {
    try {
      showSettingsDialog(
        context,
          userProfile,
        context.read<UserWorkspaceBloc>(), SettingsPage.accountManagement
      );
    } catch (e) {
      Log.error('Failed to navigate to upgrade page: $e');
    }
  }

  /// 检查并处理付费功能访问
  /// 
  /// 如果用户没有权限使用付费功能，跳转到会员升级页面
  /// 
  /// [context] 上下文
  /// [userProfile] 用户信息
  /// [feature] 要检查的付费功能
  /// [featureName] 功能名称（用于提示信息）
  /// [workspaceId] 工作区ID
  /// [spaceNum] 工作区总数
  /// 
  /// 返回 true 表示用户有权限使用该功能，false 表示没有权限并已跳转到升级页面
  Future<bool> checkAndHandlePremiumFeatureAccess({
    required BuildContext context,
    required UserProfilePB userProfile,
    required PremiumFeature feature,
    String? featureName,
    String? workspaceId,
    int? spaceNum,
  }) async {
    final hasPermission = await hasPermissionForFeature(
      userProfile: userProfile,
      feature: feature,
      spaceNum: spaceNum,
    );

    if (!hasPermission ) {
      // 跳转到会员升级页面
      await navigateToUpgradePage(
        context,
        userProfile: userProfile,
        workspaceId: workspaceId,
        featureName: featureName,
      );
      return false;
    }

    return true;
  }
  
  /// 检查并处理工作区创建校验
  /// 
  /// 专门用于处理工作区创建时的会员状态检查
  /// 
  /// [context] 上下文
  /// [userProfile] 用户信息
  /// [currentWorkspaceCount] 当前工作区数量
  /// [workspaceId] 工作区ID
  /// [showToast] 是否显示提示信息
  /// 
  /// 返回 true 表示可以创建工作区，false 表示不能创建并已处理（跳转到升级页面或显示提示）
  Future<bool> checkAndHandleWorkspaceCreation({
    required BuildContext context,
    required UserProfilePB userProfile,
    required int currentWorkspaceCount,
    String? workspaceId,
    bool showToast = true,
  }) async {
    try {
      // 检查工作区数量是否超过限制
      final canCreate = await checkWorkspaceLimit(
        userProfile: userProfile,
        currentWorkspaceCount: currentWorkspaceCount,
      );
      if (!canCreate) {
        // 显示提示并跳转到升级页面
        if (showToast) {
          showToastNotification(
            message: '您已达到工作区数量限制，请升级会员以创建更多工作区',
            type: ToastificationType.error,
          );
        }
        
        // 跳转到升级页面
        await navigateToUpgradePage(
          context,
          userProfile: userProfile,
          workspaceId: workspaceId,
          featureName: '创建工作区',
        );
        
        return false;
      }
      
      return true;
    } catch (e) {
      Log.error('Error checking workspace creation: $e');
      // 如果检查失败，默认允许创建工作区
      return true;
    }
  }

  /// 检查并处理存储限制
  /// 
  /// 用于处理文件上传、云同步等场景的存储限制检查
  /// 
  /// [context] 上下文
  /// [userProfile] 用户信息
  /// [requiredStorageMB] 所需存储空间（MB），默认为0表示只检查当前存储状态
  /// [workspaceId] 工作区ID
  /// [showToast] 是否显示提示信息
  /// [featureName] 功能名称（用于提示信息）
  /// 
  /// 返回 true 表示有足够空间，false 表示空间不足并已处理（跳转到升级页面或显示提示）
  Future<bool> checkAndHandleStorageLimit({
    required BuildContext context,
    required UserProfilePB userProfile,
    int requiredStorageMB = 0,
    String? workspaceId,
    bool showToast = true,
    String? featureName = '存储空间',
  }) async {
    try {
      // 检查是否有足够空间
      final hasEnoughSpace = await checkStorageLimit(
        userProfile: userProfile,
        requiredStorageMB: requiredStorageMB,
      );
      
      if (!hasEnoughSpace) {
        // 获取当前订阅信息
        final subscriptionService = SubscriptionService();
        final currentSubscription = await subscriptionService.getCurrentSubscription(
          userProfile: userProfile,
          caller: 'MembershipCheckerService.checkAndHandleStorageLimit',
        );
        
        final storageTotalGb = currentSubscription?.usage?.storageTotalGb ?? 0;
        
        // 显示提示并跳转到升级页面
        if (showToast) {
          showToastNotification(
            message: '存储空间不足，您的${storageTotalGb}GB配额已用完，请升级会员以获得更多存储空间',
            type: ToastificationType.error,
          );
        }
        
        // 跳转到升级页面
        await navigateToUpgradePage(
          context,
          userProfile: userProfile,
          workspaceId: workspaceId,
          featureName: featureName,
        );
        
        return false;
      }
      
      return true;
    } catch (e) {
      Log.error('Error checking storage limit: $e');
      // 如果检查失败，默认允许操作
      return true;
    }
  }

  /// 检查并处理AI对话限制
  /// 
  /// 专门用于处理AI对话时的次数限制检查
  /// 
  /// [context] 上下文
  /// [userProfile] 用户信息
  /// [workspaceId] 工作区ID
  /// [showToast] 是否显示提示信息
  /// 
  /// 返回 true 表示可以使用AI对话，false 表示次数已用完并已处理（跳转到升级页面或显示提示）
  Future<bool> checkAndHandleAIChatLimit({
    required BuildContext context,
    required UserProfilePB userProfile,
    String? workspaceId,
    bool showToast = true,
  }) async {
    try {
      // 检查AI对话次数是否已用完
      final canUseAI = await checkAIChatLimit(userProfile: userProfile);
      if (!canUseAI) {
        // 显示提示并跳转到升级页面
        if (showToast) {
          showToastNotification(
            message: 'AI对话次数已用完，请升级会员以获得更多对话次数',
            type: ToastificationType.error,
          );
        }
        
        // 跳转到升级页面
        await navigateToUpgradePage(
          context,
          userProfile: userProfile,
          workspaceId: workspaceId,
          featureName: 'AI对话',
        );
        
        return false;
      }
      
      return true;
    } catch (e) {
      Log.error('Error checking AI chat limit: $e');
      // 如果检查失败，默认允许使用AI
      return true;
    }
  }
}

/// 会员状态检查扩展
/// 
/// 为 BuildContext 添加会员状态检查方法
extension MembershipCheckerExtension on BuildContext {
  /// 检查会员状态
  Future<bool> checkMembershipStatus({String? workspaceId}) async {
    try {
      final userResult = await UserBackendService.getCurrentUserProfile();
      final userProfile = userResult.fold(
        (user) => user,
        (error) => throw Exception('Failed to get user profile: ${error.msg}'),
      );

      return await MembershipCheckerService().checkMembershipStatus(context: this,userProfile: userProfile,workspaceId: workspaceId);
    } catch (e) {
      Log.error('Failed to check membership status: $e');
      return true;
    }
  }

  /// 检查并处理工作区创建校验
  Future<bool> checkAndHandleWorkspaceCreation({
    required int currentWorkspaceCount,
    String? workspaceId,
    bool showToast = false,
  }) async {
    try {
      final userResult = await UserBackendService.getCurrentUserProfile();
      final userProfile = userResult.fold(
        (user) => user,
        (error) => throw Exception('Failed to get user profile: ${error.msg}'),
      );

      return await MembershipCheckerService().checkAndHandleWorkspaceCreation(
        context: this,
        userProfile: userProfile,
        currentWorkspaceCount: currentWorkspaceCount,
        workspaceId: workspaceId,
        showToast: showToast,
      );
    } catch (e) {
      Log.error('Failed to check workspace creation: $e');
      return true;
    }
  }

  /// 检查并处理存储限制
  Future<bool> checkAndHandleStorageLimit({
    int requiredStorageMB = 0,
    String? workspaceId,
    bool showToast = false,
    String? featureName = '存储空间',
  }) async {
    try {
      final userResult = await UserBackendService.getCurrentUserProfile();
      final userProfile = userResult.fold(
        (user) => user,
        (error) => throw Exception('Failed to get user profile: ${error.msg}'),
      );

      return await MembershipCheckerService().checkAndHandleStorageLimit(
        context: this,
        userProfile: userProfile,
        requiredStorageMB: requiredStorageMB,
        workspaceId: workspaceId,
        showToast: showToast,
        featureName: featureName,
      );
    } catch (e) {
      Log.error('Failed to check storage limit: $e');
      return true;
    }
  }

  /// 检查并处理云同步存储限制
  Future<bool> checkAndHandleCloudSyncStorageLimit({
    String? workspaceId,
    bool showToast = false,
  }) async {
    try {
      return await checkAndHandleStorageLimit(
        requiredStorageMB: 0, // 只检查当前存储状态
        workspaceId: workspaceId,
        showToast: showToast,
        featureName: '云同步存储',
      );
    } catch (e) {
      Log.error('Failed to check cloud sync storage limit: $e');
      return true;
    }
  }

  /// 检查并处理AI对话限制
  Future<bool> checkAndHandleAIChatLimit({
    String? workspaceId,
    bool showToast = false,
  }) async {
    try {
      final userResult = await UserBackendService.getCurrentUserProfile();
      final userProfile = userResult.fold(
        (user) => user,
        (error) => throw Exception('Failed to get user profile: ${error.msg}'),
      );

      return await MembershipCheckerService().checkAndHandleAIChatLimit(
        context: this,
        userProfile: userProfile,
        workspaceId: workspaceId,
        showToast: showToast,
      );
    } catch (e) {
      Log.error('Failed to check AI chat limit: $e');
      return true;
    }
  }

  /// 跳转到会员升级页面
  Future<void> navigateToUpgradePage({
    String? workspaceId,
    String? featureName,
  }) async {
    try {
      final userResult = await UserBackendService.getCurrentUserProfile();
      final userProfile = userResult.fold(
        (user) => user,
        (error) => throw Exception('Failed to get user profile: ${error.msg}'),
      );

      await MembershipCheckerService().navigateToUpgradePage(
        this,
        userProfile: userProfile,
        workspaceId: workspaceId,
        featureName: featureName,
      );
    } catch (e) {
      Log.error('Failed to navigate to upgrade page: $e');
    }
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/payment/payment_api.dart';
import 'package:appflowy/workspace/application/payment/payment_util.dart'
    show PaymentMethod, PaymentPlatformSupport, PaymentUtil;
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:bloc/bloc.dart';
import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:equatable/equatable.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:http/http.dart' as http;

import '../../subscription/subscription_service.dart';
import '../../subscription_success_listenable/subscription_success_listenable.dart';

part 'account_management_bloc.freezed.dart';

enum PurchaseDurationOption {
  monthly,
  yearly,
}

enum MembershipTab {
  upgrade,
}

class RemotePlan {
  final int? id;
  final String? planCode;
  final String? planName;
  final String? planNameCn;
  final double? monthlyPriceYuan;
  final double? yearlyPriceYuan;
  final int? cloudStorageGb;
  final bool hasInbox;
  final bool hasMultiDeviceSync;
  final bool hasApiSupport;
  final int? versionHistoryDays;
  final int? aiChatCountPerMonth;
  final int? aiImageGenerationPerMonth;
  final bool hasShareLink;
  final bool hasPublish;
  final int? workspaceMemberLimit;
  final int? collaborativeWorkspaceLimit;
  final int? pagePermissionGuestEditors;
  final bool hasSpaceMemberManagement;
  final bool hasSpaceMemberGrouping;
  final bool isActive;

  const RemotePlan({
    required this.id,
    required this.planCode,
    required this.planName,
    required this.planNameCn,
    required this.monthlyPriceYuan,
    required this.yearlyPriceYuan,
    required this.cloudStorageGb,
    required this.hasInbox,
    required this.hasMultiDeviceSync,
    required this.hasApiSupport,
    required this.versionHistoryDays,
    required this.aiChatCountPerMonth,
    required this.aiImageGenerationPerMonth,
    required this.hasShareLink,
    required this.hasPublish,
    required this.workspaceMemberLimit,
    required this.collaborativeWorkspaceLimit,
    required this.pagePermissionGuestEditors,
    required this.hasSpaceMemberManagement,
    required this.hasSpaceMemberGrouping,
    required this.isActive,
  });

  factory RemotePlan.fromJson(Map<String, dynamic> json) {
    double? _parseDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      final str = value.toString();
      return double.tryParse(str);
    }

    int? _parseInt(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    return RemotePlan(
      id: _parseInt(json['id']),
      planCode: json['plan_code'] as String? ?? '',
      planName: json['plan_name'] as String? ?? '',
      planNameCn: json['plan_name_cn'] as String? ?? '',
      monthlyPriceYuan: _parseDouble(json['monthly_price_yuan']),
      yearlyPriceYuan: _parseDouble(json['yearly_price_yuan']),
      cloudStorageGb: _parseInt(json['cloud_storage_gb']),
      hasInbox: json['has_inbox'] as bool? ?? false,
      hasMultiDeviceSync: json['has_multi_device_sync'] as bool? ?? false,
      hasApiSupport: json['has_api_support'] as bool? ?? false,
      versionHistoryDays: _parseInt(json['version_history_days']),
      aiChatCountPerMonth: _parseInt(json['ai_chat_count_per_month']),
      aiImageGenerationPerMonth:
          _parseInt(json['ai_image_generation_per_month']),
      hasShareLink: json['has_share_link'] as bool? ?? false,
      hasPublish: json['has_publish'] as bool? ?? false,
      workspaceMemberLimit: _parseInt(json['workspace_member_limit']),
      collaborativeWorkspaceLimit:
          _parseInt(json['collaborative_workspace_limit']),
      pagePermissionGuestEditors:
          _parseInt(json['page_permission_guest_editors']),
      hasSpaceMemberManagement:
          json['has_space_member_management'] as bool? ?? false,
      hasSpaceMemberGrouping:
          json['has_space_member_grouping'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

class AccountManagementBloc
    extends Bloc<AccountManagementEvent, AccountManagementState> {
  AccountManagementBloc({
    required this.workspaceId,
    required this.userProfile,
    required this.currentSubscription,
  }) : super(const AccountManagementState.initial()) {
    // 初始化订阅成功监听器
    _subscriptionSuccessListenable = getIt<SubscriptionSuccessListenable>();
    _subscriptionSuccessListener = () {
      // 支付成功后刷新订阅信息
      add(const AccountManagementEvent.loadSubscriptionInfo());
      add(const AccountManagementEvent.loadSubscriptionPlans());
    };
    _subscriptionSuccessListenable.addListener(_subscriptionSuccessListener);
    
    on<AccountManagementEvent>((event, emit) async {
      await event.when(
        initial: () async => _initial(emit),
        loadSubscriptionInfo: () async => _loadSubscriptionInfo(emit),
        loadSubscriptionPlans: () async => _loadSubscriptionPlans(emit),
        selectPlan: (plan) async => _selectPlan(plan, emit),
        selectDuration: (duration) async => _selectDuration(duration, emit),
        setAgreedProtocols: (agreed) async => _setAgreedProtocols(agreed, emit),
        switchTab: (tab) async => _switchTab(tab, emit),
        createOrUpdateSubscription: (planId, billingType) async =>
            _createOrUpdateSubscription(planId, billingType, emit),
        handleUpgradePay: () async => _handleUpgradePay(emit),
        // 临时注释：等待 freezed 重新生成后取消注释
        startPaymentPolling: (orderNo) async =>
            _startPaymentPolling(orderNo, emit),
        stopPaymentPolling: () async => _stopPaymentPolling(),
        checkPaymentStatus: () async => _checkPaymentStatus(emit),
      );
    });
  }

  final String workspaceId;
  final UserProfilePB userProfile;
  final CurrentSubscription? currentSubscription;

  Timer? _paymentPollingTimer;
  String? _currentPollingOrderNo; // 当前正在轮询的订单号
  late final SubscriptionSuccessListenable _subscriptionSuccessListenable;
  late final VoidCallback _subscriptionSuccessListener;

  String? _extractAccessToken(String? rawToken) {
    if (rawToken == null || rawToken.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(rawToken);
      if (decoded is Map<String, dynamic>) {
        final accessToken = decoded['access_token'] as String?;
        if (accessToken != null && accessToken.isNotEmpty) {
          return accessToken;
        }
      }
    } catch (_) {
      // 不是 JSON，直接返回
      return rawToken;
    }
    return null;
  }

  /// 从当前用户的 token 中解析出 GoTrue 的用户 UUID（JWT 的 sub 字段），
  /// 如果解析失败，则回退为内部自增 ID（userProfile.id）。
  String _getUserUuid() {
    final rawToken = userProfile.token;
    final accessToken = _extractAccessToken(rawToken);
    if (accessToken != null && accessToken.isNotEmpty) {
      try {
        final parts = accessToken.split('.');
        if (parts.length >= 2) {
          final payloadPart = parts[1];
          // base64url -> base64，并补齐 padding
          var normalized = payloadPart.replaceAll('-', '+').replaceAll('_', '/');
          while (normalized.length % 4 != 0) {
            normalized += '=';
          }
          final decoded = utf8.decode(base64.decode(normalized));
          final payload = jsonDecode(decoded);
          if (payload is Map && payload['sub'] is String) {
            return payload['sub'] as String;
          }
        }
      } catch (_) {
        // 解析异常时回退到内部 ID
      }
    }
    return userProfile.id.toString();
  }

  /// 接口 plan_code 与会员级别对应：fmb=免费, standard=Stand, professor=Pro, hiclass=Hiclass
  WorkspacePlanPB? _mapPlanCodeToPb(String code) {
    final lower = code.toLowerCase();
    switch (lower) {
      case 'mfb':
      case 'fmb':
        return WorkspacePlanPB.FreePlan;
      case 'standard':
      case 'stand':
        return WorkspacePlanPB.StandPlan;
      case 'professor':
      case 'pro':
        return WorkspacePlanPB.ProPlan;
      case 'hiclass':
        return WorkspacePlanPB.HiclassPlan;
      default:
        return null;
    }
  }

  Future<void> _initial(Emitter<AccountManagementState> emit) async {
    emit(const AccountManagementState.loading());
    // 1. 先获取当前会员信息，确保后续接口都能拿到最新的订阅计划
    await _loadSubscriptionInfo(emit);

    // 2. 再去拉会员计划列表
    add(const AccountManagementEvent.loadSubscriptionPlans());
  }

  Future<void> _loadSubscriptionInfo(
      Emitter<AccountManagementState> emit) async {
    // 先更新状态为加载中
    state.maybeWhen(
      orElse: () {
        emit(const AccountManagementState.loading());
      },
      ready: (
        subscriptionInfo,
        planConfigs,
        selectedPlan,
        selectedDuration,
        selectedTab,
        agreedProtocols,
        isLoadingSubscription,
        isLoadingPlans,
        isProcessingPayment,
        error,
        paymentResult,
      ) {
        emit(
          AccountManagementState.ready(
            subscriptionInfo: subscriptionInfo,
            planConfigs: planConfigs,
            selectedPlan: selectedPlan,
            selectedDuration: selectedDuration,
            selectedTab: selectedTab,
            agreedProtocols: agreedProtocols,
            isLoadingSubscription: true, // 标记为加载中
            isLoadingPlans: isLoadingPlans,
            isProcessingPayment: isProcessingPayment,
            error: error,
            paymentResult: paymentResult,
          ),
        );
      },
    );

    // 从服务器重新获取订阅信息
    try {
      final currentSubscription = await SubscriptionService().getCurrentSubscription(
        userProfile: userProfile,
        caller: 'AccountManagementBloc._loadSubscriptionInfo',
      );
      _emitSubscriptionInfo(emit, currentSubscription);
    } catch (e, stackTrace) {
      Log.error('Error fetching subscription info: $e', stackTrace);
      _emitSubscriptionInfo(emit, currentSubscription);
    }
  }

  // 辅助方法：根据订阅信息更新状态
  void _emitSubscriptionInfo(
    Emitter<AccountManagementState> emit,
    CurrentSubscription? subscription,
  ) {
    // 使用获取到的订阅信息
    final planCode =
        subscription?.subscription?.planCode ?? 'free_local';
    final mappedPlan = _mapPlanCodeToPb(planCode);
    final currentPlan = mappedPlan ?? WorkspacePlanPB.FreePlan;

    WorkspacePlanPB? selectedPlan;
    if (currentPlan == WorkspacePlanPB.FreePlan) {
      selectedPlan = WorkspacePlanPB.StandPlan;
    } else {
      selectedPlan = currentPlan;
    }

    // 创建一个基于订阅信息的WorkspaceSubscriptionInfoPB
    final info = WorkspaceSubscriptionInfoPB()..plan = currentPlan;

    state.maybeWhen(
      orElse: () {
        emit(
          AccountManagementState.ready(
            subscriptionInfo: info,
            planConfigs: const {},
            selectedPlan: selectedPlan,
            selectedDuration: PurchaseDurationOption.monthly,
            selectedTab: MembershipTab.upgrade,
            agreedProtocols: false,
            isLoadingSubscription: false,
            isLoadingPlans: true,
          ),
        );
      },
      ready: (
        subscriptionInfo,
        planConfigs,
        currentSelectedPlan,
        selectedDuration,
        selectedTab,
        agreedProtocols,
        isLoadingSubscription,
        isLoadingPlans,
        isProcessingPayment,
        error,
        paymentResult,
      ) {
        final finalSelectedPlan = currentSelectedPlan ?? selectedPlan;
        emit(
          AccountManagementState.ready(
            subscriptionInfo: info,
            planConfigs: planConfigs,
            selectedPlan: finalSelectedPlan,
            selectedDuration: selectedDuration,
            selectedTab: selectedTab,
            agreedProtocols: agreedProtocols,
            isLoadingSubscription: false,
            isLoadingPlans: isLoadingPlans,
            isProcessingPayment: isProcessingPayment,
            error: error,
            paymentResult: paymentResult,
          ),
        );
      },
    );
  }

  Future<void> _loadSubscriptionPlans(
      Emitter<AccountManagementState> emit) async {
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;
      if (baseUrl.isEmpty) {
        Log.warn('订阅计划接口 baseUrl 为空，跳过远程加载');
        state.maybeWhen(
          orElse: () {},
          ready: (
            subscriptionInfo,
            planConfigs,
            selectedPlan,
            selectedDuration,
            selectedTab,
            agreedProtocols,
            isLoadingSubscription,
            isLoadingPlans,
            isProcessingPayment,
            error,
            paymentResult,
          ) {
            emit(
              AccountManagementState.ready(
                subscriptionInfo: subscriptionInfo,
                planConfigs: planConfigs,
                selectedPlan: selectedPlan,
                selectedDuration: selectedDuration,
                selectedTab: selectedTab,
                agreedProtocols: agreedProtocols,
                isLoadingSubscription: isLoadingSubscription,
                isLoadingPlans: false,
                isProcessingPayment: isProcessingPayment,
                error: error,
                paymentResult: paymentResult,
              ),
            );
          },
        );
        return;
      }

      final accessToken = _extractAccessToken(userProfile.token);
      if (accessToken == null || accessToken.isEmpty) {
        Log.warn('订阅计划接口无法获取 access_token，使用本地默认配置');
        state.maybeWhen(
          orElse: () {},
          ready: (
            subscriptionInfo,
            planConfigs,
            selectedPlan,
            selectedDuration,
            selectedTab,
            agreedProtocols,
            isLoadingSubscription,
            isLoadingPlans,
            isProcessingPayment,
            error,
            paymentResult,
          ) {
            emit(
              AccountManagementState.ready(
                subscriptionInfo: subscriptionInfo,
                planConfigs: planConfigs,
                selectedPlan: selectedPlan,
                selectedDuration: selectedDuration,
                selectedTab: selectedTab,
                agreedProtocols: agreedProtocols,
                isLoadingSubscription: isLoadingSubscription,
                isLoadingPlans: false,
                isProcessingPayment: isProcessingPayment,
                error: error,
                paymentResult: paymentResult,
              ),
            );
          },
        );
        return;
      }

      final uri = Uri.parse(baseUrl).replace(path: 'api/subscription/plans');
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        Log.warn(
            '订阅计划接口返回非 200: ${response.statusCode}, body: ${response.body}');
        state.maybeWhen(
          orElse: () {},
          ready: (
            subscriptionInfo,
            planConfigs,
            selectedPlan,
            selectedDuration,
            selectedTab,
            agreedProtocols,
            isLoadingSubscription,
            isLoadingPlans,
            isProcessingPayment,
            error,
            paymentResult,
          ) {
            emit(
              AccountManagementState.ready(
                subscriptionInfo: subscriptionInfo,
                planConfigs: planConfigs,
                selectedPlan: selectedPlan,
                selectedDuration: selectedDuration,
                selectedTab: selectedTab,
                agreedProtocols: agreedProtocols,
                isLoadingSubscription: isLoadingSubscription,
                isLoadingPlans: false,
                isProcessingPayment: isProcessingPayment,
                error: error,
                paymentResult: paymentResult,
              ),
            );
          },
        );
        return;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final code = decoded['code'] as int? ?? -1;
      if (code != 0) {
        final message = decoded['message'] as String? ?? 'unknown error';
        Log.warn('订阅计划接口返回错误 code=$code, message=$message');
        state.maybeWhen(
          orElse: () {},
          ready: (
            subscriptionInfo,
            planConfigs,
            selectedPlan,
            selectedDuration,
            selectedTab,
            agreedProtocols,
            isLoadingSubscription,
            isLoadingPlans,
            isProcessingPayment,
            error,
            paymentResult,
          ) {
            emit(
              AccountManagementState.ready(
                subscriptionInfo: subscriptionInfo,
                planConfigs: planConfigs,
                selectedPlan: selectedPlan,
                selectedDuration: selectedDuration,
                selectedTab: selectedTab,
                agreedProtocols: agreedProtocols,
                isLoadingSubscription: isLoadingSubscription,
                isLoadingPlans: false,
                isProcessingPayment: isProcessingPayment,
                error: error,
                paymentResult: paymentResult,
              ),
            );
          },
        );
        return;
      }

      final data = decoded['data'];
      if (data is! List) {
        Log.warn('订阅计划接口 data 非数组，使用本地默认配置');
        state.maybeWhen(
          orElse: () {},
          ready: (
            subscriptionInfo,
            planConfigs,
            selectedPlan,
            selectedDuration,
            selectedTab,
            agreedProtocols,
            isLoadingSubscription,
            isLoadingPlans,
            isProcessingPayment,
            error,
            paymentResult,
          ) {
            emit(
              AccountManagementState.ready(
                subscriptionInfo: subscriptionInfo,
                planConfigs: planConfigs,
                selectedPlan: selectedPlan,
                selectedDuration: selectedDuration,
                selectedTab: selectedTab,
                agreedProtocols: agreedProtocols,
                isLoadingSubscription: isLoadingSubscription,
                isLoadingPlans: false,
                isProcessingPayment: isProcessingPayment,
                error: error,
                paymentResult: paymentResult,
              ),
            );
          },
        );
        return;
      }

      final Map<WorkspacePlanPB, RemotePlan> configs = {};
      Log.info('开始处理订阅计划数据，原始数据条数：${data.length}');
      int processed = 0;
      int skippedType = 0;
      int skippedCode = 0;
      int skippedMap = 0;
      
      for (final item in data) {
        processed++;
        if (item is! Map<String, dynamic>) {
          skippedType++;
          Log.warn('跳过非Map类型数据：${item.runtimeType}');
          continue;
        }
        
        final codeStr = item['plan_code'] as String? ?? '';
        if (codeStr.isEmpty) {
          skippedCode++;
          Log.warn('跳过plan_code为空的数据：$item');
          continue;
        }
        
        final mappedPlan = _mapPlanCodeToPb(codeStr);
        if (mappedPlan == null) {
          skippedMap++;
          Log.warn('无法映射的plan_code：$codeStr');
          // 尝试添加默认映射逻辑
          if (codeStr.toLowerCase().contains('free')) {
            configs[WorkspacePlanPB.FreePlan] = RemotePlan.fromJson(item);
            Log.info('已将 $codeStr 映射为 FreePlan');
          } else if (codeStr.toLowerCase().contains('standard') || codeStr.toLowerCase().contains('stand')) {
            configs[WorkspacePlanPB.StandPlan] = RemotePlan.fromJson(item);
            Log.info('已将 $codeStr 映射为 StandPlan');
          } else if (codeStr.toLowerCase().contains('pro')) {
            configs[WorkspacePlanPB.ProPlan] = RemotePlan.fromJson(item);
            Log.info('已将 $codeStr 映射为 ProPlan');
          } else if (codeStr.toLowerCase().contains('hiclass') || codeStr.toLowerCase().contains('hi-class')) {
            configs[WorkspacePlanPB.HiclassPlan] = RemotePlan.fromJson(item);
            Log.info('已将 $codeStr 映射为 HiclassPlan');
          } else {
            continue;
          }
        } else {
          configs[mappedPlan] = RemotePlan.fromJson(item);
          Log.info('成功映射 plan_code: $codeStr → $mappedPlan');
        }
      }
      
      Log.info('订阅计划数据处理完成：');
      Log.info('- 原始数据：${data.length} 条');
      Log.info('- 处理数据：$processed 条');
      Log.info('- 跳过非Map类型：$skippedType 条');
      Log.info('- 跳过空plan_code：$skippedCode 条');
      Log.info('- 跳过无法映射：$skippedMap 条');
      Log.info('- 最终配置：${configs.length} 条');
      Log.info('- 配置详情：${configs.keys}');


      state.maybeWhen(
        orElse: () {},
        ready: (
          subscriptionInfo,
          planConfigs,
          selectedPlan,
          selectedDuration,
          selectedTab,
          agreedProtocols,
          isLoadingSubscription,
          isLoadingPlans,
          isProcessingPayment,
          error,
          paymentResult,
        ) {
          emit(
            AccountManagementState.ready(
              subscriptionInfo: subscriptionInfo,
              planConfigs: configs,
              selectedPlan: selectedPlan,
              selectedDuration: selectedDuration,
              selectedTab: selectedTab,
              agreedProtocols: agreedProtocols,
              isLoadingSubscription: isLoadingSubscription,
              isLoadingPlans: false,
              isProcessingPayment: isProcessingPayment,
              error: error,
              paymentResult: paymentResult,
            ),
          );
        },
      );
    } catch (e, stackTrace) {
      Log.error('订阅计划接口请求异常: $e', e, stackTrace);
      state.maybeWhen(
        orElse: () {},
        ready: (
          subscriptionInfo,
          planConfigs,
          selectedPlan,
          selectedDuration,
          selectedTab,
          agreedProtocols,
          isLoadingSubscription,
          isLoadingPlans,
          isProcessingPayment,
          error,
          paymentResult,
        ) {
          emit(
            AccountManagementState.ready(
              subscriptionInfo: subscriptionInfo,
              planConfigs: planConfigs,
              selectedPlan: selectedPlan,
              selectedDuration: selectedDuration,
              selectedTab: selectedTab,
              agreedProtocols: agreedProtocols,
              isLoadingSubscription: isLoadingSubscription,
              isLoadingPlans: false,
              isProcessingPayment: isProcessingPayment,
              error: error,
              paymentResult: paymentResult,
            ),
          );
        },
      );
    }
  }



  void _selectPlan(WorkspacePlanPB plan, Emitter<AccountManagementState> emit) {
    state.maybeWhen(
      orElse: () {},
      ready: (
        subscriptionInfo,
        planConfigs,
        selectedPlan,
        selectedDuration,
        selectedTab,
        agreedProtocols,
        isLoadingSubscription,
        isLoadingPlans,
        isProcessingPayment,
        error,
        paymentResult,
      ) {
        emit(
          AccountManagementState.ready(
            subscriptionInfo: subscriptionInfo,
            planConfigs: planConfigs,
            selectedPlan: plan,
            selectedDuration: selectedDuration,
            selectedTab: selectedTab,
            agreedProtocols: agreedProtocols,
            isLoadingSubscription: isLoadingSubscription,
            isLoadingPlans: isLoadingPlans,
            isProcessingPayment: isProcessingPayment,
            error: error,
            paymentResult: paymentResult,
          ),
        );
      },
    );
  }

  void _selectDuration(
      PurchaseDurationOption duration, Emitter<AccountManagementState> emit) {
    state.maybeWhen(
      orElse: () {},
      ready: (
        subscriptionInfo,
        planConfigs,
        selectedPlan,
        selectedDuration,
        selectedTab,
        agreedProtocols,
        isLoadingSubscription,
        isLoadingPlans,
        isProcessingPayment,
        error,
        paymentResult,
      ) {
        emit(
          AccountManagementState.ready(
            subscriptionInfo: subscriptionInfo,
            planConfigs: planConfigs,
            selectedPlan: selectedPlan,
            selectedDuration: duration,
            selectedTab: selectedTab,
            agreedProtocols: agreedProtocols,
            isLoadingSubscription: isLoadingSubscription,
            isLoadingPlans: isLoadingPlans,
            isProcessingPayment: isProcessingPayment,
            error: error,
            paymentResult: paymentResult,
          ),
        );
      },
    );
  }



  void _setAgreedProtocols(bool agreed, Emitter<AccountManagementState> emit) {
    state.maybeWhen(
      orElse: () {},
      ready: (
        subscriptionInfo,
        planConfigs,
        selectedPlan,
        selectedDuration,
        selectedTab,
        agreedProtocols,
        isLoadingSubscription,
        isLoadingPlans,
        isProcessingPayment,
        error,
        paymentResult,
      ) {
        emit(
          AccountManagementState.ready(
            subscriptionInfo: subscriptionInfo,
            planConfigs: planConfigs,
            selectedPlan: selectedPlan,
            selectedDuration: selectedDuration,
            selectedTab: selectedTab,
            agreedProtocols: agreed,
            isLoadingSubscription: isLoadingSubscription,
            isLoadingPlans: isLoadingPlans,
            isProcessingPayment: isProcessingPayment,
            error: error,
            paymentResult: paymentResult,
          ),
        );
      },
    );
  }

  void _switchTab(MembershipTab tab, Emitter<AccountManagementState> emit) {
    state.maybeWhen(
      orElse: () {},
      ready: (
        subscriptionInfo,
        planConfigs,
        selectedPlan,
        selectedDuration,
        selectedTab,
        agreedProtocols,
        isLoadingSubscription,
        isLoadingPlans,
        isProcessingPayment,
        error,
        paymentResult,
      ) {
        // 切换 Tab 时按需刷新对应的数据列表
        if (tab == MembershipTab.upgrade) {
          add(const AccountManagementEvent.loadSubscriptionPlans());
        }

        // 切换 Tab 时重置“同意协议”开关和支付状态，避免误操作
        final resetAgreedProtocols = false;

        emit(
          AccountManagementState.ready(
            subscriptionInfo: subscriptionInfo,
            planConfigs: planConfigs,
            selectedPlan: selectedPlan,
            selectedDuration: selectedDuration,
            selectedTab: tab,
            agreedProtocols: resetAgreedProtocols,
            isLoadingSubscription: isLoadingSubscription,
            isLoadingPlans: isLoadingPlans,
            isProcessingPayment: false,
            error: error,
            paymentResult: paymentResult,
          ),
        );
      },
    );
  }

  ///订阅会员，支付成功后调用
  Future<void> _createOrUpdateSubscription(
    int planId,
    String billingType,
    Emitter<AccountManagementState> emit,
  ) async {
    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;
      if (baseUrl.isEmpty) {
        Log.warn('订阅接口 baseUrl 为空');
        state.maybeWhen(
          orElse: () {},
          ready: (
            subscriptionInfo,
            planConfigs,
            selectedPlan,
            selectedDuration,
            selectedTab,
            agreedProtocols,
            isLoadingSubscription,
            isLoadingPlans,
            isProcessingPayment,
            error,
            paymentResult,
          ) {
            emit(
              AccountManagementState.ready(
                subscriptionInfo: subscriptionInfo,
                planConfigs: planConfigs,
                selectedPlan: selectedPlan,
                selectedDuration: selectedDuration,
                selectedTab: selectedTab,
                agreedProtocols: agreedProtocols,
                isLoadingSubscription: isLoadingSubscription,
                isLoadingPlans: isLoadingPlans,
                isProcessingPayment: isProcessingPayment,
                error: '无法创建订阅：服务地址为空',
                paymentResult: paymentResult,
              ),
            );
          },
        );
        return;
      }

      final accessToken = _extractAccessToken(userProfile.token);
      if (accessToken == null || accessToken.isEmpty) {
        Log.warn('订阅接口缺少 access_token');
        state.maybeWhen(
          orElse: () {},
          ready: (
            subscriptionInfo,
            planConfigs,
            selectedPlan,
            selectedDuration,
            selectedTab,
            agreedProtocols,
            isLoadingSubscription,
            isLoadingPlans,
            isProcessingPayment,
            error,
            paymentResult,
          ) {
            emit(
              AccountManagementState.ready(
                subscriptionInfo: subscriptionInfo,
                planConfigs: planConfigs,
                selectedPlan: selectedPlan,
                selectedDuration: selectedDuration,
                selectedTab: selectedTab,
                agreedProtocols: agreedProtocols,
                isLoadingSubscription: isLoadingSubscription,
                isLoadingPlans: isLoadingPlans,
                isProcessingPayment: isProcessingPayment,
                error: '无法创建订阅：未登录或 token 失效',
                paymentResult: paymentResult,
              ),
            );
          },
        );
        return;
      }

      final uri =
          Uri.parse(baseUrl).replace(path: '/api/subscription/subscribe');
      final body = jsonEncode({
        'plan_id': planId,
        'billing_type': billingType,
      });

      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: body,
      );

      if (response.statusCode != 200) {
        Log.warn('创建订阅失败: ${response.statusCode}, body: ${response.body}');
        state.maybeWhen(
          orElse: () {},
          ready: (
            subscriptionInfo,
            planConfigs,
            selectedPlan,
            selectedDuration,
            selectedTab,
            agreedProtocols,
            isLoadingSubscription,
            isLoadingPlans,
            isProcessingPayment,
            error,
            paymentResult,
          ) {
            emit(
              AccountManagementState.ready(
                subscriptionInfo: subscriptionInfo,
                planConfigs: planConfigs,
                selectedPlan: selectedPlan,
                selectedDuration: selectedDuration,
                selectedTab: selectedTab,
                agreedProtocols: agreedProtocols,
                isLoadingSubscription: isLoadingSubscription,
                isLoadingPlans: isLoadingPlans,
                isProcessingPayment: isProcessingPayment,
                error: '创建订阅失败：HTTP ${response.statusCode}',
                paymentResult: paymentResult,
              ),
            );
          },
        );
        return;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final code = decoded['code'] as int? ?? -1;
      if (code != 0) {
        final msg = decoded['message'] as String? ?? '创建订阅失败';
        state.maybeWhen(
          orElse: () {},
          ready: (
            subscriptionInfo,
            planConfigs,
            selectedPlan,
            selectedDuration,
            selectedTab,
            agreedProtocols,
            isLoadingSubscription,
            isLoadingPlans,
            isProcessingPayment,
            error,
            paymentResult,
          ) {
            emit(
              AccountManagementState.ready(
                subscriptionInfo: subscriptionInfo,
                planConfigs: planConfigs,
                selectedPlan: selectedPlan,
                selectedDuration: selectedDuration,
                selectedTab: selectedTab,
                agreedProtocols: agreedProtocols,
                isLoadingSubscription: isLoadingSubscription,
                isLoadingPlans: isLoadingPlans,
                isProcessingPayment: isProcessingPayment,
                error: msg,
                paymentResult: paymentResult,
              ),
            );
          },
        );
        return;
      }

      Log.info('订阅创建/更新成功: ${decoded['data']}');
      state.maybeWhen(
        orElse: () {},
        ready: (
          subscriptionInfo,
          planConfigs,
          selectedPlan,
          selectedDuration,
          selectedTab,
          agreedProtocols,
          isLoadingSubscription,
          isLoadingPlans,
          isProcessingPayment,
          error,
          paymentResult,
        ) {
          emit(
            AccountManagementState.ready(
              subscriptionInfo: subscriptionInfo,
              planConfigs: planConfigs,
              selectedPlan: selectedPlan,
              selectedDuration: selectedDuration,
              selectedTab: selectedTab,
              agreedProtocols: agreedProtocols,
              isLoadingSubscription: isLoadingSubscription,
              isLoadingPlans: isLoadingPlans,
              isProcessingPayment: isProcessingPayment,
              error: null,
              paymentResult: paymentResult,
            ),
          );
        },
      );
    } catch (e, stackTrace) {
      Log.error('创建订阅异常: $e', e, stackTrace);
      state.maybeWhen(
        orElse: () {},
        ready: (
          subscriptionInfo,
          planConfigs,
          selectedPlan,
          selectedDuration,
          selectedTab,
          agreedProtocols,
          isLoadingSubscription,
          isLoadingPlans,
          isProcessingPayment,
          error,
          paymentResult,
        ) {
          emit(
            AccountManagementState.ready(
              subscriptionInfo: subscriptionInfo,
              planConfigs: planConfigs,
              selectedPlan: selectedPlan,
              selectedDuration: selectedDuration,
              selectedTab: selectedTab,
              agreedProtocols: agreedProtocols,
              isLoadingSubscription: isLoadingSubscription,
              isLoadingPlans: isLoadingPlans,
              isProcessingPayment: isProcessingPayment,
              error: '创建订阅异常',
              paymentResult: paymentResult,
            ),
          );
        },
      );
    }
  }

  Future<void> _handleUpgradePay(Emitter<AccountManagementState> emit) async {
    await state.maybeWhen(
        orElse: () async {},
        ready: (
          subscriptionInfo,
          planConfigs,
          selectedPlan,
          selectedDuration,
          selectedTab,
          agreedProtocols,
          isLoadingSubscription,
          isLoadingPlans,
          isProcessingPayment,
          error,
          paymentResult,
        ) async {
          // 计算有效计划
          final availablePlans = planConfigs.keys
              .where((plan) => plan != WorkspacePlanPB.FreePlan)
              .toList();
          if (availablePlans.isEmpty) {
            emit(
              AccountManagementState.ready(
                subscriptionInfo: subscriptionInfo,
                planConfigs: planConfigs,
                selectedPlan: selectedPlan,
                selectedDuration: selectedDuration,
                selectedTab: selectedTab,
                agreedProtocols: agreedProtocols,
                isLoadingSubscription: isLoadingSubscription,
                isLoadingPlans: isLoadingPlans,
                isProcessingPayment: false,
                error: '无法获取计划ID，暂无法订阅',
                paymentResult: paymentResult,
              ),
            );
            return;
          }

          final effectivePlan = (selectedPlan != null &&
                  selectedPlan != WorkspacePlanPB.FreePlan &&
                  planConfigs.containsKey(selectedPlan))
              ? selectedPlan
              : ((subscriptionInfo != null &&
                      subscriptionInfo.plan != WorkspacePlanPB.FreePlan &&
                      planConfigs.containsKey(subscriptionInfo.plan))
                  ? subscriptionInfo.plan
                  : availablePlans.first);

          final planConfig = planConfigs[effectivePlan];
          if (planConfig == null) {
            emit(
              AccountManagementState.ready(
                subscriptionInfo: subscriptionInfo,
                planConfigs: planConfigs,
                selectedPlan: selectedPlan,
                selectedDuration: selectedDuration,
                selectedTab: selectedTab,
                agreedProtocols: agreedProtocols,
                isLoadingSubscription: isLoadingSubscription,
                isLoadingPlans: isLoadingPlans,
                isProcessingPayment: false,
                error: '无法获取计划配置',
                paymentResult: paymentResult,
              ),
            );
            return;
          }
          final planId = planConfig.id;
          if (planId == null) {
            emit(
              AccountManagementState.ready(
                subscriptionInfo: subscriptionInfo,
                planConfigs: planConfigs,
                selectedPlan: selectedPlan,
                selectedDuration: selectedDuration,
                selectedTab: selectedTab,
                agreedProtocols: agreedProtocols,
                isLoadingSubscription: isLoadingSubscription,
                isLoadingPlans: isLoadingPlans,
                isProcessingPayment: false,
                error: '无法获取计划ID，暂无法订阅',
                paymentResult: paymentResult,
              ),
            );
            return;
          }

          final billingType = selectedDuration == PurchaseDurationOption.monthly
              ? 0
              : 1;

          emit(
            AccountManagementState.ready(
              subscriptionInfo: subscriptionInfo,
              planConfigs: planConfigs,
              selectedPlan: selectedPlan,
              selectedDuration: selectedDuration,
              selectedTab: selectedTab,
              agreedProtocols: agreedProtocols,
              isLoadingSubscription: isLoadingSubscription,
              isLoadingPlans: isLoadingPlans,
              isProcessingPayment: true,
              error: null,
              paymentResult: paymentResult,
            ),
          );

          // // 先创建/更新订阅
          // await _createOrUpdateSubscription(planId, billingType, emit);

          // 检查更新后的状态
          final checkState = state;
          final checkError = checkState.maybeWhen(
            orElse: () => '状态错误',
            ready: (
              subscriptionInfo,
              planConfigs,
              selectedPlan,
              selectedDuration,
              selectedTab,
              agreedProtocols,
              isLoadingSubscription,
              isLoadingPlans,
              isProcessingPayment,
              error,
              paymentResult,
            ) =>
                error,
          );

          if (checkError != null) {
            state.maybeWhen(
              orElse: () {},
              ready: (
                subscriptionInfo,
                planConfigs,
                selectedPlan,
                selectedDuration,
                selectedTab,
                agreedProtocols,
                isLoadingSubscription,
                isLoadingPlans,
                isProcessingPayment,
                error,
                paymentResult,
              ) {
                emit(
                  AccountManagementState.ready(
                    subscriptionInfo: subscriptionInfo,
                    planConfigs: planConfigs,
                    selectedPlan: selectedPlan,
                    selectedDuration: selectedDuration,
                    selectedTab: selectedTab,
                    agreedProtocols: agreedProtocols,
                    isLoadingSubscription: isLoadingSubscription,
                    isLoadingPlans: isLoadingPlans,
                    isProcessingPayment: false,
                    error: checkError,
                    paymentResult: paymentResult,
                  ),
                );
              },
            );
            return;
          }

          // 获取价格
          final monthlyPrice = planConfig.monthlyPriceYuan ?? 0.0;
          final yearlyPrice = planConfig.yearlyPriceYuan ?? monthlyPrice * 12;
          final selectedPrice =
              selectedDuration == PurchaseDurationOption.monthly
                  ? monthlyPrice
                  : yearlyPrice;

          // 获取可用支付方式
          final methods = PaymentPlatformSupport.getAvailableMethods();
          if (methods.isEmpty) {
            state.maybeWhen(
              orElse: () {},
              ready: (
                subscriptionInfo,
                planConfigs,
                selectedPlan,
                selectedDuration,
                selectedTab,
                agreedProtocols,
                isLoadingSubscription,
                isLoadingPlans,
                isProcessingPayment,
                error,
                paymentResult,
              ) {
                emit(
                  AccountManagementState.ready(
                    subscriptionInfo: subscriptionInfo,
                    planConfigs: planConfigs,
                    selectedPlan: selectedPlan,
                    selectedDuration: selectedDuration,
                    selectedTab: selectedTab,
                    agreedProtocols: agreedProtocols,
                    isLoadingSubscription: isLoadingSubscription,
                    isLoadingPlans: isLoadingPlans,
                    isProcessingPayment: false,
                    error: '当前平台暂不支持支付功能',
                    paymentResult: paymentResult,
                  ),
                );
              },
            );
            return;
          }

          // todo 选择支付方式（默认支付宝）
          // final method = methods.first;
          // final paymentType = switch (method) {
          //   PaymentMethod.applePay => PaymentType.applePay,
          //   PaymentMethod.wechatPay => PaymentType.wechatPay,
          //   PaymentMethod.alipay => PaymentType.alipay,
          // };
          final method = PaymentMethod.alipay;
          final paymentType = PaymentMethod.alipay.name;
          // 创建支付订单
          // 将 userInfo 转换为 JSON 字符串（接口要求 String 类型）
          // final userInfoJson = jsonEncode({
          //   'userId': userProfile.id.toString(),
          //   'name': userProfile.name,
          //   'email': userProfile.email,
          // });

          // 设置会员升级参数
          String? planIdValue = '$planId';

          if(!PaymentDevConfig.enableTestMode) {
            // 1. 获取当前云端配置（拿到 serverUrl）
            final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
            final baseUrl = cloudEnv.appflowyCloudConfig.base_web_domain;
            // final baseUrl = "https://www.xiaomabiji.com";
            //price 通过这个路径进行数据拼接参数，然后打开浏览器处理当前业务，后续代码不走了。
            final userUuid = _getUserUuid();
            String payUrl = 
                "$baseUrl/price?planId=${planIdValue ?? ''}&billingType=$billingType&userInfo=$userUuid";
            // 使用浏览器打开支付链接
            await PaymentUtil.webPay(payUrl);

            // 移除支付弹框显示，直接等待H5支付链接调用appScheme处理
            // 支付成功后会通过 PaymentDeepLinkHandler 处理
            state.maybeWhen(
              orElse: () {},
              ready: (
                  subscriptionInfo,
                  planConfigs,
                  selectedPlan,
                  selectedDuration,
                  selectedTab,
                  agreedProtocols,
                  isLoadingSubscription,
                  isLoadingPlans,
                  isProcessingPayment,
                  error,
                  paymentResult,
                  ) {
                emit(
                  AccountManagementState.ready(
                    subscriptionInfo: subscriptionInfo,
                    planConfigs: planConfigs,
                    selectedPlan: selectedPlan,
                    selectedDuration: selectedDuration,
                    selectedTab: selectedTab,
                    agreedProtocols: agreedProtocols,
                    isLoadingSubscription: isLoadingSubscription,
                    isLoadingPlans: isLoadingPlans,
                    isProcessingPayment: false,
                    error: null,
                    paymentResult: 'PAYMENT_INITIATED', // 标记支付已初始化
                  ),
                );
              },
            );
          } else {
            // 创建支付订单 --- todo 后续需要根据实际情况进行调整
            await createPaymentOrder(
              emit: emit,
              selectedPrice: selectedPrice,
              paymentType: paymentType,
              workspaceId: workspaceId,
              planIdValue: planIdValue,
              billingType: billingType,
              subscriptionInfo: subscriptionInfo,
              planConfigs: planConfigs,
              selectedPlan: selectedPlan,
              selectedDuration: selectedDuration,
              selectedTab: selectedTab,
              agreedProtocols: agreedProtocols,
              isLoadingSubscription: isLoadingSubscription,
              isLoadingPlans: isLoadingPlans,
              isProcessingPayment: isProcessingPayment,
              error: error,
              paymentResult: paymentResult,
            );
          }
        });
  }

  Future<void> createPaymentOrder(
      {required Emitter<AccountManagementState> emit,
      required double? selectedPrice,
      required String paymentType,
      String? workspaceId,
      String? planIdValue,
      int? billingType,
      WorkspaceSubscriptionInfoPB? subscriptionInfo,
        required Map<WorkspacePlanPB, RemotePlan> planConfigs,
        WorkspacePlanPB? selectedPlan,
        required PurchaseDurationOption selectedDuration,
        required MembershipTab selectedTab,
        required bool agreedProtocols,
        required bool isLoadingSubscription,
        required bool isLoadingPlans,
        required bool isProcessingPayment,
      String? error,
      String? paymentResult}) async {
    // 这里同样使用用户 UUID 作为 userInfo，保持与网页支付入口一致
    final userUuid = _getUserUuid();

    final createRequest = PaymentCreateRequest(
        amount: Decimal.parse(selectedPrice.toString()).toString(),
        paymentType: paymentType,
        userInfo: userUuid,
        // 必传：JSON 字符串格式
        // productName: planConfig.planNameCn.isNotEmpty
        //     ? planConfig.planNameCn
        //     : planConfig.planName, // 可选
        productName: "QR_CODE_OFFLINE",
        openid:
            paymentType == PaymentMethod.wechatPay.name ? workspaceId : null,
        // 可选：微信支付场景必传
        planId: planIdValue,
        // 会员升级时设置
        billingType: billingType == 0 ? 'monthly' : 'yearly' );

    final orderResult = await PaymentApi.createPaymentOrder(createRequest);

    if (orderResult.isFailure) {
      final error = orderResult.fold((_) => null, (e) => e);
      String errorMessage = error?.msg ?? '创建支付订单失败';

      // 处理验签错误，提供更友好的提示
      if (errorMessage.contains('invalid-signature') ||
          errorMessage.contains('验签出错') ||
          errorMessage.contains('签名')) {
        errorMessage = '支付系统配置异常，请联系客服或稍后重试';
      }

      emit(
        AccountManagementState.ready(
          subscriptionInfo: subscriptionInfo,
          planConfigs: planConfigs,
          selectedPlan: selectedPlan,
          selectedDuration: selectedDuration,
          selectedTab: selectedTab,
          agreedProtocols: agreedProtocols,
          isLoadingSubscription: isLoadingSubscription,
          isLoadingPlans: isLoadingPlans,
          isProcessingPayment: false,
          error: errorMessage,
          paymentResult: paymentResult,
        ),
      );
      return;
    }

    final order = orderResult.fold(
      (order) => order,
      (_) => null,
    );
    if (order == null) {
      emit(
        AccountManagementState.ready(
          subscriptionInfo: subscriptionInfo,
          planConfigs: planConfigs,
          selectedPlan: selectedPlan,
          selectedDuration: selectedDuration,
          selectedTab: selectedTab,
          agreedProtocols: agreedProtocols,
          isLoadingSubscription: isLoadingSubscription,
          isLoadingPlans: isLoadingPlans,
          isProcessingPayment: false,
          error: '创建支付订单失败',
          paymentResult: paymentResult,
        ),
      );
      return;
    }

    // 如果有支付 URL，保存订单信息到 state，由 UI 层显示支付弹框
    // 将订单信息编码到 paymentResult 中（格式：PAYMENT_URL:payUrl|orderNo:xxx|expireTime:xxx）
    String paymentResultMessage;
    if (order.hasPayUrl) {
      final parts = <String>['PAYMENT_URL:${order.payUrl}'];
      if (order.orderNo.isNotEmpty) {
        parts.add('orderNo:${order.orderNo}');
      }
      if (order.expireTime != null && order.expireTime!.isNotEmpty) {
        parts.add('expireTime:${order.expireTime}');
      }
      paymentResultMessage = parts.join('|');
    } else {
      paymentResultMessage = '订单创建成功，订单号: ${order.orderNo}';
    }

    emit(
      AccountManagementState.ready(
        subscriptionInfo: subscriptionInfo,
        planConfigs: planConfigs,
        selectedPlan: selectedPlan,
        selectedDuration: selectedDuration,
        selectedTab: selectedTab,
        agreedProtocols: agreedProtocols,
        isLoadingSubscription: isLoadingSubscription,
        isLoadingPlans: isLoadingPlans,
        isProcessingPayment: false,
        error: null,
        paymentResult: paymentResultMessage,
      ),
    );

    // 启动支付结果轮询
    if (order.orderNo.isNotEmpty) {
      await _startPaymentPolling(order.orderNo, emit);
    }
  }



  /// 启动支付结果轮询
  ///
  /// 注意：Timer 回调中不能直接使用 emit，因为原始事件处理器可能已经完成
  /// 改为使用 add 触发 checkPaymentStatus 事件
  Future<void> _startPaymentPolling(
    String orderNo,
    Emitter<AccountManagementState> emit,
  ) async {
    // 停止之前的轮询
    _paymentPollingTimer?.cancel();
    _paymentPollingTimer = null;
    _currentPollingOrderNo = orderNo;

    // 立即查询一次（在当前事件处理器中，可以安全使用 emit）
    await _checkPaymentStatus(emit);

    // 每 3 秒轮询一次
    // 注意：Timer 回调中使用 add 触发新事件，而不是直接调用带 emit 的方法
    _paymentPollingTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) {
        // 使用 add 触发新事件，这样 emit 会在新的事件处理器中调用
        add(const AccountManagementEvent.checkPaymentStatus());
      },
    );

    Log.info(
        '[AccountManagementBloc] Started payment polling for order: $orderNo');
  }

  /// 停止支付结果轮询
  void _stopPaymentPolling() {
    _paymentPollingTimer?.cancel();
    _paymentPollingTimer = null;
    _currentPollingOrderNo = null;

    Log.info('[AccountManagementBloc] Stopped payment polling');
  }

  /// 检查支付状态
  ///
  /// 此方法会在事件处理器中被调用，emit 是有效的
  Future<void> _checkPaymentStatus(Emitter<AccountManagementState> emit) async {
    if (_currentPollingOrderNo == null || _currentPollingOrderNo!.isEmpty) {
      // 没有订单号，停止轮询
      _stopPaymentPolling();
      return;
    }

    // 检查 emit 是否已完成（防止异步操作后 emit 失效）
    if (emit.isDone) {
      Log.warn(
          '[AccountManagementBloc] emit.isDone, skipping payment status check');
      return;
    }

    await state.maybeWhen(
      orElse: () async {},
      ready: (
        subscriptionInfo,
        planConfigs,
        selectedPlan,
        selectedDuration,
        selectedTab,
        agreedProtocols,
        isLoadingSubscription,
        isLoadingPlans,
        isProcessingPayment,
        error,
        paymentResult,
      ) async {
        final statusResult =
            await PaymentApi.queryPaymentStatus(_currentPollingOrderNo!);

        // 再次检查 emit 是否有效
        if (emit.isDone) {
          Log.warn(
              '[AccountManagementBloc] emit.isDone after query, skipping emit');
          return;
        }

        statusResult.fold(
          (status) {
            Log.info('[AccountManagementBloc] Payment status: $status');

            // 如果支付成功或失败，停止轮询并刷新订阅信息
            if (status == 'paid' || status == 'success') {
              _stopPaymentPolling();

              // 刷新订阅信息
              add(const AccountManagementEvent.loadSubscriptionInfo());

              // 通知 UI 刷新（检查 emit 是否有效）
              if (!emit.isDone) {
                emit(
                  AccountManagementState.ready(
                    subscriptionInfo: subscriptionInfo,
                    planConfigs: planConfigs,
                    selectedPlan: selectedPlan,
                    selectedDuration: selectedDuration,
                    selectedTab: selectedTab,
                    agreedProtocols: agreedProtocols,
                    isLoadingSubscription: isLoadingSubscription,
                    isLoadingPlans: isLoadingPlans,
                    isProcessingPayment: false,
                    error: null,
                    paymentResult: '支付成功',
                  ),
                );
              }
            } else if (status == 'failed' ||
                status == 'expired' ||
                status == 'canceled') {
              _stopPaymentPolling();

              if (!emit.isDone) {
                emit(
                  AccountManagementState.ready(
                    subscriptionInfo: subscriptionInfo,
                    planConfigs: planConfigs,
                    selectedPlan: selectedPlan,
                    selectedDuration: selectedDuration,
                    selectedTab: selectedTab,
                    agreedProtocols: agreedProtocols,
                    isLoadingSubscription: isLoadingSubscription,
                    isLoadingPlans: isLoadingPlans,
                    isProcessingPayment: false,
                    error: status == 'expired' ? '订单已过期' : '支付失败',
                    paymentResult: paymentResult,
                  ),
                );
              }
            }
            // pending 状态继续轮询
          },
          (error) {
            Log.error(
                '[AccountManagementBloc] Failed to query payment status: ${error.msg}');
            // 查询失败不影响轮询，继续等待
          },
        );
      },
    );
  }

  @override
  Future<void> close() {
    // 清理订阅成功监听器
    _subscriptionSuccessListenable.removeListener(_subscriptionSuccessListener);
    // 停止支付轮询
    _stopPaymentPolling();
    _paymentPollingTimer?.cancel();
    _paymentPollingTimer = null;
    return super.close();
  }
}

@freezed
class AccountManagementEvent with _$AccountManagementEvent {
  const factory AccountManagementEvent.initial() = _Initial;

  const factory AccountManagementEvent.loadSubscriptionInfo() =
      _LoadSubscriptionInfo;

  const factory AccountManagementEvent.loadSubscriptionPlans() =
      _LoadSubscriptionPlans;

  const factory AccountManagementEvent.selectPlan(WorkspacePlanPB plan) = _SelectPlan;

  const factory AccountManagementEvent.selectDuration(
      PurchaseDurationOption duration) = _SelectDuration;

  const factory AccountManagementEvent.setAgreedProtocols(bool agreed) = _SetAgreedProtocols;

  const factory AccountManagementEvent.switchTab(MembershipTab tab) = _SwitchTab;

  const factory AccountManagementEvent.createOrUpdateSubscription(
    int planId,
    String billingType,
  ) = _CreateOrUpdateSubscription;

  const factory AccountManagementEvent.handleUpgradePay() = _HandleUpgradePay;

  // 临时注释：等待 freezed 重新生成后取消注释
  const factory AccountManagementEvent.startPaymentPolling(String orderNo) =
      _StartPaymentPolling;

  const factory AccountManagementEvent.stopPaymentPolling() =
      _StopPaymentPolling;

  const factory AccountManagementEvent.checkPaymentStatus() =
      _CheckPaymentStatus;
}

@freezed
class AccountManagementState extends Equatable with _$AccountManagementState {
  const AccountManagementState._();

  const factory AccountManagementState.initial() = _InitialState;

  const factory AccountManagementState.loading() = _LoadingState;

  const factory AccountManagementState.error({
    @Default(null) FlowyError? error,
  }) = _ErrorState;

  const factory AccountManagementState.ready({
    required WorkspaceSubscriptionInfoPB? subscriptionInfo,
    required Map<WorkspacePlanPB, RemotePlan> planConfigs,
    @Default(null) WorkspacePlanPB? selectedPlan,
    @Default(PurchaseDurationOption.monthly)
    PurchaseDurationOption selectedDuration,
    @Default(MembershipTab.upgrade) MembershipTab selectedTab,
    @Default(false) bool agreedProtocols,
    @Default(true) bool isLoadingSubscription,
    @Default(true) bool isLoadingPlans,
    @Default(false) bool isProcessingPayment,
    @Default(null) String? error,
    @Default(null) String? paymentResult,
  }) = _ReadyState;

  @override
  List<Object?> get props => maybeWhen(
        orElse: () => const [],
        error: (error) => [error],
        ready: (
          subscriptionInfo,
          planConfigs,
          selectedPlan,
          selectedDuration,
          selectedTab,
          agreedProtocols,
          isLoadingSubscription,
          isLoadingPlans,
          isProcessingPayment,
          error,
          paymentResult,
        ) =>
            [
          subscriptionInfo,
          planConfigs,
          selectedPlan,
          selectedDuration,
          selectedTab,
          agreedProtocols,
          isLoadingSubscription,
          isLoadingPlans,
          isProcessingPayment,
          error,
          paymentResult,
        ],
      );
}

extension AccountManagementStateExtension on AccountManagementState {
  bool get isLoading {
    return maybeWhen(
      orElse: () => true,
      ready: (
        subscriptionInfo,
        planConfigs,
        selectedPlan,
        selectedDuration,
        selectedTab,
        agreedProtocols,
        isLoadingSubscription,
        isLoadingPlans,
        isProcessingPayment,
        error,
        paymentResult,
      ) =>
          isLoadingSubscription || isLoadingPlans,
    );
  }

  WorkspacePlanPB? get effectivePlan {
    return maybeWhen(
      orElse: () => null,
      ready: (
        subscriptionInfo,
        planConfigs,
        selectedPlan,
        selectedDuration,
        selectedTab,
        agreedProtocols,
        isLoadingSubscription,
        isLoadingPlans,
        isProcessingPayment,
        error,
        paymentResult,
      ) {
        final availablePlans = planConfigs.keys
            .where((plan) => plan != WorkspacePlanPB.FreePlan)
            .toList();
        if (availablePlans.isEmpty) return null;

        if (selectedPlan != null &&
            selectedPlan != WorkspacePlanPB.FreePlan &&
            planConfigs.containsKey(selectedPlan)) {
          return selectedPlan;
        }
        if (subscriptionInfo != null &&
            subscriptionInfo.plan != WorkspacePlanPB.FreePlan &&
            planConfigs.containsKey(subscriptionInfo.plan)) {
          return subscriptionInfo.plan;
        }
        // 优先选择标准版计划，如果没有则返回第一个可用计划
        final standPlan = availablePlans.firstWhere(
          (plan) => plan == WorkspacePlanPB.StandPlan,
          orElse: () => availablePlans.first,
        );
        return standPlan;
      },
    );
  }

  RemotePlan? getPlanConfig(WorkspacePlanPB? plan) {
    return maybeWhen(
      orElse: () => null,
      ready: (
        subscriptionInfo,
        planConfigs,
        selectedPlan,
        selectedDuration,
        selectedTab,
        agreedProtocols,
        isLoadingSubscription,
        isLoadingPlans,
        isProcessingPayment,
        error,
        paymentResult,
      ) {
        if (plan == null) return null;
        final remote = planConfigs[plan];
        if (remote != null) {
          return remote;
        }
        return null;
      },
    );
  }

  double getDurationPrice(PurchaseDurationOption option) {
    return maybeWhen(
      orElse: () => 0.0,
      ready: (
        subscriptionInfo,
        planConfigs,
        selectedPlan,
        selectedDuration,
        selectedTab,
        agreedProtocols,
        isLoadingSubscription,
        isLoadingPlans,
        isProcessingPayment,
        error,
        paymentResult,
      ) {
        final effectivePlan = this.effectivePlan;
        if (effectivePlan == null) return 0.0;
        final config = planConfigs[effectivePlan];
        if (config == null) return 0.0;
        final monthly = config.monthlyPriceYuan ?? 0.0;
        final yearly = config.yearlyPriceYuan ?? monthly * 12;
        return option == PurchaseDurationOption.monthly ? monthly : yearly;
      },
    );
  }
}

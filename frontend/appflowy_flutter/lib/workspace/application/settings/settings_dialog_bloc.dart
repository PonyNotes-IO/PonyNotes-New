import 'dart:convert';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/user_listener.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:http/http.dart' as http;

part 'settings_dialog_bloc.freezed.dart';

enum SettingsPage {
  // NEW
  account,
  accountManagement,
  rechargeRecords,
  workspace,
  workspaceManagement,
  storage,
  plan,
  billing,
  sites,
  sharing,
  aboutXiaoma,
  userProfile,
  // OLD
  notifications,
  member,
  manageData,
  shortcuts,
  ai,
  cloud,
  featureFlags,
  addonPurchaseRecords,
}

class SettingsDialogBloc
    extends Bloc<SettingsDialogEvent, SettingsDialogState> {
  SettingsDialogBloc(
    UserProfilePB userProfile,
    this.currentWorkspaceMemberRole, {
    SettingsPage? initPage,
  })  : _userListener = UserListener(userProfile: userProfile),
        super(SettingsDialogState.initial(userProfile, initPage)) {
    _dispatch();
  }

  final AFRolePB? currentWorkspaceMemberRole;
  final UserListener _userListener;
  bool _listenerStarted = false;

  @override
  Future<void> close() async {
    await _userListener.stop();
    await super.close();
  }

  void _dispatch() {
    on<SettingsDialogEvent>(
      (event, emit) async {
        await event.when(
          initial: () async {
            if (!_listenerStarted) {
            _userListener.start(onProfileUpdated: _profileUpdated);
              _listenerStarted = true;
            }

            final isBillingEnabled = await _isBillingEnabled(
              state.userProfile,
              currentWorkspaceMemberRole,
            );
            if (isBillingEnabled) {
              emit(state.copyWith(isBillingEnabled: true));
            }

            await _fetchCurrentSubscription(emit, state.userProfile);
          },
          didReceiveUserProfile: (UserProfilePB newUserProfile) {
            emit(state.copyWith(userProfile: newUserProfile));
          },
          setSelectedPage: (SettingsPage page) {
            emit(state.copyWith(page: page));
          },
        );
      },
    );
  }

  void _profileUpdated(
    FlowyResult<UserProfilePB, FlowyError> userProfileOrFailed,
  ) {
    userProfileOrFailed.fold(
      (newUserProfile) {
        if (!isClosed) {
          add(SettingsDialogEvent.didReceiveUserProfile(newUserProfile));
        }
      },
      (err) => Log.error(err),
    );
  }

  Future<bool> _isBillingEnabled(
    UserProfilePB userProfile, [
    AFRolePB? currentWorkspaceMemberRole,
  ]) async {
    if ([
      WorkspaceTypePB.LocalW,
    ].contains(userProfile.workspaceType)) {
      return false;
    }

    if (currentWorkspaceMemberRole == null ||
        currentWorkspaceMemberRole != AFRolePB.Owner) {
      return false;
    }

    if (kDebugMode) {
      return true;
    }

    final result = await UserEventGetCloudConfig().send();
    return result.fold(
      (cloudSetting) {
        final whiteList = [
          "https://api.xiaomabiji.com",
          "https://api.xiaomabiji.com",
        ];

        return whiteList.contains(cloudSetting.serverUrl);
      },
      (err) {
        Log.error("Failed to get cloud config: $err");
        return false;
      },
    );
  }

  Future<void> _fetchCurrentSubscription(
    Emitter<SettingsDialogState> emit,
    UserProfilePB userProfile,
  ) async {
    emit(
      state.copyWith(
        isLoadingCurrentSubscription: true,
      ),
    );

    try {
      final cloudEnv = getIt<AppFlowyCloudSharedEnv>();
      final baseUrl = cloudEnv.appflowyCloudConfig.base_url;
      if (baseUrl.isEmpty) {
        Log.warn('订阅信息接口 baseUrl 为空，跳过请求');
        emit(
          state.copyWith(
            isLoadingCurrentSubscription: false,
            currentSubscription: null,
          ),
        );
        return;
      }

      final accessToken = _extractAccessToken(userProfile.token);
      if (accessToken == null || accessToken.isEmpty) {
        Log.warn('订阅信息接口缺少 access_token，跳过请求');
        emit(
          state.copyWith(
            isLoadingCurrentSubscription: false,
            currentSubscription: null,
          ),
        );
        return;
      }

      final uri = Uri.parse(baseUrl).replace(path: '/api/subscription/current');
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 404) {
        Log.info('订阅信息接口返回 404，无订阅');
        emit(
          state.copyWith(
            isLoadingCurrentSubscription: false,
            currentSubscription: null,
          ),
        );
        return;
      }

      if (response.statusCode != 200) {
        Log.warn(
          '订阅信息接口返回非 200: ${response.statusCode}, body: ${response.body}',
        );
        emit(
          state.copyWith(
            isLoadingCurrentSubscription: false,
            currentSubscription: null,
          ),
        );
        return;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final code = decoded['code'] as int? ?? -1;
      if (code != 0) {
        Log.warn(
          '订阅信息接口 code!=0: code=$code, message=${decoded['message']}',
        );
        emit(
          state.copyWith(
            isLoadingCurrentSubscription: false,
            currentSubscription: null,
          ),
        );
        return;
      }

      final data = decoded['data'];
      if (data == null || data is! Map<String, dynamic>) {
        Log.warn('订阅信息接口 data 为空或格式错误');
        emit(
          state.copyWith(
            isLoadingCurrentSubscription: false,
            currentSubscription: null,
          ),
        );
        return;
      }

      final current = CurrentSubscription.fromJson(data);
      emit(
        state.copyWith(
          isLoadingCurrentSubscription: false,
          currentSubscription: current,
        ),
      );
    } catch (e, stackTrace) {
      Log.error('订阅信息接口请求异常: $e', e, stackTrace);
      emit(
        state.copyWith(
          isLoadingCurrentSubscription: false,
          currentSubscription: null,
        ),
      );
    }
  }

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
      // 非 JSON，直接使用原始 token
      return rawToken;
    }
    return null;
  }
}

@immutable
class CurrentSubscription {
  const CurrentSubscription({
    required this.subscription,
    required this.planDetails,
    required this.usage,
  });

  final SubscriptionSummary? subscription;
  final PlanDetails? planDetails;
  final UsageDetails? usage;

  factory CurrentSubscription.fromJson(Map<String, dynamic> json) {
    return CurrentSubscription(
      subscription: SubscriptionSummary.fromJson(
        json['subscription'] as Map<String, dynamic>?,
      ),
      planDetails: PlanDetails.fromJson(
        json['plan_details'] as Map<String, dynamic>?,
      ),
      usage: UsageDetails.fromJson(
        json['usage'] as Map<String, dynamic>?,
      ),
    );
  }
}

@immutable
class SubscriptionSummary {
  const SubscriptionSummary({
    required this.planCode,
    required this.planNameCn,
    required this.billingType,
    required this.status,
    required this.startDate,
    required this.endDate,
  });

  final String? planCode;
  final String? planNameCn;
  final String? billingType;
  final String? status;
  final DateTime? startDate;
  final DateTime? endDate;

  factory SubscriptionSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SubscriptionSummary(
      planCode: null,
      planNameCn: null,
      billingType: null,
      status: null,
      startDate: null,
      endDate: null,
    );
    DateTime? _parseDate(String? v) {
      if (v == null || v.isEmpty) return null;
      return DateTime.tryParse(v);
    }

    return SubscriptionSummary(
      planCode: json['plan_code'] as String?,
      planNameCn: json['plan_name_cn'] as String?,
      billingType: json['billing_type'] as String?,
      status: json['status'] as String?,
      startDate: _parseDate(json['start_date'] as String?),
      endDate: _parseDate(json['end_date'] as String?),
    );
  }
}

@immutable
class PlanDetails {
  const PlanDetails({
    required this.planCode,
    required this.planNameCn,
    required this.monthlyPriceYuan,
    required this.yearlyPriceYuan,
    required this.cloudStorageGb,
  });

  final String? planCode;
  final String? planNameCn;
  final double? monthlyPriceYuan;
  final double? yearlyPriceYuan;
  final int? cloudStorageGb;

  factory PlanDetails.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const PlanDetails(
        planCode: null,
        planNameCn: null,
        monthlyPriceYuan: null,
        yearlyPriceYuan: null,
        cloudStorageGb: null,
      );
    }

    double? _parseDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    return PlanDetails(
      planCode: json['plan_code'] as String?,
      planNameCn: json['plan_name_cn'] as String?,
      monthlyPriceYuan: _parseDouble(json['monthly_price_yuan']),
      yearlyPriceYuan: _parseDouble(json['yearly_price_yuan']),
      cloudStorageGb: json['cloud_storage_gb'] as int?,
    );
  }
}

@immutable
class UsageDetails {
  const UsageDetails({
    required this.aiChatRemaining,
    required this.aiImageRemaining,
    required this.storageUsedGb,
    required this.storageTotalGb,
  });

  final int? aiChatRemaining;
  final int? aiImageRemaining;
  final double? storageUsedGb;
  final double? storageTotalGb;

  factory UsageDetails.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const UsageDetails(
        aiChatRemaining: null,
        aiImageRemaining: null,
        storageUsedGb: null,
        storageTotalGb: null,
      );
    }

    int? _parseInt(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    double? _parseDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    return UsageDetails(
      aiChatRemaining: _parseInt(json['ai_chat_remaining_this_month']),
      aiImageRemaining: _parseInt(json['ai_image_remaining_this_month']),
      storageUsedGb: _parseDouble(json['storage_used_gb']),
      storageTotalGb: _parseDouble(json['storage_total_gb']),
    );
  }
}

@freezed
class SettingsDialogEvent with _$SettingsDialogEvent {
  const factory SettingsDialogEvent.initial() = _Initial;
  const factory SettingsDialogEvent.didReceiveUserProfile(
    UserProfilePB newUserProfile,
  ) = _DidReceiveUserProfile;
  const factory SettingsDialogEvent.setSelectedPage(SettingsPage page) =
      _SetViewIndex;
}

@freezed
class SettingsDialogState with _$SettingsDialogState {
  const factory SettingsDialogState({
    required UserProfilePB userProfile,
    required SettingsPage page,
    required bool isBillingEnabled,
    CurrentSubscription? currentSubscription,
    @Default(false) bool isLoadingCurrentSubscription,
  }) = _SettingsDialogState;

  factory SettingsDialogState.initial(
    UserProfilePB userProfile,
    SettingsPage? page,
  ) =>
      SettingsDialogState(
        userProfile: userProfile,
        page: page ?? SettingsPage.account,
        isBillingEnabled: false,
        currentSubscription: null,
        isLoadingCurrentSubscription: true,
      );
}

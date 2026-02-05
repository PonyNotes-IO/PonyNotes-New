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

import '../subscription/subscription_service.dart';
import 'account/account_management_bloc.dart';
import 'package:appflowy/workspace/application/subscription_success_listenable/subscription_success_listenable.dart';

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
}

class SettingsDialogBloc
    extends Bloc<SettingsDialogEvent, SettingsDialogState> {
  SettingsDialogBloc(
    UserProfilePB userProfile,
    this.currentWorkspaceMemberRole, {
    SettingsPage? initPage,
  })  : _userListener = UserListener(userProfile: userProfile),
        _subscriptionSuccessListenable = getIt<SubscriptionSuccessListenable>(),
        super(SettingsDialogState.initial(userProfile, initPage)) {
    _subscriptionSuccessListener = () {
      if (isClosed) {
        return;
      }
      add(const SettingsDialogEvent.initial());
    };
    _subscriptionSuccessListenable.addListener(_subscriptionSuccessListener);
    _dispatch();
  }

  final AFRolePB? currentWorkspaceMemberRole;
  final UserListener _userListener;
  final SubscriptionSuccessListenable _subscriptionSuccessListenable;
  late final VoidCallback _subscriptionSuccessListener;
  bool _listenerStarted = false;

  @override
  Future<void> close() async {
    _subscriptionSuccessListenable.removeListener(_subscriptionSuccessListener);
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
      // 使用 SubscriptionService 获取订阅信息，利用缓存机制
      final currentSubscription = await SubscriptionService().getCurrentSubscription(
        userProfile: userProfile,
        forceRefresh: false,
        caller: 'SettingsDialogBloc._fetchCurrentSubscription',
      );
      emit(
        state.copyWith(
          isLoadingCurrentSubscription: false,
          currentSubscription: currentSubscription,
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
  final RemotePlan? planDetails;
  final UsageDetails? usage;

  factory CurrentSubscription.fromJson(Map<String, dynamic> json) {
    return CurrentSubscription(
      subscription: SubscriptionSummary.fromJson(
        json['subscription'] as Map<String, dynamic>?,
      ),
      planDetails: RemotePlan.fromJson(
        json['plan_details'],
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

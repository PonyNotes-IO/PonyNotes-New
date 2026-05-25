import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:easy_localization/easy_localization.dart';

/// 按枚举数值判断，兼容旧/新生成的 Dart 枚举名（StudentPlan/StandardPlan/TeamPlan 或 StandPlan/ProPlan/HiclassPlan）
extension SubscriptionInfoHelpers on WorkspaceSubscriptionInfoPB {
  String get label => switch (plan.value) {
        0 => LocaleKeys.settings_planPage_planUsage_currentPlan_freeTitle.tr(),
        1 => LocaleKeys.settings_planPage_planUsage_currentPlan_standardTitle.tr(),
        2 => LocaleKeys.settings_planPage_planUsage_currentPlan_studentTitle.tr(),
        3 => LocaleKeys.settings_planPage_planUsage_currentPlan_teamTitle.tr(),
        _ => 'N/A',
      };

  String get info => switch (plan.value) {
        0 => LocaleKeys.settings_planPage_planUsage_currentPlan_freeInfo.tr(),
        1 => LocaleKeys.settings_planPage_planUsage_currentPlan_standardInfo.tr(),
        2 => LocaleKeys.settings_planPage_planUsage_currentPlan_studentInfo.tr(),
        3 => LocaleKeys.settings_planPage_planUsage_currentPlan_teamInfo.tr(),
        _ => 'N/A',
      };

  bool get isBillingPortalEnabled {
    if (plan.value != 0) {
      return true;
    }

    return false;
  }
}

/// 按枚举数值判断，兼容旧/新生成的 Dart 枚举名。Free=0, Stand/Standard=1, Pro/Student=2, Hiclass/Team=3
extension AllSubscriptionLabels on SubscriptionPlanPB {
  String get label => switch (value) {
        0 => LocaleKeys.settings_planPage_planUsage_currentPlan_freeTitle.tr(),
        1 => LocaleKeys.settings_planPage_planUsage_currentPlan_standardTitle.tr(),
        2 => LocaleKeys.settings_planPage_planUsage_currentPlan_studentTitle.tr(),
        3 => LocaleKeys.settings_planPage_planUsage_currentPlan_teamTitle.tr(),
        _ => 'N/A',
      };
}

extension WorkspaceSubscriptionStatusExt on WorkspaceSubscriptionInfoPB {
  bool get isCanceled =>
      planSubscription.status == WorkspaceSubscriptionStatusPB.Canceled;
}



/// These have to match [SubscriptionSuccessListenable.subscribedPlan] labels
extension ToRecognizable on SubscriptionPlanPB {
  String? toRecognizable() => switch (value) {
        0 => 'free',
        1 => 'standard',
        2 => 'professor',
        3 => 'hiclass',
        _ => null,
      };
}

extension PlanHelper on SubscriptionPlanPB {
  String get priceMonthBilling => switch (value) {
        0 => '¥0',
        1 => '¥8',
        2 => '¥3',
        3 => '¥18',
        _ => '¥0',
      };

  String get priceAnnualBilling => switch (value) {
        0 => '¥0',
        1 => '¥80',
        2 => '¥30',
        3 => '¥180',
        _ => '¥0',
      };
}

extension IntervalLabel on RecurringIntervalPB {
  String get label => switch (this) {
        RecurringIntervalPB.Month =>
          LocaleKeys.settings_billingPage_monthlyInterval.tr(),
        RecurringIntervalPB.Year =>
          LocaleKeys.settings_billingPage_annualInterval.tr(),
        _ => LocaleKeys.settings_billingPage_monthlyInterval.tr(),
      };

  String get priceInfo => switch (this) {
        RecurringIntervalPB.Month =>
          LocaleKeys.settings_billingPage_monthlyPriceInfo.tr(),
        RecurringIntervalPB.Year =>
          LocaleKeys.settings_billingPage_annualPriceInfo.tr(),
        _ => LocaleKeys.settings_billingPage_monthlyPriceInfo.tr(),
      };
}

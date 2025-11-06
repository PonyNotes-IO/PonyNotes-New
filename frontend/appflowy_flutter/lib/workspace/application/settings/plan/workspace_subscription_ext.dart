import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pbserver.dart';
import 'package:easy_localization/easy_localization.dart';

extension SubscriptionInfoHelpers on WorkspaceSubscriptionInfoPB {
  String get label => switch (plan) {
        WorkspacePlanPB.FreePlan =>
          LocaleKeys.settings_planPage_planUsage_currentPlan_freeTitle.tr(),
        WorkspacePlanPB.StudentPlan =>
          LocaleKeys.settings_planPage_planUsage_currentPlan_studentTitle.tr(),
        WorkspacePlanPB.StandardPlan =>
          LocaleKeys.settings_planPage_planUsage_currentPlan_standardTitle.tr(),
        WorkspacePlanPB.TeamPlan =>
          LocaleKeys.settings_planPage_planUsage_currentPlan_teamTitle.tr(),
        _ => 'N/A',
      };

  String get info => switch (plan) {
        WorkspacePlanPB.FreePlan =>
          LocaleKeys.settings_planPage_planUsage_currentPlan_freeInfo.tr(),
        WorkspacePlanPB.StudentPlan =>
          LocaleKeys.settings_planPage_planUsage_currentPlan_studentInfo.tr(),
        WorkspacePlanPB.StandardPlan =>
          LocaleKeys.settings_planPage_planUsage_currentPlan_standardInfo.tr(),
        WorkspacePlanPB.TeamPlan =>
          LocaleKeys.settings_planPage_planUsage_currentPlan_teamInfo.tr(),
        _ => 'N/A',
      };

  bool get isBillingPortalEnabled {
    if (plan != WorkspacePlanPB.FreePlan || addOns.isNotEmpty) {
      return true;
    }

    return false;
  }
}

extension AllSubscriptionLabels on SubscriptionPlanPB {
  String get label => switch (this) {
        SubscriptionPlanPB.Free =>
          LocaleKeys.settings_planPage_planUsage_currentPlan_freeTitle.tr(),
        SubscriptionPlanPB.Student =>
          LocaleKeys.settings_planPage_planUsage_currentPlan_studentTitle.tr(),
        SubscriptionPlanPB.Standard =>
          LocaleKeys.settings_planPage_planUsage_currentPlan_standardTitle.tr(),
        SubscriptionPlanPB.Team =>
          LocaleKeys.settings_planPage_planUsage_currentPlan_teamTitle.tr(),
        SubscriptionPlanPB.AiMax =>
          LocaleKeys.settings_billingPage_addons_aiMax_label.tr(),
        SubscriptionPlanPB.AiLocal =>
          LocaleKeys.settings_billingPage_addons_aiOnDevice_label.tr(),
        _ => 'N/A',
      };
}

extension WorkspaceSubscriptionStatusExt on WorkspaceSubscriptionInfoPB {
  bool get isCanceled =>
      planSubscription.status == WorkspaceSubscriptionStatusPB.Canceled;
}

extension WorkspaceAddonsExt on WorkspaceSubscriptionInfoPB {
  bool get hasAIMax =>
      addOns.any((addon) => addon.type == WorkspaceAddOnPBType.AddOnAiMax);

  bool get hasAIOnDevice =>
      addOns.any((addon) => addon.type == WorkspaceAddOnPBType.AddOnAiLocal);
}

/// These have to match [SubscriptionSuccessListenable.subscribedPlan] labels
extension ToRecognizable on SubscriptionPlanPB {
  String? toRecognizable() => switch (this) {
        SubscriptionPlanPB.Free => 'free',
        SubscriptionPlanPB.Student => 'student',
        SubscriptionPlanPB.Standard => 'standard',
        SubscriptionPlanPB.Team => 'team',
        SubscriptionPlanPB.AiMax => 'ai_max',
        SubscriptionPlanPB.AiLocal => 'ai_local',
        _ => null,
      };
}

extension PlanHelper on SubscriptionPlanPB {
  /// Returns true if the plan is an add-on and not
  /// a workspace plan.
  ///
  bool get isAddOn => switch (this) {
        SubscriptionPlanPB.AiMax => true,
        SubscriptionPlanPB.AiLocal => true,
        _ => false,
      };

  String get priceMonthBilling => switch (this) {
        SubscriptionPlanPB.Free => '¥0',
        SubscriptionPlanPB.Student => '¥3',
        SubscriptionPlanPB.Standard => '¥8',
        SubscriptionPlanPB.Team => '¥18',
        SubscriptionPlanPB.AiMax => '¥10',
        SubscriptionPlanPB.AiLocal => '¥10',
        _ => '¥0',
      };

  String get priceAnnualBilling => switch (this) {
        SubscriptionPlanPB.Free => '¥0',
        SubscriptionPlanPB.Student => '¥30',
        SubscriptionPlanPB.Standard => '¥80',
        SubscriptionPlanPB.Team => '¥180',
        SubscriptionPlanPB.AiMax => '¥96',
        SubscriptionPlanPB.AiLocal => '¥96',
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

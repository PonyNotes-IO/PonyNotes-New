use client_api::entity::billing_dto::{
  Currency, RecurringInterval, SubscriptionPlanDetail,
  WorkspaceUsageAndLimit,
};
use client_api::entity::billing_dto::WorkspaceSubscriptionStatus as CloudWorkspaceSubscriptionStatus;
use serde::{Deserialize, Serialize};
use std::convert::TryFrom;
use std::fmt;
use std::str::FromStr;
use validator::Validate;

// Local definition of SubscriptionPlan to support Basic variant
// This mirrors the backend definition but is independent to avoid version conflicts
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum SubscriptionPlan {
  Free = 0,
  Basic = 1,
  Pro = 2,
  Team = 3,
  AiMax = 4,
  AiLocal = 5,
}

// Local wrapper for WorkspaceSubscriptionStatus to use our local SubscriptionPlan
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceSubscriptionStatus {
  pub workspace_id: String,
  pub workspace_plan: SubscriptionPlan,
  pub recurring_interval: RecurringInterval,
  pub subscription_status: SubscriptionStatus,
  pub subscription_quantity: u64,
  pub cancel_at: Option<i64>,
  pub current_period_end: i64,
}

#[derive(Copy, Clone, Debug, Deserialize, Serialize, Eq, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum SubscriptionStatus {
  Active = 0,
  Canceled = 1,
  Incomplete = 2,
  IncompleteExpired = 3,
  PastDue = 4,
  Paused = 5,
  Trialing = 6,
  Unpaid = 7,
}

// Convert from Cloud API type to local type
impl From<CloudWorkspaceSubscriptionStatus> for WorkspaceSubscriptionStatus {
  fn from(cloud: CloudWorkspaceSubscriptionStatus) -> Self {
    Self {
      workspace_id: cloud.workspace_id,
      workspace_plan: cloud.workspace_plan.into(),
      recurring_interval: cloud.recurring_interval,
      subscription_status: cloud.subscription_status.into(),
      subscription_quantity: cloud.subscription_quantity,
      cancel_at: cloud.cancel_at,
      current_period_end: cloud.current_period_end,
    }
  }
}

impl From<client_api::entity::billing_dto::SubscriptionStatus> for SubscriptionStatus {
  fn from(status: client_api::entity::billing_dto::SubscriptionStatus) -> Self {
    use client_api::entity::billing_dto::SubscriptionStatus as CloudStatus;
    match status {
      CloudStatus::Active => SubscriptionStatus::Active,
      CloudStatus::Canceled => SubscriptionStatus::Canceled,
      CloudStatus::Incomplete => SubscriptionStatus::Incomplete,
      CloudStatus::IncompleteExpired => SubscriptionStatus::IncompleteExpired,
      CloudStatus::PastDue => SubscriptionStatus::PastDue,
      CloudStatus::Paused => SubscriptionStatus::Paused,
      CloudStatus::Trialing => SubscriptionStatus::Trialing,
      CloudStatus::Unpaid => SubscriptionStatus::Unpaid,
    }
  }
}

impl From<client_api::entity::billing_dto::SubscriptionPlan> for SubscriptionPlan {
  fn from(plan: client_api::entity::billing_dto::SubscriptionPlan) -> Self {
    use client_api::entity::billing_dto::SubscriptionPlan as CloudPlan;
    match plan {
      CloudPlan::Free => SubscriptionPlan::Free,
      CloudPlan::Basic => SubscriptionPlan::Free, // Basic plan maps to Free
      CloudPlan::Pro => SubscriptionPlan::Pro,
      CloudPlan::Team => SubscriptionPlan::Team,
      CloudPlan::AiMax => SubscriptionPlan::AiMax,
      CloudPlan::AiLocal => SubscriptionPlan::AiLocal,
    }
  }
}

impl Default for SubscriptionPlan {
  fn default() -> Self {
    SubscriptionPlan::Free
  }
}

impl fmt::Display for SubscriptionPlan {
  fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
    match self {
      SubscriptionPlan::Free => write!(f, "free"),
      SubscriptionPlan::Basic => write!(f, "basic"),
      SubscriptionPlan::Pro => write!(f, "pro"),
      SubscriptionPlan::Team => write!(f, "team"),
      SubscriptionPlan::AiMax => write!(f, "ai_max"),
      SubscriptionPlan::AiLocal => write!(f, "ai_local"),
    }
  }
}

impl FromStr for SubscriptionPlan {
  type Err = String;

  fn from_str(s: &str) -> Result<Self, Self::Err> {
    match s.to_lowercase().as_str() {
      "free" => Ok(SubscriptionPlan::Free),
      "basic" => Ok(SubscriptionPlan::Basic),
      "pro" => Ok(SubscriptionPlan::Pro),
      "team" => Ok(SubscriptionPlan::Team),
      "ai_max" => Ok(SubscriptionPlan::AiMax),
      "ai_local" => Ok(SubscriptionPlan::AiLocal),
      _ => Err(format!("Unknown subscription plan: {}", s)),
    }
  }
}

impl TryFrom<i16> for SubscriptionPlan {
  type Error = String;

  fn try_from(value: i16) -> Result<Self, Self::Error> {
    match value {
      0 => Ok(SubscriptionPlan::Free),
      1 => Ok(SubscriptionPlan::Basic),
      2 => Ok(SubscriptionPlan::Pro),
      3 => Ok(SubscriptionPlan::Team),
      4 => Ok(SubscriptionPlan::AiMax),
      5 => Ok(SubscriptionPlan::AiLocal),
      _ => Err(format!("Unknown subscription plan value: {}", value)),
    }
  }
}

use flowy_derive::{ProtoBuf, ProtoBuf_Enum};
use flowy_user_pub::cloud::{AFWorkspaceSettings, AFWorkspaceSettingsChange};
use flowy_user_pub::entities::{
  AuthType, Role, WorkspaceInvitation, WorkspaceMember, WorkspaceType,
};
use lib_infra::validator_fn::{email_or_phone, required_not_empty_str};

#[derive(ProtoBuf, Default, Clone)]
pub struct WorkspaceMemberPB {
  #[pb(index = 1)]
  pub email: String,

  #[pb(index = 2)]
  pub name: String,

  #[pb(index = 3)]
  pub role: AFRolePB,

  #[pb(index = 4, one_of)]
  pub avatar_url: Option<String>,

  #[pb(index = 5, one_of)]
  pub joined_at: Option<i64>,
}

impl From<WorkspaceMember> for WorkspaceMemberPB {
  fn from(value: WorkspaceMember) -> Self {
    Self {
      email: value.email,
      name: value.name,
      role: value.role.into(),
      avatar_url: value.avatar_url,
      joined_at: value.joined_at,
    }
  }
}

#[derive(ProtoBuf, Default, Clone)]
pub struct RepeatedWorkspaceMemberPB {
  #[pb(index = 1)]
  pub items: Vec<WorkspaceMemberPB>,
}

// Team (协作区) definitions
#[derive(ProtoBuf, Default, Clone)]
pub struct TeamPB {
  #[pb(index = 1)]
  pub team_id: String,

  #[pb(index = 2)]
  pub workspace_id: String,

  #[pb(index = 3)]
  pub name: String,

  #[pb(index = 4, one_of)]
  pub description: Option<String>,

  #[pb(index = 5, one_of)]
  pub created_at: Option<i64>,

  #[pb(index = 6, one_of)]
  pub updated_at: Option<i64>,
}

#[derive(ProtoBuf, Default, Clone)]
pub struct RepeatedTeamPB {
  #[pb(index = 1)]
  pub items: Vec<TeamPB>,
}

// Team ACL: explicit whitelist supporting both user ids and emails
#[derive(ProtoBuf, Default, Clone)]
pub struct TeamACLPB {
  #[pb(index = 1)]
  pub team_id: String,

  #[pb(index = 2)]
  pub allow_user_ids: Vec<i64>,

  #[pb(index = 3)]
  pub allow_emails: Vec<String>,
}

#[derive(ProtoBuf, Default, Clone, Validate)]
pub struct UpdateTeamACLPB {
  #[pb(index = 1)]
  pub acl: TeamACLPB,
}

#[derive(ProtoBuf, Default, Clone, Validate)]
pub struct TeamIdPB {
  #[pb(index = 1)]
  #[validate(custom(function = "required_not_empty_str"))]
  pub team_id: String,
}

#[derive(ProtoBuf, Default, Clone, Validate)]
pub struct WorkspaceMemberInvitationPB {
  #[pb(index = 1)]
  #[validate(custom(function = "required_not_empty_str"))]
  pub workspace_id: String,

  #[pb(index = 2)]
  #[validate(custom(function = "email_or_phone"))]
  pub invitee_email: String,

  #[pb(index = 3)]
  pub role: AFRolePB,
}

#[derive(Debug, ProtoBuf, Default, Clone)]
pub struct RepeatedWorkspaceInvitationPB {
  #[pb(index = 1)]
  pub items: Vec<WorkspaceInvitationPB>,
}

#[derive(Debug, ProtoBuf, Default, Clone)]
pub struct WorkspaceInvitationPB {
  #[pb(index = 1)]
  pub invite_id: String,
  #[pb(index = 2)]
  pub workspace_id: String,
  #[pb(index = 3)]
  pub workspace_name: String,
  #[pb(index = 4)]
  pub inviter_email: String,
  #[pb(index = 5)]
  pub inviter_name: String,
  #[pb(index = 6)]
  pub status: String,
  #[pb(index = 7)]
  pub updated_at_timestamp: i64,
}

impl From<WorkspaceInvitation> for WorkspaceInvitationPB {
  fn from(value: WorkspaceInvitation) -> Self {
    Self {
      invite_id: value.invite_id.to_string(),
      workspace_id: value.workspace_id.to_string(),
      workspace_name: value.workspace_name.unwrap_or_default(),
      inviter_email: value.inviter_email.unwrap_or_default(),
      inviter_name: value.inviter_name.unwrap_or_default(),
      status: format!("{:?}", value.status),
      updated_at_timestamp: value.updated_at.timestamp(),
    }
  }
}

#[derive(ProtoBuf, Default, Clone, Validate)]
pub struct AcceptWorkspaceInvitationPB {
  #[pb(index = 1)]
  #[validate(custom(function = "required_not_empty_str"))]
  pub invite_id: String,
}

// Deprecated
#[derive(ProtoBuf, Default, Clone, Validate)]
pub struct AddWorkspaceMemberPB {
  #[pb(index = 1)]
  #[validate(custom(function = "required_not_empty_str"))]
  pub workspace_id: String,

  #[pb(index = 2)]
  #[validate(email)]
  pub email: String,
}

#[derive(ProtoBuf, Default, Clone, Validate)]
pub struct QueryWorkspacePB {
  #[pb(index = 1)]
  #[validate(custom(function = "required_not_empty_str"))]
  pub workspace_id: String,
}

#[derive(ProtoBuf, Default, Clone, Validate)]
pub struct RemoveWorkspaceMemberPB {
  #[pb(index = 1)]
  #[validate(custom(function = "required_not_empty_str"))]
  pub workspace_id: String,

  #[pb(index = 2)]
  #[validate(email)]
  pub email: String,
}

#[derive(ProtoBuf, Default, Clone, Validate)]
pub struct UpdateWorkspaceMemberPB {
  #[pb(index = 1)]
  #[validate(custom(function = "required_not_empty_str"))]
  pub workspace_id: String,

  #[pb(index = 2)]
  #[validate(email)]
  pub email: String,

  #[pb(index = 3)]
  pub role: AFRolePB,
}

// Workspace Role
#[derive(Debug, ProtoBuf_Enum, Clone, Default, Eq, PartialEq)]
pub enum AFRolePB {
  Owner = 0,
  Member = 1,
  #[default]
  Guest = 2,
}

impl From<i32> for AFRolePB {
  fn from(value: i32) -> Self {
    match value {
      0 => AFRolePB::Owner,
      1 => AFRolePB::Member,
      2 => AFRolePB::Guest,
      _ => AFRolePB::Guest,
    }
  }
}

impl From<AFRolePB> for Role {
  fn from(value: AFRolePB) -> Self {
    match value {
      AFRolePB::Owner => Role::Owner,
      AFRolePB::Member => Role::Member,
      AFRolePB::Guest => Role::Guest,
    }
  }
}

impl From<Role> for AFRolePB {
  fn from(value: Role) -> Self {
    match value {
      Role::Owner => AFRolePB::Owner,
      Role::Member => AFRolePB::Member,
      Role::Guest => AFRolePB::Guest,
    }
  }
}

#[derive(ProtoBuf, Default, Clone, Validate)]
pub struct UserWorkspaceIdPB {
  #[pb(index = 1)]
  #[validate(custom(function = "required_not_empty_str"))]
  pub workspace_id: String,
}

#[derive(ProtoBuf, Default, Clone, Validate)]
pub struct OpenUserWorkspacePB {
  #[pb(index = 1)]
  #[validate(custom(function = "required_not_empty_str"))]
  pub workspace_id: String,

  #[pb(index = 2)]
  pub workspace_type: WorkspaceTypePB,
}

#[derive(ProtoBuf, Default, Clone, Validate)]
pub struct CancelWorkspaceSubscriptionPB {
  #[pb(index = 1)]
  #[validate(custom(function = "required_not_empty_str"))]
  pub workspace_id: String,

  #[pb(index = 2)]
  pub plan: SubscriptionPlanPB,

  #[pb(index = 3)]
  pub reason: String,
}

#[derive(ProtoBuf, Default, Clone, Validate)]
pub struct SuccessWorkspaceSubscriptionPB {
  #[pb(index = 1)]
  #[validate(custom(function = "required_not_empty_str"))]
  pub workspace_id: String,

  #[pb(index = 2, one_of)]
  pub plan: Option<SubscriptionPlanPB>,
}

#[derive(ProtoBuf, Default, Clone)]
pub struct WorkspaceMemberIdPB {
  #[pb(index = 1)]
  pub uid: i64,
}

#[derive(ProtoBuf, Default, Clone, Validate)]
pub struct CreateWorkspacePB {
  #[pb(index = 1)]
  #[validate(custom(function = "required_not_empty_str"))]
  pub name: String,

  #[pb(index = 2)]
  pub workspace_type: WorkspaceTypePB,
}

#[derive(ProtoBuf_Enum, Copy, Default, Debug, Clone, Eq, PartialEq)]
#[repr(u8)]
pub enum WorkspaceTypePB {
  #[default]
  LocalW = 0,
  ServerW = 1,
}

impl From<i32> for WorkspaceTypePB {
  fn from(value: i32) -> Self {
    match value {
      0 => WorkspaceTypePB::LocalW,
      1 => WorkspaceTypePB::ServerW,
      _ => WorkspaceTypePB::ServerW,
    }
  }
}

impl From<WorkspaceType> for WorkspaceTypePB {
  fn from(value: WorkspaceType) -> Self {
    match value {
      WorkspaceType::Local => WorkspaceTypePB::LocalW,
      WorkspaceType::Server => WorkspaceTypePB::ServerW,
    }
  }
}

impl From<WorkspaceTypePB> for WorkspaceType {
  fn from(value: WorkspaceTypePB) -> Self {
    match value {
      WorkspaceTypePB::LocalW => WorkspaceType::Local,
      WorkspaceTypePB::ServerW => WorkspaceType::Server,
    }
  }
}

#[derive(ProtoBuf_Enum, Copy, Default, Debug, Clone, Eq, PartialEq)]
#[repr(u8)]
pub enum AuthTypePB {
  #[default]
  Local = 0,
  Server = 1,
}

impl From<i32> for AuthTypePB {
  fn from(value: i32) -> Self {
    match value {
      0 => AuthTypePB::Local,
      1 => AuthTypePB::Server,
      _ => AuthTypePB::Server,
    }
  }
}

impl From<AuthType> for AuthTypePB {
  fn from(value: AuthType) -> Self {
    match value {
      AuthType::Local => AuthTypePB::Local,
      AuthType::AppFlowyCloud => AuthTypePB::Server,
    }
  }
}

impl From<AuthTypePB> for AuthType {
  fn from(value: AuthTypePB) -> Self {
    match value {
      AuthTypePB::Local => AuthType::Local,
      AuthTypePB::Server => AuthType::AppFlowyCloud,
    }
  }
}

#[derive(ProtoBuf, Default, Clone, Validate)]
pub struct RenameWorkspacePB {
  #[pb(index = 1)]
  #[validate(custom(function = "required_not_empty_str"))]
  pub workspace_id: String,

  #[pb(index = 2)]
  #[validate(custom(function = "required_not_empty_str"))]
  pub new_name: String,
}

#[derive(ProtoBuf, Default, Clone, Validate)]
pub struct ChangeWorkspaceIconPB {
  #[pb(index = 1)]
  #[validate(custom(function = "required_not_empty_str"))]
  pub workspace_id: String,

  #[pb(index = 2)]
  pub new_icon: String,
}

#[derive(ProtoBuf, Default, Clone, Validate, Debug)]
pub struct SubscribeWorkspacePB {
  #[pb(index = 1)]
  #[validate(custom(function = "required_not_empty_str"))]
  pub workspace_id: String,

  #[pb(index = 2)]
  pub recurring_interval: RecurringIntervalPB,

  #[pb(index = 3)]
  pub workspace_subscription_plan: SubscriptionPlanPB,

  #[pb(index = 4)]
  pub success_url: String,
}

#[derive(ProtoBuf_Enum, Clone, Default, Debug, Serialize, Deserialize)]
pub enum RecurringIntervalPB {
  #[default]
  Month = 0,
  Year = 1,
}

impl From<RecurringIntervalPB> for RecurringInterval {
  fn from(r: RecurringIntervalPB) -> Self {
    match r {
      RecurringIntervalPB::Month => RecurringInterval::Month,
      RecurringIntervalPB::Year => RecurringInterval::Year,
    }
  }
}

impl From<RecurringInterval> for RecurringIntervalPB {
  fn from(r: RecurringInterval) -> Self {
    match r {
      RecurringInterval::Month => RecurringIntervalPB::Month,
      RecurringInterval::Year => RecurringIntervalPB::Year,
    }
  }
}

#[derive(ProtoBuf_Enum, Clone, Default, Debug, Serialize, Deserialize)]
pub enum SubscriptionPlanPB {
  #[default]
  Free = 0,
  Student = 1,
  Standard = 2,
  Team = 3,

  // Add-ons
  AiMax = 4,
  AiLocal = 5,
}

impl From<WorkspacePlanPB> for SubscriptionPlanPB {
  fn from(value: WorkspacePlanPB) -> Self {
    match value {
      WorkspacePlanPB::FreePlan => SubscriptionPlanPB::Free,
      WorkspacePlanPB::StudentPlan => SubscriptionPlanPB::Student,
      WorkspacePlanPB::StandardPlan => SubscriptionPlanPB::Standard,
      WorkspacePlanPB::TeamPlan => SubscriptionPlanPB::Team,
    }
  }
}

impl From<SubscriptionPlanPB> for SubscriptionPlan {
  fn from(value: SubscriptionPlanPB) -> Self {
    match value {
      SubscriptionPlanPB::Free => SubscriptionPlan::Free,
      SubscriptionPlanPB::Student => SubscriptionPlan::Basic,
      SubscriptionPlanPB::Standard => SubscriptionPlan::Pro,
      SubscriptionPlanPB::Team => SubscriptionPlan::Team,
      SubscriptionPlanPB::AiMax => SubscriptionPlan::AiMax,
      SubscriptionPlanPB::AiLocal => SubscriptionPlan::AiLocal,
    }
  }
}

impl From<SubscriptionPlan> for SubscriptionPlanPB {
  fn from(value: SubscriptionPlan) -> Self {
    match value {
      SubscriptionPlan::Free => SubscriptionPlanPB::Free,
      SubscriptionPlan::Basic => SubscriptionPlanPB::Student,
      SubscriptionPlan::Pro => SubscriptionPlanPB::Standard,
      SubscriptionPlan::Team => SubscriptionPlanPB::Team,
      SubscriptionPlan::AiMax => SubscriptionPlanPB::AiMax,
      SubscriptionPlan::AiLocal => SubscriptionPlanPB::AiLocal,
    }
  }
}

impl From<SubscriptionPlanPB> for client_api::entity::billing_dto::SubscriptionPlan {
  fn from(value: SubscriptionPlanPB) -> Self {
    use client_api::entity::billing_dto::SubscriptionPlan as CloudPlan;
    match value {
      SubscriptionPlanPB::Free => CloudPlan::Free,
      SubscriptionPlanPB::Student => CloudPlan::Pro, // Map Student to Pro for cloud
      SubscriptionPlanPB::Standard => CloudPlan::Pro,
      SubscriptionPlanPB::Team => CloudPlan::Team,
      SubscriptionPlanPB::AiMax => CloudPlan::AiMax,
      SubscriptionPlanPB::AiLocal => CloudPlan::AiLocal,
    }
  }
}

impl From<client_api::entity::billing_dto::SubscriptionPlan> for SubscriptionPlanPB {
  fn from(value: client_api::entity::billing_dto::SubscriptionPlan) -> Self {
    use client_api::entity::billing_dto::SubscriptionPlan as CloudPlan;
    match value {
      CloudPlan::Free => SubscriptionPlanPB::Free,
      CloudPlan::Basic => SubscriptionPlanPB::Free, // Basic plan maps to Free
      CloudPlan::Pro => SubscriptionPlanPB::Standard,
      CloudPlan::Team => SubscriptionPlanPB::Team,
      CloudPlan::AiMax => SubscriptionPlanPB::AiMax,
      CloudPlan::AiLocal => SubscriptionPlanPB::AiLocal,
    }
  }
}

#[derive(Debug, ProtoBuf, Default, Clone)]
pub struct PaymentLinkPB {
  #[pb(index = 1)]
  pub payment_link: String,
}

#[derive(Debug, ProtoBuf, Default, Clone)]
pub struct WorkspaceUsagePB {
  #[pb(index = 1)]
  pub member_count: u64,
  #[pb(index = 2)]
  pub member_count_limit: u64,
  #[pb(index = 3)]
  pub storage_bytes: u64,
  #[pb(index = 4)]
  pub storage_bytes_limit: u64,
  #[pb(index = 5)]
  pub storage_bytes_unlimited: bool,
  #[pb(index = 6)]
  pub ai_responses_count: u64,
  #[pb(index = 7)]
  pub ai_responses_count_limit: u64,
  #[pb(index = 8)]
  pub ai_responses_unlimited: bool,
  #[pb(index = 9)]
  pub local_ai: bool,
  #[pb(index = 10)]
  pub ai_image_responses_count: u64,
  #[pb(index = 11)]
  pub ai_image_responses_count_limit: u64,
}

impl From<WorkspaceUsageAndLimit> for WorkspaceUsagePB {
  fn from(workspace_usage: WorkspaceUsageAndLimit) -> Self {
    WorkspaceUsagePB {
      member_count: workspace_usage.member_count as u64,
      member_count_limit: workspace_usage.member_count_limit as u64,
      storage_bytes: workspace_usage.storage_bytes as u64,
      storage_bytes_limit: workspace_usage.storage_bytes_limit as u64,
      storage_bytes_unlimited: workspace_usage.storage_bytes_unlimited,
      ai_responses_count: workspace_usage.ai_responses_count as u64,
      ai_responses_count_limit: workspace_usage.ai_responses_count_limit as u64,
      ai_responses_unlimited: workspace_usage.ai_responses_unlimited,
      local_ai: workspace_usage.local_ai,
      ai_image_responses_count: workspace_usage.ai_image_responses_count as u64,
      ai_image_responses_count_limit: workspace_usage.ai_image_responses_count_limit as u64,
    }
  }
}

#[derive(Debug, ProtoBuf, Default, Clone)]
pub struct BillingPortalPB {
  #[pb(index = 1)]
  pub url: String,
}

#[derive(ProtoBuf, Default, Clone, Validate, Eq, PartialEq)]
pub struct WorkspaceSettingsPB {
  #[pb(index = 1)]
  pub disable_search_indexing: bool,

  #[pb(index = 2)]
  pub ai_model: String,

  #[pb(index = 3)]
  pub workspace_type: WorkspaceTypePB,
 
  /// 新增：仅工作空间所有者可创建团队协作区
  #[pb(index = 4)]
  pub only_owner_can_create_team_workspace: bool,
}

impl From<&AFWorkspaceSettings> for WorkspaceSettingsPB {
  fn from(value: &AFWorkspaceSettings) -> Self {
    Self {
      disable_search_indexing: value.disable_search_indexing,
      ai_model: value.ai_model.clone(),
      workspace_type: WorkspaceTypePB::ServerW,
      only_owner_can_create_team_workspace: value.only_owner_can_create_team_workspace,
    }
  }
}

#[derive(ProtoBuf, Default, Clone, Validate, Debug)]
pub struct UpdateUserWorkspaceSettingPB {
  #[pb(index = 1)]
  #[validate(custom(function = "required_not_empty_str"))]
  pub workspace_id: String,

  #[pb(index = 2, one_of)]
  pub disable_search_indexing: Option<bool>,

  #[pb(index = 3, one_of)]
  pub ai_model: Option<String>,

  #[pb(index = 4, one_of)]
  pub only_owner_can_create_team_workspace: Option<bool>,
}

impl From<UpdateUserWorkspaceSettingPB> for AFWorkspaceSettingsChange {
  fn from(value: UpdateUserWorkspaceSettingPB) -> Self {
    let mut change = AFWorkspaceSettingsChange::new();
    if let Some(disable_search_indexing) = value.disable_search_indexing {
      change.disable_search_indexing = Some(disable_search_indexing);
    }
    if let Some(ai_model) = value.ai_model {
      change.ai_model = Some(ai_model);
    }
    if let Some(only_owner_flag) = value.only_owner_can_create_team_workspace {
      change.only_owner_can_create_team_workspace = Some(only_owner_flag);
    }
    change
  }
}

#[derive(Debug, ProtoBuf, Default, Clone)]
pub struct WorkspaceSubscriptionInfoPB {
  #[pb(index = 1)]
  pub plan: WorkspacePlanPB,
  #[pb(index = 2)]
  pub plan_subscription: WorkspaceSubscriptionV2PB, // valid if plan is not WorkspacePlanFree
  #[pb(index = 3)]
  pub add_ons: Vec<WorkspaceAddOnPB>,
}

impl WorkspaceSubscriptionInfoPB {
  pub fn default_from_workspace_id(workspace_id: String) -> Self {
    Self {
      plan: WorkspacePlanPB::FreePlan,
      plan_subscription: WorkspaceSubscriptionV2PB {
        workspace_id,
        subscription_plan: SubscriptionPlanPB::Free,
        status: WorkspaceSubscriptionStatusPB::Active,
        end_date: 0,
        interval: RecurringIntervalPB::Month,
      },
      add_ons: Vec::new(),
    }
  }
}

impl From<Vec<CloudWorkspaceSubscriptionStatus>> for WorkspaceSubscriptionInfoPB {
  fn from(cloud_subs: Vec<CloudWorkspaceSubscriptionStatus>) -> Self {
    let subs: Vec<WorkspaceSubscriptionStatus> = cloud_subs.into_iter().map(|s| s.into()).collect();
    Self::from(subs)
  }
}

impl From<Vec<WorkspaceSubscriptionStatus>> for WorkspaceSubscriptionInfoPB {
  fn from(subs: Vec<WorkspaceSubscriptionStatus>) -> Self {
    let mut plan = WorkspacePlanPB::FreePlan;
    let mut plan_subscription = WorkspaceSubscriptionV2PB::default();
    let mut add_ons = Vec::new();
    for sub in subs {
      match sub.workspace_plan {
        SubscriptionPlan::Free => {
          plan = WorkspacePlanPB::FreePlan;
        },
        SubscriptionPlan::Basic => {
          plan = WorkspacePlanPB::StudentPlan;
          plan_subscription = sub.into();
        },
        SubscriptionPlan::Pro => {
          plan = WorkspacePlanPB::StandardPlan;
          plan_subscription = sub.into();
        },
        SubscriptionPlan::Team => {
          plan = WorkspacePlanPB::TeamPlan;
        },
        SubscriptionPlan::AiMax => {
          if plan_subscription.workspace_id.is_empty() {
            plan_subscription =
              WorkspaceSubscriptionV2PB::default_with_workspace_id(sub.workspace_id.clone());
          }

          add_ons.push(WorkspaceAddOnPB {
            type_: WorkspaceAddOnPBType::AddOnAiMax,
            add_on_subscription: sub.into(),
          });
        },
        SubscriptionPlan::AiLocal => {
          if plan_subscription.workspace_id.is_empty() {
            plan_subscription =
              WorkspaceSubscriptionV2PB::default_with_workspace_id(sub.workspace_id.clone());
          }

          add_ons.push(WorkspaceAddOnPB {
            type_: WorkspaceAddOnPBType::AddOnAiLocal,
            add_on_subscription: sub.into(),
          });
        },
      }
    }

    WorkspaceSubscriptionInfoPB {
      plan,
      plan_subscription,
      add_ons,
    }
  }
}

#[derive(ProtoBuf_Enum, Debug, Clone, Eq, PartialEq, Default)]
pub enum WorkspacePlanPB {
  #[default]
  FreePlan = 0,
  StudentPlan = 1,
  StandardPlan = 2,
  TeamPlan = 3,
}

impl From<WorkspacePlanPB> for i64 {
  fn from(val: WorkspacePlanPB) -> Self {
    val as i64
  }
}

impl From<i64> for WorkspacePlanPB {
  fn from(value: i64) -> Self {
    match value {
      0 => WorkspacePlanPB::FreePlan,
      1 => WorkspacePlanPB::StudentPlan,
      2 => WorkspacePlanPB::StandardPlan,
      3 => WorkspacePlanPB::TeamPlan,
      _ => WorkspacePlanPB::FreePlan,
    }
  }
}

#[derive(Debug, ProtoBuf, Default, Clone, Serialize, Deserialize)]
pub struct WorkspaceAddOnPB {
  #[pb(index = 1)]
  type_: WorkspaceAddOnPBType,
  #[pb(index = 2)]
  add_on_subscription: WorkspaceSubscriptionV2PB,
}

#[derive(ProtoBuf_Enum, Debug, Clone, Eq, PartialEq, Default, Serialize, Deserialize)]
pub enum WorkspaceAddOnPBType {
  #[default]
  AddOnAiLocal = 0,
  AddOnAiMax = 1,
}

#[derive(Debug, ProtoBuf, Default, Clone, Serialize, Deserialize)]
pub struct WorkspaceSubscriptionV2PB {
  #[pb(index = 1)]
  pub workspace_id: String,

  #[pb(index = 2)]
  pub subscription_plan: SubscriptionPlanPB,

  #[pb(index = 3)]
  pub status: WorkspaceSubscriptionStatusPB,

  #[pb(index = 4)]
  pub end_date: i64, // Unix timestamp of when this subscription cycle ends

  #[pb(index = 5)]
  pub interval: RecurringIntervalPB,
}

impl WorkspaceSubscriptionV2PB {
  pub fn default_with_workspace_id(workspace_id: String) -> Self {
    Self {
      workspace_id,
      subscription_plan: SubscriptionPlanPB::Free,
      status: WorkspaceSubscriptionStatusPB::Active,
      end_date: 0,
      interval: RecurringIntervalPB::Month,
    }
  }
}

impl From<WorkspaceSubscriptionStatus> for WorkspaceSubscriptionV2PB {
  fn from(sub: WorkspaceSubscriptionStatus) -> Self {
    Self {
      workspace_id: sub.workspace_id,
      subscription_plan: sub.workspace_plan.clone().into(),
      status: if sub.cancel_at.is_some() {
        WorkspaceSubscriptionStatusPB::Canceled
      } else {
        WorkspaceSubscriptionStatusPB::Active
      },
      interval: sub.recurring_interval.into(),
      end_date: sub.current_period_end,
    }
  }
}

#[derive(ProtoBuf_Enum, Debug, Clone, Eq, PartialEq, Default, Serialize, Deserialize)]
pub enum WorkspaceSubscriptionStatusPB {
  #[default]
  Active = 0,
  Canceled = 1,
}

impl From<WorkspaceSubscriptionStatusPB> for i64 {
  fn from(val: WorkspaceSubscriptionStatusPB) -> Self {
    val as i64
  }
}

impl From<i64> for WorkspaceSubscriptionStatusPB {
  fn from(value: i64) -> Self {
    match value {
      0 => WorkspaceSubscriptionStatusPB::Active,
      _ => WorkspaceSubscriptionStatusPB::Canceled,
    }
  }
}

#[derive(ProtoBuf, Default, Clone, Validate)]
pub struct UpdateWorkspaceSubscriptionPaymentPeriodPB {
  #[pb(index = 1)]
  #[validate(custom(function = "required_not_empty_str"))]
  pub workspace_id: String,

  #[pb(index = 2)]
  pub plan: SubscriptionPlanPB,

  #[pb(index = 3)]
  pub recurring_interval: RecurringIntervalPB,
}

#[derive(ProtoBuf, Default, Clone)]
pub struct RepeatedSubscriptionPlanDetailPB {
  #[pb(index = 1)]
  pub items: Vec<SubscriptionPlanDetailPB>,
}

#[derive(ProtoBuf, Default, Clone)]
pub struct SubscriptionPlanDetailPB {
  #[pb(index = 1)]
  pub currency: CurrencyPB,
  #[pb(index = 2)]
  pub price_cents: i64,
  #[pb(index = 3)]
  pub recurring_interval: RecurringIntervalPB,
  #[pb(index = 4)]
  pub plan: SubscriptionPlanPB,
}

impl From<SubscriptionPlanDetail> for SubscriptionPlanDetailPB {
  fn from(value: SubscriptionPlanDetail) -> Self {
    Self {
      currency: value.currency.into(),
      price_cents: value.price_cents,
      recurring_interval: value.recurring_interval.into(),
      plan: value.plan.into(),
    }
  }
}

#[derive(ProtoBuf_Enum, Clone, Default)]
pub enum CurrencyPB {
  #[default]
  USD = 0,
}

impl From<Currency> for CurrencyPB {
  fn from(value: Currency) -> Self {
    match value {
      Currency::USD => CurrencyPB::USD,
    }
  }
}

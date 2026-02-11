use crate::entities::*;
use crate::notification::{send_notification, UserNotification};
use crate::services::cloud_config::{
  get_cloud_config, get_or_create_cloud_config, save_cloud_config,
};
use crate::services::data_import::prepare_import;
use crate::user_manager::UserManager;
use flowy_error::{ErrorCode, FlowyError, FlowyResult};
use flowy_sqlite::kv::KVStorePreferences;
use flowy_sqlite::RunQueryDsl;
use flowy_user_pub::entities::*;
use flowy_user_pub::sql::UserWorkspaceChangeset;
use lib_dispatch::prelude::*;
use lib_infra::box_any::BoxAny;
use serde_json::Value;
use std::str::FromStr;
use std::sync::Weak;
use std::{convert::TryInto, sync::Arc};
use tracing::event;
use uuid::Uuid;

fn upgrade_manager(manager: AFPluginState<Weak<UserManager>>) -> FlowyResult<Arc<UserManager>> {
  let manager = manager
    .upgrade()
    .ok_or(FlowyError::internal().with_context("The user session is already drop"))?;
  Ok(manager)
}

fn upgrade_store_preferences(
  store: AFPluginState<Weak<KVStorePreferences>>,
) -> FlowyResult<Arc<KVStorePreferences>> {
  let store = store
    .upgrade()
    .ok_or(FlowyError::internal().with_context("The store preferences is already drop"))?;
  Ok(store)
}

#[tracing::instrument(level = "debug", name = "sign_in", skip(data, manager), fields(
    email = % data.email
), err)]
pub async fn sign_in_with_email_password_handler(
  data: AFPluginData<SignInPayloadPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> DataResult<GotrueTokenResponsePB, FlowyError> {
  let manager = upgrade_manager(manager)?;
  let params: SignInParams = data.into_inner().try_into()?;

  match manager
    .sign_in_with_password(&params.email, &params.password)
    .await
  {
    Ok(token) => data_result_ok(token.into()),
    Err(err) => Err(err),
  }
}

#[tracing::instrument(
    level = "debug",
    name = "sign_up",
    skip(data, manager),
    fields(
        email = % data.email,
        name = % data.name,
    ),
    err
)]
pub async fn sign_up(
  data: AFPluginData<SignUpPayloadPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> DataResult<UserProfilePB, FlowyError> {
  let manager = upgrade_manager(manager)?;
  let params: SignUpParams = data.into_inner().try_into()?;
  let auth_type = params.auth_type;

  match manager.sign_up(auth_type, BoxAny::new(params)).await {
    Ok(profile) => data_result_ok(UserProfilePB::from(profile)),
    Err(err) => Err(err),
  }
}

#[tracing::instrument(level = "debug", skip(manager))]
pub async fn init_user_handler(
  manager: AFPluginState<Weak<UserManager>>,
) -> Result<(), FlowyError> {
  let manager = upgrade_manager(manager)?;
  manager.init_user().await?;
  Ok(())
}

#[tracing::instrument(level = "debug", skip(manager))]
pub async fn get_user_profile_handler(
  manager: AFPluginState<Weak<UserManager>>,
) -> DataResult<UserProfilePB, FlowyError> {
  let manager = upgrade_manager(manager)?;
  let session = manager.get_session()?;

  tracing::info!("🔄 [get_user_profile_handler] Step 1: Reading from local disk");
  let mut user_profile = manager
    .get_user_profile_from_disk(session.user_id, &session.workspace_id)
    .await?;
  tracing::info!(
    "🔄 [get_user_profile_handler] Step 1 result: phone={:?}",
    user_profile.phone
  );

  // Refresh the user profile from cloud and wait for it to complete
  // This ensures we get the latest user profile including phone number
  // Use force=true to bypass debounce check
  tracing::info!("🔄 [get_user_profile_handler] Step 2: Refreshing from cloud (forced)");
  let refresh_result = manager
    .refresh_user_profile_with_force(&user_profile, &session.workspace_id, true)
    .await;
  tracing::info!(
    "🔄 [get_user_profile_handler] Step 2 result: {:?}",
    refresh_result
  );
  
  // Re-fetch the user profile from disk after refresh
  tracing::info!("🔄 [get_user_profile_handler] Step 3: Re-reading from local disk");
  user_profile = manager
    .get_user_profile_from_disk(session.user_id, &session.workspace_id)
    .await?;
  tracing::info!(
    "🔄 [get_user_profile_handler] Step 3 result: phone={:?}",
    user_profile.phone
  );

  // When the user is logged in with a local account, the email field is a placeholder and should
  // not be exposed to the client. So we set the email field to an empty string.
  if user_profile.auth_type == AuthType::Local {
    user_profile.email = "".to_string();
  }

  tracing::info!(
    "🔄 [get_user_profile_handler] Final result: email={}, phone={:?}, name={}",
    user_profile.email,
    user_profile.phone,
    user_profile.name
  );

  data_result_ok(user_profile.into())
}

#[tracing::instrument(level = "debug", skip(manager))]
pub async fn sign_out_handler(manager: AFPluginState<Weak<UserManager>>) -> Result<(), FlowyError> {
  let (tx, rx) = tokio::sync::oneshot::channel();
  tokio::spawn(async move {
    let result = async {
      let manager = upgrade_manager(manager)?;
      manager.sign_out().await?;
      Ok::<(), FlowyError>(())
    }
    .await;
    let _ = tx.send(result);
  });
  rx.await??;
  Ok(())
}

#[tracing::instrument(level = "debug", skip(manager))]
pub async fn delete_account_handler(
  manager: AFPluginState<Weak<UserManager>>,
) -> Result<(), FlowyError> {
  let manager = upgrade_manager(manager)?;
  manager.delete_account().await?;
  Ok(())
}

#[tracing::instrument(level = "debug", skip(data, manager))]
pub async fn update_user_profile_handler(
  data: AFPluginData<UpdateUserProfilePayloadPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> Result<(), FlowyError> {
  let manager = upgrade_manager(manager)?;
  let params: UpdateUserProfileParams = data.into_inner().try_into()?;
  manager.update_user_profile(params).await?;
  Ok(())
}

const APPEARANCE_SETTING_CACHE_KEY: &str = "appearance_settings";

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn set_appearance_setting(
  store_preferences: AFPluginState<Weak<KVStorePreferences>>,
  data: AFPluginData<AppearanceSettingsPB>,
) -> Result<(), FlowyError> {
  let store_preferences = upgrade_store_preferences(store_preferences)?;
  let mut setting = data.into_inner();
  if setting.theme.is_empty() {
    setting.theme = APPEARANCE_DEFAULT_THEME.to_string();
  }
  store_preferences.set_object(APPEARANCE_SETTING_CACHE_KEY, &setting)?;
  Ok(())
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn get_appearance_setting(
  store_preferences: AFPluginState<Weak<KVStorePreferences>>,
) -> DataResult<AppearanceSettingsPB, FlowyError> {
  let store_preferences = upgrade_store_preferences(store_preferences)?;
  match store_preferences.get_str(APPEARANCE_SETTING_CACHE_KEY) {
    None => data_result_ok(AppearanceSettingsPB::default()),
    Some(s) => {
      let setting = serde_json::from_str(&s).unwrap_or_else(|err| {
        tracing::error!(
          "Deserialize AppearanceSettings failed: {:?}, fallback to default",
          err
        );
        AppearanceSettingsPB::default()
      });
      data_result_ok(setting)
    },
  }
}

const DATE_TIME_SETTINGS_CACHE_KEY: &str = "date_time_settings";

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn set_date_time_settings(
  store_preferences: AFPluginState<Weak<KVStorePreferences>>,
  data: AFPluginData<DateTimeSettingsPB>,
) -> Result<(), FlowyError> {
  let store_preferences = upgrade_store_preferences(store_preferences)?;
  let mut setting = data.into_inner();
  if setting.timezone_id.is_empty() {
    setting.timezone_id = "".to_string();
  }

  store_preferences.set_object(DATE_TIME_SETTINGS_CACHE_KEY, &setting)?;
  Ok(())
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn get_date_time_settings(
  store_preferences: AFPluginState<Weak<KVStorePreferences>>,
) -> DataResult<DateTimeSettingsPB, FlowyError> {
  let store_preferences = upgrade_store_preferences(store_preferences)?;
  match store_preferences.get_str(DATE_TIME_SETTINGS_CACHE_KEY) {
    None => data_result_ok(DateTimeSettingsPB::default()),
    Some(s) => {
      let setting = match serde_json::from_str(&s) {
        Ok(setting) => setting,
        Err(e) => {
          tracing::error!(
            "Deserialize DateTimeSettings failed: {:?}, fallback to default",
            e
          );
          DateTimeSettingsPB::default()
        },
      };
      data_result_ok(setting)
    },
  }
}

// 注意：通知设置不再在本地 KV 落盘。
// Flutter 仅通过 Rust 读写；Rust 以服务端为准（GET/POST）。

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn set_notification_settings(
  manager: AFPluginState<Weak<UserManager>>,
  data: AFPluginData<NotificationSettingsPB>,
  _store_preferences: AFPluginState<Weak<KVStorePreferences>>,
) -> Result<(), FlowyError> {
  let manager = upgrade_manager(manager)?;
  let setting = data.into_inner();

  // Rust 直接调用服务端接口同步（无本地落盘）
  sync_notification_settings_to_cloud(&manager, &setting).await?;
  Ok(())
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn get_notification_settings(
  manager: AFPluginState<Weak<UserManager>>,
  _store_preferences: AFPluginState<Weak<KVStorePreferences>>,
) -> DataResult<NotificationSettingsPB, FlowyError> {
  let manager = upgrade_manager(manager)?;
  let setting = fetch_notification_settings_from_cloud(&manager).await?;
  data_result_ok(setting)
}

#[derive(Debug, serde::Serialize)]
struct NotificationPreferencesRequest<'a> {
  // 同时发送 camelCase + snake_case，兼容后端字段命名差异
  #[serde(rename = "notificationsEnabled")]
  notifications_enabled_camel: bool,
  #[serde(rename = "notifyAtMe")]
  notify_at_me_camel: bool,
  #[serde(rename = "notifyPending")]
  notify_pending_camel: bool,
  #[serde(rename = "notifyPermissionChange")]
  notify_permission_change_camel: bool,
  #[serde(rename = "notifyJoinTeam")]
  notify_join_team_camel: bool,
  #[serde(rename = "notifyClip")]
  notify_clip_camel: bool,

  #[serde(rename = "notifications_enabled")]
  notifications_enabled_snake: bool,
  #[serde(rename = "notify_at_me")]
  notify_at_me_snake: bool,
  #[serde(rename = "notify_pending")]
  notify_pending_snake: bool,
  #[serde(rename = "notify_permission_change")]
  notify_permission_change_snake: bool,
  #[serde(rename = "notify_join_team")]
  notify_join_team_snake: bool,
  #[serde(rename = "notify_clip")]
  notify_clip_snake: bool,

  #[serde(skip)]
  _phantom: std::marker::PhantomData<&'a ()>,
}

fn build_notification_preferences_request(setting: &NotificationSettingsPB) -> NotificationPreferencesRequest<'_> {
  NotificationPreferencesRequest {
    notifications_enabled_camel: setting.notifications_enabled,
    notify_at_me_camel: setting.notify_at_me,
    notify_pending_camel: setting.notify_pending,
    notify_permission_change_camel: setting.notify_permission_change,
    notify_join_team_camel: setting.notify_join_team,
    notify_clip_camel: setting.notify_clip,
    notifications_enabled_snake: setting.notifications_enabled,
    notify_at_me_snake: setting.notify_at_me,
    notify_pending_snake: setting.notify_pending,
    notify_permission_change_snake: setting.notify_permission_change,
    notify_join_team_snake: setting.notify_join_team,
    notify_clip_snake: setting.notify_clip,
    _phantom: std::marker::PhantomData,
  }
}

fn normalize_base_url(url: String) -> String {
  url.trim_end_matches('/').to_string()
}

async fn sync_notification_settings_to_cloud(
  manager: &UserManager,
  setting: &NotificationSettingsPB,
) -> Result<(), FlowyError> {
  let cloud_service = manager.cloud_service()?;
  let auth_type = cloud_service.get_server_auth_type();
  if !auth_type.is_appflowy_cloud() {
    // 非云端模式无需同步
    return Ok(());
  }

  let token = manager.token_from_auth_type(&auth_type)?.unwrap_or_default();
  if token.is_empty() {
    return Err(FlowyError::unauthorized().with_context("missing auth token"));
  }

  let base_url = normalize_base_url(cloud_service.service_url());
  let url = format!("{}/api/user/notification-preferences", base_url);

  let client = reqwest::Client::builder()
    .timeout(std::time::Duration::from_secs(20))
    .build()
    .map_err(|e| FlowyError::new(ErrorCode::Internal, format!("create http client failed: {}", e)))?;

  let body = build_notification_preferences_request(setting);
  let resp = client
    .post(url)
    .bearer_auth(token)
    .json(&body)
    .send()
    .await
    .map_err(|e| FlowyError::new(ErrorCode::Internal, format!("sync notification settings failed: {}", e)))?;

  if !resp.status().is_success() {
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    return Err(FlowyError::new(
      ErrorCode::Internal,
      format!("sync notification settings failed: status={}, body={}", status, text),
    ));
  }
  Ok(())
}

async fn fetch_notification_settings_from_cloud(manager: &UserManager) -> Result<NotificationSettingsPB, FlowyError> {
  let cloud_service = manager.cloud_service()?;
  let auth_type = cloud_service.get_server_auth_type();
  if !auth_type.is_appflowy_cloud() {
    return Ok(NotificationSettingsPB::default());
  }

  let token = manager.token_from_auth_type(&auth_type)?.unwrap_or_default();
  if token.is_empty() {
    return Ok(NotificationSettingsPB::default());
  }

  let base_url = normalize_base_url(cloud_service.service_url());
  let url = format!("{}/api/user/notification-preferences", base_url);

  let client = reqwest::Client::builder()
    .timeout(std::time::Duration::from_secs(20))
    .build()
    .map_err(|e| FlowyError::new(ErrorCode::Internal, format!("create http client failed: {}", e)))?;

  let resp = client
    .get(url)
    .bearer_auth(token)
    .send()
    .await
    .map_err(|e| FlowyError::new(ErrorCode::Internal, format!("fetch notification settings failed: {}", e)))?;

  if !resp.status().is_success() {
    // 拉取失败不阻塞前端，fallback 默认值
    return Ok(NotificationSettingsPB::default());
  }

  let json: serde_json::Value = resp.json().await.unwrap_or(serde_json::Value::Null);
  Ok(parse_notification_settings_json(json))
}

fn parse_bool(v: Option<&serde_json::Value>) -> Option<bool> {
  v.and_then(|x| {
    if let Some(b) = x.as_bool() {
      Some(b)
    } else if let Some(s) = x.as_str() {
      match s.to_lowercase().as_str() {
        "true" | "1" => Some(true),
        "false" | "0" => Some(false),
        _ => None,
      }
    } else {
      None
    }
  })
}

fn pick_bool(obj: &serde_json::Map<String, serde_json::Value>, keys: &[&str]) -> Option<bool> {
  for k in keys {
    if let Some(b) = parse_bool(obj.get(*k)) {
      return Some(b);
    }
  }
  None
}

fn parse_notification_settings_json(json: serde_json::Value) -> NotificationSettingsPB {
  // 兼容：{code,msg,data:{...}} 或者直接 {...}
  let root = match json {
    serde_json::Value::Object(map) => {
      if let Some(serde_json::Value::Object(data)) = map.get("data") {
        serde_json::Value::Object(data.clone())
      } else {
        serde_json::Value::Object(map)
      }
    },
    _ => serde_json::Value::Null,
  };

  let mut pb = NotificationSettingsPB::default();
  if let serde_json::Value::Object(obj) = root {
    pb.notifications_enabled = pick_bool(&obj, &["notificationsEnabled", "notifications_enabled"])
      .unwrap_or(pb.notifications_enabled);
    pb.notify_at_me = pick_bool(&obj, &["notifyAtMe", "notify_at_me"]).unwrap_or(pb.notify_at_me);
    pb.notify_pending = pick_bool(&obj, &["notifyPending", "notify_pending"]).unwrap_or(pb.notify_pending);
    pb.notify_permission_change =
      pick_bool(&obj, &["notifyPermissionChange", "notify_permission_change"]).unwrap_or(pb.notify_permission_change);
    pb.notify_join_team = pick_bool(&obj, &["notifyJoinTeam", "notify_join_team"]).unwrap_or(pb.notify_join_team);
    pb.notify_clip = pick_bool(&obj, &["notifyClip", "notify_clip"]).unwrap_or(pb.notify_clip);
  }
  pb
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn import_appflowy_data_folder_handler(
  data: AFPluginData<ImportAppFlowyDataPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> Result<(), FlowyError> {
  let data = data.try_into_inner()?;
  let (tx, rx) = tokio::sync::oneshot::channel();
  tokio::spawn(async move {
    let result = async {
      let manager = upgrade_manager(manager)?;
      let imported_folder = prepare_import(
        &data.path,
        data.parent_view_id,
        &manager.authenticate_user.user_config.app_version,
      )
      .map_err(|err| FlowyError::new(ErrorCode::AppFlowyDataFolderImportError, err.to_string()))?
      .with_container_name(data.import_container_name);

      manager.perform_import(imported_folder).await?;
      Ok::<(), FlowyError>(())
    }
    .await;
    let _ = tx.send(result);
  });
  rx.await??;
  Ok(())
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn get_user_setting(
  manager: AFPluginState<Weak<UserManager>>,
) -> DataResult<UserSettingPB, FlowyError> {
  let manager = upgrade_manager(manager)?;
  let user_setting = manager.user_setting()?;
  data_result_ok(user_setting)
}

#[tracing::instrument(level = "debug", skip(data, manager), err)]
pub async fn sign_in_with_magic_link_handler(
  data: AFPluginData<MagicLinkSignInPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> Result<(), FlowyError> {
  let manager = upgrade_manager(manager)?;
  let params = data.into_inner();
  manager
    .sign_in_with_magic_link(&params.email, &params.redirect_to)
    .await?;
  Ok(())
}

#[tracing::instrument(level = "debug", skip(data, manager), err)]
pub async fn sign_in_with_passcode_handler(
  data: AFPluginData<PasscodeSignInPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> DataResult<GotrueTokenResponsePB, FlowyError> {
  let manager = upgrade_manager(manager)?;
  let params = data.into_inner();
  let response = manager
    .sign_in_with_passcode(&params.email, &params.passcode)
    .await?;
  data_result_ok(response.into())
}

#[tracing::instrument(level = "debug", skip(data, manager), err)]
pub async fn verify_and_bind_phone_handler(
  data: AFPluginData<VerifyAndBindPhonePB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> Result<(), FlowyError> {
  let manager = upgrade_manager(manager)?;
  let params = data.into_inner();
  manager
    .verify_and_bind_phone(&params.phone, &params.otp)
    .await?;
  Ok(())
}

#[tracing::instrument(level = "debug", skip(data, manager), err)]
pub async fn oauth_sign_in_handler(
  data: AFPluginData<OauthSignInPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> DataResult<UserProfilePB, FlowyError> {
  let manager = upgrade_manager(manager)?;
  let params = data.into_inner();
  let authenticator: AuthType = params.auth_type.into();
  let user_profile = manager
    .sign_up(authenticator, BoxAny::new(params.map))
    .await?;
  data_result_ok(user_profile.into())
}

#[tracing::instrument(level = "debug", skip(data, manager), err)]
pub async fn gen_sign_in_url_handler(
  data: AFPluginData<SignInUrlPayloadPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> DataResult<SignInUrlPB, FlowyError> {
  let manager = upgrade_manager(manager)?;
  let params = data.into_inner();
  let authenticator: AuthType = params.authenticator.into();
  let sign_in_url = manager
    .generate_sign_in_url_with_email(&authenticator, &params.email)
    .await?;
  data_result_ok(SignInUrlPB { sign_in_url })
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn sign_in_with_provider_handler(
  data: AFPluginData<OauthProviderPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> DataResult<OauthProviderDataPB, FlowyError> {
  let manager = upgrade_manager(manager)?;
  tracing::debug!("Sign in with provider: {:?}", data.provider.as_str());
  let sign_in_url = manager.generate_oauth_url(data.provider.as_str()).await?;
  event!(tracing::Level::DEBUG, "Sign in url: {}", sign_in_url);
  data_result_ok(OauthProviderDataPB {
    oauth_url: sign_in_url,
  })
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn set_cloud_config_handler(
  manager: AFPluginState<Weak<UserManager>>,
  data: AFPluginData<UpdateCloudConfigPB>,
  store_preferences: AFPluginState<Weak<KVStorePreferences>>,
) -> Result<(), FlowyError> {
  let manager = upgrade_manager(manager)?;
  let session = manager.get_session()?;
  let update = data.into_inner();
  let store_preferences = upgrade_store_preferences(store_preferences)?;
  let mut config = get_cloud_config(session.user_id, &store_preferences)
    .ok_or(FlowyError::internal().with_context("Can't find any cloud config"))?;

  let cloud_service = manager.cloud_service()?;
  if let Some(enable_sync) = update.enable_sync {
    cloud_service.set_enable_sync(session.user_id, enable_sync);
    config.enable_sync = enable_sync;
  }

  save_cloud_config(session.user_id, &store_preferences, &config)?;

  let payload = CloudSettingPB {
    enable_sync: config.enable_sync,
    enable_encrypt: config.enable_encrypt,
    encrypt_secret: config.encrypt_secret,
    server_url: cloud_service.service_url(),
  };

  send_notification(
    // Don't change this key. it's also used in the frontend
    "user_cloud_config",
    UserNotification::DidUpdateCloudConfig,
  )
  .payload(payload)
  .send();
  Ok(())
}

#[tracing::instrument(level = "info", skip_all, err)]
pub async fn get_cloud_config_handler(
  manager: AFPluginState<Weak<UserManager>>,
  store_preferences: AFPluginState<Weak<KVStorePreferences>>,
) -> DataResult<CloudSettingPB, FlowyError> {
  let manager = upgrade_manager(manager)?;
  let session = manager.get_session()?;
  let store_preferences = upgrade_store_preferences(store_preferences)?;
  let cloud_service = manager.cloud_service()?;
  // Generate the default config if the config is not exist
  let config = get_or_create_cloud_config(session.user_id, &store_preferences);
  data_result_ok(CloudSettingPB {
    enable_sync: config.enable_sync,
    enable_encrypt: config.enable_encrypt,
    encrypt_secret: config.encrypt_secret,
    server_url: cloud_service.service_url(),
  })
}

#[tracing::instrument(level = "debug", skip(manager), err)]
pub async fn get_all_workspace_handler(
  manager: AFPluginState<Weak<UserManager>>,
) -> DataResult<RepeatedUserWorkspacePB, FlowyError> {
  let manager = upgrade_manager(manager)?;
  let session = manager.get_session()?;
  let profile = manager
    .get_user_profile_from_disk(session.user_id, &session.workspace_id)
    .await?;
  let user_workspaces = manager
    .get_all_user_workspaces(profile.uid, profile.auth_type)
    .await?;

  data_result_ok(RepeatedUserWorkspacePB::from(user_workspaces))
}

#[tracing::instrument(level = "info", skip(data, manager), err)]
pub async fn open_workspace_handler(
  data: AFPluginData<OpenUserWorkspacePB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> Result<(), FlowyError> {
  let manager = upgrade_manager(manager)?;
  let params = data.try_into_inner()?;
  let workspace_id = Uuid::from_str(&params.workspace_id)?;
  manager
    .open_workspace(&workspace_id, WorkspaceType::from(params.workspace_type))
    .await?;
  Ok(())
}

#[tracing::instrument(level = "info", skip(data, manager), err)]
pub async fn get_user_workspace_handler(
  data: AFPluginData<UserWorkspaceIdPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> DataResult<UserWorkspacePB, FlowyError> {
  let manager = upgrade_manager(manager)?;
  let params = data.try_into_inner()?;
  let workspace_id = Uuid::from_str(&params.workspace_id)?;
  let uid = manager.user_id()?;
  let user_workspace = manager.get_user_workspace_from_db(uid, &workspace_id)?;
  data_result_ok(UserWorkspacePB::from(user_workspace))
}

#[tracing::instrument(level = "debug", skip(data, manager), err)]
pub async fn update_network_state_handler(
  data: AFPluginData<NetworkStatePB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> Result<(), FlowyError> {
  let manager = upgrade_manager(manager)?;
  let reachable = data.into_inner().ty.is_reachable();
  manager.cloud_service()?.set_network_reachable(reachable);
  manager
    .app_life_cycle
    .read()
    .await
    .on_network_status_changed(reachable);
  Ok(())
}

#[tracing::instrument(level = "debug", skip_all)]
pub async fn get_anon_user_handler(
  manager: AFPluginState<Weak<UserManager>>,
) -> DataResult<UserProfilePB, FlowyError> {
  let manager = upgrade_manager(manager)?;
  let user_profile = manager.get_anon_user().await?;
  data_result_ok(user_profile)
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn open_anon_user_handler(
  manager: AFPluginState<Weak<UserManager>>,
) -> Result<(), FlowyError> {
  let manager = upgrade_manager(manager)?;
  manager.open_anon_user().await?;
  Ok(())
}

pub async fn push_realtime_event_handler(
  payload: AFPluginData<RealtimePayloadPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> Result<(), FlowyError> {
  match serde_json::from_str::<Value>(&payload.into_inner().json_str) {
    Ok(json) => {
      let manager = upgrade_manager(manager)?;
      manager.receive_realtime_event(json).await;
    },
    Err(e) => {
      tracing::error!("Deserialize RealtimePayload failed: {:?}", e);
    },
  }
  Ok(())
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn create_reminder_event_handler(
  data: AFPluginData<ReminderPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> Result<(), FlowyError> {
  let manager = upgrade_manager(manager)?;
  let params = data.into_inner();
  manager.add_reminder(params).await?;
  Ok(())
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn get_all_reminder_event_handler(
  manager: AFPluginState<Weak<UserManager>>,
) -> DataResult<RepeatedReminderPB, FlowyError> {
  let manager = upgrade_manager(manager)?;
  let reminders = manager
    .get_all_reminders()
    .await
    .unwrap_or_default()
    .into_iter()
    .map(ReminderPB::from)
    .collect::<Vec<_>>();

  data_result_ok(reminders.into())
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn remove_reminder_event_handler(
  data: AFPluginData<ReminderIdentifierPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> Result<(), FlowyError> {
  let manager = upgrade_manager(manager)?;

  let params = data.into_inner();
  let _ = manager.remove_reminder(params.id.as_str()).await;

  Ok(())
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn update_reminder_event_handler(
  data: AFPluginData<ReminderPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> Result<(), FlowyError> {
  let manager = upgrade_manager(manager)?;
  let params = data.into_inner();
  manager.update_reminder(params).await?;
  Ok(())
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn delete_workspace_member_handler(
  data: AFPluginData<RemoveWorkspaceMemberPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> Result<(), FlowyError> {
  let data = data.try_into_inner()?;
  let manager = upgrade_manager(manager)?;
  let workspace_id = Uuid::from_str(&data.workspace_id)?;
  manager
    .remove_workspace_member(data.identifier, workspace_id)
    .await?;
  Ok(())
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn get_workspace_members_handler(
  data: AFPluginData<QueryWorkspacePB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> DataResult<RepeatedWorkspaceMemberPB, FlowyError> {
  let data = data.try_into_inner()?;
  let manager = upgrade_manager(manager)?;
  let workspace_id = Uuid::from_str(&data.workspace_id)?;
  let members = manager
    .get_workspace_members(workspace_id)
    .await?
    .into_iter()
    .map(WorkspaceMemberPB::from)
    .collect();
  data_result_ok(RepeatedWorkspaceMemberPB { items: members })
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn get_teams_handler(
  params: AFPluginData<UserWorkspaceIdPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> DataResult<RepeatedTeamPB, FlowyError> {
  let params = params.try_into_inner()?;
  let mgr = upgrade_manager(manager)?;
  let uid = mgr.user_id()?;
  let mut conn = mgr.db_connection(uid)?;
  use diesel::sql_types::{BigInt, Nullable, Text};
  #[derive(QueryableByName)]
  struct TeamRow {
    #[sql_type = "Text"]
    pub team_id: String,
    #[sql_type = "Text"]
    pub workspace_id: String,
    #[sql_type = "Text"]
    pub name: String,
    #[sql_type = "Nullable<Text>"]
    pub description: Option<String>,
    #[sql_type = "Nullable<BigInt>"]
    pub created_at: Option<i64>,
    #[sql_type = "Nullable<BigInt>"]
    pub updated_at: Option<i64>,
  }

  let workspace_id_esc = params.workspace_id.replace('\'', "''");
  let query = format!(
    "SELECT team_id, workspace_id, name, description, created_at, updated_at FROM teams WHERE workspace_id = '{}'",
    workspace_id_esc
  );
  let rows: Vec<TeamRow> = diesel::sql_query(query).load(&mut conn).unwrap_or_default();
  let items = rows
    .into_iter()
    .map(|r| TeamPB {
      team_id: r.team_id,
      workspace_id: r.workspace_id,
      name: r.name,
      description: r.description,
      created_at: r.created_at,
      updated_at: r.updated_at,
    })
    .collect();
  data_result_ok(RepeatedTeamPB { items })
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn get_team_acl_handler(
  params: AFPluginData<TeamIdPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> DataResult<TeamACLPB, FlowyError> {
  let params = params.try_into_inner()?;
  let team_id = params.team_id;

  // Try to read from local sqlite if possible
  let mgr = upgrade_manager(manager)?;
  let uid = mgr.user_id()?;
  let mut conn = mgr.db_connection(uid)?;
  // Query team_acls table
  use diesel::sql_types::{BigInt, Nullable, Text};
  #[derive(QueryableByName)]
  struct TeamAclRow {
    #[sql_type = "Nullable<BigInt>"]
    pub user_id: Option<i64>,
    #[sql_type = "Nullable<Text>"]
    pub email: Option<String>,
  }

  let query = format!("SELECT user_id, email FROM team_acls WHERE team_id = '{}'", team_id.replace('\'', "''"));
  let rows: Vec<TeamAclRow> = diesel::sql_query(query).load(&mut conn).unwrap_or_default();
  let mut allow_user_ids = Vec::new();
  let mut allow_emails = Vec::new();
  for r in rows {
    if let Some(uidv) = r.user_id {
      allow_user_ids.push(uidv);
    }
    if let Some(em) = r.email {
      allow_emails.push(em);
    }
  }
  let acl = TeamACLPB {
    team_id,
    allow_user_ids,
    allow_emails,
  };
  data_result_ok(acl)
}

#[tracing::instrument(level = "debug", skip(data, manager), err)]
pub async fn update_team_acl_handler(
  data: AFPluginData<UpdateTeamACLPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> Result<(), FlowyError> {
  let payload = data.try_into_inner()?;
  let mgr = upgrade_manager(manager)?;
  let uid = mgr.user_id()?;
  let mut conn = mgr.db_connection(uid)?;

  let team_id = payload.acl.team_id.replace('\'', "''");

  // Simple approach: delete existing ACL rows for this team and insert new ones
  let delete_sql = format!("DELETE FROM team_acls WHERE team_id = '{}'", team_id);
  diesel::sql_query(delete_sql).execute(&mut conn)?;

  for user_id in payload.acl.allow_user_ids {
    let insert_sql = format!("INSERT INTO team_acls(team_id, user_id) VALUES ('{}', {})", team_id, user_id);
    diesel::sql_query(insert_sql).execute(&mut conn)?;
  }
  for email in payload.acl.allow_emails {
    let esc = email.replace('\'', "''");
    let insert_sql = format!("INSERT INTO team_acls(team_id, email) VALUES ('{}', '{}')", team_id, esc);
    diesel::sql_query(insert_sql).execute(&mut conn)?;
  }

  Ok(())
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn update_workspace_member_handler(
  data: AFPluginData<UpdateWorkspaceMemberPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> Result<(), FlowyError> {
  let data = data.try_into_inner()?;
  let manager = upgrade_manager(manager)?;
  let workspace_id = Uuid::from_str(&data.workspace_id)?;

  // 优先使用uid，如果uid为0则使用email作为后备
  let user_identifier = if data.uid != 0 {
    data.uid.to_string()
  } else {
    data.email.clone()
  };

  manager
    .update_workspace_member(user_identifier, workspace_id, data.role.into())
    .await?;
  Ok(())
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn create_workspace_handler(
  data: AFPluginData<CreateWorkspacePB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> DataResult<UserWorkspacePB, FlowyError> {
  let data = data.try_into_inner()?;
  let workspace_type = WorkspaceType::from(data.workspace_type);
  let manager = upgrade_manager(manager)?;
  let new_workspace = manager.create_workspace(&data.name, workspace_type).await?;
  data_result_ok(UserWorkspacePB::from(new_workspace))
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn delete_workspace_handler(
  delete_workspace_param: AFPluginData<UserWorkspaceIdPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> Result<(), FlowyError> {
  let workspace_id = delete_workspace_param.try_into_inner()?.workspace_id;
  let manager = upgrade_manager(manager)?;
  let workspace_id = Uuid::from_str(&workspace_id)?;
  manager.delete_workspace(&workspace_id).await?;
  Ok(())
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn rename_workspace_handler(
  rename_workspace_param: AFPluginData<RenameWorkspacePB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> Result<(), FlowyError> {
  let params = rename_workspace_param.try_into_inner()?;
  let manager = upgrade_manager(manager)?;
  let workspace_id = Uuid::from_str(&params.workspace_id)?;
  let changeset = UserWorkspaceChangeset {
    id: params.workspace_id,
    name: Some(params.new_name),
    icon: None,
    role: None,
    member_count: None,
  };
  manager.patch_workspace(&workspace_id, changeset).await?;
  Ok(())
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn change_workspace_icon_handler(
  change_workspace_icon_param: AFPluginData<ChangeWorkspaceIconPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> Result<(), FlowyError> {
  let params = change_workspace_icon_param.try_into_inner()?;
  let manager = upgrade_manager(manager)?;
  let workspace_id = Uuid::from_str(&params.workspace_id)?;
  let changeset = UserWorkspaceChangeset {
    id: workspace_id.to_string(),
    name: None,
    icon: Some(params.new_icon),
    role: None,
    member_count: None,
  };
  manager.patch_workspace(&workspace_id, changeset).await?;
  Ok(())
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn invite_workspace_member_handler(
  param: AFPluginData<WorkspaceMemberInvitationPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> Result<(), FlowyError> {
  let param = param.try_into_inner()?;
  let manager = upgrade_manager(manager)?;
  let workspace_id = Uuid::from_str(&param.workspace_id)?;
  // Server-side permission check: only workspace owner can invite members.
  let uid = manager.user_id()?;
  // get_workspace_member_info expects the requesting local uid and the workspace id
  match manager.get_workspace_member_info(uid, &workspace_id).await {
    Ok(current_member) => {
      use flowy_user_pub::entities::Role;
      if current_member.role != Role::Owner {
        return Err(FlowyError::new(
          ErrorCode::NotEnoughPermissions,
          "仅工作空间所有者可以邀请成员",
        ));
      }
    }
    Err(e) => {
      // If cannot determine membership, log and deny to be safe
      tracing::error!(
        "Failed to get current workspace member info for permission check: {:?}",
        e
      );
      return Err(FlowyError::new(
        ErrorCode::NotEnoughPermissions,
        "无权限邀请成员",
      ));
    }
  }

  manager
    .invite_member_to_workspace(workspace_id, param.invitee_email, param.role.into())
    .await?;
  Ok(())
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn create_join_request_handler(
  data: AFPluginData<CreateJoinRequestPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> DataResult<JoinRequestPB, FlowyError> {
  let payload = data.try_into_inner()?;
  let mgr = upgrade_manager(manager)?;
  let uid = mgr.user_id()?;
  let mut conn = mgr.db_connection(uid)?;

  let workspace_id = payload.workspace_id.replace('\'', "''");
  let space_id = payload.space_id.replace('\'', "''");
  let reason = payload.reason.replace('\'', "''");
  let now = chrono::Utc::now().timestamp();

  let insert_sql = format!("INSERT INTO join_requests(workspace_id, space_id, requester_id, reason, status, created_at, updated_at) VALUES ('{}', '{}', {}, '{}', 'pending', {}, {})", workspace_id, space_id, payload.requester_id, reason, now, now);
  diesel::sql_query(insert_sql).execute(&mut conn)?;

  // select last inserted row
  #[derive(QueryableByName)]
  struct JR {
    #[sql_type = "diesel::sql_types::BigInt"]
    id: i64,
    #[sql_type = "diesel::sql_types::Text"]
    workspace_id: String,
    #[sql_type = "diesel::sql_types::Text"]
    space_id: String,
    #[sql_type = "diesel::sql_types::BigInt"]
    requester_id: i64,
    #[sql_type = "diesel::sql_types::Text"]
    reason: String,
    #[sql_type = "diesel::sql_types::Text"]
    status: String,
    #[sql_type = "diesel::sql_types::BigInt"]
    created_at: i64,
    #[sql_type = "diesel::sql_types::BigInt"]
    updated_at: i64,
  }

  let qr = "SELECT id, workspace_id, space_id, requester_id, reason, status, created_at, updated_at FROM join_requests WHERE rowid = last_insert_rowid()";
  let rows: Vec<JR> = diesel::sql_query(qr).load(&mut conn).unwrap_or_default();
  if let Some(r) = rows.into_iter().next() {
    let pb = JoinRequestPB {
      id: r.id,
      workspace_id: r.workspace_id,
      space_id: r.space_id,
      requester_id: r.requester_id,
      reason: r.reason,
      status: r.status,
      created_at: r.created_at,
      updated_at: r.updated_at,
    };
    data_result_ok(pb)
  } else {
    Err(FlowyError::new(ErrorCode::Internal, "Failed to create join request"))
  }
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn list_join_requests_handler(
  data: AFPluginData<QueryWorkspacePB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> DataResult<RepeatedJoinRequestPB, FlowyError> {
  let params = data.try_into_inner()?;
  let mgr = upgrade_manager(manager)?;
  let uid = mgr.user_id()?;
  let mut conn = mgr.db_connection(uid)?;

  let workspace_id = params.workspace_id.replace('\'', "''");
  let query = format!("SELECT id, workspace_id, space_id, requester_id, reason, status, created_at, updated_at FROM join_requests WHERE workspace_id = '{}'", workspace_id);
  #[derive(QueryableByName)]
  struct JR2 {
    #[sql_type = "diesel::sql_types::BigInt"]
    id: i64,
    #[sql_type = "diesel::sql_types::Text"]
    workspace_id: String,
    #[sql_type = "diesel::sql_types::Text"]
    space_id: String,
    #[sql_type = "diesel::sql_types::BigInt"]
    requester_id: i64,
    #[sql_type = "diesel::sql_types::Text"]
    reason: String,
    #[sql_type = "diesel::sql_types::Text"]
    status: String,
    #[sql_type = "diesel::sql_types::BigInt"]
    created_at: i64,
    #[sql_type = "diesel::sql_types::BigInt"]
    updated_at: i64,
  }
  let rows: Vec<JR2> = diesel::sql_query(query).load(&mut conn).unwrap_or_default();
  let items = rows.into_iter().map(|r| JoinRequestPB {
    id: r.id,
    workspace_id: r.workspace_id,
    space_id: r.space_id,
    requester_id: r.requester_id,
    reason: r.reason,
    status: r.status,
    created_at: r.created_at,
    updated_at: r.updated_at,
  }).collect();
  data_result_ok(RepeatedJoinRequestPB { items })
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn handle_join_request_handler(
  data: AFPluginData<HandleJoinRequestPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> Result<(), FlowyError> {
  let params = data.try_into_inner()?;
  let mgr = upgrade_manager(manager)?;
  let uid = mgr.user_id()?;
  // only workspace owner can approve/reject
  let member = mgr.get_workspace_member_info(uid, &Uuid::from_str(&params.workspace_id)?).await?;
  if member.role != Role::Owner {
    return Err(FlowyError::new(ErrorCode::NotEnoughPermissions, "仅工作空间所有者可以审批加入请求"));
  }

  let mut conn = mgr.db_connection(uid)?;
  let status = if params.approve { "approved" } else { "rejected" };
  let now = chrono::Utc::now().timestamp();
  let update_sql = format!("UPDATE join_requests SET status = '{}', updated_at = {} WHERE id = {}", status, now, params.request_id);
  diesel::sql_query(update_sql).execute(&mut conn)?;

  if params.approve {
    // add member to workspace by requester_id
    // fetch requester email from local profile
    #[derive(QueryableByName)]
    struct RequesterRow {
      #[sql_type = "diesel::sql_types::BigInt"]
      requester_id: i64,
    }

    let query = format!("SELECT requester_id FROM join_requests WHERE id = {}", params.request_id);
    let rows: Vec<RequesterRow> = diesel::sql_query(query).load(&mut conn).unwrap_or_default();
    if let Some(r) = rows.into_iter().next() {
      let rid = r.requester_id;
      if let Ok(profile) = mgr.get_user_profile_from_disk(rid, &params.workspace_id).await {
        let _ = mgr
          .invite_member_to_workspace(Uuid::from_str(&params.workspace_id)?, profile.email, Role::Member)
          .await;
      }
    }
  }

  Ok(())
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn cancel_join_request_handler(
  data: AFPluginData<CancelJoinRequestPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> Result<(), FlowyError> {
  let params = data.try_into_inner()?;
  let mgr = upgrade_manager(manager)?;
  let uid = mgr.user_id()?;
  let mut conn = mgr.db_connection(uid)?;
  // only requester can cancel
  #[derive(QueryableByName)]
  struct RequesterRow2 {
    #[sql_type = "diesel::sql_types::BigInt"]
    requester_id: i64,
  }
  let query = format!("SELECT requester_id FROM join_requests WHERE id = {}", params.request_id);
  let rows: Vec<RequesterRow2> = diesel::sql_query(query).load(&mut conn).unwrap_or_default();
  let row = rows.into_iter().next().map(|r| r.requester_id);
  if row != Some(uid) {
    return Err(FlowyError::new(ErrorCode::NotEnoughPermissions, "只有请求者可以撤销加入请求"));
  }
  let delete_sql = format!("DELETE FROM join_requests WHERE id = {}", params.request_id);
  diesel::sql_query(delete_sql).execute(&mut conn)?;
  Ok(())
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn list_workspace_invitations_handler(
  manager: AFPluginState<Weak<UserManager>>,
) -> DataResult<RepeatedWorkspaceInvitationPB, FlowyError> {
  let manager = upgrade_manager(manager)?;
  let invitations = manager.list_pending_workspace_invitations().await?;
  let invitations_pb: Vec<WorkspaceInvitationPB> = invitations
    .into_iter()
    .map(WorkspaceInvitationPB::from)
    .collect();
  data_result_ok(RepeatedWorkspaceInvitationPB {
    items: invitations_pb,
  })
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn accept_workspace_invitations_handler(
  param: AFPluginData<AcceptWorkspaceInvitationPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> Result<(), FlowyError> {
  let invite_id = param.try_into_inner()?.invite_id;
  let manager = upgrade_manager(manager)?;
  manager.accept_workspace_invitation(invite_id).await?;
  Ok(())
}

pub async fn leave_workspace_handler(
  param: AFPluginData<UserWorkspaceIdPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> Result<(), FlowyError> {
  let workspace_id = param.into_inner().workspace_id;
  let workspace_id = Uuid::from_str(&workspace_id)?;
  let manager = upgrade_manager(manager)?;
  manager.leave_workspace(&workspace_id).await?;
  Ok(())
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn subscribe_workspace_handler(
  params: AFPluginData<SubscribeWorkspacePB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> DataResult<PaymentLinkPB, FlowyError> {
  let params = params.try_into_inner()?;
  let manager = upgrade_manager(manager)?;
  let payment_link = manager.subscribe_workspace(params).await?;
  data_result_ok(PaymentLinkPB { payment_link })
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn get_workspace_subscription_info_handler(
  params: AFPluginData<UserWorkspaceIdPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> DataResult<WorkspaceSubscriptionInfoPB, FlowyError> {
  let params = params.try_into_inner()?;
  let manager = upgrade_manager(manager)?;
  let subs = manager
    .get_workspace_subscription_info(params.workspace_id)
    .await?;
  data_result_ok(subs)
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn cancel_workspace_subscription_handler(
  param: AFPluginData<CancelWorkspaceSubscriptionPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> Result<(), FlowyError> {
  let params = param.into_inner();
  let manager = upgrade_manager(manager)?;
  manager
    .cancel_workspace_subscription(params.workspace_id, params.plan.into(), Some(params.reason))
    .await?;
  Ok(())
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn get_workspace_usage_handler(
  param: AFPluginData<UserWorkspaceIdPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> DataResult<WorkspaceUsagePB, FlowyError> {
  let workspace_id = Uuid::from_str(&param.into_inner().workspace_id)?;
  let manager = upgrade_manager(manager)?;
  let workspace_usage = manager.get_workspace_usage(&workspace_id).await?;
  data_result_ok(WorkspaceUsagePB::from(workspace_usage))
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn get_billing_portal_handler(
  manager: AFPluginState<Weak<UserManager>>,
) -> DataResult<BillingPortalPB, FlowyError> {
  let manager = upgrade_manager(manager)?;
  let url = manager.get_billing_portal_url().await?;
  data_result_ok(BillingPortalPB { url })
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn update_workspace_subscription_payment_period_handler(
  params: AFPluginData<UpdateWorkspaceSubscriptionPaymentPeriodPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> FlowyResult<()> {
  let workspace_id = Uuid::from_str(&params.workspace_id)?;
  let params = params.try_into_inner()?;
  let manager = upgrade_manager(manager)?;
  manager
    .update_workspace_subscription_payment_period(
      &workspace_id,
      params.plan.into(),
      params.recurring_interval.into(),
    )
    .await
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn get_subscription_plan_details_handler(
  manager: AFPluginState<Weak<UserManager>>,
) -> DataResult<RepeatedSubscriptionPlanDetailPB, FlowyError> {
  let manager = upgrade_manager(manager)?;
  let plans = manager
    .get_subscription_plan_details()
    .await?
    .into_iter()
    .map(SubscriptionPlanDetailPB::from)
    .collect::<Vec<_>>();
  data_result_ok(RepeatedSubscriptionPlanDetailPB { items: plans })
}

#[tracing::instrument(level = "debug", skip_all, err)]
pub async fn get_workspace_member_info(
  param: AFPluginData<WorkspaceMemberIdPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> DataResult<WorkspaceMemberPB, FlowyError> {
  let manager = upgrade_manager(manager)?;
  let workspace_id = Uuid::parse_str(&manager.get_session()?.workspace_id)?;
  let member = manager
    .get_workspace_member_info(param.uid, &workspace_id)
    .await?;
  data_result_ok(member.into())
}

#[tracing::instrument(level = "info", skip_all, err)]
pub async fn update_workspace_setting_handler(
  params: AFPluginData<UpdateUserWorkspaceSettingPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> Result<(), FlowyError> {
  let params = params.try_into_inner()?;
  let manager = upgrade_manager(manager)?;
  manager.update_workspace_setting(params).await?;
  Ok(())
}

#[tracing::instrument(level = "info", skip_all, err)]
pub async fn get_workspace_setting_handler(
  params: AFPluginData<UserWorkspaceIdPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> DataResult<WorkspaceSettingsPB, FlowyError> {
  let params = params.try_into_inner()?;
  let workspace_id = Uuid::from_str(&params.workspace_id)?;
  let manager = upgrade_manager(manager)?;
  let pb = manager.get_workspace_settings(&workspace_id).await?;
  data_result_ok(pb)
}

#[tracing::instrument(level = "info", skip_all, err)]
pub async fn notify_did_switch_plan_handler(
  params: AFPluginData<SuccessWorkspaceSubscriptionPB>,
  manager: AFPluginState<Weak<UserManager>>,
) -> Result<(), FlowyError> {
  let success = params.into_inner();
  let manager = upgrade_manager(manager)?;
  manager.notify_did_switch_plan(success).await?;
  Ok(())
}

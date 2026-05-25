use lib_infra::util::OperatingSystem;
use lib_log::stream_log::StreamLogSender;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use crate::AppFlowyCoreConfig;

static INIT_LOG: AtomicBool = AtomicBool::new(false);
pub(crate) fn init_log(
  config: &AppFlowyCoreConfig,
  platform: &OperatingSystem,
  stream_log_sender: Option<Arc<dyn StreamLogSender>>,
) {
  #[cfg(debug_assertions)]
  if get_bool_from_env_var("DISABLE_CI_TEST_LOG") {
    return;
  }

  if !INIT_LOG.load(Ordering::SeqCst) {
    INIT_LOG.store(true, Ordering::SeqCst);

    if let Err(e) = lib_log::Builder::new("log", &config.storage_path, platform, stream_log_sender)
      .env_filter(&config.log_filter)
      .build()
    {
      eprintln!("[log_filter] 日志系统初始化失败: {}", e);
    }
  }
}

pub fn create_log_filter(
  level: String,
  with_crates: Vec<String>,
  platform: OperatingSystem,
) -> String {
  let mut level = std::env::var("RUST_LOG").unwrap_or(level);

  #[cfg(debug_assertions)]
  if matches!(platform, OperatingSystem::IOS) {
    level = "trace".to_string();
  }

  let mut filters = with_crates
    .into_iter()
    .map(|crate_name| format!("{}={}", crate_name, level))
    .collect::<Vec<String>>();
  // PonyNotes: 只保留白板相关模块的详细日志，其他模块只记录警告以上级别
  // 修改：开启云同步调试时需要 info 级别日志
  filters.push(format!("flowy_core={}", "info"));
  filters.push(format!("flowy_folder={}", "warn"));
  filters.push(format!("collab_sync={}", "info"));  // 改为 info 以显示同步状态
  filters.push(format!("collab_folder={}", "warn"));
  filters.push(format!("collab_database={}", "warn"));
  filters.push(format!("collab_plugins={}", level)); // 白板相关，保留详细日志
  filters.push(format!("collab_integrate={}", "warn"));
  filters.push(format!("collab={}", "warn"));
  filters.push(format!("flowy_user={}", "warn"));
  filters.push(format!("flowy_document={}", "warn"));
  filters.push(format!("flowy_database2={}", "warn"));
  filters.push(format!("flowy_server={}", "info"));  // 改为 info 以显示云同步日志
  filters.push(format!("flowy_notification={}", "warn"));
  filters.push(format!("lib_infra={}", "warn"));
  filters.push(format!("flowy_search={}", "warn"));
  filters.push(format!("flowy_chat={}", "warn"));
  filters.push(format!("af_local_ai={}", "warn"));
  filters.push(format!("af_plugin={}", "warn"));
  filters.push(format!("flowy_ai={}", "warn"));
  filters.push(format!("flowy_ai_pub={}", "warn"));
  filters.push(format!("flowy_storage={}", "warn"));
  filters.push(format!("flowy_sqlite_vec={}", "warn"));
  // Enable the frontend logs. DO NOT DISABLE.
  // These logs are essential for debugging and verifying frontend behavior.
  filters.push(format!("dart_ffi={}", level));

  // Most of the time, we don't need to see the logs from the following crates
  // filters.push(format!("flowy_sqlite={}", "info"));
  // filters.push(format!("lib_dispatch={}", level));

  filters.push(format!("client_api={}", level));
  filters.push(format!("infra={}", level));
  #[cfg(feature = "profiling")]
  filters.push(format!("tokio={}", level));
  #[cfg(feature = "profiling")]
  filters.push(format!("runtime={}", level));

  filters.join(",")
}

#[cfg(debug_assertions)]
fn get_bool_from_env_var(env_var_name: &str) -> bool {
  match std::env::var(env_var_name) {
    Ok(value) => match value.to_lowercase().as_str() {
      "true" | "1" => true,
      "false" | "0" => false,
      _ => false,
    },
    Err(_) => false,
  }
}

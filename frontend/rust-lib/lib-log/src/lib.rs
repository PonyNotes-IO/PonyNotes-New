use std::fs;
use std::io;
use std::io::Write;
use std::sync::Arc;

use crate::layer::FlowyFormattingLayer;
use crate::stream_log::{StreamLog, StreamLogSender};
use chrono::Local;
use lib_infra::util::OperatingSystem;
use tracing::subscriber::set_global_default;
use tracing_appender::rolling::Rotation;
use tracing_appender::rolling::RollingFileAppender;
use tracing_bunyan_formatter::JsonStorageLayer;
use tracing_subscriber::fmt::format::Writer;
use tracing_subscriber::fmt::MakeWriter;
use tracing_subscriber::{layer::SubscriberExt, EnvFilter};

mod layer;
pub mod stream_log;

pub struct Builder {
  #[allow(dead_code)]
  name: String,
  env_filter: String,
  app_log_appender: RollingFileAppender,
  sync_log_appender: RollingFileAppender,
  #[allow(dead_code)]
  platform: OperatingSystem,
  stream_log_sender: Option<Arc<dyn StreamLogSender>>,
}

const SYNC_TARGET: &str = "sync_trace_log";

impl Builder {
  pub fn new(
    name: &str,
    directory: &str,
    platform: &OperatingSystem,
    stream_log_sender: Option<Arc<dyn StreamLogSender>>,
  ) -> Self {
    // 确保日志目录存在，避免 RollingFileAppender 因目录不存在而失败
    if let Err(e) = fs::create_dir_all(directory) {
      eprintln!("[lib-log] 创建日志目录失败 '{}': {}", directory, e);
    }

    let app_log_appender = RollingFileAppender::builder()
      .rotation(Rotation::DAILY)
      .filename_prefix(name)
      .max_log_files(6)
      .build(directory)
      .unwrap_or_else(|e| {
        eprintln!("[lib-log] RollingFileAppender 构建失败 '{}': {}", directory, e);
        tracing_appender::rolling::daily(directory, name)
      });

    let sync_log_name = "log.sync";
    let sync_log_appender = RollingFileAppender::builder()
      .rotation(Rotation::HOURLY)
      .filename_prefix(sync_log_name)
      .max_log_files(24)
      .build(directory)
      .unwrap_or_else(|e| {
        eprintln!("[lib-log] sync RollingFileAppender 构建失败 '{}': {}", directory, e);
        tracing_appender::rolling::hourly(directory, sync_log_name)
      });

    Builder {
      name: name.to_owned(),
      env_filter: "info".to_owned(),
      app_log_appender,
      sync_log_appender,
      platform: platform.clone(),
      stream_log_sender,
    }
  }

  pub fn env_filter(mut self, env_filter: &str) -> Self {
    env_filter.clone_into(&mut self.env_filter);
    self
  }

  pub fn build(self) -> Result<(), String> {
    let env_filter = EnvFilter::new(self.env_filter);

    // 直接使用 RollingFileAppender 同步写入，避免 non_blocking 后台线程在进程退出时
    // 因 WorkerGuard 未 drop（存于 lazy_static）而导致缓冲日志丢失
    let app_file_layer = FlowyFormattingLayer::new(self.app_log_appender)
      .with_target_filter(|target| target != SYNC_TARGET);

    let collab_sync_file_layer = FlowyFormattingLayer::new(self.sync_log_appender)
      .with_target_filter(|target| target == SYNC_TARGET);

    if let Some(stream_log_sender) = &self.stream_log_sender {
      let subscriber = tracing_subscriber::fmt()
        .with_timer(CustomTime)
        .with_max_level(tracing::Level::TRACE)
        .with_ansi(self.platform.is_desktop())
        .with_writer(StreamLog {
          sender: stream_log_sender.clone(),
        })
        .with_thread_ids(false)
        .pretty()
        .with_env_filter(env_filter)
        .finish()
        .with(JsonStorageLayer)
        .with(app_file_layer)
        .with(collab_sync_file_layer);
      set_global_default(subscriber).map_err(|e| format!("{:?}", e))?;
    } else {
      let subscriber = tracing_subscriber::fmt()
        .with_timer(CustomTime)
        .with_max_level(tracing::Level::TRACE)
        .with_ansi(true)
        .with_thread_ids(false)
        .pretty()
        .with_env_filter(env_filter)
        .finish()
        .with(FlowyFormattingLayer::new(DebugStdoutWriter))
        .with(JsonStorageLayer)
        .with(app_file_layer)
        .with(collab_sync_file_layer);
      set_global_default(subscriber).map_err(|e| format!("{:?}", e))?;
    };

    Ok(())
  }
}

struct CustomTime;
impl tracing_subscriber::fmt::time::FormatTime for CustomTime {
  fn format_time(&self, w: &mut Writer<'_>) -> std::fmt::Result {
    write!(w, "{}", Local::now().format("%Y-%m-%d %H:%M:%S"))
  }
}

pub struct DebugStdoutWriter;

impl<'a> MakeWriter<'a> for DebugStdoutWriter {
  type Writer = Box<dyn Write>;

  fn make_writer(&'a self) -> Self::Writer {
    if std::env::var("DISABLE_EVENT_LOG").unwrap_or("false".to_string()) == "true" {
      Box::new(io::sink())
    } else {
      Box::new(io::stdout())
    }
  }
}

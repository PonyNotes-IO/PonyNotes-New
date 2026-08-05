use crate::sqlite_sql::UploadFileTable;
use crate::uploader::UploadTask::BackgroundTask;
use flowy_storage_pub::storage::StorageService;
use lib_infra::box_any::BoxAny;
use std::cmp::Ordering;
use std::collections::BinaryHeap;
use std::fmt::Display;
use std::sync::atomic::{AtomicBool, AtomicU8};
use std::sync::{Arc, Weak};
use std::time::Duration;
use tokio::sync::{watch, RwLock};
use tracing::{error, info, instrument, trace, warn};

#[derive(Clone)]
pub enum Signal {
  Stop,
  Proceed,
  ProceedAfterSecs(u64),
}

pub struct UploadTaskQueue {
  tasks: RwLock<BinaryHeap<UploadTask>>,
  notifier: watch::Sender<Signal>,
}

impl UploadTaskQueue {
  pub fn new(notifier: watch::Sender<Signal>) -> Self {
    Self {
      tasks: Default::default(),
      notifier,
    }
  }
  pub async fn queue_task(&self, task: UploadTask) {
    trace!("[File] Queued task: {}", task);
    self.tasks.write().await.push(task);
    let _ = self.notifier.send_replace(Signal::Proceed);
  }

  pub async fn remove_task(&self, workspace_id: &str, parent_dir: &str, file_id: &str) {
    let mut tasks = self.tasks.write().await;

    tasks.retain(|task| match task {
      UploadTask::BackgroundTask {
        workspace_id: w_id,
        parent_dir: p_dir,
        file_id: f_id,
        ..
      } => !(w_id == workspace_id && p_dir == parent_dir && f_id == file_id),
      UploadTask::Task { record, .. } => {
        !(record.workspace_id == workspace_id
          && record.parent_dir == parent_dir
          && record.file_id == file_id)
      },
    });
  }
}

pub struct FileUploader {
  storage_service: Arc<dyn StorageService>,
  queue: Arc<UploadTaskQueue>,
  max_uploads: u8,
  current_uploads: AtomicU8,
  pause_sync: AtomicBool,
  disable_upload: Arc<AtomicBool>,
}

impl Drop for FileUploader {
  fn drop(&mut self) {
    let _ = self.queue.notifier.send(Signal::Stop);
  }
}

impl FileUploader {
  pub fn new(
    storage_service: Arc<dyn StorageService>,
    queue: Arc<UploadTaskQueue>,
    is_exceed_limit: Arc<AtomicBool>,
  ) -> Self {
    Self {
      storage_service,
      queue,
      max_uploads: 1,
      current_uploads: Default::default(),
      pause_sync: Default::default(),
      disable_upload: is_exceed_limit,
    }
  }

  pub async fn all_tasks(&self) -> Vec<UploadTask> {
    let tasks = self.queue.tasks.read().await;
    tasks.iter().cloned().collect()
  }

  pub async fn queue_tasks(&self, tasks: Vec<UploadTask>) {
    let mut queue_lock = self.queue.tasks.write().await;
    for task in tasks {
      queue_lock.push(task);
    }
    let _ = self.queue.notifier.send(Signal::Proceed);
  }

  pub fn pause(&self) {
    self
      .pause_sync
      .store(true, std::sync::atomic::Ordering::SeqCst);
  }

  pub fn disable_storage_write(&self) {
    self
      .disable_upload
      .store(true, std::sync::atomic::Ordering::SeqCst);
    self.pause();
  }

  pub fn enable_storage_write(&self) {
    self
      .disable_upload
      .store(false, std::sync::atomic::Ordering::SeqCst);
    self.resume();
  }

  pub fn resume(&self) {
    self
      .pause_sync
      .store(false, std::sync::atomic::Ordering::SeqCst);
    trace!("[File] Uploader resumed");
    let _ = self.queue.notifier.send(Signal::ProceedAfterSecs(3));
  }

  #[instrument(name = "[File]: process next", level = "debug", skip(self))]
  pub async fn process_next(&self) -> Option<()> {
    // Do not proceed if the uploader is paused.
    if self.pause_sync.load(std::sync::atomic::Ordering::Relaxed) {
      // If disable_upload was reset to false (by a new explicit upload attempt in
      // create_upload), auto-resume so the queued task can be processed.
      // pause_sync and disable_upload are always set together by disable_storage_write(),
      // so if disable_upload is now false, it is safe to clear the pause too.
      if !self
        .disable_upload
        .load(std::sync::atomic::Ordering::SeqCst)
      {
        info!("[File] Storage limit was reset by new upload attempt, auto-resuming uploader");
        self
          .pause_sync
          .store(false, std::sync::atomic::Ordering::SeqCst);
      } else {
        info!("[File] Uploader is paused");
        return None;
      }
    }

    let current_uploads = self
      .current_uploads
      .load(std::sync::atomic::Ordering::SeqCst);
    if current_uploads > 0 {
      trace!("[File] current upload tasks: {}", current_uploads)
    }

    if self
      .current_uploads
      .load(std::sync::atomic::Ordering::SeqCst)
      >= self.max_uploads
    {
      // If the current uploads count is greater than or equal to the max uploads, do not proceed.
      let _ = self.queue.notifier.send(Signal::ProceedAfterSecs(10));
      trace!("[File] max uploads reached, process_next after 10 seconds");
      return None;
    }

    if self
      .disable_upload
      .load(std::sync::atomic::Ordering::SeqCst)
    {
      // If the storage limitation is enabled, do not proceed.
      error!("[File] storage limit exceeded, uploader is disabled");
      return None;
    }

    let task = self.queue.tasks.write().await.pop()?;
    if task.retry_count() > 5 {
      // If the task has been retried more than 5 times, we should not retry it anymore.
      let _ = self.queue.notifier.send(Signal::ProceedAfterSecs(2));
      warn!("[File] Task has been retried more than 5 times: {}", task);
      return None;
    }

    // increment the current uploads count
    self
      .current_uploads
      .fetch_add(1, std::sync::atomic::Ordering::SeqCst);

    // 【离线上传支持 2026-07-19】标记本轮是否因断网失败，用于决定退避时长。
    let mut offline_backoff = false;

    match task {
      UploadTask::Task {
        local_file_path,
        record,
        mut retry_count,
      } => {
        let record = BoxAny::new(record);
        if let Err(err) = self.storage_service.start_upload(&record).await {
          if err.is_file_limit_exceeded() && !err.is_single_file_limit_exceeded() {
            error!("[File] Storage limit exceeded for task, skipping (won't retry)");
          }

          if err.should_retry_upload() {
            // 【离线上传支持 2026-07-19】断网导致的失败**不消耗重试次数**。
            //
            // 原实现对所有可重试错误一律 retry_count += 1，而上限为 5
            // （见本函数开头的 `task.retry_count() > 5` 判断，超限即丢弃任务）。
            // 用户断网期间这 5 次会被迅速耗尽，任务被移出内存队列，
            // 于是**联网后也再不会续传**——文件虽仍在本地与 SQLite 中，却永远传不上云端。
            // 这与"断网可正常插入、联网后自动同步"的需求直接冲突。
            //
            // 故：网络不可用属于外部条件而非任务本身的问题，保持原计数重新入队即可；
            // 真正的业务性失败仍照常累加、受上限保护，避免死循环重试。
            let is_offline = err.is_network_unavailable();
            if is_offline {
              info!(
                "[File] Network unavailable, requeue without consuming retry budget: {}",
                err
              );
              // 断网期间放慢重试节奏：默认每轮仅退避 2 秒，若不加长会变成
              // 约 30 次/分钟的无谓网络尝试（断网可能持续数小时）。
              // 这里改为 30 秒；联网恢复时 update_network_reachable → uploader.resume()
              // 会立即发 Signal::Proceed 唤醒，不会因为退避而延迟续传。
              offline_backoff = true;
            } else {
              info!(
                "[File] Failed to upload file: {}, retry_count:{}",
                err, retry_count
              );
              retry_count += 1;
            }
            let record = record.unbox_or_error().unwrap();
            self.queue.tasks.write().await.push(UploadTask::Task {
              local_file_path,
              record,
              retry_count,
            });
          }
        }
      },
      UploadTask::BackgroundTask {
        workspace_id,
        parent_dir,
        file_id,
        created_at,
        mut retry_count,
      } => {
        if let Err(err) = self
          .storage_service
          .resume_upload(&workspace_id, &parent_dir, &file_id)
          .await
        {
          if err.is_file_limit_exceeded() && !err.is_single_file_limit_exceeded() {
            error!("[File] Storage limit exceeded during resume, skipping (won't retry)");
          }

          if err.should_retry_upload() {
            if err.is_network_unavailable() {
              info!(
                "[File] Network unavailable, requeue resumed upload without consuming retry budget: {}",
                err
              );
              offline_backoff = true;
            } else {
              info!(
                "[File] failed to resume upload file: {}, retry_count:{}",
                err, retry_count
              );
              retry_count += 1;
            }
            self.queue.tasks.write().await.push(BackgroundTask {
              workspace_id,
              parent_dir,
              file_id,
              created_at,
              retry_count,
            });
          }
        }
      },
    }

    self
      .current_uploads
      .fetch_sub(1, std::sync::atomic::Ordering::SeqCst);
    // 断网时用更长退避，避免无谓的高频网络尝试；联网恢复由 resume() 立即唤醒。
    let backoff_secs = if offline_backoff { 30 } else { 2 };
    trace!("[File] process_next after {} seconds", backoff_secs);
    self
      .queue
      .notifier
      .send_replace(Signal::ProceedAfterSecs(backoff_secs));
    None
  }
}

pub struct FileUploaderRunner;

impl FileUploaderRunner {
  pub async fn run(weak_uploader: Weak<FileUploader>, mut notifier: watch::Receiver<Signal>) {
    // Start uploading after 20 seconds
    tokio::time::sleep(Duration::from_secs(20)).await;

    loop {
      // stops the runner if the notifier was closed.
      if notifier.changed().await.is_err() {
        info!("[File]:Uploader runner stopped, notifier closed");
        break;
      }

      if let Some(uploader) = weak_uploader.upgrade() {
        let value = notifier.borrow().clone();
        trace!(
          "[File]: Uploader runner received signal, thread_id: {:?}",
          std::thread::current().id()
        );
        match value {
          Signal::Stop => {
            info!("[File]:Uploader runner stopped, stop signal received");
            break;
          },
          Signal::Proceed => {
            tokio::spawn(async move {
              uploader.process_next().await;
            });
          },
          Signal::ProceedAfterSecs(secs) => {
            tokio::time::sleep(Duration::from_secs(secs)).await;
            tokio::spawn(async move {
              uploader.process_next().await;
            });
          },
        }
      } else {
        info!("[File]:Uploader runner stopped, uploader dropped");
        break;
      }
    }
  }
}

#[derive(Clone)]
pub enum UploadTask {
  Task {
    local_file_path: String,
    record: UploadFileTable,
    retry_count: u8,
  },
  BackgroundTask {
    workspace_id: String,
    file_id: String,
    parent_dir: String,
    created_at: i64,
    retry_count: u8,
  },
}

impl UploadTask {
  pub fn retry_count(&self) -> u8 {
    match self {
      UploadTask::Task { retry_count, .. } => *retry_count,
      UploadTask::BackgroundTask { retry_count, .. } => *retry_count,
    }
  }
}

impl Display for UploadTask {
  fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
    match self {
      UploadTask::Task { record, .. } => write!(f, "Task: {}", record.file_id),
      UploadTask::BackgroundTask { file_id, .. } => write!(f, "BackgroundTask: {}", file_id),
    }
  }
}

impl Eq for UploadTask {}

impl PartialEq for UploadTask {
  fn eq(&self, other: &Self) -> bool {
    match (self, other) {
      (Self::Task { record: lhs, .. }, Self::Task { record: rhs, .. }) => {
        lhs.local_file_path == rhs.local_file_path
      },
      (
        Self::BackgroundTask {
          workspace_id: l_workspace_id,
          file_id: l_file_id,
          ..
        },
        Self::BackgroundTask {
          workspace_id: r_workspace_id,
          file_id: r_file_id,
          ..
        },
      ) => l_workspace_id == r_workspace_id && l_file_id == r_file_id,
      _ => false,
    }
  }
}

impl PartialOrd for UploadTask {
  fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
    Some(self.cmp(other))
  }
}

impl Ord for UploadTask {
  fn cmp(&self, other: &Self) -> Ordering {
    match (self, other) {
      (Self::Task { record: lhs, .. }, Self::Task { record: rhs, .. }) => {
        lhs.created_at.cmp(&rhs.created_at)
      },
      (_, Self::Task { .. }) => Ordering::Less,
      (Self::Task { .. }, _) => Ordering::Greater,
      (
        Self::BackgroundTask {
          created_at: lhs, ..
        },
        Self::BackgroundTask {
          created_at: rhs, ..
        },
      ) => lhs.cmp(rhs),
    }
  }
}

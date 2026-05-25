use std::{sync::Arc, time::Duration};

use diesel::{connection::Connection, r2d2::R2D2Connection, SqliteConnection};
use r2d2::{CustomizeConnection, ManageConnection, Pool};
use scheduled_thread_pool::ScheduledThreadPool;

use crate::sqlite_impl::{errors::*, pragma::*};

pub struct ConnectionPool {
  pub(crate) inner: Pool<ConnectionManager>,
}

impl std::ops::Deref for ConnectionPool {
  type Target = Pool<ConnectionManager>;

  fn deref(&self) -> &Self::Target {
    &self.inner
  }
}

impl ConnectionPool {
  pub fn new<T>(config: PoolConfig, uri: T) -> Result<Self>
  where
    T: Into<String>,
  {
    let manager = ConnectionManager::new(uri);
    let thread_pool = Arc::new(
      ScheduledThreadPool::builder()
        .num_threads(4)
        .thread_name_pattern("db-pool-{}:")
        .build(),
    );
    let config = Arc::new(config);
    let customizer_config = DatabaseCustomizerConfig::default();

    let pool = r2d2::Pool::builder()
      .thread_pool(thread_pool)
      .min_idle(Some(config.min_idle))
      .connection_customizer(Box::new(DatabaseCustomizer::new(customizer_config)))
      .max_size(config.max_size)
      .max_lifetime(None)
      .connection_timeout(config.connection_timeout)
      .idle_timeout(Some(config.idle_timeout))
      .build_unchecked(manager);
    Ok(ConnectionPool { inner: pool })
  }
}

#[allow(dead_code)]
pub type OnExecFunc = Box<dyn Fn() -> Box<dyn Fn(&SqliteConnection, &str)> + Send + Sync>;

pub struct PoolConfig {
  min_idle: u32,
  max_size: u32,
  connection_timeout: Duration,
  idle_timeout: Duration,
}

impl Default for PoolConfig {
  fn default() -> Self {
    Self {
      min_idle: 1,
      max_size: 10,
      connection_timeout: Duration::from_secs(10),
      idle_timeout: Duration::from_secs(5 * 60),
    }
  }
}

impl PoolConfig {
  #[allow(dead_code)]
  pub fn min_idle(mut self, min_idle: u32) -> Self {
    self.min_idle = min_idle;
    self
  }

  #[allow(dead_code)]
  pub fn max_size(mut self, max_size: u32) -> Self {
    self.max_size = max_size;
    self
  }
}

pub struct ConnectionManager {
  db_uri: String,
}

impl ManageConnection for ConnectionManager {
  type Connection = SqliteConnection;
  type Error = crate::sqlite_impl::Error;

  fn connect(&self) -> Result<Self::Connection> {
    Ok(SqliteConnection::establish(&self.db_uri)?)
  }

  fn is_valid(&self, conn: &mut Self::Connection) -> Result<()> {
    Ok(conn.ping()?)
  }

  fn has_broken(&self, _conn: &mut Self::Connection) -> bool {
    false
  }
}

impl ConnectionManager {
  pub fn new<S: Into<String>>(uri: S) -> Self {
    ConnectionManager { db_uri: uri.into() }
  }
}

#[derive(Debug)]
pub struct DatabaseCustomizerConfig {
  pub(crate) journal_mode: SQLiteJournalMode,
  pub(crate) synchronous: SQLiteSynchronous,
  pub(crate) busy_timeout: i32,
  #[allow(dead_code)]
  pub(crate) secure_delete: bool,
}

impl Default for DatabaseCustomizerConfig {
  fn default() -> Self {
    Self {
      journal_mode: SQLiteJournalMode::WAL,
      synchronous: SQLiteSynchronous::NORMAL,
      // 默认 5s 的 busy_timeout 在用户首次登录时执行大量迁移/初始化操作时
      // 非常容易触发 "database is locked"。用户清理本地数据或服务器数据后，
      // 同步流程会在短时间内并发读写同一个 SQLite，导致写锁持续时间远超 5s。
      // 将超时时间提升到 60s，可以让 SQLite 在高并发初始化阶段自动等待，
      // 避免直接把锁冲突暴露给上层登录流程（从而出现“出现错误，请稍后再试”）。
      busy_timeout: 60_000,
      secure_delete: true,
    }
  }
}

#[derive(Debug)]
struct DatabaseCustomizer {
  config: DatabaseCustomizerConfig,
}

impl DatabaseCustomizer {
  fn new(config: DatabaseCustomizerConfig) -> Self
  where
    Self: Sized,
  {
    Self { config }
  }
}

impl CustomizeConnection<SqliteConnection, crate::sqlite_impl::Error> for DatabaseCustomizer {
  fn on_acquire(&self, conn: &mut SqliteConnection) -> Result<()> {
    conn.pragma_set_busy_timeout(self.config.busy_timeout)?;
    if self.config.journal_mode != SQLiteJournalMode::WAL {
      conn.pragma_set_journal_mode(self.config.journal_mode, None)?;
    }
    conn.pragma_set_synchronous(self.config.synchronous, None)?;

    Ok(())
  }
}

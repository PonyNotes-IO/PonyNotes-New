//! 统一错误类型。
//!
//! 索引层的错误**不应该**向上冒泡成「文档保存失败」——索引是派生数据，
//! 它坏了不该影响正文。因此这里把错误建模成可记录、可忽略的形态，
//! 由调用方决定是重试、跳过还是记日志。

use thiserror::Error;

#[derive(Debug, Error)]
pub enum LinkError {
  #[error("sqlite error: {0}")]
  Sqlite(#[from] flowy_sqlite::Error),

  /// 从连接池取连接失败。与 `Sqlite` 分开，是因为它不是 SQL 语句的问题，
  /// 重试通常有效；调用方可以据此决定「稍后再试」而不是「这页数据坏了」。
  #[error("failed to acquire database connection")]
  ConnectionUnavailable,

  #[error("failed to parse link delta: {0}")]
  Delta(#[from] serde_json::Error),

  /// 数据库里存了当前代码不认识的 `kind`。
  ///
  /// 单条脏数据不应导致整次查询失败，所以这个错误只用于显式转换场景；
  /// 列表查询遇到它会跳过该行并打警告。
  #[error("unknown link kind stored in database: {0}")]
  UnknownLinkKind(String),
}

pub type LinkResult<T> = Result<T, LinkError>;

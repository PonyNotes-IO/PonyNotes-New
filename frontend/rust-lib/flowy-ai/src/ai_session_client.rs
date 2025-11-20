use flowy_error::{ErrorCode, FlowyError};
use futures_util::{Stream, StreamExt, TryStreamExt};
use pin_project::pin_project;
use serde_json::Value;
use std::pin::Pin;
use std::task::{Context, Poll};
use tracing::{error, trace};

const STREAM_ANSWER_KEY: &str = "1";
const STREAM_METADATA_KEY: &str = "0";

#[pin_project]
pub struct AISessionStream {
  #[pin]
  stream: Pin<Box<dyn Stream<Item = Result<Value, FlowyError>> + Send>>,
}

impl AISessionStream {
  pub fn new<S>(stream: S) -> Self
  where
    S: Stream<Item = Result<Value, FlowyError>> + Send + 'static,
  {
    AISessionStream {
      stream: Box::pin(stream),
    }
  }
}

#[derive(Debug, Clone)]
pub enum AISessionStreamValue {
  Answer { value: String },
  Metadata { value: Value },
}

impl Stream for AISessionStream {
  type Item = Result<AISessionStreamValue, FlowyError>;

  fn poll_next(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
    let mut this = self.as_mut().project();

    match futures_util::ready!(this.stream.as_mut().poll_next(cx)) {
      Some(Ok(value)) => match value {
        Value::Object(mut value) => {
          // 检查是否有元数据 (key = "0")
          if let Some(metadata) = value.remove(STREAM_METADATA_KEY) {
            trace!("[AISession] 收到元数据: {:?}", metadata);
            return Poll::Ready(Some(Ok(AISessionStreamValue::Metadata { value: metadata })));
          }

          // 检查是否有答案内容 (key = "1")
          if let Some(answer) = value
            .remove(STREAM_ANSWER_KEY)
            .and_then(|s| s.as_str().map(ToString::to_string))
          {
            trace!("[AISession] 收到答案片段: {}", answer);
            return Poll::Ready(Some(Ok(AISessionStreamValue::Answer { value: answer })));
          }

          // 无效的流值
          error!("[AISession] 收到无效的流值: {:?}", value);
          Poll::Ready(Some(Err(
            FlowyError::new(
              ErrorCode::InvalidParams,
              format!("无效的流值: {:?}", value),
            )
          )))
        },
        _ => {
          error!("[AISession] 收到意外的JSON类型: {:?}", value);
          Poll::Ready(Some(Err(
            FlowyError::new(
              ErrorCode::InvalidParams,
              format!("意外的JSON类型: {:?}", value),
            )
          )))
        },
      },
      Some(Err(err)) => {
        error!("[AISession] 流错误: {:?}", err);
        Poll::Ready(Some(Err(err)))
      },
      None => {
        trace!("[AISession] 流结束");
        Poll::Ready(None)
      },
    }
  }
}

/// 调用新的 AI 会话接口
pub async fn stream_ai_session(
  base_url: &str,
  message: &str,
  preferred_model: Option<String>,
) -> Result<AISessionStream, FlowyError> {
  use reqwest::Client;
  use std::time::Duration;

  let url = format!("{}/api/ai/chat/session", base_url);
  trace!("[AISession] 调用新接口: {}, model: {:?}", url, preferred_model);

  let client = Client::new();
  let mut body = serde_json::json!({
    "message": message,
  });

  if let Some(model) = preferred_model {
    body["preferred_model"] = serde_json::Value::String(model);
  }

  let resp = client
    .post(&url)
    .timeout(Duration::from_secs(60))
    .json(&body)
    .send()
    .await
    .map_err(|e| {
      error!("[AISession] 请求失败: {}", e);
      FlowyError::new(ErrorCode::Internal, format!("HTTP请求失败: {}", e))
    })?;

  if !resp.status().is_success() {
    let status = resp.status();
    let error_text = resp.text().await.unwrap_or_else(|_| "无法读取错误信息".to_string());
    error!("[AISession] 服务器返回错误: {} - {}", status, error_text);
    return Err(FlowyError::new(
      ErrorCode::Internal,
      format!("服务器返回错误: {} - {}", status, error_text),
    ));
  }

  // 解析 SSE 流
  use futures_util::stream::StreamExt as _;
  let stream = futures_util::stream::unfold(resp, |mut resp| async move {
    match resp.chunk().await {
      Ok(Some(bytes)) => {
        let result: Result<Value, FlowyError> = (|| {
          let text = String::from_utf8_lossy(&bytes);
          trace!("[AISession] 收到原始数据: {}", text);
          
          // 解析每一行
          for line in text.lines() {
            let line = line.trim();
            if line.is_empty() {
              continue;
            }
            
            // 解析 JSON
            match serde_json::from_str::<Value>(line) {
              Ok(json) => return Ok(json),
              Err(e) => {
                error!("[AISession] JSON解析失败: {} - 原始数据: {}", e, line);
                continue;
              }
            }
          }
          
          // 如果没有有效的JSON，返回一个空对象
          Ok(Value::Object(serde_json::Map::new()))
        })();
        Some((result, resp))
      },
      Ok(None) => None,
      Err(e) => {
        error!("[AISession] 读取流失败: {}", e);
        let err = FlowyError::new(ErrorCode::Internal, format!("读取流失败: {}", e));
        Some((Err(err), resp))
      }
    }
  });

  Ok(AISessionStream::new(stream))
}


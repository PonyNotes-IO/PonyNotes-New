use flowy_error::{ErrorCode, FlowyError};
use futures_util::{Stream, StreamExt, TryStreamExt};
use pin_project::pin_project;
use serde_json::Value;
use std::pin::Pin;
use std::task::{Context, Poll};
use tracing::{error, info, trace};

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
  token: Option<String>,
  enable_thinking: bool,
) -> Result<AISessionStream, FlowyError> {
  use reqwest::Client;
  use std::time::Duration;

  let url = format!("{}/api/ai/chat/session", base_url);
  trace!("[AISession] 调用新接口: {}, model: {:?}, enable_thinking: {}", url, preferred_model, enable_thinking);

  let client = Client::new();
  let mut body = serde_json::json!({
    "message": message,
  });

  if let Some(model) = preferred_model {
    body["preferred_model"] = serde_json::Value::String(model);
  }
  
  if enable_thinking {
    body["enable_thinking"] = serde_json::Value::Bool(true);
  }

  let mut request = client
    .post(&url)
    .timeout(Duration::from_secs(60))
    .json(&body);
  
  // 添加 Authorization header（如果提供了 token）
  if let Some(token) = token {
    let token_preview = if token.len() > 20 {
      format!("{}...", &token[..20])
    } else {
      token.clone()
    };
    request = request.header("Authorization", format!("Bearer {}", token));
    trace!("[AISession] 添加 Authorization header，token 预览: {}", token_preview);
  } else {
    error!("[AISession] 未提供 token，请求可能失败");
  }

  let resp = request
    .send()
    .await
    .map_err(|e| {
      error!("[AISession] 请求失败: {}", e);
      FlowyError::new(ErrorCode::Internal, format!("HTTP请求失败: {}", e))
    })?;

  if !resp.status().is_success() {
    let status = resp.status();
    let error_text =
      resp.text().await.unwrap_or_else(|_| "无法读取错误信息".to_string());
    error!("[AISession] 服务器返回错误: {} - {}", status, error_text);

    // 解析后端返回的 JSON 错误结构（如果可能）
    let parsed_json = serde_json::from_str::<serde_json::Value>(&error_text).ok();
    let code_str = parsed_json
      .as_ref()
      .and_then(|v| v.get("code"))
      .and_then(|v| v.as_str());
    let message_str = parsed_json
      .as_ref()
      .and_then(|v| v.get("message"))
      .and_then(|v| v.as_str());

    // 处理 402 Payment Required 错误（AI 使用次数用尽）
    if status == 402 && code_str == Some("AI_LIMIT_EXCEEDED") {
      let message = message_str
        .unwrap_or("AI调用次数已用完，请升级订阅或购买补充包")
        .to_string();
      info!("[AISession] AI使用次数用尽: {}", message);
      return Err(FlowyError::new(
        ErrorCode::AIResponseLimitExceeded,
        message,
      ));
    }

    // 处理 404 Not Found 错误（未找到订阅计划）
    if status == 404 && code_str == Some("SUBSCRIPTION_NOT_FOUND") {
      // 这里直接把后端返回的 message 透传给前端，在对话中显示给用户
      let message = message_str
        .unwrap_or("抱歉，您还未开启订阅计划，AI暂时不可用。")
        .to_string();
      info!("[AISession] 订阅计划不存在: {}", message);
      // 使用非 Internal 的错误码，确保前端能够显示这条消息
      return Err(FlowyError::new(
        ErrorCode::LimitedByWorkspacePlan,
        message,
      ));
    }

    return Err(FlowyError::new(
      ErrorCode::Internal,
      format!("服务器返回错误: {} - {}", status, error_text),
    ));
  }

  // 解析 SSE 流 - 使用缓冲区处理跨chunk的JSON行
  use futures_util::stream::StreamExt as _;
  
  struct StreamState {
    resp: reqwest::Response,
    buffer: String,
    pending_jsons: Vec<Value>,
  }
  
  let initial_state = StreamState {
    resp,
    buffer: String::new(),
    pending_jsons: Vec::new(),
  };
  
  let stream = futures_util::stream::unfold(initial_state, |mut state| async move {
    // 如果有待处理的JSON，先返回它们
    if let Some(json) = state.pending_jsons.pop() {
      return Some((Ok(json), state));
    }
    
    loop {
      match state.resp.chunk().await {
        Ok(Some(bytes)) => {
          let text = String::from_utf8_lossy(&bytes);
          trace!("[AISession] 收到原始数据: {}", text);
          
          // 将新数据追加到缓冲区
          state.buffer.push_str(&text);
          
          // 尝试从缓冲区提取完整的JSON行
          let mut results = Vec::new();
          let mut lines: Vec<&str> = state.buffer.lines().collect();
          let mut last_incomplete_line = String::new();
          
          // 检查最后一行是否完整（有换行符结尾）
          if !state.buffer.ends_with('\n') && !lines.is_empty() {
            // 最后一行可能不完整，保留到下次
            if let Some(last_line) = lines.pop() {
              last_incomplete_line = last_line.to_string();
            }
          }
          
          // 解析所有完整的行
          for line in lines {
            let line = line.trim();
            if line.is_empty() {
              continue;
            }
            
            trace!("[AISession] 处理行: [{}] (长度: {})", line, line.len());
            
            // 处理SSE格式：检查是否是 "data: " 开头
            // 使用 strip_prefix 更安全，避免索引越界
            let json_str = if let Some(rest) = line.strip_prefix("data: ") {
              rest.trim() // 去掉 "data: " 前缀并去除前后空格
            } else {
              line.trim()
            };
            
            trace!("[AISession] 提取的JSON字符串: [{}] (长度: {})", json_str, json_str.len());
            
            // 处理 [DONE] 标记（流结束标记）
            if json_str == "[DONE]" {
              trace!("[AISession] 收到流结束标记 [DONE]");
              continue; // 跳过，流会在后续自然结束
            }
            
            // 如果去掉前缀后为空，跳过
            if json_str.is_empty() {
              trace!("[AISession] 跳过空行");
              continue;
            }
            
            // 解析 JSON
            match serde_json::from_str::<Value>(json_str) {
              Ok(mut json) => {
                trace!("[AISession] 成功解析JSON: {:?}", json);
                
                // 从OpenAI兼容格式转换为内部格式
                // OpenAI格式: {"choices":[{"delta":{"content":"text"}}]}
                // 豆包格式: {"choices":[{"delta":{"content":"","reasoning_content":"text"}}]}
                // 内部格式: {"1": "text"} 或 {"0": metadata, "1": "text"}
                if let Value::Object(ref mut obj) = json {
                  if let Some(choices) = obj.get("choices").and_then(|c| c.as_array()) {
                    if let Some(first_choice) = choices.first() {
                      // 检查是否是流结束标记（finish_reason为stop）
                      if let Some(finish_reason) = first_choice.get("finish_reason").and_then(|f| f.as_str()) {
                        if finish_reason == "stop" {
                          trace!("[AISession] 收到流结束标记 (finish_reason=stop)，跳过");
                          continue; // 跳过这个chunk，不添加到results
                        }
                      }
                      
                      if let Some(delta) = first_choice.get("delta").and_then(|d| d.as_object()) {
                        // 优先使用 content，如果没有或为空则使用 reasoning_content（豆包模型的思考过程）
                        let content = delta.get("content")
                          .and_then(|c| c.as_str())
                          .filter(|s| !s.is_empty())
                          .or_else(|| {
                            delta.get("reasoning_content")
                              .and_then(|c| c.as_str())
                              .filter(|s| !s.is_empty())
                          });
                        
                        if let Some(content_text) = content {
                          // 转换为内部格式
                          let mut internal_obj = serde_json::Map::new();
                          internal_obj.insert(STREAM_ANSWER_KEY.to_string(), Value::String(content_text.to_string()));
                          
                          // 如果有metadata，也提取
                          if let Some(metadata) = obj.get("metadata") {
                            internal_obj.insert(STREAM_METADATA_KEY.to_string(), metadata.clone());
                          }
                          
                          json = Value::Object(internal_obj);
                          trace!("[AISession] 转换为内部格式: {:?}", json);
                        } else {
                          trace!("[AISession] delta中没有找到content或reasoning_content，跳过");
                          continue; // 跳过这个chunk，不添加到results
                        }
                      }
                    }
                  }
                }
                
                results.push(json);
              }
              Err(e) => {
                error!("[AISession] JSON解析失败: {} - 原始行: [{}] - 提取的JSON字符串: [{}]", e, line, json_str);
                // 尝试调试：打印前几个字符的ASCII码
                let first_chars: String = json_str.chars().take(20).map(|c| {
                  if c.is_control() {
                    format!("\\x{:02x}", c as u8)
                  } else {
                    c.to_string()
                  }
                }).collect();
                error!("[AISession] JSON字符串前20个字符: {}", first_chars);
              }
            }
          }
          
          // 更新缓冲区为未完成的行
          state.buffer = last_incomplete_line;
          
          // 如果有成功解析的JSON，保存到pending并返回第一个
          if !results.is_empty() {
            // 反转顺序，因为pop是从后面取
            results.reverse();
            let first = results.pop().unwrap();
            state.pending_jsons = results;
            return Some((Ok(first), state));
          }
          
          // 没有成功解析的JSON，继续读取下一个chunk
          continue;
        },
        Ok(None) => {
          // 流结束，检查缓冲区是否还有数据
          if !state.buffer.is_empty() {
            let line = state.buffer.trim();
            if !line.is_empty() {
              trace!("[AISession] 流结束，尝试解析剩余数据: {}", line);
              
              // 处理SSE格式
              let json_str = if line.starts_with("data: ") {
                &line[6..]
              } else {
                line
              };
              
              // 跳过 [DONE] 标记
              if json_str.trim() != "[DONE]" {
                match serde_json::from_str::<Value>(json_str) {
                  Ok(mut json) => {
                    // 转换为内部格式（与上面相同的逻辑）
                    if let Value::Object(ref mut obj) = json {
                      if let Some(choices) = obj.get("choices").and_then(|c| c.as_array()) {
                        if let Some(first_choice) = choices.first() {
                          // 检查是否是流结束标记（finish_reason为stop）
                          if let Some(finish_reason) = first_choice.get("finish_reason").and_then(|f| f.as_str()) {
                            if finish_reason == "stop" {
                              trace!("[AISession] 流结束时收到finish_reason=stop标记，正常结束");
                              state.buffer.clear();
                              return None; // 正常结束流
                            }
                          }
                          
                          if let Some(delta) = first_choice.get("delta").and_then(|d| d.as_object()) {
                            if let Some(content) = delta.get("content").and_then(|c| c.as_str()).filter(|s| !s.is_empty()) {
                              let mut internal_obj = serde_json::Map::new();
                              internal_obj.insert(STREAM_ANSWER_KEY.to_string(), Value::String(content.to_string()));
                              if let Some(metadata) = obj.get("metadata") {
                                internal_obj.insert(STREAM_METADATA_KEY.to_string(), metadata.clone());
                              }
                              json = Value::Object(internal_obj);
                              state.buffer.clear();
                              return Some((Ok(json), state));
                            }
                          }
                        }
                      }
                    }
                    // 如果没有有效内容，直接结束流
                    trace!("[AISession] 流结束时没有找到有效内容，正常结束");
                    state.buffer.clear();
                    return None;
                  }
                  Err(e) => {
                    error!("[AISession] 流结束时JSON解析失败: {} - 原始数据: {}", e, json_str);
                  }
                }
              }
            }
          }
          trace!("[AISession] 流结束");
          return None;
        },
        Err(e) => {
          error!("[AISession] 读取流失败: {}", e);
          let err = FlowyError::new(ErrorCode::Internal, format!("读取流失败: {}", e));
          return Some((Err(err), state));
        }
      }
    }
  });

  Ok(AISessionStream::new(stream))
}



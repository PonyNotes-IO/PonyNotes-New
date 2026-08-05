use serde::Serialize;
use std::fmt::Display;

#[allow(dead_code)]
pub enum StreamMessage {
  MessageId(i64),
  IndexStart,
  IndexEnd,
  OnData(String),
  OnThinking(String),
  OnFollowUp(AIFollowUpData),
  OnError(String),
  Metadata(String),
  Done,
  StartIndexFile { file_name: String },
  EndIndexFile { file_name: String },
  IndexFileError { file_name: String },
  AIResponseLimitExceeded,
  AIImageResponseLimitExceeded,
  AIMaxRequired(String),
  LocalAINotReady(String),
  LocalAIDisabled(String),
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct AIFollowUpData {
  pub should_generate_related_question: bool,
}

impl Display for StreamMessage {
  fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
    match self {
      StreamMessage::MessageId(message_id) => write!(f, "message_id:{}", message_id),
      StreamMessage::IndexStart => write!(f, "index_start:"),
      StreamMessage::IndexEnd => write!(f, "index_end"),
      StreamMessage::OnData(message) => write!(f, "data:{message}"),
      StreamMessage::OnThinking(message) => write!(f, "thinking:{message}"),
      StreamMessage::OnError(message) => write!(f, "error:{message}"),
      StreamMessage::Done => write!(f, "done:"),
      StreamMessage::Metadata(s) => write!(f, "metadata:{s}"),
      StreamMessage::StartIndexFile { file_name } => {
        write!(f, "start_index_file:{}", file_name)
      },
      StreamMessage::EndIndexFile { file_name } => {
        write!(f, "end_index_file:{}", file_name)
      },
      StreamMessage::IndexFileError { file_name } => {
        write!(f, "index_file_error:{}", file_name)
      },
      StreamMessage::OnFollowUp(data) => {
        if let Ok(s) = serde_json::to_string(&data) {
          write!(f, "ai_follow_up:{}", s)
        } else {
          write!(f, "ai_follow_up:",)
        }
      },
      StreamMessage::AIResponseLimitExceeded => write!(f, "ai_response_limit:"),
      StreamMessage::AIImageResponseLimitExceeded => {
        write!(f, "ai_image_response_limit:")
      },
      StreamMessage::AIMaxRequired(message) => write!(f, "ai_max_required:{}", message),
      StreamMessage::LocalAINotReady(message) => {
        write!(f, "local_ai_not_ready:{}", message)
      },
      StreamMessage::LocalAIDisabled(message) => {
        write!(f, "local_ai_disabled:{}", message)
      },
    }
  }
}

/// 统一清洗 AI 错误消息，避免将上游服务商、状态码、请求 ID 或 HTML 错误页展示给用户。
pub(crate) fn sanitize_ai_error_message(raw: &str) -> String {
  let trimmed = raw.trim();
  if trimmed.is_empty() {
    return "AI 服务暂时不可用，请稍后重试。".to_string();
  }

  let lower = trimmed.to_lowercase();
  let padded = format!(" {lower} ");
  let has_status = |code: &str| {
    padded.contains(&format!(" {code} "))
      || padded.contains(&format!(" {code}-"))
      || padded.contains(&format!(" {code}:"))
  };

  if has_status("429")
    || lower.contains("too many requests")
    || lower.contains("serveroverloaded")
    || lower.contains("rate limit")
  {
    return "请求过于频繁，请稍后重试。".to_string();
  }

  if has_status("408")
    || has_status("504")
    || lower.contains("timed out")
    || lower.contains("timeout")
    || lower.contains("gateway timeout")
  {
    return "请求超时，请稍后重试。".to_string();
  }

  if lower.contains("connection refused")
    || lower.contains("connection reset")
    || lower.contains("connection failed")
    || lower.contains("failed to connect")
    || lower.contains("network error")
    || lower.contains("dns error")
  {
    return "网络连接异常，请检查网络后重试。".to_string();
  }

  let status_message = if has_status("400") || has_status("422") {
    Some("请求内容无法处理，请调整后重试。")
  } else if has_status("401") {
    Some("AI 服务认证异常，请联系管理员。")
  } else if has_status("403") {
    Some("AI 服务访问异常，请联系管理员。")
  } else if has_status("404") {
    Some("AI 服务或模型不可用，请联系管理员。")
  } else if has_status("409") {
    Some("请求冲突，请稍后重试。")
  } else if has_status("413") {
    Some("发送内容过大，请减少文字或附件后重试。")
  } else if has_status("500") {
    Some("AI 服务内部异常，请稍后重试。")
  } else if has_status("502") || has_status("503") {
    Some("AI 服务暂时不可用，请稍后重试。")
  } else {
    None
  };
  if let Some(message) = status_message {
    return message.to_string();
  }

  let contains_html = lower.contains("<html")
    || lower.contains("<!doctype")
    || lower.contains("<title>")
    || (trimmed.len() > 500 && (trimmed.contains('<') || trimmed.contains('>')));
  let contains_technical_details = lower.contains("api error")
    || lower.contains("service error")
    || lower.contains("provider failure")
    || lower.contains("request id")
    || lower.contains("request_id")
    || lower.contains("internal server error");
  if contains_html || contains_technical_details {
    return "AI 服务暂时不可用，请稍后重试。".to_string();
  }

  trimmed.to_string()
}

#[cfg(test)]
mod tests {
  use super::sanitize_ai_error_message;

  #[test]
  fn sanitizes_common_http_errors_for_display() {
    let cases = [
      ("400 Bad Request", "请求内容无法处理，请调整后重试。"),
      ("401 Unauthorized", "AI 服务认证异常，请联系管理员。"),
      ("403 Forbidden", "AI 服务访问异常，请联系管理员。"),
      ("404 Not Found", "AI 服务或模型不可用，请联系管理员。"),
      ("408 Request Timeout", "请求超时，请稍后重试。"),
      ("409 Conflict", "请求冲突，请稍后重试。"),
      (
        "413 Payload Too Large",
        "发送内容过大，请减少文字或附件后重试。",
      ),
      (
        "422 Unprocessable Entity",
        "请求内容无法处理，请调整后重试。",
      ),
      (
        "Doubao web search API error: 429 Too Many Requests - {\"error\":{\"code\":\"ServerOverloaded\",\"message\":\"service overloaded\",\"request_id\":\"secret-request-id\"}}",
        "请求过于频繁，请稍后重试。",
      ),
      ("500 Internal Server Error", "AI 服务内部异常，请稍后重试。"),
      ("502 Bad Gateway", "AI 服务暂时不可用，请稍后重试。"),
      ("503 Service Unavailable", "AI 服务暂时不可用，请稍后重试。"),
      ("504 Gateway Timeout", "请求超时，请稍后重试。"),
    ];

    for (raw, expected) in cases {
      assert_eq!(sanitize_ai_error_message(raw), expected, "raw: {raw}");
    }
  }

  #[test]
  fn sanitizes_network_and_unsafe_unknown_errors() {
    assert_eq!(
      sanitize_ai_error_message("connection refused while sending request"),
      "网络连接异常，请检查网络后重试。",
    );
    assert_eq!(
      sanitize_ai_error_message("request timed out while waiting for response"),
      "请求超时，请稍后重试。",
    );
    assert_eq!(
      sanitize_ai_error_message("<html><body>upstream exploded</body></html>"),
      "AI 服务暂时不可用，请稍后重试。",
    );
    assert_eq!(
      sanitize_ai_error_message("provider failure request id: private-id"),
      "AI 服务暂时不可用，请稍后重试。",
    );
  }
}

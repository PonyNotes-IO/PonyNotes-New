use flowy_notification::entities::SubscribeObject;
use flowy_notification::send_subject;

const WHITEBOARD_OBSERVABLE_SOURCE: &str = "Whiteboard";

#[derive(Debug, Default, Clone)]
pub enum WhiteboardNotification {
  #[default]
  Unknown = 0,

  /// 当白板数据（Map）发生变更时发送
  DidReceiveUpdate = 41,
}

impl std::convert::From<WhiteboardNotification> for i32 {
  fn from(notification: WhiteboardNotification) -> Self {
    notification as i32
  }
}

impl std::convert::From<i32> for WhiteboardNotification {
  fn from(notification: i32) -> Self {
    match notification {
      41 => WhiteboardNotification::DidReceiveUpdate,
      _ => WhiteboardNotification::Unknown,
    }
  }
}

/// 发送原始 JSON 字节的变更通知
pub(crate) fn whiteboard_notification_send_json(
  view_id: String,
  ty: WhiteboardNotification,
  json_str: String,
) {
  let subject = SubscribeObject {
    source: WHITEBOARD_OBSERVABLE_SOURCE.to_owned(),
    ty: ty as i32,
    id: view_id,
    payload: Some(json_str.into_bytes()),
    error: None,
  };
  send_subject(subject);
}

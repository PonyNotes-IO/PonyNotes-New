use flowy_derive::ProtoBuf;

// ===== Protobuf 消息类型 =====

/// 创建手写笔记的请求参数
#[derive(Default, ProtoBuf)]
pub struct CreateHandwritingSaberPayloadPB {
  #[pb(index = 1)]
  pub view_id: String,

  #[pb(index = 2, one_of)]
  pub initial_data: Option<Vec<u8>>,
}

/// 保存手写笔记的请求参数
#[derive(Default, ProtoBuf)]
pub struct SaveHandwritingSaberPayloadPB {
  #[pb(index = 1)]
  pub view_id: String,

  #[pb(index = 2)]
  pub sbn2_bytes: Vec<u8>,

  #[pb(index = 3)]
  pub version: i64,

  #[pb(index = 4, one_of)]
  pub preview_png: Option<Vec<u8>>,
}

/// 手写笔记数据响应
#[derive(Default, ProtoBuf)]
pub struct HandwritingSaberDataPB {
  #[pb(index = 1)]
  pub view_id: String,

  #[pb(index = 2)]
  pub sbn2_bytes: Vec<u8>,

  #[pb(index = 3)]
  pub version: i64,

  #[pb(index = 4, one_of)]
  pub preview_png: Option<Vec<u8>>,

  #[pb(index = 5)]
  pub updated_at: i64,

  #[pb(index = 6)]
  pub updated_by: String,
}

/// 保存手写笔记的响应
#[derive(Default, ProtoBuf)]
pub struct SaveHandwritingSaberResponsePB {
  #[pb(index = 1)]
  pub new_version: i64,
}


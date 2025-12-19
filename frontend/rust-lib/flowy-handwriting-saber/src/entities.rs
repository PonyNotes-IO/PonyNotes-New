// ===== 手写笔记数据结构（当前阶段：仅在 Rust 内部使用） =====

/// 创建手写笔记的请求参数
///
/// 说明：
/// - 目前仅在 Rust 内部使用，用于描述需要传递的字段结构；
/// - 后续如果要通过 `flowy_derive::ProtoBuf` 生成 Protobuf / FFI 代码，
///   再补充相应的宏和属性标注即可。
#[derive(Default)]
pub struct CreateHandwritingSaberPayloadPB {
  pub view_id: String,
  pub initial_data: Option<Vec<u8>>,
}

/// 保存手写笔记的请求参数
#[derive(Default)]
pub struct SaveHandwritingSaberPayloadPB {
  pub view_id: String,
  pub sbn2_bytes: Vec<u8>,
  pub version: i64,
  pub preview_png: Option<Vec<u8>>,
}

/// 手写笔记数据响应
#[derive(Default)]
pub struct HandwritingSaberDataPB {
  pub view_id: String,
  pub sbn2_bytes: Vec<u8>,
  pub version: i64,
  pub preview_png: Option<Vec<u8>>,
  pub updated_at: i64,
  pub updated_by: String,
}

/// 保存手写笔记的响应
#[derive(Default)]
pub struct SaveHandwritingSaberResponsePB {
  pub new_version: i64,
}


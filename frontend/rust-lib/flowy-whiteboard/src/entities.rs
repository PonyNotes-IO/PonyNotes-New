use flowy_derive::ProtoBuf;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Excalidraw 白板数据
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct WhiteboardData {
  #[serde(default)]
  pub elements: Vec<ExcalidrawElement>,
  #[serde(default, rename = "appState")]
  pub app_state: AppState,
  #[serde(default)]
  pub files: HashMap<String, FileData>,
}

/// Excalidraw 元素（简化版，只包含核心字段）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExcalidrawElement {
  pub id: String,
  #[serde(rename = "type")]
  pub type_: String,
  #[serde(default)]
  pub x: f64,
  #[serde(default)]
  pub y: f64,
  #[serde(default)]
  pub width: f64,
  #[serde(default)]
  pub height: f64,
  #[serde(default, rename = "strokeColor")]
  pub stroke_color: String,
  #[serde(default, rename = "backgroundColor")]
  pub background_color: String,
  #[serde(default, rename = "fillStyle")]
  pub fill_style: String,
  #[serde(default, rename = "strokeWidth")]
  pub stroke_width: f64,
  #[serde(default)]
  pub roughness: f64,
  #[serde(default)]
  pub opacity: f64,
  #[serde(default)]
  pub angle: f64,
  #[serde(default)]
  pub locked: bool,
  #[serde(default)]
  pub seed: i64,
  #[serde(default, rename = "versionNonce")]
  pub version_nonce: i64,
  #[serde(default, rename = "isDeleted")]
  pub is_deleted: bool,
  // 使用 serde_json::Value 来存储剩余的动态字段
  #[serde(flatten)]
  pub extra: serde_json::Value,
}

/// 应用状态
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct AppState {
  #[serde(rename = "gridSize")]
  pub grid_size: Option<i32>,
  #[serde(default, rename = "viewBackgroundColor")]
  pub view_background_color: String,
  #[serde(default, rename = "scrollX")]
  pub scroll_x: f64,
  #[serde(default, rename = "scrollY")]
  pub scroll_y: f64,
  #[serde(default)]
  pub zoom: ZoomState,
  // 使用 serde_json::Value 来存储剩余的动态字段
  #[serde(flatten)]
  pub extra: serde_json::Value,
}

/// 缩放状态
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ZoomState {
  #[serde(default = "default_zoom_value")]
  pub value: f64,
}

fn default_zoom_value() -> f64 {
  1.0
}

impl Default for ZoomState {
  fn default() -> Self {
    Self { value: 1.0 }
  }
}

/// 文件数据
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileData {
  #[serde(rename = "mimeType")]
  pub mime_type: String,
  pub id: String,
  #[serde(rename = "dataURL")]
  pub data_url: String,
  #[serde(default)]
  pub created: i64,
}

impl WhiteboardData {
  /// 创建空白板
  pub fn empty() -> Self {
    Self {
      elements: vec![],
      app_state: AppState::default(),
      files: HashMap::new(),
    }
  }

  /// 从 JSON 字符串解析
  pub fn from_json(json: &str) -> Result<Self, serde_json::Error> {
    serde_json::from_str(json)
  }

  /// 转换为 JSON 字符串
  pub fn to_json(&self) -> Result<String, serde_json::Error> {
    serde_json::to_string(self)
  }

  /// 转换为格式化的 JSON 字符串
  pub fn to_json_pretty(&self) -> Result<String, serde_json::Error> {
    serde_json::to_string_pretty(self)
  }

  /// 转换为完整的 Excalidraw JSON 格式
  pub fn to_excalidraw_json(&self) -> Result<String, serde_json::Error> {
    let json = serde_json::json!({
      "type": "excalidraw",
      "version": 2,
      "source": "https://excalidraw.com",
      "elements": self.elements,
      "appState": self.app_state,
      "files": self.files,
    });
    serde_json::to_string(&json)
  }
}

// ===== Protobuf 消息类型 =====

/// 创建白板的请求参数
#[derive(Default, ProtoBuf)]
pub struct CreateWhiteboardPayloadPB {
  #[pb(index = 1)]
  pub view_id: String,
  
  #[pb(index = 2, one_of)]
  pub initial_data: Option<String>,
}

/// 更新白板的请求参数
#[derive(Default, ProtoBuf)]
pub struct UpdateWhiteboardPayloadPB {
  #[pb(index = 1)]
  pub view_id: String,
  
  #[pb(index = 2)]
  pub json_data: String,
}

/// 视图 ID 参数
#[derive(Default, ProtoBuf)]
pub struct ViewIdPB {
  #[pb(index = 1)]
  pub value: String,
}

/// 白板数据响应
#[derive(Default, ProtoBuf)]
pub struct WhiteboardDataPB {
  #[pb(index = 1)]
  pub view_id: String,
  
  #[pb(index = 2)]
  pub json_data: String,
}

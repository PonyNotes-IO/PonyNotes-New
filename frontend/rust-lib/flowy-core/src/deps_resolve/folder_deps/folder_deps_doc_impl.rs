use crate::deps_resolve::folder_deps::get_encoded_collab_v1_from_disk;
use bytes::Bytes;
use collab::entity::EncodedCollab;
use collab_entity::CollabType;
use collab_folder::hierarchy_builder::NestedViewBuilder;
use collab_folder::ViewLayout;
use flowy_document::entities::{ChildrenPB, DocumentDataPB};
use flowy_document::manager::DocumentManager;
use flowy_document::parser::json::parser::JsonToDocumentParser;
use flowy_error::FlowyError;
use flowy_folder::entities::{CreateViewParams, ViewLayoutPB};
use flowy_folder::manager::FolderUser;
use flowy_folder::share::ImportType;
use flowy_folder::view_operation::{
  FolderOperationHandler, GatherEncodedCollab, ImportedData, ViewData,
};
use flowy_search_pub::tantivy_state_init::get_document_tantivy_state;
use flowy_storage::manager::StorageManager;
use lib_dispatch::prelude::ToBytes;
use lib_infra::async_trait::async_trait;
use std::collections::HashMap;
use std::convert::TryFrom;
use std::str::FromStr;
use std::sync::{Arc, Weak};
use tokio::sync::RwLock;
use uuid::Uuid;

pub struct DocumentFolderOperation {
  pub document_manager: Weak<DocumentManager>,
  pub storage_manager: Weak<StorageManager>,
}

fn is_document_backed_layout(layout: &ViewLayoutPB) -> bool {
  match layout {
    ViewLayoutPB::Document => true,
    #[cfg(target_os = "windows")]
    ViewLayoutPB::Folder | ViewLayoutPB::Notebook => true,
    _ => false,
  }
}

/// 复制或导入文档时，文档数据里保留着源页面的 page_id 与全部块 ID。
/// 原样写入会让两份文档共用同一批标识符，按块 ID 做缓存、提醒或索引时
/// 会互相串。这里为副本重建全部块 ID：根块使用新页面 ID，其余块生成
/// 新 ID，并同步修正 parent_id、children_id 与 children_map。
fn remap_document_ids(mut data: DocumentDataPB, new_page_id: &str) -> DocumentDataPB {
  let old_page_id = data.page_id.clone();
  if old_page_id.is_empty() || old_page_id == new_page_id {
    return data;
  }
  data.page_id = new_page_id.to_string();

  let old_root_id = data
    .blocks
    .keys()
    .find(|id| **id == old_page_id)
    .cloned()
    .unwrap_or_else(|| old_page_id.clone());

  let mut id_map = HashMap::with_capacity(data.blocks.len());
  for id in data.blocks.keys() {
    let new_id = if *id == old_root_id {
      new_page_id.to_string()
    } else {
      Uuid::new_v4().simple().to_string()
    };
    id_map.insert(id.clone(), new_id);
  }

  let mut blocks = HashMap::with_capacity(data.blocks.len());
  for (old_id, mut block) in data.blocks {
    let new_id = id_map
      .get(&old_id)
      .cloned()
      .unwrap_or_else(|| old_id.clone());

    if !block.parent_id.is_empty() {
      block.parent_id = id_map
        .get(&block.parent_id)
        .cloned()
        .unwrap_or(block.parent_id);
    }
    if !block.children_id.is_empty() {
      block.children_id = id_map
        .get(&block.children_id)
        .cloned()
        .unwrap_or(block.children_id);
    }
    block.id = new_id.clone();
    blocks.insert(new_id, block);
  }
  data.blocks = blocks;

  let mut children_map = HashMap::with_capacity(data.meta.children_map.len());
  for (old_id, children) in data.meta.children_map {
    let new_id = id_map
      .get(&old_id)
      .cloned()
      .unwrap_or_else(|| old_id.clone());
    let children = ChildrenPB {
      children: children
        .children
        .into_iter()
        .map(|child| id_map.get(&child).cloned().unwrap_or(child))
        .collect(),
    };
    children_map.insert(new_id, children);
  }
  data.meta.children_map = children_map;

  // text_map 的键是文本的 external_id，不是块 ID；块 ID 变化不影响它。
  data
}

impl DocumentFolderOperation {
  fn document_manager(&self) -> Result<Arc<DocumentManager>, FlowyError> {
    self
      .document_manager
      .upgrade()
      .ok_or_else(FlowyError::ref_drop)
  }
}
#[async_trait]
impl FolderOperationHandler for DocumentFolderOperation {
  fn name(&self) -> &str {
    "DocumentFolderOperationHandler"
  }

  async fn create_workspace_view(
    &self,
    uid: i64,
    workspace_view_builder: Arc<RwLock<NestedViewBuilder>>,
  ) -> Result<(), FlowyError> {
    let manager = self.document_manager()?;

    let mut write_guard = workspace_view_builder.write().await;
    // Create a view named "Getting started" with an icon ⭐️ and the built-in README data.
    // Don't modify this code unless you know what you are doing.
    write_guard
      .with_view_builder(|view_builder| async {
        let view = view_builder
          .with_name("Getting started")
          .with_icon("⭐️")
          .build();
        // create a empty document
        let json_str = include_str!("../../../assets/read_me.json");
        let document_pb = JsonToDocumentParser::json_str_to_document(json_str).unwrap();
        let view_id = Uuid::from_str(&view.view.id).unwrap();
        manager
          .create_document(uid, &view_id, Some(document_pb.into()))
          .await
          .unwrap();
        view
      })
      .await;
    Ok(())
  }

  async fn open_view(&self, view_id: &Uuid) -> Result<(), FlowyError> {
    self
      .document_manager()?
      .open_document(view_id, None)
      .await?;
    Ok(())
  }

  /// Close the document view.
  async fn close_view(&self, view_id: &Uuid) -> Result<(), FlowyError> {
    self.document_manager()?.close_document(view_id).await?;
    Ok(())
  }

  async fn delete_view(&self, view_id: &Uuid) -> Result<(), FlowyError> {
    let document_manager = self.document_manager()?;
    let workspace_id = document_manager.user_service.workspace_id()?;
    if let Some(state) = get_document_tantivy_state(&workspace_id).and_then(|v| v.upgrade()) {
      let _ = state.write().await.delete_document(&view_id.to_string());
    }

    if let Some(storage) = self.storage_manager.upgrade() {
      let parent_dir = view_id.to_string();
      if let Err(err) = storage.delete_all_files_for_view(&parent_dir).await {
        tracing::error!("🔴cleanup files for document {} failed: {}", view_id, err);
      }
    }

    match document_manager.delete_document(view_id).await {
      Ok(_) => tracing::trace!("Delete document: {}", view_id),
      Err(e) => tracing::error!("🔴delete document failed: {}", e),
    }
    Ok(())
  }

  async fn duplicate_view(&self, view_id: &Uuid) -> Result<Bytes, FlowyError> {
    let data: DocumentDataPB = self
      .document_manager()?
      .get_document_data(view_id)
      .await?
      .into();
    let data_bytes = data.into_bytes().map_err(|_| FlowyError::invalid_data())?;
    Ok(data_bytes)
  }

  async fn gather_publish_encode_collab(
    &self,
    user: &Arc<dyn FolderUser>,
    view_id: &Uuid,
  ) -> Result<GatherEncodedCollab, FlowyError> {
    let encoded_collab =
      get_encoded_collab_v1_from_disk(user, view_id.to_string().as_str(), CollabType::Document)
        .await?;
    Ok(GatherEncodedCollab::Document(encoded_collab))
  }

  async fn create_view_with_view_data(
    &self,
    user_id: i64,
    params: CreateViewParams,
  ) -> Result<Option<EncodedCollab>, FlowyError> {
    debug_assert!(
      is_document_backed_layout(&params.layout),
      "DocumentFolderOperationHandler received unsupported layout: {:?}",
      params.layout
    );
    let new_view_id = params.view_id.to_string();
    let data = match params.initial_data {
      ViewData::DuplicateData(data) => Some(remap_document_ids(
        DocumentDataPB::try_from(data)?,
        &new_view_id,
      )),
      ViewData::Data(data) => Some(remap_document_ids(
        DocumentDataPB::try_from(data)?,
        &new_view_id,
      )),
      ViewData::Empty => None,
    };
    let encoded_collab = self
      .document_manager()?
      .create_document(user_id, &params.view_id, data.map(|d| d.into()))
      .await?;
    Ok(Some(encoded_collab))
  }

  /// Create a view with built-in data.
  async fn create_default_view(
    &self,
    user_id: i64,
    _parent_view_id: &Uuid,
    view_id: &Uuid,
    _name: &str,
    layout: ViewLayout,
  ) -> Result<(), FlowyError> {
    debug_assert_eq!(layout, ViewLayout::Document);
    match self
      .document_manager()?
      .create_document(user_id, view_id, None)
      .await
    {
      Ok(_) => Ok(()),
      Err(err) => {
        if err.is_already_exists() {
          Ok(())
        } else {
          Err(err)
        }
      },
    }
  }

  async fn import_from_bytes(
    &self,
    uid: i64,
    view_id: &Uuid,
    _name: &str,
    _import_type: ImportType,
    bytes: Vec<u8>,
  ) -> Result<Vec<ImportedData>, FlowyError> {
    let data = DocumentDataPB::try_from(Bytes::from(bytes))?;
    let encoded_collab = self
      .document_manager()?
      .create_document(uid, view_id, Some(data.into()))
      .await?;
    Ok(vec![(
      view_id.to_string(),
      CollabType::Document,
      encoded_collab,
    )])
  }

  async fn import_from_file_path(
    &self,
    _view_id: &str,
    _name: &str,
    _path: String,
  ) -> Result<(), FlowyError> {
    // TODO(lucas): import file from local markdown file
    Ok(())
  }
}

#[cfg(test)]
mod tests {
  use super::{is_document_backed_layout, remap_document_ids};
  use flowy_document::entities::{BlockPB, ChildrenPB, DocumentDataPB, MetaPB};
  use flowy_folder::entities::ViewLayoutPB;
  use std::collections::HashMap;

  #[test]
  fn document_backed_layouts_follow_platform_boundary() {
    assert!(is_document_backed_layout(&ViewLayoutPB::Document));
    #[cfg(target_os = "windows")]
    {
      assert!(is_document_backed_layout(&ViewLayoutPB::Folder));
      assert!(is_document_backed_layout(&ViewLayoutPB::Notebook));
    }
    #[cfg(not(target_os = "windows"))]
    {
      assert!(!is_document_backed_layout(&ViewLayoutPB::Folder));
      assert!(!is_document_backed_layout(&ViewLayoutPB::Notebook));
    }
    assert!(!is_document_backed_layout(&ViewLayoutPB::Whiteboard));
  }

  fn block(id: &str, parent_id: &str) -> BlockPB {
    BlockPB {
      id: id.to_string(),
      ty: "paragraph".to_string(),
      data: "{}".to_string(),
      parent_id: parent_id.to_string(),
      children_id: String::new(),
      external_id: None,
      external_type: None,
    }
  }

  #[test]
  fn duplicate_regenerates_all_block_ids() {
    let old_page = "old-page";
    let new_page = "new-page";
    let mut blocks = HashMap::new();
    let mut root = block(old_page, "");
    root.children_id = old_page.to_string();
    blocks.insert(old_page.to_string(), root);

    let mut child = block("child", old_page);
    child.children_id = "child".to_string();
    child.external_id = Some("child".to_string());
    blocks.insert("child".to_string(), child);

    let mut grand = block("grand", "child");
    grand.external_id = Some("grand".to_string());
    blocks.insert("grand".to_string(), grand);

    let mut children_map = HashMap::new();
    children_map.insert(
      old_page.to_string(),
      ChildrenPB {
        children: vec!["child".to_string()],
      },
    );
    children_map.insert(
      "child".to_string(),
      ChildrenPB {
        children: vec!["grand".to_string()],
      },
    );
    let mut text_map = HashMap::new();
    text_map.insert("child".to_string(), "child text".to_string());

    let data = DocumentDataPB {
      page_id: old_page.to_string(),
      blocks,
      meta: MetaPB {
        children_map,
        text_map,
      },
    };

    let remapped = remap_document_ids(data, new_page);

    assert_eq!(remapped.page_id, new_page);
    assert_eq!(remapped.blocks.len(), 3);
    assert!(!remapped.blocks.contains_key(old_page));
    assert!(!remapped.blocks.contains_key("child"));
    assert!(!remapped.blocks.contains_key("grand"));

    let root = &remapped.blocks[new_page];
    assert_eq!(root.id, new_page);
    assert_eq!(root.children_id, new_page);

    let child = remapped
      .blocks
      .values()
      .find(|block| block.external_id.as_deref() == Some("child"))
      .expect("child block");
    let grand = remapped
      .blocks
      .values()
      .find(|block| block.external_id.as_deref() == Some("grand"))
      .expect("grand block");
    assert_ne!(child.id, "child");
    assert_ne!(grand.id, "grand");
    assert_eq!(child.parent_id, new_page);
    assert_eq!(grand.parent_id, child.id);

    assert_eq!(
      remapped.meta.children_map[new_page].children,
      vec![child.id.clone()]
    );
    assert_eq!(
      remapped.meta.children_map[&child.id].children,
      vec![grand.id.clone()]
    );
    assert_eq!(remapped.meta.text_map["child"], "child text");
  }

  #[test]
  fn remap_keeps_existing_children_key_when_it_differs_from_page_id() {
    let old_page = "old-page";
    let new_page = "new-page";
    let children_key = "root-children";

    let mut blocks = HashMap::new();
    let mut root = block(old_page, "");
    root.children_id = children_key.to_string();
    blocks.insert(old_page.to_string(), root);

    let mut children_map = HashMap::new();
    children_map.insert(
      children_key.to_string(),
      ChildrenPB {
        children: vec!["child".to_string()],
      },
    );
    let data = DocumentDataPB {
      page_id: old_page.to_string(),
      blocks,
      meta: MetaPB {
        children_map,
        text_map: HashMap::new(),
      },
    };

    let remapped = remap_document_ids(data, new_page);

    assert_eq!(remapped.page_id, new_page);
    assert_eq!(remapped.blocks[new_page].children_id, children_key);
    assert!(remapped.meta.children_map.contains_key(children_key));
    assert!(!remapped.meta.children_map.contains_key(new_page));
  }

  #[test]
  fn remap_is_noop_when_page_id_already_matches() {
    let page_id = "same-page";
    let mut blocks = HashMap::new();
    blocks.insert(page_id.to_string(), block(page_id, ""));
    let data = DocumentDataPB {
      page_id: page_id.to_string(),
      blocks,
      meta: MetaPB::default(),
    };

    let remapped = remap_document_ids(data, page_id);

    assert_eq!(remapped.page_id, page_id);
    assert_eq!(remapped.blocks.len(), 1);
    assert!(remapped.blocks.contains_key(page_id));
  }
}

use std::collections::HashMap;

use collab::preclude::uuid_v4;
use collab_database::database::DatabaseData;
use collab_database::entity::CreateDatabaseParams;
use collab_document::document_data::generate_id;
use collab_entity::CollabType;
use serde_json::json;

use crate::document::getting_started::*;
use crate::TemplateData;
use crate::TemplateObjectId;
use crate::{hierarchy_builder::WorkspaceViewBuilder, WorkspaceTemplate};

#[cfg(test)]
mod tests {
  use super::*;
  use crate::document::util::{create_database_from_params, create_document_from_json};
  use collab_database::database::gen_database_view_id;

  #[tokio::test]
  async fn create_document_from_desktop_guide_json_test() {
    let json_str = include_str!("../../assets/desktop_guide.json");
    test_document_json(json_str).await;
  }

  #[tokio::test]
  async fn create_document_from_mobile_guide_json_test() {
    let json_str = include_str!("../../assets/mobile_guide.json");
    test_document_json(json_str).await;
  }

  #[tokio::test]
  async fn create_document_from_getting_started_json_test() {
    let json_str = include_str!("../../assets/getting_started.json");
    test_document_json(json_str).await;
  }

  #[tokio::test]
  async fn create_database_from_todos_json_test() {
    let json_str = include_str!("../../assets/to-dos.json");
    let template_data = test_database_json(json_str).await;
    // one database and 5 rows
    assert_eq!(template_data.len(), 6);
  }

  async fn test_document_json(json_str: &str) {
    let object_id = uuid_v4().to_string();
    let result = create_document_from_json(object_id.clone(), json_str).await;
    let template_data = result.unwrap();

    match template_data.template_id {
      TemplateObjectId::Document(oid) => {
        assert_eq!(oid, object_id);
      },
      _ => {
        panic!("Template data is not a document");
      },
    }
    assert_eq!(template_data.collab_type, CollabType::Document);
    assert!(!template_data.encoded_collab.doc_state.is_empty());
  }

  async fn test_database_json(json_str: &str) -> Vec<TemplateData> {
    let object_id = gen_database_view_id().to_string();
    let database_data = serde_json::from_str::<DatabaseData>(json_str).unwrap();

    let database_view_id = database_data.views[0].id.clone();
    let create_database_params =
      CreateDatabaseParams::from_database_data(database_data, &database_view_id, &object_id);
    let result = create_database_from_params(object_id.clone(), create_database_params).await;
    let template_data = result.unwrap();

    for (i, data) in template_data.iter().enumerate() {
      if i == 0 {
        // The first item is the database
        assert_eq!(data.collab_type, CollabType::Database);
      } else {
        // The rest are database rows
        assert_eq!(data.collab_type, CollabType::DatabaseRow);
      }

      assert!(!data.encoded_collab.doc_state.is_empty());
    }

    template_data
  }

  #[tokio::test]
  async fn create_workspace_view_with_getting_started_template_test() {
    let template = GettingStartedTemplate;
    let mut workspace_view_builder = WorkspaceViewBuilder::new(generate_id(), 1);

    let result = template
      .create_workspace_view(1, &mut workspace_view_builder)
      .await
      .unwrap();

    // 【默认工作区精简 2026-07-20】1 个空间 + 1 篇欢迎信文档
    // （原为 2 空间 + 4 文档 + 1 数据库 + 5 数据库行 = 12）
    assert_eq!(result.len(), 2);

    let views = workspace_view_builder.build();

    // 只保留一个默认空间
    assert_eq!(views.len(), 1);

    let general_space = &views[0];

    assert_eq!(general_space.parent_view.name, "默认的工作空间");
    // 空间下只有一篇欢迎信
    assert_eq!(general_space.child_views.len(), 1);
    assert_eq!(
      general_space.child_views[0].parent_view.name,
      "写给第一批测试用户的一封信"
    );
    // 欢迎信没有子视图
    assert!(general_space.child_views[0].child_views.is_empty());
  }

}

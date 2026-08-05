use async_trait::async_trait;

use collab_database::database::timestamp;
use collab_folder::ViewLayout;

use crate::document::util::create_document_from_json;
use crate::hierarchy_builder::WorkspaceViewBuilder;
use crate::{gen_view_id, TemplateData, WorkspaceTemplate};

// Template Folder Structure:
// |-- 默认的工作空间 (space)
//     |-- 写给第一批测试用户的一封信 (document)
//
// 【默认工作区精简 2026-07-20】原为 General + Shared 两个空间、共 7 个内置视图
// （Getting started 及其 3 个子指南、To-dos 看板、空的 Shared 空间）。
// 现按产品要求精简为「一个空间 + 一封欢迎信」，用户可自行删除或保留。
// Note: Update the folder structure above if you changed the code below
pub struct GettingStartedTemplate;

impl GettingStartedTemplate {
  /// Create a document template data from the given JSON string
  ///
  /// Create a series of database templates from the given JSON String
  ///
  /// Notes: The output contains DatabaseCollab, DatabaseRowCollab
  async fn create_document_data(
    &self,
    general_view_uuid: String,
    welcome_letter_view_uuid: String,
  ) -> anyhow::Result<(TemplateData, TemplateData)> {
    let default_space_json = include_str!("../../assets/default_space.json");
    let general_data =
      create_document_from_json(general_view_uuid.clone(), default_space_json).await?;

    // 欢迎信：由 assets/welcome_letter.json 生成，内容源自
    // 项目根目录的《写给第一批测试用户的一封信.md》。
    let welcome_letter_json = include_str!("../../assets/welcome_letter.json");
    let welcome_letter_data =
      create_document_from_json(welcome_letter_view_uuid.clone(), welcome_letter_json).await?;

    Ok((general_data, welcome_letter_data))
  }
}

#[async_trait]
impl WorkspaceTemplate for GettingStartedTemplate {
  fn layout(&self) -> ViewLayout {
    ViewLayout::Document
  }

  async fn create(&self, _object_id: String) -> anyhow::Result<Vec<TemplateData>> {
    unreachable!("This function is not supposed to be called.")
  }

  async fn create_workspace_view(
    &self,
    _uid: i64,
    workspace_view_builder: &mut WorkspaceViewBuilder,
  ) -> anyhow::Result<Vec<TemplateData>> {
    let general_view_uuid = gen_view_id().to_string();
    let welcome_letter_view_uuid = gen_view_id().to_string();

    let (general_data, welcome_letter_data) = self
      .create_document_data(general_view_uuid.clone(), welcome_letter_view_uuid.clone())
      .await?;

    // 唯一的默认空间，内含一封欢迎信。二者用户均可自行删除或保留。
    workspace_view_builder
      .with_view_builder(|view_builder| async {
        let created_at = timestamp();
        let mut view_builder = view_builder
          .with_view_id(general_view_uuid.clone())
          .with_name("默认的工作空间")
          .with_extra(&format!(
              "{{\"is_space\":true,\"space_icon\":\"interface_essential/home-3\",\"space_icon_color\":\"0xFFA34AFD\",\"space_permission\":0,\"space_created_at\":{}}}",
              created_at
          ));

        view_builder = view_builder
          .with_child_view_builder(|child_view_builder| async {
            let child_view_builder = child_view_builder
              .with_view_id(welcome_letter_view_uuid.clone())
              .with_name("写给第一批测试用户的一封信")
              .with_icon("💌");
            child_view_builder.build()
          })
          .await;

        view_builder.build()
      })
      .await;

    Ok(vec![general_data, welcome_letter_data])
  }
}

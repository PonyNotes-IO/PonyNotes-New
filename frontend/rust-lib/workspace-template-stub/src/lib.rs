use anyhow::Result;
use async_trait::async_trait;
use collab::entity::EncodedCollab;
use collab_entity::CollabType;
use uuid::Uuid;

#[derive(Clone, Debug)]
pub enum TemplateObjectId {
  Folder(String),
  Document(String),
  DatabaseRow(String),
  Database {
    object_id: String,
    database_id: String,
  },
}

pub struct TemplateData {
  pub template_id: TemplateObjectId,
  pub collab_type: CollabType,
  pub encoded_collab: EncodedCollab,
}

#[async_trait]
pub trait WorkspaceTemplate: Send + Sync {
  async fn generate(
    &self,
    uid: i64,
    workspace_id: &Uuid,
  ) -> Result<Vec<TemplateData>>;
}

pub struct WorkspaceTemplateBuilder {
  uid: i64,
  workspace_id: Uuid,
  templates: Vec<Box<dyn WorkspaceTemplate>>,
}

impl WorkspaceTemplateBuilder {
  pub fn new(uid: i64, workspace_id: &Uuid) -> Self {
    Self {
      uid,
      workspace_id: *workspace_id,
      templates: Vec::new(),
    }
  }

  pub fn with_templates<T>(mut self, templates: Vec<T>) -> Self
  where
    T: WorkspaceTemplate + 'static,
  {
    self.templates = templates
      .into_iter()
      .map(|template| Box::new(template) as Box<dyn WorkspaceTemplate>)
      .collect();
    self
  }

  pub async fn build(&self) -> Result<Vec<TemplateData>> {
    let mut results = Vec::new();
    for template in &self.templates {
      results.extend(template.generate(self.uid, &self.workspace_id).await?);
    }
    Ok(results)
  }
}

pub mod document {
  pub mod vault_template {
    use super::super::*;

    #[derive(Clone, Copy)]
    pub struct VaultTemplate;

    #[async_trait]
    impl WorkspaceTemplate for VaultTemplate {
      async fn generate(
        &self,
        _uid: i64,
        _workspace_id: &Uuid,
      ) -> Result<Vec<TemplateData>> {
        let object_id = Uuid::new_v4().to_string();
        let encoded_collab = EncodedCollab::new_v1(Vec::new(), Vec::new());
        Ok(vec![TemplateData {
          template_id: TemplateObjectId::Document(object_id),
          collab_type: CollabType::Document,
          encoded_collab,
        }])
      }
    }
  }
}


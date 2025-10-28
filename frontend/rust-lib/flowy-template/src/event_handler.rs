use crate::entities::*;
use crate::manager::TemplateManager;
use flowy_error::FlowyResult;
use std::sync::Arc;

pub struct TemplateEventHandler {
  manager: Arc<TemplateManager>,
}

impl TemplateEventHandler {
  pub fn new(manager: Arc<TemplateManager>) -> Self {
    Self { manager }
  }

  pub async fn handle(&self, event: TemplateEventPB, payload: Vec<u8>) -> FlowyResult<Vec<u8>> {
    match event {
      TemplateEventPB::GetMyTemplates => {
        let templates = self.manager.get_my_templates().await?;
        let repeated = RepeatedTemplateItemPB { items: templates };
        Ok(repeated.try_into()?)
      }
      TemplateEventPB::AddToMyTemplates => {
        let payload = AddTemplateToMyTemplatesPayloadPB::try_from(payload.as_slice())
          .map_err(|e| flowy_error::FlowyError::from(anyhow::anyhow!("Failed to parse payload: {}", e)))?;
        self.manager.add_to_my_templates(payload.template).await?;
        Ok(vec![])
      }
      TemplateEventPB::RemoveFromMyTemplates => {
        let payload = RemoveTemplateFromMyTemplatesPayloadPB::try_from(payload.as_slice())
          .map_err(|e| flowy_error::FlowyError::from(anyhow::anyhow!("Failed to parse payload: {}", e)))?;
        self.manager.remove_from_my_templates(&payload.template_id).await?;
        Ok(vec![])
      }
      TemplateEventPB::GetAllTemplates => {
        let templates = self.manager.get_all_templates().await?;
        let repeated = RepeatedTemplateItemPB { items: templates };
        Ok(repeated.try_into()?)
      }
      TemplateEventPB::GetTemplatesByCategory => {
        let payload = TemplateCategoryPB::try_from(payload.as_slice())
          .map_err(|e| flowy_error::FlowyError::from(anyhow::anyhow!("Failed to parse payload: {}", e)))?;
        let templates = self.manager.get_templates_by_category(&payload.category).await?;
        let repeated = RepeatedTemplateItemPB { items: templates };
        Ok(repeated.try_into()?)
      }
      TemplateEventPB::SearchTemplates => {
        let payload = TemplateSearchPB::try_from(payload.as_slice())
          .map_err(|e| flowy_error::FlowyError::from(anyhow::anyhow!("Failed to parse payload: {}", e)))?;
        let templates = self.manager.search_templates(&payload.query).await?;
        let repeated = RepeatedTemplateItemPB { items: templates };
        Ok(repeated.try_into()?)
      }
      TemplateEventPB::GetFeaturedTemplates => {
        let templates = self.manager.get_featured_templates().await?;
        let repeated = RepeatedTemplateItemPB { items: templates };
        Ok(repeated.try_into()?)
      }
    }
  }
}

use serde::{Deserialize, Serialize};

#[derive(Default, Debug, Clone, Serialize, Deserialize)]
pub struct TemplateItemPB {
  pub id: String,
  pub title: String,
  pub description: String,
  pub category: String,
  pub author: String,
  pub preview_url: String,
  pub featured: bool,
  pub tags: Vec<String>,
  pub download_url: String,
  pub created_at: i64,
  pub updated_at: i64,
}

#[derive(Default, Debug, Clone, Serialize, Deserialize)]
pub struct RepeatedTemplateItemPB {
  pub items: Vec<TemplateItemPB>,
}

#[derive(Default, Debug, Clone, Serialize, Deserialize)]
pub struct TemplateIdPB {
  pub template_id: String,
}

#[derive(Default, Debug, Clone, Serialize, Deserialize)]
pub struct TemplateCategoryPB {
  pub category: String,
}

#[derive(Default, Debug, Clone, Serialize, Deserialize)]
pub struct TemplateSearchPB {
  pub query: String,
}

#[derive(Default, Debug, Clone, Serialize, Deserialize)]
pub struct AddTemplateToMyTemplatesPayloadPB {
  pub template: TemplateItemPB,
}

#[derive(Default, Debug, Clone, Serialize, Deserialize)]
pub struct RemoveTemplateFromMyTemplatesPayloadPB {
  pub template_id: String,
}

#[derive(Debug, Clone, Default)]
pub enum TemplateEventPB {
  #[default]
  GetMyTemplates = 0,
  AddToMyTemplates = 1,
  RemoveFromMyTemplates = 2,
  GetAllTemplates = 3,
  GetTemplatesByCategory = 4,
  SearchTemplates = 5,
  GetFeaturedTemplates = 6,
}

impl std::convert::From<i32> for TemplateEventPB {
  fn from(val: i32) -> Self {
    match val {
      0 => TemplateEventPB::GetMyTemplates,
      1 => TemplateEventPB::AddToMyTemplates,
      2 => TemplateEventPB::RemoveFromMyTemplates,
      3 => TemplateEventPB::GetAllTemplates,
      4 => TemplateEventPB::GetTemplatesByCategory,
      5 => TemplateEventPB::SearchTemplates,
      6 => TemplateEventPB::GetFeaturedTemplates,
      _ => TemplateEventPB::GetMyTemplates,
    }
  }
}

impl TryFrom<&[u8]> for TemplateItemPB {
  type Error = serde_json::Error;
  
  fn try_from(data: &[u8]) -> Result<Self, Self::Error> {
    serde_json::from_slice(data)
  }
}

impl TryFrom<&[u8]> for RepeatedTemplateItemPB {
  type Error = serde_json::Error;
  
  fn try_from(data: &[u8]) -> Result<Self, Self::Error> {
    serde_json::from_slice(data)
  }
}

impl TryFrom<&[u8]> for TemplateIdPB {
  type Error = serde_json::Error;
  
  fn try_from(data: &[u8]) -> Result<Self, Self::Error> {
    serde_json::from_slice(data)
  }
}

impl TryFrom<&[u8]> for TemplateCategoryPB {
  type Error = serde_json::Error;
  
  fn try_from(data: &[u8]) -> Result<Self, Self::Error> {
    serde_json::from_slice(data)
  }
}

impl TryFrom<&[u8]> for TemplateSearchPB {
  type Error = serde_json::Error;
  
  fn try_from(data: &[u8]) -> Result<Self, Self::Error> {
    serde_json::from_slice(data)
  }
}

impl TryFrom<&[u8]> for AddTemplateToMyTemplatesPayloadPB {
  type Error = serde_json::Error;
  
  fn try_from(data: &[u8]) -> Result<Self, Self::Error> {
    serde_json::from_slice(data)
  }
}

impl TryFrom<&[u8]> for RemoveTemplateFromMyTemplatesPayloadPB {
  type Error = serde_json::Error;
  
  fn try_from(data: &[u8]) -> Result<Self, Self::Error> {
    serde_json::from_slice(data)
  }
}

impl TryInto<Vec<u8>> for RepeatedTemplateItemPB {
  type Error = serde_json::Error;
  
  fn try_into(self) -> Result<Vec<u8>, Self::Error> {
    serde_json::to_vec(&self)
  }
}
use crate::entities::*;
use flowy_sqlite::schema::user_template_table;
use chrono::Utc;
use diesel::prelude::*;
use flowy_error::FlowyResult;
use flowy_sqlite::{DBConnection, RunQueryDsl, ConnectionPool};
use std::sync::Arc;

#[derive(Clone, Queryable, Identifiable, Insertable, AsChangeset)]
#[diesel(table_name = user_template_table)]
pub struct UserTemplateTable {
  pub id: String,
  pub user_id: i64,
  pub template_id: String,
  pub title: String,
  pub description: String,
  pub category: String,
  pub author: String,
  pub preview_url: String,
  pub featured: bool,
  pub tags: String, // JSON string
  pub download_url: String,
  pub created_at: i64,
  pub updated_at: i64,
}

impl UserTemplateTable {
  pub fn new(user_id: i64, template: TemplateItemPB) -> Self {
    let _now = Utc::now().timestamp();
    Self {
      id: uuid::Uuid::new_v4().to_string(),
      user_id,
      template_id: template.id,
      title: template.title,
      description: template.description,
      category: template.category,
      author: template.author,
      preview_url: template.preview_url,
      featured: template.featured,
      tags: serde_json::to_string(&template.tags).unwrap_or_default(),
      download_url: template.download_url,
      created_at: template.created_at,
      updated_at: template.updated_at,
    }
  }

  pub fn to_pb(&self) -> TemplateItemPB {
    let tags: Vec<String> = serde_json::from_str(&self.tags).unwrap_or_default();
    TemplateItemPB {
      id: self.template_id.clone(),
      title: self.title.clone(),
      description: self.description.clone(),
      category: self.category.clone(),
      author: self.author.clone(),
      preview_url: self.preview_url.clone(),
      featured: self.featured,
      tags,
      download_url: self.download_url.clone(),
      created_at: self.created_at,
      updated_at: self.updated_at,
    }
  }
}

pub struct TemplateService {
  pool: Arc<ConnectionPool>,
}

impl TemplateService {
  pub fn new(pool: Arc<ConnectionPool>) -> Self {
    Self { pool }
  }

  pub async fn initialize(&self) -> FlowyResult<()> {
    let mut conn = self.pool.get()?;
    crate::migration::run_migrations(&mut conn)?;
    Ok(())
  }

  pub async fn get_my_templates(&self) -> FlowyResult<Vec<TemplateItemPB>> {
    let mut conn = self.pool.get()?;
    let user_id = self.get_current_user_id(&mut conn)?;
    
    let templates = user_template_table::dsl::user_template_table
      .filter(user_template_table::user_id.eq(user_id))
      .order(user_template_table::created_at.desc())
      .load::<UserTemplateTable>(&mut *conn)?;

    Ok(templates.into_iter().map(|t| t.to_pb()).collect())
  }

  pub async fn add_to_my_templates(&self, template: TemplateItemPB) -> FlowyResult<()> {
    let mut conn = self.pool.get()?;
    let user_id = self.get_current_user_id(&mut conn)?;

    // Check if template already exists
    let exists = user_template_table::dsl::user_template_table
      .filter(user_template_table::user_id.eq(user_id))
      .filter(user_template_table::template_id.eq(&template.id))
      .first::<UserTemplateTable>(&mut *conn)
      .optional()?;

    if exists.is_some() {
      return Ok(()); // Already exists
    }

    let template_table = UserTemplateTable::new(user_id, template);
    diesel::insert_into(user_template_table::dsl::user_template_table)
      .values(&template_table)
      .execute(&mut *conn)?;

    Ok(())
  }

  pub async fn remove_from_my_templates(&self, template_id: &str) -> FlowyResult<()> {
    let mut conn = self.pool.get()?;
    let user_id = self.get_current_user_id(&mut conn)?;

    diesel::delete(
      user_template_table::dsl::user_template_table
        .filter(user_template_table::user_id.eq(user_id))
        .filter(user_template_table::template_id.eq(template_id))
    )
    .execute(&mut *conn)?;

    Ok(())
  }

  pub async fn get_all_templates(&self) -> FlowyResult<Vec<TemplateItemPB>> {
    // This would typically fetch from external API or local cache
    // For now, return empty vector as this should be handled by the Flutter side
    Ok(vec![])
  }

  pub async fn get_templates_by_category(&self, _category: &str) -> FlowyResult<Vec<TemplateItemPB>> {
    // This would typically fetch from external API or local cache
    // For now, return empty vector as this should be handled by the Flutter side
    Ok(vec![])
  }

  pub async fn search_templates(&self, _query: &str) -> FlowyResult<Vec<TemplateItemPB>> {
    // This would typically fetch from external API or local cache
    // For now, return empty vector as this should be handled by the Flutter side
    Ok(vec![])
  }

  pub async fn get_featured_templates(&self) -> FlowyResult<Vec<TemplateItemPB>> {
    // This would typically fetch from external API or local cache
    // For now, return empty vector as this should be handled by the Flutter side
    Ok(vec![])
  }

  fn get_current_user_id(&self, _conn: &mut DBConnection) -> FlowyResult<i64> {
    // This should get the current user ID from the session or context
    // For now, return a placeholder
    Ok(1)
  }
}

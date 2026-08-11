use async_stream::stream;
use futures::Stream;
use std::pin::Pin;
use std::sync::Weak;
use tokio::sync::RwLock;
use tracing::{error, trace};
use uuid::Uuid;

use crate::entities::{
  CreateSearchResultPBArgs, LocalSearchResponseItemPB, RepeatedLocalSearchResponseItemPB,
  ResultIconPB, ResultIconTypePB, SearchResponsePB,
};
use crate::services::manager::{SearchHandler, SearchType};
use flowy_error::FlowyResult;
use flowy_search_pub::entities::TanvitySearchResponseItem;
use flowy_search_pub::tantivy_state::DocumentTantivyState;
use lib_infra::async_trait::async_trait;

pub struct DocumentLocalSearchHandler {
  state: Weak<RwLock<DocumentTantivyState>>,
}

impl DocumentLocalSearchHandler {
  pub fn new(state: Weak<RwLock<DocumentTantivyState>>) -> Self {
    Self { state }
  }
}

#[async_trait]
impl SearchHandler for DocumentLocalSearchHandler {
  fn search_type(&self) -> SearchType {
    SearchType::DocumentLocal
  }

  async fn perform_search(
    &self,
    query: String,
    workspace_id: &Uuid,
  ) -> Pin<Box<dyn Stream<Item = FlowyResult<SearchResponsePB>> + Send + 'static>> {
    let workspace_id = *workspace_id;
    let state = self.state.clone();
    Box::pin(stream! {
      match state.upgrade() {
        None => {
          yield Ok(
            CreateSearchResultPBArgs::default()
              .local_search_result(None)
              .build()
              .unwrap(),
          );
        },
        Some(state) => {
          match state.read().await.search(&workspace_id, &query, None, 10, 0.4) {
            Ok(items) => {
              trace!("[Tanvity] local document search result: {:?}", items);
              if items.is_empty() {
                yield Ok(
                  CreateSearchResultPBArgs::default()
                    .local_search_result(None)
                    .build()
                    .unwrap(),
                );
              } else {
                let items = items.into_iter().map(tanvity_item_to_local_search_item).collect::<Vec<_>>();
                let search_result = RepeatedLocalSearchResponseItemPB { items };
                yield Ok(
                  CreateSearchResultPBArgs::default()
                    .local_search_result(Some(search_result))
                    .build()
                    .unwrap(),
                );
              }
            },
            Err(err) => error!("[Tantivy] Failed to search documents, {:?}", err),
          }
        }
      }
    })
  }
}

fn tanvity_item_to_local_search_item(item: TanvitySearchResponseItem) -> LocalSearchResponseItemPB {
  LocalSearchResponseItemPB {
    id: item.id,
    display_name: item.display_name,
    icon: item.icon.map(|icon| ResultIconPB {
      ty: ResultIconTypePB::from(icon.ty),
      value: icon.value,
    }),
    workspace_id: item.workspace_id,
  }
}

#[cfg(test)]
mod tests {
  use super::{DocumentLocalSearchHandler, SearchHandler};
  use flowy_search_pub::tantivy_state::DocumentTantivyState;
  use futures::StreamExt;
  use std::sync::Arc;
  use tokio::sync::RwLock;
  use uuid::Uuid;

  #[tokio::test]
  async fn mobile_global_search_returns_chinese_title_substring() {
    let temp_dir = tempfile::tempdir().unwrap();
    let workspace_id = Uuid::new_v4();
    let mut state =
      DocumentTantivyState::new(&workspace_id, temp_dir.path().to_path_buf()).unwrap();
    state
      .add_document(
        "doc-1",
        Some("无关正文内容".to_string()),
        Some("可乐本地文档".to_string()),
        None,
      )
      .unwrap();
    state.reader.reload().unwrap();

    let state = Arc::new(RwLock::new(state));
    let handler = DocumentLocalSearchHandler::new(Arc::downgrade(&state));
    let mut responses = handler
      .perform_search("可乐".to_string(), &workspace_id)
      .await;

    let response = responses.next().await.unwrap().unwrap();
    let items = response.local_search_result.unwrap().items;

    assert_eq!(items.len(), 1);
    assert_eq!(items[0].id, "doc-1");
    assert_eq!(items[0].display_name, "可乐本地文档");
  }
}

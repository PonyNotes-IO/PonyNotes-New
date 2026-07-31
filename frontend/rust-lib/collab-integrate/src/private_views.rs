use std::collections::HashSet;
use std::sync::{Arc, RwLock};

/// 私有空间视图的共享登记表。
///
/// 存在的理由：创建同步插件的 `ServerProvider`（flowy-core）需要知道某个 collab
/// 是否属于私有空间，才能给它选「编辑静默后才推送」的同步配置；而这个信息只有
/// folder（flowy-folder）知道。两者不能互相依赖 —— folder manager 本身就依赖
/// server provider，反向注入会成环。
///
/// 于是把它降到双方都依赖的 `collab-integrate`：folder 侧在加载/变更时写入，
/// server provider 侧只读查询。
///
/// 语义上是一份**缓存**而非权威数据：查不到时按「非私有」处理，也就是维持原有的
/// 实时推送节奏 —— 宁可多推，也不会让协作内容退化成「对方停手才可见」。
#[derive(Clone, Default)]
pub struct PrivateViewRegistry {
  inner: Arc<RwLock<HashSet<String>>>,
}

impl PrivateViewRegistry {
  pub fn new() -> Self {
    Self::default()
  }

  /// 整体替换当前用户的私有视图集合。folder 每次重新加载 / 私有区发生增删时调用。
  pub fn replace(&self, view_ids: HashSet<String>) {
    *self.inner.write().unwrap_or_else(|e| e.into_inner()) = view_ids;
  }

  /// 该视图是否在私有空间。查不到一律返回 `false`（按非私有处理）。
  pub fn is_private(&self, view_id: &str) -> bool {
    self.inner.read().map(|s| s.contains(view_id)).unwrap_or(false)
  }

  /// 当前登记的私有视图数量，用于日志与排查。
  pub fn len(&self) -> usize {
    self.inner.read().map(|s| s.len()).unwrap_or(0)
  }

  pub fn is_empty(&self) -> bool {
    self.inner.read().map(|s| s.is_empty()).unwrap_or(true)
  }

  /// 切换用户 / 退出登录时清空，避免上一个账号的私有集合影响下一个账号。
  pub fn clear(&self) {
    self.inner.write().unwrap_or_else(|e| e.into_inner()).clear();
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn unknown_view_is_treated_as_not_private() {
    let registry = PrivateViewRegistry::new();
    assert!(
      !registry.is_private("never-registered"),
      "查不到时必须按非私有处理，否则协作内容会被误判为私有而延迟推送"
    );
  }

  #[test]
  fn replace_swaps_the_whole_set() {
    let registry = PrivateViewRegistry::new();
    registry.replace(HashSet::from(["a".to_string(), "b".to_string()]));
    assert!(registry.is_private("a"));
    assert!(registry.is_private("b"));

    registry.replace(HashSet::from(["b".to_string()]));
    assert!(!registry.is_private("a"), "replace 必须是整体替换而非合并");
    assert!(registry.is_private("b"));
  }

  #[test]
  fn clear_empties_the_registry() {
    let registry = PrivateViewRegistry::new();
    registry.replace(HashSet::from(["a".to_string()]));
    registry.clear();
    assert!(registry.is_empty());
    assert!(!registry.is_private("a"));
  }
}

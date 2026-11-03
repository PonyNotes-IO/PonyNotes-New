//! 双向链接索引的本地实体定义。
//!
//! 这些结构是「正文 → 索引表」的中间表示。设计原则：
//!
//! 1. 边是**有向且带位置**的：同一个块可能引用多个目标，跳转要能定位到字符偏移。
//! 2. 同块内对同一目标的重复引用**合并为一条边 + `occurrence` 计数**，
//!    否则一个「索引列表」式的块能把边数放大几十倍。
//! 3. 悬空引用（目标页不存在）单独收集，不从结果里丢弃。

/// 边的类型。决定 UI 的展示方式与是否计入图谱结构层。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum LinkKind {
  /// 页面内联提及（mention type = page）。默认计入图谱结构层。
  Reference,
  /// 嵌入引用（mention type = childPage / embed）。渲染为内嵌块。
  Embed,
  /// 块引用 `((block_id))`，指向具体块而非整页。
  BlockRef,
  /// 数据库 relation 字段产生的引用，不是正文里的链接。
  Relation,
}

impl LinkKind {
  /// 写入 SQLite 的稳定字面量。**不要随意改名**，历史数据里存的就是这些值。
  pub fn as_str(&self) -> &'static str {
    match self {
      Self::Reference => "reference",
      Self::Embed => "embed",
      Self::BlockRef => "block_ref",
      Self::Relation => "relation",
    }
  }

  /// 从数据库读回。未知值返回 `None`，由调用方决定跳过还是报错，
  /// 而不是默认成 `Reference` —— 静默降级会让统计口径悄悄漂移。
  pub fn from_str(value: &str) -> Option<Self> {
    match value {
      "reference" => Some(Self::Reference),
      "embed" => Some(Self::Embed),
      "block_ref" => Some(Self::BlockRef),
      "relation" => Some(Self::Relation),
      _ => None,
    }
  }
}

/// 一条结构边：源块 → 目标页（或目标块）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LinkEdge {
  pub src_page_id: String,
  pub src_block_id: String,
  pub dst_page_id: String,
  /// 块引用时非空；页面引用时为空。
  pub dst_block_id: Option<String>,
  pub kind: LinkKind,
  /// 展示文本快照。目标页存在时应优先用其当前标题，此字段只在目标缺失时兜底。
  pub label: String,
  /// 在该块正文中的字符偏移，用于跳转后滚动定位。
  pub char_offset: u32,
  /// 同一块内对同一目标的重复引用次数（>= 1）。
  pub occurrence: u32,
}

/// 悬空引用：正文里有 `[[某标题]]`，但当前不存在同名页面。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UnresolvedLink {
  pub src_page_id: String,
  pub src_block_id: String,
  /// 规范化后的标题，用于跨页匹配。
  pub normalized_title: String,
  /// 用户实际输入的标题，用于「创建此页」时回填。
  pub raw_title: String,
  pub char_offset: u32,
}

/// 单次提取的完整结果。
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ExtractedLinks {
  pub edges: Vec<LinkEdge>,
  pub unresolved: Vec<UnresolvedLink>,
}

impl ExtractedLinks {
  pub fn is_empty(&self) -> bool {
    self.edges.is_empty() && self.unresolved.is_empty()
  }

  /// 合并提取结果，并把「同源块 + 同目标」的边合并为一条，累加 `occurrence`。
  ///
  /// 合并必须在**提取之后**做，而不是在遍历过程中就地判断：
  /// 遍历顺序按 `children_map` 走，合并表用 HashMap，两者解耦才能保证输出顺序稳定。
  pub fn push(&mut self, mut other: ExtractedLinks) {
    for edge in other.edges.drain(..) {
      match self
        .edges
        .iter_mut()
        .find(|e| e.src_block_id == edge.src_block_id && e.dst_key() == edge.dst_key())
      {
        Some(existing) => {
          // 保留首次出现的偏移，因为它才是用户视觉上的第一个落点
          existing.occurrence += edge.occurrence;
        },
        None => self.edges.push(edge),
      }
    }
    self.unresolved.append(&mut other.unresolved);
  }
}

impl LinkEdge {
  /// 用于合并判断的目标标识：目标页 + 目标块 + 类型。
  fn dst_key(&self) -> (&str, Option<&str>, LinkKind) {
    (&self.dst_page_id, self.dst_block_id.as_deref(), self.kind)
  }

  /// 是否为自引用（本页引用本页）。允许存在，但图谱和计数里要排除。
  pub fn is_self_reference(&self) -> bool {
    self.src_page_id == self.dst_page_id
  }
}

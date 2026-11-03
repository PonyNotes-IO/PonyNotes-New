//! 从 `DocumentData`（CRDT 快照）中提取结构化的链接边。
//!
//! # 为什么不用「递归找键名」
//!
//! 旧实现（`plugins/knowledge_graph`）会把每个 block 的 `data` 和 `meta.text_map`
//! 整个 `jsonDecode` 后深度遍历，只要键名是 `page_id` 就记一条边。问题有三个：
//!
//! - 数据库 relation 字段、备份残留字段也会叫 `page_id`，会被误判成正文链接；
//! - 拿不到字符偏移，无法「跳转到引用处」；
//! - 拿不到引用类型，无法区分内联提及和嵌入。
//!
//! 这里改为**只认结构化位置**：行内提及只认 delta 里
//! `attributes.mention` 命名空间，块级提及只认 `data.view_id`。
//!
//! # 两种链接形态
//!
//! 1. **行内提及**：delta 中出现 `{"insert":"$","attributes":{"mention":{"type":"page","page_id":..}}}`。
//!    一个块里可以有多个，各自带偏移。
//! 2. **块级提及**：整块就是一个页面引用，目标在 `block.data.view_id`。
//!    这时偏移记 0，因为它占据整个块。
//!
//! # 为什么走 `children_map`
//!
//! `DocumentData.blocks` 是 `HashMap`，遍历顺序不稳定。若按它遍历，同样的文档
//! 两次解析会得到不同的边顺序，索引内容随之抖动。`children_map` 才是真实文档顺序。

use std::collections::{HashMap, HashSet};

use collab_document::blocks::{Block, DocumentData};
use serde_json::Value;

use crate::entities::{ExtractedLinks, LinkEdge, LinkKind, UnresolvedLink};

/// 行内提及在 delta 中的占位符。CRDT 里提及不存自身文本，只存这个符号 + 属性。
const MENTION_PLACEHOLDER: &str = "$";

/// 提取一页的全部链接。
///
/// 返回值里的 `unresolved` 是**候选**：它只表示「正文出现了 `[[某标题]]`」，
/// 这些标题是否真的有对应页面，需要上层拿标题表比对后才好判定。
/// 这样拆开是因为 extractor 不应该关心工作区里有几页笔记。
pub fn extract_links(doc: &DocumentData) -> ExtractedLinks {
  let src_page_id = doc.page_id.as_str();
  let mut out = ExtractedLinks::default();

  // 防环：正常数据是树，但损坏或并发写入可能产生环，递归会栈溢出。
  let mut visited: HashSet<&str> = HashSet::new();
  // 倒序入栈：栈是后进先出，只有倒着压才能按文档顺序弹出。
  // 这一步漏掉的话，边顺序会整体反转，图谱和面板的排序随之抖动。
  let mut stack: Vec<&str> = doc
    .meta
    .children_map
    .get(
      doc
        .blocks
        .get(src_page_id)
        .map(|root| root.children.as_str())
        .unwrap_or(src_page_id),
    )
    .map(|children| children.iter().rev().map(String::as_str).collect())
    .unwrap_or_default();

  // 显式栈而非递归：文档嵌套可能很深，递归在深链上会爆栈。
  while let Some(block_id) = stack.pop() {
    if !visited.insert(block_id) {
      tracing::warn!(
        "[Link] cycle detected while walking blocks, page_id: {}, block_id: {}",
        src_page_id,
        block_id
      );
      continue;
    }

    let Some(block) = doc.blocks.get(block_id) else {
      // children_map 指向不存在的 block：数据不一致，跳过但记录。
      tracing::warn!(
        "[Link] children_map references missing block, page_id: {}, block_id: {}",
        src_page_id,
        block_id
      );
      continue;
    };

    extract_from_block(doc, block, src_page_id, &mut out);

    if let Some(children) = doc.meta.children_map.get(&block.children) {
      // 倒序入栈，保证出栈顺序与文档顺序一致
      for child in children.iter().rev() {
        stack.push(child.as_str());
      }
    }
  }

  let mut merged = ExtractedLinks::default();
  merged.push(out);
  let mut unresolved_seen = HashSet::new();
  merged.unresolved.retain(|link| {
    unresolved_seen.insert((link.src_block_id.clone(), link.normalized_title.clone()))
  });
  merged
}

/// 处理单个块：先看它是不是块级提及，再解析行内 delta。
fn extract_from_block(
  doc: &DocumentData,
  block: &Block,
  src_page_id: &str,
  out: &mut ExtractedLinks,
) {
  // ---- 块级提及：整块指向一个页面（子页面块、嵌入块）----
  if let Some(dst) = block_level_mention(block) {
    out.edges.push(LinkEdge {
      src_page_id: src_page_id.to_string(),
      src_block_id: block.id.clone(),
      dst_page_id: dst,
      dst_block_id: None,
      kind: LinkKind::Embed,
      label: String::new(),
      char_offset: 0,
      occurrence: 1,
    });
    // 块级提及没有正文文本，不必再解析 delta。
    return;
  }

  if matches!(block.ty.as_str(), "link_preview" | "link_embed") {
    if let Some((dst_page_id, dst_block_id)) = block
      .data
      .get("url")
      .and_then(Value::as_str)
      .and_then(internal_link_target)
    {
      out.edges.push(LinkEdge {
        src_page_id: src_page_id.into(),
        src_block_id: block.id.clone(),
        dst_page_id,
        kind: if dst_block_id.is_some() {
          LinkKind::BlockRef
        } else {
          LinkKind::Reference
        },
        dst_block_id,
        label: String::new(),
        char_offset: 0,
        occurrence: 1,
      });
    }
  }
  // ---- 行内提及 + 纯文本 wikilink ----
  let Some(delta) = block_delta(doc, block) else {
    return;
  };
  extract_from_delta(&delta, &block.id, src_page_id, out);
}

/// 块级提及的目标页 id。
///
/// 用字段存在性判断而不是 `block.ty`：`ty` 的取值在版本间会变，
/// 而 `view_id` 只出现在页面提及块上，这个约定更稳定。
fn block_level_mention(block: &Block) -> Option<String> {
  if !matches!(
    block.ty.as_str(),
    "sub_page" | "mention" | "link_to_page" | "embed"
  ) {
    return None;
  }
  block
    .data
    .get("view_id")
    .and_then(Value::as_str)
    .filter(|s| !s.is_empty())
    .map(str::to_string)
}

/// 取块的 delta。
///
/// 查找顺序有讲究：
/// 1. `text_map[external_id]` —— 外部块（模板、引用块）的文本挂在 external_id 下；
/// 2. `text_map[block.id]` —— 普通块的常规位置；
/// 3. `block.data["delta"]` —— 部分块把 delta 直接内联在 data 里。
fn block_delta(doc: &DocumentData, block: &Block) -> Option<Vec<Value>> {
  if let Some(text_map) = doc.meta.text_map.as_ref() {
    let keys: [Option<&str>; 2] = [block.external_id.as_deref(), Some(block.id.as_str())];
    for key in keys.into_iter().flatten() {
      if let Some(raw) = text_map.get(key) {
        if let Ok(parsed) = parse_delta_json(raw) {
          return Some(parsed);
        }
      }
    }
  }

  let inline = block.data.get("delta")?;
  match inline {
    Value::String(raw) => parse_delta_json(raw).ok(),
    Value::Array(ops) => Some(ops.clone()),
    _ => None,
  }
}

/// delta 可能是「JSON 字符串」也可能是「已解析的数组」，两种都接受。
fn parse_delta_json(raw: &str) -> Result<Vec<Value>, serde_json::Error> {
  let value: Value = serde_json::from_str(raw)?;
  Ok(match value {
    Value::Array(ops) => ops,
    // 空字符串、null 之类的脏数据当作「无内容」，不报错
    _ => Vec::new(),
  })
}

/// 遍历 delta，累加字符偏移，收集提及与 wikilink。
fn extract_from_delta(ops: &[Value], block_id: &str, src_page_id: &str, out: &mut ExtractedLinks) {
  // 偏移按「字符」而非字节推进：中文块里两者差三倍，用字节会让跳转落到半个汉字中间。
  let mut offset: u32 = 0;

  for op in ops {
    let Some(insert) = op.get("insert") else {
      continue;
    };

    // Only editor href attributes can introduce URL references.
    if let Some((dst_page_id, dst_block_id)) = op
      .pointer("/attributes/href")
      .and_then(Value::as_str)
      .and_then(internal_link_target)
    {
      out.edges.push(LinkEdge {
        src_page_id: src_page_id.into(),
        src_block_id: block_id.into(),
        dst_page_id,
        kind: if dst_block_id.is_some() {
          LinkKind::BlockRef
        } else {
          LinkKind::Reference
        },
        dst_block_id,
        label: insert.as_str().unwrap_or_default().into(),
        char_offset: offset,
        occurrence: 1,
      });
    }
    // 提及：insert 是占位符 "$"，真正的目标在 attributes.mention 里
    if insert.as_str() == Some(MENTION_PLACEHOLDER) {
      if let Some(mention) = op.pointer("/attributes/mention") {
        if let Some(edge) = mention_to_edge(mention, block_id, src_page_id, offset) {
          out.edges.push(edge);
        }
      }
      offset = offset.saturating_add(1);
      continue;
    }

    if let Some(text) = insert.as_str() {
      // 纯文本里手打的 [[标题]]：先收成候选，是否悬空由上层判定
      for found in scan_wikilinks(text) {
        out.unresolved.push(UnresolvedLink {
          src_page_id: src_page_id.to_string(),
          src_block_id: block_id.to_string(),
          normalized_title: normalize_title(&found.title),
          raw_title: found.title,
          char_offset: offset.saturating_add(found.start as u32),
        });
      }
      offset = offset.saturating_add(char_len(text));
      continue;
    }

    // 其他类型的 insert（表情、公式等对象）：占一个位置。
    offset = offset.saturating_add(1);
  }
}

/// 把 mention 属性翻译成一条边。
fn mention_to_edge(
  mention: &Value,
  block_id: &str,
  src_page_id: &str,
  offset: u32,
) -> Option<LinkEdge> {
  let dst_page_id = mention.get("page_id")?.as_str()?;
  if dst_page_id.is_empty() {
    // 空目标通常意味着用户刚插入还没选页面，不是有效链接。
    return None;
  }

  let ty = mention
    .get("type")
    .and_then(Value::as_str)
    .unwrap_or("page");
  let dst_block_id = mention
    .get("block_id")
    .and_then(Value::as_str)
    .filter(|id| !id.is_empty())
    .map(str::to_string);
  let kind = match ty {
    "page" if dst_block_id.is_some() => LinkKind::BlockRef,
    "page" => LinkKind::Reference,
    "childPage" | "child_page" => LinkKind::Embed,
    "blockRef" | "block_ref" => LinkKind::BlockRef,
    other => {
      tracing::debug!("[Link] ignoring non-page mention type: {}", other);
      return None;
    },
  };

  // 展示文本快照：mention 可以带自定义显示文本（[[页面|别名]]）。
  let label = mention
    .get("text")
    .and_then(Value::as_str)
    .unwrap_or_default()
    .to_string();

  Some(LinkEdge {
    src_page_id: src_page_id.to_string(),
    src_block_id: block_id.to_string(),
    dst_page_id: dst_page_id.to_string(),
    dst_block_id,
    kind,
    label,
    char_offset: offset,
    occurrence: 1,
  })
}

/// 扫描结果：标题、在文本内的起始偏移。
struct FoundWikiLink {
  title: String,
  start: usize,
}

/// 手写扫描 `[[标题]]` / `[[标题|别名]]`。
///
/// 不用正则有两个原因：一是避免为一件小事引入依赖，二是这里要精确控制
/// 「什么算不合法」——标题内不允许出现 `[`、`]`、换行，否则 `[[a] 与 [b]]`
/// 会被错误地连成一个链接。
///
/// 返回值里的 `start` 是**字符**索引，不是字节索引：它要直接参与 `char_offset`。
/// 曾按字节走 UTF-8，中文标题的偏移会算成三倍，跳转落在块中间。
fn scan_wikilinks(text: &str) -> Vec<FoundWikiLink> {
  // 先转成字符序列，后续所有下标天然是字符下标，不必反复做字节→字符换算。
  let chars: Vec<char> = text.chars().collect();
  let mut found = Vec::new();
  let mut i = 0;

  while i + 1 < chars.len() {
    if chars[i] == '[' && chars[i + 1] == '[' {
      let body_start = i + 2;
      let mut j = body_start;
      let mut closed = false;

      while j + 1 < chars.len() {
        match chars[j] {
          // 标题里出现单个 '[' 或 ']' 都说明这不是我们想要的语法，整体放弃
          '[' | '\n' => break,
          ']' if chars[j + 1] == ']' => {
            closed = true;
            break;
          },
          ']' => break,
          _ => j += 1,
        }
      }

      if closed {
        let body: String = chars[body_start..j].iter().collect();
        // 别名语法 [[标题|显示文本]]：取竖线左边作为目标标题
        let title = body.split('|').next().unwrap_or("").trim();
        if !title.is_empty() {
          found.push(FoundWikiLink {
            title: title.to_string(),
            start: i,
          });
        }
        // 跳过整个 [[...]]，避免把内部的 '[' 当成新链接的开头
        i = j + 2;
        continue;
      }
    }
    i += 1;
  }

  found
}

/// 字符数（不是字节数）。`chars().count()` 对代理对按一个字符计，符合编辑器语义。
fn char_len(text: &str) -> u32 {
  text.chars().count() as u32
}

/// 标题规范化，用于跨页匹配。
///
/// 规则：折叠连续空白 → 去首尾空白 → 小写化。
///
/// 小写化对中文无影响，但英文标题（`Rust Ownership` vs `rust ownership`）
/// 不折叠就会出现「明明同名却互不可见」的鬼故事。
///
/// TODO(P1): 补 NFKC，处理全角/半角差异（`ＡＢＣ` 与 `ABC` 目前不相等）。
/// Resolve only recognized application schemes or official HTTPS share URLs.
fn internal_link_target(raw: &str) -> Option<(String, Option<String>)> {
  let uri = url::Url::parse(raw).ok()?;
  let internal = matches!(uri.scheme(), "ponynotes" | "appflowy" | "appflowy-flutter");
  let share = uri.scheme() == "https"
    && uri.path() == "/share"
    && matches!(
      uri.host_str(),
      Some("xiaomabiji.com" | "www.xiaomabiji.com" | "ponynotes.io" | "www.ponynotes.io")
    );
  if !internal && !share {
    return None;
  }
  let params: HashMap<_, _> = uri.query_pairs().into_owned().collect();
  let page = params
    .get("viewId")
    .or_else(|| params.get("page_id"))?
    .trim();
  if page.is_empty() {
    return None;
  }
  let block = params
    .get("blockId")
    .or_else(|| params.get("block_id"))
    .filter(|id| !id.is_empty())
    .cloned();
  Some((page.to_string(), block))
}

pub fn normalize_title(raw: &str) -> String {
  use unicode_normalization::UnicodeNormalization;
  raw
    .nfkc()
    .collect::<String>()
    .split_whitespace()
    .collect::<Vec<_>>()
    .join(" ")
    .to_lowercase()
}

#[cfg(test)]
mod tests {
  use std::collections::HashMap;

  use collab_document::blocks::{Block, DocumentMeta};
  use serde_json::json;

  use super::*;

  /// 构造一个最小的 DocumentData：根页 + 若干块，每块的 delta 以 JSON 字符串挂在 text_map。
  fn doc(
    page_id: &str,
    blocks: Vec<(&str, &str, &str)>,
    deltas: Vec<(&str, Value)>,
  ) -> DocumentData {
    let mut block_map = HashMap::new();
    let mut children = Vec::new();
    for (id, ty, _text) in &blocks {
      block_map.insert(
        id.to_string(),
        Block {
          id: id.to_string(),
          ty: ty.to_string(),
          parent: page_id.to_string(),
          children: format!("{}-children", id),
          external_id: None,
          external_type: None,
          data: HashMap::new(),
        },
      );
      children.push(id.to_string());
    }

    let mut text_map = HashMap::new();
    for (id, delta) in deltas {
      text_map.insert(id.to_string(), delta.to_string());
    }

    let mut children_map = HashMap::new();
    children_map.insert(page_id.to_string(), children);

    DocumentData {
      page_id: page_id.to_string(),
      blocks: block_map,
      meta: DocumentMeta {
        children_map,
        text_map: Some(text_map),
      },
    }
  }

  #[test]
  fn real_root_children_and_repeated_references_are_indexed_once() {
    let mut d = doc(
      "root",
      vec![("b1", "paragraph", "")],
      vec![(
        "b1",
        json!([
          {"insert":"$", "attributes":{"mention":{"type":"page", "page_id":"target", "block_id":"target-block"}}},
          {"insert":"$", "attributes":{"mention":{"type":"page", "page_id":"target", "block_id":"target-block"}}},
          {"insert":" [[ＡＢＣ]] [[ABC]]"}
        ]),
      )],
    );
    let children = d.meta.children_map.remove("root").unwrap();
    d.meta.children_map.insert("root-children".into(), children);
    d.blocks.insert(
      "root".into(),
      Block {
        id: "root".into(),
        ty: "page".into(),
        parent: String::new(),
        children: "root-children".into(),
        external_id: None,
        external_type: None,
        data: HashMap::new(),
      },
    );
    let out = extract_links(&d);
    assert_eq!(out.edges.len(), 1);
    assert_eq!(out.edges[0].occurrence, 2);
    assert_eq!(out.edges[0].dst_block_id.as_deref(), Some("target-block"));
    assert_eq!(out.edges[0].kind, LinkKind::BlockRef);
    assert_eq!(out.unresolved.len(), 1);
    assert_eq!(out.unresolved[0].normalized_title, "abc");
  }

  #[test]
  fn non_link_attributes_are_ignored_and_internal_urls_are_strict() {
    let mut d = doc(
      "root",
      vec![("b1", "paragraph", "")],
      vec![(
        "b1",
        json!([
          {"insert":"$", "attributes":{"mention":{"type":"user", "page_id":"fake"}}},
          {"insert":"external", "attributes":{"href":"https://evil.example/share?viewId=fake"}},
          {"insert":"internal", "attributes":{"href":"ponynotes://open?viewId=target&blockId=block"}}
        ]),
      )],
    );
    d.blocks
      .get_mut("b1")
      .unwrap()
      .data
      .insert("view_id".into(), json!("not-a-link"));
    let out = extract_links(&d);
    assert_eq!(out.edges.len(), 1);
    assert_eq!(out.edges[0].dst_page_id, "target");
    assert_eq!(out.edges[0].dst_block_id.as_deref(), Some("block"));
  }

  #[test]
  fn extract_inline_page_mention() {
    let d = doc(
      "p1",
      vec![("b1", "paragraph", "")],
      vec![(
        "b1",
        json!([
          {"insert": "见 "},
          {"insert": "$", "attributes": {"mention": {"type": "page", "page_id": "p2"}}},
          {"insert": " 那篇"}
        ]),
      )],
    );

    let out = extract_links(&d);
    assert_eq!(out.edges.len(), 1);
    let edge = &out.edges[0];
    assert_eq!(edge.dst_page_id, "p2");
    assert_eq!(edge.kind, LinkKind::Reference);
    // "见 " 占两个字符，提及落在偏移 2
    assert_eq!(edge.char_offset, 2);
    assert_eq!(edge.occurrence, 1);
  }

  #[test]
  fn char_offset_counts_characters_not_bytes() {
    // 中文前缀：若按字节算偏移会变成 9，导致跳转落到块中间
    let d = doc(
      "p1",
      vec![("b1", "paragraph", "")],
      vec![(
        "b1",
        json!([
          {"insert": "参考链接： "},
          {"insert": "$", "attributes": {"mention": {"type": "page", "page_id": "p2"}}}
        ]),
      )],
    );

    let out = extract_links(&d);
    assert_eq!(out.edges[0].char_offset, 6, "五个汉字加一个空格");
  }

  #[test]
  fn extract_block_level_mention() {
    let mut d = doc("p1", vec![("b1", "sub_page", "")], vec![]);
    d.blocks
      .get_mut("b1")
      .unwrap()
      .data
      .insert("view_id".to_string(), json!("p_child"));

    let out = extract_links(&d);
    assert_eq!(out.edges.len(), 1);
    assert_eq!(out.edges[0].dst_page_id, "p_child");
    assert_eq!(out.edges[0].kind, LinkKind::Embed);
    assert_eq!(out.edges[0].char_offset, 0);
  }

  #[test]
  fn skip_mention_without_page_id() {
    let d = doc(
      "p1",
      vec![("b1", "paragraph", "")],
      vec![(
        "b1",
        json!([{"insert": "$", "attributes": {"mention": {"type": "page"}}}]),
      )],
    );
    assert!(extract_links(&d).edges.is_empty(), "缺目标不应产出半条边");
  }

  #[test]
  fn scan_wikilink_plain_and_alias() {
    let found = scan_wikilinks("看 [[双向链接]] 和 [[图谱|关系图]]");
    assert_eq!(found.len(), 2);
    assert_eq!(found[0].title, "双向链接");
    assert_eq!(found[0].start, 2);
    // 别名只取竖线左边
    assert_eq!(found[1].title, "图谱");
  }

  #[test]
  fn scan_wikilink_rejects_malformed() {
    // 未闭合、跨行、内部含方括号都不是合法链接
    assert!(scan_wikilinks("[[未闭合").is_empty());
    assert!(scan_wikilinks("[[跨\n行]]").is_empty());
    assert!(scan_wikilinks("[[a] 与 [b]]").is_empty());
    assert!(scan_wikilinks("[[]]").is_empty(), "空标题不产生候选");
  }

  #[test]
  fn wikilink_becomes_unresolved_candidate_with_offset() {
    let d = doc(
      "p1",
      vec![("b1", "paragraph", "")],
      vec![("b1", json!([{"insert": "另见 [[未来页]]"}]))],
    );

    let out = extract_links(&d);
    assert_eq!(out.unresolved.len(), 1);
    assert_eq!(out.unresolved[0].normalized_title, "未来页");
    assert_eq!(out.unresolved[0].raw_title, "未来页");
    assert_eq!(out.unresolved[0].char_offset, 3);
  }

  #[test]
  fn walk_order_follows_children_map_not_hashmap() {
    // 三个块在 blocks 里是 HashMap，但 children_map 决定了顺序
    let d = doc(
      "p1",
      vec![
        ("b3", "paragraph", ""),
        ("b1", "paragraph", ""),
        ("b2", "paragraph", ""),
      ],
      vec![
        (
          "b1",
          json!([{"insert": "$", "attributes": {"mention": {"type": "page", "page_id": "p_b1"}}}]),
        ),
        (
          "b2",
          json!([{"insert": "$", "attributes": {"mention": {"type": "page", "page_id": "p_b2"}}}]),
        ),
        (
          "b3",
          json!([{"insert": "$", "attributes": {"mention": {"type": "page", "page_id": "p_b3"}}}]),
        ),
      ],
    );

    let out = extract_links(&d);
    let order: Vec<&str> = out.edges.iter().map(|e| e.dst_page_id.as_str()).collect();
    // doc() 里 children 按传入顺序：b3, b1, b2
    assert_eq!(order, vec!["p_b3", "p_b1", "p_b2"]);
  }

  #[test]
  fn missing_block_reference_does_not_panic() {
    let mut d = doc("p1", vec![], vec![]);
    d.meta
      .children_map
      .insert("p1".to_string(), vec!["ghost".to_string()]);
    // children_map 指向不存在的块，应跳过而不是 panic
    assert!(extract_links(&d).edges.is_empty());
  }

  #[test]
  fn cycle_does_not_hang() {
    let mut d = doc(
      "p1",
      vec![("b1", "paragraph", ""), ("b2", "paragraph", "")],
      vec![],
    );
    // 人为制造环：b1 的 children 指向 b2 的 children 容器，反之亦然
    d.meta
      .children_map
      .insert("b1-children".to_string(), vec!["b2".to_string()]);
    d.meta
      .children_map
      .insert("b2-children".to_string(), vec!["b1".to_string()]);

    // 能在有限时间返回即算通过
    let out = extract_links(&d);
    assert!(out.edges.is_empty());
  }

  #[test]
  fn normalize_title_collapses_and_lowercases() {
    assert_eq!(normalize_title("  Rust   Ownership  "), "rust ownership");
    assert_eq!(normalize_title("双向  链接"), "双向 链接");
  }
}

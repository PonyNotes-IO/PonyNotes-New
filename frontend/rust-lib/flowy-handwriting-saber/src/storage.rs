//! Entity records overlay an immutable legacy snapshot. Flat keys share the existing
//! Y.Map, so concurrent upgrades never create competing nested shared types.
use anyhow::{anyhow, bail, Result};
use serde_json::{json, Map, Value};
use std::collections::{BTreeMap, BTreeSet};
use uuid::Uuid;

pub const PREFIX: &str = "hw2:";
const COLLECTIONS: &[&str] = &[
  "strokes",
  "images",
  "webViews",
  "textBoxes",
  "listBoxes",
  "taskListBoxes",
];
const RANK: &str = "_syncOrder";

pub type Records = BTreeMap<String, Value>;

fn key(parts: &[&str]) -> String {
  format!("{}{}", PREFIX, serde_json::to_string(parts).unwrap())
}

fn legacy_id(scope: &str, index: usize) -> String {
  Uuid::new_v5(&Uuid::NAMESPACE_OID, format!("{scope}/{index}").as_bytes()).to_string()
}

fn object(value: &Value) -> Result<&Map<String, Value>> {
  value
    .as_object()
    .ok_or_else(|| anyhow!("Expected handwriting object"))
}

fn array<'a>(value: &'a Map<String, Value>, field: &str) -> Result<&'a [Value]> {
  match value.get(field) {
    Some(Value::Array(items)) => Ok(items),
    None => Ok(&[]),
    _ => bail!("Invalid handwriting collection: {field}"),
  }
}

fn numeric_legacy_id(scope: &str, index: usize) -> i64 {
  let uuid = legacy_id(scope, index).replace('-', "");
  i64::from_str_radix(&uuid[..13], 16).unwrap()
}

fn identity(value: &Map<String, Value>, scope: &str, index: usize, numeric: bool) -> String {
  match value.get("id") {
    Some(Value::String(id)) if !id.is_empty() => id.clone(),
    Some(Value::Number(id)) => format!("integer:{id}"),
    _ if numeric => format!("integer:{}", numeric_legacy_id(scope, index)),
    _ => legacy_id(scope, index),
  }
}

/// Canonicalize only the storage identity/order; keep every original content field.
/// `base` is the exact snapshot the editor saw, not the current merged document.
pub fn flatten(bytes: &[u8], scope: &str, base: Option<&Records>) -> Result<Records> {
  if bytes.is_empty() {
    return Ok(Records::new());
  }
  let value: Value = serde_json::from_slice(bytes)?;
  let doc = object(&value)?;
  if !doc.contains_key("pages") {
    bail!("Handwriting pages missing");
  }
  let mut records = Records::new();
  for (field, value) in doc {
    if field != "pages" && field != "_syncHistory" {
      records.insert(key(&["doc", field]), value.clone());
    }
  }
  for entry in array(doc, "_syncHistory")? {
    let record = entry
      .as_str()
      .ok_or_else(|| anyhow!("Invalid deletion history"))?;
    let parts: Vec<String> = serde_json::from_str(
      record
        .strip_prefix(PREFIX)
        .ok_or_else(|| anyhow!("Invalid deletion record"))?,
    )?;
    if parts.len() != 4 || !["deleted", "restored"].contains(&parts[0].as_str()) {
      bail!("Invalid deletion record");
    }
    records.insert(record.to_owned(), json!(true));
  }
  if let Some(base) = base {
    for (record, value) in base {
      if is_history(record) {
        records.entry(record.clone()).or_insert(value.clone());
      }
    }
  }
  let pages = array(doc, "pages")?;
  let page_ids: Vec<_> = pages
    .iter()
    .enumerate()
    .map(|(i, page)| Ok(identity(object(page)?, &format!("{scope}/pages"), i, false)))
    .collect::<Result<_>>()?;
  let page_ranks = ranks(&page_ids, "pages", base, pages)?;
  let mut seen = BTreeSet::new();
  for (i, page) in pages.iter().enumerate() {
    let page = object(page)?;
    let id = &page_ids[i];
    if !seen.insert(("pages".to_owned(), id.clone())) {
      bail!("Duplicate page ID");
    }
    records.insert(key(&["pages", id, "@exists"]), json!(true));
    records.insert(key(&["pages", id, RANK]), json!(page_ranks[i]));
    for (field, value) in page {
      if field != "id" && field != RANK && !COLLECTIONS.contains(&field.as_str()) {
        if field == "backgroundImage" && value.is_object() {
          records.insert(key(&["pages", id, field]), json!({}));
          for (property, value) in value.as_object().unwrap() {
            records.insert(key(&["pages", id, field, property]), value.clone());
          }
        } else {
          records.insert(key(&["pages", id, field]), value.clone());
        }
      }
    }
    for &kind in COLLECTIONS {
      let items = array(page, kind)?;
      let ids: Vec<_> = items
        .iter()
        .enumerate()
        .map(|(n, item)| {
          Ok(identity(
            object(item)?,
            &format!("{scope}/pages/{i}/{kind}"),
            n,
            kind == "webViews",
          ))
        })
        .collect::<Result<_>>()?;
      let item_ranks = ranks(&ids, kind, base, items)?;
      for (n, item) in items.iter().enumerate() {
        let item = object(item)?;
        let item_id = &ids[n];
        if !seen.insert((kind.to_owned(), item_id.clone())) {
          bail!("Duplicate {kind} ID: {item_id}");
        }
        if let Some(value @ Value::Number(_)) = item.get("id") {
          records.insert(key(&[kind, item_id, "@id"]), value.clone());
        } else if kind == "webViews" && !item.contains_key("id") {
          records.insert(
            key(&[kind, item_id, "@id"]),
            json!(numeric_legacy_id(&format!("{scope}/pages/{i}/{kind}"), n)),
          );
        }
        records.insert(key(&[kind, item_id, "@exists"]), json!(true));
        records.insert(key(&[kind, item_id, "@page"]), json!(id));
        records.insert(key(&[kind, item_id, RANK]), json!(item_ranks[n]));
        for (field, value) in item {
          if field != "id" && field != RANK {
            records.insert(key(&[kind, item_id, field]), value.clone());
          }
        }
      }
    }
  }
  Ok(records)
}

// Preserve the longest increasing run of existing positions. Only inserted/moved
// entities receive new fractional keys; inserting a page never renumbers its peers.
fn ranks(
  ids: &[String],
  kind: &str,
  base: Option<&Records>,
  items: &[Value],
) -> Result<Vec<String>> {
  let Some(base) = base else {
    return Ok(
      (0..ids.len())
        .map(|i| {
          items[i]
            .get(RANK)
            .and_then(Value::as_str)
            .map(str::to_owned)
            .unwrap_or_else(|| format!("{:016x}8", (i as u64 + 1) * 1024))
        })
        .collect(),
    );
  };
  let old: Vec<Option<String>> = ids
    .iter()
    .map(|id| {
      base
        .get(&key(&[kind, id, RANK]))
        .and_then(Value::as_str)
        .map(str::to_owned)
    })
    .collect();
  let mut tails: Vec<usize> = Vec::new();
  let mut previous = vec![None; ids.len()];
  for (i, rank) in old.iter().enumerate() {
    if let Some(rank) = rank {
      let pos = tails.partition_point(|&j| old[j].as_ref().unwrap() < rank);
      if pos > 0 {
        previous[i] = Some(tails[pos - 1]);
      }
      if pos == tails.len() {
        tails.push(i);
      } else {
        tails[pos] = i;
      }
    }
  }
  let mut anchors = BTreeSet::new();
  let mut cursor = tails.last().copied();
  while let Some(i) = cursor {
    anchors.insert(i);
    cursor = previous[i];
  }
  let mut output = Vec::with_capacity(ids.len());
  for i in 0..ids.len() {
    if anchors.contains(&i) {
      output.push(old[i].clone().unwrap());
    } else {
      let next = anchors
        .range((i + 1)..)
        .next()
        .and_then(|&j| old[j].as_deref());
      output.push(between(output.last().map(String::as_str), next)?);
    }
  }
  Ok(output)
}

fn between(lower: Option<&str>, upper: Option<&str>) -> Result<String> {
  if let (Some(a), Some(b)) = (lower, upper) {
    if a >= b {
      bail!("Invalid handwriting ordering");
    }
  }
  let lower = lower.unwrap_or("").as_bytes();
  let mut upper = upper.map(str::as_bytes);
  let mut result = String::new();
  for i in 0..1024 {
    let a = lower
      .get(i)
      .map(|c| (*c as char).to_digit(16))
      .unwrap_or(Some(0))
      .ok_or_else(|| anyhow!("Invalid order key"))?;
    let b = upper
      .and_then(|s| s.get(i))
      .map(|c| (*c as char).to_digit(16))
      .unwrap_or(Some(16))
      .ok_or_else(|| anyhow!("Invalid order key"))?;
    if b > a + 1 {
      result.push(char::from_digit((a + b) / 2, 16).unwrap());
      return Ok(result);
    }
    result.push(char::from_digit(a, 16).unwrap());
    if b > a {
      upper = None;
    }
  }
  bail!("Handwriting order key exhausted")
}

/// Only explicit local differences are written. Missing fields are preserved for
/// forward compatibility; removals from entity collections become durable tombstones.
fn is_history(record: &str) -> bool {
  record.starts_with("hw2:[\"deleted\",") || record.starts_with("hw2:[\"restored\",")
}

pub fn changes(base: &Records, next: &Records) -> Result<Records> {
  let mut edits = Records::new();
  for (record, value) in next {
    if base.get(record) != Some(value) {
      edits.insert(record.clone(), value.clone());
    }
    let parts: Vec<String> = serde_json::from_str(&record[PREFIX.len()..])?;
    // An explicit add after observing a deletion restores that incarnation only.
    // A stale modification cannot revive it, nor cancel a later unseen deletion.
    if parts.len() == 3 && parts[2] == "@exists" && !base.contains_key(record) {
      for history in base.keys().filter(|k| is_history(k)) {
        let deleted: Vec<String> = serde_json::from_str(&history[PREFIX.len()..])?;
        if deleted[0] == "deleted" && deleted[1] == parts[0] && deleted[2] == parts[1] {
          edits.insert(
            key(&["restored", &parts[0], &parts[1], &deleted[3]]),
            json!(true),
          );
        }
      }
    }
  }
  for record in base.keys().filter(|k| !next.contains_key(*k)) {
    let parts: Vec<String> = serde_json::from_str(&record[PREFIX.len()..])?;
    if parts.len() == 3 && parts[2] == "@exists" {
      let history: Vec<_> = base.keys().filter(|k| is_history(k)).collect();
      let token = Uuid::new_v5(
        &Uuid::NAMESPACE_OID,
        format!("{record}:{history:?}").as_bytes(),
      )
      .to_string();
      edits.insert(key(&["deleted", &parts[0], &parts[1], &token]), json!(true));
    }
  }
  Ok(edits)
}

pub fn project(records: &Records) -> Result<Vec<u8>> {
  if records.is_empty() {
    return Ok(Vec::new());
  }
  let mut doc = Map::new();
  let mut entities: BTreeMap<(String, String), Map<String, Value>> = BTreeMap::new();
  let mut backgrounds: BTreeMap<String, Map<String, Value>> = BTreeMap::new();
  let mut deleted = BTreeSet::new();
  let mut history = Vec::new();
  for (record, value) in records {
    let parts: Vec<String> = serde_json::from_str(&record[PREFIX.len()..])?;
    match parts.as_slice() {
      [kind, field] if kind == "doc" => {
        doc.insert(field.clone(), value.clone());
      },
      [kind, collection, id, token] if kind == "deleted" || kind == "restored" => {
        history.push(json!(record));
        if kind == "deleted" && !records.contains_key(&key(&["restored", collection, id, token])) {
          deleted.insert((collection.clone(), id.clone()));
        }
      },
      [kind, id, field, property] if kind == "pages" && field == "backgroundImage" => {
        backgrounds
          .entry(id.clone())
          .or_default()
          .insert(property.clone(), value.clone());
      },
      [kind, id, field] => {
        entities
          .entry((kind.clone(), id.clone()))
          .or_default()
          .insert(field.clone(), value.clone());
      },
      _ => bail!("Invalid handwriting record"),
    }
  }
  for (id, properties) in backgrounds {
    if let Some(fields) = entities.get_mut(&("pages".into(), id)) {
      if let Some(Value::Object(background)) = fields.get_mut("backgroundImage") {
        background.extend(properties);
      }
    }
  }
  let mut grouped: BTreeMap<(String, String), Vec<Value>> = BTreeMap::new();
  for ((kind, id), fields) in &entities {
    if kind == "pages" || deleted.contains(&(kind.clone(), id.clone())) {
      continue;
    }
    let Some(page_id) = fields.get("@page").and_then(Value::as_str) else {
      continue;
    };
    let mut item = fields.clone();
    item.remove("@exists");
    item.remove("@page");
    let original_id = item.remove("@id").unwrap_or_else(|| json!(id));
    item.insert("id".into(), original_id);
    grouped
      .entry((page_id.to_owned(), kind.clone()))
      .or_default()
      .push(Value::Object(item));
  }
  let mut pages = Vec::new();
  for ((kind, id), fields) in &entities {
    if kind != "pages" || deleted.contains(&(kind.clone(), id.clone())) {
      continue;
    }
    let mut page = fields.clone();
    page.remove("@exists");
    page.insert("id".into(), json!(id));
    for &collection in COLLECTIONS {
      let mut items = grouped
        .remove(&(id.clone(), collection.to_owned()))
        .unwrap_or_default();
      sort(&mut items);
      page.insert(collection.to_owned(), Value::Array(items));
    }
    pages.push(Value::Object(page));
  }
  sort(&mut pages);
  doc.insert("pages".into(), Value::Array(pages));
  if !history.is_empty() {
    doc.insert("_syncHistory".into(), Value::Array(history));
  }
  Ok(serde_json::to_vec(&doc)?)
}

fn sort(items: &mut [Value]) {
  items.sort_by(|a, b| {
    a[RANK]
      .as_str()
      .cmp(&b[RANK].as_str())
      .then_with(|| a["id"].as_str().cmp(&b["id"].as_str()))
  });
}

#[cfg(test)]
mod tests {
  use super::*;

  fn doc() -> Vec<u8> {
    serde_json::to_vec(
      &json!({"future": {"keep": 1}, "pages": [{"width":595,"height":842,
      "backgroundImage":{"pdfFilePath":"/offline.pdf","pdfPageIndex":3,"pdfUrl":null},
      "strokes":[{"points":[{"x":1,"y":2}],"shape":"circle","futureStroke":123}],
      "images":[{"id":"img","imageBase64":"aW1hZ2U=","imageUrl":null}],
      "quill":{"document":[{"insert":"hello","attributes":{"bold":true}}]},
      "webViews":[{"id":42,"url":"https://example.com"}]}]}),
    )
    .unwrap()
  }

  #[test]
  fn legacy_content_and_unknown_fields_roundtrip_without_rewriting_source() {
    let bytes = doc();
    let records = flatten(&bytes, "note", None).unwrap();
    let projected = project(&records).unwrap();
    let original: Value = serde_json::from_slice(&bytes).unwrap();
    let actual: Value = serde_json::from_slice(&projected).unwrap();
    assert_eq!(actual["future"], original["future"]);
    for field in ["backgroundImage", "quill", "width", "height"] {
      assert_eq!(actual["pages"][0][field], original["pages"][0][field]);
    }
    for kind in ["strokes", "images", "webViews"] {
      for (field, value) in original["pages"][0][kind][0].as_object().unwrap() {
        assert_eq!(&actual["pages"][0][kind][0][field], value);
      }
    }
    assert_eq!(records, flatten(&projected, "note", None).unwrap());
    assert_eq!(records, flatten(&bytes, "note", None).unwrap());
  }

  #[test]
  fn stale_snapshots_change_only_local_entities_and_tombstones_win() {
    let base = flatten(&doc(), "note", None).unwrap();
    let mut a: Value = serde_json::from_slice(&project(&base).unwrap()).unwrap();
    let mut b = a.clone();
    a["pages"][0]["strokes"]
      .as_array_mut()
      .unwrap()
      .push(json!({"id":"a","points":[{"x":9,"y":9}]}));
    b["pages"][0]["strokes"]
      .as_array_mut()
      .unwrap()
      .push(json!({"id":"b","points":[{"x":8,"y":8}]}));
    let mut merged = base.clone();
    merged.extend(
      changes(
        &base,
        &flatten(&serde_json::to_vec(&a).unwrap(), "note", Some(&base)).unwrap(),
      )
      .unwrap(),
    );
    merged.extend(
      changes(
        &base,
        &flatten(&serde_json::to_vec(&b).unwrap(), "note", Some(&base)).unwrap(),
      )
      .unwrap(),
    );
    let out: Value = serde_json::from_slice(&project(&merged).unwrap()).unwrap();
    assert_eq!(out["pages"][0]["strokes"].as_array().unwrap().len(), 3);
    a["pages"][0]["strokes"].as_array_mut().unwrap().remove(0);
    merged.extend(
      changes(
        &base,
        &flatten(&serde_json::to_vec(&a).unwrap(), "note", Some(&base)).unwrap(),
      )
      .unwrap(),
    );
    let out: Value = serde_json::from_slice(&project(&merged).unwrap()).unwrap();
    assert_eq!(out["pages"][0]["strokes"].as_array().unwrap().len(), 2);
  }

  #[test]
  fn insertion_and_reordering_leave_unaffected_positions_alone() {
    let bytes = serde_json::to_vec(&json!({"pages":[{"id":"a"},{"id":"b"},{"id":"c"}]})).unwrap();
    let base = flatten(&bytes, "note", None).unwrap();
    let next = flatten(
      br#"{"pages":[{"id":"a"},{"id":"new"},{"id":"b"},{"id":"c"}]}"#,
      "note",
      Some(&base),
    )
    .unwrap();
    for id in ["a", "b", "c"] {
      assert_eq!(
        next[&key(&["pages", id, RANK])],
        base[&key(&["pages", id, RANK])]
      );
    }
    let reordered = flatten(
      br#"{"pages":[{"id":"c"},{"id":"a"},{"id":"b"}]}"#,
      "note",
      Some(&base),
    )
    .unwrap();
    let out: Value = serde_json::from_slice(&project(&reordered).unwrap()).unwrap();
    assert_eq!(
      out["pages"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v["id"].as_str().unwrap())
        .collect::<Vec<_>>(),
      vec!["c", "a", "b"]
    );
  }

  #[test]
  fn invalid_data_is_rejected_instead_of_becoming_empty() {
    for data in [
      br#"{}"#.as_slice(),
      br#"{"pages":[null]}"#,
      br#"{"pages":123}"#,
      br#"{"pages":[{"strokes":[1]}]}"#,
    ] {
      assert!(flatten(data, "note", None).is_err());
    }
  }
}

#[cfg(test)]
mod merge_tests {
  use super::*;

  #[test]
  fn observed_undo_restores_without_cancelling_future_deletions() {
    let original = flatten(
      br#"{"pages":[{"id":"page","strokes":[{"id":"stroke","points":[]}]}]}"#,
      "test",
      None,
    )
    .unwrap();
    let removed = flatten(
      br#"{"pages":[{"id":"page","strokes":[]}]}"#,
      "test",
      Some(&original),
    )
    .unwrap();
    let first_delete = changes(&original, &removed).unwrap();
    let mut current = original.clone();
    current.extend(first_delete);
    let observed = flatten(&project(&current).unwrap(), "test", None).unwrap();
    let restored = flatten(
      br#"{"pages":[{"id":"page","strokes":[{"id":"stroke","points":[]}]}]}"#,
      "test",
      Some(&observed),
    )
    .unwrap();
    current.extend(changes(&observed, &restored).unwrap());
    let out: Value = serde_json::from_slice(&project(&current).unwrap()).unwrap();
    assert_eq!(out["pages"][0]["strokes"].as_array().unwrap().len(), 1);
    let observed = flatten(&project(&current).unwrap(), "test", None).unwrap();
    let removed = flatten(
      br#"{"pages":[{"id":"page","strokes":[]}]}"#,
      "test",
      Some(&observed),
    )
    .unwrap();
    current.extend(changes(&observed, &removed).unwrap());
    let out: Value = serde_json::from_slice(&project(&current).unwrap()).unwrap();
    assert!(out["pages"][0]["strokes"].as_array().unwrap().is_empty());
  }

  #[test]
  fn unknown_fields_survive_an_editor_that_does_not_serialize_them() {
    let base = flatten(
      br#"{"future":true,"pages":[{"id":"page","width":595,"futurePage":1}]}"#,
      "test",
      None,
    )
    .unwrap();
    let next = flatten(
      br#"{"pages":[{"id":"page","width":600}]}"#,
      "test",
      Some(&base),
    )
    .unwrap();
    let mut current = base.clone();
    current.extend(changes(&base, &next).unwrap());
    let out: Value = serde_json::from_slice(&project(&current).unwrap()).unwrap();
    assert_eq!(out["future"], true);
    assert_eq!(out["pages"][0]["futurePage"], 1);
    assert_eq!(out["pages"][0]["width"], 600);
  }
}

#[cfg(test)]
mod attachment_merge_tests {
  use super::*;

  #[test]
  fn upload_reference_does_not_overwrite_a_concurrent_pdf_transform() {
    let original = br#"{"pages":[{"id":"p","backgroundImage":{"pdfFilePath":"/original.pdf","pdfPageIndex":2,"dstRect":{"left":0},"future":123}}]}"#;
    let base = flatten(original, "note", None).unwrap();
    let mut upload: Value = serde_json::from_slice(&project(&base).unwrap()).unwrap();
    let mut transform = upload.clone();
    upload["pages"][0]["backgroundImage"]["pdfUrl"] = json!("https://cloud/file.pdf");
    transform["pages"][0]["backgroundImage"]["dstRect"] = json!({"left":10});
    let mut merged = base.clone();
    for snapshot in [upload, transform] {
      let next = flatten(&serde_json::to_vec(&snapshot).unwrap(), "note", Some(&base)).unwrap();
      merged.extend(changes(&base, &next).unwrap());
    }
    let result: Value = serde_json::from_slice(&project(&merged).unwrap()).unwrap();
    let background = &result["pages"][0]["backgroundImage"];
    assert_eq!(background["pdfUrl"], "https://cloud/file.pdf");
    assert_eq!(background["dstRect"]["left"], 10);
    assert_eq!(background["future"], 123);
    let cleared = flatten(
      br#"{"pages":[{"id":"p","backgroundImage":null}]}"#,
      "note",
      Some(&merged),
    )
    .unwrap();
    let edits = changes(&merged, &cleared).unwrap();
    merged.extend(edits);
    let cleared: Value = serde_json::from_slice(&project(&merged).unwrap()).unwrap();
    assert!(cleared["pages"][0]["backgroundImage"].is_null());
  }
}

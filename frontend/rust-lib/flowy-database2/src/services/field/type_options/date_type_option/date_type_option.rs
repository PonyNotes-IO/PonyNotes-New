use std::cmp::Ordering;

use async_trait::async_trait;
use bytes::Bytes;
use collab::util::AnyMapExt;
use collab_database::database::Database;
use collab_database::fields::date_type_option::{DateCellData, DateTypeOption};
use collab_database::fields::{Field, TypeOptionData};
use collab_database::rows::{Cell, new_cell_builder};
use collab_database::template::date_parse::cast_string_to_timestamp;
use flowy_error::FlowyResult;
use tracing::info;

use crate::entities::{DateCellDataPB, DateFilterPB, FieldType};
use crate::services::cell::{CellDataChangeset, CellDataDecoder};
use crate::services::field::date_type_option::date_filter::DateCellChangeset;
use crate::services::field::{
  CELL_DATA, CellDataProtobufEncoder, TypeOption, TypeOptionCellDataCompare,
  TypeOptionCellDataFilter, TypeOptionTransform, default_order,
};
use crate::services::sort::SortCondition;

impl TypeOption for DateTypeOption {
  type CellData = DateCellData;
  type CellChangeset = DateCellChangeset;
  type CellProtobufType = DateCellDataPB;
  type CellFilter = DateFilterPB;
}

impl CellDataProtobufEncoder for DateTypeOption {
  fn protobuf_encode(
    &self,
    cell_data: <Self as TypeOption>::CellData,
  ) -> <Self as TypeOption>::CellProtobufType {
    let include_time = cell_data.include_time;
    let is_range = cell_data.is_range;

    let timestamp = cell_data.timestamp;
    let end_timestamp = if is_range {
      cell_data.end_timestamp.or(timestamp)
    } else {
      None
    };

    let reminder_id = cell_data.reminder_id;

    // 创建 DateCellDataPB，确保 repeat_type 和 repeat_rule_json 总是被设置为 Some
    // 即使值是默认值（0 或空字符串），也要设置为 Some，确保字段被序列化
    DateCellDataPB {
      timestamp,
      end_timestamp,
      include_time,
      is_range,
      reminder_id,
      repeat_type: Some(cell_data.repeat_type),
      repeat_rule_json: Some(cell_data.repeat_rule_json.clone()),
    }
  }
}

#[async_trait]
impl TypeOptionTransform for DateTypeOption {
  async fn transform_type_option(
    &mut self,
    view_id: &str,
    field_id: &str,
    old_type_option_field_type: FieldType,
    _old_type_option_data: TypeOptionData,
    _new_type_option_field_type: FieldType,
    database: &mut Database,
  ) {
    match old_type_option_field_type {
      FieldType::RichText => {
        let rows = database
          .get_cells_for_field(view_id, field_id)
          .await
          .into_iter()
          .filter_map(|row| row.cell.map(|cell| (row.row_id, cell)))
          .collect::<Vec<_>>();

        info!(
          "Transforming RichText to DateTypeOption, updating {} row's cell content",
          rows.len()
        );
        for (row_id, cell_data) in rows {
          if let Some(cell_data) = cell_data
            .get_as::<String>(CELL_DATA)
            .and_then(|s| cast_string_to_timestamp(&s))
            .map(DateCellData::from_timestamp)
          {
            database
              .update_row(row_id, |row| {
                row.update_cells(|cell| {
                  cell.insert(field_id, Cell::from(&cell_data));
                });
              })
              .await;
          }
        }
      },
      _ => {
        // do nothing
      },
    }
  }
}

impl DateTypeOption {
  /// 从 Cell 中解码 DateCellData（公共逻辑）
  fn decode_cell_internal(cell: &Cell) -> Option<DateCellData> {
    // 优先尝试从 protobuf 字节中读取完整数据
    if let Some(bytes_vec) = cell.get_as::<Vec<u8>>(CELL_DATA) {
      let bytes = Bytes::from(bytes_vec);
      if let Ok(pb) = DateCellDataPB::try_from(bytes.as_ref()) {
        return Some(DateCellData::from(&pb));
      }
    }
    
    // 回退到字符串解析方式（向后兼容）
    let s = cell.get_as::<String>(CELL_DATA)?;
    let timestamp = cast_string_to_timestamp(&s)?;
    Some(DateCellData::from_timestamp(timestamp))
  }
}

impl CellDataDecoder for DateTypeOption {
  fn decode_cell(&self, cell: &Cell) -> FlowyResult<<Self as TypeOption>::CellData> {
    Self::decode_cell_internal(cell)
      .ok_or_else(|| {
        flowy_error::FlowyError::internal().with_context("无法从 Cell 读取数据")
      })
  }

  fn stringify_cell_data(&self, cell_data: <Self as TypeOption>::CellData) -> String {
    let include_time = cell_data.include_time;
    let timestamp = cell_data.timestamp;
    let is_range = cell_data.is_range;

    let (date, time) = self.formatted_date_time_from_timestamp(&timestamp);

    if is_range {
      let (end_date, end_time) = match cell_data.end_timestamp {
        Some(timestamp) => self.formatted_date_time_from_timestamp(&Some(timestamp)),
        None => (date.clone(), time.clone()),
      };
      if include_time && timestamp.is_some() {
        format!("{} {} → {} {}", date, time, end_date, end_time)
          .trim()
          .to_string()
      } else if timestamp.is_some() {
        format!("{} → {}", date, end_date).trim().to_string()
      } else {
        "".to_string()
      }
    } else if include_time {
      format!("{} {}", date, time).trim().to_string()
    } else {
      date
    }
  }

  fn decode_cell_with_transform(
    &self,
    cell: &Cell,
    _from_field_type: FieldType,
    _field: &Field,
  ) -> Option<<Self as TypeOption>::CellData> {
    Self::decode_cell_internal(cell)
  }
}

impl CellDataChangeset for DateTypeOption {
  fn apply_changeset(
    &self,
    changeset: <Self as TypeOption>::CellChangeset,
    cell: Option<Cell>,
  ) -> FlowyResult<(Cell, <Self as TypeOption>::CellData)> {
    if let Some(true) = changeset.clear_flag {
      let cell_data = DateCellData::default();
      // 使用 protobuf 序列化，确保格式一致
      let pb = self.protobuf_encode(cell_data.clone());
      let pb_bytes: Bytes = pb.try_into().map_err(|e| {
        tracing::error!("❌ [DateTypeOption::apply_changeset] protobuf 序列化失败: {:?}", e);
        flowy_error::FlowyError::internal().with_context(format!("protobuf 序列化失败: {:?}", e))
      })?;
      // 将 Bytes 转换为 Vec<u8>，因为 Cell 的 insert 方法需要可以转换为 Any 的类型
      let pb_vec = pb_bytes.to_vec();
      let mut cell = new_cell_builder(FieldType::DateTime);
      cell.insert(CELL_DATA.into(), pb_vec.into());
      return Ok((cell, cell_data));
    }

    // old date cell data
    // 使用 decode_cell 来读取完整数据（包括 repeat_type 和 repeat_rule_json）
    let is_new_cell = cell.is_none();
    let cell_data = match cell {
      Some(cell) => self.decode_cell_with_transform(&cell, FieldType::DateTime, &Field::default()).unwrap_or_default(),
      None => DateCellData::default(),
    };

    let is_range = changeset.is_range.unwrap_or(cell_data.is_range);

    let has_timestamp = changeset.timestamp.is_some();
    let has_end_timestamp = changeset.end_timestamp.is_some();
    let unexpected_end_changeset = !is_range && has_end_timestamp;
    let missing_timestamp = is_range && has_timestamp != has_end_timestamp;

    // update include_time and reminder_id if necessary
    let include_time = changeset.include_time.unwrap_or(cell_data.include_time);
    let reminder_id = changeset.reminder_id.unwrap_or(cell_data.reminder_id);

    // 对于 repeat_type 和 repeat_rule_json 的处理：
    // 1. 如果是新创建的单元格（is_new_cell），即使 changeset 中为 None，也要使用默认值（0 和空字符串）
    //    因为首次创建时，如果 Protobuf 没有序列化这些字段（默认值），changeset 中会是 None
    // 2. 如果是更新现有单元格，changeset 中为 None 时使用旧值（保持现有值）
    let repeat_type = if is_new_cell {
      // 首次创建：如果 changeset 中有值就用，否则用默认值 0
      changeset.repeat_type.unwrap_or(0)
    } else {
      // 更新现有：如果 changeset 中有值就用，否则保持旧值
      changeset.repeat_type.unwrap_or(cell_data.repeat_type)
    };
    
    let repeat_rule_json = if is_new_cell {
      // 首次创建：如果 changeset 中有值就用，否则用默认值空字符串
      changeset.repeat_rule_json.clone().unwrap_or_else(|| String::new())
    } else {
      // 更新现有：如果 changeset 中有值就用，否则保持旧值
      changeset.repeat_rule_json.clone().unwrap_or_else(|| cell_data.repeat_rule_json.clone())
    };

    // Compute timestamp/end_timestamp with validation; if validation fails, keep previous values
    let (timestamp, end_timestamp) = if unexpected_end_changeset || missing_timestamp {
      (cell_data.timestamp, cell_data.end_timestamp)
    } else {
      let timestamp = changeset.timestamp.or(cell_data.timestamp);
      let end_timestamp = if is_range && timestamp.is_some() {
        changeset
          .end_timestamp
          .or(cell_data.end_timestamp)
          .or(timestamp)
      } else {
        None
      };
      (timestamp, end_timestamp)
    };

    let cell_data = DateCellData {
      timestamp,
      end_timestamp,
      include_time,
      is_range,
      reminder_id,
      repeat_type,
      repeat_rule_json,
    };

    // 使用 protobuf 序列化，确保格式一致
    let pb = self.protobuf_encode(cell_data.clone());
    let pb_bytes: Bytes = pb.try_into().map_err(|e| {
      tracing::error!("❌ [DateTypeOption::apply_changeset] protobuf 序列化失败: {:?}", e);
      flowy_error::FlowyError::internal().with_context(format!("protobuf 序列化失败: {:?}", e))
    })?;
    
    let mut cell = new_cell_builder(FieldType::DateTime);
    cell.insert(CELL_DATA.into(), pb_bytes.to_vec().into());

    Ok((cell, cell_data))
  }
}

impl TypeOptionCellDataFilter for DateTypeOption {
  fn apply_filter(
    &self,
    filter: &<Self as TypeOption>::CellFilter,
    cell_data: &<Self as TypeOption>::CellData,
  ) -> bool {
    filter.is_visible(cell_data).unwrap_or(true)
  }
}

impl TypeOptionCellDataCompare for DateTypeOption {
  fn apply_cmp(
    &self,
    cell_data: &<Self as TypeOption>::CellData,
    other_cell_data: &<Self as TypeOption>::CellData,
    sort_condition: SortCondition,
  ) -> Ordering {
    match (cell_data.timestamp, other_cell_data.timestamp) {
      (Some(left), Some(right)) => {
        let order = left.cmp(&right);
        sort_condition.evaluate_order(order)
      },
      (Some(_), None) => Ordering::Less,
      (None, Some(_)) => Ordering::Greater,
      (None, None) => default_order(),
    }
  }
}

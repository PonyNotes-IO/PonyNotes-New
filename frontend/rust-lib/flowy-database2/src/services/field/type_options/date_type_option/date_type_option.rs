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
    
    // 添加调试日志，确认编码时的值
    tracing::debug!(
      "📤 [DateTypeOption::protobuf_encode] 编码 DateCellData: repeat_type={}, repeat_rule_json={:?}",
      cell_data.repeat_type,
      cell_data.repeat_rule_json
    );

    // 创建 DateCellDataPB，确保 repeat_type 和 repeat_rule_json 总是被设置为 Some
    // 即使值是默认值（0 或空字符串），也要设置为 Some，这样 flowy-derive 生成的代码
    // 会调用 set_repeat_type 和 set_repeat_rule_json，确保字段被序列化
    let pb = DateCellDataPB {
      timestamp,
      end_timestamp,
      include_time,
      is_range,
      reminder_id,
      // 关键：总是设置为 Some，即使值是默认值
      // flowy-derive 生成的序列化代码会检查 Some，然后调用 set_repeat_type
      repeat_type: Some(cell_data.repeat_type),
      repeat_rule_json: Some(cell_data.repeat_rule_json.clone()),
    };

    tracing::debug!(
      "📤 [DateTypeOption::protobuf_encode] 编码结果: repeat_type={:?}, repeat_rule_json={:?}",
      pb.repeat_type,
      pb.repeat_rule_json
    );
    
    // 关键修复：Protobuf 在序列化 one_of 字段时，如果值是默认值（0 或空字符串），
    // 可能不会序列化该字段。我们需要在序列化之前，将 DateCellDataPB 转换为真正的 Protobuf 消息，
    // 然后显式调用 set_repeat_type 和 set_repeat_rule_json，确保字段被设置。
    // 但是，flowy-derive 生成的代码已经会做这个转换，所以问题可能不在这里。
    // 
    // 真正的问题可能是：Protobuf 的 value_size 函数对于默认值（0）会返回 0，
    // 导致字段不被序列化。我们需要确保即使值是默认值，也要序列化。
    // 
    // 解决方案：在序列化后立即验证，如果字段丢失，说明 Protobuf 忽略了默认值。
    // 这种情况下，我们需要使用特殊的方法来强制序列化（比如使用非默认值，或者修改 Protobuf 配置）。
    // 
    // 但是，从 Protobuf 的标准来看，one_of 字段如果被设置，应该会被序列化，不管值是什么。
    // 所以问题可能在于 flowy-derive 生成的代码，或者 Protobuf 的配置。
    //
    // 关键修复：验证序列化后的结果，确认字段是否真的被序列化
    // 如果字段丢失，说明 Protobuf 在序列化时忽略了字段（可能是优化导致的）
    let test_bytes: Result<Bytes, _> = pb.clone().try_into();
    if let Ok(bytes) = test_bytes {
      if let Ok(parsed_pb) = DateCellDataPB::try_from(bytes.as_ref()) {
        // 对于非默认值，字段必须存在
        if parsed_pb.repeat_type.is_none() && cell_data.repeat_type != 0 {
          tracing::error!("❌ [DateTypeOption::protobuf_encode] 序列化后 repeat_type 丢失！原始值: {}, 字节长度: {}", cell_data.repeat_type, bytes.len());
          // 如果字段丢失，说明 Protobuf 在序列化时忽略了字段
          // 这可能是因为 Protobuf 的 value_size 函数对于某些值返回 0，导致字段不被序列化
          // 我们需要使用特殊的方法来强制序列化
        } else if parsed_pb.repeat_type.is_none() && cell_data.repeat_type == 0 {
          tracing::warn!("⚠️ [DateTypeOption::protobuf_encode] repeat_type=0 在序列化后丢失（这是 Protobuf 的标准行为，默认值不会被序列化）");
        } else {
          tracing::info!("✅ [DateTypeOption::protobuf_encode] 序列化后 repeat_type 存在: {:?} (原始值: {})", parsed_pb.repeat_type, cell_data.repeat_type);
        }
        if parsed_pb.repeat_rule_json.is_none() && !cell_data.repeat_rule_json.is_empty() {
          tracing::error!("❌ [DateTypeOption::protobuf_encode] 序列化后 repeat_rule_json 丢失！原始值: {:?}, 字节长度: {}", cell_data.repeat_rule_json, bytes.len());
        } else if parsed_pb.repeat_rule_json.is_none() && cell_data.repeat_rule_json.is_empty() {
          tracing::warn!("⚠️ [DateTypeOption::protobuf_encode] repeat_rule_json=\"\" 在序列化后丢失（这是 Protobuf 的标准行为，默认值不会被序列化）");
        } else {
          tracing::info!("✅ [DateTypeOption::protobuf_encode] 序列化后 repeat_rule_json 存在: {:?} (原始值: {:?})", parsed_pb.repeat_rule_json, cell_data.repeat_rule_json);
        }
      } else {
        tracing::error!("❌ [DateTypeOption::protobuf_encode] 无法反序列化测试字节");
      }
    } else {
      tracing::error!("❌ [DateTypeOption::protobuf_encode] 无法序列化测试字节: {:?}", test_bytes.err());
    }

    pb
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

impl CellDataDecoder for DateTypeOption {
  fn decode_cell(&self, cell: &Cell) -> FlowyResult<<Self as TypeOption>::CellData> {
    // 使用和 decode_cell_with_transform 相同的逻辑来读取完整数据
    // 首先尝试从 protobuf 字节中读取完整数据（包括 repeat_type 和 repeat_rule_json）
    tracing::info!("📖 [DateTypeOption::decode_cell] 开始读取 Cell 数据");
    
    if let Some(bytes_vec) = cell.get_as::<Vec<u8>>(CELL_DATA) {
      tracing::info!("📖 [DateTypeOption::decode_cell] 找到 Vec<u8> 数据，长度: {}", bytes_vec.len());
      // 打印原始字节的前 50 个字节，用于调试
      let preview = bytes_vec.iter().take(50).map(|b| format!("{:02x}", b)).collect::<Vec<_>>().join(" ");
      tracing::info!("📖 [DateTypeOption::decode_cell] 原始字节预览: {}...", preview);
      
      let bytes = Bytes::from(bytes_vec);
      if let Ok(pb) = DateCellDataPB::try_from(bytes.as_ref()) {
        // 如果成功解析 protobuf，使用完整数据
        tracing::info!(
          "✅ [DateTypeOption::decode_cell] 从 protobuf 读取成功: repeat_type={:?}, repeat_rule_json={:?}",
          pb.repeat_type,
          pb.repeat_rule_json
        );
        
        // 关键检查：如果 Protobuf 中字段为 None，说明序列化时丢失了
        if pb.repeat_type.is_none() {
          tracing::error!("❌ [DateTypeOption::decode_cell] Protobuf 中 repeat_type 为 None！说明序列化时丢失了字段");
        }
        if pb.repeat_rule_json.is_none() {
          tracing::error!("❌ [DateTypeOption::decode_cell] Protobuf 中 repeat_rule_json 为 None！说明序列化时丢失了字段");
        }
        
        let cell_data = DateCellData::from(&pb);
        tracing::info!(
          "✅ [DateTypeOption::decode_cell] 解析结果: repeat_type={}, repeat_rule_json={:?}",
          cell_data.repeat_type,
          cell_data.repeat_rule_json
        );
        return Ok(cell_data);
      } else {
        let err = DateCellDataPB::try_from(bytes.as_ref()).unwrap_err();
        tracing::warn!("⚠️ [DateTypeOption::decode_cell] protobuf 解析失败: {:?}，回退到字符串解析", err);
      }
    } else {
      tracing::warn!("⚠️ [DateTypeOption::decode_cell] 未找到 Vec<u8> 数据，尝试字符串解析");
      // 检查是否有 String 数据
      if let Some(s) = cell.get_as::<String>(CELL_DATA) {
        tracing::info!("📖 [DateTypeOption::decode_cell] 找到 String 数据: {}", s);
      }
    }
    
    // 如果 protobuf 解析失败，回退到旧的字符串解析方式（向后兼容）
    let s = cell.get_as::<String>(CELL_DATA)
      .ok_or_else(|| {
        tracing::error!("❌ [DateTypeOption::decode_cell] 无法从 Cell 读取数据（既没有 Vec<u8> 也没有 String）");
        flowy_error::FlowyError::internal().with_context("无法从 Cell 读取数据")
      })?;
    let timestamp = cast_string_to_timestamp(&s)
      .ok_or_else(|| {
        tracing::error!("❌ [DateTypeOption::decode_cell] 无法解析时间戳: {}", s);
        flowy_error::FlowyError::internal().with_context("无法解析时间戳")
      })?;
    let cell_data = DateCellData::from_timestamp(timestamp);
    tracing::warn!(
      "⚠️ [DateTypeOption::decode_cell] 从字符串解析（丢失重复信息）: repeat_type={} (默认值), repeat_rule_json={:?} (默认值)",
      cell_data.repeat_type,
      cell_data.repeat_rule_json
    );
    Ok(cell_data)
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
    // 首先尝试从 protobuf 字节中读取完整数据（包括 repeat_type 和 repeat_rule_json）
    // 尝试获取 Vec<u8>，然后转换为 Bytes
    if let Some(bytes_vec) = cell.get_as::<Vec<u8>>(CELL_DATA) {
      tracing::info!("📖 [DateTypeOption::decode_cell_with_transform] 找到 Vec<u8> 数据，长度: {}", bytes_vec.len());
      let bytes = Bytes::from(bytes_vec);
      if let Ok(pb) = DateCellDataPB::try_from(bytes.as_ref()) {
        // 如果成功解析 protobuf，使用完整数据
        tracing::info!(
          "✅ [DateTypeOption::decode_cell_with_transform] 从 protobuf 读取: repeat_type={:?}, repeat_rule_json={:?}",
          pb.repeat_type,
          pb.repeat_rule_json
        );
        
        // 关键检查：如果 Protobuf 中字段为 None，说明序列化时丢失了
        if pb.repeat_type.is_none() {
          tracing::error!("❌ [DateTypeOption::decode_cell_with_transform] Protobuf 中 repeat_type 为 None！说明序列化时丢失了字段");
        }
        if pb.repeat_rule_json.is_none() {
          tracing::error!("❌ [DateTypeOption::decode_cell_with_transform] Protobuf 中 repeat_rule_json 为 None！说明序列化时丢失了字段");
        }
        
        let cell_data = DateCellData::from(&pb);
        tracing::info!(
          "✅ [DateTypeOption::decode_cell_with_transform] 解析结果: repeat_type={}, repeat_rule_json={:?}",
          cell_data.repeat_type,
          cell_data.repeat_rule_json
        );
        return Some(cell_data);
      } else {
        let err = DateCellDataPB::try_from(bytes.as_ref()).unwrap_err();
        tracing::warn!("⚠️ [DateTypeOption::decode_cell_with_transform] protobuf 解析失败: {:?}，回退到字符串解析", err);
      }
    } else {
      tracing::debug!("📖 [DateTypeOption::decode_cell_with_transform] 未找到 Vec<u8> 数据，尝试字符串解析");
    }
    
    // 如果 protobuf 解析失败，回退到旧的字符串解析方式（向后兼容）
    let s = cell.get_as::<String>(CELL_DATA)?;
    let timestamp = cast_string_to_timestamp(&s)?;
    let cell_data = DateCellData::from_timestamp(timestamp);
    tracing::debug!(
      "📖 [DateTypeOption::decode_cell_with_transform] 从字符串解析: repeat_type={} (默认值), repeat_rule_json={:?} (默认值)",
      cell_data.repeat_type,
      cell_data.repeat_rule_json
    );
    Some(cell_data)
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

    // 对于 repeat_type 和 repeat_rule_json，如果 changeset 中明确设置了（Some），就使用新值
    // 即使新值是 0 或空字符串，也要使用，因为这是用户明确设置的值
    // 注意：必须区分 None（未设置，使用旧值）和 Some(0)/Some("")（明确设置为默认值）
    let repeat_type = if let Some(new_repeat_type) = changeset.repeat_type {
      tracing::info!(
        "🔧 [DateTypeOption::apply_changeset] changeset 中设置了 repeat_type: {} (旧值: {})",
        new_repeat_type,
        cell_data.repeat_type
      );
      new_repeat_type
    } else {
      tracing::info!(
        "🔧 [DateTypeOption::apply_changeset] changeset 中未设置 repeat_type，使用旧值: {}",
        cell_data.repeat_type
      );
      cell_data.repeat_type
    };
    
    let repeat_rule_json = if let Some(new_repeat_rule_json) = &changeset.repeat_rule_json {
      tracing::info!(
        "🔧 [DateTypeOption::apply_changeset] changeset 中设置了 repeat_rule_json: {:?} (旧值: {:?})",
        new_repeat_rule_json,
        cell_data.repeat_rule_json
      );
      new_repeat_rule_json.clone()
    } else {
      tracing::info!(
        "🔧 [DateTypeOption::apply_changeset] changeset 中未设置 repeat_rule_json，使用旧值: {:?}",
        cell_data.repeat_rule_json
      );
      cell_data.repeat_rule_json.clone()
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
      repeat_rule_json: repeat_rule_json.clone(),
    };
    
    // 关键修复：确保 repeat_type 和 repeat_rule_json 被正确设置
    // 即使值是默认值（0 或空字符串），也要确保它们被序列化
    tracing::info!(
      "🔧 [DateTypeOption::apply_changeset] 准备创建 DateCellData: repeat_type={}, repeat_rule_json={:?}",
      cell_data.repeat_type,
      cell_data.repeat_rule_json
    );

    // 添加调试日志，确认 repeat_type 和 repeat_rule_json 的值
    tracing::debug!(
      "🔧 [DateTypeOption::apply_changeset] 创建新的 DateCellData: repeat_type={}, repeat_rule_json={:?}",
      cell_data.repeat_type,
      cell_data.repeat_rule_json
    );

    // 使用 protobuf_encode 确保 repeat_type 和 repeat_rule_json 被正确序列化
    let pb = self.protobuf_encode(cell_data.clone());
    tracing::debug!(
      "📤 [DateTypeOption::apply_changeset] protobuf_encode 结果: repeat_type={:?}, repeat_rule_json={:?}",
      pb.repeat_type,
      pb.repeat_rule_json
    );

    // 关键修复：在序列化之前，验证 Protobuf 结构中的字段是否正确设置
    tracing::info!(
      "🔍 [DateTypeOption::apply_changeset] 序列化前验证: pb.repeat_type={:?}, pb.repeat_rule_json={:?}",
      pb.repeat_type,
      pb.repeat_rule_json
    );
    
    // 将 protobuf 序列化为字节，然后存储到 Cell 中
    // 这样 decode_cell 就可以读取完整数据（包括 repeat_type 和 repeat_rule_json）
    let pb_bytes: Bytes = pb.try_into().map_err(|e| {
      tracing::error!("❌ [DateTypeOption::apply_changeset] protobuf 序列化失败: {:?}", e);
      flowy_error::FlowyError::internal().with_context(format!("protobuf 序列化失败: {:?}", e))
    })?;
    
    // 关键验证：立即反序列化，检查字段是否在序列化后丢失
    if let Ok(parsed_pb) = DateCellDataPB::try_from(pb_bytes.as_ref()) {
      if parsed_pb.repeat_type.is_none() && cell_data.repeat_type != 0 {
        tracing::error!("❌ [DateTypeOption::apply_changeset] 序列化后 repeat_type 丢失！原始值: {}, 字节长度: {}", cell_data.repeat_type, pb_bytes.len());
        // 打印字节的十六进制表示，用于调试
        let hex_preview = pb_bytes.iter().take(50).map(|b| format!("{:02x}", b)).collect::<Vec<_>>().join(" ");
        tracing::error!("❌ [DateTypeOption::apply_changeset] 序列化后的字节预览: {}...", hex_preview);
      }
      if parsed_pb.repeat_rule_json.is_none() && !cell_data.repeat_rule_json.is_empty() {
        tracing::error!("❌ [DateTypeOption::apply_changeset] 序列化后 repeat_rule_json 丢失！原始值: {:?}, 字节长度: {}", cell_data.repeat_rule_json, pb_bytes.len());
      }
    } else {
      tracing::error!("❌ [DateTypeOption::apply_changeset] 无法反序列化刚刚序列化的数据！");
    }
    
    // 将 Bytes 转换为 Vec<u8>，因为 Cell 的 insert 方法需要可以转换为 Any 的类型
    let pb_vec = pb_bytes.to_vec();
    
    tracing::info!(
      "💾 [DateTypeOption::apply_changeset] 准备保存到 Cell: repeat_type={}, repeat_rule_json={:?}, pb_vec.len()={}",
      cell_data.repeat_type,
      cell_data.repeat_rule_json,
      pb_vec.len()
    );
    
    let mut cell = new_cell_builder(FieldType::DateTime);
    cell.insert(CELL_DATA.into(), pb_vec.into());
    
    // 验证保存的数据：尝试从 Cell 中读取，确认数据是否正确保存
    if let Some(saved_bytes_vec) = cell.get_as::<Vec<u8>>(CELL_DATA) {
      if let Ok(saved_pb) = DateCellDataPB::try_from(Bytes::from(saved_bytes_vec.clone()).as_ref()) {
        tracing::info!(
          "✅ [DateTypeOption::apply_changeset] 验证保存成功: repeat_type={:?}, repeat_rule_json={:?}",
          saved_pb.repeat_type,
          saved_pb.repeat_rule_json
        );
        
        // 检查字段是否真的被保存了
        if saved_pb.repeat_type.is_none() && cell_data.repeat_type != 0 {
          tracing::error!("❌ [DateTypeOption::apply_changeset] repeat_type 丢失！期望: {}, 实际: None", cell_data.repeat_type);
        }
        if saved_pb.repeat_rule_json.is_none() && !cell_data.repeat_rule_json.is_empty() {
          tracing::error!("❌ [DateTypeOption::apply_changeset] repeat_rule_json 丢失！期望: {:?}, 实际: None", cell_data.repeat_rule_json);
        }
      } else {
        tracing::error!("❌ [DateTypeOption::apply_changeset] 验证保存失败：无法解析保存的 protobuf 数据");
      }
    } else {
      tracing::error!("❌ [DateTypeOption::apply_changeset] 验证保存失败：无法从 Cell 读取 Vec<u8> 数据");
    }
    
    tracing::info!(
      "✅ [DateTypeOption::apply_changeset] 保存到 Cell 完成: repeat_type={}, repeat_rule_json={:?}",
      cell_data.repeat_type,
      cell_data.repeat_rule_json
    );

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

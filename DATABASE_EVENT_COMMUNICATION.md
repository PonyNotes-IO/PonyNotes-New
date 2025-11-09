# DatabaseEventUpdateDateCell 与 Rust 通信机制详解

## 概述

`DatabaseEventUpdateDateCell` 是 Flutter 端用于更新日期单元格数据的事件类。它通过 FFI (Foreign Function Interface) 与 Rust 后端进行通信，使用 Protobuf 进行数据序列化。

## 通信流程

### 1. Flutter 端发送事件

**位置**: `frontend/appflowy_flutter/lib/plugins/database/domain/date_cell_service.dart`

```dart
Future<FlowyResult<void, FlowyError>> update({
  int? repeatType,
  String? repeatRuleJson,
  // ... 其他参数
}) {
  final payload = DateCellChangesetPB()
    ..cellId = cellId
    ..repeatType = repeatType ?? 0
    ..repeatRuleJson = repeatRuleJson ?? '';
  
  // 发送事件到 Rust 后端
  return DatabaseEventUpdateDateCell(payload).send();
}
```

**关键点**:
- `DatabaseEventUpdateDateCell` 是一个事件包装类，由 `appflowy_backend` 包自动生成
- `payload` 是 `DateCellChangesetPB` 类型的 Protobuf 消息
- `.send()` 方法将事件发送到 Rust 后端

### 2. 事件定义（Rust 端）

**位置**: `frontend/rust-lib/flowy-database2/src/event_map.rs`

```rust
#[derive(Clone, Copy, PartialEq, Eq, Debug, Display, Hash, ProtoBuf_Enum, Flowy_Event)]
#[event_err = "FlowyError"]
pub enum DatabaseEvent {
  /// [UpdateDateCell] event is used to update a date cell's data
  #[event(input = "DateCellChangesetPB")]
  UpdateDateCell = 80,
  // ... 其他事件
}
```

**关键点**:
- `DatabaseEvent::UpdateDateCell` 是事件枚举值，对应数字 `80`
- `#[event(input = "DateCellChangesetPB")]` 宏指定输入类型为 `DateCellChangesetPB`
- `Flowy_Event` 宏会自动生成 Flutter 端的对应类

### 3. 事件注册（Rust 端）

**位置**: `frontend/rust-lib/flowy-database2/src/event_map.rs`

```rust
pub fn init(database_manager: Weak<DatabaseManager>) -> AFPlugin {
  let plugin = AFPlugin::new()
    .name(env!("CARGO_PKG_NAME"))
    .state(database_manager);
  plugin
    .event(DatabaseEvent::UpdateDateCell, update_date_cell_handler)
    // ... 注册其他事件
}
```

**关键点**:
- `AFPlugin` 是事件插件容器
- `.event()` 方法将事件枚举值与处理函数绑定
- `update_date_cell_handler` 是实际的事件处理函数

### 4. 事件处理函数（Rust 端）

**位置**: `frontend/rust-lib/flowy-database2/src/event_handler.rs`

```rust
pub(crate) async fn update_date_cell_handler(
  data: AFPluginData<DateCellChangesetPB>,
  manager: AFPluginState<Weak<DatabaseManager>>,
) -> Result<(), FlowyError> {
  let manager = upgrade_manager(manager)?;
  let data = data.into_inner();
  let cell_id: CellIdParams = data.cell_id.try_into()?;
  
  // 提取 repeat_type 和 repeat_rule_json
  let repeat_type = data.repeat_type;
  let repeat_rule_json = data.repeat_rule_json.clone();
  
  // 创建 changeset
  let cell_changeset = DateCellChangeset {
    timestamp: data.timestamp,
    end_timestamp: data.end_timestamp,
    include_time: data.include_time,
    is_range: data.is_range,
    clear_flag: data.clear_flag,
    reminder_id: data.reminder_id,
    repeat_type,
    repeat_rule_json,
  };
  
  // 获取数据库编辑器并更新单元格
  let database_editor = manager
    .get_database_editor_with_view_id(&cell_id.view_id)
    .await?;
  database_editor
    .update_cell_with_changeset(
      &cell_id.view_id,
      &cell_id.row_id,
      &cell_id.field_id,
      BoxAny::new(cell_changeset),
    )
    .await?;
  Ok(())
}
```

**关键点**:
- 函数签名必须匹配 `AFPluginHandler` trait 的要求
- `AFPluginData<T>` 是包装类型，用于从请求中提取数据
- `AFPluginState<T>` 用于访问插件状态（如 `DatabaseManager`）
- 函数是异步的，返回 `Result<(), FlowyError>`

## 底层通信机制

### FFI 层（Flutter ↔ Rust）

**位置**: `frontend/rust-lib/dart-ffi/src/lib.rs`

通信通过以下步骤完成：

1. **Flutter 端调用**:
   ```dart
   DatabaseEventUpdateDateCell(payload).send()
   ```

2. **FFI 函数调用**:
   - Flutter 通过 FFI 调用 Rust 的 C 函数
   - 函数签名定义在 `dart-ffi/binding.h` 中

3. **请求处理**:
   ```rust
   // dart-ffi/src/lib.rs
   pub struct Task {
     dispatcher: Arc<AFPluginDispatcher>,
     request: AFPluginRequest,
     port: i64,
     ret: Option<mpsc::Sender<AFPluginEventResponse>>,
   }
   ```

4. **事件分发**:
   ```rust
   // lib-dispatch/src/dispatcher.rs
   pub async fn async_send_with_callback(
     dispatch: &AFPluginDispatcher,
     request: Req,
     callback: Callback,
   ) -> AFPluginEventResponse
   ```

### 数据序列化

**Protobuf 序列化流程**:

1. **Flutter 端**:
   - `DateCellChangesetPB` 对象被序列化为字节数组
   - 字节数组通过 FFI 传递给 Rust

2. **Rust 端**:
   - 接收字节数组
   - 反序列化为 `DateCellChangesetPB` 结构
   - 传递给事件处理函数

3. **关键代码**:
   ```rust
   // lib-dispatch/src/request/payload.rs
   impl<T: Message> Payload for T {
     fn to_bytes(&self) -> Vec<u8> {
       self.write_to_bytes().unwrap_or_default()
     }
   }
   ```

### 事件分发系统

**架构图**:

```
Flutter (Dart)
    │
    │ FFI Call
    ▼
Rust FFI Layer (dart-ffi)
    │
    │ AFPluginRequest
    ▼
Event Dispatcher (lib-dispatch)
    │
    │ 查找对应 Plugin
    ▼
AFPlugin (flowy-database2)
    │
    │ 调用注册的 Handler
    ▼
update_date_cell_handler
    │
    │ 处理业务逻辑
    ▼
DatabaseManager
    │
    │ 更新数据库
    ▼
Collab Database
```

## 关键组件说明

### 1. AFPluginDispatcher

**位置**: `frontend/rust-lib/lib-dispatch/src/dispatcher.rs`

- 负责事件的分发和路由
- 维护事件到插件的映射关系
- 管理异步任务的执行

### 2. AFPlugin

**位置**: `frontend/rust-lib/lib-dispatch/src/module/module.rs`

- 事件插件容器
- 管理事件处理器
- 维护插件状态

### 3. AFPluginHandler

**位置**: `frontend/rust-lib/lib-dispatch/src/service/handler.rs`

- 定义事件处理器的 trait
- 提供类型安全的处理函数接口

### 4. Flowy_Event 宏

**位置**: `frontend/rust-lib/build-tool/flowy-derive/`

- 自动生成 Flutter 端的事件类
- 生成事件序列化/反序列化代码
- 生成事件发送方法

## 数据流示例

### 完整流程示例

1. **Flutter 端**:
   ```dart
   final payload = DateCellChangesetPB()
     ..cellId = cellId
     ..repeatType = 2
     ..repeatRuleJson = '{"unit":1,"interval":1}';
   
   await DatabaseEventUpdateDateCell(payload).send();
   ```

2. **FFI 层**:
   - Protobuf 序列化: `DateCellChangesetPB` → `Vec<u8>`
   - 通过 FFI 传递字节数组到 Rust

3. **Rust 事件分发**:
   - 接收 `FFIRequest`，包含事件名 `"UpdateDateCell"` 和 payload 字节
   - 查找 `DatabaseEvent::UpdateDateCell` 对应的插件
   - 反序列化 payload 为 `DateCellChangesetPB`

4. **事件处理**:
   - 调用 `update_date_cell_handler`
   - 提取 `repeat_type` 和 `repeat_rule_json`
   - 创建 `DateCellChangeset`
   - 调用 `database_editor.update_cell_with_changeset()`

5. **数据持久化**:
   - `apply_changeset` 将数据编码为 Protobuf
   - 保存到 `Cell` 结构（`Vec<u8>`）
   - 写入 Collab 数据库

## 调试技巧

### 1. 添加日志

**Flutter 端**:
```dart
if (kDebugMode) {
  print('📤 [DateCellBackendService] 发送: repeatType=$repeatType');
}
```

**Rust 端**:
```rust
tracing::info!(
  "📥 [update_date_cell_handler] 接收: repeat_type={:?}",
  data.repeat_type
);
```

### 2. 检查 Protobuf 序列化

在 Rust 端添加验证：
```rust
let pb_bytes: Bytes = pb.try_into()?;
if let Ok(parsed_pb) = DateCellDataPB::try_from(pb_bytes.as_ref()) {
  if parsed_pb.repeat_type.is_none() {
    tracing::error!("❌ repeat_type 在序列化后丢失！");
  }
}
```

### 3. 检查事件路由

查看事件是否正确注册：
```rust
// event_map.rs
.event(DatabaseEvent::UpdateDateCell, update_date_cell_handler)
```

## 常见问题

### 1. 事件未触发

- 检查事件是否正确注册在 `event_map.rs` 中
- 确认 Flutter 端事件名称与 Rust 端枚举值匹配

### 2. Protobuf 字段丢失

- 对于 `one_of` 字段，即使值是默认值也要显式设置
- 检查序列化/反序列化逻辑

### 3. 类型不匹配

- 确认 `#[event(input = "DateCellChangesetPB")]` 中的类型正确
- 检查 Flutter 端和 Rust 端的 Protobuf 定义是否一致

## 相关文件

- **Flutter 端**: `frontend/appflowy_flutter/lib/plugins/database/domain/date_cell_service.dart`
- **Rust 事件定义**: `frontend/rust-lib/flowy-database2/src/event_map.rs`
- **Rust 事件处理**: `frontend/rust-lib/flowy-database2/src/event_handler.rs`
- **事件分发**: `frontend/rust-lib/lib-dispatch/src/dispatcher.rs`
- **FFI 层**: `frontend/rust-lib/dart-ffi/src/lib.rs`
- **Protobuf 定义**: `frontend/rust-lib/flowy-database2/src/entities/type_option_entities/date_entities.rs`


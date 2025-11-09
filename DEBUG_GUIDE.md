# 日程重复字段调试指南

## 当前状态
应用正在启动，Rust 日志已配置为输出到 Flutter 控制台。

## 已添加的调试日志

### 1. Rust 后端 - flowy-database2
- **`🔧 [DateTypeOption::apply_changeset]`** - 保存时应用 changeset 的日志
  - 显示：`repeat_type` 和 `repeat_rule_json` 的值变化
- **`📤 [DateTypeOption::protobuf_encode]`** - 编码为 protobuf 时的日志
  - 显示：序列化到 `DateCellDataPB` 的值
- **`recv PB repeat_type`** - 接收 protobuf 时的日志（在 `event_handler.rs`）

### 2. Rust 后端 - collab-database
- **`💾 [DateCellData -> Cell]`** - 保存到数据库时的日志
  - 显示：保存到 `Cell` 的 `repeat_type` 和 `repeat_rule_json` 值
- **`📖 [Cell -> DateCellData]`** - 从数据库读取时的日志
  - 显示：从 `Cell` 读取的 `repeat_type` 和 `repeat_rule_json` 值

### 3. Flutter 前端
- **`📝 [DateCellBackendService]`** - 发送更新请求时的日志
- **`[_getDateRangeWithExtra]`** - 查询时读取字段的日志

## 调试步骤

### 1. 创建/更新日程
1. 打开应用
2. 进入日历视图
3. 创建或编辑一个日程
4. 设置重复类型（如：每天、每周等）
5. 保存

### 2. 查看日志输出
在终端中查看以下关键日志：

#### 保存流程（从上到下）：
```
📝 [DateCellBackendService] update 调用参数
  - repeatType: 1
  - repeatRuleJson: {...}

📤 [DateCellBackendService] 发送 DateCellChangesetPB
  - hasRepeatType: true
  - repeatType: 1

recv PB repeat_type=Some(1) repeat_rule_json=Some("{...}")

🔧 [DateTypeOption::apply_changeset] repeat_type: Some(1) -> 1

💾 [DateCellData -> Cell] 保存到数据库: repeat_type=1, repeat_rule_json="{...}"
```

#### 查询流程（从上到下）：
```
📖 [Cell -> DateCellData] 从数据库读取: repeat_type=1, repeat_rule_json="{...}"

📤 [DateTypeOption::protobuf_encode] repeat_type: Some(1), repeat_rule_json: Some("{...}")

[_getDateRangeWithExtra] repeatType 字段存在，值为: 1
```

### 3. 问题排查

如果看到 `repeatType 字段不存在，使用默认值 0`：
- 检查 `📤 [DateTypeOption::protobuf_encode]` 日志，确认是否序列化了值
- 检查 `💾 [DateCellData -> Cell]` 日志，确认是否保存到数据库
- 检查 `📖 [Cell -> DateCellData]` 日志，确认是否从数据库读取到值

如果看到 `hasRepeatType: false`：
- 检查 `📝 [DateCellBackendService]` 日志，确认是否传递了参数
- 检查 Dart protobuf 生成代码是否包含 `repeatType` 字段

## 日志文件位置
- Flutter 日志：`/tmp/flutter_logs.txt`
- Rust 日志：通过 `RustLogStreamReceiver` 输出到 Flutter 控制台

## 查看实时日志
```bash
# 查看所有日志
tail -f /tmp/flutter_logs.txt

# 只查看重复字段相关日志
tail -f /tmp/flutter_logs.txt | grep -E "(repeat|💾|📖|🔧|📤|DateCell|schedule)"
```


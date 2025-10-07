# 主页功能架构图

## 整体架构

```
┌─────────────────────────────────────────────────────────────────────┐
│                          Flutter Frontend                            │
│                                                                       │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │                    UI Layer (Widgets)                       │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │    │
│  │  │  HomePage    │  │ TodoPlanView │  │ AIInputSection│     │    │
│  │  │   Widget     │  │   Widget     │  │    Widget     │     │    │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘     │    │
│  └─────────┼──────────────────┼──────────────────┼─────────────┘    │
│            │                  │                  │                   │
│  ┌─────────┼──────────────────┼──────────────────┼─────────────┐    │
│  │         │       Business Logic Layer (BLoC)   │             │    │
│  │         │                  │                  │             │    │
│  │  ┌──────▼────────┐  ┌──────▼────────┐  ┌─────▼────────┐   │    │
│  │  │ Homepage      │  │   TodoBloc    │  │  AIService   │   │    │
│  │  │   Bloc        │  │               │  │              │   │    │
│  │  └──────┬────────┘  └──────┬────────┘  └──────┬───────┘   │    │
│  └─────────┼──────────────────┼──────────────────┼─────────────┘    │
│            │                  │                  │                   │
│  ┌─────────┼──────────────────┼──────────────────┼─────────────┐    │
│  │         │         Service Layer              │             │    │
│  │  ┌──────▼────────┐  ┌──────▼────────┐  ┌─────▼────────┐   │    │
│  │  │    View       │  │  TodoService  │  │  AIConfig    │   │    │
│  │  │   Service     │  │               │  │   Service    │   │    │
│  │  └──────┬────────┘  └──┬────────┬───┘  └──────┬───────┘   │    │
│  └─────────┼───────────────┼────────┼─────────────┼─────────────┘    │
└────────────┼───────────────┼────────┼─────────────┼──────────────────┘
             │               │        │             │
             │               │        │             │
    ┌────────▼────────┐  ┌───▼────┐  │   ┌─────────▼─────────┐
    │  Rust Backend   │  │ Local  │  │   │   External APIs   │
    │      APIs       │  │Storage │  │   │                   │
    │                 │  │        │  │   │  ┌──────────────┐ │
    │ • CreateOrphan  │  │SharedPr│  │   │  │   OpenAI     │ │
    │   View          │  │eferen- │  │   │  │     API      │ │
    │ • GetCalendar   │  │ces     │  │   │  └──────────────┘ │
    │   Event         │  │        │  │   │  ┌──────────────┐ │
    │ • GetView       │  │ JSON   │  │   │  │  Anthropic   │ │
    │                 │  │Storage │  │   │  │     API      │ │
    └─────────────────┘  └────────┘  │   │  └──────────────┘ │
                                     │   └───────────────────┘
                                     │
                            ┌────────▼──────────┐
                            │  Calendar DB      │
                            │  Integration      │
                            │  (Rust Backend)   │
                            └───────────────────┘
```

## 数据流详解

### 1. 待办事项创建流程

```
用户输入
   │
   ▼
TodoFormDialog (UI)
   │
   │ 提交表单
   ▼
TodoBloc.add(CreateTodoEvent)
   │
   │ 业务逻辑处理
   ▼
TodoService.createTodo()
   │
   ├──> 生成 UUID
   │
   ├──> 创建 TodoItem 对象
   │
   ├──> 添加到内存列表
   │
   └──> SharedPreferences.setString()
        (保存 JSON)
   │
   ▼
StreamController 通知
   │
   ▼
TodoBloc 更新状态
   │
   ▼
UI 重新渲染
```

### 2. 日历事件集成流程

```
TodoService.initialize()
   │
   ▼
确保日历视图存在
   │
   ├──> ViewBackendService.getView()
   │    (调用 Rust API)
   │
   └──> 如果不存在，创建
        ViewBackendService.createOrphanView()
        (调用 Rust API: CreateOrphanView)
   │
   ▼
加载日历事件
   │
   └──> DatabaseEventGetAllCalendarEvents()
        (调用 Rust API: GetCalendarEvent)
   │
   ▼
转换为 TodoItem
   │
   └──> _convertCalendarEventToTodo()
        • 检查 timestamp
        • 提取标题、描述
        • 设置来源为 calendar
   │
   ▼
合并到待办列表
   │
   ▼
更新 UI
```

### 3. AI 对话流程

```
用户输入问题
   │
   ▼
AIInputSection (UI)
   │
   │ 按 Enter 或点击发送
   ▼
AIService.sendMessage()
   │
   │ 读取配置
   ▼
AIConfig.load() from .env.ai
   │
   ├──> AI_PROVIDER = openai?
   │    │
   │    └──> _callOpenAI()
   │         └──> HTTP POST to api.openai.com
   │              • model: gpt-4
   │              • messages: [...]
   │              • stream: true
   │
   └──> AI_PROVIDER = anthropic?
        │
        └──> _callAnthropic()
             └──> HTTP POST to api.anthropic.com
                  • model: claude-3-5-sonnet
                  • messages: [...]
                  • stream: true
   │
   ▼
流式响应处理
   │
   └──> yield 每个 chunk
   │
   ▼
UI 实时显示
```

## 模块职责

### UI Layer (Widgets)

| 组件 | 职责 |
|------|------|
| `HomePage` | 主页容器，协调各个区域 |
| `HomepageHeader` | 显示用户信息和搜索 |
| `TodoPlanSection` | 待办列表展示 |
| `TodoItemWidget` | 单个待办项 |
| `TodoFormDialog` | 待办编辑表单 |
| `RecentViewsSection` | 最近访问列表 |
| `AIInputSection` | AI 对话输入 |

### Business Logic Layer (BLoC)

| 组件 | 职责 |
|------|------|
| `HomepageBloc` | 主页整体状态管理 |
| `TodoBloc` | 待办业务逻辑 |
| `AIService` | AI 对话管理 |

### Service Layer

| 组件 | 职责 |
|------|------|
| `TodoService` | 待办 CRUD 操作、持久化 |
| `ViewService` | 视图查询（Rust API 封装）|
| `AIConfigService` | AI 配置加载 |

### Data Layer

| 组件 | 职责 |
|------|------|
| `SharedPreferences` | 本地 JSON 存储 |
| `Rust Backend` | 视图和日历数据 |
| `External APIs` | OpenAI/Anthropic |

## 状态管理

### TodoBloc 状态机

```
┌─────────────┐
│   Initial   │
└──────┬──────┘
       │
       │ LoadTodos
       ▼
┌─────────────┐
│   Loading   │
└──────┬──────┘
       │
       ├──> Success ──┐
       │              │
       └──> Error ────┤
                      │
       ┌──────────────┘
       │
       ▼
┌─────────────┐
│   Loaded    │◄─────┐
└──────┬──────┘      │
       │             │
       ├─ CreateTodo─┤
       ├─ UpdateTodo─┤
       ├─ DeleteTodo─┤
       ├─ ToggleTodo─┤
       └─ FilterTodo─┘
```

### 事件流

```
TodoEvent (用户操作)
    │
    ▼
TodoBloc._mapEventToState()
    │
    ├─> TodoService 处理数据
    │
    ├─> 更新内部状态
    │
    └─> emit(新状态)
    │
    ▼
BlocBuilder 监听
    │
    ▼
UI 重新构建
```

## 数据模型

### TodoItem 结构

```dart
@freezed
class TodoItem with _$TodoItem {
  const factory TodoItem({
    required String id,              // UUID
    required String title,           // 标题
    String? description,             // 描述
    @Default(false) bool isCompleted,// 完成状态
    @Default(TodoPriority.medium)
    TodoPriority priority,           // 优先级
    DateTime? dueDate,               // 截止日期
    @Default([]) List<String> tags,  // 标签
    required DateTime createdAt,     // 创建时间
    DateTime? completedAt,           // 完成时间
    @Default(TodoSource.manual)
    TodoSource source,               // 来源
    String? calendarEventId,         // 日历事件ID
    // ... 其他字段
  }) = _TodoItem;
  
  factory TodoItem.fromJson(Map<String, dynamic> json) 
      => _$TodoItemFromJson(json);
}
```

### 数据持久化格式

```json
{
  "homepage_todos": [
    {
      "id": "1696723200000",
      "title": "完成项目报告",
      "description": "准备下周一的项目进度报告",
      "isCompleted": false,
      "priority": "high",
      "dueDate": "2025-10-08T10:00:00.000Z",
      "tags": ["工作", "报告"],
      "createdAt": "2025-10-05T10:00:00.000Z",
      "source": "manual"
    },
    {
      "id": "calendar_12345",
      "title": "团队会议",
      "isCompleted": false,
      "priority": "medium",
      "dueDate": "2025-10-08T14:00:00.000Z",
      "createdAt": "2025-10-05T09:00:00.000Z",
      "source": "calendar",
      "calendarEventId": "12345"
    }
  ]
}
```

## 关键技术决策

### ✅ 为什么使用 SharedPreferences？

**优点：**
- 简单易用，无需复杂配置
- 快速读写，无网络延迟
- 适合小规模数据（待办列表）
- 跨平台支持（iOS, Android, Web, Desktop）

**缺点：**
- 无法跨设备同步
- 数据量大时性能下降
- 无事务支持

**替代方案（未来）：**
- SQLite（本地关系数据库）
- Hive（NoSQL 本地数据库）
- Rust Backend Database（云端同步）

### ✅ 为什么不在 Rust 后端实现？

**当前设计：**
- 待办是轻量级功能
- 不需要复杂查询
- 不需要跨用户共享
- 快速迭代，易于修改

**未来扩展：**
当需要以下功能时，再迁移到 Rust：
- 跨设备同步
- 多用户协作
- 高级查询和过滤
- 数据备份和恢复

### ✅ 为什么集成日历？

**价值：**
- 统一任务视图
- 避免重复管理
- 利用现有数据
- 提升用户体验

**实现方式：**
- 只读集成（不修改日历）
- 明确标记来源
- 保持独立性

## 性能优化

### 1. 延迟加载
```dart
// HomePage 启动时
Future<void> _initialize() async {
  await TodoService.instance.initialize(); // 异步加载
  // UI 先显示，数据后填充
}
```

### 2. 流式更新
```dart
// 使用 StreamController
final _todosController = StreamController<List<TodoItem>>.broadcast();

// UI 监听变化
StreamBuilder<List<TodoItem>>(
  stream: TodoService.instance.todosStream,
  builder: (context, snapshot) { ... }
)
```

### 3. 缓存策略
```dart
// 内存缓存
List<TodoItem> _todos = [];

// 仅在变化时保存
Future<void> _saveTodos() async {
  if (_isDirty) {
    await prefs.setString(_todosKey, json.encode(_todos));
    _isDirty = false;
  }
}
```

## 错误处理

### 1. 网络错误（AI API）
```dart
try {
  final response = await http.post(...);
} on SocketException {
  yield '网络连接失败';
} on TimeoutException {
  yield '请求超时';
} catch (e) {
  yield '未知错误: $e';
}
```

### 2. 数据损坏
```dart
try {
  _todos = todosList.map((json) => TodoItem.fromJson(json)).toList();
} catch (e) {
  // 清除损坏数据，创建默认数据
  await prefs.remove(_todosKey);
  _todos = _createSampleTodos();
}
```

### 3. API 配置错误
```dart
if (apiKey.isEmpty) {
  yield '请配置 API 密钥';
  return;
}
```

## 测试策略

### 单元测试
```dart
test('创建待办项', () {
  final todo = TodoItem(
    id: '1',
    title: '测试',
    createdAt: DateTime.now(),
  );
  expect(todo.isCompleted, false);
  expect(todo.priority, TodoPriority.medium);
});
```

### BLoC 测试
```dart
blocTest<TodoBloc, TodoState>(
  '添加待办项',
  build: () => TodoBloc(),
  act: (bloc) => bloc.add(CreateTodoEvent(...)),
  expect: () => [
    isA<TodoLoading>(),
    isA<TodoLoaded>(),
  ],
);
```

### 集成测试
```dart
testWidgets('待办列表显示', (tester) async {
  await tester.pumpWidget(MyApp());
  await tester.pumpAndSettle();
  
  expect(find.byType(TodoItemWidget), findsWidgets);
  expect(find.text('完成项目报告'), findsOneWidget);
});
```

---

**文档版本**: 1.0  
**最后更新**: 2025年10月7日  
**维护者**: AppFlowy Team


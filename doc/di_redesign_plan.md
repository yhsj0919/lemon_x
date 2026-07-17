# LemonX 依赖注入重构计划

状态：已按确认方案实现  
目标版本：0.2.0

## 1. 背景

当前 LemonX 使用严格的容器树查找：依赖只能从当前 `LxScope` 向父容器查找。这个模型的所有权清晰，但 Flutter 的 `Dialog`、`BottomSheet`、`Overlay` 位于 Navigator Overlay 中，不是页面 Widget 子树的后代，因此弹窗中的 `context.lx.find<T>()` 无法看到页面 Controller。

手动把页面容器桥接到弹窗虽然安全，但会产生重复模板代码。期望的使用体验是：

- 页面注册的 Controller 可以在页面、弹窗和异步回调中随用随取；
- 默认由页面作用域持有，页面销毁时自动回收；
- 显式指定 `permanent: true` 后常驻到应用根作用域；
- 不接管 Navigator，不要求 RouteObserver，不绑定 go_router；
- 多页面注册相同类型时行为确定且可诊断。

这里的“用完自动回收”定义为“生命周期所有者（`State` 或 `LxScope`）销毁后回收”，不采用引用计数。引用计数无法可靠识别闭包、Future、Stream 和 Flutter Element 持有的对象，容易过早销毁。

## 2. 核心设计：可见性与所有权分离

每条注册同时具有两个概念：

1. **所有者（owner）**：决定何时销毁实例；
2. **可见性（visibility）**：决定可以从哪里找到实例。

单 Controller 页面使用便捷入口创建“页面持有、全局可发现”的注册：

```dart
LxScope.put(
  LoginController.new,
  child: const LoginPageBody(),
)
```

行为：

- Owner：当前页面的 `LxScope`；
- Visibility：全局索引和当前容器树；
- 页面销毁：从全局索引移除，并执行 `onDispose()`；
- 弹窗获取：`Lemon.find<LoginController>()`；
- 页面严格查找：仍可使用 `context.lx.find<LoginController>()`。

常驻依赖显式注册到根作用域：

```dart
bindings: (it) => it.put(
  SessionController.new,
  permanent: true,
),
```

也可以继续在 composition root 使用：

```dart
Lemon.put(SessionController.new);
```

## 3. 建议 API

### 3.1 LxRegistrar

`LxScope.bindings` 继续接收专用的 `LxRegistrar`。注册方法返回 `void`，确保箭头表达式不会错误推断泛型。

```dart
abstract interface class LxRegistrar {
  void put<T>(
    LxFactory<T> builder, {
    Object? tag,
    LxDisposer<T>? dispose,
    bool permanent = false,
  });

  void lazyPut<T>(
    LxFactory<T> builder, {
    Object? tag,
    LxDisposer<T>? dispose,
    bool permanent = false,
  });
}
```

通过页面 `LxRegistrar` 注册的依赖默认全局可发现，不再提供 `expose` 开关。`putInstance`、`factory`、`putAsync` 使用相同的 `permanent` 规则。`putInstance` 的 `owned` 语义保持不变：

- `owned: false`：只注册，不负责销毁外部实例；
- `owned: true`：由目标作用域负责销毁；
- `permanent: true`：目标作用域变为根作用域，但不会隐式把 `owned` 改为 true。

### 3.2 查找 API

保留两种明确的查找模式：

```dart
// 严格作用域查找：当前 Scope -> 父 Scope -> 根 Scope
final controller = context.lx.find<LoginController>();

// 全局可见注册：适用于 Dialog、BottomSheet、Overlay、异步服务
final controller = Lemon.find<LoginController>();
```

建议 `context.lx.find()` 不自动搜索兄弟作用域，避免 Tab、多 Navigator 和后台页面之间发生隐式串用。`Lemon.find()` 才使用全局索引。

### 3.3 单 Controller 页面便捷入口

常规页面不要求手写 `Builder + context.lx.put()`，增加静态泛型便捷入口：

```dart
LxScope.put(
  LoginController.new,
  child: const LoginPageBody(),
)
```

计划签名：

```dart
static Widget put<T>(
  LxFactory<T> builder, {
  required Widget child,
  Object? tag,
  bool permanent = false,
  LxDisposer<T>? dispose,
  Key? key,
  String? debugLabel,
});
```

它内部等价于创建 `LxScope` 并调用 registrar.put，不依赖 runtimeType 注册，因此仍支持按接口类型显式调用：

```dart
LxScope.put<AuthService>(
  AuthServiceImpl.new,
  child: const LoginPageBody(),
)
```

需要一次注册多个依赖时继续使用 bindings：

```dart
LxScope(
  bindings: (it) {
    it.put(LoginController.new);
    it.lazyPut(LoginRepository.new);
  },
  child: const LoginPageBody(),
)
```

确实需要在页面子树中按需注册时，仍保留返回实例的底层能力：

```dart
final controller = context.lx.put(LoginController.new);
```

当 `LxContainer` 由 `LxScope` 创建时，该注册由页面 Scope 持有并进入全局索引；页面销毁后自动回收。独立创建、未挂到 `LxScope` 的 `LxContainer` 仍保持隔离容器语义。

`find()` 只负责查找，不隐式执行 put：

```dart
final existing = context.lx.find<LoginController>();
```

根作用域注册同样返回实例：

```dart
final session = Lemon.put(SessionController.new);
```

### 3.4 StatefulWidget 生命周期入口

能够修改页面 `State` 时，推荐使用 Mixin，直接让 `State` 成为生命周期所有者：

```dart
class _LoginPageState extends State<LoginPage>
    with LxStateOwner<LoginPage> {
  late final controller = put(LoginController.new);
}
```

Mixin 的 `put()` 返回实例，并在 `State.dispose()` 时自动撤销、销毁该 State 持有的全部注册。业务代码不需要显式传入 `owner: this`，也不需要调用 `Lemon.disposeOwner(this)`。

`late final` 用于让字段在首次读取时通过当前 `State` 调用 Mixin 实例方法；依赖仍只注册一次。若页面不适合或无法使用 Mixin，则使用 `LxScope.put(...)` 或 `LxScope(bindings: ...)` 包裹 Widget 子树。

公开 API 不提供任意 `owner` 参数和 `disposeOwner`。所有者令牌仅作为内部机制，避免业务代码退化为手动生命周期管理。

## 4. 全局索引

根容器维护独立于所有权容器的索引：

```text
(Type, tag)
  -> 唯一 canonical registration
```

规则：

1. 每个 `(Type, tag)` 最多存在一条 canonical 注册；
2. 第一次注册确定 builder、实例和生命周期 owner；
3. 后续相同 `(Type, tag)` 的注册直接复用第一次注册，后续 builder 不执行；
4. 重复注册不会改变第一次注册的 owner、owned 或 permanent 属性；
5. 后注册 Scope 可以保存一条非 owning alias，使其严格作用域查找也返回 canonical 实例；
6. alias 不延长实例生命周期，canonical owner 销毁后 alias 同时失效；
7. tag 是 key 的一部分，只有 tag 不同才允许同一类型存在多个实例；
8. 注册构建失败时保留可重试语义，不留下半初始化实例；
9. canonical owner dispose/reset/remove 时必须同步撤销全局注册和全部 alias。

索引只保存注册引用，不复制实例，不改变销毁所有者。

## 5. 重复类型和多 Navigator

同一个 `(Type, tag)` 不采用覆盖或栈式遮蔽。无论来自页面、Dialog、Tab 还是多个 Navigator，后续注册都复用第一次注册的实例。

规则：

- `context.lx.find()` 始终采用严格容器树规则；
- `Lemon.find()` 返回该 `(Type, tag)` 唯一的 canonical 实例；
- 重复注册输出 duplicate 诊断，但不构造第二个实例；
- 多个页面需要共享 Controller 时不传 tag；
- 多个页面需要各自独立的同类型 Controller 时必须使用不同 tag；
- 首版不引入“当前 Route”概念，避免耦合 Navigator/go_router。

例如页面 A 首先注册 `DetailController`，页面 B 再次注册同类型且不传 tag，B 会复用 A 的实例。A 是实例 owner；A 销毁后实例随之销毁，B 的重复注册不会自动接管所有权。普通 Navigator Push 场景中 A 在 B 下面仍保持挂载，因此共享期间不会提前销毁。路由替换等会先销毁 A 的场景，应把共享实例注册为 permanent，或放到两者共同的父 Scope。

示例：

```dart
bindings: (it) => it.put(
  DetailController.new,
  tag: 'left-pane',
),

final controller = Lemon.find<DetailController>(tag: 'left-pane');
```

## 6. 生命周期语义

| 场景 | 所有者 | 销毁时机 |
| --- | --- | --- |
| `LxStateOwner.put()` | 当前页面 State | `State.dispose()` |
| `LxRegistrar.put()` | 当前页面 Scope | 页面从 Widget 树移除 |
| `LxRegistrar.lazyPut()` | 当前页面 Scope | 页面移除；未创建则只撤销注册 |
| `permanent: true` | Lemon 根容器 | `Lemon.remove/reset/dispose` |
| `putInstance(..., owned: false)` | 外部调用者 | LemonX 不销毁 |
| `putInstance(..., owned: true)` | 目标 Scope | 目标 Scope 销毁 |
| `factory()` 创建的对象 | 调用者 | LemonX 不销毁实例 |

销毁顺序继续保持：

1. 子 Scope；
2. 当前 Scope 中按创建顺序逆序销毁的实例；
3. Controller 持有资源；
4. `onDispose()`；
5. 从全局索引彻底移除注册。

为了避免销毁期间再次被全局找到，实际实现应在进入 disposing 时先把该 Scope 的注册从全局索引隐藏，再执行异步清理。

## 7. Dialog 使用体验

页面：

```dart
LxScope(
  bindings: (it) => it.put(LoginController.new),
  child: const LoginPageBody(),
);
```

页面和弹窗都可以直接获取：

```dart
final controller = Lemon.find<LoginController>();
```

弹窗不再需要复制页面 Scope：

```dart
showDialog<void>(
  context: context,
  builder: (_) => const LoginDialog(),
);
```

如果弹窗需要自己的 Controller，仍建议给弹窗增加独立 `LxScope`，使弹窗 Controller 在关闭时回收。页面 Controller 无需再次注册。

## 8. Lemon API 语义调整

当前 `Lemon.find()` 只读取根容器。重构后改为读取全局可见索引，这是本次最主要的行为变化。

建议：

- `Lemon.put()`：根容器注册，等价于 permanent，并返回注册实例；
- `Lemon.find()`：返回 `(Type, tag)` 唯一的全局可见注册；
- `Lemon.contains()`：检查全局可见注册；
- `Lemon.remove()`：只允许删除 owner 为根容器的注册；命中页面 Scope 注册时抛出所有权错误；
- `Lemon.reset()`：只清理根容器注册，不跨页面清理仍挂载的 Scope；
- `Lemon.dispose()`：销毁根容器及其所有子 Scope，重建全新根容器。

为保留严格根容器能力，可以继续公开 `Lemon.root.find<T>()`。

## 9. 不采用的方案

### 9.1 根容器自动搜索任意子容器

无法区分当前页面、后台页面、Tab 和多个 Navigator，容易返回错误 Controller。

### 9.2 自动监听 RouteObserver

需要用户向每个 Navigator 安装 Observer；嵌套 Navigator 和 go_router 配置不同，会让 DI 与路由实现耦合。

### 9.3 引用计数自动销毁

Dart 无法可靠统计闭包、异步任务、Stream 和 Widget Element 的实际引用，可能过早销毁仍在使用的 Controller。

### 9.4 自动把 InheritedWidget 复制到 Overlay

Flutter 没有对任意 InheritedWidget 提供透明跨 Route 继承机制，最终仍需要包装 Dialog builder。

## 10. 实施阶段

### 阶段 A：数据结构

- 为注册记录增加明确的 owner 信息；
- 根容器增加 `(Type, tag) -> canonical registration`；
- 完成 register、alias、remove、reset、dispose 的索引一致性；
- 销毁开始时先隐藏注册。

### 阶段 B：API

- `LxRegistrar` 增加 `permanent`；
- 增加 `LxStateOwner` Mixin，提供返回实例且随 State 自动回收的 `put()`；
- 保留 `LxScope.put(...)` 和 `LxScope(bindings: ...)`，用于无法使用 Mixin 的 Widget；
- 不公开任意 `owner` 参数和手动 `disposeOwner`；
- 页面 `context.lx.put()` 注册进入全局索引并返回实例；
- `Lemon.find/contains` 接入全局索引，`Lemon.remove` 增加 owner 校验；
- `LxContainer.find` 保持严格层级查找；
- 保留并扩展 Debug duplicate 诊断。

### 阶段 C：测试

- 页面 Controller 能从 `Lemon.find` 获取；
- 普通 Dialog 无 Scope 桥接也能获取页面 Controller；
- 页面销毁后全局注册消失并执行一次 `onDispose()`；
- permanent Controller 在页面销毁后仍存在；
- 同类型同 tag 重复注册复用第一次实例且不执行后续 builder；
- 页面 B 销毁后页面 A 仍能获取原实例；
- canonical owner 销毁后重复注册 alias 同时失效；
- tag 相互隔离；
- 多 Scope 同实例只销毁一次；
- lazy/async 初始化失败后可重试；
- dispose 进行中不能再次全局获取；
- `context.lx.put()` 返回实例且由最近页面 Scope 自动回收；
- `LxStateOwner.put()` 返回实例，并在 State 销毁时自动回收且仅执行一次 dispose；
- `LxScope.put()` 在不能使用 Mixin 时具备相同的自动回收语义；
- `Lemon.put()` 返回实例且由根容器持有；
- `Lemon.remove()` 无法删除页面 Scope 持有的注册；
- 多 Navigator 同 key 共享实例，不同 tag 保持隔离。

### 阶段 D：性能验证

- 严格 Scope find：不得明显退化；
- `Lemon.find` 全局索引：目标 O(1)；
- 注册/销毁索引维护；
- 1000 个页面 Scope 反复创建/销毁后索引无残留；
- 与当前 DI find 基准和 GetX Plus 做同机对照；
- Debug diagnostics 与 Release/disabled diagnostics 分开测试。

## 11. 兼容与迁移

潜在破坏性变化：

- `LxBindings` 参数已经从完整容器收紧为 `LxRegistrar`；
- bindings 内不能再依赖 `put()` 返回实例，需要先注册再 `find()`；
- 页面可以改用返回实例的 `context.lx.put()` 做按需注册；
- `Lemon.find()` 从“仅根容器”变成“当前全局可见注册”；
- `Lemon.remove()` 增加 owner 限制，只能删除根容器持有的注册；
- 同类型同 tag 的页面注册会复用第一条 canonical 注册；需要独立实例时必须增加 tag。

本次重构已纳入 0.2.0，并同步提供迁移说明。

## 12. 开发前需要确认

以下决策确认后再开始实现：

1. 页面 bindings 和 `context.lx.put()` 注册是否默认进入全局索引？已确认：是。
2. 弹窗是否统一改用 `Lemon.find<T>()`，而 `context.lx.find<T>()` 保持严格作用域？已确认：是。
3. 多个页面注册同一 `(Type, tag)` 时是否始终复用第一次注册，且后续 builder 不执行？已确认：是。
4. 是否删除 `expose` 参数，让页面注册默认全局可发现？已确认：是。
5. `permanent: true` 是否表示注册到根作用域，直到显式 remove/reset/dispose？已确认：是。
6. `Lemon.remove<T>()` 是否禁止删除页面 Scope 持有的注册？已确认：是。
7. `Lemon.reset()` 是否只清理根注册，页面注册继续由各自 Scope 管理？已确认：是。
8. 多 Navigator 使用相同 `(Type, tag)` 时是否共享第一次注册的实例，需要独立实例时由调用方提供 tag？已确认：是。
9. 页面生命周期入口是否同时保留 `LxStateOwner` Mixin 与 `LxScope`？已确认：是；能使用 Mixin 时优先使用，不能使用时套一层 `LxScope`。
10. 是否公开 `owner: state` 和 `disposeOwner` 供业务手动管理？已确认：否；owner 仅作为内部机制。

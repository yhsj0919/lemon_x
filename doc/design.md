# LemonX 设计文档

> 状态：已接受（Accepted）  
> 实现版本：0.1.0  
> 包名：`lemon_x`

## 1. 背景

LemonX 是一个面向 Flutter 的轻量状态管理与依赖注入库。它希望提供接近 GetX 的简洁 API：状态声明短、组件绑定直观、依赖获取方便；同时让作用域、对象所有权、销毁时机和测试替换保持明确。

项目不以复刻 GetX 为目标。首个版本只解决两件事：

1. 响应式状态管理；
2. 带生命周期和作用域的依赖注入。

项目只包含状态管理和依赖注入。路由绑定仅用于把 DI 作用域绑定到 Flutter Route 的销毁时机，不提供任何路由框架能力。

## 2. 设计目标

- **低样板代码**：普通值可直接通过 `.obs` 变为响应式值。
- **细粒度刷新**：Widget 只订阅读取过的状态，不依赖手写 selector。
- **API 熟悉**：为 GetX 用户提供自然的迁移体验，但使用 `Lx` 命名避免概念混淆。
- **生命周期明确**：注册者、作用域和 Widget 的销毁关系可预测。
- **同步优先、异步完整**：同步依赖简单，异步依赖有独立且类型安全的接口。
- **可测试**：容器可独立创建，依赖可覆盖，测试之间无需共享全局状态。
- **最小内核**：核心实现尽量只依赖 Dart/Flutter SDK。
- **低侵入、可退出**：业务对象不必继承框架基类，状态和依赖可逐步替换为 Flutter/Dart 原生实现，不要求一次性重写应用。

## 3. 非目标

- 不提供导航 API、路由表、命名路由封装、参数解析、守卫、重定向或深链接；
- 路由适配层只负责创建页面依赖作用域，并在 Route 销毁时释放作用域；
- 不提供持久化、网络缓存或数据层框架；
- 不通过代码生成完成基础功能；
- 不自动监听任意普通 Dart 字段；
- 不保证与 GetX API 一比一兼容；
- 首版不提供跨 isolate 状态同步和 time-travel 调试。

## 4. 核心概念

### 4.1 `Rx<T>`：响应式值

```dart
final count = 0.obs;            // RxInt
final user = Rxn<User>();       // 可空对象

count.value++;
user.value = currentUser;
```

行为约定：

- 赋值前后通过 `==` 判断；相等时默认不通知；
- 可调用 `refresh()` 强制通知，适合对象内部发生原地修改的场景；
- `Rx<T>` 实现 `ValueListenable<T>`，可与 Flutter 原生生态互操作；
- 调用 `dispose()` 后禁止继续写入或订阅，debug 模式给出清晰错误；
- 不劫持 `List`、`Map`、`Set` 的所有修改操作。首版推荐不可变更新。

```dart
items.value = [...items.value, newItem];
```

同时提供 GetX 风格的常用类型：`Rxn<T>`、`RxInt`、`RxDouble`、`RxBool`、`RxString`、`RxList<E>`、`RxMap<K, V>`、`RxSet<E>`。`.obs` 根据静态类型返回对应的 Rx 类型。`RxList` 提供 `replaceAll()`、`reverse()`、`shuffle()`、`swap()` 和 `move()` 等常用批量操作，每次最多发送一次通知。

### 4.2 `RxComputed<T>`：派生状态

```dart
final fullName = RxComputed(
  () => '${firstName.value} ${lastName.value}',
);
```

派生状态只读，自动跟踪计算期间读取的依赖。依赖变化后将结果标记为 dirty；下一次读取时重新计算。计算结果变化时通知观察者。

约束：计算函数应保持纯粹，不应在计算期间写入其他响应式状态。检测到同步循环依赖时抛出 `LxCircularDependencyError`。

### 4.3 `RxEffect` 与 Worker：副作用

```dart
final effect = rxEffect(() {
  analytics.setUserId(currentUser.value?.id);
});

effect.dispose();
```

Effect 自动收集执行期间读取的依赖，并在依赖变化后重新执行。连续同步更新默认合并到当前 microtask 末尾，避免重复执行。Effect 必须可销毁，并支持返回清理函数：

```dart
final effect = rxEffect(() {
  final subscription = service.watch(query.value).listen(onData);
  return subscription.cancel;
});
```

### 4.4 `RxAsync<T>`：可选的轻量异步状态

`RxAsync<T>` 只表达互斥的 loading、data、error 三种状态，不公开冗长的状态子类：

```dart
final user = RxAsync<User>(); // 初始为 loading

user.loading();
user.data(currentUser);
user.error(error, stackTrace);
```

UI 通过 `when` 处理三种状态：

```dart
Obx(() => user.when(
  loading: () => const CircularProgressIndicator(),
  data: (user) => Text(user.name),
  error: (error, _) => Text('$error'),
));
```

公开 API 保持为单一类型：

```dart
class RxAsync<T> implements Listenable {
  RxAsync();

  bool get isLoading;
  bool get hasData;
  bool get hasError;

  T? get value;
  Object? get errorValue;
  StackTrace? get stackTrace;

  void loading();
  void data(T value);
  void error(Object error, [StackTrace? stackTrace]);

  Future<void> guard(Future<T> Function() task);

  R when<R>({
    required R Function() loading,
    required R Function(T value) data,
    required R Function(Object error, StackTrace? stackTrace) error,
  });

  @override
  void addListener(VoidCallback listener);

  @override
  void removeListener(VoidCallback listener);
}
```

`when` 和状态 getter 会读取内部 Rx，因此可以被 `Obx` 自动跟踪。`RxAsync<T>` 同时实现 `Listenable`，不使用 `Obx` 时可配合 Flutter 原生 `ListenableBuilder`。

`guard` 是可选便利方法：调用时先进入 loading，成功后进入 data，捕获异常和 StackTrace 后进入 error；它不重新抛出已捕获异常。需要自定义错误处理或继续抛出时，调用方直接使用 `loading/data/error`。

```dart
await user.guard(repository.getUser);
```

严格限制：

- 只提供 loading、data、error，不增加 idle、refreshing、empty 等状态；
- 不内置重试、缓存、持久化、网络请求和自动取消；
- `value == null` 不能用于判断状态，必须使用 `hasData`，以支持 `T` 本身可空；
- 它只用于 presentation 层，Domain、Repository 和 Service 不依赖 `RxAsync`；
- 用户始终可以改用 `Rx<MyCustomState<T>>` 表达更复杂的业务状态。

### 4.5 `LxController`：业务状态生命周期

```dart
class CounterController extends LxController {
  final count = 0.obs;

  void increment() => count.value++;

  @override
  void onInit() {}

  @override
  void onDispose() {}
}
```

Controller 不是响应式状态的必要基类；它只用于统一管理业务对象生命周期。核心钩子只保留：

- `onInit()`：实例进入容器后调用一次；
- `onReady()`：首帧结束后调用一次，仅对绑定到 Flutter 作用域的 Controller 生效；
- `onDispose()`：从容器移除时调用一次。

Controller 可通过 `own(disposable)` 托管 `Rx`、effect、worker、订阅等资源，在自身销毁时统一释放。

`LxController` 始终是可选便利基类。普通 Dart 类也可以注册到容器，并通过注册时的 `dispose` 回调释放：

```dart
final service = container.put(
  () => PlainService(),
  dispose: (service) => service.close(),
);
```

## 5. Widget API

### 5.1 自动依赖收集：`Obx`

```dart
Obx(() => Text('${controller.count.value}'))
```

builder 执行期间读取的所有 Rx 会成为依赖。任一依赖变化后，仅此 `Obx` 标记为需要重建。每次 build 都重新收集依赖，因此条件分支能够正确增删订阅。

### 5.2 显式监听：`RxBuilder<T>`

```dart
RxBuilder<int>(
  listenable: controller.count,
  builder: (context, count, child) => Text('$count'),
)
```

用于需要明确依赖、传递静态 `child` 或排查重建范围的场景。

### 5.3 获取依赖

依赖查找分为三种明确方式，不做隐式的“当前页面”猜测：

```dart
// 1. Widget：从当前 BuildContext 最近的作用域向上查找
final controller = context.lx.find<CounterController>();

// 2. 普通 Dart 对象：由调用者通过构造函数传入（推荐）
final repository = AuthRepository(apiClient);

// 3. 应用级服务：从根容器查找
final analytics = Lemon.find<AnalyticsService>();
```

规则如下：

- `context.lx.find<T>()` 从最近的页面或 Widget 子树容器开始，逐级查找到根容器；
- `Lemon.find<T>()` **只查找根容器**，不会自动访问当前 Route 的容器；
- 页面级 Controller 必须通过 `context.lx.find<T>()` 获取；
- 应用级 Service 可以通过 `Lemon.find<T>()` 获取；
- Controller、Repository、Service 之间优先使用构造函数注入，不在业务对象内部读取 `BuildContext`；
- `Obx` 只收集 Rx 依赖，不负责创建或查找 Controller；
- 找不到依赖时立即抛出 `LxNotFoundError`，不进行隐式注册。

容器底层仍使用 `get<T>()`；面向使用者公开 `find<T>()` 作为等价别名，以保持 GetX 风格。文档和示例统一使用 `find<T>()`。

## 6. 依赖注入

### 6.1 容器模型

```dart
final container = LxContainer();

final api = container.put<ApiClient>(() => ApiClient());
container.lazyPut<AuthRepository>(() => AuthRepository(container.find()));
container.factory<Session>(() => Session());
```

每个容器可有一个父容器。查找顺序为当前容器到父容器；子容器可覆盖父容器注册，但不能修改父容器注册。

```text
应用根容器
  └─ 页面容器
      └─ Dialog / 局部功能容器
```

核心注册类型：

| API | 创建时机 | 同一容器内结果 | 默认销毁时机 |
| --- | --- | --- | --- |
| `put<T>(builder)` | 注册时立即构造 | key 不存在时构造并返回；存在时直接返回已有实例 | 注册被移除或容器销毁 |
| `putInstance<T>(instance)` | 立即 | 注册外部已有实例；存在时返回已有实例 | 默认由外部调用者负责 |
| `lazyPut<T>(factory)` | 首次获取 | 缓存单例 | 注册被移除或容器销毁 |
| `factory<T>(factory)` | 每次获取 | 新实例 | 调用者负责 |
| `putAsync<T>(factory)` | 显式异步初始化 | 缓存单例 | 注册被移除或容器销毁 |

可通过 `tag` 区分同类型实例：

```dart
container.putInstance<HttpClient>(publicClient, tag: 'public');
container.putInstance<HttpClient>(privateClient, tag: 'private');
container.find<HttpClient>(tag: 'private');
```

首版 `tag` 使用 `Object?`，注册键由 `(Type, tag)` 组成。tag 必须具有稳定的 `==` 和 `hashCode`，不建议使用字段仍会变化的对象。

### 6.2 异步依赖

异步获取必须显式使用 `findAsync<T>()`，同步 `find<T>()` 不会隐式阻塞或返回包装类型。

```dart
container.putAsync<Database>(() async {
  final db = Database();
  await db.open();
  return db;
});

final db = await container.findAsync<Database>();
```

同一个异步单例初始化期间的并发请求共享同一个 Future。初始化失败不缓存实例；后续调用默认允许重试。

同步和异步初始化都必须具备失败回滚：

- builder 或 `onInit()` 抛错时，不保留半初始化实例；
- 清除本次创建中的缓存和 Future，使后续调用能够重试；
- 若实例已经创建，则尽力执行其销毁协议；
- 多个并发 `findAsync()` 收到同一次初始化错误，不重复启动 builder；
- 错误保留原始异常和堆栈，并补充依赖 key 与作用域信息。

### 6.3 注册覆盖

- 注册 key 由 `(Type, tag)` 组成，`put<T>()` 按 key 去重；
- `put<T>(() => instance)` 是立即构造式注册：容器先检查 key，未注册时才执行 builder；
- key 已存在时，`put` 不执行 builder、不替换注册，直接返回已有实例；
- 已经在容器外构造好的对象使用 `putInstance<T>(instance)`；默认 `owned: false`，容器不负责销毁；
- `putInstance(instance, owned: true)` 表示显式把实例所有权转移给容器；若 key 已存在，新传入对象仍不归容器所有；
- `lazyPut`、`factory`、`putAsync` 与已有 key 冲突时默认抛出 `LxAlreadyRegisteredError`，避免静默忽略不同注册策略；
- 确实需要替换时显式调用 `replace<T>()`，测试覆盖也使用此 API；
- 去重只检查当前容器；父容器已有相同 key 时，子容器仍可注册并覆盖查找结果；
- `find` 按当前容器到父容器查找；子容器销毁后，父容器实例重新可见；
- 提供 `contains<T>()`、`remove<T>()` 和 `reset()`；
- `reset()` 按实例创建顺序的逆序销毁，减少依赖先于使用者销毁的问题。

```dart
final first = container.put(() => CounterController());
final second = container.put(() => CounterController());

identical(first, second); // true

final externalClient = ApiClient();
final client = container.putInstance<ApiClient>(externalClient);
```

`put` 接收 builder，因此在 `build()` 中重复调用也不会重复创建对象。不过注册通常仍应集中写在 bindings 中，页面只使用 `find`，让依赖来源更容易定位。

```dart
T put<T>(
  T Function() builder, {
  Object? tag,
  FutureOr<void> Function(T value)? dispose,
});

T putInstance<T>(
  T instance, {
  Object? tag,
  bool owned = false,
  FutureOr<void> Function(T value)? dispose,
});
```

`put` 与 `lazyPut` 都接收 builder，区别仅在执行时机：`put` 在注册语句执行时立即构造，`lazyPut` 到第一次 `find` 时才构造。

`putInstance` 的 `dispose` 回调仅在 `owned: true` 时生效；框架不会因为传入回调而隐式取得外部实例所有权。

### 6.4 所有权、销毁协议与容器状态

所有权默认规则：

| 注册方式 | 默认所有者 |
| --- | --- |
| `put(builder)` | 容器 |
| `lazyPut(builder)` | 容器 |
| `putAsync(builder)` | 容器 |
| `factory(builder)` | 调用者 |
| `putInstance(instance)` | 外部调用者 |

容器移除实例时，按以下顺序选择一种协议调用：

1. `LxController.onDispose()`；
2. 实现 `LxDisposable.dispose()` 的对象；
3. 注册时传入的 `dispose: (value) { ... }` 回调。

销毁协议支持同步或异步返回值：

```dart
abstract interface class LxDisposable {
  FutureOr<void> dispose();
}
```

`remove()`、`reset()` 和容器 `dispose()` 均返回 `Future<void>`。同一个实例只销毁一次，并按实际实例创建顺序逆序销毁。`factory` 创建的对象不归容器所有。

容器状态机固定为：

```text
active -> disposing -> disposed
```

- `dispose()` 幂等，多次调用返回同一个 Future；
- 进入 disposing 后立即拒绝新的 put/find；
- disposing 或 disposed 状态访问时抛出 `LxDisposedError`；
- 父容器持有其创建的子容器，销毁父容器前先销毁仍存活的子容器；
- 子容器必须先完成销毁，父容器才销毁自己的实例；
- 异步销毁某个对象失败时继续销毁其余对象，结束后汇总报告错误。

Flutter 的 `State.dispose()` 不能等待 Future。`LxScope` 卸载时应立即把容器标记为 disposing，然后启动异步清理；异常通过 `FlutterError.reportError` 上报。测试和应用主动关闭时应显式 `await container.dispose()`。

### 6.5 循环依赖检测

同步 DI MVP 必须包含构造链检测，不能等到后续版本：

```text
LxCircularDependencyError: A -> B -> C -> A
```

每次构造维护当前作用域的解析栈，并通过 `try/finally` 恢复。同步、lazy 和异步依赖都使用同一套路径诊断；错误包含 Type、tag 和容器 debugLabel。

### 6.6 Flutter 作用域

```dart
LxScope(
  create: (parent) {
    final scope = LxContainer(parent: parent);
    scope.lazyPut(() => CounterController());
    return scope;
  },
  child: const CounterPage(),
)
```

`LxScope` 拥有其创建的容器，并在 Widget 卸载时销毁。若传入外部容器，则默认不取得所有权，必须通过 `disposeContainer: true` 显式转移所有权。

应用根节点可使用：

```dart
LemonApp(
  bindings: (container) {
    container.lazyPut<ApiClient>(() => ApiClient());
  },
  child: const MaterialApp(...),
)
```

`LemonApp` 只负责根容器和生命周期，不包装或替代 `MaterialApp`。

### 6.7 全局便捷入口

为脚本、应用入口和渐进迁移提供可选的根容器代理：

```dart
Lemon.put(() => ApiClient());
final api = Lemon.find<ApiClient>();
await Lemon.reset();
```

约束：

- 全局入口是便利层，不是容器内核的唯一使用方式；
- Widget 内优先使用 `context.lx`；
- 测试应创建独立 `LxContainer`，或在 tearDown 中 `Lemon.reset()`；
- package 内部不得直接依赖全局容器，以确保内核可隔离测试。

### 6.8 页面生命周期与未来 `go_router` 适配

核心包不创建自己的 Route/Page 类型，也不封装 Navigator。0.1.0 只提供 `LxScope`，使用者可以把页面依赖绑定到 Widget 子树：

```dart
LxScope(
  bindings: (container) {
    container.lazyPut<CounterController>(
      () => CounterController(container.find<CounterRepository>()),
    );
  },
  child: const CounterPage(),
)
```

后期直接适配 `go_router`，不实现一套 LemonX 路由。适配建议放在独立包 `lemon_x_go_router` 中，使 `lemon_x` 核心包不依赖 `go_router`，两者可以独立升级。

未来适配只完成以下映射：

1. GoRoute 页面实例创建时，为该页面创建 `LxContainer` 子容器；
2. 执行页面 bindings，并通过 `LxScope` 暴露给页面 Widget；
3. 页面通过 `context.lx.find<T>()` 获取 Controller；
4. 页面实例从 go_router 的页面栈真正移除时，销毁对应容器；
5. 容器销毁时调用其中 Controller 的 `onDispose()`。

生命周期约定：

| 页面事件 | 容器行为 | Controller 行为 |
| --- | --- | --- |
| 页面实例创建 | 创建子容器并执行 bindings | `put` 立即构造并执行 `onInit()`；lazy 实例暂不创建 |
| 首次 `find` | 创建并缓存 lazy 实例 | 执行 `onInit()` |
| 首帧完成 | 容器保持有效 | 已创建 Controller 执行一次 `onReady()` |
| 页面被另一页覆盖 | 不处理 | 保持实例，不销毁 |
| 页面恢复 | 不处理 | 继续使用原实例 |
| 页面实例从栈中移除 | 销毁子容器 | 执行 `onDispose()` |

适配器必须正确处理同一路径的多个页面实例、ShellRoute/StatefulShellRoute 分支保活、重定向、返回手势以及页面 key 复用。判断销毁的依据是页面实例离开路由栈，而不是 Widget 的一次 rebuild。

`lemon_x_go_router` 只提供 bindings 和作用域生命周期桥接，不封装 `go()`、`push()`、`pop()`，不管理路径、参数、重定向或守卫。这些全部继续使用 `go_router` 原生 API。

## 7. 推荐使用方式

```dart
class CounterController extends LxController {
  final count = 0.obs;

  void increment() => count.value++;
}

void main() {
  runApp(
    LemonApp(
      bindings: (it) {
        it.lazyPut<CounterController>(() => CounterController());
      },
      child: const MaterialApp(home: CounterPage()),
    ),
  );
}

class CounterPage extends StatelessWidget {
  const CounterPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.lx.find<CounterController>();

    return Scaffold(
      body: Center(
        child: Obx(() => Text('${controller.count.value}')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: controller.increment,
        child: const Icon(Icons.add),
      ),
    );
  }
}
```

## 8. 更新与调度语义

1. `Rx.value = next` 同步更新值；
2. 状态监听器同步收到失效通知；
3. Widget 通过 `markNeedsBuild` 进入 Flutter 当前调度周期，不直接调用 build；
4. Effect 默认在 microtask 中批量执行；
5. `rxBatch(() { ... })` 可显式合并多次通知，普通赋值不会默认进入 batch。

```dart
rxBatch(() {
  firstName.value = 'Ada';
  lastName.value = 'Lovelace';
});
```

批处理只合并通知，不回滚状态。状态值在 batch 内仍然立即改变，但 listener 和 Worker 通知推迟到最外层 batch 结束；每个发生变化的 Rx 最多通知一次，监听器看到最终值。

| 行为 | 普通赋值 | `rxBatch` |
| --- | --- | --- |
| `.value` 更新 | 立即 | 立即 |
| Rx listener | 每次有效赋值同步通知 | 最外层 batch 结束后，每个 Rx 一次 |
| `ever` | 每次有效变化执行 | batch 结束后执行一次 |
| `Obx` | Flutter 调度下一帧 | Flutter 调度下一帧 |
| 同一个 `Obx` 的同帧重建 | Flutter 通常自动合并为一次 | 一次 |
| 异常回滚 | 不支持 | 不支持 |

保持普通 listener 同步通知，是为了兼容 `ValueListenable` 的直观语义：

```dart
count.value = 1;
assert(count.value == 1);
assert(listenerCalled);
```

`rxBatch` 支持嵌套；只有最外层结束时发送通知。即使回调抛出异常，也必须通过 `try/finally` 恢复调度状态，并为已经完成的状态修改发送最终通知。

响应式通知使用监听器快照遍历，允许监听器在回调中取消自身。Worker 销毁后，即使已有 microtask 排队也不得再次执行。`RxList`、`RxMap`、`RxSet` 的一次公开可变操作最多发送一次通知。

为避免 build 中更新造成难以定位的问题，在 Flutter debug 模式下，如果 `Obx` 构建期间修改其已读取状态，抛出带状态创建位置的诊断错误。

## 9. 错误与诊断

提供结构化异常，而不是仅使用字符串断言：

- `LxNotFoundError`：依赖未注册，包含类型、tag 和已查找的作用域；
- `LxAlreadyRegisteredError`：非幂等注册 API 与当前 key 冲突；
- `LxCircularDependencyError`：DI 或 computed 出现循环依赖；
- `LxDisposedError`：访问已销毁对象；
- `LxInvalidMutationError`：不允许的构建/计算期间写入。

Debug 模式下响应式节点可指定名称：

```dart
final count = Rx(0, debugLabel: 'CounterController.count');
```

### 9.1 依赖容器诊断日志

所有加入容器的对象都产生结构化诊断事件。开发模式下，根容器默认打印注册、创建、重复、替换、移除和销毁事件，方便发现对象被意外放入全局作用域或未按预期销毁。

```text
[LemonX][root] PUT       Logger#184728
[LemonX][root] LAZY_PUT  ApiClient
[LemonX][root] CREATE    ApiClient#938271
[LemonX][root] REPLACE   Logger#184728 -> FakeLogger#927361
[LemonX][root] DISPOSE   Logger#184728
[LemonX][root] RESET     disposed=5
```

子容器必须带可识别的作用域名称：

```text
[LemonX][route:/orders] CREATE   OrderController#182736
[LemonX][route:/orders] DISPOSE  OrderController#182736
```

事件类型至少包括：

```dart
enum LxDiEventType {
  register,
  create,
  find,
  duplicate,
  replace,
  remove,
  dispose,
  reset,
}
```

每个事件包含 `type`、`scope`、依赖类型、tag、实例 identity、时间戳和可选调用栈。容器只产生事件，不依赖第三方日志框架；格式化和输出由 `LxDiagnostics` 负责：

```dart
LxDiagnostics.configure(
  enabled: kDebugMode,
  logFind: false,
  includeStackTrace: true,
  onEvent: (event) => debugPrint(event.format()),
);
```

默认行为：

- Debug 模式开启，Release 模式完全关闭；
- 默认记录 register/create/duplicate/replace/remove/dispose/reset；
- `find` 频率高，默认不打印，仅在 verbose 或 `logFind: true` 时启用；
- 重复 `put` 即使成功去重，也发送 duplicate 事件并标明复用的实例；
- 根容器事件使用 `[root]`，局部容器使用其 `debugLabel`；
- 可选调用栈用于定位注册来源，但框架不尝试自动判断某次注册是否违反架构分层；
- 不调用依赖对象的 `toString()`，不输出字段内容，只记录类型、tag、作用域和 `identityHashCode`，避免泄露 token 或用户数据；
- 关闭诊断后不采集调用栈，并尽量消除字符串格式化开销。

开发工具可以订阅结构化事件构建当前容器快照，但这属于诊断展示层，不进入状态管理或 DI 内核。

## 10. 测试策略

### 10.1 响应式内核

- 相等值不通知，`refresh()` 强制通知；
- `Obx` 动态依赖切换后取消旧订阅；
- 嵌套 `Obx` 分别收集直接依赖，跟踪栈在 build 抛错后通过 `try/finally` 正确恢复；
- computed 缓存、懒计算、链式失效与循环检测；
- effect 去重、清理函数和销毁；
- batch 嵌套和异常退出后仍恢复调度状态；
- 普通 listener 同步通知，batch 内只在结束时通知最终值；
- listener 在通知期间取消自身不会破坏遍历；
- Worker 销毁后忽略已排队任务；
- 响应式集合一次可变操作只通知一次；
- 已销毁节点的访问行为；
- `RxAsync` 三态互斥、可空 data、错误 StackTrace、guard 成功与失败路径。

### 10.2 依赖容器

- 各注册模式的创建次数；
- 父子容器查找与覆盖；
- tag 隔离；
- 同步与异步循环依赖；
- 并发异步初始化及失败重试；
- builder/onInit 失败后回滚，后续允许重试；
- 当前作用域去重与父作用域 shadow；
- 逆序销毁、只销毁一次和外部实例所有权；
- 同一对象通过多个 key 注册时仍只销毁一次；
- `putInstance` 默认不销毁，`owned: true` 才转移所有权；
- active/disposing/disposed 状态转换及 dispose 幂等；
- 异步销毁继续执行并汇总错误；
- 父容器销毁前先销毁所有子容器；
- replace/reset 后无残留注册。
- 根容器与子容器产生正确的结构化诊断事件；
- 关闭诊断时不采集调用栈，Release 配置不输出日志；
- 日志不调用实例 `toString()`，不暴露对象字段内容。

### 10.3 Flutter 集成

- 只重建读取了变化状态的 `Obx`；
- 条件读取能够切换订阅；
- `LxScope` 卸载时释放 Controller；
- 外部容器默认不会被 Widget 销毁；
- `onReady()` 只调用一次且发生在首帧后。

## 11. 建议目录结构

```text
lib/
  lemon_x.dart
  src/
    reactive/
      rx.dart
      rx_async.dart
      rx_computed.dart
      rx_effect.dart
      tracking.dart
      scheduler.dart
    di/
      container.dart
      registration.dart
      lifecycle.dart
      errors.dart
    flutter/
      obx.dart
      rx_builder.dart
      lx_scope.dart
      lemon_app.dart
      context_extension.dart
    diagnostics/
      diagnostics.dart
```

公开入口 `lemon_x.dart` 只导出稳定 API；跟踪器、调度器和注册记录保持 internal。

## 12. 实施阶段

### M1：响应式 MVP

- `Rx<T>`、常用 Rx 类型和 `.obs` 扩展；
- `Obx`、`RxBuilder<T>`；
- 自动依赖收集和动态取消订阅；
- dispose、refresh、batch；
- 单元测试与 Widget 测试。

### M2：依赖注入 MVP

- 独立 `LxContainer`；
- put、putInstance、lazyPut、factory、find、tag；
- 父子作用域、replace、remove、reset；
- `LxController` 和销毁协议；
- 同步循环依赖检测与初始化失败回滚；
- 容器状态机、实例所有权和异步销毁；
- `LxScope`、`LemonApp`、`context.lx`、`Lemon`。

### M3：派生与异步能力

- `RxComputed`、`RxAsync`、`RxEffect` 和基础 Worker；
- putAsync/findAsync 和并发去重；
- 异步循环依赖检测；
- diagnostics 事件。

### M4：稳定化

- example 应用和完整 README；
- 性能基准：核心读写、通知、对象创建和代表性 Widget 重建；
- API 文档与迁移指南；
- 公开 API 兼容性审查后发布 0.1.0。

## 13. 首版公开 API 清单

```text
Reactive
  Rx<T>, Rxn<T>, RxInt, RxDouble, RxBool, RxString
  RxList<E>, RxMap<K, V>, RxSet<E>
  RxComputed<T>, RxAsync<T>, RxEffect, Worker
  .obs, rxEffect(), ever(), once(), debounce(), interval(), rxBatch()

Flutter
  Obx, RxBuilder<T>
  LxScope, LemonApp, BuildContext.lx

DI / lifecycle
  LxContainer, Lemon
  LxController, LxDisposable
  put, putInstance, lazyPut, factory, putAsync
  find, findAsync, contains, replace, remove, reset

Diagnostics
  LxDiagnostics and typed Lx errors
```

## 14. 已确定的设计决策

以下决策按本项目 0.1.0 的默认建议正式确定：

1. `RxList`、`RxMap`、`RxSet` 在首版支持常用可变操作并自动通知；
2. 保留默认可用的 `Lemon` 根容器，同时文档优先使用 `LemonApp`、`context.lx` 和独立 `LxContainer`；
3. 首版提供 `ever`、`once`、`debounce`、`interval` Worker；
4. 首版提供 `RxComputed` 与基础 `rxEffect`；普通派生值仍优先推荐 Dart getter；
5. 不实现 GetX 的 `permanent` / `fenix`，使用根作用域、Route 作用域和 lazy factory 表达生命周期；
6. `put` 使用立即构造式 builder，并在执行 builder 前按 `(Type, tag)` 去重；
7. 页面依赖通过 `context.lx.find<T>()` 获取，`Lemon.find<T>()` 只读取根容器；
8. 核心包不实现 Route/Page 类型；后期通过独立的 `lemon_x_go_router` 包适配页面 DI 生命周期。
9. `putInstance` 默认不转移所有权，只有 `owned: true` 时容器负责销毁；
10. 销毁协议支持 `FutureOr<void>`，容器采用 active/disposing/disposed 状态机；
11. 初始化失败必须回滚，失败的异步 Future 不缓存；
12. 去重只发生在当前容器，子容器允许 shadow 父容器；
13. 同步循环依赖检测属于 DI MVP；
14. 普通 Rx 更新同步通知，批量通知必须显式调用 `rxBatch`；
15. `RxAsync<T>` 只提供 loading/data/error 三态，保持可选且仅用于 presentation 层。

## 15. 最终范围约束

LemonX 始终只包含以下两类能力：

1. 状态管理：Rx、Obx、派生状态、Worker 和响应式调度；
2. 依赖注入：容器、作用域、注册查找、Controller 生命周期和销毁。

未来的 `go_router` 绑定只是第二项的生命周期适配：页面实例离开路由栈时，销毁对应 DI 子容器和其中的 Controller。核心包不提供路由或导航能力。

项目不加入导航、路由管理、国际化、主题管理、网络请求、缓存、持久化、日志、Snackbar、Dialog、BottomSheet 或其他 UI 工具。

## 16. 低侵入与退出策略

### 16.1 硬性约束

- Domain model、DTO、Repository 和 Service 必须能够保持为普通 Dart 类；
- 不使用注解、代码生成、反射或框架专用构造函数；
- 构造函数注入是业务对象之间传递依赖的首选方式；
- `LxController`、`Rx`、`Obx` 和 `context.lx` 只建议出现在 presentation/composition 层；
- 核心 API 不修改 `MaterialApp`、Navigator、go_router 或 Flutter binding 的全局行为；
- 不要求应用使用 `LemonApp`，用户可以直接创建 `LxContainer` 或完全不用容器；
- 不接管 `runApp()`，不使用隐藏的全局 Zone，不 monkey patch Flutter 生命周期；
- 每项能力可以单独使用：使用 Rx 不要求使用 DI，使用 DI 也不要求使用 Rx。

### 16.2 与 Flutter 原生接口互操作

`Rx<T>` 实现 Flutter 的 `ValueListenable<T>`，因此不使用 `Obx` 也能直接通过原生 Widget 监听：

```dart
final count = 0.obs;

ValueListenableBuilder<int>(
  valueListenable: count,
  builder: (_, value, __) => Text('$value'),
)
```

需要把 Rx 暴露给外部模块时，优先暴露原生接口而不是具体类型：

```dart
class CounterPresenter {
  final RxInt _count = 0.obs;

  ValueListenable<int> get count => _count;

  void increment() => _count.value++;
}
```

这样调用方不知道 LemonX 的存在，后续可以把内部实现直接换成 `ValueNotifier<int>`。

### 16.3 依赖注入退出路径

容器不注入字段，也不生成对象。业务类继续使用普通构造函数：

```dart
class AuthRepository {
  AuthRepository(this.client);

  final ApiClient client;
}
```

使用 LemonX 时，组装发生在应用边界：

```dart
container.lazyPut(
  () => AuthRepository(container.find<ApiClient>()),
);
```

移除 LemonX 后，只需改为原生手工组装：

```dart
final client = ApiClient();
final repository = AuthRepository(client);
```

`find()` 不应散落在 Repository、Service 或 Domain 逻辑中。否则切换容器时需要修改大量业务代码。

### 16.4 状态管理退出路径

建议按照以下边界使用：

```text
Domain / data       普通 Dart 值、Stream、Future
Presentation        Rx、Worker（可选）
Flutter Widget      Obx 或 ValueListenableBuilder
Composition root    LxContainer、bindings、LxScope
```

对应替换关系：

| LemonX | Flutter/Dart 原生替代 | 迁移影响 |
| --- | --- | --- |
| `Rx<T>` | `ValueNotifier<T>` | 替换状态字段实现 |
| `RxAsync<T>` | 自定义 sealed state + `ValueNotifier` | 替换异步展示状态 |
| `Obx` | `ValueListenableBuilder` / `ListenableBuilder` | 逐个 Widget 替换 |
| Worker | `addListener`、Timer、StreamSubscription | 逐个副作用替换 |
| `LxController` | 普通类 + `dispose()` | 去掉继承并显式释放 |
| `LxContainer` | 应用入口手工构造 | 只修改 composition root |
| `LxScope` | `InheritedWidget` 或构造参数下传 | 按页面逐步替换 |
| go_router 适配 | go_router 原生 builder/pageBuilder | 删除 bindings 包装 |

迁移可以逐页进行：同一个应用中允许部分页面使用 `Obx`，其他页面使用 `ValueListenableBuilder`；部分依赖从容器获取，其他依赖通过构造参数传入。

### 16.5 禁止形成的框架耦合

实现和文档示例不得鼓励以下模式：

```dart
// 禁止：Domain/Repository 内直接访问全局容器
class OrderRepository {
  final client = Lemon.find<ApiClient>();
}

// 禁止：业务方法依赖 BuildContext 获取服务
Future<void> checkout(BuildContext context) async {
  final service = context.lx.find<CheckoutService>();
}
```

应改为普通构造函数注入：

```dart
class OrderRepository {
  OrderRepository(this.client);

  final ApiClient client;
}
```

代码评审和 example 应用以“删除 LemonX 后，改动是否主要集中在 UI 与 composition root”为低侵入验收标准。

# LemonX

一个专注于 Flutter 状态管理和依赖注入的轻量库。响应式 API 采用熟悉的 `Rx`、`.obs`、`Obx` 风格，依赖注入使用明确的父子作用域和所有权规则。

LemonX 不提供路由、网络、国际化或 UI 工具，也不要求业务类继承框架基类。`Rx<T>` 实现 `ValueListenable<T>`，可以逐步替换为 Flutter 原生写法。

## 状态管理

```dart
final count = 0.obs;

Obx(() => Text('${count.value}'));

count.value++;
```

普通赋值同步通知。需要让多个修改只在结束时通知一次，可以显式批处理：

```dart
rxBatch(() {
  firstName.value = 'Ada';
  lastName.value = 'Lovelace';
});
```

### 响应式集合

```dart
final items = <String>[].obs;
items.add('Lemon');
items.removeWhere((item) => item.isEmpty);
```

### Worker

```dart
final worker = debounce(
  keyword,
  search,
  time: const Duration(milliseconds: 400),
);

worker.dispose();
```

可用 Worker：`ever`、`once`、`debounce`、`interval`。

### 异步展示状态

`RxAsync<T>` 只表达 loading、data 和 error 三种互斥状态：

```dart
final user = RxAsync<User>();

await user.guard(repository.getUser);

Obx(() => user.when(
  loading: () => const CircularProgressIndicator(),
  data: (value) => Text(value.name),
  error: (error, stackTrace) => Text('$error'),
));
```

它不包含重试、缓存、持久化或网络逻辑；复杂业务状态仍应使用自定义类型配合 `Rx<T>`。

### Flutter 原生互操作

```dart
ValueListenableBuilder<int>(
  valueListenable: count,
  builder: (_, value, __) => Text('$value'),
);
```

## 依赖注入

应用级常驻依赖显式使用 `permanent: true`：

```dart
Lemon.put(ApiClient.new, permanent: true);
```

页面推荐只使用 `Lemon.put/find`。安装可选 Route Observer 后，普通注册自动归当前 Route 所有：

```dart
MaterialApp(
  navigatorObservers: [LemonRouteObserver()],
  home: const LoginPage(),
);
```

```dart
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Lemon.put(LoginController.new);
    return Obx(() => Text('${controller.count.value}'));
  }
}
```

Route 从 Navigator 栈移除后，页面注册会先从全局索引撤销，再执行 `onDispose()`。Observer 不接管 push、pop、路由表、参数或重定向；每个 Navigator 应创建自己的 `LemonRouteObserver`。

使用 go_router 时同样只需配置 Observer，其他路由 API 保持不变：

```dart
final router = GoRouter(
  observers: [LemonRouteObserver()],
  routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => const HomePage(),
    ),
  ],
);
```

`ShellRoute` 会创建嵌套 Navigator。根 Navigator 和 Shell Navigator 应分别使用不同的 Observer，并关闭 Shell 对根 Observer 的重复通知：

```dart
final rootNavigatorKey = GlobalKey<NavigatorState>();
final shellNavigatorKey = GlobalKey<NavigatorState>();

final router = GoRouter(
  navigatorKey: rootNavigatorKey,
  observers: [LemonRouteObserver()],
  routes: [
    ShellRoute(
      navigatorKey: shellNavigatorKey,
      notifyRootObserver: false,
      observers: [LemonRouteObserver()],
      builder: (_, __, child) => LxPage(
        bindings: (container) {
          container.put(ShellController.new);
        },
        child: AppShell(child: child),
      ),
      routes: [
        // Shell 内的页面路由……
      ],
    ),
  ],
);
```

外层 `LxPage` 只在需要 Shell 级共享实例时使用：子页面切换不会销毁 `ShellController`，整个 Shell 移出 Widget 树时才会销毁。仅使用各子页面自己的 Controller 时，不需要给 Shell 包 `LxPage`。

使用 `parentNavigatorKey: rootNavigatorKey` 打开的根层全屏页不属于 Shell 的 Widget 父链，但只要 Shell 仍在路由栈中，就可以通过全局 canonical 查找共享实例：

```dart
final controller = Lemon.find<ShellController>();
```

此处不要使用 `context.lx.find<ShellController>()`，也不要在全屏页重新 `put`。如果使用 `go/replace` 离开整个 Shell，外层 `LxPage` 会卸载，Shell 实例随之销毁。

`StatefulShellRoute` 的每个 `StatefulShellBranch` 都有独立 Navigator，因此每个分支配置独立 Observer；整个 Shell 共享的实例仍放在 builder 外层的 `LxPage`：

```dart
StatefulShellRoute.indexedStack(
  notifyRootObserver: false,
  builder: (_, __, navigationShell) => LxPage(
    bindings: (container) {
      container.put(ShellController.new);
    },
    child: AppShell(navigationShell: navigationShell),
  ),
  branches: [
    StatefulShellBranch(
      observers: [LemonRouteObserver()],
      routes: [/* 首页分支 */],
    ),
    StatefulShellBranch(
      observers: [LemonRouteObserver()],
      routes: [/* 我的分支 */],
    ),
  ],
);
```

需要每个分支各自长期持有同类型实例时，应在各分支根部提供独立 `LxPage`，并使用不同 `tag`；不要依赖相同 `(Type, tag)` 的首次注册复用来表达共享生命周期。

无 Context 的 `Lemon.put()` 只能表达一个“当前活跃导航位置”。双栏、桌面多窗格等多个 Navigator 同时可见时，最后一次 Route 事件决定当前 owner，框架无法从无 Context 调用反推出调用方属于哪个 Navigator。此类界面应在每个窗格的 `LxPage.bindings` 中直接注册，并用 `context.lx` 做严格父链查找；不要依赖全局当前 Route 归属。

### 不监听路由

不安装 Observer 时，用一层 `LxPage` 提供 Widget 生命周期所有权：

```dart
LxPage(
  child: const LoginPage(),
);
```

`LoginPage` 内仍然使用同样的 `Lemon.put/find`，`LxPage` 卸载时自动销毁。未安装 Observer、也没有 `LxPage` 时，非 permanent 的 `Lemon.put()` 会抛出 `LxNoPageScopeError`，不会静默泄漏为根级常驻对象。

任意位置（包括 Dialog、BottomSheet、Overlay 和异步回调）统一查找：

```dart
final controller = Lemon.find<LoginController>();
```

相同 `(Type, tag)` 始终复用首次 canonical 注册，后续 builder 不执行、不替换 owner；需要多个同类型实例时使用不同 `tag`。

### 进阶作用域

复杂组装、严格父链查找或非页面子树仍可使用 `LxScope`、`LxStateOwner`、`context.lx` 和独立 `LxContainer`：

```dart
LxScope(
  bindings: (container) {
    container.lazyPut(CounterController.new);
  },
  child: const CounterPage(),
);
```

`bindings` 使用专用注册器，`put()` 和 `lazyPut()` 会直接从构造函数推断类型。代码块和箭头写法都安全：

```dart
bindings: (container) => container.put(CounterController.new),
```

```dart
final controller = context.lx.find<CounterController>();
```

`context.lx.find()` 只查找当前 Scope 到父 Scope；`Lemon.find()` 始终使用全局 canonical 索引。`Lemon.remove()` 只能删除根注册或当前页面 owner 自己持有的注册，不能跨页面删除 Controller。

Repository 和 Service 之间仍建议使用普通构造函数注入，不要在业务类内部访问全局容器。

## Controller 生命周期

```dart
class CounterController extends LxController {
  final count = 0.obs;

  void increment() => count.value++;

  @override
  void onInit() {}

  @override
  void onReady() {}

  @override
  void onDispose() {}
}
```

`LxController` 是可选便利基类。普通 Dart 对象也能注册，并通过 `dispose` 回调释放。

## 异步依赖

```dart
await container.putAsync<Database>(() async {
  final database = Database();
  await database.open();
  return database;
});

final database = await container.findAsync<Database>();
```

并发查找共享同一个初始化 Future；失败不会被缓存，后续调用可以重试。

## 性能基准

以下结果用于观察不同状态管理实现自身的相对开销，不代表完整应用的 FPS。测试环境为 Windows x64、Flutter 3.44.6、Dart 3.12.2，使用 `flutter_test` 的 Debug/JIT 模式。每个基准启动 3 个独立测试进程；每个进程先预热，再执行 5 轮并取中位数。表格报告 3 个进程中位数的中位数和 `[最小值–最大值]`，数值越低越好。

对比版本：LemonX 0.2.0、GetX Plus 5.2.0、Provider 6.1.5+1、flutter_bloc 9.1.1、Riverpod 3.3.2、Signals 7.1.0、MobX 2.6.0。

### 状态核心路径

读取测试预先创建 1024 个不同的状态对象，通过运行时生成的 4096 项伪随机索引表循环访问，防止 JIT 将不变 getter 提到循环外；`List<int>` 使用完全相同的索引路径作为基线。连续写入均使用不同的整数值；“一个监听者”表示状态变化确实送达一个订阅者。Provider 的核心状态使用其常见的 `ChangeNotifier` 模型。

| 框架 | 读取 ns/op | 无监听写入 ns/op | 一个监听者写入 ns/op | 状态对象创建 ns/op |
| --- | ---: | ---: | ---: | ---: |
| `List<int>` 基线 | **0.7 [0.6–0.9]** | — | — | — |
| **LemonX** | 3.6 [3.6–4.0] | **4.8 [4.4–5.2]** | 30.5 [26.1–34.3] | 35.6 [33.9–45.9] |
| GetX Plus | 1.9 [1.7–1.9] | 19.8 [19.1–20.5] | 36.7 [36.4–39.0] | 56.5 [49.5–81.4] |
| Raw ChangeNotifier | 0.7 [0.7–0.8] | 13.7 [12.4–14.1] | **20.1 [19.6–23.1]** | 24.3 [18.6–33.5] |
| BLoC / Cubit | 0.8 [0.6–1.2] | 13.3 [12.7–14.6] | 29.8 [26.4–42.1]¹ | **27.1 [22.6–30.4]** |
| Signals | 5.8 [5.6–5.9] | 219.6 [215.3–230.8] | 310.6 [306.2–321.4] | 9121.8 [8948.3–10734.5] |
| MobX | 15.8 [14.5–16.8] | 61.5 [54.6–64.9] | 1731.0 [1647.4–1840.0] | 399.8 [392.4–722.8] |
| Riverpod `StateProvider` | 2175.6 [2061.1–2629.7]² | 7036.9 [6870.9–8086.3] | 6760.3 [6705.2–8472.3] | — |

1. Cubit 的 Stream 异步投递；该值只测量 `emit`/入队，不包含回调最终执行时间。
2. Riverpod 读取使用其公共 `ProviderContainer.read` 路径，包含容器查找；它与直接字段 getter 的语义并不完全相同。

Provider 和 Cubit 的读取与 `List<int>` 基线基本一致，说明其普通字段 getter 被 JIT 内联后几乎没有额外工作。LemonX 的读取包含销毁检查和 Obx 自动依赖收集，因此稳定多出约 3 ns；在更接近实际响应式使用的写入和同步通知路径上，LemonX 与原生 `ChangeNotifier` 处于同一梯队。对象创建结果容易受到 GC 时机影响，其波动范围比读取和写入更大。

### Widget 重建

每次样本执行 250 次“写入不同状态 → `pump()` 直到观察组件实际完成一次重建”，共 5 轮并取中位数。所有框架都验证了父组件不重建，只有目标观察组件重建一次。为消除 JIT 启动和执行顺序偏差，所有实现先统一预热，正式样本再交错执行；下表同样汇总 3 个独立测试进程。

| 排名 | Widget | μs/重建，中位数 `[范围]` | pump/重建 |
| ---: | --- | ---: | ---: |
| 1 | Signals `SignalBuilder` | **310.9 [309.9–337.3]** | 1.00 |
| 2 | **LemonX `Obx`** | **325.1 [265.8–332.1]** | **1.00** |
| 3 | GetX Plus `Obx` | 346.0 [337.8–348.6] | 2.00 |
| 4 | Provider `Consumer` | 348.9 [318.7–361.7] | 1.00 |
| 5 | MobX `Observer` | 358.4 [315.2–366.1] | 1.00 |
| 6 | Riverpod `Consumer` | 364.1 [338.1–367.9] | 1.00 |
| 7 | BLoC `BlocBuilder` | 380.6 [372.4–392.1] | 2.00 |

`pump/重建` 只描述 `flutter_test` 中从写入到观察到重建所需的 pump 次数，不应直接解释为真实设备上的可见 vsync 帧数。Widget 结果受机器、Flutter 版本和运行模式影响，建议关注数量级和重复运行的稳定区间，而不是几微秒的单次差异。

复现命令：

```bash
cd benchmark
flutter pub get
flutter test core_benchmark.dart
flutter test mainstream_state_benchmark.dart
flutter test widget_rebuild_benchmark.dart
```

完整测试实现见 [`benchmark/`](benchmark/)。

### DI 重构回归

canonical 全局索引重构后，`core_benchmark.dart` 额外覆盖严格 Scope 查找、`Lemon.find()` 全局查找，以及 Scope 创建/注册/销毁。诊断关闭，连续运行 3 个独立测试进程；下表仍报告进程中位数的中位数和 `[最小值–最大值]`。

| 路径 | LemonX | GetX Plus | 相对结果 |
| --- | ---: | ---: | ---: |
| 严格 Scope `find` | **48.1 [47.3–52.5] ns/op** | 590.9 [421.7–627.5] ns/op | LemonX 快约 12.3× |
| 全局 `Lemon.find` | **67.1 [50.8–69.6] ns/op** | 596.1 [556.6–596.3] ns/op | LemonX 快约 8.9× |
| Scope 创建 + 注册 + 销毁 | 34.3 [22.8–34.7] μs/周期 | — | 1 万次循环后索引无残留 |

严格查找与全局查找处于同一数量级；新增所有权和 canonical 索引主要增加注册、销毁阶段的维护，不会把页面重建或 Rx 读写带入 DI 路径。

## 项目边界

LemonX 只包含状态管理和依赖注入，不接管 Navigator。页面生命周期可以由可选 `LemonRouteObserver` 驱动，也可以通过 `LxPage`、`LxStateOwner` 或 `LxScope` 绑定到 Flutter Widget 的销毁时机。

迁移说明见 [doc/migration_from_getx.md](doc/migration_from_getx.md)，完整设计见 [doc/design.md](doc/design.md)。

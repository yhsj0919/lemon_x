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

### Flutter 原生互操作

```dart
ValueListenableBuilder<int>(
  valueListenable: count,
  builder: (_, value, __) => Text('$value'),
);
```

## 依赖注入

```dart
final container = LxContainer(debugLabel: 'app');

final api = container.put(() => ApiClient());

container.lazyPut(
  () => AuthRepository(container.find<ApiClient>()),
);

final repository = container.find<AuthRepository>();
```

`put` 是立即构造式注册，并在执行 builder 前按 `(Type, tag)` 去重：

```dart
final first = container.put(() => CounterController());
final second = container.put(() => CounterController());

identical(first, second); // true
```

已有实例通过 `putInstance` 注册，默认仍由外部管理：

```dart
container.putInstance(client); // 容器不销毁 client
container.putInstance(cache, owned: true); // 转移所有权
```

### Widget 作用域

```dart
LxScope(
  bindings: (container) {
    container.lazyPut(() => CounterController());
  },
  child: const CounterPage(),
);
```

页面内从最近作用域查找：

```dart
final controller = context.lx.find<CounterController>();
```

作用域卸载后，其拥有的 Controller 会执行 `onDispose()`。应用级服务可以放入 `Lemon` 根容器：

```dart
Lemon.put(() => AnalyticsService());
final analytics = Lemon.find<AnalyticsService>();
```

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

## 项目边界

LemonX 只包含状态管理和依赖注入。未来的 go_router 支持会作为独立适配包，只负责把页面销毁映射为 DI 作用域销毁。

完整设计见 [docs/design.md](docs/design.md)。

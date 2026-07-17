# 从 GetX 迁移到 LemonX

LemonX 只覆盖响应式状态与依赖注入，不提供导航、网络、国际化或全局 UI 工具。迁移可以逐页进行，不要求一次性替换整个应用。

## 响应式状态

基础状态声明和 `Obx` 用法基本一致：

```dart
final count = 0.obs;

Obx(() => Text('${count.value}'));
```

LemonX 的 `Rx<T>` 实现 `ValueListenable<T>`，因此也可以逐步替换为 Flutter 原生 `ValueListenableBuilder`。多个同步修改需要合并通知时，显式使用 `rxBatch()`。

## Controller

将 `GetxController` 改为可选的 `LxController`：

```dart
class CounterController extends LxController {
  final count = 0.obs;

  @override
  void onDispose() {}
}
```

`onInit()`、`onReady()` 和 `onDispose()` 分别对应注册、作用域首帧完成和容器移除。普通 Dart 对象不必继承 `LxController`。

## 依赖注入

应用级服务显式注册为 permanent：

```dart
Lemon.put(ApiClient.new, permanent: true);
final api = Lemon.find<ApiClient>();
```

安装可选 Observer 后，页面可以直接使用接近 GetX 的写法：

```dart
MaterialApp(
  navigatorObservers: [LemonRouteObserver()],
  home: const CounterPage(),
);

final controller = Lemon.put(CounterController.new);
```

不使用 Observer 时，给页面包一层 `LxPage`：

```dart
LxPage(
  child: const CounterPage(),
);
```

普通弹窗不在页面 Widget 子树中，可以通过全局 canonical 索引获取页面注册：

```dart
final controller = Lemon.find<CounterController>();
```

相同 `(Type, tag)` 始终复用首次注册，不提供覆盖或 `fenix`。非 permanent 注册必须存在当前 Route 或 `LxPage` owner，否则会抛出 `LxNoPageScopeError`，不会静默变成根级常驻对象。

## 导航

删除 `GetMaterialApp`、`Get.to()`、`Get.back()` 和 `GetPage` 等调用，继续使用 Flutter `Navigator`、go_router 或自研路由。`LemonRouteObserver` 只把 Route 进出翻译为页面 Scope 创建和销毁，不管理路径、参数、重定向或导航 API。

## 退出 LemonX

状态可以从 `Obx` 逐步替换为 `ValueListenableBuilder`，依赖可以从 `context.lx.find()` 逐步替换为构造函数参数。Domain、DTO、Repository 和 Service 应保持为普通 Dart 类型，使迁移集中在 UI 和 composition root。

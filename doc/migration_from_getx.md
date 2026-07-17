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

应用级服务可以通过根容器注册：

```dart
Lemon.put<ApiClient>(() => ApiClient());
final api = Lemon.find<ApiClient>();
```

`StatefulWidget` 页面可以使用 Mixin，获得接近 `Get.put()` 的声明方式，同时绑定页面生命周期：

```dart
class _CounterPageState extends State<CounterPage>
    with LxStateOwner<CounterPage> {
  late final controller = put(CounterController.new);
}
```

无法使用 Mixin，或需要一次注册多个依赖时使用 Widget 作用域：

```dart
LxScope(
  bindings: (container) {
    container.lazyPut<CounterController>(() => CounterController());
  },
  child: const CounterPage(),
);

final controller = context.lx.find<CounterController>();
```

普通弹窗不在页面 Widget 子树中，可以通过全局 canonical 索引获取页面注册：

```dart
final controller = Lemon.find<CounterController>();
```

相同 `(Type, tag)` 始终复用首次注册，不提供覆盖或 `fenix`。长期对象使用 `Lemon.put()`，也可以在 bindings 中指定 `permanent: true`；页面对象放在 `LxStateOwner` 或 `LxScope`，需要延迟创建时使用 `lazyPut()`。

## 导航

删除 `GetMaterialApp`、`Get.to()`、`Get.back()` 和 `GetPage` 等调用，改用 Flutter `Navigator` 或独立路由包。LemonX 不接管路由生命周期；页面离开 Widget 树时，由 `LxStateOwner` 或包裹页面的 `LxScope` 释放依赖。

## 退出 LemonX

状态可以从 `Obx` 逐步替换为 `ValueListenableBuilder`，依赖可以从 `context.lx.find()` 逐步替换为构造函数参数。Domain、DTO、Repository 和 Service 应保持为普通 Dart 类型，使迁移集中在 UI 和 composition root。

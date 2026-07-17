# LemonX 页面生命周期设计

状态：已实现  
版本：0.2.0

## 目标

日常页面只使用 `Lemon.put/find`，同时保持单 owner、canonical 全局查找和自动销毁：

```dart
final controller = Lemon.put(LoginController.new);
final same = Lemon.find<LoginController>();
```

LemonX 不提供导航 API，不替换 `MaterialApp`，也不管理路径、参数、重定向或守卫。

## 两种页面 owner

### Route owner

每个 Navigator 安装独立 Observer：

```dart
MaterialApp(
  navigatorObservers: [LemonRouteObserver()],
  home: const LoginPage(),
);
```

Observer 只把 Route push/pop/remove/replace 翻译为页面容器创建、激活和销毁。普通 pop 会等待退出动画完成后销毁；remove/replace 会立即撤销旧 canonical，避免新页面误复用旧 Controller。

## go_router 配置

### 普通根路由

将独立 Observer 放入 `GoRouter.observers`：

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

### ShellRoute

`ShellRoute` 使用嵌套 Navigator。根 Navigator 和 Shell Navigator 各安装一个不同的 `LemonRouteObserver`，并设置 `notifyRootObserver: false`，避免同一次 Shell 导航被两个 Observer 重复处理：

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
        // Shell 子路由……
      ],
    ),
  ],
);
```

这里的 `LxPage` 是 Shell 级 owner，只在需要跨 Shell 子页面共享非 permanent 实例时使用：

- 子页面切换不会销毁 Shell 实例；
- 向根 Navigator push 全屏页时 Shell 仍在栈中，实例继续存活；
- 整个 Shell 被 go/replace 移除后，`LxPage` 卸载并销毁实例；
- 只有子页面独享 Controller 时，无需给 Shell 包 `LxPage`。

根层全屏页不在 Shell 的 Widget 父链内，应使用全局 canonical：

```dart
final controller = Lemon.find<ShellController>();
```

不要使用 `context.lx.find<ShellController>()`，也不要在全屏页重新注册同一实例。全屏页只是使用者，不取得所有权。

### StatefulShellRoute

`StatefulShellRoute` 为每个分支保留独立 Navigator。每个 `StatefulShellBranch` 安装自己的 Observer；Shell 公共实例由 builder 外层的 `LxPage` 持有：

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

分支切换会保留各分支 Navigator，不能把“当前可见分支”等同于 route push/pop。需要分支级长期实例时，在各分支根部使用独立 `LxPage`；相同类型的分支实例使用不同 `tag`。应用全局共享的服务则直接使用 `Lemon.put(..., permanent: true)`。

### 多个同时可见的 Navigator

无 Context 的 `Lemon.put()` 只能使用一个全局当前 Route owner。双栏、桌面多窗格等多个 Navigator 同时可见时，最后一次 Observer 路由事件获胜；后续无 Context 注册无法判断调用代码实际来自哪个窗格。

这种界面不要依赖全局当前 Route 注册，而是在各窗格的明确 owner 中直接组装：

```dart
LxPage(
  bindings: (container) {
    container.put(DetailPaneController.new);
  },
  child: const DetailPane(),
);
```

窗格子树通过 `context.lx.find<DetailPaneController>()` 使用严格父链；需要跨窗格访问时再显式使用 `Lemon.find`。这是无 Context 极简 API 的边界，不应把“最后一次 Route 事件”理解为 Flutter 的唯一可见页面。

### Widget owner

不监听路由时，用一层 `LxPage`：

```dart
LxPage(child: const LoginPage());
```

`LxPage` mount 时建立页面 owner，卸载时销毁。它同时向子树暴露严格 `context.lx` 容器。

## 注册规则

- `Lemon.put(..., permanent: true)` 始终注册到根容器；
- 非 permanent 的 `put/lazyPut/putInstance/factory/putAsync` 注册到当前 Route 或 `LxPage`；
- 没有当前页面 owner 时抛出 `LxNoPageScopeError`，不回退为根常驻；
- 最近的、属于当前 Route 的 `LxPage` 优先于 Route owner；
- 相同 `(Type, tag)` 首次 canonical 注册胜出，后续注册复用且不改变 owner；
- `Lemon.find` 使用全局 canonical 索引，因此 Dialog 和 Overlay 可以读取页面 Controller；
- `Lemon.remove` 只允许删除根注册或当前页面 owner 自己持有的注册。

## 保留的进阶入口

`LxScope`、`LxStateOwner`、`context.lx` 和独立 `LxContainer` 继续保留，用于严格父链、测试、复杂组装和非页面子树，不作为 README 首页主路径。

## 边界

Route 模式根据当前活跃 Route 归属无 Context 的 `Lemon.put`。推荐在 State 字段、`initState` 或页面同步 build 中注册；页面切换后的异步回调不应创建新的页面依赖。嵌套 Navigator 必须各自安装一个 `LemonRouteObserver`；多个同时可见的 Navigator 使用上文的显式 Widget owner。

本设计不引入引用计数、Lease、AutoDispose、fenix、生产 shadow、Controller pause/resume 或路由接管。

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

Route 模式根据当前活跃 Route 归属无 Context 的 `Lemon.put`。推荐在 State 字段、`initState` 或页面同步 build 中注册；页面切换后的异步回调不应创建新的页面依赖。嵌套 Navigator 必须各自安装一个 `LemonRouteObserver`。

本设计不引入引用计数、Lease、AutoDispose、fenix、生产 shadow、Controller pause/resume 或路由接管。

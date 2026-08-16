# Sliver widget 修复规划

> 状态:规划草案 · 关联 `docs/sliver-scroll-refactoring-plan.md`(该计划已完成协议/重构主体,本文档聚焦其遗留的渲染端 stub 与若干声明未兑现的问题)

## 背景与范围

sliver-scroll 重构已把 `ListView`/`Sparse_extent_list` 这两个 native widget 升级为协议核心节点(`sliver_fixed_extent` / `sliver_varied_extent` / `sliver_box` / `sliver_list` / `sliver_fill` / `sliver_padding` / `sliver_app_bar`),协议编解码、OCaml widget 构造器、`Scroll_view` + `ScrollViewScope` 共享控制器模型都已落地。但 Dart 渲染端(`widget_registry.dart` 的各 `_buildSliver*`)只完成了"能挂出来不崩"的最小 stub,虚拟化反馈环和若干 props 字段尚未兑现。

本文档规划修复以下四项(严重度由高到低):

| # | widget | 严重度 | 问题 |
|---|---|---|---|
| 1 | `Sliver_fixed_extent` / `Sliver_varied_extent` | 🔴 严重 | 虚拟化完全没实现: `total_count`/`first_index`/`overscan` 全忽略, `visible_range_changed`(tag 14) 事件不发, 反馈环断开; varied_extent 还丢了 extent/overrides/transition |
| 2 | `Sliver_fill` | 🟡 中 | `flex` 字段协议层有、渲染端没用, 声明的能力未兑现 |
| 3 | `Sliver_app_bar` | 🟡 中 | 子节点只能当 title, 缺 leading/flexibleSpace/bottom/actions + floating/snap/stretch 等; 高度参数无校验 |

不在本次范围(`Sliver_box` / `Sliver_list` / `Sliver_padding`): 实现已正确,仅 `Sliver_padding` 有一个类型层未表达"子节点必须是 sliver"的约束(见末尾"开放问题"),非本次修复目标。

## 约束与前提

- **AGENTS.md**: 不修改 `spec/` 下的 OCaml `.ml`/`.mli`,不修改 dune 文件。本 checkout 无 `spec/` 目录;协议定义在 `protocol/schema.sexp`(sexp 数据文件,非 OCaml spec)。**扩展协议字段需改 `protocol/schema.sexp` + `make protocol-generate` 重新生成 `generated_protocol.dart` / `generated_protocol.ml`**,这不违反 spec 约束,但属协议变更,需同步 OCaml widget 构造器(`ocaml/ui/widget.ml`)与 Dart 编解码(`binary_codec.dart`)。
- **事件管线已就绪**: `VisibleRangeEventPayload` 的编解码(`event_batch.dart:834/1060`)、tag 14(`EventTagId.visibleRangeChanged`)、coalescing(`event_batch_queue.dart:185-188`)、OCaml runtime 解码(`event_dispatcher.ml:121`)全部齐备。**缺的只是 Dart 渲染端的生产者。**
- **共享控制器已就绪**: `_buildScrollView` 已用 `ScrollViewScope` 把 `ScrollController` + `Axis` 发布给 sliver 子节点(`widget_registry.dart:507-572`)。`renderer_resource_store.dart` 的 `scrollTo(nodeId)` 仍按 nodeId 查控制器——虚拟化 sliver **不**应再自己 acquireScrollController,必须消费 `ScrollViewScope.of(context)`。
- **旧实现是迁移资产**: `native_widget/virtual_list.dart`(fixed) 与 `native_widget/sparse_extent_list.dart`(varied,含 `SparseExtentGeometry` + 过渡动画状态机)虽已从主源码删除,但仍 vendored 在各 `examples/*/.bonsai-flutter/...` 与 `_build/...` 下,状态机逻辑成熟,应提取复用。

---

## 修复一: `Sliver_fixed_extent` / `Sliver_varied_extent` 虚拟化落地

### 现状

```dart
// widget_registry.dart:606-621  — fixed
return SliverFixedExtentList(
  delegate: SliverChildListDelegate(children),   // 非 builder, 无 itemCount
  itemExtent: props.itemExtent,
);
// widget_registry.dart:623-635  — varied
return SliverList(delegate: SliverChildListDelegate(children));  // 退化为裸 SliverList
```

后果:可滚动总长 = `len(children)*extent`(而非 `total_count*extent`);`first_index != 0` 时窗口错位;滚动时 tag 14 永不发,OCaml 窗口永不前进;varied 的 extent/overrides/transition 全丢;无 `findChildIndexCallback`,窗口滑动丢 element 身份。

### 目标

落地 `flutter/.../renderer/sliver_virtual_host.dart`,内含 `_SliverFixedExtentHost` 与 `_SliverVariedExtentHost`,把旧 native host 的状态机迁移到 sliver + 共享控制器模型:

- 消费 `ScrollViewScope.of(context)` 拿父 `Scroll_view` 的 `ScrollController`,**不**自己 acquire。
- fixed → `SliverFixedExtentList(delegate: SliverChildBuilderDelegate(...), itemExtent: ...)`。
- varied → `SliverVariedExtentList(delegate: ..., extentBuilder: (i, _) => geometry.itemExtent(i))`。
- `itemCount = total_count`;`itemBuilder` 把逻辑 index 映射到窗口 index(`index - first_index`),窗口外返回 `SizedBox.shrink()`。
- `findChildIndexCallback` 按 child key 映射回 `first_index + windowIndex`,保 element 身份。
- 监听 `controller` 算可见区间,发 tag 14(`visible_range_changed`)。
- varied 复用 `SparseExtentGeometry`(二分查 extent / leadingOffset / visibleRange)与过渡动画状态机(anchor 校正、expand/collapse curve、reduce-motion 直接收束)。

### 设计决策点

#### D1. visible range 上报语义 + overscan ↔ cacheExtent 协调 — 已定方案 B

旧 `virtual_list.dart` 上报**纯可见区间** `[first, last)`,并把 `scrollCacheExtent = overscan * itemExtent` 设在自有的 `ListView` 上,让 Flutter 多渲染 overscan 屏外项;OCaml 侧收到纯可见区间后自己加 overscan 切窗口。

迁移到 sliver 模型后,`cacheExtent` 是 **viewport 级**(`CustomScrollView.cacheExtent`)而非 per-sliver,单个 sliver host 无法设置。若不协调,Flutter 默认 cacheExtent(≈250px)可能 < `overscan*extent`,导致用户滚动时新进入 cache 区的项不在 OCaml 发的窗口里 → 白屏。

**决策:采用方案 B** — `Scroll_view` props 加 `cache_extent: optional_f64`,OCaml 在挂虚拟化 sliver 时算 `max(子 sliver 的 overscan*extent)` 下发,`_buildScrollView` 直接传给 `CustomScrollView(cacheExtent: ...)`。visible range 仍上报纯可见区间,语义不变,OCaml 侧 `visible_range_of_payload` / 切窗逻辑不动。

**为什么选 B(设计合理性,不计工作量)**: 本质是"谁算 `cacheExtent == max(子 overscan*extent)` 这条约束"。OCaml 是 widget 树的唯一构造者,在构造 `Scroll_view` + 子 sliver 时天然持有所有 overscan/extent 值,在源头算一次 `max` 是单点、确定、无时序问题的计算——信息在它本来就在的地方被处理,是顺信息流。`Scroll_view` 已在协议里表达 `axis`/`reverse`/`primary`(viewport 怎么滚动),`cacheExtent` 同属 viewport 级属性,放这里语义自洽。方案 A(Dart 侧子→父向上收集)是逆信息流,且 Flutter widget 树父构造 slivers 列表时子尚未 build,向上收集涉及时序/dry-run 抖动等不确定性,仅为绕开"cacheExtent 只能设在父 viewport"的工程限制。方案 C 改 visible range 语义为"含 overscan 的需渲染窗口",语义污染且 `overscan*extent < 250` 时仍白屏,是设计倒退。

**性能**: B 无性能问题。OCaml 计算(O(子 sliver 数),个位数,纳秒级,仅 `Scroll_view` 节点变化时算)、协议传输(一个 `optional_f64`,9 字节)、Dart 解码(一次 `optionalFloat64()`)均可忽略。Flutter 渲染侧开销与方案 A **逐字节相同**——两者最终都给 `CustomScrollView` 设同一个 viewport 级 `cacheExtent = max(overscan*extent)`,虚拟化 sliver 的 cache 区项返回 `SizedBox.shrink()`(空占位,layout 极轻);非虚拟化 `sliver_list` 会多布局屏外真实子项,但这是"设大 cacheExtent"的固有代价,A 同样承担,且 `max(overscan*extent)` 有界(开发者显式选的 overscan)。当 `overscan*extent < 250` 时 B 显式设更小值反而比现状默认值**省工**。

**B 的正确性维护点(非性能)**: OCaml 必须在子 sliver 的 `overscan`/`extent` 变化时重算并重发 `scroll_view` 的 `cache_extent`,否则一帧 stale(极端下 stale 值偏小 → 白屏一瞬)。因 OCaml 是树唯一构造者,此不变式在本地守住:构造 `Scroll_view` 时强制遍历子算 max 作为构造器既定行为。无虚拟化子 sliver 时 `cache_extent = None` → Dart 用 Flutter 默认值,向后兼容。

**被否决方案(存档)**:
- 方案 A:sliver host 经 `InheritedWidget` 向上汇报,`_buildScrollView` 收集取 max。不改协议,但子→父向上收集涉 build 时序不确定性,是逆信息流的工程绕行。作为"避免协议变更的降级路径"保留,不采用。
- 方案 C:visible range 上报含 overscan,Flutter 用默认 cacheExtent。语义污染(可见 ≠ 需渲染)+ 小 overscan 仍白屏,设计倒退,否决。

#### D2. 初始锚定 (`first_index`)

旧实现把控制器 `initialScrollOffset = first_index * itemExtent`(fixed)或 `geometry.leadingOffset(first_index)`(varied)。sliver 模型下控制器由 `Scroll_view` 持有,`first_index` 在 sliver 节点上。host 首次 attach 时若 `controller.offset == 0` 且 `first_index > 0`,应 `jumpTo(geometry.leadingOffset(first_index))` 校正一次(需防抖:仅在尚未有用户交互时)。varied 的过渡动画也会改 extent 导致 offset 漂移,沿用旧 `_captureAnchor` + `_scheduleAnchorCorrection`(`position.correctBy`)即可。

#### D3. primary scroll controller

`Scroll_view` 的 `primary` 节点用 `PrimaryScrollController.maybeOf(context)`(路由级),非 primary 用 `resources.acquireScrollController(node.id)`。虚拟化 sliver host 通过 `ScrollViewScope.of(context)` 拿到的是同一个控制器,无需区分。但需注意:host 在 `dispose` 时只 `removeListener`,**不** dispose 控制器(控制器生命周期归 `Scroll_view` / resource store)。

#### D4. tag 14 发射的 binding 接线

`_buildSliverFixedExtent` 需 `final binding = _binding(node, EventTagId.visibleRangeChanged)`,把 `binding` + `onEvent` 传入 host;host 在 `_reportVisibleRange` 里调 `onEvent(RendererEvent(nodeId: node.id, eventTag: binding.eventTag, handlerId: binding.handlerId, payload: VisibleRangeEventPayload(firstIndex:, lastExclusive:)))`。binding 为 null(无 on_visible_range handler)时静默不发,不报错。

### 实现步骤

1. **新建 `sliver_virtual_host.dart`**:
   - 从旧 `sparse_extent_list.dart` 提取 `SparseExtentGeometry`(可单独放 `sparse_extent_geometry.dart` 供两 host 共用)。
   - `_SliverFixedExtentHost`: StatefulWidget,字段 `nodeId / localRevision / props / children / controller / binding / onEvent`。State: `_lastRange`、`_viewportExtent`、`_anchorCorrectionScheduled`。`initState` → `controller.addListener(_reportVisibleRange)`;`build` → `SliverFixedExtentList(delegate: SliverChildBuilderDelegate(_itemBuilder, childCount: total_count, findChildIndexCallback: _findChildIndex), itemExtent: itemExtent)`。
   - `_SliverVariedExtentHost`: 同上 + `SingleTickerProviderStateMixin` + 过渡动画状态机(`_extentStarts/Targets`、`_surfaceStarts/Targets`、`_anchor`、`_animating`),从旧 `_SparseExtentListHostState` 整段迁移;emit 改用 `RendererEvent` + `VisibleRangeEventPayload` 而非 `NativeEventEmitter`。
2. **改 `widget_registry.dart`**:
   - `_buildSliverFixedExtent` / `_buildSliverVariedExtent` 改为:取 `props`、`_binding(node, EventTagId.visibleRangeChanged)`、`ScrollViewScope.of(context)`(拿不到 → 抛 `RendererBuildException("Sliver X node Y must be inside a Scroll_view")`),返回对应 host。
3. **cacheExtent 协调(方案 B,改协议)**: `protocol/schema.sexp` 的 `scroll_view` 组加 `(cache_extent 4 optional_f64)` → `make protocol-generate`;OCaml `scroll_view_widget` 构造时遍历子 sliver 算 `max(overscan*extent)`(无虚拟化子时为 None);Dart `ScrollViewProps` 加 `cacheExtent: double?`,`_readScrollViewProps` 读 `optionalFloat64()`,`_buildScrollView` 传给 `CustomScrollView(cacheExtent: props.cacheExtent)`。
4. **删除/不再引用** 旧 `native_widget/virtual_list.dart`、`sparse_extent_list.dart`(主源码已删,vendored 副本随 example 重生成时清除)。

### 验收

- 50000 项 fixed_extent list: 滚动范围 == `50000 * itemExtent`(可用 `controller.position.maxScrollExtent` 断言)。
- 滚动时 tag 14 被发射,OCaml 收到 `Visible_range { first_index; last_exclusive }`,`first_index` 随滚动前进,窗口 children 更新,无白屏(overscan 区有内容)。
- `first_index = 100` 初始挂载时,首屏显示第 100 项(`find.text("Item 100")`)。
- varied_extent: `extent_overrides` 指定的 index 实际高度 = override;展开/收起过渡动画跑通;`Morphing_surface` 收到正确 progress。
- 多个虚拟化 sliver 同处一个 `Scroll_view` 时,各自独立报 range、不互相干扰控制器。

---

## 修复二: `Sliver_fill` — 删除 `flex` 字段(方案 A)

### 现状

```dart
// widget_registry.dart:595-604
final props = _expectProps<SliverFillProps>(node);   // 读了 flex
return SliverFillRemaining(child: children.single);   // 没用 props.flex
```

`flex` 在 `SliverFillProps`(`frame.dart:728`)、编解码(`binary_codec.dart:845-855 / 2361-2367`,校验 `flex != 0`)、`SliverFillPropId.flex=1`(`generated_protocol.dart:531`)、OCaml(`widget.ml:1062`,校验 `flex > 0`,默认 1)全链路存在,唯独渲染端丢弃。无论 flex=1 还是 3,行为相同。

### 决策:删除 `flex`,`Sliver.fill` 语义定为"填满视口剩余"

**理由**:`Sliver.fill` 的文档(`widget.mli:143` "Fills the remaining viewport extent")与实际用法都指向"吞掉视口剩余空间",即 Flutter `SliverFillRemaining`——这正是当前渲染端已实现的、忽略 flex 后的行为。flex 在这个语义下没有安放之处:

- "按比例分剩余"(Expanded 风格)在 sliver 体系无原语,`SliverFillRemaining` 多个并列时第一个吞完,需自定义 `RenderSliver` + 兄弟 sliver 通信,投入产出比低且无已知用例。
- "视口比例 1/flex"(`SliverFillViewport`)虽能映射,但与 `Body.fill` 同名 `flex` 语义相反(Body flex=2 = 占 2 份,Sliver flex=2 = 占 1/2),同名异义易误用,且与"fill remaining"措辞矛盾。

因此采纳**方案 A**:从 spec/协议删除 `flex`,渲染端维持 `SliverFillRemaining`(已正确),消除"声明未兑现"的冗余字段。这是协议不兼容变更,但 flex 当前仅测试用到(`native_widget_tests.ml:245/270`),无真实下游依赖。

### 改动清单

**OCaml spec / 协议:**
- `ocaml/ui/widget.ml:281` GADT:`| Sliver_fill : [ \`Sliver_fill ] node`(去掉 `{ flex }`)
- `ocaml/ui/widget.ml:1062` `sliver_fill_widget`:去掉 `?(flex = 1)` 参数与 `flex <= 0` 校验
- `ocaml/ui/widget.ml:1698` `Sliver.fill`:去掉 `?flex`
- `ocaml/ui/widget.mli:144` 签名:`val fill : ?key:Key.t -> widget -> t`(去掉 `?flex:int`),注释保持 "Fills the remaining viewport extent"
- `ocaml/runtime/driver.ml:391`:`| Sliver_fill -> Ok Sliver_fill_props`(去掉 `{ flex }` / 解构)
- `ocaml/protocol/binary_codec.ml` sliver_fill 编解码:去掉 flex 字段读写
- `ocaml/protocol/wire_frame.ml` sliver_fill_props:去掉 flex
- `protocol/schema.sexp:159` `sliver_fill` 组移除 `(flex 1 u32)`(组变空,或保留空组)`→ make protocol-generate`

**Dart 渲染 / 协议(生成产物 + 手写):**
- `generated_protocol.dart`:`SliverFillPropId` 类整体移除(重新生成)
- `frame.dart:728`:`SliverFillProps` 改为 `EmptyProps`(或直接复用 `EmptyProps` 并删 `SliverFillProps` 类;考虑 `node_store.dart` 的 kind→props 映射要同步改 `sliverFill => props is EmptyProps`)
- `binary_codec.dart`:`_readSliverFillProps` / `_writeSliverFillExtent` / `SliverFillProps()` field-mask case 移除,sliver_fill 走空 props 路径
- `widget_registry.dart:595-604`:`_buildSliverFill` 改为 `_expectProps<EmptyProps>(node)`,维持 `return SliverFillRemaining(child: children.single)`(行为不变)

**测试:**
- `ocaml/test/native_widget_tests.ml:245`:`Sliver.fill ~flex:2 (text "Fill")` → `Sliver.fill (text "Fill")`
- `native_widget_tests.ml:262-264`:`Sliver_fill { flex }` 解构断言改为 `Sliver_fill -> ()`(或移除该断言)
- `native_widget_tests.ml:265-272`:`~flex:0` 的 invalid_arg 用例整段移除(flex 不再存在)
- `flutter/.../test/viewport_constraint_guard_test.dart:30`:`SliverFixedExtentProps` 不受影响,但若有 `SliverFillProps(flex: ...)` 用例需同步改
- `virtual_list_test.dart`:无 SliverFillProps 用例,无需改

### 验收

- `Sliver.fill (child)` 构造的节点 round-trip 通过协议,无 flex 字段。
- 渲染端 `SliverFillRemaining` 占满视口剩余,行为同变更前。
- OCaml 侧 `Sliver.fill ~flex:0` 不再可能(参数已删),原 invalid_arg 用例随之移除。
- `protocol-check` / `dart-analyze` / `native-test` 全绿。

### 备注:协议不兼容性

此变更移除线上协议字段 `sliver_fill.flex`。因该字段当前无真实消费方(渲染端忽略、OCaml 仅校验),不兼容性影响有限。若有外部消费者已发 `sliver_fill` 带 flex 的帧,旧 host 会读到多余字节 → 解码错位。**需确认无外部消费者依赖该字段后再合入**;若有顾虑,可先按方案 D(flex 锁 1 + 文档预留)过渡,但本项目当前无外部消费者,直接删除。

---

## 修复三: `Sliver_app_bar` 完整支持

### 现状

```dart
// widget_registry.dart:656-670
return SliverAppBar(
  pinned: props.pinned,
  expandedHeight: props.expandedHeight,
  collapsedHeight: props.collapsedHeight,
  title: children.single,   // 单子节点只能当 title
);
```

两个问题:

1. **子节点只能当 title**: Flutter `SliverAppBar` 有 `leading` / `title` / `actions` / `flexibleSpace` / `bottom` 多个 widget 槽位,bonsai 当前单子节点模型只能填 `title`,带背景图 + 右侧操作按钮的折叠栏做不出来。此外 `floating`/`snap`/`stretch`/`toolbarHeight` 等交互/布局参数也缺。
2. **高度参数无校验**: `expandedHeight` / `collapsedHeight` 是裸 `optional_f64`,`_readSliverAppBarProps`(`binary_codec.dart:2466`)直接 `optionalFloat64()` 读,不校验非负/有限/`collapsed <= expanded`。传负数或 NaN 会一路送到 Flutter 触发内部断言。

### 关键结论: 多槽位不 blocked-on-spec

之前本项标 "blocked-on-spec,需 spec 定子节点槽位模型方向",基于"bonsai 无多槽位机制"的前提。核对代码发现 **bonsai 已有现成多槽位先例 `material_list_tile`**,采用"布尔 props 标记槽存在 + children 按序映射"模式,协议层零特殊机制(`Set_children` 仍是 `node_id list`,槽位区分靠父节点 props 的布尔字段)。因此 `Sliver_app_bar` 多槽位**照搬该模式即可,不需新 spec 决策、不动协议核心**。

先例参考(`widget.ml:1428` + `widget_registry.dart:1134`):`material_list_tile` 有 `has_subtitle`/`has_leading`/`has_trailing` 布尔 props,children 按 `[optional leading; title; optional subtitle; optional trailing]` 顺序展开,Dart 侧按 props 布尔重建槽位 `final leading = hasLeading ? children[index++] : null;`。

### 目标: 完整支持 `SliverAppBar`

Flutter `SliverAppBar` 完整参数分两类处理:

**子节点槽位(4 个)** — 照搬 `material_list_tile` 模式:

| 槽 | Flutter 类型 | 处理 |
|---|---|---|
| `leading` | `Widget?` | 单子节点,布尔 props `has_leading` 标记 |
| `title` | `Widget?` | 必填单子节点(无需标记) |
| `flexibleSpace` | `Widget?` | 单子节点,布尔 props `has_flexible_space` |
| `bottom` | `PreferredSizeWidget?` | 单子节点,布尔 props `has_bottom`;几何约束见下"bottom 槽" |
| `actions` | `List<Widget>` | **当单个子节点**,内部用 `Row` 包多个按钮(与 `material_list_tile` 的 `trailing` 一致,不破坏"一槽一子"模式);若未来要原生表达列表,可加 `action_count : int` props,先期不必要 |

children 顺序约定(存在性由布尔 props 决定):
```
[optional leading] ; [title] ; [optional flexible_space] ; [optional bottom] ; [optional actions]
```

**标量参数(props 字段)** — 协议扩字段:

必加(影响布局/交互,缺了功能不完整):
- `floating : bool`(默认 false)— 不滚到顶也能下拉浮现
- `snap : bool`(默认 false)— 配 floating,松手到位
- `stretch : bool`(默认 false)— 过度滚动拉伸 flexibleSpace
- `toolbar_height : f64`(默认 56.0)— 折叠态工具栏高度

建议加(常用外观):
- `force_elevated : bool`(默认 false)
- `automatically_imply_leading : bool`(默认 true)— 没传 leading 时是否自动加返回箭头
- `center_title : optional_bool`(默认 null = 系统默认对齐)
- `background_color : optional_argb32`
- `foreground_color : optional_argb32`
- `elevation : optional_f64`

可后置(少用或 bonsai 暂无对应概念):`shadow_color`/`surface_tint_color`/`shape`/`title_spacing`/`exclude_header_semantics`/`primary` — 颜色用 `argb32`(同 `schema.sexp` theme),形状(`ShapeBorder`)暂无对应,后续按需加。

### `bottom` 槽的 `PreferredSizeWidget` 约束 — 已定方案 B:新增 `preferred_size` widget

Flutter 的 `bottom` 槽类型是 `PreferredSizeWidget?`(典型 `TabBar`),Dart 编译期就拒绝普通 `Widget`——没有"默认 fallback"。bonsai 当前所有 widget 都不实现该接口,也没有"声明自身尺寸"的概念。要填 `bottom` 槽必须显式提供高度信息。

**决策:方案 B — 新增 `preferred_size` widget 节点**。形状 `{ height : float }` + 单 child,Dart 映射到 `PreferredSize(preferredSize: Size.fromHeight(height), child: ...)`。它是通用 widget(任何需要 `PreferredSizeWidget` 的 Flutter 槽位都能用,不止 `SliverAppBar.bottom`)。`bottom` 槽的子节点就是 `preferred_size` 节点,Dart 侧 `children[i++]` 拿到的已是 `PreferredSize`(实现 `PreferredSizeWidget`),直接 `bottom: children[i++]` 满足类型约束,无需特殊接线。

OCaml 用法:
```ocaml
Sliver.app_bar
  ~bottom:(Widget.preferred_size ~height:48. (Widget.tab_bar ...))
  ~title:(Widget.text "标题")
  ()
```

#### `preferred_size` widget 完整落地清单(逐层逐处,以 `sized_box` 为模板)

**协议定义层**
- `protocol/schema.sexp`:node_kinds 段加 `(preferred_size <next_id>)`;kind_props 段加 `(preferred_size ((height 1 f64)))`
- `make protocol-generate`:自动重生成 `protocol/generated/protocol-ids.md`、`flutter/.../protocol/generated_protocol.dart`(`NodeKind` debug 名 + `PreferredSizePropId` 类)、`ocaml/protocol/generated_protocol.ml`(`preferred_size` id + debug + `module Preferred_size_prop`)

**OCaml widget 层 (`ocaml/ui/widget.ml`,7 处)**
- `kind_tag` 枚举:`| K_preferred_size`
- `kind_tag` 显示名:`| K_preferred_size -> "Preferred_size"`
- GADT:`| Preferred_size : { height : float } -> [ `Preferred_size ] node`
- kind 映射:`| Preferred_size _ -> K_preferred_size`
- 相等比较:`| Preferred_size x, Preferred_size y -> Float.equal x.height y.height`
- 构造器(校验 height > 0 且有限):
```ocaml
let preferred_size ?key ~height child =
  validate_finite_positive "preferred_size.height" height;
  create_typed ~key ~node:(Preferred_size { height })
    ~event_bindings:[||] ~children:(plain_children [ child ])
;;
```
- `Private` 模块 K_ 列表 + GADT 镜像同步

**OCaml mli (`ocaml/ui/widget.mli`,3 处)**
- 签名:`val preferred_size : ?key:Key.t -> height:float -> t -> t`
- `Private` K_ 列表 + GADT 镜像同步

**OCaml wire/codec (`ocaml/protocol/wire_frame.ml` 2 处 + `ocaml/protocol/binary_codec.ml` 6 处)**
- `wire_frame.ml`:node kind 枚举加 `| Preferred_size`;props 变体加 `| Preferred_size_props of { height : float }`
- `binary_codec.ml`:write kind+props、props→kindId、field mask、write props 变体、kind→wire kind、read props — 6 处按 `sized_box` 模式加

**OCaml driver (`ocaml/runtime/driver.ml`,2 处)**
- K→kind:`| K_preferred_size -> Ok Preferred_size`
- node→props:`| Preferred_size { height } -> Ok (Preferred_size_props { height })`

**Dart frame (`flutter/.../protocol/frame.dart`,2 处)**
- `enum NodeKind` 加 `preferredSize,`
- props类:
```dart
final class PreferredSizeProps extends UiProps {
  const PreferredSizeProps({required this.height});
  final double height;
  @override
  bool operator ==(Object other) => other is PreferredSizeProps && other.height == height;
  @override
  int get hashCode => Object.hash(PreferredSizeProps, height);
}
```

**Dart codec (`flutter/.../protocol/binary_codec.dart`,6 处)**
- write kind+changed+props case、write props-only case、NodeKind→NodeKindId 映射、read props dispatch、field mask、`NodeKindId` 类加 `static const int preferredSize = <id>;`

**Dart renderer (`flutter/.../renderer/widget_registry.dart`,2 处)**
- 注册:`NodeKind.preferredSize: _buildPreferredSize,`
- builder:
```dart
Widget _buildPreferredSize(context, node, children, onEvent) {
  _expectChildCount(node, children, 1);
  final props = _expectProps<PreferredSizeProps>(node);
  return PreferredSize(
    preferredSize: Size.fromHeight(props.height),
    child: children.single,
  );
}
```

**Dart store (`flutter/.../store/node_store.dart`,1 处)**
- kind→props 映射:`NodeKind.preferredSize => props is PreferredSizeProps,`

**测试**
- `ocaml/test/native_widget_tests.ml`:`preferred_size` round-trip + kind 断言(`K_preferred_size` / `Preferred_size { height }`)
- Dart test:`PreferredSizeProps` round-trip;`_buildPreferredSize` 产出 `PreferredSize` 且 `preferredSize.height == props.height`
- 集成:`Sliver.app_bar ~bottom:(preferred_size ...)` 验证 `SliverAppBar.bottom` 编译通过且几何正确

### 实现方案

#### OCaml `widget.ml` GADT(扩字段)

```ocaml
| Sliver_app_bar :
    { pinned : bool
    ; expanded_height : float option
    ; collapsed_height : float option
    ; floating : bool
    ; snap : bool
    ; stretch : bool
    ; toolbar_height : float
    ; has_leading : bool
    ; has_flexible_space : bool
    ; has_bottom : bool
    ; has_actions : bool
    ; force_elevated : bool
    ; automatically_imply_leading : bool
    ; center_title : bool option
    ; background_color : int option      (* argb32 *)
    ; foreground_color : int option
    ; elevation : float option
    }
    -> [ `Sliver_app_bar ] node
```

#### OCaml `sliver_app_bar_widget`(从单 child 改多槽)

```ocaml
let sliver_app_bar_widget
      ?key ?(pinned = false) ?expanded_height ?collapsed_height
      ?(floating = false) ?(snap = false) ?(stretch = false)
      ?(toolbar_height = 56.) ?(force_elevated = false)
      ?(automatically_imply_leading = true) ?center_title
      ?background_color ?foreground_color ?elevation
      ?leading ?flexible_space ?bottom ?actions
      ~title ()
  =
  let optional = Option.to_list in
  create_typed
    ~key
    ~node:(Sliver_app_bar
             { pinned; expanded_height; collapsed_height
             ; floating; snap; stretch; toolbar_height
             ; has_leading = Option.is_some leading
             ; has_flexible_space = Option.is_some flexible_space
             ; has_bottom = Option.is_some bottom
             ; has_actions = Option.is_some actions
             ; force_elevated; automatically_imply_leading; center_title
             ; background_color; foreground_color; elevation
             })
    ~event_bindings:[||]
    ~children:(plain_children
                 (optional leading @ [ title ] @ optional flexible_space
                  @ optional bottom @ optional actions))
;;
```

`widget.mli` 签名同步:
```
val app_bar
  :  ?key:Key.t
  -> ?pinned:bool
  -> ?expanded_height:float
  -> ?collapsed_height:float
  -> ?floating:bool
  -> ?snap:bool
  -> ?stretch:bool
  -> ?toolbar_height:float
  -> ?force_elevated:bool
  -> ?automatically_imply_leading:bool
  -> ?center_title:bool
  -> ?background_color:int
  -> ?foreground_color:int
  -> ?elevation:float
  -> ?leading:t
  -> ?flexible_space:t
  -> ?bottom:t
  -> ?actions:t
  -> title:t
  -> unit
  -> t
```

#### Dart `widget_registry.dart`(`_buildSliverAppBar`)

```dart
Widget _buildSliverAppBar(context, node, children, onEvent) {
  final props = _expectProps<SliverAppBarProps>(node);
  final expected = 1
      + (props.hasLeading ? 1 : 0)
      + (props.hasFlexibleSpace ? 1 : 0)
      + (props.hasBottom ? 1 : 0)
      + (props.hasActions ? 1 : 0);
  _expectChildCount(node, children, expected);
  var i = 0;
  final leading = props.hasLeading ? children[i++] : null;
  final title = children[i++];
  final flexibleSpace = props.hasFlexibleSpace ? children[i++] : null;
  final bottom = props.hasBottom ? children[i++] : null;
  final actions = props.hasActions ? [children[i++]] : null;
  return SliverAppBar(
    pinned: props.pinned,
    expandedHeight: props.expandedHeight,
    collapsedHeight: props.collapsedHeight,
    floating: props.floating,
    snap: props.snap,
    stretch: props.stretch,
    toolbarHeight: props.toolbarHeight,
    forceElevated: props.forceElevated,
    automaticallyImplyLeading: props.automaticallyImplyLeading,
    centerTitle: props.centerTitle,
    backgroundColor: props.backgroundColor,
    foregroundColor: props.foregroundColor,
    elevation: props.elevation,
    leading: leading,
    title: title,
    flexibleSpace: flexibleSpace,
    bottom: bottom,
    actions: actions,
  );
}
```

#### 协议改动(`protocol/schema.sexp`)

```sexp
(sliver_app_bar
 ((pinned 1 bool)
  (expanded_height 2 optional_f64)
  (collapsed_height 3 optional_f64)
  (floating 4 bool)
  (snap 5 bool)
  (stretch 6 bool)
  (toolbar_height 7 f64)
  (has_leading 8 bool)
  (has_flexible_space 9 bool)
  (has_bottom 10 bool)
  (has_actions 11 bool)
  (force_elevated 12 bool)
  (automatically_imply_leading 13 bool)
  (center_title 14 optional_bool)
  (background_color 15 optional_argb32)
  (foreground_color 16 optional_argb32)
  (elevation 17 optional_f64)))
```
`→ make protocol-generate` 重生成 `generated_protocol.{dart,ml}`。

#### 高度校验(原阶段 3a,并入本次)

`_readSliverAppBarProps` 加校验:
```dart
if (expandedHeight case final e when e != null && (!e.isFinite || e < 0))
  _fail(..., 'expanded_height must be non-negative and finite');
if (collapsedHeight case final c when c != null && (!c.isFinite || c < 0))
  _fail(..., 'collapsed_height must be non-negative and finite');
if (expandedHeight != null && collapsedHeight != null && collapsedHeight! > expandedHeight!)
  _fail(..., 'collapsed_height must not exceed expanded_height');
if (toolbarHeight <= 0 || !toolbarHeight.isFinite)
  _fail(..., 'toolbar_height must be positive and finite');
```
OCaml `sliver_app_bar_widget` 对称加 `invalid_arg`(非负/有限/`collapsed <= expanded`/`toolbar_height > 0`)。

### 完整改动清单(按层)

| 层 | 文件 | 改动 |
|---|---|---|
| 协议定义 | `protocol/schema.sexp` | `sliver_app_bar` 组从 3 字段扩到 17 字段 |
| 协议生成 | `make protocol-generate` | 重生成 `generated_protocol.{dart,ml}` |
| OCaml widget | `ocaml/ui/widget.ml` | GADT `Sliver_app_bar` 扩字段;`sliver_app_bar_widget` 从单 child 改 `~title + ?leading + ?flexible_space + ?bottom + ?actions` + 标量参数 |
| OCaml mli | `ocaml/ui/widget.mli` | `app_bar` 签名同步 |
| OCaml codec | `ocaml/protocol/binary_codec.ml` + `wire_frame.ml` | sliver_app_bar 编解码扩字段 |
| OCaml driver | `ocaml/runtime/driver.ml` | `Sliver_app_bar` 解构同步 |
| Dart props | `frame.dart` `SliverAppBarProps` | 加所有新字段 + `==`/`hashCode` |
| Dart codec | `binary_codec.dart` | `_readSliverAppBarProps`/`_writeSliverAppBar` 扩字段 + 高度校验 |
| Dart renderer | `widget_registry.dart` `_buildSliverAppBar` | 按布尔 props 重建 4 槽 + 传所有标量参数 |
| Dart node_store | `node_store.dart` | kind→props 映射不变(仍 `SliverAppBarProps`) |
| 测试 | `native_widget_tests.ml` + dart test | 多槽构造 round-trip;各槽位 widget 定位;高度校验失败用例 |
| 新增 widget | `widget.ml`/`widget.mli` + 协议各层 | 新增 `preferred_size` widget 节点(方案 B):schema/wire/codec/driver/frame/codec/registry/store 全链路,见上"preferred_size widget 完整落地清单" |

### 验收

- `Sliver.app_bar ~title ~leading:(text "back") ~actions:(row [...]) ~flexible_space:(image ...) ~bottom:(...)` 构造的节点 round-trip 通过协议,各槽位 widget 在 Flutter 侧正确定位(`find.byType` / `find.text`)。
- `expanded_height = -1` / `collapsed_height = NaN` / `collapsed > expanded` / `toolbar_height = 0`:解码抛 `invalidProps` / OCaml 抛 `invalid_arg`,不进 Flutter。
- `floating`/`snap`/`stretch` 行为按参数生效(下拉浮现 / 松手到位 / 过滚拉伸)。
- `bottom` 槽:`preferred_size` widget 包装的 child 正确填入 `SliverAppBar.bottom`,`preferredSize.height` 等于传入 height,app bar 总高计算正确。

---
## 实现顺序

1. **修复三**(Sliver_app_bar 完整支持)— 照搬 `material_list_tile` 多槽位模式 + 标量参数扩字段;高度校验并入;`bottom` 槽用新增 `preferred_size` widget(方案 B,全链路落地清单已列入)。
2. **修复一**(虚拟化 host)— 核心价值,工作量最大。先 fixed(状态机较简),再 varied(过渡动画)。
3. **修复二**(Sliver_fill 删除 flex)— 已定方案 A(删除 flex 字段),协议不兼容但无外部消费者,可独立合入。

## 测试计划

### 修复一(虚拟化)
- 扩 `test/virtual_list_test.dart`: 当前只测编解码 + "挂出 SliverFixedExtentList"。补:
  - 滚动范围断言(`maxScrollExtent == total_count * itemExtent`)。
  - 滚动后 tag 14 发射: 用一个收集 `RendererEvent` 的 fake `onEvent`,断言 `eventTag == visibleRangeChanged` 且 `firstIndex` 随滚动前进。
  - `first_index = 100` 初始锚定: 首屏 `find.text("Item 100")`。
  - varied extent override: 指定 index 实际高度 = override(用 `tester.getRect(find.byKey(...))` 断言)。
  - varied 过渡: pump 动画帧,断言 extent 渐变 + anchor 校正不跳。
- 注意: OCaml 侧 `test_sliver_fixed_extent_contract`(`native_widget_tests.ml:60`)从 harness 模拟事件,**不**验证真实 Flutter 宿主发射——需 Dart 侧 widget test 补这条链路。

### 修复二(Sliver_fill 删除 flex)
- `Sliver.fill (text "Fill")` 节点 round-trip 通过协议,无 flex 字段。
- 渲染端 `SliverFillRemaining` 占满视口剩余,行为同变更前(`tester.getRect` 主轴高度 == viewport 高度)。
- `Sliver.fill ~flex:0` 不再可能(参数已删);原 invalid_arg 用例随参数移除。

### 修复三(Sliver_app_bar 完整支持)
- 多槽构造 round-trip:`Sliver.app_bar ~title ~leading ~flexible_space ~bottom ~actions` 各槽位 widget 在 Flutter 侧 `find.byType`/`find.text` 定位正确。
- 高度校验:`expanded_height = -1` / `collapsed_height = NaN` / `collapsed > expanded` / `toolbar_height = 0` 四个解码失败用例(`expect(() => FrameCodec.decode(...), throwsA(...))`)。
- `floating`/`snap`/`stretch` 行为生效(下拉浮现 / 松手到位 / 过滚拉伸)。

## 风险与开放问题

1. **[协议] `Sliver_fill.flex` 删除的兼容性** — 修复二已定方案 A(删除 flex)。需确认无外部消费者依赖 `sliver_fill.flex` 字段;本项目当前无外部消费者,可直接删。若有顾虑先走方案 D 过渡。
2. **[spec] `Sliver_padding` 子节点必须是 sliver 的约束未在类型层表达** — `widget.ml:1748` 的 `padding` 接收 `Sliver inner`(OCaml 类型层已约束为 `Sliver.t`!),但 Dart `_buildSliverPadding` 直接 `sliver: children.single` 无校验。若 OCaml 侧类型已保证,则 Dart 侧靠协议节点 kind 保证(非 sliver kind 的节点不应出现在 sliver_padding 的 children)。**需确认 reconciler 是否校验子节点 kind 兼容性**;若不校验,是潜在的运行时约束违反。非本次范围,记录备查。
3. **[协议] cacheExtent 协调(修复一 D1)** — 已定方案 B(`scroll_view` 加 `cache_extent: optional_f64`,OCaml 算 max 下发)。正确性维护点:OCaml 须在子 sliver overscan/extent 变化时重算重发,守住"构造 Scroll_view 时遍历子算 max"的不变式即可。
4. **已定方案 B** — app_bar `bottom` 槽的 `PreferredSizeWidget` 约束:新增 `preferred_size` widget 节点(`{ height }` + 单 child → `PreferredSize`),见修复三落地清单。修复三不再 blocked。
5. **多虚拟化 sliver 共享控制器** — 一个 `Scroll_view` 里挂两个 `sliver_fixed_extent` 时,两者监听同一 controller、各自报自己的 range。需确认 Flutter `SliverFixedExtentList` 在共享 viewport 下的 offset 语义(各 sliver 的 leading 各自独立,visibleRange 计算需用 `controller.offset` 减去该 sliver 在 viewport 中的 leading offset)。旧实现是单 ListView 自治,迁移时此点需专门验证。
# 收向锚点 / 从锚点展开过渡（设计说明）

状态：静态纹理运行模型（§3）+ genie 网格形变（§6，`.anchor` 的默认画面）已实现；第一级“曲线路径 + 缩放 + 渐隐”保留为
`Tokens.shape = .affine`，也是没有网格合成的后端（D3D / Vulkan / OpenGL / Web）的退化画面；原地“淡出并轻微缩小”模式
`fade_scale` 已实现（Z12b，§2.1）。
来源：ZeroWork 上游缺口 Z12——浮动卡片属于某个顶部 tab，切到别的 tab 时快速收回到该 tab 在 tab 条上的位置
（类似 macOS Dock 最小化），切回时从 tab 的位置展开回原来停放的地方。

## 1. 为什么要新能力

| 现有能力 | 为什么不够 |
|---|---|
| `animation/node_animator.zig` | 只能对节点属性做插值；路径、缩放中心、时长、反向都要调用方自己组合，等于下游手写动画 |
| `snapshot_transition.zig` | 只有 `dissolve`（快照原地淡出） |
| `overlay_transition.zig` | 浮层在锚点附近几 pt 内出现 / 消失，不是飞向远处的锚点 |
| `glass_bars/tab_motion.zig` | tab 条内的选中镜片动力学，与卡片无关 |
| `ContentWarp` | 玻璃透镜，不是对任意内容做网格形变 |

## 2. 结构

- `src/ui/animation/anchor_motion.zig`：纯几何与时钟，不依赖窗口。
  - 一个进度值 `progress`：0 = 原位，1 = 在锚点里。收回朝 1 走，展开朝 0 走，各自的速率是“每个完整过程 `collapse_duration_s` / `expand_duration_s`”。
  - `frameAt(home, anchor, progress, tokens)`：矩形中心沿二次贝塞尔曲线从原位中心到锚点中心
    （控制点由 `path_bend` 决定，默认先向锚点所在的列偏，再落进去）；尺寸比运动略快地缩到锚点尺寸
    （`scale_lead`，吸入感），`progress = 1` 时**正好等于锚点矩形**；不透明度在 `fade_start` 之前保持 1，之后缓到 `end_opacity`。
  - `Motion.retarget(.collapse / .expand)` 只翻转方向，不重置进度：中途改向从当前画面继续，回程用剩余比例的时间，不排队。
    形状是进度的固定函数（缓动曲线对称），所以翻转那一帧画面连续。
  - 展开的时钟（`expand_easing`，默认 `ease_out_cubic`）：画面仍是同一个 `frameAt(progress)`，只是展开时 `progress` 随时间的走法变了——
    “离原位还剩的形状距离” `easing(progress)` 按 `1 - expand_easing(t)` 缩小（`expandStep` 反解出 `progress`）。效果是从锚点**起步就是最快的**、
    收尾柔和、不过冲（macOS 窗口 / Dock 还原的观感）；对称曲线直接走线性时钟时，前几帧几乎停在锚点里且完全透明（ZeroWork AI 面板实测前 7 帧≈117 ms 是空的）。
    因为画面只取决于 `progress`，中途反向仍连续；回程时间是按展开时钟算的剩余份额。`expand_easing = null` 恢复线性时钟；减少动态效果不受影响（线性淡入）。
  - `clampAnchor(anchor, bounds)`：把锚点滑进裁剪区（保留尺寸，超出时截到裁剪区大小）。
- `Tokens.mode`：`.anchor`（默认，上面的飞向锚点）或 `.fade_scale`（§2.1）。
- `src/ui/anchor_transition.zig`：运行时 `AnchorTransition`（`ui.fx.AnchorTransition`）与每窗口的锚点登记表
  `Cx.motion_anchors`。
- `src/ui/view.zig` / `src/yix/compiler.zig`：声明式属性（§4）。
- `Snapshot.appendTransformed` / `Snapshot.rectToRect`（`src/ui/core/snapshot.zig`）：用任意仿射把快照画到目标矩形（非等比缩放）。
  飞行层用 `Snapshot.nodeRectToRect`：把**节点自身矩形**（快照局部坐标里位于 `node_offset`）映射到当前帧矩形；外阴影等画在节点外的部分随之围在外面。
  默认快照的局部原点是“所有绘制命令的包围盒”左上角，带外阴影的卡片原点会偏到阴影左上（例：blur 24 → 偏 24pt），
  直接用 `rectToRect` 会让整段飞行偏移阴影外扩量、落地瞬间跳回（ZeroWork AI 面板实测 24pt / 32pt）；改用 `node_rect` 几何虽然原点对，但会把阴影裁掉、落地时阴影突然出现。

### 2.1 原地淡出并轻微缩小（`fade_scale`，Z12b）

来源：ZeroWork 设置里可选浮动卡片切换 tab 的动画——“收向锚点”（`.anchor`）或“淡出并轻微缩小”（`.fade_scale`）。
用户原话：“一个是带缩放回 anchor 的退场动画，另一款是直接 fade out，带一点缩小一点点”。

- `fadeScaleFrameAt(home, progress, tokens)`：矩形始终以原位中心为中心，尺寸从 1 倍缩到 `fade_scale_end_scale`（默认 0.97），
  不透明度从 1 到 `end_opacity`，两者都沿 `easing`；`progress = 0` 正好是原位矩形、完全不透明。`frameAt` 在 `.fade_scale` 下转到这里。
- 收起 = 淡出 + 缩小，展开 = 反向（从 0.97 倍、透明放大淡入回原位）。时长单独取 `fade_scale_out_duration_s` / `fade_scale_in_duration_s`。
- 不使用锚点：运行时不解析锚点，锚点缺失也不会退化（`anchor == .none` 照样是缩放 + 淡出）。
- 中途改向、快照、覆盖层、命中、`display:none`、节点释放等规则与 `.anchor` 完全相同（§3）。
- 减少动态效果：与 `.anchor` 一样退化为原地纯淡入淡出（`reduced_duration_s`，没有缩放）；`.reduced = .instant` 直接显隐。
- 预设：`anchor_transition.fade_scale_tokens`（`ui.fx.anchor_transition.fade_scale_tokens`）= `.{ .mode = .fade_scale }`。

**切换模式**：`AnchorTransition.setTokens` 静止时立即生效；过程中调用时记为待定，当前过程保持原形状（反向仍连续），
落定后才换成新 token，下一次过程按新模式走。`ui.view` 的 `.anchor_motion`（Yix `anchorMotion`）可以是源，跟随规则同上，
所以应用里“设置改了立即生效”只需把设置项映射成 `AnchorMotion` 的源。

## 3. 运行时规则（静态纹理模型）

过渡期间被动画的只是一张**静态图**：节点和它的子元素在飞行期间不参与布局、不重绘、不命中。

| 状态 | 节点 | 飞行层 |
|---|---|---|
| expanded（静止） | 正常渲染、正常命中 | 无 |
| collapsing / expanding | **不在布局里**：见下面的“压住方式”；不画、不命中 | 一个不命中的覆盖层把快照作为**一张缓存纹理**合成到当前帧（genie 网格或仿射） |
| collapsed（静止） | `display: none`（不占布局、不画、不命中、不在 Tab 序与 a11y 树里）；自己的不透明度与命中标志已还原 | 无 |

- **压住方式**（`Options.hold`，默认 `.auto`）：`position: absolute` 的节点（浮动卡片）整段 `display: none`（`.hide`）；
  在流里的节点（分屏窗格、tab 主体）保留**自身盒子**（兄弟不重排）、不画不命中，**子元素**整段 `display: none`（`.keep_box`），
  所以内容既不布局也不绘制。`.keep_box` 下按内容自适应尺寸的节点会缩到只剩内边距。
- **纹理**：快照（绘制命令）挂在一个 `begin_opacity_layer` 上，带一个稳定的 `surface_stable_id`（保留区间，见
  `opacity_layer.isTransitionSurface`）和静止位置 `surface_rest_origin`。渲染器按 id + 内容哈希缓存这张纹理：内容不变时**只光栅化一次**，
  之后每帧只做一次合成（GPU retained hit，内容命令整段跳过）。纹理按静止位置对齐像素网格，所以落地时纹素正好对到真实节点的像素上。
  过渡层的纹理在任意嵌套深度都可复用（它的命令是自身局部坐标、自带裁剪，与外层无关）。缓存键用快照的版本号
  （`surface_content_version`，换一张快照就换一个版本），不用逐帧的命令哈希：冻结的命令带着取图那一帧的 id 和文字句柄，
  逐帧哈希会漂移，导致飞行中途被重新光栅化。
- **收起（从静止）**：抓取上一帧显示出来的画面（`Snapshot.captureDisplayed`，不重新渲染），节点**立即**按上面的方式退出布局，
  从同一帧开始只画纹理。
- **展开（从静止）**：节点在收起期间可能变了，所以在请求所在的那一帧做**一次**私有渲染：节点带着被压住的绘制进入这一帧的布局，
  在 after-layout 轮次里 `Snapshot.capture`（渲染到私有列表，不上屏），读出原位矩形，然后立刻退出布局（再要一轮布局）。
  内容没变时 GPU 端命中同一张缓存纹理，不再光栅化。之后只画纹理；**落地那一帧**把节点交还（恢复显示、去掉飞行层并要一轮布局），
  所以落地帧画的已经是真实节点，节点只在这一帧布局和绘制一次。
  zenit 目前没有可靠的“隐藏子树自上次以来是否变化”的标记，因此展开总是做这一次私有渲染；内容一致时由纹理缓存保证不重新光栅化。
  取图前先让子树的 before-render 钩子按本帧最终布局再跑一次（不推进时间），由钩子摆放的几何（ScrollArea 的滚动条）就和真实节点一致。
  随后是**一帧沉淀**：节点在这一帧和下一帧仍在布局里（绘制压住），下一帧再私有渲染一次后才退出布局——内容自己下一帧才测量完
  （虚拟列表）、盒子下一帧才被周围排定（停靠后的分屏）都会进到图里；`.keep_box` 的过程在沉淀期间停在锚点（不会有一帧对着临时原位），
  脱离布局流的节点停在第一帧。最多 3 帧。
- **几何冻结**：原位矩形与锚点矩形在过程开始时取一次（锚点在第一帧按本帧布局再确认一次），之后**不再每帧读布局**。只有真实变化才重新取目标：
  - 窗口尺寸变化（`cx.viewport`）：重新解析锚点；展开方向还要重新读原位——节点被压住绘制地进入一轮布局、读出矩形、再退出；
  - 锚点节点被重新布局（它的 layout epoch 变了，如 tab 条重排）：重新解析锚点；
  - `setAnchor` / 新的 `collapse` / `expand` 带了别的锚点；
  - `.keep_box` 压住的节点（盒子仍在父布局里）在展开中被重新布局到别的位置 / 尺寸（例如分屏在停靠后一帧才排定）：重新读原位，
    尺寸变了就再私有渲染一次内容（每次过程最多 3 次）；这发生在过程最初几帧时直接取新原位，不做混合。
  重新取目标时用 `retarget_blend_s`（0.12 s）从当前画面平滑过渡到新目标，画面连续。锚点每次解析仍会夹进裁剪祖先与视口；
  取不到时用最后一次解析到的矩形，从未解析到则本次退化为原地淡入淡出。
- **反向**：对进行中的过程发相反请求只翻转方向，纹理与几何不变；展开还在等私有渲染时收回，直接回到收起状态。
- **`.fade_scale`**：不解析锚点，其余规则不变（同样只画纹理）。
- **减少动态效果**：`cx.reduced_motion`、`cx.renderer_reduced_motion` 或系统设置（`a11y/preferences.zig`）任一开启时，
  `Tokens.reduced = .fade`（默认）为原地淡入淡出（`reduced_duration_s`），`.instant` 为直接显隐。
- **没有可画的内容**（节点尺寸为 0、子树不产生绘制命令）：直接切到目标状态。
- **节点在过程中被释放**：下一帧丢弃覆盖层和快照，钩子注销。`destroy()` / 作用域释放把节点交还为显示状态（子元素也还原）。
- **所有权**：过渡在收起与飞行时接管节点的 `display`（`.keep_box` 时接管子元素的 `display`）、不透明度与命中标志。不要在同一节点上再绑 `visible`。
  过程中别处改写了节点的不透明度（主题重放、应用写入），过渡把新值当作结束时要还原的值，并继续压住绘制。
- **观测**：`anchor_transition.flight_stats`（harness `/stats` 的 `anchor_flight`）累计飞行帧、私有渲染、重新取目标、落地次数；
  `ZENIT_ANCHOR_FLIGHT_PROBE=1` 时每帧检查子树：飞行帧里子树（节点的后代）的布局次数与绘制命令数（都应为 0）。
  渲染端 `/stats` 的 `transition_texture_hits / rasters / uncached` 是过渡纹理的复用 / 光栅化 / 不可缓存次数，`genie_mesh_cells` 是画过的网格单元数。

## 4. API

### Yix

```yix
// 锚点：tab 条里的 tab
<box motionAnchor={tabAnchor(vm, row)}> … </box>

// 卡片：不是当前 tab 时收进所属 tab
<box anchorCollapsed={!isCurrentTab(vm, card)} anchorTo={ownerAnchor(vm, card)}>
    …
</box>

// 也可以直接给窗口坐标矩形，并覆盖动效 token
<box anchorCollapsed={vm.minimized} anchorRect={dockRect(vm)} anchorMotion={fast_motion}> … </box>

// 原地淡出并轻微缩小；anchorMotion 给源时，切换设置即对下一次过程生效
<box anchorCollapsed={!isCurrentTab(vm, card)} anchorTo={ownerAnchor(vm, card)} anchorMotion={vm.card_motion}> … </box>
```

| 属性（`ui.view` 字段） | 值 |
|---|---|
| `motionAnchor`（`.motion_anchor`） | 锚点名，字符串或源（跟随源改名） |
| `anchorCollapsed`（`.anchor_collapsed`） | bool 或源。挂载时的值是初始状态，不播放；之后每次变化开始或反转过程 |
| `anchorTo`（`.anchor_to`） | 目标锚点名，字符串或源 |
| `anchorRect`（`.anchor_rect`） | `?ui.view.AnchorRect` 或源，窗口坐标；不用 `anchorTo` 时 |
| `anchorMotion`（`.anchor_motion`） | `ui.view.AnchorMotion`（即 `Tokens`）或源；源变化在静止时立即生效，过程中则从下一次过程生效 |

五个属性都可以写在组件元素上，作用于组件根；`anchorTo` / `anchorRect` / `anchorMotion` 必须和 `anchorCollapsed` 写在同一元素上。

### Zig

```zig
const fx = ui.fx;
const t = try fx.AnchorTransition.attach(scope, cx, card_node, .{
    .tokens = fx.anchor_transition.default_tokens,
    .on_complete = onRest, // fn (ctx: ?*anyopaque, phase: Phase) void
    .on_complete_ctx = vm,
});
t.snapTo(!is_current);                       // 初始状态，不播放
t.collapse(.{ .node = tab_node });           // 或 .{ .id = "tab-42" } / .{ .rect = r } / .none
t.expand(.{ .id = "tab-42" });               // 中途调用即反向
t.setCollapsed(away, .{ .id = owner_anchor });
t.setTokens(fx.anchor_transition.fade_scale_tokens); // 静止时立即生效，过程中从下一次过程生效
t.motionTokens();                                    // 当前（或下一次）过程用的 token
t.phase();        // .expanded / .collapsing / .collapsed / .expanding
t.progress();     // 0..1
t.currentFrame(); // 本帧画的矩形与不透明度（测试 / e2e 用）

// 锚点登记（Yix motionAnchor 就是它）
const token = try cx.motion_anchors.register(cx, "tab-42", tab_node);
defer cx.motion_anchors.unregister(token);
```

`AnchorTransition.create(cx, node, options)` + `destroy()` 是不挂作用域的版本。`destroy` 必须在 `Cx.deinit` 之前。

## 5. Token（`anchor_motion.Tokens`，默认值即 `default_tokens`）

| 字段 | 默认 | 说明 |
|---|---|---|
| `collapse_duration_s` | 0.28 | 完整收回时长 |
| `expand_duration_s` | 0.32 | 完整展开时长 |
| `easing` | `ease_in_out_cubic` | 进度到路径 / 尺寸的映射；用对称曲线，反向才连续 |
| `expand_easing` | `ease_out_cubic` | 展开的时钟：形状距离按 `1 - expand_easing(t)` 缩小（起步快、收尾柔和）；`null` = 与收回同样的线性时钟 |
| `path_bend` | 0.6 | 0 为直线；1 时控制点在（锚点中心 x，原位中心 y） |
| `scale_lead` | 0.25 | 尺寸领先运动的比例 |
| `fade_start` | 0.35 | 开始渐隐的进度 |
| `end_opacity` | 0 | 落进锚点时的不透明度 |
| `reduced` | `.fade` | 减少动态效果时：`.fade` / `.instant` |
| `reduced_duration_s` | 0.15 | 减少动态效果下的淡入淡出时长 |
| `mode` | `.anchor` | `.anchor` 飞向锚点；`.fade_scale` 原地淡出并轻微缩小（§2.1） |
| `fade_scale_end_scale` | 0.97 | `.fade_scale` 淡出结束 / 淡入开始时的缩放（以原位中心为中心），1 = 纯淡入淡出 |
| `fade_scale_out_duration_s` | 0.18 | `.fade_scale` 完整淡出时长 |
| `fade_scale_in_duration_s` | 0.22 | `.fade_scale` 完整淡入时长 |
| `shape` | `.genie` | `.anchor` 的画面：`.genie` 网格形变（§6），`.affine` 曲线路径 + 缩放（第一级，`affine_tokens`） |
| `genie_rows` / `genie_cols` | 32 / 8 | 网格密度：沿飞行方向（会弯曲的行）/ 横向的单元数（渲染端各夹到 1..64） |
| `genie_stagger` | 0.35 | 吸入曲线：远端边比朝向锚点的近端边晚出发的进度份额 |
| `genie_squeeze` | 0.6 | 吸入曲线：每一行收窄到锚点宽度比它移动快多少（0 = 同步） |
| `genie_collapse_duration_s` / `genie_expand_duration_s` | 0.36 / 0.40 | genie 完整收起 / 展开时长 |
| `genie_fade_start` | 0.6 | genie 开始淡入锚点（到 `end_opacity`）的进度；之前保持不透明 |

`.fade_scale` 下 `easing`、`expand_easing` 与 `end_opacity` 同样生效；`path_bend` / `scale_lead` / `fade_start` / `collapse_duration_s` / `expand_duration_s` 不使用。

## 6. genie 网格形变（已实现）

- 几何：`src/genie_warp.zig`（独立模块 `zenit_genie_warp`，UI 与渲染器共用同一个函数）。纹理上铺 `rows × cols` 的网格，
  每个网格点从它在原位矩形里的位置移向锚点矩形里的对应位置；**行**（垂直于飞行方向的线）不同步：朝向锚点的近端先走，远端晚
  `genie_stagger`；每一行横向收窄比移动快（`genie_squeeze`），所以近端先捏到锚点宽度、两侧弯成平滑的 S 形，然后整条滑进锚点（macOS Dock 最小化）。
  画面只是进度的函数：0 正好是原位，1 正好是锚点矩形，中途反向连续。飞行方向在锚点完全在上 / 下 / 左 / 右时取该方向，重叠时取相对位移大的一轴。
- 运行时：`anchor_motion.genieFrameAt` 给出 `Frame.genie`（`GenieWarp`）、外包矩形 `rect`（e2e / 探针用）与仿射退化画面 `fallback_rect`；
  不透明度在 `genie_fade_start` 之前保持 1。展开的时钟按 genie 自己的“离原位距离”（各行横向与纵向权重的平均，`GenieDistance`）走 `1 - expand_easing(t)`，
  所以落地前最后几帧整张网格都已贴近原位（不是只有一个缓动标量贴近，行的错位还在）。展开到达原位后，先用**一帧时间**（≥ 15 ms 时钟）
  把纹理精确画在原位（纹素对像素），再把画面交还真实节点：落地帧与它的前一帧逐像素一致（最后一帧运动可能还差零点几个像素）。
- 显示项：`begin_opacity_layer.genie`（`paint_table` 同名字段）。渲染器（Metal）在合成这张缓存纹理时不画单个四边形，而是
  `opacity_layer.compositeGenieMesh`：每个网格单元一个图像实例，`image.metal` 的顶点着色器直接取实例里的四个角（`sampling[3] = 1` 标记），
  两个三角形仿射插值纹理，相邻单元共享角点，无缝。纹理外留 2pt 透明边，变形后的轮廓由双线性过滤得到抗锯齿边。
  变形全部在 GPU 上：CPU 只算 (rows+1)×(cols+1) 个网格点。
- 损伤：图层的 `draw_x/y/w/h` 是 genie 外包与仿射外包的并集；整帧损伤和外层 retained 表面的局部重绘都按这个外包（`paint_fingerprint.nestedCompositeBounds`），
  genie 图层不按“仅平移”的子层处理。
- 其它后端（D3D12 / Vulkan / OpenGL / Web record）：`opacity_layer.genieMeshAvailable` 为假，同一个图层按 `draw_transform`（仿射退化画面）合成，
  其余运行规则不变。

## 7. 测试

- `anchor_motion.zig`（无窗口）：起止几何（终点正好是锚点矩形）、曲线路径、尺寸与不透明度单调、两个方向的时长、
  中途反向画面连续且用剩余时间、展开时钟（起步快、收尾最小步、第一帧可见、反向连续、减少动态效果仍线性）、快速来回切换、减少动态效果（淡入淡出 / 直接切换）、零尺寸锚点、锚点夹取；
  `fade_scale` 的居中缩放与单调淡出、缩放 token、坏值不产生 NaN、两个方向的时长、中途反向、减少动态效果为纯淡入淡出。
- `anchor_transition.zig`（无窗口 Cx，真实布局 / 快照 / 覆盖层 / 绘制列表）：收回时快照画在当前帧矩形、节点本身不画、
  结束后 `display:none` 与还原；展开重新快照（内容在收起期间变化）、结束同帧无覆盖层且节点恢复绘制；中途反向；
  减少动态效果；带外阴影的卡片按自身矩形飞（快照里的卡片填充正好映射到原位、阴影包含在内、飞行层按该映射绘制）；过程中命中穿透；锚点移动时跟随、裁剪区外夹取；具名锚点注销、无锚点退化、节点在过程中被释放；
  `fade_scale` 原地收起 / 无锚点展开 / 中途反向、减少动态效果下纯淡出、过程中 `setTokens` 从下一次过程生效。
- `anchor_transition_view_tests.zig`：`ui.view` 属性的挂载初始状态、信号驱动的收回 / 展开、`anchor_motion` token 生效（含源切换 `.anchor` ↔ `.fade_scale`）、
  `motion_anchor` 随源改名、作用域在过程中释放。
- `tests/yix/compiler_tests.zig`：五个 Yix 属性的编译、组件元素上作用于根、同名组件参数被拒、`<text>` 上报错。
- 静态纹理模型（`anchor_transition.zig`）：飞行中子树的 layout epoch 不变、本帧显示列表里没有子树的绘制命令、`flight_stats` 探针计数为 0、
  图层带 genie 与稳定的纹理 id 和静止位置、损伤外包含 genie 外包；从静止展开恰好一次私有渲染，落地帧画的就是真实节点且没有飞行层；
  几何冻结（锚点节点之外的变化不影响）、窗口缩放重新取目标且画面连续、锚点被重新布局时跟随；在流里的节点保留盒子（兄弟不重排）、子元素退出布局；
  反向保留纹理、不再私有渲染。
- `genie_warp.zig`（`zig build test-support`）：起止正好是原位 / 锚点、近端先捏、行不折叠且随进度连续、外包包含所有采样点、四个方向、坏值不出 NaN。
- `anchor_motion.zig`：genie 为默认画面、终点是锚点、近端先窄、淡出只在末段、仿射退化画面随行、时长 token；genie 中途反向连续。
- Metal（`zig build test-metal`，`metal_integration_tests.zig`）：genie 在进度 0 与普通仿射合成逐像素相同；进度 0.35 时朝锚点的一边已捏窄、远端仍覆盖、画面已越过原位上沿。
- Storybook `anchortransition` 故事、`genie` 故事（`examples/storybook/genie_story.zig`：Dock 最小化，可切换 Genie / Path + scale / Fade、慢动作）与 LC3 故事用例。

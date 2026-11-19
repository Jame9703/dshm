# 152 · PC/2in1 档三键「关闭」改为**收进后台**（`windowWillClose` 判别器 · 托盘常驻 · 左键唤回）

> 本轮用户原话：
>
> 「捎带手，PC端右上角的三键，关闭的动作默认改为只关闭APP窗口，实际驻留后台，
> 托盘区APP图标常驻，左键点击呼出APP，然后再全新编译」
>
> 即：**PC（2in1）档**点窗口右上角三键里的「关闭」⇒ 只把窗口藏起来，进程 / Host /
> 托盘图标继续活着；从托盘图标左键唤回窗口。
> **手机 / 平板档行为逐字不变**（仍是系统官方语义：关闭 = 退出应用）。
>
> 改动面**只在宿主侧 ArkTS**（`entry/**` 的 4 个 `.ets` + 1 个 `module.json5` 注释），
> **`hostcore/**` 与核心树一字未动 ⇒ `coreVersion` 不升**（仍 `0.2.1-alpha.2+dshm.37`）。

---

## 0. 一句话结论

| # | 请求 | 结论 | 依据 |
|---|---|---|---|
| 1 | PC 档三键「关闭」= 只收窗口、驻留后台 | 已落地（待 PC 连机复核） | `win.on('windowWillClose', …)` + 回调里 `resolve(true)` 前先 `minimize()` |
| 2 | 托盘图标常驻 | 已有物（本轮未改） | `setupTray()`：`install` → 300ms `hold` → `onIconClick`；`StatusBarTray.remove()` 只在真退出链上摘 |
| 3 | 托盘左键唤回 APP | 已有物（本轮未改） | `onIconClick('leftClick')` → `restoreMainWindow()`（`showAbility`）+ `onForeground` 里 `ensureWindowShown()` |
| 4 | 手机 / 平板档不变 | 已确保 | `handleWindowWillClose()` 首行 `isHandheldForm()` 早退；本档从不挂该监听 |

---

## 1. 根因与判据

### 1.1 为什么**不能**拿 `onPrepareToTerminate` 当判别器

`UIAbility.onPrepareToTerminate()` 的 SDK 原文把触发面写成
"clicks the close button … **or exits from the dock or system tray**" ⇒
它**分不开**这两件事：

* 「三键关闭」——本轮要拦成"收进后台"；
* 「托盘 / 任务栏退出」——本轮要放行，而且那条链上还挂着**唯一能可靠摘掉托盘图标**的收尾
  （`finalizeBeforeExit`：`StatusBarTray.remove()` → `publishExitRequest()` → `stopHostThenExit()`）。

同一个回调既要"拦"又要"放行"，且两者的区分信息不在回调参数里 ⇒ 只能另找一个判别器。

### 1.2 为什么 `windowWillClose` 可以

`window.on('windowWillClose', cb)`（API 15 起，syscap `Window.SessionManager`）的 SDK 原文：

> "Subscribes to the event indicating that the main window or child window will be closed.
> This event is triggered **only when the user clicks the close button in the system-provided
> title bar** to close the window. It is not triggered when the window is closed in other ways."

⇒ 触发面**正好**是"标题栏那个关闭按钮"，与托盘 / 任务栏那条真退出天然分开。
返回值语义：**`resolve(true)` = 不关这一个窗；`resolve(false)` 或 reject = 继续关**。

两个还有一处必须确认的地方 —— 两条回调能不能**共存**：

`onPrepareToTerminate` 的 SDK NOTE 列出三个"本回调**不会执行**"的条件，点名的是
`windowStageClose` 监听 / `onPrepareToTerminateAsync` / `AbilityStage.onPrepareTermination*`。
`windowWillClose` **不在**这三条里。本工程也**不满足**这三条（没注册 `windowStageClose`、
没实现 `onPrepareToTerminateAsync`、`AppAbilityStage` 没实现 `onPrepareTermination*`）
⇒ 预期可以共存。这条**不是靠读文档拍死**的，落了两行探针去实测判读（见 §6）。

> 【为什么**不用** `windowStageClose`】同一个 NOTE 明确：「若应用注册了 `windowStageClose` 监听，
> 本回调**不会执行**」⇒ 用了它就会把 `onPrepareToTerminate` 里的托盘摘除链一起废掉
> （`docs/101` 那条修好的回归会复发）。

### 1.3 为什么 `resolve(true)` 之前**必须**先把窗口收起

`resolve(true)` 只表示"别关这一个窗"，系统**不会**替我们把它藏起来 —— 不主动最小化，
用户看到的就是"点了关闭没反应"。回调本身是异步的（SDK 要求返回 `Promise<boolean>`，系统等
这个 Promise 落定）⇒ **先 `minimize()` 再 resolve** 正合时序。

手段选 `window.Window.minimize()`：

* 主窗调用 = 最小化到 Dock，2-in-1 上 `restore()` / 点 Dock 图标可恢复 —— 与"左键唤回"配套；
* 本工程 API 26 SDK 里 **`Window.hide()` 根本不存在**（全文 0 命中）；
* `UIAbilityContext.hideAbility()` 能真正隐藏，但**只对 PC/2-in-1 与平板**开放 ⇒ 与"手持档
  一个字节不改"的目标面不一致，本轮**不接**。

---

## 2. 实现（分档语义 · 三处挂/解绑 + 探针）

全部落在 `entry/src/main/ets/entryability/EntryAbility.ets`：

| 位置 | 作用 |
|---|---|
| `:243` `writeWindowCloseDiag()` | 关闭链的**落盘诊断**（本机读不到本应用的 ArkTS `hilog` ⇒ 一律追加到 `filesDir/diag-window-close`） |
| `:438` `onWindowWillClose` 字段 | 存成**字段**而非内联箭头函数：`off()` 必须拿到同一个函数引用，否则解绑静默失败、留下悬空回调（与 `onGeometryChanged` / `onDecorStatusChanged` 同族） |
| `:1020` `handleWindowWillClose(source)` | 分档判据 + `minimize()` + 诊断 |
| `:1326` 挂监听 | `afterWindowStageReady()` 末尾、`bindGeometry(win)` 之后，且 `if (!isHandheldForm())` |
| `:1653` 解绑 | `unbindGeometry()` 内与 `windowStatusChange` **对称**（手持档解 `statusChange`、非手持档解 `willClose`） |
| `:939` `onPrepareToTerminate()` | 本轮回**不改语义**，只加一行探针；返回值仍 `false`（继续终止），收尾顺序不动 |

`handleWindowWillClose()` 的早退顺序（`true` = 不关窗）：

1. `isHandheldForm()` ⇒ `false`（**手持档一个字节不改**：关闭仍是退出）；
2. `this.exiting` ⇒ `false`（已在退出链里，放行，否则把退出链卡住）；
3. `launchParams.kind !== WindowKind.MAIN` ⇒ `false`（只拦主窗，会话窗关闭不该让整个应用躲后台）；
4. 拿不到 `mainWindow` ⇒ 落盘 + `false`（既不装作成功、也不留"窗口还在、点关闭没反应"的死界面）；
5. 落盘 `拦截成功：最小化到后台` ⇒ `target.minimize()`：
   * `.then(() => true)` 交给系统"别关"；
   * `.catch(() => false)` 落盘 + 按系统默认关窗（降级不撒谎）。

> 【为什么早退判据里没有"托盘是否就绪"】回程入口有**两条且互相独立**：① 托盘图标左键
> （`setupTray().onIconClick` → `restoreMainWindow`）；② 任务栏 / Dock 图标（进程仍活着 ⇒
> 条目还在，点它走 `onForeground` → `ensureWindowShown`）。托盘挂不上只等于少一个入口
> （`setupTray` 本身就是"失败降级而不抛"），不该拿它当前置条件。

---

## 3. 为什么 PC/2in1 之外一个字节不变

| 分档 | 三键「关闭」 | 怎么保证没被碰到 |
|---|---|---|
| 手机 / 平板 | 退出应用（官方默认） | ① 本档**从不挂** `windowWillClose`（挂点带 `if (!isHandheldForm())`）；② 即便被挂上，`handleWindowWillClose` 首行 `isHandheldForm()` 早退；③ `onPrepareToTerminate` 语义与顺序本轮零改动 |
| PC / 2in1 | 收进后台 | 走 `windowWillClose`；托盘 / 任务栏退出仍走 `onPrepareToTerminate`（`false` = 继续终止）+ `finalizeBeforeExit` 收尾 |

分档判据取 `!isHandheldForm()`（**不是** `!isPhoneForm()`）：`isHandheldForm()` = `PHONE || TABLET`
（`platform/src/main/ets/system/FilePicker.ets`），折叠屏在设备事实上仍是 `phone`
⇒ 折叠屏与平板同属手持档、跟着不改（与 `docs/151` 的口径一致）。

---

## 4. 门禁

* `tools/check-decor-button-mode.mjs`：断言"第一次出现 `if (!isHandheldForm()) {`"必须早于
  `win.on('windowStatusChange'` —— 本轮新增的那个 `if (!isHandheldForm())` 挂在
  `bindGeometry(win)` **之后**、`windowStatusChange` **之前**的同一段里，时序安全；
  `win.off('windowStatusChange', …)` 与 `setDecorButtonStyle` / `reassertDecorButtons` 锚点未动。
* `tools/check-handheld-back.mjs`：`moveAbilityToBackground` 全文件出现次数必须 = 1
  —— 本轮**没有**在 `EntryAbility` 里用它（`minimize` 与它不是一回事）。
* `rg tools/` 复核：**没有**任何门禁断言 `onPrepareToTerminate` / `windowWillClose` 的存在与否
  ⇒ 本轮不新增门禁锚点（这条判断依据是"功能正确性由真机探针回答，静态门禁守不住回调触发面"）。

---

## 5. 出包

* `coreVersion` **不升**（纯 ArkTS + 注释改动，不碰 `hostcore/**` 与核心树）。
* 编译走 `.\tools\update-device.ps1`（内部 `hvigorw assembleHap` + `hdc install -r`）。

---

## 6. 真机判据（PC 需现场连线）

`filesDir/diag-window-close` 是本轮的**唯一判据文件**（一行一件事，带 ISO 时间戳）：

| # | 操作 | 期望读数 |
|---|---|---|
| 1 | PC 档启动 | `windowWillClose 监听已挂上（PC 档）` |
| 2 | PC 档点三键「关闭」 | 窗口消失；`ps` 里进程仍在；托盘图标仍在；文件里有 `windowWillClose 拦截成功：最小化到后台（不终止应用）` |
| 3 | 同上 | 文件里**没有** `onPrepareToTerminate 到达` ⇒ 证明两回调互斥的担心不成立（**有则按 §7 回退**） |
| 4 | 托盘左键 | 窗口回来（`onIconClick` + `onForeground.ensureWindowShown`） |
| 5 | 托盘右键系统「退出」/ 任务栏退出 | 真退出；`diag-tray` 有 `remove ok`；`ps` 零条 |
| 6 | **手机回归** | 关闭仍是退出；`diag-window-close` 里**无** `拦截成功` 行（连"监听已挂上"都不该有） |

---

## 7. 未做 / 待观察 · 回退方案

**未做**：

* 真机复核（§6 全部待跑；PC 必须现场连线，手机可立刻回归）。
* `UIAbilityContext.hideAbility()`（PC / 平板专属）—— 与"手持档一个字节不改"面不一致，不接。
* `onApplicationFocusStateChange` / `setTouchableAreas` 等 API 26 相邻特性 —— 与本需求无关，不顺手接。

**回退方案**（若真机证明 `windowWillClose` 不触发、或与 `onPrepareToTerminate` 互斥）：

改用当年 `ab996b8` 的写法 —— `onPrepareToTerminate` 判 `!isHandheldForm()` 时 `return true`
（取消终止）并同步 `win.minimize()`，`finalizeBeforeExit` 只在"显式退出标记"或手持档才走。
当年撤掉它的理由是**托盘图标残留**（`docs/101`），而那条已由 `StatusBarTray.remove()` 修掉，
**不是这条判据本身的问题** ⇒ 回退是可行的，但会失去"三键关闭 vs 托盘退出"的干净区分
（需要在回调里再读一次"是不是退出标记"），故优先保留本轮的 `windowWillClose` 方案。

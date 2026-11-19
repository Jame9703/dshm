# 419 · 沉浸光感混合承载落地（entry 弹窗材质 + 网页菜单原生接管）

> 日期：2026-11-17 ｜ 状态：**已落地（entry 构建绿），真机观感待验**
>
> 用户口径：「沉浸光感走推荐的方案，帮我实现，规划清楚就直接做完，期间不用我确认，保证现有功能正常即可」。
>
> 关联：[`279`](279-沉浸光感调研（API26特性可行性与实现方案）.md) / [`280`](280-沉浸光感二次调研（官方AI方案逐条求证与重新规划）.md)（调研链）、
> [`281`](281-侧栏浏览器卡死与沉浸光感观感复核（端口偏移断链）.md)（10-29 方案档，其 §3.1 的 entry 行与当前代码不符，见 §4）、
> [`283`](283-Web内沉浸光感（垫片实现·三次失败复盘与最终口径）.md)（Web 内路线三次失败 ⇒ 本轮走原生混合承载，不碰 Web 画布）。

---

## 0. 一页结论

| 面 | 落地 |
|---|---|
| AlertDialog 弹窗 | entry 4 处全部挂 `systemMaterial: dialogMaterial()`（THICK，platform Kit） |
| Web 右键/长按菜单 | `onContextMenuShow` 接管（return true）→ `openMenu` 弹原生菜单：THIN `immersiveMaterialOf`（非交互）+ `WithTheme` 定深浅 + `anchorPosition` 锚到 Stack 内 1×1 透明块 |
| 菜单项集 | 链接：打开链接（直开不二次确认）/ 复制链接；图片：复制图片 / 保存图片；可编辑：剪切 / 复制 / 粘贴 / 全选（`EditStateFlags` 位掩码）；纯选区：复制 / 全选；空集回退默认菜单 |
| 共享 Kit | `ImmersiveMaterialKit` 三个包装函数补**实参求值前**的 API≥26 判定 + try/catch（`ImmersiveStyle` 在未实现设备上是 `undefined`，裸求值抛错） |
| 权限面 | 零新增（`result.paste()` 复用已声明 `READ_PASTEBOARD`；entry 18 / phone 9 不变） |
| 诊断 | `diag-material`（能力探针，启动一次性）+ `diag-webmenu`（菜单全链路） |
| 回退 | 任何异常 / 空项 / 坐标越界 → `return false` → ArkWeb 默认菜单 |

**一句话**：混合承载 = 弹窗与网页菜单走**原生沉浸材质**（自绘 ArkUI 面），Web 画布本身不动（10-11 真机实验结论：材质盖 ArkWeb 只是色罩 + 模糊，不是内容相关毛玻璃）。

## 1. 落地内容（代码事实）

| 位置（entry `WebApp.ets`，8199 行版） | 内容 |
|---|---|
| 4 处 `showAlertDialog` | ① `confirmCloudLogin`（登录华为账号确认）② 打开外部浏览器确认 ③ 无法打开外部浏览器（失败提示）④ 系统预览未受理（失败提示）——均挂 `systemMaterial: dialogMaterial()` |
| 模块级 | `WebContextMenuItem` / `WebContextMenuPanelParams` 接口 + 全局 `@Builder WebContextMenuPanel`（`WithTheme` 包 `Menu{ForEach(MenuItem)}`，key=label） |
| 接管链 | `.onContextMenuShow((event?) => this.handleWebContextMenuShow(event))`（`.attributeModifier` 之后） |
| `handleWebContextMenuShow` | 按语境构建菜单项 → `openMenu(ComponentContent, {id:'dshm-web-menu-anchor'}, {systemMaterial: THIN 材质, anchorPosition:{x,y}})`；`onDisappear` → 幂等 `closeContextMenu` + `dispose`；`openMenu` reject → dismiss + dispose |
| Stack 锚点 | `Column().width(1).height(1).position({x:0,y:0}).hitTestBehavior(HitTestMode.None).id('dshm-web-menu-anchor')`（Web 收口后、启动页前） |
| 共享 Kit（platform `ImmersiveMaterialKit`） | `dialogMaterial` / `shellMaterial` / `controlMaterial` 先判 `sdkApiVersion>=26` **再**求值 `ImmersiveStyle.X` 实参 + try/catch；`immersiveMaterialOf` JSDoc 补调用方纪律 |

## 2. 关键机制（SDK d.ts 已核）

- `AlertDialogParam.systemMaterial?: ImmersiveMaterial`（since 26）——**存在且有效**；「AlertDialog 无 systemMaterial」旧结论作废。
- `ContextMenuOptions.systemMaterial?`（`MenuOptions` 继承）；`getPromptAction().openMenu(content, target:{id}, opts)` since 18；`anchorPosition` since 20。
- `position` 相对父**内容区**（= 父尺寸扣 border / padding / safeAreaPadding）⇒ Stack 内 `position(0,0)` 与 Web 原点对齐，Stack 有 padding 也不偏。
- 材质 API 26 起但在未实现设备上 `uiMaterial.ImmersiveStyle` 为 `undefined` ⇒ **实参求值必须先过 API 闸门**（本轮 Kit 修复的根因；entry 最低 API 23 的平板裸求值会当场抛错）。
- `WithTheme` 定深浅（10-11 真机结论：`ThemeColorMode.SYSTEM` 实测仍给深色）；`colorInvert` 不开（糊菜单自身条目文字）。

## 3. 诊断探针（filesDir，应用内终端 cat 即读）

| 标记 | 时机 | 内容 |
|---|---|---|
| `diag-material` | 启动一次性（`aboutToAppear` 尾部） | `sdk=<n> supported=<0\|1> level=<n>`；API<26 记 `below26` |
| `diag-webmenu` | 每次右键/长按 | `show x y src media link sel editable flags items mat` / `fallback <原因>` / `open ok\|fail <err>` / `appear` / `dismiss` / `item <label>` / `copy-link-fail <err>` |

## 4. 与 [`281`](281-侧栏浏览器卡死与沉浸光感观感复核（端口偏移断链）.md) §3.1 的差异

281（2026-10-29 方案档，文首自注「不含已做的代码改动」）§3.1 表中 entry 相关行与当前代码不符：

| 281 §3.1 行 | 当前实测 |
|---|---|
| 弹窗挂载「entry 4 处」 | 本轮落地**前** entry 0 处 `dialogMaterial`（git 2026-10-21 提交版同为 0；「phone 3 处」属实）。本轮落地后 entry 为 4 处（见 §1） |
| 顶栏挂载 `topBarShellMaterial = shellMaterial()` | 当前 entry / phone 均无 `shellMaterial` 调用；`topBarBgNow()` 为无引用死代码（已于 2026-11-17 随 [`420`](420-%E8%AE%BE%E7%BD%AE%E9%9D%A2%E6%9D%BF%E5%AE%98%E6%96%B9%E6%8E%92%E9%99%A4%E6%89%A9%E5%88%B0%E5%85%A8%E5%BD%A2%E6%80%81%EF%BC%88%E5%B9%B3%E6%9D%BF%E6%B5%85%E9%BB%91%E8%A6%86%E7%9B%96%E4%BF%AE%E5%A4%8D%E4%B8%8E%E9%97%A8%E7%A6%81%E5%9F%BA%E7%BA%BF%E5%86%BB%E7%BB%93%E8%AE%A2%E6%AD%A3%EF%BC%89.md) 退役清理） |

281 保留原样（方案档有审计价值）；entry 侧材质现状以本文为准。

## 5. 验证与余项

- entry 构建（`devecocli build --modules entry`）**全绿**（含 Kit 改动；warning 全为存量）。
- phone 独立构建在本机 `devecocli` 下不产出（1 task 空转，环境受限不作判据）；phone 编译由 beta 出包（`--combined-app`）全量覆盖。
- 真机待验判据：Web 内长按/右键出玻璃菜单（项随语境）、4 类弹窗带玻璃；`cat files/diag-material`（supported=1）、`cat files/diag-webmenu` 全链路标记；API<26 设备菜单回退系统默认且不崩。
- beta 包：登录修复（判据 `ws item attempt=waiting-browser url=yes → deliver auto <url>`）与本轮沉浸光感**同一包双验证**。

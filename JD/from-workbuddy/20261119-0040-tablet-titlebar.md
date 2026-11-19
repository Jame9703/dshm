# 交接单：平板系统标题栏淡化 + 竖屏适配核查

- **ID**：JD-006
- **提交方**：WorkBuddy
- **日期**：2026-11-19 00:40
- **状态**：待 DevEco 编译 / 真机验证
- **对应看板**：[`../STATUS.md`](../STATUS.md)

## 1. 变更摘要（开发已完成，编译交给 DevEco）

平板自由窗口的系统标题栏"淡化"：把右上角**三键缩小**（背景 24vp / 间距 8vp / 贴右 12vp），降低存在感；**只改按钮样式，不改装饰可见性** ⇒ 三键、四边缩放、分屏入口全部保留。PC / 2in1 保持默认。

## 2. 涉及文件

- `entry/src/main/ets/entryability/EntryAbility.ets` —— `reassertDecorButtons()`（本文件**唯一**一处 `setDecorButtonStyle`）。

## 3. 关键约束与"半透明"为何没做满（重要）

- 本项目门禁 `check-decor-button-mode` 钉死：**能力层只能有 1 处 `setDecorButtonStyle`**，且**手持档启动分支只允许"发布"，不许加装饰调用链**。因此改动收进既有 `reassertDecorButtons()`，未新增第二处。
- SDK（`@ohos.window.d.ts`）**没有"标题栏背景透明度"公开 API**：`DecorButtonStyle` 只有按钮字段；能影响整条标题栏的只有 `setWindowDecorVisible(false)`（整体隐藏=沉浸，内容延伸到标题区）。
- 真"半透明"只能走 `setWindowDecorVisible(false)` + `setWindowTitleButtonVisible(true,true,true)`，但会**放弃四边缩放边框**（docs/416 的既定取舍），且与 `check-free-window-decor` 里"自由窗口恢复装饰=可见"的期望冲突。⇒ 属产品取舍，未擅自做；若要，请 DevEco 评估并同步改该门禁。

## 4. 竖屏适配核查（开发已完成）

- 两壳 `WebApp.ets` 的侧栏几何已按官方断点收口（2026-11-18）：`narrow=viewport<1024`、`drawer<768`；`写死 280/56` 只在 `@media (min-width:1024px)` 生效，`<1024` 由 `tagLayout()` 补 `data-sidebar-drawer` 交官方抽屉浮层。
- 平板竖屏（典型 736–950vp）/ 折叠屏展开 ⇒ 走抽屉，不挤压主区。
- 本次未改这段逻辑（已正确），仅随附核查结论。

## 5. 开发侧验证（已跑，门禁绿）

```sh
node tools/check-decor-button-mode.mjs        # PASS  第一组 9/0、第二组 130/0
node tools/check-window-mode.mjs              # PASS 27/0
node tools/check-sidebar-shim-css.mjs         # PASS 32/0
node tools/check-dual-shell-parity.mjs        # OK 双壳 7 文件一致
node tools/check-phone-sidebar-core-compat.mjs# PASS
```

> 未编译、未出包（按分工交 DevEco）。`check-free-window-decor.mjs` 当前在本机崩溃（`KEY_MAIN_WINDOW_ID is not defined`，为其 harness 作用域的既有问题，与本次改动无关），请 DevEco 一并看。

## 6. 请 DevEco 做的事

1. **编译**：`devecocli build --modules entry`（若同时改 phone 则加 `--product phone`）。
2. **真机（平板/2in1 自由窗口）**：
   - 三键是否明显变小、位置/配色正常；
   - 四边缩放、分屏入口、拖动/双击最大化是否仍在（应保留）；
   - 竖屏平板 / 折叠屏展开：侧栏是否走抽屉、主区未被挤压。
3. **决策项**：是否进一步做成"真透明标题栏"（`setWindowDecorVisible(false)`，放弃四边缩放，需同步改 `check-free-window-decor`）。由你/用户定。
4. 结论写入 `JD/from-deveco/20261119-tablet-titlebar-result.md`，更新 `STATUS.md`（JD-006）。

## 7. 边界

未改可见性/权限/版本；未编译/未出包；未动 `terminal.js`。

## 8. 红线遵守声明

未 `git commit`；未 `hdc uninstall`；未删交付件；未自行升版本/改权限。

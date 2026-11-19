# 247 · PC / 平板 / 手机三档侧栏布局修正（Edge / Pro Max 按 PC 接入）

> 日期：2026-10-24
>
> 应用：`1.1.6 / 1010007`
>
> 核心：`0.2.1-rc.3+dshm.93`

用户侧载复验 `docs/246` 后确认：只按“原生顶栏是否显示”隐藏 Web 入口范围过宽。
Edge 上确实消除了重复按钮，但左侧栏仍被自动收起。最终产品口径如下。

## 1. 三档布局

| 档位 | 设备 | 顶栏 | 左侧栏默认 |
|---|---|---|---|
| PC | PC / 2in1 / MatePad Edge / MatePad Pro Max / 平板电脑模式 | 原生 PC 顶栏常驻 | 常驻；可用 PC 顶栏按钮手动收起 |
| 平板 | 普通平板、折叠屏展开态 | 不画原生 PC 顶栏 | 横屏常驻；竖屏默认收起只留入口 |
| compact | 直板手机、折叠屏单屏折叠态 | 不画原生顶栏 | 收起，左右栏通过入口按钮覆盖打开 |

普通平板竖屏进入时只自动收起一次；用户在竖屏里手动打开后，巡检不会反复关闭。
从竖屏转回横屏会重新进入平板默认展开链。折叠屏从单屏展开后会重置一次性自愈，
按同一平板规则处理。

## 2. 判据收口

- `DeviceFacts.isDesktopPcSeries()` 覆盖 `QXS-*`、`MatePad Edge`、
  `MatePad Pro Max` 与 `MatePad ProMax` 市场名；
- `platformForm()`：PC、2in1、Edge、Pro Max 与平板电脑模式统一返回 `desktop`；
- desktop 形态**无条件**挂 `dshm-pc`，进入 PC 默认展开与自愈链；
- PC 档才隐藏 Web 内重复左入口；普通平板不挂 `dshm-pc`，保留自己的左右侧栏入口；
- PC 窗口退回普通平板窗口时会摘掉 `dshm-pc`，避免旧分类残留；
- 覆盖式抽屉只挂 `dshm-compact`，不再作用于全部 `dshm-handheld`；
- PC / Edge 的原生顶栏在横竖屏都常驻；普通平板不画原生 PC 顶栏。

## 3. 回归门禁

已通过：

- `check-sidebar-shim-css.mjs`：11/0，4 个变异全部判红；
- `check-handheld-sidebar-recover.mjs`：正例 0 失败，M1–M12 全部判红；
- `check-feature-wiring.mjs`；
- `check-decor-button-mode.mjs`：顶栏策略与 A–R 对照臂全绿；
- `check-edge-desktop-policy.mjs`；
- `check-pc-only-surface.mjs`；
- `check-pc-api26.mjs`；
- `assert-resfile-sync.mjs`。

## 4. 产物

AGC 正式签名 release：

```text
dist/release-test/DSHM-1.1.6-1010007-core93-sidebar-pc-tablet-r4-release-20261024.app
size    460,637,942 B
sha256  859c0c47f12c6b3762cd5d03dc6d8765d56e7ecf10759ce591d412656dcce682
```

DSHM Beta 合包：

```text
dist/beta/DSHM-beta-1.1.6-1010007-core93-sidebar-pc-tablet-r4-combined/
  DSHM-beta-1.1.6-1010007-combined-debug.app
size    465,953,167 B
sha256  32bc9a250150db18a8f4a2628941de542fef1815515577e286bd9ac8c17967cf
```

两个 `.app` 均通过 `hap-sign-tool verify-app`。当前环境没有可用 `hdc`
设备目标，最终三档布局由用户侧载复验。

## 5. 验收重点

1. Edge / Pro Max 横竖屏都显示 PC 顶栏，左侧栏默认常驻；
2. Edge / Pro Max 只有一个左侧栏入口；
3. 普通平板横屏左侧栏常驻，竖屏默认收起并保留入口按钮；
4. 普通平板竖屏手动打开后不被巡检反复收起；
5. 折叠屏展开后按平板规则，横屏常驻、竖屏收起；
6. 直板手机左右栏默认隐藏、只留入口按钮；
7. 旋转、会话切换、设置面板开关后都不出现重复入口或入口消失。

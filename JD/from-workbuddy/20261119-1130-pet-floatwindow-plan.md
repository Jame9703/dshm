# 方案规划 v2：dsh-pet 桌宠三端适配（PC / 2in1 · 平板 · 手机）

- 性质：**方案评估，未落地代码**
- 版本：v2（2026-11-19 15:20，按华为工程师补充参考重排三端）
- 结论：**PC / 2in1 可做到"桌面级悬浮桌宠"；平板为"自由浮窗（不置顶）"；手机不做桌面悬浮，降级为应用内形态**。最大不确定项仍是 `dsh-pet` 源码形态。

> **2026-11-20 复核（结论有修正）**：详见 [`outputs/DSHM-桌宠悬浮窗方案复核-20261120.md`](../../outputs/DSHM-桌宠悬浮窗方案复核-20261120.md)。
> 关键修正：① 平板受 `entry.deviceTypes` 的 PC 应用分类阻断，当前不可做浮窗；② 透明区逐像素穿透在自由窗口主窗不可行（仅子窗/全局悬浮窗，后者需受限权限）；
> ③ `excludeFromMissions` 对三方应用无效；④ 拖拽须 `startMoving()`，系统标题栏拖拽不存在；⑤ 权限应为 18→20（`WINDOW_TOPMOST` + `SET_WINDOW_TRANSPARENT`）。

---

## 一、工程师参考 → 落地映射（API 已在本机 SDK 核实）

| 需求 | 实现 | SDK 事实 |
|---|---|---|
| 全局悬浮窗 | 独立 `UIAbility` + 自由窗口（参考 FAQ 995） | `setWindowTopmost` **since 14** |
| 无边框（去阴影） | `setWindowShadowEnabled(false)` | **since 20** |
| 无标题栏 / 无三键 | `setWindowDecorVisible(false)` + `setWindowTitleButtonVisible(false,false,false)` | since 11 / 14 |
| 背景透明 | `setWindowBackgroundColor('#00000000')`；可选 `SET_WINDOW_TRANSPARENT`（API 20+，normal） | since 9 |
| 不规则命中区 | `setWindowMaskWithAlpha(mask,...)` | **since 26** |
| 不抢焦点（可选） | `setWindowFocusable(false)` | since 9 |
| 右键/长按菜单 | ArkUI `bindContextMenu(..., ResponseType.RightClick)`，指向型/自定义菜单 | 官方示例 4 |

> 关键：`setWindowTopmost` 仅在**支持且处于自由窗口**的设备上生效，否则返回 801 —— 这直接决定三端分级。

## 二、三端能力矩阵与降级策略

| 能力 | PC / 2in1 | 平板（自由窗口） | 手机 / 折叠单屏 |
|---|---|---|---|
| 独立悬浮窗 | ✅ | ✅（自由窗口下） | ❌（默认全屏，无窗口概念） |
| 全局置顶 | ✅ | ⚠️ 多数不可用（801） | ❌ |
| 无边框 / 透明 | ✅ | ✅ | — |
| 拖拽移动 | ✅（系统无标题栏拖拽） | ✅ | — |
| 右键 / 长按菜单 | ✅ 右键 | ✅ 长按 | ✅ 长按（应用内） |
| 常驻桌面 | ✅ | ⚠️ 仅浮窗存在期间 | ❌ |
| **降级形态** | 全功能桌宠 | **浮窗桌宠（不置顶）** | **应用内桌宠页 / 小窗入口，不做桌面悬浮** |

## 三、技术架构

1. **窗口层**：新增 `PetAbility`（`launchType: specified`、`supportWindowMode: ["floating"]`、`excludeFromMissions: true`），复用 `platform/.../WindowRegistry.ets` 的 specified 多窗机制，新增 `pet` 键。
2. **窗口属性**（逐项独立 try，801/能力缺失不致命）：
   `setWindowShadowEnabled(false)` → `setWindowDecorVisible(false)` → `setWindowTitleButtonVisible(false,false,false)` → `setWindowBackgroundColor('#00000000')` → `setWindowTopmost(true)`（仅 PC/2in1）→ 可选 `setWindowFocusable(false)`。
3. **渲染**：先 A（Web，复用 ArkWeb + 现有桥），体验不足再 B（原生 Canvas/Live2D）。
4. **交互**：右键/长按用 `bindContextMenu`；拖拽依赖系统无标题栏拖拽；透明区穿透用 `setWindowMaskWithAlpha`（API 26）。
5. **宿主**：`dsh-pet` 作为 hostcore 插件跑在宿主 Node 内，窗口只负责渲染与交互；不新增第二条通信通道。

## 四、dsh-pet 鸿蒙适配缺口（阶段 0 逐项确认）

1. 是否 Electron 专用（`BrowserWindow`/`alwaysOnTop`/`transparent`/`setIgnoreMouseEvents`）→ 全部替换为 ArkUI 窗口 API。
2. UI 技术栈（Web / Canvas / Live2D）→ 决定 A/B 路线。
3. 资源体积与首帧成本（精灵图/模型/音频）。
4. 系统 API 依赖：托盘、开机自启、通知、剪贴板、文件监听。
5. Node 原生模块能否编译为 openharmony-arm64。
6. 交互模型：拖拽、点击穿透、右键菜单、悬停气泡。
7. 生命周期：主窗最小化/退出时是否常驻（与 `BackGroundAbility` 的关系）。

## 五、分期与工作量（人日，三端）

| 阶段 | 内容 | 估时 |
|---|---|---|
| 0. 源码评估 | 取得 `dsh-pet`、能力盘点、A/B 选型 | 1–2 |
| 1. PC/2in1 原型 | `PetAbility` + 无边框/透明/置顶/拖拽/位置记忆 | 2–3 |
| 2. 平板适配 | 浮窗不置顶降级、长按菜单、尺寸/多窗共存 | 1–2 |
| 3. 手机降级 | 应用内桌宠页/入口、能力探测与提示 | 1–2 |
| 4. 插件接入与打磨 | `dsh-pet` 适配、渲染接入、点击穿透、功耗、权限面 | 4–6 |

合计 **9–15 人日**（若 `dsh-pet` 深绑 Electron，阶段 4 可能 +2～3 人日）。

## 六、权限与合规（三端差异）

- `WINDOW_TOPMOST`：normal / system_grant / **PC·2in1** / API 13 起，无需 ACL；手机与多数平板不可用。
- `SET_WINDOW_TRANSPARENT`：API 20+，normal；用于去主窗边框阴影。
- entry 权限 **18 → 19**：`check-permission-surface` EXPECTED、自检样本、隐私协议 reason、`docs/HANDOFF` 均需同步。
- 隐私协议需补一条"桌宠窗口置顶/透明"的用途说明。

## 七、主要风险

1. **置顶受限**：平板/手机无置顶，桌宠会被其他窗口遮挡 → 必须明确"平板是浮窗、手机是应用内"的产品边界。
2. **点击穿透**：透明区域若不能穿透，会挡住桌面操作；`setWindowMaskWithAlpha` 需 API 26。
3. **最近任务**：用 `excludeFromMissions` 规避（需设备核实）。
4. **功耗/常驻**：桌宠长期运行，需按官方功耗建议克制刷新与动画。
5. **审核**：刻意避开受限的系统级悬浮窗权限，走 normal 权限路径。

## 八、待确认决策点

1. 渲染路线：先 **A（Web）** 还是直接 B（原生）？
2. `dsh-pet` 来源：你提供仓库，还是我按公开仓库评估？
3. 平板形态：接受"浮窗但不置顶"吗？
4. 手机形态：做"应用内桌宠页"还是本期不做？
5. 排期：正式上架后单独排 1.1.9？

---

> **状态（2026-11-19）**：方案 v2 已按工程师参考重排三端；当前**暂缓，正式上架后再启动**。启动时按"八、待确认决策点"逐项拍板后进入阶段 0。

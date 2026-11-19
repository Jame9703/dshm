# 193 · 手持档右侧栏打开时返回手势直接回桌面（BACK_SHIM 不认识右侧栏）

> 2026-10-18 用户复报（手机 `62T0225B18039433`）：「点开右侧边栏的时候，手势不返回会话区，
> 而是直接回到桌面了」。

## 1. 根因

`BACK_SHIM_JS` 的分层消费链只有四支：`panelBack`（插件二级页）→ `overlay`（dialog/menu/listbox/
设置面板）→ `drawer`（左侧抽屉）→ `home`（主面板回会话）。**右侧栏不在任何一支里**：

- 它不是 `OVERLAY_SEL` 里的 `role=dialog/menu/listbox`（是 pane 容器）；
- 它不进 Web 历史（官方前端纯 SPA，`accessBackward()` 恒假）；
- 左侧抽屉判据 `__DSHM_SIDEBAR__.state()` 也不覆盖它。

⇒ `consume()` 返回 `none` ⇒ ArkTS 侧 `finishWebBack('none')` 走 `minimizeToBackground()`
⇒ 系统返回手势把应用最小化回桌面。

**第二层坑**：即使网页肯回 `right`，ArkTS 的 `readWebVerdict()` 白名单（`overlay/drawer/panel/home/none/off`）
里没有 `right` ⇒ 会被判成 `absent`，**照样**走系统默认回桌面。两处必须同时改。

## 2. 修法

| 层 | 改动 |
|---|---|
| Web（`BACK_SHIM_JS`） | 新增 `RIGHT_OPEN_SEL = '[data-sidebar-right-open]'`（官方展开态属性）；`rightPanelVisible()`（属性 + 非 `aria-hidden` + 可见）、`rightPanelToggle()`（`data-sidebar-right-toggle`）、`consumeRightPanel()`：点官方收起按钮 ⇒ 返回 `right`；320ms 未收起则补一次 `Escape`（**绝不** `askSystemBack`，否则又回桌面） |
| 顺序 | `consume()`：`panelBack` → **`right`** → `overlay` → `drawer` → `home`；`state()` 同步新增 `right` |
| ArkTS | `readWebVerdict()` 白名单、`finishWebBack()` 的"已消费"集合都加入 `right` |
| 门禁 | `check-handheld-back` 新增 5 条断言 + **对照臂**（删掉右侧栏分支必须判红），45 passed / 0 failed |

## 3. 验收判据（真机）

1. 打开文件预览（右侧栏）→ 右缘内划 → **右侧栏收起、回到会话区**（不退出应用）。
2. `files/diag-web-console` 出现：
   `[dshm-back] consume: right-panel <panel 描述>`
3. `files/diag-web-back` 最后一行是 `right`（ArkTS 侧确认"已消费"）。
4. 连划第二次：右侧栏已关 ⇒ 若无其它层，按原语义回桌面（这是预期，不是回归）。

## 4. 边界

- 右侧栏收起按钮缺失的形态：退化为对面板派发 `Escape`（官方关面板同路径），仍返回 `right`。
- PC / 2in1：`handheld()` 为假，`consume()` 首行即 `off`，行为不变。

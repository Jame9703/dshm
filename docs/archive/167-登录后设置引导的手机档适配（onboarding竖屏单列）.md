# 167 · 登录后「设置引导」的手机档适配（DesktopOnboarding 竖屏单列）

> 用户原话：**"首次进入后，登录 deepseek 账号，会进入设置引导，在这个界面能不能适配手机端，
> 现在的解决方案是直板机横屏过来。"** —— 本轮把这个"只能横屏用"的界面改成竖屏可用。

## 0. 这个界面是什么（先把对象钉准）

| 项 | 事实 | 出处 |
|---|---|---|
| 渲染者 | `@deepseek-ai/dsh-client-ui-settings-account` 的 `DesktopOnboarding` | 核心树该包 `lib/client.js` |
| 挂载 | `ctx.slots.register({name:'shell.overlay', id:'desktop-onboarding'})` → **body portal**，`position:fixed;inset:0;z-index:900` | 同上（`OnboardingSurface`） |
| 四步 | `welcome → purpose → process → credit`（再 `done`） | 同上（`OnboardingSettingsFields.step`） |
| 稳定锚点 | `section[data-desktop-onboarding=<step>]`（JSX 字面量）；覆盖层根内 `[data-window-drag="true"]` | 同上（不是 CSS Modules 哈希） |
| 进度真源 | **设备本地** Host settings 的 ns `ui-settings-account`：`step` / `purpose` / `process` / `completion` / `usage` / `developerTools` | 同包 `lib/index.js` 的 `Config` |
| 显示条件 | `desktopOnboardingVisible = ("dshDesktop" in globalThis)`；`visible = !done && signedIn && !unavailable` | client.js（本仓 `WebApp.ets` 的 `DESKTOP_CARRIER_JS` 注入 `dshDesktop` 是**故意**的：不注入则账号菜单/登录/设置面板整块不注册，见该常量头注） |

## 1. 为什么竖屏用不了（都是上游 CSS 里的原值）

- `.content`（四步共用的包裹层）：`position:absolute;top:50%;left:50%;transform:translate(-50%,-50%)`。
- 欢迎步：文案 `.copy` **固定 520px** 且绝对定位；插图 **1247×822**、`left:min(41.667vw+112.5px,712.5px)`，
  内层又是一张 **1331px** 的绝对定位图。
- 用途卡 **2 列** / 流程卡 **3 列**（`repeat(2|3,minmax(0,1fr))`），卡内 `padding:48.5px 32.5px 64.5px`、`min-height:222px`。
- 主按钮 `position:absolute;top:100%;margin-top:100px`；额度步是 `grid-template-columns:594px 400px`。
- 上游的窄屏处理**最窄只到 `@media (width<=1100px)`** —— 没有手机档（实测 `grep @media` 全表：1200/1100）。

直板机竖屏 ≈ **366 CSS px** ⇒ 文案被切、卡片列挤成一条、按钮跑出视口。用户只能横屏。

## 2. 修法（`entry/src/main/ets/pages/WebApp.ets` 的 `ONBOARDING_SHIM_JS`）

与 `SIDEBAR_SHIM_JS` / `SETTINGS_SHIM_JS` **同一套路**："打标记 + 自己的 CSS + fail-closed"，
且**一个哈希类名都不写**：

1. **只在直板手机档**：`html.dshm-phone`（与设置面板垫片同源，唯一真源仍是原生桥）⇒ 平板 / 折叠屏 /
   PC / 2in1 **一个字节都不改**（它们宽度够，且用户已定"平板向 PC 看齐"）。
2. **只认两个官方字面量锚点**：`section[data-desktop-onboarding]` 与 `[data-window-drag="true"]`；
   结构对不上（不在 body portal / 认不出拖拽带 / 没有内容块）就只记日志、**不挂 `dshm-onb-ready`**，
   整套 CSS 一条不生效 ⇒ 页面退回官方桌面版式（宁可"没适配"，也绝不改出半拉子）。
3. **版式改写**（全部以 `html.dshm-phone .dshm-onb-page.dshm-onb-ready` 起头）：
   - `.page`：`box-sizing:border-box` + `height:auto;min-height:100%` + 四边内边距（含 `env(safe-area-inset-*)`）；
   - `stage`：`flex+center` → **顶部对齐 + 纵向滚动**（居中配 overflow 会把顶部内容顶出可视区，滚不到）；
   - `.content`：绝对居中 → 常态流式 `flex-direction:column`；文案块去掉 520px 固定宽；
   - 插图两层绝对定位 → 置顶（`order:-1`）+ 按容器宽度缩放；
   - 卡片格：`div:has(>div+div)`（用途步）与 `[role="radiogroup"]`（流程步）→ **单列**，卡内 padding/圆角收小；
   - 主按钮：`purpose/process` 的 `div:has(>button)` 回到正常流、整行；额度步的「去充值 / 下一步」竖排；
   - `<footer>`（第二步起：上一步 / 跳过）与 `[role="alert"]`（保存失败提示）：绝对定位 → 跟着内容走；
   - 字号：h1 28→22、正文 16→14、卡内说明 15→13。
4. **顺手一条**：把该 section 加进 `SIDEBAR_SHIM_JS` 的 `PANEL_SEL` ⇒ 引导期间 **⊞ 自动隐藏**
   （它是全屏 portal，⊞ 是钉在视口左上角的浮动按钮，不藏就会压在标题上）。

> 首跑踩到的坑（已修）：官方 `.page` 是 `width:100%`，而垫片新加的 padding 落在 **content-box** 上
> ⇒ 整页右溢 2×18px，文案与按钮右边被切。修法：给 `.page` 补 `box-sizing:border-box`。

## 3. 真机验证（手机 `62T0225B18039433`，2026-10-16）

| 项 | 读数 |
|---|---|
| 垫片接线 | console：`[dshm-onb] shim installed` → `手机档布局已生效（step=welcome）`（diag-web-console 可查） |
| 四步截图 | welcome：插图置顶自适应 + `开始设置` 整行；purpose：两张卡**单列** + `继续` 整行 + 底部 `上一步/跳过` 可达；process：三张卡**单列**；credit：插图 + 文案 + 按钮竖排 —— **四步都能竖屏走完** |
| 右溢修复对照 | 修前 `%TEMP%\dshm-onb1.jpeg`（文案/按钮右边被切 18px）→ 修后 `onb3/4/5.jpeg`（贴边整齐） |
| 滚到底 | `%TEMP%\dshm-onb6.jpeg`：末屏元素完整、手势条下方留白够，无裁切 |
| ⊞ 是否藏 | 四张截图左上角都没有 ⊞ ⇒ `PANEL_SEL` 那条接线生效 |
| 返回键 | 引导页按返回 = 最小化到桌面（**不吞返回键**，符合本仓"不盲用"纪律）；重进 APP 仍停在当前步骤 |
| 门禁 | 仓库内 26 条全绿（含 `check-arkts-entry` 0 error、`check-sidebar-shim-css`、`check-handheld-back`、`check-dead-code`、`check-feature-wiring`） |

**验收技巧（下次复现这条引导，不必卸载重装）**：进度就在 settings ns `ui-settings-account` 里。
`hdc fport` 后取 cookie，`POST /api/settings/update`，args = `{ns:"ui-settings-account", patch:{step:"welcome"}}`；
**客户端实时订阅** ⇒ 2~3 秒界面自己切到那一步。验完改回原值即可
（本轮原值：`step=done, purpose=both, process=detailed, completion=completed`）。

## 4. 产物

| 文件 | 大小（B） | sha256 |
|---|---:|---|
| `dist/beta/DSHMbeta-1.1.2-core0.2.1-alpha.4+dshm.56-arm64-signed.hap` | 442,300,907 | `D93F10881FAD0368A90ED1DBE875D46486C832655DE0EB24D62BB4879539AFC6` |

本轮**只动 entry 侧垫片**（核心树未动）⇒ **`coreVersion` 不升**（仍是 `0.2.1-alpha.4+dshm.56`），
但**产物 sha 变了**：`dist/beta/README.md`、`SHA256SUMS.txt`、`更新说明-20261016.md` 三处已同步成上表这一份。

## 5. 未做 / 待办

- ⚠️ **该垫片还没有专属门禁**（本仓其余垫片都有，例如 `check-sidebar-shim-css` / `check-handheld-back` /
  `check-market-bridge`）。建议新增 `tools/check-onboarding-phone.mjs`：断言 phone 门 / 两个稳定锚点 /
  fail-closed / 关键 CSS 规则 / 已注册进 `pickerShimScripts` / ⊞ 判据含该 section，并配 3~4 条变异臂。
- 平板 / 折叠屏**刻意未适配**（沿用"设置面板只手机化"的既有口径）；若平板也要，按用户"向 PC 看齐"的方向另议。
- 引导页期间返回键的语义（现在=最小化）如果用户希望改成"什么都不做 / 跳过引导"，另行拍板。
- **未 commit / 未 push。**

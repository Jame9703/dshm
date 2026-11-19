# 359 · Web 液态玻璃化可行性评估（HarmonyOSLiquidGlass 调研）

> 日期：2026-11-05 ｜ 触发：用户给出 https://github.com/Liu-gt/HarmonyOSLiquidGlass ，
> 要求评估「把 DSHM 的 Web 界面全部液态玻璃化」
>
> 本轮只做调研与样张，不改产品代码。参考源码保存在 `.research/liquid-glass-ref/`（gitignore 区）。

---

## 0. 结论（先看这段）

1. **这个仓库不能直接给我们的 Web UI 上玻璃。** 它不是 CSS 库、也不是可叠加的玻璃容器，
   而是**整屏 XComponent + C++ GLES 自绘**的场景渲染器（`libbackdrop.so`，渲染器源码 251 KB）。
   它的"透射"只接受两种背景：① 一张 RGBA 位图；② 用 `BuilderNode(RENDER_TYPE_TEXTURE)`
   把 **ArkUI 组件树**渲进纹理。**ArkWeb 的网页内容没有这条纹理通道**。
2. **"Web 全部液态玻璃化"本身可以做，但只能做 CSS 近似版**：模糊 + 饱和 + 半透明分层 +
   边缘高光 + 噪点 + 光泽渐变。**真折射/色散/逐像素位移做不到**（CSS 的 `backdrop-filter`
   不接受 SVG displacement，也不允许把背景二次采样）。
3. **不建议字面意义"全部"**：长会话正文、代码块、表格上铺玻璃会直接伤可读性与滚动性能。
   推荐**结构性玻璃**：外壳（侧栏/顶栏/输入区）+ 浮层（对话框/菜单/卡片）玻璃化，
   内容区保持实底。这既像 Apple 的 Liquid Glass 用法，也不碰性能红线。
4. 成本：一期（令牌 + 外壳 + 浮层 + 开关 + 降级）约 **3–5 人日**；
   二期（列表/卡片/设置全覆盖 + 主题双态）约 **1–2 周**；三期（性能调优 + 门禁）约 **3–5 人日**。
5. 原生 HAR（路线 C）只在"想给原生页做真折射演示"时才有价值，**对 Web 界面零收益**，不建议现在接。

---

## 1. 这个仓库到底是什么

来源：`Liu-gt/HarmonyOSLiquidGlass`（Apache-2.0，效果设计来自 Kyant 的 Compose 版本）。

| 项 | 事实（读源码得到） |
|---|---|
| 形态 | 根目录是 HAR 库工程（`backdrop/`），`demo/` 是独立 DevEco 工程 |
| 渲染 | `XComponent(SURFACE)` + EGL/GLES，独立渲染线程；文字用 `native_drawing` 栅格化 |
| 入口 | `GlassGLBindNode(id, FrameNode)` / `GlassGLSetScene(n)` / `GlassGLSetNumber/Bool(id,v)`（83 数值 + 8 开关） |
| 背景来源 | `GlassGLSetPhoto(RGBA)`（demo 带 14.5 MB `photo.rgba`）或 `GlassGLGetContentSurfaceId()` → ArkTS `BuilderNode(RENDER_TYPE_TEXTURE)` |
| 调度 | VSync 对齐：交互 120 fps、常规 60 fps、静止跳过重绘（`frames=0, idle≈60`） |
| 依赖 | HarmonyOS SDK `26.0.0`；需要签名与真机 |
| 规模 | 仓库 6.2 MB（tar.gz）；仅 `gles_renderer.cpp` 就 251 KB |

它是**一整套"玻璃场景"**（页签条、锁屏、控制中心、放大镜、渐进模糊……），
不是「`<Glass>` 包一层内容」的通用组件。

---

## 2. 为什么不能直接用在 Web UI 上

### 2.1 没有"网页 → 纹理"的通道

`BuilderNode(RENDER_TYPE_TEXTURE)` 的输入是 **ArkUI 组件树**。ArkWeb 是独立渲染管线：

- 没有公开 API 把 ArkWeb 的合成结果导出成 `OH_NativeImage` / 外部纹理；
- 即使强行截屏再上传纹理，也只能拿到**静态一帧**，滚动/输入/光标全丢，且每帧全屏回读，
  在 2in1 上就是灾难级开销。

所以「AR 式真折射 + 我们的真实网页内容」这条路，当前 HarmonyOS 上没有合法接口。

### 2.2 它没有"叠加层"语义

库的 API 是把**整块 Surface** 交给渲染线程；没有"只在某个矩形里画玻璃、其余给 ArkUI"的合成接口。
要把它塞进我们现在的布局（侧栏 + 顶栏 + WebView + 输入区），得改它的 C++ 渲染器：
自绘我们的布局、接管命中测试、还要和 WebView 抢 Z 序与输入法焦点。

### 2.3 收益/代价不匹配

- 引入：CMake/NAPI、第二个 EGL 上下文、约 250 KB+ 渲染器与 `libbackdrop.so`、API 26 设备限定；
- 得到：**原生页**的真折射；Web 页仍然什么都没有。
- 我们剩下的原生页很少（`Poc1`、诊断页），做"演示级"可以，做"产品级"不值。

---

## 3. 三条路线对比

| | A. Web CSS 玻璃（推荐） | B. 扩 ArkUI `systemMaterial` | C. 接原生 HAR |
|---|---|---|---|
| 覆盖 | **Web 界面全部** | 仅 ArkUI 外壳/弹窗/菜单 | 仅原生页（整屏场景） |
| 效果 | 近似液态玻璃：模糊/饱和/高光/噪点/光泽，**无真折射** | 系统真材质（含光感），组件级 | 真折射/色散/动态光照 |
| 成本 | 3–5 人日（一期） | 1–2 人日 | 1–2 周 + 原生维护 |
| 风险 | 上游 class 变动、性能、对比度 | 低（系统保证深浅色） | 高（GLES/输入/设备限定） |
| 三端 | 同一套 CSS，可分级降级 | 受设备材质能力影响 | 需 API 26 + GPU 条件 |

### 3.1 路线 A 能做到 / 做不到

**能做到（Chromium 系 ArkWeb 均支持）**

```css
/* 玻璃基元：模糊 + 饱和 + 提亮 + 半透明底色 */
backdrop-filter: blur(18px) saturate(180%) brightness(1.06);
background: linear-gradient(160deg, rgba(255,255,255,.62), rgba(255,255,255,.28));
box-shadow: inset 0 1px 0 rgba(255,255,255,.75),   /* 顶部高光 */
            inset 0 -1px 0 rgba(0,0,0,.06),        /* 底部暗边 */
            0 8px 32px rgba(0,0,0,.18);            /* 投影 */
border: 1px solid rgba(255,255,255,.35);
```

- 静态噪点：`background-image: url("data:image/svg+xml,…feTurbulence…")`（一次生成，几乎零成本）；
- 边缘光泽：`conic-gradient` + `mask` 做"玻璃倒角"的亮边；
- 圆角/阴影/分层：`border-radius` + `box-shadow` 多级；
- 深浅色：CSS 变量 + `prefers-color-scheme`（或我们自己的 `data-theme`）。

**做不到**

- 真折射（背景按法线位移）：`backdrop-filter` 只接受滤镜函数，不接受 `url(#displacement)`；
- 色散（RGB 分离）：同上；
- 逐像素"厚度"变化：CSS 没有背景二次采样通道。

> 换句话说：**Apple 视觉语言 ≈ 85% 可以复刻，光学真实感 ≈ 0%。**
> 但用户对"液态玻璃"的第一感知是**模糊 + 半透明 + 高光边缘 + 弹性动效**，这四项 CSS 都能给。

### 3.2 性能红线（必须在真机测，不许拍脑袋）

`backdrop-filter` 的代价 = 背景重采样面积 × 层数。经验值：

| 面积 | 单层代价 | 建议 |
|---|---|---|
| 侧栏 280×800 | 中 | 可常驻 |
| 顶栏 全宽×48 | 低 | 可常驻 |
| 输入区 全宽×120 | 低-中 | 可常驻 |
| 会话正文全区 | **高** | **禁止**（滚动时每帧重采样） |
| 对话框/菜单 | 低（偶发） | 可常驻 |

降级策略（一期就带）：
- `@supports not (backdrop-filter: blur(1px))` → 退回实色 + 边框（不清真）；
- 低内存/省电/手机小屏 → 只保留外壳玻璃，模糊半径降 18px→10px；
- 静态玻璃用 `will-change: backdrop-filter` 慎用（会常驻合成层，反而吃显存）；
- 滚动容器内**不加**玻璃层。

---

## 4. 我们项目现状（决定落地路径）

| 现状 | 位置 |
|---|---|
| ArkUI 已经有系统材质：菜单/弹窗/控制件 | `platform/src/main/ets/ui/ImmersiveMaterialKit.ets`、`WebApp.ets` 的 `MenuTitle.systemMaterial` |
| 模块级材质总闸已开（API 26 生效） | `entry/src/main/module.json5` 的 `ohos.arkui.UIMaterial.state = enable` |
| **Web 层有现成的注入通道** | `entry/src/main/ets/pages/WebApp.ets` 的 `SIDEBAR_SHIM_JS`（注入 `<style>` + 巡检 `<html>` 属性） |
| Web 是上游 React 客户端 | 核心树 `@deepseek-ai/dsh-client-ui-*`，class 名属上游资产 |

⇒ **A 路线不用动原生、不用改核心树**，只要在 `SIDEBAR_SHIM_JS` 旁加一段 `GLASS_SKIN_JS`
（或独立注入器），用低特异性选择器 + `data-dshm-glass` 开关生效即可。这一点很关键：
它把"改产品视觉"变成**一次前端注入**，可随时关掉、可灰度、可回退。

---

## 5. 若要做，建议的分期

### 一期（3–5 人日）「外壳 + 浮层」

- 设计令牌：`--dshm-glass-bg / --blur / --sat / --edge / --shadow`，深浅色两套；
- 玻璃面：侧栏、顶栏、输入区、对话框、右键菜单、Toast；
- 开关：设置里「界面材质：实色 / 玻璃」+ 环境变量兜底；
- 特性检测与降级：`CSS.supports` 探针写 `diag-glass`（真机可 grep）；
- 性能：滚动区零玻璃；模糊半径按设备档位。

### 二期（1–2 周）「组件级覆盖」

- 卡片、列表项 hover/active 态、按钮、页签、设置分区；
- 与主题系统对齐（明/暗/跟随系统），对比度检查；
- 上游 class 变动门禁：选择器清单 + `check-web-glass-skin.mjs`（缺一个选择器就红）。

### 三期（3–5 人日）「质感与动效」

- 边缘光泽、噪点、按下形变（`transform: scale(.98)` + 高光位移）；
- 开关弹层时的 spring 过渡（CSS `cubic-bezier` 近似，避免 JS 逐帧）；
- 帧率/内存回归：滚动 60 fps、静止零额外绘制。

> 不建议做：正文玻璃、每帧 JS 计算折射、WebGL 覆盖层（与 WebView 合成打架）。

---

## 6. 预览样张

本轮附了一个**自包含 HTML 样张**（无外部资源），复刻我们的外壳布局 + 玻璃令牌，
可现场切换「玻璃 / 实色」、拖动模糊与透明两个滑杆，并显示当前内核的
`CSS.supports('backdrop-filter', …)` 结果：

```
Download/com.dshm.dshclient/glass-mock.html
```

它只用于**看效果与量性能**，不是产品代码；样式变量可直接搬进 `GLASS_SKIN_JS`。

---

## 7. 建议的下一步

1. 你先在样张上确认视觉方向（外壳玻璃 vs 全量玻璃）；
2. 确认后我按一期落地：注入器 + 令牌 + 五个玻璃面 + 开关 + 降级探针 + 门禁；
3. 真机取三组数：滚动帧率、静止功耗、ArkWeb 内存增量，再决定是否进二期。

> 一句话：**这个仓库值得读，但不适合接进 Web；Web 玻璃化要自己做，且应该"少而准"。**

---

## 8. 一期已落地（2026-11-05，1010011 包）

按 §5 的一期范围实现，全部在 Web 注入层，**不动原生、不动核心树**：

| 项 | 落点 |
|---|---|
| 注入器 | `WebApp.ets` 的 `GLASS_SKIN_JS`，登记进 `pickerShimScripts`（排在侧栏垫片之后） |
| 令牌 | `--dshm-glass-blur / -sat / -bg / -edge / -shadow`，附深色媒体查询与 `html.dshm-phone` 降档（18px→12px） |
| 五个玻璃面 | `sidebar`（认 `.dshm-sbcol` 我们自己的钩子）、`topbar`（`header/[role=banner]`）、`composer`（textarea 向上找容器）、`dialog`（`[role=dialog]/[aria-modal]`）、`menu`（`[role=menu]/[role=listbox]`） |
| 开关 | `window.dshmGlass.set('on'|'off'|'auto')`，持久化 `localStorage['dshm.glass.mode']`，默认 `auto`（支持才开） |
| 降级探针 | `CSS.supports('backdrop-filter',…)`；不支持时 `@supports not` 退回实色，并把 `mode/support/dark/counts` 写 `files/diag-glass`（桥方法 `writeGlassDiag`） |
| 选择器门禁 | 新增 `tools/check-web-glass-skin.mjs`：五面齐全 + 真有 `mark()` + 括号配平 + 探针/降级/开关/桥两处登记；**5 个变异对照臂**全判红；已接进 CI |

**为什么不用官方类名**：Web 客户端是 CSS Modules 哈希类名（实测 `._dialog_o6lrb_33` 这种），
每次构建都变；所以只认**结构/角色 + 我们自己的 `data-dshm-glass-*` 钩子**。

**行为验证**：用桩 DOM 真跑注入脚本 —— 五个面全部打标、`diag-glass` 计数为 1、
`dshmGlass.set('off')` 立刻生效且 `effective=false`（见本轮执行记录）。

**玻璃验收**（当前口径，取代跨端五面标准）：

- entry 只验侧栏、对话框、菜单三个面；顶栏与输入区已撤回官方样式，不再要求五面计数。浮层未打开时对应计数为 0 正常。diag-glass 缺失或损坏仍判失败；有记录只证明诊断可读，不代表视觉效果已验证。
- phone 没有 GLASS_SKIN_JS，不引入 entry CSS。WebApp 在 aboutToAppear 经已有 writeDiagMarkerPublic 一次性写原生声明：module 为 phone，implemented:false、effective:false、reason:'phone-shell-no-glass-skin'、cssSupport:null。null 表示 CSS 未探测，不伪报支持或不支持；这不是玻璃渲染修复。
- tools/dshm-verify.mjs 按标准 haps/entry/files 或 haps/phone/files 路径识别模块；导出目录可凭完整 phone 原生声明识别。可靠判定为 phone 时玻璃项记 notapplicable，即使旧包没有声明也不计玻璃故障；未知目录且无可靠声明时记 unknown，不能假通过。entry 路径优先，不能用 phone 声明豁免 entry 缺诊断。
- 离线验证使用 tools/check-phone-glass-diagnostics.mjs --self-test，覆盖生产声明幂等性及 entry、phone、unknown、旧包无声明。设备效果、性能和渲染有效性需另行真机取证。

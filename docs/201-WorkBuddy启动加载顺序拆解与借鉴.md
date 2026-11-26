# 201 — WorkBuddy 启动加载顺序拆解与 DSHM 借鉴

> 调研对象：WorkBuddy Desktop 5.6.4（OpenHarmony / arm64，Electron 37.2.0 + Node 22.17.0 + Chromium 138.0.7204.45）
> 调研方式：静态解包（`app.asar` 头解析 + 定向提取）+ 运行时日志取证（4 份 `startup/*.jsonl` + 1 份 `.log`）
> 结论口径：**代码事实**与**运行时事实**分开标注；推断内容单独标注「推断」。
> 本文只做拆解与建议，不改代码。

---

## 0. 结论摘要

1. **WorkBuddy 的启动不是一个流程，而是六个可独立观测的阶段**（A 进程 / B 引导 / C 窗口 / D preload / E 渲染 / F daemon），共 66 个具名标记。每个标记都带 `id + phase + proc + pid + epochMs`，可跨进程还原成一条时间轴。这套埋点体系本身比任何单项优化都更值得借鉴。
2. **它把"用户感知的启动"和"系统真实就绪"彻底拆开了**。实测（warm）：窗口 297 ms 就带内容形状出现，React 挂载 2.4 s，骨架 3.0 s 拆除，daemon 4.2 s 才 ready。也就是说**用户在 0.3 s 就看到了"像应用"的东西**，而其后 4 秒是在"已经像应用的界面"里补齐数据。
3. **B（后端引导）与 C（窗口）是并行推进的，不是串行等待**。日志原文：`main window already created before bootstrap completion`。窗口从不等待数据库/迁移/daemon。
4. **首屏有三条"免等待快路径"**：主题快照（parse 期写 dataset，防闪白/闪黑）、账号快照（跳过 daemon `getAccount` 约 2.6 s）、启动种子（`wb-seed://` 同步注入会话元数据，且用一次性 token 做安全边界）。
5. **动画不是装饰，是被约束过的工程参数**：物理弹簧（`springMotion`）用于品牌淡入/呼吸；进度条明确**禁用**弹簧与指数曲线，改匀速 11.5 %/s + 0.3 %/s 慢爬 + 98 % 上限；全部动画都有 `prefers-reduced-motion` 降级。
6. **对 DSHM 最重要的差距不是"动画不够好看"，而是"启动期没有中间形态"与"启动期不可测量"**：DSHM 在 `BOOTING` 阶段根本不创建 `Web` 组件，用户看到的是纯 ArkUI 启动页，直到 Host 就绪才一次性切换到真实界面；同时缺少 WorkBuddy 那种分段标记与跨进程对齐，导致 8 秒究竟花在哪一段只能靠猜。

---

## 1. 调研方法与证据面

### 1.1 证据来源

| 编号 | 证据 | 路径 | 性质 |
|---|---|---|---|
| E1 | 主进程入口 | `app.asar → /package.json` 的 `main: main/ohos-main-bootstrap.cjs` | 代码事实 |
| E2 | 引导壳 | `/main/ohos-main-bootstrap.cjs`（705 B） | 代码事实 |
| E3 | 主进程主体 | `/main/index.js`（1.44 MB，rolldown 单行产物） | 代码事实 |
| E4 | 标记注册表 | `/main/marks.js`（`S` 表：A0–F19） | 代码事实 |
| E5 | Splash | `/main/splash/splash.html` + `splash-preload.js` | 代码事实 |
| E6 | 渲染入口 | `/renderer/index.html`（26 KB，含内联骨架与三条 IIFE） | 代码事实 |
| E7 | 骨架拆除协议 | `/renderer/skeleton/skeleton-bootstrap.js` | 代码事实 |
| E8 | 启动剖析器 | `app.asar.unpacked/cli/bin/startup-profile.cjs` | 代码事实 |
| E9 | 真实时序 | `~/.workbuddy/logs/startup/2026-11-22/*.jsonl`（4 份） | 运行时事实 |
| E10 | 阶段文本日志 | `~/.workbuddy/logs/startup/2026-11-22/43752-145706.log` | 运行时事实 |
| E11 | 启动剖析上报 | `~/.workbuddy/last-launch.json`（版本 + build + 时间戳） | 运行时事实 |

### 1.2 解包方法（可复现）

`app.asar` 结构：`uint32(4) + uint32(headerSize) + headerJSON + payload`。用 Node 直接读 header 即可枚举 14 840 个条目，再按 `offset` 定向提取单文件，无需完整解包 228 MB：

```js
const b = Buffer.alloc(16); fs.readSync(fd, b, 0, 16, 0);
const jsonSize = b.readUInt32LE(12);
const header = JSON.parse(fs.readFileSync(fd, { offset: 16, length: jsonSize }));
// 文件内容起点 = 16 + jsonSize，条目 offset 相对该起点
```

> 注意：标记为 `unpacked: true` 的条目（`cli/`、`preload/`、`native/`、`resources/`）内容在 `app.asar.unpacked/` 下，asar 内 `offset` 无意义，必须走 unpacked 路径。

---

## 2. 六阶段模型（A–F）

### 2.1 总览

| 阶段 | 名称 | 标记 | 主责进程 | 用户可见性 |
|---|---|---|---|---|
| A | `A_process` 进程 | A0–A9 | main | 不可见 |
| B | `B_bootstrap` 引导 | B1–B15 | main | 不可见（splash 盖住） |
| C | `C_window` 窗口 | C1–C8 | main | **从这里开始可见** |
| D | `D_preload` 预加载 | D1–D5 | preload | 窗口内空白 |
| E | `E_renderer` 渲染 | E1–E15 | renderer | 骨架屏 → 首内容 → 可交互 |
| F | `F_daemon` 守护 | F1–F19 | daemon | 数据逐步补齐 |

设计要点：**阶段不是按进程划分的，而是按"用户能看到什么"划分的**。B 与 C 在时间轴上交错（见 §4），但语义上分开——这让"窗口为何先出来"和"数据为何后到"可以分别度量、分别优化。

### 2.2 A 阶段：进程（0 → 92–353 ms）

| 标记 | key | 含义 | 实测 |
|---|---|---|---|
| A0 | `process_created` | 进程创建（`process.getCreationTime`） | — |
| A1 | `process_started` | 主 JS 开始执行（`globalThis.__workbuddyMainJsStartEpochMs`） | 0 ms（基准） |
| A2 | `imports_completed` | 全部顶层 import 完成 | 11 ms |
| A3 | `bundled_assets_root_set` | 资源根确定 + V8 CodeCache 打开 | 13 ms |
| A4 | `logger_configured` | electron-log 就绪 | 13 ms |
| A5 | `crash_writer_installed` | CPU/崩溃采样器挂载 | 13 ms |
| A6 | `shell_env_loaded` | 继承环境修复（mojibake / PATH） | 13 ms |
| A7 | `electron_app_configured` | 命令行开关、代理/TLS、GPU 降级决策 | 61 ms |
| A8 | `single_instance_locked` | 单实例锁 | 67 ms |
| A9 | `app_ready` | `app.whenReady()` 返回 | 92–353 ms |

关键代码（`/main/index.js`）：

- **引导壳零依赖**：`ohos-main-bootstrap.cjs` 只有 20 行——设 `process.env.WORKBUDDY_OHOS='1'`、`require('./index.js')`、`catch` 后 `process._rawDebug()` 打栈再抛。注释写明理由：*"HarmonyOS Electron shell can fail while evaluating the real main entry before the application's logger and crash handlers are installed."*
- **早于一切日志**：`_mainJsStartEpochMs` 在模块求值最开始就打点，后续所有相对时间都以它或进程创建时间为基准。
- **A3 同时做两件事**：设资源根 + 打开 V8 CodeCache（`enableMainCompileCache`）。实测 CodeCache 命中 24 个文件 / 1.26 MB。
- **A7 内含"上次崩溃"决策**：`applyGpuDegradationIfNeeded()` —— 上一次 GPU 进程崩溃过则本次直接禁用硬件加速，把"启动即崩"变成"慢但能起"。

### 2.3 B 阶段：引导（155 → 4 863 ms）

| 标记 | key | 含义 |
|---|---|---|
| B1 | `bootstrap_entered` | 进入 `bootstrapMainProcess` |
| B2 | `platform_created` | 平台层实例化 |
| B3 | `celljs_container_ready` | 依赖注入容器就绪 |
| B4 | `database_initialized` | DB 打开 |
| B5 | `migration_context_ready` | 迁移上下文（可向 splash 报进度） |
| B6 | `daemon_bridge_handlers_registered` | 主进程侧桥处理器注册 |
| B7 | `daemon_env_ready` | daemon 环境变量就绪 |
| B8 | `daemon_process_started` | daemon 进程已拉起 |
| B9 | `daemon_connection_created` | 与 daemon 的连接建立 |
| B10 | `renderer_migration_bridge_ready` | 渲染侧迁移桥就绪 |
| B11 | `daemon_event_bridges_registered` | daemon 事件桥注册 |
| B12 | `desktop_host_rpc_registered` | 桌面宿主 RPC 注册 |
| B13 | `wsrpc_ready` | WebSocket RPC 就绪 |
| B14 | `background_services_kicked` | 后台服务启动（不等待） |
| B15 | `bootstrap_complete` | 引导整体完成 |

实测：B1 155 ms → B15 4 328–4 651 ms，**约 4.2–4.5 s 全部花在这一段**，是启动的绝对主成本。

关键设计：

- **迁移进度可上报**：`e.update({ phase:'migrating', current, total })` → splash 真实百分比进度条。`migrating` 只在首次进入时清空 caption，避免文案闪回。
- **修复阶段独立**：迁移失败进入 `repairing`（backup / rebuild / recover 三个步骤），splash 切回 indeterminate 动画并显示当前步骤。
- **看门狗**：`createSplashProgressWatchdog({ idleMs: 60_000, absoluteMs: 300_000 })` —— 60 s 无进度或 5 min 总量即判定卡死，不让 splash 无限转。
- **B14 之后立刻 B15**：后台服务只"踢一脚"，不等结果。这是 p3 思想的早期体现。

### 2.4 C 阶段：窗口（238–711 ms 起）

| 标记 | key | 含义 | 实测（warm 样本） |
|---|---|---|---|
| C1 | `window_manager_created` | 窗口管理器实例化 | 238 ms |
| C2 | `splash_shown` | splash 首次显示 | 140 ms（早于 C1） |
| C3 | `vendor_ensured` | 随包运行时解压检查 | 155 ms（已解压则 3 ms） |
| C4 | `main_window_creating` | 开始建主窗 | 329 ms |
| C5 | `main_window_created` | 主窗对象创建完成 | 297–389 ms |
| C6 | `browser_window_load_url` | 发起 `loadURL` | 387 ms |
| C7 | `index_html_load` | 渲染进程完成导航（`did-finish-load`） | 2 336–3 209 ms |
| C8 | `startup_seed_primed` | 首屏种子数据就绪 | 604 ms（另有一次 37.5 s 的二次 prime） |

**C 阶段最重要的事实**：C5（297–389 ms）远早于 B15（4 328 ms）。窗口在引导完成前就已创建并显示。日志原文（E10）：

```
[+4882ms] Event: renderer:ready received
[+4892ms] Phase: migrationDonePromise resolved
[+4893ms] Phase: main window already created before bootstrap completion
```

也就是说：**bootstrap 是"数据面"，窗口是"呈现面"，两者从一开始就并行**。

窗口创建时的 URL 注入（`buildInitialRendererQuery`）只放三样东西：

```js
{
  locale,
  wbSeedToken: ensureSeedToken(),        // 16 字节随机 hex，单次启动内复用
  accountSnapshot: encodeAccountSnapshotForQuery(snapshot)  // 可选
}
```

注意：**不放凭据、不放 token**。真正的会话凭据在 preload/RPC 层，页面 URL 只携带"首屏快路径"所需的非敏感数据 + 一个用于校验 seed 请求的随机串。

### 2.5 D 阶段：preload（711–858 ms）

| 标记 | key | 含义 |
|---|---|---|
| D1 | `preload_start` | preload 脚本开始执行 |
| D2 | `preload_bootstrap_requested` | 向主进程请求引导数据 |
| D3 | `preload_bootstrap_resolved` | 引导数据返回 |
| D4 | `preload_rpc_connected` | RPC 通道连接 |
| D5 | `preload_exposed` | `contextBridge` 暴露完成 |

实测：D1 711 ms → D5 732 ms，**21 ms 内完成**，而 D3（`bootstrap_resolved`）出现在 4 628 ms——即 **preload 先把 API 暴露出去（不等数据），数据后到再 resolve**。这是"桥先通、数据后补"的典型手法，避免渲染进程因等数据而无法开始解析 HTML。

### 2.6 E 阶段：渲染（2 336 → 2 988 ms）

| 标记 | key | 含义 | 实测 |
|---|---|---|---|
| E1 | `renderer_nav_start` | 导航开始 | —（缺 epochMs，见 §7.2） |
| E2 | `renderer_response_end` | 响应结束 | — |
| E3 | `renderer_dom_interactive` | DOM interactive | — |
| E4 | `renderer_web_first_paint` | Web 首次绘制 | — |
| E5 | `renderer_dom_content_loaded` | DOMContentLoaded | — |
| E6 | `renderer_script_start` | 主 bundle 开始执行 | 2 547 ms |
| E7 | `renderer_dom_ready` | DOM ready | 2 336 ms |
| E8 | `renderer_react_mounted` | React 挂载完成 | 2 425 ms |
| E9 | `renderer_adapter_init_start` | 数据适配器初始化 | 2 697 ms |
| E10 | `renderer_first_paint` | 首帧绘制 | 3 144 ms |
| E11 | `renderer_web_first_contentful_paint` | FCP | — |
| E12 | `renderer_adapter_connected` | 适配器连接 | 530 091 ms（异常样本） |
| E13 | `renderer_skeleton_gone` | **骨架屏拆除** | 2 988 ms |
| E15 | `renderer_first_content_paint` | 首个真实内容绘制 | 3 036 ms |
| E14 | `renderer_app_ready` | 应用可交互 | 530 100 ms（异常样本） |

**E 阶段的核心不是"快"，而是"有东西可看"**：DOM ready 2.3 s、React 挂载 2.4 s、骨架 3.0 s 拆除、首内容 3.0 s。骨架在 React 挂载后 563 ms 才拆，这 563 ms 就是"用真实内容替换骨架"的窗口——用户不会看到空白。

### 2.7 F 阶段：daemon（1 857 → 4 216 ms）

| 标记 | key | 含义 | 实测 |
|---|---|---|---|
| F1 | `daemon_started` | daemon 进程启动 | 1 857 ms |
| F2 | `daemon_db_ready` | daemon DB 就绪 | 2 055 ms |
| F3 | `daemon_celljs_deps_resolved` | 依赖解析 | 2 130 ms |
| F4 | `daemon_tencent_docs_ready` | 文档引擎就绪 | 2 135 ms |
| F5 | `daemon_migration_service_ready` | 迁移服务 | 2 136 ms |
| F6 | `daemon_sidecar_manager_ready` | sidecar 管理 | 2 155 ms |
| F7 | `daemon_rpc_ready` | RPC 就绪 | 2 156 ms |
| F8 | `daemon_domain_ready` | 领域服务 | 4 402 ms |
| F9 | `daemon_ready` | daemon 整体就绪 | 4 216–4 519 ms |
| F10–F19 | 迁移完成 / MCP 宿主 / 服务启动 / 背景完成 / 状态刷新 / 鉴权 / 配置 / 最终状态 | 4 777–4 944 ms |

关键：**F 与 E 并行**。渲染进程 2.4 s 已挂载，daemon 4.2 s 才 ready。中间 1.8 s 由渲染层的"本地态 + 骨架"承担。这正是"用户感知启动"能被压到 3 s 而真实就绪 4.9 s 的原因。

---

## 3. 十一个可借鉴设计模式

### P1｜零依赖引导壳（fail-visible bootstrap）

**问题**：应用真正入口一旦抛异常，日志系统尚未初始化，异常静默丢失，表现为"点了没反应"。

**做法**：`ohos-main-bootstrap.cjs` 不引用任何模块、不初始化日志、不读配置，只做三件事——打环境标记、`require` 真入口、`catch` 后用 `process._rawDebug` 直接写 stderr 再 `throw`。

**证据**：E2（705 B）。

**DSHM 对应**：`EntryAbility.onCreate` 首行已有"静态配置必须先于任何 Web 组件"的纪律，但缺一个"最早期失败也要可见"的兜底。ArkTS 侧对应物是 `AppAbilityStage.onCreate` + `hilog.error`（W 级，端侧可见）。建议在 `EntryAbility.onCreate` 最前 3 行内完成一次 `hilog.warn('DSHM-TRACE onCreate enter')`，并在 `onWindowStageCreate` 失败分支保证至少一条 W 级日志。

---

### P2｜分段标记 + 跨进程时钟对齐

**问题**：启动慢，但不知道慢在哪一段；主进程、渲染进程、daemon 各有各的时钟，无法拼成一条时间轴。

**做法**：

1. 66 个具名标记，每个带 `id/phase/key`，`phase` 归入 A–F 六个桶。
2. 每条记录同时写 `timestamp`（`performance.now()`，相对本进程）与 `epochMs`（`Date.now()`，绝对）。
3. 汇总时按 `source` 分组求 `epochMs - timestamp` 的中位数，得到每个进程的"时钟偏移"，再统一换算成绝对时间（`computeClockOffsets` / `markAbsEpoch` / `computeEndToEndMs`）。
4. 输出 `summary`：`totalMs`、`firstInteractiveMs`（E14 相对最早标记）、`phases`、`flowType`。
5. 日志落地为 JSONL（一行一标记），另有 `.log` 文本版给人读。

**证据**：E4（`marks.js` 的 `S` 表）、E8（`startup-profile.cjs` 的 recorder）、E9/E10。

**DSHM 对应**：目前只有零散 `DSHM-TRACE` 文本日志，没有结构、没有阶段、没有跨进程对齐。**这是投入产出比最高的一条**——先有度量，再谈优化。

---

### P3｜Splash 编排器（三态 + 最短展示 + 崩溃守卫）

**问题**：splash 容易变成"无限转圈"或"一闪而过"，两者都比没有更糟。

**做法**（`SplashOrchestrator`）：

| 机制 | 参数 | 目的 |
|---|---|---|
| 三态机 | `initializing` / `migrating` / `repairing` | 有真实进度时给真进度，没有时给 indeterminate |
| 最短展示 | `SPLASH_MIN_DISPLAY_MS = 3000`，**仅 repairing 阶段生效** | 修复类文案要看得清；普通初始化不拖 |
| 空闲看门狗 | `idleMs = 60 s` | 60 s 无新进度 → 判卡死 |
| 绝对看门狗 | `absoluteMs = 300 s` | 5 min 兜底 |
| 崩溃守卫 | `.splash-crash-guard` 记数；≥1 次默认跳过；`bypassCrashGuard` 时 ≥3 次仍拒绝 | 防"splash 自身崩 → 无限重启循环" |
| 进度合并 | `update()` 浅合并，`phase` 从非 migrating 进入 migrating 时删旧 caption | 防文案闪回 |

**证据**：E3 中 `SplashOrchestrator=class` 段；E5。

**DSHM 对应**：启动页已有，但**没有三态、没有看门狗、没有崩溃守卫**。DSHM 已有 `autoRetry` 与 `fail()`，可在此基础上加"卡死判定"。

> 注意：**3 s 最短展示不能照搬**（见 §7.1）。

---

### P4｜HTML 内联骨架屏 + 拆除协议

**问题**：Electron 的 `index.html` 从 parse 到 React 挂载有 1–2 s 的空白窗口。

**做法**：

1. 骨架 DOM **直接写在 `index.html` 的 `<body>` 首部**，<style> 内联在 `<head>`。HTML 一 parse 就能画，不等任何 JS。
2. 骨架**按真实 UI 布局排**：`titlebar 38px + sidebar 220px + content + statusbar 22px`，占位块数量与真实导航项一一对应（5 个导航项、4 条会话、2 个分组）。
3. 视觉用 `--sk-*` CSS 变量 + shimmer 扫光（1.5 s，`ease-in-out`，`background-position -200% → 200%`）。
4. 每种窗口有**独立骨架**：`settings` / `conversation` / `im-merge-detail` / `global-search` / `developer-profile` / `office`——避免"把小窗塞进主窗三栏骨架"的畸形。
5. 拆除协议 `window.__removeSkeleton({animate})`：
   - 先把 `-webkit-app-region` 从 `drag` 改成 `no-drag`（否则 macOS 上重算窗口区域会异常）；
   - `animate` 时加 `.sk-fade-out`（`opacity 50ms ease-out`），`transitionend` 移除 + 200 ms `setTimeout` 兜底；
   - 非 animate 时 `display:none` → `requestAnimationFrame` → `remove()`。
6. 主窗额外挂 `startup:message` IPC：`startup:error` → 显示失败覆盖层 + 重试按钮（`app:restart`）；`startup:reconnecting` → 显示"第 N 次连接"；`startup:connected` → 隐藏覆盖层；**25 s 无消息**主动显示失败覆盖层。
7. `splashState` query 注入颜色与版式变量（`--sk-bg/--sk-titlebar-bg/--sk-sidebar-w/...`），让 splash → 骨架 → 真实界面**三跳颜色一致**。
8. 全部动画带 `@media (prefers-reduced-motion: reduce)` 关闭。

**证据**：E6（`index.html` 注释极详尽）、E7（`skeleton-bootstrap.js`）。

**DSHM 对应**：**完全缺失**。DSHM 在 `WebPhase.BOOTING` 时不创建 `Web` 组件（`if (this.phase !== WebPhase.BOOTING) Web(...)`），所以 Web 侧任何骨架都无从显示。这是最值得改的一处。

---

### P5｜三段式主进程编排（p1 / p2 / p3）

**问题**：启动链一旦写成线性 `await`，任何一步慢都会拖住窗口。

**做法**（`onReady()` 的显式分层）：

| 段 | 内容 | 是否阻塞首屏 |
|---|---|---|
| **p1 前奏** | 菜单（仅 darwin）、`armStallWatchdog()`、**splash 立刻显示**、vendor 资源按需解压 | 是（但很快，155 ms） |
| **p2 引导** | `bootstrapMainProcess`（DB/迁移/daemon）、迁移进度推 splash、`awaitMigrationDone`、关 splash、`ensureMainWindowIfNeeded` | 是（4.2 s，但 splash 盖住） |
| **p3 杂务** | 排空深链、清理陈旧文件、flush 遥测、日志 ACL、剪贴板 watcher、DevTools 扩展、后台清理、Win/Mac 分享目标注册 | **否**（全部 fire-and-forget） |

命名带 `_p1/_p2/_p3` 前缀，代码里一眼能看出"这段是不是关键路径"。

**证据**：E3 中 `onReady()` 与 `_p1UiPrelude/_p1EnsureVendorAssets/_p2Bootstrap/_p2AwaitMigrationAndCloseSplash/_p3*`。

**DSHM 对应**：`EntryAbility` 已有"首帧后再起宿主"的正确分流，但**没有显式分层命名**，且 `onCreate` 里仍有若干同步段（目录授权恢复、speech bridge、restart watcher、card watcher、tray）与首帧竞争。建议按 p1/p2/p3 重新归位，并把 p3 项移到 `onWindowStageCreate` 回调之后或 `setTimeout(0)`。

---

### P6｜首屏三条免等待快路径

| 快路径 | 机制 | 省下的时间 |
|---|---|---|
| **主题快照** | `index.html` 内联 IIFE，parse 期读 `?windowTheme`/`?colorScheme`，写 `html.dataset.theme` + `class` + `colorScheme` | 消除"骨架浅色 → 真实深色"闪一帧 |
| **账号快照** | 主进程 `?accountSnapshot=<encoded>` 注入上次登录快照；页面 IIFE 解出挂 `window.__initialAccount`，React 顶部同步 `setAccount()` | 跳过等 daemon `getAccount`，注释写明 **≈2.6 s** |
| **启动种子** | `?wbSeedToken=<32 hex>`；页面 IIFE 用 `document.write` **同步**注入 `wb-seed://seed/<token>/startup-seed.js`；自定义协议 handler 校验 token 才应答 | 会话列表首屏不等 RPC |

**安全边界（重要）**：seed 脚本是 parser-blocking 的 classic script，且**必须带 token**。原因写在注释里：`wb-seed:` 在主窗 CSP `script-src` 内，sandboxed `srcdoc` iframe（AI 产物预览）会继承该 CSP；不带 token 时它们可拉 seed（uid + 会话元数据）外发。opaque origin 读不到父页 URL query，因此无法构造合法请求。

**证据**：E6 三段内联 IIFE 的注释；E3 中 `ensureSeedToken` / `primeStartupSeedCache` / `buildInitialRendererQuery`。

**DSHM 对应**：

- 主题：DSHM 已有 `splashDark = systemAppearance()==='dark'` 且启动视图用 `start_window_background` 资源（base `#FFFFFF` / dark `#151517`），方向正确，但**Web 侧首帧主题**没有快照注入，仍可能"启动页深 → Web 首帧白 → 主题上报后深"。
- 账号/会话快照：DSHM 有 `HostStore` / `RememberedHost`，可做"上次 URL + 上次会话标题"的只读快照。
- **安全对照**：DSHM 目前把 token 直接拼进 URL（`AppStorage KEY_HOST_LAUNCH_URL = ${baseUrl}/?token=${token}`），而 WorkBuddy 明确让页面 URL **不携带凭据**。这是可以直接对齐的安全改进。

---

### P7｜窗口不等引导（B/C 并行）

**问题**：直觉写法是"先 bootstrap 完，再建窗口"，用户要盯着 splash 4 秒。

**做法**：`_p2Bootstrap` 内部 `onWindowManagerReady` 回调里，`bootstrapMainProcess` 一交出 `windowManager` 就建主窗；`_p2EnsureMainWindowIfNeeded` 只是兜底（"如果还没建就建"）。日志因此出现 "main window already created before bootstrap completion"。

**证据**：E10 的 `+4893ms` 行；E9 时序表中 C5(389) ≪ B15(4651)。

**DSHM 对应**：DSHM 是"Host 就绪 → 发布 `KEY_HOST_LAUNCH_URL` → Web 才创建"。**结构上就是串行的**。这是感知启动 8 s 的根因之一。

> 适配时注意：DSHM 不能真"并行"（ArkTS 单线程 + Node 子进程），可行解是"**先给壳内骨架 + 占位 URL，数据后补**"，而不是"Web 等 Host"。

---

### P8｜编译缓存与预读（CodeCache + prewarm）

| 手段 | 参数 | 效果 |
|---|---|---|
| V8 CodeCache | `enableMainCompileCache`，按 `appVersion + v8Version` 分目录 | 实测 24 文件 / 1.26 MB，A3 阶段 1 ms 完成 |
| 主进程分块预热 | `PREWARM_BUDGET_BYTES = 128 MB`，单文件上限 32 MB，跳过 `worker` 与 `.map` | `app.whenReady` 后异步 `readFile` 填 OS page cache，不解析 |
| lazy chunk 预读 | `preload-lazy-chunks.cjs`：优先读 `manifest.json.lazy_files`，并发 `readFile` 填 page cache，再按扩展名 `require`/`import` | 单块失败不阻塞；目录缺失静默 no-op |

**证据**：E3（`prewarmMainChunks`、`PREWARM_*` 常量、`enableMainCompileCache`）、E2 目录下 `preload-lazy-chunks.cjs`。

**DSHM 对应**：`NodeRuntime` 是 V8（Node 22），理论上可用 `--cache` 或 `NODE_COMPILE_CACHE`。**需实测**（见 §6 B1）。

---

### P9｜启动类型分流 + 退化策略

| 机制 | 实现 | 作用 |
|---|---|---|
| 启动类型 | `resolveStartupType()` + `last-launch.json`（version/build/timestamp）+ `markWarmActivation()` | 区分 cold / warm / reload，summary 里带 `startupType` |
| GPU 降级 | `applyGpuDegradationIfNeeded()`：上次 GPU 崩溃 → 本次禁用硬件加速 | 把"必崩"变"慢但能起" |
| ffmpeg 守卫 | 文件缺失/损坏 → `showErrorBox` + `quit`，并给出可操作文案（加信任区 / 重装） | 失败可解释 |
| 崩溃守卫 | splash 崩溃计数（§P3） | 防重启循环 |
| 退出抑制 | `BootstrapQuitGuard`：`stage=pending` 时抑制退出；`armStallWatchdog()` 超时强制 `stage=failed` 恢复语义 | 防止"引导未完就退出"导致下次启动全量重来 |

**证据**：E3（`startup_type_exports`、`BootstrapQuitGuard`、`applyGpuDegradationIfNeeded`）、E11。

**DSHM 对应**：`DshHost` 有 8 态状态机（UNWIRED/EMPTY/EXTRACTING/IDLE/STARTING/READY/DEGRADED/FAILED），比 WorkBuddy 更细；但**没有启动类型概念**（每次都是同一套动画 + 同一套流程），也**没有"上次异常 → 本次降级"的记忆**。

---

### P10｜动画参数化（弹簧 / 匀速 / 降级）

WorkBuddy 侧：

- splash 进度条：`indeterminate` 用 `translateX(-100%) → 333%`，1.4 s 线性无限。
- 真实进度：`width` + `transition: width 0.3s ease`。
- 骨架 shimmer：1.5 s，`ease-in-out`，无限。
- 骨架呼吸：`opacity 0.55 ↔ 1`，1.2 s `alternate`。
- Office 冷启：进度条 `width 0 → 85%`，2.4 s `ease-out`，**不谎报 100%**。
- 全部带 `prefers-reduced-motion` 降级。

DSHM 侧（`WebApp.ets`）已做得更细，且有明确的用户反馈驱动：

- 品牌淡入：`curves.springMotion(0.42, 0.86)` + `delay 80 ms`（物理弹簧，略欠阻尼）。
- 品牌呼吸：`springMotion(0.62, 0.62)` + `iterations:-1` + `PlayMode.Alternate` + `delay 720 ms`。
- 进度条：**明确禁用弹簧、禁用指数**。匀速 `11.5 %/s` → 92 %，之后 `0.3 %/s` 慢爬，上限 98 %；`40 ms`（25 fps）节拍；**不取整**（`Math.floor` 会造成"卡住再跳"）。
- 就绪收尾：`380 ms` `ease-out cubic` 补到 100 %，而不是直接赋值。

**结论**：动画这一块 DSHM **不需要借鉴 WorkBuddy，反而更成熟**。唯一可补的是"`prefers-reduced-motion` 等价能力"——ArkUI 无该媒体查询，可读系统"减弱动效"开关（若有）或提供应用内开关。

---

### P11｜启动剖析器可按需开关

`startup-profile.cjs` 只在 `CODEBUDDY_STARTUP_PROFILE=1` 或 `--startup-prof[-md]` 时启用；支持 `--startup-prof-dir` / `--startup-prof-name`，并对文件名做 Windows 可移植性校验（拒绝 `<>:"/\|?*`、结尾点/空格、`con/prn/aux/...` 保留名）。默认零开销。

**DSHM 对应**：可作为"启动埋点默认关闭、`hdc shell aa start --ps dshStartupProf 1` 时开启"的设计参考。

---

## 4. 真实时序数据

### 4.1 warm 样本（`52220-004453.jsonl`，最完整）

| 相对 ms | 进程 | 标记 | 含义 |
|---:|---|---|---|
| 0 | main | A1 | 主 JS 开始 |
| 92 | main | A9 | app ready |
| 238 | main | C1 | 窗口管理器就绪 |
| 297 | main | C5 | **主窗创建完成** |
| 711 | preload | D1 | preload 开始 |
| 732 | preload | D5 | **API 暴露完成** |
| 2 336 | renderer | E7 | DOM ready |
| 2 382 | main | C7 | 页面导航完成 |
| 2 425 | renderer | E8 | **React 挂载** |
| 2 988 | renderer | E13 | **骨架拆除** |
| 4 216 | daemon | F9 | daemon ready |
| 4 328 | main | B15 | 引导完成 |

### 4.2 冷 / 慢样本（`43752-145706`，阶段文本日志）

| 相对 ms | 事件 |
|---:|---|
| 7 | 进程启动（`appspawn` 参数含 `--no-zygote`、`--user-data-dir`） |
| 12 | CodeCache enabled（1 ms） |
| 61 | `configureElectronApp` 完成 |
| 67 | 单实例锁 / preflight `platform-skip` |
| 101 | `app.whenReady` |
| 110 | PAC prewarm **异步发起** |
| 140 | splash 崩溃守卫：`crashCount=0, skipSplash=false` |
| 152–155 | vendor 检查 + `ensureAll`（3 ms，已解压）+ mcp.json 迁移 |
| 155 | 进入 `bootstrapMainProcess` |
| 531 | PAC prewarm 完成（404 ms，**不阻塞**） |
| 611 | CodeCache 磁盘状态（24 文件 / 1.26 MB） |
| **4 863** | **bootstrap 完成** |
| 4 882 | `renderer:ready`（**早于 bootstrap 完成**） |
| 4 893 | 迁移完成 / 主窗早已创建 / STARTUP COMPLETE |

### 4.3 三次样本的关键节点对比

| 样本 | A9 | C5 | C7 | E13 | B15 |
|---|---:|---:|---:|---:|---:|
| 15214 | 353 | 834 | 3 209 | — | — |
| 19999 | 182 | 427 | 2 558 | — | — |
| 52220 | 92 | 297 | 2 382 | 2 988 | 4 328 |

**读法**：A9 波动 92–353 ms（进程冷热差异），C5 波动 297–834 ms，C7（页面导航完成）波动 2.4–3.2 s。**主导成本在 C7 之前的 bundle 解析与 B 阶段的 bootstrap**，而不是进程创建。

### 4.4 两个必须说明的数据异常

1. **`E12/E14 = 530 091 / 530 100 ms`**：该样本中适配器连接发生在 8.8 分钟后。这是异常会话（可能长时间挂起后恢复），**不能当作"启动要 8 分钟"**。按同文件其他标记推断，正常应在 3–5 s 区间（标注：推断）。
2. **`summary.totalMarks = 13, phases = {}`**：summary 在流早期就被 flush，未包含后续标记。这是**WorkBuddy 自身的埋点缺陷**——`flush()` 有 `summaryWritten` 幂等锁，但调用时机过早。**借鉴时不要照抄**：DSHM 应在 `E13/E14` 或进程退出时写 summary。
3. **`E1/E2/E3/E5/E11` 缺 `epochMs`**：renderer 早期标记只有 `timestamp`，导致跨进程对齐时算出 `NaN`（本次分析脚本的输出即为证）。**借鉴时要强制所有标记双时间戳**。
4. **`C8 startup_seed_primed` 出现两次**（604 ms 与 37 541 ms）：说明 seed prime 会被二次触发，缺少幂等保护。

---

## 5. DSHM 现状对照

### 5.1 已具备（且部分优于 WorkBuddy）

| 能力 | 位置 | 评价 |
|---|---|---|
| 首帧后再起宿主 | `EntryAbility.ets` `HOST_START_DELAY_AFTER_FIRST_FRAME_MS = 32` | 方向正确，注释记录了 AGC 9 039 ms → 目标 4 000 ms 的背景 |
| 启动页状态机 | `WebApp.ets` `WebPhase.BOOTING/LOADING/READY/ERROR` | 比 splash 三态更贴合壳层 |
| 防闪规则 | `everReady`：只有"从未就绪"才把启动页盖在 LOADING 上 | 避免应用内整页导航闪启动页 |
| 进度条曲线 | 匀速 11.5 %/s + 慢爬 + 98 % 上限 + 380 ms 收尾 | **优于** WorkBuddy 的指数/线性混合 |
| 品牌动效 | `springMotion` 物理弹簧双段 | **优于** WorkBuddy 的 CSS 过渡 |
| 白屏自愈 | `AUTO_RETRY_MAX` + 保持启动页不展示错误页 | 已覆盖"首启解包 6–7 s 后 404" |
| 失败可读 | `KEY_HOST_BOOT_ERROR` + ERROR 覆盖层 | 已有 |
| 宿主状态机 | `DshHost` 8 态（含 `EXTRACTING`/`DEGRADED`） | 比 WorkBuddy 更细 |
| 三端隔离 | `entry` / `phone` / `hostruntime` 分模块 | 架构上优于单 asar 单入口 |

### 5.2 缺口（按影响排序）

| # | 缺口 | 影响的用户感受 | 证据 |
|---|---|---|---|
| G1 | **启动期无中间形态**：`BOOTING` 不创建 `Web`，只有 ArkUI 启动页 | 0–8 s 是"一个 logo + 进度条"，没有信息密度；就绪瞬间整屏切换，观感突变 | `WebApp.ets:7886` `if (this.phase !== WebPhase.BOOTING) Web(...)` |
| G2 | **启动不可分段度量**：只有文本 `DSHM-TRACE`，无阶段、无跨进程对齐、无 summary | 8 s 花在哪只能猜；优化无法验收 | 全仓无标记表实现 |
| G3 | **无启动类型分流**：每次都是同一套动画与流程 | 热启动也要看完整启动动画；上次异常也无降级 | `WebApp.ets` 无 cold/warm 分支 |
| G4 | **凭据在 URL 上**：`?token=xxx` 直接进页面 URL | 页面内脚本/日志/崩溃上报都可能带出 token | `EntryAbility.ets:2959` |
| G5 | **无首屏数据快路径**：会话列表/上次 URL 没有快照 | 就绪后仍要等一次 RPC 才有内容 | 无 snapshot 机制 |
| G6 | **无看门狗/崩溃守卫**：启动卡死只能靠用户杀进程 | 卡死时表现为"永远停在启动页" | 无 idle/absolute watchdog |
| G7 | **p1/p2/p3 未显式分层**：`onCreate` 仍有同步重活 | 首帧与同步段竞争 ArkTS 线程 | `EntryAbility.ets` onCreate 段 |

---

## 6. 借鉴清单

### A 档：直接可做（低风险、高收益）

#### A1｜建立 DSHM 启动分段标记（先度量）

- **落点**：新增 `platform/src/main/ets/diagnostics/StartupMarks.ets`（三端共享），在 `EntryAbility`、`WebApp`、`DshHost`、`NodeRuntime` 埋点。
- **阶段划分**（对齐 A–F，但按鸿蒙实际命名）：

| 段 | 标记 |
|---|---|
| S0 | `S0_process`：`onCreate` 入口 |
| S1 | `S1_ability`：静态配置完成 / 启动参数发布完成 |
| S2 | `S2_window_stage`：`onWindowStageCreate` 进入 / `loadContent` 回调到达 |
| S3 | `S3_first_frame`：首帧（`onPageShow` 或首帧回调） |
| S4 | `S4_host_start`：`installBundled` 开始 / 结束 |
| S5 | `S5_host_ready`：`host.start()` resolve、`KEY_HOST_URL` 发布 |
| S6 | `S6_web_load`：`onPageBegin` / `onPageEnd` / 首内容 |
| S7 | `S7_ready`：`WebPhase.READY` |

- **强制字段**：`id / phase / proc(arkts|node) / pid / timestamp / epochMs / bootId`。**不接受只有单一时间戳的标记**（吸取 WorkBuddy 的 E1/E2 教训）。
- **落地**：JSONL 追加写 `<filesDir>/dsh/logs/startup/<yyyy-mm-dd>/<pid>-<hhmmss>.jsonl`，同时保留一条 `hilog.warn` 便于 `hdc` 直读。
- **summary 时机**：只在 `S7_ready` 或 `Host` 退出时写，且带 `written` 幂等锁。**不要在流早期 flush**（吸取 §4.4 教训）。
- **验收**：一次冷启动能在单文件里还原 S0→S7 时间轴，误差 ≤ 5 ms。

#### A2｜壳内骨架屏（解决 G1）

- **落点**：`entry/src/main/ets/pages/WebApp.ets` 的 `build()`；`phone` 壳单独一份。
- **做法**：
  1. 把 `if (this.phase !== WebPhase.BOOTING) Web(...)` 改为**始终创建 `Web`**，`BOOTING` 阶段用一个"本地占位页"（`about:blank` 或 `loadData` 内联 HTML）满足组件初始化，避免首帧后二次创建带来的白块。
  2. 在 `Web` 之上叠一层 ArkUI 骨架（`Stack` + `Column/Row` 占位块），布局与真实首屏对齐：PC/平板 `顶栏 + 左栏 + 内容区`，手机 `顶栏 + 内容区`。
  3. 骨架用 `@State skeletonOpacity` + `animateTo` 做 200 ms 淡出；`READY` 且首内容已绘制后移除。
  4. **不要**在骨架里放品牌 logo —— 品牌动效留给启动页，骨架只表达"结构已就位"。
- **动效参数**：占位块 `opacity 0.55 ↔ 1`，1.2 s，`PlayMode.Alternate`，与 WorkBuddy 骨架呼吸一致；骨架整体淡出 200 ms。
- **验收**：`S3_first_frame` 之后 100 ms 内屏幕上有结构（非纯色）；`READY` 时骨架淡出，全程无纯白/纯黑帧。

> 若 A2 成本过高，退一步：至少把启动页从"logo + 进度条"升级为"logo + 进度条 + 结构占位（左栏 4 条 / 内容区 1 个大块）"，改动只在 `WebApp.ets` 一个文件内。

#### A3｜启动页最短展示与防闪烁（替代 3 s 硬等）

- **做法**：不引入 WorkBuddy 的 3 s 最短展示，改为**双向阈值**：
  - 启动页已显示 `< 200 ms` 且已 `READY` → 延迟到 200 ms 再淡出（防"闪一下"）。
  - 启动页已显示 `> 200 ms` → 立即淡出，不额外等待。
- **落点**：`WebApp.ets` 的 `onPageEnd` → `finishProgress()` 之后。
- **验收**：热启动不再出现"启动页一闪"；AGC 启动指标不因等待而增加。

#### A4｜卡死看门狗 + 崩溃守卫（解决 G6）

- **落点**：`EntryAbility.ets`（宿主侧）+ `WebApp.ets`（渲染侧）。
- **做法**：
  - 宿主：`host.start()` 后启动 `idle 60 s / absolute 300 s` 看门狗，超时写 `KEY_HOST_BOOT_ERROR` 并置 `WebPhase.ERROR`（复用现有错误覆盖层，不新增 UI）。
  - 渲染：`onPageBegin` 后若 `25 s` 内既无 `onPageEnd` 也无 `onErrorReceive`，主动走 `fail()`。
  - 崩溃守卫：在 `filesDir` 写 `.startup-crash-guard` 计数；连续 `>= 2` 次异常退出则**跳过品牌动画**（直接进骨架/启动页静态态），避免"动画还没播完就崩"的循环观感。
- **验收**：人为制造 Host 不 ready，25 s 内出现可读错误；连续两次异常后第三次启动无品牌动画。

#### A5｜凭据与首屏数据分离（解决 G4，安全）

- **落点**：`EntryAbility.ets:2959` 附近（`KEY_HOST_LAUNCH_URL` 构造）。
- **做法**：
  1. 页面 URL 改为**不带 token**：`${baseUrl}/?launchSeed=<32 hex>`。
  2. token 经既有 AppStorage 通道（`KEY_HOST_TOKEN`）下发，由 `WebApp` 在 `onPageEnd` 后通过桥注入，或由 Host 侧以 HttpOnly Cookie 形式建立会话。
  3. `launchSeed` 仅用于校验"首屏快照请求"，一次性、启动期内有效、与 token 无关联。
- **注意**：这是**行为变更**，需按项目规范先出方案等确认（涉及会话建立方式）。
- **验收**：`hdc shell` 抓到的页面 URL 中不含任何长期凭据；刷新页面仍能恢复会话。

#### A6｜首屏快照（解决 G5）

- **落点**：`platform`（存储）+ `hostruntime`（写入）+ `WebApp`（读取注入）。
- **做法**：Host `READY` 时写 `last-screen.json`：`{ url, title, sessionCount, updatedAt }`（**不含消息正文、不含凭据**）。下次启动 `LOADING` 阶段把它通过 query 或 `runJavaScript` 注入，Web 首屏先渲染"上次的壳"，再由 RPC 校正。
- **验收**：冷启动 `READY` 后首屏有内容的时间 < 300 ms（不含数据校正）。

### B 档：需要适配（中风险，需实测）

#### B1｜Node 侧编译缓存与预读

- **落点**：`hostruntime/src/main/ets/runtime/NodeRuntime.ets`（启动参数）。
- **做法**：评估 Node 22 的 `NODE_COMPILE_CACHE` 或自定义 `v8.serialize` 缓存；先做**只读预读**（把核心树的 `.js` 读一遍填 page cache），不做全量解析。
- **风险**：鸿蒙沙箱下 `dlopen`/`mmap` 行为与桌面不同；需实测是否真的提速。
- **验收**：`S4_host_start` → `S5_host_ready` 缩短 ≥ 10 %，否则回退。

#### B2｜启动类型分流（解决 G3）

- **做法**：写 `last-launch.json`（版本 / build / 时间戳 / 是否异常退出）；启动时判定 `cold | warm | reload`。
  - `cold`：完整品牌动画 + 启动页。
  - `warm`（上次正常退出且 < 阈值）：跳过品牌淡入，直接骨架 + 进度条。
  - `reload`（上次异常退出）：跳过动画，直接骨架 + 静态提示。
- **落点**：`platform`（读写）+ `WebApp`（分支）。
- **验收**：连续两次启动，第二次品牌动画跳过；异常退出后第三次无动画。

#### B3｜p1/p2/p3 显式分层（解决 G7）

- **做法**：把 `EntryAbility.onCreate` 的同步段按"是否阻塞首帧"重新归位：
  - p1（首帧前，必须）：静态配置、启动参数发布、主题写入。
  - p2（首帧后、宿主前）：目录授权恢复、restart watcher、语音桥、卡片 watcher、托盘。
  - p3（`READY` 后）：日志清理、遥测 flush、过期文件回收。
- **落点**：`EntryAbility.ets`。
- **验收**：`S1_ability` → `S3_first_frame` 缩短；`onCreate` 同步段总时长 < 10 ms（可用 `S1` 内部细粒度标记度量）。

#### B4｜三端骨架差异化

- **做法**：`entry` 用 PC/平板骨架（三栏/两栏），`phone` 用单栏骨架（顶栏 + 列表 + 输入框占位）。两壳独立文件，不共享布局常量。
- **验收**：`check-dual-shell-parity` 通过；两端骨架比例与真实首屏一致。

#### B5｜启动剖析按需开启

- **做法**：`dshStartupProf=1`（`aa start --ps`）才写 JSONL；默认只写一条 summary 到 `hilog`。文件名做可移植性校验。
- **验收**：默认启动无额外 IO；开启后可导出完整时间轴。

### C 档：不建议照搬

| 项 | 原因 |
|---|---|
| **3 s splash 最短展示** | 会直接顶穿 AGC「启动加载完成」4 000 ms 目标；DSHM 的启动页是**主呈现**而非过渡层，等待成本更高 |
| **多进程并行 bootstrap** | Electron 主进程与渲染进程天然分离；DSHM 是 ArkTS 单线程 + Node 子进程，重活只能"分片让出"，不能真并行 |
| **128 MB 全量 prewarm** | 移动端内存与 IO 代价高，且鸿蒙 page cache 策略不同；应改为"只预热核心入口与首屏必需模块" |
| **`document.write` 注入 seed** | ArkWeb 对 `document.write` 的时序保证与 Chromium 不完全一致，且与 DSHM 的 CSP/桥模型冲突；用 `runJavaScript` 或桥注入更稳 |
| **summary 早 flush** | 这是 WorkBuddy 的缺陷（§4.4），不要复制 |

---

## 7. 风险与反例

### 7.1 平台差异是最大的坑

| 维度 | WorkBuddy（Electron） | DSHM（ArkTS + ArkWeb） | 影响 |
|---|---|---|---|
| 线程模型 | 主进程 / 渲染 / daemon 多进程 | ArkTS 单线程 + Node 子进程 | "并行"不可照搬，只能"让出 + 异步" |
| 渲染层 | Chromium 完整能力（`document.write`、自定义协议、`prefers-reduced-motion`） | ArkWeb 子集 | P4 的 seed 注入、P10 的媒体查询需替换方案 |
| 启动指标 | 自建（`startup/*.jsonl`） | AGC「启动加载完成」 | 任何"人为等待"都会直接恶化对外指标 |
| 包结构 | 单 asar + unpacked | 多 HAP + HSP + HAR | 分段标记要考虑跨模块（`platform` 共享） |

### 7.2 埋点本身的三个反例（来自 WorkBuddy 实测）

1. **summary 过早 flush** → `phases` 为空。DSHM 必须"最后写 summary"。
2. **早期标记缺 `epochMs`** → 跨进程对齐出 `NaN`。DSHM 必须"双时间戳强制"。
3. **`C8` 重复打点** → seed prime 缺幂等。DSHM 每个标记要有"只打一次"的守卫（`@State` 或模块级布尔）。

### 7.3 不要为了"看起来快"而谎报

WorkBuddy 的 Office 冷启进度条只走到 85 %，**不谎报 100 %**；DSHM 的 98 % 上限同理。任何"提前到 100 % 再等"的做法都会在用户侧变成"卡在 100 %"，比 92 % 更糟。

---

## 8. 下一步建议（按优先级）

| 优先级 | 动作 | 预计收益 | 风险 |
|---|---|---|---|
| P0 | **A1 分段标记** | 让后续所有优化可验收 | 低（纯新增） |
| P0 | **A4 看门狗 + 崩溃守卫** | 消除"永远停在启动页" | 低 |
| P1 | **A2 壳内骨架** | 感知启动从"8 s 纯 logo"变为"0.3 s 有结构" | 中（改 `build()` 结构） |
| P1 | **A3 双向阈值防闪** | 热启动观感 | 低 |
| P2 | **A6 首屏快照** | `READY` 后首内容 < 300 ms | 中（存储 + 注入） |
| P2 | **B2 启动类型分流** | 热启动跳过动画 | 中 |
| P3 | **A5 凭据与 URL 分离** | 安全 | 高（行为变更，需确认） |
| P3 | **B1 Node 编译缓存** | 宿主启动 -10 %（待实测） | 中（平台差异） |

**建议的推进方式**：先做 P0（A1 + A4），用一次真实冷启动拿到 DSHM 自己的 S0–S7 时间轴；**用数据决定 A2 与 B1 的优先级**，而不是先改 UI。

---

## 9. 附：证据索引

| 结论 | 证据 |
|---|---|
| 六阶段 66 标记 | `app.asar → /main/marks.js`，`S` 表 |
| 引导壳零依赖 | `/main/ohos-main-bootstrap.cjs` |
| p1/p2/p3 编排 | `/main/index.js` → `onReady()` / `_p1*` / `_p2*` / `_p3*` |
| Splash 三态 + 看门狗 + 崩溃守卫 | `/main/index.js` → `SplashOrchestrator=class` |
| 骨架屏与拆除协议 | `/renderer/index.html`、`/renderer/skeleton/skeleton-bootstrap.js` |
| 三条首屏快路径 | `/renderer/index.html` 三段 IIFE 注释 |
| seed token 安全边界 | 同上（`wbSeedToken` 注释） |
| CodeCache | `/main/index.js` → `enableMainCompileCache` |
| prewarm | `/main/index.js` → `PREWARM_BUDGET_BYTES=134217728` |
| 并行事实 | `~/.workbuddy/logs/startup/2026-11-22/43752-145706.log` +4893ms |
| 真实时序 | `~/.workbuddy/logs/startup/2026-11-22/{15214,19999,52220,43752}-*.jsonl` |
| DSHM 现状 | `entry/src/main/ets/entryability/EntryAbility.ets`、`entry/src/main/ets/pages/WebApp.ets`、`hostruntime/src/main/ets/runtime/DshHost.ets` |

---

## 10. 落地记录（2026-11-25，A1 + B3 第一批）

### 10.1 已落地

| 项 | 文件 | 说明 |
|---|---|---|
| **A1 分段标记** | `platform/src/main/ets/diagnostics/StartupMarks.ets`（新增）+ `platform/Index.ets` 导出 | S0–S7，双时间戳（`ts` 相对 / `epochMs` 绝对），幂等（同 id 只记一次），JSONL 追加写 `<filesDir>/dsh/logs/startup/<epoch>-<pid>.jsonl`，同时打一条 W 级 hilog `DSHM-STARTUP`；`finish()` 只在终态写 SUMMARY（吸取 WorkBuddy summary 早 flush 的缺陷） |
| **B3 诊断后置** | `EntryAbility.onCreate` | `probeNativeBindings()`（`dlopen` + 原生调用，纯日志）从 onCreate 同步段移到 `setTimeout(0)`，不再与首帧争 ArkTS 线程 |
| **B3 预热让位** | `EntryAbility.scheduleHostStartAfterFirstFrame` | `warmWebEngineOnce()` 从"紧跟宿主启动"改为"下一个宏任务"。依据：历史实测 `DSHM-TRACE ArkWeb 引擎预热完成（106–118 ms）`，这 110 ms 原本会压住宿主链已排队的 Promise 回调 |
| **A1 打点接线** | `EntryAbility` / `WebApp` | S0 onCreate 入口 · S1 启动参数发布 · S2 onWindowStageCreate · S3 loadContent 回调 · S4 宿主链调度 · S5 `KEY_HOST_LAUNCH_URL` 发布 · S6 onPageBegin · S7 onPageEnd→READY |
| **报告工具** | `tools/startup-report.mjs`（新增） | `node tools/startup-report.mjs <本次.jsonl> [--baseline <基线.jsonl>]`，输出 S0→S7 表与逐段差值 |

### 10.2 量化结论

**确定性收益（有历史实测支撑）**：`initializeWebEngine()` 同步占用 UI 线程 106–118 ms（`dist/acceptance/startup-1010017/pc-run{1,2}-hilog.txt`、`dist/acceptance/20261124-phone-sigsys-io-uring/phone-hilog-live-full.txt`）。该调用原先紧跟在 `autoStartHostForDiagnosis()` 之后，处于宿主启动 Promise 回调的前方；移到下一个宏任务后，这约 110 ms 从「S4→S5 宿主就绪」中移除。

**未量化部分**：`probeNativeBindings()` 的 dlopen 耗时无历史计时，提升量在 0–50 ms 量级，需 S1→S2 前后对比才能确认。

**仍未解决的主成本**：宿主启动（S4→S5，历史观测约 8 s，首启解包可达 30–60 s）与 Web 首屏（S6→S7）。本批改动不动这两段。

### 10.3 验证方式（上机后一条命令）

```bash
# 1) 取回本机日志（包名按产物替换：dshclient / dshmbeta）
hdc file recv /data/app/el2/100/base/com.dshm.dshclient/haps/entry/files/dsh/logs/startup ./dist/startup-logs
# 2) 出表；有基线就带 --baseline
node tools/startup-report.mjs dist/startup-logs/<本次>.jsonl --baseline dist/startup-logs/<基线>.jsonl
# 3) 与 hilog 互证
hdc shell "hilog -x -T DSHM-STARTUP"
```

验收口径：
- S0→S7 能在单文件里还原，误差 ≤ 5 ms（同一进程内 `Date.now()` 精度）。
- `S4→S5` 相比基线下降 ≥ 80 ms 视为「预热让位」生效。
- S7 缺失时说明未到首屏就绪，此时应看 SUMMARY 是否存在及最后到达的段。

### 10.4 本批不做（需真机确认后再动）

- **A2 壳内骨架**：要改 `WebApp.build()` 的 `if (phase !== BOOTING) Web(...)` 结构，涉及三端布局；无设备时无法验收视觉与骨架拆除时序。
- **A3 双向阈值防闪**：属纯观感项，需真机确认不会引入"启动页多停留"。
- **A5 凭据与 URL 分离**：行为变更（会话建立方式），按项目规范需先出方案确认。
- **B1 Node 编译缓存**：需实测 `NODE_COMPILE_CACHE` 在鸿蒙沙箱的可用性。

### 10.5 顺带修复（既有失败，非本批引入）

`tools/check-startup-work.mjs` 在 2026-11-25 凌晨的「工具链解包后置到 startupWork」改动后失效（断言仍按 6 条请求 + 裸调用锚点）。本批同步为：7 条请求、锚点改为 `startupWork.request('toolchain'`、`ensurePythonBridge` 允许两个挂载点（boot + 解包收尾补挂）。修后 `--self-test` 10 mutants 全部被拒。

---

## 11. 落地记录（第二批：A2 骨架 + B1 编译缓存可见化）

### 11.1 A2：启动页骨架暗示（**已撤回**，2026-11-25 10:00）

> **撤回原因（用户 PC 真机截图裁决）**：进度条下方那块灰色结构被判定为「多余的东西」，
> 启动环节不要它。已移除骨架块、`skeletonTint()` / `skeletonEdge()`，启动页恢复为
> 「品牌标 92 + 线性进度条（上距 40）」两项。
>
> **这次撤回对 A2 的一般性结论**：在 DSHM 上，"窗口先带结构出现"这条路**不成立**——
> 启动页是纯 ArkUI 覆盖层，它下面此刻没有任何可对齐的真实布局，画出来的占位只会被读成
> "多余"。WorkBuddy 之所以成立，是因为它的骨架是**真实首屏 HTML 的内联骨架**（同一份
> 文档里的 DOM），骨架与内容位置天然一致。**若未来重做，前提是 Web 组件带着真实首屏骨架，
> 而不是在 ArkUI 启动页里画假结构。**
>
> 下面保留的是该次尝试的原始记录，仅作决策依据，不代表当前代码。


**改动**：`entry/src/main/ets/pages/WebApp.ets` 的启动页分支（`BOOTING || (LOADING && !everReady)`）。

| 项 | 改动 |
|---|---|
| 品牌标 | 92 → 84（给下方结构让出垂直空间） |
| 进度条 | 上间距 40 → 28 |
| 新增 | 内容区中性占位：标题块 188×24、三个场景 pill 72×24、输入框 86%×84（带 1px 描边），整体 `constraintSize({ maxWidth: 340 })` |
| 颜色 | 新增 `skeletonTint()` / `skeletonEdge()`：浅色 `#0D000000` / `#14000000`，深色 `#12FFFFFF` / `#1FFFFFFF`（ARGB，避免 `rgba()` 解析差异） |
| 动效 | **不加**。品牌呼吸已占用 `brandBreath`，再叠同时长动画会争同一属性；动感仍由进度条与品牌呼吸承担 |

**为什么只做"内容区暗示"而不是完整三栏骨架**（与 WorkBuddy 的差异是有意的）：

1. 真实布局三端差异大——PC 顶栏+常驻左栏、平板 280/56 展开收起、`<1024` 交官方抽屉。按任一形态硬编码骨架，另两种形态会出现「骨架 → 真界面」的二次跳变，比没有骨架更糟。
2. `TopBar()` 在 `Stack()` 之外，启动期已经渲染；再画顶栏占位会重叠。
3. 内容区（标题 / pill / 输入框）是三端共有的首屏结构，位置稳定，不会造成错位。

**为什么不做"提前创建 Web"（报告原文的第 1 步）**：

- 需要在 `BOOTING` 阶段用 `about:blank` 占位并守卫 `onPageBegin/onPageEnd`，否则占位页的 `onPageEnd` 会把 `phase` 置成 `READY`，启动页提前消失（白屏）。
- 提前创建会提前占用 ArkWeb 渲染进程，与既有的「MatePad Edge 内存风暴」收口（`applyWebMemoryProfile`）方向相反。
- 收益不确定：引擎已由 `warmWebEngineOnce()` 预热（实测 106–118 ms），剩下的是渲染进程创建，量级在百毫秒。
- 无设备可验收。按「保证启动加载完成后所有功能正常」的硬约束，本批不做。

### 11.2 B1：编译缓存——现状核实与可见化

**核实结论：`NODE_COMPILE_CACHE` 的接线在 2026-11-15 已完成，不是本批新增。**

- `hostruntime/.../RuntimePort.buildHostEnv` 已把 `NODE_COMPILE_CACHE=<cacheDir>/v8-compile-cache` 写入宿主环境；
- `NodeRuntime` 构造时算好目录、`startHost` 打日志；
- 真机日志证实已实际传入（3 个样本）：
  `startHost：NODE_COMPILE_CACHE=/data/storage/el2/base/haps/entry/cache/v8-compile-cache`。

**真正的缺口是"是否真的生效"不可判定**：环境变量被设置 ≠ libnode 启用了缓存。若这一版 libnode 未编译 `src/compile_cache.cc`，Node 会静默忽略，启动耗时不变化，无法区分"没命中"与"没生效"。

**本批补的可见性探针**（`hostcore/app/main.js`，紧随 `BOOT_00_NODE_START`）：

```js
function reportCompileCache() { /* module.getCompileCacheDir() 只读一次 */ }
reportCompileCache();
```

三种结论写进 `node-output.log`：
- `已启用 dir=...` ⇒ 缓存真的在跑；
- `未生效 env=...（当前 libnode 可能未编译 compile_cache）` ⇒ 环境变量是摆设，结论落盘；
- `未配置（NODE_COMPILE_CACHE 为空）` ⇒ 调用方没传。

**审核中主动收敛的两处**（初版写错、已改）：

| 问题 | 后果 | 修正 |
|---|---|---|
| 初版用 `fs.readdirSync(activeDir).length` 统计缓存条目 | 在 `BOOT_00` 之后、所有启动工作之前做同步 IO，缓存目录可能上千条目 ⇒ 用几十毫秒换一行日志 | 删除计数，`getCompileCacheDir()` 只读一次，**零 IO** |
| 初版有 `DSHM_CACHE_DIR` + `enableCompileCache()` 主动启用分支 | ArkTS 侧从不传该变量，分支永不触发；且 `enableCompileCache` 与 `NODE_COMPILE_CACHE` 同一套实现，libnode 没编译时同样无效 | 整段删除 |

### 11.3 验证

| 项 | 结果 |
|---|---|
| `check-arkts-entry --clean`（强制全量重编） | 0 error；`WebApp.ets` 零告警 |
| `devecocli build --product default` | 143 tasks（82 executed / 61 up-to-date）BUILD SUCCESSFUL |
| `devecocli build --modules phone@default` | BUILD SUCCESSFUL |
| 门禁 14 条 | 全绿：resfile 27/27、boot-rescue 13/0、startup-work+selftest、brand 110、dual-shell、feature-wiring、dead-code、doc-refs、parity、权限 19/9、tools-syntax 210、python-env 18/0、node-cli 43/0、vm-bash 376/376 |
| Beta 包 | `dist/beta/DSHM-beta-1.1.8-1010020-20261125T014426/`，app 647,695,115 B |
| SHA256SUMS | 5/5 |
| `hap-sign-tool verify-app` | success |
| 包内容核验 | HSP `app/main.js` 含 `compile-cache` 探针；tablet / phone 两个 hap 的 abc **均不含** `skeletonTint`（骨架已撤回）；权限 19 / 9 |
| 身份还原 | `AppScope/app.json5` sha `88fff7ba`、`build-profile.json5` sha `0b94c7aa`，与出包前逐字一致 |

### 11.4 仍需真机确认

> 骨架相关的两项（观感、"骨架→真界面"是否闪帧）已随 §11.1 撤回而作废。

1. **B1 结论**：看 `node-output.log` 里 `compile-cache:` 那一行是"已启用"还是"未生效"。若"未生效"，说明当前 libnode 未编译该特性，B1 需要走别的路径（例如对核心树做模块级 snapshot），不再在环境变量上投入。
2. **S4→S5**：用 `tools/startup-report.mjs` 对比首批基线，确认「预热让位」的净效果（骨架已撤，本项是唯一变量）。
3. **S0→S7 全链路**：确认 S1（静态配置 + 启动参数发布）在 `probeNativeBindings` 移出后确实 < 50 ms。

---

## 12. 收尾与全量复核（2026-11-25 10:56）

### 12.1 启动优化的最终状态

| 项 | 状态 | 说明 |
|---|---|---|
| S0–S7 分段标记 | **保留** | `StartupMarks.ets` + S0/S1（onCreate）· S2（onWindowStageCreate）· S3（loadContent 回调）· S4（宿主链调度）· S5（URL 发布）· S6（onPageBegin）· S7（onPageEnd→READY） |
| 出表工具 | **保留** | `tools/startup-report.mjs`，支持 `--baseline` 逐段差值 |
| `probeNativeBindings` 后移 | **保留** | 纯日志，移出 `onCreate` 同步段 |
| `warmWebEngineOnce` 让位 | **保留** | 让出一个宏任务；依据实测 106–118 ms |
| `compile-cache` 可见性探针 | **保留** | `main.js` 紧随 BOOT_00，零 IO |
| 启动页骨架暗示 | **已撤回** | 用户真机截图裁决（§11.1） |
| Web 提前创建 / 首屏快照 / 启动类型分流 / 看门狗 / 凭据与 URL 分离 | 未做 | 需真机验收或属行为变更，见 §6 / §11.4 |

### 12.2 全量门禁

`tools/` 侧从 `gates.yml` 现提 133 条命令逐条执行（每条 240 s 超时），报告
`dist/acceptance/20261125-full-gates-startup-closeout.txt`：

**131 通过 / 2 失败 / 0 超时**。

| 失败项 | 判定 | 依据 |
|---|---|---|
| `check-guest-terminal-lifecycle.mjs` | **环境限制，非回归** | 该门禁只读 `hostcore/plugins/dshm-vm-bash/lib/terminal.js`（本轮未改，`git status` 为空）。失败点是 `pickShell()` 选出的宿主 sh 不支持可靠的 `kill()` 函数覆盖 ⇒ 模拟信号空转（期望 `SIGNAL -TERM …` 序列，实得 `[]`）。同源限制见 `docs/PITFALLS.md` §3.14（shell 不能枚举 `/proc`）。需在标准 sh 环境复跑。 |
| 同上 `--self-test` | 同上 | 主检失败时自测必然跟随 |

### 12.3 复核中发现并修复的回归（本轮引入）

| 问题 | 影响 | 修复 |
|---|---|---|
| S6 标记插在 `onPageBegin` 的 `cancelNativeCapture()` 之前 | `check-native-capture-lifecycle` 的两条断言同时失效：① 正则 `\.onPageBegin\(\(\) => \{\s*this\.cancelNativeCapture\(\);` 不匹配；② 自测 mutant 4 的锚点 `this.cancelNativeCapture();\n            //` 打不上（"mutant 4 must apply"） | 把 `cancelNativeCapture()` 放回回调第一行，S6 标记移到其后；注释也排在 `cancelNativeCapture();` 之后且首行为 `//`（门禁的 `\s*` 只允许空白，块注释同样会破坏锚点）。修后 15 个 negative control 全部被拒 |

> 这条值得单独记：**"只观测"的埋点也会改变代码形状**，而门禁锚点常常就钉在形状上。
> 埋点的正确位置是「不改变既有语句顺序、不打断相邻行的紧邻关系」。

### 12.4 清理记录

| 项 | 处理 | 释放 |
|---|---|---|
| `dist/beta` 历史包 13 个 → 1 个（仅留 `…20261125T025309`） | 已删 | 22.72 GB → **1.76 GB**（约 21 GB） |
| 本轮临时产物（骨架方法、临时脚本） | 已随撤回删除 | — |
| `dist/core/work` 的 4 个旧版本（rc.1–rc.4，约 4.2 GB） | **未删**（见下） | — |
| `dist/acceptance`（验收证据，2.5 GB）、`outputs`（交付存档，1 GB）、`backup`（150 MB） | **未删** | — |

**为什么不删 `dist/core/work` 旧版本**：`pack-core.mjs` 会从最新的 `dsh-core-*` 目录复用
`package-lock.json`，以保证**依赖闭包可复现**（不随 rebuild 漂移）。删掉后下次物化会由 npm
现场解析 ranges，可能出现"同一份配方、两次出包内容不同"。若确需释放这 4.2 GB，应在删前先把
rc.5 的 `package-lock.json` 备份到 `hostcore/` 下作为基线，属独立动作。

### 12.5 收尾后仍需真机确认

1. `S4→S5` 是否下降 ≥ 80 ms（预热让位是否生效）；
2. `compile-cache:` 日志是"已启用"还是"未生效"（决定 B1 是否换路径）；
3. `S0→S7` 全链路能还原（`tools/startup-report.mjs` 一条命令出表）。

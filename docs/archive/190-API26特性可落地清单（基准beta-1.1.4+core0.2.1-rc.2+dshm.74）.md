# 190 · API26 特性可落地清单（基准：beta 1.1.4 / core `0.2.1-rc.2+dshm.74`，2026-10-18）

> 用户 2026-10-18：「先落本地，让内测组测试，看下 API26 特性项目可落地清单」。
> 本文是**可执行版的 API 26 能力盘面**：在 `docs/172`（能力全景与三件套）的基础上，
> 把"已落地 / 可落地 / 观察区 / 排除区"钉到**具体落点、工作量、风险、验收判据**，
> 供 1.1.5 / 1.2 排期直接取用。

---

## 0. 前置判据（任何一项都不可突破）

| 约束 | 当前值 | 对落地的影响 |
|---|---|---|
| manifest 权限面 | **恒 8 条**（2 条已审批 ACL + 6 条免申请） | 任何需要第 9 条权限的能力一律**排除**，不做"先声明再看" |
| 兼容面 / 目标面 | `minAPIVersion=60100023`（API 23）/ `targetAPIVersion=260000026`（API 26） | 所有 26 能力必须 `canIUse` 守卫 + API 23 降级，不能硬调 |
| Node 运行时 | `--jitless`（无 WASM、无 JIT） | 依赖 WASM 的 npm 包不可用；native 侧只能靠已有 `.so` |
| 手持档执行面 | 无 execve/无 spawn（真机实测），真命令走 guest VM | 依赖"起进程"的能力改进程内实现，或走 VM |
| 双工作区 | beta `com.dshm.dshmbeta` / 正式 `com.dshm.dshclient` | 端侧配置类改动（shortcut/agent/label）两侧各自维护 |

---

## 1. 已落地（1.1.4 已交付，清单只做登记）

| 能力 | 端侧落点 | 证据 |
|---|---|---|
| 桌面快捷方式（26 配置式） | `resources/base/profile/shortcuts_config.json`（新建会话） | `docs/172 §5.2` |
| 意图框架 insightIntent | `insight_intent.json` + `StartNewSessionImpl.ets` | `docs/172 §5.3` |
| A2A 端侧（AgentExtensionAbility + AgentCard） | `agentextability/AgentExtAbility.ets` + `agent_config.json`，`bm dump extensionTypeName=agent` 三层读数通过 | `docs/172 §5.4`（平台注册待用户在小艺开放平台操作） |
| 桌面服务卡片（进度/余额/四档用量） | `UsageFormAbility` + `CardStateWatcher` + `UsageCard` | `docs/178` |
| PC 状态栏托盘（图标 + 菜单 + hover 基础） | `system/StatusBarTray.ets`（`@hms.pcService.statusBarManager`） | 本档 §3.1 表 |
| 浏览器自动化 / 抓取增强 | 宿主 `/dshm-browser/*` + 外开桥 | `docs/174-177` |
| guest SSH 客户端（内置虚拟机通道） | `dshm-vm-bash` + QGA | `docs/188` |

---

## 2. 可落地（按"风险×收益"排序，编号可直接进排期）

### P0 —— 低风险、零权限、可独立出包（建议 1.1.5）

| # | 能力 | SDK 事实 | DSHM 落点 | 工作量 | 风险 / 处理 |
|---|---|---|---|---|---|
| P0-A | **文件页缓存释放** `appMemoryOptimizer.evictFilePages()` | `@ohos.app.ability.appMemoryOptimizer`，**since 26.0.0**，`@syscap SystemCapability.Ability.AbilityRuntime.Core`，只接受 `.so/.hap/.hsp`，系统按内存压力决定是否真释放 | 能力层新 `MemoryTrim.ets`：`canIUse('SystemCapability.Ability.AbilityRuntime.Core')` + `deviceInfo.sdkApiVersion >= 26` 才调；触发点 = `onBackground()` + 手持 VM 启动前 + `onMemoryLevel(CRITICAL)`；参数用**当前 HAP 内已加载的核心/宿主导出清单**（不猜路径） | 0.5 d | 误释放导致重载抖动 → 只在后台/临界内存触发；`16000163` 按文件类型过滤；失败只落 diag 不阻断 |
| P0-B | **PC 状态栏菜单增强**（26 新增 hover/菜单形态） | `@hms.pcService.statusBarManager`（已有基础实现） | `StatusBarTray.ets`：菜单项收敛为「打开主窗口 / 新建会话 / 当前会话进度」，hover 只做高亮不改布局 | 0.5 d | 2in1 真机复验（菜单坐标/DPI/深色）；API 23 不注册、静默降级 |
| P0-C | **系统分享面板** `systemShare` | ShareKit，since 11 | 会话导出（`.md`/`.jsonl`）与工作区文件分享入口；只在"文件已落在公共 `Download/<包名>`"时给入口，沙箱文件先复制再分享 | 0.5 d | 分享目标为外部应用，确认无越权读取；API 23 走"另存到下载目录"降级 |
| P0-D | **AppLinking / Want(viewData) 注册** | AppLinkingKit，since 12 | `module.json5` 加 `uris`（`https://dshm.app/link` 之类）+ `EntryAbility.onNewWant` 解析 `sessions/<id>` / `workspace`；端侧先做"能收就跳"，域名校验文件属网页侧（另行） | 1 d | 域名归属校验未完成前，浏览器打开会落到系统"无应用处理"→ 端侧先只做 `want.uri` 直开兜底；不改权限面 |

### P1 —— 需要 UI 或真机专项验证（建议 1.2）

| # | 能力 | SDK 事实 | DSHM 落点 | 工作量 | 风险 / 处理 |
|---|---|---|---|---|---|
| P1-E | **文件预览组**（PDF Kit / Preview 加速 / `fs.mmap` / `listFileExt`） | PDFKit / PreviewKit / CoreFileKit，12 起；26 增强 | 工作区文件"直读直显"：先做 **PC/2in1 的 PDF + 图片预览**（`PreviewKit` 或 PDF Kit 原生页），手持档仍走 ArkWeb 内嵌；`fs.mmap` 只用于大文件切片读取 | 2–3 d | 渲染宿主选择（原生页 vs Web 组件）影响返回栈，需与 `docs/166-170` 的返回链一起验；只对 26 开，23 降级为下载 |
| P1-F | **智慧手势** `SmartGestureController` | `@ohos.arkui.UIContext`，since 26 | 与现有 `onBackPress` 分层消费链合并：边缘返回手势统一走"先问 Web 要关什么"（`__DSHM_BACK__.consume()`），避免与官方手势重复消费 | 2 d | 手势冲突是主要风险 → 只在手持档挂、提供 `DSHM_GESTURE=off` 开关；三条真机路径（抽屉/设置面板/根状态）逐条复验 |
| P1-G | **应用内嵌小艺智能体**（AgentFrameworkKit `AgentController`） | `@hms.ai.AgentFramework`，20 起（本机 SDK 未随包，需装对应 SDK 复核） | 设置页/侧栏加"问小艺"入口：`isAgentSupport()` 为真才显式，弹出事件回落到内置 agent 会话 | 1–2 d | 依赖设备小艺可用性与隐私告知；`isAgentSupport` 假则整块不渲染（fail-closed） |
| P1-H | **PC 快捷栏任务/分组** `quickBarManager` | `@hms.pcService.quickBarManager`，22 起；26 加分组（本机 SDK 未命中，需复核导入路径） | 任务（turn）状态进 Dock：运行中/等待确认两态；分组按工作区分 | 1–2 d | 自定义图标/进度条受限（`docs/172 §3.2`）→ 只做系统默认样式；2in1 真机验证 |

### P2 —— 值得做但成本高（1.2 之后）

| # | 能力 | 说明 | 工作量 | 前置条件 |
|---|---|---|---|---|
| P2-I | harmonyShare 碰一碰 / 隔空传送（接收侧） | 手机碰 PC 传文件进工作区 | 1–2 d | 需硬件交互与双机验证；接收侧权限面不变 |
| P2-J | HDS 组件（HdsSideBar/HdsNavigation，26 加 HdsColorPicker） | PC 端 UI 对齐系统风格 | 2–3 d | 需 `canIUse` 探测 + 组件替换面评估（现有自绘顶栏不能直接换） |
| P2-K | 窗口 API26 群（窗口姿态/跨屏演示/任务快照/容器模态色） | PC 多窗、跨屏、任务视图 | 3–5 d | 2in1 真机覆盖成本高；与现有 `setWindowDecor` 链有交叉，需先做兼容矩阵 |

---

## 3. 观察区（先不做，写清触发条件）

| 能力 | 不做的原因 | 何时重看 |
|---|---|---|
| LiveView（实况窗） | 需企业权益/华为侧权益审核，三方应用门槛未确认 | 用户拿到权益或平台开放三方申请时 |
| quickBar 自定义图标/进度条 | 平台限制（`docs/172 §3.2`） | 平台放开后再评估 |
| AgentFrameworkKit | 本机 SDK 未随包，无法验证导入面 | 装 26 SDK（含 HMS）后复核 |
| harmonyShare 发送侧 | 接收侧先做，发送侧需文件选择器与授权链配合 | P2-I 完成并验证后 |

---

## 4. 排除区（权限铁律，永不申请，也不写进文档当"待办"）

`floatView`/`floatingBall`（`FLOAT_VIEW`/`USE_FLOAT_BALL`）、`inputEventClient`（`CONTROL_DEVICE`）、
ServiceInteraction 碰一碰连接（`KNOCK_COLLABORATION`）、AccessoryKit（`ALLOW_ACCESSORY_ACCESS`）、
NearLink（`ACCESS_NEARLINK`）、`pluginBundleManager`/HSP 本地插件管理（`SUPPORT_LOCAL_PLUGIN`）、
NetworkBoost（`LINKTURBO`）、Pen Kit 跟手性加强（`STYLUS_FRAME_BOOST`）。

> 判据：候补 API 的 `@permission` 含本包 8 条之外的条目 ⇒ 一律不做。详见 `docs/172 §3.3`。

---

## 5. 落地顺序建议

1. **1.1.5（本清单 P0-A/B/C/D）**：零权限、无 UI 大改、可独立门禁；出一版内测即可收数据。
2. **1.2（P1-E/F/G/H）**：需要 UI 与真机专项；建议先 E（预览）与 F（手势）两项，因为都牵动返回栈这一条公共链，一起验更省时间。
3. **P2** 按用户优先级另排，不进 1.1.5/1.2 的承诺范围。

---

## 6. 每项的验收判据（落地时必须同时满足）

1. `canIUse(<syscap>)` 且 `sdkApiVersion >= 26` 才调用；否则整条静默降级（不报错弹窗）。
2. 权限面零变更：`node tools/check-permission-surface.mjs` 通过（8 条）。
3. API 23 真机/模拟：功能降级路径可用（工作区/会话/文件不因新能力缺失而失败）。
4. 真机读数落 diag（如 `diag-memtrim`、`diag-gesture`、`diag-share`），供内测组回传。
5. 涉及配置的（P0-D 的 `uris`），`module.json5` 改动必须同时更新 `tools/check-feature-wiring.mjs` 的接线判据。

---

## 7. 风险登记

- **版本面**：26 能力在 API 23 手持上不存在 ⇒ 所有入口按"能力探测 + 降级"，不按机型/版本号硬判。
- **权限面**：本清单 P0/P1 全部零新增权限；若未来候选项需要第 9 条，先走用户拍板，不走"先做再看"。
- **性能面**：P0-A 只在后台/临界内存触发，避免前后台切换抖动；P1-E 预览渲染要与 Web 视图共用返回栈。
- **验证面**：2in1 与手持的差异集中在窗口/手势/状态栏三块，P1-F/H 必须各出 2in1 + 手持两份读数。

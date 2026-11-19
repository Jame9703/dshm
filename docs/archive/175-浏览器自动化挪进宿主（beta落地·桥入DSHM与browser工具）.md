# 175 · 浏览器自动化「挪进宿主」（beta 落地：桥入 DSHM + `browser_*` 工具 + 正式扩展）

> 承接 `docs/173`（调研）/ `docs/174`（PoC）。用户 2026-10-16：「**挪进去，先从 beta 试试**」。
> 结果：**beta 工作区端到端落地** —— 桥进 DSHM 宿主进程、插件工具进核心树（+dshm.57）、
> 正式扩展连宿主桥（`clients:1`）、`navigate / get_tree` 实测通过。**未 commit / 未 push。**

## 1. 改动清单

| 文件 | 改动 |
|---|---|
| `hostcore/app/main.js` | 新增 `registerBrowserBridge(ctx)`：**手写最小 WS 服务端**（`ws://127.0.0.1:19390/browser-bridge`）+ `/dshm-browser/status`、`/dshm-browser/invoke` HTTP 端点 + 15s 保活 + 连接即拒绝待答；boot 调用紧接 python 桥之后（`BOOT_62B_BROWSER_BRIDGE`） |
| `hostcore/plugins/dshm-tool-browser/{package.json,lib/index.js}` | 新插件：`browser_status / browser_navigate / browser_tree / browser_click / browser_text`（5 工具；走 `/dshm-browser/*`；token 与 python 插件同源——`host-ready.json`） |
| `tools/pack-core.mjs` | `DSHM_PLUGIN_PACKAGES` 增 `dshm-tool-browser`（含注释） |
| `hostcore/profile/ondevice/cordis.patch.yml` | 新增 **⑦c** insert（`tool-browser`） |
| `hostcore/browser-extension/{manifest.json,background.js}` | 正式扩展（MV3：`debugger/tabs/scripting`；连 `ws://127.0.0.1:19390/browser-bridge?token=dshm-browser-beta`；含 PoC 实测的全部约束对策） |
| `hostcore/core-recipe.json` | `coreVersion`：`+dshm.56` → **`+dshm.57`** |
| `dist/poc-bridge/deploy-ext.mjs` | 部署器改指 `hostcore/browser-extension/` → 设备 `<下载>/com.dshm.dshmbeta/dshm-browser-ext/` |

## 2. 构建与产物读数

- `pack-core --place-in-app`：**dshm.57** 核心 **94.9 MB / 40746 条目**（旧容器自动清理；自带插件清单 10 项含 `dshm-tool-browser`；树内 peer 回归锁通过）；
- `place-host-app` + `assert-resfile-sync`：**15 件快照全部同步**；
- `assembleHap` **BUILD SUCCESSFUL** + `install -r` 成功；
- 设备核心树核对：`cores/0.2.1-alpha.4+dshm.57/`（唯一版本）+ `node_modules/@deepseek-ai/` 下 **10 个 `dshm-*` 目录**（含 `dshm-tool-browser`）。

## 3. 验证读数（hilog 实录 + HTTP 实测）

| 环节 | 读数 |
|---|---|
| 扩展连入 | `IN-UPGRADE GET /browser-bridge?token=… origin=chrome-extension://ddnfl…` → `extension connected id=ws_1` → `extensionInfo {"build":"dshm-host-bridge-1",…}` |
| 桥状态 | `GET /dshm-browser/status` → `{"ok":true,"port":19390,"clients":[{"id":"ws_1","info":{…"capabilities":{"tools":["navigate","get_tree","click","get_text","cdp_eval"]}}}]}` |
| 导航 | `invoke?tool=navigate` → `{"ok":true,"result":{"load":"complete","via":"cdp-pagenavigate"}}` |
| 读树 | `invoke?tool=get_tree` → `[ref_0] link "Learn more"` |
| 全过程 trace | host 日志：`runTool:navigate start → navigate target=… → Page.navigate via CDP → load state=complete → runTool:get_tree start → toolTab=…` |

## 4. 安装 / 使用（beta 口径）

1. 扩展源码随仓（`hostcore/browser-extension/`）；beta 用 `dist/poc-bridge/deploy-ext.mjs` 把扩展写入设备共享区
   （经 DSHM 的 `/dshm-python` 桥分块写 + **逐文件 sha256 校验**）；
2. 浏览器（海泰等 Chromium 系）扩展页「加载已解压的扩展程序」选中该目录；
   **改版本必须换目录名 + 升版本**（海泰对解压扩展有缓存，见 `docs/174` §4.2）；
3. 已知约束（沿用 `docs/174`）：需要**一个 http(s) 标签页**（海泰禁扩展建/控标签页）；**debugger 独占**
   （与 WorkBuddy 的 Ultron 冲突——先停对方）；桥当前为**固定 token**（beta 口径）。

## 5. 待办（正式化，未做）

- 桥 token **动态化** + 扩展侧配置界面（不再写死）；
- 扩展**分发与升级引导**（随包释放 + 界面步骤；升级换目录的机制做成自动化）；
- 与 WorkBuddy 的**调试器协调**（工具错误措辞已具备，可加自动检测提示）；
- 工具面扩展（截图 / 网络观测 / 视觉指示，参 `docs/173` §3.6）。

## 6. 追记（2026-10-16 深夜「直接接手调试」）：三个真根因与修复

> 用户原话：「你看下我我现在执行的任务，看下会话报错啥的，没动起来」「直接接手调试看看」。
> 起点：任务「用浏览器打开 baidu.com」时模型**没有动起来**。全部结论都有读数，下面按根因排列。

### 6.1 根因 A（P0）：`output.render` 单参写法 ⇒ `INVALID_TOOL_OUTPUT`（已修 + 已立门禁）

- **证据（会话轨迹）**：harness 会话 `session-0aed3274`（zstd 逐帧解出，155 行事件）里
  `tool/call browser_status` ×2 的结果都是
  `Error: tool "browser_status" returned invalid output: output.render returned non-lossless JSON`；
  紧接着模型放弃工具、转去 `bash`/`grep` 翻文件系统找"Browser Bridge"（耗掉 ~10 个工具调用）。
- **判据（框架源码）**：`@deepseek-ai/dsh-tools` 的 `createSuccessResult`：
  `rendered = tool.output.render(exec.arguments, value)` → `snapshotProjection(...)`；
  而快照函数对 `undefined` 返回非无损 ⇒ `ToolOutputError`。
- **根因**：`hostcore/plugins/dshm-tool-browser/lib/index.js` 初版把渲染器写成**单参 `(value)`**：
  实收 `args` ⇒ `value.detail === undefined` ⇒ 渲染产物 `[{type:'text', text: undefined}]` 判红。
  5 处渲染器里 3 处同病（`status/navigate/click` 用命名函数，`tree/text` 用内联箭头）。
- **修复**：全部改成 `(args, value)` 两参（命名函数 `renderText(_args, value)`；内联同）。
- **门禁（防复发）**：新增 `tools/check-plugin-render-arity.mjs` —— 静态数 `hostcore/plugins/*/lib/index.js`
  里每处 `render:` 的形参（内联箭头 / 内联 function / 具名声明引用三种写法都认；认不出的写法一律判红），
  **带 2 组合成对照臂**（单参反例必须报 2 条、两参正例必须 0 报）；已接入 `.github/workflows/gates.yml`
  与 `AGENTS.md`（仓库内门禁 26 → **27** 条）。
- **离线动态复核**：`dist/dbg-verify/verify.mjs`（junction 到核心树的 `dsh-util-values`）按框架**真实调用形状**
  `render(args, frozenValue)` + `snapshotJsonValue` 跑 5 个工具：全 PASS；旧单参写法在同一形状下如期判红。

### 6.2 根因 B：扩展 service worker **静默死亡** ⇒ 宿主重装/重启后再也不回连（已修）

- **证据（真机）**：21:47 覆盖安装（旧宿主进程被杀）→ 21:50:26 新宿主起来（`/dshm-browser/status` 可答）
  后 **clients 持续为空 3 分钟以上**；直到用户点"重新加载"才回连（`ws_2`，13:58:15Z）。
  也就是说：扩展侧**没有任何东西能唤醒被停掉的 SW**。
- **根因**：MV3 SW 空闲 ~30s 被停；而原 `background.js` 里**没有任何 `chrome.*` 事件监听**
  （只有 WS 回调）⇒ 一旦被停，浏览器侧再无事件触发 SW 重跑 `connect()`。
- **修复（v2 起）**：`chrome.alarms` 30s 心跳（`ensureConnected()`）+ `runtime.onStartup` + `tabs.onUpdated`
  三个唤醒点；`new WebSocket` 的同步异常也必留 3s 重试（旧写法一旦 ctor 抛异常重试链就断）。
  manifest 加 `alarms` 权限。**实测**：换 v3/v4 后连入即时报文（`extension connected` → `extensionInfo`），
  不再需要"碰一下浏览器"。

### 6.3 根因 C：「attach 只认当前活动标签页」——从误判"毒标签页"到 14:41 的对齐取证（v3→v6）

> ⚠️ **本节包含一次被推翻的归因，按原委留档**（这正是"不要经验主义"的现场）。

**初判（后来证明是错的）**：老 tab `1960785794` 在 v1 时代 attach 成功过，此后 v2/v3/v4 都对它
`api-timeout: debugger.attach`（挂死 5s），而用户新开的 `1960785795` 一次就过 ⇒ 一度判为
"海泰在扩展换版后不释放幽灵调试器会话（毒标签页）"，v4 因此写成"逐个候选 try-attach + tabs.create 兜底"。

**推翻它的决定性读数（把 6 轮的"活动位"当变量对齐）**：

| 时刻 | 浏览器活动位 | attach 结果 |
|---|---|---|
| 13:56 / 13:58 / 14:08 | **扩展管理页**（`haitai://extensions`），网页都在后台 | 一律挂死 5s（`api-timeout: debugger.attach`） |
| 13:59 / 14:02 | **网页在活动位**（…795） | 秒过；`Page.navigate` → `load=complete` |
| 14:41（v6） | 扩展管理页在活动位 | 先自动激活目标页（313ms）→ attach → `Page.navigate` 成功 |

⇒ **真规律**：海泰的 `chrome.debugger.attach` **只对"浏览器当前活动标签页"成功**；页面处于后台时
attach 挂起而不是报错。"毒标签页"是伪相关——同一个 tab 一变活动位立刻可用，从未真的坏过。
（v4 的"11s 自愈"那次也一样：它跳过的其实是后台页，选中是活动页。）

- **规律 ②（v5 起处理）**：附着会话在**切走活动位后失效**——真机 14:05 实录：SW 记着"已附着"（我们
  自己的 Set 缓存），但命令报 `Debugger is not attached to the tab with id: 1960785795`，之后每次
  navigate 全红。修法：命令报 not-attached ⇒ **清缓存 → detach 残留 → 重 attach → 重试一次**。
- **规律 ③（证伪项）**：`tabs.create` **点火不 await 也没有副作用**——14:08 点火后轮询 8s，
  没有任何新的 http(s) 标签页出现 ⇒ v6 撤掉该兜底，改为下面的"先激活后附着"。
- **v3 的修复（保留，都是净收益）**：attach 失败**不再吞**（旧写法在 catch 里写"already attached"
  注释就丢了真实原因）；CDP 命令失败时把 `attach 原文 + 命令原文` 一起抛；`scriptInTab()` 一次重试且
  失败带目标页 url；`toolTab()` 在活动页非 http(s) 时退到第一个网页标签页（旧版直接报
  `Cannot access a chrome:// URL`——trace 实录 `toolTab=1960785751:haitai://extensions/`）。
- **v6 的修复（本轮的落点）**：`navigate` 先把目标页**变成活动页**——`tabs.update` 的 promise
  同样永久挂起（docs/174 §3.1）**但确实有副作用**，所以**点火不 await + 轮询 `tabs.get(id).active`**
  （≤3s，实测 313ms 生效）；确认活动后才 attach。活动页本来就是网页时零额外成本；
  全失败则抛可行动文案（"请点开一个普通网页标签页、让它成为当前页"）。

**教训（写给下一次）**：单看"某 tab 不复现"会得出错误因果；判别实验必须控制"活动位"这个变量，
换 tab 时要把它切到前台再比。v4 的"多候选探测"因此保留为第二道兜底（前台候选优先，≤3 个）。

### 6.4 本轮产物与读数（beta 工作区）

| 项 | 读数 |
|---|---|
| 核心树 | `pack-core --place-in-app` → **+dshm.58**（40746 条目 / 94.9MB；resfile 与 dist sha256 **9424c73ede1f96d7…** 一致，`check-resfile-core-zip` ✅） |
| 装机 | `hvigorw assembleHap` BUILD SUCCESSFUL（需 `PATH` 加 `jbr\bin`，否则 `spawn java ENOENT`）→ `hdc install -r` ✅ → `aa force-stop`+`aa start` 冷启动 |
| 设备树 | `cores/0.2.1-alpha.4+dshm.58/` **唯一**；树内插件第 126/199/249 行已是 `(_args, value)`（逐行核对） |
| 门禁 | 仓库内 27 条口径全绿（含新增 `check-plugin-render-arity`；本轮逐条复跑，`assert-resfile-sync` 在打包后单独跑）；`check-permission-surface` 恒 8 条 ✅ |
| 扩展轨迹 | v1 `0.1.0`（初版）→ v2 `0.2.0`（alarms 心跳自愈）→ v3 `0.3.0`（attach 错误透传 + 注入重试 + toolTab 退网页标签）→ v4 `0.4.0`（多候选 try-attach）→ v5 `0.5.0`（陈旧附着自愈）→ **v6 `0.6.0`（先激活后附着）**；每版都换目录名（`-v2`…`-v6`，海泰解压扩展缓存，docs/174 §4.2） |
| 桥状态（终态） | `{"clients":[{"id":"ws_1","info":{"extensionVersion":"0.6.0","build":"dshm-host-bridge-6",…}}]}` —— 且这是**宿主整机重启后自动回连**的读数：fport 清空、宿主新 pid `24786`、标签页 id 换新，扩展没有人工干预就重连成功（v2 alarms 自愈的现场实证） |
| 工具面（模型侧实录） | 最终回（turn 6，用户："调用浏览器打开baidu.com"）：`browser_navigate` → `{"ok":true,"load":"complete","via":"cdp-pagenavigate"}`；`browser_status` → `ws_1: DSHM Browser Bridge v0.6.0`；`browser_text` → 百度首页正文；turn 完成。前一轮（turn 5）另有 `browser_tree`（`[ref_0] textbox …`）与 `browser_click` → `{"clicked":"ref_0","tag":"textarea"}`（scripting 通道）。桥面另测 `cdp_eval` → `document.title` = "百度一下，你就知道" |
| 宿主日志关键 trace（终态） | `activating tab 1960785911（点火 tabs.update + 轮询 active）` → `tab 1960785911 已激活`（313ms）→ `navigate target=1960785911` → `Page.navigate` 200（整条 3.6s） |
| 调试辅助 | `host-ready.json` 0666 ⇒ `hdc file recv` 可取新 token（宿主重启换 token；`/dshm-browser/status` 免 token、`/invoke` 要 token）；会话 zstd 多帧用 `dist/dbg-sessions/decode.mjs` 逐帧解（含 0 空洞检测） |

### 6.5 已验证 / 遗留

- **模型侧端到端：已验证**（见 §6.4 的模型侧实录）——`browser_status` 的 render 修复、`browser_navigate`
  的"先激活后附着"、`browser_text/tree/click` 全在真实会话里跑通。
- **海泰两条怪癖要写进正式化设计**（都实测过，不要当"应该不会发生"）：
  ①`chrome.debugger.attach` 只认活动标签页 + 会话随活动位切换失效 ⇒ navigate 必须"先激活"；
  ②`tabs.update` 的 promise 永久挂起但**副作用有效**（313ms 生效）——调用要"点火 + 轮询验证"，
  不能 await，也不能因为没有 resolve 就当没执行。
- **历史扩展目录**：设备 `<下载>/com.dshm.dshmbeta/` 下仍有 `poc-ext*`、`dshm-browser-ext`、`-v2`…`-v5`
  等调试遗留（v6 是当前生效版）；dev 侧 `dist/dbg-sessions/`、`dist/dbg-verify/` 是本轮调试脚手架
  （含会话 zstd 逐帧解码器与框架调用形状复现器），按用户口径决定去留（本轮未删）。
- **正式化（未做，沿用 §5）**：桥 token 动态化、扩展随包分发与升级引导（把"换目录名"做进流程）、
  与 WorkBuddy/Ultron 的调试器冲突协调、工具面扩展（截图 / 网络观测 / 视觉指示）。

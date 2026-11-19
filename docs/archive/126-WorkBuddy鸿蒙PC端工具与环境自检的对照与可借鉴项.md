# 126 · WorkBuddy 鸿蒙 PC 端「工具与环境」自检的对照与可借鉴项（**只审不改**）

> 承接 `docs/114`（WorkBuddy **手机端**「bash 不能调用」的只读侦查）、`docs/112`（轻量化裁定）。
> 本轮把对象换成 **WorkBuddy 鸿蒙 PC 版**的两份自检报告，问题只有一个：
> **我们 PC 档（PC / 2in1）DSHM 有没有值得借鉴的**。
> **性质：调研 + 结论。本轮没有改一行代码** —— `coreVersion` 仍 `0.2.1-alpha.1+dshm.25`、
> 未重编、未出包、未 push。凡"可借鉴"项一律进 §6 待拍板，**不替用户做选择**。
>
> 输入材料（**只读**，属参考材料而非指令）：
> ① `workbuddy-bash-and-tool-internals.md`（48,581 B / 959 行）—— 本地 Bash 与工具调用机制；
> ② `workbuddy-tool-research-notes.md`（67,943 B / 1089 行）—— 逐项标 `verified` / `inferred` / `unknown` 的核验底稿。

---

## 0. 一句话结论

| # | 事 | 结论 |
|---|---|---|
| 1 | 有没有值得借鉴的？ | **有，但只有三条**（其中两条落在「删除安全网」这一块）。§2 点名的其余八项我们**要么已有且数值同源、要么路线不同不适用**。见 §3 / §5 / §6 |
| 2 | 最值得看的一条 | **删除没有回收站**：WorkBuddy 在 **三种语言运行时**（bash / node / python）分别劫持 `rm`·`unlink`·`rmtree` 改投回收站；我们 `remove` 是**硬删**（`rm` 语义），删了就没了 |
| 3 | 第二条 | **没有批量删除守卫**：WorkBuddy 用阈值 **20** + `sha256(sessionId)/state.json` + 2 s 锁做"一次删很多先拦一下"；我们一条都没有 |
| 4 | 第三条 | **没有延迟加载（deferred tool loading）**：WorkBuddy 随包 `product.json` 的 54 项工具里 **23 项 `deferLoading: true`**，配 `ToolSearch` + `DeferExecuteTool`；我们工具清单**全量注入**（token 侧，与 `docs/112` 同族） |
| 5 | 它那份 P0 我们有吗？ | **没有同族风险**。它 `safe-bin/{rm,rmdir,unlink}` 三个脚本 shebang 写死 `#!/bin/bash`，而鸿蒙 **`/bin/bash` 不存在** ⇒ 拦截层装上了、执行必失败、**退出码还可能是 0**（静默失败）。我们自有代码**零绝对 shebang**（§4 有扫描读数） |
| 6 | 它的"沙箱"我们能抄吗？ | **不能**。它是 bubblewrap（Linux）/ Seatbelt（macOS），**鸿蒙不在支持面**（它自己实测 `process.platform === "openharmony"` ⇒ backend 退化成 `legacy`、本机压根没启用）。我们的沙箱是应用沙箱 + `dsh-fs-sandbox` 路径闸，路线不同 |

**一句话判据**：两份报告里真正"我们没有"的东西，全部落在 **「删除/破坏性动作的安全网」** 这一小块；
其余（超时、输出上限、进程组杀、权限档位、越权审批、结果提醒）**上游 dsh 已经有，且口径与我们一致**。

---

## 1. 对照口径（先说我拿什么比）

| 项 | WorkBuddy（鸿蒙 PC 版） | 我们（PC 档 DSHM） |
|---|---|---|
| 形态 | Electron 壳 + 内嵌 CLI 引擎（`app.asar.unpacked/cli/dist/codebuddy.js` ~22 MB） | ArkUI/Web 壳 + 随包核心树（上游 `dsh` + 端侧补丁） |
| 关系 | **宿主包住一个完整 CLI** | **改派上游实现**（注入补丁 + 自带插件） |
| `process.platform` | 它自报 `openharmony` | 同样 `ohos` / `openharmony` |
| 本轮可比的面 | 工具 schema、校验、权限、沙箱、后台任务、Skill/Agent、MCP/defer、结果回传 | 见 §2 逐条点名 |

> **证据等级沿用它的约定**：本文凡写"**已有**"的，都在本仓或核心树里**读到了坐标**；
> 凡写"**没有**"的，都做过**反向检索**（见 §7 的检索口令，可复现）。

---
## 2. 「我们已经有，且口径和它同源或更强」的逐条点名

> 核心树路径统一简写成 `@deepseek-ai/<包>/lib/index.js`（实际位于 `dist/core/work/dsh-core-<ver>/node_modules/`）。

| # | WorkBuddy 的做法（报告坐标） | 我们的对应物（本仓 / 核心树坐标） | 判定 |
|---|---|---|---|
| 2.1 | 超时 **120 s 默认 / 600 s 上限**；先 `onTimeout()` → `process.kill(-pid, SIGTERM)` 整个**进程组** → SIGKILL | `@deepseek-ai/dsh-bash-local/lib/index.js:71-73` `timeoutMs:12e4` / `maxTimeoutMs:6e5`；`@deepseek-ai/dsh-subprocess-local/lib/index.js:439` `process.kill(-child.pid, signal)` + `:493` `detached: true`；`dsh-bash-local:28` 的 `graceMs`（注释明写"matches OpenCode's 3s"）就是 SIGTERM→SIGKILL 宽限 | **同源，数值逐字相同**（120/600）。不借鉴 |
| 2.2 | 输出上限 30,000 字符 / 上限 150,000，超限**溢出到临时文件**（`OutputSpiller`） | `dsh-bash-local:73` `maxOutputBytes:64e3`（**64,000 字节**，比它宽 1 倍）；`@deepseek-ai/dsh-subprocess-local/lib/output.js` 做"有界尾部 + 私有时 spill 文件"（`privateSpillDir()` 0700 + 退出清理），注释与它 `OutputSpiller` 同构 | **已有，且更宽**。不借鉴 |
| 2.3 | 六档权限模式（`default`/`acceptEdits`/`auto`/`dontAsk`/`plan`/`bypassPermissions`）+ 隐藏第 7 档 `Delegate` | `@deepseek-ai/dsh-permission-presets/lib/index.js:107-179`：`workspace-write` / `danger-full-access` / `auto` / `custom`（+ 保留名不许占用）；`dsh-sandbox-policy` 的 `SANDBOX_MODES` | **同族**。命名不同，语义覆盖度相当 |
| 2.4 | 沙箱越权要二次审批（`dangerouslyDisableSandbox` + 逃生舱可用性开关） | `@deepseek-ai/dsh-tool-bash/lib/index.js:644` 走 `ctx.approval`：只有 `sandbox_permissions` **与** `justification` **同时给**才进 `approveBashEscalation`；`dsh-fs-sandbox:157,164` 的 `FS_SANDBOX_DENIED`（`read-only` 一律拒 / `workspace-write` 做**路径包含性**判定） | **同族**（这正是 Codex 侧 `sandbox_permissions: require_escalated` 的来源） |
| 2.5 | 工具结果可被改写 / 注入运行时提醒（`<system-reminder>` 178 处、`<task-notification>`） | `@deepseek-ai/dsh-repeat-tool-reminder`（重复工具提醒）；`@deepseek-ai/dsh-compaction-tool-result-pruner`（结果裁剪） | **同族**，机制名不同 |
| 2.6 | 两套校验（内置 zod / defer 走 ajv），失败把**期望 schema 回灌给模型** | 上游 `dsh-tool-*` 自带参数 schema + 错误序列化 | **同族**（我们不分 defer 通道，见 §3.3） |
| 2.7 | 命令构造用 `eval '<用户命令>'` 包一段 bootstrap | 我们**不做 eval**：`hostcore/plugins/dshm-vm-bash` 把 argv 逐个 `shq()` 后 exec（`docs/120` §脚本生成） | **我们更保守**（少了 `eval` 这一层注入面） |
| 2.8 | 平台感知的提示词渲染（Nunjucks `{% if platform %}`） | `hostcore/profile/ondevice/cordis.patch.yml` 的平台别名注入 + 端侧 profile | **同族** |

> 2.1 / 2.2 这两条值得单独记一笔：**"120 s / 600 s"完全撞上不是巧合** ——
> 上游 dsh 与 CodeBuddy 都是照着同一批公开产品（OpenCode 等）的常量抄的，
> 所以"对照竞品找差距"在这两块**注定找不到差距**。真正的差距只可能在**产品自选**的那几层。

---
## 3. 「我们真的没有」的三条（可借鉴项，逐条给落点 / 代价 / 风险）

### 3.1 删除没有回收站（**最值得看的一条**）

**它怎么做的**（报告 ①§四.8 / ①§四.9，`verified`）：

- **三条语言运行时通道同时挂**：
  - bash：`BASH_ENV` → `shell-runtime-bash-env.sh`，在 shell 里**定义 `rm()` / `unlink()` / `rmdir()` 函数**并 `export -f` 转发给 safe-bin；
  - node：`NODE_OPTIONS=--require node-language-shim.cjs` → 劫持 `fs.rm` / `unlink` / `rmdir` / `rmSync`；
  - python：`PYTHONPATH` → `sitecustomize.py` → patch `os.remove` / `shutil.rmtree` / `pathlib.Path.*` 等一整片；
- 落点由 **broker IPC**（Unix socket + JSON-line）决定：`try_trash` 优先走 broker，rc 2 降级到本地 trash，rc 1 = denied；最终 `genie-trash` 原生实现，再往下还有各平台降级链。
- 目标：**"删除"变成"移进回收站"**，用户可还原。

**我们现状**（`verified`，反向检索见 §7）：

- `hostcore/plugins/dshm-tool-fs-remove/lib/index.js:482` —— `remove` 工具直接 `rm(path, { recursive, force: false })`，**真删**；
- 同文件 `:90-93` 注释写得很直白：本插件**不做任何路径范围判断、不做任何确认/审批握手、不接 approval 服务**（`danger-full-access ⇒ approval: never`）；
- 全仓检索 `回收站|recycle|trash|genie-trash` 的命中**只有文档与注释**，没有实现。
- PC 档还叠一层：`shimRunnable()` 为真 ⇒ 模型能用**真 bash** 直接 `rm -rf`（连 `remove` 工具都不经过）。

**如果要做，落点有两个，代价天差地别**：

| 方案 | 落点 | 代价 | 风险 |
|---|---|---|---|
| A. 只在 `remove` 工具侧改投回收站 | `dshm-tool-fs-remove` 的 `remove()` 改成"同目录 `rename` 到 `<root>/.dshm-trash/<时间戳>-<原名>`" | 小：一个插件、一台已验门禁 | **只能盖住 `remove` 工具**，盖不住 `bash rm`；且回收站目录会出现在用户工作区里（可隐藏但仍在） |
| B. 学它做运行时拦截层 | `bash` 走 `BASH_ENV` + node 走 `--require` + python 走 `PYTHONPATH` | 大：三层各一份垫片，且 `BASH_ENV` 对**非交互 shell** 生效依赖调用方式、`--require` 会与 `jitless-env.cjs` / 假壳链打架 | 高：这三条通道我们**恰好都在用**（`jitless-env.cjs` 管 `NODE_OPTIONS` / `fetch-shim.js` / `internal-undici-shim.cjs`）。真动手前必须先证明**不破坏现有垫片顺序** |

> **我的判断（供拍板）**：A 是"值 / 险比"合理的那一档；B 的收益（覆盖 shell 原生 `rm`）在 **PC 档有审批面**（2.4）的情况下并不划算。
> 注意另一面：**用户的工作区本来就是用户自己的目录**，把"删文件"一律改成"进回收站"等于**替用户改变了文件系统的语义** ——
> 这与本项目一贯的「不替用户做选择」冲突，所以这条**必须由用户拍板**，不能默认做。

### 3.2 没有批量删除守卫

**它怎么做的**（报告 ①§四.9，`verified`）：决策链里有一道**批量守卫** —— 阈值 **20**；
状态落在 `<sha256(sessionId)>/state.json`；锁 2 s、stale 5 min；`-i` 一律 fail-closed；`tmp` 直通不拦。

**我们现状**：`verified`——**一条都没有**。删 1 个和删 10,000 个走的是同一条路（`rm(path, {recursive})`）。

**落点**：`dshm-tool-fs-remove` 的 `remove()` 开头做一次 `readdir` 计数（只在 `recursive===true` 时），
>20 个条目就要求模型显式带一个 `confirm: true` 参数（**不弹 UI**，纯工具契约层的"再问一次"）。

**代价**：极小（一个 `readdir` + 一个 schema 字段）。
**风险**：低但真实 —— 模型可能学会"习惯性带 `confirm: true`"，那就白做了；
按 workbuddy 的做法光靠阈值、靠**状态目录 + 锁**才能防"分几次删"。**是否要做同样交用户拍板。**

### 3.3 没有延迟加载（deferred tool loading）

**它怎么做的**（报告 ②§2.3 / §10，`verified`）：随包 `product.json` 的 `tools[]` 54 项（53 唯一名），
其中 **23 项 `deferLoading: true`**；一旦有 `Defer(...)` 就自动补 `ToolSearch` + `DeferExecuteTool` 两个工具；
优先级链 `NoDefer > Defer > MCP 工具级 > MCP 服务器级 > 环境变量 > 用户设置 > product.json`。

**我们现状**：`verified` —— 核心树里**没有** `defer` / `tool-search` 同名包；工具清单**全量注入**。

**要不要做**：**倾向不做，但记一笔**。理由：

1. 这是**上游 `dsh` 的契约面**（工具注册 / 提示词组装），我们改它等于改上游，与 `docs/112` 的"轻量化只动产物能力"是两回事；
2. 收益不确定：`docs/112` 已把**容器体积**压过一轮（81.3 → 56.3 MB），但那省的是磁盘不是 token；
   token 预算要靠工具数 × 描述长度来算，我们**没有实测数据**，不该拍脑袋改；
3. 真要减 token，**更便宜的杠杆**是砍 `dsh-tool-*` 的挂载面（端侧 profile 的 include 清单），
   而不是引入一套 defer 协议。

---
## 4. 它那份 P0 缺陷，我们有同族风险吗？—— **没有**

**它的缺陷**（报告 ①§四.10，`verified`）：`safe-bin/{rm,rmdir,unlink}` 三个脚本 shebang 全是 `#!/bin/bash`，
而 OpenHarmony 上 **`/bin/bash` 不存在**（真 bash 在 `libs/arm64/bash/bin/bash`，靠 PATH 提供）⇒
真机报 `bash: …/safe-bin/rm: /bin/bash: bad interpreter`，
**拦截层装上了、执行必然失败，而退出码可能仍是 0**（静默失败）。它的规避方式居然是用 `python3 -c "os.remove"` 绕过自家拦截器。

**我们的扫描读数**（本轮实跑，三档都扫）：

| 范围 | 结果 |
|---|---|
| **本仓自有代码**（tracked，全树） | `#!/usr/bin/env node` 31 · `#!/usr/bin/env bash` 21 · `#!/usr/bin/env python3` 2 —— **零条绝对解释器路径** |
| **非 tracked 的产物/源码树**（`hostcore` / `entry` / `tools` / `dist` / `platform` / `dshcompat` …） | 有 `#!/bin/sh` / `#!/bin/bash`，但**全部落在两个地方**：① 上游 npm 包的 `.bin/*` 垫片（端侧装备了假壳，这些垫片根本不执行）；② `node-pty/deps/winpty/**` 的构建脚本（Windows 专用，端侧永不执行）。`dist/_net5.sh` 是测试残留 |
| **核心树里 `.sh` 的绝对 shebang**（R4） | **零命中** |

**结论**：这条 P0 的成因是"**自己手写脚本时把解释器写死成绝对路径**"。我们的纪律（`AGENTS.md` 的「所有沙箱内 ELF 必须构建期自签名」同族）在**生成期**就把垫片的解释器写成变量：
`hostcore/app/main.js:1892` 的 `bashShimLines(binDir)` 返回 `#!${ashi}`（形①，用随包的 ash 副本）或
`#!${BASH_SHIM_SYSTEM_SHELL}`（形②，`/system/bin/sh`），**形态在生成期选定**，不是硬编码。
这条**记进踩坑总览即可，不需要改代码**。

---

## 5. 明确判定「不采纳 / 不适用」

| 项 | 它的情况 | 为什么我们不采纳 |
|---|---|---|
| **bubblewrap / Seatbelt 沙箱** | `sandbox-cli-linux/macos`，Windows 都没有；它自己实测鸿蒙 `process.platform==="openharmony"` ⇒ `resolveSandboxBackendForHost()` 返回 `legacy`，**本机压根没启用** | 鸿蒙无对应系统调用面；我们的沙箱是"应用沙箱 + `dsh-fs-sandbox` 路径闸 + bash 层 `sandbox_permissions`"，**已是这个平台上能做到的那一层** |
| **`getcwd()` 噪声**（它每条 bash 结果都带 `shell-init: error retrieving current directory`） | 它的**宿主 `getcwd()` 失败**（不是工具错）——这是它 Electron 壳的现场，会污染模型上下文 | 我们的 `dsh-bash-local` 明确把 `cwd: spec.workdir` 钉进 spawn spec（`:114`），**结构性不产生这条噪声**。前提是工作区存在——用户删掉工作区是另一回事，不加防御 |
| **`eval '<用户命令>'` 式命令构造** | 它拼 `env … && eval '<cmd>'` | 我们**特意不做**（`dshm-vm-bash` 逐个 `shq()` + exec）。**保持现状** |
| **权限规则的前缀匹配 + `&&` / `\|\|` / `;` / `\|` 感知** | 它 `Bash(npm run test:*)` 明确**不**放行 `safe-cmd && other-cmd`，并自己列了 5 种绕过方式 | 我们的授权面是**沙箱档位 + 路径包含性 + 越权审批**（见 2.3 / 2.4），不是"命令前缀白名单"。**这不是缺口，是两种模型**。真要抄它的思路会引入"看起来安全实际可绕"的假安全感 |
| **MCP 工具命名 / defer 优先级链** | 它一整套 `mcp__<server>__<tool>` + `defer_loading` 三级覆盖 | 我们端侧 profile 的 MCP 面尚未铺开，**现在抄等于给不存在的消费者写代码** |
| **后台任务（`run_in_background` / `Ctrl+B` / `<task-notification>`）** | 它一整套 | 我们有 `dsh-tool-jobs` / `dsh-tool-schedule`（上游的作业面）；且端侧"真后台"要过鸿蒙的后台限制，**不是本仓能单方面决定的** |

---

## 6. 待用户拍板（**本轮一律没动**）

| # | 候选 | 落点 | 代价 | 险 | 建议 |
|---|---|---|---|---|---|
| **P1** | `remove` 工具改投回收站（§3.1 方案 A） | `hostcore/plugins/dshm-tool-fs-remove/lib/index.js` | 小 | 中（改变了工作区文件系统语义；回收站目录落在用户目录里） | **先问清楚想要哪种语义**再动 |
| **P2** | 批量删除守卫，阈值 20（§3.2） | 同上 | 极小 | 低（可能被模型"习惯性带 confirm"绕过） | 可做，但要配一条"分次删也要拦"的状态 |
| **P3** | 运行时拦截层（§3.1 方案 B） | `BASH_ENV` / `NODE_OPTIONS --require` / `PYTHONPATH` | 大 | **高**（与 `jitless-env.cjs` / `fetch-shim.js` / `internal-undici-shim.cjs` 打架） | **不建议**，除非 P1/P2 都不够 |
| **P4** | 延迟加载 / 工具面收窄（§3.3） | 端侧 profile 的 include 清单 | 中 | 中 | 先出**实测 token 读数**再谈 |
| **P5** | 把本章的"删除安全网"结论写进 `docs/70` 踩坑总览 | `docs/70` | 0 | 0 | 可随时做 |

---
## 7. 复现口令与本轮读数（**只读**，可复跑）

```powershell
# R1 —— 我们有没有回收站实现（排除文档/产物/第三方）
git grep -n -I -i -E '回收站|genie-trash|recycle' -- ':!docs' ':!*.md' ':!dist'     # → 零命中

# R2 —— 我们有没有批量删除守卫
git grep -n -I -E 'bulkDelete|deleteGuard|批量删除' -- .                            # → 零命中

# R3 —— 核心树有没有 defer / tool-search
Get-ChildItem -Directory -Name dist/core/work/dsh-core-*/node_modules/@deepseek-ai |
  Where-Object { $_ -match 'defer|tool-search' }                                    # → 零命中

# R4 —— 核心树 .sh 里有没有绝对 /bin/bash|/bin/sh shebang（PowerShell）
Get-ChildItem dist/core/work/dsh-core-*/node_modules -Recurse -File -Filter *.sh |
  ForEach-Object { $f = Get-Content -LiteralPath $_.FullName -TotalCount 1
                   if ($f -match '^#! */bin/(bash|sh)') { $_.FullName } }   # → 零命中
# 注：不带 -Filter 的全树扫描**会**命中上游 `.bin/*` 垫片与 winpty 构建脚本，
#     但那两类端侧都不执行（见 §4 表第二行）——"零命中"只对 .sh 成立。

# R5 —— 自有代码 shebang 全表
git grep -n -I -E '^#! */[a-zA-Z0-9_./-]+' -- .
```

| 读数 | 值 |
|---|---|
| `coreVersion` | `0.2.1-alpha.1+dshm.25`（**未动**） |
| 本轮文件改动 | 新增 `docs/126-*.md`；`docs/README.md` 索引 +1 行、标题区间改 `95–126` |
| 本轮代码改动 | **无**（未改 `hostcore/**`、未改核心树、未升 `coreVersion`、未重编、未出包） |
| 需不需要跑门禁 | **不需要**（没有代码改动）；若后续动 P1/P2，按 `AGENTS.md` 走：改 `hostcore/**` ⇒ `node tools/place-host-app.mjs` + `node tools/assert-resfile-sync.mjs`；动核心树 ⇒ 升 `coreVersion` + `node tools/pack-core.mjs --place-in-app` |

### 已知遗留（不在本轮范围，转给后续）

- 本会话的沙箱策略**禁止删除**，所以上一轮登记的清理项仍在：
  `dist/core/dsh-core-…+dshm.24*.zip` / `dist/core/work/dsh-core-…+dshm.24` / `entry/.cxx`（**三样必须一起清**）+ `D:\temp\dshm-r43` + `%TEMP%\dshm-*`。
- 手持档终端冷启动仍是 12.4 s；预热开关 `DSHM_VM_BASH=warm` 是否默认打开**仍待拍板**（`docs/125` §4）。

---

## 8. 一句话收尾

两份报告**值得看完**，但结论比"照抄"更省事：
**它花大力气建的"删除安全网"（三条运行时拦截 + 回收站 + 批量守卫）是我们唯一真缺的一块**，
而那块**恰恰是最不能照抄的** —— 它替用户改了文件系统语义，我们还必须先把"要不要改"问清楚。
其余每一项，我们**要么已经有了（且 120/600 这种数值是逐字相同）、要么平台的物理约束让它无从谈起**。
# 372 · 升级 Node 前那批修复的回归验证（七项）与三端处置

> 日期：2026-11-05 ｜ 背景：以下七项都是**升级 libnode 24.9 / 换核心 `0.2.2-rc.1` 之前**做的修改，
> 对应一批用户反馈；换库换核之后必须逐项复验是否还成立。
> 复核对象：应用 1.1.7 / `1010014` + 核心 `0.2.2-rc.1+dshm.1` + libnode `24.9.0`（sha `dfe298d0…`）
> 性质：**复验 + 修复**；改动只落在 `hostcore/app/main.js` 与一个新门禁上，未碰权限面

---

## 0. 结论

| # | 项 | 复验结论 | 依据 |
|---|---|---|---|
| 1 | 手机端插件安装 | **结构仍在，未随换核失效** | 安装器仍在 Host 侧（`dshm-installer.js` 支持 npm / github: / alias）；`bin/{dsh,npm,pnpm}` 假壳与 `lib/bin.js` 入口在 0.2.2 树里仍成立（`bin.dsh = lib/bin.js` 实读） |
| 2 | 云服务同步报错 | **未修，且与换核无关** | 全仓无 `DISTRIBUTED_DATASYNC`（源码 + `phone/module.json5` 9 条都无）；登录态仍只存内存 |
| 3 | Node 环境调用有问题 | **仍有效**（换库后未回归） | `nodecli` 候选路径 `libnode.so.137` 与新件同名；随包件 `155,413,312 B` 带 `.codesign`；`@deepseek-ai/dsh@0.2.2-rc.1` 的 `engines.node = ">=24.9.0"` 被满足 |
| 4 | 任务完成后提示音 | **仍有效，且双响已收敛** | `platform/.../DoneSound.ets` 在位并 `EntryAbility:2543` attach；`1770/1775` 有 `done-sound: play/skip` 诊断，play 只在通知未发出时执行 |
| 5 | 状态栏托盘图标白底 | **无法验证（缺截图）**；但实现与 SDK 语义有偏差 | `StatusBarTray.ets:97-99` 把**彩色**图同时当 `white`/`black` 传；SDK 注释写明 `white` 用于深色壁纸、推荐纯白 |
| 6 | 平板端后台状态栏沉浸 | **仍有效** | `WebApp.ets:3799` 起「平板沉浸式状态栏（2026-11-04）」；`isHandheldForm()` 覆盖 PHONE/TABLET，PC 档不变 |
| 7 | 平板无法后台任务 | **发现真缺陷并已修** | Host 的 `workload.json` 判据读的是**不存在的键**（`card.running` / `card.turnActive`），`turnRunning` 恒 0 ⇒ `refs` 只剩安装队列 ⇒ 熄屏判"无诉求"。已改为认 `session.state === 'running'`，并新增门禁 |

一句话：**七项里六项没被换库换核碰坏**（第 2 项本来就未修），**第 7 项挖出一个一直在静默失效的判据**，本轮已修并加锁。

---

## 1. 逐项复验

### 1.1 手机端插件安装 — 结构仍在

- 安装串解析在 Host（`hostcore/app/dshm-installer.js`）：支持 `npm`（含 `dist.integrity`/`shasum` 校验）、`github:owner/repo`（含 `#path:`/`#commit` 子目录形态）、`npm:` 别名；**不支持** `link:` / `file:`（`docs/351` 已登记，非本轮引入）。
- 换核后的关键前提仍成立：`@deepseek-ai/dsh` 的 `bin.dsh` 仍是 `lib/bin.js`，文件在容器里；`bin/dsh` 假壳按「脚本自身位置 → `<sandbox>/dsh/cores`」运行时解析核心目录，不再写死版本。
- 门禁：`check-installer-integrity`、`check-install-spec-normalize`、`check-cli-shim-semantics`、`check-market-bridge`（142 项）全绿。
- **未证实的部分**：客户反馈里"装完插件页面出不来"（#2）与"装不上 dsh-better-sidebar"（#15）都缺附件，无法确认是否与本链有关。

### 1.2 云服务同步报错 — 未修

- 结构性缺口没变：`phone/src/main/module.json5` 的 9 条权限里没有 `DISTRIBUTED_DATASYNC`，源码里也搜不到该串 ⇒ `setDistributedTables(DISTRIBUTED_CLOUD)` 必然失败。
- 登录态仍只存内存（`preferences/` 下只有 `dsh_folder_grants` 与 `dsh_host_state`）。
- 与换库换核**无关**：这两条是产品/权限面问题，换 Node 既不会修好也不会修坏。

### 1.3 Node 环境调用 — 换库后未回归

| 检查 | 结果 |
|---|---|
| `nodecli` 找库名 | `libnode.so.137`（`nodecli.c:146`），与新件同名 ✔ |
| 随包 libnode | `155,413,312 B` / sha `dfe298d0…`，ELF 有 `.codesign`(4096 B) ✔ |
| 版本门槛 | `@deepseek-ai/dsh@0.2.2-rc.1` 要求 `>=24.9.0`，随包 24.9.0 ✔ |
| 启动器 | `main.js` 的 `ensureBundledNodeCli()` 在 `installElfLaunchers()` **之后**再装一次（`docs/360` 的修复），当前代码顺序仍在 ✔ |
| jitless 垫片链 | `check-fetch-shim` / `check-undici-shim-exports` / `check-worker-jitless` / `check-internal-undici` / `check-web-fetch-jitless` / `check-ptc-*` 全绿 ✔ |

### 1.4 任务完成后提示音 — 仍有效

- 实现：`platform/src/main/ets/notify/DoneSound.ets`（`diag-done-sound` 落盘），`EntryAbility.ets:2543` attach。
- 双响治理（`docs/360`）：两处 `doneSound.play()` 都带前置判断，且只在 `id <= 0`（通知没发出）时播；`1770/1775` 分别打 `done-sound: play/skip` 诊断行。
- 结论：**换核不影响**（纯 ArkTS 音频，不经 Node）。

### 1.5 状态栏托盘图标白底 — 缺证据，且实现与 SDK 建议不一致

- 资产本身没问题：`tray_color.png`(96×96)、`tray_white.png`(72×72)、`tray_black.png`(72×72) 都是 RGBA、四角透明、无"不透明白底"（实测：`tray_color` 透明 69.6%、不透明白 0.0%）。
- 实现问题：`StatusBarTray.ets:97-99` 把**彩色**图同时塞给 `white` 与 `black` 两个槽；而 SDK 原文是 `white` = 深色壁纸用、推荐**纯白**；`black` 同理推荐纯黑。给彩色图时系统可能自行单色化/加底板，观感就是"白底"。
- **未能定论**：缺用户截图，无法区分"系统加底板"与"图标被单色化"。
- 处置建议（**未动手**，见 §3）：
  - 方案 A（最小、符合 SDK）：`white` 槽用 `tray_white.png` 纯白剪影，`black` 槽保留彩色；
  - 方案 B：两槽都用单色剪影，彻底放弃彩色；
  - 无论哪个都需要一张真机截图确认现状，否则改完可能"从一个错误换成另一个错误"。

### 1.6 平板端后台状态栏沉浸 — 仍有效

- `WebApp.ets:3799` 起是「顶部状态栏避让高度 —— 平板沉浸式状态栏（2026-11-04，用户需求）」，与底部手势区沉浸（`:3791`）成对。
- 生效条件用 `isHandheldForm()`（PHONE / TABLET 为真），PC/2in1 分支一个字节不变 —— 与 `docs/360` 的口径一致。
- 结论：**换核不影响**（纯 ArkTS/Web 层样式）。

### 1.7 平板无法后台任务 — **发现真缺陷，已修**

**缺陷**（`hostcore/app/main.js:892-897`，改前）：

```js
const card = JSON.parse(fs.readFileSync(...'card-state.json'));
turnRunning = (card && (card.running === true || card.turnActive === true)) ? 1 : 0;
const refs = turnRunning + pending;
```

而 `card-state.json` 的**真实形状**（由同文件 `registerCardState()` 写出）是：

```js
{ updatedAt, session: { sessionId, title, state, turn, step }, balance, usage }
// state ∈ idle | running | done | error
```

`running` / `turnActive` 这两个**顶层键从来没被任何写入方产生过** ⇒ `turnRunning` 恒为 0 ⇒ `refs` 只剩"在途安装数"。

**后果链**：ArkTS `EntryAbility.workloadRefs()` 读到的 `workloadRefs=0` → `maybeAcquireHandheldKeepAlive()` 的 `busy` 少算了"turn 正在跑"这一项 → 若此刻又没有界面投影（`running/pending/streams/outbox`）→ 判"无保活诉求" → 不申请长时任务 → 熄屏/切后台即被系统冻结。**这正是客户反馈「熄屏后无法运行」「平板无法后台任务」的宿主侧一半原因**（另一半是 `KeepAlive.noteScreenState()` 的 `refs>0||active` 判据）。

**修复**（本轮已落地）：

```js
const sess = card && card.session ? card.session : null;
const running = (card && (card.running === true || card.turnActive === true))
  || (sess && sess.state === 'running');
turnRunning = running ? 1 : 0;
```

- 兼容历史两键，同时认当前真实字段；
- 不采用 `turn > 0` 作判据（`done`/`error` 之后 `turn` 仍保留上一轮值，会假阳性）。

**新增门禁**：`tools/check-workload-refs.mjs`（已进 `gates.yml`，含 `--self-test`）
判据三条：① 必须认 `session.state === 'running'`；② 必须保留历史键兼容；③ `refs` 必须等于 `turnRunning + pending` 且 `turnRunning` 由判据赋值。
自检 3 个变异体（删判据 / 常量赋值 / `refs` 置 0）全部判红 —— 门禁有牙。

---

## 2. 本轮改动清单

| 文件 | 改动 | 三端影响 |
|---|---|---|
| `hostcore/app/main.js` | workload 判据认 `session.state === 'running'`（+ 注释写明来龙去脉与反例） | **共享 Host**，`entry` / `phone` / `hostruntime` 三端同源生效；已 `place-host-app` 同步到 resfile 快照 |
| `tools/check-workload-refs.mjs`（新增） | 上述判据的门禁 + 3 个自检变异体 | CI |
| `.github/workflows/gates.yml` | 加 `check-workload-refs` 与它的 `--self-test` 两步 | CI |

验证：

```
node tools/check-workload-refs.mjs            → ✅ 通过
node tools/check-workload-refs.mjs --self-test → ✅ 3/3 变异体判红
node tools/assert-resfile-sync.mjs            → 22 件快照全部同步
全量回归                                        → 见 dist/acceptance/20261105-post-workload-fix.txt
```

> **关于"三端"**：Host 的 `main.js` 只有一份（`hostcore/app/` → resfile 快照 → `hostruntime` 的 HSP），`entry` 与 `phone` 共用同一份，所以这一处改动天然三端一致。ArkTS 侧的保活接线由 `check-keepalive-wiring`（entry / phone 两个壳层）单独钉住，本次未改动 ArkTS。

---

## 3. 仍需处理（按优先级）

| 优先级 | 项 | 要做什么 | 依赖 |
|---|---|---|---|
| **P0** | 熄屏保活的**另一半**（`KeepAlive.noteScreenState`） | 熄屏时 `refs=0 && !active` 直接跳过；应改为"允许在后台任务启动时 acquire"，或熄屏即无条件申请 `TASK_KEEPING` | 需真机（本机无 hdc） |
| **P0** | 云同步（#13/#18/#19） | ① 申请 `DISTRIBUTED_DATASYNC`（权限面变更，需 ACL + Profile）；② 登录态落盘；③ AGC 云侧核对 | ① 外部周期 1–2 周 |
| **P1** | 托盘图标白底 | 先要一张真机截图；确认后再按 SDK 语义改 `white`/`black` 两槽 | 截图 |
| **P1** | 平板沉浸的**顶部避让值**是否与三键/状态栏实际高度一致 | 真机量一次 `inset`，与 `3799` 的 vp 值对账 | 真机 |
| **P2** | 插件安装 `link:`/`file:` 分支 | 若产品需要本地目录安装，补 `resolveSpec` 两个分支 | 需求确认 |

---

## 4. 风险与验证方法

1. **`turnRunning` 从恒 0 变成会为 1**，会让手持档在"turn 在跑"时更积极地申请长时任务 —— 可能出现"后台多一条通知"。这是设计意图（`docs/326`），但要真机确认通知文案与频次可接受。
2. **反向风险**：若 `card-state.json` 因故停在 `state='running'`（异常退出没写 done），`refs` 会一直为 1 ⇒ 长时任务不释放。缓解：`KeepAlive` 侧有 `backgroundWanted` 与回前台 `release()`；另建议后续给 `card-state` 加"心跳过期"判断（超过 N 分钟未更新视为 idle），本轮未做。
3. **验证方法（有设备时）**：跑一个长 turn → 锁屏 5 分钟 → 亮屏看 `node-output.log` 是否还有 `LOOP-GAP`；同时看 `diag-keepalive` 里 `need` 行的 `workloadRefs=` 是否为 1、是否出现 `申请保活成功`。

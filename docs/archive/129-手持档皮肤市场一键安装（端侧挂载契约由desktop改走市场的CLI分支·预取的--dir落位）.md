# 129 · 手持档皮肤市场「一键安装」（端侧的市场挂载契约由 desktop 改走市场自己的 CLI 分支）

> 用户原话：「点开皮肤市场原本在PC端正常的安装按钮，手机端是需手动安装，我需要的是实现一样的功能」。
> 承接 `docs/125`（把市场的托管安装入口 `installPlugin` 补上）与 `docs/128`（点「使用」→ 重启链）。
> **性质：自带插件 `dshm-market-bridge` 一处新增能力（改市场的挂载契约）+ 一处落位口径修复（预取的 `--dir`）**，
> 外加门禁 `tools/check-market-bridge.mjs` 的两节（J/K）⇒ `coreVersion` 升 **`+dshm.28`**。
> 真机：手机 `62T0225B18039433`（`const.product.devicetype=phone`），覆盖安装（`hdc install -r`），
> home 指纹 `links=8 size=3440` 装前装后一致。

---

## 0. 一句话结论

| # | 事 | 结论 |
|---|---|---|
| 1 | 手机端为什么是「需手动安装」 | 市场的**界面判定只有一个公式**：`hostKind === 'desktop' ? skin.install.desktop?.mode !== 'managed' : skin.review?.installation === 'manual-only'`。端侧因为我们的宿主桥给市场提供了 `desktopProfiles`，被判成 `hostKind='desktop'` ⇒ 只剩「官方 Desktop 托管」那 41 条可装；而目录里 **204 条 `review.installation=verified` 被 `install.desktop.mode=manual-only` 挡在门外**。见 §1 |
| 2 | 为什么 PC 端是好的 | PC 档我们的随包假壳可 `spawn` ⇒ 桥**整条惰性**（既不 provide 也不打补丁）⇒ 市场走它自己的 CLI 分支 ⇒ `hostKind='dsh'` ⇒ 用 `review.installation` 判定 ⇒ 一键装。**同一个缺陷在 PC 上根本不出现**，所以它只可能是端侧的挂载契约问题。见 §1.2 |
| 3 | 修法 | 对**已安装**的 `dsh-skin-market` 就地改写 desktop 分支那一行：`hostKind: 'desktop'` → `'dsh'`，并把 CLI 分支同款的 `restart` 补上（`restart` 是 `mountRoutes` 的独立入参，**不由 `hostKind` 推出**）。幂等、锚点唯一才写、任何一条判据不中 ⇒ 一个字节都不写。见 §2/§4 |
| 4 | 为什么不改市场目录（catalog） | `manual-only` 里那句 `reason=npm-package-not-found` 是**上游审核的真话**：它说的是「**Desktop 的托管安装**找不到已核验的 npm 制品」。我们换的是**宿主形态**，不是替市场改口 —— 端侧确实没有 Desktop 那套 npm 托管器，但有一条能跑 pnpm 装卸契约的**进程内通道**。见 §2.2 |
| 5 | 顺带修掉的第二个缺陷 | 市场的 `prefetch()` 发的是 `add <target> --dir <临时目录> --ignore-scripts`（先在**没被监视的临时项目**里解析下载、校验通过才落 live profile）；桥原来只认 profileDir ⇒ **预取直接装进 live profile、而临时目录是空的** ⇒ 市场读不到 manifest（`installed package manifest missing`）+ 包/依赖/插件行全部泄漏。见 §3 |
| 6 | 门禁 | `check-market-bridge` **87/87**（J 节：改写 + 幂等 + **上一代补丁的就地升级** + 三条负向臂；K 节：`--dir` 口径 7 条 + 预取端到端 3 条）。**本轮自己先踩了一个坑**：正则尾部写成 `\n$` ⇒ 单行能中、真文件里必不中 ⇒ J 节先红 11 条，去掉 `$` 才全绿。见 §5 |
| 7 | 真机状态 | **端到端已验**：冷启动后 `dsh/cores` = `+dshm.28`、日志 `皮肤市场挂载契约改写：已从上一代补丁升级（hostKind 'dsh' + restart）`、`GET /dsh-skin-market/state` 回 `hostKind="dsh"`；两条「`verified` + `desktop.mode=manual-only`」的皮肤（纯 GitHub 的 `denia`、多包仓库 `&path:` 的 `maid-whale-webui`）**都一键装成功**（`installation=installed`，profile 里记的是 GitHub 原样 spec）。见 §6 |

---

## 1. 缺陷 A：手机端为什么只剩「需手动安装」

### 1.1 判定公式只有一处，且只看 `hostKind`

`dsh-skin-market/client/client.js:1967`：

```js
const isManualOnly = (skin) => hostKind === "desktop"
  ? skin.install.desktop?.mode !== "managed"
  : skin.review?.installation === "manual-only";
```

`hostKind` 由服务端下发（`routes.js:59` 与 `lifecycle.js:136` 是同一句回落：`options.hostKind ?? options.runner.hostKind ?? 'dsh'`）。
另外两处用它挑文案（`client.js:1969-1971` 的 `manualInstallNotice` / `manualHealthNotice`），还有一处用它开「换用 npm」（`client.js:2418`）。

### 1.2 端侧为什么落到 `desktop` 分支

市场 `lib/index.js`（设备上那份：`profiles/ondevice/node_modules/dsh-skin-market/lib/index.js`）：

```js
const officialDesktop = configuredProfile?.toLowerCase() === 'desktop'                            // ①
  || (configuredProfile === undefined && launchedProfile?.toLowerCase() === 'desktop')            // ②
  || (desktopProfiles === undefined && pluginManager !== undefined);                              // ③
```

- 端侧 `core-recipe.json` 的 `profile` 是 **`ondevice`** ⇒ `configuredProfile=undefined`、`launchedProfile='ondevice'` ⇒ ① ② 假；
- 我们的宿主桥**故意** `provide('desktopProfiles')`（手持档的进程内包通道要它，见 `docs/107`）⇒ ③ 也假；
- ⇒ `officialDesktop=false` ⇒ 跳过官方 Desktop 分支；紧接着 `if (desktopProfiles === undefined)` 同样为假 ⇒ **落到最后那条 desktop 分支**，`hostKind: 'desktop'` 就此写死。

服务端还会在同一处**第二次**拦住（`lifecycle.js` 的 `begin()`）：

```js
if (this.hostKind === 'desktop' && skin.install.desktop?.mode !== 'managed')
  throw new Error(desktopInstallError(skin.install.desktop));
if (this.hostKind !== 'desktop' && skin.review?.installation === 'manual-only')
  throw new Error('该皮肤尚未满足市场自动安装所需信息，请查看仓库安装说明');
```

⇒ 「界面说需手动安装」与「真点了也被拒」是**同一处判据**的两个投影。

**PC 档为什么没这问题**：PC 上 `shimRunnable()` 为真 ⇒ 桥在 `provideMarketBridge()` 里第一道闸就 `return false`（`hostcore/plugins/dshm-market-bridge/lib/index.js:664-667`）⇒ **没有 `desktopProfiles` 服务** ⇒ 市场自然走 `desktopProfiles === undefined` 那条 CLI 分支 ⇒ `hostKind='dsh'`。同一条公式在 PC 上给出的是**正确**答案。

### 1.3 目录实测（远端新鲜目录 302 条）

| 口径 | 分布 |
|---|---|
| `install.desktop.mode` | `manual-only` **247** / 无该字段 **14** / `managed` **41** |
| `review.installation` | `verified` **251** / `manual-only` 50 / 缺失 1 |
| **两者交叉** | `review=verified` **且** `desktop.mode=manual-only`：**204** |

⇒ 改走 CLI 分支后，可一键装的条数从 **41 → 252**（`review?.installation !== 'manual-only'`）。
用户点开看到的那两条正是交叉集里的样本：

| id | `review.installation` | `install.desktop` | `reason` |
|---|---|---|---|
| `yunxiiqwq.maid-whale-webui` | `verified` | `manual-only` | `npm-package-not-found` |
| `ewnscat-ya.dsh-client-ui-skin-denia` | `verified` | `manual-only` | `npm-package-not-found` |

两条的 `install.target` 都是 GitHub 形态（`github:…/…#<sha>`、`…&path:/maid-whale-webui`）—— 端侧的安装器**本来就吃这一形态**（`docs/110` / `docs/125`，`installedSpecMatches()` 按 `spec.includes(skin.install.commit)` 认账）⇒ 卡住它们的**不是能力，是那一行 `hostKind`**。

## 2. 修法

### 2.1 目标形态（改前 → 改后，逐字）

改前（设备现场那份，已带上一代补丁）：

```js
            const desktopHost = desktopContext;
            /* dshm-market-bridge: desktop-restart */ const appExit = readService('appExit');
            const restart = appExit === undefined ? undefined : createCliRestartScheduler(appExit);
            desktopHost.effect(() => mountRoutes(host, { profile: current.name, profileDir: current.dir, runner: desktopRunner(service, current.dir), hostKind: 'desktop', runtime: detectDshRuntime(), agents, restart }), 'dsh-skin-market: desktop routes');
```

改后：

```js
            const desktopHost = desktopContext;
            /* dshm-market-bridge: cli-branch */ const appExit = readService('appExit');
            const restart = appExit === undefined ? undefined : createCliRestartScheduler(appExit);
            desktopHost.effect(() => mountRoutes(host, { profile: current.name, profileDir: current.dir, runner: desktopRunner(service, current.dir), hostKind: 'dsh', runtime: detectDshRuntime(), agents, restart }), 'dsh-skin-market: desktop routes');
```

只动两点：`hostKind` 由 `'desktop'` 改 `'dsh'`、补上 `restart`（与 CLI 分支逐字同形）。`runner` **保持 `desktopRunner(service, current.dir)`** —— 它才是通往我们进程内队列的那条路（`commands.js:451-465`：`service.runPlugin` / `service.installPlugin` ⇒ 队列 `.req`/`.rem`）。

### 2.2 为什么这不是"自造的缝"

- `desktopProfiles` + `desktopPnpm` 是**上游明文契约**（`desktopRunner`、`desktopProfiles.current` 都在上游代码里）；我们只是**提供了它们**。
- `hostKind` 同样是上游入参，且它只决定「按哪套来源判定 + 用哪套文案」，**不改变 `runner` 是谁**。
- 端侧的进程内通道**确实覆盖** pnpm 装卸契约：`add <spec>` 既吃 `name@version`，也吃 `github:o/r#sha[&path:/sub]`（`hostcore/app/dshm-installer.js`）；装完 `installedSpecMatches()` 认 GitHub 形态原样记录的 spec。
- **不改 catalog**：`manual-only` 是市场对自己审核结论的如实陈述，改它等于替市场改口。

### 2.3 为什么不能改成「不 provide `desktopProfiles`」

那条路会让市场落到 CLI 分支，`runner` 变成 `runPluginCli` —— 它**要 spawn `bin/pnpm`**，而手持档**没有可用的 spawn 链路**（`docs/104` / `docs/110` 已判决）。结果是「按钮能点了，一点就失败」。所以「provide 桥 + hostKind 归位」是唯一能同时满足**界面判定**与**执行路径**的组合。

## 3. 缺陷 B：预取的 `--dir` 落位

`lifecycle.js` 的 `prefetch()`（947 起）：

```js
let directory = mkdtempSync(join(tmpdir(), 'dsh-skin-market-download-'));
this.preparePrefetchDirectory(directory, ...);
await this.run(['add', target, '--dir', directory, '--ignore-scripts', ...], operation);
```

它的注释写得很清楚：**先在没被监视的临时项目里解析下载、校验通过才落 live profile**（免得一个大 GitHub 下载在途中就改了 live profile，让 DSH Web 提前 reload）。

桥原来只认「宿主 profile 目录」⇒ 预取那一步**直接写进 live profile**，而临时目录里空着 ⇒ 紧接着 `validateInstalledSkin(directory, …)` 失败（`installed package manifest missing`），同时 profile 里已经留下包/依赖/插件行 —— 与 `bin/pnpm` 假壳踩过的「报告 7 §1a」是同一个坑。

修法（新增 `targetDirFromArgv()`）：按 **argv 的 `--dir`（`--dir <v>` 与 `--dir=<v>` 两种写法）> 宿主 profile** 取落位目录；相对路径按 profileDir 归一；`--dir` 后没跟值、或值为 `/` 时不采纳 —— 与 `bin/pnpm` 假壳的 `shimDirResolveLines()` **同优先级**。`.req` 旁边那份 `.dir` 现在写的是市场要的那个临时目录。

> 顺带一条：`marketTargets()` 的 `VALUE_OPTS = ["--dir", "--profile"]` 会把 `--dir` 的**值**一起吞掉，所以 `--dir <绝对路径>` 不会被误当成包名投进队列（K7a/K7b 验的就是这条）。

## 4. 幂等与升级路径

判据（**全中才写**）：

1. 文件在 `<profileDir>/node_modules/dsh-skin-market/lib/index.js`（读不到 = 没装 ⇒ 跳过，**不造文件**）；
2. 锚点 `            const desktopHost = desktopContext;` 恰好命中 **1** 次；
3. 紧随其后那一行 `desktopHost.effect(…)` 恰好命中 **1** 次，且它**紧贴**锚点（或只隔着**上一代补丁的整段**）—— 中间出现任何别的东西 ⇒ 不猜着改；
4. 先算完整段文本，再一次性 `writeFileSync`。

幂等：目标形态（标记 `/* dshm-market-bridge: cli-branch */` + `hostKind: 'dsh'`）下重算结果与原文逐字节相同 ⇒ 不写盘。

**为什么必须认得上一代补丁**：上一代（随 `docs/125` 那轮）插的是 `/* dshm-market-bridge: desktop-restart */` + `const appExit` + `const restart`，**与新补丁同名同作用域**。若只按锚点追加 ⇒ 一处 `const` 变两处 ⇒ **重复声明 = 语法错 ⇒ 整个市场插件挂不起来**（比原缺陷更糟）。所以旧形态不是兼容分支，而是**升级路径**：整段摘掉、写上新形态；`LEGACY_PATCH_BLOCK` 逐字核对，对不上就不写。

## 5. 门禁

`tools/check-market-bridge.mjs`（566 → 678 行，**87 passed / 0 failed**）：

- **J 节（改写契约）**：J0/J0b（导出面只剩新名，不留双份实现）、J1（没装 ⇒ 不造文件）、J2a–J2f（上游原形改写后的六个计数口径：`hostKind: 'desktop'` **0** 处 / `'dsh'` 恰好 **2** 处 / `, agents, restart }` 恰好 **1** 处 / CLI 分支那处 `, restart, agents }` 未动 / `const appExit` 与 `const restart` 各恰好 **2** 处 / 新标记恰好 **1** 处）、J3（第二次是 no-op、逐字节不变）、**J4a–J4e（升级路径：旧形态 ⇒ 终态与"直接改写上游原形"逐字节相同、无重复 `const`、旧标记被摘掉）**、J5/J6/J6b（三条负向臂：锚点不唯一 / 调用行出现两次 / 锚点之间有未知行 ⇒ 一个字节都不写）、J7/J7b（本插件绝不自 `provide("appExit")` —— 撞名会把 Host 打挂）。
- **K 节（落位口径）**：K1–K7（`--dir` 两种写法 / 值为 `/` 不采纳 / 缺值 / 相对路径归一 / `remove` 同口径）+ K7a/K7b/K7c（`--dir <临时目录>` 原样进 `.dir`、预取句柄成功落定）。

**本轮自己先踩的坑（记下来，因为它说明「语法已验」≠「门禁已跑」）**：正则原来写成

```js
/^ {12}desktopHost\.effect\(…routes'\);\n$/m
```

`$` 在 `/m` 下命中「行尾」，但 `\n` 已经被消费掉 ⇒ 它实际要求的是「这一行之后**紧接着文件结束**」——**单拿一行去测能中，在真文件里永远不中**。后果：J2a/J2b/J2c/J2e/J2f/J3/J4a/J4b/J4d/J4e/J6b 共 **11 条先红**；而在真机上，`patchMarketCliBranch()` 会一路回「上游形状变了 ⇒ 不改」——**表现成"补丁静默不生效"，与"没写这个功能"一模一样**。去掉 `$` 后 87/87 全绿。

> 这一条也顺带证明了负向臂的价值：J5/J6 只断言 `ok === false`，所以它们在"正则根本不匹配"时**照样是绿的**——真正抓住缺陷的是 J2a 那类"必须真的改写成功"的正向断言。

## 6. 真机验证（手机 `62T0225B18039433`，下面每条都是真机读数）

| 项 | 读数 |
|---|---|
| 核心树 | `+dshm.28` 已物化（`16501` 条目 / 解包 176.7 MB / 压缩 52.4 MB）；`check-resfile-core-zip` ✅ —— resfile 只有 1 份容器、与配方、与产出三者 sha256 一致（`59,271,457 B` / `1d3c77e9…`） |
| 构建 / 装机 | `entry-default-signed.hap` **381.6 MiB**（debug / debugKey）；`hdc install -r` OK；home 指纹 `links=8 size=3440` 装前装后**同值** |
| 进门（先记一笔环境坑） | 首次 `aa start` 被**设备锁屏**挡住：`Error Code:10106102 The device screen is locked during the application launch, unlock screen failed`（开发者模式下无法自动解锁）—— 这不是缺陷，是验收环境；**解锁后** `aa start` 立即 `start ability successfully.` |
| 冷启动 | `pidof` = `22634`；`dsh/cores` = **`0.2.1-alpha.1+dshm.28`** ⇒ 新树确实解包并运行 |
| **升级路径（真机）** | `node-output.log`：`[2026-10-09T06:36:14.291Z] [dshm-market-bridge] 皮肤市场挂载契约改写：已从上一代补丁升级（hostKind 'dsh' + restart）` —— 设备上那份 `lib/index.js` 装前**正是**上一代形态（`desktop-restart` 标记），所以这一行就是「就地升级而不是叠加」的真机证据 |
| 落盘终态 | 设备文件 `…/profiles/ondevice/node_modules/dsh-skin-market/lib/index.js`：`grep -c cli-branch` = **1**、`grep -c desktop-restart` = **0**、第 63 行 = `desktopHost.effect(() => mountRoutes(host, { profile: current.name, profileDir: current.dir, runner: desktopRunner(service, current.dir), hostKind: 'dsh', runtime: detectDshRuntime(), agents, restart }), 'dsh-skin-market: desktop routes');`；全文 `const appExit = readService('appExit')` 恰好 **1** 处 ⇒ **没有重复声明** |
| 判定面 | `GET /dsh-skin-market/state` → **`"hostKind": "dsh"`**、`"restartAvailable": true`（`docs/128` 的「使用」链所需那条仍在） |
| **端到端 · 简单形态** | `POST /dsh-skin-market/install {"skinId":"ewnscat-ya.dsh-client-ui-skin-denia"}` → **202** + operationId；轮询 `downloading（下载并检查安装包）` → `installing（安装到 profile）` → 终态 `installation:"installed"`、`installedVersion:"1.0.0"`、`installedSpec:"github:Ewnscat-ya/dsh-client-ui-skin-denia#217a5cbb6034917c0176f5bc0c6843855e9a7309"` |
| **端到端 · 多包仓库 `&path:`** | `POST … {"skinId":"yunxiiqwq.maid-whale-webui"}` → 同样走完 `downloading → installing → done`（终态文案 `installed; choose Use to activate`）；`installedVersion:"0.1.1"`、`installedSpec:"github:yunxiiQwQ/dsh-maid-whale-webUI#34c09d7bfbed9b36b3b23f1f72a733ed310265cd&path:/maid-whale-webui"` |
| profile 落账 | `profiles/ondevice/package.json` 的 `dependencies` 出现两条 GitHub 原样 spec（`@dsh-external/dsh-client-ui-skin-denia`、`@yunxii/dsh-client-ui-skin-maid-whale-webui`）—— 正是 `installedSpecMatches()`（按 `spec.includes(skin.install.commit)`）认的形态 |
| 队列 | `install-queue/` 装完为空（`.req`/`.dir` 被宿主安装器消费后清理）；桥日志 `[dshm-market-bridge] 已接管市场包操作：profile=ondevice，队列=…/dsh/home/install-queue` |
| 前后对照 | 这两条装前都是 `review.installation=verified` + `install.desktop.mode=manual-only` ⇒ **修复前在同一台设备上只可能显示「需手动安装」**（走 `isManualOnly` 的 desktop 分支），且真点下去会被 `lifecycle.begin()` 当场拒（桌面档只认 `managed`）。同一设备、同一条链路的前后对照 |

> **`--dir` 这一条为什么能算验过**：`prefetch()` 的三步是「在临时目录里 `add` → `validateInstalledSkin(临时目录)` → 才落 live profile」。桥若仍只认 profileDir，预取会写进 live profile 而临时目录空着 ⇒ 第二步必然失败（`installed package manifest missing`）。两次安装都走到了 `installing` 并 `done`，说明**临时目录里确实有那份被校验过的包**。
>
> **这两条皮肤现在是 `installed` / `inactive`**（未激活 ⇒ 不改用户当前主题；要回到装前状态，卸载一次即可）。

**本轮未验（明确记下，不含糊）**

1. UI 上按钮的肉眼复验（本轮走的是同一条 API 链路 + `hostKind` 读数，没做 UI 自动化）；
2. **PC 档回归**（桥在 PC 上惰性 ⇒ 市场文件一个字节都不该被改；PC 上原本能一键装的 `managed` 皮肤仍要能装）；
3. 点「使用」→ 整机冷启动那一跳（`docs/128` 已端到端验过该链，本轮只确认 `restartAvailable=true` 未回归）。
## 7. 未做 / 待办

- **PC 档回归**（最重要的一条）：桥在 PC 上 `shimRunnable()===true` ⇒ 整条惰性，理论上市场文件一个字节都不会被改；但 PC 上原本能一键装的 `managed` 皮肤**必须**再确认一次能装 —— 这是"修好手持档不许改坏 PC"的那道闸。
- 端侧 UI 上按钮的肉眼复验（已用 `hostKind` 读数 + 真装成功间接证明）。
- 这两条皮肤的去留：现在是 `installed / inactive`，激活（`POST /dsh-skin-market/activate`）与「使用」重启留给用户点 —— **不替用户改主题**。
- 正式侧载包：本轮产物是 debug HAP 381.6 MiB，`dist/sideload/` **未同步**。
- `docs/126` 的五项「删除安全网」候选仍在待拍板（与本轮无关）。
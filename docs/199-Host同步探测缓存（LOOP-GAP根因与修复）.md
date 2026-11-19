# 199 · Host 同步探测缓存（LOOP-GAP 根因与修复）

> 批次：Beta `1.1.4 / 1010004`，核心 `0.2.1-rc.2+dshm.76`（**核心版本未升**：本次只改 Host 侧
> `hostcore/app/**` 与门禁/文档，不碰上游核心树、不碰 `entry/` 与 `platform/` 的 ArkTS）。
> 日期：2026-10-19。状态：**代码已落盘 + 门禁全绿；真机待验**（清单见 §7）。

---

## 1. 现象：事件循环被同步调用成段冻住

内测日志（`dist/triage/2026-10-19/logs1019/DSH日志-20261019/` 与 `tar1018/live/`）里，
我们自己在 `hostcore/app/main.js` 装的诊断（LOOP-GAP / SYNC-RING / SYNC-SLOW-LOG / SYNC-COUNT）
给出的读数非常一致：

```
LOOP-GAP 33277ms（事件循环停顿；第 9413 拍）
LOOP-GAP-33277ms SYNC-SLOW-LOG 36839ms existsSync
    ~/.node_modules/@linxin666/dsh-web-all/package.json
SYNC-COUNT 同步调用总耗时 113819ms，Top12：
    existsSync×332830=64485ms | readFileSync×122216=42862ms |
    readdirSync×8728=5114ms | realpathSync×14914=773ms
LOOP-GAP 800711ms（最长一次，13 分钟）
```

读法（三层互相印证，不是单点猜测）：

| 读数 | 说明 |
|---|---|
| `LOOP-GAP 33277ms` | 事件循环**整段**停了 33 秒（看门狗每秒一拍，实测到的一跳差值） |
| `SYNC-SLOW-LOG 36839ms existsSync <某 package.json>` | 停顿那一刻**正在执行**的同步调用就是它：一次 `existsSync` 花了 36.8 秒 |
| `SYNC-COUNT existsSync×332830=64485ms` | 进程生命周期内 `existsSync` 累计 **33.5 万次 / 64.7 秒**；`readFileSync` 12.2 万次 / 42.9 秒 |
| `LOOP-GAP 800711ms` | 最长一次 13 分钟 —— 已经不是"卡一下"，是整段不可用 |

---

## 2. 根因：模块解析在同步 `existsSync` 上反复扫描慢存储

`existsSync` 这 33.5 万次里**绝大多数是负结果**，来源不是我们的业务代码，而是
**Node / 打包器解析依赖时逐级向上找 `node_modules`**：

```
~/.node_modules/…            ← 用户家目录上方的探测
/data/storage/node_modules/…
/data/node_modules/…
```

每解析一个名字，解析器就会沿父目录链一路 `existsSync` 上去，答案几乎全是"不存在"。
三个放大器叠加：

1. **重复**：同一个"这个名字在不在"的答案，在同一个进程里被问上万次（33.5 万次里绝大多数是重复的负结果）；
2. **穿透慢存储**：这些路径落在用户数据区（el2）的慢路径上，一次负探测在真机上可以要几十毫秒到几十秒；
3. **同步**：`existsSync` 是同步 API，全部跑在 JS 主线程上 ⇒ 一次慢探测 = 一次 LOOP-GAP。

⇒ **答案在秒级内不会变**，却每次都要重新穿透一次慢存储。这就是要修的东西。

---

## 3. 修复：只缓存"探测型"调用的**负结果**

新增 `hostcore/app/fs-probe-cache.cjs`（Host 层，**不改核心树里 node_modules 的任何文件**），
在 `hostcore/app/main.js` 里于**核心树 require 之前**安装。

### 3.1 只做三件事

| 入口 | 接管的形态 | 说明 |
|---|---|---|
| `fs.existsSync` | 负结果（返回 `false`） | 本次 LOOP-GAP 的**主犯**，收益最大 |
| `fs.statSync` | 负结果（抛 `ENOENT`） | `{throwIfNoEntry:false}` 一律直通（它的负结果是 `undefined`，是另一套语义） |
| `fs.readFileSync` | 负结果（抛 `ENOENT`） | 只缓存"读不到"；**正结果一律不缓存** |

其余 fs 一个字节都不碰：`readdirSync` / `realpathSync` / `openSync` / `write*` / `mkdir*` /
`rm*` / `rename*` …都不接管（`readdirSync` 5.1s、`realpathSync` 0.77s 的收益远小于改语义的风险）。

### 3.2 保守规则（最终值）

| 规则 | 最终值 |
|---|---|
| 缓存面 | **只缓存负结果**；正结果（存在 / 读到内容）**一律不缓存** —— 装完插件 / 升完核心必须立刻可见 |
| TTL | 默认 **30000ms**；`DSHM_FS_PROBE_CACHE_TTL_MS` 可调（非法值退回默认、超 10 分钟夹到 10 分钟、`0` 等同关闭） |
| 路径白名单 | 路径含 `node_modules`、`/package.json`、`/profiles/`、`/install-queue`（反斜杠先归一成 `/`）；**其它路径直通** |
| 全关 | `DSHM_FS_PROBE_CACHE=off`（也认 `false` / `0` / `no`）⇒ **完全不接管**，fs 原样不动 |
| 异常 | 缓存层自己的任何异常 ⇒ 退回原函数；**原函数抛出的异常原样、原对象、只抛一次地往上抛**（绝不改写成 `false`） |
| 幂等 | 同一个 fs 只包装一次（重复 install 返回同一句柄） |
| 上限 | 条目封顶 4096（满了先清过期项，仍满就整体丢弃 —— 丢缓存永远安全） |

### 3.3 接线（`hostcore/app/main.js`）

安装点位置是**承重的**，三个顺序都有理由：

1. **早于核心树 require**：缓存只对"装上之后的调用"生效。核心树（`node_modules`）与
   `profiles/` 的整棵模块图是在那之后才被加载的，晚一步就等于这一轮 LOOP-GAP 白修；
2. **晚于 `installNativeRedirect()`**：那条把 `existsSync` 改写成了"沙箱里找不到就去 HAP
   `libs/` 找平铺 `.node`"。缓存层套在它外面，`.node` 探测的真答案仍由重定向给出；
   而 `libs/…` 不在白名单里 ⇒ 直通、不缓存；
3. **早于同步调用环（SYNC-RING / SYNC-COUNT）**：那一层包的是"有效代价"，装在它前面，
   命中缓存就立刻表现为快调用 —— 真机上正是靠 SYNC-COUNT 的下降验证收益，顺序反了读数会骗人。

诊断行（启动时一行，供事后检索）：

```
[dshm-host] fs 探测缓存已安装（TTL=30000ms，白名单=node_modules/package.json/profiles/install-queue）
```

退出时（`process.on('exit')`）打一行 stats，命中率与"估计节省 ms"都在里面：

```
[dshm-host] fs 探测缓存 stats：enabled=true TTL=30000ms 命中=… 未命中=… 直通=… 入缓存=… 估计省=…ms 条目=…
```

> 句柄用 `let fsProbeCacheHandle = null;` 在 exit 钩子**之前**声明：安装点比钩子注册晚，
> 若进程在安装之前就退出，直接读还没初始化的 `const` 会踩 TDZ 抛 ReferenceError，
> 把"进程最后几行日志"变成一条异常。

### 3.4 打包同步（不碰核心树 zip 内容）

`tools/place-host-app.mjs` 与 `tools/assert-resfile-sync.mjs` 的 `FILES` 清单都加了
`fs-probe-cache.cjs`。**漏掉它不会崩**（安装点自带 try/catch，只留一行 diag），但缓存层整段不生效
⇒ 真机 LOOP-GAP / SYNC-COUNT 与修复前一模一样，属于"静默白修"——所以两份清单都必须带它。

---

## 4. 边界与取舍（如实记，不假装更全）

1. **只对 install 之后的调用生效**：在此之前 `const { existsSync } = require('fs')` 解构走的模块
   看不见这层（与 `jitless-env.cjs` 的 `installNativeRedirect()` 同一约束）。
2. **同进程安装窗口**：若某路径在本进程里先被探测成"不存在"，紧接着（同一个 TTL 内，≤30s）
   才被安装器创建出来，那次负结果仍会命中。跨启动没有这个问题（缓存只活在内存里）。
   处置口径：`DSHM_FS_PROBE_CACHE=off` 全关 / TTL 调小；模块导出了 `clear()` 供安装器或诊断面
   显式清空（**本批未接线**，见 §7 待验第 5 条）。
3. **负异常的语义**：`statSync` / `readFileSync` 的负结果是**一次抛出**，本层缓存的是**当初那个
   Error 对象**，命中时原样重抛 ⇒ `code` / `errno` / `syscall` / `path` / `message` 与真实调用
   逐字一致（不重新构造错误对象，重新构造就会把 `ENOENT` 悄悄变成别的 errno）。
   代价：`stack` 停在首次抛出点。
4. **`readFileSync` 为什么没有"小文件内容缓存"**：保守规则 ①（正结果一律不缓存）意味着
   **不存在"把文件内容缓存在内存里"这回事**，也就没有"缓存了 256KB 以上内容"的风险面；
   这条通道只缓存 `ENOENT`（那时一个字节都没读到，大小无从谈起）。
   因此本层**刻意不写**一个没人读的 256KB 常量（"不要忠实转发没人要的字段"那条教训），
   改为由门禁的**行为断言**守住：一个 300KB 的文件连续读两次，底层必须被调用**两次**。
   将来若真要开内容缓存：上限常量 + 失效判据（mtime/size）+ 安装窗口显式失效，三件一起加。
5. **worker 线程未装**：worker 是新 module registry，需要时由 `worker-bootstrap.cjs` 另行安装。
   本批不装 —— LOOP-GAP 读数来自**主线程**（同步解析就跑在主线程上）。
6. **不做 `readdirSync` / `realpathSync`**：它们不是"负结果缓存"能安全覆盖的东西
   （目录内容变化、符号链接解析都有语义），收益（5.1s / 0.77s）不值得。

---

## 5. 门禁：`tools/check-fs-probe-cache.mjs`（离线，已入 CI）

```
node tools/check-fs-probe-cache.mjs
```

三段判据：

| 段 | 内容 |
|---|---|
| **A 纯逻辑**（13 项） | A1 负结果命中 / A2 过期后重探 / A3 正结果不缓存 / A4 白名单外直通 + `isCacheablePath` 矩阵 / A5 `off` 直通 / A6 异常直通（原对象、不缓存、不变成 `false`）/ A7 TTL 与上限口径 / A8 `statSync` 负结果 + `throwIfNoEntry:false` 直通 / A9 `readFileSync` 负结果 + 300KB 内容永不缓存 / A10 绝不自崩（奇怪参数 / env getter 抛错 / 冻结 fs）/ A11 `savedMs` 估计 / A12 幂等 / A13 统计与 `clear()` |
| **B 接线**（真实文件） | B1 `main.js` 真的 require + 调用；B2 安装点**早于核心树 require**；B3 早于同步调用环；B4 诊断行逐字存在且白名单清单与模块 `WHITELIST_LABEL` 一致；B5 退出时打 stats（句柄声明在 exit 钩子之前）；B6 resfile 两份清单都带上它；B7 已入 `gates.yml`；B8 `docs/199` 在且被 `docs/README.md` 索引 |
| **C 变异对照臂**（5 个，**必须全部判红**） | ① 正结果也缓存 ② 白名单失效（全路径缓存）③ 异常被吞成 `false` ④ 过期失效（TTL 不生效）⑤ `off` 被忽略 |

C 段的做法不是"看代码像不像"，而是**把模块源码就地改一处、加载变异体、再跑同一条行为断言**，
断言**必须抛**才算这条有牙（变异锚点在源码里找不到 / 变异体仍然通过 ⇒ 门禁自己判红）。

实测：**44 项全绿**（A 13 / B 18 / C 5 + 8 项接线细分），5 个变异臂全部判红。

---

## 6. 这一轮刻意没做什么

- **不改核心树**：`node_modules` 里的解析器一行不动（缓存层在 app 层，升级核心树时不用搬家）。
- **不升 `coreVersion`**：只改 `hostcore/app/**` + `tools/` + `docs/`，核心树内容未变。
- **不动 `entry/` 与 `platform/` 的 ArkTS**：没有新增权限、没有新增 ArkTS 调用点。
- **不做"缓存预热"**：预热本身就要先扫一遍慢存储，收益可疑且会让启动路径变复杂。

---

## 7. 真机待验清单（装机后按顺序做）

前置：用本工作区（beta，`com.dshm.dshmbeta`）出包并**覆盖安装**（`hdc install -r <hap>`，不卸载、
不清 el2 数据），冷启动一次。

1. **启动诊断行**（一条命令，确认这层真的装上了）：

   ```powershell
   hdc shell "grep -a 'fs 探测缓存' /data/app/el2/100/base/com.dshm.dshmbeta/haps/entry/files/dshm-host.log | tail -3"
   ```

   期望：看到 `[dshm-host] fs 探测缓存已安装（TTL=30000ms，白名单=node_modules/package.json/profiles/install-queue）`。
   若看到 `未启用` 或 `安装失败` ⇒ 环境里 `DSHM_FS_PROBE_CACHE` 被关 / resfile 漏了
   `fs-probe-cache.cjs`（先跑 `node tools/place-host-app.mjs` 再重出包）。

2. **LOOP-GAP 是否消失（核心验收，一条命令）**：

   ```powershell
   hdc shell "grep -aE 'LOOP-GAP|SYNC-COUNT' /data/app/el2/100/base/com.dshm.dshmbeta/haps/entry/files/dshm-host.log | tail -20"
   ```

   判据（对照修复前：单次 33277ms / 最长 800711ms、`existsSync×332830=64485ms`）：

   - 冷启动 + 首轮会话期间 **`LOOP-GAP` 条数 = 0**（或单次 < 1500ms，即根本不触发记录）；
   - 若仍有 `LOOP-GAP`，`SYNC-SLOW-LOG` 里**不再出现** `existsSync …/node_modules/…`；
   - `SYNC-COUNT` 里 `existsSync` 的累计耗时从 ~64s 掉到**秒级**（命中后每条只剩记账开销）。

3. **退出 stats 读数**（命中率与估计节省）：
   正常停止 Host（或让进程自然退出）后：

   ```powershell
   hdc shell "grep -a 'fs 探测缓存 stats' /data/app/el2/100/base/com.dshm.dshmbeta/haps/entry/files/dshm-host.log | tail -1"
   ```

   期望：`命中` 显著大于 0、`估计省` 是秒级以上、`直通` 也有（说明白名单没吃掉别的路径）。

4. **功能不被缓存挡住**（这一条比性能更重要）：
   - 装一个插件 → **立刻**（不重启）在「插件」页看到并可用；
   - 升级/切换核心版本 → 重启后会话与插件正常；
   - 皮肤市场一键安装一条 → 装完立刻生效（不要等 30s 再试，那正是要证明的窗口）。

5. **可关性**：把 `DSHM_FS_PROBE_CACHE=off` 用于一次排障启动（或把 TTL 调成 `1000`），
   确认日志出现 `fs 探测缓存未启用` / LOOP-GAP 回到"有缓存前"的形状 —— 证明这层是可退的。

6. **安装窗口实测**（若第 4 条出现"装了要重启才生效"）：记录当时的时间线，判据是
   "负探测 → 安装完成"的间隔是否 < 30s；若是，把 `clear()` 接进安装器的 `finish` 路径（本批未接）。

7. **手机 / 平板档**：本层与分档无关（纯 fs 层），但手持档的存储更慢、收益应更明显；
   顺手确认 `SYNC-COUNT` 里 `readFileSync` 的累计耗时是否也跟着降（负读命中）。

> **验收结论写回本档 §9**，并写明设备、HAP 版本、冷启动后跑了多久的会话。

---

## 8. 除根：收窄全局模块路径（第 1 次探测也不再走慢存储）

### 8.1 缓存治的是第 2 次，第 1 次还在付

分诊报告（`dist/triage/2026-10-19/TRIAGE.md` P0-2 / S-07）给的读数**不是**重复探测，而是**第一次**：

```
SYNC-SLOW 192220ms existsSync
  ~/.node_modules/@cocofhu/skillhub/package.json
（另两笔同型：15843ms、36839ms；日志 logs1019/dshm-host.log:8369 / :9239 / :12825）
```

第 3 节那层负结果缓存只能让"同一路径 30s 内的**第二次**探测"免付；**第一次**必须真的去问一次。
所以本节的改动不是调缓存，而是**把那条慢路径本身从解析器的输入里摘掉**。

### 8.2 自变量是 Node 的全局搜索路径

Node 启动时（`internal/modules/cjs/loader.js` 的 `Module._initPaths()`）按两个输入拼"全局路径表"：

```
<prefix>/lib/node  +  $HOME/.node_modules  +  $HOME/.node_libraries  +  NODE_PATH 各项
```

本机 `HOME=~`（公共存储挂载）⇒ 前两条就是慢存储。于是**任何一次**
`require('某包')` 在正常 `node_modules` 链上没命中，都会回退去探它们 —— 一次 miss 3.7s / 15.8s / 192s。
这就是"周期 67s、单次 8.1s 级"的自变量：解析失败越频繁，回退探测越多。

### 8.3 为什么不是 `Module.globalPaths.splice()` 一下就好（实测：那样无效）

Node 24 里是**两个东西**：

```
modulePaths = paths;                                   // ← 解析真正用的"活路径表"（模块内私有变量）
Module.globalPaths = ArrayPrototypeSlice(modulePaths); // ← 只是给自省用的**浅拷贝**
```

`Module._resolveLookupPaths()` 用的是 `modulePaths`。实测（Node v24.19.0，PC）：

| 操作 | `require.resolve('foo')`（foo 只在 NODE_PATH 里） |
|---|---|
| 基线 | ✅ 命中 |
| `Module.globalPaths.splice(0)` | ✅ **仍然命中**（自省副本被改，活表没动） |
| `Module.globalPaths = []` | ✅ **仍然命中**（同上） |
| 换 env 后调 `Module._initPaths()` | ❌ `MODULE_NOT_FOUND`（活表真的变了） |

⇒ 收窄必须让 Node **用收窄后的输入重算一次活路径表**，这正是本节实现做的事。

### 8.4 做法（`hostcore/app/module-path-guard.cjs`）

1. **过滤 `NODE_PATH`**：把指向 `~` 的项从 env 里删掉
   （写入收窄后的串；全删则写空串）。worker 线程继承 env ⇒ 这一半连带修好。
2. **同步窗口内重算活路径表**：把 `HOME` / `USERPROFILE` 临时清空（`_initPaths` 里 `Boolean('')` 为假
   ⇒ 不再加 `$HOME/.node_modules`、`$HOME/.node_libraries`），调一次 `Module._initPaths()`，
   然后**立刻在 `finally` 里逐字还原**两个 env。不存在"异步期间 HOME 是空"的窗口。
3. **只摘前缀项**：`~`（正好等于或前缀 + `/…`；反斜杠先归一）。
   **应用沙箱内路径一律保留**：`/data/storage/**`、`<prefix>/lib/node`、沙箱里的 `NODE_PATH` 项。
4. **顺手过滤自省副本**：`Module.globalPaths`（若 `_initPaths` 不可用，作为"至少读数一致"的兜底，
   但它**不改变解析**——见 8.3）。

诊断行（启动一行，供事后检索与断言）：

```
[dshm-host] 全局模块路径已收窄（移除 2 项 ~，NODE_PATH 移除 0 项，保留 1 项）
```

`keep` 模式（排障复现旧行为）：`[dshm-host] 全局模块路径保持原样（DSHM_GLOBAL_PATHS=keep）`。

**与缓存层的顺序是承重的**：收窄必须**早于** `fs-probe-cache` —— 先摘慢路径，再缓存剩下的负结果。
反了会把"第一次 192s 的那条负结果"缓存起来，收益仍然只有第二次。

### 8.5 边界与回退

| 项 | 口径 |
|---|---|
| 关闭开关 | `DSHM_GLOBAL_PATHS=keep` ⇒ 完全不接管（不重算、不改 env、不碰 globalPaths） |
| 失败面 | 任何异常都直通：安装不抛、不改变解析；env 尽量还原；只留一行 `全局模块路径收窄失败（不阻塞）` |
| 语义面 | 不改 `_resolveFilename` / `_resolveLookupPaths` / `_pathCache`（原对象、原缓存、原算法）；只改"去哪儿找"的目录清单 |
| 幂等 | 同一个 Module 只做一次（重复 install 返回同一份结果） |
| 只影响主线程 | worker 是新 module registry，会按 env 自行初始化：`NODE_PATH` 那一半继承我们的收窄结果；但 worker 里的 `$HOME/.node_modules` 仍会被它自己加回去（我们不动 `HOME` 的长期值）。LOOP-GAP 读数来自主线程，本批不装 worker（需要时由 `worker-bootstrap.cjs` 另行安装） |
| 前缀范围 | 只认 `~`；其它 `/storage/Users/<name>` 形态（单用户设备上不存在）不在此列，如实登记 |
| 依赖的运行时杠杆 | `Module._initPaths`（Node 内部函数，非公开 API）。Node 24 实测在；若某次运行时它不存在，本层只过滤自省副本、日志写明"`_initPaths` 不可用"，**不会假装生效** |

### 8.6 门禁：`tools/check-module-path-guard.mjs`（离线，已入 CI）

```
node tools/check-module-path-guard.mjs
```

| 段 | 内容 |
|---|---|
| **A 纯逻辑**（8 项，注入 fake Module + fake env，不碰真实 Module） | A1 `filterPaths` 只摘用户项 / 沙箱项保留 / 归一化与边界；A2 `filterNodePath` 分段收窄（空段、分隔符口径）；A3 安装后**活路径表真的变窄** + `HOME`/`NODE_PATH` 逐字还原 + 诊断行计数；A4 `keep` 完全不动；A5 异常直通（不抛、env 还原、如实报失败）；A6 幂等；A7 不改 `_resolveFilename`/`_resolveLookupPaths`/`_pathCache`；A8 真 Node 运行时具备收窄杠杆（只读核对） |
| **B 接线**（真实文件） | B1 `main.js` require + 调用；B2 安装点早于核心树 require、**且早于 fs 探测缓存**；B3 诊断行逐字存在；B4 resfile 两份清单都带上它；B5 已入 `gates.yml`；B6 本档 §8 在 |
| **C 变异对照臂**（4 个，必须全部判红） | ① 不删用户项（等于白装）② 删掉沙箱项（沙箱依赖整体丢失）③ `keep` 被忽略（排障时关不掉）④ `HOME` 不还原（进程余下生命周期环境被污染） |

> 第 ② 个变异体是本层最危险的放宽：它"看起来更省"（全摘掉），实际会让沙箱里的依赖也解析不到。

### 8.7 真机验收：第 1 次探测也不再出现

1. 冷启动后先看这层有没有装上：

   ```powershell
   hdc shell "grep -a '全局模块路径已收窄' /data/app/el2/100/base/com.dshm.dshmbeta/haps/entry/files/dshm-host.log | tail -2"
   ```

   期望：`[dshm-host] 全局模块路径已收窄（移除 2 项 ~，…）`。
   若看到 `保持原样` ⇒ `DSHM_GLOBAL_PATHS=keep` 被设了；`收窄失败` ⇒ 看 reason。

2. **判据（核心）**：冷启动 + 首轮会话之后，日志里**再没有一条**探测落在用户家目录的全局路径上：

   ```powershell
   hdc shell "grep -a -c '~/.node_modules' /data/app/el2/100/base/com.dshm.dshmbeta/haps/entry/files/dshm-host.log"
   ```

   修复前：该串会在 `SYNC-SLOW` / `SYNC-WARN` 里反复出现（3.7s / 15.8s / 192s 那几笔的路径主体）；
   修复后：**0**（连"第一次"也没有了 —— 路径已不在解析器的输入里）。

3. `SYNC-SLOW` / `SYNC-WARN` 里不再出现 `existsSync … ~/…`：

   ```powershell
   hdc shell "grep -aE 'SYNC-SLOW|SYNC-WARN' /data/app/el2/100/base/com.dshm.dshmbeta/haps/entry/files/dshm-host.log | grep -a -c '~'"
   ```

   期望 **0**；`LOOP-GAP` 条数同时应为 0（两边合起来才算"既有缓存止血、也除了根"）。

4. **可退性**：把 `DSHM_GLOBAL_PATHS=keep` 用于一次排障启动，确认日志出现 `保持原样`
   且第 2/3 条的读数回到修复前形状 ⇒ 证明这层是关得掉的（不是"焊死"）。

5. **功能面不能少**：插件安装/激活、核心树 `require`、`profiles/node_modules` 的依赖解析全部正常
   （这一层只摘公共存储那两条，沙箱路径一个都没动；若出现 `MODULE_NOT_FOUND`，
   先把 `keep` 打开对照一次，就能判定是不是本层误伤）。

---

## 9. 真机验收记录

（待填：设备型号 / HAP sha256 / 冷启动时间 / LOOP-GAP 条数 / SYNC-COUNT 对照 /
`~/.node_modules` 命中条数（应为 0） / 第 4 条的功能回归结果）

## 9. 收口：写操作必须清缓存（2026-10-19 全仓门禁抓到的真回归）

### 9.1 真机门禁回归

`tools/check-plugin-toggle.mjs`（宿主离线起一遍，断言四条自带插件行必须 `enabled`）在本轮改完后**变红**：
`FAIL: baseline host never became ready`，宿主日志停在探针读数之后、`beforeExit code=0`。
二分：`DSHM_FS_PROBE_CACHE=off` ⇒ **rc=0**；`DSHM_GLOBAL_PATHS=keep` / `DSHM_PY_INLINE=1` ⇒ 仍红 ⇒ 唯一自变量是缓存层。

### 9.2 根因

缓存只记"不存在"（负结果），但**同一个进程里的写操作会让路径立刻存在**：
`check-plugin-toggle` 先探测插件清单（缺失 ⇒ 负结果入缓存），再**改写 profile / 落位插件**，
然后让宿主重载插件 —— 重载时 `existsSync` 命中 30s 内的旧负结果 ⇒ 宿主认为"插件全不存在" ⇒ 起不来。
真机同型场景：插件安装、皮肤市场落位、profile 首次生成。

### 9.3 修法

`fs-probe-cache.cjs` 新增 `wrapInvalidate`：把 `writeFileSync / appendFileSync / renameSync / unlinkSync /
rmSync / mkdirSync / rmdirSync / copyFileSync / truncateSync / symlinkSync / linkSync` 逐个包一层，
**执行真实写之前先 `runtime.store.clear()`**（整表清空，O(1)、绝不漏）。
写操作远少于读探测，清空的代价可忽略；`patched` 仍只列三个被缓存的读入口（口径不变），
写入口单独登记在句柄的 `invalidateWrites` 上。

### 9.4 门禁加牙

- A14：负结果入缓存 → 写 → **写后立刻能读到新文件**、且缓存条目归零、底层真的被调用第二次；
- 第 6 条变异臂「写操作不清缓存」：把 `runtime.store.clear()` 去掉 ⇒ **必须判红**。
  门禁从 44 项提升到 **46 项 / 6 变异臂**。

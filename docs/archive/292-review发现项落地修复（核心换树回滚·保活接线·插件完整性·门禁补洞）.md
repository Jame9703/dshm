# 292 · review 发现项落地修复（核心换树回滚 · 保活接线 · 插件完整性 · 门禁补洞）

> 日期：2026-10-29 ｜ 状态：**代码已落地，离线门禁全绿；真机项待验收**
>
> 输入：
> - 2026-10-29 的独立 review（架构 / 构建链 / ArkUI / Host 四个方向，静态取证）；
> - [`291`](291-稳定性与性能完整测试报告（日常使用加开发环境）.md) beta 端稳定性与性能完整测试报告。
>
> 用户口径：「结合 beta 测试端的检测文档-291 一起修复这些问题，**beta 端暂时不用修浏览器调用的问题**」。
> 因此 **Beta 浏览器桥端口断链（docs/281 §1）本轮不修**，其余项全部落地。
>
> 纪律：全程**未**执行任何真机安装/卸载，**未**删除 el2 用户数据，**未**改动签名物料。

---

## 0. 一页结论

| # | 问题 | 严重度 | 处置 | 守卫门禁 |
|---:|---|---|---|---|
| 1 | 同版本核心**换树失败会删掉旧树**，设备失去可用核心 | P0 | 拆成 `stage()`（解包+校验，不碰目标）/ `commitStaged()`（落位）；**先验证后替换，失败回滚** | `check-bundled-core-rollback`（3 臂） |
| 2 | phone **系统取消后的续期永远不触发**（从未调 `noteBackground`） | P1 | 后台按在途事实 `noteBackground(running)`；回前台 `noteBackground(false)` | `check-keepalive-wiring`（3 臂） |
| 3 | entry 手持档**晚到 acquire** 回前台后残留任务/通知 | P1 | 代次 + 前后台二次校验，失效即 `release()`；代次自增先于 held 判断 | `check-keepalive-wiring` |
| 4 | 核心暂存树**无条件复用**，可把旧核心打上新版本标签 | P1 | 复用前与打包前各断言 `installed === recipe.coreVersion` | 打包链自检（见 §2.2） |
| 5 | 插件安装**不校验** registry 的 `integrity` / `shasum` | P1 | 解包前按 SRI 判死；两者皆无 ⇒ 拒绝安装 | `check-installer-integrity`（3 臂 + 行为样例） |
| 6 | **phone 权限面完全不在判据里**（"唯 一裁判"名不副实） | P1 | `check-permission-surface` 改为 entry/phone 各自 EXPECTED、逐条 + 顺序 + reason | 同门禁（+4 个 phone 变异体） |
| 7 | `__DSHM_BRIDGES__` 每拍探测桥，未就位时高频报错 | P1 | `applyHandheld` 加**指数退避**（1s→2s→4s→8s，成功清零）entry/phone 同步 | `check-bridge-methodlist`（新增 2 条判据 + 1 臂） |
| 8 | `check-profile-pnpm-bridge` **卡死 rc=124** | P1 | 临时沙箱避开 `/data/storage/`（否则伪装成端侧运行时 ⇒ 走接管分支等到超时） | 同门禁（47/47） |
| 9 | README/HANDOFF 仍是「恒 8 条」旧口径 | P2 | README 三处改为 **entry 17 / phone 9** 并写明 7 条 ACL | `check-doc-refs` |

**不再采纳报告的两处**（证据见 §4）：
- 「jitless 下全局 `fetch()` 崩溃」——本机实测**不成立**；
- 「`check-fetch-shim` / `check-internal-undici` / `check-web-fetch-jitless` 真失败」——**三条均绿**。

---

## 1. 核心换树：先验证、后替换、失败回滚（P0）

### 1.1 事故形态

原实现（`hostruntime/src/main/ets/core/BundledCore.ets`）的顺序是：

```text
指纹不同 ⇒ ① rename 旧树 → cores/<v>.stale-<ts>.tmp
           ② copyFile + stageFromZip
           ③ 失败时只记 failed
           ④ 末尾**无条件** rmdir 所有 stale ⇒ 旧树被删
```

覆盖安装一个**同版本号但内容损坏**的新容器时：旧树已被挪走，新树在解压/哨兵校验处失败
⇒ 该版本**一棵树都不剩**，而 `state.current` 仍指着它 ⇒ 下次 `host.start()` 报"没有可用的核心树"。
`CoreStore.stageFromZip` 那条"current 版本拒绝覆盖"的守卫也一起失效（目录早被挪空）。

### 1.2 修法

`CoreStore` 拆成两段：

| 方法 | 职责 | 是否碰 `cores/<version>` |
|---|---|---|
| `stage(zip, version)` | 解包到 `staging/` + 四道校验（顶层目录 / 树内元数据 / 关键件哨兵 / 版本目录名） | **不碰** |
| `commitStaged(version, allowExisting)` | 只把 staging 树 `rename` 到位 | 落位 |
| `stageFromZip(...)` | 兼容入口：`stage` + `commitStaged` | — |

`BundledCore.installOneVersion()`（新增，首装与换树共用）严格按：

```text
① 拷到可写目录 → ② store.stage() → ③ 新树已完整，才把旧树改名为 .stale-*.tmp
→ ④ store.commitStaged() → ⑤ finally：stale 仍非空 ⇒ 改名回去（回滚）
```

回滚失败**绝不删除**那棵 `.tmp`，把位置写进 `failed` 供人工处理 —— 宁可多一棵垃圾目录，也不能让用户失去能跑的核心。

### 1.3 守卫

`node tools/check-bundled-core-rollback.mjs`（新增，已入 CI + `--self-test`）：

- `stage()` 函数体内**不得**出现 `renameSync(inner, target)`；
- `installOneVersion` 里 `store.stage(` < `renameSync(oldDir` < `commitStaged(` 三步顺序；
- `finally` 里必须有 `renameSync(stale, oldDir)` 回滚；
- 旧写法 0 命中。
- 对照臂：先挪后装 / 删回滚 / 两段又合并 —— 逐个必须判红（3/3 已验证）。

---

## 2. 其余落地项

### 2.1 保活接线（entry + phone）

| 壳层 | 缺陷 | 修法 |
|---|---|---|
| phone | 全程无 `noteBackground(...)` ⇒ `backgroundWanted` 恒 false ⇒ 系统取消后只打 `renew 跳过` | `reconcileHandheldKeepAlive` 里按 `running` 调 `noteBackground(running === true)`；`onForeground` 补 `noteBackground(false)` |
| entry | `acquire()` 晚到成功时只打日志 ⇒ 前台残留长时任务/通知 | 引入 `keepAliveGeneration` + `appBackgrounded`；`.then` 里任一失效即 `release()`；`releaseHandheldKeepAlive` **先**自增代次、**再**判 held |

> phone 原本已有代次机制（`keepAliveGeneration`），本轮只补它缺的 `noteBackground`；
> entry 则补代次机制。两侧现在结构对称。

守卫：`node tools/check-keepalive-wiring.mjs`（新增，已入 CI + `--self-test`，3 臂）。

### 2.2 核心暂存树复用断言

`tools/pack-core.mjs` 两处：

- `materialize()` 复用分支：读 `node_modules/@deepseek-ai/dsh/package.json` 的 `version`，
  **不等于** `recipe.coreVersion` 直接 `die`，并提示 `--force-install`；
- `writeManifest()` 开头：打包前再断言一次（锁的是"即将被 zip 读走的那棵树"）。

### 2.3 插件安装完整性（SRI）

`hostcore/app/dshm-installer.js`：

- `resolveSpec()` 带出 `dist.integrity` 与 `dist.shasum`；
- 新增 `verifyTarballIntegrity(buf, spec)`：支持 `sha512/384/256/1` 的 SRI 与旧 `shasum`；
- `installSpecInner()` 在 `zlib.gunzipSync()` **之前**校验，失败即抛（不落位）；
- 判据取向：**"读不懂"≠"被篡改"** —— integrity 只含不支持算法时按不可判放行并打一行日志；
  **两者都没有**才算"无据可依"，直接拒绝安装。

守卫：`node tools/check-installer-integrity.mjs`（新增，已入 CI + `--self-test`，8 条行为样例 + 3 臂）。

### 2.4 phone 权限面进门禁

`tools/check-permission-surface.mjs`：

- 新增 `MODULES`（entry / phone 各自的 `module.json5` 与 `string.json`）与 `PHONE_EXPECTED`（9 条，顺序钉死）；
- `checkModuleText(text, stringEntries, expected)` 接受各自的 EXPECTED；
- 主流程两侧各跑一遍，任何一侧红即判红；
- 自检新增 4 个 phone 变异体（真 9 条绿 / 少一条 / 多一条 / 换序 ⇒ 判红）。

### 2.5 桥探测退避（`__DSHM_BRIDGES__` 高频报错）

`entry`/`phone` 的 `WebApp.ets` 中 `applyHandheld()`：桥未就位时不再每拍硬打，
按 `bridgeMiss` 指数退避（1s→2s→4s→8s 封顶），就位即清零。**只改探测节奏，不改任何形态判定。**

> 注意：本轮修的是"**探测节奏**"这一面。报告统计的 13 次/秒里若还有其它来源
> （例如某个轮询垫片调用了未登记的方法），由 `check-bridge-methodlist` 的"调用 ⊆ 登记"
> 判据兜底 —— 当前 entry/phone 两侧该判据均为绿。

---

## 3. 门禁与验证

### 3.1 本轮新增 / 修改的门禁

| 门禁 | 状态 | 是否入 CI |
|---|---|---|
| `check-bundled-core-rollback.mjs`（新） | ✅ 正例 + 3 臂 | 是（门禁 + 自检） |
| `check-keepalive-wiring.mjs`（新） | ✅ 正例 + 3 臂 | 是（门禁 + 自检） |
| `check-installer-integrity.mjs`（新） | ✅ 正例 + 3 臂 | 是（门禁 + 自检） |
| `check-permission-surface.mjs`（改） | ✅ entry 17 / phone 9 + 4 个 phone 变异体 | 是 |
| `check-bridge-methodlist.mjs`（改） | ✅ 新增退避判据 + 1 臂 | 是 |
| `check-profile-pnpm-bridge.mjs`（改） | ✅ 47/47（原为 rc=124 卡死） | 是 |

### 3.2 实跑读数

```text
离线门禁（仓库内文件，55 项）              PASS 55 / FAIL 0
需要核心树的门禁（解出 rc.4+dshm.97 后）    10/10 通过：
  check-ptc-wiring · check-core-openharmony-patches · check-plugin-toggle
  check-undici-shim-exports · assert-core-entrypoints · check-fs-local-permission
  check-agent-instructions-scope-walk · check-web-fetch-jitless
  assert-fs-search-fallback · compat-drift
```

### 3.3 本轮期间新修的两处回归（自检抓到的）

| 回归 | 根因 | 处置 |
|---|---|---|
| `assert-resfile-sync` 红 | 改了 `hostcore/app/dshm-installer.js` 未重新放置 | `node tools/place-host-app.mjs`（22 件同步） |
| `check-sidebar-shim-css` 红 | 新注释进了模板字符串，**反引号**会让 ArkTS 模板提前闭合 | 注释去反引号（这正是该门禁存在的意义） |

---

## 4. 不采纳的项与依据（如实登记）

### 4.1 「jitless 下全局 `fetch()` 崩溃」——本机实测不成立

`docs/291` §5.2 的复现命令在本机（Node v26.12.1, `--jitless`）实跑了五种形态：

```text
typeof WebAssembly                                  → undefined        （成立：无 WASM）
global fetch GET   http://127.0.0.1:59999/          → connect ECONNREFUSED（真实网络结果，不是崩溃）
global fetch POST body                              → connect ECONNREFUSED
new Request + fetch                                 → connect ECONNREFUSED
https fetch example.invalid                         → getaddrinfo ENOTFOUND
```

即 **`--jitless` 下全局 `fetch` 可用**（该版本 Node 的 fetch 路径不依赖 WASM llhttp）。
`fetch('http://127.0.0.1:1/')` 报的 `bad port` 是 Node 对保留端口**故意的**拒绝，与 WASM 无关。

结论：**不为一个不存在的缺陷改代码**。若在其它 Node 版本上复现，请附 `node -p process.version`
与完整栈（`WebAssembly is not defined` 的调用栈顶必须是 `lazyllhttp`）。

### 4.2 「三处 fetch 相关门禁真失败」——实测三条均绿

```text
check-fetch-shim.cjs        PASS（含请求方向流式体 ⑧′ 与「吞体必须判红」⑧″ 对照臂）
check-internal-undici.mjs   PASS（对照实验成立）
check-web-fetch-jitless.mjs PASS（需核心树；解出 rc.4 后实跑）
```

`check-ptc-wiring` 在核心树缺失时按设计 **exit 3（环境不具备）**，不是 FAIL —— 这是既有正确语义，
本轮未改。

### 4.3 `check-profile-pnpm-bridge` 卡死——根因是**门禁自身**，不是产品

本机 `TMPDIR=/data/storage/el2/base/cache` ⇒ `mkdtemp` 造出的临时沙箱恰好以 `/data/storage/` 开头
⇒ `isDshmAppRuntime()` 判"在端侧 Host 里" ⇒ 走进接管分支 ⇒ `waitOutcome()` 等到 20 分钟上限。
修法：临时沙箱显式避开 `/data/storage/`（与 `check-vm-bash` 的隔离做法同源）。
**产品代码未改** —— 该判据在真机上是对的。

---

## 5. 未做 / 待真机

| 项 | 状态 | 判据 |
|---|---|---|
| **Beta 浏览器桥端口断链**（`docs/281` §1） | **本轮不做**（用户口径） | 扩展连 19391 后 `/dshm-browser/status` 的 `clients` 非空 |
| 回环浏览器 WS 固定口令 / 无 Origin 校验 | 未做 | 与端口修复一并做（每次启动随机凭据 + Origin 白名单） |
| 核心换树回滚的真机演练 | 未做 | 构造一个同版本号但截断的容器 ⇒ 启动后旧树仍在、`failed` 有原因 |
| 保活：熄屏 >10 分钟续期 | 未做 | `diag-keepalive` 出现 `cancel reason=… userStopped=false` → `renew 计划` → `renew 成功` |
| `__DSHM_BRIDGES__` 报错归零 | 未做 | 重启后后台放 10 分钟，`grep -c "native proxy object not found"` **零增量** |
| AGC/Beta 出包 | 未做 | 按用户节奏另行出包 |

---

## 6. 改动文件清单

**产品代码**
- `hostruntime/src/main/ets/core/BundledCore.ets`（换树顺序 + 回滚 + `installOneVersion`）
- `hostruntime/src/main/ets/core/CoreStore.ets`（拆 `stage` / `commitStaged`）
- `hostcore/app/dshm-installer.js`（`integrity`/`shasum` + `verifyTarballIntegrity`）
- `entry/src/main/ets/entryability/EntryAbility.ets`（代次 + `appBackgrounded` + 晚到回收）
- `phone/src/main/ets/entryability/EntryAbility.ets`（`noteBackground` 接线）
- `entry/src/main/ets/pages/WebApp.ets`、`phone/src/main/ets/pages/WebApp.ets`（桥探测退避）

**工具 / 门禁**
- 新增：`tools/check-bundled-core-rollback.mjs`、`tools/check-keepalive-wiring.mjs`、`tools/check-installer-integrity.mjs`
- 修改：`tools/check-permission-surface.mjs`、`tools/check-bridge-methodlist.mjs`、`tools/check-profile-pnpm-bridge.mjs`、`tools/pack-core.mjs`
- `.github/workflows/gates.yml`（三条新门禁 + 各自的自检）
- `entry/src/main/resources/resfile/resources/app/dshm-installer.js`（经 `place-host-app` 同步）

**文档**
- `README.md`（权限口径 8 条 → entry 17 / phone 9；交付件路径）
- 本文 `docs/292`

---

## 7. 一句话交接

review 与 `docs/291` 里**真实存在**的问题已全部落地并有门禁守着（核心换树回滚、保活接线、
插件完整性、phone 权限面、桥探测退避、pnpm 门禁卡死）；
报告里 `fetch` 相关的四条经本机实测**不成立**，本轮没有为它们改任何代码；
**Beta 浏览器桥按你的口径暂不修**。

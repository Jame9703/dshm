# 156 PC 档冷启动闪退双根因（node-pty socket 未赋值 · client-hmr 轮询风暴）

## 结论

PC 档「点侧边栏终端 → 显示正在启动 → 随后闪退」「启动巨慢」「内存又炸了」三条现象，
是**两个互相独立**的端侧缺陷叠出来的，两个都在 `tools/pack-core.mjs` 里修掉：

1. **node-pty 的 socket 未赋值就 destroy** —— `node_modules/node-pty/lib/unixTerminal.js` 在
   `DESTROY_SOCKET_TIMEOUT_MS`（200 ms）到点后**无条件**执行 `this._socket.destroy()`。
   端侧 pty 探针（`hostcore/app/main.js` 的 `runtimeFacts()`）在这台设备上拿不到 socket，
   `_socket` 仍是 `undefined` ⇒ 回调里抛
   `TypeError: Cannot read properties of undefined (reading 'destroy')`。
   这条抛在 **N-API 回调**里，被 Node 记成 `uncaughtException`（`[DEP0168] Uncaught N-API callback exception`）
   ⇒ **宿主线程直接死**，于是 `runProfile 已返回 但没有 webServer`、界面停在「正在启动」后消失。
   时序证据（`dist/acceptance/pc-node-output.log`，pid=25954）：
   `BOOT_40_PROFILE_BOOT +1053ms` → `[DEP0168]` → **恰好 +200 ms** →
   `unixTerminal.js:114:35 TypeError` → `BOOT_50_DSH_INIT runProfile 已返回 但没有 webServer`。

2. **`@deepseek-ai/dsh-client-hmr` 的 bundle 轮询风暴** —— 该插件由
   `dsh-web-app/cordis.patch.yml` **总是挂载**，默认 `pollIntervalMs: 500`，
   每拍对 bundle 目录做**全量 `statSync`**。端侧没有 `dev:web` 重建器，
   这些 statSync **100% 是白工**。真机读数：
   `LOOP-GAP 4262ms` + `SYNC-COUNT statSync×23117=4114ms`，
   紧接着 `LOOP-GAP 11503ms` + `statSync×23185=8016ms`，
   同一时段 `RenderExited pid: 35761 exitSig: 9`（WebView 渲染进程被系统 OOM 杀掉）。
   调用栈（`tmp-pcverify/prof1.cpuprofile`，149933 samples）：
   `statSync@node:fs:1717 ← (anon)@app/main.js:986 ← bundleStat@dsh-client-hmr/lib/index.js:28
   ← pollWatches@…/lib/index.js:79 ← listOnTimeout@processTimers`。

**「内存炸了」的归因要说清**：真机上一次 `MemFree` 掉到几十 MB，主因**不是** App 主机内存失控，
而是设备系统的 `virus_protection_executor`（uid 1250）RSS 涨到 16.5 GB 被 OOM 后**循环重启**，
把整机压死、App 跟着被系统回收。statSync 风暴是叠在这一层系统级风暴上面的**本仓缺陷**，
它让宿主事件循环每几秒停摆一次，观感「启动巨慢」。两条都要处理，但只有后者归本仓。

行为变化进入包体，`coreVersion` 升到 `0.2.1-alpha.2+dshm.46`。

## 修改

1. `tools/pack-core.mjs` 新增两处注入补丁（编号 ⑲「宿主稳健性」），锚点唯一性用
   `(text.split(before).length - 1) !== 1 ⇒ die()` 把关，**拒绝静默跳过**。

   - `patchNodePtySocketGuard()`（标记 `DSHM_NODE_PTY_SOCKET_GUARD`）：
     把那条无条件 `_this._socket.destroy();` 包进
     `if (_this._socket !== undefined && _this._socket !== null) { … }`。
     **只加守卫，不删定时器** —— 上游那条 macOS 兜底逻辑原样保留。
   - `patchClientHmrPoll()`（标记 `DSHM_CLIENT_HMR_POLL_OFF`）：
     在 bundle-watches 那个 `ctx.effect(() => {` 之后插入
     `if (process.env.DSHM_CLIENT_HMR_POLL !== "1") return () => {};`。
     **只关轮询 effect，不动 `/plugins/events` 那条 SSE effect** ——
     前端热重载订阅面（`onRebuilt`）一个字节不碰，需要时置 `DSHM_CLIENT_HMR_POLL=1` 即恢复旧行为。

2. `hostcore/core-recipe.json`：`coreVersion` `+dshm.45` → `+dshm.46`。

3. `tools/check-core-openharmony-patches.mjs`：门禁从 **24 处扩到 26 处**，新增两个
   **结构判据**而不是字符串计数 ——

   - `nodePtyGuardStructural()`：要求「定时器还在 **且** 守卫在回调体内 **且** destroy 在守卫里」
     三者**同时**成立 ⇒ 堵死「为过判据把整段 `setTimeout` 删掉」这条捷径（那会废掉上游兜底）。
   - `clientHmrPollStructural()`：要求 `/plugins/events` effect 仍在、`onRebuilt` 订阅仍在、
     `setInterval(pollWatches, pollIntervalMs);` 订阅点仍在 ⇒ 惰性门只决定「跑不跑」，
     不许有人顺手把热重载骨架拆掉。
   - `shapeCases` 新增 3 条定点变异：守卫挪出定时器 / 轮询订阅点被删 / SSE effect 被误删。

## 验证

- `node tools/check-core-openharmony-patches.mjs`：**199 passed / 0 failed**（标语已显示 26 处）。
- `node tools/check-core-openharmony-patches.mjs --self-test`：**PASS（190 用例，0 不合格）**。
- `node tools/pack-core.mjs --skip-install --place-in-app`：两条补丁日志均打印
  「node-pty 补丁：unixTerminal.js 的 socket destroy 容忍未赋值」/
  「client-hmr 补丁：bundle 轮询默认关闭」。
- 产物：`dsh-core-0.2.1-alpha.2+dshm.46-openharmony-arm64.zip`，58,874,646 B / 17112 条目 /
  sha256 `7b60b4ab826595574eed3315543af6a170e111cdf00bb6f637c9effa399d5b98`，已放入
  `entry/src/main/resources/resfile/`（旧 `+dshm.45` zip 由 `pack-core` 自动清掉）。
- `hvigorw assembleHap … --no-daemon`：`BUILD SUCCESSFUL in 17 s 559 ms`，
  `entry-default-signed.hap` = **406,920,286 B** / sha256 `0F6C4917743935A255D3ED81A1785F2FD10B4336C11601989DB4FFE4079126B3`。

## 真机

装机走 `hdc file send` + 设备侧 `bm install -p … -r`（**覆盖安装**：不卸载、不删 el2 用户数据；
避开 `hdc install` 把主机压死）。装机后核对 el2：`dsh/`（cores + home）、`toolchain/`、`vm/`、
`dshm-host.log` 全在。

**冷启动第 1 次**（18:36:00，pid=55140）：

| 读数 | 值 |
|---|---|
| 核心解出 | `dsh/cores/0.2.1-alpha.2+dshm.46` |
| `uncaughtException` | **0** |
| `SYNC-COUNT` / `LOOP-GAP` | **0**（两个都没再出现） |
| 启动 | `BOOT_70_HTTP_READY GET / → HTTP 401（78ms）（+3949ms）` |
| 侧边栏终端 | `IN-DONE POST /api/terminal/create 6291ms status=200` |
| guest | `QGA 就绪（+4852ms）` → `终端会话已建立（#1 /dev/hvc0，argv=/bin/sh -i，shell pid=75，前台进程组=75）` |
| 事件循环 | `LOOP-ALIVE 第 20 拍` |

**冷启动第 2 次**（18:39，端侧验收脚本重启，pid=58396）：`BOOT_70_HTTP_READY +3060ms`、
`uncaughtException` 0、`QGA 就绪（+5573ms）`、`terminal/create 7033ms status=200`、
`LOOP-ALIVE 第 100 拍`。

**statSync 风暴消失的读数对照**（本次唯一一条 SYNC-COUNT，78 秒窗口内）：

| | 修前 | 修后 |
|---|---|---|
| 触发频率 | 每 500 ms 一拍，反复 | 78 s 内 1 次 |
| `statSync` | `×23117 = 4114ms` / `×23185 = 8016ms` | `×937 = 26ms` |
| `LOOP-GAP` | 4262 ms / 11503 ms（反复） | 1795 ms（1 次，总同步耗时 518 ms） |
| 头号耗时项 | `statSync` | `spawnSync×6=183ms` / `readFileSync×2989=148ms` / `realpathSync×1983=117ms` |

**内存采样**（2 s 一拍 × 90 s，App 已起 VM + 渲染进程）：

| | 读数 |
|---|---|
| 宿主 `.dshm.dshclient` RSS | 692 → 701 → 685 → 687 MB，**平走无爬升** |
| `MemFree` | 11.9 → 12.0 GB（略升） |
| `virus_protection_executor` | 17–19 MB / 119–124 MB（**正常**，未复现系统级风暴） |

**端侧验收**：`dist/acceptance/20261014-183906` —— 自动判定 **5/5 PASS**
（设备在线 / 核心已启动 / 客户端已接入 / 平台标识 = ohos / 无异常退出）。

**代码指纹**：`tools/device-code-fingerprint.ps1` → **一致（13/13）/ RC=0**，
设备跑的正是本机这份 `+dshm.46` 树（`token 来源：host-ready.json`）。

## 未做 / 边界

- 本轮未承诺、也未验证 PC 档 release（8 权限）档的 guest VM 可用性 —— 装机件是
  `buildMode=debug`。`docs/154` 的 TCG 执行页拒绝对 release 档的判决不变。
- `LOOP-GAP-1795ms` 这类**单次**停顿未归零（总同步 518 ms，其余时间在 QEMU worker 与
  原生调用里）；它是单发、不反复，与修前那种「每几秒停摆一次」不同量级，本轮不再追。
- `docs/138` 登记过的 `LOOP-GAP-1198565ms` / `statSync` 单次 100 s 是**另一条**性质的问题
  （宿主性能），本轮没有触碰。
- 权限面**恒 8 条**，本轮未增未减；全仓无名字含 `apk` 的文件/目录。
- 未 commit / 未 push。

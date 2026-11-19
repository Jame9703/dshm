# 200 · Python 桥异步化（LOOP-GAP 根因二）

> 日期：2026-10-19 ｜ 工作区：`D:\desktop\ohos\desktop.ohos.arm64`（beta） ｜ 核心版本：**未升**（仍 `0.2.1-rc.2+dshm.76`）
>
> 本轮只动 Host 侧（`hostcore/app/**` + 门禁 + 文档）：**不碰** `entry/`、`platform/` 的 ArkTS，**不改**核心树 zip，**不 commit / 不 push**，**不加权限**（权限面恒 8 条）。
>
> 同日的另一条 LOOP-GAP 根因见 `docs/199`（同步 fs「探测型」调用：`existsSync` / `statSync` 扫慢存储）。两条是**两个不同的病**：199 是"单次同步系统调用慢"，本篇是"整段 Python 在主线程里跑几分钟"。

## 1. 现象（内测日志）

证据文件：`dist/triage/2026-10-19/logs1019/DSH日志-20261019/node-output.log`。

```
[2026-10-19T06:13:03.458Z] LOOP-GAP 33277ms（事件循环停顿；第 9413 拍；js-tid=11184）
[2026-10-19T03:37:44.979Z] LOOP-GAP 522814ms（事件循环停顿；第 7212 拍；js-tid=11184）
（另有 800711ms 那一处，同一台设备同一份日志，由分诊表登记）
```

三处停顿**都**伴随 `/dshm-python/*` 的 `pip install`：

```
[2026-10-19T06:11:07.674Z] IN-REQ GET /dshm-python/run-get?token=…&code=from pip._internal.cli.main import main…
[2026-10-19T06:13:03.458Z] LOOP-GAP 33277ms（事件循环停顿；第 9413 拍；js-tid=11184）
[2026-10-19T06:13:03.459Z] LOOP-GAP-33277ms SYNC-SLOW-LOG 36839ms existsSync ~/.node_modules/…
```

关键读法：**`IN-REQ` 与 `LOOP-GAP` 之间没有第二行日志** —— 事件循环从"接单"那一刻起就没再跑过一拍（看门狗自己也在主线程，只能事后补记一笔）。`js-tid` 全程是同一个主线程 tid。

> 注意：`SYNC-SLOW 36839ms existsSync …` 是**同一段停顿里**的第二个慢点（属于 `docs/199` 的写面），不是本篇的原因。两者叠在一起才让那次停顿长到 33 秒；本篇只解决"Python 在主线程执行"这一条，199 解决"同步探测扫慢存储"那一条。

## 2. 根因

`hostcore/app/main.js` 的 Python HTTP 桥端点（`/dshm-python/run-get`、`/dshm-python/exec`）在**主线程**同步调用 NAPI：

```js
// 旧实现（示意）
const r = bridge.captureRun(prelude + code);   // ← 同步 NAPI：Python 跑多久，事件循环停多久
```

`python_runner.cpp` 的 `captureRun` 是同步导出（`PyGILState_Ensure` → `PyRun_SimpleString` → `PyGILState_Release`）。所以：

- `pip install` 这类**分钟级**任务 ⇒ 整台 Host 的 Web 请求、心跳、会话、停止通道全部停摆；
- 唯一"超时"手段是 Python 侧 SIGALRM（prelude 里注入 `setitimer`），它只能打断**字节码**执行，卡在 C 层长阻塞时连 alarm handler 都要等它返回；
- 主线程的 `LOOP-GAP` 看门狗与心跳线程也挡不住它（看门狗在主线程排不上队；心跳线程只能证明"整进程没死"）。

**结论：执行位置错了。** 不是超时值不够、也不是 pip 太慢 —— 是 Python 被放在了**唯一的那个线程**上。

## 3. 修法

### 3.1 新增两个文件（都是 `hostcore/app/` 下的 CommonJS）

| 文件 | 角色 |
|---|---|
| `python-worker.cjs` | **worker_threads 入口**：唯一默认加载 `libpython_runner.so`（`process.dlopen`）并执行 Python 的地方；协议服务端 |
| `python-bridge-async.cjs` | **主线程侧**：懒启动 worker、单飞队列、看门狗超时 → `terminate()` + 重建、`status()`、`cancel()`、`shutdown()` |

主线程**只**排队与调度。执行线程变了，**HTTP 响应语义一个字节没变**：返回体仍是 `{ok, stdout, errStderr, rc, error?}`，`timeout` 默认 120、clamp 1..300、超时 `rc="124"`。

### 3.2 协议（两个文件头注写的是同一份，改一边必须改另一边）

```
主线程 → worker:  { type:'run',    id, code, timeoutMs }
                  { type:'status', id }
worker → 主线程:  { type:'result', id, ok, stdout, stderr, rc, error? }
                  { type:'error',  id, message }
                  { type:'ready',  bridge, ready, initialized }   // 加载 addon 后的首帧
                  { type:'status', id, bridge, ready, initialized }
```

- `PROTOCOL_VERSION` 两边都是 `1`，门禁断言一致。
- 协议字段叫 `stderr`，HTTP 字段仍叫 `errStderr` —— 映射只在 `toResultFrame()` 一处做。
- `ready`/`status` 都只调 `isReady()`（addon 注释：**不触发** `Py_Initialize`），所以"探测"不会顺手把解释器拉起来。

### 3.3 为什么是"单飞 + 排队"，为什么超时是 `terminate`

- **单飞**：内嵌 CPython 是**一个**解释器 + 一把 GIL，两个任务"并发"只会互相串 stdout 捕获、串 itimer、串 `sys.argv`（旧实现里这些全是进程级全局状态）。所以同一时刻只允许 1 个任务在 Python 里跑，其余排队（FIFO）。
- **超时 = terminate + 下次重建**：Python 侧 SIGALRM 先到（它保留在 prelude 里，行为与旧实现一致）；主线程看门狗**再多等 3s**（`WATCHDOG_MARGIN_MS`），只有它彻底没回来才 `worker.terminate()`。此时返回 `{ok:false, rc:"124", timedOut:true}` —— rc 口径与旧行为逐字一致。terminate 后解释器随线程消失，**下个任务重建**（慢，但状态干净，不会带着残留 alarm / 重定向 / argv 进下一个请求）。
- **取消**：不再"跑一段取消代码"（旧实现清 itimer 只能清掉**还没触发**的定时器，停不掉正在跑的任务），改成 terminate 当前任务；排队项一并回**明确取消**（`cancelled:true`）。宿主停止链（`requestStop`）也接上了这条。

### 3.4 改到的 4 个调用点（`main.js`）

| 位置 | 旧 | 新 |
|---|---|---|
| python 自检（boot 顶层 + 解包收尾两处挂载） | `bridge.captureRun('print(1+1)')`（主线程） | `pyBridgeSelftestAsync()`：`await bridge.status()` + `await bridge.run({code:'print(1+1)'})`（worker） |
| `/dshm-python/run-get` | `pyBridgeSendJson(…, pyBridgeRun(...))` | `await pyBridgeRun(...)`（`pyBridgeRun` 变 async，内部 `await getPyWorkerBridge().run(...)`） |
| `/dshm-python/exec` | 同上 | 同上 |
| 取消 / 清 itimer 路径 | `bridge.runString('…setitimer(ITIMER_REAL, 0)…')` | 默认通道：worker 的 epilogue 自己清；**取消**改用 `python worker.shutdown()` → `terminate` |

`/dshm-python/status` 也改成 `await getPyWorkerBridge().status()`（字段 `ok / bridge / stdlib / ready / initialized / home` 逐字保留）。

> `ensurePythonBridge()` **保持同步签名**：两个挂载点都是 `try { ensurePythonBridge(); } catch` 的同步形态，改成 async 会引入"没人 await 的 Promise"，而 Node 24 对未处理的 rejection 默认致命。所以同步部分只做前置判据（libs 是否齐备 / stdlib 是否解包就位），真正的自检在 `pyBridgeSelftestAsync()` 里自己 try/catch。

### 3.5 降级开关

```
DSHM_PY_INLINE=1   # 退回旧的同步实现（Python 在主线程跑，会挡事件循环；仅排障用）
```

- **默认异步**（不设 env 就是 worker）。
- 启动时固定打一行，真机验收就 grep 它：

```
python 桥：执行线程=worker（DSHM_PY_INLINE=1 可回退）
```

- 降级分支的范围被门禁钉死：`main.js` 里只允许两个函数出现 `.captureRun(`（`ensurePythonBridgeInline` / `pyBridgeRun` 的 inline 分支），且两处都在 `DHSM_PY_INLINE` 判定之内；`getPyBridge()` 里默认会**拒绝**在主线程 dlopen（首次调用打一行"主线程拒绝加载 addon"）。

### 3.6 打包清单（漏了就静默不生效）

两个新文件必须同时进两份 FILES 清单：

- `tools/place-host-app.mjs`（拷贝到 `resfile/resources/app/`）
- `tools/assert-resfile-sync.mjs`（逐字节比对，两份清单要一致）

**为什么必须单独列**：`python-bridge-async.cjs` 被 `main.js` 顶层 `require` ⇒ 漏掉它 **Host 直接起不来**（一眼可见）；而 `python-worker.cjs` 只在**首个 python 请求**才被 `new Worker(...)` 到 ⇒ 漏掉它启动日志毫无异常，只在真正用 Python 时失败（"静默白修"的同族，见 `docs/199` 对 fs 缓存清单的同样处理）。

## 4. 门禁：`tools/check-python-async-worker.mjs`

离线、不需要真 Python、不需要真机（CI 可跑）。**38 项判据 + 6 个变异对照臂**，另加一条"事件循环不被挡"的正面判据。

| 段 | 判什么 |
|---|---|
| A 协议面（静态） | 两边 `PROTOCOL_VERSION` 一致；run/result 帧字段齐备；worker 是唯一默认执行点（addon dlopen 在 worker 里 1 处、主线程那处被 `DSHM_PY_INLINE` 判定包住）；`errStderr → stderr` 映射在；worker 的 epilogue 清 itimer；未捕获异常也要回 error 帧；主线程桥里 0 处 `dlopen` / 0 处 `captureRun` |
| B 主线程零同步调用（静态） | `main.js` 里 `.captureRun(` 只出现 2 处且都落在降级分支函数里；`pyBridgeRun` 的**默认分支**只有 `await getPyWorkerBridge().run(...)`；两个端点都 `await pyBridgeRun(...)`；itimer 清理只在 inline 分支；取消 = `shutdown()`/terminate；顶层 require 异步桥；worker 脚本路径与会话同目录 |
| C 开关面（**行为**） | 把 `pyBridgeInlineEnabled()` 的真实实现抽出来在隔离作用域里求值：未设 env ⇒ `false`（走 worker）、`=1` ⇒ `true`、`=0` ⇒ `false`、`" 1 "` 也认；启动日志那一行必须在 |
| D 行为面（**假 worker 注入**） | 协议字段与结果映射；单飞（同时只投递 1 个）；FIFO（上一个完成才发下一个，投递顺序 A,B,C）；超时 → terminate + 重建 + `rc="124"`；worker 退出/回 error 帧 ⇒ 明确错误；取消 ⇒ terminate + 排队项一并 `cancelled:true`；status 形状不变且超时不挂住；空 code / 关闭后调用 ⇒ 明确拒绝 |
| D13 **事件循环正面判据** | 起一个**真 worker 线程**在里忙等 700ms（模拟"Python 在跑"），断言主线程 50ms 定时器照常跳（≥3 拍）。旧实现这条必红（主线程被 `captureRun` 占死）。 |
| E 接线面 | 两份 FILES 清单都带两个新文件；`gates.yml` 里真有这一步 |

变异对照臂（`--self-test`，逐个必须判红）：

1. 把 `captureRun` 放回**默认分支**（等于没修）⇒ B1/B3 红；
2. 超时只回结果、不 `terminate` ⇒ D5 红；
3. 排队用 `queue.pop()`（LIFO）⇒ 投递顺序变 A,C,B ⇒ D3 类判据红；
4. worker 报错被静默成 `{ok:true}`（空成功）⇒ D8 红；
5. 降级开关默认翻转（没设 env 也走主线程）⇒ C2 红；
6. worker 的 result 帧不再映射 `stderr` ⇒ A6 红。

CI：`.github/workflows/gates.yml` 里加了 `门禁 · check-python-async-worker` 与 `自检 · check-python-async-worker --self-test` 两步（6 空格 `- name:` / 8 空格 `run:`，与其它步骤同形）。

## 5. 真机验收怎么看（**不需要**真跑 pip 分钟级任务）

1. **启动那一行**（`dshm-host.log` / `node-output.log`）：
   ```
   python 桥：执行线程=worker（DSHM_PY_INLINE=1 可回退）
   ```
   若是"执行线程=主线程"⇒ 有人设了 `DSHM_PY_INLINE=1`，本次不是异步路径。
2. **每次执行一行**（新加 `thread=` 字段，直接回答"这一跑在哪"）：
   ```
   PY-RUN ok=true codeLen=… ms=… outBytes=… VmHWMkB=… ctypes=no thread=worker
   ```
3. **看门狗读数**：长任务期间应持续出现 `LOOP-ALIVE 第 N 拍`（每 20 拍一条），且**没有**紧跟在 `/dshm-python/*` 的 `IN-REQ` 之后的 `LOOP-GAP`。
   旧实现的形态是"`IN-REQ` 之后直接一条几万/几十万毫秒的 `LOOP-GAP`"；修好后同一场景应是"`IN-REQ` … `LOOP-ALIVE`×N … `IN-DONE`"。
4. **接口侧证据**（PC 档回环、或真机 `hdc shell` 里 `wget`）：
   ```
   GET /dshm-python/status        → {"ok":true,"bridge":true,"ready":true,...}
   GET /dshm-python/run-get?token=<live>&code=print(1%2B1)   → {"ok":true,"stdout":"2\n","rc":"None"}
   ```
   关键不是"能跑"，而是**跑的同时 Web UI 仍可点击**（旧实现期间整页无响应）。
5. **超时口径**：`&timeout=1` + `code=import time; time.sleep(30)` ⇒ 设备侧应在 ~1s 左右回
   `rc="124"`（Python 侧 SIGALRM 正常路径），若 Python 侧信号不可用则由看门狗在 `1s+3s` 后 terminate，
   两种都仍是 `rc="124"`；**不会**再出现"整个 Host 卡住 30 秒"。
6. **worker 起不来时不许静默**：把 `libs/arm64/libpython_runner.so` 改名后再请求，应看到
   `PY-RUN ok=false …` + 返回体 `{"ok":false,"error":"python worker：python worker：addon 加载异常：…"}`，
   **不是** `{"ok":true,"stdout":""}`。

## 6. 边界与未做

- **CPU 仍占一个核**：Python 照旧在跑，只是不再占**主线程**。单飞意味着 pip 期间第二个 python 请求要排队（这是刻意的：串 stdout 捕获 / itimer / `sys.argv` 的旧缺陷不会再回来）。
- **worker 线程里的 SIGALRM**：CPython 对 `signal.signal` 有"只能在主解释器主线程"的判定，取决于它如何认定主线程。若端侧判定失败，prelude 的 `except` 分支会打印一行 `[dshm] prelude: signal timeout unavailable:` 并**退化**为"无 Python 侧超时"，超时统一由主线程看门狗 terminate 收口（rc 仍是 `"124"`）。这是设计内的降级，不是缺陷。
- **解释器重建的代价**：terminate 后首个新任务要重新 dlopen/Py_Initialize（秒级）。这是"慢但安全"的取舍；只有超时/崩溃/取消之后才会付这笔钱。
- **没做**：把单飞队列扩成"多解释器池"（收益低、状态隔离成本高）；把 Python 挪到独立**进程**（端侧 execve 被拒，见 `docs/104`，本档做不到）。
- **真机验收未做**（设备侧动作不在本轮范围）：本文 §5 是验收清单，装机后按它逐条看。

## 7. 顺带修了什么（分诊 S-15：`git=FAIL` 是"结构性不适用"被读成了失败）

分诊 `dist/triage/2026-10-19/TRIAGE.md` 指出：`logs1019` + `tar1018` 的 **11/11 个 boot** 全打
`工具链：解包收尾 python=OK，git=FAIL`，而更早一版是 `git=OK`。

**根因**：手持档 spawn 必 EPERM ⇒ 走 `inProcessToolchainFallback()`；回退**故意**只解 python（git 真身 execve 被拒，解出来也起不来，白占 ~100MB）。但收尾函数只有二态，把"本档不该解"记成了 `git=FAIL`；更糟的是 `ensureExecutables()` 的条件是 `pyOk && gitOk` ⇒ 连 **python** 的 chmod / 探测兜底都一次没跑。

**修法（把"结构性不适用"与"失败"分开）**：

- `inProcessToolchainFallback()`：只差 git 待解时打 `工具链：git 归档在手持档不做进程内解包（execve 被拒）；git=SKIPPED` 并调 `finishToolchainExtraction(false, false, true)`；python 解完后若 `needGit`，同一句 `SKIPPED` 文案 + `finishToolchainExtraction(true, false, needGit)`。
- `finishToolchainExtraction(didPy, didGit, gitSkipped = false)`：三态 `gitState = (didGit || gitOk) ? 'OK' : (gitSkipped ? 'SKIPPED' : 'FAIL')`；收尾行变成
  `工具链：解包收尾 python=OK，git=SKIPPED（手持档 execve 被拒；git 仅 PC 档可用）（详见 .extract.log）`；
  `log()` 行同步三态（`就绪 / 本档跳过 / 未就绪`）；`ensureExecutables()` 条件收成 **只看 `pyOk`**。
- 门禁：`tools/check-tar-extract.mjs` 33 → **42** 项。原有的"成功形态"保留（`didGit` 或 `gitOk` ⇒ `OK`），**新增**：SKIPPED 接线（两处调用点真的传第三个参数）、自 `main.js` 抽出三态表达式后求值的三条行为断言（`OK` / `SKIPPED` / 真失败仍 `FAIL`）、收尾文案、`ensureExecutables` 条件、以及一条对照臂（"把失败也洗成 SKIPPED"必须让"真失败仍判 FAIL"失去依据）。`tools/assert-exec-fix.mjs` 第 31 条同步改口径（原断言 `if (pyOk && gitOk)`）。
- **没有真去解 git**（那会白占 ~100MB 且 execve 仍被拒）。

## 8. 相关文件

| 文件 | 改动 |
|---|---|
| `hostcore/app/python-worker.cjs` | **新增**：worker 入口（唯一默认 dlopen + 执行 + 协议服务端） |
| `hostcore/app/python-bridge-async.cjs` | **新增**：主线程侧排队/调度/超时 terminate/status/cancel/shutdown |
| `hostcore/app/main.js` | 4 个调用点异步化；`pyBridgeInlineEnabled()` + 启动日志 + 降级分支护栏；`pyBridgeArtifacts()`；`pyBridgePrelude()`；`getPyWorkerBridge()`；`pyBridgeSelftestAsync()`；requestStop 里 terminate；**另**：S-15 的 `git=SKIPPED` 三态与 `ensureExecutables` 条件 |
| `tools/check-python-async-worker.mjs` | **新增**门禁（38 项 + 6 变异臂 + D13 事件循环正面判据） |
| `tools/check-tar-extract.mjs` | 33 → 42 项（S-15 三态与对照臂） |
| `tools/assert-exec-fix.mjs` | 第 31 条改口径（`ensureExecutables` 触发条件只看 pyOk） |
| `tools/place-host-app.mjs` / `tools/assert-resfile-sync.mjs` | 两份 FILES 清单各加两个新文件 |
| `.github/workflows/gates.yml` | 加本门禁 + `--self-test` 两步 |

## 9. 相关文档

- `docs/199`：同日的另一条 LOOP-GAP 根因（同步 fs 探测缓存）—— 两条一起才是那几处 33s/522s/800s 的完整拼图。
- `docs/104`：手持档为什么不能 spawn / execve（本篇"为什么只能在进程内、只能搬线程不能搬进程"的依据）。
- `docs/106`：`runtime.python` 探针读数口径（`python 桥自检通过/失败` 两行文案的来源）。

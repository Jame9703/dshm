# JD-048 编译与测试：启动分段标记 + 预热让位（对照 WorkBuddy 启动拆解）

- 提交方：WorkBuddy
- 接收方：DevEco
- 时间：2026-11-25 09:20
- 关联：`docs/201-WorkBuddy启动加载顺序拆解与借鉴.md`（调研与借鉴口径）、JD-033/JD-034（此前的启动提速分析与计时）
- 版本：未改（`1.1.8 / 1010020`）
- **本轮不出 Beta / AGC 包**（用户未要求出包），只做编译 + 门禁 + 静态取证

---

## 1. 本轮改动（6 个文件）

| 文件 | 类型 | 改动 |
|---|---|---|
| `platform/src/main/ets/diagnostics/StartupMarks.ets` | 新增 | S0–S7 启动分段记录器：双时间戳（`ts` 相对 / `epochMs` 绝对）、同 id 幂等、JSONL 追加写 `<filesDir>/dsh/logs/startup/<epoch>-<pid>.jsonl`、同时打一条 W 级 `hilog`（tag `DSHM-STARTUP`）、终态才写 SUMMARY |
| `platform/src/main/ets/Index.ets` | 改 | 导出 `StartupPhase` / `startupMarks` |
| `entry/src/main/ets/entryability/EntryAbility.ets` | 改 | ① 埋 S0（onCreate 首行）/ S1（启动参数发布后）/ S2（onWindowStageCreate）/ S3（loadContent 回调）/ S4（宿主链 setTimeout 开头）/ S5（`KEY_HOST_LAUNCH_URL` 发布后）；② `probeNativeBindings()`（纯日志）移出 onCreate 同步段；③ `warmWebEngineOnce()` 由「紧跟 `autoStartHostForDiagnosis()`」改为「下一个宏任务」 |
| `entry/src/main/ets/pages/WebApp.ets` | 改 | 埋 S6（`onPageBegin`）/ S7（`onPageEnd` → `READY` 后 `finish('ready')`） |
| `tools/startup-report.mjs` | 新增 | 读 JSONL 出 S0→S7 表；`--baseline` 输出逐段差值 |
| `tools/check-startup-work.mjs` | 改 | **修既有失败**（非本批引入，见 §6） |

**没有改动**：三端布局与 UI 结构、`hostcore/**`（不重打核心容器）、`module.json5` / 权限面、`web` 垫片、`appstate`。

---

## 2. 改动依据（不是凭感觉）

| 结论 | 证据 |
|---|---|
| `initializeWebEngine()` 同步占用 UI 线程 **106–118 ms** | `dist/acceptance/startup-1010017/pc-run1-hilog.txt`（109 ms）、`pc-run2-hilog.txt`（118 ms）、`dist/acceptance/20261124-phone-sigsys-io-uring/phone-hilog-live-full.txt`（106 / 110 ms） |
| 该调用原先位于宿主链 Promise 回调前方 | `EntryAbility.scheduleHostStartAfterFirstFrame`（原顺序：`autoStartHostForDiagnosis()` → `warmWebEngineOnce()`） |
| 首帧后再起宿主已是既有设计 | 同一方法内注释与 `HOST_START_DELAY_AFTER_FIRST_FRAME_MS = 32` |
| 启动期无可测量分段 | 全仓只有零散 `DSHM-TRACE` 文本，无阶段/无 summary（`docs/201` §5.2 G2） |

---

## 3. 编前门禁（本地已全绿，12/12）

```bash
node tools/assert-resfile-sync.mjs        # 27 件快照全部同步
node tools/check-arkts-entry.mjs          # entry ArkTS 编译 0 error
node tools/check-boot-rescue.mjs          # PASS 13 / 0
node tools/check-startup-work.mjs --self-test   # 10 mutants rejected
node tools/check-brand-surface.mjs        # 110 项断言全过
node tools/check-dual-shell-parity.mjs    # 双壳 7 个共享文件逐字节一致
node tools/check-feature-wiring.mjs       # 177 文件 / 24 功能接线完整
node tools/check-dead-code.mjs            # 2588 处声明无零使用
node tools/check-doc-refs.mjs             # 引用落点一致
node tools/check-parity.mjs               # 缺口登记 37 个 id
node tools/check-permission-surface.mjs    # entry 19 / phone 9
node tools/check-tools-syntax.mjs         # 210 个脚本语法通过
```

> `check-startup-work` 在本轮开始前是 **FAIL**（`7 !== 6`），属 2026-11-25 凌晨「工具链解包后置到 `startupWork`」的遗留，详见 §6。

---

## 4. 编译结果

```bash
devecocli build --product default      # 143 tasks, 66 executed / 77 up-to-date → BUILD SUCCESSFUL
devecocli build --modules phone@default # 81 tasks, 30 executed / 51 up-to-date → BUILD SUCCESSFUL
```

> 当前 `build-profile.json5` 只有 `default` 一个 product（`phone` 模块的 target 也 `applyToProducts: default`），
> 因此手机壳验证走 `--modules phone@default`；`--product phone` 会报 `Product 'phone' not found`。

产物（2026-11-25 09:16）：

| 产物 | 大小 | sha256（前 16） |
|---|---|---|
| `build/outputs/default/DSHM-deveco-workspace-default-signed.app` | 647,660,933 B | `02692731d648be1e…` |
| `entry/build/default/outputs/default/entry-default-signed.hap` | 57,081,428 B | `fe7d30ce5f618e90…` |
| `phone/build/default/outputs/default/phone-default-signed.hap` | 5,709,343 B | `818927b7da45ff54…` |

**产物内容核验**：
- `entry` 的 `ets/modules.abc` 含 `StartupMarks` / `DSHM-STARTUP` 标记 ⇒ 新模块确实进包。
- `phone` 的 `ets/modules.abc` **不含** —— 因为 phone 壳未 import `startupMarks`，ArkTS 摇树不打包未引用模块。
  这是预期行为，**不是旧产物**（phone 构建 30 tasks executed，产物字节与 08:54 一致 ⇒ 内容未变）。

---

## 5. 验收（DevEco 侧）

### 5.1 出包（仅当用户要求）

```bash
node tools/build-beta.mjs    # Beta
node tools/build-agc.mjs     # AGC（release）
```

本轮无 `hostcore/**` 改动 ⇒ **不需要重打核心容器**（`tools/pack-core.mjs` 不必跑）。

### 5.2 取数与出表（核心验收项）

```bash
# 1) 冷启两次（第二次为 warm 对照），然后取回日志
hdc file recv /data/app/el2/100/base/com.dshm.dshclient/haps/entry/files/dsh/logs/startup ./dist/startup-logs
#    beta 包把包名换成 com.dshm.dshmbeta

# 2) 出表
node tools/startup-report.mjs dist/startup-logs/<本次>.jsonl
#    有对照时
node tools/startup-report.mjs dist/startup-logs/<本次>.jsonl --baseline dist/startup-logs/<基线>.jsonl

# 3) 与 hilog 互证（W 级端侧可见）
hdc shell "hilog -x -T DSHM-STARTUP"
```

期望看到的标记序列（缺任何一段即为该段未到达）：

| id | 事件 | 判据 |
|---|---|---|
| S0 | onCreate 入口 | 必有，`ts` 为 0 |
| S1 | 静态配置 + 启动参数发布 | 应 < 50 ms（本轮把 `probeNativeBindings` 移出后才可能达到） |
| S2 | `onWindowStageCreate` | 与 S1 之间是窗口创建 |
| S3 | `loadContent` 回调 | 页面树就绪 |
| S4 | 宿主链调度 | 与 S3 相差 ≈32 ms（`HOST_START_DELAY_AFTER_FIRST_FRAME_MS`） |
| S5 | 宿主就绪、URL 已发布 | **S4→S5 是主成本**（历史约 8 s，首启解包 30–60 s） |
| S6 | Web 开始导航 | 与 S5 相差应很小（`@Watch` 触发） |
| S7 | 首屏就绪 + SUMMARY | 缺失即"没到 READY" |

**通过口径**：
1. S0→S7 能在单文件内还原，误差 ≤ 5 ms；
2. **S4→S5 相比改动前基线下降 ≥ 80 ms**（预热让位的目标；实测依据是 106–118 ms，留出抖动余量）；
3. S7 存在且 `SUMMARY.spans` 非空（若为空，说明 SUMMARY 被提前 flush，需回报）。

### 5.3 回归项（本轮改动了启动路径，必须覆盖）

1. **首启**：无核心 → 解包 → 进主界面（启动页不闪、进度条不倒退）；
2. **二次启动**：直接进主界面（S7 有值）；
3. **应用内整页跳转**：不应闪启动页（`everReady` 逻辑未改，但 S6/S7 会重复触发，`mark` 幂等应不重复写）；
4. **加载失败**：断网或 Host 未起时仍走 ERROR 覆盖层 + 自动重试（`onPageEnd` 的 `loadFailed` 分支未改）；
5. **多窗**：开 2–3 个会话窗，`startupMarks` 不应产生重复 S0/S5（同 id 幂等只在同进程内保证，多窗同进程 ⇒ 正确）；
6. **手机壳**：编译通过即可，本轮未改 phone 行为。

---

## 6. 顺带修复（既有失败，非本批引入）

`tools/check-startup-work.mjs` 在 2026-11-25 凌晨「工具链解包后置到 `startupWork.request('toolchain', …)`」之后失效：

| 现象 | 根因 | 修法 |
|---|---|---|
| `requests.length` `7 !== 6` | 新增了一条 `startupWork.request('toolchain', …)` | 6 → 7 |
| `boot` 切片为空 | 锚点是裸调用字面量 `'  scheduleToolchainExtraction(resRoot, binDir, true);'`，已被包进 `request(...)` | 锚点改为 `startupWork.request('toolchain'` |
| `ensurePythonBridge` `2 !== 1` | 解包收尾新增了"补挂 Python 桥"的第二个挂载点（设计如此） | 1 → 2，并注明两个挂载点 |
| 需要一个 toolchain 桩 | vm context 缺 `scheduleToolchainExtraction` / `resRoot` / `binDir`，否则报 ReferenceError 被计入 errors | 补三个桩，期望数组与 `calls.length` 同步 +1 |

修后：`--self-test` 10 个 mutant 全部被拒。已记入 `docs/PITFALLS.md` §2.12「门禁断言写死代码形态，改实现即静默失效」。

---

## 7. 边界与未做项

| 项 | 状态 | 原因 |
|---|---|---|
| 真机 S0–S7 读数 | **未做** | 当班 `hdc list targets` 静默、`devecocli device list` 报 `No active devices`、`devecocli run --module entry` 同 |
| 壳内骨架屏（`docs/201` §6-A2） | 未做 | 需改 `WebApp.build()` 的 `if (phase !== BOOTING) Web(...)`，三端布局均受影响，无设备无法验收视觉 |
| 启动页最短展示防闪（§6-A3） | 未做 | 纯观感项，需真机确认不会让启动页多停留 |
| 凭据与 URL 分离（§6-A5） | 未做 | 行为变更（会话建立方式），按流程需先出方案确认 |
| Node 编译缓存（§6-B1） | 未做 | 需实测 `NODE_COMPILE_CACHE` 在鸿蒙沙箱的可用性 |
| 启动看门狗（§6-A4） | 未做 | 与本节改动无耦合，建议与 A2 同批 |

---

## 8. 请 DevEco 回报

1. 是否有设备可用；若可用，贴 `startup-report` 的完整输出（含 `--baseline` 对比）。
2. `S4→S5` 的实测值，以及是否达到「下降 ≥ 80 ms」。
3. 5.3 的 6 项回归结果（尤其 1/4/5）。
4. 若 `SUMMARY` 缺失或 `spans` 为空，回报 `startup/<...>.jsonl` 原文。

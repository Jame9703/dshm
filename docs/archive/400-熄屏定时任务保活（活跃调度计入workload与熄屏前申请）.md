# 400 · 熄屏后定时任务停摆：活跃调度计入保活诉求

- 日期：2026-11-08
- 输入：`熄屏运行情况排查报告-20261108.md`（平板 / 2in1，宿主 19:22 启动；三次熄屏全部冻结，19:30:30 的定时任务 19:33:19 才补跑）
- 状态：**已修代码 + 门禁；Beta 构建验证中，待真机复测**

---

## 1. 根因（报告已定位，这里只补代码侧结论）

熄屏时 DSH 被系统整体冻结，事件循环、心跳、定时器全部停摆。保活链是：

```text
Host 写 $DSH_HOME/workload.json 的 refs
  → ArkTS workloadRefs()
  → maybeAcquireHandheldKeepAlive() 的 busy
  → KeepAlive.acquireTaskKeeping()
```

旧 `refs` 只有 `turnRunning + pendingInstalls`：**"等一个稍后到点的定时任务"不算在途事实**。
熄屏那一刻没有 turn、没有安装 ⇒ `refs=0` ⇒ 判成"无保活诉求" ⇒ 不申请长时任务 ⇒ 冻结。
另外，熄屏事件本身只做 `noteScreenState()`，不触发按需申请；用户在前台直接锁屏时
`onBackground` 也不一定先到。

### 1.1 更直接的根因：ArkTS 读错了 workload 路径

Host 的 `HOME_DIR` 是 `<filesDir>/dsh/home`，`workload.json` 写在
`<filesDir>/dsh/home/workload.json`；而 `EntryAbility.workloadRefs()` 读的是
`<filesDir>/workload.json`。**差一级目录 ⇒ 文件永远读不到 ⇒ `refs` 恒为 0。**

真机报告里 `dsh/home/workload.json` 明明已有 `refs=1 turnRunning=1`，ArkTS 侧却始终
判"无保活诉求"，就是这一级路径差造成的（2026-11-03 的"并入 Host 在途事实"因此从未生效）。
本次一并修正，并把路径写进门禁。

## 2. 改动

### 2.1 Host：把活跃调度写进 workload

`hostcore/app/main.js`

- 新增 `readScheduledWork()`：读 `$DSH_HOME/storages/schedule.json`（domain=`schedule`、table=`tasks`），
  只统计 `status === 'active'` 且 `record.scheduledAt` 可解析的任务，取最早一条。
- `workload.json` 新增：
  - `scheduledTasks`：活跃调度条数
  - `nextScheduleAt`：最早一条的 UTC 时刻
- `refs` 改为 `turnRunning + pendingInstalls + (scheduledTasks > 0 ? 1 : 0)`。
  读到损坏 / 不认识的调度文件一律按 0，不会把应用变成"永远忙"。

### 2.2 ArkTS：保活判据纳入调度 + 熄屏补申请

`entry/src/main/ets/entryability/EntryAbility.ets`

- `workloadRefs()` / `workloadSchedules()` / `workloadNextSchedule()` 的读取路径统一为
  `<filesDir>/dsh/home/workload.json`（修掉少一级 `dsh/home`、refs 恒为 0 的根因）。
- 新增 `workloadSchedules()` / `workloadNextSchedule()`，读 Host 的新字段。
- `maybeAcquireHandheldKeepAlive()` 的 `busy` 增加 `schedules > 0`；
  `needs` 诊断行追加 `schedules=N next=<ISO>`。
- 新增 `maybeAcquireBeforeScreenOff()`：
  - 手持档（平板 / 手机）走原有按需申请；
  - PC/2in1 若启动时申请失败，再补一次（每个前台周期只补一次，避免 refs 膨胀）。
- `setupScreenWatcher()` 的熄屏分支先调用 `maybeAcquireBeforeScreenOff()`，再校准任务；
  亮屏且仍在前台时释放熄屏临时申请的手持档保活。
- 新增 `screenOffed` 标志：熄屏期间申请的保活，在晚到检查里按"不可见"处理，
  不会被 `!appBackgrounded` 误判成"已回前台"而立即回收；亮屏后清除。

### 2.3 KeepAlive：避免熄屏与 onBackground 并发申请

`platform/src/main/ets/notify/KeepAlive.ets`

- 新增 `pendingAcquire`：申请在途时 `noteScreenState()` 只记诊断、不重复
  `startBackgroundRunning`。两条并发时后到的一条会报"任务已存在"并把 `active` 覆写成
  false（任务其实在跑），后续判据全错。

## 3. 门禁

- `tools/check-workload-refs.mjs`：要求 `refs` 含活跃调度项、负载含 `scheduledTasks` /
  `nextScheduleAt`、读取路径仍是 `storages/schedule.json` 且过滤 `status !== 'active'`；
  新增 2 个变异体（丢调度项 / 删调度读取）必须判红。
- `tools/check-keepalive-wiring.mjs`：entry 壳必须读 `workloadSchedules()`、
  `busy` 含 `schedules > 0`、熄屏分支调用 `maybeAcquireBeforeScreenOff()`；
  新增 2 个变异体必须判红。

## 4. 验证

本地：

```bash
node tools/check-workload-refs.mjs && node tools/check-workload-refs.mjs --self-test
node tools/check-keepalive-wiring.mjs && node tools/check-keepalive-wiring.mjs --self-test
```

真机（按报告第七节）：

1. 建一个 2 分钟后到点的定时任务，不要保持 turn 运行；
2. 熄屏 ≥2 分钟；
3. 唤醒后看 `diag-keepalive` 是否出现 `schedules=1 next=…` 与 `active=true`；
4. 看任务是否按点送达（`scheduledAt` 与 `deliveredAt` 差值应远小于熄屏时长）；
5. 对照：无任何定时任务时熄屏，`diag-keepalive` 仍应记"无保活诉求"，不应常驻通知。

## 5. 边界（如实登记）

- 平板若只能用 `DATA_TRANSFER`（`TASK_KEEPING` 被系统拒），仍受"10 分钟无进度被取消"
  的官方约束；本次能保证"熄屏前已申请、且不被误判为空闲"，超长保活仍取决于设备是否
  授予 `taskKeeping`。`diag-keepalive` 会记录实际 `mode=`。
- `schedule.json` 是上游 `@deepseek-ai/dsh-schedule` 的持久域。上游若改域名 / 表名，
  Host 读取会退化为 0（不会崩），需同步更新 `readScheduledWork()` 与门禁。
- 手机壳（`phone/`）的保活仍按自身 `card-state` 轮询，未纳入本次调度判据；本次只覆盖
  `entry`（平板 / PC / 2in1）。如需手机同样按点执行，另开一轮。

## 6. 手机端隔离（用户口径：手机后台任务正常，不能改坏）

- `phone/src/main/ets/entryability/EntryAbility.ets` **未修改**，调用仍是
  `noteScreenState(off)`。
- `KeepAlive.noteScreenState()` 新增的 `skipIfPending` 参数**默认 false**：
  手机不传 ⇒ 完全走原有分支；只有 entry 熄屏分支显式传 `true`。
- Host 的 `workload.json` 只**新增字段**，原有 `refs` / `turnRunning` /
  `pendingInstalls` 保留；手机壳不读这个文件，行为不受影响。
- 已由 `check-keepalive-wiring.mjs` 钉住：phone 不得出现 `noteScreenState(off, true)`。

## 7. 本轮产物

```text
dist/beta/DSHM-beta-1.1.8-1010015-20261108T115725/
  DSHM-beta-1.1.8-1010015-combined-debug.app   546M
  tablet/  entry HAP + hostruntime HSP
  phone/   phone HAP + hostruntime HSP
```

包内实测：entry `tablet+2in1` / 17 权限；phone `phone` / 9 权限；
HSP 内 `main.js` 已含 `readScheduledWork` 与 `scheduledTasks`。

## 8. 复测建议（按用户报告第七节）

1. 建一个 2 分钟后到点的定时任务，不要保持 turn 运行；
2. 熄屏 ≥2 分钟；
3. 唤醒后看 `diag-keepalive`：应出现 `schedules=1 next=…` 与 `active=true`；
4. `scheduledAt` 与 `deliveredAt` 差值应远小于熄屏时长；
5. 对照：无定时任务时熄屏，仍应记"无保活诉求"，不常驻通知；
6. 手机端回归：跑一轮后台任务，确认行为与旧版一致。

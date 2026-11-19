# 209 · MatePad Edge 后台保活根因：DATA_TRANSFER 十分钟取消转为 TASK_KEEPING

> 输入：2026-10-20 内测日志包、`DSHM内存问题报告.md`。
> 结论：报告里的 `.73` 与 Beta 日志里的 `.78` 不是同一内核；当前附加日志已推翻
> “ArkWeb 在真正后台仍按 120Hz 出帧”的描述。可复现的主因是 PC/2in1 错误申请了
> `DATA_TRANSFER`，约 600 秒后被系统取消，随后进程被整段冻结。

## 1. 版本与证据边界

| 项 | 值 |
|---|---|
| 报告内核 | `0.2.1-rc.2+dshm.73` |
| Beta 日志内核 | `0.2.1-rc.2+dshm.78` |
| Beta HAP | `1.1.4 / 1010004`，`com.dshm.dshmbeta` |
| 设备 | MatePad Edge 系列，PC/平板双形态 |

`.73` 报告不能直接归因到 `.77/.78` 的源码。本文只采用日志包中能逐行定位的
`.78` 现场，并补当前构建。

## 2. ArkWeb 是否在后台继续出帧

日志包里的 `node-output.log*` 同时记录了 `OnWindowHide` 与每一个
`ExternalBeginFrameSourceOHOS::OnVSyncImpl`。按行号分段统计：

| 日志 | 前台 SHOW 段 vsync | HIDE 后 vsync |
|---|---:|---:|
| `node-output.log.3` | 36,084 | 0（两次 HIDE） |
| `node-output.log.2` | 424 / 83 | 0（两次 HIDE） |
| `node-output.log.1` | 26,166 | 0 |
| `node-output.log` | 629 / 40 | 0（两次 HIDE） |

真实 `HIDE` 事件之后都会出现：

```text
NWebImpl::SetVisibility ... visible:0
WebContentsImplExt::SetPageVisibility, is_page_visible_:0
NWebDelegate::OnWindowHide
SetVsyncEnabled 0, vsync_cnt_: 0
SetFrameRateLinkerEnable 0
```

⇒ `InvisibleThrottle already:0,ratio:1` 只说明当时没有进入 invisible throttle；
不能脱离 `SetVisibility` 状态把它解释成“后台继续 120Hz”。ArkWeb 在真正收到
`OnWindowHide` 后已经停 vsync。

## 3. 冻结为什么从约 10 分钟后开始

应用把 PC/2in1 后台保活申请成 `DATA_TRANSFER`。官方《长时任务(ArkTS)》对
该类型写明：首次进度超过 **10 分钟**未更新，长时任务会被取消；进度更新还必须
使用实况窗通知。本应用后台执行的是 Agent / 模型计算，没有上传下载进度。

hiLog 的启动/停止配对：

| 启动 | `HandleSubscribeOnContinuousTaskStop` | 间隔 |
|---|---|---|
| 10:29:49 | 10:39:52 | 603 s |
| 11:12:23 | 11:22:26 | 603 s |
| 11:38:33 | 11:48:36 | 603 s |

最后一次停止后 5 秒，`dshm-hb.log` 开始出现周期性断档：

```text
11:48:41 -> 11:48:50   9.9 s
11:48:56 -> 11:49:18  22.0 s
11:49:23 -> 11:49:42  19.2 s
...
```

之后每约 30 秒出现一次 20–25 秒的整进程停跳，和 Host 的
`LOOP-GAP 20000~25000ms` 同刻。原生心跳线程也停，说明不是 JS 单点死循环，
而是长时任务失效后的进程冻结。

`diag-mem` 同期 Host RSS 约 550–780 MiB、系统 `MemAvailable` 约 7.3–8.2 GiB；
没有证明新增泄漏。09:49 的 `LowMemoryKill` 是一批 82 条的系统级回收，同时杀了
微信、文件管理、日历、输入法和 DSHM 两个包，不能单独归因给本应用。

## 4. 本轮修复

1. `entry/src/main/module.json5` 增加 `taskKeeping` 后台类型。
2. `platform/.../KeepAlive.ets` 新增 `acquireTaskKeeping()`；PC/2in1 优先申请
   `TASK_KEEPING`，系统判定不支持时降级回 `DATA_TRANSFER`。
3. `EntryAbility` 的非手持档启动保活改走 `acquireTaskKeeping()`；手机/平板原有
   `onBackground + DATA_TRANSFER` 路径不变。
4. `StatusBarTray.hold()` 从当前 `context.abilityInfo.bundleName` 取包名，修掉 beta
   写死 `com.dshm.dshclient`、把后台 Ability 拉进正式包的错误。
5. `KeepAlive` 写 `files/diag-keepalive`：
   `mode=TASK_KEEPING active=true`、降级、取消原因、释放都留一行。

## 5. 复测判据

安装新侧载件后，把应用切后台并保持 **12 分钟以上**：

```sh
cat /data/app/el2/100/base/com.dshm.dshmbeta/haps/entry/files/diag-keepalive
```

通过：

- 出现 `mode=TASK_KEEPING active=true`；
- 10 分钟附近没有 `cancel reason=...`；
- `dshm-hb.log` 不再出现 20–25 秒一轮的整段断档；
- 回前台后 Host、会话和终端正常。

若出现：

```text
fallback TASK_KEEPING -> DATA_TRANSFER
```

说明系统仍把该形态判成非 PC/2in1。此时保留旧路径，需把 `diag-keepalive`、
`dshm-hb.log` 和同时间段 hiLog 一起回传，再决定是否单独走系统能力申请。

## 6. 门禁

`tools/check-memory-guard.mjs` 新增 E1–E6，并加三条变异对照臂：

- M8：去掉 `taskKeeping` 声明必须判红；
- M9：PC 仍申请 `DATA_TRANSFER` 必须判红；
- M10：托盘重新写死正式包名必须判红。

## 7. 官方依据

- 长时任务（V244，抓取 2026-10-15）：
  `https://developer.huawei.com/consumer/cn/doc/capabilities/continuous-task`
- `@ohos.resourceschedule.backgroundTaskManager.d.ts`：
  `MODE_DATA_TRANSFER` 注释明确“超过 10 分钟未更新进度会取消”；
  `MODE_TASK_KEEPING` 对 PC/2in1 不要求
  `KEEP_BACKGROUND_RUNNING_SYSTEM` ACL。


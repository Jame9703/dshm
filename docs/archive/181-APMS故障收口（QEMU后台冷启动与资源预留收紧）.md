# 181 · APMS 故障收口：QEMU 后台冷启动与资源预留收紧

> 2026-10-17。对象：AGC `1.1.3` 的 APMS Crash 数据，以及当前 beta 工作区的
> `dshm-vm-bash` 生命周期。目标是先把**能直接导致原生崩溃**的一路收口，不用
> “多试几次”掩盖问题。

## 1. 已确认的现场

APMS 当前版本页面与 Crash v1 API 的统计口径不同：API 会保留跨版本 fingerprint
的累计记录，页面按当前版本聚合。两边不能混着当同一个数使用。

- 页面当前 `1.1.3` TOP 仍以 QEMU 为主：
  - `libqemu-system-aarch64.so(tcg_region_init+1944)`：8 次，2 台设备；
  - `libqemu-system-aarch64.so` 地址 `0x17524ac`：3 次，2 台设备；
  - `libnode.so.137` 地址 `0x536a110`：2 次，1 台设备。
- API 首个 QEMU 个例的主进程状态是 `foreground=false`。
- 1.1.3 的延迟静默预热默认在宿主启动 60 秒后触发；旧实现只检查
  `MemAvailable`，不知道 UIAbility 是否已进后台。
- QEMU 的 `mmap/mprotect` 失败发生在 worker 线程的原生路径，JS 无法 catch；
  appspawn 最终把它转成 SIGABRT，整个宿主进程一起消失。

## 2. 根因判断

这一轮不把“旧版本 SIGSYS 425 的历史累计”当成当前故障继续加补丁：

- `SIGSYS 425` 最后出现在 2026-10-16 21:23（Asia/Shanghai），且 fingerprint
  跨 `1.1.2 ~ 1.1.3`；构建脚本已有 libuv 的 io_uring 无条件关闭补丁，
  继续靠运行时 `UV_USE_IO_URING=0` 并不会修它。
- `SIGILL` 是跨版本汇总，页面当前版本 TOP 没有它，不能仅凭上游累计摘要
  断定当前包仍在触发。
- 可以确定的当前风险是：**后台状态下仍可能冷启动 QEMU**。系统收紧内存时，
  QEMU 在 `tcg_region_init` 里拿不到所需映射，原生退出拖死宿主。

## 3. 修复

### 3.1 前后台状态变成可判事实

`EntryAbility` 只在**主窗**的 `onForeground` / `onBackground` 覆写：

```text
<filesDir>/dsh/home/app-lifecycle.json
```

内容包含 `pid`、`foreground`、`source`、`updatedAt`。Node 侧只认同 pid 且字段
完整的记录；旧进程留下的文件按 unknown 处理。

### 3.2 冷启动 fail-closed

`dshm-vm-bash` 在 `startWorker()` 前增加生命周期闸门：

- 明确后台：不冷启动 VM；已经运行的 VM 不受影响，后台任务可继续使用；
- 明确前台：允许；
- 状态未知：真实请求按兼容路径放行，**静默预热一律跳过**。

因此延迟预热即使定时器已经排上，应用切到后台后也不会再起 QEMU。

### 3.3 收小固定预留

VM 的实际用途是 bash、短命令和终端，不是完整桌面环境：

| 项 | 旧值 | 新值 |
|---|---:|---:|
| guest RAM | 384 MiB | **256 MiB** |
| TCG buffer | 256 MiB | **64 MiB** |

guest 仍保留 `prealloc=off` / `merge=off`，只有被触碰的页才常驻。TCI 解释档
cpus=1 时只有一个 region，64 MiB 足够当前命令面；`DSHM_VM_MEMORY_MIB` 仍可
在仓库外覆盖回大值做对照。

## 4. 回归门禁

```powershell
node tools/check-vm-bash.mjs
```

新增覆盖：

- 前台/后台/未知 × request/prewarm 的行为矩阵；
- 状态文件同 pid、旧 pid 两种读取结果；
- `lifecycleGate → memBudget → startWorker` 的接线顺序；
- `tb-size=64`、guest `256M`，并禁止旧的 `256/384` 预留复活；
- 主窗 `onForeground` / `onBackground` 两个写入点。

## 5. 版本与待验

- `coreVersion`：`0.2.1-alpha.4+dshm.68`；
- 核心容器：`dsh-core-0.2.1-alpha.4+dshm.68-openharmony-arm64.zip`
  **99,558,193 B / `dad33628c72457a3…`**；
- beta HAP：`entry-default-signed.hap` **440,536,930 B /
  `183D9DEA8A5D717E…`**，包内可见 `libqemu-system-aarch64.so`、`libslirp.so.0`
  与 `.68` 核心容器，APK 相关条目 **0**；
- 本轮不新增任何权限，权限面仍恒 8 条；
- 待真机：手机/平板/PC 各做一次“前台开终端、切后台等过预热窗口、再回前台”
  的内存与日志复核；需要读取 `vmDiagnostics().lifecycle` 和
  `node-output.log` 中的“静默预热跳过”。

### 5.1 PC 真机复核（`86E0226429000417`，2026-10-17 18:30）

首轮装机暴露了一个额外问题：HAP 中原代码已经包含 `writeAppLifecycle`，但设备上
`app-lifecycle.json` 不存在。原因是写盘函数对**已存在的 `dsh/home`**直接调用
`fs.mkdirSync(dir, true)`，在 PC 形态上抛错后被 catch 静默吞掉。修法：

- 先 `fs.accessSync(dir)`，不存在才 `mkdirSync`；
- `onCreate`、主窗 `onWindowStageCreate`、`onForeground` 三处都写前台兜底。

修复后读取值：

```json
{"pid":15265,"foreground":true,"source":"onForeground","updatedAt":"2026-10-17T10:32:36.777Z"}
```

- 60 s 预热确实执行：`MemAvailable 4024 MiB ≥ 1792 MiB`，`tb-size=64`，
  QGA 就绪 `+7015 ms`，预热结果 `ok=true`；
- 真实 `terminal/create` 返回 `state=running`、`/bin/sh -i`、`/dev/hvc0`，
  耗时 `2349 ms`；
- WebSocket 输入执行 `uname -a; pwd` 成功，输出命中 `Linux hish` 与
  `~/harness`；
- 当时宿主 `VmRSS 279,760 KiB` / `VmHWM 1,404,076 KiB`，无新增
  `SIGABRT/SIGSYS/SIGILL/SIGSEGV/tcg_region_init/uncaughtException/OOM` 日志。

覆盖安装未删用户数据，`home` 指纹保持 `links=10 size=3440`。因当前构建使用
debug 签名且设备应用域仍对宿主直接 `execve` 返回 `EPERM`，旧装机脚本第 8 步的
“exec 探测全通”仍会报红；该阶段不是 VM 终端判据，本轮的 VM 端到端读数以上述
RPC 与 WebSocket 为准。

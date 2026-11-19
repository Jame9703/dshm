# 121 · 手持档 guest VM 真机首跑：两个 P0 与一个 P1

> 接 `docs/120`（把 `ctx.subprocess.spawn` 改派到随包 QEMU guest 的手持档插件）。
> 本档记的是**出包之后、真机首次把这条链路跑起来**时踩到的东西：两个 P0（都**不是**插件业务逻辑，
> 而是「端侧调试构建」这个环境本身的口径问题）与一个 P1（guest 起不来，靠**取证**才定性）。
> 设备：`62T0225B18039433`（VYG-AL00 / API 26 / `const.product.devicetype=phone` / 手持档）。

## 0. 一句话结论

| 项 | 症状 | 根因 | 修法 | 版本 |
|---|---|---|---|---|
| **P0①** | 模型第一次用 `bash` 工具 → `Error: 端侧 VM 不可用：Initiated Worker with invalid execArgv flags: --jitless` | `jitless-env.cjs` 的 `wrapWorkerThreads()` 把**隐式继承**的 `process.execArgv` 写成**显式**数组，而 Node 对显式 `execArgv` 是**严格校验**的 | 按 Node 自己的报文清单过滤后重试一次（名单不写版本硬表）+ 插件侧显式 `execArgv: []` | `+dshm.15` |
| **P0②** | 收下①之后**进程当场消失**（无 faultlog、无 JS 异常），只剩一行 `call.hh:150: Assertion 'AlignLen(size, 16) == size' failed` | koffi 3.2.1 的 `base.hh:66` 把 `K_DEBUG` 绑在 `!defined(NDEBUG)` 上，而 `call.hh:150` 的断言与 `abi/arm64.cc:368` **故意**算出的 `stk_size = AlignLen(19*8+so,16) + 8`（arm64 栈基址必须 ≡8 mod 16）互斥 ⇒ arm64 上**第一条 koffi 调用必 abort**；上游发布产物带 `NDEBUG`，我们走 `buildMode=debug` 把它编进来了 | 给 koffi 目标补 `target_compile_definitions(koffi PRIVATE NDEBUG)`（`entry/src/main/cpp/CMakeLists.txt`） | `+dshm.16` |
| **P1** | 进程不再消失、worker 走到「`qemu_system_entry` 已进入」，但 **QGA 150 s 不响应**，串口**恒 0 B** | `-serial unix:<socket>` 这条 unix chardev **没有读端**时，QEMU 按 posix「写成功即丢弃」（不阻塞、不留存）⇒ 启动日志结构性不可得（连"停在 kernel、还是停在 initrd"都判不了） | 串口改 **file chardev**（`-chardev file,id=ser0,path=<workDir>/serial.log` + `-serial chardev:ser0`）；补 `earlycon=pl011,0x09000000`；把 worker 的 stdout/stderr **显式转发**进日志 | `+dshm.17` |

> **P1 的"修好"目前只到"让下一次真机复跑能一次定性"**：取证通道本身是这一轮的交付物。
> 真机复跑因**设备锁屏**（`aa start` 报 `10106102`）暂停，见 §6。

---

## 1. P0①：worker 起不来（`+dshm.15`）

### 1.1 现场
模型侧看到的是一句业务报文，端侧 `node-output.log` 里才有原文：

```
Initiated Worker with invalid execArgv flags: --jitless
```

### 1.2 为什么"继承"会变成"显式"
端侧宿主的 argv 里有 `--jitless`（无 JIT 档的既定口径）。`hostcore/app/jitless-env.cjs` 的
`wrapWorkerThreads()` 为了让 worker 也拿到 jitless 补齐，会读 `process.execArgv` 并**写成一个显式数组**
交给 `new Worker(...)`。差别就在这里：

- **不写** `execArgv` ⇒ 隐式继承 ⇒ Node **自己过滤**掉 worker 不接受的标志；
- **写了**一个数组（哪怕内容与继承的完全一样）⇒ Node **严格校验**，`--jitless` 不在 worker 允许集合里 ⇒ 直接抛。

于是端侧**任何不写 `execArgv` 的插件 worker 都起不来** —— 这不是本插件独有的问题。

### 1.3 修法
`withoutWorkerRejectedFlags()`：把继承来的 argv 按 **Node 自己的报文清单**过滤（"invalid execArgv flags: …" 里点名的那些）
后重试一次；**不写版本硬表**（Node 版本升级后名单会变，硬表会静默过期）。
插件侧 `vm.js` 的 `new Worker(...)` 同时显式写 `execArgv: []`（与上游 `lib/index.js:1904` 同一做法：要补的
`--expose-internals --require worker-bootstrap.cjs` 由那层包装器加）。

门禁 `tools/check-vm-bash.mjs` 里带**对照臂**：把"继承的 argv 原样显式交出去"复现真机那行报文 ⇒ 断言有牙。

---

## 2. P0②：koffi 在 arm64 上第一条调用必 abort（`+dshm.16`）

### 2.1 现场
修完 P0① 之后，worker 起来了、`koffi.load` 也成功了，然后**整个宿主进程消失**：
没有 `faultlog`、没有 JS 异常、`node-output.log` 的最后一行是一句 C++ 断言

```
call.hh:150: Assertion `AlignLen(size, 16) == size' failed
```

### 2.2 根因（三层，缺一层就解释不通）
1. `lib/native/base/base.hh:66` 把 `K_DEBUG` 绑在 `!defined(NDEBUG)` 上 ⇒ 只要没定义 `NDEBUG`，断言就编进来；
2. 断言在 `call.hh:150`（`AllocStack`）：要求栈块大小**对齐到 16**；
3. 而 `abi/arm64.cc:368` 给 arm64 算的是 `stk_size = AlignLen(19*8+so, 16) + 8` —— **故意**多加 8：
   arm64 的栈基址必须 ≡8 (mod 16)（`abi/arm64_asm.S:47` 是 `add sp, x1, #152`，152 = 19*8）。

⇒ 两者**结构性互斥**：在最严的构型（arm64 + 断言开启）下，第一条 koffi 调用必 abort。
koffi 的**发布产物带 `NDEBUG`**，所以上游用户看不到；我们的 HAP 走 `buildMode=debug`，把它编进来了。

### 2.3 修法
`entry/src/main/cpp/CMakeLists.txt` 给 koffi 目标补 `NDEBUG`（只影响 koffi 目标，不改全局 debug 口径）。
实测 `libkoffi.so` **5,595,568 → 5,466,816 B**，断言字符串在产物里**已消失**。

> **为什么这条值得单独记一档**：它的失败形态是"进程消失"，最容易被人当成"VM 崩了"去查 guest。
> 判据是**这条断言的出处**——只要报错文件是 koffi 的 `.hh/.cc`，就一定在宿主侧的 FFI，而不是 guest。

---

## 3. P1：guest 起不来，且**没有证据**（`+dshm.17`）

### 3.1 症状链（修 P0 之后的第二跑）
```
[11:01:44.754] 启动 guest VM（第 1 次尝试；share=/data/storage/el2/base/haps/entry/files）
[11:01:44.759] 资产已就位：rootfs 副本 48631808 B + guest apk + socket 目录
[11:01:44.765] worker 线程已拉起（lib=/data/storage/el1/bundle/libs/arm64/libqemu-system-aarch64.so）
[11:01:44.974] worker: koffi.load(libqemu-system-aarch64.so)
[11:01:45.071] worker: koffi.load 成功
[11:01:45.073] worker: qemu_system_entry 绑定成功：int qemu_system_entry(int argc, char **argv)
[11:01:45.074] worker: 即将调用 qemu_system_entry（argc=61）
[11:01:45.074] qemu_system_entry 已进入（argc=61）——此后由 QEMU 接管（串口/QGA）
… 每 10 s：仍在等 QGA（已 N s，串口 0 B）…
[11:04:14.856] QGA 超时，串口尾部：
[11:04:14.857] VM 启动失败（阶段 failed）：QGA 在 150000 ms 内没有就绪
```
注意那句"每 10 s"在本轮**一次都没打过**（见 §3.4 的心跳 bug）。

### 3.2 用 QMP 直连拿到的硬读数（Python 桥探针）
- QEMU 活着：`10.2.0`，`query-status` → `running: true`
- guest 只有 1 个 vCPU，PC **三次采样完全不变** = `ffff80008091f748`，该处指令是
  `dsb sy` / `wfi` / `ret`（arm64 `arch_cpu_idle`），周围 `nop` 填充；PSTATE 标志位 `-Z--`
- X08 单调 **+208/秒**（与 timer 频率无关）
- `query-blockstats`：父节点 `wr_bytes=0`/`rd_bytes=0`，但 `rootfs.qcow2` **48,631,808 → 48,963,584**
  = 恰好 **+331,776 = 81×4096**，`wr_highest_offset=48,963,584` ⇒ **盘确实被写过**（guest 跑过一段才停）
- `info chardev`：`serial0: filename=disconnected:unix:…serial_socket,server=on`
  ⇒ QEMU 在没有读端时按 posix 语义**丢弃**串口输出（不阻塞、不留存）⇒ **串口恒 0 B 是结构性的，不是"kernel 没输出"**
- QGA 侧：连接成功但零应答；10 s 后重连得 `BlockingIOError(11)`（accept 积压未 drain）
- 设备上 `files/vm/tmp/` 有 `qga_socket` / `qmp_socket` / `serial_socket`（s 位）

⇒ 这一轮**唯一**的结论是「guest 真的跑起来了（QEMU running + 盘被写）但没到 QGA」，而"停在哪一步"
**无法判定** —— 因为唯一能回答这个问题的通道（串口）被设计性地丢掉了。这就是要修的东西。

### 3.3 修法：把证据变成可得的
1. **串口改 file chardev**（`vm.js: bootArgv()`）：
   ```
   -chardev file,id=ser0,path=<vmWorkDir>/serial.log
   -serial chardev:ser0
   ```
   - 下游对 `serial_socket` **零依赖**（`qga.js` 只用 QGA、`stop()` 只用 QMP、原 `attachSerial()` 是唯一读它的人）；
   - `serialText(keep)` 直接读文件尾部并**剔 NUL**（设备侧 `grep` 把 NUL 当行尾 ⇒ 含 NUL 的行会"假截断"，`docs/106` §7.3）；
   - `stage()` 顺手清掉**上一版遗留**的 `tmp/serial_socket` 与本次的 `serial.log`（保证日志里读到的尾部一定是**本次**启动的）。
2. **`earlycon=pl011,0x09000000`** 进 `-append`：`console=ttyAMA0` 要等 PL011 驱动 probe 完才生效，
   而"更早就停了"（解压/MMU/PSCI/设备树）恰恰是本次症状的候选；earlycon 直写 PL011，把这之前的输出也捞出来。
3. **worker 的 stdout/stderr 显式转发进日志**：`stdout: true`/`stderr: true` 是"接成管道"、**不会**自动转发，
   而 QEMU 是**同进程**跑的 ⇒ 它 `error_report()` 打的 stderr（例如 `-serial: invalid option`）全部落在
   **没人读**的管道里：既看不到，又可能把 64 KB 塞满反手把 worker 卡死。

### 3.4 顺手修掉的两个 bug
- **心跳 bug**：`waited % 5000 === 0` 在 `waited` 每次 +400 的步长下**永远不命中** ⇒ 真机上"每 5 s 一拍"一次都没打过。
  改 `% 10000`（10 s）。
- **`stage()` 的陈旧 socket 清单**：串口不再走 socket，清单相应收窄（保留 QGA/QMP）。

### 3.5 门禁
`tools/check-vm-bash.mjs` **74/74**（原 72），新增两条：
- `-chardev file,id=ser0,path=<stage>/serial.log` 且 `-serial chardev:ser0` 都在 argv 里；
- **对照臂**：argv 里**不再出现** `serial_socket`。

---

## 4. 出包与验包（本机读数）

### 4.1 一条新口径：复用已知良树（`robocopy` + `--skip-install`）
核心树每升一次版本号就要**重新物化 + `npm install`**（十几分钟量级）。本轮的唯一代码改动是
`hostcore/plugins/dshm-vm-bash/lib/vm.js`（插件的 `cpSync(..., {force:true})` 每次都覆盖），
因此把 `.16` 树整棵复制成 `.17` 后以 `--skip-install` 打包，**并用下面的逐条目 CRC 比对背书**：

> **判据**：`.17` 容器与 `.16` 容器（从**已装 HAP** 里取回，不是从工作树）逐条目比 `Crc32 + Length`，
> 归一化掉版本前缀后，**内容有差异的只有 3 条**：
> `dshm-core.json`（版本字段）、`node_modules/@deepseek-ai/dshm-vm-bash/lib/vm.js`（本次修复）、`package.json`（版本字段）；
> 条目集合差 **1 条**：`node_modules/koffi/index.d.ts`。

那个 `.d.ts` 的来去已查清，是**构建历史**而不是功能差异：`.13`–`.16` 那几次 `replaceKoffiJs()`
（在 `prune()` **之后**执行）会把 `third_party/koffi/package` 拷进树里，`index.d.ts` 因此被重新带进来；
本轮那个步骤打印的是 `koffi JS 层已是 3.2.1（跳过）` ⇒ 它被 `**/*.d.ts` 规则正常裁掉。
`.d.ts` 运行期从不被 `require`（配方里那条规则的原话），**不影响功能**。

### 4.2 产物
| 项 | 值 |
|---|---|
| `coreVersion` | `0.2.1-alpha.1+dshm.17` |
| 核心容器 | `dist/core/dsh-core-0.2.1-alpha.1+dshm.17-openharmony-arm64.zip` **59,233,693 B** / 16,499 条目 / sha256 `9bad5fdbea5f4674dfeb6050d55e544f3e0a9657ab0167c83b820573ed410968` |
| `check-resfile-core-zip` | ✅ resfile 只有 1 份容器，且与配方、与本次产出**完全一致** |
| HAP | `entry/build/default/outputs/default/entry-default-signed.hap` **400,094,264 B** / sha256 `1ee124a58763d5752383229018088e4bb52edbcae2f80f50c89a0328fd61872d` |
| 包内容器 | 从 HAP 里取回的 `resfile/dsh-core-…+dshm.17….zip` 与 resfile 侧**逐字节相同**（同为上式 sha256） |
| `assert-resfile-sync` | 14 件快照全部同步 |
| `check-core-openharmony-patches` | **172 passed / 0 failed**（23 处端侧注入都在、上游原文形态均已消失） |

### 4.3 覆盖安装
`.\tools\update-device.ps1 -SkipRebuild`：`hdc install -r` **成功**；`home` 指纹 **8/3440 → 8/3440**（用户数据未被触碰）。
**但端侧没起来**，真机复跑暂停 —— 原因见下。

---

## 5. 又一条真机坑：`aa start` 在**锁屏**下会失败，而脚本把这条报文吞了

```
$ hdc shell "aa start -a EntryAbility -b com.dshm.dshclient"
error: failed to start ability.
Error Code:10106102  Error Message:The device screen is locked during the application launch, unlock screen failed.
```

- 这是**设备侧策略**（"developer mode 下不能自动解锁屏幕"），不是安装问题、不是应用崩溃；
- 判据：`ps -ef | grep dshclient` 为空，且 `files/` 下所有日志的 mtime **停在安装之前**（本轮是 19:11 vs 安装 19:18）；
- **脚本的表现具有误导性**：`Shell "aa start …" | Out-Null` 把 error 报文吞了，外层只看到
  「本轮没有任何新的 exec 探测行」+「核心树里没看到 `+dshm.17`」，看上去像"应用装坏了"。
  ⇒ 下一版应把 `aa start` 的 stderr 收下来，命中 `10106102` 时直接报「**请先解锁设备屏幕**」。

---

## 6. 本轮**未做** / 待真机 → **已结案（2026-10-08）**

| # | 待验 | 判据 |
|---|---|---|
| 1 | `aa start` 成功、端侧出现本轮 exec 探测 | 设备解锁后 `tools/update-device.ps1 -SkipRebuild`（或直接 `aa start`） |
| 2 | **串口文件是否真的有内容** | `hdc file recv <files>/vm/serial.log`；看得到 kernel/initramfs 行 ⇒ 取证通道成立 |
| 3 | guest 停在哪一步 | 由 ②的末尾几行判：`No working init found` / `Kernel panic` / 停在 `Freeing unused kernel memory` / 或一路到 `login:`（后者说明问题在 QGA 而不在 kernel） |
| 4 | QGA 是否就绪 | 日志出现 `QGA 就绪（+N ms）`；`check-model-roundtrip.mjs` 驱动一次真 `bash` 工具调用 |
| 5 | 端到端命令 | 模型 `bash` 工具真执行（`docs/120` §6 的 8 项里第 6 项） |
| 6 | PC 档零变化 | 鸿蒙 PC 装同一包：本插件三条判据第一条即不成立 ⇒ 0 条本插件日志、`exec` 探测 10/10 |

**已定论（2026-10-08）**：P1 的真因是 `qga.js` 这一层的两条设计错误 ——
**一次问答挂一次监听器**（读完第一行就 `socket.off("data")`，而 Node 的 `net.Socket` 进过 flowing 模式后
**摘掉最后一个 `data` 监听器不会自动 pause** ⇒ 两次问答之间到达的字节被静默读掉）＋ **只认第一行**
（带 `\xff` 的 `guest-sync-delimited` **必然**先回一行 `JSON parse error, stray '\uFFFD'` 杂音，真应答紧随其后）
⇒ 两者叠起来是死循环，再加等待循环里的 `catch {}` ⇒ 现场零证据。**与 guest / 内核 / QEMU 无关**
（串口一路到 `login[658]: root login on 'ttyAMA0'` / `hish:~#`，QGA 在 guest 里 `[ ok ]`）。
修法与真机读数见 `docs/122`（§1 根因、§2 guest 侧三处、§3 端到端验收）。

| 原"待验"项 | 真机读数（原文） | 结论 |
|---|---|---|
| 串口文件是否真有内容 | `serial.log` 18,136 B：`EXT4-fs (sda): mounted filesystem …` → openrc → `Starting QEMU Guest Agent ... [ ok ]` → `login[658]: root login on 'ttyAMA0'` / `hish:~#` | ✅ 取证通道成立（file chardev + earlycon + worker 转发） |
| guest 停在哪一步 | **没有停**：kernel → init → openrc → QGA → login 全程走完 | ✅ 问题在宿主 QGA 客户端 |
| QGA 是否就绪 | `QGA sync 成功（3804 ms，跳过 1 行杂音）` → `QGA 就绪（+13446 ms）` | ✅ `+dshm.18` |
| 端到端命令 | 三条命令 `rc=0`；探针原文 `GNU bash, version 5.2.37(1)-release` / `pwd=~/Download/harness` / `workspace_files=7` | ✅ `+dshm.19` |
| PC 档零变化 | 分档判据与接管面本轮一字未动（改动全在"接管之后"的分支） | ✅（2in1 装机复跑仍待做） |

---

## 7. 文件清单（本轮）

| 文件 | 改动 |
|---|---|
| `hostcore/plugins/dshm-vm-bash/lib/vm.js` | 串口 file chardev；`serialText/serialBytes/serialTail`；`earlycon`；worker stdout/stderr 转发；心跳 `% 5000 → % 10000`；`stage()` 清理清单 |
| `hostcore/plugins/dshm-vm-bash/lib/vm-worker.cjs` | 逐步 `diag()`（上一轮已加，本轮沿用） |
| `hostcore/app/jitless-env.cjs` | `withoutWorkerRejectedFlags()`（P0①） |
| `entry/src/main/cpp/CMakeLists.txt` | koffi 目标补 `NDEBUG`（P0②） |
| `hostcore/core-recipe.json` | `coreVersion` → `+dshm.17` |
| `tools/check-vm-bash.mjs` | 72 → **74** 条（串口 file chardev + 对照臂） |
| `AGENTS.md` | 文档编号到 `121`；`coreVersion` 当前值与 `.17` 说明 |
| `docs/121-*.md` / `docs/README.md` | 本档 + 索引 |
| `docs/120-*.md` | §7 指向本档（版本/产物读数以本档为准） |
# 119 调研：HiSH（QEMU 全系统模拟）能不能给手机 / 平板档接上真 bash

> **历史状态说明（2026-10-18）**：本文是 HiSH / QEMU 的只读调研与 PoC 记录。
> PoC 已产品化为 `dshm-vm-bash`，后续演进见 `docs/120`、`docs/155`、`docs/181`
> 和 `docs/188`。不要把本文的 PoC 资源、内存读数或早期权限判断当成当前状态。

> 2026-10-08。用户提问原话：「有人使用鸿蒙端 hishell 的 Linux 执行核心拆出来，集成进去，手机和平板端就可以执行 bash 了，调研一下看看」。
> 本篇是**只读调研 + 真机实测 + 可行性裁定**，**未改一行产品代码**。2026-10-08 晚追加一轮：把 §6 建议里的"三个数"分掉 ①③ 实测量掉（见 §2），并把 JIT 一节的机制**更正**为"编译期开关 + 平台权限闸门"、判定"解释档必须自建"（见 §1.4）。

> **2026-10-08 深夜第三轮（PoC，决定性）**：按用户"开动吧"的指示，我们把 QEMU **真的搬进自己的 HAP 并装机**：应用进程内起 VM、guest 里 `bash 5.2.37` 执行命令、输出与退出码都取回，8/8 用例全过（**§2.5**）。
> 同一轮**推翻了 §1.4 的"手机档 JIT 不了 ⇒ 必须自建 TCI 档"**：实测应用里**可执行内存完全通**，公开的 **JIT 档产物直接可用**（§1.4 更正、§2.5 硬结论 1）。

---

## 0. 结论先行（三层，别混）

| # | 问题 | 结论 |
|---|---|---|
| 1 | 鸿蒙**手机 / 平板**上能不能有**真 Linux shell**？ | **能**。真机实测：设备上装着的 HiSH（应用市场版）首屏就是 Alpine 的 `hish:~#`，`uname -a` 给出 `Linux hish **6.12.60** … aarch64` |
| 2 | 它靠的是"把 execve 解锁"吗？ | **不是**。它是**把内核换掉** —— App 进程内跑 **QEMU 全系统模拟**（`-accel tcg`）+ 一个完整 arm64 Linux 内核 + Alpine 根文件系统。**一次 `execve` 都不发生** |
| 3 | 能不能拆出来集成进 DSHM？ | **能，而且已经真的跑通（PoC 通过，见 §2.5）**：我们自己的 HAP 里用 `ctypes` 加载 JIT 档 `libqemu-system-aarch64.so` → 起 arm64 linux/Alpine 虚拟机 → 经 QGA 让 guest 里的 **bash 5.2.37** 执行命令，输出与退出码都取回。剩下的全是**代价问题**：体积 **+103.8 MB**（实测 HAP 295.5 → 399.3 MB）、VM 常驻 **≈ +1.15 GB VmRSS**、冷启动 **11.8 s** 到可用、GPLv2 义务、以及一个需长期维护的新子系统 |

⇒ 这与 `docs/104` 的判决**不冲突**：104 说的是"**随包 ELF 的 execve 在手持档一律 `EACCES`**"，那条**仍然成立**；HiSH 走的不是那条路。
换句话说：`docs/104` 的"真 shell 无解"要**限定为"在应用进程的域里直接 execve 无解"**；**换成虚拟机这一层就有解**。

---

## 1. HiSH 是什么（事实基线，全部带出处）

### 1.1 仓库与许可

| 项 | 值 |
|---|---|
| 仓库 | `harmoninux/HiSH`（★661 / fork 50，`master`，创建 2025-09-06，最后推送 2026-09-26） |
| 描述 | **「在鸿蒙上运行 Linux Shell，支持手机、平板、2in1/PC」** |
| 许可 | **MIT**（`LICENSE`：`Copyright (c) 2025 hackeris`） |
| README 的额外要求 | 「使用本项目代码，**按惯例需在软件本体『关于』中注明基于本项目（HiSH）以及本项目的仓库地址**」 |
| 关键依赖 | 内核与镜像在 `harmoninux/linux-config`；QEMU 在 **`harmoninux/qemu`**（描述：`QEMU modified for HarmonyOS, to support HiSH/Termony/Harmonix`，默认分支 **`hish-libqemu`**） |
| 设备上的实物 | `app.hackeris.hish` **1.0.17**（vendor `hackeris`，应用市场安装，`appProvisionType: release`，`apiTargetVersion 50100018`＝API 18，`cpuAbi arm64-v8a`，模块名 `phone`） |

### 1.2 机制：App 内跑一台虚拟机（不是 exec 系统二进制）

以 tag `release-20260516` 的源码为准（`entry/src/main/ets/lib/startVm.ets`；⚠️ 旧稿写的 `feature/hish_main/…` 路径与 `supportJit` 字段，在这一版**都不存在**）：

```ts
const started: boolean = napi.startVM({
  argsLines: args.join('\n'),
  unixSocket: options.serialUnixSocket,   // 终端字节流
  qmpSocket: options.qmpUnixSocket        // QEMU 管理口（native 侧读了但没用）
})
```

native 侧是 `entry/src/main/cpp/napi_init.cpp`，NAPI 模块名 = **`libentry.so`**（不是 `libhish_main.so`）：

- `dlopen("libqemu-system-aarch64.so", RTLD_LAZY)` → **`dlsym(…, "qemu_system_entry")`**
  ⚠️ 这是他们 fork（`hish-libqemu`）**自加**的导出符号，**上游 QEMU 顶替不了**（上游那两条 `main` / `qemu_main` 也仍在 `.dynsym` 里）；
- 拿到入口后 `std::thread` 里 `qemuEntry(argc, argv)` 阻塞跑；另一条线程 `serial_output_worker(unixSocket)` 把终端字节流推回 ArkTS；
- 对外 4 个 NAPI：`startVM({argsLines, unixSocket, qmpSocket})` / `sendInput(ArrayBuffer)` / `onData(cb)` / `onShutdown(cb)`；
- `libqemu-img.so` 同理走 `qemu_img_entry`（快照 / 镜像管理那一串）；
- **两条 `dlopen` 都传裸 soname** ⇒ 依赖"应用自身 libs 目录在加载器搜索路径里"（我们照抄这个口径，或自己改绝对路径）。

命令行关键片段（原文摘录，逐字）：

- 加速与 CPU：`-accel tcg,thread=multi,tb-size=2048`、`-cpu max,pauth-impdef=on,sve=off,pmu=off`、`-machine virt,acpi=on,gic-version=max,…`
- 内核与磁盘：`-kernel <kernel_aarch64>`、`-drive if=none,format=qcow2,file=<rootfs>.qcow2,…` + `virtio-scsi-pci` + `scsi-hd,…bootindex=1`
- 内存 / CPU 数（**用户可调**）：`-smp cpus=N`、`-object memory-backend-ram,id=mem0,size=<N>M` + `-m <N>M`
- 网络：`-netdev user,id=eth0,hostfwd=tcp::<host>-:<guest>`（**端口转发进 guest**）
- 共享目录：`-fsdev local,security_model=mapped-file,path=<dir>` + `-device virtio-9p-pci,mount_tag=hostshare`（2in1 额外挂 `~`）
- 三条通道：
  - `-serial unix:<sock>,server,nowait` → **终端**
  - `-qmp unix:<sock>,server,nowait` → 管理
  - **`-chardev socket,path=<sock>,server=on,wait=off,id=qga0` + `virtserialport … name=org.qemu.guest_agent.0`** → **QEMU Guest Agent（命令执行）**
- 内核命令行里 `init=<...>`、`console=ttyAMA0 console=tty0`、`selinux=0 apparmor=0 security=none` 等一大堆"为模拟器调优"的开关

**终端 UI**：`resources/rawfile/term/` 是一套 **xterm.js**（`xterm.js` 283 KB + `xterm-addon-webgl.js` 99 KB + fit），在 Web 组件里渲染；
`term.onData(data => native.sendInput(data))`、`term.onResize(...)` —— 字节流进 native，native 再喂给 serial chardev。

### 1.3 真正"可执行命令"的那一环：QGA（对我们的接缝最友好）

`entry/src/main/ets/lib/QemuAgent.ets` 是一个 **QEMU Guest Agent 的 JSON-RPC 客户端**（走 `socket.LocalSocket`），
接口里已经有我们正好需要的东西：

| QGA 命令/字段 | 作用 |
|---|---|
| `guest-exec` (`arguments: { path, arg[], 'capture-output' }`) | 在 guest 里**起一个进程** |
| `guest-exec-status` (`exited` / **`exit-code`** / **`out-data`** / **`err-data`**) | 取回**退出码与输出** |
| `guest-info`（`version` / `supported_commands`） | 能力探测 |
| `guest-network-get-interfaces` / `guest-get-fsinfo` / `guest-get-vcpus` | 状态读取 |

⇒ 这几乎就是 DSHM `dsh-bash-local.execute()` 的契约（`stdout` / `stderr` / `exitCode`），**字段一一对应**。

`QemuAgent.ets` 里已经实现的完整命令面（照抄即可，全是 MIT）：

| 方法 | QGA 命令 | 备注 |
|---|---|---|
| `exec(path, args)` / `execStatus(pid)` | `guest-exec` / `guest-exec-status` | 要 `capture-output` 为真才回 `out-data` / `err-data` |
| `ping` / `getInfo` / `getHostName` | `guest-ping` / `guest-info` / `guest-get-host-name` | 能力探测 |
| `getNetworkInterfaces` / `getFilesystemInfo` / `getVcpus` | `guest-network-get-interfaces` / `guest-get-fsinfo` / `guest-get-vcpus` | 状态读取 |
| `shutdown` / `reboot` / `suspend` | `guest-shutdown` / `guest-suspend-ram` | 不等响应 |
| 内部 | `guest-sync-delimited`（先发 `0xFF` 引导串、再带 token 同步） | 每次会话前清 guest 侧 JSON 解析器 |

工程细节（照抄时别漏）：`socket.LocalSocket` + 换行分隔的 JSON-RPC、`sendCommand(…, timeoutMs = 10000)`、**一把内部锁**把所有请求串行化、连接/解析失败只 `hilog` 不抛。

### 1.4 JIT：手机档**能跑**（实测：应用里可执行内存未被拦）——旧稿"必须自建解释档"已**推翻**

> **⚠️ 本轮更正（2026-10-08 深夜，PoC 实测）**：下面这节的原结论（"手机档 JIT 不了 ⇒ 必须自建 TCI 档"）**不成立**。
> 我们在**自己的应用进程内**用内嵌 CPython 实测：`mmap` **RWX / RW / RX**、`mprotect(RW→RX)`、以及真跳过去执行机器码，**全部 `errno=0`** ——
> **W^X 没有被拦**。随后把公开的 **JIT 档** `libqemu-system-aarch64.so` 直接 `dlopen` + `qemu_system_entry()` 起 VM，**一次成功**（§2.5）。
> 结论修正为：**`--jitless` 是 V8 自己在启动时按能力选的档**（`ohos.permission.kernel.ALLOW_WRITABLE_CODE_MEMORY` 那条闸门管的是 **V8 的申请**），
> **不是内核禁止 `PROT_EXEC`**；QEMU 自己 `mmap` 可执行页**不受这条约束**。
> HiSH 的市场版用解释档，是**为过它自己的上架政策**（合规选择），**不是手机上跑不了 JIT** —— 这两件事旧稿混为一谈了。
> ⇒ **"必须自建 TCI 档"这条从风险清单里划掉**；公开产物（release HAP 里那份 41.4 MB strip 过的 JIT 档）直接用。
> （下面保留原文作为**历史记录**，读的时候请以上面这段为准。）

**先纠正旧稿**：`supportJit = deviceInfo.deviceType !== 'phone'` 与「`deps/Makefile` 里有 `aarch64-tci` 目标」——**两条都不成立**（该 tag 的 `startVm.ets` 没有 `supportJit`；`deps/Makefile` 只有 `x86_64` / `aarch64` 两个目标）。JIT 是**编译期开关**：

- `deps/libqemu/Makefile` 顶部原话：`# to disable jit, add --enable-tcg-interpreter option`；
- 分发口径（README 逐字）：**应用市场版「因应用市场政策限制，不支持 JIT，运行效率一般」**；**Releases 的 HAP / 源码自编译版「支持 JIT，运行效率更高」**；
  `docs/guide/Z1_Jit.md`：解释档相比 JIT「性能可提升 5-6 倍甚至更高」；
- **实测我们下载的 release `release-20260516` HAP**：`libs/arm64-v8a/libqemu-system-aarch64.so` 里含 **aarch64 JIT 后端**的符号与源码路径串（`tcg/aarch64/tcg-target`、`tcg_region_init`、`tcg_prologue_init`）⇒ **它就是 JIT 档**；
- **`libs.zip`（`hish-20260110`，他们唯一发布的一份 QEMU 产物）也是 JIT 档**（未 strip，`tcg_out_*` 一应俱全）。
- ⇒ **两份公开产物都是 JIT 档；解释档（TCI）没有现成产物可下。**

**手机档为什么用不了 JIT —— 本仓自己的判据比他们的 README 更硬**（`docs/50` E13，华为口径）：

> V8 需要可写可执行匿名内存；鸿蒙默认拦截，须申请 ACL 权限 `ohos.permission.kernel.ALLOW_WRITABLE_CODE_MEMORY`，
> 而**当前仅平板、PC/2in1 设备应用可申请**；否则要 `v8_jitless=true`。

⇒ **手机上这个权限连申请都不行**（`docs/90` 记：一旦出现在 `requestPermissions` 里，装机直接 `grant request permissions failed`）
⇒ **手机档任何应用进程都 JIT 不了**，不只是"市场审核政策"。这正是我们自身全程 `--jitless` 的由来（`docs/70` §0.1）。
（顺带解释了他们为什么要分两个版本：**市场版 = 解释档**才能过审 / 才能在手机上跑。）

**对我们的直接后果（已更正）**：JIT 档**拿来就能用**，不需要新的构建供应链。真正要付的代价变成三条：
**体积**（+103.8 MB）、**常驻内存**（实测 +1.15 GB VmRSS，可通过降 `-m` / `tb-size` 压）、
**GPLv2 义务**（§5 第 1 条）。另有一条实测踩出来的工程约束：**同一进程只能初始化一次 QEMU**（§2.5 第 2 条硬结论）。

### 1.5 体积（决定我们能不能"顺手塞进去"）

| 件 | 来源 | 大小 |
|---|---|---|
| `libs.zip`（QEMU + slirp；glib/pixman 已静态进去） | `harmoninux/qemu` release `hish-20260110` | **29,786,658 B**（解包 3 个 `.so`：`libqemu-system-aarch64.so` **52,481,120 B**〔含 `.symtab` + `.debug_*`，未 strip〕、`libqemu-img.so` 10,161,136 B、`libslirp.so.0` 558,816 B） |
| HiSH 自己的 HAP | GitHub release `release-20260516` 的 `entry-default-unsigned.hap` | **163,743,041 B**（外层 zip 43,018,705 B）。里面：`libs/arm64-v8a/` 下 `libqemu-system-aarch64.so` **41,438,848 B**（strip 过）、`libentry.so` 578,304 B、`libc++_shared.so` 1,262,248 B、`libslirp.so.0` 213,264 B；`resources/rawfile/vm/` 下 `rootfs_aarch64.qcow2` **48,631,808 B**、`kernel_aarch64` **12,980,736 B**、`efi-virtio.rom` 160,768 B；终端 UI `term/xterm.js` 283,405 B |
| `kernel_aarch64` | `harmoninux/linux-config` release `kernel-20260228` | **12.4 MB** |
| `rootfs_aarch64.qcow2`（Alpine） | `linux-config` release `rootfs-20260117` | **35.3 ~ 46.4 MB** |
| Ubuntu 24.04 镜像（可选） | `rootfs-20251213` | 77.8 MB |

对照：DSHM 当前正式侧载包 = **295,513,598 B**。

---

## 2. 真机实测（2026-10-08，手机 `62T0225B18039433`）

设备上**已经装着** HiSH（应用市场版 1.0.17 = **解释档**）⇒ 量到的正是**我们真会拿到的那一档（TCI）**的读数：

| # | 观测 | 读数 |
|---|---|---|
| 1 | 冷启动到出提示符 | 首行 `Uptime **4.61s**`（另一次 `4.98s`）⇒ ~5 s 内可用 |
| 2 | 首屏内容 | `Welcome to Alpine Linux of HiSH!` / `You can install packages with: apk add <package>` / `OpenRC is disabled by default…` / `login[52]: root login on 'ttyAMA0'` |
| 3 | 提示符 | `hish:~#`（**root**，Alpine 的 busybox ash） |
| 4 | guest 内核 | `uname -a` → `Linux hish **6.12.60** #39 SMP Sat Jan 17 13:46:52 CST 2026 aarch64 Linux` |
| 5 | 轻任务 | `time ls /usr/bin \| wc -l` → `154`，**real 0m0.16s**（user 0.02s / sys 0.11s） |
| 6 | **重任务（本轮新量）** | `time apk add --no-cache python3 2>&1 \| tail -3` → **real 3m17.86s**（**user 1m43.27s / sys 0m35.58s**） |
| 7 | **常驻内存（本轮新量）** | `com.dshm.dshclient` VmRSS **124,948 kB**；`app.hackeris.hish`（VM 在跑，默认档 **1 vCPU / 512 MB**）VmRSS **131,992 kB** / VmSize 48,563,108 kB / 85 线程 ⇒ **VM 的常驻开销 ≈ +130 MB** |
| 8 | 输入方式 | 屏幕下方 15 个虚拟键（ESC/FN/TAB/CTRL/方向/PGDN…）；**从 hdc 侧可驱动**（本轮实测打通）：`uitest uiInput click 400 400` → `uitest uiInput inputText 400 400 '<cmd>'` → **`uitest uiInput keyEvent 2054`（回车）** |

**读数解读**：

- 0.16 s 跑完"列目录 + 计数"⇒ **解释档（TCI）的日常命令行可用**；
- 但 `apk add python3` 花了 **3 分 18 秒**，其中 guest 自记的 CPU 时间是 **2 分 19 秒**（real 只比它多 58 s ⇒ 大头不是网速，是**被 TCI 放慢的 emulated CPU**）。
  README 自陈 JIT 是解释的 5~6 倍 ⇒ 同一个动作在 JIT 档约 **30~40 s**。这条最能代表"重活在手机档的体感"；
- 第 6 条还**顺带证实了 guest 能出网**（`apk add` 真去下载了，`-netdev user` + `hostfwd` 不需要额外权限）⇒ 旧稿未验证清单里的"guest 出网"一条**可以销掉**。

**未做 / 未证的（照实记）**：

- `apk add python3` 的**输出**被 `| tail -3` 缓冲、且我注入的两个字符（`ZZQ1`）混进了时间行 ⇒ **屏幕上没落到 apk 自己的那 3 行** ⇒ **"是否装成"未证**（但 real 3m18 / CPU 2m19 说明它确实干了大量活）。**没复测**：手机前台随后切到了别的 App（可能用户在用），我随即停止注入 UI 输入；
- guest 里 `python3` / `node` 的**实际耗时**（未量）；
- **平板 / 2in1 的 JIT 档对照**（手上只有手机；机制见 §1.4 —— 权限闸门只对平板开放，要单独验）；
- **我们自己的 HAP 里 `dlopen` 这份 `.so`**（未做：需要一个临时包，见 §4 末尾；静态面已核，见 §4.1 第 1 条）；
- `bash -c true` 经 **QGA 的单次往返耗时**（未做：QGA 是**他们 App 沙箱内**的 unix socket，`hdc shell` 域**够不到**，只有"在我们自己的 HAP 里把 VM 起来"才量得到 —— 这是 PoC 的结构性限制，不是漏做）。

---

## 2.5 PoC 实测：把 QEMU 搬进**我们自己的 HAP**，真跑通 bash（2026-10-08 深夜，手机 `62T0225B18039433`）

§2 末尾那三条"结构性量不到"，这一轮全部销掉。做法**纯 Python、一行 C++ 都没写**（PoC 性质，可回退）：

| 步骤 | 做法 | 结果 |
|---|---|---|
| 1 | HiSH release HAP 里的 `libqemu-system-aarch64.so`（41,438,848 B，**JIT 档**）与 `libslirp.so.0` 放 `entry/libs/arm64-v8a/`；`kernel_aarch64` / `rootfs_aarch64.qcow2` / `efi-virtio.rom` 放 `entry/src/main/resources/resfile/vm/` | `hvigor assembleHap` **16 s** 通过；HAP **295.5 → 399,298,500 B（+103.8 MB）** |
| 2 | `tools/update-device.ps1 -SkipRebuild` 覆盖安装 | **用户数据完好**：`dsh/home` 指纹 `links=8 size=3440`，装前 = 装后 |
| 3 | 经内嵌 Python 桥：`ctypes.CDLL("/data/storage/el1/bundle/libs/arm64/libqemu-system-aarch64.so")` → 在 Python 线程里调 `qemu_system_entry(argc, argv)`（签名 `int(int, const char**)`，逐字照 HiSH `napi_init.cpp`） | **加载成功、符号可解析**；`-L` / `-kernel` / `-drive` 全指 `resfile/vm/`，`rootfs` 先复制到 el2 再读写（resfile 只读） |
| 4 | guest 通道：`-chardev socket,path=<el2>/tmp/qga_socket,server=on,wait=off,id=qga0` + `virtserialport,name=org.qemu.guest_agent.0`，用 Python `AF_UNIX` 直连、换行分隔 JSON-RPC | **通了**。两个坑：`guest-sync-delimited` 必须先发 `\xff` 且**只**对它发；退出码字段是 **`exitcode`**（不是 `exit-code`） |

**读数（全部真机实测）**：

| # | 观测 | 读数 |
|---|---|---|
| 1 | VM 冷启动 → QGA 可用 | **11.8 s** |
| 2 | 串口引导日志（`-serial unix:…`，先连后启才抓得到） | `Run /init as init process`（内核 T+1.71s）→ OpenRC 起 → `udhcpc: lease of 10.0.2.15 obtained` → **`Starting QEMU Guest Agent ... [ ok ]`** → `hish:~#`（`Uptime 14.04s`） |
| 3 | guest 身份 | `uname -a` → `Linux hish 6.12.60 #44 SMP … aarch64`；`id` → `uid=0(root) gid=0(root)`；`df -h /` → 124.9G；`ls /bin \| wc -l` → 84 |
| 4 | **`/bin/sh` 可用** | `echo hi` → `hi`；`seq 1 2000 \| sort -rn \| head -3` → `2000/1999/1998`；后台子壳 + `wait` → `DONE_BG` |
| 5 | **`bash` 起初不存在** | `command -v bash` → 空、`BASH_RC=1` ⇒ Alpine 默认只有 busybox `ash` |
| 6 | **`apk add --no-cache bash`** | **装成**（mirrors.aliyun.com）**bash 5.2.37-r0**；guest 侧总耗时 **30.9 s**（JIT 档；对照 §2 第 6 行 TCI 档 `apk add python3` = 3m18s） |
| 7 | **`/bin/bash -c` 真执行** | `BASH_VERSION=5.2.37(1)-release`；`BASH_VERSINFO` = `5 2 37 1 release aarch64-alpine-linux-musl`；`$((6*7))`=42；`${BASH_VERSION%%(*}`=`5.2.37`；`bash -lc` 登录壳 `pwd`=`/` ⇒ **真 bash，不是 ash 伪装** |
| 8 | **退出码透传** | `exit 7` → `exitcode: 7` |
| 9 | 单次命令耗时 | `guest-exec` RPC **16~52 ms**（暖态）；"提交→拿到输出"端到端 **81~219 ms**（含轮询粒度） |
| 10 | 9p 共享目录 | `mount \| grep 9p` → `hostshare on /mnt/share type 9p (rw,…)`，guest 里能看到宿主侧 `files/vm/share`（属主 uid = 应用 uid）⇒ **宿主↔guest 传文件是现成的** |
| 11 | 常驻开销 | 应用进程 VmRSS **1,277,712 kB ≈ 1.22 GB**（512 MB 客户机 + TCG TB + Node + 核心树）；99 线程 |
| 12 | QEMU 身份 | QMP `query-status` → `{"status":"running"}`，版本 **10.2.0** |

**两条硬结论（都踩过，必须写下来）**：

1. **可执行内存没有被拦**（推翻 §1.4）：在我们**应用进程内**实测 `mmap` RWX / RW / RX、`mprotect(RW→RX)`、真跳过去执行，**全部 `errno=0`**。
   ⇒ `--jitless` 是 **V8 自己在启动时按能力选的档**（`ohos.permission.kernel.ALLOW_WRITABLE_CODE_MEMORY` 管的是 **V8 的申请**），
   **不是内核禁止 `PROT_EXEC`**；QEMU 自己 `mmap` 可执行页**不受这条约束** ⇒ **公开的 JIT 档产物直接用，"必须自建 TCI 档"取消**。
   （HiSH 市场版用解释档是**为过它自己的上架政策**，不是手机上跑不了 JIT —— 旧稿把这两件事混为一谈了。）
2. **同一个进程里 QEMU 只能初始化一次**：第一台 `quit` 后 `qemu_system_entry` **正常返回 `rc=0`**（两次实测 `after=200.7s` / `after=268.4s`），**应用进程安然无恙**；
   但在**同一个进程**里再起第二台 ⇒ **进程当场消失**（无 `cppcrash` / faultlog ⇒ 像 `exit()`，不是段错误）。
   ⇒ 产品化必须"**一个应用进程只拥有一台 VM**"：换 VM 走**换进程**（应用重启），或给 QEMU 的 exit 路径加护栏。

**本轮的临时物料（收尾按需还原，`coreVersion` 未动，仍 `+dshm.13`）**：
`entry/libs/arm64-v8a/libqemu-system-aarch64.so` + `libslirp.so.0`、`entry/src/main/resources/resfile/vm/`（三件）、设备侧 `files/vm/`（rootfs 副本 53 MB + 脚本 + socket）。
**未 commit、未 push。**
---

## 3. 与 DSHM 现状的关系：这不是"104 被推翻"，而是"104 之上多了一层"

`docs/104` 的三条判决性读数（随包 ELF `EACCES`、系统 `sh` 连 `stat` 都被拒、只有 `toybox` 能跑但与宿主同域）**全部仍然成立** ——
因为 HiSH 这条路上，**没有任何一个"我们的 ELF"被 execve**：guest 里的每个进程都是 QEMU 解释出来的，syscall 由**guest 内核**处理。

把三条路摆在一起看（判断该走哪条）：

| 路 | 真 shell？ | 代价 | 成立条件 |
|---|---|---|---|
| **A. 内置命令翻译层**（现状：`toybox` 真命令 + 我们自己的解析层） | ❌（无 shell 语义） | 已完成 | 无（已经能用） |
| **B. 远程 Host**（`docs/117`/`docs/118` 的 NAS + `ConnectPane`「远程 Host」） | ✅ **原生速度** | **0 MB** | 要有网 / 有台顺手的机器（已在我们手里） |
| **C. 本机虚拟机档**（本篇，HiSH 那条路） | ✅ 真 Alpine + 真 bash | **+76~87 MB**、内存、~5 s 冷启动、手机档掉到解释档 | 无（**离线也能用**） |

⇒ **B 和 C 不互斥**：B 是"在家 / 有网"的最优解，C 是"**离线兜底**"。而 B 我们**已经做完了**（只差 NAS 入口那一步）。

---

## 4. 如果要做：集成方案（拆哪四件、接哪两个缝）

### 4.1 要搬的四件套

1. **一份我们自己构建的 `libqemu-system-aarch64.so`（必须带 `--enable-tcg-interpreter`）** + 依赖 → 放 `entry/libs/arm64-v8a/`。
   **不能直接用他们发布的 `libs.zip`**（那是 JIT 档，见 §1.4）；构建来源是**他们的 fork 分支 `hish-libqemu`**
   （`qemu_system_entry` 这个导出符号是 fork 自加的，用上游 QEMU 顶替不了），配方见 `deps/libqemu/Makefile`。
   **本轮已静态核对**：该 `.so` 是 ELF64 LE / `EM_AARCH64` / `DYN`，带 **`.note.ohos.ident`（OHOS ABI tag = 1）**，`.comment` = `OHOS (dev) clang version 15.0.4` / `Linker: LLD 15.0.4`；
   `DT_NEEDED` **只有 3 条**：`libslirp.so.0` / `libz.so` / `libc.so`（两条系统自带、`libslirp.so.0` 随包带）
   ⇒ 依赖闭包干净，符合本仓 `tools/check-native-closure.mjs` 的判据。**唯一没验的是"在我们进程里真 `dlopen` 一次"**。
2. `kernel_aarch64`（12.4 MB）→ `entry/src/main/resources/rawfile/vm/`
3. `rootfs_aarch64.qcow2`（35~46 MB）→ 同上（或首次启动解包到 `files/`）
4. ArkTS 驱动：`startVm.ets`（命令行）+ **`QemuAgent.ets`（QGA 客户端）** —— 这两份是 MIT，可直接改

### 4.2 要接的两个缝

| 缝 | 对面是什么 | 怎么接 |
|---|---|---|
| **工具调用** `dsh-bash-local.execute()` | `{ cmd, cwd, env, timeout }` → `{ stdout, stderr, exitCode }` | 新增一个 **VM 档 transport**：命令经 QGA `guest-exec`（`capture-output`）+ 轮询 `guest-exec-status`。⚠️ guest 是 **Alpine**，默认只有 **busybox ash**：要保住 `bash -lc` 的语义得先 `apk add bash`（**未在 guest 里核实**），否则改走 `sh -lc` |
| **终端面板** | 一个 pty 语义的字节流 | 直接吃 QEMU 的 `-serial unix:<sock>`（`server,nowait`），前端用 **xterm.js**（可照抄 HiSH 的 `term.html`/`term.js`，MIT） |

### 4.3 分档与开关（**PC 档别动**）

- **PC / 2in1 档**：完全惰性早退（它本来就有 `ash=ok`，用不着 VM）；
- **手持档**：新增"本机 Linux（实验）"开关，默认关；开则起 VM，工具与终端都改走 VM 档；
- 生命周期要处理：VM 内存占用（`-m` 可调）、后台保活、崩溃自愈、共享目录（`virtio-9p` 挂我们的工作区，正好和现有 workspace 对齐）。

### 4.4 需要新写 / 新维护的东西（别低估）

1. **一份我们自己的 QEMU（TCI 档）构建流水线** —— 最容易被低估的一条：公开产物只有 JIT 档，手机档又 JIT 不了（§1.4），
   所以必须能用他们的 fork + 他们的 buildroot 复现出 `--enable-tcg-interpreter` 的 `.so`，**并且以后能跟着他们的 tag 升级**（§5 第 8 条）；
2. 我们自己的 NAPI 启动器（或者直接用他们的 `libentry.so` —— 但那会把 GPLv2 的链接面拉到我们的 native 层，见 §5）；
3. 镜像与共享目录的落盘、校验、升级、清理策略；
4. VM 档的失败降级（起不来 → 自动回落到现状的翻译层，绝不把"看起来能用"当能用 —— 这是 `docs/115` 的教训）；
5. 一份真机验收门禁（冷启动时延、`bash -c` 往返、退出码/输出正确性、断网可用性）；
6. **要在我们自己的 HAP 里做一次最小 PoC**（把 TCI 档 `.so` 放进 `entry/libs/`）、量出 §6 剩下的 ②，并实测 `dlopen` 是否被策略拒 ——
   这一条**必须改产品包**（临时加一件 libs），所以本轮**没做**。

---

## 5. 代价与风险（按重要性排）

| # | 项 | 说明 |
|---|---|---|
| 1 | **许可证：GPLv2** | HiSH 自己的代码是 MIT，但它**捆绑 QEMU（GPLv2）与 Linux 内核（GPLv2）**。我们要分发这些二进制，就**必须**同时给出许可证文本与**对应源码的可获得性**（仓库里放我们的 QEMU fork/wrapper + 指向上游，或写"书面要约"）。这是**必做功课**，不是可选项 |
| 2 | **署名义务** | HiSH README 明确要求「关于」页注明**基于 HiSH** 与仓库地址（惯例 + MIT 版权声明保留） |
| 3 | **体积** | **实测 +103.8 MB**（HAP 295.5 → 399,298,500 B，+35%）；与用户此前"轻量化"的方向**直接冲突**（§2.5 步骤 1） |
| 4 | ~~手机档只能解释执行，且现成产物不适用~~ **（已销）** | 见 §1.4 / §2.5：**JIT 档实测直接可用**（应用里可执行内存未被拦），"自建 TCI 档"取消。参考读数：JIT 档 `apk add bash` guest 侧 **30.9 s**（§2 第 6 行的 TCI 档 `apk add python3` 是 3m18s） |
| 5 | **冷启动与常驻** | **实测**：VM 冷启动 → QGA 可用 **11.8 s**（宿主 App 起来 ~5 s ⇒ 用户体感约 17 s）；应用进程 VmRSS **1,277,712 kB ≈ 1.22 GB**（含 512 MB 客户机 + TCG TB）；**电池 / 发热未量**（§2.5 读数 1 / 11） |
| 6 | **API / ABI 兼容** | **已动态验证**（§2.5）：`targetSdk 26` 自签应用进程内 `dlopen` + 起 VM + QGA 收命令，全通 ⇒ **ABI 无障碍**。剩下要守的是 §2.5 的"一进程一 VM"与 GPLv2 |
| 7 | **上架政策** | 若 DSHM 也想上架：HiSH 的"上架版不给 JIT"就是先例；内含 Linux VM/模拟器可能触发审核问询（**我们不打算上架，此条仅备忘**） |
| 8 | **维护面** | 引入 `harmoninux/qemu` 分支 + 内核 + 镜像三条外部依赖 ⇒ 以后跟着升级是一份持续工作 |

---

## 6. 裁定与建议


**裁定（PoC 后更新）**：这条路**成立、可行，而且已经在我们自己的 HAP 里端到端跑通**（§2.5：起 VM → guest 里 `bash 5.2.37` 执行命令 → 输出与退出码取回）。
它仍然是一个**新子系统**，不是"把 core 拆出来接上"那么轻；但现在挡在前面的只剩**代价与工程约束**：
体积 **+103.8 MB**、常驻 **+1.15 GB VmRSS**、冷启动 **11.8 s**、**一进程一 VM**、GPLv2 义务 —— **不再是"技术上能不能"**。

**建议的推进顺序**：

1. **首选仍是远程 Host**（`docs/117` / `docs/118`）：**0 MB、原生速度**，是"手机 / 平板真 bash"的主路；
   VM 路线适合**手上没有 PC 可当执行主机**的用户，两者可以并存（VM 当兜底）。
2. **若要做 VM 集成，最小可用面**（下面每条都有本轮实测依据）：
   - **默认不启**：只在手持档、且用户显式打开时启动；**PC 档完全不动**；
   - **降配**：先按 `-m 256M` / 更小 `tb-size` / `-smp 1` 试，把常驻从 1.15 GB 压下来（**未验**，见 §7）；
   - **一进程一 VM**：VM 停机 = 应用进程重来；别在同进程里起第二台（§2.5 硬结论 2）；
   - **通道用 QGA，不用串口**：换行分隔 JSON-RPC 已在 Python 里跑通；退出码字段是 `exitcode`；
   - **镜像要预装 bash**：本轮的 rootfs 只有 busybox ash，现场 `apk add bash` 花了 **30.9 s** 且依赖外网；
   - **必做功课**：GPLv2 许可证文本 + 对应源码可获得性 + 「关于」页署名（§5 第 1、2 条）。
3. **不要误解**：VM **不是** `docs/104` 的替代 —— 104 的"应用域内 execve 一律 `EACCES`"**仍然成立**，
   VM 是**在它之上又盖了一层**；体积 / 内存 / 启动的代价必须和"工具能调 bash"的收益一起算。

**如果只是想"现在就能用"**：让用户**直接用 HiSH**（已装、能用、`apk add` 装什么都行）——它和 DSHM 不冲突，
只是"另一个 App 里的 Linux"，而不是"DSHM 的工具能调 bash"。

---

## 7. 未验证清单（照实记，别当已完成）

**已被 §2.5 销掉（这一轮的 PoC 直接把它们量了）**：

- ~~在我们自己的 HAP 里 `dlopen` 这份 `.so` 并真的起 VM~~ ⇒ **做了，成功**；
- ~~`bash -c` / 命令经 QGA 的单次往返耗时~~ ⇒ **16~52 ms（RPC）/ 81~219 ms（端到端）**；
- ~~guest 里 `bash` 是否存在~~ ⇒ **默认没有**（只有 busybox ash），`apk add --no-cache bash` **装成 5.2.37**，`bash -c` / `bash -lc` 都验过；
- ~~`dlopen` 放在 `libs/` 之外是否被拒~~ ⇒ 旧轮已证 data 目录**拒**（E39 原样），`entry/libs/` **可以**；
- ~~解释档（TCI）我们自己能不能构建出来~~ ⇒ **不需要**（JIT 档可用，见 §1.4 更正）。

**仍然未做 / 未定论（照实记）**：

- **产品化集成**：本轮是**临时 PoC**（`entry/libs` + `resfile/vm` 是临时物料，收尾按需还原）；把它接成"模型的 bash 工具"还没写一行；
- **平板 / 2in1 的对照**（手上只有手机）；
- **电池 / 发热 / 长时间稳定性**（未量）；**降配方案**（`-m 256M`、`tb-size`、`-smp`）未试；
- **一进程一 VM 的硬约束**怎么在架构上落（换进程重启？给 exit 加护栏？未定）；
- guest 里 `python3` / `node` 的实测耗时（未量）；
- ~~已由上一轮销掉的旧条目~~：guest 出网（`apk add` 实测在下载）；~~上架版无 JIT 是政策还是平台强制~~ ⇒ 见 §1.4 更正：**是政策选择，不是平台禁止**。

## 8. 出处

- `https://github.com/harmoninux/HiSH`（README / README_EN / LICENSE / `docs/guide/*` / `entry/src/main/ets/lib/{startVm,QemuAgent,QemuAgentManager}.ets` / `entry/src/main/cpp/napi_init.cpp` / `resources/rawfile/term/*` / `deps/Makefile` / `deps/libqemu/Makefile`）
- `https://github.com/harmoninux/qemu`（`hish-libqemu` 分支；release `hish-20260110` 的 `libs.zip`）
- `https://github.com/harmoninux/linux-config`（`kernel-20260228` / `rootfs-20260117` / `rootfs-20251213`）
- 应用市场条目：`app.hackeris.hish`（设备侧 `bm dump -n app.hackeris.hish` 的读数见 §2）
- 本仓相关：`docs/104`（手持档 execve 的 MAC 判决）、`docs/114`（WorkBuddy 的取舍）、`docs/115`（进程内解包）、`docs/117`/`docs/118`（远程 Host）
- `https://codeload.github.com/harmoninux/HiSH/tar.gz/refs/tags/release-20260516`（本轮**按 tag 拉全量源码树**核对，7,539,295 B；§1.2/§1.3/§1.4 的路径与命令面都从这份读）
- `https://github.com/harmoninux/HiSH/releases/download/release-20260516/entry-default-20260516.zip`（43,018,705 B ⇒ 内含 `entry-default-unsigned.hap` 163,743,041 B；§1.5 的条目大小是直接读中央目录得的）
- `https://github.com/harmoninux/qemu/releases/download/hish-20260110/libs.zip`（29,786,658 B；未 strip ⇒ 本轮用它核 `DT_NEEDED` / `.dynsym` / `.comment`（构建工具链）/ `.note.ohos.ident`）
- 本仓相关（JIT 权限闸门）：`docs/50` E13、`docs/70` §0.1、`docs/90`（`--jitless` 与 `grant request permissions failed`）、`tools/check-store-readiness.mjs`

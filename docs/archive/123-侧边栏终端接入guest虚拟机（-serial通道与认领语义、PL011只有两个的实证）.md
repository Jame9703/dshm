# 123 · 侧边栏终端接入 guest 虚拟机（`-serial` 通道 · 控制终端认领 · PL011 只有两个的实证）

> 承接 `docs/120`（产品化：把 `ctx.subprocess.spawn` 改派到随包 QEMU guest）与 `docs/122`
> （bash 通道收口）。本档记「**侧边栏终端**」这一条缝的接法：把 `ctx.subprocess.spawnTerminal`
> 接到**同一台 guest VM 的第二个串口**上，并把它前面的 `terminalEnvironment()` /
> `resolveExecutable()` 一起换掉（少换一个，会话永远到不了这一跳）。
> 设备：`62T0225B18039433`（VYG-AL00 / API 26 / `const.product.devicetype=phone` / 手持档），
> `coreVersion` `+dshm.20`。

---

## 0. 一句话结论

| 项 | 结论（都有真机读数/证据，见 §6） |
|---|---|
| 通道选型 | **`-serial` + socket chardev**，**不用** `virtio-console`：后者在 guest 里是 `/dev/vport5p1`，`ls -l` = `251, 1`（**动态 cdev，不是 tty**）⇒ 没有 termios / 行规程 / 作业控制 |
| guest tty | `/dev/ttyAMA<i>`（`204, 64` = PL011，真 tty）。0 号留给控制台日志（`serial.log`），终端从 1 号开始 |
| 端口数 | **1**（不是 3）：guest 里**只有 2 个 PL011** —— 内核日志 `9000000.pl011: ttyAMA0` / `9040000.pl011: ttyAMA1`，第 3/4 条 `-serial` 不产生 tty |
| 挂 shell | Linux 既有语义：**会话首领首开一个没有控制终端的 tty ⇒ 该 tty 成为它的控制终端**。`setsid /bin/busybox sh -c 'exec <shell> <args> < /dev/ttyAMA1 > /dev/ttyAMA1 2>&1' &` |
| 换的方法 | `spawnTerminal` + `terminalEnvironment` + `resolveExecutable` **三个一起**（终端链路在到达 `spawnTerminal` 之前先要解析 shell） |
| PC / 2in1 | **零变化**：判据 `shimRunnable()` 为真 ⇒ 四个方法一个都不换（门禁带反向臂） |
| 认领失败 | **fail-loud**：拿不到前台 pid 就抛错，绝不留一个「屏幕永远空白」的空壳终端 |
| 真机结论 | 端到端通：`create` 13.9 s（含 VM 冷启动）→ snapshot `~/Download/harness # ` → 写入回执 `PROOF=DSHM-TERM-READY` / `TTY=/dev/ttyAMA1` / `uid=0(root)` → `resize 132x43` 在 guest 里读到 `43 132` → **第二个终端明确报错**（不是空壳）→ `close` 后端口归还、下一个终端仍拿 `#1` |

---

## 1. 要接的是哪条缝

侧边栏终端走的是**链 2**（与模型的 `bash` 工具那条链 1 并列）：

```
ui-sidebar-terminal → dsh-api-terminal-controller → dsh-terminal-bash → ctx.subprocess.spawnTerminal
```

`dsh-api-terminal-controller/lib/index.js` 里三处都与 `subprocess` 直接相关：

| 行 | 调用 | 手持档在宿主沙箱里的结果 |
|---|---|---|
| `:16` | `subprocess.terminalEnvironment(signal)` | 回答 `platform: win32` / `defaultShell: cmd.exe`（那是**官方桌面端**的口径）|
| `:19` | `subprocess.resolveExecutable(shell.path, …)` | 对 `cmd.exe` / `/bin/sh` 一律 `ENOENT` |
| `:999` | `subprocess.spawnTerminal({...})` | 本机没有可 execve 的 shell、也没有能被 dlopen 的 pty 后端 ⇒ 打不开 |

⇒ **三个入口必须一起换**。只换 `spawnTerminal`，会话在 `:16`/`:19` 就已经 reject，
永远到不了我们这一跳（这正是「看着像没接线」的典型形态）。

---

## 2. 通道选型：为什么是额外的 `-serial`，不是 `virtio-console`

两条候选都真机验过：

| 候选 | QEMU argv | guest 侧 | `ls -l` | 判定 |
|---|---|---|---|---|
| `virtserialport` | `-device virtio-serial-pci` + `-device virtserialport,chardev=…` | `/dev/vport5p1` | `251, 1`（动态 cdev）| **不可用**：不是 tty，没有 termios / 行规程 / 作业控制（交互式 shell 挂上去只能得到哑终端）|
| `-serial` | `-chardev socket,id=term1,path=<vm>/tmp/term1,server=on,wait=off` + `-serial chardev:term1` | `/dev/ttyAMA1` | `204, 64`（PL011）| **可用**：真 tty；镜像里 `ttyAMA0` 上本来就跑着 autologin 的 root shell —— 同一套机制，只是把 chardev 从 `file` 换成 `socket` 让宿主连得上 |

宿主侧就是一条 unix socket：`net.connect("<vm>/tmp/term1")`。`server=on,wait=off` 的语义是
**QEMU 建 socket 后不等连接**（宿主随时连、连了就通），这也让"后连的宿主进程"能接上一个已经在跑的 guest。

0 号串口继续留给控制台日志（`-chardev file,id=ser0,path=<vm>/serial.log` + `-serial chardev:ser0`）——
那份日志是**本档全部真机取证的一手材料**（§4 的 PL011 计数就是这么读出来的），不能被终端顶掉。

---

## 3. guest 侧：怎么把一个交互式 shell 挂到这条串口上

镜像里**没有** `telnetd` / `socat` / `agetty` 的替代品，也不该为此再塞一个守护进程。用 Linux 的一条既有语义：

> **会话首领（session leader）第一次 `open` 一个还没有控制终端的 tty ⇒ 该 tty 成为它的控制终端。**

所以驱动脚本是：

```sh
setsid /bin/busybox sh -c 'exec <shell> <args> < <tty> > <tty> 2>&1' &
```

关键点有两处：

1. **内层 `sh` 刚 `setsid` 完 = 会话首领且无控制终端**；`exec` 的**重定向由它执行** ⇒ `open(<tty>)` 成功
   ⇒ 控制终端认领成功 ⇒ `exec` 之后 shell 拿到控制终端（作业控制、`SIGWINCH` 都在）。
2. `/bin/setsid` 在镜像里**没有链接**（`ls -l` → MISSING），必须走 `busybox setsid`。

真机实测（`/proc/<pid>/stat` 原始字段）：该进程 `pgrp = session = pid`、`tty_nr = 1026`（非 0 = 有控制终端）。

### 3.1 起 shell 之后必须拿到回执，拿不到就抛错

起 shell 的脚本里带一行标记 `echo DSHM_TERM_SPAWNED`；宿主随后在 `CLAIM_TIMEOUT_MS = 8000 ms` 内
扫 `/proc/<pid>/stat` 找「`stdin` 指向本 tty」的那个会话首领，取它的 `tpgid`（前台进程组）与 `pid`。

**这只是前置条件，不是终点**：拿不到就**当场抛错**（「`<tty>` 上没有 shell 认领终端…」并提示"若反复出现说明端口表与 guest 的 tty 对不上"），
走既有 `catch` 归还端口并 `destroy` socket。绝不返回半成品 —— 半成品在 UI 上的样子就是
「终端开了、光标闪、屏幕永远空白」，用户完全无法判断是没接上还是命令没执行。

---

## 4. 端口数：3 → 1（这条是**真机读数钉死的**，不是"留余量"）

### 4.1 第一个错：按"经典 virt 有 4 个槽位"取 3

`paths.js` 初版写 `TERM_PORTS = 3`，理由是"0 号留给串口日志 ⇒ 终端 1..3"。
真机上第二个终端的样子是：

- UI 拿到 `#2 /dev/ttyAMA2`，`state: running`；
- 8.3 s 后日志是 `shell pid=未知`；**屏幕永远空白**。

### 4.2 决定性读数：guest 里只有 2 个 PL011

`<vm>/serial.log`（宿主持久留痕的内核日志）：

```
9000000.pl011: ttyAMA0 at MMIO 0x9000000 (irq = 13, base_baud = 0) is a PL011 rev1
9040000.pl011: ttyAMA1 at MMIO 0x9040000 (irq = 14, base_baud = 0) is a PL011 rev1
```

**没有** 9080000。guest 里 `ls /dev/ttyAMA*` = `0 1`、`TTYCOUNT=2`。
⇒ 第 3/4 条 `-serial` **根本不产生 tty**，`-chardev term2/term3` 只是白建两个 socket，
于是 2 号端口必然开出**没有 shell 的死终端**。

### 4.3 修法：端口表与 guest 的事实对齐 + 两道 fail-loud

| 改动 | 位置 | 判据 |
|---|---|---|
| `TERM_PORTS` `3 → 1` | `lib/paths.js`（头注重写，含上面的内核日志实证）| 端口表**只能等于 guest 真有的 UART 数** |
| 先验 tty 设备 | `lib/terminal.js` 的 `spawnScript`：`[ -c <tty> ] || { echo DSHM_TERM_NO_TTY; exit 3; }` | 端口表与 guest 的 UART 数**不一致**时立刻抛「guest 里没有 X 这个 tty 设备」，而不是等 8 s 认领超时 |
| 认领失败抛错 | 见 §3.1 | 见 §3.1 |

代价是**最多 1 个并发终端**，第二个会拿到可行动的报错
（`端侧终端端口已用满（本档最多 1 个并发终端），请先关闭一个终端再开新的`）。
这条取舍是刻意的：**宁可如实说"先关一个"，也不给一个看起来能用、实际是死的第二个终端**。

### 4.4 真要多终端：两条后续候选（本轮**未做**，别当成已支持）

- `-device virtconsole,chardev=…` ⇒ guest 侧应是 `/dev/hvc*`（mainline `virtio_console` 会给 console 端口建真 tty）
  —— **先要确认镜像的驱动真的建 `hvc` 节点**（本轮实测 `ls /dev/hvc*` 是空的）；
- 去掉 cmdline 的 `acpi=on`（走 DT 路径：QEMU 的 DT 按 `serial_hd(i)` 建 UART 节点，可能给出 4 个）
  —— 风险落在**整机启动路径**上，改完必须重跑 bash 通道验收。

---

## 5. 与本地实现的差异（刻意，写在这里而不是藏起来）

| # | 差异 | 为什么 |
|---|---|---|
| ① | **窗口尺寸靠 ioctl 带外设置**：`resize(cols, rows)` 落成 guest 侧 `stty -F <tty> rows R cols C` | QEMU 的 chardev 不带 winsize 通道。`TIOCSWINSZ` 会由 guest 内核自己给前台进程组发 `SIGWINCH`，所以交互式程序的重绘是通的 |
| ② | **前台进程组靠 `/proc` 探测**：扫 `/proc/<pid>/stat` 找「stdin 指向本 tty」的会话首领，取它的 `tpgid` | guest 的 `ps -o` 支持 `pid/pgid/sid/tty/stat` 但**没有 `tpgid`**。结果按 `FOREGROUND_TTL_MS = 1000` 缓存 —— 上游的 `inspectForeground()` 会被**逐块输出**调用，不能每块都问一次 guest |
| ③ | **pid 是 guest 侧的 pid** | 宿主上没有对应进程（QEMU 在进程内跑，没有 per-shell 的宿主 pid）。上游只用它做展示与 `inspectActivity`，语义不受影响 |
| ④ | **`done` 的 `exitCode` 恒为 `null`** | shell 死在 guest 里，宿主拿不到它的退出码（tty 通道断开只能说明「这条 tty 没了」）。`signal` 如实写 `SIGHUP` / `SIGTERM` |
| ⑤ | **并发上限 = 1** | 见 §4 |

收尾按**进程组**杀（`kill -TERM -<pgid>` 再 `kill -KILL -<pgid>`）：否则 tty 会被一个活着的 shell 攥住，
下一次会话拿到的就是一个「有人在里面」的设备。

---

## 6. 真机读数（`62T0225B18039433`，2026-10-08，`+dshm.20`）

### 6.1 宿主侧 RPC（不依赖 UI，走 `/api/<ns>/<method>`）

| 步骤 | 读数 |
|---|---|
| `terminal/environment` | `{cwd: "~/Download/harness", maxInputBytes: 65536, maxCols: 500, maxRows: 200, scrollback: 1000}` |
| `terminal/shells` | `[{path:"/bin/sh",name:"sh",args:["-i"]},{path:"/bin/bash",name:"bash",args:["-i"]}]` |
| `terminal/create` | **13868 ms**（含 VM 冷启动）⇒ `{id, shell:{path:"/bin/sh"}, state:"running", cols:100, rows:30}` |
| `terminal/follow`（WS） | 第一帧 `snapshot` = `~/Download/harness # ` |
| `terminal/write` | `{"ok":true}`；随后 WS 收到 `output` 帧（含回显与 `[J` 清屏序列）|
| `terminal/resize(132, 43)` | `{"ok":true}` |
| 第二个终端 | `create` **当场**回 `gateway/internal`：`端侧终端端口已用满（本档最多 1 个并发终端），请先关闭一个终端再开新的` |
| `terminal/close` 后 | 再 `create` 仍拿到 `#1`（端口已归还，不是"用过一次就没了"）|

宿主 `node-output.log` 的对应两行（插件的 `diag`）：

```
[dshm-vm-bash] 终端会话已建立（#1 /dev/ttyAMA1，argv=/bin/sh -i，shell pid=734，前台进程组=734）
[dshm-vm-bash] 终端会话已关闭（#1 /dev/ttyAMA1）
```

### 6.2 guest 侧回执（经共享目录回读，见 §6.3）

```
PROOF=DSHM-TERM-READY
TTY=/dev/ttyAMA1          # 与 -serial 的顺序一致，且是唯一的终端 tty
~/Download/harness
uid=0(root) gid=0(root)
BASH=                     # 默认 shell 是 busybox sh ⇒ 没有 BASH 变量（如实为空，不假装）
```

`resize 132x43` 之后在 guest 里读：

```
43 132        # stty size（shell 自己的 stdin）
43 132        # stty -F /dev/ttyAMA1 size（设备本身）
```

### 6.3 读 0700 目录的办法（本档所有 guest 回执都靠它）

`<app>/files/` 是 `0700` ⇒ `hdc file recv` / `hdc shell cat` **都读不到**（`recv` 直接失败、
`ls -l` 倒是看得见 —— 所以"文件明明在"与"能读到"是两件事）。两条可用的路：

- **宿主的 Python 桥**（首选）：`GET http://127.0.0.1:<fport>/dshm-python/run-get?token=<宿主 token>&code=<urlencoded python>`；
- **核心树里的文件**：el2 的 `dsh/cores/<ver>/…` 是可读的（`hdc file recv` 直接取），
  这一条是"设备到底在跑哪一版代码"最硬的判据（本轮的 terminal.js / paths.js 逐字节 sha256 比对就是走它）。

### 6.4 装机与重解包（同一个版本号也必须真的换树）

本轮**没有**升版本号（仍是 `+dshm.20`），换成"同一个版本号、不同内容"的情形：
端侧 `BundledCore` 的跳过判据是 **资源包大小指纹**（`.dshm-bundled-stamp` vs `srcSize`），
不是"版本已安装就跳过" ⇒ 容器字节变了就重解。实测：装机后设备树里的
`dshm-vm-bash/lib/paths.js` / `terminal.js` 与本机源码 **sha256 逐字节相同**，
且 `paths.js` 里读到的就是 `export const TERM_PORTS = 1;`。

> ⚠️ 这条只对"**容器字节真的变了**"成立。若改动后容器字节凑巧没变（例如只改注释），
> 端侧会跳过重解 ⇒ 还是旧树。稳妥做法仍是**升 `coreVersion`**（AGENTS.md 的「出包三坑」第 2 条）。

---

## 7. 接线与门禁

| 位置 | 内容 |
|---|---|
| `hostcore/plugins/dshm-vm-bash/lib/paths.js` | `TERM_PORTS = 1`、`termSocket(i)` = `<vm>/tmp/term<i>`、`termTty(i)` = `/dev/ttyAMA<i>` |
| `.../lib/vm.js` | boot argv 在 `-chardev file,id=ser0` 之后追加 `TERM_PORTS` 组 socket chardev + `-serial`；stale socket 清理带 `termSocket(k + 1)` |
| `.../lib/terminal.js` | `createVmTerminal()` / `terminalDiagnostics()`；handle 形状对齐 `LocalTerminalHandle`（`write` / `resize` / `inspectForeground` / `signalForeground` / `inspectActivity` / `terminate`）|
| `.../lib/index.js` | `GUEST_SHELL_EXECUTABLES`（sh/ash/bash）、`shouldTakeOverTerminal()`、`guestShellPath()`；`apply()` 里同时换 `spawn` + `spawnTerminal` + `terminalEnvironment` + `resolveExecutable` |
| `.../package.json` | `files` 加 `lib/terminal.js` |
| `hostcore/profile/ondevice/cordis.patch.yml` | ⑬ 段补整段说明（通道选型 / 认领语义 / 三个入口一起换 / `shellPath: /usr/bin/zsh` 不动）|
| `tools/device-code-fingerprint.ps1` | 关键文件 9 → **10**（加 `lib/terminal.js`）|
| `tools/check-vm-bash.mjs` | **116 → 188** 项：新增「接管面」「shell 解析」「QEMU argv」「guest 侧口径与接线」四段 |

门禁里有几条是**反向臂**（"修好了"必须有牙）：

- `DSHM_VM_BASH=off` ⇒ **四个方法一个都不换**（PC / 2in1 档的回归守卫）；
- 白名单外的 `argv[0]`（含 `/usr/bin/zsh`）⇒ **真的**调回原 `resolveExecutable` / `spawnTerminal`（不是我们自己编一个答案）；
- QEMU argv 里**不再出现** `term2` / `term3`（guest 里没有对应的 tty）；
- `-serial` 恰好 2 条（`ser0` + `term1`）且顺序 = `ser0, term1`（顺序即 `/dev/ttyAMA<i>` 的编号，错一位整条映射全错）；
- `terminal.js` 里必须有 `DSHM_TERM_NO_TTY` / `[ -c ` / `没有 shell 认领终端` 三处 fail-loud 标记。

本轮跑过的门禁（全绿）：`check-vm-bash` 188/188、`check-resfile-core-zip`、
`check-core-openharmony-patches` 172/0、`check-native-closure` PASS、`assert-core-entrypoints` PASS、
`assert-fs-search-fallback` 73/0、`check-ptc-wiring` PASS、`check-fs-local-permission` PASS、
`compat-drift` 无漂移、`check-ptc-runtime-inproc` / `check-web-fetch-jitless` / `check-worker-jitless` /
`check-internal-undici` / `check-fetch-shim.cjs` / `check-ptc-ts-strip` / `check-skill-sync` /
`check-denial-hints` / `check-market-bridge` / `check-profile-pnpm-bridge` / `check-decor-button-mode` /
`assert-cli-shim` 40/40、`check-parity`、`assert-exec-fix` 38/38、`assert-python-bridge` 69/69、
`check-doc-refs`、`check-dead-code`、`check-workspace-claim` 13/13、`assert-resfile-sync` 14/14。

---

## 8. 刻意不做（以及怎么恢复）

- **不为非白名单程序开工**：`argv[0]` 必须能过 `translateProgram`（`sh` / `ash` / `bash` 及其常见绝对路径），
  其余（含 `/usr/bin/zsh`、`python3`、宿主随包假壳）一律交回**原实现**，不假装能跑；
- **不把宿主随包假壳（`bin/pnpm` / `python3`…）放进 guest 白名单**：它们的逻辑在宿主上；
- **`terminal-bash` 那行的 `shellPath: /usr/bin/zsh` 不动**：那是 2in1 档的系统 zsh（链 1 / backend 注册表用），
  手持档走的是 terminal-controller 的默认 shell（由本插件回答 `/bin/sh`，候选表里 `bash` 也被解析出来）；
- **不做"看起来能用"的第二个终端**：见 §4.3。

恢复：删掉 `cordis.patch.yml` 的 ⑬ insert 行 + `pack-core.mjs` 里 `DSHM_PLUGIN_PACKAGES` 的那一项，
即回到"手持档侧边栏终端打不开"（本插件的全部行为都在包内，不碰其它任何东西）。
临时回退见 `cordis.patch.yml` ⑬ 段的 `DSHM_VM_BASH=off`。

---

## 9. 本轮**未做**（诚实清单）

1. **真机 UI 点击验证**：链路是拿「UI 调用的那四个 RPC」逐条打的（protocol 层端到端），
   但**没有**在手机上手动点开侧边栏终端这一下（需要在设备上操作 UI）；
2. **多终端**：见 §4.4，两条候选路各需一次真机验证；
3. **guest 侧 `exitCode`**：见 §5 ④，宿主拿不到；
4. **`resize` 的失败面**：`stty` 未装/被拒时只记一行日志、不 reject（`resize` 是"尽力而为"的一条），
   未做更细的判据。


# 122 · 手持档 guest VM bash 通道收口：QGA 客户端的根因 + guest 侧三处阻断

> 承接 `docs/120`（产品化集成：把 `ctx.subprocess.spawn` 改派到随包 QEMU guest）
> 与 `docs/121`（真机首跑的两个 P0 与一个 P1）。本档记两件事：
> ① 上一轮那句「**QGA 150 s 不响应**」的**最终根因** —— 全在 `qga.js` 这一层，不在 guest、
>    不在 QEMU、不在内核（`+dshm.18`）；
> ② 真机第二次首跑暴露的 **guest 侧三处阻断** —— 自指符号链接、工作区在应用沙箱之外、
>    以及"一进程一 VM"缺的**串行**闸门（`+dshm.19`）。
> 设备：`62T0225B18039433`（VYG-AL00 / API 26 / `const.product.devicetype=phone` / 手持档）。

---

## 0. 一句话结论

| 项 | 症状（真机原文/读数） | 根因 | 修法 | 版本 |
|---|---|---|---|---|
| **QGA** | `QGA 在 150000 ms 内没有就绪`；同时 QMP 报 `query-status=running: true`、串口一路到 `hish:~#` | ① `exchange()` **一次问答挂一次监听器**：读完第一行就 `socket.off("data")`，而 Node 的 `net.Socket` 一旦进过 flowing 模式，**摘掉最后一个 `data` 监听器不会自动 pause** ⇒ 两次问答之间到达的字节被静默读掉并丢弃；② **只认第一行**，而带 `\xff` 的 `guest-sync-delimited` 请求**必然**先带回一行 `{"error":{"class":"GenericError","desc":"JSON parse error, stray '\uFFFD'"}}`，真应答紧随其后 ⇒ 把杂音当最终答案 reject。两个错叠加 = **死循环**，再叠上调用点的 `catch {}` 静默 ⇒ 现场一行证据都不留 | 整份重写 `lib/qga.js`：`LineStream`（一条连接**只挂一次**监听器 + 行队列 + 单等待者）、`sync()` 跳杂音**直到看见自己的 id**、**只有"一个字节都没收到"才丢弃连接**、每次问答留一行读数 | `+dshm.18` |
| **guest ①** | `guest 侧 bash 未装成（exit=1）：DSHM_PROVISION_NO_APK` | provision 里的 `ln -sfn ${share} ${EL2_FILES}`，而 `share`（宿主沙箱根）与 `EL2_FILES` 是**同一个字符串** ⇒ 造出一条**指向自己的符号链接**，guest 里宿主路径恒不可达（失败恰好落在紧接着的 `cd` 上，所以只剩那个标签） | 链接目标改成**挂载点** `/mnt/share`；并顺手确认镜像自带的那份 9p 真在 `/proc/mounts` 里 | `+dshm.19` |
| **guest ②** | guest 里 `cd ~/Download/harness` → `No such file or directory` | 工作区可以落在**应用沙箱之外**（用户授权目录），不在 fsdev0 的 `path` 里 ⇒ guest 根本看不到它 | 第二份 9p（`mount_tag=hostshare2`）：`path` = **被授权的那一层**，在 guest 里挂到**同一个绝对路径** | `+dshm.19` |
| **guest ③** | 第一次启动失败后再点一条 `bash` ⇒ **应用进程当场消失**（无 faultlog） | `ensureRunning()` 的重入闸门只挡**并发**（`pending` 单飞）；**串行**的第二次调用会绕过它，真的起第二台 QEMU —— 而"一进程一 VM"是硬约束（上一轮 PoC 实测：同进程第二台必带走进程） | 新增 `startGate(state)`：**本进程已经拉起过 QEMU 就拒绝**，报文告诉用户重启应用 | `+dshm.19` |

> 一句话：`+dshm.18` 把**通道**修通（QGA 客户端），`+dshm.19` 把**通道两端的地面**铺平
> （guest 侧路径与挂载）。真机端到端读数见 §3。

---

## 1. QGA 根因（`+dshm.18`）

### 1.1 现场（`docs/121` §3 的记录）

QEMU 活着（`query-status` → `running: true`）、盘被写过（`rootfs.qcow2` +331,776 B = 81×4096）、
串口一路到 `login[658]: root login on 'ttyAMA0'` / `hish:~#`（连 QEMU Guest Agent 的
`Starting QEMU Guest Agent ... [ ok ]` 都在），**只有宿主这一侧**整整 150 s 一次都没 sync 上，
而且日志里**连一行 QGA 错误都没有**。

### 1.2 两条互相叠加的设计错误

1. **一次问答挂一次监听器**（旧 `exchange()`）：读完第一行就 `socket.off("data")`。
   Node 的 `net.Socket` 一旦进过 flowing 模式，**摘掉最后一个 `data` 监听器不会自动 pause** ——
   新到的字节被流层当成"没人要"直接丢掉。于是"下一次重试捡回那条真应答"这条自救路径**结构性失效**。
2. **只认第一行**：真机的 `\xff` sentinel 会让 qemu-ga 先回一行
   `{"error":{"class":"GenericError","desc":"JSON parse error, stray '\uFFFD'"}}`（**每一条带
   `\xff` 的请求都必然先带一行**），真正的 `\xff{"return": 424242}` 紧随其后。旧实现把杂音当最终答案
   reject ⇒ 永远 sync 不上。

两条错**合起来**才是死循环：①让"下次重试捡回真应答"失效，②让"这一次就一定失败"。
而 `ensureRunning()` 的等待循环当时是 `catch {}` ⇒ 现场没有一点证据（**最贵的不是 bug，是证据被吞**）。

### 1.3 三个决定性实验（方法可复用）

| 实验 | 做法 | 观测 | 说明 |
|---|---|---|---|
| **chardev-change** | QMP 里 `{"execute":"chardev-change","arguments":{"id":"qga0","backend":{"type":"socket","data":{"addr":{"type":"unix","data":{"path":"…/qga2_socket"}},"server":true,"wait":false}}}}` | 换 socket 后**新连接立刻收到 guest 应答** | 证明"通道与 guest 都没问题，问题在客户端这一层" |
| **FIONREAD**（不消费数据） | Python 桥里把 `/proc/self/fd/*` 中 `socket:[ino]` 的 fd 传 `fcntl.ioctl(fd, 0x541B, b"\0"*4)` | `fd 81`（inode `55804821`）有 **68 B 未读** = 上一条空闲 QMP 连接的 `{"return":{"status":"running","running":true}}` | 能在不破坏连接的前提下回答"这条连接里有没有字节" |
| **新连接 vs 旧连接** | 对同一条 QGA 反复"老连接读 / 新连接读" | 那种"开机就连、一辈子不换"的旧连接**永远收不到任何字节**；**每条新连接**立刻有 | ⇒ 判据定成"**一个字节都没收到才换连接**"，不做轮询式重连 |

> 附带的环境事实：`/proc/<pid>/fd` 与 `/proc/<pid>/net/unix` 对**应用自身**的 Python 桥可读（`shell` 域读不了）；
> QMP 被空闲连接占住时，可从 Python 桥 `ctypes.CDLL(None).shutdown(fd, 2)` 打断它再夺回。

### 1.4 修法（`lib/qga.js` 整份重写，523 行）

- `LineStream`：**一条连接只挂一次 `data` 监听器**，行进了队列就不会丢；只允许一个等待者
  （QGA 应答不带宽窄标识，顺序就是语义）；超长行与队列溢出都**计数**而不静默。
- `parseLine()` 剥 `\xff`/NUL 再解析；`isSentinelNoise()` **只有** `class=GenericError` 且 desc 含
  `JSON parse error` 才算杂音，**其余 error 一律抛**（命令真的失败不能吞）。
- `sync()`：在超时内**跳杂音直到看见自己的 id**；**收到过字节就保留连接**，只有"零字节"才 `#drop()` 重连。
- `call()`：同口径跳杂音；`exec()` 每次命令留一行读数（`pid/rc/轮询次数/ms`）。
- `vm.js` 把 `log()` 交给 `QgaSession`（失败原文进 `node-output.log`），等待循环的 `catch {}` 换成
  `lastSync` 记录，心跳行与超时报文都带上"上次失败原因"，`diagnostics()` 加 `qga: session.stats()`。

### 1.5 修好之后的真机读数

```
[12:46:32.326] 丢弃 QGA 连接（sync 4000 ms 内一个字节都没收到（发出 62 B））
[12:46:36.733] 丢弃 QGA 连接（sync 4000 ms 内一个字节都没收到（发出 62 B））
[12:46:40.883] 跳过一行杂音（与本次 id 不符）：{"error": {"class": "GenericError", "desc": "JSON parse error, stray '\uFFFD'"}}
[12:46:40.900] QGA sync 成功（3762 ms，跳过 1 行杂音）
[12:46:40.901] QGA 就绪（+13003 ms）
```

这三行正是新设计的**逐条落地**：前两次"零字节 ⇒ 换连接"，第三次"跳过 1 行杂音 ⇒ sync 成功"。

---

## 2. guest 侧三处（`+dshm.19`）

### 2.1 QGA 通了之后，真机立刻给出的事实（QMP `chardev-change` + QGA 探针）

```
[mount 9p]   hostshare on /mnt/share type 9p (rw,relatime,access=client,trans=virtio)
[haps/entry] lrwxrwxrwx 1 root root 39 files -> /data/storage/el2/base/haps/entry/files   ← 指向自己
[el2 files]  lrwxrwxrwx 1 root root 39 /data/storage/el2/base/haps/entry/files -> …/files ← 指向自己
[share vm/guestpkgs] 4 个 Alpine 包都在（bash / readline / libncursesw / ncurses-terminfo-base）
[fstab]      hostshare /mnt/share 9p trans=virtio,version=9p2000.L 0 0
[workspace]  ls: ~/Download/harness: No such file or directory
[which bash] ls: /bin/bash: No such file or directory；/bin/ash -> /bin/busybox（镜像自带）
```

⇒ 四条读数分别钉住：**9p 是好的**（镜像 fstab 自己挂上了）、**符号链接是自指的**、
**apk 闭包在 guest 里是可见的**（所以 `DSHM_PROVISION_NO_APK` 只可能是 `cd` 那一跳的路径问题）、
**工作区在 guest 里不存在**。

### 2.2 ① 自指符号链接

`provision()` 原来写的是 `ln -sfn ${share} ${EL2_FILES}`，而 `share = DSHM_SANDBOX_HOME`
与 `EL2_FILES = /data/storage/el2/base/haps/entry/files` 是**同一个字符串**。
原意（`docs/120` 里写对了）是「`ln -sfn /mnt/share <el2 files>`」—— 链接目标必须是**挂载点**。

修：`ln -sfn /mnt/share ${EL2_FILES}`；并把"镜像自带的那份 9p 到底在不在"变成**先查再补挂**
（`grep -q " /mnt/share " /proc/mounts`），不把"镜像的约定"当"我一定有"。
失败分支也补上现场（打 `grep -i 9p /proc/mounts` 与 `ls -l /mnt`）——上一轮那句
`DSHM_PROVISION_NO_APK` 之所以查不动，就是因为它是**唯一**的证据。

### 2.3 ② 工作区在应用沙箱之外

真机上"宿主磁盘授权"的粒度是**按目录**给的（同进程 Python 桥实测）：

| 路径 | `stat` | `opendir`/`listdir` | 读文件 |
|---|---|---|---|
| `~` | OK（`771`） | **EPERM** | — |
| `~/Download` | OK（`771`） | **EPERM** | — |
| `~/Download/harness`（工作区） | OK | **OK**（7 个条目） | OK |

⇒ 往上一级都**挂不上**（9p 服务端要为共享根 `open` 目录），只能挂"被授权的那一层"。
`extraShareRoot(cwd, sandbox, canOpen)` 就是这条判据的实现：沙箱内 ⇒ `null`（fsdev0 已覆盖）；
沙箱外 ⇒ **从 cwd 逐级往上 `opendir`，能打开的最后一层**就是根（真机上即工作区本身）；
打不开 ⇒ `null`（不硬挂，否则 QEMU 启动就失败）。

两个刻意的取舍（都写进代码注释）：

- **挂载点 = 宿主路径本身**。这样 guest 里的 `pwd`、相对路径、报错里的路径与宿主侧逐字一致
  （整条链路的核心不变量）；代价是**挂载点以上**在 guest 里是空目录。
- **在启动那一刻定死**。一进程一 VM ⇒ fsdev 的 `path` 不能热插。所以脚本里的 `cd` 失败报文
  明确写了"要在这个工作区用 bash 请重启应用"（`handle.js`），不让调用方去猜。

### 2.4 ③ 一进程一 VM 的串行闸门

`startGate(record)`：`record.spawned === true` ⇒ 拒绝，报文
「本进程已经启动过一台 guest VM（一进程一 VM 是硬约束）⇒ 不再启动第二台；要换 VM 请重启应用」。
`state.spawned = true` 放在 **`startWorker()` 之前**（门禁里有一条断言钉住这个顺序：
闸门必须先于 spawn 关死，否则等于没闸门）。
判据**故意**不放在"启动流程走过"上 —— `assetsPresent()`/环境变量这类 **spawn 之前**的失败不该吃掉这一次机会。

### 2.5 改法汇总

| 文件 | 改动 |
|---|---|
| `lib/qga.js` | 整份重写（`+dshm.18`，见 §1.4） |
| `lib/vm.js` | `EXTRA_TAG` / `startGate` / `extraShareRoot` / `defaultCanOpen` / `shq`；`bootArgv(extraShare)` 条件式加第二份 9p；`provision()` 按 §2.2+§2.3 重写；`ensureRunning({cwd})` 接闸门与工作区共享；`diagnostics()` 加 `spawned`/`extraShare`；头注补三件事 |
| `lib/index.js` | spawn 改派时把 `spec.cwd` 交给 `ensureRunning({cwd})` |
| `lib/handle.js` | `cd` 失败报文补一句可行动提示（重启应用） |
| `hostcore/core-recipe.json` | `coreVersion` → `+dshm.19` |
| `tools/check-vm-bash.mjs` | 95 → **116** 条（新增两节：串行闸门、沙箱外工作区；含 5 条对照臂） |

---

## 3. 端到端验收（真机读数，2026-10-08 20:45–20:49 CST）

**装机链路**（`.\tools\update-device.ps1 -SkipRebuild`）：`hdc install -r` 成功；
`home` 指纹 **8/3440 → 8/3440**（用户数据未被触碰）；端侧核心树 `0.2.1-alpha.1+dshm.19` 在位；
`exec 探测` 手持档判据通过（`toybox=ok`；`bash/ash/rg/python3.12=denied` 属预期，`docs/104`）。

**代码指纹**（`tools\device-code-fingerprint.ps1`）：**一致（9/9）/ RC=0** —— 设备在跑的核心树
就是本机这一份（含本轮改过的 `vm.js`）。

**触发**：往手机那次会话注入一条探针提示（`POST /api/session/prompt`），让端侧模型**只调一次** `bash`。
（点火口只有"模型真的用一次工具"；本轮注入了 3 条探针，用户可在会话里删掉。）

**日志读数**（`node-output.log`，原文）：

```
[12:46:27.898] 启动 guest VM（第 1 次尝试；share=/data/storage/el2/base/haps/entry/files；工作区共享=~/Download/harness）
[12:46:28.240] qemu_system_entry 已进入（argc=67）——此后由 QEMU 接管（串口/QGA）
[12:46:40.900] QGA sync 成功（3762 ms，跳过 1 行杂音）
[12:46:40.901] QGA 就绪（+13003 ms）
[12:47:16.494] guest 命令结束：pid=640 rc=0 轮询 669 次、35590 ms
[12:47:16.494] guest 侧已就绪：/bin/bash 可用
[12:47:17.150] guest 命令结束：pid=665 rc=0 轮询 25 次、653 ms      ← 模型那条命令
[12:48:27.462] guest 命令结束：pid=673 rc=0 轮询 16 次、424 ms      ← 第三条命令：复用同一台 VM
```

**命令侧的真证据**（第三条探针把读数写进共享目录，宿主侧取回，原文）：

```
VM_BASH_VERIFY
Linux hish 6.12.60 #44 SMP Sat Mar 21 09:57:01 CST 2026 aarch64 Linux
~/Download/harness
uid=0(root) gid=0(root)
GNU bash, version 5.2.37(1)-release (aarch64-alpine-linux-musl)
workspace_files=7
```

逐条判据：

| 判据 | 读数 | 结论 |
|---|---|---|
| guest 里有真 bash | `GNU bash, version 5.2.37(1)-release` | ✅ 离线 apk 闭包装成了 |
| **cwd = 宿主工作区** | `pwd` → `~/Download/harness` | ✅ 宿主路径在 guest 里逐字成立 |
| **工作区在 guest 里可见** | `workspace_files=7`（= 宿主上该目录的真实条目数） | ✅ 第二份 9p 生效 |
| 工作区**可写** | 第二条探针的 `echo probe > dshm-vm-probe.txt && cat … && rm -f …` 整链 `rc=0`（`&&` 链） | ✅ 写/读/删都在工作区里发生 |
| 一进程一 VM（复用） | 三条命令 653 ms / 424 ms，且日志只有**一次** `启动 guest VM` | ✅ 没有第二台 |

> 共享目录里的探针文件（`vm/tmp/dshm-verify.txt`，`-rw-------`）已删除；`vm/tmp/` 的其余遗留见 §7。

---

## 4. 门禁

`tools/check-vm-bash.mjs` **116/116**（新增两节 + 对照臂）：

- 「一进程一 VM 的串行闸门」：`spawned:false ⇒ allow` / `spawned:true ⇒ 拒绝` /
  报文可行动 / **源码级**钉住 `startGate(state)` 真在用、且 `state.spawned = true` 在
  `startWorker()` **之前**、`pending` 单飞仍在；
- 「沙箱之外的工作区」：沙箱内 ⇒ `null`、空 cwd ⇒ `null`、`cwd=/` ⇒ `null`、
  授权只到工作区 ⇒ 挂工作区本身、**对照臂**（父目录可打开 ⇒ 走到最上层可打开的那一级）、
  `cwd` 打不开 ⇒ `null`；`argv` 侧（`mount_tag=hostshare2` + `path=` 是工作区本身 / 无工作区时**一个参数都不加**）；
  provision 脚本侧（链接指向 `/mnt/share`、**对照臂**"不再把宿主路径当链接目标"、第二份共享按 tag 挂、失败时打 mount 表、镜像那份 9p 先查在位）。

仓库内其余 15 条门禁全绿（本轮实跑）：`assert-cli-shim` 40/40、`assert-resfile-sync` 14 件、
`check-parity`、`assert-exec-fix` 38/38、`assert-python-bridge` 69/69、`check-doc-refs`、
`check-dead-code`、`check-decor-button-mode`、`check-market-bridge` 44/0、
`check-profile-pnpm-bridge` 42/0、`check-denial-hints` 45/0、`check-vm-bash` 116/116、
`check-resfile-core-zip` ✅（1 份容器 = 配方 = 产出）、`check-core-openharmony-patches` 172/0、
`assert-core-entrypoints` PASS。

---

## 5. 产物（本机）

| 项 | 值 |
|---|---|
| `coreVersion` | `0.2.1-alpha.1+dshm.19` |
| 核心容器 | `dist/core/dsh-core-0.2.1-alpha.1+dshm.19-openharmony-arm64.zip` **59,245,050 B** / 16,500 条目 / sha256 `041712cb83fc8734c9a562176f6cd81b5c4647274f667adc18d959fe6db4673d` |
| HAP | `entry/build/default/outputs/default/entry-default-signed.hap`（`BUILD SUCCESSFUL in 17 s 842 ms`） |
| 装机 | `62T0225B18039433` 覆盖安装（`-r`），`home` 指纹不变、核心树 `.19` 在位 |

---

## 6. 本轮**未做** / 已知限制

| # | 项 | 现状 |
|---|---|---|
| 1 | **侧边栏真终端** | 仍不可用，且**不在本轮**：`spawnTerminal` 是交互式 PTY，而 QGA 的 `guest-exec` **不支持流式 stdin**（连不上"边敲边收"）。要做真终端得在 guest 里另起 pty + 一条能到宿主的字节流通道 —— 本轮把 **bash 通道**打通，是它的前置 |
| 2 | 换工作区要重启应用 | 第二份 9p 的 `path` 只能在启动时定（一进程一 VM）；报文已说清楚，见 §2.3 |
| 3 | `DSHM_VM_BASH=warm` 预热时没有 cwd | 只挂沙箱那份共享；这是调试开关，不承诺"沙箱外工作区" |
| 4 | PC/2in1 档 | **零变化**：分档判据（`spawnProbeOk()`）与接管面一个字未动；本轮所有改动都在"接管之后"的分支里 |
| 5 | GPLv2 §3 落实 / 常驻内存（`-m`、`tb-size`）/ `python3`·`git` 进 guest / `vmDiagnostics()` 进 `host-ready.json` | 同 `docs/120` §5，未动 |

---

## 7. 文件清单（本轮）

| 文件 | 改动 |
|---|---|
| `hostcore/plugins/dshm-vm-bash/lib/{qga,vm,index,handle}.js` | 见 §2.5（`qga.js` 属 `+dshm.18`） |
| `hostcore/core-recipe.json` | `coreVersion` → `+dshm.19` |
| `tools/check-vm-bash.mjs` | 95 → 116 条 |
| `docs/122-*.md` / `docs/README.md` | 本档 + 索引 |
| `docs/120-*.md` / `docs/121-*.md` | §6 的"待真机/未定论"按本档读数结案 |
| `AGENTS.md` | 文档编号到 `122`；`coreVersion` 当前值与 `.18`/`.19` 说明 |

真机侧本轮留下的临时件：`vm/tmp/ram.dump`（512 MB，上一轮遗留）、若干 `run-*.sh`（每次命令一份，
**刻意留作复盘**）、`dshm-verify.txt`（已删）。仓库侧 `dist/localtest/` 的探针脚本与日志见清理记录。

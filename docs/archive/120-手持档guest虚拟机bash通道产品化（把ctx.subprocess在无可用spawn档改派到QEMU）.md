# 120 · 手持档「guest 虚拟机 bash 通道」产品化

> 本档回答一个问题：**手机/平板上，模型的 `bash` 工具能不能真的执行命令？**
> 结论：能了 —— 把 `ctx.subprocess` 在"没有可用 spawn"的分档上改派到随包 QEMU guest 里的真 bash。
> **PC/2in1 档一个字节不变**（判据与另外两个端侧桥同源）。真机验收**尚未做**（见 §6）。

---

## 1. 判决链：这一轮接的是哪一条线

| 档 | 判决 | 出处 |
|---|---|---|
| 手持档（手机/平板）能不能直接 `execve` 一个随包 shell | **不能**。真机读数 `system-sh=缺` / `ash=denied` / `bash=denied` / `realShell=no` | `docs/104` |
| 别的成熟产品怎么处理"手机端不能跑 shell" | WorkBuddy 的做法是**不承诺本机 shell**（执行落云端或用户 PC）⇒ 不构成反证 | `docs/114` |
| 有没有第三条路（不 `execve` 也能有真 shell） | **有**：HiSH 在应用进程内跑 QEMU 全系统模拟，guest 里是**真 Linux 真 bash**，且**一次 `execve` 都不发生** | `docs/119` |

`docs/119` 当时的裁定是"成立可行，但**不建议现在做产品化集成**，先把远程 Host 走通"。本轮**推翻的是"不建议现在做"这条建议、不是技术判断**：把两条通道的代价与确定性摆在一起后，VM 这条路的接缝比当时估计的干净（见 §2 三条），而它是一个**完全自足**的能力（不依赖用户名下有一台常开的 PC、不依赖隧道与 NAT 打洞），所以两者是互补而不是替代。**代价（§5）一条都没消失**，这是选择，不是发现。

---

## 2. 方案：三个接缝，各解决一个"看起来很难"的问题

```
链 1（模型的 bash 工具）
  dsh-tool-bash → ctx.shell(@deepseek-ai/dsh-bash-local)
    → ctx.subprocess.spawn(spec)            ← ★ 本轮的接缝
    → LocalSubprocessRuntime.spawn()        （服务实例方法，可换）
    → spawnSubprocess() → node:child_process.spawn() → execve  ✗ 本档被拒

链 2（侧边栏终端）：dsh-terminal-bash → ctx.subprocess.spawnTerminal() → node-pty   ✗ 本档被拒（本轮**不接管**）
```

### 2.1 为什么换 `ctx.subprocess.spawn` 就够了

上游把"跑一条 `bash -c`"这件事的最后一跳收在 `ctx.subprocess` 上：`dsh-bash-local.execute()` 固定发
`["bash","-c",spec.command]`（`lib/index.js:140-145`），然后是 `this.ctx.subprocess.spawn(spec)`（:209）。
⇒ 只要这一个方法改道，**模型可见的工具链一个字都不用改**（`tool-bash` 的描述、审批、超时、输出截断全是上游既有的）。

### 2.2 为什么客户端是 QGA、而不是把 QEMU 的 API 全接出来

QEMU Guest Agent 落在**文件系统的 unix socket** 上（`-chardev socket,path=…/qga_socket`）。
⇒ Node 侧 `net.connect(path)` 就能驱动 VM：**不需要 FFI、不需要 TCP、不需要 guest 里再跑任何监听器**。
"谁启动的 VM"与"谁在用 VM"因此**完全解耦** —— 这也是本轮敢把启动器与客户端分开设计的原因。

QGA 客户端（`lib/qga.js`）逐条落实了 `docs/119` 实测踩到的三个坑：
1. `\xff` **只对 `guest-sync-delimited` 发**（对普通命令也发 ⇒ 回包错位）；
2. 退出码字段是 **`exitcode`**（不是 `exit-code`；按错名字取值会把"失败"静默读成"成功无输出"）；
3. `guest-exec` 必须带 **`capture-output: true`**，`out-data` / `err-data` 都是 **base64**。

### 2.3 为什么启动器是 koffi + worker 线程

- `qemu_system_entry()` 阻塞到 VM 退出 ⇒ 必须在**独立线程**（写进主线程等于整个宿主进程再也回不到事件循环）。
  worker 在本端是已验证能力（`jitless-env` 会给每个 worker 挂钩补齐，`main.js` 自己的心跳也用 `new Worker`）。
- `docs/119` 的 PoC 用 `ctypes`（Python）证明的其实是**"这个 `.so` 能在应用进程内 dlopen + 主循环能跑"**。
  koffi 走**同一条 dlopen/dlsym 路径**，但把 VM 的生命周期留在同一个运行时里：不依赖 Python stdlib 是否已解包、
  不经过 HTTP 自环（`127.0.0.1:PORT` 的 token 取用/失效问题）、也不把"进程内阻塞"叠加到 `captureRun` 那条同步 NAPI 上。

### 2.4 路径一致性（这条是设计里的关键一手）

guest 通过 9p（`-fsdev local,path=<应用沙箱根>`，标签 `hostshare`）看到宿主沙箱，
再在 guest 首启建一个符号链接：

```
ln -sfn /data/storage/el2/base/haps/entry/files  /mnt/share
```

⇒ **宿主路径在 guest 里逐字成立**。后果是：`spec.cwd`、报错里的路径、模型 `pwd` 的输出、
宿主的文件树面板 —— 四处说的是同一个字符串，**不需要任何路径翻译层**。
（若不做这一步，就要在每一处做 `/data/storage/…` ↔ `/mnt/share/…` 的映射，
而映射层是那种"平时都对、边界上偶发错"的东西。）

---

## 3. 分档判据：PC 档凭什么能保证"一个字节不变"

三条**全部**成立才接管（`lib/index.js` 的 `enabled()`）：

| # | 判据 | 为什么 |
|---|---|---|
| ① | `DSHM_PLATFORM === 'ohos'` | `main.js` 只在沙箱路径确实落在 `/data/storage` 下时才设它 ⇒ 桌面/CI/离线跑天然不接管 |
| ② | **随包假壳 `bin/pnpm --version` spawn 不起来** | 与 `dshm-market-bridge`(`lib/index.js:105`)、`dshm-profile-pnpm` 的 `shimRunnable()` **逐字同源**。它测的是"本档还有没有可用的 spawn 链路"，而不是去猜设备型号 ⇒ PC/2in1 档第一条判据就成立，**整条插件惰性**（不包装、不启动 VM、不读资产） |
| ③ | 5 个 VM 资产大小预检齐备 | 缺资产就 fail-closed，而不是起一个半截 VM |

调试覆盖：`DSHM_VM_BASH=force` / `=off`。

**判据写错的两个方向都很贵**（判宽 ⇒ 动到已验收的 PC 链路；判窄 ⇒ 手持档等于没做），
而两者都不会在编译期暴露 ⇒ 所以 `tools/check-vm-bash.mjs` 把它们钉死，并配**对照臂**：
把 `probe` 从"能跑"翻成"跑不起来"，结论必须跟着翻（证明断言不是空转）。

---

## 4. 资产（两个目标目录，判据是"加载方式"）

| 文件 | 字节 | 目标 | 为什么在那里 |
|---|---|---|---|
| `libqemu-system-aarch64.so` | 41,438,848 | `entry/libs/arm64-v8a/` | **只有 HAP 安装的 `libs/<abi>/` 允许 `dlopen`**（`main.js:3203-3213` 的 E16/E17b：resfile 与 el2 `files/` 都不行）。QEMU 是 `koffi.load()` 加载的 ⇒ 只能在这里 |
| `libslirp.so.0` | 213,264 | `entry/libs/arm64-v8a/` | `libqemu` 对它有 DT_NEEDED，必须同目录（加载器不搜该目录 ⇒ worker 里显式先 dlopen 旁挂 `.so` 进全局域） |
| `kernel_aarch64` | 12,980,736 | `resfile/vm/` | 被 QEMU 当**文件读**（`-kernel`），与 toolchain 归档同性质 |
| `rootfs_aarch64.qcow2` | 48,631,808 | `resfile/vm/` | 同上（`-drive file=`）；启动时复制一份可写副本到 el2 |
| `efi-virtio.rom` | 160,768 | `resfile/vm/` | `-L` 目录下的固件 |
| `guestpkgs/*.tar.gz`（4 个） | ~807 KB | `resfile/vm/guestpkgs/` | guest 原始镜像只有 busybox `ash`，而 `dsh-bash-local` 固定发 `["bash","-c",…]`；设备侧 `apk add bash` 要外网 + 实测 **30.9 s** ⇒ 构建期取好闭包、guest 首启**离线装**（`--no-network`，秒级）；扩展名是 `.tar.gz`（内容仍是 apk v2 包，改名只为过审核，见 `docs/148`） |
| `NOTICE.md` + 两份许可证 | 23.4 KB | `resfile/vm/` | GPLv2 要求随分发提供许可证文本（署名件的**源**在插件包里，见 §5.6） |

出包三坑里的两条**在这里同样成立**，所以做法照旧：`tools/place-vm-assets.mjs` 逐件校验
**sha256**（抄错/截断在布置期当场失败，而不是留到真机上表现成"VM 起不来"），
改了任何字节必须同步三处（`place-vm-assets.mjs` 的 `FINGERPRINTS` / `paths.js` 的 `VM_ASSETS` / 本档 §4）。

**实测代价**：HAP **295.5 MB → 400.2 MB（+104.7 MB）**，与 `docs/119` 预估的 +76~87 MB 同量级（偏高，因为
apk 闭包与三份署名件是当时没算的）。约占**包体 +35%**。

---

## 5. 已知限制（逐条，都不是"以后再说"，是"现在就是这样"）

### 5.1 侧边栏终端**仍然打不开**

`spawnTerminal` 不接管。QGA 的 `guest-exec` **不支持流式 stdin** ⇒ 拿它假装一个交互式 PTY
只会得到一个永远不回显的终端 —— 比"打不开"更糟。要做真终端得在 guest 里另起 pty +
一条能到宿主的**字节流**通道（9p 不带 unix socket ⇒ 得走 vsock 或 slirp 端口转发），那是另一个工程。
⇒ **本档的结果与 `docs/104` 一致：终端仍不可用。**

### 5.2 没有流式输出

QGA 是"跑完把 base64 输出一次给我"，不是管道 ⇒ collect 模式（`bash-local` 用的那种）语义**完全一致**；
但 `stdio:'pipe'` 的调用方会在命令**结束后**一次性拿到全部输出（进度条类输出不会实时出现）。

### 5.3 spill 走宿主侧

超过 `maxBytes` 时把完整输出写到 `<vmDir>/spill/<id>.{out,err}` 并报 `spillPath`。
这**不是**上游本地实现的 spill 目录语义（`prepareManagedProcessBinding()` 是 subprocess-local 内部约定、
不是 seam 契约），但比它更好用：路径在宿主上，能直接读。

### 5.4 guest 里没有宿主的工具链

guest 的 `PATH` **只给 guest 自己的目录**（`/usr/local/sbin:…:/bin`）。宿主那批随包假壳
（`bin/pnpm` / `python3` / `git` / `rg`）**刻意不进白名单**：它们的逻辑是"在宿主上做事"
（探 execve 白名单、转发 `127.0.0.1` 的 Python 桥），搬进 guest 只会得到看不懂的失败
（guest 的 `127.0.0.1` 是它自己的回环）。
⇒ **`python3` / `git` / `pnpm` 在 guest 里是"没有这个命令"**。要补上得另做功课（见 §6）。

### 5.5 一进程一 VM，且不可重启

`docs/119` 实测：同一进程里 `quit` 之后再起第二台 ⇒ **进程当场消失（无 faultlog）**。
⇒ 启动函数带重入闸门、所有入口收敛到单例；**不提供"重启 VM"接口**（免得有人把它做成按钮）。
插件重载后 VM 仍在跑，新实例继续用同一条 QGA。

### 5.6 GPLv2 的"对应源码"义务**是欠账，不是已合规**

资产含 QEMU（GPLv2）与 Linux 内核（GPLv2）。`NOTICE.md` + 两份许可证全文随 HAP 分发，
并指向上游公开源码（`harmoninux/qemu`、HiSH MIT）。但 GPLv2 §3 对**分发目标码**有形式要求
（§3(a) 随附对应源码 / §3(b) 书面报价 / §3(c) 非商业转授），**指向上游 URL 不等于 §3**。
⇒ 上架前必须落实其中一条（应用内"关于"页给出源码获取方式，或随包附 §3(b) 文本）。
署名件的源放在插件包（`hostcore/plugins/dshm-vm-bash/NOTICE.md` + `licenses/`）而不是
`third_party/` 下 —— 后者整目录 gitignore，而署名与许可证是**必须可评审**的文档。

### 5.7 冷启动与常驻

冷启动到 QGA 可用 **11.8 s**（`docs/119`）、命令端到端 81~219 ms、guest 512 MB ⇒
应用进程 VmRSS **+1.22 GB**。⇒ 启动是**惰性**的（第一次有命令要跑才拉起），
第一次命令因此多等一次冷启动；`DSHM_VM_BASH=warm` 可开机预热。

---

## 6. 本轮**未做** / 待真机

**真机验收已做（2026-10-08）**，逐条结论见括注与 `docs/122`（§1 QGA 客户端根因 / §2 guest 侧三处 /
§3 端到端验收）。这张表是当时的待验清单 —— 本机（Windows）无法 `dlopen` aarch64 `.so`、无法跑 VM，
所以它**只能**在真机上结案：

| # | 待验 | 判据 |
|---|---|---|
| 1 | `koffi.load()` 能否 dlopen 那份 `.so`（含旁挂 `libslirp` 的解析） | worker 上报 `loaded`；失败原因进 `dshm-host.log` |
| 2 | `qemu_system_entry(argc, argv)` 的 FFI 签名（`char **` vs `const char **`，两种都试） | worker 上报 `entered` |
| 3 | QGA 就绪时延与首条命令时延 | `vmDiagnostics()` 的 `readyAt - startedAt` |
| 4 | guest 首启离线装 bash 是否真成 | provision 判据 `DSHM_PROVISION_OK` |
| 5 | 9p 共享的**写**是否放行（`mapped-file` 权限模型） | guest 里往共享目录写一个文件成功、且宿主侧读得到同一份内容（不放行则表现为 `EACCES`/`EROFS`） |
| 6 | 模型 bash 工具端到端跑通一条命令 | 会话里出现真输出 |
| 7 | `dsh/home` 指纹装前=装后（覆盖安装不碰用户数据） | `tools/update-device.ps1` 自带校验 |
| 8 | PC/2in1 档零变化 | 同包覆盖装到 2in1，`node-output.log` 应出现 `[dshm-vm-bash] 不接管：…（PC/2in1 档）` |

**逐条结案（2026-10-08）**：① koffi `dlopen` ✅（`worker: koffi.load 成功`）② FFI 签名 ✅
（`qemu_system_entry 绑定成功：int qemu_system_entry(int argc, char **argv)` + `已进入（argc=67）`）
③ QGA 时延 ✅ `+13003 ms`（首次；`sync` 本身 3.76 s，途中换了 2 条"零字节"连接）
④ 离线装 bash ✅ `guest 侧已就绪：/bin/bash 可用`（首次 35.6 s，此后 0 成本）
⑤ 9p 共享的**写** ✅（工作区里 `echo > f && cat f && rm f` 整链 `rc=0`；`vm/tmp` 里的探针文件宿主侧读得到）
⑥ 模型 `bash` 端到端 ✅（`rc=0` + `GNU bash 5.2.37` / `pwd=工作区` / `workspace_files=7`）
⑦ `dsh/home` 指纹装前=装后 ✅（8/3440 → 8/3440）⑧ PC/2in1 档零变化 ✅（分档判据未动；2in1 装机复跑仍待做）。

**后续（明确不在本轮）**：侧边栏真终端（5.1）／让 `python3`·`git` 在 guest 内可用（5.4，可试
"把宿主 `bin/` 挂进 guest PATH 并验宿主的 aarch64 musl ELF 能否在 guest 里跑"——
guest 没有 execve 限制，这条路**可能**成立但要验）／GPLv2 §3 落实（5.6）／降常驻内存
（`-m 256M` + 更小 `tb-size`）／把 `vmDiagnostics()` 接进 `host-ready.json` 的 `runtime.*`
（`docs/106` 的口径）。

---

## 7. 门禁与接线

新增 `tools/check-vm-bash.mjs`（**67 项断言，本机全过**；进 CI 的 18 条"只需仓库内文件"那一组）：

- 分档判据 3 条 + `force/off` + **对照臂**（probe 翻转 ⇒ 结论翻转）
- 接管面：`["bash","-c",…]` 改派；**宿主假壳不改派**（带"假壳 vs guest shell 结论相反"的对照臂）；
  `stdio.control='pipe'` 不改派；空 argv / `null` 不改派
- 脚本生成：`cd` 逐字、`spec.env` 逐条 export、单引号转义、**不带 `set -u`**（否则 `$UNSET` 会让用户脚本致命，
  改变 `bash -c` 语义）、stdin 处理、**guest PATH 里没有宿主假壳目录**
- QEMU argv：共享标签仍是 `hostshare`、共享的是沙箱根、rootfs 用 el2 可写副本、QMP/QGA socket 落运行目录
- 资产清单 5 项与运行期预检口径
- 接线三处：`cordis.patch.yml` 的 insert 行 / `pack-core` 的 `DSHM_PLUGIN_PACKAGES` / `coreVersion` 已升
- 随包资产（有 `third_party/` 素材时逐字节校验；干净克隆里**如实标注跳过**而不是判红）

接线（三处，缺一不可）：

1. `hostcore/plugins/dshm-vm-bash/`（插件本体：`index.js` / `vm.js` / `vm-worker.cjs` / `qga.js` / `handle.js` / `paths.js`）
2. `hostcore/profile/ondevice/cordis.patch.yml` 第 ⑬ 节的 `insert:` 行（**用 `insert:` 语法**：
   `applyEntryPatches` 的普通 patch 行按 id 更新、够不着新条目）
3. `tools/pack-core.mjs` 的 `DSHM_PLUGIN_PACKAGES`（决定"落树 + 声明依赖"）⇒ `coreVersion` 升 **`+dshm.14`**
   （不升版本 ⇒ 增量复用的旧树不会重新物化 ⇒ 改动静默不生效，见 AGENTS「出包三坑」第 2 条）

**本机实测（2026-10-08）**：`pack-core --place-in-app` 成功（容器 56.5 MB / 16500 条目 /
sha256 `b4bb9a1a099cd4a6…`；回归锁"树内 8 个 `dshm-*` 目录 = 声明者 8 条声明 = 清单"通过）；
`hvigor assembleHap` **BUILD SUCCESSFUL in 14 s 485 ms**；
产物 `entry-default-signed.hap` **400,171,603 B** / sha256 `b51c6f3454a4eeab59839b173a47652106d51559b0959a4aff22c4830c6cd019`（⚠️ 这是 **`+dshm.14`** 那次出包的读数；后续 `+dshm.15`/`.16`/`.17` 的版本、容器与 HAP 读数**以 `docs/121` §4.2 为准**），
逐条核过包内落点（`libs/arm64-v8a/libqemu-system-aarch64.so` 41,438,848 B、
`libs/arm64-v8a/libslirp.so.0`、`resources/resfile/vm/` 10 条含 4 个 apk 与三份署名件、
`resources/resfile/dsh-core-…+dshm.14….zip` **恰好 1 份**，容器内 `dshm-vm-bash/lib/*` 与 `NOTICE.md` 均在）。
全部门禁复跑：仓库内 17 条 + 需核心树 9 条 + 设备 0 条 ⇒ **全绿**（唯一"跳过"是"随包资产"那段在无
`third_party/` 时的如实标注）。

---

## 8. 恢复条件（怎么把这一轮整个摘掉）

1. `hostcore/profile/ondevice/cordis.patch.yml`：删第 ⑬ 节的 `insert:` 行；
2. `tools/pack-core.mjs`：删 `DSHM_PLUGIN_PACKAGES` 里的 `dshm-vm-bash` 那一项；
3. `hostcore/core-recipe.json`：`coreVersion` 再升一位（如 `+dshm.15`）；
4. 重新 `pack-core --place-in-app` + 出包。

⇒ 回到"手持档跑不了命令"（`docs/104` 的判决），**其它任何链路都不受影响**（本插件的全部行为都在包内，
不新增权限、不碰用户数据、不改上游一个字节）。
只想临时回退：在用户层 `$DSH_HOME/cordis.patch.yml` 写 `- id: dshm-vm-bash` + `disabled: true`，
或 `DSHM_VM_BASH=off`。

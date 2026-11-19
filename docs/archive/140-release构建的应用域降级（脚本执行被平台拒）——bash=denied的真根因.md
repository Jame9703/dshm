# 140 · release 构建的应用域降级与「脚本执行被平台拒」——`bash=denied` 的真根因

日期：2026-10-10（晚）
设备：PC/2in1 `86E0226429000417`（HUAWEI MateBook 14，`const.product.devicetype=2in1`，`const.ohos.apiversion=26`）
核心：`0.2.1-alpha.2+dshm.31`（两轮跑的是**同一份**核心树；包内 `resources/resfile/**` 逐条目逐字节相同）

> 用户指令：「按 1」= 先在本机跑一次 `buildMode=release` 编译，把 `dist/sideload/README.md`
> 「备注：release 构建的差异」里那句**原因未查明**钉死；随后「编译出来 APP 我上传测试看看」。
> **本档只取证 + 裁定影响面，未改一行代码**（修法候选见 §5，待拍板）。

## 1 复现（本机命令）

沙箱里跑 hvigor 会因写不了 `~/.hvigor` 报**假 ENOENT**（`docs/127`），必须带这套 env：

```powershell
$clt='C:\Program Files\Huawei\DevEco Studio\tools'
$env:JAVA_HOME='C:\Program Files\Huawei\DevEco Studio\jbr'
$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'
$env:DEVECO_CLI_CLT_PATH=$clt
$env:PATH="$env:JAVA_HOME\bin;$clt\node;$env:PATH"
& "$clt\node\node.exe" "$clt\hvigor\bin\hvigorw.js" assembleHap --mode module -p product=default -p buildMode=release --no-daemon
```

⇒ `BUILD SUCCESSFUL in 30 s 134 ms`；产物 `entry/build/default/outputs/default/entry-default-signed.hap` = **398,452,877 B**
（同代码的 debug 件 r14 = 401,775,967 B）。

装机（唯一入口，只 `install -r`，不碰 el2）：

```powershell
.\tools\update-device.ps1 -Hap entry\build\default\outputs\default\entry-default-signed.hap -SkipRebuild
```

⇒ `覆盖安装成功`；`home 指纹：links=14 size=3440 → links=14 size=3440`（用户数据未动）。

## 2 逐行读数对照（原文，同一设备、同一核心）

| 项（`node-output.log`） | debug 件（2026-10-10T09:41 一轮） | release 件（2026-10-10T10:08 一轮） |
|---|---|---|
| `exec 探测` | `…rg=ok，ash=ok，bash=ok，system-sh=ok，toybox=ok，git-ls-remote=ok`（10/10） | `…rg=ok，ash=ok，bash=denied，system-sh=ok，toybox=ok，git-ls-remote=ok`（**只有 bash 翻红**） |
| 宿主域（`终端能力 toybox域`） | `u:r:develop_tools_debug_hap:s0` | `u:r:develop_tools_hap:s0` |
| `终端能力汇总` | `宿主域=u:r:develop_tools_debug_hap:s0，toybox域=rc0，toybox-stat-sh=rc0，toybox-exec-sh=rc0，toybox-exec-ash=rc0，libs-exec=err(EACCES)` | 同形，只有 `宿主域=u:r:develop_tools_hap:s0` 变（其余四条 rc0 不变） |
| `dshm-market-bridge` | `随包 bin/pnpm 假壳可执行 ⇒ 不接管（市场走已验收的假壳链路）` | `已接管市场包操作：profile=ondevice，队列=…/install-queue（原因：随包假壳无法 spawn）` |
| `dshm-vm-bash` | `不接管：本档 spawn 可用（PC/2in1 档）⇒ 完全惰性` | `已接管 ctx.subprocess.spawn` / `已接管 ctx.subprocess.spawnTerminal`（`手持档（spawn 不可用）且 VM 资产齐备`） |
| `bash 垫片` | `bash/hush 已布置（解释器 …/files/bin/ash；busybox 无 bash applet）` | **同一行**（布置照样成功） |

> `libs-exec=err(EACCES)` 两轮都红 = 既有已知项（签名域不给 exec 随包 `libs`），**与本次无关**。

## 3 根因：应用域被降级 ⇒「应用数据区里的脚本」不能 execve

平台按**包的 `debug` 标志**挑应用域：`module.json` `"debug":true`（debug 构建）⇒ `u:r:develop_tools_debug_hap:s0`；
release 构建（`"debug":false`）⇒ `u:r:develop_tools_hap:s0`。而后者**不允许 execve「应用数据区里的脚本文件」**（shebang 那一步）。

三条独立证据（都不是推演）：

1. **垫片本身没毛病**：设备侧 `stat` 到 `…/files/bin/bash` = `-rwxr-xr-x 755`、463 B、owner = app uid `20020292`；内容首行 `#!/data/storage/el2/base/haps/entry/files/bin/ash`、末行 `exec "…/ash" "$@"`。而 `probeExec()` 只在 `spawn` 拿到 **EACCES** 时记 `denied`（ENOENT 走 `fail(…)`、缺 so 走 `so-fail`）⇒ 拒绝发生在 **execve 那一刻**，不是"文件不存在/权限位不对/loader 缺库"。
2. **同目录的 ELF 全部照旧能执行**：`ash=ok`（`ash` 就是 busybox 的拷贝），`python3.12` / `git` / `git-core/git` / `git-remote-http` / `rg` / `system-sh` / `toybox` / `git ls-remote` 也全 `ok` ⇒ 同一个目录、同一个 uid、同一个进程，被拒的只是**脚本这一步**。
3. **第二条独立脚本通道同时翻红**：`ensureCliShims()` 写的 `pnpm/npm/npx/dsh` 也是文本脚本，而 `dshm-market-bridge` / `dshm-vm-bash` 的 `shimRunnable()` 判据正是「真去 spawn 一次 `<bin>/pnpm`」—— 同一份判据、同一批文件，只换构建模式就从「不接管」翻成「已接管」⇒ 变量只剩**执行者（域）**。

## 4 影响面

- **PC / 2in1 档**：release 件下 `bash` 工具通道（垫片）不可用；`python`/`python3`/`pip3`/`git`/`rg` 的 **wrapper 同为文本脚本** ⇒ 同一类拒绝；三处「分档判据」把 PC **误判成手持档** ⇒ `vm-bash` 接管**全部** `ctx.subprocess.spawn`/`spawnTerminal`（命令进 QEMU guest）、市场与「设置 → 插件」安装改走进程内队列。⇒ release 件在 PC 上会**退化成手持档形态**。
- **手持档（手机 / 平板）**：不受影响。那两档本来就 `ash=denied`（随包 ELF 也执行不了，见 `docs/104`）⇒ `shimRunnable()` 结论不变，该接管还是接管。
- **上架口径**：`docs/110` 定的兼容面与权限面不变；本条只是「release 产物」的功能降级，**不是**签名/权限问题。

## 5 修法候选（未做，待拍板）

- **A. 判据改成「真身（ELF）能不能 spawn」+ 给脚本通道补一条不依赖 shebang 的执行路径。**
  ① 三处 `shimRunnable()`（`dshm-vm-bash` / `dshm-market-bridge` / `dshm-profile-pnpm`）的探针从「spawn `<bin>/pnpm`（脚本）」扩成「脚本 + `<bin>/ash`（ELF）」两问 ⇒ release-PC 归回宿主档，不再被误判；
  ② 宿主在 spawn 拦截层把「目标是本包 bin 目录里的脚本」改写成 `spawn(<bin>/ash, [脚本, ...args])`（内核不碰 shebang ⇒ 绕开拒绝），bash / wrapper / 假壳在 release-PC 全部恢复**原生**执行（语义与今天垫片的 `exec ash "$@"` 等价）。
- **B. 只修判据**：`vm-bash` 不再误接管，但 bash / wrapper 在 release-PC 报明确的不可用（诚实降级，功能不回）。
- **C. 不动，只把口径写实**：release 件只面向手机/平板；PC/2in1 继续用 debug 侧载包（= 本档现状，但 `dist/sideload/README.md` 那句「原因未查明」已订正）。

## 6 未做 / 未验

- **未验**：手持档的 release 件与 debug 件是否同判（本机只有 PC 在线；按 §4 的机制**应当**同判，但**这是推断不是读数**）。
- **未做**：AGC / 上架用**发布签名**。本机 `~/.ohos/config` 只有 DevEco 调试证书一套（`type=debug`、`allowed-acls` 5 条、`device-ids` 4 条），`~/.ohos/config/material` 与 `Downloads` 里都没有发布证书/profile ⇒ 现在的 release 件只能 `hdc install -r` 装机，**不能上传 AGC**。
- **未做**：§5 的任何一项修法（等拍板）。

## 7 release 件 vs debug 件（包内差异）

- 条目数 128（debug）→ **127**（release，少 `ets/sourceMaps.map`）；
- 内容不同 9 条：`.pages.info` 28,888→28,680 · `ets/modules.abc` 3,141,228→1,818,804 · `libs/arm64-v8a/libdshhost.so` 133,144→70,952 · `libdshm-gitcompat.so` 5,472→5,096 · `libentryprobe.so` 5,808→5,640 · `libkoffi.so` 1,521,808→1,165,816 · `libpython_runner.so` 94,464→68,088 · `libsystem.so` 10,464→9,904 · `module.json` 4,067→4,070（**只差 `"debug":true→false` 与 `"buildMode":"debug"→"release"`**）；
- `resources/resfile/**`（核心树 zip / toolchain / busybox / vm / ohos-skills）**逐字节相同** ⇒ 本次差异与核心树无关。

## 8 本轮产物

- 侧载包（**正式件 r14**，debug 构建，仍在位）：`dist/sideload/DSHM-1.1.0-core0.2.1-alpha.2+dshm.31-arm64-signed.hap`
- release 件（**仅供 hdc 装机验证 / 留档，未分发**）：`dist/release-test/DSHM-1.1.0-core0.2.1-alpha.2+dshm.31-arm64-release-buildMode-signed.hap`（398,452,877 B）
- release 件当轮设备日志原文：`dist/release-test/node-output-release.log`

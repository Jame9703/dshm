# 125 · 手持档终端多实例与皮肤市场托管安装（`virtconsole` 换通道 · 「两行路径」根治 · `installPlugin` 的 `recovery` 形状）

> 承接 `docs/123`（侧边栏终端接入 guest 虚拟机）、`docs/124`（全系统体检）。
> 本档记用户这一轮的两件事 + 一条追加：**① 终端启动时打印两行当前路径**、
> **② 皮肤市场「一键安装」要求手动安装**、**③（追加）终端报「端口已占满」**。
> 设备：`62T0225B18039433`（VYG-AL00 / API 26 / `const.product.devicetype=phone` / 手持档）。

---

## 0. 一句话结论

| # | 事 | 结论（都有真机读数，见 §1–§3） |
|---|---|---|
| 1 | 终端打印两行当前路径 | 根因是 **prompt 比列数宽**（镜像 `/etc/profile` 给非 bash/ash 分支 `PS1='${HOSTNAME%%.*}:$PWD'` ⇒ 46 列 > 侧栏 42 列），随后的 SIGWINCH 重绘落在第二行上。**已根治**：自写 rc（ash 走 `$ENV` / bash 走 `--rcfile`）+ `PS1` 定为 `\W# `。真机首屏实测 = `harness# `（**一行**） |
| 2 | 终端「端口已占满」 | 旧通道是额外的 `-serial`，而 guest 里**只有 2 个 PL011**（0 号留给控制台）⇒ 并发终端恒为 1。**已换通道**：`-device virtconsole` ⇒ guest 侧 `/dev/hvc<i-1>` 真 tty，端口 1 → **4**。真机实测 4 个终端分别落在 `hvc0..hvc3`，第 5 个才报「先关一个」 |
| 3 | 皮肤装不上 / 要求手动安装 | 两层根因，**都修了**：① 桥只实现 `runPlugin`、没有 `installPlugin` ⇒ 市场 `lifecycle.js:774` 直接抛 `service.installPlugin is not a function`（42 条 `mode==='managed'` 皮肤一条都装不上）；② 补上后又发现**包名不在顶层** —— 市场 `desktopRunner`（`commands.js:454`）把它放在 **`request.recovery.packageName`**。真机实测 `phase=done`、`installed; choose Use to activate`，profile 里 `dsh-theme-macintosh: 0.1.2` |
| 4 | 终端启动慢 | **本轮未改**。读数：冷启动（VM 首次拉起）`terminal/create` **12.4 s**、之后 **361/486/566 ms**。快的路只有一条 —— 插件里**已有**的预热开关 `DSHM_VM_BASH=warm`（`index.js:288`），要不要默认打开属于产品取舍，**留给用户拍板**（见 §4） |

**一句话判据**：终端那条 tty 只要**不是真 tty**（`virtio-console` 的普通 port = `251,1` 动态 cdev），
作业控制 / 行规程 / 尺寸就都没有 ⇒ 换通道时**必须**用 `virtconsole`（console 型端口），
而不是随便挂一个 `virtserialport`。

---

## 1. 终端：换通道（`-serial` → `virtconsole`）与 prompt 根治

### 1.1 「端口已占满」的根因（真机日志原文）

```
端侧终端端口已用满（本档最多 1 个并发终端），请先关闭一个终端再开新的
```

`paths.js` 的 `TERM_PORTS = 1` 不是保守，而是**被硬件钉死的**：镜像里 `ttyAMA0` 是控制台、
`ttyAMA1` 是唯一可用的终端 tty，第 3/4 条 `-serial` **不产生 tty**（`docs/123` 真机读数：
`ls /dev/ttyAMA*` 只有 0/1）。所以第二条终端只能报错 —— 这是**正确的 fail-loud**，但用户
要的是「能同时开好几个」。

### 1.2 换通道：`-device virtconsole`

三条候选**都上过真机**，最后选的不是最早那条：

| 通道 | guest 侧 | 是什么 | 结论 |
|---|---|---|---|
| `-device virtserialport` | `/dev/vportXpY`（`251,1`） | **动态 cdev**，不是 tty | 没有 termios / 行规程 / 作业控制 ⇒ 哑终端，弃 |
| `-serial` | `/dev/ttyAMA<i>`（`204,64`） | PL011，真 tty | 质量最好，但只有 2 个 ⇒ 并发恒 1，弃 |
| `-device virtconsole` | `/dev/hvc<i-1>`（`229,<i-1>`） | virtio-console 的 **console 型**端口，真 tty | **选它**；`/proc/tty/drivers` 有 `hvc /dev/hvc 229 0-7 system` |

`paths.js`：`TERM_PORTS = 4`、`termTty(i) = '/dev/hvc' + (i - 1)`（`termSocket(i)` 仍是 `<vm>/tmp/term<i>`，没动）。
`vm.js`：终端 chardev 循环只留 `-chardev socket,…server=on,wait=off`，**去掉** `-serial chardev:term<i>`，
改在 `virtio-serial-pci` 控制器与 QGA 之后追加
`-device virtconsole,chardev=term<i>,id=vc<i>,bus=virtio-serial0.0`
（**顺序有硬约束**：`virtconsole` 要引用 `bus=virtio-serial0.0` ⇒ 必须写在控制器之后；
QGA 那条普通 `virtserialport` **不占** hvc 号）。

> 顺带钉死一条**死路**：同一份内核 config 里 `# CONFIG_SERIAL_8250 is not set`
> ⇒ `pci-serial` 那条候选反射弧**不存在**，不用再试；`/sys/bus/acpi/devices` 也不存在
> ⇒ 实际走 DT。还有一条**没试**的路（去掉 `acpi=on` 走 DT，QEMU 的 DT 按 `serial_hd(i)`
> 建 UART 节点、可能给出 4 个 `ttyAMA`）——风险落在整机启动路径上、收益与现在的 hvc 相同 ⇒ 不做。

### 1.3 「两行当前路径」的根治

**现象**：终端一开就打印两行当前路径。**不是**宿主拼帧的问题，是 **prompt 比列数宽**：
镜像 `/etc/profile` 给「非 bash / 非 ash-zsh 分支」的 `PS1` 是 `${HOSTNAME%%.*}:$PWD`（+ root 的 `# `），
本档 cwd `~/Download/harness` ⇒ prompt **46 列** > 侧栏 **42 列** ⇒ 折成两行；
其后的 SIGWINCH 重绘（`\r` + prompt + `ESC[K`）落在第二行上 ⇒ 看起来「路径又打了一遍」。

**为什么不能直接 `export PS1`**：`/etc/profile` 里那行是**无条件赋值**，exec 前 export 会被它盖回去。
所以**自写一份 rc**（落 guest 的 `/tmp/.dshm-rc`，tmpfs，**不碰镜像**）：

```
[ -r /etc/profile ] && . /etc/profile     # 先继承镜像的 umask / PAGER 等
PS1='\W# '                                # 后覆盖 prompt：cwd 的 basename ⇒ 永远十几列
umask 022
```

- **ash 家族**（`/bin/sh` 是 busybox ash）读 `$ENV`（**交互式** shell 才读）⇒ 起 shell 前 `export ENV=<rc>`；
- **bash** 的交互式非登录 shell **既不读 `/etc/profile` 也不读 `$ENV`**（只读 `~/.bashrc` 或 `--rcfile`）
  ⇒ 对 bash 走 `argvParts.splice(1, 0, '--rcfile ' + shq(RC_PATH))`。

真机实证：`exec env ENV=<rc> /bin/sh -i` ⇒ prompt 变成 rc 里的值；`exec /bin/bash --rcfile <rc> -i`
⇒ 同样生效（`BASH_VERSION=5.2.37`）。`\W` 在真机 ash 里可用（`cd /usr/share` ⇒ `share# `）。

**顺带修掉一处自找的重绘**：`sizeScript()` 原来发**两条** `stty`（rows / cols 各一条）⇒ 各触发一次重绘
（真机实测合并前 3 行、合并后 2 行）。已合并成一条
`stty -F <tty> rows R cols C`。

### 1.4 真机读数（2026-10-09，覆盖安装后）

```
create #1: status=200 ms=12394 ok=true     ← 冷启动（VM 首次拉起）
create #2: status=200 ms=361   ok=true
create #3: status=200 ms=486   ok=true
create #4: status=200 ms=566   ok=true
create #5: status=200 ok=false  "端侧终端端口已用满（本档最多 4 个并发终端），请先关闭一个终端再开新的"
首屏（terminal/follow 的 snapshot，去 ANSI）: "harness# "     ← 一行
```

宿主日志（`node-output.log`）逐条对上「端口 ↔ tty」：

```
终端会话已建立（#1 /dev/hvc0，argv=/bin/sh -i，shell pid=655，前台进程组=655）
终端会话已建立（#2 /dev/hvc1，argv=/bin/sh -i，shell pid=673，前台进程组=673）
终端会话已建立（#3 /dev/hvc2，argv=/bin/sh -i，shell pid=692，前台进程组=692）
终端会话已建立（#4 /dev/hvc3，argv=/bin/sh -i，shell pid=712，前台进程组=712）
```

（`pgrp=session=pid` 说明**作业控制是开的**；关闭后四条都正常回收，`inUse` 归零。）

---

## 2. 皮肤市场：`installPlugin` 缺失 → 补上 → 再修 `recovery` 形状

### 2.1 第一层：桥没有 `installPlugin`

真机 `GET /dsh-skin-market/operations/<id>` 原文：

```json
{"kind":"install","skinId":"fengb3.dsh-theme-macintosh","phase":"failed",
 "message":"service.installPlugin is not a function","step":"安装到 profile","attempt":1}
```

链路：市场 `lib/commands.js:451` 的 `desktopRunner()` 提供 `runner.installPlugin`（走
`service.installPlugin(...)`），而 `lib/lifecycle.js:774` 取 `this.options.runner.installPlugin`、
**没有就 throw**。我们的 `createDesktopPnpm()` 原来只实现了 `runPlugin`（通用 pnpm argv 通道）
⇒ 42 条 `install.desktop.mode === 'managed'` 的皮肤**一条都装不上**，UI 于是显示「需手动安装」。

**注意不要去改 catalog**：另外 259 条 `manual-only` 是市场**自己的**策略
（`lifecycle.js:400` 在 `hostKind==='desktop'` 时拒绝 `mode!=='managed'`），那是上游审核的真话。

### 2.2 第二层：包名不在顶层，在 `request.recovery`

补上 `installPlugin` 后，真机报错**换了内容**（这一步很关键 —— 症状相似、根因不同）：

```json
{"phase":"failed","step":"安装到 profile","message":"未给出包名或 GitHub 地址"}
```

这是我的实现读错了形状（读顶层 `request.packageName`）。市场真正发的是
`commands.js:454`：

```js
service.installPlugin({
  pnpmOptions: request.pnpmOptions,
  invokingDir: profileDir,
  recovery: { packageName: request.packageName, packageVersion: request.packageVersion, receiptId: request.receiptId },
  signal,
})
```

⇒ 包名/版本在 **`recovery`** 里。顶层那对是**官方 Electron runner** 的形状
（`official-desktop.js:145` 的 `request.packageName`），本档走不到。现在**两种都认、`recovery` 优先**，
取消信号同时接受 `request.signal` 与 `options.signal`。

### 2.3 落进 profile 的值必须是**裸 version**

装完市场还会核一次来源：`lib/profile.js:173` 的 `exactNpmSpecMatches()` 只认
`spec === version` / `name@version` / `npm:name@version` 三种，带 `^` 会被判「来源不符」再抛一次。
本桥走 `marketTargets()`（`-` 开头的选项整段滤掉）+ `dshm-installer.js` 的 `dependencyValueFor()`
⇒ `name@version` 记成裸 `version`，正好对得上。真机实证 profile `package.json`：

```json
{ "dsh-theme-macintosh": "0.1.2" }
```

### 2.4 真机读数

```
INSTALL 202 opId = 2ae1b82c-2012-472d-97db-f67b084c00ac
  {"phase":"done","message":"installed; choose Use to activate","step":"安装到 profile","attempt":1}
catalog: {"skinId":"fengb3.dsh-theme-macintosh","installation":"installed","activation":"inactive",
          "installedVersion":"0.1.2","installedSpec":"0.1.2","updateAvailable":false}
```

即：**装上了**（`installation: installed`），等待用户点「Use」激活（`activation: inactive`）——
这是市场的正常流程，`restartAvailable=false`（本档 `mountRoutes` 没给 desktop 分支配 `restart`）。

---

## 3. 本轮改动的文件与门禁

**改（仓库内）**

| 文件 | 改了什么 |
|---|---|
| `hostcore/plugins/dshm-vm-bash/lib/paths.js` | `TERM_PORTS` 1 → **4**；`termTty(i)` = `/dev/hvc<i-1>`；头注整段重写（两版通道 + 热插拔实证 + 8250 死路） |
| `hostcore/plugins/dshm-vm-bash/lib/vm.js` | 终端 chardev 去掉 `-serial`，改 `-device virtconsole,…,bus=virtio-serial0.0`（排在控制器之后） |
| `hostcore/plugins/dshm-vm-bash/lib/terminal.js` | 新增 `RC_PATH`；`spawnScript()` 写 rc + `export ENV` + bash 的 `--rcfile`；env 跳过列表加 `ENV`/`PS1`；`sizeScript()` 合并成一条 `stty` |
| `hostcore/plugins/dshm-vm-bash/package.json` | description 跟上通道口径（`-serial`/`ttyAMA` → `virtconsole`/`hvc`） |
| `hostcore/plugins/dshm-market-bridge/lib/index.js` | `createDesktopPnpm()` 新增 `installPlugin(request, options)`：`recovery` 优先、顶层回落、两种信号都接 |
| `hostcore/core-recipe.json` | `coreVersion` `+dshm.24` → **`+dshm.25`**（不升 ⇒ 增量复用的旧树不重新物化 ⇒ 改动静默不生效） |
| `tools/check-vm-bash.mjs` | 通道那一节按新口径重写（`TERM_PORTS===4` / `termTty(i)` / `-device virtconsole` 计数与顺序 / `-serial` 只剩 1 条 / 终端不再用 `-serial`）；新增 prompt 三件套断言（`RC_PATH` / `--rcfile` / `ENV` / `PS1='\W# '` / 单条 `stty`） |
| `tools/check-market-bridge.mjs` | 新增 I 节（`installPlugin`：`.req` 是裸 `name@version`、`.dir` 落 profile、`{exitCode:0,signal:null}`、缺目标走拒绝面且不投递、`signal` 接到 `cancel`）；并用**市场真实形状**（`recovery`）发请求 —— 原来那种「顶层和 recovery 都给」的写法**抓不到** 2.2 那个 bug |

**门禁（本机全绿）**

```
tools/check-vm-bash.mjs            233/233
tools/check-market-bridge.mjs      57 passed / 0 failed
tools/check-core-openharmony-patches.mjs   172 passed（23 处注入 + 1 处撤除守卫）
另跑：assert-cli-shim / check-parity / compat-drift / assert-exec-fix / assert-python-bridge /
      assert-fs-search-fallback(dshm.25 树) / check-feature-wiring / check-workspace-claim /
      check-decor-button-mode / check-denial-hints / check-profile-pnpm-bridge / check-ptc-ts-strip /
      check-ptc-runtime-inproc / check-ptc-wiring / check-internal-undici / check-worker-jitless /
      check-doc-refs / check-dead-code / check-skill-sync.cjs / check-fetch-shim.cjs /
      check-fs-local-permission / assert-core-entrypoints / check-native-closure / check-plugin-toggle
      ⇒ 全 rc=0（`assert-fs-search-fallback` 在树未物化前必红，物化后 73/73）
```

**产物**

```
coreVersion  0.2.1-alpha.1+dshm.25
容器         dist/core/dsh-core-0.2.1-alpha.1+dshm.25-openharmony-arm64.zip
             59,266,924 B / sha256 98d438ee93903cfced18adcc879e5d91b971461db58f7fb6eb646cbb6f1e4f34
             （resfile 里只有这 1 份；check-resfile-core-zip ✅）
HAP          entry-default-signed.hap 400,129,455 B
             sha256 eeec4ccb50cf1853b0cdeeb9984704886dd7ffee22b8bdbe5ded4efe63616535
```

**真机**：`hdc install -r` 覆盖安装；`home` 指纹 **8/3440 装前 = 装后**（会话 / 插件 / 工作区未动），
核心树切到 `+dshm.25`，端侧就绪判据通过（`toybox=ok`）。

---

## 4. 没做 / 待拍板

1. **终端冷启动 12.4 s**（热启 0.4–0.6 s）。这是**在应用进程里冷启一台 QEMU** 的固有代价
   （kernel → init 1.23 s、EXT4 re-mount 6.22 s 等，见 `docs/120` 的读数）。仓库里**已经有**
   预热开关：`index.js:288` 的 `DSHM_VM_BASH=warm`（`apply()` 里 `void ensureRunning()`，
   不阻塞启动，是**后台**预热）。要不要在手持档**默认打开**是产品取舍 ——
   代价是每次启动都占一份 CPU/RAM（VmRSS +1.22 GB 量级），收益是第一条命令 / 第一个终端不再等 12 s。
   **本轮不替用户决定。**
2. `installPlugin` 成功后市场会写 profile 的 loader 行 ⇒ **需要重启应用**才生效；
   本档 desktop 分支没配 `restart`（`index.js:61`），所以市场只显示「choose Use to activate」。
   要不要给手持档接 `restart`（走 `appExit` 调度），留到下一轮。
3. 皮肤装完的**激活**（`activation: inactive → active`）本轮**没验**；本轮只验到「装得上」。

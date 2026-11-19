# 260 — 真机取证落地（hdc 端口发现 · PC 与手机双档启动实读）

> 日期：2026-10-25
> 起因：侧载 `1.1.6 / 1010007 / 0.2.1-rc.3+dshm.96` 后需要「抓启动日志、监控异常」，
> 但 `hdc list targets` 长期是 `[Empty]`，整条取证链走不通。
> 本篇记录**端口根因**与**两台设备的真实启动读数**，并把此前只能靠"问用户看界面"
> 的判断改成可机器判读。

---

## 1. 根因：hdc 连不上不是权限问题，是端口用错了

### 1.1 之前的错误做法

`hdc list targets` 恒为 `[Empty]`；`hdc kill` / `hdc start server` 重来一遍仍是空。
于是沿"权限 / 服务没起"的方向试：

| 试过的端口 | 结果 |
|---|---|
| `8710`（AGENTS.md 与 docs 里写的老端口） | `[Fail]Connect failed` |
| `5555` / `1080` / `8711` / `3721` | 全部 closed |

结论一度写成"本机无法用 hdc 连自己"。**这个结论是错的。**

### 1.2 正确的做法

本机 hdc 的监听端口**记在系统参数里，不写死在任何文档**：

```bash
param get persist.hdc.port      # → 45595
```

拿到端口后：

```bash
hdc tconn 127.0.0.1:45595       # → Connect OK
hdc list targets -v             # → 127.0.0.1:45595  TCP  Connected  localhost  hdc
```

### 1.3 连带解开的三件事

1. `hdc shell` 拿到的是 **`uid=2000(shell)`**（我的进程是 `uid=20020093`），
   组含 `file_manager/log/netsys_socket/readproc` ⇒ **能读 el2**（应用数据目录实测是 `0777`）。
2. `snapshot_display` 与 `uitest dumpLayout` 都是**经 hdc 的 shell 身份**调起来的，
   与我自己的 uid 无关 —— 之前判"本机没有截图能力"时，卡的是同一个端口。
3. 手机侧同名工具同路径可用，两台设备可以用同一套命令取证。

> **口径**：以后凡是"本机 hdc 连不上"，**先 `param get persist.hdc.port`**，
> 不要去猜 8710/5555。老文档里的端口是历史值。

---

## 2. 取证命令基线（两台设备通用）

```bash
H=/data/service/hnp/hmos-clt.org/hmos-clt_1.0.0/sdk/default/openharmony/toolchains/hdc

# PC（本机回环）
$H -t 127.0.0.1:45595 shell ...

# 手机（USB）
$H -t 62T0225B18039433 shell ...        # VYG-AL00
```

关键读数位置（模块名 `entry` = PC/平板档，`phone` = 手机档）：

| 内容 | 路径 |
|---|---|
| 启动链 / 插件 / 探针 | `.../haps/<module>/files/node-output.log` |
| 心跳 / LOOP-GAP / 内存 | `.../haps/<module>/files/dshm-host.log`、`diag-mem` |
| Host 就绪（**含 token**） | `.../haps/<module>/files/dsh/home/host-ready.json` |
| 崩溃 | `.../haps/<module>/files/host-crash.log`（0 字节 = 无崩溃） |

宿主机侧再验一层（端口转发后）：

```bash
hdc fport tcp:3120 tcp:3120
curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:3120/?token=<上式>"
# 无 token → 401；带 token → 303 并下发 dsh-auth-* cookie
curl -s -b cookie.txt -X POST http://127.0.0.1:3120/api/session/list \
  -H 'Content-Type: application/json' \
  -d '{"type":"client-request","rpcId":"r1","method":"session/list","payload":{"args":{"_request":{}}}}'
```

---

## 3. 两台设备的安装身份（重要，与交付包不是一回事）

```
PC   appIdentifier=6918740027110769940  appProvisionType=debug
手机  appIdentifier=6918740027110769940  appProvisionType=debug
```

- 两台设备装的都是**本地 debug 身份**，`versionName=1.1.6` / `versionCode=1010007`。
- 我给用户编的 AGC `.app` 是 **release 身份 `6917614360926110054`**（`internaltesting`）。
  ⇒ **设备上跑的不是那份 `.app`**，是此前 IDE Run 出来的 debug 包。
- 两台设备的核心树都是 `0.2.1-rc.3+dshm.96`，与源码基线一致。

> 这条差别在"日志对不对得上源码"时很关键：核心树一致 ⇒ 代码一致；
> 但签名身份不同 ⇒ 不能拿设备上的包去验 AGC 侧行为。

---

## 4. PC 档启动实读（`entry` 模块，pid 16332）

### 4.1 启动链完整（7.0 s）

```
BOOT_00_NODE_START   node=v24.2.0 platform=openharmony/arm64 jitless=true
BOOT_10_ENV_READY    core=.../cores/0.2.1-rc.3+dshm.96  profile=ondevice
BOOT_20_CORE_FOUND   entry=profile-boot.js        (+11ms)
BOOT_30_PROFILE_READY                            (+34ms)
BOOT_40_PROFILE_BOOT                             (+148ms)
BOOT_65_AUTH_URL     port=3120 tokenLen=43       (+6472ms)
BOOT_50_DSH_INIT     runProfile 已返回           (+6613ms)
BOOT_60_HTTP_BIND    port=3120                   (+6613ms)
BOOT_70_HTTP_READY   GET / → HTTP 401 (389ms)    (+7006ms)
```

- `host-ready.json` 的 `pid` 与主进程一致，`workspace=~/Download/com.dshm.dshclient`。
- `dshm-host.log` 心跳拍到第 **1560+** 拍，**无 `LOOP-GAP`**。
- 宿主机 `curl`：无 token → 401，带 token → 303；`POST /api/session/list` 返回真实会话。

### 4.2 原生能力（PC）

| 能力 | 结果 |
|---|---|
| koffi / sharp / node-pty | ok |
| `pty-spawn` | **ok**（`fork+exec` 全链通过，pid=16590）|
| 内嵌 CPython | ok（`selftest=ok`，执行线程=worker）|
| exec 探测 | python3.12 / git / git-remote-http / rg / ash / bash / toybox **全 ok** |
| terminal | `realShell: yes`，`hostDomain=u:r:develop_tools_hap:s0` |
| `sandbox-dlopen` | **false**（E39 原样，见 `docs/215`）|

### 4.3 两条"看着像故障其实不是"的日志

- **`host-ready.json 属于旧进程（pid 不符），等本次写入`**
  出现在**上一轮**（pid 12333）那次启动，是旧进程残留文件造成的等待。本轮 pid 一致后已消失。
- **`E AppKit: dir:.../bundle/entry/resources/resfile not exist`**
  `entry` 侧本来就不该有整份 resfile —— 核心树是打进 `hostruntime` HSP 的。
  `BOOT_10_ENV_READY core=.../dshm.96` 证明核心树加载成功。

---

## 5. 手机档启动实读（`phone` 模块，VYG-AL00，pid 17536）

### 5.1 启动链同样完整（9.4 s）

```
BOOT_00_NODE_START   node=v24.2.0 jitless=true
BOOT_10_ENV_READY    core=.../cores/0.2.1-rc.3+dshm.96
BOOT_20_CORE_FOUND   (+97ms)
BOOT_30_PROFILE_READY(+123ms)
BOOT_40_PROFILE_BOOT (+1206ms)
BOOT_65_AUTH_URL     port=3120 tokenLen=43  (+8373ms)
BOOT_50_DSH_INIT     (+8632ms)
BOOT_60_HTTP_BIND    (+8633ms)
BOOT_62_PY_BRIDGE_HTTP /dshm-python/status|run-get|exec  (+8634ms)
BOOT_62E_CARD_STATE  (+8637ms)
BOOT_63_REGISTRY_VIEW(+8638ms)
BOOT_63B_PACKAGE_LIST(+8639ms)
BOOT_64_SHOT_PROXY   (+8640ms)
BOOT_70_HTTP_READY   GET / → HTTP 401 (758ms)  (+9402ms)
```

`host-ready.json` `pid=17536`，与主进程一致。

### 5.2 与 PC 的差异全部是**架构既定**，不是退化

| 项 | PC (`entry`) | 手机 (`phone`) | 判读 |
|---|---|---|---|
| `realShell` | yes | **no**（`rc1` / `relay rc126`） | 手持档本来就没有真 shell |
| `pty-spawn` | ok | **false**（`forkpty(3) failed`，E15） | 同上 |
| exec | 全 ok | `toybox=ok`，其余 `denied`/`缺` | 同上 |
| bash / 终端 | 宿主原生 | **guest VM 接管** | 见 5.3 |
| 内嵌 CPython | ok | **ok**（`print(1+1)=2`，1326ms）| 手机也能跑 python |

`terminal.note` 原话：`两条路径都被拒（toybox 中继 / 随包 ELF 都起不来）⇒ 本档没有真 shell，见 docs/104`。

### 5.3 guest VM 确实按设计接管了

```
[dshm-vm-bash] 已接管 ctx.subprocess.spawn（鸿蒙端侧且 VM 资产齐备（三端同步走 guest VM））
[dshm-vm-bash] VM 内存档位：economy total=11614MiB guest=256MiB tcg=64MiB minAvail=1280MiB
[dshm-vm-bash] 已接管 ctx.subprocess.spawnTerminal（同上）
[dshm-vm-bash] 静默预热：已关闭（economy 档；首条 bash / 终端请求时才拉 guest VM）
```

⇒ 手机档的 bash 不靠宿主原生 `fork`，走 guest VM；`realShell=no` 与"bash 可用"可以同时成立。
**判手机档的终端能力，不能只看 `terminal.realShell`。**

### 5.4 异常扫描结果

| 项 | 读数 | 判定 |
|---|---|---|
| `host-crash.log` | **0 字节** | 无崩溃 |
| 本轮 `LOOP-GAP` | **0**（03:10 之后） | 无卡顿 |
| 心跳 | 第 40+ 拍持续 | 事件循环在跳 |
| 内存 | `rss=588MiB` / `avail=2505MiB`（阈值 1600/384） | 安全区 |
| `onMemoryLevel=moderate` | 2 次，`trim=moderate` | 系统常规回收，非本应用请求 |

历史 `LOOP-GAP` 共 25 条，**全部落在 2026-10-24T15:24（上一轮 .95 核心）**，
明细为 `realpathSync×8009=504ms ⏐ spawnSync×11=656ms ⏐ readFileSync×1995=160ms` ——
正是 `docs/199`（fs 探测缓存）与 `docs/200`（Python 异步 worker）已在治的那两个根因。
本轮 `.96` 未复现。

### 5.5 一条已知噪音（不是故障）

```
工具链：解包子进程异常：Error: spawn .../files/bin/busybox EACCES
```

随后紧接 `工具链：python=就绪，git=本档跳过` ⇒ 手机档不装 git，busybox 解包这一步不参与，抛错被吞。

---

## 6. 界面：已能自己看见，不必再问用户

`snapshot_display` 实拍（PC 2880×1920 / 手机 1280×2832）确认：

- **PC**：三栏布局 + 会话列表 + 会话区 + 文件面板；文件面板列 `~/harness`。
- **手机**：侧栏抽屉态正常，列表与输入框在位。

注意两点：

1. 首帧可能拍到**别的前台应用**（本次是浏览器）。应用 `state #FOREGROUND` 不等于窗口在最前；
   要拍它就用 `aa start -b com.dshm.dshclient -a EntryAbility` 拉到前台再拍。
2. `aa dump -l` 里手机的 `window attached #0` 曾被我当异常，实拍证明**窗口正常**。

---

## 7. 没做的事

- 未卸载、未删除任何设备数据；全程只读 + `aa start` 一次。
- 未改源码、未重编、未动签名物料。
- 未把手机侧的 `appIdentifier=6918740027110769940`（debug）换成 release —— 那需要卸载，
  会清 el2 会话/插件/工作区，按 `AGENTS.md` 必须先问用户。

---

## 8. 回归

本期只新增档与只读取证，未改代码。相关既有门禁不变。
`node tools/check-doc-refs.mjs` 用于确认本篇引用与编号合法。

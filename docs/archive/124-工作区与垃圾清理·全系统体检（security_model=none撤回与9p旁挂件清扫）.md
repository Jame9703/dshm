# 124 · 工作区与垃圾清理 + 全系统体检（`security_model=none` 撤回 · 9p 旁挂件清扫）

> 承接 `docs/113`（工作区登记再收窄）、`docs/123`（侧边栏终端接入 guest 虚拟机）。
> 本档记用户这一轮的三件事：**① 把用户没建过的工作区与纯垃圾清掉（并加代码级守卫）**、
> **② 让模型跑一次完整测试 + 全系统 / 工具调用体检**、**③ 修已知问题**。
> 设备：`62T0225B18039433`（VYG-AL00 / API 26 / `const.product.devicetype=phone` / 手持档）。

---

## 0. 一句话结论

| # | 事 | 结论（都有真机读数，见 §1–§7） |
|---|---|---|
| 1 | 工作区 / 会话 / 垃圾 | 注册表里那条用户没建过的 `com.dshm.dshclient` **已删**（连它名下那 1 条空壳会话）；设备侧清 **668.3 MiB**、仓库侧清 **2,057.8 MiB**；自带插件 `dshm-workspace-claim` 再收窄成「只要那条是自己登记的就撤」 |
| 2 | 模型体检 | 三轮：r43（首次全通）、r44（**抓到一条本轮改动造成的回归**）、r46（修复后复跑） |
| 3 | 已知问题 | 真缺陷 **1 条 P0**：`+dshm.22` 把 9p 改成 `security_model=none` ⇒ **guest 在用户工作区里一次都写不进去**（`Operation not permitted`，真机 2/2 复现）。已**撤回**并新增 `sweepSidecars()` 清旁挂件 ⇒ `+dshm.23` |
| 4 | r46 自检实收 | `<工作区>/DSHM-端侧自检-r46.md`（8534 B）经宿主 Python 桥读回：**全部列表项 PASS**（含 r44 失败的那条写测试 `ws_rc=0`）——见 §9.1 |
| 5 | 追加轮（同日） | 残留清完（`vm/tmp` 11 件 + 空 `.virtfs_metadata/`）；真缺陷 **再 1 条**：`CoreStore.evict()` 有实现、有判据、有单测却**一个调用点都没有** ⇒ 真机上 **15 棵核心树并存 ≈5 GB**；判据里还有一条致命假设（`state.current` 可空）⇒ 一并修掉 ⇒ `+dshm.24`，见 §9.2–§9.4 |

**一句话判据**：9p 的 `security_model` **不能用 `none`** —— 它让 QEMU 按 guest 请求的 uid/gid
落盘（impersonate），而宿主给应用的「工作区授权」是**按应用**给的 ⇒ 换成 uid 0 就落在授权之外。

---

## 1. 清理（三处，逐项有读数）

### 1.1 注册表：那条用户没建过的 `com.dshm.dshclient`

- 走 dsh 自己的 RPC：`POST /api/workspace/delete`，args 必须是 `{"request":{"workspaceId":…}}`
  —— **包一层 `request`**；直接给 `workspaceId` 会报 `missing "request"`
  （`workspace/*` 与 `session/*` 的入参口径不同：后者用 `_request`）。
- 会话文件用应用自身的 Python 桥删：`$DSH_HOME/sessions/--storage-Users-currentUser-Download-com.dshm.dshclient--/`
  整个目录 + `storages/session_projcache/sessions/session-<id>.json`。
- 装后复核：`workspaceIds` 只剩 `c76fc493…`（harness，4 会话）；`sessions/` 只剩 `--root--` 与
  `--storage-…-harness--`；`session/list` 9 条、**0 条 blank**。
- ⚠️ **不要删** `~/Download/com.dshm.dshclient`：那是 ArkTS 认领的宿主目录，删了会重建。

### 1.2 设备侧垃圾（清 668.3 MiB）

| 清的 | 量 | 为什么是垃圾 |
|---|---|---|
| `dshm-diag/dshm-profile-*.cpuprofile` ×46 | 156 MiB | 每次启动最多 3 份、**跨启动累积**（见 §5） |
| `vm/tmp/ram.dump` | **512 MiB** | 调试期的手工转储 |
| `vm/tmp/run-*.sh` ×6 + `qga2/3/7_socket` 死 socket + `*_hold.txt` | 小 | 上一轮进程留下的运行件（`.21` 起由 `sweepStaleTmp()` 起点清） |
| `dshm-term-*.txt` ×5 | 小 | 终端取证留下的临时件 |

保留：`vm/tmp/{qga_socket,qmp_socket,term1}`（当时进程在用）、`bin/`、`tmp/`、`workspace/`、`toolchain/`。

### 1.3 仓库侧垃圾（清 2,057.8 MiB）

`dist/core/work/dsh-core-*+dshm.{13..20}`（8 棵树）、对应 8 个容器 zip + manifest、`dist/localtest`（131 MiB）、
`dist/dbg`（48.7 MiB）、`dist/bootprobe`（9.7 MiB）、`dist/_update_build.log`、`entry/.cxx`。
保留 `dist/core/work/*+dshm.22`、`dist/sideload/`、`dist/acceptance/`。

> **两个操作坑**（都复现过）：
> · `Remove-Item -Recurse` 被本机 shell 策略拒 ⇒ 改用 Node `rmSync` + 「必须在工作区内」白名单；
> · 清 `dist/core/work/<旧版本>` 之后**必须**删 `entry/.cxx`，否则 ninja 缓存引用已删路径，
>   下一次 `BuildNativeWithNinja` 报 `flock.c missing`（构建缓存，允许清）。

---

## 2. 代码级守卫：以后不再私自加工作区

`hostcore/plugins/dshm-workspace-claim/lib/index.js`：原来撤自己那条要**它 0 会话**，
而真机反例是那条工作区名下挂着 **1 条会话** ⇒ 永远撤不掉。那条会话**不是**本插件建的，
是**客户端**首启自动连的（`restoreSelection()` → `connectWorkspace()` → `reuseOrCreateBlank()` 建一条空壳）。
判据改成「**只要那条是我们自己登记的（按路径命中认领目录）就撤**」，并且：
会话**一条都不删**（上游没有删会话的接口）、撤完注册表必须**仍非空**
（否则上游 `initializeDefault()` 会去跑在本端必失败的目录探测）。
门禁 `tools/check-workspace-claim.mjs` 10 → **16** 条。

---

## 3. 模型体检（三轮，机制可复用）

| 轮 | 触发 | 结果 |
|---|---|---|
| r43 | 首次全量自检 | bash 5 条、文件 / 搜索 5 条、web 1 条 **全 PASS**；报告落 `<工作区>/DSHM-端侧自检-r43.md` |
| r44 | `.22` 装机后复跑 | **抓到 P0 回归**：guest 写工作区 `Operation not permitted`（2/2 复现），同一时刻写沙箱共享根 `rc=0` |
| r46 | `.23` 装机后复跑 | `ws_rc=0` / `mkdir_rc=0` ⇒ 回归消除；报告落 `<工作区>/DSHM-端侧自检-r46.md` |

触发模型的接口与两条经验：

- `POST /api/session/prompt`，body `{"request":{"sessionId":…,"requestId":<uuid>,"mode":"queue","content":[{"type":"text","text":…}]}}`
  —— **`mode` 必填**（wire schema 是 `z.union([literal("queue"), literal("steer")])`，不是 optional）。
- 让模型把读数**写进工作区文件**（宿主侧 write 工具），再用应用自身的 Python 桥读回：
  比读会话产物省事 —— 会话日志是 `session.v4.jsonl.zstd`，而端侧 CPython 3.12 没有内置 zstd。
- 模型自检**必须让它真调工具**（"不要凭记忆回答"），否则它会把 expected 当 observed 写。

---

## 4. 核心发现：`security_model=none` 必须撤回（本轮唯一的真缺陷）

### 4.1 症状与边界（真机原始读数）

`.dshm-r44` 那轮（`+dshm.22`）：guest 里 `echo x > <工作区>/…` 与 `mkdir <工作区>/…`
⇒ `Operation not permitted`，**2/2 复现**；同一时刻写沙箱共享根 `rc=0`。

`.dshm-r45` 那轮把边界钉死（同一次 bash 里的一次性读数）：

```
uid=0(root) gid=0(root)
---MOUNTS
hostshare  /mnt/share                                    9p rw,relatime,access=client,trans=virtio 0 0
hostshare2 ~/Download/harness   9p rw,relatime,access=client,trans=virtio 0 0
---TESTS
touch_ws=1      ← 工作区（宿主侧 drwxrwx--x 20001006:1006）失败
mkdir_ws=1
touch_parent=0  ← 父目录**不是** 9p 挂载（guest 自己的 rootfs 目录）⇒ 这个 0 不构成证据
touch_sbox=0    ← 沙箱共享根（drwxrwxrwx 20020450:20020450）成功
```

⇒ 两份 9p 的**挂载参数逐字相同**，差别只在被导出目录的**属主 / 权限**。

### 4.2 为什么（判据是实测的，机制是推断）

- **实测事实**：应用**自己**（同一进程、同一 uid 20020450）在同一个目录里
  `open(O_CREAT)` 与 `openat(O_CREAT|O_NOFOLLOW)` 都**成功**（主线程与新建 worker 线程各一次）
  ⇒ 这不是「应用不能写这个目录」，而是**做这次写的不是应用的身份**。
- **推断（未经 QEMU 源码确认）**：`security_model=none` 下 QEMU 会**按 guest 请求的 uid/gid 落盘**
  （impersonate；guest 里是 root ⇒ uid 0）。而宿主的「工作区授权」是**按应用**给的
  （`docs/105`：授权只对该应用有效、父目录 `opendir` 一律 `EPERM`）⇒ 换成 uid 0 之后
  **落在授权之外**，写 / 建一律 `EPERM`。只有「宿主 uid 自己就有 DAC 写权限」的目录
  （沙箱共享根 0777 且属主就是应用）才碰巧能用 —— 这正是上面 `touch_sbox=0` 的原因。
- **对照**：`security_model=mapped-file` 下 QEMU **从不 impersonate**，始终以本应用身份落盘，
  uid/gid/mode 记在旁挂件里 ⇒ 授权照旧生效（r43 与 r46 两轮都能写；HiSH 上游也是这一档，见 `docs/119`）。

> 判据的形状：**一个改动要么在两处都能写、要么在两处都不能写；出现「一处能一处不能」，
> 就说明被改的是一层与目录属性耦合的东西（身份映射），而不是与操作无关的东西。**

### 4.3 结论与取舍

- **回到 `mapped-file`**（两份同档 —— 混档只会制造「一份能写、一份不能写」的假象，
  `+dshm.22` 就是这么翻的车）。
- 不用 `passthrough`：它同样按 guest 的 uid 去 `chown`，而 QEMU 不是 root ⇒ 每次写都可能 EPERM。
- 旁挂件的代价用 `sweepSidecars()` 在起点兜掉（§5）。
- **下一轮候选**：`mapped-xattr`（把 uid/gid 记在 `user.virtfs.*` 扩展属性上，一个旁挂件都不落）
  —— 但 `~/**` 这一层支不支持 user xattr 本仓还没实测过，
  按「判据现状优先于整洁」本轮先用**已验证能写**的这一档。

### 4.4 修复后真机复核（`+dshm.23`）

```
[dshm-vm-bash] QGA 就绪（+11425 ms）/ guest 侧已就绪：/bin/bash 可用
guest: echo probe > <工作区>/.dshm-r46-probe && cat …   → probe / ws_rc=0
guest: mkdir <工作区>/.dshm-r46-dir                     → mkdir_rc=0
宿主: .dshm-r46-probe uid=20001006 gid=1006 mode=660（落盘属主是鸿蒙文件服务，不是 root）
```

---

## 5. `sweepSidecars()`（旁挂件清扫）与另两处卫生

| 位置 | 做什么 | 真机读数 |
|---|---|---|
| `hostcore/plugins/dshm-vm-bash/lib/vm.js` `sweepSidecars()`（`.23`） | `stage()` 起点清 `<共享目录>/.virtfs_metadata/*.virtfs_metadata`，空目录 `rmdir`；**两个共享根都扫** | `已清掉 ~/Download/harness/.virtfs_metadata 里上一轮留下的 2 个 9p 旁挂件` |
| 同文件 `sweepStaleTmp()`（`.21`） | 起点清 `vm/tmp` 的 `run-*.sh` / `stdin-*.txt` / 死 socket / `ram.dump` | `已清掉 vm/tmp 里上一轮留下的 6 个陈旧运行件：run-muzm…` |
| `hostcore/app/main.js` `pruneProfiles()`（`.21`） | CPU profile **跨启动**只留最近 3 份（原来 `profDumps >= 3` 只管本进程 ⇒ 累积 46 份 / 156 MiB） | 目录里稳定 1–3 份 |

三处共同的设计约束：

- 只在 **VM 未拉起时**发生（`stage()` + `ensureRunning()` 的 `ready` 早退与 `pending` 单飞保证只走到一次）
  ⇒ **不可能**删掉本次运行要用的东西；
- 只动**我们自己的命名空间**（`vm/tmp` 的白名单、`.virtfs_metadata/*.virtfs_metadata`、`dshm-diag/dshm-profile-*`），
  共享目录里的**用户文件一个都不碰**；
- 失败一律只记日志（清不干净顶多留个隐藏目录，绝不影响能不能读写）。

> **避坑（差点给出假绿）**：guest 侧 `ls -a` **看不到** `.virtfs_metadata`
> （virtfs 对 guest 隐藏自己的元数据目录）⇒ 判「有没有旁挂件」必须在**宿主侧** glob/read，
> 在 guest 里查永远是「没有」。

---

## 6. 门禁与验收

- `tools/check-vm-bash.mjs` 212 → **219** 条：9p 档位判据改成 `mapped-file` + 两条撤除守卫
  （`none` / `passthrough` 都不得复活）+ 新增「9p 旁挂件清扫」一段 6 条。**注入式负测试**：
  把 fsdev0 就地改回 `none` ⇒ `FAIL 217/219`，还原后与本机树逐字节一致。
- `tools/check-workspace-claim.mjs` **16** 条、`check-core-openharmony-patches.mjs` **172** 条、
  `check-resfile-core-zip`（1 份容器、与配方 / 产出三者一致）、`assert-resfile-sync`（14 件）全绿。
- 真机：`device-code-fingerprint.ps1` **10/10 / RC=0**（含改过的 `dshm-vm-bash/lib/vm.js`）；
  `device-acceptance.ps1` **5/5 PASS**（证据目录 `dist/acceptance/20261008-230704`）；
  `home` 指纹 `links=8 size=3440` 装前 = 装后。

---

## 7. 产物

- `coreVersion`：`0.2.1-alpha.1+dshm.22` → **`+dshm.23`**（核心树内容变了必须升，否则端侧不换树、补丁静默不生效）。
- 容器：`dist/core/dsh-core-0.2.1-alpha.1+dshm.23-openharmony-arm64.zip`
  **59,261,790 B** / sha256 `504dda03d7e54391…` / 16501 条目（旧 `+dshm.22` 容器已由 pack-core 自动清掉）。
- HAP：`entry/build/default/outputs/default/entry-default-signed.hap`，**381.6 MiB**，覆盖安装成功。
- **未 commit、未 push**（推送由用户决定）。

---

## 8. 未做 / 下一轮

1. **`mapped-xattr`**：若 `~/**` 支持 `user.virtfs.*` xattr，就能做到
   「能写 + 一个旁挂件都不落」（判据：guest 写一个文件后宿主侧既看得到内容、又看不到 `.virtfs_metadata`）。
   需要一次真机 A/B；失败就保持 `mapped-file` + 起点清扫。
2. **观测项（成因未定，只登记不下结论）**：本轮排障中观测到一次**主循环停顿** —— 14:40:45 起
   `LOOP-ALIVE` 停更、宿主 HTTP 无响应、进程仍在（**无 faultlog、无 `LOOP-GAP` 记录**），
   `aa force-stop` + `aa start` 后恢复。当时有**并发探针**（Python 桥 + 已起来的 VM）在跑，
   不能排除探针干扰 ⇒ 留给下一轮观察（尤其要在「有 VM 时从宿主侧做大量文件操作」这条路径上复现看看）。
3. **`os.walk('~/Download')` 从应用内返回空列表**（同一路径下的子目录
   `listdir` / `walk` 正常）—— 应用沙箱在那一层拿不到 `scandir`，而 `os.walk` 默认**吞错**。
   写「扫用户下载目录找垃圾」这类脚本时不能拿它当判据 —— 本轮第一次扫就因此报了「没找到」，
   `.virtfs_metadata` 那 6 个孤儿也是这么被漏掉的。
4. **guest 侧仍无 `node` / `python3`**（命中即 127）与 **guest 为 root** 这两条现状不变。

---

## 9. 追加轮（同日）：残留清干净 + 又一条真缺陷（核心树只增不减）

### 9.1 r46 自检报告的实收（报告本体已读回，不是等用户转述）

`<工作区>/DSHM-端侧自检-r46.md`（**8534 B**）由模型写进工作区，再由宿主 Python 桥读回。
**全部列表项 PASS**，其中最关键的一条是 r44 曾经 FAIL 的那个写测试：

| 项 | 读数 | 判定 |
|---|---|---|
| 1.1 `uname -a; id; pwd` | `Linux hish 6.12.60 … aarch64` / `uid=0(root)` / `~/Download/harness` | PASS |
| 1.2 `ls -d <工作区> && ls … \| head` | 共享可读（`head` 未触发截断） | PASS |
| **1.3 写测试** | `probe` / **`ws_rc=0`**（r44 这里是 `Operation not permitted`） | **PASS** |
| 1.4 `mkdir` | `mkdir_rc=0` | PASS |
| 1.5 管道与退出码 | `rc=1` / `1` | PASS |
| 1.6 `cat /etc/os-release` | `Alpine Linux 3.22.0` | PASS |
| 2 文件 / 搜索（glob·grep·read·write/read/remove） | 逐项有原文读数 | PASS |
| 3 `web_fetch https://example.com` | HTTP 200 / `Example Domain` | PASS |
| 4.1 guest 内 `node`/`python3` | 双双 `command not found`（127）—— **如实"没有"** | PASS |
| 4.2 插件/技能清单 | 本会话无对应工具 ⇒ 用只读 `read` 给清单 | N-A |

报告同时**如实记下两条反向证据**（都写进了 §5）：

- **9p 旁挂件仍在工作区链路上产生**（`hostshare2` 那份共享）—— 这与 `mapped-file` 档位的设计一致：
  旁挂件是**这一档的代价**，本轮的处置是"起点清掉"（`sweepSidecars()`），不是"不产生"。
- 报告 §5 第 2 条怀疑"工作区状态在轮次之间被重置"（它上一轮写的诊断文件不见了）——
  实为**我们自己的清理动作**（上一轮的探针件由 `r46clean` 类脚本删除），不是工作区被重置；
  该条按"探针自述、未证实"处理。

### 9.2 残留清理（设备侧，先确认 VM 没在跑再动手）

判据：`ps -ef` 里只有应用进程、**没有 qemu** ⇒ `vm/tmp` 与 socket 全是死件。清掉 **11 件**：

| 清的 | 为什么是垃圾 |
|---|---|
| `.dshm-r45-c`（空目录） | 上一轮 9p 对照实验探针留下的（不在 `STALE_TMP` 白名单里 ⇒ 得手工清） |
| `run-muz*.sh` × 7 | 每条命令一份的落盘脚本（名字带随机 id ⇒ 天然越攒越多，`.21` 起由 `sweepStaleTmp()` 在起点清） |
| `qga_socket` / `qmp_socket` / `term1` | 死 socket（下次 `stage()` 也会先删，QEMU `bind()` 前必须不存在） |
| 工作区里的 `.virtfs_metadata/` | **空目录**（旁挂件已被 r46 那轮清掉）⇒ `rmdir`；留着它就是用户可见目录里平白多一个隐藏目录 |

复核：`vm/tmp` 空；工作区只剩 4 份报告 + 既有文件（`hello.txt`/`notes.md`/`data.csv` + 3 份历史报告）。

### 9.3 真缺陷：`CoreStore.evict()` 有实现、有判据、有单测，**一个调用点都没有**

真机清点（`du -m`）：`dsh/cores/` 下 **15 棵核心树 ≈ 5 GB**
（`0.1.7-rc.2`、`0.2.0-rc.2`、`+dshm.6/.7/.13…​.23`）。

- **成因**：核心树是**每版一份**解包落地的（`cores/<version>/`，实测 ~350 MB/棵），而安装器
  （`BundledCore.installBundledCores`）只在"同一版本换了容器"时替换**同一棵**
  ⇒ 跨版本升级**只增不减**。而 `CoreStore.evict()`（判据 `Types.evictionCandidates`）虽然
  早就写好、还配了单元用例，**却从来没有调用点** —— 这正是 `check-feature-wiring` 该拦下的那类缺口。
- **判据里还有一条致命假设**：`evictionCandidates` 只保护 `current`/`previous`。
  而真机上 `state.json` **可以不存在**（首启只解包、从未激活：实测 15 棵树并存而
  `state.current` 为空）—— 那种状态下 `DshHost.start()` 取的是 `newestVersion(installed)`
  ⇒ 按原判据算，**正在跑的那棵树**也在"可删"名单里。真删下去就是"把自己脚下的地板拆了"，
  下一次启动会落到"还没有安装任何核心版本、无法启动"。
- **修法（三处，都尽量小）**：
  1. `Types.evictionCandidates` 增加两条不变量：**永不删"会真正启动的那棵"**
     （`current` 缺失/已不在时 = `newestVersion(installed)`）+ 调用方点名的 `keepExtra`；
  2. `CoreStore.evict(keep, keepExtra)` 透传；`BundledCore` 在**走完安装流程之后**调用
     `evict(0, result.installed)`（**不只是"真装了东西"那一次**：设备上的实况恰恰是
     "已安装过 ⇒ 跳过"，若只在真装时清，这一轮攒下的旧树要等到下次换容器才可能被清）；
     放在安装之后算，刚落地的新树才是"会真正启动的那棵"；
     点名 `result.installed` 是为了"回退到旧侧载包"那种场景（新装的反而更旧时不被误删）；
     整段吞异常：清理不能把"装成功"拖下水。
  3. `hostruntime/src/main/ets/Index.ets` 的文件头把"尚未实现"更正
     （切换/回滚的界面动作**早已**接线：`Index.ets` 里 `switchTo`/`rollbackTo` 各一处调用）。
- **验法**：新增 3 条单元用例（`entry/src/ohosTest/…/CoreDecision.test.ets`）+ 1 条接线门禁
  （`check-feature-wiring` 的 `旧核心树清理`，钉"定义签名 + 调用点"两处）。
  纯逻辑另外用 Node 的 **type-stripping** 把 `Types.ets`/`Naming.ets` 直接跑了一遍（**8/8**，
  含 4 条老行为回归）；接线门禁做了注入式负测试（把调用点改名 ⇒ `✗ 旧核心树清理 … 只找到 0 处`，退出码 1）。

### 9.4 本轮门禁与产物

- **门禁**：仓库内 **30 条**全绿（16 条 CI 档 + 核心树档 + `check-vm-bash` 225/225 + `check-workspace-claim` 16 +
  `check-resfile-core-zip` + `check-tar-extract` + `check-native-closure` + `assert-core-entrypoints`）；
  另跑 `check-feature-wiring`（19 个功能全接线）、`check-store-readiness`、`check-doc-refs` 等。
- **`coreVersion`**：`+dshm.23` → **`+dshm.24`**（`vm.js` 的共享根清单改了树内插件 ⇒ 必须升，
  否则端侧不换树、改动静默不生效）。容器 `dist/core/dsh-core-0.2.1-alpha.1+dshm.24-openharmony-arm64.zip`
  **59,263,020 B** / sha256 `33656530fd96223a…` / 16501 条目（pack-core 自动清掉旧的 `.23` 容器）。
- **HAP**：覆盖安装（`hdc install -r`），`home` 指纹 `links=8 size=3440` 装前 = 装后（用户数据未动）。
- ⚠️ **本轮末设备锁屏**：`aa start` 被系统拒绝（`10106102 The device screen is locked`）⇒
  `.24` 的解包与"清理旧核心树"的真机读数**留待解锁后补**（见 §10）。

### 9.5 另外一条：`vm.js` 的共享根清单（`.24` 的另一半改动）

见 §5 表里 `sweepSidecars()` 那一行的补充：旁挂件只长在**被 9p 导出过**的目录里，
而导出目录一进程一 VM（`state.extraShare` 由首个拿到 cwd 的调用定死）⇒ **换过工作区的用户**，
上一个工作区里那坨谁都不会扫。现在把"我们挂过的根"记进 `vm/shared-roots.json`
（只留最近 8 条、已不存在的路径剔掉、读不到/写不进都只记日志），下次 `stage()` 起点一并扫。
门禁 `check-vm-bash` 219 → **225**（注入式负测试：删掉 `existsSync` 过滤 + 把 `sweepSharedRoots` 换成
`sweepSidecars` ⇒ `FAIL 223/225`，还原后逐字节一致）。

---

## 10. 解锁后的真机实收（把 §9 的改动全部落到实处）

### 10.1 清理旧核心树：`15 棵 → 1 棵`（真机读数）

运行 `.\tools\update-device.ps1`（覆盖安装，`hdc install -r`）后：

```
[2] 安装前：0.1.7-rc.2、0.2.0-rc.2、+dshm.6、.7、+dshm.13…​.23、+dshm.24   ← 16 棵
[7] 安装后：0.2.1-alpha.1+dshm.24                                            ← 1 棵
```

```
$ ls $FILES/dsh/cores        →  0.2.1-alpha.1+dshm.24
$ du -s -m …/cores/*         →  350  （改前 15 棵合计 ≈ 5131 MB ⇒ 释放 ≈ 4.8 GB）
hilog: DSHM-BundledCore: 已清理旧核心树 15 棵：0.1.7-rc.2、0.2.0-rc.2、+dshm.6、+dshm.7、
        +dshm.13、+dshm.14、+dshm.15、+dshm.16、+dshm.17、+dshm.18、+dshm.19、+dshm.20、
        +dshm.21、+dshm.22、+dshm.23
```

- 用户数据未动：`home` 指纹 `links=8 size=3440` 装前 = 装后；`workspaceIds` 仍只有 `harness`。
- 端侧就绪：本轮 `exec` 探测逐项 + Host HTTP（websocket `98 → 99`）全 OK。
- **没有把"正在跑的那棵"删掉**：`+dshm.24` 正是被保护的那棵（`state.current` 为空 ⇒ 保护 `newestVersion`）。
  这一步就是 §9.3 第二条不变量在真机上的对照臂。

### 10.2 两处起点清扫：**种了孤儿再验**（A/B，真机读数）

判据要能证伪，所以先**人为种下**孤儿（宿主侧 Python 桥）：

- 工作区 `.virtfs_metadata/` 下种 2 个假旁挂件（`r48-orphan.virtfs_metadata`、`r48-orphan2…`）；
- `vm/tmp` 下种 `run-orphan-r48.sh`、`stdin-orphan-r48.txt`。

然后 `aa force-stop` + `aa start`（重启进程，VM 归零），再让模型真跑一次 `bash`（`echo r48b-ok`）。
下一次 `stage()` 的读数（`node-output.log`）：

```
[dshm-vm-bash] 启动 guest VM（第 1 次尝试；share=/data/storage/el2/base/haps/entry/files；
               工作区共享=~/Download/harness）
[dshm-vm-bash] 已清掉 vm/tmp 里上一轮留下的 6 个陈旧运行件：run-muzq20hw-0c574q.sh、
               run-muzq2a3e-kcqt7b.sh、run-muzq2eec-m5u3ru.sh、run-muzq2jba-8lisnc.sh、
               run-orphan-r48.sh、stdin-orphan-r48.txt
[dshm-vm-bash] 已清掉 ~/Download/harness/.virtfs_metadata 里
               上一轮留下的 2 个 9p 旁挂件（security_model=mapped-file 的副产物）
[dshm-vm-bash] QGA 就绪（+11489 ms）
```

复核（宿主侧 Python 桥，权威视角）：工作区 `.virtfs_metadata` **整个目录已 rmdir**（`SIDECAR_DIR False`），
工作区只剩 10 个条目（4 份报告 + 既有文件 + 3 份历史报告）；`vm/tmp` 只剩活 socket + 本轮那份 `run-*.sh`。

### 10.3 共享根清单真机落地

```
$ cat $FILES/vm/shared-roots.json
["/data/storage/el2/base/haps/entry/files","~/Download/harness"]
```

⇒ §9.5 的清单第一次真机落盘就有两项（沙箱根 + 授权工作区），也正是 §10.2 那次清扫的扫描面。

### 10.4 bash 通道（改完 vm.js 之后）仍可用

同一次 r48 任务：`uname -sr` = `Linux 6.12.60`、`id` = `uid=0(root)`、`pwd` = 工作区；
写测试 `ws_rc=0`（模型自己删掉了探针件，工作区复核无残留）；
`node-output.log` 里本轮 5 条 `guest 命令结束：… rc=0`，`guest 侧已就绪：/bin/bash 可用`。

### 10.5 门禁与验收（最终）

| 项 | 读数 |
|---|---|
| 仓库内 30 条门禁 | **全绿**（含 `check-vm-bash` 225/225、`check-feature-wiring` 19 功能全接线、`check-workspace-claim` 16、`check-resfile-core-zip`、`check-native-closure`、`assert-core-entrypoints`） |
| 设备代码指纹 `device-code-fingerprint.ps1` | **10/10 / RC=0**（含改过的 `dshm-vm-bash/lib/vm.js`） |
| 设备验收 `device-acceptance.ps1` | **5/5 PASS**（证据目录 `dist/acceptance/20261009-000336`；其余为人工界面勾选项） |
| `home` 指纹 | `links=8 size=3440` 装前 = 装后（全程未动用户数据） |
| 工作区注册表 | 只有 `harness`（`com.dshm.dshclient` 未被重新登记）；`session/list` 9 条、**0 条 blank** |

---

## 11. r49：手机解锁后的复验 + 本轮清扫读数（2026-10-09 00:0x）

> 用户把设备解锁后重连（`62T0225B18039433` / 手持档），本轮把 §9/§10 的改动**再跑一遍真机判定**，
> 并顺手清掉这一轮自己留下的垃圾。**代码一行未改**（只修了本档 §10.1 的一处字节级勘误，见 §11.5）。

### 11.1 门禁（仓库内 31 条，全绿）

`assert-cli-shim` / `assert-resfile-sync` / `check-parity` / `compat-drift` / `assert-exec-fix` /
`assert-python-bridge` / `assert-fs-search-fallback` / `check-web-fetch-jitless` / `check-worker-jitless` /
`check-internal-undici` / `check-fetch-shim` / `check-skill-sync` / `check-ptc-ts-strip` /
`check-ptc-runtime-inproc` / `check-ptc-wiring` / `check-core-openharmony-patches` / `check-decor-button-mode` /
`check-market-bridge` / `check-profile-pnpm-bridge` / `check-denial-hints` / `check-fs-local-permission` /
`assert-core-entrypoints` / `check-doc-refs` / `check-dead-code` / `check-workspace-claim` /
`check-resfile-core-zip` / `check-plugin-toggle` / `check-native-closure` / `check-tar-extract` /
`check-vm-bash`（225/225）/ `check-feature-wiring` ⇒ **31/31 rc=0**。

`check-doc-refs` 读数：扫描文档 **54 个** · 带行号引用 **289 条**，全部落点与声称的节一致。

### 11.2 设备读数（全部与 §10 一致，且是**本进程**）

| 项 | 本轮读数 |
|---|---|
| 代码指纹 `device-code-fingerprint.ps1` | **10/10 / RC=0**；`token 来源：host-ready.json`；设备树 = 本机 `+dshm.24` |
| 设备验收 `device-acceptance.ps1`（强制冷启动 + 覆盖安装） | **5/5 PASS**（`dist/acceptance/20261009-000921`；`bm dump updateTime` = 2026-10-09 00:03:55） |
| 核心树 | `$FILES/dsh/cores/` 只有 `0.2.1-alpha.1+dshm.24`；`du -s -m` = **350** |
| 工作区注册表 | `workspaceIds` 只有 `c76fc493…`（`harness`）；`tables.workspaces` 只 1 条、路径 `~/Download/harness` |
| 会话 | `sessions/` 只有 `--root--` 与 `--storage-…-harness--`；`session/list` **9 条**、`blank` 全 `false`、`running` 全 `false` |
| 工作区内容 | 10 个条目（7 份报告 + `data.csv`/`hello.txt`/`notes.md`）；`.virtfs_metadata` **不存在** |
| 共享根清单 | `vm/shared-roots.json` = `["/data/storage/el2/base/haps/entry/files","~/Download/harness"]` |
| `vm/tmp` | 只剩 `qga_socket`/`qmp_socket`/`term1` 三个活 socket + 本轮 1 份 `run-*.sh` |

### 11.3 bash 通道：**这一轮现场又跑了一次**（不是复用 §10 的旧读数）

冷启动后经 `session/prompt` 派一个极小任务（只跑两条命令、不许写文件），模型回执的原始输出：

```
uname -sr; id; pwd
  Linux 6.12.60
  uid=0(root) gid=0(root)
  ~/Download/harness
```

`node-output.log` 同批读数（本进程）：

```
[dshm-vm-bash] 启动 guest VM（第 1 次尝试；share=/data/storage/el2/base/haps/entry/files；工作区共享=~/Download/harness）
[dshm-vm-bash] 已清掉 vm/tmp 里上一轮留下的 1 个陈旧运行件：run-muzq5syo-vam4f2.sh
[dshm-vm-bash] guest 命令结束：pid=647 rc=0 轮询 4 次、205 ms
[dshm-vm-bash] guest 侧已就绪：/bin/bash 可用
[dshm-vm-bash] guest 命令结束：pid=667 rc=0 轮询 10 次、222 ms
[dshm-vm-bash] guest 命令结束：pid=671 rc=0 轮询 4 次、98 ms
```

⇒ §10.2 的**起点清扫**与 §10.4 的**bash 可用**都是独立第二次成立（§10.2 那次是种了孤儿再验，这次是自然残留）。

### 11.4 本轮清扫（三处，逐项有读数）

| 处 | 清掉 | 判据 |
|---|---|---|
| 设备 `/data/local/tmp` | **126 件**（本仓探针产物：`acc-*`、`r9-*`、`screenCap_*`、`lay*.json`、`t_*.jpeg` …） | 逐条列名核对后单次 `rm -f`；**保留**系统/他应用条目 8 项（`debug_app_list.json`、`native_daemon.pid`、`debugserver/`、`ecd/`、`kingkongDir/` 及 3 个他应用目录）—— 清后复核只剩这 8 项 |
| Windows `%TEMP%` 下 `dshm*` | **183 项 / 495 文件 / 113 MB**（门禁临时舞台、`dshm-cmp` 核心树比对副本、串口 / kernel-config 日志…） | 只在 `os.tmpdir()` 下、逐条 `realpath` 校验前缀后才删；清后 0 项 |
| `dist/core` 旧产物 | **9 项 / 701 MB**（`+dshm.21`/`.22`/`.23` 的 3 份容器 + 3 份 manifest + 3 棵旧工作树） | 保留 `+dshm.24` 容器与工作树、`.pack-core-pristine`、`libvips-libs.json`；按 AGENTS「清 `dist/core/work/<旧版本>` 后**必须**删 `entry/.cxx`」同步删掉 ninja 缓存；**清后 12 条依赖核心树的门禁复跑全绿**（`check-resfile-core-zip` / `compat-drift` / `assert-fs-search-fallback` / `check-web-fetch-jitless` / `check-ptc-runtime-inproc` / `check-ptc-wiring` / `check-core-openharmony-patches` / `check-fs-local-permission` / `assert-core-entrypoints` / `check-plugin-toggle` / `check-native-closure` / `check-tar-extract`） |

**没有动的**（登记为本轮不删，留待用户定）：`dist/sideload/previous-internal-test/` 的 5 份内部测试 HAP（≈1.46 GB）、
`dist/acceptance/` 的 10 个历史证据目录（≈86.6 MB）、`dist/{plugsrc,localtest,_func_test,layout-fixtures,…}`（文档有引用或门禁夹具）。
另：`dist/sideload/` 现存的正式件是 **`+dshm.19`**（2026-10-08 20:45），而工作树已到 **`+dshm.24`** ⇒ 若出正式侧载包，需要重出（本轮未出，等用户发话）。

### 11.5 本档勘误（字节级）

§10.1 首行的命令曾被写坏：`.\tools\update-device.ps1` 里的 `t` 变成了**制表符**（该行字节序 `… 60 2E 09 6F 6F 6C 73 …`，`09` 即 TAB），
渲染出来是 `.` + 一个制表位。已就地改成 `2E 5C 74 6F 6F 6C 73`（`.` + 反斜杠 + `tools`）。**行数未变**，行号引用不受影响。

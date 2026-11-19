# 158 release 侧载包 / AGC 上架包出齐 +「内存又炸了」定性（设备系统进程 `virus_protection_executor` 的 OOM 风暴 · 本仓零泄漏证据）

## 结论

本轮两件事：

1. **出包**：`release` 侧载件（release 构建 + 调试签名，可 `hdc install -r` 覆盖安装）、
   AGC 上架件（`.app`，发布证书）、以及同批发布签名的 HAP（发布证书，**不能装机**，
   留档用）三件全部出齐并逐件复核（大小 / sha256 / 权限面恒 8 条 / `.apk` 条目 0 /
   `verify-app success`）。侧载件已在真机覆盖安装并冷启动跑通（见 §3）。
2. **「内存又炸了」的定性**：本轮 19:11 宿主停跳那次，现场与 `docs/156` 上午那次**同族** ——
   设备系统进程 `virus_protection_executor` 进入 **RSS 16 GB + Swap 26.5 GB 的
   OOM → 被杀 → 秒级重启 → 再涨** 循环，把整机压死；App 侧**没有发现新增泄漏证据**
   （宿主 RSS 历史 690–990 MB，日志只有系统内存压力的传导链：
   `MEMORY_PRESSURE_LEVEL_CRITICAL` → `RenderExited exitSig:9` → 事件循环停摆）。
   19:22 之后风暴**自行消退**（`MemAvailable` 回到 18.5 GB / `SwapFree` 51.8 GB、
   executor 进程消失），19:24 用户解锁后冷启动复测干净通过（见 §5）。
   ⇒ 属于设备侧周期性问题，**本仓无待修项**。

## 1. 三件产物（实读复核）

版本面：`versionName=1.1.2` / `versionCode=1010002` /
`coreVersion=0.2.1-alpha.2+dshm.46` / `minAPIVersion=60101024` /
`targetAPIVersion=260000026` / `deviceTypes=phone,tablet,2in1` /
权限恒 **8 条** / `.apk` 条目 **0**。

| 产物 | 大小（B） | sha256 | 用途 / 安装口径 |
|---|---:|---|---|
| `dist\sideload\DSHM-1.1.2-core0.2.1-alpha.2+dshm.46-arm64-signed.hap` | 403,568,279 | `32B1B04B017E78DD3ADD859FC4689290CA40CBB596DA80E705A363755DCA7B3B` | **侧载**：release 构建 + 调试签名 ⇒ `hdc install -r` 覆盖安装（不动 el2 用户数据） |
| `dist\release-test\DSHM-1.1.2-core0.2.1-alpha.2+dshm.46-arm64-release-signed.app` | 196,251,853 | `A0F6A9D9DE2DACAE6F7E13CA7891440978D342F208B59FCEDC2829910FA2466C` | **AGC 上传用**（`.app` 容器 3 条目：`entry-default.hap` + `pack.info` + `pac.json`；0 个 apk 条目） |
| `dist\release-test\DSHM-1.1.2-core0.2.1-alpha.2+dshm.46-arm64-release-signed.hap` | 403,568,156 | `DACB588B2D3F327BFC09C584F97E7D9D172EF405A869D19F7AEF4F26530B694D` | 发布证书件，**不能装机**（发布 profile 无 UDID ⇒ 设备侧 `9568322`，见 `docs/145`），留档 / 送审对照 |

发布签名复核：`verify-app success`；profile `type=release`；
`allowed-acls=ALLOW_EXTERNAL_NATIVE_CODE,FILE_ACCESS_PERSIST`（2 条）；
`uuid=0bbda76e-e5dd-46f5-9b93-3cda1d87ac84`。
侧载件 `verify-app success`，内嵌 profile `type=debug`（allowed-acls 5 条、含 4 个 UDID）。

### 构建 / 签名口径（重建命令）

```powershell
$dev='D:\Program Files\Huawei\DevEco Studio'
$env:JAVA_HOME="$dev\jbr"; $env:DEVECO_SDK_HOME="$dev\sdk"; $env:DEVECO_CLI_CLT_PATH="$dev\tools"; $env:PATH="$env:JAVA_HOME\bin;$dev\tools\node;$env:PATH"
& "$dev\tools\node\node.exe" "$dev\tools\hvigor\bin\hvigorw.js" assembleHap --mode module -p product=default -p buildMode=release --no-daemon
& "$dev\tools\node\node.exe" "$dev\tools\hvigor\bin\hvigorw.js" assembleApp -p product=default -p buildMode=release --no-daemon
.\tools\sign-release-hap.ps1 -InFile 'build\outputs\default\desktop.ohos.arm64-default-unsigned.app' -OutFile 'dist\release-test\<名>.app' -NoteFile 'D:\DSHM-signing-backup\release-20261010\新建文本文档.txt'
```

注：`D:\desktop\release\新建文本文档.txt` 已不在原位，口令备注**只有备份份可用**
（`D:\DSHM-signing-backup\release-20261010\`；`passwd:` 行 10 字符；
`alias:ohosdsh` 那行是旧值，脚本默认别名已订正为 `ohosdshm`）。

### 出包前预检（全绿）

- `node tools/assert-resfile-sync.mjs`：14 件 resfile 同步；
- `node tools/check-permission-surface.mjs`：恒 8 条；
- `node tools/check-resfile-core-zip.mjs`：`+dshm.46` 容器与工作树逐字节同源；
- 全仓无 `.apk` 文件 / 目录；resfile 20 个 `.tar.gz`（`docs/148` 口径）。

## 2. 真机安装（PC 2in1 `86E0226429000417`）

- `hdc install -r` 成功（15.9 s，**未 uninstall**）；`bm dump`：`1010002` / `1.1.2` / `debug=false`。
- `force-stop + aa start` 冷启动正常，boot pid 43796（19:09:31）。
- home 指纹装前 = 装后（files=16 / dirs=10 / 236,272 KB）⇒ 覆盖安装零数据损失。
- `dsh/cores` = `0.2.1-alpha.2+dshm.46`；无本包 faultlog。

## 3. release 档功能核对（真机读数）

| 项 | 读数 | 备注 |
|---|---|---|
| `host-ready.json` | 新 token / `workspace=~/Download/com.dshm.dshclient` | python 桥 `ready` / `stdlib=true` / selftest `stdout=2` |
| 工作区授权跨启动恢复 | `diag-folder-grants`：`restore 1/1 已启用：~/harness=ok` | `docs/157` 的修复在 **release 档**同样成立 |
| guest VM 终端 | `dshm-vm-bash` 接管；VM 起于 19:10:14，QGA 就绪 +4941 ms；`终端会话已建立（#1 /dev/hvc0…shell pid=78）`；后续 guest 命令 rc=0 | 回答 `docs/156` 的「未做：PC 档 release（8 权限）档的 VM 可用性」 |
| exec 探测 | `rg/ash/bash/redirection=fail(EPERM)` | release 档应用域降级的既有边界（`docs/140`/`docs/154`），非新伤 |

## 4.「内存又炸了」现场与定性（19:11–19:23）

### 4.1 App 侧：系统内存压力的**传导链**（不是源头）

`dshm-hb.log` 心跳止于 `HB 108 / cpu=4077`（19:11:25.579Z）；
`node-output.log` 死前现场（同一时刻）：

```
NWebImpl::NotifyMemoryLevel MEMORY_PRESSURE_LEVEL_CRITICAL
RenderExited pid: 44160 exitSig: 9 exitReason: process was killed
SYNC-WARN 508ms readdirSync …/dsh/home/install-queue
LOOP-GAP 9246ms（第 105 拍）
SYNC-COUNT 同步调用总耗时 1113ms：readdirSync×81=592ms ⏐ spawnSync×6=192ms ⏐ …
```

⇒ 现场是「系统内存压力 → ArkWeb 渲染进程被 SIGKILL → 事件循环被拖停」，
宿主 RSS 历史读数 690–990 MB（`docs/156`/`docs/157` + 本轮 VmHWM 采样），
**没有失控爬升**。

### 4.2 设备侧真凶：`virus_protection_executor` 的 OOM 风暴

19:14 首轮读数（`hdc shell`）：

| 读数 | 值 |
|---|---|
| `MemTotal` | 24.4 GB |
| `MemFree` / `MemAvailable` | **67.9 MB / 62.5 MB** |
| `SwapTotal` / `SwapFree` | 50 GB / **6.98 GB**（≈43 GB swap 已被吃光） |
| `ps` | `virus_protection_executor` PID 54754 **RSS 16 GB / %MEM 68.1%** |

约 1 分钟后再读，**PID 已换**：56995 → 59648 → 60787 → 63692 —— 即该进程在
**OOM 被杀 → 秒级重启 → 又涨到十几 GB** 的循环里。
`/proc/<pid>/status` 实读：`VmRSS 15,884,664 kB` / `VmSwap 26,534,700 kB` / `Threads 10`。

`hilog`（memmgrservice）：

```
CalcSystemMemoryLevel The current memory is 214016 < 614400, launch taskMgr!
LowMemoryKillSystemAbilityProc idleProcInfos from samgr is empty
[OHSW].[VmManager] [LowMemoryPause] current vm status is not running
19:13:10 foundation EcologicalRule … blocking app start due to low memory
```

### 4.3 消退与对照

- 19:22 之后 `virus_protection_executor` 进程**不再出现**（只剩常驻的
  `virus_protection_service`，CPU 占比正常）；`MemAvailable` 回到 **18.5 GB**、
  `SwapFree` 回 **51.8 GB**（19:23:15 实读：`MemFree 17,264,584 kB` /
  `MemAvailable 18,534,400 kB` / `SwapFree 51,779,248 kB`）。
- 与 `docs/156` 记录的 10-14 上午那次（`virus_protection_executor` RSS 16.5 GB
  OOM 循环）**同族** ⇒ 设备侧周期性风暴，非本仓可修。
- `hilog -z 400/800` 复核：无新的 memmgr LowMemory 击杀；`ERI250 failed` 行
  归属 uid `1096` / `7102`，与本包 uid `20020303` 无关（别的应用起停噪声）。

## 5. 风暴消退后的冷启动复测（19:24，用户解锁后）

锁屏 + 开发者模式下 `aa start` 被平台拒绝（`10106102`，禁止远端拉起），
用户 19:24 解锁后立即复测：

| 项 | 读数 |
|---|---|
| `aa start` | `start ability successfully`；主进程 pid **2985**、`:entry:BackGroundAbility` pid 3172 |
| 启动 | `BOOT_70_HTTP_READY GET / → HTTP 401（89ms）（+3362ms）` |
| 异常 | `uncaughtException` **0**；`LOOP-GAP` / `SYNC-COUNT` **0** |
| 心跳 | `HB 14…19` 每秒一拍，cpu 平走（977→1060） |
| `host-ready.json` | 新 token（pid 2985，`startedAt 11:24:37.126Z`） |
| 工作区授权 | `11:24:33.754Z restore 1/1 已启用：~/harness=ok` |
| 宿主内存 | `VmRSS 977,804 kB` / `VmHWM 1,151,096 kB` / Threads 76（渲染进程 3453/3495/3498 另计） |

⇒ 风暴过后一键冷启动即恢复，工作区授权、核心解出（`+dshm.46`）全部正常。

## 6. 未做 / 待办

- **平板 / 手机档**用本批产物复验（本轮真机只有 PC 2in1）。
- 设备侧对 `virus_protection_executor` 风暴做长期观察（非本仓可控；
  如复发影响使用，建议按华为设备侧反馈渠道上报，附本档 §4 读数）。

## 7. 红线遵守（本轮）

- **未执行任何 uninstall**（只用 `hdc install -r` / `aa start` / 只读采样）；
- 未动 `C:\Users\Sol\.ohos`、`D:\DSHM-signing-backup\`、`D:\desktop\release\` 任何文件；
- 权限面恒 8 条，未新增 / 未写回任何受限权限条目；
- 全仓（含产物）`.apk` 文件与归档条目均为 0；
- 未裸跑 `tools/pack-core.mjs`、未跑 `tools/place-toolchain.mjs`（出包四坑）。

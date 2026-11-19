# 413 终端分档：只有 PC / Edge / Pro Max 有原生终端

**口径（用户 2026-11-12 最终拍板）**

| 设备 | 终端路线 | 可用 shell |
|---|---|---|
| PC / 2in1 / MateBook | 原生 PTY | sh / zsh / bash |
| MatePad Edge（`QXS-*`）、MatePad Pro Max | 原生 PTY | sh / zsh / bash |
| **其余所有平板**（含 MatePad Pro `MRO-W00` 等）与手机 | **guest VM** | 无原生终端 |

判据只有两路：`DeviceFacts` 的型号族白名单 `EDGE_FAMILY_TOKENS = ['QXS']`，以及市场名 `MatePad Edge` / `PROMAX`+`MATEPAD` 分词。`MRX/MRR/MRD/MRO/DRA` 这五个型号族**不进白名单**。

**事故与根因（`MRO-W00` 真机，2026-11-12）**

终端点开即报 `终端错误：subprocess-local: command "/bin/sh" is not an executable file`。日志显示：

- `DSHM_DEVICE_FORM=desktop`、`DSHM_DEVICE_FAMILY=MRO` ⇒ 命中当时含 6 个 token 的型号族白名单；
- 该机 `hostDomain=o:r:normal_hap:s0`、`realShell=no`、`toybox-exec-sh rc126`、`libs-exec EACCES`、`forkpty` 失败 —— 这是平板/手机类设备的**正常读数**（`docs/145` §3.3 手机 release 包同为此值），不是权限异常；
- 判成 desktop 后 `nativeTerminalOnly=true` ⇒ `RuntimePort` 写 `DSHM_VM_BASH=off` + `DSHM_BASH_EXECUTABLE=/usr/bin/zsh` ⇒ `dshm-vm-bash` 的 `terminalTakeoverEnabled()` 恒 false ⇒ **VM 兜底也被关死**；
- 结果：既无原生 shell 也无 VM，终端必然失败，且报的是核心通用文案。

`docs/379` §3 在 2026-11-08 已记录同一口径与同一后果（"终端也被切到宿主原生 PTY 路线"），但代码与门禁一直停在 6 token 版本，属于口径未落地。

**改动**

| 位置 | 改动 |
|---|---|
| `platform/src/main/ets/system/DeviceFacts.ets` | `EDGE_FAMILY_TOKENS` 由 `['QXS','MRX','MRR','MRD','MRO','DRA']` 收窄为 `['QXS']`；Pro Max 继续由 `PROMAX`+`MATEPAD` 市场名联合判定 |
| `tools/check-edge-desktop-policy.mjs` | A5 改为反向断言：`QXS` 必须在、`MRX/MRR/MRD/MRO/DRA` **必须不在**；新增 `--self-test`（3 个变异体：加回 MRO / 加回另外四个 / 去掉 QXS，全部必须判红） |
| `AGENTS.md` §3 | 写入终端分档口径与"不得加回 MR 系列"的约束 |

**原生终端的三种 shell**：核心 `dsh-api-terminal-controller` 的 `shellCandidates` 默认 `['zsh','bash','fish','pwsh','powershell','cmd']`，默认 shell 取 `terminalEnvironment().defaultShell`（端侧 `SHELL=/bin/sh`）⇒ 桌面档列出 `sh`（默认）+ `zsh` + `bash`，与口径一致，无需自有配置。

**验证边界**：本机无 hdc，改动的真机效果（`MRO-W00` 回到 tablet 档后终端走 VM）需装机确认；离线证据为门禁 + 全量回归。

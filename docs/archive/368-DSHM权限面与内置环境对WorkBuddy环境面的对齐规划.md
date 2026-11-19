# 368 · DSHM 权限面 / 内置环境 ↔ WorkBuddy 内置环境 对照与对齐规划

> 日期：2026-11-05 ｜ 性质：**只读梳理 + 规划，未执行任何环境、权限或配置变更**
> 对象：本机 WorkBuddy（`com.tencent.workbuddy` 5.6.4/1000564）实测环境 ↔ 本仓 DSHM（`com.dshm.dshclient` 1.1.7/1010014，核心 `0.2.2-rc.1+dshm.1`）
> 证据来源：`tools/check-permission-surface.mjs` 的 `EXPECTED`/`PHONE_EXPECTED`、`entry|phone/src/main/module.json5`、`signing/**/*.p7b` 与 `.certs/**/*.p7b` 的 `allowed-acls`、`/data/storage/el1/bundle/electron.hap` 内 `module.json` 与 `libs/` 清单、本机 PATH 与本机二进制实测

> **2026-11-05 口径（用户拍板，优先级高于本文任何建议）**
> ① `kernel.ALLOW_WRITABLE_CODE_MEMORY` **后续再申请，当前不接入** ⇒ A5（解 `--jitless`）**挂起**，本轮及可预见的一段时间内不排期；
> ② **「没有的权限就不要接入」**——任何能力设计都不得依赖尚未获批的权限，也不得"先写代码、等权限批了再开"；权限面之外只做**降级实现**（现成的 jitless 垫片链就是范例），不做"等权限"的分支；
> ③ Node **对齐到 24.13**（主动对齐，非 dsh 门槛驱动）；
> ④ beta 包只为本地测试、用独立 App ID，ACL 2 条是**既有约束**（`build-beta.mjs` 自己断言），上架包（AGC 签名）**7 条齐全**。

---

## 0. 口径与结论

**对齐方向（我的理解，需你确认 C1）**：把 **WorkBuddy 的内置环境能力**当作目标面，把 **DSHM 现有 17 条权限面**当作**硬边界**——凡是不新增权限就能补齐的能力尽量补齐；必须新增权限才能拿到的能力，**不擅自做**，也不预留"等权限"的分支。

**一句话结论**：

- **权限面**不是"谁多谁少"，而是**方向不同**：WorkBuddy 走"全盘 + 系统集成"路线（30 条，含 `ACCESS_USER_FULL_DISK`、`CAMERA`、`LOCATION*`、`PRINT`、`DISTRIBUTED_DATASYNC`、`kernel.ALLOW_WRITABLE_CODE_MEMORY`）；DSHM 走"沙箱内自足工具链"路线（17 条，7 条 ACL，**永不申请全盘**，`READ_WRITE_USER_FILE`/`ACCESS_USER_FULL_DISK` 是仓里的 RETIRED 词）。
- **内置环境**在工具面上 DSHM 已基本对齐甚至更宽（PTC/jobs/goal/ralph/schedule/terminal/guest VM）；**差距三件**：① 原生 ripgrep（WB 有、DSHM 纯 JS）；② JIT/WASM（WB 有、DSHM `--jitless`，**已挂起不追**）；③ Node 版本（24.9.0 ↔ 24.13.0，**主动对齐**）。
- 两条路线各有代价：DSHM 的"自足"靠**更重的随包**（自带 CPython/git/gh/tmux/bash/ffmpeg/qemu），WorkBuddy 靠**更宽的权限**。**不应互相吞并**，只在交集上补能力。

---

## 1. 现状梳理

### 1.1 DSHM 权限面（entry 17 / phone 9，逐位钉死）

判据唯一处：`tools/check-permission-surface.mjs` 的 `EXPECTED`（entry）与 `PHONE_EXPECTED`（phone）——条数、**顺序**、`reason` 任一不同即红；`--self-test` 用变异体自证有牙。

**entry 17 条**：

| 组 | 条目 | 性质 | 用途 |
|---|---|---|---|
| 网络 | `INTERNET`、`GET_NETWORK_INFO` | normal | 宿主/模型通道 |
| 后台 | `KEEP_BACKGROUND_RUNNING`、`RUNNING_LOCK`、`PREPARE_APP_TERMINATE` | normal | Host 常驻、退出前排空 |
| 原生执行 | `ALLOW_EXTERNAL_NATIVE_CODE`、`CUSTOM_SANDBOX`、`kernel.IGNORE_LIBRARY_VALIDATION`、`kernel.EXEMPT_ANONYMOUS_EXECUTABLE_MEMORY` | **ACL(4)** | 随包 ELF、沙箱域、库校验豁免、匿名可执行内存 |
| 数据 | `STORE_PERSISTENT_DATA`、`FILE_ACCESS_PERSIST` | normal/ACL | 持久化、目录授权留存 |
| 目录 | `READ_WRITE_DOCUMENTS_DIRECTORY`、`READ_WRITE_DOWNLOAD_DIRECTORY`、`READ_WRITE_DESKTOP_DIRECTORY` | **ACL(3)** | 用户三目录（**不含全盘**） |
| 交互 | `READ_PASTEBOARD`、`MICROPHONE`、`VIBRATE` | normal | 粘贴板读、语音、振动 |

**phone 9 条**：`INTERNET`、`KEEP_BACKGROUND_RUNNING`、`FILE_ACCESS_PERSIST`、`STORE_PERSISTENT_DATA`、`VIBRATE`、`READ_PASTEBOARD`、`MICROPHONE`、`GET_NETWORK_INFO`、`RUNNING_LOCK`。手持档故意没有原生 PTY/随包 ELF 的宿主域路线（终端走 guest VM）。

**ACL 实况（本机从 p7b 实读）**：

| profile | type | bundle | `allowed-acls` | 用途 |
|---|---|---|---:|---|
| `.certs/multihap-20261024/DSHM-multihap-release-20261024{,-newacl}.p7b` | release | `com.dshm.dshclient` | **7** | **AGC / 上架包** |
| `.certs/multihap-20261024/DSHM-multihap-debug-pc-phone-20261024.p7b` | debug | `com.dshm.dshclient` | **7** | 正式调试 |
| `signing/debug/default_desktop.ohos.arm64_H6ERY….p7b` | debug | `com.dshm.dshmbeta` | **2** | 本地测试 beta 包 |

7 条 = 3 个 `READ_WRITE_*_DIRECTORY` + `CUSTOM_SANDBOX` + `READ_PASTEBOARD` + `ALLOW_EXTERNAL_NATIVE_CODE` + `FILE_ACCESS_PERSIST`。

> **beta 只有 2 条 ACL 是既有约束，不是缺陷**：beta 用独立 App ID（`com.dshm.dshmbeta`），**独立 bundle 沿用不了正式 App ID 的 ACL**；`tools/build-beta.mjs:155-172` 把"beta Profile 的 `allowed-acls` 必须恰好等于 `BETA_ACLS`"写成断言，并在 `--existing-beta-upgrade` 时给明确告警。
>
> **由此产生的是一条"测试覆盖边界"**：beta 通道**验不了** ACL 相关能力——`CUSTOM_SANDBOX`（沙箱域降档会连带终端/工作区文件/ELF 执行，见 `docs/143`/`144`）、三个用户目录、剪贴板。这些只能在**正式签名的包**上验，所以 beta 通过的结论按"功能面/UI 面"读。

**三条铁律**：① 不新增未审批的 `system_basic`/`system_core`（无审批声明了也拿不到，且设备侧 `PERMISSION_ACL_RULE` 整包拒装）；② 不声明**没有运行时消费点**的权限（`DISTRIBUTED_DATASYNC` 就这么撤的，`docs/249`）；③ 不把"删权限"当排障手段（`docs/143`/`144`/`215`/`222`）。

**已废/未获批词表**：`READ_WRITE_USER_FILE`、`ACCESS_USER_FULL_DISK`（门禁 `RETIRED`，全仓文本出现即红）；`DISTRIBUTED_DATASYNC`（已撤）。

### 1.2 DSHM 内置环境

| 层 | 内容（实测/实读） |
|---|---|
| Node 运行时 | 自建 **libnode 24.9.0** `155,413,312 B` / sha `dfe298d0…`（16 槽 io_uring 已字节中性化 + 自签，`docs/366`）+ `nodecli` 启动器（52,120 B） |
| Python 运行时 | **CPython 3.12.14 (musl)**（27.7 MB，含 `pip 26.2.1`、`ensurepip`、`venv`）+ HSP 内 `libpython3.12.so.1.0`（20.4 MB）供进程内桥 |
| 命令面 | `bash`(alpine)、`git 2.47.3`、`gh 2.72.0`、`tmux`、`ffmpeg 9.0.1`(28 库)、`npm`(JS)、`pnpm`(JS)、`busybox` |
| 虚拟化 | `qemu-system-aarch64`(34.8 MB) + `kernel_aarch64` + `rootfs_aarch64.qcow2` + 13 组 guest 包（含 `dropbear` ssh/scp/dbclient） |
| dsh 核心树 | `0.2.2-rc.1+dshm.1`，341 个 `@deepseek-ai/*` 包；工具面 bash/fs/fs-search/web/terminal/todo/subagent/skill/schedule/ask-user/present/str-replace-editor/PTC/jobs/goal/ralph/pwsh |
| 原生模块 | `koffi`(FFI, openharmony_arm64)、`node-pty`、`sharp`(openharmony_arm64)；**无** `better-sqlite3`、**无** ripgrep |
| 执行域 | `CUSTOM_SANDBOX` → `u:r:develop_tools_debug_hap:s0`；`subprocess` 与 `sandbox` 在 profile 里已启用 |
| 运行模式 | **`--jitless`**（OHOS 不允许 W^X）：`WebAssembly === undefined` ⇒ `fetch`/`undici`/`worker`/WASM 全靠 6 个纯 JS 垫片（`fetch-shim`、`undici-shim`、`internal-undici-shim`、`worker-bootstrap`、`jitless-env`、PTC erasable-TS 擦除器） |
| 文件面 | 3 个用户目录权限 + `FILE_ACCESS_PERSIST` + picker；工作区/家目录在 el2 `files/dsh/home` |
| 技能面 | `ohos-skills/` 5 篇内建指导 + `dsh-skill-filesystem`（支持**目录 bundle 与扁平 Markdown**） |

**已知硬约束（实测）**：`kernel.*` 两条虽已授予，内核仍拒 `mmap(RWX)`/`mprotect(RX)` 与从应用 files 复制出的 `.so` dlopen（`docs/222`）——**但那是在没有 `ALLOW_WRITABLE_CODE_MEMORY` 的前提下测的**，故不能据此断定"有权限也没用"；当前口径是**不申请、不接入**，继续走 jitless。

### 1.3 WorkBuddy 权限面（本机实读 `electron.hap!/module.json`）

`com.tencent.workbuddy` 5.6.4 / 1000564 ｜ module `electron` ｜ `deviceTypes = ['2in1','tablet']`（**无 phone**）｜ min/target API = `6.1.1(24)` ｜ **`requestPermissions` 30 条**：

`READ_LOCAL_DEVICE_NAME`、`DISTRIBUTED_DATASYNC`、**`ACCESS_USER_FULL_DISK`**、`GET_NETWORK_INFO`、`CUSTOM_SANDBOX`、`kernel.LOAD_INDEPENDENT_LIBRARY`、`kernel.EXEMPT_ANONYMOUS_EXECUTABLE_MEMORY`、`ALLOW_EXTERNAL_NATIVE_CODE`、`kernel.IGNORE_LIBRARY_VALIDATION`、`INTERNET`、`ACCESS_CERT_MANAGER`、`RUNNING_LOCK`、`PRINT`、`PREPARE_APP_TERMINATE`、`ACCESS_BIOMETRIC`、`FILE_ACCESS_PERSIST`、`PRIVACY_WINDOW`、`WINDOW_TOPMOST`、**`kernel.ALLOW_WRITABLE_CODE_MEMORY`**、`GYROSCOPE`、`ACCELEROMETER`、`GET_FILE_ICON`、`READ_PASTEBOARD`、`LOCATION`、`APPROXIMATELY_LOCATION`、`LOCATION_IN_BACKGROUND`、`MICROPHONE`、`CAMERA`、`ACCESS_BLUETOOTH`、`CUSTOM_SCREEN_CAPTURE`

### 1.4 WorkBuddy 内置环境（本机实测）

| 层 | 内容 |
|---|---|
| 包体 | `electron.hap` **1,177,917,856 B**（1.18 GB） |
| 随包 libs | `bash`(52 项)、`node`(**2108 项**，含 npm/npx/corepack)、`python`(**844 项**)、`ripgrep.node`、`node-pty.node` + `pty.node`、`better_sqlite3.node`、`job-object.node`、`os-bridge.*`(4 平台)、`binary-sign-tool`、`editor_sdk`、`libelectron.so`、`libc++*.so`、`libffmpeg.so` |
| PATH 组成 | `safe-bin` shim（`rm`/`rmdir`/`unlink` 被接管）→ 随包 node → 随包 python → `~/.workbuddy/binaries/{node,python envs}` → 插件 `bin/` → `/data/app/bin`、`/data/service/hnp/bin`、`/system/bin` |
| 运行时实测 | `node v24.13.0`：**`Function()` 与 `WebAssembly.Module` 均可用（JIT 在）**；`python 3.12.9`：`pip 24.3.1`、`venv`、`ssl/sqlite3/zlib/ctypes` 全可用 |
| 二进制实测 | ✔ `bash sh git curl wget tar zip unzip ssh ps npm npx corepack brew deveco`；✘ `rg`(PATH 无)、`ffmpeg/ffprobe`(CLI 无)、`gcc clang make cmake java pnpm tmux gh jq sqlite3 sshd` |
| 平台约束 | `AF_UNIX` bind `EPERM`（UDS 被禁）；`rm` 经 shim 静默失败；无 `hdc` 服务端 |

### 1.5 对照口径（谁向谁对齐）

- **目标面** = WorkBuddy 的"环境能力"；**边界** = DSHM 现有 17 条权限面（`AGENTS.md` 铁律）。边界外的差距一律"保留"，**不通过加权限消除，也不预留等权限的分支**。
- **不动的东西**：真机 el2 用户数据、签名物料、正式包名/身份、`.certs/**`。

---

## 2. 差异清单

标记：**应对齐** = 边界内可补齐；**保留** = 边界外明确不对齐；**领先** = DSHM 已优于 WorkBuddy。

### 2.1 权限面差异（集合运算）

| # | 项 | DSHM entry | WorkBuddy | 结论 |
|---|---|---|---|---|
| P1 | 交集（11 条） | — | — | `ALLOW_EXTERNAL_NATIVE_CODE`、`CUSTOM_SANDBOX`、`FILE_ACCESS_PERSIST`、`GET_NETWORK_INFO`、`INTERNET`、`MICROPHONE`、`PREPARE_APP_TERMINATE`、`READ_PASTEBOARD`、`RUNNING_LOCK`、`kernel.EXEMPT_ANONYMOUS_EXECUTABLE_MEMORY`、`kernel.IGNORE_LIBRARY_VALIDATION` |
| P2 | 仅 DSHM（6） | `KEEP_BACKGROUND_RUNNING`、3×`READ_WRITE_*_DIRECTORY`、`STORE_PERSISTENT_DATA`、`VIBRATE` | — | WorkBuddy 不需要（常驻策略/实现路径不同） |
| P3 | 仅 WorkBuddy（19） | — | 全盘、相机、定位×3、蓝牙、打印、生物识别、证书、截屏、置顶、隐私窗、传感器×2、文件图标、设备名、分布式同步、**W^X JIT**、独立库加载 | 见下逐项 |
| P4 | 全盘访问 | **RETIRED（永不申请）** | `ACCESS_USER_FULL_DISK` | **保留**（`docs/142`/`161`） |
| P5 | 分布式同步 | 已撤（无消费点，`docs/249`） | `DISTRIBUTED_DATASYNC` | **保留**（先实现后声明） |
| P6 | JIT 可写码页 | **未声明、当前不申请** | `kernel.ALLOW_WRITABLE_CODE_MEMORY` | **保留**（后续再申请，见 §3.3） |
| P7 | 系统集成 12 项 | 无 | 有 | **保留**（定位不同） |
| P8 | 独立库加载 | 无（靠 `IGNORE_LIBRARY_VALIDATION`） | `kernel.LOAD_INDEPENDENT_LIBRARY` | 观察项，无消费场景 |

### 2.2 环境能力差异

| # | 维度 | DSHM | WorkBuddy | 差异方向 | 判定 |
|---|---|---|---|---|---|
| D1 | **JIT / WASM** | 无（`--jitless`，`WebAssembly===undefined`） | **有**（实测通过） | WB 强 | **保留**（不申请权限、不接入） |
| D2 | Node 版本 | 24.9.0（自建、已中性化自签） | 24.13.0 | WB 新 4 个 minor | **应对齐**（主动对齐，见 A4） |
| D3 | 检索 | 纯 JS（`dsh-tool-fs-search` + 79 断言回退） | 原生 `ripgrep.node` | WB 快一个量级 | **应对齐**（A2） |
| D4 | 原生 FFI | `koffi`(openharmony_arm64) | 无（N-API 预编译） | DSHM 强 | 领先 |
| D5 | PTY | 自建 `libpty` + `node-pty` + `tmux` | `node-pty.node`/`pty.node` | 平 | 无需动 |
| D6 | Python | 3.12.14 + **pip 26.2.1** + venv | 3.12.9 + pip 24.3.1 + venv | DSHM 略新 | 领先 |
| D7 | ffmpeg | **CLI + 28 库（9.0.1）** | 仅 `libffmpeg.so` | DSHM 强 | 领先 |
| D8 | git/gh/tmux | 2.47.3 / 2.72.0 / tmux 随包 | git(hnp)、无 gh、无 tmux | DSHM 强 | 领先 |
| D9 | ssh 客户端 | 仅 guest VM 内 `dropbear` | 系统 `/usr/bin/ssh` | WB 强 | 应对齐（A6，低优先） |
| D10 | sqlite | 无原生（会话 JSONL） | `better_sqlite3.node` | WB 强 | 可选（A7） |
| D11 | 编译器/构建 | 无 gcc/clang/make/cmake | 同无 | 平 | 不新增 |
| D12 | java | 无 | 无 | 平 | 不新增（验签因此做不了） |
| D13 | 技能面 | `ohos-skills` 5 篇 + 目录 bundle/扁平 MD | 40+ 技能（含连接器/市场） | WB 生态大 | 部分应对齐（A3，格式已兼容） |
| D14 | 工具语义 | bash/fs/fs-search/web/terminal/todo/subagent/skill/schedule/ask-user/present/PTC | Bash/Read/Write/Edit/Grep/Glob/WebFetch/WebSearch/Task/Agent/Skill/AskUser | 一一可映射，DSHM 更宽 | A8 登记 |
| D15 | API 级别 | min `6.1.0(23)` / target `26.0.0` | min/target `6.1.1(24)` | DSHM 更新 | 领先 |
| D16 | 设备档 | phone + tablet + 2in1 | tablet + 2in1（无 phone） | DSHM 更宽 | 不可比 |
| D17 | 包体策略 | 自足工具链（容器 108 MB / 包 608 MB） | 单 hap 1.18 GB | 都重 | 无需动 |
| D18 | 平台硬约束 | UDS 禁、W^X 禁、无 hdc | 同（同一台机器） | 相同 | 记录，不对齐 |
| D19 | **beta / AGC 包能力不等价** | beta 独立 App ID ⇒ ACL 2 条；**上架包 7 条齐全** | 不适用 | 设计使然 | **不在对齐范围**；作"测试覆盖边界"登记 |

---

## 3. 对齐规划

### 3.1 对齐范围

- **L1 运行时与二进制面**：检索（原生 rg）、宿主 ssh、Node 24.13、（可选）sqlite。
- **L2 工具与技能面**：工具语义最小集登记、技能根与可移植技能、平台约束单页。
- **明确排除**：JIT/WASM（权限未申请）、全盘访问、12 项系统集成、`DISTRIBUTED_DATASYNC`、编译器/java。

### 3.2 逐项调整点

> 「实际调整对象」是可核对落点；未列落点的项视为**不该做**。

| # | 目标 | 实际调整对象 | 类型 | 优先级 | 验收标准 | 预期影响 |
|---|---|---|---|---|---|---|
| **A2** | 检索对齐（原生 rg） | `hostcore/core-recipe.json`（overrides/native）、`tools/place-toolchain.mjs`、`hostruntime/src/main/resources/resfile/toolchain/rg/`、`tools/gen-oss-notices.mjs`、`tools/assert-fs-search-fallback.mjs`（保留回退臂） | 随包二进制 | **P0** | 10k 文件全量 grep 基准 ≤ 纯 JS 的 1/5 耗时；无 rg 时回退 79/79 仍过；OSS 同步 | 包体 +5 MB 级；`Grep/Glob` 语义与 WB 一致 |
| **A3** | 技能面可移植 | `hostcore/profile/ondevice/cordis.patch.yml`（`skill-filesystem` 根）、`resfile/ohos-skills/`、`docs/` 清单 | 配置+内容 | **P0** | dsh 能列出 ≥5 技能并加载；`ohos-skills` 5 篇不丢；manifest 与 WB `SKILL.md` 同构 | 技能可跨端复用 |
| **A4** | Node 24.9.0 → **24.13.0**（与 WB 同版） | `hostruntime/libs/arm64-v8a/libnode.so.137`（重编 + 16 槽中性化 + 重签）、`tools/patch-libnode-io-uring.mjs`（`SHIPPED`/`SYSCALL_STUB`/`SIBLING_SLOT`/`ANCHORS`/`SITES`）、`tools/check-libnode-io-uring.mjs`、`core-recipe.json`（`+dshm.<n>` +1 强制换树） | 二进制换代 | **P1** | 新件仍定位 **16 槽**（主测 16/0、自检 8/0）；`display-sign` self-sign；`node -v` = 24.13.0；新容器起得来；回归 99/0 | 与 WB 同版、问题可复现；代价是重走 `docs/366` 流程（2–4 h），本机无 hdc 验不了真机 |
| **A6** | 宿主 ssh 客户端 | `resfile/toolchain/dropbear/`（guest 包已有 dbclient/scp）、`tools/place-toolchain.mjs`、`tools/check-guest-pkgs.mjs` | 随包二进制 | **P1** | `dbclient -V` 可执行；私钥目录 600；OSS 补齐 | 远端推拉不绕 VM；包体 +~1 MB |
| **A7** | sqlite（可选） | `core-recipe.json` overrides（`better-sqlite3` 鸿蒙移植或 `node:sqlite`） | 原生模块 | **P2** | 打开/事务/关库三例通过；会话仍默认 JSONL | 收益不确定，先评估 |
| **A8** | 工具语义最小集登记 | `docs/parity-matrix.md` 新增一节 + `tools/check-parity.mjs` 条目 | 文档+门禁 | **P0** | 差异表逐项有"对齐/保留/领先"；`check-parity` 合法 | 防"对齐了没人知道、退化了没人发现" |
| **A9** | 平台约束单页 | `docs/` 一页（UDS 禁、safe-delete 阈值 50、无 hdc/java） | 文档 | **P1** | 两端共用一页结论 | 减少照搬 WB 命令踩坑 |

**已挂起/撤下的两项**：

- ~~**A1** beta ACL 2→7~~ **撤回**：beta 用独立 App ID，独立 bundle 沿用不了正式 App ID 的 ACL；`build-beta.mjs` 自己断言。代价不对等（见 §3.3）。
- ~~**A5** 解除 `--jitless`~~ **挂起**：`ALLOW_WRITABLE_CODE_MEMORY` 后续再申请、当前不接入；按「没有的权限就不要接入」，不预留等权限的分支，现有 jitless 垫片链就是正式实现。

> 优先级：**P0** = 边界内、无权限变更、风险低、收益直接；**P1** = 需重编/需外部配合；**P2** = 可选或收益待评估。

### 3.3 不做清单（明确保留差异）

| 项 | 理由 |
|---|---|
| JIT / WASM（`kernel.ALLOW_WRITABLE_CODE_MEMORY`） | **后续再申请，当前不接入**。理由：① 破 17 条铁律要连带改门禁、`AGENTS.md`、隐私政策与 AGC 声明；② `docs/222` 的"内核仍拒 RWX"是在没有该权限时测的，**能不能用尚无定论**；③ 现在没有能力设计依赖它——jitless 垫片链已稳定跑在 99 条门禁下 |
| beta ACL 补到 7 条（原 A1） | beta 只为本地测试、独立 App ID；沙箱类能力本来就必须在正式签名包上验 |
| `ACCESS_USER_FULL_DISK` / `READ_WRITE_USER_FILE` | RETIRED 词表（`docs/142`/`161`）；替代路径 = picker + `FILE_ACCESS_PERSIST` |
| `DISTRIBUTED_DATASYNC` | 无运行时消费点；铁律"先实现、后声明"（`docs/249`） |
| `CAMERA`/`LOCATION*`/`BLUETOOTH`/`PRINT`/`BIOMETRIC`/`CERT_MANAGER`/`SCREEN_CAPTURE`/`WINDOW_TOPMOST`/`PRIVACY_WINDOW`/`GYROSCOPE`/`ACCELEROMETER`/`GET_FILE_ICON`/`READ_LOCAL_DEVICE_NAME` | 定位不同（DSHM 是 Agent 宿主，不是通用效率套件）；每条都要 ACL 审批 + 隐私政策 |
| 编译器 / java | 两端都没有；随包编译器带来发行合规与体积双负担 |

---

## 4. 影响与风险

| 项 | 影响面 | 等级 | 风险 | 缓解 | 回退 |
|---|---|---|---|---|---|
| A2 ripgrep | 包体、许可证、执行面 | 低-中 | ① OHOS arm64 版 `rg` 需自建（musl 版不能直接 exec，guest 包只给 VM 用）；② 新 native 要走 `sign-bundled-libs` | 先做"无 rg 仍可用"对照臂再上二进制；许可证进 OSS 表 | 删 `toolchain/rg/` 并回退搜索 provider |
| A4 Node 升级 | 核心树 ABI、构建链 | 中-高 | ① 新件的 `syscall@plt` 桩地址与 16 槽位必然变，`ANCHORS`/`SITES` 全要重定位（`docs/365` "23 处候选只有 16 处是真 syscall"的判别必须重做，不能硬编码地址）；② 重签要"先抹 `.codesign` 段 `sh_name`"；③ 本机无 hdc | 复用 `docs/366` 流程；旧 24.9.0 件保留在 `dist/node/`；先把"桩反推 + 16 槽交叉校验"跑通再改随包件 | 换回 24.9.0 预中性化件重签 |
| A6 ssh | 包体、密钥管理 | 低 | 私钥权限过宽 | 走 toolchain 目录约定 + 600 | 删目录 |
| 通用 | 真机数据 | — | 安装/卸载都可能碰 el2 | 只覆盖安装 `-r`；**不卸载**；不动 `signing/`、`.certs/` | — |

**两个前提**：① 本机 hdc 服务端 UDS 绑定被拒（`docs/352`），**A4/A6 的真机验收在本机做不了**，证据只到"离线门禁 + 包结构"；② 沙箱/目录/剪贴板类能力**不在 beta 通道上验**（beta 2 条 ACL）。

---

## 5. 待确认项

| # | 问题 | 选项 | 建议 |
|---|---|---|---|
| **C1** | 对齐方向确认为「DSHM 向 WorkBuddy 补环境能力，权限面为硬边界」？ | ① 按本文口径 ② 反向收紧 WB ③ 只做差异台账 | ① |
| **C2** | ~~是否申请 `ALLOW_WRITABLE_CODE_MEMORY`~~ | **已定：后续再申请，当前不接入**（A5 挂起） | 关闭 |
| **C3** | Node 24.13 **何时做**？ | ① 立刻单独一轮 ② 与 A2/A3 同批 ③ 等下次核心同步 | ①/②（只动 `libnode` + 三个门禁文件，独立做回退面最小） |
| **C3b** | 24.13 **怎么取件**？ | ① 沿用 `docs/366` 自建构建链 ② 取官方 v24.13.0 linux-arm64 再中性化重签 | ② 更快，但须先确认 `DT_NEEDED` 与 24.9 自建件一致（自建件只依赖 `libc.so`） |
| **C4** | ripgrep 走哪条路？ | ① 自建 OHOS arm64 `rg` 随包 ② 挂原生绑定 ③ 继续优化纯 JS | ①（与现有 toolchain 一致，回退面清晰） |
| **C5** | 移植哪些 WB 技能进 DSHM？ | 逐个白名单（排除腾讯专有/连接器类） | 先 3–5 个纯本地技能验链路 |
| **C6** | 接受"沙箱/目录类能力只在正式签名包上验"？ | ① 接受 ② 给 beta App ID 单独申请同组 ACL | ① |
| **C7** | 文件面差异（全盘 vs 三目录）确认保留？ | ① 保留 ② 重评 | ① |
| **C8** | 本规划是否落成 `docs/parity-matrix.md` 一节并进 `check-parity`？ | ① 是 ② 只留本文件 | ① |

---

## 6. 附：只读取数命令（可复核）

```bash
# DSHM 权限面判据
node tools/check-permission-surface.mjs --self-test
# WorkBuddy 权限面（不落地任何文件）
python3 -c "import zipfile,json;m=json.loads(zipfile.ZipFile('/data/storage/el1/bundle/electron.hap').read('module.json'))['module'];print(len(m['requestPermissions']));[print(p['name']) for p in m['requestPermissions']]"
# 两侧 ACL 实况
python3 - <<'PY'
import glob,re
for p in glob.glob('signing/debug/*.p7b')+glob.glob('.certs/**/*.p7b',recursive=True):
    t=open(p,'rb').read().decode('utf-8','ignore')
    m=re.search(r'"allowed-acls"\s*:\s*\[(.*?)\]',t,re.S)
    print(p, len(re.findall(r'"ohos',m.group(1))) if m else '?')
PY
# 本机能力实测
node -e "console.log(process.version, typeof WebAssembly)"
python3 -V && python3 -m pip --version
```

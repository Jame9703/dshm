# DSHM PC 项目交接

> 更新：2026-10-23
>
> 当前角色：PC-only 工程 `com.dshm.dshclient`
>
> 当前版本：`1.1.5 / 1010005`
>
> 当前核心：`0.2.1-rc.2+dshm.84`
>
> 历史快照见 `HANDOFF-2026-10-21-historical.md`；历史专题只用于追溯，
> 当前事实以源码、Profile、交付件、门禁和本文为准。

## 1. 当前结论

本仓库只构建 HarmonyOS `2in1` PC 工程。手机和平板由独立移动端工程承载，
不在本仓构建、签名、上传 AGC 或安装。

当前正式交付：

| 项 | 值 |
|---|---|
| Bundle | `com.dshm.dshclient` |
| AGC App ID | `6917614360926110054` |
| 本机 debug App ID | `6918740027110769940`（仅 DevEco Run） |
| 版本 | `1.1.5 / 1010005` |
| 核心 | `0.2.1-rc.2+dshm.84` |
| min API | `260000026`（HarmonyOS API 26） |
| target API | `260000026`（API 26） |
| deviceTypes | `2in1` |
| 权限 | 11 条：3 ACL + 2 kernel + 6 普通 |
| release Profile ACL | `CUSTOM_SANDBOX` / `ALLOW_EXTERNAL_NATIVE_CODE` / `FILE_ACCESS_PERSIST` |
| APK 相关条目 | 0 |

正式交付文件：

| 文件 | 大小 | SHA-256 |
|---|---:|---|
| `dist/release-test/DSHM-1.1.5-PC-2in1-dshclient-AGC-signed-20261023.app` | 333,077,390 B | `6d17c911d0d62673403edc3ca7ac6ff4836ba77652d7d17cb7c301b279d0b102` |
| `dist/release-test/DSHM-1.1.5-PC-2in1-dshclient-AGC-signed-20261023.hap` | 335,037,239 B | `9b60c28b6b4437b20eab0bb357bdaf10901ff99dcebae4e512729b6ba06e7b39` |

HAP 内层实读：127 个文件条目、`buildMode=release`、`debug=false`、
`versionName=1.1.5`、`versionCode=1010005`、
`minAPIVersion=targetAPIVersion=260000026`。

## 2. 当前权限与设备能力

| 类别 | 条目 |
|---|---|
| ACL | `ALLOW_EXTERNAL_NATIVE_CODE`、`FILE_ACCESS_PERSIST`、`CUSTOM_SANDBOX` |
| 2in1 kernel | `kernel.IGNORE_LIBRARY_VALIDATION`、`kernel.EXEMPT_ANONYMOUS_EXECUTABLE_MEMORY` |
| 普通 | `INTERNET`、`GET_NETWORK_INFO`、`KEEP_BACKGROUND_RUNNING`、`PREPARE_APP_TERMINATE`、`STORE_PERSISTENT_DATA`、`MICROPHONE` |

关键边界：

- `CUSTOM_SANDBOX` 已恢复随包 ELF 的原生执行；PC / 2in1 的 shell、PTY、
  Python、git、rg 全部走宿主原生路径，PC 工程不再包含 guest VM。
- `kernel.EXEMPT_ANONYMOUS_EXECUTABLE_MEMORY` 已声明且被系统授予，但当前设备
  内核的 `mmap(RWX)` / `mprotect(RX)` 仍返回 `EINVAL`。生产 `NodeRuntime`
  因此固定传 `buildHostArgv(..., true)`，Host 继续 `--jitless`。
- `buildHostArgv` 的默认值也固定为 jitless；JIT 只允许通过显式 `false` 的受控探针测试。
- jitless 下 WASM 不存在，`undici`、fetch、worker 的纯 JS 补齐层仍是生产必需路径。
- 当前 release 包中 `ACCESS_USER_FULL_DISK` 尚未获批、不得声明。申请材料见 `docs/223`；
  批准后必须先更新 release Profile 的 `allowed-acls`，再从源码声明。

## 3. 数据与签名红线

- 真机只允许 `hdc install -r`。
- 禁止 `hdc uninstall`、`bm uninstall`、递归删除 `/data/app/el2/**`。
- 禁止删除 `.certs/`、`signing/`、仓库外签名备份、`dist/node/libnode.so.137.orig`
  或当前核心 zip / manifest。
- 签名变化导致覆盖安装失败时，先停止并取得用户确认，不得自行卸载。
- 独立正式目录和备份侧不互相写入。

## 4. 当前架构

```text
ArkUI / ArkWeb
    │ HTTP /api/*, WebSocket /api/remote.mux, 127.0.0.1
    ▼
应用进程内 Node Host
    │ DSH_HOME = <sandbox>/dsh/home
    ▼
核心版本仓库 dsh/cores/<version>
    ├─ 自带插件与 ondevice profile
    ├─ Python worker / PTC 同进程运行时
    ├─ Git / rg / shell / PTY 原生执行
    ├─ 浏览器桥 / 卡片 / 会议 AI
    └─ 原生能力诊断与降级提示
```

Host 只监听回环地址。文件工具、glob/grep 与 publish 另有应用内路径闸门：
允许应用沙箱与 `~`，其余系统区拒为 `FS_PERMISSION_DENIED`。

## 5. 当前验证

2026-10-23 的 1.1.5 邀请测试批次已完成：

- clean 后 `assembleApp` 82/82 任务执行，`.app/.hap` 独立 `verify-app` 通过；
- HAP 内为 `release / debug=false / 1.1.5 / 1010005 / 2in1`；
- 签名证书链与 `.certs/release1012/dshm.cer` 三张证书逐指纹一致；
- 11 条权限面和 release Profile 的 3 条 ACL 对齐；
- APK 文件、目录与归档条目均为 0；
- MatePad Edge `QXS-*`/市场名强制 desktop + 原生终端策略通过；
- 未安装新包、未卸载、未修改 el2 用户数据。

AGC 云端核对仍未执行：当前工作区没有 AGC 凭据，CLI `auth status`
明确返回缺少 `AGC_CLIENT_ID` / `AGC_CLIENT_SECRET`。详见 `docs/229`。

2026-10-22 复审已执行并通过：

- 身份 / 权限 / Profile / resfile / PC-only / 无 APK / 功能接线；
- 协议 0 drift，核心 30 处端侧补丁，核心入口 3701 条全部可达；
- 原生闭包 61 个库 PASS；
- fs 闸门、fs-local 权限映射、agent-instructions scope walk；
- Python worker / Python tool、undici / fetch / worker jitless、PTC；
- 市场桥、profile pnpm 桥、插件启用、`output.render`；
- 宿主原生 shell / 终端能力由 `tools/doctor.mjs` 现场取证；
- 浏览器自动关闭与截图 fail-fast、用量卡片；
- 文档引用、死代码、架构边界。

环境阻塞：

- DevEco 终端可能继承非法值 `JAVA_HOME=root directory not existed`。用户级
  `.profile` / `.bashrc` / `.zshrc` / `.zshenv` 已加入幂等修复：若
  `$JAVA_HOME/bin/java` 不可执行，则回填
  `~/.harmonybrew/opt/openjdk/libexec`，并设置
  `DEVECO_HOME` / `DEVECO_CLI_CLT_PATH` / `DEVECO_SDK_HOME`。新终端会自动生效；
  已打开的终端需重开或执行 `. ~/.profile`。
- 当前没有 `pwsh`。因此 `device-acceptance.ps1`、`device-code-fingerprint.ps1`
  和 `sign-release-hap.ps1` 不能在鸿蒙 PC 直接运行；`update-device.mjs` 已可用。
  `node tools/doctor.mjs` 提供不依赖 PowerShell 的只读环境/设备/权限/运行时体检。
- CLT 的签名工具是原生 `toolchains/lib/hap-sign-tool`，不是 Windows 路径下的
  `hap-sign-tool.jar`；本轮可直接用它复验正式 `.app/.hap`。
- 正式 HAP 不在真机安装；发布签名与 debug 签名互斥。真机覆盖安装使用 DevEco Run
  或同身份 debug HAP。

最近一次真机能力探测（2026-10-21 16:14–16:17，设备
`MNTXM-24B / API 26 / 2in1`）：

- 安装身份是 debug：`debug=true`、`appProvisionType=debug`、
  `appIdentifier=6918740027110769940`；不是 AGC release 身份。
- 11 条权限中 10 条已授予；`MICROPHONE=-1`，等待首次运行时授权。
- Host `BOOT_*` 全链路成功，页面 `/` 返回 200，内置终端 `terminal/create` 200。
- Node `24.2.0`、`zstd=true`、`jitless=true`；Python worker、
  `print(1+1)=2`、Python/Git/rg/bash 等 10 项 exec 探测均通过。
- PC 工程已彻底删除 `dshm-vm-bash`、QEMU/QGA/prewarm、VM 资源与专属工具；
  手机和平板能力由独立移动端工程维护。
- 工作区授权恢复 `2/2`；浏览器扩展已连接。
- 浏览器扩展已收口到 `0.11.2/build 13` 并由设备实际加载：扩展不再声明
  screenshot，Host 默认不注册 `browser_screenshot`；导航、正文、标签页、
  元素树、网络、CDP、点击、输入、切页和关闭实测通过，截图兼容调用 11 ms
  内明确 fail-fast。
- Codex 子智能体已完成真实端到端验收：`@deepseek-ai/dsh-subagent-codex@0.2.1-rc.2`
  复用本机 brew `codex 0.163.0`，应用私有 `CODEX_HOME`/CA/登录态齐备；父会话调用
  `subagent_codex` 返回 `CODEX_CA_OK pong`，不再出现 npm 找不到
  `@openai/codex/package.json` 或 TLS 重连空等。详见 `docs/228`。
- 所有 `browser_*` 调用在 `clients=[]` 时都会主动拉起海泰并打开
  `/dshm-browser/start` 可驱动页；`browser_navigate` 遇到
  `chrome://newtab` / 无候选 tab 会强制按目标 URL 重新拉起并重试。
- 未生效的能力：JIT/匿名可执行页、`entry/libs` 直接 exec（`EACCES`）、
  麦克风运行时授权、`ACCESS_USER_FULL_DISK`（尚未申请获批）。
- 探测时系统内存处于 critical：总 23,858 MiB、free 1,083 MiB；
  Host RSS 约 377–426 MiB，未持续增长，已写 `diag-mem-critical`。
  这是系统级内存压力，不应归因于已移除的移动端 VM。

尚未完成：

- 其它非 `2in1` 形态由独立移动端工程验收；
- `ACCESS_USER_FULL_DISK` AGC 申请结果；
- 当前内核对匿名可执行页的后续系统升级复验；
- 设计令牌棘轮对 `UsageCard` / `MeetingPanel` / `WebApp` 新增文件仍有
  存量裸值，已纳入当前基线，后续只允许下降。

## 6. 构建与运行

日常开发：

1. DevEco Studio 打开工程根目录；
2. Product 选 `default`；
3. Signing Configs 选自动签名，bundle 为 `com.dshm.dshclient`；
4. 连接 HarmonyOS PC 后运行 `entry:default`。

命令行环境：

```bash
export DEVECO_CLI_CLT_PATH=/data/service/hnp/hmos-clt.org/hmos-clt_1.0.0
hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
```

正式发布：

```bash
hvigorw assembleApp --mode project -p product=default -p buildMode=release --no-daemon
```

正式 `.app` 走 AGC App ID `6917614360926110054` 与对应 release Profile。
日常调试不要安装 release `.app`。

## 7. 资源归置与清理

| 类型 | 位置 | 规则 |
|---|---|---|
| 正式交付 | `dist/release-test/` | 保留当前 `.app`、`.hap`、README、校验和 |
| 当前核心 | `dist/core/*.zip`、`entry/src/main/resources/resfile/*.zip` | 当前版本保留；旧版按回滚策略处理 |
| 核心工作树 | `dist/core/work/<current>/` | 可从 zip 重建，保留用于树门禁 |
| 本地验收 | `dist/acceptance/` | 真机证据，保留 |
| 构建缓存 | `build/`、`entry/build/`、模块 `build/`、`.hvigor/`、`.cxx/` | 可再生，完成构建验证后可清 |
| 签名 | `.certs/`、`signing/` | 永不清理 |
| 外部素材 | `third_party/` | 保留构建原料与有审计价值的原件 |
| 迁移规格 | `spec/hmpc-dev-adaptation/` | 已标 superseded，只作历史 |

清理前后必须核对正式交付 SHA-256、当前核心包哈希和 `check-resfile-core-zip`。

## 8. 接手顺序

1. 读 `AGENTS.md` 的物理门禁、权限、数据和回归纪律；
2. `git status --short`，保留当前脏树，不擅自回滚；
3. 读本文与 `docs/review-prompts.md`；
4. 跑本文与提示词中的离线门禁；
5. 需要 DevEco 时设置 `DEVECO_CLI_CLT_PATH` 后编译；
6. 需要真机时只覆盖安装；
7. 结论写入新的编号文档或 `dist/acceptance/`。

## 9. 文档入口

- `docs/README.md`：当前导航与历史状态
- `docs/review-prompts.md`：当前对抗性审查提示词
- `docs/223-...`：`ACCESS_USER_FULL_DISK` 申请材料
- `docs/224-当前项目复审与过期文档资源清理.md`：2026-10-22 本轮复审与清理台账
- `docs/225-PC工程移除guest-VM与原生执行收口（core+dshm.80覆盖安装验收）.md`：guest VM 移除、CLT 原生 ELF 自签名、覆盖安装与终端验收
- `docs/226-鸿蒙PC浏览器扩展故障复核与重适配（CUSTOM_SANDBOX后）.md`：浏览器扩展能力协商与截图收口
- `docs/227-浏览器主动拉起与newtab陷阱修复（core+dshm.84真机验收）.md`：浏览器自动拉起与可驱动启动页
- `docs/228-Codex子智能体安装修复（精确版本与brew-Codex适配）.md`：Codex 子智能体安装与 brew Codex 适配
- `docs/229-1.1.5邀请测试APP构建与AGC一致性本地复核.md`：1.1.5 正式签名 APP、证书链/ACL/APK/Edge 本地复核与 AGC 云端待上传项
- `docs/214`：双端分离
- `docs/215`：PC-only 与 CUSTOM_SANDBOX
- `docs/222`：11 条权限、Profile 与设备能力边界

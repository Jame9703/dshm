# Implementation Plan: 鸿蒙 PC 开发环境深度适配

**Input**: Feature specification from `spec/hmpc-dev-adaptation/spec.md`

## Summary

在鸿蒙 PC（MateBook 14，DevEco Studio 鸿蒙版）上恢复 DSHM beta 工作区的全部开发工作流。主路径：① 扩展 `tools/lib/deveco-home.mjs` 认得鸿蒙 PC 的 DevEco 布局（双判据：CLT `hvigor/bin/hvigorw.js` + Windows `tools/hvigor/bin/hvigorw.js`）；② 新增共享库 `tools/lib/hdc-client.mjs`（hdc 解析/调用/多设备 -t 契约）；③ 按"忠实移植"原则把 4 个 Windows-only .ps1 工具移植为 node .mjs（装机链/端侧验收/代码指纹/发布签名），全部实战判据原样保留，.ps1 原版不删（双平台并存）；④ 从 resfile 核心 zip 用 python3 zipfile 重建 `dist/core/work/dsh-core-0.2.1-rc.2+dshm.78/`（已探明 zip 内 0 符号链接、0 unix 属性 → 纯解压无 symlink 风险）；⑤ 跑全部仓库内 CI 门禁建基线；⑥ 写 `docs/212` 晨间清单（GUI 自动签名步骤 + 签名一致性决策点）。签名链阻塞（无 dshmbeta profile）按 spec 定性为晨间用户动作，本轮交付"未签名构建 + 全工具就绪 + 清单"。

## Technical Context

**Language/Version**: node ≥ 20（本机 26.8.2 harmonybrew；工具只依赖 node:fs/node:path/node:child_process/node:os 标准 modules）；python3（3.14.7，仅核心树解压用一次）  
**Primary Dependencies**: DevEco Studio 鸿蒙版（`/data/service/hnp/hmos-clt.org/hmos-clt_1.0.0/`，`~/devecostudio/Contents` 为符号链接）：hvigor 7.26.8（`hvigor/bin/hvigorw.js`）、SDK HarmonyOS 26.0.0.105 Release（`sdk/default/openharmony/`）、hdc（`sdk/default/openharmony/toolchains/hdc`，无 .exe）、hap-sign-tool.jar（`sdk/default/openharmony/toolchains/lib/`）、hmos-clt 自带 node（`node/bin/node`）  
**State Management**: N/A（CLI 工具，无 UI 状态）  
**Storage**: 证据/产物只落 gitignored 区：`dist/acceptance/<时间戳>/`、`dist/logs/`、`dist/core/work/`（核心树，构建产物区）  
**Testing**: 仓库门禁体系（`.github/workflows/gates.yml`，60 步）+ 移植工具的实战契约（退出码/输出/读数逐项对照 .ps1 原版）  
**Target Platform**: OpenHarmony（鸿蒙 PC，本机 `127.0.0.1:45595` = HUAWEI MateBook 14）；工具跨平台（同源 .mjs 在 Windows 上亦应可跑，但 Windows 侧继续用 .ps1，不要求双跑）  
**Project Type**: 既有 HarmonyOS 应用的开发工具链（node CLI 工具集）  
**Performance Goals**: N/A（离线工具，无性能指标）  
**Constraints**: 红线——不改坏项目（git 脏树保持、无破坏性 git 操作、不触碰 `~/.ohos`/resfile/entry/libs/third_party 既有内容）；设备零伤害（全程零卸载，仅 `hdc install -r`）；权限面恒 8 条；APK 条目恒 0；`bm dump` stdout 宿主侧捕获；日志取证 `file recv` 回宿主按字节看  
**Scale/Scope**: 新增 5 个文件（4 个 .mjs 工具 + 1 个共享库），修改 1 个文件（deveco-home.mjs），重建 1 棵核心树（40,768 条目），产出 1 份晨间清单文档（docs/212）

## Project Structure

### Documentation (this feature)

```text
spec/hmpc-dev-adaptation/
├── spec.md              # Phase 1 产出
├── plan.md              # 本文件
└── tasks.md             # Phase 3 产出
```

### Source Code (repository root)

```text
tools/
├── lib/
│   ├── deveco-home.mjs      # 【修改】+ 鸿蒙 PC 布局：双判据（hvigor/bin/hvigorw.js 或 tools/hvigor/bin/hvigorw.js）
│   │                        #   候选列表扩展：DEVECO_HOME → ~/devecostudio/Contents → /data/service/hnp/hmos-clt.org/hmos-clt_1.0.0
│   │                        #   Windows 候选逻辑与导出面（DEVECO_ROOT_MARKER/isDevecoRoot/devecoRootCandidates/
│   │                        #   resolveDevecoRoot/devecoPath/devecoSdkHomeCandidates/resolveDevecoSdkHome）零破坏
│   └── hdc-client.mjs       # 【新增】共享库：resolveHdc()（DSHM_HDC → devecoPath(sdk/.../toolchains/hdc) → PATH hdc）
│                            #   listTargets()/runHdc(target,args)/多设备 -t 契约/spawnSync 封装（stdout 宿主侧捕获）
├── update-device.mjs        # 【新增】update-device.ps1 的 node 等价物（装机链：构建→install -r→冷启动→数据保全→就绪判定）
├── device-acceptance.mjs    # 【新增】device-acceptance.ps1 的 node 等价物（端侧验收：采证→report.md 自动判定）
├── device-code-fingerprint.mjs # 【新增】device-code-fingerprint.ps1 的 node 等价物（三态指纹核对 0/1/2）
├── sign-release-hap.mjs     # 【新增】sign-release-hap.ps1 的 node 等价物（发布签名 + verify-app 复验）
├── update-device.ps1        # 【保留不动】Windows 原版（FR-011）
├── device-acceptance.ps1    # 【保留不动】
├── device-code-fingerprint.ps1 # 【保留不动】
└── sign-release-hap.ps1     # 【保留不动】

docs/
└── 212-鸿蒙PC开发环境适配与晨间签名清单.md   # 【新增】今晚适配记录 + GUI 自动签名步骤 + 签名一致性决策点 + 闭环步骤

dist/core/work/
└── dsh-core-0.2.1-rc.2+dshm.78/   # 【重建】从 resfile 核心 zip 解压（40,768 条目；gitignored 构建产物区）
```

**Structure Decision**: 遵循既有仓库结构——工具一律落 `tools/`（97 个 .mjs 的既有惯例），共享库落 `tools/lib/`（deveco-home.mjs 既有惯例），文档落 `docs/`（编号顺延 212），产物落 gitignored 的 `dist/`。不引入任何新目录层级；不新建 test 目录（工具验证走门禁体系与契约对照）。本特性为纯工具链适配，不触碰 `entry/src/main/ets`（应用代码零改动）。

## Complexity Tracking

无宪法冲突需要豁免：全部改动落在既有目录惯例内，文件数最小（5 新 + 1 改 + 1 文档）。

## Research & Decisions

### D1: deveco-home.mjs 双判据扩展（而非改判据）

- **Decision**: `DEVECO_ROOT_MARKER`（`tools/hvigor/bin/hvigorw.js`）导出与语义不变；新增 HM PC 判据 `hvigor/bin/hvigorw.js`；`isDevecoRoot(dir)` 在两个判据任一命中时为真；候选列表追加 `~/devecostudio/Contents`（用 `os.homedir()` 展开）与 `/data/service/hnp/hmos-clt.org/hmos-clt_1.0.0`，追加在 `DEVECO_HOME` 之后、Windows 候选之前
- **Rationale**: Windows 侧 6 个 node 工具（pack-core/place-toolchain/check-arkts-entry/check-layout-fixtures/strip-ungranted-acl-perms/dshtest.py 语义）依赖现有判据与候选顺序；改判据会让 Windows 侧 `isDevecoRoot` 对真安装根返回 false（回归）。追加式扩展使 HM PC 解析在两个平台都安全（Windows 上 POSIX 候选路径 existsSync 恒 false，零干扰）。先例：`check-arkts-entry.mjs:65` 已用无前缀判据认 CLT 布局
- **Alternatives considered**: ① 新建 `deveco-home-hmpc.mjs`——拒绝：解析口必须唯一（否则两个口各自漂移，违背该文件存在的初衷）；② 只靠 `DEVECO_HOME` 环境变量——拒绝：要求每 shell 手工设置，等于把 2026-10-10 那次"路径写死失效"的雷换个形态埋回来

### D2: 共享库 hdc-client.mjs（而非各工具内嵌）

- **Decision**: 新增 `tools/lib/hdc-client.mjs`：`resolveHdc()`（`DSHM_HDC` 环境变量 → `devecoPath('sdk/default/openharmony/toolchains/hdc')` → PATH 里的 `hdc`）、`listTargets(hdc)`、`runHdc(hdc, target, args)`（target 非空时自动加 `-t`，stdout/stderr 宿主侧 Buffer 捕获，避免设备侧重定向/编码坑）
- **Rationale**: 3 个移植工具（装机/验收/指纹）都要 hdc，同一套 `-t` 多设备契约、`[Empty]` 判定、编码处理不该抄三遍；三份副本漂移正是本仓 `denial-hints.js`/`fs-fence.js` "两份判据副本逐字节一致"门禁存在的原因——共享库是仓库已验证的反模式解法
- **Alternatives considered**: 各工具自带 Resolve-Hdc 等价物——拒绝（三份漂移风险）；扩展 deveco-home.mjs 放 hdc 解析——拒绝（该文件职责是"DevEco 安装根"，hdc 调用语义是另一个职责，混在一起以后没法单测）

### D3: 移植原则 = 忠实移植（契约逐项对照），已知缺陷顺手修正并留档

- **Decision**: 4 个 .ps1 → .mjs，逐项保留：参数名（kebab-case 化：`-Target` → `--target`）、退出码、输出语义、全部实战判据注释（中文注释随代码翻译保留）。唯一主动修正：`device-code-fingerprint` 的 filesDir 从写死 `com.dshm.dshclient` 改为从 `build-profile.json5`/`AppScope/app.json5` 解析 bundle（与 device-acceptance 2026-10-18 的修法同源——"beta 工作区里写死正式包名会让整套验收读错应用"是已实测的教训，.ps1 版是漏网之鱼）
- **Rationale**: .ps1 里的每条判据都对应一次真机事故（540 行 update-device 尤甚）；"忠实移植"把回归风险压到最低。写死包名是已知缺陷而非设计，port 时修正并注释留档
- **Alternatives considered**: ① 重写为"更好的"工具——拒绝：重写丢判据 = 把 2026-09-25 数据事故的护栏拆了；② 连写死包名一起忠实保留——拒绝：违反已实测教训

### D4: 核心树解压 = python3 zipfile（一次性动作，脚本不留 tools/）

- **Decision**: 用 python3 `zipfile` 把 resfile 核心 zip 解压到 `dist/core/work/`（zip 内顶层即版本目录，直接解压落位）。已探明：zip 内 40,768 条目、**0 符号链接、0 unix 属性位**（pack-core 打包时不存储）→ 无 AGENTS.md "Windows tar 破坏 symlink" 同族风险，纯解压即可。解压脚本写到仓库外临时目录（`/data/storage/el2/base/temp/deveco/`）执行后即弃，不留 tools/
- **Rationale**: pack-core 路线被否：① 它从 node_modules 重打包（不是从 zip 恢复），会踩 AGENTS.md 出包坑 #2（树增量复用静默跳过补丁）与"裸跑 pack-core 重盖 builtAt"坑（docs/116 记录）；② 目标是"树依赖门禁可跑"，逐字节恢复随包 zip 就是唯一无损口径。python 是 AGENTS.md 认可的解压工具（"只允许 Python tarfile"先例）
- **Alternatives considered**: ① `unzip` 二进制——可用性未证实且无逐条目校验；② node 脚本——zip 解压 node 标准库不支持，引第三方依赖违反工具自包含惯例

### D5: 门禁基线跑法 = 按 gates.yml 逐条执行（不新建 runner 工具）

- **Decision**: Phase 5 验证时按 `.github/workflows/gates.yml`（60 步）逐条运行仓库内门禁（约 37 条 repo-only + 树重建后 ~15 条树依赖），记录每条退出码与读数；不新建 `run-gates.mjs` 常驻工具
- **Rationale**: 仓库惯例是门禁单条可跑（AGENTS.md 门禁清单即按条列出）；一次性基线不需要常驻 runner，避免 tools/ 膨胀。`assert-resfile-sync` 前须先跑 `tools/place-host-app.mjs`（gates.yml 既有顺序）
- **Alternatives considered**: 写常驻 runner——拒绝（一次性需求，违反"一次性脚本不留 tools/"口径）

### D6: AGENTS.md 不动，适配记录落 docs/212

- **Decision**: 本轮不修改 AGENTS.md（它是用户拍板的约束宪法，Windows 双工作区门禁描述等仍有效）；鸿蒙 PC 侧的适配事实、工具用法、晨间清单全部落 `docs/212`
- **Rationale**: AGENTS.md 的修改应由用户主导（约束变更 = 决策变更）；docs/ 是事实记录的既定归置。docs/210 的基线口径（版本、门禁）不受本轮影响
- **Alternatives considered**: 在 AGENTS.md 追加鸿蒙 PC 章节——拒绝（越权；等用户晨间确认后再议）

### D7: 签名链交付口径 = 工具就绪 + 未签名件 + 晨间清单

- **Decision**: sign-release-hap.mjs 移植完成（物料默认路径指向 `~/data/AGC-operations/release-signing/`，已核实 cer/p12/p7b 在位；口令备注文件不在本机 → 工具留 `--pwd`/`--note-file` 参数，OQ-2 晨间解决）。debug 签名（dshmbeta profile）不在本轮工具范围——它走 DevEco GUI 自动签名（清单步骤化），不走 hap-sign-tool（无 profile 可签）
- **Rationale**: 本机无 dshmbeta profile 是硬事实（全盘已搜）；CLI 铸造 profile 需要的权限面夜间不可验。GUI 自动签名是 DevEco 官方唯一可靠路径，也是用户既有工作流
- **Alternatives considered**: ① 夜间用 `devecocli signature` 尝试铸造——拒绝（触碰 `~/.ohos` 签名物料区，红线敏感区夜间不冒险；且该命令面向的是 app signature 而非 debug profile 铸造，口径不符）；② 跳过签名链——拒绝（装机闭环是 spec 核心诉求，工具与清单必须就绪）

## Data Model

无持久化数据模型（CLI 工具集）。运行的临时数据契约：

- **装机链读数**: 装前/装后 home 链接数与文件数（`ls -l | wc -l` / `find | wc -l` 口径）、核心版本串（`cores/<ver>` 正则）、就绪判定行——全部 stdout 打印，不落盘（与 .ps1 一致）
- **验收证据**: `dist/acceptance/<时间戳>/` 下 `report.md`（自动判定表）、`nav.md`（导航表）、`<页面>.json/.jpeg`（布局/截图）、`<阶段>.log`（摘录）、`device-*.log`（持久日志原文）——目录 gitignored
- **指纹读数**: 13 个关键文件的设备侧/本机侧 sha256 对照表、三态结论、退出码 0/1/2——stdout
- **核心树**: `dist/core/work/dsh-core-0.2.1-rc.2+dshm.78/`（40,768 条目，与 resfile zip 逐字节一致）
- **hdc 目标**: 连接键（如 `127.0.0.1:45595`）——多设备时显式传参，环境变量不自动生效（.ps1 同款契约）

## Contracts & Interfaces

### C1: `tools/lib/deveco-home.mjs`（修改，导出面向后兼容）

| 导出 | 变化 |
|---|---|
| `DEVECO_ROOT_MARKER` | 不变（`tools/hvigor/bin/hvigorw.js`） |
| `DEVECO_ROOT_MARKER_CLT`（新名） | 新增：`hvigor/bin/hvigorw.js`（HM PC/CLT 布局） |
| `isDevecoRoot(dir)` | 行为扩展：两判据任一命中即真；Windows 真根判定结果不变 |
| `devecoRootCandidates()` | 追加 HM PC 候选（DEVECO_HOME 之后）；Windows 候选顺序不变 |
| `resolveDevecoRoot()` / `devecoPath()` / `devecoSdkHomeCandidates()` / `resolveDevecoSdkHome()` / `devecoCandidatesHint()` | 签名不变，行为随根解析扩展 |

### C2: `tools/lib/hdc-client.mjs`（新增）

- `resolveHdc(): string | null` — `DSHM_HDC` → DevEco toolchains hdc → PATH `hdc`；找不到 null（调用方自定退出码）
- `listTargets(hdc): string[]` — 解析 `hdc list targets`，`[Empty]` → `[]`
- `runHdc(hdc, target, args, opts): { stdout, stderr, status }` — target 非空自动前插 `-t <target>`；spawnSync Buffer 捕获（utf8 解码）
- 全部函数零副作用（不写文件、不联网）

### C3: `tools/update-device.mjs`（新增；对齐 update-device.ps1 契约）

- 参数：`--target <key>`（多设备必填）、`--skip-build`（跳构建直接装）、`--hap <path>`（指定产物）、`--build-mode <debug|release>`（默认 debug）
- 流程契约：环境自检（全文零 uninstall 断言）→ 设备确认 → 数据基线 → 构建（DevEco hvigorw，HM PC/Windows 双布局解析）→ 定位 HAP → 读包内 debug 标志 → `hdc install -r`（三态判定）→ 冷启动 → 数据保全校验（不减少）→ 分档就绪判定
- 退出码：0 成功；非 0 各失败段（与 .ps1 段落对应）；设备不在线 3

### C4: `tools/device-acceptance.mjs`（新增；对齐 device-acceptance.ps1 契约）

- 参数：`--skip-install`、`--target <key>`、`--boot-wait-seconds <n>`（默认 45）、`--hilog-early-seconds <n>`（默认 8）
- 契约：bundle 从 `build-profile.json5`/`AppScope/app.json5` 解析；强制冷启动；判据 = 设备侧持久日志（node-output.log 每启动轮转、dshm-host.log 截"写锁巡检"后）；UI 按文本定位点击（非坐标）；证据落 `dist/acceptance/<时间戳>/`；report.md 自动判定五项（设备在线/核心启动/客户端接入/平台标识/无崩溃）；零卸载
- 退出码：0 完成；4 无 HAP；5 启动失败；3 无设备

### C5: `tools/device-code-fingerprint.mjs`（新增；对齐 .ps1 契约 + D3 修正）

- 参数：`--token`、`--port`、`--timeout-sec`（默认 25）、`--local-tree`（负控制用）
- 契约：filesDir 按解析出的 bundle 拼（修正点，见 D3）；三态结论/退出码 0/1/2；token 三级优先（命令行 > host-ready.json > 日志按 boot 段三级，来源打进输出）；端口从 `entry/src/main/ets/runtime/RuntimePort.ets` 的 `HOST_DEFAULT_PORT` + 候选探测；fport 失败清理（只删自己建的）；设备侧只读
- 13 个关键文件清单与 .ps1 逐字一致

### C6: `tools/sign-release-hap.mjs`（新增；对齐 .ps1 契约）

- 参数：`--in-file`（默认未签名 HAP 路径）、`--out-file`、`--keystore`、`--cert`、`--profile`、`--key-alias`（默认 `ohosdshm`）、`--pwd`、`--note-file`、`--sign-alg`（默认 SHA256withECDSA）；物料默认路径改指 `~/data/AGC-operations/release-signing/`（HM PC 本机物料，已核实存在），可参数覆盖
- 契约：输入必须 unsigned（拒签已签包）；签名前摘除未授权 ACL（调 `strip-ungranted-acl-perms.mjs`，幂等）；hap-sign-tool 经 HM PC SDK 路径解析（`resolveDevecoSdkHome`）；java 用 `JAVA_HOME`/PATH；verify-app 复验 + profile type=release 断言；产物大小/sha256 打印

### C7: 晨间清单 `docs/212-鸿蒙PC开发环境适配与晨间签名清单.md`（新增）

- 内容契约：① 本轮适配事实（环境读数/构建验证/门禁基线/工具用法对照表）；② GUI 自动签名步骤（DevEco Studio → File → Project Structure → Signing Configs → Automatically generate signature，选 `com.dshm.dshmbeta`，预期读数 = `~/.ohos/config` 出现 dshmbeta 的 profile 文件）；③ 签名一致性决策点（OQ-1：新身份 install -r 预期失败 9568322 同族 → 选项呈现：接受卸载重装[beta 数据丢失]/保留旧签方案/其他，用户拍板）；④ 装机验收闭环步骤（update-device.mjs → device-acceptance.mjs → device-code-fingerprint.mjs 的完整命令序列）；⑤ 发布签名口令补齐（OQ-2）

### C8: 核心树重建（一次性动作产物）

- 输入：`entry/src/main/resources/resfile/dsh-core-0.2.1-rc.2+dshm.78-openharmony-arm64.zip`（SHA256 与 MIGRATION-MANIFEST 已核验一致）
- 输出：`dist/core/work/dsh-core-0.2.1-rc.2+dshm.78/`，40,768 条目逐字节一致（抽验 + 条目数全验）
- 验收：`check-core-openharmony-patches`、`assert-core-entrypoints` 等树依赖门禁可运行

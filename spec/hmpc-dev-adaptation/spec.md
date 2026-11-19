# Feature Specification: 鸿蒙 PC 开发环境深度适配（DSHM beta 工作区）

**Created**: 2026-10-21  
**Status**: Approved（用户授权 yolo 模式，本 spec 由代理自行批准并留档）  
**Input**: 用户描述："将刚迁移到鸿蒙 PC（MateBook 14，DevEco Studio 鸿蒙版）的 DSHM beta 工作区深度适配鸿蒙 PC 开发环境，确保 APP 能在鸿蒙 6.1.0 及以上的手机/平板/PC 上正常运行，修复各设备问题，且保证项目不被改坏。权限自己审批，开启 yolo 模式。"

## Overview

DSHM beta 工作区已从 Windows 迁移至鸿蒙 PC（`~/data/DSHM-deveco-workspace`），三大关键资产（libnode / 核心 zip / sherpa-onnx har）经 SHA256 核验逐字节一致，完整构建链当晚已验证可用（ArkTS 0 错误、原生库本机新编、未签名 HAP 产出）。但仍有五条工作流断裂或缺失：① 6 个 Windows-only PowerShell 工具在鸿蒙 PC 不可用（装机/端侧验收/代码指纹/发布签名/DevEco 根解析）；② `deveco-home.mjs` 解析口不认鸿蒙 PC 的 DevEco 布局（hvigorw 无 `tools/` 前缀、hdc 无 `.exe`）；③ 核心树 `dist/core/work/` 因迁移排除而缺失，约 15 条树依赖门禁无法运行；④ 签名链阻塞（本机无 `com.dshm.dshmbeta` 的 profile，且既有 beta 包为 Windows 侧签名）；⑤ 全套 CI 门禁尚未在本机建立基线。本特性将这五条全部收口，使鸿蒙 PC 成为一等开发环境。

## User Scenarios & Testing *(mandatory)*

### User Story 1 - DevEco 根解析口认得鸿蒙 PC（Priority: P1）

开发者（代理）在鸿蒙 PC 上运行任何需要 DevEco 自带工具（hvigorw / hdc / hap-sign-tool / node）的仓库脚本时，`tools/lib/deveco-home.mjs` 能自动解析出鸿蒙 PC 的 DevEco 安装根，无需手工设置环境变量；同时 Windows 侧的解析行为一个字节不变。

**Why this priority**: 解析口是全部工具链的地基——装机、签名、验收、指纹、pack-core 全部经由它取工具路径；它不通，后面全部不通。

**Independent Test**: 在不设任何环境变量的情况下调用解析口，断言返回 `/data/service/hnp/hmos-clt.org/hmos-clt_1.0.0`（或 `~/devecostudio/Contents` 符号链接指向的等价路径）；再断言 Windows 判据（`tools/hvigor/bin/hvigorw.js`）仍保留在代码里。

**Acceptance Scenarios**:

1. **Given** 鸿蒙 PC 上未设 `DEVECO_HOME`，**When** 调用 `resolveDevecoRoot()`，**Then** 返回非 null 且该根下存在 `hvigor/bin/hvigorw.js`
2. **Given** 显式设置 `DEVECO_HOME`，**When** 调用解析口，**Then** 优先返回该值（既有契约不变）
3. **Given** Windows 布局（`tools/hvigor/bin/hvigorw.js` 存在），**When** 调用 `isDevecoRoot()`，**Then** 判定逻辑与现状一致（Windows 侧零回归）

---

### User Story 2 - 装机链在鸿蒙 PC 可用（Priority: P1）

开发者能在鸿蒙 PC 上以一条命令完成"构建 → 覆盖安装 → 冷启动 → 数据保全验证"的完整装机链，全程只 `hdc install -r`、绝不卸载，装后断言 el2 用户数据（会话/插件/工作区）原样保留。

**Why this priority**: 装机链是"确保 APP 正常运行"的主通道，也是历次真机事故（数据不可逆丢失）的唯一安全入口；`update-device.ps1` 里 540 行实战判据一条都不能丢。

**Independent Test**: 在本机 MateBook（`127.0.0.1:45595`）上跑移植后的装机链工具，断言：构建成功、`install -r` 成功、装前装后 home 指纹一致、核心版本读数正确。（实际执行受签名阻塞，工具就绪度以 dry-run/构建段验证，装机段晨间签名后执行。）

**Acceptance Scenarios**:

1. **Given** 仓库在鸿蒙 PC 上，**When** 运行移植后的装机链工具，**Then** 它用 DevEco 自带 hvigorw 构建 debug 包并产出 HAP
2. **Given** 设备在线，**When** 安装，**Then** 只出现 `hdc install -r`，且安装判定为三态（成功/失败/回空重试 + updateTime 正判）
3. **Given** 装机完成，**When** 校验数据，**Then** 装前记录的 home 链接数/文件数装后不减少，`install -r` 未触碰 el2 数据
4. **Given** 任一步失败，**When** 工具退出，**Then** 立即停止并给非零退出码（fail-fast 契约不变）

---

### User Story 3 - 仓库内 CI 门禁在鸿蒙 PC 全绿（Priority: P1）

开发者能在鸿蒙 PC 上运行 `.github/workflows/gates.yml` 里的全部仓库内门禁（约 37 条，不需要核心树/设备的那些），并全部通过，建立本机回归基线。

**Why this priority**: "不把项目改坏"的唯一客观判据就是门禁全绿；本轮所有改动（解析口 + 工具移植）必须被既有门禁（尤其 check-deveco-paths、check-permission-surface、check-no-apk-surface、check-doc-refs）反向验证。

**Independent Test**: 逐条运行 gates.yml 中的仓库内门禁命令，记录每条退出码；断言 0 红。

**Acceptance Scenarios**:

1. **Given** 本轮改动已完成，**When** 运行 `node tools/check-deveco-paths.mjs`（含 `--self-test`），**Then** 通过——新代码没有引入写死的 DevEco 安装根
2. **Given** 本轮改动已完成，**When** 运行 `check-permission-surface`（恒 8 条）与 `check-no-apk-surface`（恒 0 条），**Then** 通过
3. **Given** 其余仓库内门禁，**When** 逐条运行，**Then** 0 红（既有基线若有个别红，如实登记原因，不静默）

---

### User Story 4 - 核心树重建，树依赖门禁可跑（Priority: P2）

开发者能在鸿蒙 PC 上从随包 resfile 核心 zip（`dsh-core-0.2.1-rc.2+dshm.78-openharmony-arm64.zip`）重建 `dist/core/work/dsh-core-0.2.1-rc.2+dshm.78/` 核心树，使约 15 条树依赖门禁（compat-drift、check-core-openharmony-patches、check-plugin-toggle 等）恢复可运行。

**Why this priority**: 树依赖门禁守着核心树的 29 处注入补丁与插件面，是"核心树没被改坏"的判据；迁移时 dist/ 被排除，这层验证当前完全缺失。

**Independent Test**: 解压重建后运行树依赖门禁，断言可运行且结果与 Windows 侧最后基线（`+dshm.78`，见 docs/210）一致。

**Acceptance Scenarios**:

1. **Given** resfile 里的核心 zip（SHA256 已与迁移清单核验一致），**When** 解压到 `dist/core/work/dsh-core-0.2.1-rc.2+dshm.78/`，**Then** 目录结构与 zip 内布局一致（根目录一层版本目录）
2. **Given** 重建的树，**When** 运行 `check-core-openharmony-patches`、`assert-core-entrypoints` 等树依赖门禁，**Then** 可运行；若红，读数与 Windows 侧最后基线一致才算"迁移无损"

---

### User Story 5 - 端侧验收工具移植（Priority: P2）

开发者能在鸿蒙 PC 上运行端侧验收（找设备、装机、冷启动、采证、生成 report.md），证据落 `dist/acceptance/<时间戳>/`，自动判定项（核心启动/客户端接入/平台标识/无崩溃）由工具判好。

**Why this priority**: 端侧验收是每次真机改动的标准回执；没有它，"修复各设备问题"无法闭环取证。

**Independent Test**: 移植后在本机跑一次（-SkipInstall 或装机后），断言证据目录生成、report.md 自动判定表齐全。

**Acceptance Scenarios**:

1. **Given** 设备在线且已装最新包，**When** 运行验收工具 `-SkipInstall` 模式，**Then** 冷启动、采证、report.md 生成，且全程无卸载命令
2. **Given** bundle 名，**When** 工具解析，**Then** 从 `build-profile.json5` 读出 `com.dshm.dshmbeta`（不写死，2026-10-18 实测教训）
3. **Given** hilog 环形缓冲仅 8-10 秒，**When** 采证，**Then** 判据以设备侧持久日志（node-output.log 每启动轮转 / dshm-host.log 截"写锁巡检"之后）为准（E385 契约）

---

### User Story 6 - 设备代码指纹工具移植（Priority: P2）

开发者能在鸿蒙 PC 上运行设备代码指纹核对（设备核心树 13 个关键文件 ↔ 本机树逐字节 SHA256），三态结论（一致/不一致/未验证）与退出码契约（0/1/2）不变。

**Why this priority**: 它回答"设备跑的是不是本机这份代码"——历次"装了但没生效"错位的唯一裁判。

**Independent Test**: 在核心树重建（US4）后对在线设备跑一次，断言三态输出与退出码契约。

**Acceptance Scenarios**:

1. **Given** 设备在线且宿主已启动，**When** 运行指纹工具，**Then** token 按三级优先取（-Token > host-ready.json > dshm-host.log 按 boot 段），来源打进输出
2. **Given** 桥回 401，**When** 工具退出，**Then** 结论为"未验证"并说明 401 含义，不把"读不到"写成"一致"
3. **Given** 端口，**When** 解析，**Then** 从 `RuntimePort.ets` 常量取 + 逐候选探测（不从日志猜端口的契约不变）

---

### User Story 7 - 发布签名工具移植（Priority: P3）

开发者能在鸿蒙 PC 上对未签名 HAP/App 做发布签名（AGC 上传件），物料取本机 `~/data/AGC-operations/release-signing/`（cer/p12/p7b 已确认在位），签后 verify-app 复验 + profile type=release 断言。

**Why this priority**: 发布签名属正式包链路（AGC 上架），非 beta 日常刚需，故 P3；但物料已随迁移到位，移植成本低。

**Independent Test**: 对本轮构建的未签名 HAP 跑一次签名 + 复验（口令需晨间用户提供，见开放问题）。

**Acceptance Scenarios**:

1. **Given** 未签名 HAP 与 AGC 物料，**When** 运行签名工具，**Then** 签名前先摘除发布 profile 未授权的 ACL 声明（幂等），签后 verify-app 通过且 profile type=release
2. **Given** 输入不是未签名产物（名字无 unsigned），**When** 运行，**Then** 拒绝（契约不变）

---

### User Story 8 - 晨间签名清单与决策文档（Priority: P3）

用户晨间醒来后，有一份按步骤可执行的清单：① DevEco GUI 里为 `com.dshm.dshmbeta` 完成自动签名（本机无该 profile，CLI 无法铸造，必须 GUI）；② 处理签名身份一致性决策（设备上既有 beta 为 Windows 侧签名，新身份 `install -r` 会签名不一致——历史教训：换身份只能卸载，而卸载触碰数据红线，必须用户拍板）；③ 用就绪的装机链完成装机与验收闭环。

**Why this priority**: 签名是本轮唯一无法夜间自主完成的一跳；清单让晨间动作 5 分钟内可执行，并明确红线决策留给用户。

**Independent Test**: 清单文件存在于 `docs/`（编号顺延 212），含可勾选步骤、预期读数、失败回退路径。

**Acceptance Scenarios**:

1. **Given** 用户晨间打开清单，**When** 按步骤操作 GUI 自动签名，**Then** 每步有预期读数可对照
2. **Given** 签名身份与设备既有包不一致，**When** 到达决策点，**Then** 清单明确列出选项（接受卸载重装[数据丢失] / 保留 Windows 侧签名方案 / 其他），不替用户决定

---

### Edge Cases

- **hdc 多设备在线**：裸 `hdc shell` 被拒（need connect-key）→ 移植工具沿用 `-t <key>`/`-Target` 契约，多台时必须显式指定
- **`bm dump` 设备侧重定向拿不到 stdout**：判定读取一律在宿主侧捕获（AGENTS.md 真机读数坑 #2）
- **含 NUL 的日志行**：设备侧 grep 假截断 → 日志取证一律 `file recv` 回宿主侧按字节看（AGENTS.md 真机读数坑 #3）
- **设备不在线**：装机/验收/指纹工具以明确退出码退出（3/2），不悬挂、不误报
- **既有门禁个别红**：如实登记读数与原因，与 Windows 侧最后基线对比定性（迁移引入 vs 本来就有），不静默跳过

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `tools/lib/deveco-home.mjs` MUST 支持鸿蒙 PC 布局：命中判据接受 `hvigor/bin/hvigorw.js`（CLT 布局）与 `tools/hvigor/bin/hvigorw.js`（Windows IDE 布局）两者；候选列表按 `DEVECO_HOME` → `~/devecostudio/Contents` → `/data/service/hnp/hmos-clt.org/hmos-clt_1.0.0` 顺序扩展；Windows 候选逻辑 MUST NOT 改变
- **FR-002**: hdc 解析 MUST 按 `DSHM_HDC` 环境变量 → `<DevEco 根>/sdk/default/openharmony/toolchains/hdc(.exe)` 顺序；平台差异（`.exe` 后缀）由工具侧处理
- **FR-003**: 装机链工具（`update-device` 的 node 等价物）MUST 保留全部实战契约：仅 `hdc install -r`（全文零 uninstall）、装前数据基线（home 链接数/文件数）、安装三态判定（成功/失败/回空→重试→bm dump updateTime 正判）、冷启动（force-stop + aa start）、按分档判"宿主就绪"、fail-fast 非零退出
- **FR-004**: 端侧验收工具 MUST 保留契约：bundle 名从 `build-profile.json5`/`AppScope/app.json5` 解析（不写死）、强制冷启动（node-output.log 轮转语义）、判据以设备侧持久日志为准（E385）、UI 定位按文本非坐标（E261）、证据只落 `dist/acceptance/`、零卸载
- **FR-005**: 代码指纹工具 MUST 保留契约：三态结论与退出码 0/1/2、token 三级优先（命令行 > host-ready.json > 日志按 boot 段三级）、端口从 `RuntimePort.ets` 常量 + 候选探测、fport 失败清理、设备侧只读
- **FR-006**: 发布签名工具 MUST 保留契约：签名前摘除未授权 ACL 声明（幂等、对 profile 比）、verify-app 复验、profile type=release 断言、拒绝非 unsigned 输入；物料默认路径指向本机 AGC-operations 目录（可参数覆盖）
- **FR-007**: 核心树重建 MUST 从 resfile 核心 zip 恢复 `dist/core/work/dsh-core-<ver>/`，文件逐字节一致；重建后树依赖门禁 MUST 可运行
- **FR-008**: 全部新增/修改代码 MUST NOT：触碰 `~/.ohos`（签名物料）、修改 resfile/entry/libs/third_party 的既有内容、对设备执行任何卸载/删除、改动权限面（恒 8 条）或引入 APK 条目（恒 0）
- **FR-009**: 全部仓库内 CI 门禁 MUST 在改动后于本机通过（0 红；既有红如实登记并定性）
- **FR-010**: 晨间清单文档 MUST 落 `docs/212-*`（编号顺延），含 GUI 自动签名步骤、签名一致性决策点（用户拍板）、装机验收闭环步骤
- **FR-011**: 移植工具的 Windows 原版（.ps1）MUST 保留不删（双平台并存；Windows 侧继续用 .ps1，鸿蒙 PC 侧用 .mjs）

### Key Entities

- **DevEco 安装根（HM PC）**: `/data/service/hnp/hmos-clt.org/hmos-clt_1.0.0/`，含 `hvigor/bin/hvigorw.js`、`sdk/default/openharmony/toolchains/{hdc,lib/hap-sign-tool.jar,lib/PermissionDefinitions.json}`、`node/bin/node`；`~/devecostudio/Contents` 为其符号链接
- **装机链（update-device）**: 唯一装机入口；输入 = 仓库 + 在线设备；输出 = 已装 HAP + 数据保全读数 + 就绪判定；不变量 = 零卸载、fail-fast
- **核心树**: `dist/core/work/dsh-core-0.2.1-rc.2+dshm.78/`，由 resfile zip 重建；树依赖门禁的判据对象
- **AGC 发布物料**: `~/data/AGC-operations/release-signing/{dshm.cer,dshm.p12,dshmRelease.p7b}`；仅 `com.dshm.dshclient`（正式包），发布 profile 无 UDID 不能装机
- **签名身份（beta）**: 本机 `~/.ohos` 已有开发者身份，但无 `com.dshm.dshmbeta` 的 profile → GUI 自动签名是唯一铸造路径

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 鸿蒙 PC 上完整构建可重复：ArkTS 编译 0 错误、未签名 HAP 产出（本轮已验证一次，改动后复验一次）
- **SC-002**: 仓库内 CI 门禁 0 红（含 check-deveco-paths --self-test、check-permission-surface、check-no-apk-surface、check-doc-refs）
- **SC-003**: 6 个移植目标中 4 个核心工具（解析口/装机链/验收/指纹）+ 签名工具全部可在无 PowerShell 环境运行（纯 node）
- **SC-004**: 核心树重建后，树依赖门禁可运行且读数与 Windows 侧 `+dshm.78` 基线一致
- **SC-005**: 设备零伤害：全程零卸载、零 el2 数据删除；装机链（签名后执行）home 指纹装前=装后
- **SC-006**: 晨间清单就绪：GUI 签名步骤 + 决策点 + 闭环步骤，用户 5 分钟内可开始执行

## Assumptions

- 用户已入睡并授权 yolo 模式（"权限自己审批"）：所有关卡由代理自行批准并留档（本 spec 的批准即第一例）
- 手机/平板今晚不在线：设备验证以本机 MateBook（127.0.0.1:45595）为限，其余进晨间清单
- 签名阻塞定性：本机无 dshmbeta profile → 未签名构建 + 晨间 GUI 签名；CLI 无法铸造 debug profile（工具面已核：`devecocli signature` 存在但铸造 profile 需 GUI/AGC 权限面，夜间不冒险触碰 `~/.ohos`）
- 工具风格：node .mjs 为主（仓库 97 个 .mjs 的主流风格）；.ps1 原版保留（FR-011）
- `export-deveco-workspace.ps1` 不移植：它是迁移导出工具，迁移已完成，鸿蒙 PC 侧无复用场景
- 既有 git 脏树（~300 未提交条目）保持原样：本轮改动叠加其上，不做任何 git 清理/重置
- `dist/` 与 `entry/build/` 是构建产物区：重建核心树、落验收证据均属允许写入区

## Open Questions

- **OQ-1（晨间决策）**: GUI 自动签名后若新签名身份与设备上既有 beta（Windows 侧签名）不一致，`install -r` 将失败——是否接受"卸载重装（beta 包 el2 数据丢失）"？或保留其他方案？需用户拍板（清单 FR-010 呈现选项）
- **OQ-2（口令）**: `dshm.p12` 的密钥库口令在 Windows 侧存于备注文件（`D:\desktop\release\新建文本文档.txt`），本机 AGC-operations 目录内**无**该备注文件——发布签名执行需晨间用户提供口令（或告知口令文件位置）
- **OQ-3（基线口径）**: 树依赖门禁若出现与 Windows 侧 `+dshm.78` 基线不一致的红，本轮口径 = 登记读数 + 定性（迁移引入 vs 既有），修复另行立项——除非红由本轮改动直接引入（则当场修，回归纪律）

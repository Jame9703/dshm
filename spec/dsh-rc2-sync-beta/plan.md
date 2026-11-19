# 实施方案：DSH rc.2 同步与 Beta 交付

**输入**：~/data/DSHM-deveco-workspace/spec/dsh-rc2-sync-beta/spec.md

## Summary

沿用现有三端壳层、共享宿主与核心物化体系，完成指定 rc.2 的补丁、协议、插件与静态容器同步。先保全现场并建立当前基线，再修契约采集及补丁兼容，执行同口径回归，最后由验证代理构建 Beta、核验实物及尝试安全部署；设备不可用时交付离线已核验的待测包并明确限制。

## Technical Context

- **Language/Version**：沿用项目 ArkTS、JavaScript ESM/CJS、Python 与 C/C++；本轮不升级运行时或 SDK。
- **Primary Dependencies**：DSH 0.2.2-rc.2；现有鸿蒙原生依赖覆盖、共享 hostruntime、guest VM 与随包工具链。
- **State Management**：保留现有状态管理和双壳结构，不引入 V1/V2 迁移。
- **Storage**：保留现有核心目录、用户 profile、会话、插件、工作区和同步存储布局，不新增业务存储。
- **Testing**：现有工具门禁、行为验证、变异体自检、契约对比、ArkTS/C++ 静态检查、编译与包结构核验。
- **Target Platform**：现有 PC/2in1/Edge/Pro Max、普通平板、手机与折叠屏；设备与 SDK 约束取实际配置，不改动。
- **Performance Goals**：不引入已知性能倒退，不另设无需求依据的性能指标。
- **Constraints**：应用 1.1.8/1010016 不变；entry 18/phone 9 权限不变；不提交、不毁损现有改动、签名、用户数据及历史交付。
- **Scale/Scope**：本次升级闭环及 review 证实的现有缺陷，不新增功能、不重构全项目。

## Project Structure

项目根目录为 `~/data/DSHM-deveco-workspace`，下列为绝对目标路径。

### Documentation (this feature)

- `~/data/DSHM-deveco-workspace/spec/dsh-rc2-sync-beta/spec.md`：需求。
- `~/data/DSHM-deveco-workspace/spec/dsh-rc2-sync-beta/plan.md`：本方案。
- `~/data/DSHM-deveco-workspace/spec/dsh-rc2-sync-beta/tasks.md`：后续任务与验证范围。

### Source Code (repository root)

| 路径 | 责任及允许的增量改动 |
|---|---|
| `~/data/DSHM-deveco-workspace/hostcore/core-recipe.json` | 指定核心目标；不追更其他版本 |
| `~/data/DSHM-deveco-workspace/tools/pack-core.mjs` | rc.2 物化、补丁兼容及静态容器一致性 |
| `~/data/DSHM-deveco-workspace/tools/protocol-contract.mjs` | 完整契约采集、版本来源、冲突检测 |
| `~/data/DSHM-deveco-workspace/tools/gen-compat-endpoints.mjs` | 现有兼容表生成入口 |
| `~/data/DSHM-deveco-workspace/.research/protocol/` | 契约快照与来源元数据 |
| `~/data/DSHM-deveco-workspace/dshcompat/src/main/ets/` | 生成兼容定义及必要的既有适配 |
| `~/data/DSHM-deveco-workspace/hostcore/app/` | 宿主、安装、连接与文件等现有功能适配 |
| `~/data/DSHM-deveco-workspace/hostcore/profile/` | 终端、插件与 profile 配置迁移 |
| `~/data/DSHM-deveco-workspace/hostcore/plugins/` | 自带插件兼容及版本约束 |
| `~/data/DSHM-deveco-workspace/entry/src/main/ets/` | 仅必要的 PC/平板既有功能修复 |
| `~/data/DSHM-deveco-workspace/phone/src/main/ets/` | 仅必要的手机/折叠屏既有功能修复 |
| `~/data/DSHM-deveco-workspace/platform/src/main/ets/` | 仅证实必要的共享能力修复 |
| `~/data/DSHM-deveco-workspace/hostruntime/src/main/resources/` | 同步物化后的单一核心容器与资源 |
| `~/data/DSHM-deveco-workspace/tools/` | 已有门禁、OSS 与 Beta 工具的必要修复 |
| `~/data/DSHM-deveco-workspace/dist/acceptance/` | 本轮基线、回归及实物核验证据 |
| `~/data/DSHM-deveco-workspace/dist/beta/` | 新批次交付，不覆盖或删除历史包 |

**Structure Decision**：沿用现有工程架构，不引入 MVVM 迁移、新模块或泛化抽象。以上是责任边界，不要求修改每个目录；每处源码改动必须对应确认问题。

## Complexity Tracking

无架构例外。跨核心与壳层修改限于证实的兼容需求；不把大量历史 git diff 当作本轮纯净变更。

## Research & Decisions

### 1. 固定当前目标并保全现场
- **Decision**：以配方 rc.2+dshm.1 为唯一目标，保留当前未提交内容，实施前记录相关文件状态与比较基线。
- **Rationale**：当前工作树已存在 rc.2，而静态容器仍为 rc.1；需要完成闭环而非另起升级。
- **Alternatives considered**：追最新版本或重置工作区均超出批准范围。

### 2. 协议采集先于生成验收
- **Decision**：修复协议提取器版本来源问题，使用同一提取口径比较 rc.1/rc.2，保留核心与插件扩展来源及冲突证据，再生成兼容定义。
- **Rationale**：当前 158 项快照与更新中的多源采集存在口径差异，历史无漂移不足以证明接口完整。
- **Alternatives considered**：直接信任旧表或删除扩展接口去重会制造假绿，拒绝。

### 3. 行为优先的补丁迁移
- **Decision**：逐项判断上游原生行为、仍需迁移的鸿蒙补丁、旧断言漂移和真实缺陷；必要门禁保留正负对照。
- **Rationale**：预检 10 红并非必然代表 10 个相同层次的产品缺陷。
- **Alternatives considered**：重新注入全部旧补丁或放宽文本检查都可能掩盖故障。

### 4. 单容器物化与来源闭环
- **Decision**：核心或自带插件变更后，使用既有 pack-core 入口重新物化并放入应用，核对源、工作树、容器、manifest、resfile 与 OSS 一致。
- **Rationale**：只编译应用会继续带旧静态核心。
- **Alternatives considered**：手工只替换 zip 名称不能证明内容版本，拒绝。

### 5. 编译与 Beta 身份
- **Decision**：保留 Beta 工具的临时身份/签名及逐字恢复契约；Harmony 编译统一由 devecocli 进行，若现有 Beta 入口直接调用底层构建工具，在实施阶段将必要调用适配至 devecocli，保留原打包校验及恢复语义。最终 Beta 构建由阶段 5 验证代理执行。
- **Rationale**：兼顾项目既有身份隔离与强制 CLI 规范；避免阶段 4 提前消耗正式验证。
- **Alternatives considered**：永久改成 Beta 身份、重新签名或绕过恢复机制均不可接受。

### 6. 环境与知识核验
- **Decision**：官方文档先使用 devecocli docs search/read；当前 search 因 better-sqlite3 本地绑定缺失无法返回文档 ID，不伪造 read 目标。后续先复核可用工具环境；若仍不可用，记录限制，避免引入未经核验的新官方 API。
- **Rationale**：本轮主要沿用已有工程 API，不能把工具不可用当成已查证。
- **Alternatives considered**：凭记忆新增 API 或改动全局 CLI/凭据超出本轮范围，拒绝。

## Data Model

| 实体 | 字段/关系 | 验证约束与状态 |
|---|---|---|
| 同步目标 | 上游版本、本地版本、应用版本、平台 | 固定 rc.2+dshm.1、1.1.8/1010016；配方与实物一致 |
| 契约条目 | 接口名、参数 wire 名、流式/取消属性、权威源、扩展包来源 | 同口径采集；冲突明确失败；不丢必要扩展 |
| 问题记录 | 来源、影响端、复现证据、根因分类、修复落点、相关检查、遗留限制 | 发现→确认→修复/门禁适配→回归；环境不可验单列 |
| 回归结果 | 命令、退出状态、证据路径、前后状态、限制分类 | 比较基线与当前结果可追溯；不得将受限写成通过 |
| 核心产物 | 目标版本、容器摘要、工作树/manifest/resfile 来源 | 实物内容一致；resfile 单容器；保留历史回滚件 |
| Beta 批次 | 身份、应用版本、模块、核心摘要、合包摘要、恢复核验 | 构建→结构核验→待真机测试；失败不得冒充交付通过 |

不新增业务数据模型或用户数据迁移。

## Contracts & Interfaces

1. **配方契约**：目标树必须来自当前 core-recipe；目标不存在明确失败，禁止静默使用旧树。
2. **协议契约**：核心汇总与插件扩展分别保留来源、共同形成完整接口面；重复必须可解释，冲突不得静默吞掉。
3. **平台契约**：PC/2in1/Edge/Pro Max 原生 PTY；普通平板、手机和折叠屏 guest VM；QXS 与既定市场名判据不扩大。壳层特有修复互不污染。
4. **权限契约**：现有权限门禁为唯一判据；entry 18/phone 9 条数、顺序、reason 不变；Beta Profile 限制不通过删权限解决。
5. **核心物化入口**：保留 `CODEBUDDY_SAFE_DELETE_ENABLED=0 node tools/pack-core.mjs --skip-install --place-in-app` 的既有流程与单容器约束，必要时依据实际工作树状态选择既有干净物化支持；禁止删历史交付或未知 pristine 资料。
6. **回归入口**：以 `~/data/DSHM-deveco-workspace/dist/acceptance/20261112-nontablet-postbuild-gates.txt` 为升级前比较源，以 `~/data/DSHM-deveco-workspace/dist/acceptance/20261112-rc2-preflight-gates.txt` 为诊断源；结合当前 CI 清单补齐遗漏。重跑脚本包含写资源行为，只能在批准的实施阶段执行。
7. **Beta 入口**：保留 `CODEBUDDY_SAFE_DELETE_ENABLED=0 node tools/build-beta.mjs --combined-app`，内部 Harmony 编译使用 devecocli。构建前后逐字恢复受临时修改文件，绝不输出签名口令；只对本条构建命令设置安全删除豁免。
8. **部署契约**：先探测设备；仅允许保留数据的覆盖安装，禁止 uninstall/清数据/换签名。Beta 与正式包身份不同，不宣称跨身份原地迁移。无可用通道即记录环境受限。
9. **包核验契约**：核对 pack.info、模块设备面、权限、HSP 内核心摘要与 rc.2 实际版本、必要资源、关键 abc 标识、合包 sha256 及正式身份恢复；不把 SignApp 成功等同于独立验签。
10. **文档契约**：本轮过程证据放 acceptance，已确认当前状态回写 HANDOFF/必要索引，工作记忆 append-only；不新增未验证结论至编号文档。

## Requirements Traceability

| 需求 | 方案覆盖 |
|---|---|
| FR-001、FR-002 | 固定同步目标、配方/产物模型、版本不变核验 |
| FR-003 | 协议多源采集、补丁迁移、核心物化与来源闭环 |
| FR-004 | 问题记录、10 红分类、针对性行为与负控制 |
| FR-005 | 同源基线、完整门禁、前后对比及受限单列 |
| FR-006、FR-007 | 平台/权限契约、分支隔离与共享回归 |
| FR-008 | 现场保全、恢复契约、禁止破坏/提交 |
| FR-009 | Beta 构建入口、临时身份、包核验契约 |
| FR-010 | 批次证据、修复摘要、校验信息和待真机清单 |
| FR-011 | 文档契约与 append-only 记忆 |
| NFR-001 至 NFR-004 | 可追溯证据、增量架构、不新增功能、受限如实报告 |

## 执行边界

阶段 4 仅委派实施、静态/行为回归、核心物化及文档收口，不执行最终应用编译/部署验证。阶段 5 由唯一验证代理完成编译修复循环、Beta 实物核验、安全部署尝试；是否包含 UI 验证由阶段 3 的 tasks.md 选择标记决定。

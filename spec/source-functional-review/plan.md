# Implementation Plan: 当前源码独立功能审查方案

**Input**：~/data/DSHM-deveco-workspace/spec/source-functional-review/spec.md

## Summary

保留用户批准的五阶段评审，但不实施产品改动：阶段 4 为只读源码审查，阶段 5 为独立证据反证复核。按六个功能责任域并行阅读当前实际入口、调用者、状态和错误分支，再跨域核对，输出分级问题清单及覆盖矩阵；不以历史文档、注释或旧门禁绿灯作为正确性依据。

## Technical Context

- **Language/Version**：审查现有 ArkTS、JavaScript、C/C++ 与配置，不升级或修改。
- **Primary Dependencies**：根据当前 core-recipe 及实际安装树识别依赖，查看实际模块实现，不沿用历史版本描述。
- **State Management**：分析现有状态生命周期、异步竞争、资源释放与跨壳差异，不进行状态管理迁移。
- **Storage**：只读检查路径、写入/导入/回滚边界；不打开用户私有数据及凭据内容，不执行存储操作。
- **Testing**：当前源码证据和独立反证优先；仅在检查脚本及其依赖确定无写入、设备、网络状态变化后执行无副作用检查。最小复现只能内存运行并直接输出，不能落项目文件。
- **Target Platform**：当前入口可达的 PC、普通平板、手机和折叠屏分支；不操作设备。
- **Project Type**：现有多模块应用的独立功能实现审计。
- **Performance Goals**：仅报告有调用链证据的阻塞、轮询或资源问题，不虚构设备性能指标。
- **Constraints**：仅写本轮 spec 目录及获批功能索引；禁止源码、配置、资源、旧文档和记忆修改，禁止构建、部署与修复。
- **Scale/Scope**：覆盖两个用户故事、六个审查域，不保证穷尽所有缺陷。

## Project Structure

### Documentation (this feature)

所有新文档限于 `~/data/DSHM-deveco-workspace/spec/source-functional-review/`：spec.md、plan.md、tasks.md、分域审查报告、review.md 与 verification.md。除获批 `~/data/DSHM-deveco-workspace/spec/feature.json` 外不写其他目录。

### Source Code (repository root)

项目根 `~/data/DSHM-deveco-workspace`。以下目录均只读，责任入口已通过当前源码定位确认：

| 审查域 | 当前绝对入口/目录 | 检查重点 |
|---|---|---|
| A 双壳与交互 | `~/data/DSHM-deveco-workspace/entry/src/main/ets/pages/WebApp.ets`、`~/data/DSHM-deveco-workspace/phone/src/main/ets/pages/WebApp.ets`、`~/data/DSHM-deveco-workspace/platform/src/main/ets/system/DeviceFacts.ets` | 形态判定、侧栏、输入、返回、窗口生命周期、桥注册及核心DOM可达性 |
| B 启动会话后台 | `~/data/DSHM-deveco-workspace/entry/src/main/ets/entryability/EntryAbility.ets`、`~/data/DSHM-deveco-workspace/phone/src/main/ets/entryability/EntryAbility.ets`、`~/data/DSHM-deveco-workspace/hostruntime/src/main/ets/runtime/DshHost.ets`、`~/data/DSHM-deveco-workspace/platform/src/main/ets/notify/` | 启停与就绪、连接重试、会话运行取消恢复、前后台与通知 |
| C 终端运行时 | `~/data/DSHM-deveco-workspace/hostruntime/src/main/ets/runtime/RuntimePort.ets`、`~/data/DSHM-deveco-workspace/hostcore/plugins/dshm-vm-bash/lib/`、`~/data/DSHM-deveco-workspace/hostruntime/src/main/cpp/` | 环境下发、终端分派、PTY/VM/QGA状态及释放、取消与路径转换 |
| D 文件插件市场 | `~/data/DSHM-deveco-workspace/platform/src/main/ets/system/FilePicker.ets`、`~/data/DSHM-deveco-workspace/hostcore/app/dshm-installer.js`、`~/data/DSHM-deveco-workspace/hostcore/plugins/` | 授权恢复、工作区、文件读写删除、安装卸载错误传播及市场调用 |
| E 账号云同步 | `~/data/DSHM-deveco-workspace/platform/src/main/ets/system/HuaweiCloud.ets`、`~/data/DSHM-deveco-workspace/platform/src/main/ets/sync/`、`~/data/DSHM-deveco-workspace/hostcore/plugins/dshm-cloud-sync/lib/` | 登录退出、范围、上传导入、冲突隔离、取消、插件恢复及UI错误反馈 |
| F 核心升级契约 | `~/data/DSHM-deveco-workspace/hostruntime/src/main/ets/core/`、`~/data/DSHM-deveco-workspace/hostcore/app/main.js`、`~/data/DSHM-deveco-workspace/hostcore/profile/ondevice/cordis.patch.yml`、`~/data/DSHM-deveco-workspace/tools/pack-core.mjs`、`~/data/DSHM-deveco-workspace/dshcompat/src/main/ets/` | 实际装配、安装切换回滚、数据保全、补丁作用与当前核心接口匹配 |

当前配方指定的实际核心树 `~/data/DSHM-deveco-workspace/dist/core/work/dsh-core-0.2.2-rc.2+dshm.1/` 仅作为当下依赖实物读取；不将其存在视作与随包逐字一致。必要时以只读归档检查核对特定证据，不全量解包写文件。

**Structure Decision**：沿用现有架构的责任边界开展审查，不设计或新增应用模块，不进行 MVVM 或任何其他重构。域间重叠仅用于跟踪调用，防止把死代码当实际功能。

## Complexity Tracking

用户已显式批准将阶段 4/5 从实现及构建部署调整为只读审查/证据复核。此调整是本轮执行契约，不授权任何代码修复。默认构建、部署和 UI 验证任务不得进入本轮任务。

## Research & Decisions

### 证据来源
- **Decision**：当前入口和可达调用链为依据，历史 docs、memory、旧 acceptance 及上轮结论不纳入正确性证据。
- **Rationale**：用户要求排除错误历史口径干扰。源码注释也可能过期，须以执行逻辑核对。
- **Alternatives considered**：先读历史缺陷清单会造成先入为主，不采用。

### 六域并行与跨域复核
- **Decision**：分域独立研究，交接处核实生产者/消费者双方，再由独立复核者重新读候选证据。
- **Rationale**：大文件及双壳相似实现容易漏掉实际接线、异步保护或重复根因。
- **Alternatives considered**：只搜关键词、比对两壳文本或仅跑门禁不足以证明可达缺陷。

### 严重性与确认等级分离
- **Decision**：严重性 P0/P1/P2/P3 与确认等级分别记录；确认缺陷需要具体可达因果证据。
- **Rationale**：高影响猜测仍然是风险，不能因影响大而提升证据确定性。
- **Alternatives considered**：把所有可疑代码统一叫 bug 会误导修复优先级。

### 无副作用验证
- **Decision**：检查及其导入依赖先做副作用筛查，再决定是否运行；无法证明安全则不执行。
- **Rationale**：部分门禁会同步资源、生成文件、启动子进程或写缓存，不符合只读授权。
- **Alternatives considered**：全量重跑旧门禁可能越界，且无法替代逻辑审查。

### 官方行为核验
- **Decision**：涉及 ArkTS 或系统 API 的决定性断言，应先通过 devecocli docs search/read 核验；工具不可用时记录缺口，不能以记忆推定运行故障。
- **Rationale**：静态业务矛盾与系统平台行为需区分，用户要求不受错误口径影响。
- **Alternatives considered**：凭既有经验直接断言某API必失败不够可靠。

## Data Model

| 实体 | 必需属性 | 状态/约束 |
|---|---|---|
| CoverageItem | 功能域、端侧、入口、调用链、已检查分支、未覆盖边界 | 未读/已定位/已审查/证据不足，不将定位等同深入审核 |
| Finding | ID、根因、严重性、确认等级、触发条件、影响端、文件与行区间、实际/预期、证据、建议方向 | 候选→复核保留/降级/剔除；不得输出应用补丁 |
| CounterEvidence | 保护分支、调用者约束、默认值、上游实现、系统证据缺口 | 每个候选至少记录反证检查结果 |
| CheckRecord | 检查名、无副作用依据、执行结果或未执行原因 | 无安全证明不执行；检查通过不直接证明全部功能正常 |
| ReviewBoundary | 实测输入、未操作设备、未覆盖模块、未读私有数据 | PC正常为用户信息；其他端无本轮真机结论 |

## Contracts & Interfaces

- **审查输出契约**：review.md 先列确认问题，再列风险与待验证项，按严重性排序；每条包含触发、影响、位置、因果链及建议。
- **跨域契约**：核对UI动作→桥方法→宿主/插件→实际核心/平台接口→状态反馈，不能只看单个函数。
- **复核契约**：verification.md 逐候选说明保留/降级/剔除及依据；最终清单只能采用复核后结论。
- **安全契约**：阶段 4/5 仅写本轮 spec 目录，禁止任何源码、配置、资源、用户数据、凭据、文档历史或设备变更；不使用会写入的构建、lint修复、门禁和脚本。
- **操作审计契约**：记录本轮允许写入的文档；已有工作区差异不归为本轮审查改动，不回滚他人内容。

需求覆盖：FR-001/002 对应六域覆盖矩阵；FR-003 对应 Finding；FR-004 对应跨域与独立反证；FR-005 对应 CheckRecord；FR-006 对应最终报告及安全契约。C-001至C-005、SC-001至SC-004均由文档隔离、证据分级与独立复核约束覆盖。

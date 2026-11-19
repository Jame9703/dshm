# Implementation Plan: 最小修复、复核与双包交付

**Input**：~/data/DSHM-deveco-workspace/spec/fix-review-dual-release/spec.md

## Summary

保留现有双壳、共享platform/hostruntime及DSHM宿主/插件架构。以本地适配修复为主，保持官方manager恢复、会话格式和Cordis机制；实施阶段完成针对性测试、核心物化、全量回归和独立源码反证，验证阶段再编译核验Beta与AGC两种三端合包。任何条件风险只修证据支持的薄弱点，不承诺未经验证的事故已被复现。

## Technical Context

- **Language/Version**：现有ArkTS、JavaScript及工具脚本，不升级SDK、Node或上游DSH。
- **Primary Dependencies**：当前配方0.2.2-rc.2+dshm.1及实际核心依赖；保留既有官方扩展机制。
- **State Management**：保留既有状态管理，增量完善任务拥有权和代次，不迁移V1/V2或MVVM。
- **Storage**：保留用户profile、会话、工作区和云表schema；新增的安全快照/备份仅服务已有功能，不推测用户路径。
- **Testing**：生产逻辑级正常/失败测试、变异自检、静态检查、同批门禁对比、独立反证、编译及包结构和签名核验。
- **Target Platform**：当前PC/平板/手机/折叠分支；不改设备归属及权限。
- **Constraints**：1.1.8/1010016不变；entry18/phone9不变；保留签名、已有改动、用户数据、历史交付；不提交/重置、不上传AGC。
- **Performance Goals**：文件摘要采用既有流式能力，避免整文件驻内存；保留VM与Host有界停止。摘要与安全迁移可能有首次安装耗时，须记录。
- **Scale/Scope**：11项候选及附属错误；不新增手动映射UI或扩展其他产品能力。

## Project Structure

**项目根**：`~/data/DSHM-deveco-workspace`。下述源码路径均在此绝对根下。

### Documentation (this feature)

- `~/data/DSHM-deveco-workspace/spec/fix-review-dual-release/`：spec.md、plan.md、tasks.md、修复与独立复核交接。
- `~/data/DSHM-deveco-workspace/spec/source-functional-review/recheck-final.md`：问题基准，保留原始结论不覆盖。
- `~/data/DSHM-deveco-workspace/dist/acceptance/`：基线、失败注入、回归、核心一致性及双包核验证据，采用新批次路径不覆盖旧留档。

### Source Code (repository root)

| 绝对目录/文件 | 最小责任范围 |
|---|---|
| `~/data/DSHM-deveco-workspace/platform/src/main/ets/system/FilePicker.ets` | DR1探测对象拥有权与清理 |
| `~/data/DSHM-deveco-workspace/platform/src/main/ets/sync/` | E01/E02/E04/E03/E05请求、映射、任务隔离、内容核验及资产身份 |
| `~/data/DSHM-deveco-workspace/platform/src/main/ets/view/CloudSyncSettings.ets` | 遗漏与冲突反馈、旧任务回调隔离 |
| `~/data/DSHM-deveco-workspace/platform/src/main/ets/notify/KeepAlive.ets` | B01引用拥有权 |
| `~/data/DSHM-deveco-workspace/entry/src/main/ets/`、`~/data/DSHM-deveco-workspace/phone/src/main/ets/` | 必要调用方配平及同步桥反馈，不改其他壳行为 |
| `~/data/DSHM-deveco-workspace/hostcore/app/dshm-installer.js`、`~/data/DSHM-deveco-workspace/hostcore/app/main.js` | D01安装/移除/恢复事务与tmp错误 |
| `~/data/DSHM-deveco-workspace/hostcore/plugins/dshm-cloud-sync/lib/` | 结构化同步结果与取消反馈 |
| `~/data/DSHM-deveco-workspace/hostcore/plugins/dshm-vm-bash/lib/` | C01退出依据及CR2日志作用域 |
| `~/data/DSHM-deveco-workspace/hostruntime/src/main/ets/core/BundledCore.ets` | FR1实际容器身份及安全旧stamp迁移 |
| `~/data/DSHM-deveco-workspace/tools/` | 行为门禁、自检、物化和AGC的devecocli入口适配 |

**Structure Decision**：沿用现有架构，不新增MVVM层、不改官方核心业务算法。可将现有文件摘要能力收敛为platform共享基础组件，文件名在任务阶段依据既有导出确定；避免hostruntime依赖上传编排层。所有实际改动必须对应候选或必要构建适配。

## Complexity Tracking

不引入新架构。D01需覆盖官方manager先remove的真实链，不能只修安装函数；这是跨队列事务复杂度而非重写官方manager理由。必要的官方生命周期适配必须证明本地入口不足、记录最小差异，保留既有恢复控制流。

## Research & Decisions

### 1. 安全探针
- **Decision**：当前ArkTS SDK无公开EXCL枚举，优先使用SDK唯一临时目录建立本次拥有的探测空间；禁止硬编码Native标志或先判断再截断。
- **Rationale**：SDK的mkdtempSync可避免碰触预存同名文件；清理只归本次拥有的对象。
- **Alternatives considered**：随机平面文件加先access存在竞态；新增Native桥扩大改动。唯一目录会保守要求可建目录，不能把这种探测失败宣称所有平面文件不可写；保留已授权路径及既有兜底、明确探测未确认状态，避免无谓封死用户目录。

### 2. 本地安装事务与官方恢复配合
- **Decision**：覆盖本地remove/install队列，以profile、真实包、来源/版本及明确事务身份关联备份、提交与恢复；先核实关联可靠性，再决定是否需要最小官方生命周期适配。
- **Rationale**：官方manager先remove后install，且卸载会改配置，安装入口才备份为时已晚。新版启用失败后的再次remove不能覆盖最初旧版备份。
- **Alternatives considered**：只在installSpecInner保旧无法覆盖真实更新；将所有卸载视为更新会误复活用户主动卸载；整文件盲回滚会覆盖manager合法配置。普通卸载、独立重装、更新失败与恢复必须分别测试。

### 3. 同步请求、任务与遗漏反馈
- **Decision**：按npm版本/alias/Git等来源保持完整请求；映射每次拉取刷新，未映射项保留统计；任务捕获代次/身份/根目录，runner、进度、提交及UI完成回调统一遵守拥有权。
- **Rationale**：仅屏蔽引擎回调不能阻止后续文件/数据库/安装步骤；相同根目录重复attach不应无故取消；旧finally不能释放新任务锁。
- **Alternatives considered**：新增手动映射超范围；只清状态不隔离任务；承诺取消已发系统或安装操作不真实。未完成旧任务排空前保持执行锁是可选保守策略，但界面须如实说明。

### 4. 导入摘要与不可变资产
- **Decision**：复用流式摘要能力核验暂存副本；已有目标摘要相同才幂等跳过，异内容报告冲突不覆盖。缺摘要保持当前拒绝不可信导入的安全行为并明确原因。资产路径与完整unit身份及不可变快照身份绑定，摘要与实际尺寸来自同一快照。
- **Rationale**：不能用收到的文件自算摘要冒充远端验证，也不能依赖未知Asset快照时点；不新增官方格式限制。
- **Alternatives considered**：仅拼basename仍可能碰撞；insert/固定延时不是平台不再引用文件的证明。未登记本次对象可清理，已登记资产不因退出或本批结束立即删除；保留导致空间成本须报告，回收依据不足时不猜测安全时间。

### 5. 引用、VM与核心身份
- **Decision**：配平保活失败、取消、成功和释放路径，保留代次与PC持有策略；VM正常完成仅以捕获worker退出为准，QMP事件仅为控制信号，超时记录未确认退出。日志变量只修作用域。核心stamp绑定容器内容摘要，旧/缺/损坏stamp视为未知，走既有事务安装后确认。
- **Rationale**：不把断连当退出、不把旧builtAt当内容身份；内容stamp仅证明安装来源，不证明运行期整树未被更改。
- **Alternatives considered**：无限等待会挂Host；擅改版本绕过stamp违反需求；直接将旧尺寸认证成新摘要会继续掩盖旧内容。旧stamp迁移可能一次重装，必须测profile与用户数据保全。

### 6. 编译与交付
- **Decision**：Beta与AGC顺序构建，保持各自finally逐字恢复机制；AGC现仍直调hvigor，实施阶段将必要调用适配devecocli，保留release product/release模式、原签名与包校验。禁止两种身份并发构建。
- **Rationale**：同源修复需要共享资源恢复后再编另一身份；不混淆正式ACL与Beta授权限制。
- **Alternatives considered**：直接复制Beta参数到AGC不能保证release语义；修改签名、上传或绕设备信任均不在范围。

### 7. 证据与官方知识
- **Decision**：官方文档先search/read；当前search绑定缺失不能伪造read，关键定义结合当前SDK声明核实并记录局限。修改.ets前加载语法skill并静态检查，编译最终验证。
- **Rationale**：文件EXCL与Asset生命周期不能凭记忆假定，SDK事实与ROM实测分开。
- **Alternatives considered**：修全局CLI或新增不确定API超范围。

## Data Model

| 实体 | 身份/状态 | 不变量 |
|---|---|---|
| ProbeOwnership | 本次唯一目录及文件、创建成功与关闭状态 | 不触碰非本次创建对象，失败清理不扩大 |
| InstallTransaction | profile/包/来源版本/事务ID、旧快照、新候选、提交或回滚 | 普通卸载不误恢复；旧快照不被后续失败覆盖；配置与运行态一致 |
| SyncTask | 代次、账号、根目录、锁拥有者、在途步骤/淘汰 | 旧任务不能回填当前状态、不能投下一业务步骤、不能释放新锁 |
| ImportResult | 成功/相同/冲突/未映射/无法校验/取消 | 未映射不等于无云数据；异内容不无确认覆盖 |
| AssetSnapshot | unit身份、内容摘要、实际尺寸、不可变路径、登记状态 | 不同身份不覆盖；摘要尺寸与登记文件一致 |
| CoreIdentityStamp | 格式标记、容器摘要、安装确认 | 未验证旧stamp不直接升级可信；失败不认证 |
| DeliveryBatch | Beta/AGC身份、模块、权限、核心/包摘要、恢复核验 | 共享源码同源、签名身份分离、正式配置准确恢复 |

不改变云表schema、官方会话格式和用户工作区目录规则。

## Contracts & Interfaces

- **来源契约**：本轮候选与反证来自 `~/data/DSHM-deveco-workspace/spec/source-functional-review/recheck-final.md`；实施前重新核当前入口，不只改旧页面。
- **官方差异契约**：每处触及官方核心的补丁列必要性、最小行为差异、上游保护和测试；优先DSHM本地实现。不能为了门禁通过重写上游代码。
- **测试契约**：覆盖旧同名文件、更新双失败与普通卸载、版本来源往返、映射新增/零项、退出等待/重登录、同长异内容、合法技能碰撞、失败重试引用、QMP greeting/close/timeout、旧stamp迁移及正常路径；新门禁带变异体，模型不能替代生产逻辑验证。
- **顺序契约**：探写→npm恢复→保活/退出/映射→事务安装/内容/资产→VM/核心身份/日志错误；共享基础能力先建立不代表擅自提高低优先功能范围。
- **回归契约**：前后同批门禁并补当前CI遗漏，任何OK→BAD即处理；基线取当前真实实跑，不照搬历史统计。
- **物化契约**：核心/插件变化后经既有 `CODEBUDDY_SAFE_DELETE_ENABLED=0 node tools/pack-core.mjs --skip-install --place-in-app` 同步，核源→工作树→manifest→zip→resfile单容器→OSS。历史交付保留，不拿旧包冒充新修复。
- **复核契约**：实施结束另由只读研究者反证全部候选、正常保护与新引入风险；处理结论后再进入应用构建。
- **构建契约**：阶段4不执行最终应用编译/部署；阶段5唯一验证代理在初始最多10次devecocli build范围内修编译并顺序执行Beta、AGC工具，保留原命令入口及单条安全删除豁免；UI范围由tasks决定。
- **核包契约**：检查两包身份、1.1.8/1010016、entry tablet+2in1/phone phone/共享HSP、18/9条权限与reason、核心实物摘要、关键资源、签名/Profile及配置恢复；具备工具时独立验签，不仅看SignApp。
- **安全部署契约**：仅安全覆盖，不卸载清数据、不换签名或改系统信任；AGC包不强行侧载、不上传；设备受限明确记录，照常交付合格待测双包。

需求覆盖：FR-001/002对应逐项顺序；FR-003对应官方差异契约；FR-004至FR-012对应七项决策与数据不变量；FR-013/014对应测试、回归与独立复核；FR-015对应双包构建核验；FR-016对应新批次证据及当前状态更新。所有安全约束持续执行。

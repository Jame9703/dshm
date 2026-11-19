# E-03 / E-05 当前源码重新核实

## 范围与结论

本轮只负责既有候选 E-03、E-05，不代表已复核其余候选。以当前源码重新取证，`review.md` 仅用于定位候选，不沿用其结论。不读取历史 docs、memory、旧 acceptance 作为依据。未修复代码、配置或资源，未 build/deploy/device，未执行 git 命令、验证代理或业务网络操作。唯一主动写入为本报告。

| 候选 | 整体判定 | 已确认事实 | 影响分级与边界 |
|---|---|---|---|
| E-03 | **条件性存在** | 导入实际入口没有内容摘要验证；已有目标只按大小跳过；新目标只验大小与可读字节，不验会话格式 | 同尺寸内容分歧被静默跳过为 P2；错误资产进入新目标、使重要恢复数据不可用可达 P1，但需额外错误输入/时序条件，未确认真实损坏事故 |
| E-05 | **条件性存在** | 真实允许的技能布局可产生不同 unitId、同绝对暂存路径；后暂存会删除并替换先暂存文件 | 本地暂存路径复用确实存在；若平台在覆盖之后才消费旧 Asset 路径，可导致备份内容错配，潜在 P1。平台同步失败或立即快照也可能阻断该影响，不能称云端必坏 |

“条件性存在”不是“仅凭注释猜测”：以下分别列出源码闭合的局部事实与未闭合的平台/事故条件。严重性指条件成立后的影响，不代表发生概率或所有端必现。

## 官方 Asset 契约证据缺口

首先执行只读检索：`devecocli docs search relationalStore Asset --limit 8`。CLI 返回 `Could not locate the bindings file`，缺少 `better-sqlite3` 对应 OpenHarmony 原生绑定；没有得到 documentId，故无法继续有效的 `devecocli docs read`，未伪造 read 结果。没有安装依赖或修复工具环境，也未改用业务网络请求。

本轮不能确认以下平台语义：

- `RdbStore.insert` 是否同步复制 Asset 文件内容到平台私有快照，还是只登记路径及属性。
- `insert` 返回后是否允许调用方删除/替换 Asset 的 path；平台是否保留 fd、复制 inode、改写 path，或对共享路径做去重。
- `autoSync` 的具体启动时点、文件读取时点，以及 `cloudSync` 成功对“行元数据和文件内容一致”的保证范围。
- 云资产下载的校验覆盖传输完整性、平台内部摘要，还是也保证业务 `sha256` 列与 payload 内容匹配。

`SyncStore.ets` 中标为“官方”的源码注释不是本轮官方证据。即使平台保证上传下载字节无损，也不能自动推出其会核对业务表中的独立 `sha256` 字符串，或核对本机 sessions 目标内容。反之，没有应用层 digest 也不能反向证明平台会损坏文件。

## 路径与入口全链

以下路径均相对工程根。短名前缀 `S/` 表示 `platform/src/main/ets/sync/`；`C/` 表示当前配方对应的 `dist/core/work/dsh-core-0.2.2-rc.2+dshm.1/node_modules/@deepseek-ai/`。核心版本对应关系来自 `hostcore/core-recipe.json:3`，不是历史报告。依赖 work 树只作为当前可读上游实现，不宣称已与实际安装包逐字核对。

### 真实动作与根目录

- 网页插件 `hostcore/plugins/dshm-cloud-sync/lib/client.js:197–205,603–604` 发送 `upload` / `pull`；入口并非只有未接线的导出函数。
- entry 的 `entry/src/main/ets/pages/WebApp.ets:4324–4353,4513–4517` 先注入根、做动作判定，再调用 `SyncEngine.syncNow` / `pullAndImport`。phone 的同名文件 `4121–4125` 同样直接调用共享引擎。
- 原生面板 `platform/src/main/ets/view/CloudSyncSettings.ets:511–522` 也直接调用 `pullAndImport`，没有额外 digest 校验；返回空串显示“拉取并导入完成”。
- `S/SyncActions.ets:104–118` 的上层检查只有登录、忙状态、上传开关，不读文件。`S/SyncState.ets:40–48` 注入 `<filesDir>/dsh/home/sessions` 和 profile。
- `S/SyncEngine.ets:323–351` 上传要求开启、登录、目录就绪且无同引擎任务；扫描 sessions，以及 home 下 attachments、skills，再合并交 runUpload。`394–438` 拉取要求登录、目录就绪、无任务，先启用云同步并等待拉取结果，再发现候选并运行导入。
- `S/SyncEngine.ets:458–477` 只把本地已有 `--…--` 工作区名转换为映射；未知 workspace 在 `S/ImportRunner.ets:155–159` 被排除。因此任意云行不能无条件落到全新未知工作区；下述 E-03 输入均要求映射存在。

### 命名域矩阵

| 对象 | unitId / 源目录 | 暂存或目标路径 | 隔离结果 |
|---|---|---|---|
| 会话 | `session/<wsHash>/<encodedSessionId>:v<N>`；源为 `sessions/<projectKey>/<id>/<canonicalLog>` | 上传名 `<id>-v<N>.jsonl.zstd`；导入为 `sessions/<mappedProjectKey>/<id>/session[.vN].jsonl.zstd` | 导入目标有工作区与会话目录隔离；上传暂存名没有工作区 |
| 附件 | `attachment/global/<完整rel>`；源为 `home/attachments/<rel>` | rel 的 `/` 换 `_`，再 Store 安全化截断 | 源路径有目录隔离；暂存路径丢失层级，也不带 kind |
| 技能 | `skill/global/<完整rel>`；源为 `home/skills/<rel>` | 同附件算法 | skill 与 attachment 的 unitId 分离，暂存目录不分离 |
| 插件清单 | `plugin_manifest/global/current` | 固定 `plugin-manifest.json`，同一暂存根 | 不与技能/附件另建目录；特定技能资源同名也能共用路径 |
| 设备/日期 | 行列 `device_id`、`uploaded_at` | 均不进入 unitId、暂存目录、文件名或导入目标 | 不形成每设备/每日期不可变快照命名域 |

依据：`S/SyncPlanner.ets:158–185,259–270`、`S/SyncModel.ets:165–168`、`S/SyncStore.ets:200–225,243–258`、`S/SyncEngine.ets:528–562`、`S/ImportRunner.ets:270–272`。`makeUnitId` 只 trim key，未将不同 rel 安全化为同一 key；本报告技能例没有前后空白，不依赖 trim 的另一个问题。

`S/SyncStore.ets:92–119` 的设备 ID 来自本机文件或型号加随机后缀，仅写设备列；`UploadRunner.ets:170–174` 的时间也仅写列。日期/设备 UI 意图或源码注释不是目录隔离。`upsertUnit:243–258` 对相同 unitId 删旧行再插，并无日期分版。

## E-03：同尺寸跳过与未校验 SHA

### 正向证据

1. `S/ImportRunner.ets:150–179` 从 session 行读取记录 sha、bytes、Asset.path/size，未计算资产摘要，也未读取 Asset.status；`assetSize` 虽收集但后续未参与判定。
2. `240–267` 只检验 sha 文本形态、资产路径非空、stat 可读及文件大小等于行 bytes。`S/SyncModel.ets:375–387` 是十六进制文本判断，不是哈希计算。
3. `273–289` 本地已有目标时，`stat(target).size === c.bytes` 就 SKIPPED；不读目标内容，不比较 sha。不同大小则失败且不覆盖。
4. 新目标在 `296–315` 复制到 cache staging，复验大小后 rename；`337–363` 只验目标存在、大小以及最多读 64 字节能得到 `n > 0` 就 OK。没有 zstd 解码、header/version/id/cwd、JSONL 或事件格式验证。
5. 引擎 `421–438` 的拉取成功检查没有在上层补业务摘要校验。全工程对 `runImport` / `discoverImportCandidates` 的调用搜索只找到引擎这一条生产消费链，另有 `platform/src/main/ets/Index.ets:218–219` 导出。
6. 全工程搜索 `sha256OfFile` 只找到上传计算及插件清单上传，未找到导入校验包装。`decideAction` 虽在 `S/SyncModel.ets:330–347` 实现摘要冲突判定，但生产导入未调用；搜索消费仅有定义与 tools 模型检查。`loadUnitIndex` 也未在上传或导入主流程使用。

### 上游保证与反证

- 上传并非完全没有摘要：`S/UploadRunner.ets:69–95,135–176` 流式哈希 sourcePath，之后才复制 sourcePath 至 Asset，再写行 sha。正常静止源文件可得到一致 sha/bytes/payload。
- 扫描 `platform/src/main/ets/system/SessionSyncScope.ets:170–201` 限工作区形态及规范代际文件名，记录 stat 大小；但不解析文件内容。这是范围约束，不是内容真实性证明。
- “同代际永远同字节”不成立。上游 `C/dsh-session-persistence-jsonl/lib/index.js:969–977,2955–2961,3341–3355` 通过当前格式同一路径以 `open(path, "a")` 追加事件并 fsync。version 是格式版本，不是每次会话变更的内容快照序号；不能将迁移旧代际保留规则扩大到当前日志永不变。
- 上游 `create:2499–2513` 拒绝本库已有 session，`open:2554–2573` 有单写者租约，`persistContiguous:257–274` 验事件连续性。这些保护上游写操作，不是同步扫描器取得的读锁，也不提供跨设备全局禁止分叉。
- 常规 UI 新建会话确有随机 ID：`C/dsh-api-session-controller/src/agent.ts:433` 使用 `session-${randomUUID()}`。不能把两个独立新建会话碰巧同 ID 作为常见触发；下述分叉例使用已恢复的同一会话，不依赖 UUID 碰撞。
- 上游 encodeSegment 是单段注入式编码（`C/dsh-session-persistence-jsonl/lib/index.js:892–903`），原会话树有工作区/会话层级隔离，不能把暂存名碰撞等同于原 sessions 源文件本来相同。
- 上游读取会做校验：`3182–3214,3510–3519` 核对 header 版本/ID/物理路径；`1330,1408–1417` 的 zstd 帧有 checksum、解码时验证。这可能拒绝后续打开错误文件，降低“静默使用坏内容”的范围，但发生在导入报告 OK 之后，不会补回本次导入摘要或同尺寸冲突结果。
- 无本轮真实坏云资产、已安装同尺寸分叉会话或设备日志样本；不据此声称现有会话已损坏。

### 可触发数据与证据强度

**例 1：同一会话恢复后分叉，本地同长不同内容。** 两台设备已有相同工作区编码（或可映射工作区）、同一已恢复 session、相同格式 v4；各自继续追加不同事件。如两份压缩日志最终长度相同，则远端 sha/资产即使完全正确、本机目标也会被 `277–283` 判为 SKIPPED，报告不提示分歧。原目标不会被覆盖，直接影响是恢复/冲突反馈错误，不是主动销毁本机原文件。需要等长这一条件，正常追加并不保证等长。

本轮纯内存使用 Node 内建 crypto/zlib，把同一 header 帧与不同文本事件帧拼为带 checksum 的 zstd 日志容器，找到 `branch-0001` / `branch-0002` 两份均 196 字节：sha 分别为 `3ce3a27df3cc734b6006a3e13c081b222c6a2702f3f3e03822e2a6cf4d850720` 与 `a8e586faa11c87ec8871f120f7297d5307a06b02b1738522fc9bd51f15b6d868`。它证明实际压缩容器也可等长异内容，不只是抽象字符串长度反例。该事件简化模型未通过生产事件 schema 验证，不冒称实际完整合法会话复现；合法分叉等长的具体生产样本仍缺。

**例 2：错误内容资产进入新目标。** 映射有效、目标不存在，行 sha 为 `SHA256(AAAA)`、bytes=4，Asset 文件实际为 `BBBB`。实际检查会接受大小和正数读取量，导入记 OK；这是当前消费者的确定反例，能由可编辑源会话文件或错误生产者/资产关联产生，不要求伪造 SHA 文本形态。扫描器并不限制源内容，但正常无变更 runUpload 会计算实际内容 SHA，不会自动产生这个特定 sha/内容矛盾，故不能凭此例证明正常云链路已产生坏行。随后上游 zstd/格式解析很可能拒绝它，而不是必然当合法对话使用。

**例 3：真实上传流程的读取窗口。** `SessionSyncScope` 先 stat，runUpload 后异步读 hash，再单独 copy source；未持上游写租约或取得文件快照。当前代际可并行追加，因此“扫描时 bytes、hash 所读字节、copy 所读字节”并无应用层原子一致保证。普通增长多会被导入大小检查拦下，不能据此直接构造必然等长错配；同长替换、分叉或先增后回退需要额外条件。若平台保证传输文件原样，也不能替代上传前源快照的一致性。

因此 E-03 不是误报，但整体保留**条件性存在**：无摘要消费和大小等价判据确实存在；实际损坏数据到达及严重结果没有平台/真机闭环证据。同尺寸静默跳过影响按 P2 表述；新文件错误落位的 P1 为条件性上限。

## E-05：资产安全化碰撞

### 正向证据与时间顺序

1. `S/SyncPlanner.ets:226–270` 对附件/技能递归到 depth 6，按原 rel 构 unitId，却将 `/` 改 `_` 构 assetName。不检查扩展名、技能 frontmatter 或内容摘要命名。
2. `S/SyncStore.ets:202–215` 统一使用 `<distributedFilesDir>/dshm-sync-assets/<safeName>`；safeName 把非 `[A-Za-z0-9._-]` 替成 `_` 后截取前 120 字符。已有 dst 先 unlink 再 copy。路径不含 unitId/hash/kind/workspace/device/date。
3. `S/UploadRunner.ets:129–188` 顺序执行：哈希源 A，暂存 A，构造 Asset A，await 删/插行 A；再处理 B。Asset A 的 `path`/`uri` 是当时 dst 的字符串；构造对象本身没有读取字节的应用代码。
4. `S/SyncStore.ets:217–225,240–258` 行保存传入 Asset 描述；应用未在 insert 前后检查文件 sha 与 unit.sha 一致，也未把每 unit 内容复制到独有保留目录。是否由平台内部另做快照，未知。
5. `S/UploadRunner.ets:190–206` 批内文件都处理后才显式 enable + cloudSync，故首次尚未开启自动同步时，显式同步调用位于覆盖之后。已启用过则 `S/SyncStore.ets:292–296` 的 `autoSync:true` 可能使各 insert 更早触发消费；没有逐 unit 等待云资产完成后再覆盖的代码。
6. `S/UploadRunner.ets:213–224` 末尾只核对表统计，不读回各 payload 内容或 digest。不同 unitId 仍可使行数正常，统计不能检测暂存路径别名。

### 真实可允许的碰撞输入

**首要反例：两种合法技能布局同时存在。**

```text
<home>/skills/demo/SKILL.md
<home>/skills/demo_SKILL.md
```

第一份内容可为 `---\nname: demo\ndescription: first\n---\nAAAA\n`，第二份为 `---\nname: other\ndescription: other\n---\nBBBB\n`。技能名称合法且不同，文件路径合法，深度在限制内。上游 `C/dsh-skill-filesystem/lib/index.js:181–185,595–625,678–717` 同时接受目录的 `SKILL.md` 与根下 `.md`，名称从 frontmatter 读取而非强制等于文件名；`C/dsh-skill/lib/index.js:17,29–30` 名称规则允许 demo/other。因此该例不是“只有垃圾文件才能构造”的碰撞，也不要求上游生成含斜杠的单个文件名。

规划产生：

```text
unit A = skill/global/demo/SKILL.md
unit B = skill/global/demo_SKILL.md
asset A = asset B = demo_SKILL.md
dst A = dst B = <distributedFilesDir>/dshm-sync-assets/demo_SKILL.md
```

合并计划按 unitId 排序（`S/SyncPlanner.ets:324–325`），本例 A 在 B 前。B 暂存替换 A 暂存；原始两个 skills 文件完全不同目录且不被 stageAsset 修改，覆盖的是中转资产，不是源技能文件。反例也不需要两个并发上传任务，running 锁不能阻止同一批串行覆盖。

本轮纯内存 Map 模型复刻上述排序和路径生成，输出 A 的路径已不是自己的原字节、B 仍是自己的原字节。模型明确只验证路径保留行为，不模拟 RDB 或证明平台没有快照。

**其他可达路径类：** `skills/a b.md` 与 `skills/a_b.md` 在 Store 阶段合并；两个前 120 字符完全相同但后缀不同的正常长度文件名也合并。技能扫描不要求文件 basename 等于技能 name。不同 kind 还可由附件真实 rel 对应的平铺名称出现在 skills 资源文件中，或 `skills/plugin-manifest.json` 与后续固定插件清单同名；扫描器没有 md-only 限制。不过这些扩展例不是主结论必需条件，未发现现有用户实际文件对。

### 附件上游保证：不能滥报不同内容碰撞

`C/dsh-attachment-local/lib/index.js:275–298,445–447,698–721,1031` 表明附件使用完整 64 位 hex SHA 路径，图片为 `v1/objects/<前2位>/<sha>`，文件别名为 `v1/files/<前2位>/<sha>/<name>`，另有 `v1/file-objects/<前2位>/<sha>`。保存时 hash 内容且做不可变发布，读取还有 `637,775` 的 digest 校验。

这些正常源路径在安全化之后仍保留完整 SHA（短于 120 字符处已完整出现）；不同 digest 的常规附件不会仅因普通原文件同名就碰撞。不能把“用户上传两个都叫 photo.png”直接当 E-05 的不同内容反例。

相同 digest 下的长文件别名可被 120 截断碰撞，但其字节按上游保证本来相同。本轮内存计算了 `v1/files/aa/<64个a>/<43个n>A.txt` 与同前缀 `B.txt`，输出同暂存路径，同时明确 `differentContentProven:false`。这只证明别名损失，不证明内容损坏。不同 digest、人为 SHA 碰撞或越过上游保证不能凭空补入。

跨 kind 没有此保证：skills 目录不是附件内容寻址库，技能/资源内容可任意，故附件内部内容寻址不能消除技能主反例。

### 保留、清理与实际读取

- 对全工程生产源码搜索 `ASSET_DIR`、`dshm-sync-assets`、`stageAsset`、`distributedFilesDir`，本轮命中的该暂存目录创建/覆盖入口就是 SyncStore.stageAsset，调用者为 runUpload 和插件清单上传。
- 该链没有按完成状态清理旧资产、引用计数、日期保留期或 per-unit GC；不传入后续文件的 unitId/hash，也不检测安全化碰撞。每次碰到同名都会删除旧暂存，即使其对应行来自较早任务仍在表中。
- `S/SyncStore.ets:243–258` 的删行仅按本次 unitId，不删除其他 unitId 的旧行；A/B 不同 unitId 所以不通过数据库主键去重互相排除。代码也没有实际事务包围删/插，不能把注释“同一事务”当额外保护。
- 插件清单在 `S/SyncEngine.ets:351–359,539–563` 的普通上传返回后暂存并插行，仍用共享目录；没有独立不可变快照命名域。读取 `576–593` 从查询的 Asset.path 直接 readText，不补 digest。
- 导入器当前只取 `kind='session'`（`ImportRunner:150–152`），因此主技能碰撞不意味着立刻覆盖正式 sessions，也不能据此宣称技能/附件已经在新设备导入为错误文件。实际可确认的是上传中转不再保留 A 的文件路径内容；云备份错配与后续恢复影响有平台语义前提。
- 如果平台在 A 的 insert 返回前已保存独立字节快照，那么 B 覆盖公共路径未必影响 A 的云资产；若持有旧 inode 的 fd 也可能隔离本次 unlink/copy。反之，若只保留路径并在显式 cloudSync/后续 autoSync 才打开，A/B 可读到同一份 B 字节。若平台检测到 size/属性异常并报错，则可能表现为同步失败而非静默错配。以上均非本轮已获官方证实的语义。

因此 E-05 不剔除：合法技能输入与同路径替换已闭合，不依赖理论哈希碰撞。整体仍判**条件性存在**，而不是“确实已经损坏云备份”；潜在 P1 必须随 Asset 生命周期缺口一起陈述。

## 验证边界

只运行了官方文档只读搜索，以及两条 `node -e` 纯内存 stdout 模型。模型仅导入 Node 内建 crypto/zlib，未 production import、读写用户数据或发业务请求。未运行工程测试/门禁，也未把旧门禁结果当依据。

全局检索覆盖共享同步模块、双壳动作入口、网页插件动作、当前依赖的会话存储/格式、技能文件系统与附件存储。检索与关键调用点重新阅读不等于逐行通读全仓。未取得官方 Asset 契约、真实云数据、平台快照时序、安装包一致性或设备复现证据；报告中的分叉容器与错误四字节模型都未冒称生产完整格式验收。

结论可被进一步证据收窄：证明平台 insert 固定独立内容快照可降低 E-05 云端错配风险；证明端到端业务摘要保证可降低 E-03 错误云资产风险，但不会使本地目标同尺寸即同内容成立，也不会改变暂存命名非单射这一源码事实。

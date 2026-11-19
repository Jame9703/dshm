# 源码功能复核最终问题清单

## 最终裁定

四组报告均已完成，本文件替换此前“仅因报告缺失而全部待证”的占位结论。以下独立整合十一候选，结合当前源码定向复读关键反证，不沿用旧清单的确认数量。

| ID | 最终状态 | 严重性 | 最小成立结论与影响边界 |
|---|---|---|---|
| DR1 | **真实** | **P1，SDK 契约下的条件触发破坏操作** | 固定探针以 CREATE/READ_WRITE/TRUNC 打开，预存同名可写文件会被截断并可能删除；下载根启动路径跨端可达。不是已确认真机事故 |
| E01 | **真实** | **P1** | npm 恢复丢失独立 name，只把版本 spec 投递安装器，无法保证恢复原包；不覆盖全部来源/全部 profile |
| E02 | **真实** | **P2** | 有同路径自动映射建立路径，但无显式远端到本地映射与遗漏反馈；非空映射缓存不重扫，未映射会话可被静默排除 |
| B01 | **真实** | **P2** | 失败申请留下 refs，主 caller 放弃 held；后续成功再单次释放不能配平。未证明具体系统通知/耗电表现 |
| E04 | **真实** | **P2** | 退出未隔离旧在途任务，旧任务继续后续步骤并回填进度/结果；不等于重新登录，不指控跨账号泄漏 |
| CR2 | **真实** | **P3** | 卸载统计回调访问块外不可见变量并抛 ReferenceError；Cordis 隔离异常，不证明宿主崩溃或 VM 泄漏 |
| D01 | **条件性存在** | **条件性 P1** | 删除旧包机制真实；标准有恢复的 manager 更新需新版安装和旧版重装均失败才留下缺包，不能说一次失败完全无恢复 |
| E03 | **条件性存在（整体严重影响）** | **P2 事实；P1 损坏条件风险** | 导入不消费内容 SHA、同尺寸即 skip 已确认；错误资产导致重要恢复数据不可用的 P1 尚需输入/时序及实际影响证据 |
| E05 | **条件性存在** | **潜在 P1** | 合法技能路径产生不同 unitId、相同 staging path 已确认；云资产错配取决于平台消费/快照时点 |
| C01 | **条件性存在** | **潜在 P1** | 任意 QMP data（包括 greeting）可经 destroy/close 提前结束 stop 等待；worker 尚未退出时 Host 可进入退出链，镜像损坏未证实 |
| FR1 | **条件性存在** | **P2 条件风险** | 大小 stamp 非内容身份；无 stamp 且旧 builtAt 非空可跨尺寸跳过并补写当前大小。无实际旧/新容器与已装树事故样本 |

“真实”表示可达源码因果及所需语言/API 契约已闭合，不表示每个用户必触发或已有事故。“条件性存在”表示局部实现事实已成立，但候选的最终用户损失仍依赖未闭合条件。普通触发前提与未知平台保证不是同一层次：DR1 已有 SDK 明确截断语义，不能与 E05 尚未知的 Asset 快照时点混为一谈。

## 证据口径

- 输入为 `spec/source-functional-review/recheck-install-files.md`、`recheck-sync-flows.md`、`recheck-sync-assets.md`、`recheck-runtime-core.md`；旧 final 仅用于确认被替换内容。本次未读取历史 docs、memory、acceptance，也未读取旧 review/verification 作为新证据。
- 本次只读定向核对了 installer 删除与 TDZ、manager 更新恢复、FilePicker 探针/下载根/启动认领、当前 SDK 枚举、npm 清单与恢复投递、映射/导入/退出控制流、资产规划与暂存、合法技能布局、KeepAlive 与 phone caller、VM stop/Host 退出、卸载变量与 Cordis 捕获、BundledCore 跳过分支。不重复全域研究，不声称逐字全仓已读。
- 下文均为项目相对路径及行号。为使实际依赖定位精确，`C/` 统一展开为 `dist/core/work/dsh-core-0.2.2-rc.2+dshm.1/node_modules/@deepseek-ai/`；`S/` 统一展开为 `platform/src/main/ets/sync/`。这两个是路径缩写，不代表另一份源码或虚构展开行号。
- 本次未执行生产入口、纯内存模型、业务网络、构建、部署、设备操作、门禁或 git。四组所述纯内存模型只说明其各自的语言/顺序/路径反例，不能当成生产业务最小复现；本次没有新增或冒领这些实验。
- 本次唯一主动写入是本文件；没有修复或改动任何源码、配置、资源、其它报告或 memory。

## 真实问题

### DR1：固定名可写探针会破坏预存同名文件

**定位与事实。** `platform/src/main/ets/system/FilePicker.ets:162,385-398` 使用固定名 `dshm-write-probe.tmp`，按 `CREATE | READ_WRITE | TRUNC` 打开，写入 `ok` 后 unlink。`394` 的 created 仅表示打开成功，不代表本次新建；`401-419` 的异常清理也可能继续删除该路径。没有独占创建、原内容备份或本次文件所有权验证。

**系统契约。** 当前工具链 SDK 的 `ets/api/@ohos.file.fs.d.ts:147-173` 明确规定 CREATE 仅在不存在时创建，TRUNC 在已存在且写/读写打开时长度清零；`platform/src/main/ets/system/FilePicker.ets:30` 导入的是 CoreFileKit fileIo，不是 Node fs。SDK 完整外部路径为 `/data/service/hnp/hmos-clt.org/hmos-clt_1.0.0/sdk/default/openharmony/ets/api/@ohos.file.fs.d.ts`。本次直接复读了该声明，非仅引用项目注释或类比 POSIX。

**触发与入口。** 目标目录已有准确同名普通文件、操作获准且 open 成功。`FilePicker.ets:578-591` 的应用 Download 根探写没有 handheld/persisted 闸门；`703-725` 认领函数通向 `hostruntime/src/main/ets/runtime/NodeRuntime.ets:251-261,365-377` 的启动链，phone 宿主入口见 `phone/src/main/ets/entryability/EntryAbility.ets:932-934,984`。因此跨端应用下载根可达，不限桌面选目录。

**全局保护与缺口。** 任意所选目录的直接探写受非手持且 persisted=false 限制，见 `FilePicker.ets:335-346`、`entry/src/main/ets/pages/WebApp.ets:3541-3555`、`phone/src/main/ets/pages/WebApp.ets:3315-3329`；这不能阻断另一路下载根探写。认领缓存 `FilePicker.ets:704-710,735` 减少同进程调用，不保护第一次的既存文件。open 被拒绝且未改文件时不成立；无同名文件时只是正常临时文件操作。Node 侧原子写不包围 ArkTS 直调，catch/fallback 不能恢复清零前的字节。

**影响裁定。** SDK 证实条件下的既存文件截断/删除，P1；仅限探针对应文件，不是全目录、任意全盘文件或每次选择目录都损坏。尚无实际 ROM/权限状态与用户文件事故复现，不能写“真机已丢数据”。

### E01：npm 插件恢复投递丢包名

**定位与事实。** `hostcore/app/dshm-installer.js:1125-1160,1659-1661,1688-1690` 将 npm 包保存为 dependencies 的 name→版本范围；`S/PluginManifest.ets:134-157,190-196` 保留独立 `{name,spec}`。`S/PluginRestore.ets:173-177` 却只把 `s.spec` 交 installOne，`114-123` 将其原文写 req；事后的 `r.name=s.name` 仅修饰显示。`hostcore/app/main.js:8777-8817,8838-8839`、`hostcore/app/dshm-install-command.js:145-166` 没有补名通道，installer `567-586,603-631` 会按版本文本作包名查询。

**触发与用户影响。** 清单含普通 npm 用户包如 `{name:sample-plugin,spec:^1.2.3}`，目标缺包，用户勾选安装，实际请求变为 `^1.2.3` 而非完整标识。原包恢复失败或请求了非预期目标，P1。触发 UI 为 `platform/src/main/ets/view/CloudSyncSettings.ets:534-586,929-973`；两端当前 Web 桥都接共享引擎，不是旧 Settings 页推断。

**全局保护与缺口。** installer `685-698` 会给包内依赖补 name，但在顶层解析后才调用，不救本项。换 registry 不补名；版本差异默认保留本机是合理防替换保护，不是缺陷。完整 GitHub spec 不受这个最小反例覆盖。默认种子 dependencies 为空，独立 profile/外部市场不一定纳入此清单；未证明所有插件都失败、现有插件被删，或当前用户已经遇到恢复失败。

### E02：映射可自动建立，但遗漏不可见且非空缓存不刷新

**定位与事实。** `S/SyncPlanner.ets:66-75,151-183` 按完整 projectKey 生成 workspaceId。`C/dsh-session-persistence-jsonl/lib/index.js:914-943,3237-3263` 的普通会话物化建立目录，是实际自动映射建立路径；`S/SyncEngine.ets:458-477` 从已有 sessions 项目目录自动生成映射。不能再写“完全没有映射建立入口”。

`S/ImportRunner.ets:143-159` 直接排除未映射远端会话，不生成遗漏 outcome；`197-214,377-390` 仅统计过滤后的候选，零候选可成功。`S/SyncEngine.ets:433-441` 及 `platform/src/main/ets/view/CloudSyncSettings.ets:511-522` 将其呈现为完成。`SyncEngine.ets:459-461` 非空缓存直接复用，空缓存才重扫；`206-235,271-281` 的 attach/登录/退出不清映射。

**触发与用户影响。** 远端有 session，但本地没有对应 workspaceId，或非空缓存建立后才物化新增目录；拉取成功却零项/部分完成，遗漏原因不可见。P2，不是要求系统猜目录。

**全局保护与缺口。** 同 cwd 且已有对应项目目录时可恢复；拒绝未知目标本身是安全保护。已检查动作与面板没有显式远端 ID→本地目标映射，见 `S/SyncActions.ets:23-29,69-130`、`CloudSyncSettings.ets:390-648,650-980`；普通选目录不等于云映射。不能保证“建目录后再拉一次”绕过非空缓存，也不能断言所有换设备恢复均失败。未取得实际云行/新设备恢复实例。

### B01：保活申请失败的引用未配平

**定位与事实。** `platform/src/main/ets/notify/KeepAlive.ets:364-385` 先 refs++，失败不退回；`388-426` 吞系统异常返回 false。phone 主 caller `phone/src/main/ets/entryability/EntryAbility.ets:1778-1795` 失败仅清 held，`1799-1809` 仅 held=true 时 release。phone 的轮询/30秒退避见 `1689-1700,1771-1775`。entry 手持对应路径为 `entry/src/main/ets/entryability/EntryAbility.ets:2012-2108`，可由多次后台/熄屏进入，不套用 phone 固定轮询节拍。

**触发与用户影响。** 失败→重试成功→回前台，一次 release 后仍留 refs；`KeepAlive.ets:429-444` 正引用提前返回，遗漏 stopBackgroundRunning。无需并发即可证明拥有权失配，P2。通知残留、耗电、系统自动取消或冻结的实际表现未证实。

**全局保护与缺口。** generation 仅收回晚到成功，不补 false 分支；phone 备用 `EntryAbility.ets:1879-1886` 确有失败 release，但不包围主路径。主窗销毁 forceRelease（entry `1228-1231`、phone `1154-1157`）及重启可清旧计数，不是普通前台保证。用户手动停止在 refs++ 前拒绝；PC 常驻持有本身不是本问题。entry 完成通知可额外 release，但不是每次回前台必经的配平路径。

### E04：退出后的旧任务继续并回填状态

**定位与事实。** `S/SyncActions.ets:91-94` 不按 busy 拒绝退出；`S/SyncEngine.ets:271-281` 清身份/开关/显示，却不推进代次或隔离在途任务。上传 `323-377` 只在开始检查身份，await 后继续插件清单上传及结果写回；拉取 `394-447` 同样继续发现/导入与云状态写回。恢复 `620-637`、`S/PluginRestore.ets:173-180` 也不淘汰旧任务。

**触发与用户影响。** 上传/拉取/恢复 await 期间退出，旧任务随后恢复执行；进度、最近结果、连接/错误状态与完成 notice 可被旧回调重新写入，应用后续步骤仍可执行。P2，限定为任务与状态隔离缺口。

**全局保护与缺口。** `S/SyncEngine.ets:333-336,401-404` 的 running 防新上传/拉取并发，不是取消旧任务。旧任务不重写 unionId/enabled，不是自动重新登录；网页 `hostcore/plugins/dshm-cloud-sync/lib/client.js:527-568,618,689-698` 和原生面板 `CloudSyncSettings.ets:722-775` 隐藏未登录区，故不保证退出后立刻看到“已连接”。重登录与旧任务完成的先后影响显示。系统是否终止云调用、系统账号切换后的数据库归属未确认；跨账号泄漏证据不足，明确不作指控。

### CR2：卸载统计日志的块作用域错误

**定位与事实。** `hostcore/plugins/dshm-vm-bash/lib/index.js:312-314` 的 takenTerminal/delegatedTerminal 是 if 内 let；块外 `413-419` 的卸载 effect 模板引用它们，求值时 ReferenceError，进不到 `69-75` 的 log 内 try/catch。

**触发与用户影响。** enabled、runtime.spawn 可用、未 WRAPPED 且 apply 完成注册后卸载/重载/root dispose；不要求 VM 已启动或 terminal takeover 分支为真。P3：统计日志丢失并产生错误记录。

**全局保护与缺口。** `C/cordis/lib/index.js:693-706` 逐项 catch 并发起其他清理；shutdown hook 删除和预热 timer 清理是独立 effect（插件 `254,410`）。本 effect 内没有被跳过的实际资源释放语句。不能扩大为宿主崩溃、VM 泄漏或 C01 的根因。

## 条件性问题

### D01：换版不事务保旧，标准恢复也失败时才留下缺包

**定位与实现事实。** `hostcore/app/dshm-installer.js:1398-1421` 在确认版本漂移后记录版本字符串、删除旧目录，再下载新包；`1434-1437` 才解包临时目录。不是先保留旧目录到新包验证完成。队列失败收尾 `hostcore/app/main.js:8848-8882` 只回执/释放 busy。

**必须保留的反证。** 当前 Web 更新调用 `C/dsh-client-ui-plugin-manager/lib/client.js:2` 字符列约 160687 的 updateBundle；`C/dsh-plugin-manager/lib/index.js:2691-2715` 先校验更新计划，`2762-2791` 的 HMR 分支 remove→install→失败后 install previous，**确有旧版恢复尝试**。旧来源重装成功即恢复可用，不能再称“新版一次失败完全无恢复”。恢复是重新获取旧来源，不是把本地保留目录改名复原。

**触发与裁定。** 标准有兜底更新实际移除成功后，新版安装失败，且旧版重装也失败，才留下旧安装缺失，按条件性 P1。`2735-2742` 无 HMR 分支直接安装不套这层恢复；直接 req/CLI 同样不一定有 manager 包围层，但本次没有设备 HMR 状态/CLI 可用性证据，不能据此扩大为标准 UI 单失败必丢。

**入口与全局保护。** 当前添加 UI 在同长行字符列约 168870 有 already-installed/shipped 保护，manager `3042-3044` 亦会拒绝部分重复安装。旧 `entry/src/main/ets/view/SettingsPlugins.ets:248-305` 虽能直写 req，却不是已证明的当前活跃入口。catalog update action（client 同行约 156685）另有先 remove 再开安装向导代码，但未穷尽其可见条件，不用它替代标准入口裁定。

同版可用跳过、元数据失败未删包、隔离目标目录都是真保护；清单恢复 `C/dsh-plugin-manager/lib/index.js:3049,3160-3162,3350-3359` 只保 package.json/pnpm-lock 文本，不保 node_modules。缓存/换源/启动自愈/救援启用不等于旧包备份。确认对象只限旧插件目录；未证会话/工作区数据丢失、应用必崩或已发生生产安装故障。

**附属轻微确认，不增加候选/根因数量。** installer `1427-1435` 在完整性检查返回非空错误时，`1430` 先访问尚未初始化的 const tmp，抛 TDZ ReferenceError 并遮蔽原完整性错误；首次安装也能触发。按 P3 错误诊断缺陷单列，校验仍失败，不是绕过校验。它不解释旧包为何删除，也不把 D01 从条件性升级为真实 P1；十一候选统计不另加一项。

### E03：无摘要消费与同尺寸跳过真实，损坏严重性仍有前提

**定位与实现事实。** `S/ImportRunner.ets:150-179,240-267` 读 sha 文本但只校验形态/路径/大小，`273-289` 既存目标仅按大小 skip；`296-315,337-363` 新目标复制后验大小和少量字节可读，不验 SHA、zstd、header 或 JSONL。`S/SyncModel.ets:330-347` 的摘要冲突函数没有进入该导入链。

**P2 已确认部分。** 已映射的同会话/同代际若本地与远端等长异内容，会静默 SKIPPED 而非提示冲突。上游当前代际可追加，见 `C/dsh-session-persistence-jsonl/lib/index.js:969-977,2955-2961,3341-3355`；格式 version 不是内容快照号。此项是不正确的内容等价判据，不覆盖/销毁既存本地文件。等长仍是触发条件，四组模型不是生产合法分叉会话验收。

**P1 条件与全局保护。** 错误内容资产等长、目标不存在且映射有效时，可被记 OK 后在正式会话读取失败，严重恢复不可用为条件性 P1。正常上传 `S/UploadRunner.ets:69-95,135-176` 确有摘要；扫描/hash/copy 无应用级原子快照，但普通追加增长通常被大小检查拦截，不能据此断言必出错。上游读取的 header/路径校验与 zstd checksum（核心 `3182-3214,3510-3519,1330,1408-1417`）可能拒绝坏文件，不补本次导入验证。既存不同尺寸不覆盖、映射过滤与 staging 落位均是保护。平台传输校验不能未经证实当成业务 SHA 比对，也不能反向因无应用 SHA 就断言平台损坏；无真实坏资产/用户损坏证据。整体保留条件性，P2 子事实不另计候选。

### E05：合法技能路径复用暂存文件，云错配取决于 Asset 时点

**定位与实现事实。** `S/SyncPlanner.ets:259-270` 原 rel 构 unitId，却以 `/`→`_` 构 assetName；`S/SyncStore.ets:200-225` 再安全化/截断120字符，统一目录下先 unlink 再 copy。`S/UploadRunner.ets:129-188` 顺序写每行，`190-206` 批后才显式 cloudSync；串行运行锁不能避免同批覆盖。

**真实合法输入。** `<home>/skills/demo/SKILL.md` 与 `<home>/skills/demo_SKILL.md` 可分别有合法不同 frontmatter name，`C/dsh-skill-filesystem/lib/index.js:595-625,678-717` 同时接受目录 SKILL.md 与根 .md，并从 frontmatter 取名。得到不同 `skill/global/...` unitId，却同为 `<distributedFilesDir>/dshm-sync-assets/demo_SKILL.md`。后者暂存替换前者，源技能文件未被覆盖。

**条件与全局保护。** 若平台只登记路径并在替换后读旧 Asset，可能备份错配，潜在 P1；若 insert 已独立快照或持有旧 inode，则可隔离，若平台报错则可表现为失败。尚未取得这一生命周期的官方契约或真机时序，不能写云备份必坏。`S/SyncStore.ets:243-258` 不同 unitId 不互相删行，末尾统计不核字节；没有应用层独立不可变路径/碰撞检测。常规附件上游完整 SHA 内容寻址是有效反证，不能用“两个同名 photo.png”证明异内容碰撞。导入当前只选 session（`S/ImportRunner.ets:150-152`），技能中转碰撞不等于正式会话已覆盖或技能恢复已损坏。整体条件性，不剔除合法技能反例。

### C01：QMP 通道事件提前完成停止等待

**定位与实现事实。** `hostcore/plugins/dshm-vm-bash/lib/vm.js:1523-1568` 设 worker.exit/8秒等待，却在任意 data 时 destroy，close/end 直接 finish；finish 仅看 done，不确认 worker 已退出。data 可是连接 greeting，不能当 quit 成功。同步建连接异常亦可直接 finish。QMP greeting 语义由 runtime/core 组读取的 QEMU 官方协议支持，本次未重新在线取证。

**后续与条件影响。** `hostcore/app/main.js:8533-8587` hooks settled 即清10秒 guard 并进入 finishHostStop，调用 shutdown 后另有1.5秒显式退出；这不是提前完成后再强制等10秒。若 worker 尚活、退出/刷盘超过剩余窗口，存在提前终止风险，潜在 P1。尚未证明实际慢退出、quit 丢失、qcow2 或业务数据损坏。

**全局保护与缺口。** quit 已写出，QEMU 可能及时结束；真正 worker exit 也可结束等待，无 VM 时直接完成正确，8/10秒本就是有界策略。`C/dsh/lib/profile-boot-QhDEDXsF.js:22-71,265-299` 的 dispose 没有第二次 VM join，ArkTS `hostruntime/src/main/ets/runtime/NodeRuntime.ets:541-560` 仅等待 Host 结束。QMP quit 也不等于 guest OS 完整关机。本项只涉及启用的 guest VM 路径，不扩大为所有原生终端；CR2 日志异常不是其根因。

### FR1：核心跳过只认大小，缺 stamp 可跨尺寸误认证

**定位与实现事实。** `hostruntime/src/main/ets/core/BundledCore.ets:154-193` 已有同标签目录且 stamp 等于容器大小即 skip，无内容摘要；`198-222` 在 stamp 缺失/读取异常时，只检查树信息文件存在及旧 builtAt 非空，补写当前 srcSize 后 skip。没有比较新旧 builtAt 或新旧内容，所以本分支不要求同尺寸。

**触发与用户影响。** 同标签重新发布不同内容，旧目录尚在，同时满足大小 stamp 相同，或缺 stamp 且旧 builtAt 非空；可能继续使用旧核心并把新大小写成已认证 stamp，P2 条件风险。`tools/pack-core.mjs:4944-4945,5047-5052,5109-5168,5372-5389` 允许同名输出更新并核对本次摘要，不锁历史标签不可变。不能只拿注释中的版本纪律否定可达性。

**全局保护与缺口。** 首装/新标签，或 stamp 存在且尺寸不同，进入真正安装；`BundledCore.ets:338-421` stage/commit/rollback 确实保旧，但不能修正提前 skip。`hostruntime/src/main/ets/core/CoreStore.ets:262-313` 未提供已装内容 hash，`hostruntime/src/main/ets/runtime/DshHost.ets:815-831` 没有上层补验。当前归档只有当前字节，未拿到已部署旧树及真实新旧容器对，不宣称本次发布已经更新失败，也不是坏包删除旧树问题。

## 数量与剔除

| 统计口径 | 数量 | ID |
|---|---:|---|
| 真实候选 | 6 | DR1、E01、E02、B01、E04、CR2 |
| 条件性候选 | 5 | D01、E03、E05、C01、FR1 |
| 整项证据不足 | 0 | 四组已补齐，不再因缺报告把候选全部待证 |
| 整项剔除 | 0 | 每项至少有可定位实现缺口，不等于所有原始扩大结论都成立 |
| 合计 | 11 | 每候选仅计一次 |

- 真实候选按主等级：P1 2项（DR1、E01），P2 3项（E02、B01、E04），P3 1项（CR2）。DR1 的 P1 必须保留同名文件/授权成功条件与 SDK 证据层级。
- 条件候选按严重影响上限：条件性/潜在 P1 4项（D01、E03、E05、C01），条件性 P2 1项（FR1）。E03 另有已确认 P2 行为事实，不重复加入“真实候选”计数；这不是四起已确认 P1 事故。
- TDZ 为附属 P3 轻微确认，不增加十一候选总数，不重复计算旧包删除根因，不硬凑“第七个真实候选”。
- 剔除/收窄的是扩大主张：D01 标准一次失败完全无恢复、旧 Settings 即当前添加页；E02 完全没有映射建立路径；E04 自动重新登录/已证跨账号；CR2 必致崩溃或 VM 泄漏；C01 已证坏镜像；DR1 普通手机所有选目录必破坏；FR1 只能同尺寸触发。不是把候选本身全部剔除。
- 尚证据不足的严重影响分别保留在项内：E03 实际损坏输入与业务结果、E05 Asset 消费时点、C01 慢退出及镜像后果、FR1 实际发布/已装状态、D01 标准双失败实例、DR1 实际 ROM 事故。不能用“整项证据不足0”宣称这些缺口已解决。

## 当前树与归档层次

1. **本次直接证据**：当前工作树/当前 dist work 依赖关键位置及本机 SDK 声明的只读复核。没有重新打开 zip 做逐字节核对，没有制造新模型或运行生产代码。
2. **四组报告已有的只读归档对照**：install/files 组记录 app installer/main 资源副本摘要一致，以及 manager、两桥、核心 UI/patch 等相关成员与 resfile zip 一致；sync/flows 组记录云同步插件、ondevice profile 及相关 loader/settings 消费链归档对照；runtime/core 组记录 VM 三文件、Cordis、profile-boot、profile 与当前归档一致，以及 app main 副本一致。这些是报告层的既有对照证据，不冒称本次全部重新计算。
3. **不能跨用的覆盖**：sync/assets 组明确把 session/skill/attachment 的 dist work 上游实现作为当前可读依赖，没有声称这些成员都做过归档逐字节核对；其它组核对了部分模块，不自动给所有 work 依赖背书。本次技能布局复读确认当前 work 行为，不升级为已部署字节确认。
4. **没有的证据**：签名 APP/HAP/HSP 与 abc 的本次核对、设备私有已解包树、实际激活核心/HMR 服务、真实云行/账号归属、Asset 生命周期、实际安装或生产同步故障、真机文件 API/QMP/镜像复现。resfile 归档对照不等于设备已装一致，当前树存在缺口不等于用户已发生损失。

最终结论是十一候选的源码级问题清单及严重影响边界，不是逐字全仓审计、生产业务复现、构建验收或真机验收。此前“报告缺失”的占位理由已经失效，以本文件裁定为准。

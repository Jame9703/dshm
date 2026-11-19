# 修复后独立只读复核

## 最新最终裁定（第四轮，2026-11-13）

**PASS：第三轮仅剩的N1/N4/N6三个具体阻塞均已关闭，T018独立源码/行为复核可完成。可以进入专用静态重跑，静态真实错误处理后进入受控编译验证。** 这不是静态全绿、构建成功、包核验或真机通过声明。本次未修改tasks勾选，未运行build/fix/deploy/device；唯一修改是本报告。下方各轮FAIL和行号均保留为历史，最新状态以本节为准。

### 三项关闭证据

| 项 | 实际生产逻辑及反证结果 | 裁定 |
|---|---|---|
| N1 stable neighbour | `hostcore/app/dshm-update-transaction.cjs:48-56`按原后继的blockKey稳定身份查找当前块，插入时使用当前邻居的新内容，不再匹配完整旧文本。邻居合法修改后target仍在其前；未改前方块保留在前，不整文件回滚。`tools/check-lifecycle-final.mjs:89-107`保留name-before-id和邻居config变更，并新增明确顺序断言；`:139-145`回退旧完整文本匹配的变异被拒绝。此前确认的顺序反例不再成立。 | 关闭 |
| N4 same-name requiredIds | helper `:101-111`保留独立rowIds；选中包直接传原rowIds，包名demo不再剔除真实entry id demo，故意未选中仍传[]。`:151-157`仅在reconcile成功返回后才构造applied/restart-required。测试`:121-137`确认选中demo收到['demo']且目标失败抛出、不能得到applied；未选中不强制require。重新读取官方 `C/dsh-app-boot/lib/index.js:4645-4654`，requiredIds命中真实失败entry会抛激活错误，故此测试的reconcile边界并非替代一条不存在的业务判据。`:139-145`回退包名过滤变异被拒绝。 | 关闭 |
| N6 pendingStops | `platform/src/main/ets/notify/KeepAlive.ets:100-106,389-425,475-494`在release首次await前同步pendingStops++，覆盖stop排队及执行期；finally减回。pending期间active快路径不能授予引用，B进入同一systemTail，在stop完成后重新start/确认active，成功后才refs++。`tools/check-review-production.mjs:121-144`完整生产类验证已有lease→release stop待决→B不提前resolve→停止后第二次start→最终refs=1/active=true；`:178-179`恢复旧active快路径的变异被拒绝。原A→forceRelease→B及晚到清理用例也仍通过。申请失败/代次作废分支不增加refs，systemTail的失败结算不毒化后续队列。 | 关闭 |

本次只核三项有限反例，不额外扩展YAML语法、设备策略或其它风格改动。保守复杂YAML拒绝仍在helper`:25-37,103`，早于owned备份创建及operation/remove，不进入破坏性恢复分支；不能把该兼容限制写成支持任意合法YAML。

### 本次独立执行

- `node tools/check-lifecycle-final.mjs`：rc0；包括N1稳定邻居顺序、N4同名requiredIds/目标失败/未选中、两个新增生产回归变异；已有N2/N3/N5和no-HMR/restart检查通过。
- `node tools/check-review-production.mjs --self-test`：rc0；包括N6 release待决新拥有者、该新增变异及原跨代次时序；来源往返、取消和资产预算/清理/复用原测试也通过。
- 新增三个变异分别恢复实际旧错误并由针对性的业务断言判失败，不以系统异常本身代替数据/拥有权断言。合理文件/系统边界mock接受，不冒称真实云端或ROM运行。
- 实施报告顶部所述同批113/0、targeted15、CI22及宿主24件同步为实施者已有证据，本轮未重复全量或逐字节核包，未将它们冒称本次独立执行。此次仅改宿主helper及ETS，核心zip未新增改动的说明与本次范围一致。

### 十一项最终状态

| 候选 | 最终处置 |
|---|---|
| DR1 | 固定名破坏路径已修，唯一拥有探测目录隔离 |
| E01 | npm/scoped/alias/GitHub来源往返已修并有生产链测试 |
| E02 | 自动映射刷新、未映射遗漏反馈、不写未知目录已处理 |
| B01 | 失败引用配平、释放代次及在途stop/new acquire隔离已处理，本轮N6关闭 |
| E04 | 合作取消、hash catch/尾阶段检查、旧进度与锁拥有权隔离已处理 |
| CR2 | 统计变量作用域已修；Cordis异常隔离证据保留 |
| D01 | 旧包准备/本地恢复、配置局部顺序、同名目标激活判据、writer/取消及原错诊断已处理，本轮N1/N4关闭 |
| E03 | 暂存及已有目标摘要校验、冲突不覆盖、缺摘要拒绝已处理 |
| E05 | 不可变资产身份、真实摘要复用、未登记清理及预算已处理 |
| C01 | workerexit正常完成、QMP不冒充exit、明确有界超时已处理 |
| FR1 | 内容身份stamp、旧/缺/坏stamp安全迁移及事务保全已处理 |

附属tmp TDZ已关闭，不另计候选。维持此前认可的官方差异结论：update外层＋共同change两个边界具必要性，保留官方同步control登记、检查、previous恢复、file-lock/HMR算法；本轮无需增加公共封套或再次重构。

### 非阻塞限制及后续门禁

- 复杂合法YAML可能被明确拒绝自动更新，这是保旧兼容代价，不代表数据损坏或完整YAML支持。
- writer跨进程冲突/崩溃残锁不自动抢占，需要明确恢复；不是对同UID不可信插件的安全隔离。
- 已登记/提交不明Asset可能仍被系统引用，512MiB预算到限拒绝增长，不提供猜测式自动回收；遍历与摘要有性能成本。
- VM超时是未确认退出，不承诺guest OS完整关机；尚无设备全功能验收。不得因此阻断经离线核验的待测包，也不得宣传真机已正常。
- **T018通过不代替T017专用静态或T020–T022编译/包验证。** 必须重跑当前ETS检查（至少本次KeepAlive及受影响依赖，累计清单沿用实施报告），真实诊断处理后可进入受控编译；若编译修正影响本轮不变量，只复跑受影响测试，不重启无界全域审查。

**本轮未发现这三项范围内剩余具体阻塞。T018源码/行为审查完成，可以移交静态及受控编译验证。**

## 第三轮历史（保留，不代表最新状态）

## 有限终核（第三轮，2026-11-13）

**T018仍不能通过：仅保留下述三个具体阻塞，不追加其它审查范围。可继续专用静态重跑；三个反例闭合后即可进入受控编译/待测包验证，不以真机或消除所有mock为前置。** 本轮未build/fix/deploy/device，只修改本报告。下方第二轮、第一轮为历史证据，不能当作最新未修清单。

已读取implementation-report顶部、当前helper/writer/KeepAlive、统一生成器、物化manager公共install/change及官方恢复/激活消费者，审读并运行最新测试。单审查者，无派生研究者。没有读取口令或用户数据。

### 三个当前阻塞

1. **N1余项 / P2：原邻居有合法内容修改时，恢复顺序仍错。** `hostcore/app/dshm-update-transaction.cjs:48-54`以完整旧块文本 `restored.includes(candidate)` 找后继，不以邻居身份定位。原文件目标demo在neighbor前；operation删目标并将neighbor的config从before改为after；恢复找不到完整旧neighbor，直接追加demo到文尾。两个块内容都保留，但相对次序改变；patch顺序本身有语义，不能声称“原邻居恢复”已完成。本次执行真实helper全文、内存文件边界确认输出neighbor→demo。最新 `tools/check-lifecycle-final.mjs:76-93`恰好修改了other，却仅断言目标和config存在，没有断言顺序，故绿灯不反证此问题。最小闭合：按稳定块身份匹配当前邻居，保留其新内容；在现有案例增加目标仍位于other之前的断言。不要求支持复杂YAML。

2. **N4余项 / P2：真实entry id等于包名时被错误移除，目标仍failed可被记成恢复成功。** helper `:99-109`先合并name与rowIds，再用 `filter(id => id !== name)`生成requiredIds。这会同时删掉合法的同名entry id。物化manager `C/dsh-plugin-manager/lib/index.js:2691-2692`本来已经能取得真实row.id，应以rowIds本身决定require，而非从混合身份集合反推。项目真实同名entry用法见 `hostcore/app/dshm-user-rows.js:403-409,432-435`。本次真实helper设置rowIds=['demo']、原bundles包含demo，确认reconcile收到[]。官方 `C/dsh-app-boot/lib/index.js:4645-4654`会将无requiredIds的同一既存失败降为warning；helper随后依据无restartReason记applied，因此N4的targetfailed反例仍未全闭合。最小闭合：使用独立原rowIds，保留同名id；补选中包且rowId==name的传递断言及目标失败不报applied，故意未选中仍传[]。

3. **N6余项 / P2：释放在途时active快路径绕开systemTail，新的成功拥有者最终无保活。** `platform/src/main/ets/notify/KeepAlive.ets:388-390`仍直接active→refs++→true；release `:473-487`排队/等待系统stop期间active尚真。顺序：已有成功lease→release归零并开始await stop→新acquire读active=true返回true→旧stop完成写active=false；最终refs=1、active=false，新caller已经收到成功。完整生产KeepAlive类仅mock系统stop Promise，本次确认该结果。新systemTail `:100-105,417-423`确实阻断上一轮“旧start清理误停新start”，但未约束这条active快路径。最小闭合：释放待决期间不能直接借用即将停止的active任务；补现成lease release→stop待决→新acquire的单一时序，以及失败申请refs不增加。无需改PC/手机策略。

### N1–N6终核状态

| 项 | 当前裁定 | 有效证据与边界 |
|---|---|---|
| N1 | 部分关闭，留阻塞1 | blockKey `:19-22`优先id，name-before-id已修。captureRows `:25-37`在owned目录/复制/operation之前拒绝被识别的anchor/alias、顶层flow/tag；直接throw，不进入恢复catch，原包/manifest/YAML均未写。拒绝合法复杂配置是明确兼容代价，不是支持该配置。识别是保守文本门禁，并非完整YAML验证器；本终核不要求扩展语法支持。 |
| N2 | 关闭 | writer `:40-52`内层finally始终release并清tail；业务异常追加cleanup诊断。真实清理throw后第二请求有界结算通过；磁盘残锁不自动抢占仍属保守限制。 |
| N3 | 关闭 | `tools/lib/manager-lifecycle.mjs:3-42`唯一规范化；pack `:25,3085`实际调用；物化manager `:2682-2698`是writer→transaction→official。共同change `:3471-3477`writer在原file-lock之前；嵌套change同token重入。clean/work输入幂等测试通过，四个public writer封套已移除。marker命中返回原文属于本生成器的判重，不宣称能修复任意人工破坏文件。 |
| N4 | no-HMR/restart关闭，留阻塞2 | helper `:105-109,136-155`显式no-hmr，previous applied+restart归一restart-required；真实configure/publishAndReload/reload仍在manager `:3422-3469`。官方UI已有restore.application、restart及operation-error diagnostic消费者，不再依赖localRestore独有字段。仍须修同名目标id丢失。 |
| N5 | 关闭 | manager `:3038-3057`同步建立AbortController和installs，再调用排writer的change；操作第一步检查stopped。实际public install/cancel排队测试确认cancelled且未进入安装。测试对change等待边界mock可接受：本次同时复读真实change原file-lock及错误归类，未把mock冒称全栈安装。 |
| N6 | 原跨代次start反例关闭，留阻塞3 | systemTail串行start/stop且reject后不毒化尾Promise；真实A→forceRelease→B测试通过，失败/取消只成功持有才refs++。active快路径与release待决交叉仍错。 |

### 官方差异必要性

**update外层＋共同change两边界是本需求下可接受的有限最小方案，不再要求继续压缩或重构。** update需要在官方remove之前保全并覆盖失败恢复全周期；共同change使普通remove、install、bundle/plugin enable与该周期串行，且不延迟install公共control登记。仅在本地installer排锁挡不住manager此前配置写入。当前不替换官方检查、previous恢复、file-lock/HMR算法，重入发生在writer层，不把HMR事务嵌套。剩三个问题分别在局部恢复/目标身份/保活拥有权，不需要新增官方公共封套。

### 十一项最终处置

| 候选 | 本次有限终核裁定 |
|---|---|
| DR1 | 原固定名破坏路径已修；唯一拥有目录隔离，未发现本轮倒退 |
| E01 | alias、npm名称版本、GitHub简写producer→manifest→payload→restore→实际parser已通过 |
| E02 | 每次刷新映射、未映射计数/原因反馈及不写未知目录已处理 |
| B01 | 原失败refs已修；因阻塞3仍不能全项通过 |
| E04 | token取消、末项hash resolve/reject、旧进度清理及排空锁已处理 |
| CR2 | 变量共同作用域已修；实际Cordis隔离已有运行证据，完整VM启动不作为此项前置 |
| D01 | 准备失败保旧、原诊断/多备份、拒绝不删、writer及public取消已处理；阻塞1/2使配置及运行态保全未完全通过 |
| E03 | 暂存/已有目标SHA消费、异内容不覆盖、缺SHA拒绝已处理 |
| E05 | 唯一不可变快照、实际摘要复用、未登记清理和512MiB拒绝增长已处理 |
| C01 | workerexit正常完成、8秒明确未确认超时、QMP不冒充exit已处理 |
| FR1 | 内容stamp及旧/缺/坏stamp事务迁移已处理，完整安装函数故障矩阵已有证据 |

附属tmp TDZ已移除，direct失败恢复保留原错并继续后续备份；不新增候选计数。

### 本次执行与非阻塞限制

- `node tools/check-lifecycle-final.mjs`：rc0，clean/work顺序及幂等、同步control取消、FIFO清理异常、name-before-id/anchor拒绝、no-HMR及previous+restart通过。
- `node tools/check-review-production.mjs --self-test`：rc0，来源往返7、末项取消2、原late acquire及新A/释放/B、资产预算/清理/摘要复用、现有变异通过。
- `node tools/check-manager-recovery.cjs --self-test`、`node tools/check-review-regressions.cjs --self-test`：均rc0，原保全及诊断负控未倒退。
- 三个补充反例均运行真实生产helper/完整KeepAlive类，仅mock文件和系统边界；确认了具体当前错误，不是因“仍有mock”而拒绝。
- 合法复杂YAML可能被明确拒绝更新；跨进程锁冲突/崩溃残留明确拒绝、需恢复；不提供不可信同UID插件隔离；已登记Asset到512MiB后拒绝增长、不猜系统回收时点；预算遍历/hash有可解释性能成本；VM有界退出不是guest OS完整关机保证。这些不单独阻塞待测包。
- 实施者报告的专用ArkTS首次诊断处理不等于当前静态全绿；必须重跑并处理真实错误。此为后续阶段门禁，本审查未运行静态/build、不判编译成功。包实物、签名及覆盖测试仍属后续验证，不要求真机才可提供离线核验待测包。

**实现者只需闭合以上三个有限反例及其断言，再复核受影响物化/静态结果；无需追加新全域审查。当前T018不通过，原因是三条已证控制流缺陷，而非设备或mock边界。**

## 第二轮历史（保留，不代表最新状态）

## 最新复核状态（第二轮，2026-11-13）

**结论：仍未通过。可以进入专用静态检查；当前不能作为已完成T018的候选进入最终编译/双包构建。** 静态检查可与下列修正并行，不必等所有mock消失。本轮未运行静态检查或build；本次唯一修改仍为本报告。下方“第一轮历史”完整保留，其行号及失败状态不应再当作当前源码结论。

本次读取implementation-report最新节、当前生产源码和新增生产测试，独立执行四个经审读的测试入口；无研究者派生工具，不声称多组独立复核。未修改源码/build/deploy/device/签名/提交/reset，未读口令或用户数据。测试写入仅限脚本自建唯一临时fixture，全部业务反例在内存执行。

### 当前缺陷（按影响排序）

#### N1 / 条件性P1：目标YAML块恢复会破坏合法配置，不只是“复杂格式未测”

准确定位：`hostcore/app/dshm-update-transaction.cjs:15-45,84-90,117-128`；官方合法配置消费：`C/dsh-plugin-manager/lib/index.js:1311-1357`。

- `blockKey`取文本中首先出现的id或name，而非优先id。合法块 `- name: plugin-module\n  id: target-entry` 被认成plugin-module；rowIds包含target-entry时抓不到该目标配置。官方writePluginEnabled按YAML map的id/name匹配，不限制键顺序，因此不能用“DSHM通常id在前”排除此输入。
- 即使是当前支持的顶层 `- id:` sequence，restoreRows也先删除原目标块再将其追加到文尾，未保原位置。已确认反例：目标块含 `config: &shared`，后续其它块含 `config: *shared`。原文件合法；恢复后anchor移到alias之后，实际项目`yaml`解析器抛`Unresolved alias`。这个例子不需要flow sequence、奇异标签或恶意输入，也不要求remove先把目标删除。官方previous恢复成功仍会无条件执行该重排。
- 顶层flow项、锚点在条目头、带注释/复杂标量等超出正则识别能力时没有显式拒绝；结果可静默漏存目标。不能声称完整目标YAML恢复已完成。整个文件盲回滚也不是合格修法，因为会覆盖非目标更改。

最小闭合：使用项目既有YAML语义/CST能力定位目标id并保留顺序和引用关系，或者在不可安全处理的合法形式上于任何remove之前明确拒绝更新、保旧不动。补三个生产helper失败/官方恢复场景：name先于id、target anchor被后续alias引用、非目标块保持原语义；断言恢复文件能由真实yaml/patch加载器解析且目标配置不丢。无需穷举所有YAML语法。

#### N2 / P2：writer释放异常使FIFO尾永不完成，后续请求挂起

定位：`hostcore/app/dshm-profile-writer.cjs:21-43`。

finally先执行 `fs.rmdirSync(lock)` 再release尾Promise。rmdir失败即跳过release和tails清理。当前调用抛错，后续所有同profile请求却永久await previous，连“锁残留，需恢复”的明确拒绝都拿不到。active已delete，因此队列所有权检查也不能识别这条永久等待。本次真实writer全文、仅mock锁IO抛LOCK_RELEASE_FAILED，确认第二次请求既不执行也不reject。

最小闭合：不论锁清理成败必须结算内存FIFO；磁盘锁留存可保守拒绝后续请求，诊断不能遮盖业务原错。补一个清理失败后第二个请求有界失败/可重试的测试。跨进程mkdir失败目前会走release，不是同一个bug。

#### N3 / P2：干净物化与当前work树的update封套顺序不同，快照和恢复不一定在writer内

定位：`tools/pack-core.mjs:3087-3135`；当前work `C/dsh-plugin-manager/lib/index.js:2682-2699`。

补丁先给官方update加writer封套，再用同一个公共 `async updateBundle(...)` 锚加transaction。在干净未注入manager上生成的是 **transaction→writer→官方算法**，快照准备和恢复位于writer外；当前复用work因先已有旧transaction，再补writer，实际是 **writer→transaction→官方算法**。本次直接执行生产补丁这一段文本变换，以五个原始公共签名作内存输入，确认两种顺序不同。未运行pack/build。

当前manager测试只读已有物化文件，不能证明重新安装依赖或干净CI重打仍有相同锁边界。这不是要求重做整个打包测试，仅需使补丁生成形态唯一，并增加“干净原体”和“已补丁work”两输入的同形/顺序断言，明确快照准备、官方remove/install及最终恢复都在同一writer生命周期内。

#### N4 / P2：恢复运行态与官方结果字段仍有错误成功判断

定位：helper `:87-90,117-135`；物化manager `:2695-2696,3447-3454,3474-3494`；HMR `C/dsh-hmr/lib/index.js:1320-1326,1364-1373`；激活判据 `C/dsh-app-boot/lib/index.js:4645-4654`。

- 无HMR的真实publishAndReload→reload返回 `{warnings:[]}`，没有restartReason。helper据此把本地恢复标成 `application:'applied'` 并宣称“运行态已本地恢复”；但无HMR仅compose配置，不会重启已卸载/异常模块。这里应明确restart-required/no-hmr，不能从缺字段推导运行态已恢复。本次真实helper内存执行确认该成功形态。
- 官方previous恢复分支只 `Object.assign(result.restore, runtime)`。原restore.application是applied，而后续reconcile返回restartReason时不会改为restart-required，与官方change原本根据restartReason调整application的规则不一致。本次实际helper确认applied+module-comparison并存。
- reconcile没有传恢复目标requiredIds。HMR会把“此前已失败且此次仍相同失败”的entry作为warning，而非必然throw；helper只看restartReason，可能将目标仍失败记成已恢复运行态。原官方enable/install会明确传目标row id。应基于原选中/启用状态判断哪些目标必须恢复，不可把故意disabled的entry强制启用。

消费者的正面反证：本次读取官方UI实际长行，已有restore.application进度判据、operation-error diagnostic和restart提示消费者，因此第一轮“只有无人消费localRestore”的问题已实质改善。但字段能到消费者不等于字段语义正确。

最小闭合：保留真实configure/publishAndReload/reload，注入HMR服务边界或小型合法Loader fixture验证no-HMR、restartReason、目标仍failed三种结果；官方previous成功和本地恢复都输出一致application/restartReason/diagnostic。当前测试将configure、publishAndReload、change全替换（`tools/check-manager-recovery.cjs:48-55`），恰好掩盖这些业务判据；不要求删除系统IO mock。

#### N5 / P2：新增FIFO排队使安装请求不可取消，却会在随后真正执行

定位：manager `:3051-3066,3226-3245`；writer `:21-35`。

公共installBundle先等待writer，只有进入dshmWriter_installBundle才注册this.installs。等待其它update/enable结束期间，cancelInstall(requestId)找不到请求而返回not-running，waitForInstall也返回null；FIFO任务没有取消标记，拿到锁后照常安装。本次提取真实公共install/cancel方法，仅控制writer排队边界，确认先收到not-running再执行安装。原来installBundle同步注册control，新封套改变了其取消/恢复生命周期。

最小闭合：排队阶段也登记可取消身份；取消后不能执行后续安装；waitForInstall能等待这个已受理请求。补一条真实install公共入口等待其它writer→cancel→释放锁的测试，不必为此重写官方安装算法或全栈联网。

#### N6 / P2：旧保活申请的晚到清理会误停新代次任务

定位：`platform/src/main/ets/notify/KeepAlive.ets:367-400,403-447,451-481`。

第一轮“forceRelease后旧申请复活refs”已修；但晚到成功直接stopBackgroundRunning(ctx)，没有排空/串行保护新请求。顺序为A申请在途→forceRelease→B新申请成功（active=true refs=1）→A晚到成功发现代次变更并stop。系统任务被停止，facts仍active=true refs=1，B caller以为持有有效保活。本次用完整真实KeepAlive类和系统申请/停止mock确认此结果。不是仅凭API记忆推断通知/耗电。

最小闭合：串行化系统start/stop或明确排空旧代次后再允许新拥有者申请，旧stop不能跨代次误停新任务；补A/B两次申请成功逆序、release停止在途时新acquire这两个时序。已有单次晚到测试有效，但不能覆盖跨代次新拥有者。

### 锁与官方差异必要性

- 同进程正常update→remove/install嵌套：当前work的外层writer和AsyncLocalStorage确实能重入，profile+活动token严格相等才跳过FIFO；queue的.writer在.req前写、main在调用installer前读取并传入，见 `hostcore/plugins/dshm-profile-pnpm/lib/index.js:369-382`、main`:8828-8846`、installer`:1310-1315,1764-1769`。main注册已前移runProfile前（`:8423-8426`）。旧注册时序缺口关闭。
- 随机伪造/过期/跨profile token不能匹配active，supplied不匹配会明确拒绝。token是bearer能力，写在同应用可读队列文件中，不能称“防同UID不可信插件偷取”。现有信任模型没有隔离同进程插件，未因此另报安全漏洞。显式token重入未context.run，会让队列operation失去ALS派生上下文；当前installSpecOwned/removeSpecOwned没有再调用manager写方法，因此没有据此断言现有必死锁，若未来加入嵌套调用需保持身份传递。
- mkdir跨进程锁采取拒绝、不自动抢占残留，是明确可接受的保守可用性成本；两profile路径独立。单进程FIFO保序，普通卸载/enable封套自身不做transaction恢复，只会排在update后执行，不因一次普通卸载自动复活。队列无token碰活动writer则明确失败重试，不冒称成功。
- **从1到5个封套的必要性：增加串行覆盖有必要，但当前“精确五处就是最小实现”未获证明。** update必须覆盖跨remove/install的完整保全；其它manager写者必须参与同一串行域，installer队列锁单独无法阻止manager在此前selectBundle/writePluginEnabled及随后reconcile写配置。因此“只在本地install/remove加锁、官方只保留update封套”不足以满足现行保全要求。新增remove/enable/install接线的意图不是无关功能扩展。
- 但官方公共change是这些写方法的共同本地可注入边界（`C/dsh-plugin-manager/lib/index.js:3496`起）。可在update外层保完整事务、在change边界统一加入writer，使install控制注册仍按原时机执行，减少公共方法改名/重复接线。必须核对file-lock→writer的锁序和HMR，不能未经测试直接替换。实现者应在“保留五封套并解决N5”与“update+共同change边界”中给出一个有限、可验证的最小差异说明，不需要无界寻找所有理论更小方案。N3使当前五封套的干净生成也尚未闭合。

### 资产预算、来源和取消裁定

- E01：上轮R4最小反例已关闭。installer `:1149-1152`保留npm alias真实目标，restore `S/PluginRestore.ets:95-102`保留GitHub简写；新增producer→manifest→payload→restore→真实parser的7例本次通过。没有发现本轮新引入来源格式实质缺陷；未要求安装器突然支持任意Git host。中间进度消息中的初步怀疑经测试已排除。
- E04：`S/UploadRunner.ets:126-143,173-194,220-227`在catch后再check、finally清未登记对象；engine`:123-128`清旧progress/stat并明确排空，锁仍由旧task归还。真实末项hash resolve/reject、前有成功项两例本次通过。没有复现第一轮取消后新调用cloud的旧反例，不重复判失败。系统已提交操作无法撤回仍属边界。
- E05/R8：`S/SyncStore.ets:43-91,251-295,305-330`已有512MiB预算、提交前owned集合、提交后放弃可删拥有权；copy/hash/取消未登记副本可清，模糊提交保守留存合理。重复单元先hash源，再query既有行并hash快照/验size复用；不是只信数据库SHA。上传 `:114-139`正常新增文件读hash两次，未变文件也读两份，保守内容核验的线性字节成本可以解释，不单独当缺陷阻塞。
- 预算计数每次stage前/后同步递归遍历全部保留文件（SyncStore`:47-59,260-273`）；N个新增单元约2N次全目录遍历，文件数高时接近二次元数据成本，512MiB限制字节而非文件数。此为需明确的性能成本，不在没有规模耗时证据时升级成已证卡死。最小补测是用计数IO给一次多单元上限示例，或按本批缓存预算计数并在拥有权变化时更新；不强求本轮另造性能工程。
- 本次资产复用/预算4例及有效变异通过。未登记清理、登记后不删的取舍成立。当前没有证据要求删除所有系统边界mock；对budget失败、SHA不符、同unit多次资产的原有单位测试可保留。

### 核心与VM裁定

- FR1新增测试确实执行完整installBundledCores函数，不再只是matches判等；旧/缺/坏/不同digest×成功/stage失败/commit失败12例本次通过。CoreStore.stage/commit作为边界注入合理，结合实际CoreStore stage先校验、commit失败回滚和home/cores分离复读，没有新发现本轮会删除用户profile的实质缺陷。`/home/profile`恒定Map断言不是实际ensureProfile迁移测试，但不因此要求全栈ROM解压才能进编译。旧大小/builtAt注释仍过时，应更正；摘要读失败不认证stamp，会重装，属于性能/可用性取舍而非误认证。
- C01 stop仍仅workerexit或8秒明确超时完成，QMP greeting/close不完成，未发现新的实质回归。CR2变量位于共同作用域，真实Cordis dispose异常隔离本次执行通过。当前测试未执行VM插件完整apply→Cordis dispose，因此不能把它写成完整插件验收，但不能仅因“少一个全栈测试”维持原作用域缺陷未修的结论。
- apply现有wrapper和shutdown hook生命周期保持原实现；没有将历史已有卸载不stop VM策略扩大成此次修复回归。若实现者补一条实际apply的effects注册/统计求值测试即可覆盖CR2目标，不要求启动真实QEMU或重做虚拟机架构。

### 本次测试与历史状态映射

本次执行且rc0：`node tools/check-review-regressions.cjs --self-test`、`node tools/check-review-production.mjs --self-test`、`node tools/check-manager-recovery.cjs --self-test`、`node tools/check-review-core-assets.mjs`。均先审读后运行；临时目录只由各测试自建/清理。没有pack/build或业务网络调用。

额外只读内存反例确认：N1的name/id识别与真实yaml anchor错误、N2清理异常尾Promise悬挂、N3生产补丁干净生成顺序、N4实际helper字段、N5公共install排队取消、N6完整KeepAlive跨代次误停。没有把异常就reject当作保全负控通过。

| 第一轮项 | 最新状态 |
|---|---|
| R1 | 已关闭原P1复制准备破坏路径；prepared/operationStarted守卫及首/中途ENOSPC保全测试有效 |
| R2 | 拒绝不再删包、正常writer接线已有；剩N2/N3/N5，不能全项关闭 |
| R3 | 精确恢复及真实reconcile接线已加；剩N1/N4，不能全项关闭 |
| R4 | 原简写/alias生产往返已关闭 |
| R5 | 原末项取消及旧进度已关闭 |
| R6 | 原单次释放后复活已关闭；新拥有者被旧stop误停见N6 |
| R7 | 原诊断遮蔽与多备份回滚中断已关闭；锁finally另见N2 |
| R8 | 原无界复制/未登记清理已关闭，512MiB拒绝增长及核验复用成立；保留性能成本说明 |

十一候选当前口径：DR1/E01/E02/E03/E04/E05/C01/CR2/FR1的原薄弱点已获得源码及相应测试支持，不再沿用第一轮的“全部待完整集成”要求；B01因N6、D01因N1-N5仍不通过。该裁定不是设备全功能验收。

### 给实现者的有限闭合清单

1. 先修N1目标YAML保全、N2 writer尾释放、N3物化顺序；各补上述一个最小真实业务反例/变异，不扩大需求。
2. 闭合N4真实恢复结果与运行态、N5排队取消；manager测试可mock文件/网络/HMR服务边界，但不要mock掉正要验的configure/reload和control登记语义。
3. 修N6旧stop/新start互斥并补两次申请时序；保持PC/手机既有拥有权策略。
4. 可立即做15个ETS的专用静态检查，任何真实诊断需实现者处理。本审查不运行build；N1-N6修正、定向重测、受影响源到物化一致性复核后，可进入受控编译验证，不要求无限追加系统/设备测试。当前T018仍不能标完成，当前候选不放行最终编译/双包交付。

## 第一轮历史（保留，不代表最新状态）

复核日期：2026-11-13。结论：**FAIL，不能进入最终应用 build / Beta、AGC 出包。T018尚未完成验收。**

本次独立重读已执行，但T018不仅要求有人审查，还要求发现的问题修正、重测、重物化后闭合。下列缺陷未修，因此不能勾选T018。没有派生研究者工具，本报告是单一审查者的独立复核，不声称多组独立验证。

## 范围与证据

- 根目录为 `~/data/DSHM-deveco-workspace`。读取本目录spec、plan、tasks、implementation-report、原post-fix-review、test-contract；问题基准为 `spec/source-functional-review/recheck-final.md`。实施报告仅用于定位，不作为通过依据。
- 重读实际安装器、事务helper、main启动/队列、物化manager的update/install/remove/select/configure/change、同步engine/task/runner/store/manifest/restore/state、两壳回调、原生同步UI、KeepAlive及关键caller、BundledCore/CoreStore/ensureProfile、VM stop/workerexit、插件dispose与Cordis隔离。
- 本报告中 `C/` 精确代表 `dist/core/work/dsh-core-0.2.2-rc.2+dshm.1/node_modules/@deepseek-ai/`；`S/` 代表 `platform/src/main/ets/sync/`。行号均为本次读取的实际工作树，不是历史清单行号。
- glob实际定位helper为 `hostcore/app/dshm-update-transaction.cjs`，资源副本为 `hostruntime/src/main/resources/resfile/resources/app/dshm-update-transaction.cjs`，不是猜测的`.js`文件。main注册见 `hostcore/app/main.js:8656-8658`；物化manager消费见 `C/dsh-plugin-manager/lib/index.js:2682-2689`。
- 本次唯一文件写入为本报告。未改源码、tasks、memory、配置、资源；未构建、打核心、deploy、device、签名、提交或reset；未读口令或用户数据。未执行会写fixture目录的事务测试，只审读该测试。补充反例全部通过命令行内存FS/依赖mock执行，不接网络、云端、用户profile或设备。
- 本次未重新解包/逐字节核zip或应用包，不能把实施者的core-integrity报告提升为本次实物验证。专用ArkTS静态检查和应用编译未执行，不能据类型擦除测试声称编译通过。

## 缺陷（按严重性）

### R1 / P1：准备快照失败反而删除完整旧包

定位：`hostcore/app/dshm-update-transaction.cjs:48-56,76-85`。

`cpSync(dest, backup)`尚未完成就可能因ENOSPC、权限或单个文件不可读而抛出，此时backup目录可以存在但只有部分文件。catch只检查backup存在，立即 `rmSync(dest)` 删除仍完好的原包，再将不完整backup改名到dest。没有prepared标记或“原包是否已被operation修改”的判别。operation甚至没有执行，便发生旧安装破坏。这是本轮新增的保旧反向破坏路径，不需要新版/旧版联网双失败。

本次以真实helper全文和内存FS注入“cp创建部分backup后抛ENOSPC”，确认catch删除原dest并恢复部分副本。此证据证明控制流及故障条件，不声称发生过真实磁盘事故。还应注意operation抛错且本地恢复成功时owned目录未清理，但不是本项主要损失。

必须补测：真实helper的cp首文件失败/复制中途失败/ENOSPC，断言原包所有字节不变、operation未调用；恢复rename/manifest失败时完整备份仍可定位；变异删除prepared保护必须判红。

### R2 / P2：官方无变更拒绝也会删除重放旧包，封套绕开原生命周期保护

定位：helper `:39-75`；`C/dsh-plugin-manager/lib/index.js:2697-2722,2751-2777,3224-3237,3480-3507`；注入源 `tools/pack-core.mjs:3084-3095`。

封套在官方检查之前复制旧包，之后只按 `result.result.application` 判断恢复。官方降级/同版拒绝、无效更新计划、Git主机不可达、remove拒绝等都返回failed；即使 `changed:false` 且从未进入安装，helper仍删dest、恢复副本、重写manifest并附localRestore。官方的invalid-spec、management-required、bundle-in-use等保护并未被删除，但其“拒绝就不动安装”的行为已被封套改变。

本次真实helper内存测试以 `{step:'check', result:{changed:false, application:'failed'}}`返回，确认仍删除dest。无HMR也被同一封套包围，不是只改HMR更新。无变更失败因此增加同步大目录复制、磁盘耗尽和R1的触发面。

另外pending只排斥同进程同profile/name的另一次update，既不参加manager的package.json文件锁，也不覆盖普通remove、enable和direct队列；复制/恢复处于官方change锁之外。检查期间同包卸载或配置更改可能被恢复覆盖，跨进程也不受Set保护。不同profile的key有隔离，但这不等于同profile所有写者已串行。

必须补测：真实manager的检查拒绝、同版/降级、管理插件拒绝、remove失败/仍在用、无HMR、并发普通卸载/enable/direct install、同包跨profile。无变更失败必须零删除/零配置恢复；普通卸载不得被晚到update复活。

### R3 / P2：本地恢复只恢复包和部分manifest，用户配置及运行态未恢复，重启提示没有消费者

定位：helper `:13-36,67-74`；installer `hostcore/app/dshm-installer.js:2018-2078`；manager `C/dsh-plugin-manager/lib/index.js:2778-2798,3171-3182,3224-3246,3368-3394,3440-3460`。

真实remove会删 `.dshm-plugin-rows.yml` 的目标块及 `cordis.patch.yml` 的匹配行；helper没有保存/恢复这些目标配置。旧包及dependency/bundles回来，不代表用户的覆盖配置回来。特别是同名用户行承载enabled/config的情况，双失败后重启仍不能凭恢复的package.json重新生成已删用户块。不能整文件盲回滚，仍必须保存并精确恢复本事务拥有的条目。

helper也没有调用manager的publish/reload/reconcile。HMR下remove已卸载旧实例、enable失败后还可能第二次remove；本地文件回滚不使旧实例重新工作。无HMR下保留正在运行的旧模块是既有策略，不能强行改成一律HMR恢复。helper新增 `localRestore.application='restart-required'` 不是既有manager结果字段；本次读取官方UI全文确认不含 `localRestore`，hostcore检索也只有helper生产该字段，没有反馈消费者。因此“请重启”的diagnostic不能据此认定用户可见。

还有disabled旧bundle的边界：本地installer总会appendProfileBundle；manager在options.enabled=false时不会主动selectBundle(false)，只是跳过select true。原官方恢复结果可能被判成功而跳过本地恢复，不能仅凭restore.application宣称原启用状态不变。此交互需真实集成确认，不以helper假结果替代。

必须补测：用户行/patch原有enabled和config、同名与不同entry id、无关用户并发改动保全；新版enable失败再remove、官方恢复成功/失败；HMR运行实例与无HMR待重启状态；真实UI收到本地恢复/需要重启提示；disabled更新不能被重新启用。

### R4 / P2：E01只修了版本拼名，来源往返仍不完整

定位：`S/PluginRestore.ets:94-102,188-194`；`S/PluginManifest.ets:134-157,190-196`；installer `:547-564,567-586,1136-1160`；main `:8779-8818` 与 `hostcore/app/dshm-install-command.js:159-166`。

1. 生产者明确接受并原样持久化 `owner/repo#ref`、`github.com/owner/repo` 等GitHub简写。restoreInstallSpec只识别github:/git+/git@/http(s):前缀，将这些值转换为 `包名@owner/repo#ref`，队列不会补救，安装器不能按原GitHub意图解析。本次真实restore函数内存执行确认该输出。
2. npm alias消费函数的单例通过，但生产者dependencyValueFor按最后一个@截range，将 `alias@npm:@scope/real@1.0.0` 持久化成 `1.0.0`。清单再读只剩 `{name:'alias', spec:'1.0.0'}`，恢复请求变成alias@1.0.0，真实目标丢失。本次生产函数提取确认该值。修消费端不能恢复生产端已经丢弃的身份。

现有测试仅断言手工输入的格式化字符串，并未贯穿producer→manifest→payload→restore→parser。git+等字符串被原样传递也不证明实际installer支持任意Git host；installer头部`:17-21`已说明边界。不能把“保持原文”写成“所有Git来源恢复可用”。

必须补测：scoped/普通npm range/tag、alias（含saveExact）、github简写/网址/SSH/commit/subpath、已有支持和明确不支持来源的完整往返；默认保留本机版本差异及多profile目标。

### R5 / P2：取消被hash catch吞掉后还能发起新云步骤，旧进度也未清空

定位：`S/UploadRunner.ets:121-129,169-201`；`S/ImportRunner.ets:275-290,315-336,385-392`；`S/SyncEngine.ets:123-126,289-300,373-376,401-405,453-458,718-724`；`S/SyncState.ets:66-94`；网页消费者 `hostcore/plugins/dshm-cloud-sync/lib/client.js:568-612`。

上传hash的task.check在try内，取消抛错被当作“计算校验值失败”，continue。若这是最后一项，且前面已有成功项，循环退出直接执行enableCloudSync，直到await后才再次task.check。这是取消后新发的系统业务操作，不属于无法撤回的已提交副作用。本次执行真实runUpload全文，以第二/最后项hash完成时取消，确认enableCloudSync仍调用一次。hash自身reject并同时取消同样有此缺口。

导入两处hash catch也会吞取消并调用sink，末尾还能生成DONE；engine的sink过滤和await后check确实挡住这些新回填，目前不能称它们会直接覆盖新任务状态，但runner本身未满足统一取消契约。uploadPluginManifest catch也吞取消，不过syncNow外层随后check，未据此扩大成已证后续上传。

锁反证成立：invalidateTask没有置running=false，旧任务排空前新任务被拒；finally还比对task对象，因此未发现“旧finally释放已运行新任务”的实际路径。代价是不可终止的await可能一直保持busy，UI未明确标识取消排空。signOut没有清progress/kindStat，重登录而旧任务仍busy时，encodeCloudState会把旧progress继续交给网页ProgressBlock；两壳then代次校验不能隐藏这个已有快照。不是已证明跨账号云数据泄漏。

必须补测：每个hash resolve/reject同时取消、最后项及先有成功项、所有runner尾阶段无新IO/DB/cloud请求；旧cloud回调晚到；退出/重登录时旧progress不可展示；排空后新任务正常启动、旧finally/旧sink不能改新锁/新进度；原生UI及两桥完成回调。

### R6 / P2：forceRelease不淘汰在途acquire，销毁后可复活保活

定位：`platform/src/main/ets/notify/KeepAlive.ets:364-395,397-435,438-468`；entry启动caller `entry/src/main/ets/entryability/EntryAbility.ets:1416-1433`、销毁`:1215-1231`；phone caller `phone/src/main/ets/entryability/EntryAbility.ets:1776-1808`。

active=false时acquire正在await，forceRelease只refs=0并release；release因尚未active直接返回。随后requestMode成功写active=true，acquire再refs++。KeepAlive没有generation/释放代次检查；entry PC启动caller也没有晚到release，形成销毁后active=true refs=1。pendingAcquire是布尔诊断/屏幕去重，不是淘汰或互斥机制。

本次真实KeepAlive类类型擦除，仅mock系统申请边界，执行acquire→forceRelease→晚到成功，确认facts为active=true/refs=1。手持caller的foreground generation有部分补偿，但不能救PC caller及类自身forceRelease契约；普通失败→成功引用配平已修，不应因此把全部B01判绿。renewNow和screen停起同样须纳入释放在途矩阵，不能只测acquire短路。

必须补测：成功晚到/失败晚到、TASK_KEEPING失败后fallback与forceRelease交错、并发acquire、renew/screen与release交错、entry PC/手持及phone held/generation真实caller。

### R7 / P2：direct install的finally恢复异常遮蔽原错，并中断后续包回滚

定位：`hostcore/app/dshm-installer.js:1306-1331`；main `:8866-8884`。

catch已经将原异常转换为 `{ok:false,error}`，但finally中的rm/rename/清理全部无保护。恢复rename失败会使整个installSpec reject，原下载/完整性错误从最终回执丢失；for循环也提前中断，后续备份不再尝试恢复。成功安装后仅清理旧备份失败也会把成功结果变成队列异常。这不符合函数“不抛错”契约。

本次提取真实installSpec，仅mock内部业务边界触发preserve后抛ORIGINAL_INTEGRITY_ERROR，再令恢复rename抛RESTORE_RENAME_FAILED，确认最终只收到后者。main catch能够写fail，不能补回已经被遮蔽的原错。

必须补测：新包失败+旧包恢复失败保留两条诊断/备份路径、多包回滚继续尝试、成功后清理失败不变业务结果，以及实际integrity错误不含tmp TDZ。

### R8 / P2：不可变快照无限增长，失败且从未登记的副本也不清理

定位：`S/SyncStore.ets:201-229`；`S/UploadRunner.ets:105-166`；`S/SyncEngine.ets:580-608`。

每次上传每个单元都创建唯一目录并复制，不按索引/摘要跳过。没有容量上限、可靠回收状态或未登记失败副本清理。copy失败可留部分文件；hash失败/取消、upsert失败同样保留从未登记的完整副本。反复备份未变数据时空间开销按所有尝试的累计字节增长，而不是按当前云表有效资产量。空间满反过来影响本地安装与备份，且扩大R1的触发面。

已登记资产不能因批次结束或退出就删，这个安全取舍正确；不能据未知平台生命周期猜一个延时强删。但这不要求永远保留已知未登记对象，也不能把无界累计当成完整交付。当前E05碰撞已修，空间问题应单独保留，不声称已证明平台错误快照或用户源文件被覆盖。

必须补测：copy/hash/insert失败与取消时仅清本次未登记对象、重复未变单元空间界限、容量不足可解释失败；已登记路径在平台可能引用期间保持不可变；明确可执行空间预算/回收策略后才能闭合。

## 官方差异裁定

**必要性：成立。最小性及隐藏行为不变：不通过。**

- 本地install入口晚于官方HMR remove，单修installSpec无法保住已删除旧包；官方previous重装仍需网络，因此增加remove之前的本地保全边界有实质必要。
- 物化manager只新增updateBundle委托封套、原实现改名dshmUpdateBundleInner；已重读原检查、HMR remove/install/previous恢复、无HMR直接install分支，算法未被替换。但“原方法还在”不证明外围无行为变化，R1/R2/R3都是新边界产生或未处理的差异。
- 注册没有平台/HMR条件，位于main通用start内；但在 `runProfile` 已await返回之后（main`:8423-8429`）才注册（`:8658`），不是初始化前的全模式保证。正常ready后的manager可调用helper；启动插件在boot期间主动调用update则仍可能走无helper fallback。不能宣称所有启动时序/所有独立CLI进程均已包围。
- 参数用this.profile.dir，helper key为resolved profile+name；队列`.dir`/命令profile解析见main`:8716-8727,8794-8838`。不同profile具备路径区分，但没有跨manager/CLI的全事务锁和统一启用/卸载拥有权。
- 普通remove本身未调用helper，不会仅因一次普通卸载自动恢复，这是有效保护；但更新与普通卸载交错的反例未被Set阻断，不能扩大为“普通卸载绝不复活”。

必须在官方实际manager+DSHM队列集成矩阵闭合后再接受此diff，不能仅凭6个模拟operation返回值说明“最小且保留原行为”。

## 十一项裁定

| ID | 修复后裁定 | 依据及剩余边界 |
|---|---|---|
| DR1 | 源码级修复成立 | FilePicker`:385-435`唯一目录+仅清本次对象；SDK `@ohos.file.fs.d.ts:1972-1996`证实唯一目录返回。旧固定同名文件不再打开。7种内存故障路径通过；授权短路、ROM行为仍非本次实测。 |
| E01 | 未闭合 | 普通/scoped npm版本已补名；GitHub简写与alias完整往返仍错，见R4。 |
| E02 | 核心修复成立，UI验收不足 | engine`:498-514`每次重扫；ImportRunner`:145-180,223-230,385-398`保留未映射并计失败/原因，不写未知目录。engine`:475-477`及原生UI`:520-524`传summary；网页lastSync消费者`:607-612`存在。未宣称增加了手动映射功能。 |
| B01 | 部分修复，未闭合 | 原“失败refs++”已去除，phone备用失败release已收口；forceRelease及在途申请仍有R6。 |
| E04 | 部分修复，未闭合 | token/engine回填过滤、两桥代次、排空锁有效；R5存在取消后新步骤与旧快照展示。 |
| CR2 | 作用域修复成立，真实dispose验收缺失 | `hostcore/plugins/dshm-vm-bash/lib/index.js:312-314,413-419`变量移共同作用域；Cordis `C/cordis/lib/index.js:693-706`逐项catch仍在。本轮没有运行真实Cordis dispose，不能把静态复读写成运行通过。 |
| D01 | 不通过，含新增P1 | 本地备份和官方恢复都存在，但R1/R2/R3/R7使保旧、配置/运行态及诊断不闭合。tmp TDZ已移除（installer`:1446-1453`）。 |
| E03 | 摘要/冲突修复成立，取消交叉测试缺失 | ImportRunner`:272-290,310-324`消费目标及暂存SHA；异摘要不覆盖、缺SHA拒绝。未增加错误的官方zstd/header格式限制；5例通过不等于官方合法会话端到端恢复通过。R5影响其取消契约。 |
| E05 | 覆盖碰撞修复成立，空间未闭合 | stageAsset每次mkdtemp独立路径；upload hash/size来自同副本，不依赖insert快照时点。SDK `@ohos.data.relationalStore.d.ts:136-160`此处Asset.path是必选string，不按“可选字段”虚报编译缺陷。R8另为实际空间问题。 |
| C01 | 原提前完成路径修复成立 | vm.js`:1524-1574`捕获原worker，只有exit或8秒超时finish；QMP greeting/close/end不完成，超时明确unconfirmed；worker原exit置空见`:975-990`，Host10秒guard及后续1.5秒退出仍在main`:8533-8587`。8断言通过；未证guest OS完整关机/镜像实机安全。 |
| FR1 | 弱身份跳过已修，完整迁移验收未完成 | BundledCore`:153-235`计算实际容器SHA，只有完全匹配stamp才skip，旧/缺/坏stamp不会认证旧builtAt；`:341-424`仍stage→挪旧→commit→失败回滚。测试只测matches函数，不覆盖完整安装。 |

FR1补充：CoreStore`:143-169`将cores与home分开，BundledCore只切cores；main ensureProfile`:8170-8235,8238-8285`保留既有dependencies并合并bundles、捕获旧patch交给composeUserRows。没有本轮新增“删除整个用户profile”证据。但这不能替代旧stamp迁移后启动/用户配置保全测试。BundledCore`:32-40,152,175-195,207-228`仍描述旧大小/builtAt认证，现已与代码不符，应更正，不能当新算法依据。

## 测试真实性与本次执行

本次安全复跑：

| 命令 | 结果 | 实际覆盖边界 |
|---|---|---|
| `node tools/check-fix-review-behavior.mjs --self-test` | rc0 | DR1 7、E01 5、B01 4、token2、engine5、mapping3、unmapped3；6个变异被拒绝。 |
| `node tools/check-fix-review-content.mjs --self-test` | rc0 | E03 5、E05 3、C01 8断言、FR1判等7；4+1变异被拒绝。 |

补充内存反例已执行并确认：R1部分cp失败删除原包、R2无变更拒绝仍删除重放、R4简写错误/alias生产端丢身份、R5末项hash取消后enableCloudSync仍调用、R6forceRelease晚到成功复活、R7finally遮蔽完整性原错。执行的是真实helper/真实类或生产函数体，仅替换IO/系统边界；不是ROM、网络或完整manager业务复现。

现有测试提取不是凭空手写同构算法，但覆盖及负控边界必须收窄：

- behavior`:9-18,50-56,73-81`确实切生产函数；`:109-112`擦除engine类型；engine测试`:121-127`却用自带token.check的mock runUpload，永远走不到真实runner吞取消的分支，所以不能证明R5不存在。
- E01`:59-65`只测试字符串formatter，未走dependencyValueFor/manifest/installer；alias案例因此假设了生产者并未保存的输入。不是“假提取”，是关键producer完全没测。
- B01`:82-97`mock requestMode，且`:89`手工refs--代替真实release；因此4个案例不证明forceRelease、系统start、renew、caller generation正确。
- content`:105-118`只提取matchesBundledIdentity，旧/缺/坏stamp字符串断言不等于installBundledCores整函数迁移。既有 `tools/check-bundled-core-rollback.mjs:86-136`是源码顺序检查，不能替代事务失败注入/用户profile保全。
- content`:34-46`用ABC/XYZ内存字节验证摘要消费是有效单位测试，但不是官方合法zstd会话恢复；Token.check恒空（`:16`），无法检验取消。
- content`:72-103`确实提取stop生产代码，有QMP与worker故障时序价值；worker是EventEmitter，不能升级为真实QEMU/Host退出验收。缺worker已退出/null、会话close同步异常、QMP建连抛错、超时与exit同拍的完整矩阵。
- `tools/check-update-transaction.cjs:18-30`确实调用真实helper，但operation手工删包/改manifest/返回状态；stage标签download/integrity/placement没有执行这些实际生产失败点。`:44-58`快照禁用变异会因rename缺失backup而reject，测试预期reject就判“变异拒绝”；这只证明操作抛错，未断言旧安装仍在，不是数据保全负控。尤其不会发现R1。
- CR2没有新增真实Cordis dispose行为测试。读取Cordis隔离与变量作用域只能给源码结论。

## 放行条件

1. 报告R1-R8及相关并发/启用/配置问题只报告未修。先完成修复和上述生产集成/有效保全负控，特别是manager真实remove/install/recover、direct回滚、KeepAlive及runner取消交叉测试。
2. FR1必须补完整installBundledCores+CoreStore失败注入和用户profile保全；CR2补真实Cordis dispose；补所有改动ETS的专用静态检查。此处没有执行应用build来替代静态/行为验收。
3. 核心/插件/宿主后续修正后，重新物化与核源→work→zip→resfile一致性，重跑同口径回归及受影响独立复核。当前引用旧物化sha不等于新修正已入包。
4. T018要求的独立复核环节本次已有实质执行，但**任务整体未闭合，不得标完成，不可进最终build**。设备/UI受限不是本次拒绝放行原因；新增数据保全风险与未完成必要生产验收才是。

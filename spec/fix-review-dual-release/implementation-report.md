# 本轮实施报告

## 阶段5最终收口（2026-11-13，覆盖下方未构建快照）

T020–T022已执行并留证勾选。**离线PASS；端到端INCOMPLETE，安全Beta部署受限；按用户要求没有UI。**

- build-01失败后的FileDigest两处throw已为as Error；build-02真实编译exit0。初始循环2/10。本续作无产品源码修改。
- Beta成功：dist/beta/DSHM-beta-1.1.8-1010016-20261113T074043/DSHM-beta-1.1.8-1010016-combined-debug.app，665909499字节，SHA256 `4412107afb4000630be69114ad60a8b80f73a74c236c5c82c67a3c4532e72241`。
- AGC中断遗留仅build-profile不同；先核两份安全备份全部77摘要匹配，再限定恢复原字节，未盲跑recover。重跑agc-build-resume.txt exit0：dist/release-test/dshm-1.1.8-1010016-dshm.1-AGC-invite-20261113T075635.app，659570787字节，SHA256 `8f0d3f8c5e8676d57df773944ce170281556b0274f007d1fd19a1ab47dda0a11`。
- 两包身份版本/设备矩阵/18及9权限顺序与逐条reason/核心资源摘要通过，Beta APP及三侧载模块、AGC APP共5组独立verify-app与verify-profile exit0；正式release/app_gallery 8 ACL，Beta debug仅2 ACL，不等于获权。
- 最终77配置/物料摘要不变，宿主24件同步；核心SHA保持3e4c5e3849eaf1c41afa1d43e927ebdbe3fe2e88d03e447c29b174d05bb83e4d。
- 包后同批113/0、CI补充22命令rc0、专项15命令rc0，OK→BAD=0。
- 单台MateBook14可见，但AGC clean已覆盖Beta缓存；缓存只含正式release且run无artifact路径参数，故安全Beta run跳过，未侧载AGC。不得将历史信任拒绝当本轮安装结果。
- 权威报告dist/acceptance/fix-review-dual-release/{verification.md,delivery.md}；原始证据和首次审计正则失败均保留。docs search因sqlite绑定缺失受限。无UI、commit/reset、卸载/清数据、改版本权限身份或上传AGC；未修改MEMORY/HANDOFF。

本续作仅修改验证脚本与报告：fix-review-verification.py新增经77项摘要校验的限定恢复入口，fix-review-evidence.py支持独立输出，复用rc2-beta-package-audit.py参数化并加强逐权限reason，新增fix-review-package-audit.py。所有手工修改apply_patch，无新增代码注释。

## 阶段4最终移交：COMPLETED（仅T001–T019，非构建/交付成功）

父代理独立第四轮终核已在post-fix-review.md最新节给出PASS，11候选及tmp均有最终处置，三条有限阻塞关闭。依据真实测试、物化、回归及该独立报告，tasks.md的T001–T019已收口勾选；T020–T022未执行且未勾选。下方历轮PARTIAL/未决文字是过程快照，当前状态以本节为准。

### 最后只读核查及静态边界

父会话已对累计15ETS执行两轮check_ets_files。最新工具结果`~/.local/share/deveco/tool-output/tool_1d3c2c398001Zd7mhMLZ1T286q`提取severity1共8条：UploadRunner五条旧misplaced-import、SyncStore一条旧insertWithConflictResolution、Index两条旧重复sha256。当前实物逐项核查：

- UploadRunner imports在27–36，export转发在38，已不是报错描述的旧顺序。
- SyncStore当前327行实际为 `await store.insert(SYNC_TABLE, row, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);`，没有该旧方法调用。
- Index当前216行只导出runUpload，217行仅一次从system/FileDigest导出sha256OfFile，末尾无第二个导出。

本轮只读确认后**未为刷诊断改任何生产源码**。T017勾选表示静态步骤真实已执行、诊断与实物已核对及移交，不表示静态全绿。服务旧快照不能作为通过证据；由T020真实编译核验当前源码/SDK重载和所有真实诊断。不得使用lint Files checked0或本报告代替编译。

### 阶段结果与证据

Setup T001–T002、Foundational T003、故事T004–T015、Polish T016–T019完成。生产边界mock的合理测试及非阻塞限制按独立第四轮裁定接受，不要求设备全功能通过才进入受控编译。

- before.txt 113/0；最新terminal-final.txt 113/0，最终OK→BAD=0；早期失败报告保留不覆盖。
- terminal-final-ci.txt 22命令rc0（含重复，不相加称135唯一门禁）；targeted.txt 15命令rc0。
- 新增最终三个回归变异：旧邻居全文匹配、同名requiredId过滤、pending stop时active快授予，均被真实业务断言拒绝；详细统计及其它生产测试见下方各证据节和targeted原输出。
- core-integrity.md：源→核心zip VM字节一致、manager规范封套与原previous恢复均在；宿主24件同步；OSS check通过。
- 当前核心 `hostruntime/src/main/resources/resfile/dsh-core-0.2.2-rc.2+dshm.1-openharmony-arm64.zip`，SHA256 **3e4c5e3849eaf1c41afa1d43e927ebdbe3fe2e88d03e447c29b174d05bb83e4d**。最后仅宿主helper及ETS修改，已place，不需再pack。核心及应用版本未擅改。

### 累计全部变更ETS（父/验证会话编译检查清单）

1. platform/src/main/ets/system/FilePicker.ets
2. platform/src/main/ets/system/FileDigest.ets
3. platform/src/main/ets/sync/PluginRestore.ets
4. platform/src/main/ets/notify/KeepAlive.ets
5. platform/src/main/ets/sync/SyncTask.ets
6. platform/src/main/ets/sync/SyncEngine.ets
7. platform/src/main/ets/sync/UploadRunner.ets
8. platform/src/main/ets/sync/ImportRunner.ets
9. platform/src/main/ets/sync/SyncStore.ets
10. platform/src/main/ets/view/CloudSyncSettings.ets
11. platform/src/main/ets/Index.ets
12. entry/src/main/ets/pages/WebApp.ets
13. phone/src/main/ets/pages/WebApp.ets
14. phone/src/main/ets/entryability/EntryAbility.ets
15. hostruntime/src/main/ets/core/BundledCore.ets

C++改动0。其它源码/工具/生成件清单见下方各轮具体记录，原有未提交改动均保留。

### 阶段5入口及非阻塞限制

现在可进入阶段5受控真实编译：由验证代理显式选择模块，初始最多10次按tasks核验；此处未运行。Beta与AGC顺序使用既有入口，不能并行改身份：

```sh
CODEBUDDY_SAFE_DELETE_ENABLED=0 node tools/build-beta.mjs --combined-app
CODEBUDDY_SAFE_DELETE_ENABLED=0 node tools/build-agc.mjs
```

AGC已适配devecocli release product/release模式，原配置Buffer/finally恢复机制保留；本轮未构建两种应用包，故无新APP路径/大小/摘要或签名成功结论。后续应核两包身份、三端设备面、18/9权限顺序reason、核心sha、签名/profile及逐字恢复。

非阻塞限制：复杂YAML明确拒绝自动更新；跨进程冲突/崩溃锁不自动抢占；同UID插件非安全隔离；已登记/提交不明资产保留，512MiB到限拒绝增长，摘要和遍历有成本；VM8秒超时仍是退出未确认，不承诺完整guest关机。设备信任/平板手机未测应写离线合格待测，不宣称真机正常。无commit/reset、无清用户数据/签名/历史交付，无版本权限分档改变。

## 最后三条阻塞局部修正（最新，待父终核）

仅修改第三轮确认的N1/N4/N6，不改已认可官方update外层+共同change边界。

- N1：恢复后继由完整旧文本匹配改为blockKey稳定身份在当前块中定位，使用当前邻居新内容，保持target在neighbor之前；复杂不安全YAML仍在remove前明确拒绝零改原件。现有真实helper测试增加顺序断言，并在neighbour内容变更后验证目标位于其前。
- N4：requiredIds直接来自独立原rowIds，不再从混有包名的identities集合过滤。真实rowIds=['demo']且包名demo用例：选中包向reconcile传['demo']；target失败抛出，不得到applied；故意未选中传[]。
- N6：pendingStops覆盖release排队和系统stop在途，active快路径只在pendingStops==0时授予引用；等待stop的acquire进入systemTail，真正停完后再启动/确认active。真实完整类测试现有lease→release stop待决→B不提前返回，stop完成后B返回true，最终refs=1/active=true；原失败refs不增、旧start跨代次清理用例也通过。

新增有效负控：回退N1旧完整文本邻居匹配、回退N4包名过滤两变异均被生产断言拒绝；回退N6active快路径变异被pending期间返回语义断言拒绝，共3个新增回归变异。证据targeted.txt：15命令rc0；terminal-final.txt：113/0；terminal-final-ci.txt：22命令rc0；最终OK→BAD=0。

本次生产源码仅hostcore/app/dshm-update-transaction.cjs及platform/src/main/ets/notify/KeepAlive.ets；测试修改tools/check-lifecycle-final.mjs、tools/check-review-production.mjs。宿主app已place，24件同步断言通过。未改核心/插件，按本轮要求不再pack；zip SHA保持3e4c5e3849eaf1c41afa1d43e927ebdbe3fe2e88d03e447c29b174d05bb83e4d，core-integrity.md已回读确认。

当前可以交父代理对三条有限反例终核，并重新check_ets_files（至少KeepAlive；累计15ETS清单下文保留）。本子代理无专用静态复跑接口，不声明静态全绿。T018仍由父终核决定，未自评PASS；T020–T022完全未执行。任务现有未勾验收项保持待最终证据确认，而非把本报告当全数完成。

## 最新N1–N6有限修正及首次专用静态诊断处理

本节覆盖下文旧状态。候选可交父代理独立终核及专用静态重跑，**不是自评T018 PASS，不执行应用build/出包**。

| 项 | 修正与实际证据 |
|---|---|
| N1 | blockKey优先id，不取先出现name；目标按原邻居恢复。anchor/alias、flow/tag等不安全局部结构在operation/remove前明确拒绝，保持原文件/旧包不变；不承诺支持任意YAML自动恢复。真实helper name-before-id与anchor引用拒绝测试通过。 |
| N2 | writer磁盘锁清理外再套finally，无论rmdir结果都结算FIFO；业务原错追加cleanup诊断而非覆盖。真实writer清理抛错后第二请求有界结算通过。 |
| N3 | 新tools/lib/manager-lifecycle.mjs唯一规范化生成：update外writer→事务；其余写者改为共同change入口writer，去掉四个public封套。clean签名与旧work两输入均断言writer在事务外、重复幂等。新规范marker V2。 |
| N4 | lifecycle显式hasHmr；no-HMR一律restart-required/no-hmr，官方previous applied遇reconcile restart同步改application。原选中包的恢复目标ids传给真实publishAndReload，故意未选中不强制require。helper no-hmr及previous+restart测试通过；目标仍failed交由官方requiredIds判据，不自造running成功。 |
| N5 | installBundle公共方法恢复官方同步control登记，只在共同change排writer；真实public install/cancel测试确认排队时已登记、cancel后不会执行安装。 |
| N6 | KeepAlive共享systemTail串行系统start/stop；旧start晚到清理完成前新start不能进入。完整类A→forceRelease→B测试旧A停止后B才启动，最终B active/refs正确。 |

首次父会话check_ets_files证据tool_1d394f100001KEE0UTumlR8kfm已提取全部severity1共16条。明确修正UploadRunner import位于export之后、Index重复sha导出、SyncStore不存在insertWithConflictResolution（改SDK insert三参冲突重载）。FileDigest @throws说明传播，close失败不覆盖原读/hash错误；KeepAlive权限warning不改权限。缺导出/Expected参数数已实物核查：SyncStore确实export两个函数，runUpload四参/runImport六参/upsert四参；尚不能判它们已通过或仅缓存误报，必须父会话对当前依赖重跑。CloudSyncSettings/BundledCore首次结果没有severity1；不要凭旧长输出猜新结果。专用检查本子代理未复跑，无静态全绿声明。

最终实跑：targeted.txt 15命令rc0；n-final.txt同批113/0；n-final-ci.txt22命令rc0；最终OK→BAD=0。新check-lifecycle-final覆盖N1–N5上述路径；check-review-production补N6跨代次串行。原有变异均重跑；本N系列不是每条均新增独立变异，不扩大统计。

核心已重pack+place+OSS，最新zip SHA256 **3e4c5e3849eaf1c41afa1d43e927ebdbe3fe2e88d03e447c29b174d05bb83e4d**，core-integrity.md已刷新。宿主24件同步。新增官方差异由五个public写封套收敛为update+共同change两个边界；保留官方install控制注册、原file-lock/HMR/previous恢复算法，有限最小性选择依据N5反例。T018仍待独立终核；专用静态重跑可能产生真实类型诊断，须先修后再进入阶段5。

本N轮新增tools/lib/manager-lifecycle.mjs、tools/check-lifecycle-final.mjs；修改hostcore/app/{dshm-profile-writer.cjs,dshm-update-transaction.cjs}，tools/{pack-core.mjs,check-core-openharmony-patches.mjs,check-review-production.mjs,check-review-regressions.cjs,check-manager-recovery.cjs,fix-review-evidence.py}；ETS实际修改为FileDigest、KeepAlive、UploadRunner、SyncStore、Index（累计15路径清单不变）。C++仍0，原独立报告保持FAIL原文未动。

## 最新续作：写锁、配置运行态恢复及资产预算（本节覆盖下文旧未决状态）

状态仍PARTIAL，待父代理独立复核与专用ArkTS静态检查，不进入应用build。以下新增实现已真实执行测试，但不将测试边界mock宣称完整设备/业务验收。

### 本次实质落地

- R2：新增hostcore/app/dshm-profile-writer.cjs，profile级FIFO+异步上下文重入token+原子mkdir跨进程拒绝锁；manager update/install/remove/bundle-enable/plugin-enable公共生命周期封套共享此锁。profile-pnpm桥将当前token在请求文件出现前写.writer，宿主读取并只允许同一活动token重入。普通manager卸载FIFO排到更新结束后执行；独立direct请求若撞活动更新明确失败并要求重试，不伪称卸载成功、不在之后偷偷复活。锁崩溃残留不自动抢占，需明确恢复，属保守可用性成本。
- R3：事务保存目标包名和bundle声明entry id对应的完整顶层YAML块；仅恢复目标块，保留其它配置改动。官方previous成功也恢复原选择/配置；本地恢复调用manager configure/publishAndReload走原HMR/no-HMR机制，结果写入官方restore/application/restartReason及error.diagnostic已有字段，而不只生产无消费者的localRestore。旧算法本体保留。目标YAML处理限定当前DSHM写入的顶层sequence格式，复杂用户自定义YAML形式仍需独立审查。
- R8：512 MiB资产文件总预算，stage前和copy后核算；不足明确拒绝并说明已登记资产可能仍被系统引用，不盲清。已有单元只有数据库SHA相同、路径属于snapshot命名空间、实际文件hash及size都一致才安全复用，不重写不可变路径；重复不变插件清单同样复用。未登记副本copy/hash/取消可清，提交数据库后即放弃可删拥有权（失败可能提交不明，保守留存）。累计已登记历史到预算后会拒绝新增，不能宣称无限历史或自动安全回收。
- R4/R5/R6补真实生产链：producer依赖保存→manifest→payload→restore→installer parser；真实runUpload末项hash resolve/reject取消且前有成功项；完整KeepAlive类forceRelease后系统start晚到成功停止。

### 最新证据

- targeted.txt：14条命令全部rc0。
- check-review-production：R4往返7/7；R5取消2/2；R6完整类晚到1例；R8清理/登记留存/内容验证复用/预算拒绝4例。R5/R6两个变异判红；R8撤预算/不核内容复用两个真实生产变异对照成立。
- check-manager-recovery：物化manager真实update/remove/previous分支6场景（check拒绝、remove拒绝、双失败、enable失败、官方恢复、无HMR），保原包/原目标配置/无关配置变更、reconcile及提示字段；writer重入/FIFO/普通卸载意图断言通过；失去reconcile变异1个判红。注意：installBundle/runPnpm/change/HMR边界仍被注入，并非整类+真实队列全栈集成。
- check-review-core-assets：完整installBundledCores在旧/缺/坏/异内容stamp×成功/stage失败/commit失败12场景，旧树回滚和独立profile字节保护。CoreStore边界注入，未执行其真实解压；实际安装Cordis Context/fiber.dispose异常隔离执行通过。尚未运行完整VM插件apply→Cordis卸载链。
- review-final.txt初跑112/1，唯一失败是旧门禁期望installBundle入口直接跟requestId，现有写锁封套使该原体改名；门禁精确锚改为dshmWriter_installBundle原体，非删判据。review-final2.txt完整同113条再跑113/0；review-final-ci.txt22命令rc0，最终OK→BAD=0。
- 最新核心zip SHA256 c9fac6fe38ca43cb7c65f44f2d13d8ec06fc2179bde952569be60dcbf68dd441；pack及resfile复核一致，宿主24件同步、OSS重新生成并check通过。core-integrity.md为最新实物记录。

### 新增/修改与官方diff

新增hostcore/app/dshm-profile-writer.cjs、tools/check-review-production.mjs、tools/check-manager-recovery.cjs、tools/check-review-core-assets.mjs。修改事务helper、installer/main、profile-pnpm插件、pack/place/assert、SyncStore/UploadRunner/SyncEngine及测试证据工具。ETS仍为下文15路径，无新增ETS、C++0。

新增官方diff较初版扩到五个manager公共写生命周期封套及本地恢复reconcile委托；必要性是原change文件锁仅包单次remove/install，无法覆盖跨两次操作的本地快照与恢复，队列执行又脱离原异步上下文，因此需显式token。不得宣称官方0改动或无需再审。现有官方检查/previous恢复/配置/HMR算法仍在原体，不追上游不改版本。

### 仍需父代理审查/续作边界

T018保持未完成，原独立FAIL报告未改。专用check_ets_files须首次fullbuild前做；尤其核StoreResult控制流、SDK querySql参数及Asset API。真实manager全类/真实installBundle+队列、完整CoreStore及VM插件dispose尚非全栈验收；新增YAML目标块、锁恢复/跨进程和并发enable需继续反证。当前报告明确这些差距，不能以专项14rc0或113绿自动放行。T005/T006/T007及T009–T015不擅勾全，留最终验收核实。

## 独立FAIL后的修正增量（仍未放行）

完整读取post-fix-review.md，原独立FAIL报告未改写。修正了R1准备完成/业务开始/恢复尝试状态门：复制首文件或中途ENOSPC时不触碰原dest，partial backup不作恢复源；恢复用copy并保留完整backup直到manifest成功，恢复自身失败不再次破坏性重试。R2对官方step=check/remove拒绝直接返回，不删包或重放manifest（仍有准备复制成本，未完成锁集成）。R4补GitHub shorthand原文和alias生产端dependencyValueFor身份保存。R5补hash catch取消再抛、runner尾阶段检查、invalidate清旧progress/kindStat并提示排空。R6增加释放代次，系统申请前后校验及晚到成功停止，screen stop后校验，release归零淘汰在途。R7将逐备份恢复错误收集到结果，保留原错误并继续后续备份。R8增加未提交快照拥有权集合、copy/hash失败清理；一旦提交数据库即移除可删拥有权，模糊提交失败仍保留，不猜平台安全删除时点。插件清单finally清理是否已生效须继续核查。

新生产故障注入tools/check-review-regressions.cjs：R1首文件/中途复制失败2例，operation未调用且旧包完整字节不变；R2 check/remove拒绝2例零包删除；R7真实installSpec原错误+恢复失败诊断并继续第二备份。R1/R2两个变异均判红。尚未补全R4/R5/R6/R8真实链新增反例测试，不把原测试通过当新增反例闭合。

最终本增量实跑：review-after.txt 113/0；review-after-ci.txt 22命令rc0；targeted.txt 11命令rc0。pack再次成功；核心zip SHA保持8e09f51ac60d3fcfc6593e0f84219d40b7a1adc07c480cafe34721bc79d7b6b3，因为本次改的是宿主resfile app与ETS，未进一步改zip中的manager/VM字节；23件宿主资源已重新place并assert同步通过。main注册已前移runProfile之前。

**实质未闭合，不得进入应用build：R3目标用户行/patch精确恢复、运行态恢复及用户可见提示消费者尚未实现；R2与普通卸载/enable/direct写者统一锁未闭合；R8总空间预算/重复未变单元上限未实现。完整真实manager remove/install/recover集成矩阵仍未新增。需要继续实现这些，不是直接交验证代理。当前状态仍PARTIAL，必须再次独立只读复核，不能把报告改成PASS。**

本增量新增文件tools/check-review-regressions.cjs；改动hostcore/app/{main.js,dshm-installer.js,dshm-update-transaction.cjs}、platform/src/main/ets/{notify/KeepAlive.ets,sync/PluginRestore.ets,sync/UploadRunner.ets,sync/ImportRunner.ets,sync/SyncEngine.ets,sync/SyncStore.ets}、tools/{check-fix-review-behavior.mjs,check-fix-review-content.mjs,fix-review-evidence.py}及生成证据/资源。专用静态仍为原15个ETS清单，无新增ETS路径，C++仍0。

## 状态：PARTIAL

已实施11候选及tmp的源码修复初稿，并完成核心物化及同口径回归；但问题级覆盖、独立复核及专用静态检查尚不完整，不能宣布T004–T019全数完成，也不能进入无条件出包。

## 已执行证据

- before.txt：113/0；after.txt第一次112/1（plugin-toggle宿主启动90秒超时）；单独重跑PASS；after-final.txt同113条完整再跑113/0，最终OK→BAD=0。保留首次失败报告，不抹除。
- before-ci.txt、after-ci.txt：各22条rc0，含重复命令，不能相加成135唯一门禁。
- targeted.txt：10个命令rc0，包括新增生产逻辑测试、既有自检、单容器、Beta入口及文档门禁。
- 新behavior测试：DR1 7案例；E01 5；B01 4；E04 token2+engine5；E02 mapping3+unmapped3；6个变异判红。生产函数提取/类型擦除，系统边界mock，不是ROM测试。
- 新content测试：E03导入5案例、E05资产3、C01 stop8断言；4个变异判红。FR1追加了生产identity判等7断言及1变异，需以最终targeted重跑为准。
- D01真实本地事务helper6场景及1变异通过；这不是完整官方manager remove/install/recover集成测试。普通卸载未接入事务helper，不误复活；成功官方restore保留，不替换官方恢复。
- 既有host-vm门禁改为不允许QMP close/end冒充exit，13变异判红；原门禁要求close直接finish属于旧错误契约，已纠正而非放宽。

## 源码落地

DR1唯一mkdtemp目录隔离；E01 name+spec/npm alias与Git保留；B01只有成功获取计入refs并修phone备用caller失败release；E04任务token取消、身份/root代次、执行锁排空、runner检查及两壳/原生回调隔离；E02每次重扫、未映射保留统计且不写未知目录；D01本地快照+官方更新生命周期封套和direct安装保旧、tmp TDZ删除；E03目标/暂存流式SHA校验；E05每次唯一快照、hash与size来自快照；C01捕获worker退出或8秒明确未确认超时；FR1 sha256 stamp、未知旧stamp重装；CR2计数移到共同作用域；AGC调用改为devecocli build --product release --build-mode release，保留原finally恢复。

## 官方差异及必要性

非零新增官方diff：仅在pack-core中对官方manager updateBundle加入委托封套，原实现改名dshmUpdateBundleInner。原检查、防重复、remove→install→previous重装分支完整保留。原因：本地installSpec入口晚于官方remove，无法在其入口保住已删除旧目录。封套将备份/恢复实现在DSHM本地模块，不重写官方更新算法。仍需独立审查并补manager真实集成测试。

## 核心与资源

已执行CODEBUDDY_SAFE_DELETE_ENABLED=0 node tools/pack-core.mjs --skip-install --place-in-app；core-integrity.md记录实际zip与VM源逐字节一致、manager封套和previous恢复都在zip。zip为hostruntime/src/main/resources/resfile/dsh-core-0.2.2-rc.2+dshm.1-openharmony-arm64.zip，SHA256 8e09f51ac60d3fcfc6593e0f84219d40b7a1adc07c480cafe34721bc79d7b6b3。宿主23件资源同步，OSS已重新生成及check通过。pack原生签名47通过/7未检出，不声称全部验签通过。

## 待父代理专用检查的全部ETS

platform/src/main/ets/system/FilePicker.ets
platform/src/main/ets/system/FileDigest.ets
platform/src/main/ets/sync/PluginRestore.ets
platform/src/main/ets/notify/KeepAlive.ets
platform/src/main/ets/sync/SyncTask.ets
platform/src/main/ets/sync/SyncEngine.ets
platform/src/main/ets/sync/UploadRunner.ets
platform/src/main/ets/sync/ImportRunner.ets
platform/src/main/ets/sync/SyncStore.ets
platform/src/main/ets/view/CloudSyncSettings.ets
platform/src/main/ets/Index.ets
entry/src/main/ets/pages/WebApp.ets
phone/src/main/ets/pages/WebApp.ets
phone/src/main/ets/entryability/EntryAbility.ets
hostruntime/src/main/ets/core/BundledCore.ets

C++修改0。不将lint Files checked0当通过。父会话必须在首次full build前check_ets_files并修复真实诊断。

## 其它修改文件

hostcore/app/main.js、dshm-installer.js、新dshm-update-transaction.cjs；hostcore/plugins/dshm-vm-bash/lib/{vm,index}.js；tools/{pack-core,place-host-app,assert-resfile-sync,build-agc,check-host-vm-graceful-stop}.mjs；新增tools/check-fix-review-{behavior,content}.mjs、check-update-transaction.cjs、fix-review-{baseline,evidence}.py；feature测试/阻塞/复核/实施文档与tasks；dist/acceptance本批证据；生成的resfile、core manifest/zip、两壳OSS。

## 未决与边界

T009–T015代码虽已改，但未逐项达到全部批准的验收矩阵，保守保持未勾选；T016已物化有证据；T017可执行回归已完成但专用静态待父；T018待父独立委派。不能用本报告补记成全完成。需先补审查发现的问题及测试，再核tasks。FR1整函数旧stamp迁移/profile保护、CR2真实Cordis dispose、完整manager更新链仍缺问题级生产集成证据。新增Asset长期留存空间成本未解决安全回收。

应用身份1.1.8/1010016、权限18/9及签名设备策略未改。未应用build、未Beta/AGC出包、未deploy/UI；T020–T022未执行。未commit/reset、未清用户数据或签名。Beta入口仍node tools/build-beta.mjs --combined-app；AGC入口node tools/build-agc.mjs，两者只交下一验证阶段。未生成本轮应用包，不宣称真机正常。

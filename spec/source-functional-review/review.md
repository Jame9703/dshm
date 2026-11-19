# 当前源码功能审查：独立复核后最终清单

## 结论与判读

本文件是本轮候选的最终权威清单；分域报告是阶段4记录，若分级冲突以本文件及 `verification.md` 为准。12条候选逐项复核后：**6条静态确认缺陷、5条条件性风险、1条剔除**。没有证据充分的P0；未运行应用或真机复现，不能据此证明产品全功能正确。

- 确认缺陷分布：P1两条（D-01、E-01），P2三条（E-02、B-01、E-04），P3一条（C-R2）。确认指条件下代码因果闭合，不表示当前用户已经遇到。
- 风险分布：P1四条（C-01、E-03、E-05、D-R1），P2一条（F-R1）。风险严重性表示条件成立后的潜在影响，不是事故证据。
- P1为主要能力不可用/重要数据损坏，P2为局部流程失败或状态错误，P3为可观测性等轻微问题。严重性与确认等级分开。
- 用户PC目前正常是外部实测输入；本轮未验证PC、普通平板、手机、折叠屏运行状态。共享代码影响面不代表所有端必现。
- 官方检索因better-sqlite3绑定缺失失败；没有documentId，未伪造docs read。系统API和Asset时序不能由源码注释或经验补足。

下列路径均相对项目根 `~/data/DSHM-deveco-workspace`；同步文件前缀为 `platform/src/main/ets/sync/`。

## 一、静态确认缺陷

### D-01 · P1 · 插件换版失败会丢失原可用安装目录

- **影响端/触发**：共享安装器，所有端；对已装可用npm用户插件请求不同版本，解析成功后下载、完整性或解包失败。不是仅凭某市场upgrade按钮推断；直接安装指定版本也是换版入口。
- **可达因果**：`entry/src/main/ets/view/SettingsPlugins.ets:248–270` 将输入spec投递req；`hostcore/app/main.js:8777–8789,8834–8858`解析后交安装器。`hostcore/app/dshm-installer.js:1095–1104,1398–1421`在版本漂移时越过幂等，1418删除live dest，1421才下载；失败由`1306–1311`返回false，没有备份恢复。`1434–1437`的tmp是新包解压目录，**不是先保旧的事务staging**；最终`1529–1543`也只删除/替换新目标。`1590–1714`未恢复旧包。
- **实际/预期**：失败后旧目录已删除、原profile登记仍可能保留；预期更新失败保留旧可用安装。不能夸大为所有App必崩，当前内存中已加载模块也不一定即时失效。
- **反证**：同版可用会幂等；解析失败在删包前；GitHub缺构建产物的npm fallback在`1566–1584`，不能救普通npm下载/校验失败。市场隔离prefetch可能减小部分入口风险，不构成直接请求的保护。main仅回.fail，不回滚。
- **附属错误**：`1429–1435`完整性失败分支在const tmp初始化前引用tmp，会遮盖原错误，不是绕过校验。随资源副本`hostruntime/src/main/resources/resfile/resources/app/dshm-installer.js:1398–1435`复核相同。
- **建议方向**：新包下载、验包、可加载验证完成后再事务替换，失败保旧；错误路径只清理已拥有的临时对象。不提供补丁。

### E-01 · P1 · 云插件恢复丢失npm包名

- **影响端/触发**：所有端；云清单中的npm依赖在本机缺失，用户勾选恢复。
- **可达因果**：`PluginManifest.ets:109,134–157,190–196`保存独立name与版本spec；`SyncEngine.ets:683–709,608–637`原样解析并投恢复器；`platform/src/main/ets/view/CloudSyncSettings.ets:534–586`缺失项选择不重组。`PluginRestore.ets:114–123,173–177`仅写s.spec进req，随后才修改结果显示name。main上述解析链及`hostcore/app/dshm-install-command.js:159–166`不补包名；installer`567–586,603–631`将`^1.2.3`当包名查询，而不是foo的版本。
- **实际/预期**：请求错误包标识，无法按清单恢复原包；预期传递完整安装意图。
- **反证**：完整GitHub spec本来包含仓库身份，不能类推；r.name只是结果展示；版本不同默认保留本机并不影响缺失项触发。内存正则演示得到parsedName=`^1.2.3`，没有发registry请求。
- **建议方向**：按npm版本、别名、Git来源分别重建完整请求并验证清单往返。

### E-02 · P2（由P1收窄降级）· 未映射远端工作区被静默排除且无建立映射入口

- **影响端/触发**：所有端；云表有会话，但新设备sessions为空，或本地projectKey与远端不同且workspaceId不匹配。
- **可达因果**：`SyncPlanner.ets:66–75,151–183`以完整projectKey摘要生成ID；`SyncEngine.ets:433–477`只映射本地已有`--…--`目录并缓存，没有公开映射setter。`ImportRunner.ets:143–159`发现阶段就continue掉未知ws；`200–204,377–388`零候选以ok=true结束；`SyncEngine.ets:439–441`返回空错误，`platform/src/main/ets/view/CloudSyncSettings.ets:511–522`显示“拉取并导入完成”。
- **实际/预期**：不能区分“云端无内容”和“有内容但未映射”，未映射数/原因不进入结果；现有UI也不能建立远端→本地映射。预期至少明确未导入原因；并不要求自动写入未知目录。
- **反证**：拒绝未知映射是合理安全策略，不单独当bug；同路径且已有目录可导入，用户先创建同路径工作区可绕过部分场景。全工程WorkspaceMapping引用仅类型/engine/runner；原生面板`390–859`及云client搜索无映射动作，仅有未接线的map_workspace翻译。没有将不同设备路径设计本身定性为错误。故从“主要恢复必坏”降为局部恢复/反馈缺陷。
- **建议方向**：保留未映射发现结果、显示数量和原因，提供显式确认目标；不能猜绝对路径。

### B-01 · P2 · 失败保活申请累加引用，后续成功后的单次释放不足

- **影响端/触发**：明确可达phone/折叠及entry手持分支（普通平板）；申请失败后重试成功，再回前台。PC还有长驻申请策略，不能把PC前台仍保活直接叫本缺陷。
- **可达因果**：`platform/src/main/ets/notify/KeepAlive.ets:364–385`先refs++，失败无回退；`429–458`仅归零才stop。phone`EntryAbility.ets:1734–1808`失败清held但不release，30秒后可重试；前台`1462–1485`和`1799–1805`只按held释放一次。entry对应`2070–2107`同样失败失配。
- **实际/预期**：两次失败再成功，refs=3，回前台释放后refs=2、held=false、active仍true；预期只持有成功申请对应的引用。
- **反证**：generation只处理晚到成功；userStopped在++前拒绝不计此例；forceRelease只在销毁/特定关闭路径清零，不是常规前台兜底。phone`1879–1882`异常备用路径确有失败release，但主轮询路径没有；entry完成通知`2840`可能额外释放，不能保证在“任务仍运行、回前台”条件下发生。内存演示验证计数，不调用后台API；通知残留或系统冻结的实际表现未测。
- **建议方向**：以引用拥有权配平失败/成功/取消，避免caller held与底层refs分离。

### E-04 · P2 · 退出后旧同步任务仍回写状态

- **影响端/触发**：所有端；上传或拉取已进入await期间点击退出。
- **可达因果**：`SyncActions.ets:91–94`不以running拒绝退出，`hostcore/plugins/dshm-cloud-sync/lib/client.js:558–561`退出未禁用；phone WebApp`3988–3990`调用signOut；原生面板`741–748`同样可达。`SyncEngine.ets:271–281`仅清字段，不取消任务/推进代次；`351–377,421–447`恢复执行后继续调用runner/上传插件清单并重填lastSync/cloudOk。
- **实际/预期**：退出后signedIn=false、enabled=false，却可重新出现旧任务完成/连接状态；退出不阻断已在途任务。预期隔离退出前任务结果并明确取消或等待策略。
- **反证**：入口身份/开关检查只挡新任务；UI busy挡上传等按钮，不挡退出；runner不回读登录态。**没有证据证明跨华为账号泄漏**，也未证明平台账号切换和旧任务云归属；不作该指控。
- **建议方向**：任务身份/代次与取消策略贯穿await及状态回填，退出时清晰处理在途任务。

### C-R2 · P3（由P2风险调整为低影响确认）· VM插件卸载统计日志抛ReferenceError

- **影响端/触发**：启用VM且apply已进入包装分支的端，插件实际卸载/重载执行effect清理；常规新建终端不触发，VM disabled/运行时不可用提前return也不注册该回调。
- **证据**：`hostcore/plugins/dshm-vm-bash/lib/index.js:312–314`的let位于if块内，块外`413–419`清理模板引用它；没有同名外层绑定。内存同构闭包演示抛ReferenceError。profile`hostcore/profile/ondevice/cordis.patch.yml:777–779`装配该插件；实际随包zip中相同成员、相同行存在。
- **反证与影响收窄**：当前依赖 `dist/core/work/dsh-core-0.2.2-rc.2+dshm.1/node_modules/@deepseek-ai/cordis/lib/index.js:693–706`的_unload逐个运行dispose并catch/logger.error，其他dispose继续。出错回调除统计log没有释放逻辑；删除shutdown hook与清预热timer是另两个effect（VM index`254,410`）。所以确认的影响仅卸载统计失败并记错误，**不能认定宿主崩溃或阻断VM资源释放**；依赖工作树尚未与归档Cordis逐字核对。
- **建议方向**：让统计状态与使用回调处于一致作用域；不扩大为资源泄漏修复。

## 二、条件性风险（不是确认事故）

| ID / 级别 | 影响端、触发条件与当前证据 | 反证/缺口 | 建议方向 |
|---|---|---|---|
| C-01 / P1 | VM启用端（通常普通平板/手机/折叠）；关闭Host时QMP close/end先于worker exit且worker超过后续退出窗口。`hostcore/plugins/dshm-vm-bash/lib/vm.js:1523–1568`将close/end也连到finish，任意data主动destroy；index`251–254,428–430`注册，main`8533–8587`确实等待hook，完成后1500ms兜底退出。随包zip关键段相同。 | 控制流提前完成窗口成立；快速quit时可能正常。未启动QMP/VM，未测worker刷盘和process.exit实际时序，**不确认坏镜像/数据损坏**。内存演示只表明finish不检查workerExited。 | 以worker退出作为正常完成信号，区分协议连接关闭、超时和真正退出。 |
| E-03 / P1 | 所有同步端；同长不同内容到达导入器，或本地目标同长不同内容。`ImportRunner.ets:240–267`只查sha形态和大小；`273–288`同大小skip；`309–363`复制后仅大小和头64字节可读，无内容sha/会话格式校验。`UploadRunner.ets:135–168`确实产生sha。 | 大小不符拒绝、已有目标不覆盖；同尺寸不等于同内容的内存反例成立。但当前真实损坏资产/同ID代际分叉样本未提供，平台是否保证资产完整性未核，不能报必然损坏。注释“六道闸”不当行为证据。 | 消费真实摘要并验证会话格式；目标相同判定不只看长度。 |
| E-05 / P1 | 所有上传端；技能目录同时有`a/b`及`a_b`等可被递归扫描的不同文件，或跨kind同相对名。`SyncPlanner.ets:226–270`以原rel构unitId，却把斜杠换下划线作assetName；`SyncModel.ets:165–168`保留原rel，不是单射保护。`SyncStore.ets:200–225`再次安全化/截断并删同名dst；`UploadRunner.ets:146–176`将同一路径存给不同unit。 | 内存展示不同unitId同assetName；普通文件名与深度检查不排除反例，故不剔除。**本地共享路径覆盖窗口确认，云端拿错字节仍是风险**：autoSync/insert何时快照Asset未获官方证据，没有实际技能/附件碰撞样本。 | 使用包含unit身份或内容摘要的不可变资产路径，别仅安全化显示名。 |
| D-R1 / P1 | 当前直接证据为entry非手持（PC/2in1及原生桌面判定设备）选目录、持久授权失败并遇已有同名文件。`platform/src/main/ets/system/FilePicker.ets:162,336–346,385–418`固定名CREATE/READ_WRITE/TRUNC后write/unlink；entry WebApp`3541–3555`也调用。 | handheld和persisted=true短路不探写，不能说普通手机/平板每次选目录都损坏。官方TRUNC/open既存文件语义查询失败，无设备探针，故保持风险而非确认损坏；不凭注释授权面定论。 | 独占、不可覆盖的临时对象及明确所有权清理，不接触预存文件。 |
| F-R1 / P2 | 所有使用BundledCore的端；同版本标签且等尺寸但不同内容容器替换、旧树stamp存在。`hostruntime/src/main/ets/core/BundledCore.ets:154–222`比较大小后直接continue；缺stamp的builtAt分支更弱。 | `338–421`确有stage/commit/恢复旧树，但不参与跳过分支。本轮没有具体旧/新等尺寸容器对或已安装旧树证据，**降为低证据发布健壮性风险**，不是当前版本未更新的确认bug。 | 可复核内容身份/摘要，结合真实发布与已安装树样本确认。 |

## 三、剔除项及不成立的扩大主张

**A-R1剔除出缺陷/风险统计**：`entry/src/main/ets/pages/WebApp.ets:1298–1337`挂摘不对称可见，但`4233–4234`普通平板form不随pcMode变化；`3917,3957`形态缓存及entry模块`deviceTypes`未闭合当前生产同文档desktop→handheld序列。DESKTOP_CLASS当前引用另见`1439,1449`为诊断，未形成实际CSS冲突证据。不能用注释“PC模式翻转”证明可达视觉故障；若以后有真实切换序列可重新建候选，不能列为本轮P2问题。

没有保留“慢启动必永久401”“固定zsh令手机终端全坏”“cancel一定泄漏返回的终端”“坏核心zip必删旧树”“完成通知降级完全未消费”“云插件清单永不上云”“退出必跨账号泄漏”等扩大主张。阶段4这些反证不等于本阶段全路径重新验收，也不增加确认缺陷数量。

## 四、覆盖与交付边界（T013）

`coverage.md`保留阶段4六域阅读矩阵，不改写其当时执行账。本阶段完整读取本轮spec、plan、tasks、review、coverage及六域报告后，独立重读以上12条的关键生产者、消费者和保护分支；**不是六个独立研究者的结论投票，也不是全仓第二次深审**。

| 域 | 本阶段补核 | 仍未验证 |
|---|---|---|
| A | entry分类脚本/原生形态桥/类消费者定位、module设备声明 | DOM/CSS完整视觉、IME/焦点/返回/折叠分屏真机行为 |
| B | KeepAlive refs所有acquire/release调用点定位、phone轮询与前台、entry后台及额外释放反证 | 平台后台API及通知实际表现、多会话完整时序 |
| C | VM stop→hook→Host退出、effect作用域、Cordis卸载隔离；随包VM两成员内存读取 | VM启动/退出刷盘、QEMU/native PTY、随包Cordis完整一致性 |
| D | installer换版至失败/落位/fallback/结果全链，直接req入口、解析消费者及资源副本 | 所有市场upgrade UI实现、网络/解包故障注入、fs-local完整能力、官方文件API |
| E | 清单往返、UI选择、映射引用及原生面板、导入校验、资产命名与上传、退出异步链 | 真云数据、系统账号隔离、Asset生命周期、技能附件真实碰撞实例 |
| F | BundledCore跳过及stage/commit/finally反证 | 新旧同长容器实例、构建/签名/已安装私有树、全补丁闭包 |

执行账、纯内存命令结果和每项决定详见 `verification.md`。仅主动写review.md、verification.md、tasks.md；没有源码/配置/资源修复，没有build/deploy/UI/device、业务网络测试、docs/memory/acceptance写入、提交或重置。任务勾选仅表示只读审查交付完成，不表示没有缺陷或产品通过。

# 阶段5独立证据复核（T012/T013）

## 范围及流程审计

- PROJECT_ROOT：`~/data/DSHM-deveco-workspace`；动态解析本机HOME后CONFIG_ROOT为`~/.local/share/deveco/`；Confirmed_Feature_Dir直接使用本目录。
- 完整读取CONFIG_ROOT下spec-verify.md以及本轮spec、plan、tasks、review、coverage、六域报告。加载deveco-cli技能；未读取历史docs/HANDOFF、memory、旧acceptance或旧审查。AGENTS只约束安全，不作产品正确性依据。
- tasks第45行明确`source-review+side-effect-free-checks`。用户和本轮任务禁止build/deploy/UI/device/fix；默认spec-verify只定义build-only/build+ui，**不原生支持此自定义scope**。本次没有擅自归入build-only，也没有执行默认fix loop；下表如实报告默认流程未执行，不能冒称默认验证通过。
- `code_modified=false`，build调用0、deploy调用0、UI调用0、修复0。默认Phase 2不适用（不是build+ui且无per-story修复）；本次独立源码反证不是UI final pass。
- 初始命令`pwd; printenv HOME`仅用于原生home定位；它发生在加载spec-verify之前。加载后发现其“不得shell检查环境变量”约束，记录这一流程偏差；未重复环境变量检查，也不把它隐去。

| 步骤 | 状态 | 原因/结果 |
|---|---|---|
| 读取范围与报告、重新查源码 | 已执行 | 12候选逐项独立判断，不能以阶段4报告替代证据 |
| 官方API检索 | 失败，保留缺口 | better-sqlite3绑定缺失，未返回documentId；不安装/修复工具、不伪造read |
| 归档只读抽查 | 已执行 | VM index.js/vm.js直接zip.read进内存，无extract/落盘，无业务模块导入 |
| 纯内存逻辑演示 | 已执行 | 仅字面对象、字符串、正则、计数和闭包，stdout输出；不是ArkTS/系统API或业务端到端测试 |
| build/start/deploy | 未执行 | 本轮明令禁止，自定义scope；默认工作流的这些步骤未满足 |
| UI计划/逐故事验证/重试/final pass | 未执行 | 未授权应用设备操作；没有UI通过/失败/重试统计 |
| 修复/资源生成/业务门禁 | 未执行 | 不在授权内；没有完整安全证明的脚本不执行 |
| 报告收口 | 已执行 | review为权威，tasks仅勾选审查任务；coverage阶段4文件未修改，当前边界补在review |

## 逐候选复核决定与反证

路径均相对PROJECT_ROOT；同步文件位于`platform/src/main/ets/sync/`。完整最终问题描述及建议见review，以下记录独立决定而非复述首轮分级。

| 候选 | 决定 | 独立依据及反证 |
|---|---|---|
| D-01 | 保留P1静态确认 | installer`1095–1104,1398–1437`不同npm版本删除live dest后才下载，tmp仅新包解压；`1529–1589,1590–1714`没有旧包恢复；GitHub fallback在落位可加载失败后，不能救普通npm下载异常。main`8777–8789,8834–8858`不备份。直接设置req入口`entry/.../view/SettingsPlugins.ets:248–270`足以触发指定版本换版；没有声称每个市场upgrade都绕过prefetch。资源installer`1398–1435`相同，校验错误还存在tmp TDZ。 |
| E-01 | 保留P1静态确认 | Manifest`109,134–157`→Engine`683–709,608–637`→面板`534–586`→Restore`114–123,173–177`保持name/spec分离，却只投spec。install-command`159–166`单token不补名；installer`567–586,603–631`当完整包名。内存`^1.2.3`被解析为name本身。GitHub完整仓库spec是反例边界，不推翻npm问题。 |
| E-02 | 收窄降为P2静态确认 | 未映射过滤是安全策略，不能单独报错。Engine`433–477`只建本地hash映射，Planner`66–75`完整projectKey相关；全工程WorkspaceMapping引用无公开设置通路，面板`390–859`和云client未接映射动作。Import`143–159`提前过滤后`377–388`仍ok=true，面板`511–522`完成提示无未映射原因，这是确认的局部恢复/反馈缺陷。相同路径已有工作区可以成功，不声称所有新设备必不可恢复。 |
| B-01 | 保留P2静态确认，缩小表现断言 | KeepAlive`364–385,429–458`失败不退refs；phone`1771–1805`主路径失败清held、成功只释放一份。完整定位所有acquire/release；phone备用`1879–1882`失败确有release，非主路径保护；forceRelease在销毁，不在常规前台。entry`2840`完成通知额外release也不能覆盖任务仍跑回前台窗口。内存2失败1成功后refs=2/active=true；平台通知残留未实测。PC长驻策略不当此缺陷证据。 |
| E-04 | 保留P2静态确认 | Actions`91–94`、client`558–561`、phone WebApp`3988–3990`和面板`741–748`允许busy退出。Engine`271–281`清状态而无epoch/cancel，`351–377,421–447`越过await后继续写状态；runner无登录态保护。仅确认旧任务延续和退出后回填，不指控跨账号上传/泄漏。 |
| C-01 | 保留P1风险 | stop`1523–1568`data→destroy→close/end→finish不要求worker exit；main`8533–8587`确实await hook并1500ms兜底exit。已从当前随资源zip读同段，排除“只有开发源码有”的反证。快速退出正常的可能仍在；未取得真实QMP/worker慢退出及镜像损伤样本，不能升级事故确定性。 |
| E-03 | 保留P1风险，确认校验缺失事实 | Import`240–288,309–363`未比较内容sha、未解压验证会话结构，同尺寸skip；Upload`135–168`确实有sha。大小不符拒绝、目标已存在不覆盖；真实同ID同长不同内容/损坏资产可达性仍无样本，系统保障无法核验。注释承诺不能代替格式消费者证据。 |
| E-05 | 保留P1风险，补非单射证据 | Planner`226–270`递归允许普通相对名a/b与a_b；Model`165–168`unitId保留kind/ws/原rel，而Store`207–225`只接assetName并再次安全化和截断。Upload`146–176`不加unitId，所以“ID唯一”不能保护文件名。内存给出不同unitId同assetName。未提供用户实际碰撞目录，且系统insert/autoSync是否即时快照未知；确认本地别名覆盖窗口，不确认云资产已损坏。 |
| D-R1 | 保留P1风险，端面收窄 | FilePicker`162,336–346,385–418`及entry WebApp`3541–3555`表明只有非handheld且persist失败才探写。固定名无预存文件保护；但TRUNC/open已有对象行为无官方证据，因此不报已确认用户文件被毁。没有创建探针/目录。 |
| C-R2 | 改为P3静态确认（影响降级） | VM index`312–314,413–419`块外读取块内let，闭包内存演示ReferenceError；zip同段存在。进一步独立读当前Cordis`463–478,533–563,693–706`，确认卸载会执行dispose且逐项catch/logger.error；该出错effect只有log，hook删除和timer清理是别的effect。撤销“干扰全部清理/宿主崩溃”推断，确认仅统计日志失败。未做插件实际卸载，未导入VM入口。 |
| F-R1 | 降为低证据P2风险 | BundledCore`154–222`只大小stamp可skip，`338–421`事务保旧仅在未skip后生效。没有本轮真实新旧同长容器实例；不能把代码上的弱判等直接认成当前更新失败。 |
| A-R1 | 剔除，不计风险 | entry WebApp`1298–1337`不对称属实，但`4233–4234`tablet form不随pcMode变化，`3917,3957`缓存和模块deviceTypes未形成生产同文档desktop→handheld序列；DESKTOP_CLASS其余`1439,1449`为诊断，未闭合CSS冲突。仅理论类残留不足以列P2用户问题。并非证明所有UI正确。 |

结果：原5条确认候选中4条维持级别、E-02降级；原7条风险中C-R2改为低影响确认，F-R1证据降级，A-R1剔除，其余保留条件边界。最终6确认+5风险+1剔除；无重复根因新增计数，D-01的TDZ为附属而非另起条目。

## 无副作用检查记录

### K1 官方API

实际命令：`devecocli docs search fileIo OpenMode TRUNC relationalStore Asset --format json`。

输出：`Could not locate the bindings file`，列出better_sqlite3.node候选路径；未返回文档ID。失败后没有修依赖、安装包或猜ID；无docs read可执行。因而D-R1保持风险，E-03/E-05的系统资产行为保持缺口。本命令是文档查询，不是云端业务请求；工具内部缓存行为不能由本轮调用记录证明，未主动请求写文件。

### K2 归档内存读取

执行前确认：下面代码仅标准库zipfile只读打开既有归档，read解压到内存并print；没有extract、write、mkdir、子进程、网络或业务模块导入。`-B`禁止pyc写入。无需创建目录。

```sh
python3 -B -c 'import zipfile; p="hostruntime/src/main/resources/resfile/dsh-core-0.2.2-rc.2+dshm.1-openharmony-arm64.zip"; z=zipfile.ZipFile(p,"r"); suffixes=("/dshm-vm-bash/lib/vm.js","/dshm-vm-bash/lib/index.js"); names=[n for n in z.namelist() if any(n.endswith(s) for s in suffixes)]; print("archive_matches",names); [(print("MEMBER",n),[(print(str(i)+": "+s)) for i,s in enumerate(z.read(n).decode().splitlines(),1) if (1523<=i<=1569 if n.endswith("/vm.js") else 244<=i<=258 or 310<=i<=315 or 410<=i<=431)]) for n in names]; z.close()'
```

结果：当前归档找到`node_modules/@deepseek-ai/dshm-vm-bash/lib/index.js`及`vm.js`两个成员；上述行显示hook注册、块内let/块外清理和QMP close/end完成，与本次候选一致。仅核这两成员关键段，不代表整个zip、安装树、签名或其他依赖一致。

### K3 纯内存控制流

执行前确认：无require/import、文件/网络/设备API、定时器、进程启动、生产入口eval；只有字面量、正则、数组、集合、函数和stdout。是同构演示而非执行ArkTS原文件，不能验证系统API或真实业务调度。

```sh
node -e '"use strict"; const p={name:"foo",spec:"^1.2.3"}; const m=/^((?:@[^/\s]+\/)?[^@\s/]+)(?:@([^@\s]+))?$/.exec(p.spec); console.log("E-01",JSON.stringify({request:p.spec,parsedName:m[1],expectedName:p.name})); let refs=0,active=false,held=false; for(const ok of [false,false,true]){held=true;refs++;active=ok;if(!ok)held=false;} if(held){held=false;if(refs>0)refs--;if(refs===0)active=false;} console.log("B-01",JSON.stringify({refs,active,held})); const safe=s=>s.replace(/\//g,"_").replace(/[^A-Za-z0-9._-]/g,"_").slice(0,120); console.log("E-05",JSON.stringify(["a/b","a_b"].map(rel=>({unitId:"skill/global/"+rel,assetName:safe(rel)})))); const a="AAAA",b="BBBB"; console.log("E-03",JSON.stringify({different:a!==b,sameSize:a.length===b.length,branch:"skip"})); function setup(){if(true){let takenTerminal=0;void takenTerminal;}return()=>takenTerminal;}try{setup()();}catch(e){console.log("C-R2",e.name);} let done=false,workerExited=false;const finish=()=>{done=true;};finish();console.log("C-01",JSON.stringify({qmpClose:true,promiseFinished:done,workerExited})); const state={signedIn:true,enabled:true,lastSync:"running",cloudOk:false};state.signedIn=false;state.enabled=false;state.lastSync="";state.cloudOk=false;state.lastSync="upload complete";state.cloudOk=true;console.log("E-04",JSON.stringify(state)); const remote=["ws-remote"],mapped=new Set();const candidates=remote.filter(ws=>mapped.has(ws));console.log("E-02",JSON.stringify({remote:remote.length,candidates:candidates.length,failed:0,ok:true}));'
```

stdout要点：E-01 request/parsedName=`^1.2.3`而expectedName=`foo`；B-01 refs=2、active=true、held=false；E-05两个不同unitId均assetName=a_b；E-03 different=true/sameSize=true；C-R2 ReferenceError；C-01 promiseFinished=true/workerExited=false；E-04 signedIn=false/enabled=false/lastSync=upload complete/cloudOk=true；E-02 remote=1/candidates=0/ok=true。

局限：C-01/E-04/E-02为人为排列的同构状态路径，不是生产事件调度复现；E-03内容字符串不是实际session zstd；E-05文件名为合法可扫描反例而非用户数据样本。D-01无需模拟删文件，静态顺序足以证明条件后果；D-R1没有探针；F-R1没有伪造资源对。

## 最终状态与边界

- **只读审查交付：PASS**。T012逐条决定已完成，T013最终清单/覆盖/证据缺口已收口；这不表示产品质量PASS。产品仍有6条静态确认缺陷、5条条件风险。
- **默认spec-verify构建/部署/UI验证：INCOMPLETE / 未执行**。自定义scope不在默认工作流枚举中，且本轮禁止这些操作；不能把审查PASS替代默认验证结果。官方API检索失败已降级相关结论，非伪造通过。
- 两个故事的源码审查交付均已完成（US1六域边界透明、US2逐候选反证），无UI用例及retry；Phase2未执行，不存在Phase2权威UI结果。**权威源码结论为本次review，而非阶段4分域表。**
- 仅用apply_patch主动写本轮review.md、verification.md、tasks.md；其余源码、配置、资源、历史文档、memory、acceptance不写，已有改动未提交/还原。未读取凭据/用户私有数据，未运行build、deploy、device、UI、生产入口、业务网络或修复。没有全工作区前后哈希审计，不作“所有外部工具绝无隐式写入”的超证据保证。

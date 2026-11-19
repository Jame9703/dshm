# E-01 / E-02 / E-04 源码反证复核

## 结论

本轮独立重新取证，不继承 `review.md` 的定性。项目根为 `~/data/DSHM-deveco-workspace`。以下路径相对项目根，行号为本轮实际读取时的行号；`sync/` 指 `platform/src/main/ets/sync/`。

| 项目 | 最终判定 | 证据支持的最小结论 | 不支持的扩大结论 |
| --- | --- | --- | --- |
| E-01 | **确实存在** | 普通 npm 依赖被保存为独立 name 与版本 spec，恢复时只投递 spec，顶层安装器没有补回 name | 所有来源的插件都恢复失败；随包默认 profile 当前已有 npm 用户插件；所有市场/独立 profile 都进入此清单 |
| E-02 | **确实存在** | 未映射远端会话在发现阶段被丢弃，不能进入未映射/失败计数；零候选可成功结束。没有远端 ID 到本地目标的显式映射入口，且非空自动映射缓存不刷新 | 拒绝未知目录本身就是错误；任何换设备恢复都失败；用户在普通工作区页选目录就已经完成云映射 |
| E-04 | **确实存在** | 应用内退出清空账号显示与开关，却不隔离在途任务；旧 await 后续、进度回调和完成/失败路径仍可回填状态并继续后续步骤 | 退出必然重新登录；退出后网页立即显示连接成功；已经证明跨华为账号泄漏或系统账号切换后的云归属 |

这里的“确实存在”指可达入口与源码因果闭合，不表示已在真机/现有用户数据上发生。三个问题均有明确触发条件；平台云服务是否成功不是本轮离线审查能够保证的事实。

## 范围与方法

- 仅将 `spec/source-functional-review/review.md` 用作候选定位，随后重新读取生产者、消费者、桥、任务状态及保护分支。
- 未以历史 docs、memory、旧 acceptance 或测试脚本既有结论作为证据，也未运行门禁。
- 核对 `entry`、`phone`、`platform`、`hostruntime`、`hostcore` 的相关引用，及随包核心归档中的第一层 `@deepseek-ai` JavaScript 模块。否定性结论限于这些实际引用与调用链，不声称穷尽所有第三方依赖内部实现。
- 未 build、deploy、连接设备、执行生产模块 import、生产文件/网络操作、git 操作或修复。仅主动写本报告；未写 docs、memory 或其他交付文件。
- 归档使用 `python3 -B`、标准库 `zipfile` 只读内存读取，不解压、不执行成员；资源副本使用只读逐字比较。
- 纯内存例子执行前检查：无 import/require、文件、网络、定时器、生产 API 调用；只含正则、集合、对象、Promise 与标准输出。它们是控制流示例，不冒充真实 ArkTS/云服务集成测试。

## 共同可达性

### 当前共享实现而非仅旧模块

1. `platform/src/main/ets/Index.ets:208–234` 导出当前 engine、planner、runner、manifest、restore、actions。
2. `entry/src/main/ets/pages/WebApp.ets:80–91`、`phone/src/main/ets/pages/WebApp.ets:83–89` 导入共享云同步能力。桥注册分别为 entry `4272,4288,7129`，phone `3927,3932,6249–6252`，不是只定义未暴露的方法。
3. 客户端 `hostcore/plugins/dshm-cloud-sync/lib/client.js:123–188,197–216` 实际调用这两个桥，`717–732` 注册 `settings.section`。插件宿主半边 `lib/index.js:32–44` 只导出空 apply 与 name，没有暗中的参数补全、恢复或退出守卫。
4. 插件 `package.json:7–15,22–31` 指向实际 host/client 入口与 web client 声明；`hostcore/profile/ondevice/cordis.patch.yml:769–771` 有真实 insert。客户端恢复按钮 `lib/client.js:657–660` 发 restore；两壳受理后置 `cloudSyncOpen=true`，分别在 entry `4354–4361,7433–7441`、phone `4000–4004,6500–6508` 挂载共享原生面板。
5. 配方 `hostcore/core-recipe.json:3,15` 对应本轮归档 `hostruntime/src/main/resources/resfile/dsh-core-0.2.2-rc.2+dshm.1-openharmony-arm64.zip`。归档根 `dsh-core-0.2.2-rc.2+dshm.1/` 下插件 `lib/client.js`、`lib/index.js`、`package.json` 及 `profiles/ondevice/package.json`、`cordis.patch.yml` 均与对应源码逐字一致。
6. 归档 `node_modules/@deepseek-ai/dsh-client-modules/lib/index.js:615,790,974` 遍历 loader entries 并筛 web client；归档 `dsh-client-ui-settings-general/lib/client.js:10`（`settings.section` 首次匹配列 5806）读取槽位版本与 entries，消费已注册分区。不是凭源码注释认定设置分区可达。

### 真实 profile 的边界

- 正常 Host：entry `entryability/EntryAbility.ets:998–1003`、phone 对应 `932–936` 使用不带 profile 覆盖的 `new DshHost`；`hostruntime/.../runtime/DshHost.ets:124,132–146` 默认 `ondevice`，`443–444` 传给 runtime；`RuntimePort.ets:204–215` 写 `DSHM_PROFILE`。
- Host `hostcore/app/main.js:1560–1563,8140–8173,8423–8428` 据 HOME/PROFILE 建用户 profile 并启动该 profile。`SyncRoot.attach` 实际位于 `sync/SyncState.ets:40–48`，固定注入 `<filesDir>/dsh/home/sessions` 和 `profiles/ondevice`。
- `hostcore/profile/ondevice/package.json:6` 默认 dependencies 为空。E-01 需要用户安装后产生 npm 依赖或云端已存在相应清单，不能拿空种子证明当下已经触发。
- 安装器存在其他 profile 通道：main `8711–8724,8792–8826` 的 `.dir` / 命令 `--dir` / `--profile`。云恢复器不写这些字段；正常 ondevice Host 才与清单目录吻合。entry `superagent/SuperagentAbility.ets:130–131` 明确启动独立 profile，不能把它的全部插件恢复也算作已证明范围。
- entry/phone 模块声明分别在 `entry/src/main/module.json5:7–10`（tablet、2in1）、phone 对应 `7–9`（phone）。本文影响面为使用上述本地 WebApp 云同步链的端，不推断所有远程 Host、特殊窗口或第三方 profile 都具有相同行为。

## E-01：npm 恢复只剩版本

### 正证：写入到消费的完整链

| 阶段 | 当前证据与行为 |
| --- | --- |
| 安装后真实依赖形状 | `hostcore/app/dshm-installer.js:1125–1132` 以包名作 dependencies key；`1136–1160` 把 `name@range` 保存为 range，裸 name 保存为 `^version`，exact 保存版本。`1659–1661,1688–1690` 对顶层安装执行该登记。因此版本 spec 不是伪造输入才会出现 |
| 本地清单 | `sync/PluginManifest.ets:109,134–157` 从 deps[name] 取值，保留 `{name,spec}`；只排除 `@deepseek-ai/` 基础包（`58–64`），普通 npm 用户包不被排除 |
| 上传载荷 | `PluginManifest.ets:190–196` 分别序列化 name/spec。`SyncEngine.ets:177–183,505–563` 导出、暂存并写插件清单 Asset，不预先拼接完整 npm 标识 |
| 读取及比对 | `SyncEngine.ets:576–599,608–612,683–709` 读 payload、按原字段还原并比对。`PluginRestore.ets:73–89` 缺失组保留原对象，不重组 spec |
| 用户选择 | `platform/src/main/ets/view/CloudSyncSettings.ets:534–565` 将 diff.missing 作为候选并默认勾选；`568–586` 把勾选对象交 engine；`929–973` 有实际勾选和安装按钮 |
| 恢复投递 | `SyncEngine.ets:620–637` 调 `runPluginRestore`；`PluginRestore.ets:168,173–178` 只传 `s.spec` 给 installOne，之后的 `r.name=s.name` 仅改结果显示；`114–123` 将该 spec 原文写 `.req` |
| 队列消费 | `hostcore/app/main.js:8656–8658,8695–8725,8777–8817` 从 `.req` 读取一个字符串，解析命令及 profile/registry，`8838–8839` 将 parsed spec 直接交 installer，没有读远端 PluginSpec.name 的通道 |
| 命令解析 | `hostcore/app/dshm-install-command.js:145–166` 单 token 原样返回 spec；返回对象的 profile/dir/registry 默认空。版本文本不变成 name@version |
| 最终解析 | installer `1315–1356,1372–1378` 将顶层 spec 入队并解析；`567–586` npm 正则把 `^1.2.3` 当 name，range 为空；`603–631` 按这个 name 查询 registry。顶层解析失败直接抛出，由 `1306–1311` 返回失败，main `8857–8858` 写 fail 回执 |

### 反证检查

- **确有另一个补全函数，但不救顶层恢复**：installer `enqueuePackageDependencies:685–698` 为包内依赖拼 `depName+'@'+value`；调用在已解析/已安装包后（`1408,1610`）。恢复顶层 `queue=[{spec:spec.trim(),depth:0}]`（`1353`）先于此，已没有包名。
- **确有 alias，但用途不同**：installer `89–100,590–591` 的皮肤展示名别名是固定完整名查表，版本值不会命中；npm alias 正则 `575–577` 也要求完整别名安装标识，不会从版本推断原包。
- **确有重试，但仍查错名**：`614–627` 更换 registry；不会补 name。Host 取走 req 就删（main `8725`），恢复轮询 done/fail（`PluginRestore.ets:133–158`）不是重新构造正确请求的重试。
- GitHub 完整 spec 自带 owner/repo，installer `592–601` 可直接解析；不受“仅版本丢包名”这一最小结论覆盖。某些 tag 如 `latest` 可能恰是另一 npm 包名，故精确影响是**无法保证恢复原包**，不能只表述为“永远 404”。
- 版本不同时默认保留本机是明确的防替换选择（diff `84–87`、面板 `549–556`），不是本缺陷；触发以 missing 为准。
- 随包宿主资源 `hostruntime/src/main/resources/resfile/resources/app/{main.js,dshm-install-command.js,dshm-installer.js}` 与 `hostcore/app` 对应文件逐字一致，不存在资源副本已经补全而源码尚旧的反证。

### 触发与影响

源设备曾正常安装 `sample-plugin@^1.2.3`，profile 保存 `sample-plugin: ^1.2.3`，清单可被另一端读到；目标 ondevice profile 缺包，用户检查并安装。队列实际收到 `^1.2.3`，而非 `sample-plugin@^1.2.3`。原包不能按意图恢复，界面收到失败或错误目标的结果；没有证据证明用户现有插件被删除或所有插件来源均失败。

**判定：确实存在。** 纯内存正则结果：`^1.2.3 → {name:"^1.2.3",range:""}`，`1.2.3`、`latest` 同样成为 name；完整 `sample-plugin@^1.2.3 → {name:"sample-plugin",range:"^1.2.3"}`。未查询 registry。

## E-02：workspace 映射与静默空成功

### 正证：ID、映射建立入口、筛选与反馈

1. `sync/SyncPlanner.ets:66–75` 对完整 projectKey 做 FNV-1a，`151–183` 把相应 workspaceId 写入 session 单元。不是仅按项目显示名匹配。
2. 实际核心归档 `node_modules/@deepseek-ai/dsh-session-persistence-jsonl/lib/index.js:914–943` 根据 cwd 编码 projectKey，`3237–3263` materialize 时建立 project/session 目录。普通本地会话持久化因此是**自动映射的间接建立入口**，不能说完全没有建立入口。
3. `SyncEngine.ets:458–477` 唯一自动映射建立逻辑从 sessionsRoot 列目录，仅取 `--...--` 名称，生成 `{workspaceId:workspaceIdOf(k),projectKey:k}`，赋给私有 mappings。没有远端 workspaceId 参数或公开 setter；`394` 的 pullAndImport 实际签名只有 ctx，`392` 注释里的 templates 不构成实现。
4. `ImportRunner.ets:143–159` 查询 session 行后，对 mapped 集合之外的 workspace_id 直接 continue。不生成 outcome，不计 skipped/failed，不把未知 workspace 返回 UI。
5. `ImportRunner.ets:197–214,377–390` 以筛选后的 candidates 为总数；空数组使 failed=0，结果 `ok:true`、`导入完成：0 项可用`。runner `225–231` 虽有“工作区未映射”失败分支，但正常发现链已把这些行去掉，到不了这里。
6. `SyncEngine.ets:433–441` 用上述候选执行导入并返回空错误；原生面板 `CloudSyncSettings.ets:511–522` 显示“拉取并导入完成”。网页 client `603–612` 则显示桥状态的最近一次结果；两壳 task 包装（entry `4513–4533`、phone `4121–4132`）也不补未映射信息。

### 有无另外的映射或重试

- 当前同步类型引用形成闭环：`ImportRunner.ets:85–88,144,198`、`SyncEngine.ets:30,118,433,458–477`、公共类型导出 `Index.ets:219`。源码与归档桥引用未发现可写映射动作；`SyncActions.ets:23–29,69–130` 动作仅 login/signout/enable/disable/upload/pull/restore。
- client `lib/client.js:257` 的 `map_workspace` 仅阶段文案。共享原生面板完整动作/构建面（`390–648,650–980`）没有远端工作区列表或目标确认控件。普通工作区模型 `appstate/.../model/Workspace.ets:6–16` 是 id/name/path/sessionCount/primary；`entry/.../view/WorkspacePane.ets:49–52,170–172,214` 处理本地选择/选目录，不传云 workspaceId。
- WebApp 的目录浏览（entry `4069–4189`）是本地路径选择与 resolver，不能把它当成远端到本地映射 setter。新建目录或注册工作区也不等于已物化对应 sessions 项目目录；核心真正 mkdir(project) 位于上面的会话 materialize 路径。
- **同 cwd 且已存在对应 sessions 项目目录时可恢复**：自动生成同 workspaceId，这是真实保护性反证。未知目标不自动落盘是合理保守设计；确认的问题是不可操作的跨路径匹配和未告知被排除，而不是要求猜目录。
- **空缓存会重扫，非空缓存不会**：engine `459–461` 只有 length>0 才复用；`206–212` attach 只是更新路径，`271–281` 退出、`220–235` 登录均不清映射。首次拉取缓存了其他本地工作区后，即使再物化同路径目标，后续拉取也不会纳入新增目录，直到静态状态重建。不能简单保证“新建后再点一次拉取”总可绕过。
- 改成本地目标路径再建会话只会得到该本地 key 的摘要，不会自动认领不同路径远端 ID。普通重试只重复 query/filter，没有兜底映射。云表含数据时，`refreshStat` 的 kind 计数也不是未导入原因计数。

### 触发与影响

云拉取与 query 成功，有至少一条远端 session，目标本地映射集合为空或不含该 workspaceId；没有其他候选失败。导入结果成功且零项，用户无法区分云端无会话和云端有会话但未映射。若混有已映射会话，会报告部分已导入数量而不披露未映射遗漏。若非空映射已缓存，新增本地工作区仍可能不被后续拉取识别。

**判定：确实存在。** 内存反例 `remote=1,mapped=empty → candidates=0,failed=0,ok=true`，不调用 RDB。不同设备路径必然不同、云中确有记录、文件导入后可打开等运行事实不由这个例子证明。

## E-04：退出后旧任务继续与状态回填

### 所有华为云同步退出入口

| 入口 | 实际执行与保护 |
| --- | --- |
| 网页客户端 | `lib/client.js:558–562` 退出按钮不传 disabled；`515–523` act 没有 busy 拒绝。上传/拉取按钮才使用 busy（`569,603–604`） |
| 共用判定 | `SyncActions.ets:91–94` 对 signout 直接受理，不看 running。`92` 注释称任务会下一次读取状态失败，必须由消费者实现核对，不能当证据 |
| entry 桥 | `WebApp.ets:4324–4345` 读事实后直接 signOut，仅另清 cloudSyncAutoLogin |
| phone 桥 | `WebApp.ets:3967–3991` 同上 |
| 原生面板 | `CloudSyncSettings.ets:741–748` 退出无 enabled(!busy)，直接 signOut/refresh/notice |
| 引擎 | `SyncEngine.ets:271–281` 清 unionId、enabled、lastSync、资料与云状态。不变 running/progress，不推进任务代次、不调用取消、不等待现有任务 |

项目 ArkTS 调用引用只发现以上三个 `SyncEngine.signOut()` 调用点与该定义；没有另一个同名华为退出包装自动收尾。核心另有 DeepSeek 账号退出，见下方反证，不混为同一账号。

### 在途路径与全部主要纠正路径

- 上传入口 `SyncEngine.ets:323–339` 检查 enabled/unionId/root/running，只在开始检查。`351–359` await runUpload 后还调用 uploadPluginManifest；`360–375` 不论成功/部分失败/异常均可覆盖退出清掉的 lastSync/cloud 字段，`377` 只释放 running。
- UploadRunner `105–125,129–188,190–236` 会继续计算 sha、stageAsset、upsert、enableCloudSync、runCloudSync、statByKind 和 sink。参数没有取消 token、账号或 generation；它不 import engine，不回读 unionId/enabled。退出发生在计算摘要或开库 await 时，也可能尚未进入云调用，之后仍继续执行。
- 插件清单上传 `SyncEngine.ets:505–563` 只检查 profileDir/json/store，未检查退出状态；仍可在退出后暂存、计算 sha 与 upsert。是否由平台自动上云是另一层语义，不能只凭 autoSync=true 断言实际网络传输成功。
- 拉取入口 `394–405` 的身份/忙态检查同样只在开始。`407,416,421–424` await 之间没有复核；成功后 `431–440` 继续发现及导入并写 lastSync/cloudOk=true。`418,426` 失败路径也会在退出后回写异常云状态；`444` 异常回写 lastSync；`447` 只释放 running。
- ImportRunner `197–391` 未接收取消/代次，也不查询登录态，逐项文件处理和 sink 不因 engine.signOut 自动停止。这里指应用控制流未停，不是承诺平台在系统退出后仍能给它数据。
- 插件恢复 `SyncEngine.ets:620–637` 未使用 running 锁，也没有登录/代次校验；`PluginRestore.ets:173–180` await 单项后继续下一项。已发队列由 Host 独立执行，退出不撤单；最终 progress/lastSync 仍回填。没有把安装器自身磁盘行为扩大成跨账号结论。
- 其他状态写者：`setEnabled:288–298` 只是开关及 lastSync；`adoptLogin:220–235` 清资料、置“待开启”，不淘汰旧任务；`setCloudService:264–267` 不校验身份；`refreshStat:481–488` 可在退出后写 kindStat。bridge 每次 `encodeCloudState`（`SyncState.ets:60–95`）读取当前值，不按 signedIn 屏蔽/纠正 cloudOk、lastSync、busy、progress。
- 两壳 task 完成包装 entry `4513–4533`、phone `4121–4132` 只按返回字符串显示错误 toast，不校验任务代次。原生面板 pull/upload 完成（`511–525,628–647`）会重新 refresh 并设置完成 notice，插件安装完成（`586–598`）也设置安装结果，没有退出后丢弃回调的逻辑。
- busy 是新任务互斥而非退出保护：engine.running 在退出时保持 true，旧上传/拉取结束前仍挡新上传/拉取；这可避免把“旧任务 finally 清掉新上传锁”当成已证明事故。插件 restore 不设 engine.running 是另一个事实，但本报告不另扩展并发缺陷。

### 核心账号退出是否提供兜底

归档 `node_modules/@deepseek-ai/dsh-client-ui-settings-account/lib/client.js:2`，列 175710 附近实际调用 `ctx.remote.account.signOut(...)`。相应 `dsh-deepseek-account/lib/index.js:1320–1340` 取消该服务自己的 sign-in attempt、删除 credentials grant、后台 revoke、emit `deepseek-account/signed-out`。`1346–1347` 的 running-account-task 查询也针对 agents 的账号路由任务。它没有调用 ArkTS SyncEngine、云桥或 RDB 同步；因此它的取消/重试机制不能作为 E-04 的反证。它也不是本轮华为账号退出入口。

### 必须保留的反证与影响收窄

- signOut 不会让旧任务重新写 unionId/enabled，旧上传完成后仍是 signedIn=false/enabled=false；不是“自动重新登录”。
- 网页 `lib/client.js:527–568,618,689–698` 依据 signedIn 隐藏同步与内容区。因此退出后立即在网页看到“已连接”并非必然；原生同样在 `CloudSyncSettings.ets:722–775` 隐藏登录后的账号/同步区。完成 notice 仍可更新，桥状态可观察到不一致。
- 若退出后**重新登录且旧任务尚未结束**，adoptLogin 的“待开启”可被旧任务后续结果覆盖，此时网页重新显示同步区后能读到旧结果；若旧任务先结束再登录，adoptLogin 会再次清云状态，但未清 lastSync。显示时序需要分开说明。
- 任务在退出前已完成、后续 await 永不恢复、或进程被结束，都不构成这里的完成态回填触发；成功恢复执行的 await 才形成例子。失败路径可形成异常文案回填，不要求真实云成功。
- 应用退出语义明确为本地清内存（engine `270–281`）；允许已提交任务自然结束可以是设计选择。但当前没有标识“退出前任务”，状态字段刚清后又被无条件写回，且 actions 注释声称的下一次身份检查不存在，这才是本项确认的状态隔离缺口。不能仅因未调用系统 cancel 就断言 bug。
- 没有实际系统账号 A/B 切换、平台数据库账号归属、Asset 传输目标证据，**跨账号泄漏判定为证据不足，不作指控**。

### 触发与影响

上传/拉取/插件安装在 await 期间，从网页或原生面板退出，随后旧任务恢复执行。旧进度、最近同步结果与连接/异常状态可重新进入共享状态；应用级后续步骤未被取消。可影响退出后 notice、重登录后的最近同步与云服务显示，以及用户对在途任务是否停止的理解。

**判定：确实存在，限于旧任务继续与状态污染。** 纯内存 deferred Promise 例子在清空状态后释放旧任务，最终为 `{signedIn:false,enabled:false,lastSync:"completed",cloudOk:true,running:false}`。这是状态时序反例，不证明云端账号隔离失效。

## 官方 API 与剩余边界

实际尝试 `devecocli docs search relationalStore cloudSync autoSync --limit 3`，失败原因是本机 `better-sqlite3` 缺少可加载绑定。未取得 documentId，因此无法按真实检索 ID 执行 docs read；没有猜 ID、伪造 read 或用源码注释替代官方保证。

因此下列内容均不作为确认事实：系统是否取消已在途的 cloudSync、autoSync 在退出应用内账号后的真实行为、系统华为账号切换的隔离/重绑定时序、当前 AGC 服务开通与云端实际记录、设备私有 profile 当前内容。确认项依靠应用自身的字符串/集合/await 控制流，不依赖这些尚未验证的官方语义。

本轮完整交付为三个候选的重新定性、调用链、正反证与触发影响。本报告不是构建、安装、真机恢复验收，也没有修复代码。

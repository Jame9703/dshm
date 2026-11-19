# Runtime/Core 候选反证复核

## 范围与结论

本次独立判断 B-01、C-01、C-R2、F-R1，不沿用 review.md 的确认等级。路径均相对项目根；行号对应本次读取的源码。只读源码、实际依赖与当前归档，未读历史 docs、memory、旧 acceptance；AGENTS 产品口径与源码注释不作为正确性裁判。读取了本轮 review.md、verification.md，仅作候选定位与已有缺口索引。

| 候选 | 本次判断 | 已闭合的事实 | 不成立或尚未证实的扩大结论 |
|---|---|---|---|
| B-01 | **确实存在** | 主路径失败申请留下 refs，caller 却放弃 held；之后成功的单次常规释放不能配平 | 未证明系统通知残留、耗电或冻结的实际表现；PC 常驻申请本身不是缺陷 |
| C-01 | **条件性存在** | QMP data/destroy/close 可先于 worker exit 完成 stop，取消 8 秒等待，Host 随后进入退出链 | 未证明当前 VM 慢退出、quit 丢失、qcow2 损坏或用户数据损坏 |
| C-R2 | **确实存在** | 已注册的卸载统计回调引用不可见的块内 let，执行时 ReferenceError | Cordis 逐项捕获；不能据此认定宿主崩溃、其他清理不执行或 VM 泄漏 |
| F-R1 | **条件性存在** | 大小 stamp 不是内容身份；缺 stamp 时只凭旧树 builtAt 可跳过并认证当前大小；同版重打未被上游不可变性守卫排除 | 无真实旧/新同长容器对或已安装树，不能说当前发布已经更新失败 |

## B-01：失败申请与引用拥有权失配

### 生产与消费

- `platform/src/main/ets/notify/KeepAlive.ets:347-385`：acquire/acquireTaskKeeping 汇合到 acquireWithMode；userStopped 在递增前拒绝，否则先 refs++。active 或 context 缺失直接返回；requestMode 最终失败也不回退 refs。TASK_KEEPING 到 DATA_TRANSFER 的内部 fallback 只递增一次，不能把内部两次 API 申请计为两个引用。
- `KeepAlive.ets:388-426`：wantAgent 获取及 startBackgroundRunning 都在 try 内，异常转为 active=false/返回 false。这里没有抛给 caller 后自动退款的保护。
- `KeepAlive.ets:429-459`：release 最多减一；refs 仍正立即返回，不调用 stopBackgroundRunning；forceRelease 才先清零。
- phone 主调用 `phone/src/main/ets/entryability/EntryAbility.ets:1734-1795`：running=true、后台、held=false、用户未停且距上次至少 30 秒才申请。1779-1782 的 false 分支只清 held、不 release；catch 亦只清 held。
- phone 重试不是假设中的按钮：`EntryAbility.ets:1689-1700` 建立 1500ms card-state 轮询，1771-1775 的 30 秒退避允许失败后再申请。Host 生产 `session.state='running'` 见 `hostcore/app/main.js:6048-6064`，写入 card-state 的 payload 与原子落位见 `5731-5737`；phone `1715-1727` 消费相同字段。
- phone 回前台 `1462-1485` 清后台意图、停轮询，再走 `1799-1809`：推进 generation，仅 held=true 才减一。无常规 forceRelease。
- entry 手持主调用 `entry/src/main/ets/entryability/EntryAbility.ets:2012-2089` 同样失败清 held、不 release；busy 来源为 SessionHub/workload/schedules，而非仅注释。其申请入口为后台 `2175-2184` 及熄屏 `2145-2166`，并非 phone 那种后台 30 秒轮询。多次生命周期或熄屏事件足以再次进入；不能给 entry 套用 phone 固定重试节拍。
- entry 前台 `1697-1723`、亮屏前台 `2157-2161` 汇入 `2093-2108` 的单次释放。

### 所有拥有权与恢复反证

本轮定位到的生产 acquire 调用共**五处**：entry `1423`（非手持主窗常驻）、`2003`（非手持熄屏一次补试）、`2070`（手持）；phone `1778`（主轮询）、`1879`（onBackground 同步异常备用）。KeepAlive 两个公开方法定义不算 caller，未用注释里的 acquire 文本计数。

release 调用为 entry `2080`（晚到成功）、`2104`（held 释放）、`2840`（完成通知）；phone `1786`（晚到成功）、`1805`（held 释放）、`1882`（备用失败/作废回收）。forceRelease 仅 entry `1228-1231` 与 phone `1154-1157` 主窗 onDestroy。实例分别位于 entry `520`、phone `478`，不是另外一个隐藏全局计数器；platform 导出见 `platform/src/main/ets/Index.ets:21-23`。

- generation 比较只在 active=true 后的分支执行（phone `1779-1789`、entry `2071-2084`），不能追回已返回 false 的引用。release 在 acquire await 完成前已经能减到引用，源码注释所谓“尚未 refs++”不符合 `KeepAlive.ets:370-375` 的实际顺序；本项因果不依赖该注释。
- phone 备用 `1879-1886` 的 false 分支确实 release，是反例而非主路径补偿；同步 try/catch 不会捕获已被 requestMode 吞掉的 API 失败。
- `KeepAlive.ets:141-168` 系统取消只清 active/记原因，refs 不清；`180-198,333-339` 前台/后台意图与 userStopped 清理也不改 refs。续期 `222-235`、屏幕校准 `251-330` 明确不增减 refs，不能偿还失败引用。
- noteBackground(false) 会清退避，故不能声称“回前台仍必然自动续期”。但它不停止已 active 的长时任务；refs>0 的 release 仍提前返回。
- entry 完成通知 `2831-2841` 的无 held 检查 release 可能抵消一个或多个残余引用，但任务尚未完成时回前台无需经过该路径，不能作为配平保证。
- 主窗销毁 forceRelease 可清掉既有偏高计数，进程重启亦重建初始状态。它不是普通前台兜底，也不是对晚到系统 API 的事务取消保证。
- 非手持 entry 常驻与补试可以合法持有多个引用；不能仅以 PC 前台 active=true 判定本缺陷。

### 可达条件与影响

取无并发申请、无系统取消、任务始终 running 的 phone 序列即可闭合：失败、等待退避、失败、等待退避、成功、回前台。refs 依次 1/2/3/2，最后 held=false、active=true。entry 可通过分离的后台周期构造同类序列。这个结论是应用内部所有权和 stop 调用遗漏，不要求先证明某种具体系统错误码会发生。

纯内存同构演示输出 `refs:2, active:true, held:false`；没有调用系统 API。官方检索 `devecocli docs search continuousTaskCancel startBackgroundRunning stopBackgroundRunning` 因 better-sqlite3 本机绑定缺失失败，无 documentId 可 read。系统是否实际留下通知、自动取消、耗电等保持证据缺口。

## C-01：QMP 通道完成不等于 worker 退出

### 实际退出链

- `hostcore/plugins/dshm-vm-bash/lib/index.js:244-267` 在 enabled 判定前注册 global shutdown Set，并另注册删除 hook 的 effect；`428-430` shutdown 返回 stop Promise。
- `lib/vm.js:918-936` 真正创建 worker，`949-990` 独立处理 returned/error/exit；只有 exit 回调将 state.worker=null。`lib/vm-worker.cjs:94-118` 经 koffi 同步调用 qemu_system_entry，返回后发送 returned；没有额外 JS finally 刷盘完成屏障或另一条 stop 等待。
- `lib/vm.js:1523-1549` 拍下 worker、关闭 QGA session，建立 8000ms 有引用定时器与 worker.once('exit', finish)。QGA close 不是 QMP quit、也不是 worker join。
- `1552-1568` connect 写 capabilities 与 quit；**任意 data 都 destroy QMP**，close/end 都直接 finish。finish 只看 done，清定时器并 resolve，不检查 state.worker 或 exit。error 虽写“worker 非空继续等”，随后 close 仍可完成；同步 createConnection 异常也直接完成。
- QEMU 官方协议 `https://www.qemu.org/docs/master/interop/qmp-spec.html` 的 Server Greeting 规定连接即发 greeting，Capabilities Negotiation 说明能力协商阶段。故 data 不必是 quit 回复，甚至不是命令成功；不能把任意 data 认定为退出证明。本次读取的是 QEMU 当前官方规范，不是随包二进制版本逐行实现证明。
- `hostcore/app/main.js:8503-8509,8533-8587` 对 requestStop 幂等，取 hook 快照、调用、allSettled 或 10 秒 guard 后 finishHostStop；已完成 hook 的 guard 会清掉，所以 10 秒不是提前完成后的额外等待。
- `main.js:8544-8559` 调 result.shutdown.shutdown(0)，不 await，再排 1500ms 的 unref timer；timer 先置 ALLOW_EXIT=true 再 process.exit。`225-245` 的退出拦截因此**不保护停止路径**。
- 实际依赖 `dist/core/work/dsh-core-0.2.2-rc.2+dshm.1/node_modules/@deepseek-ai/dsh/lib/profile-boot-QhDEDXsF.js:22-71,265-299` 的 process shutdown 等待 root fiber dispose/代理释放，5 秒兜底；没有第二次 VM stop/join。它默认调用的是当前 process.exit，并非捕获的 realExit。root dispose 会删除插件 hook，并不会补发 stop。
- 文件停止入口 `main.js:8590-8608`、应用重启 `8633-8643`、SIGTERM `8889` 可进入 requestStop。ArkTS `hostruntime/src/main/ets/runtime/DshHost.ets:757-786` 写 host-stop-request 后等 port.stop；`NodeRuntime.ets:541-560` 只轮询原生 Host 是否结束，不阻止 Host 自己提前 exit。上游 profile-boot 另有 SIGTERM/SIGINT listener，SIGTERM 下 dispose 与 requestStop 的并发顺序不能简化为唯一串行链。

### 正反证与影响收窄

确实存在“QMP greeting/error/连接关闭 → stop settle，但 worker 尚未退出”的源码窗口；纯内存事件回调演示得到 finished=true/workerExited=false。运行中的 worker 默认有引用，主线程自然排空不等于 worker 已退出；1500ms 显式退出路径仍可终止这个等待。

但不确认镜像损坏：quit 已在 connect 写出，QEMU 可以在这 1500ms 内正常结束；写出不等于 quit 必被丢弃，close 也可以由真正退出导致。若没有 worker/session，stop 立即完成本来正确；8 秒 VM 与 10 秒 Host 上限也本来是有界停止策略。没有执行真实 QMP、worker、guest 或磁盘测试，没有随包 QEMU C 实现及慢退出证据，无法判断本设备上的实际窗口持续时间、刷盘状态。QMP quit 与 guest OS 完整关机也不能混为一谈。

`tools/check-host-vm-graceful-stop.mjs:35-59` 只要求存在 worker exit listener、等待注册表和超时，且把 close→finish 明列为通过条件；不是“所有正常 resolve 均已 worker exit”的证明。本次未运行该脚本。

## C-R2：cleanup 中的块作用域引用

- `hostcore/plugins/dshm-vm-bash/lib/index.js:269-272` 的 taken/delegated 在 apply 函数作用域；`312-314` 的 takenTerminal/delegatedTerminal 则只在 if 块。`413-419` 的 effect 回调定义于该块外，在模板表达式求值时就找不到这两个绑定；不会进入 log 函数内部 try/catch（`69-75`）。没有同名外层声明。
- 注册条件为 enabled=true、runtime 有 spawn、runtime 尚未 WRAPPED（`255-269`），且 apply 确实执行到末尾。terminalTakeoverEnabled 为真或假均不改变块外不可见性；VM 是否真正已启动、计数是否非零不是条件。
- profile `hostcore/profile/ondevice/cordis.patch.yml:777-779` 装配插件。卸载可来自 root shutdown：上述实际 profile-boot `272-285` 调 root fiber.dispose；Cordis effect `463-478,533-542` 注册返回的清理，`693-706` _unload 逐个 async dispose 并 catch/logger.error，Promise.all 启动其他清理。
- 删除 shutdown hook (`index.js:254`) 与清预热 timer (`410`) 是独立 effect。出错 effect 仅统计 log，没有位于其后本应执行的实际资源释放语句；stop 不在其中，不能把这个 ReferenceError 当作 VM stop 缺失根因。
- 正常 logger.error 不抛的依赖路径中，该异常被隔离；理论上日志系统自己再抛不是本项已有证据。WRAPPED/方法恢复问题与 hook 卸载策略不在这个变量错误中另算影响。

纯内存词法闭包演示对 terminalTakeover=true/false 都得到 ReferenceError；未导入或执行插件 apply。结论仅为卸载统计日志丢失及错误记录，可达于插件卸载/重载或正常 root dispose，不是每次新建终端触发。

## F-R1：同版更新身份与 stamp

### 命名、生产和上游约束

- `hostcore/core-recipe.json:2-6` 当前 coreVersion 为 `0.2.2-rc.2+dshm.1`。`hostruntime/src/main/ets/core/Naming.ets:14-16,25-67` 只将版本作为安全目录名/容器名的一部分，不含内容 hash。
- `tools/pack-core.mjs:106,1354-1391,5327-5351` 由该标签建立树名，覆盖拷贝自带插件，生成树信息后 pack。`4944-4945` 用 openSync(zipPath,'w')，`5047-5052` 同名输出会重写；没有“同一 coreVersion 已产出不同字节则拒绝”的旧摘要比较。
- `pack-core.mjs:4822-4859` 写 coreVersion、builtAt、插件清单，不写容器 hash；builtAt 来自 reproducibleStamp，不是对内容计算的身份。固定时间只消除时间戳噪声，不能保证修改后内容不变。
- `5109-5168` 清单记录本次容器 bytes/sha256 并覆盖同标签 manifest；校验的是上游版本相符，不是历次标签不可变。`5074-5102,5372-5389` 同名 resfile 允许覆盖，回读 hash 与**本次** manifest 比较。
- `tools/check-resfile-core-zip.mjs:49-80` 只比配方名与当前 dist/core、resfile 的 hash/size；两者同时被同版新产物替换时不违反判据。`tools/check-core-openharmony-patches.mjs:728-735` 元数据标签校验同理。`tools/build-agc.mjs:406-409` 检查共享 HSP 一份核心且名含版本；最终 app hash `463-464` 也不是旧安装树身份。
- `tools/check-bundled-core-rollback.mjs:86-136` 约束 stage/move/commit/rollback 的顺序，未约束跳过分支。未运行构建、门禁或打包器。源码中“改核心必升标签”之注释不当作已实施的强制保护；本次所追生产路径未发现跨发布同标签摘要锁。

### 端侧消费者与可达分支

- `hostruntime/src/main/ets/core/BundledCore.ets:37-65` stamp 只写 String(size) 并回读，无摘要。`119-161,190-193` 已有同目录版本且 srcSize>0、stamp 文本相同即 continue；不读取新树 manifest、不进入 stage。
- `BundledCore.ets:198-222` stamp 不存在或读取异常时，旧树 info 文件可访问且 readTreeInfo.builtAt 非空即补写当前容器大小并跳过。实际代码**没有比较新旧 builtAt，也没有在这里比较 coreVersion 内容**。所以缺 stamp 时，新容器即使大小不同也可被跳过；之后补写的大小会进一步让下一次命中第一分支。
- `CoreStore.ets:262-295` readTreeInfo 宽容解析字段，`230-252` listInstalled 只看安全目录名/目录；`302-313` records.sha256 恒为空。`Types.ets:20-27` 的 sha256 字段不是被消费的 hash 校验器。
- `DshHost.ets:815-831` 原样调用，无上游 hash 验证。实际入口为 entry `EntryAbility.ets:1016`、phone `EntryAbility.ets:942-954`、entry 核心页 `pages/Index.ets:3609-3616`、superagent `superagent/SuperagentAbility.ets:126-140`；均非强制重装参数。设置页“安装内置核心”也经过同一 skip。
- `BundledCore.ets:338-421` 的 stage/挪旧/commit/回滚保护确实存在；`CoreStore.ets:341-395,445-474` 解包与哨兵检查只在未 skip 后运行，不能修正错误命中。它能保旧，故此项不是“坏容器必删旧树”。

### 判断边界

条件为旧版本目录存在且新发布仍使用同标签，并满足大小 stamp 碰撞，或 stamp 缺失而旧 info.builtAt 有值。生产器允许同版重打覆盖，不能以命名纪律反证不可达。跨版本目录不存在、或 stamp 已存在且尺寸不同，都走真正安装，是明确反例；首次安装也不受影响。

纯内存谓词演示为：同尺寸换内容 skip=true；有 stamp 且改尺寸 skip=false；无 stamp/旧 builtAt 非空且改尺寸 skip=true。没有制造磁盘资源对。当前归档能证明当前字节，不证明任何用户已有旧树或历史发布碰撞，因此保持条件性存在，而非已发生更新事故。

## 归档核对与执行边界

只读 `hostruntime/src/main/resources/resfile/dsh-core-0.2.2-rc.2+dshm.1-openharmony-arm64.zip`，标准库 ZipFile(...,'r')/read 解压在内存；没有 extract/落盘。当前文件大小 201771842 字节，内置 tree info coreVersion=`0.2.2-rc.2+dshm.1`、builtAt=`2026-11-12T14:47:17.980Z`。resfile 根没有随行 manifest.json。

| 归档成员（省略顶层 dsh-core-标签/） | SHA-256 | 对照 |
|---|---|---|
| node_modules/@deepseek-ai/dshm-vm-bash/lib/index.js | 155c237f26314153ce3371a2d9b02887137bb3497551602d525ab1fc5979e4ed | 源码及当前 work 逐字一致 |
| node_modules/@deepseek-ai/dshm-vm-bash/lib/vm.js | f20dafadef783a591d302fd97aab697b7c1cc4cb7abbdf4a06f9140ab6df445f | 源码及当前 work 逐字一致 |
| node_modules/@deepseek-ai/dshm-vm-bash/lib/vm-worker.cjs | 41c51483b0212bb33eedab665c0477447233375a40d697676ef7c884b299e64a | 源码及当前 work 逐字一致 |
| node_modules/@deepseek-ai/cordis/lib/index.js | 627409afa06a265f7253200d3bc4648e88805c39fd3768568eb9b9518a31fe8f | 当前 work 逐字一致；package 版本 4.1.0 |
| node_modules/@deepseek-ai/dsh/lib/profile-boot-QhDEDXsF.js | 75985ad5807803dee1603b47e348498eb86c2d9be8d15b74c5cf97857085ff54 | 当前 work 逐字一致 |
| profiles/ondevice/cordis.patch.yml | ee28f1aa4e1c7b71681544749f41ffae83542efba605b4f5afef9eb00b478518 | profile 源码逐字一致 |

另外 `hostruntime/src/main/resources/resfile/resources/app/main.js` 与 `hostcore/app/main.js` 逐字一致。故上文 VM、Cordis、Host 关键路径不是仅开发源码中的未入包片段；这不是 HSP/APP 构建物或已安装设备私有树的核验。

本次仅主动写本文件。未执行代码/配置/资源修改、git 操作、build/deploy/device、生产入口导入、业务网络或有副作用测试；未调用验证代理。纯内存 Node 演示只用字面状态/函数与 stdout，不是实际 ArkTS API 或事件调度复现。Python -B 只读归档与对照文件，不写 pyc。工具对长输出自动保存日志不代表本次主动落盘解包；没有对所有工具内部隐式写入作绝对保证。

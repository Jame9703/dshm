# 当前源码审查覆盖

## 授权与基准（T001）

- 唯一写入目录：`spec/source-functional-review/`；仅报告及 tasks 勾选。不写 feature.json、docs、memory、acceptance 或产品文件。
- 不读历史审查、HANDOFF、memory、旧 acceptance；不打开签名、凭据及 build-profile 内容。不运行构建、部署、设备、修复、提交、重置。
- 用户 PC 当前正常是外部输入，并非全部 PC 路径证明；普通平板、手机、折叠屏无本轮真机结论。
- 审查基准为当前工作区实物，不还原既有差异；源码注释不是判据。依赖工作树不自动等同随包归档。
- 六域入口以本轮 plan.md 的 A–F 为导航；先追入口和消费者，再判断可达性。没有子代理派生工具，改由同一审查者分域串行读取；下一阶段独立代理仍须重新验证。
- 执行状态、深读范围、未覆盖项及检查记录将在 T010 收口；本表不代表全仓无遗漏。

## 覆盖矩阵（T010）

“深读”指报告列出的具体段已读；大文件仅这些段深入，其他部分仍未审。表中依赖前缀 `CORE/` = `dist/core/work/dsh-core-0.2.2-rc.2+dshm.1/`。

| 功能域 | 已深入的入口/实现 | 仅定位或抽样 | 明确未覆盖 |
|---|---|---|---|
| A形态/侧栏/输入/返回 | DeviceFacts、WindowChrome、InputDevices全文；两WebApp形态桥和分类脚本；phone返回5565–5639及Web区域变化 | CORE/sidebar压缩client定位；两壳生命周期/桥methodList定位 | 完整DOM/CSS、键盘焦点/IME、触控、拖拽、输入设备消费者闭环、折叠分屏、无障碍 |
| B启动/会话/后台/通知 | 两EntryAbility onCreate及相关后台片段；phone915–1138/1689–1878/1462–1485；entry2012–2116；DshHost全文；NodeRuntime250–649；KeepAlive1–450；NotificationCenter70–369/400–455；main5677–5777/5913–6129；CORE/session-controller取消与follow | EntryAbility其余大段；session-controller装饰器和其他端点未全文；appstate SessionHub只定位调用 | 发送/审批/问答完整链、mux网络重连/队列、多会话并行状态、迁移全文、通知点击全链 |
| C终端/VM | RuntimePort全文；VM index75–431/terminal全文/handle25–330/qga100–629；vm1370–1635；CORE/terminal-controller1150–1319/1380–1600；工作树VM对应段 | C++dshhost400–609；VM启动前半及资产路径仅部分定位 | 真PTY后端、QEMU native/9p、完整stage/provision、guest rootfs、设备运行/取消时序 |
| D文件/工作区/插件 | FilePicker20–446，FolderGrants100–248，FilePreview全文；两壳目录桥片段；CORE/workspaceFiles30–274/470–624；installer1–1088/1110–1194/1300–1729；tar70–260；market290–489/profile-pnpm110–479；main队列8830–8887 | install-command只定位；workspace registry未深读；installer输出截断未显示区不算已读 | fs-local全部读写删、卸载全文、市场远端/网络、预览下载全链、安装依赖闭包 |
| E同步 | SyncEngine、ImportRunner、Planner、Actions全文；Store65–374/Upload100–275/Manifest30–220/Restore35–236/State70–141；HuaweiCloud170–318；SessionSyncScope140–299；CloudSyncSettings390–855；phone桥3967–4162；cloud client指定动作/恢复段 | entry同步桥仅定位；cloud插件ScopeList未深读 | RDB系统云隔离、完整合并/冲突、账号API前半、附件技能正式导入、云配置/真实同步 |
| F核心 | recipe全文、BundledCore全文、CoreStore190–259/329–545、Types125–196、main启动/关闭指定段、pack1360–1417、place-host20–117；资源installer关键区、工作树VM关键区 | dshcompat Endpoints1–240样本及文件名；pack各patch函数仅定位 | zip归档逐字一致、装配完整闭包、所有补丁及223端点全比对、真实已安装树、构建/签名配置 |

具体行号及反证见 `domain-a-ui.md` 至 `domain-f-core.md`。读到源码内历史注释不视为历史证据；所有结论均指向实际执行代码。没有访问docs/HANDOFF、memory、旧acceptance或旧审查。

## 检查执行账

| 项目 | 执行情况 | 依据/结果及边界 |
|---|---|---|
| Read/Grep/Glob | 已执行 | 仅读取当前源码/本轮文档/实际依赖，未打开用户数据或凭据。长行和截断输出不算完整深读。 |
| `pwd && printenv HOME` | 已执行 | 仅stdout，动态解析CONFIG_ROOT为`~/.local/share/deveco/`。 |
| `devecocli docs search fileIo OpenMode TRUNC cloudSync ProgressDetails --format json` | 已尝试 | 官方只读文档查询，不构建/设备；CLI因SQLite原生绑定缺失未能检索，无documentId可read，不安装依赖或修工具。没有可引用官方API结果。 |
| 现有门禁/测试/lint | 未执行 | 没有完成其全部导入依赖副作用证明，且不以旧绿灯替代审查。pack/place脚本已看到mkdir/copy/write，明确拒绝执行。 |
| 内存最小复现 | 未执行 | 静态调用链已足以提出候选；不导入会写文件/启动VM的previewScript、createVmHandle或业务模块。独立复核可另行审核纯内存模拟。 |
| build/deploy/UI/设备/联网同步 | 禁止，未执行 | 阶段4/5只读例外，没有应用启动、socket/VM/网络业务执行。 |

## 允许写入且本轮实际写入

仅coverage.md、review.md、domain-a-ui.md、domain-b-lifecycle.md、domain-c-terminal.md、domain-d-files-plugins.md、domain-e-sync.md、domain-f-core.md及tasks.md。spec.md/plan.md未改；verification.md未创建；其他目录不主动写入。未运行git提交/重置/清理；不将既有工作区差异归为本轮。

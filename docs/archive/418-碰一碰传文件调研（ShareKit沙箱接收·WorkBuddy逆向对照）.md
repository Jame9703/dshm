# 418-碰一碰传文件调研（ShareKit沙箱接收·WorkBuddy逆向对照）

> 状态：**已落地（PC 档，2026-11-16）**——`KnockShareReceiver` + `WebApp.ets` 接线完成，构建与 113 条门禁全绿。真机两轮实测（Beta 1010017 调试包侧载）：**注册成功**（diag-knock：canIUse=true / windowId=454 / on ok）但 **dataReceive 一次未触发**——断点锁定在「系统投递」。已按判别树做两项排除改动（注册后移到页面就绪 + 窗口身份三件套对比，§5.2），复测若仍无投递即指向侧载包资格（签名，§6）。范围裁定（用户）：仅 PC 档接收、普通平板不启用、手机端是系统发送方无需代码。
> 需求：手机（HarmonyOS）选文件 → 轻碰 DSHM 所在 PC/2in1 屏幕 → 文件进 dsh 会话输入框，不自动发送（对标 WorkBuddy 鸿蒙版）。
>
> **2026-11-17 更正**：§6 的「签名资格」结论**证据不足**（本机 `diag-knock` 时间轴与 `Huawei Share/` 落盘对齐后，没有一次能确认"接收方在线却被跳过"）；能力表、注册寿命、窗口覆盖三处缺口的现场审计与修复方案见 [`421-碰一碰传文件（DSHM端实现与修复方案）.md`](421-碰一碰传文件（DSHM端实现与修复方案）.md)。

## 1. 一句话结论

碰一碰传文件是鸿蒙 Share Kit 的系统能力（`harmonyShare` 沙箱接收 `dataReceive`），**零新增 manifest 权限、权限面 18/9 不动**；WorkBuddy 的实现为「ArkTS 注册接收 → 桥接 → 前端注入」三层；本仓是原生 ArkTS 壳，比 WorkBuddy 的 Electron 形态**少一层桥**，集成点已定位；**前端注入扩展点已查明：dsh 官方文件 intake 可被合成事件驱动，无需改上游**；剩余未决均为真机待验项（§6）。

## 2. 权限结论（权威核验）

- `@hms.collaboration.harmonyShare.d.ts` 全文 591 行**零 `@permission` 注解**（本机 SDK 实读，路径见 §7）——接收侧不需要任何 manifest 权限。
- 授权机制在 API 层闭环：`ReceivableTarget.receive()` 官方注释明确——Share Kit 在传输开始前对指定目录**取授权、传输完成后自动回收**；文件由系统直接写入应用给的沙箱目录，应用不经手任何用户授权。
- 排除项：`ServiceInteraction` 碰一碰连接（需 `KNOCK_COLLABORATION`）是另一个特性（近场服务协作），与本需求无关；`docs/172` 归入「排除」。
- 前置条件（非权限）：`canIUse('SystemCapability.Collaboration.HarmonyShare')`；接收设备为 PC/2in1（d.ts 原文 "triggered when a phone lightly touches a PC/2-in-1 device screen"）；两端亮屏解锁、开启华为分享、登录同一华为账号。

## 3. SDK API 核验（本机 d.ts 逐条）

版本门槛：沙箱接收 `dataReceive` 自 6.0.0(20) 起；轻碰坐标 26.0.0 起。本仓 compatible 6.1.0(23) / target 26.0.0：**沙箱接收在最低版本即满足；坐标 API 编译可用，运行时需设备在 API 26**。

API 链（签名与 WorkBuddy 文档一致，已逐条核验）：

| 环节 | API | 要点 |
|---|---|---|
| 注册 | `harmonyShare.on('dataReceive', RecvCapabilityRegistry, Callback<ReceivableTarget>)` | **仅支持文件数据**；文本/链接走系统原有接收逻辑（不进此回调） |
| 能力声明 | `RecvCapabilityRegistry { windowId, capabilities: RecvCapability[] }`；`RecvCapability { utd, maxSupportedCount }` | windowId 绑定参与轻碰识别的窗口 |
| 接收 | `ReceivableTarget.receive(receiveUri, ReceiveCallback): Promise<void>` | receiveUri 必须是**已存在**目录，官方建议空目录（安全）；系统传输前授权、完成后自动回收 |
| 数据回调 | `ReceiveCallback.onDataReceived(systemShare.SharedData)`、`onResult?: Callback<ShareResultCode>` | `SharedData.getRecords(): Array<SharedRecord>` |
| 记录 | `SharedRecord { utd, content?, uri?, title?, ... }` | ≤500 条 / IPC 200KB 上限——文件走 `uri`（落盘路径），不走 `content` |
| 结果码 | `ShareResultCode { SHARE_SUCCESS=0, SEND_FAILED=1, CANCEL_BY_SENDER=2, CANCEL_BY_RECEIVER=3 }` | 只反映本端接收；「对方是否收到」仅系统通知，应用拿不到 |
| 拒收 | `ReceivableTarget.reject(ReceivableErrorCode)` | `NO_RECEIVABLE_ERROR = 1` |
| 坐标（API 26） | `ReceivableTarget.getInfo().coordinate.{screenX,screenY}` | 默认 -1；「碰哪插哪」需设备在 API 26 |

勘误（对 WorkBuddy 文档）：`SharedRecord` 的 `utd`/`content` 是**属性**而非 `getUtd()`/`getContent()` 方法；其文档示例中的 `getContent?.()` 调法在 d.ts 无据。

## 4. WorkBuddy 逆向逻辑（其自产文档 + 核验状态）

WorkBuddy Desktop 5.6.4（Electron on OpenHarmony）三层结构：

| 层 | 载体 | 职责 |
|---|---|---|
| ① ArkTS `ShareKitAdapter` | 静态类，绑进运行时 | `on('dataReceive')` 注册（windowId + capabilities）；`receive(filesDir)` 落盘；记录规整为 `{filePath, fileName}` 入静态队列 |
| ② Electron 主进程 `HarmonyShareBridge` | 7 个 IPC handler + `systemPreferences.callArkTSFunction` | 渲染层每 500ms 轮询 `CheckReceivedFiles`（返回双重编码 JSON：外层数组、内层各为一条 JSON 字符串） |
| ③ 渲染层 `useAutoKnockReceive` | React hook | 构造 `resource_link` content block，`wb.conversations.prepareInput({submitMode:'none'})` 注入输入框，**不自动发送** |

- 7 个 IPC 通道：knockReceive start/stop/check、knockShare start/stop、sharePanel show、diag。
- 生命周期：仅会话页激活时启动接收、离开即停；注册失败指数退避重试（1s/2s/4s/8s，至多 5 次）。
- 核验状态：API 签名、版本、零权限**已核验吻合**；「必须正式签名才能拉起碰一碰目标（调试签名碰了没反应）」为该文档经验之说，d.ts 无此约束，属设备侧行为，**未核验**。

## 5. 本仓落地映射

**架构差异（关键）**：WorkBuddy 文档的目标项目是「Electron 37 版 dsh-desktop-hos」（web_engine / collect-runtime.mjs / runtime-overlays），**不是本仓**——本仓为原生 ArkTS 壳（entry / phone / hostruntime 模块 + hostcore 核心容器 + `WebApp.ets` ArkWeb），仓内不存在上述 Electron 目录。因此该文档的第二层（Electron 桥 + 轮询）在本仓**不存在也不需要**：ArkTS 就是本仓自己的代码。

| WorkBuddy 层 | 本仓对应 | 落点 |
|---|---|---|
| ① ArkTS ShareKitAdapter | entry 模块新增碰一碰接收桥 | 并入 `WebApp.ets` 既有 `__DSHM_BRIDGES__` 聚合注册（`javaScriptProxy` 单对象约束，多桥已聚合为先例）；`receive` 用 filesDir 下**每次新建的空目录** |
| ② Electron 主进程轮询 | 不需要 | ArkTS 在 `onDataReceived` 后直接经 `controller.runJavaScript` 推事件到 web（同 `buildOpenSessionScript` / `KEYBOARD_*` 既有推送模式），无轮询 |
| ③ 渲染层注入 | dsh web UI 侧扩展点 | **已查明可落地（无需改上游 dsh）**，方案见 §5.1 |

### 5.1 前端注入扩展点（核心树源码查明）

对核心树（`dsh-core-0.2.2-rc.3`）`dsh-client-ui-conversation` 的源码核验结论：

- **官方编程式入口存在**：输入 facade 有 `addFiles(references, ids)` / `addAttachments(ids)` / `paste(text)` / `submit(mode)` 等方法（`src/client/input/facade.ts`），但 facade 实例归 React 会话视图私有，**无全局暴露**——外部拿不到直接调用。
- **页面级 intake 是 DOM 事件驱动且无合成门槛**：document 级 `paste` 监听（`src/client/input/file-intake.ts`）从 `clipboardData.items` 取 `File`，按「最近聚焦的 composer，否则主会话 composer」路由，调 `target.add(files)` 进官方管线（上传 → 附件 chip → 草稿，**不自动发送**）；document 级 `drop` 监听（`dsh-client-ui-attachment/src/client/drop-events.ts`）同理。两处均**不校验 `isTrusted`**——注入脚本可合成 `ClipboardEvent('paste')`（init 携 `clipboardData`，规范允许）驱动官方 intake，零上游改动。
- **注入载体现成**：既有注入脚本机制（`OPEN_LINK_SHIM_JS` 等先例）或插件 client 半边（`window.__ModuleLoader__.load` 工厂内可 `require` 客户端模块、走 `globalThis.__DSHM_BRIDGES__` 调原生——`dshm-office-system-preview` 先例）。
- **文件字节进页面的三通道**：小文件走 `runJavaScript` 推 base64 → `new File([bytes], name)`（原生听写 base64 先例）；大文件走资源接管——shell 以 `onInterceptRequest` 把 filesDir 暂存文件以同源路径供 `fetch`（外链接管/`onLoadIntercept` 先例，docs/275）；兜底走系统剪贴板（听写 `copyText` 先例，用户手动粘贴，UX 降级）。
- 与 WorkBuddy 对照：WorkBuddy 有 `wb.conversations.prepareInput`（自研编辑器的稳定 API）；dsh 无对应全局 API，但合成事件走官方 intake 达到同等效果（附件 chip 进输入框、不自动发送）。
- 分寸提醒：合成事件属「借用官方入口」而非上游契约，dsh 升级若给 intake 加 `isTrusted` 门槛或改路由规则会失效——落地时配套 DOM 探针诊断标记（与 `diag-*` 系列同法），并在升级回归清单里挂此项。

- 平台归属：接收侧归 entry（deviceTypes 含 2in1/tablet）；按三端矩阵只动 entry 壳、PC 分支不动；phone 模块不涉及（手机端是发送方，走系统分享面板）。
- 数据消费：碰一碰文件落 filesDir 后等价于「一次免手选的文件选择结果」，回传可复用现有三段式模式（`javaScriptProxy` 同步吞下 → 原生异步完成 → `runJavaScript` resolve web 垫片 Promise）。
- 与既有排期对齐：`docs/190` 的 P2-I「harmonyShare 碰一碰（接收侧）——接收侧权限面不变」，本文补齐其 API 细节与 WorkBuddy 对照；`docs/172` 归类「第一层：零 manifest 权限」与本文一致。

### 5.2 落地记录（2026-11-16）

实现（全部通过 `devecocli build --modules entry` 与 113 条门禁回归，权限面 18/9 逐字未动）：

| 件 | 落点 | 职责 |
|---|---|---|
| `entry/src/main/ets/system/KnockShareReceiver.ets`（新增） | ArkTS 接收器 | `canIUse` 门控；`on('dataReceive')` 注册（FILE/IMAGE/VIDEO/AUDIO/MEDIA 各一条，maxSupportedCount=5）；每次传输新建 `filesDir/knock/<时间戳>` 空目录（传完即清，启动时清扫残留）；`onDataReceived` 读 `SharedRecord.uri` → `FileUri(...).path` → fileIo 读取（单文件上限 16 MiB，超限跳过留痕）→ base64 入挂起队列（页面未就绪封顶 10 个）；`onFiles` 通知壳页 |
| `WebApp.ets` 接线 | 壳页 | `KNOCK_SHIM_JS` 入 `pickerShimScripts`（document-start，定义 `window.__DSHM_KNOCK__.emit`：base64 → `File` → 合成 document 级 `paste`，退路 `drop`，双路不通留痕）；`startKnockReceiver()` 仅 `desktopForced` 时注册（aboutToAppear）；`deliverKnockFiles()` 在 dataReceive 通知与 onPageEnd 两个入口取队列补发；`buildKnockEmitScript` 把载荷 JSON 嵌入 `runJavaScript` 推送；aboutToDisappear 注销 |

- 链路：手机碰 → dataReceive → 每传输独立空目录 receive → 系统落盘 → 读出 base64 → `runJavaScript` → `__DSHM_KNOCK__.emit` → 合成 paste → 官方 file-intake → 上传/附件 chip/草稿（不自动发送）。
- 诊断（双通道）：`DSHM-KNOCK` hilog 域 + web 侧 `[dshm-knock]` console 转发（shim ready、paste/drop 路不通等）+ **`filesDir/diag-knock` 落盘文件**（2026-11-16 真机实测后补：用户设备 hilog 对本应用不可读，故注册/接收/投递全链按 `writeDiagMarkerPublic` 同机制落 ISO 时间戳事件行）——start 入口/canIUse 真假/窗口身份三件套（`windowId=N type=T showing=B 主窗=M 一致·不一致·未知`，其中**主窗 id 由 EntryAbility 主窗分支经 AppStorage `dshMainWindowId` 发布**——页面拿不到 windowStage，只能这样对比）/`on('dataReceive')` ok·err（code+msg）/handleTarget 目录/receive err/onResult code/入队与投递摘要/inject result，一条链读完。
- **注册时机（二轮实测后移）**：首轮注册发生在页面就绪前 14s（aboutToAppear）⇒ 后移到 **onPageEnd（webReady）之后**（与 `deliverKnockFiles` 同触发点；幂等，失败下轮重试）——排除「系统在注册那一刻定格可接收窗口」。会话窗（SESSION 独立 UIAbility 实例）各自注册自己的窗口，不全局绑主窗（多窗时 knock 按 windowId 路由到被碰的窗）。
- 投递中断不丢文件：`pushKnockFile` 的 `runJavaScript` 同步抛（controller 未挂载）时，`deliverKnockFiles` 停止本批投递并把残余 `requeue()` 回接收器（队列封顶 10，超限丢弃留痕），等下次 onFiles/onPageEnd 补发。
- 平板分支（desktopForced=false）不注册即不接收（skip 落 diag-knock）；phone 模块零改动。

## 6. 未决与风险

| 项 | 状态 |
|---|---|
| **真机实测（2026-11-16，Beta 1010017 调试包侧载，两轮）** | 第一轮：碰了没反应（WorkBuddy 正式签名同操作 OK），证实 desktopForced 过、shim ready、无 hilog 可读。第二轮（diag-knock 版）：**注册全链成功**（`start enter`→`canIUse=true`→`windowId=454`→`on ok`），但 `files/knock` 未建、无 `target` 行 ⇒ **dataReceive 一次未触发，断点锁定在系统投递**。剩余三候选：②注册太早（已排除性后移到页面就绪）③拿错窗口（已补 type/showing/主窗对比，待复测读数）①侧载包资格/签名（WorkBuddy 文档经验 + 其正式签名同操作 OK） |
| ArkWeb 合成 `ClipboardEvent` 支持度 | 真机待验（两轮均未走到注入步）：代码已带 paste→drop 双退路与 `[dshm-knock]` 诊断；验收看「附件 chip 是否出现在输入框」+ diag-knock `inject result=paste/drop` |
| 正式签名要求 | **头号嫌疑（二轮后）**：d.ts 无据、WorkBuddy 文档经验（「调试签名碰了没反应」）+ WorkBuddy 正式签名同操作 OK + 本包注册成功仍无投递。判据：复测若窗口身份三件套全对（type=0/showing=true/与主窗一致）且注册在页面就绪后仍无 `target` ⇒ 基本坐实；修复路径是含本特性的 AGC 包走邀请测试（正式签名），不可本地侧载 |
| 平板接收 | **已按用户裁定关闭（2026-11-16）：普通平板不启用**；仅 PC 档（desktopForced：PC/2in1/MatePad Edge/Pro Max）注册 |
| receive 目录用一次性子目录 | 保留 `filesDir/knock/<时间戳>`（官方建议已存在空目录、授权面最小，WorkBuddy 用 filesDir 根是更松的写法）；用户疑「系统只放行已授权根」会退化——receive err 已落 diag-knock，若证据指向再改 |
| 大文件通道 | v1 已落 16 MiB 单文件上限（超限跳过留痕）；`onInterceptRequest` 供源仍未实现，真有需求再做 |
| 仅文件数据 | 文本/链接仍走系统原有接收路径，不进沙箱回调 |
| 无送达回调 | 分享结果只有系统通知；UI 不得假设「已送达」 |
| 上游升级脆弱性 | 合成事件方案依赖 intake 不加 `isTrusted` 门槛；升级回归清单挂「碰一碰注入结果≠unrouted」判据 |
| 坐标能力 | 运行时需设备 API 26；设备在 6.1.0(23) 时拿不到轻碰坐标（v1 未消费坐标，无影响） |

## 7. 证据清单

- 本机 SDK d.ts（权威）：`/data/service/hnp/hmos-clt.org/hmos-clt_1.0.0/sdk/default/hms/ets/api/@hms.collaboration.harmonyShare.d.ts`、同目录 `@hms.collaboration.systemShare.d.ts` 与 `kits/@kit.ShareKit.d.ts`
- WorkBuddy 自产调研文档（用户提供）：`~/WorkBuddy/2026-11-16-11-40-57/碰一碰传文件到输入框-DSHM开发文档.html`
- 前端注入点（核心树源码，`dist/core/work/dsh-core-0.2.2-rc.3+dshm.1/node_modules/@deepseek-ai/` 下）：`dsh-client-ui-conversation/src/client/input/facade.ts`（编程式 addFiles/paste/submit）、`src/client/input/file-intake.ts`（document 级 paste 路由，无 isTrusted 门槛）、`dsh-client-ui-attachment/src/client/drop-events.ts`（document 级 drop）、`dsh-client-ui-conversation/src/client/contract/slots.ts`（composer 契约）
- 本仓集成点：`entry/src/main/ets/pages/WebApp.ets`（`__DSHM_BRIDGES__` 聚合注册、`runJavaScript` 事件推送、三段式异步回传、原生听写 base64 与剪贴板先例）；插件 client 半边载体先例 `hostcore/plugins/dshm-office-system-preview/lib/client.js`
- 落地实现：`entry/src/main/ets/system/KnockShareReceiver.ets`、`WebApp.ets`（`KNOCK_SHIM_JS` / `startKnockReceiver` / `deliverKnockFiles` / `pushKnockFile` / `buildKnockEmitScript`）、`EntryAbility.ets`（主窗 id 发布 `dshMainWindowId`，仅 MAIN 分支）；门禁回归基线 `dist/acceptance/upstream-alignment-20261116/gates-titlebar-beta.txt`（113 条，改后全绿）
- 真机实测包：`dist/beta/DSHM-beta-1.1.8-1010017-20261116T132116/`（注册后移 + 窗口身份对比复测包）；前序 `...T125339/`（diag-knock 版，证实注册全链成功）；首轮 `...T122807/`（无埋点版，证实 shim ready/desktopForced 过）
- 既有口径：[`172-API26能力全景与系统融合三件套（A2A·意图框架·系统入口）.md`](172-API26能力全景与系统融合三件套（A2A·意图框架·系统入口）.md)（零权限层归类与排除项）、[`190-API26特性可落地清单（基准beta-1.1.4+core0.2.1-rc.2+dshm.74）.md`](190-API26特性可落地清单（基准beta-1.1.4+core0.2.1-rc.2+dshm.74）.md)（P2-I 排期位）

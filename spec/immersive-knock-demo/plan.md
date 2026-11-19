# Implementation Plan: 沉浸光感 + 碰一碰传文件双 Demo（全机制复刻）

**Input**: Feature specification from `spec/immersive-knock-demo/spec.md`

## Summary

在 `{PROJECT_ROOT}/demo/` 下用 `devecocli create` 脚手架新建独立 HarmonyOS 工程（bundle `com.dshm.dshdemo`，untracked，生产码/配置零改动），以**全机制保真**复刻两项生产特性：

1. **沉浸光感混合承载**：THICK 材质 AlertDialog（复刻生产 4 处形态）+ 网页右键/长按原生接管（THIN 材质、语境菜单项、锚定、空集回退）；
2. **碰一碰传文件**：Share Kit 真实接收全套机制（canIUse 守卫/1-2-4-8s 退避/挂起队列/落盘清理）+「模拟碰一碰」单机入口，两者收敛到**同一注入管线**（垫片合成 paste → 退 drop → unrouted 留痕）。

单页 Tabs 双页签组织（沉浸光感 / 碰一碰），State Management V2，权限面目标 0 条，三诊断探针（diag-material/webmenu/knock）落 filesDir。生产 131 门禁落地后重跑必须全绿（FR-013/SC-003）。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS API 6.1.0(23) min / 26.0.0 target，对齐生产 API 纪律；demo 自身版本 1.0.0，与生产版本号铁律无关）
**Primary Dependencies**: ArkWeb（Web 组件、onContextMenuShow、javaScriptOnDocumentStart、runJavaScript）、Share Kit（@kit.ShareKit，harmonyShare/systemShare）、file picker（DocumentViewPicker，系统选择器免权限）、windowStage 主窗（Share Kit 注册载体）
**State Management**: State Management V2（greenfield 规则：@ComponentV2/@Local；菜单面板沿用生产「每次显示构造 ComponentContent + wrapBuilder」模式，不依赖 V1 响应式状态）
**Storage**: filesDir（三个 diag 追加文件 + 真实接收落盘目录，demo 自身沙箱）；rawfile（两演示 HTML + 内置样例文件）
**Testing**: check_ets_files（demo 全部 .ets）→ demo 独立构建绿（demo/ 目录内执行）→ 生产 131 全量门禁重跑全绿（`python3 dist/acceptance/rerun-gates.py dist/acceptance/20261117-full-yml-gates-sweep.txt <输出>`）
**Target Platform**: HarmonyOS 平板 / 2in1（主演示设备）+ 手机；API 23–26（材质相关能力仅 API≥26 生效，<26 全功能纯色兜底）
**Project Type**: 独立可安装的演示应用（调试签名 hap，脚手架自动生成 demo 自有签名物料）
**Performance Goals**: 演示应用无性能指标；单文件 ≤16MiB、挂起队列 ≤10、注册退避 ≤5 次与生产纪律一致
**Constraints**: 生产模块/配置/门禁零改动；demo 权限面目标 0 条（兜底最多 INTERNET 一条并留痕）；材质 API≥26 守卫必须在实参求值前；本机无 hdc（交付证据上限 = 离线门禁 + 包结构）
**Scale/Scope**: 单 entry 模块 + 13 个 ArkTS 文件 + 2 个 rawfile HTML + 1 个内置样例文件

## Project Structure

### Documentation (this feature)

```text
spec/immersive-knock-demo/
├── spec.md              # 已批准的需求规格
├── plan.md              # 本文件
└── tasks.md             # Phase 3 产出
```

### Source Code (repository root)

```text
demo/                                    # untracked 独立工程（脚手架生成后填充）
├── AppScope/app.json5                   # com.dshm.dshdemo / 1.0.0 / label "DSHM Demo"
├── build-profile.json5                  # min 6.1.0(23) / target 26.0.0；demo 自有调试签名
├── oh-package.json5
├── hvigor/ + hvigorfile.ts              # 脚手架自带
└── entry/
    ├── src/main/module.json5            # requestPermissions 空；deviceTypes: tablet/2in1/phone
    ├── src/main/resources/
    │   └── rawfile/
    │       ├── immersive-demo.html      # 五类对象演示页（离线：图用内嵌 data URI）
    │       ├── knock-demo.html          # file-intake 演示页（document 级 paste/drop → chip）
    │       └── demo-sample.txt          # 内置样例文件（模拟碰一碰来源一）
    └── src/main/ets/
        ├── entryability/EntryAbility.ets        # 主窗加载 + 启动写 diag-material
        ├── pages/Index.ets                      # Tabs 两页签 + 主题切换（System/Light/Dark）
        ├── views/
        │   ├── ImmersiveDemoView.ets            # 弹窗 4 形态按钮 + Web 演示区（菜单接管）
        │   └── KnockDemoView.ets                # Web 输入区 + 模拟按钮×2 + 注册状态行
        ├── viewmodel/
        │   ├── ImmersiveDemoViewModel.ets       # 菜单计算编排 + 弹窗动作 + diag-webmenu
        │   └── KnockDemoViewModel.ets           # 接收状态 + 模拟管线 + 挂起补发编排
        ├── service/
        │   ├── DemoMaterialKit.ets              # 移植 platform/.../ImmersiveMaterialKit.ets
        │   ├── WebMenuHost.ets                  # 移植 WebApp.ets :7311-7452 接管链
        │   ├── KnockShim.ets                    # 移植 KNOCK_SHIM_JS(:3393) + 载荷注入
        │   ├── DemoKnockShareReceiver.ets       # 移植 KnockShareReceiver.ets（去 PC 档门控）
        │   └── Diag.ets                         # 三探针追加写 filesDir
        ├── model/
        │   └── DemoTypes.ets                    # KnockFile / WebContextMenuItem / PanelParams / ThemeMode
        └── common/
            └── DemoTheme.ets                    # themeMode 状态 + themeDark 求值
```

**Structure Decision**: 新工程选 **MVVM 档（最小拆分）**。触发项：业务服务与算法（Share Kit 接收生命周期、base64 注入管线、材质构造纪律、菜单接管链）超出 Trivial/Light 承载力。文件数 13（含脚手架 EntryAbility）略超 6–12 目标，超因 = 5 个保真移植的生产单职责服务（材质/菜单/垫片/接收/诊断）+ 2 个视图编排 viewmodel，每个服务对齐一个生产源文件（移植对照性优先于文件数压缩）；不再合并文件以免破坏「一职责一源」的移植审计。viewmodel/ 承接每视图编排（接收状态、菜单计算、模拟管线），views/ 保持薄装配，pages/Index 只做 Tabs 装配与主题切换。资源一律在 entry/src/main/resources/（rawfile），不放在 ets/ 下；无重复同名目录。绿色新工程用 State Management V2（greenfield 规则），不引入生产 V1 状态。

## Complexity Tracking

无违宪项。（唯一可议点：demo 嵌套于工作区根目录内而工作区根本身是 hvigor 工程——经门禁扫描审计（见 Research #3），生产 131 门禁全部生产路径钉定，不会枚举 demo/；demo 构建一律在 demo/ 目录内独立执行，两工程互不可见。）

## Research & Decisions

### R1 脚手架与工程身份
- **Decision**: `devecocli create --app-name dshm-demo --project-path demo --bundle-name com.dshm.dshdemo` 生成工程；后置对齐 `demo/build-profile.json5` 为 min 6.1.0(23) / target 26.0.0；AppScope 版本 1.0.0、label "DSHM Demo"。
- **Rationale**: 标准脚手架拿到可构建的独立工程与自动调试签名物料；API 面对齐生产纪律使 <26 兜底场景（SC-002）可测。
- **Alternatives considered**: 手工拼工程（弃：易错且绕过脚手架签名物料生成）；复制生产树改造（弃：拖带生产签名/配置/模块，违反 FR-001 隔离）。

### R2 demo 权限面 = 0 条（兜底 INTERNET 一条）
- **Decision**: module.json5 `requestPermissions` 留空。所用能力（Share Kit 注册、DocumentViewPicker、rawfile 本地加载、startAbility 拉系统浏览器、沙箱内文件 I/O、粘贴板写）均无 @permission 要求。若实现/验证发现 Web 加载 rawfile 受阻，兜底方案 = 仅声明 INTERNET 一条（demo 侧，与生产 18/9 铁律无关）并在 diag 留痕。
- **Rationale**: spec 假设「demo 自身接近零权限」；`devecocli docs` 本机 SQLite 绑定损坏无法检索（环境受限），退回本会话已核 d.ts 事实 + 生产证据；验证阶段实证后定案。
- **Alternatives considered**: 预声明 INTERNET 防御（弃：违反「先实现后声明」纪律，且 demo 加载本地 rawfile 预期免权限）。

### R3 生产 131 门禁与 demo/ 的隔离（FR-013 风险审计）
- **Decision**: demo/ 落地后重跑全量基线作 FR-013 终判；审计证明无误扫风险。
- **Rationale**: 逐门禁核对：check-dead-code `SCAN_ROOTS=['entry/src/main/ets','appstate/src/main/ets']`、check-import-path 只看单文件、check-permission-surface 只看 entry/phone module.json5、gen-oss-notices 走核心树 node_modules、check-doc-refs 只扫 docs/——131 条全部生产路径钉定，无仓库根递归枚举。
- **Alternatives considered**: 把 demo 放工作区外（弃：用户已裁定 demo/ 子目录）；改 .gitignore 掩盖（弃：生产文件零改动，且 demo/ 保持 untracked 即可，仓库本就永不提交）。

### R4 页面组织：单页 Tabs 双页签
- **Decision**: Index 单页 + Tabs 两个页签（沉浸光感 / 碰一碰），两个 Web 组件常驻。
- **Rationale**: 碰一碰注入目标 web 不因导航卸载（模拟按钮随时可用、挂起队列就绪即补发）；演示切换零导航成本。
- **Alternatives considered**: Navigation 路由多页（弃：后台页生命周期复杂化 demo，无对应收益）。

### R5 状态管理 V2 + 菜单面板构造模式
- **Decision**: 页面/视图用 @ComponentV2/@Local（greenfield 规则）；玻璃菜单面板沿用生产「每次显示时构造 ComponentContent + wrapBuilder(WebContextMenuPanel)」模式（移植锚 WebApp.ets :7447-7452），面板状态不依赖 V1 响应式。
- **Rationale**: 生产面板即按显示时构造，无跨帧响应式依赖，V2 下逐位可移植。
- **Alternatives considered**: 整页用 V1 复刻生产（弃：greenfield 规则要求 V2；面板构造模式已证明与状态管理解耦）。

### R6 同一注入出口（FR-009）
- **Decision**: 真实接收 `onDelivered` 与「模拟碰一碰」按钮（内置样例 / 文件选择器两来源）全部收敛到 `KnockShim.injectFile(webController, KnockFile)` 单一入口。
- **Rationale**: 规格要求模拟与真实走完全相同管线（同一出口），旁路注入违反 FR-009 且破坏保真对照。
- **Alternatives considered**: 模拟路径直调 web runJavaScript（弃：形成第二管线，破坏同一出口约束）。

### R7 接收器移植差异：去 PC 档门控
- **Decision**: DemoKnockShareReceiver 移植 KnockShareReceiver.ets 全机制（canIUse 守卫、主窗注册、1/2/4/8s 退避至多 5 次、幂等 start/stop、filesDir 接收、落盘记账与传输后清理、16MiB 上限、挂起队列封顶 10、takePending/requeue），**去掉 desktopForced 门控**，差异以注释注明「生产仅 PC 档注册，demo 无形态矩阵不门控（FR-010）」。
- **Rationale**: demo 无形态矩阵，门控无意义；注释保住生产对照可审计性。
- **Alternatives considered**: 保留门控常量但恒真（弃：伪机制不如显式去除+注释）。

### R8 签名与 git 隔离
- **Decision**: demo 用脚手架自动生成的自有调试签名物料；生产 `signing/**`、`.certs/**`、build-profile 一概不动；`.gitignore` 不改，demo/ 仅保持 untracked。
- **Rationale**: 4.2 签名物料保全红线；仓库基线「代码永不提交」使 untracked 即安全。
- **Alternatives considered**: 复用生产调试签名（弃：跨工程身份混淆且违反物料保全边界）。

### R9 演示内容离线化
- **Decision**: immersive-demo.html 五类对象全离线——图片用内嵌 data URI、链接用 IANA 保留示例域（example.com，仅作语境菜单触发与「打开链接」拉起系统浏览器演示）；knock-demo.html 自带 file-intake 脚本（document 级 paste/drop 监听 → 附件 chip，可移除、不自动发送）。
- **Rationale**: demo 不依赖网络（设备可能无网）；chip 行为复刻官方 file-intake（FR-008）。
- **Alternatives considered**: 加载外网演示资源（弃：网络依赖 + 权限面膨胀）。

## Data Model

- **KnockFile**：`{ name: string, mime: string, size: number, base64: string }`——校验：`size ≤ 16MiB`（超限跳过留痕）、base64 可解（atob 失败留痕不注入）；来源三路：内置样例（rawfile 读取）/ 文件选择器 / 真实接收落盘文件读取。
- **挂起队列（PendingQueue）**：元素 = 落盘文件路径（真实接收）或 KnockFile（模拟）；状态迁移 `waiting → injected`，投递中断 `→ requeued`，页签未就绪注入 `→ waiting`（页面就绪补发）；容量 10，超限丢弃留痕。
- **WebContextMenuItem**：`{ label: string, run: () => void }`；**WebContextMenuPanelParams**：`{ items: WebContextMenuItem[], themeDark: boolean }`。
- **ThemeMode**：`System | Light | Dark`（demo 内可切换，默认 System）；`themeDark` 由它显式求值（材质明暗不用 SYSTEM 档，生产纪律）。
- **DiagLine**：`ISO8601 时间戳 + 空格 + 标记文本 + 换行`，追加式写入 filesDir 下 `diag-material` / `diag-webmenu` / `diag-knock` 三文件。
- **接收记账（Ledger）**：`Map<传输uri, 落盘路径[]>`，onResult 后按 uri 逐个清理落盘文件（不删目录），与生产对齐。

## Contracts & Interfaces

- **DemoMaterialKit**（移植自 platform/src/main/ets/ui/ImmersiveMaterialKit.ets，保持守卫纪律）：
  - `dialogMaterial(): MaterialOptions | undefined`——THICK 非交互；API≥26 判定与构造异常兜底（undefined）在**实参求值前**守卫
  - `menuMaterial(themeDark: boolean): MaterialOptions | undefined`——THIN，明暗显式
  - `immersiveMaterialOf(...)` 及三包装（dialog/shell/control）签名与生产一致
- **WebMenuHost**（移植自 WebApp.ets :7311-7452）：
  - `buildMenuItems(param, result, themeDark): { items: WebContextMenuItem[], handled: boolean }`——语境判定（link / image / editable+位掩码 / 纯选区 / 空集）、坐标负值回退（handled=false 走系统菜单）、THIN 材质仅 API≥26 求值、动作映射（打开链接拉系统浏览器、复制/剪切/粘贴/全选走 ArkWeb result、复制图片、保存图片按 API 存在性 typeof 守卫）
  - 面板渲染契约：`ComponentContent + wrapBuilder(WebContextMenuPanel)`，WithTheme{Menu{ForEach MenuItem}} 结构逐位移植（锚 :195-225）
- **KnockShim**：
  - `SHIM_SCRIPT`：document-start 注册串（scriptRules ['*']），内容 = KNOCK_SHIM_JS 逐位移植（window.__DSHM_KNOCK__ 防重入、toFile、dispatchPaste 合成 ClipboardEvent('paste') 带 DataTransfer、退 DragEvent('drop')、[dshm-knock] 日志、unrouted 留痕）
  - `injectFile(controller, file: KnockFile): Promise<boolean>`——唯一注入入口（R6）；返回是否成功路由（false = unrouted，diag 留痕）
- **DemoKnockShareReceiver**（移植自 entry/src/main/ets/system/KnockShareReceiver.ets）：
  - `start(context, hooks: { onDelivered(file: KnockFile): void }): void` / `stop(): void` / `state(): 'unsupported' | 'registering' | 'registered' | 'failed'`
  - 全机制见 R7；receiveUri = demo 自身 filesDir
- **Diag**：`Diag.material(line) / Diag.webmenu(line) / Diag.knock(line)`——追加写、ISO 时间戳行、启动 diag-material 一次性能力读数（sdk/supported/level；API<26 记 below26）
- **DemoTheme**：themeMode 状态 + `themeDark(mode, systemColorMode): boolean` 求值；系统明暗经 EntryAbility onConfigurationUpdate 跟踪
- **rawfile 页面契约**：
  - `immersive-demo.html`：必含五类对象——`<a>` 链接（示例域）、`<img>`（data URI）、可编辑 `<input>`、可选中文本段、空白区；无外部资源引用
  - `knock-demo.html`：document 级 paste/drop 监听 → chip（文件名 + 大小）进输入区、chip 可 ×移除、不自动发送；接受垫片合成事件（clipboardData.files / dataTransfer.files）
- **构建/验证契约**：demo 构建一律在 demo/ 内执行（独立 hvigor 根）；生产构建与 131 门禁在仓库根执行，互不可见（R3）

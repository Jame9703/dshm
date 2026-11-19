# Feature Specification: 沉浸光感 + 碰一碰传文件双 Demo（全机制复刻）

**Created**: 2026-11-17  
**Status**: Draft  
**Input**: User description: "把现在实现的沉浸光感的效果再复刻一个demo，还有碰一碰传文件的demo一起"

## Overview

在 DSHM 工作区内新建独立 demo 工程（`demo/` 子目录，与生产模块隔离、untracked），以**全机制保真度**复刻两项已落地生产特性，供安装到设备单独演示：

1. **沉浸光感混合承载**（生产依据：`docs/419` + entry `WebApp.ets` 现行实现）——AlertDialog THICK 材质弹窗 + 网页右键/长按菜单原生接管（THIN 材质、语境菜单项、锚定、回退纪律）；
2. **碰一碰传文件**（生产依据：`docs/418` + `KnockShareReceiver.ets` + `KNOCK_SHIM_JS`）——Share Kit 沙箱接收 → base64 注入合成 paste → 附件 chip 进输入框；**真实注册 + 「模拟碰一碰」按钮双轨**（单机必可演示）。

生产码零改动（entry / phone / platform / hostruntime / tools 等一概不动），生产 131 门禁不受影响。

## User Scenarios & Testing

### User Story 1 - 沉浸光感材质弹窗演示 (Priority: P1)

打开 demo 进入沉浸光感 demo 页，点按钮弹出演示弹窗：API≥26 设备上弹窗挂 THICK 沉浸材质（玻璃观感）；API<26 设备纯色兜底；材质构造异常时弹窗照常。按钮排布复刻生产 4 处 AlertDialog 形态（确认类双按钮 / 失败提示类）。

**Why this priority**: 沉浸光感两大可见效果之一，单按钮即可演示，最小独立切片。

**Independent Test**: 点任一弹窗按钮即可独立演示与验收。

**Acceptance Scenarios**:

1. **Given** API≥26 真机, **When** 点弹窗演示按钮, **Then** 弹窗出现且挂玻璃材质（THICK），形态与生产一致
2. **Given** API<26 设备, **When** 同上, **Then** 弹窗出现、无材质、不崩
3. **Given** 材质构造抛异常的设备, **When** 同上, **Then** 材质缺席（undefined 兜底）、弹窗照常可读可点

---

### User Story 2 - 网页菜单原生接管演示 (Priority: P1)

沉浸光感 demo 页内含本地网页演示区（含链接、图片、可编辑输入框、可选中文字、空白区）。右键/长按不同对象弹出原生玻璃菜单（THIN 材质 + 明暗随主题显式指定 + 锚定触点），菜单项按语境生成：链接→打开链接/复制链接；图片→复制图片/保存图片；可编辑→剪切/复制/粘贴/全选（按可用位掩码）；纯选区→复制/全选；空集→回退 ArkWeb 系统默认菜单。

**Why this priority**: 沉浸光感第二大可见效果，语境菜单项逻辑是生产接管链核心。

**Independent Test**: 对演示区五类对象分别长按/右键即可独立验收。

**Acceptance Scenarios**:

1. **Given** 演示页加载完成, **When** 长按链接, **Then** 玻璃菜单出「打开链接/复制链接」，点开链接能拉起系统浏览器
2. **When** 长按图片, **Then** 出「复制图片」（「保存图片」按 API 存在性出现）
3. **When** 焦点在输入框内长按, **Then** 按可编辑位掩码出剪切/复制/粘贴/全选子集
4. **When** 长按纯选中文字, **Then** 出复制/全选
5. **When** 长按空白处（菜单项空集）, **Then** 回退系统默认菜单，不崩、不弹空菜单
6. **Given** API<26 设备, **When** 任一长按, **Then** 菜单照常（无材质）、功能完整

---

### User Story 3 - 碰一碰模拟演示（单机必现） (Priority: P1)

进入碰一碰 demo 页，点「模拟碰一碰」：选内置样例文件或经系统文件选择器选真实文件 → 读取 + base64 → 走**与真实接收完全相同**的注入管线（垫片合成 paste，退路 drop）→ demo 网页输入区出现附件 chip、不自动发送。

**Why this priority**: 碰一碰链路的单机可演示入口，不依赖第二台设备。

**Independent Test**: 单机点按钮即可看到 chip 进输入框。

**Acceptance Scenarios**:

1. **Given** 演示页就绪, **When** 点「模拟碰一碰（内置样例）」, **Then** 输入区出现该文件附件 chip（文件名/大小），内容不自动发送，chip 可移除
2. **When** 经文件选择器选一个 ≤16MiB 文件, **Then** 同上
3. **When** 选 >16MiB 文件, **Then** 跳过并留诊断痕（不注入、不崩）
4. **Given** 垫片 paste 路不通, **When** 模拟碰一碰, **Then** 自动退 drop 路；两路皆不通时留痕 unrouted

---

### User Story 4 - 碰一碰真实接收（双机） (Priority: P2)

demo 在主窗注册 Share Kit 真实接收（能力守卫 + 1/2/4/8s 退避注册全套机制，不做生产端的 PC 档门控——demo 无形态矩阵）；第二台手机轻触本机屏幕发起分享时，文件落盘 → 读取 → 注入 → chip 进输入框，与模拟链路同一出口。页面重载窗口收到的文件挂起补发不丢。

**Why this priority**: 生产机制复刻的完整形态，但需双机、且调试签名下投递属首验项，故次优先。

**Independent Test**: 有第二台设备时碰一碰即可验收；单机可验注册诊断标记。

**Acceptance Scenarios**:

1. **Given** 设备具备 Share Kit 能力, **When** demo 启动, **Then** 真实接收注册成功（诊断可读注册/窗口/重试标记）
2. **Given** 注册成功且手机发起轻触分享, **When** 传输完成, **Then** chip 进输入框
3. **Given** 设备无该能力（canIUse=false）, **When** demo 启动, **Then** 不注册、只留痕、不重试
4. **Given** 注册瞬时失败, **When** 按退避节奏, **Then** 1/2/4/8s 重试至多 5 次后放弃留痕
5. **Given** 演示页重载窗口收到文件, **When** 页面就绪, **Then** 挂起队列补发（不丢）；投递中断回队

---

### User Story 5 - 诊断探针复刻 (Priority: P3)

生产三探针全套移植：`diag-material`（启动一次性能力读数）、`diag-webmenu`（菜单全链路）、`diag-knock`（注册/接收/投递全链），追加式落 filesDir 可 cat。

**Why this priority**: 全机制复刻的组成部分，纯诊断、不影响观感演示。

**Independent Test**: 设备文件管理器/终端读取对应标记文件。

**Acceptance Scenarios**:

1. **Given** demo 启动完成, **When** 读 diag-material, **Then** 有 sdk/supported/level 读数（API<26 记 below26）
2. **When** 每次长按/右键, **Then** diag-webmenu 追加 show/fallback/open/appear/dismiss/item 等全链标记
3. **When** 注册/接收/模拟任一环节, **Then** diag-knock 追加对应标记

---

### Edge Cases

- API<26 设备：材质全部缺席（守卫在**实参求值前**）、菜单/弹窗/碰一碰功能完整、零闪退（生产 docs/196 闪退教训的守卫纪律照搬）
- 垫片 ClipboardEvent 构造失败的 ArkWeb 版本：退 DragEvent drop；两路皆失败留痕（unrouted）
- 单文件 >16MiB：跳过留痕不注入（base64 脚本体量上限纪律）
- 挂起队列封顶（10）：超限丢弃留痕
- 真实接收注册瞬时失败：退避重试至多 5 次后放弃；能力永久缺失（canIUse=false）不重试
- 演示页未就绪时的注入：挂起等页面就绪补发；投递中断回队不丢
- 真实接收传输结束后：按记账逐个清理落盘文件（不删目录）
- 空/损坏载荷（atob 失败）：留痕不注入

## Requirements

### Functional Requirements

**沉浸光感**

- **FR-001**: demo MUST 为工作区 `demo/` 子目录下的独立工程，生产模块与配置零改动
- **FR-002**: 弹窗演示 MUST 复刻生产 4 处 AlertDialog 的材质（THICK、非交互）与按钮形态（确认类双按钮/失败提示类），文案改 demo 演示语境
- **FR-003**: 材质构造 MUST 在实参求值前判 API≥26，构造异常兜底返回 undefined（= 不挂材质），任何设备不因材质缺席而崩
- **FR-004**: 网页右键/长按 MUST 原生接管：语境菜单项（链接/图片/可编辑位掩码/纯选区/空集回退系统菜单）、THIN 材质、明暗随主题显式指定（不用 SYSTEM 档）、锚定触点坐标弹出
- **FR-005**: 菜单项动作 MUST 对应生产行为：打开链接直开（不二次确认）、复制/剪切/粘贴/全选走 ArkWeb result、复制图片、保存图片（API 存在性 typeof 守卫）

**碰一碰**

- **FR-006**: 真实接收 MUST 复刻 KnockShareReceiver 全机制：canIUse 守卫、主窗注册、1/2/4/8s 退避（首次+4 重试）、幂等 start/stop、filesDir 接收、落盘记账与传输后清理、单文件 16MiB 上限、挂起队列（封顶 10）、takePending/requeue
- **FR-007**: 注入链 MUST 复刻：document-start 垫片（base64→File→合成 ClipboardEvent('paste') 带 DataTransfer；失败退 DragEvent('drop')；再失败 unrouted）+ 单文件 JSON 载荷注入脚本
- **FR-008**: demo 网页 MUST 复刻官方 file-intake 行为：document 级 paste/drop 监听 → 文件以附件 chip 进输入框、不自动发送、chip 可移除
- **FR-009**: 「模拟碰一碰」MUST 提供两种文件来源（内置样例文件；系统文件选择器选真实文件），且走与真实接收完全相同的注入管线（同一出口）
- **FR-010**: demo 与生产的门控差异（生产仅 PC 档注册、demo 不门控）MUST 在 demo 代码注释注明

**诊断与工程**

- **FR-011**: 三探针 MUST 复刻（diag-material / diag-webmenu / diag-knock），追加式落 filesDir，不依赖 hilog
- **FR-012**: demo 工程 MUST 可独立构建出调试签名 hap，可安装到设备演示
- **FR-013**: demo 的加入 MUST NOT 影响生产 131 门禁（生产码/配置零改动，落地后重跑验证）

### Key Entities

- **KnockFile**：单个注入载荷（name / mime / size / base64）
- **WebContextMenuItem**：菜单项（label / run）
- **WebContextMenuPanelParams**：菜单面板入参（items / themeDark）
- **ImmersiveMaterialKit**：材质构造纪律单源（API 守卫 + undefined 兜底；dialog/shell/control 三包装 + immersiveMaterialOf）
- **KnockShareReceiver**：真实接收器（注册/接收/队列/清理生命周期）
- **三诊断标记文件**：diag-material / diag-webmenu / diag-knock（追加式、ISO 时间戳行）

## Success Criteria

### Measurable Outcomes

- **SC-001**: API≥26 真机安装 demo 后：4 类弹窗带玻璃材质、五类对象长按均出语境玻璃菜单、模拟碰一碰单机 100% 出 chip——全部可见效果单机可演示
- **SC-002**: API<26 设备全程零闪退，材质缺席但弹窗/菜单/碰一碰功能完整
- **SC-003**: 生产 131 门禁在 demo 落地后重跑全绿（0 失败）
- **SC-004**: demo 独立构建绿；三个 diag 文件按场景可读
- **SC-005**: 双机场景真实碰一碰走通（受调试签名投递资格影响；注册诊断标记必须可读）

## Assumptions

- demo 工程位于工作区 `demo/` 子目录（用户已确认），untracked 不入 git
- 真实碰一碰在调试签名下是否投递属环境未知（生产亦属首验项），demo 以模拟链路保证单机可演示性
- demo 设备面以平板/2in1 为主（用户演示设备为平板），顺带支持手机形态
- demo 权限面独立于生产（生产 18/9 铁律不受影响）；demo 自身接近零权限（Share Kit 注册、合成 paste、拉起浏览器、文件选择器均无 @permission 要求）
- 弹窗/菜单演示文案改为 demo 语境，材质/结构/行为逐位复刻
- 生产的明暗跟随（themeMode 桥）在 demo 简化为跟随系统明暗 + demo 内切换开关（观感演示用）
- 生产 4 处弹窗中与 DSHM 业务强绑定的语境（如登录华为账号确认）在 demo 中以等价结构（确认双按钮/失败提示）演示

## Open Questions

- 无（四项关键决策已经用户确认：demo 位置 / 碰一碰触发方式 / 复刻保真度 / spec 目录）

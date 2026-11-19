# 147 · API 26 特性深度调研与 `targetSdkVersion` 抬到 26.0.0（`compatibleSdkVersion` 保持 6.1.1(24)）

> **历史状态说明（2026-10-18）**：API 26 特性调研和 target 抬升结论仍有效；
> 文件名与正文中的 `compatibleSdkVersion 6.1.1(24)` 已被 `docs/183` 更新为
> `6.1.0(23)`。当前值以 `build-profile.json5` 和最终 HAP 为准。

日期：2026-10-11
设备：手机 Mate80 `62T0225B18039433`（API 26，在线）；**鸿蒙 PC / 平板（API 24）本轮未连接**
编译 SDK：DevEco **Release** SDK `26.0.0.105`
核心树：`0.2.1-alpha.2+dshm.32`（**本轮未升** —— 只动工程配置与注释，不碰核心树）

用户原话：

> 我的想法，`targetSdkVersion` 到 26.0.0、`compatibleSdkVersion` 保持 6.1.1(24)，并且全面接入 26.0.0 的特性，
> 之前其他会话调研过一次，你再看看 26 的特性对于我们的项目哪些是值得接入的，深度调研一下，
> 然后再升 `targetSdkVersion` 到 26.0.0

⇒ 拆成三步，并给出结论：

| 步 | 内容 | 本档 | 落地状态 |
|---|---|---|---|
| ① | API 26 增量面 + 行为变更面**深度调研** | §4 / §3 | 完成（**285 个 d.ts、4033 条 `@since 26.0.0` 逐文件扫描**） |
| ② | 抬 `targetSdkVersion` → `26.0.0(26.0.0)`（`compatible` **不动**） | §1 / §2 | **已改 `build-profile.json5`** |
| ③ | 「哪些值得接入」的取舍 | §4 / §5 / §6 | 逐条给结论；**外观 / 行为变更类一律先问**（§9） |

**先给结论**：API 26 对本仓**真正值得接入的只有 2 条**（且都要求 API 26 设备 + `apiAvailable` 守卫，
否则 API 24 手持档会拿到不存在的方法）；其余 4000 余条要么与产品无关，要么会**改外观 / 改布局**，
要么只能动核心树。**抬 target 的真实代价是 3 条行为变更**（§3），不是安装面。

---

## 1 只抬 target 不丢安装面（沿用 `docs/146` §1 同一实测）

`docs/146` §1 已经把这条钉死，本轮**不重跑**，只引用结论：

| `targetSdkVersion` | `compatibleSdkVersion` | 产物 `minAPIVersion` | 产物 `targetAPIVersion` | debug HAP |
|---|---|---|---|---|
| `"6.1.1(24)"` | `"6.1.1(24)"` | 60101024 | 60101024 | 399,421,087 B |
| `"26.0.0(26.0.0)"` | `"6.1.1(24)"`（**未动**） | **60101024（未变）** | 260000026 | 399,421,088 B |

⇒ **装机门槛由 `compatibleSdkVersion`（→ 产物 `minAPIVersion`）决定，不是 `targetSdkVersion`。**
官方 schema 原文（`hvigor-ohos-plugin\res\schemas\ohos-project-build-profile-schema_zh.json`）：

> `compatibleSdkVersion`：「应用/元服务运行所需兼容的最低SDK版本。**运行应用的系统 API 版本不能低于该值，否则无法安装**；不能高于目标SDK版本」
> `targetSdkVersion`：「应用/元服务运行的目标SDK版本。**系统会根据 targetSdkVersion 控制应用的行为**。如未配置，默认与 compileSdkVersion 保持一致」

⇒ 只抬 target、保持 `compatible=6.1.1(24)`，**API 24（HarmonyOS 6.1.1）的平板照装**，`docs/110` 那一档兼容面不丢。
两版 HAP 体积只差 **1 字节**（260000026 比 60101024 恰好多一位）⇒ 除 `targetAPIVersion` 外逐字节相同。

- **写法**：必须写 `"26.0.0(26.0.0)"`；写 `"6.2.0(26)"` 被 hvigor 拒：
  `00303082 targetSdkVersion is not supported. Change it to a valid version in the available list.`
  依据 `...\hvigor-ohos-plugin\node_modules\@ohos\hos-sdkmanager-common\build\res\hos-config.json` 的
  `osVersionMapper`：`"26.0.0":"26.0.0"` / `"6.1.1":"24"` / `"6.1.0":"23"`。
- **本轮唯一未实证的一条**：`targetAPIVersion=260000026` 的包装到 **API 24 真机**会不会被 BMS 拒。
  机制上 target > device 是允许的（按 `compatible` 判门槛），但本仓**没有这条实测** —— 在线设备只有 Mate80
  （API 26）。要判死需接一台 API 24 平板装一次（见 §10 回归计划）。
- 本节数字 60101024 / 260000026 **刻意不加反引号**：`tools/check-doc-refs.mjs` 会把同行"纯数字的反引号段"
  归给前面最近的 mention（`docs/136` §6 登记的门禁盲区；`docs/146` §1 同样处理）。

---

## 2 本轮已改的内容（只 2 个文件 + 本档 + 索引）

| 文件 | 改动 | 为什么 |
|---|---|---|
| `build-profile.json5`（`.gitignore:74` 已忽略 ⇒ 不进公开仓） | `products[default].targetSdkVersion`：`"6.1.1(24)"` → **`"26.0.0(26.0.0)"`**；`compatibleSdkVersion` **未动**（仍 `"6.1.1(24)"`）。两处注释按实测订正并指向本档 | 用户诉求②的直接落实 |
| `appstate\src\main\ets\ui\HarmonyTheme.ets`（`HarmonyMaterial` / `HarmonyElevation` 注释） | ① 把「官方沉浸光感要求 `targetAPIVersion>=26`，本仓固定在 24 ⇒ 不引入」这段**已过期**的注释改成「target 已抬到 26，但 `IMMERSIVE_ENABLED` 仍为 false 是**产品决定**，不是技术限制」；② 升级四步补上漏掉的第 ④ 步（`module.json5` 的 `module.metadata` 应用级开关）；③ `HarmonyElevation` 补一条**防御性**注释「radius 不要写 0」（来源说明见 §6②） | 注释与事实对齐；否则半年后有人按旧注释判断"开不了" |
| `docs\README.md` | 索引尾部加本档一条；章节标题编号上界 144 → 147 | 索引纪律 |

**决策文案口径同步（2026-10-11 追加已做，见 §8）**：`README.md` / `docs/parity-matrix.md` /
`docs/device-validation.md` 的「target 保持 24」口径**已就地同步**（就地替换、不动行数 ⇒ 不牵动
`docs/NN:行号` 引用）；`docs/110` §5.1 / §6 与 `docs/142` §6 的**历史拍板本体不改**，只加一行日期化
「后续变更」注记。改后 `check-doc-refs` 全绿。

---

## 3 抬 target 后启用的行为变更影响面

API 26（OpenHarmony SDK 7.0.0.x）**影响契约兼容性**的 ArkUI 变更共 6 条，逐条读过原文（来源：OpenHarmony
SDK 7.0.0.17 / .18 / .19 / .20 / .21 / .22 / .24 的 `changelogs-arkui.md` 与 `changelogs-arkts.md`），
**命中本仓 3 条**、**零命中 3 条**（外加若干非 ArkUI 子系统变更，与本仓零命中）。

### 3.1 命中 ①：`cl.arkui.2`（7.0.0.20）—— 弹层默认开启**沉浸式系统材质**

> 变更后：**Dialog / Toast / AlphabetIndexer / 文本选择菜单**默认开启沉浸式系统材质。
> 1. 当开发者**主动**为上述组件配置了背景色、背景模糊、阴影和边框样式时，沉浸式系统材质**不会**默认生效。
> 2. 不期望开启 ⇒ `module.json5` 的 `module.metadata`（**仅 entry 类型 module 生效**）把值设为 `"disable"`。
> 3. 只关部分组件 ⇒ 组件级接口 `systemMaterial`（`.systemMaterial(uiMaterial.Material.empty)`）。

命中点（源码树实读）：

| 落点 | 组件 | 现状 |
|---|---|---|
| `entry\src\main\ets\pages\WebApp.ets` 2550 / 2580 / 2646 / 3865 | `showAlertDialog` ×4 | **都没设 `backgroundColor`** ⇒ 走 DEFAULT 档 ⇒ 外观会变 |
| `entry\src\main\ets\pages\Index.ets:2421` | `.bindSheet(...)` | 助手 / 命令面板 |
| `entry\src\main\ets\pages\WebApp.ets:4097` | `.bindMenu(items)` | 顶栏菜单（`appMenu()` / `editMenu()`） |
| `entry\src\main\ets\view\MessageRow.ets:185`、`ConversationPane.ets:114` 附近 | `.bindContextMenu(...)` | 消息右键菜单 |

> `MaterialState` 三档（`@ohos.arkui.uiMaterial.d.ts` 原文实读）：
> `DEFAULT=0` —— Dialog / Toast / AlphabetIndexer 在**没设背景色/模糊/阴影**时默认开；其他组件由应用决定。
> `ENABLE=1` —— 在 DEFAULT 基础上**额外**给 ChipGroup/Chip/Select/Menu/Toggle/SegmentButton/Slider/`bindSheet`/SelectionMenu 默认开，
> 且**材质样式优先于组件自设的背景色/模糊/阴影/边框**。
> `DISABLE=2` —— 任何组件都不开，即便显式设参数也不生效。
> ⇒ **默认（不加 metadata）= DEFAULT 档**；要「关掉」必须加 `disable`（加 `default` 等于没加）。

**处理**：**本轮不改**。这是**外观 + 功耗**变更，必须由用户拍板（§9 问题 1）。

### 3.2 命中 ②：`cl.arkui.4`（7.0.0.20，起始 API 15）—— 表单类组件触摸**热区**最小高度 28vp → 32vp

涉及 `Button` / `Button 模式的 Toggle` / `Select` / `Chip` / `ChipGroup`。
**热区变大 ≠ 视觉变大**；不想要可 `.responseRegion(undefined)` 重置为与组件实际大小一致；
自定义了高度/热区的**随自定义生效**。

命中点：全仓源码树实读 **52 处 `Button(`**（`Select` / `Chip` / `ChipGroup` / `Toggle` 零命中）。
**风险低**（只影响点击热区，不影响布局尺寸）⇒ **只回归目视确认，不改代码**。

### 3.3 命中 ③：`cl.arkui.1`（7.0.0.19，起始 API 12）—— 内置文本的组件**文本样式优化**

三种场景，全部**默认优化**（无需改代码即生效）：

1. **孤字换行**：中文换行后不再出现"孤字单独一行"（上一行尾部文字跟到第二行）。
2. **小语种行高**：藏语 / 缅甸语行高自动调整，不再重叠截断。
3. **单词换行 → 音节换行**：英文等长单词按音节换行并用连词符连接，不再把词截断。

涉及面极广：`bindPopup` / `bindTips` / `showToast` / `openToast` / Menu / MenuItem / Slider / Select /
`showAlertDialog` / `showActionSheet` / `showActionMenu` / `showDialog` / Search / Hyperlink / Marquee / TextClock /
Badge / Chip / ChipGroup / SegmentButton(V2) / `bindSheet` / Dialog / 日期时间文本 picker / CalendarPickerDialog。

命中点：`showAlertDialog` ×4、`bindSheet`、`bindMenu`、`bindContextMenu`（同上表）。
官方适配指导明确点出：**即使应用没适配小语种，用户把系统语言切成藏 / 缅语也会受影响。**
**处理**：只回归，不改代码（属"显示更正确"，无逻辑面影响）。

### 3.4 零命中（逐条读过，本仓无对应写法）

| 变更 | 本仓读数 |
|---|---|
| `cl.arkui.1`（7.0.0.20）`@ReusableV2` 复用属性支持动态 reuseId | **零 `@ReusableV2`** |
| `cl.arkui.3`（7.0.0.20）鼠标事件 `rawDeltaX`/`rawDeltaY` 返回值变更 | **零 `rawDelta`** |
| `cl.arkui.1`（7.0.0.21）`LayoutPolicy.matchParent` 单方向布局行为变更 | **零 `LayoutPolicy`** |
| `cl.arkui.1`（7.0.0.22）`WithTheme` 相关组件行为变更 | **零 `WithTheme`** |
| `cl.arkui.2`（7.0.0.22）ArkUI 接口新增「仅支持 Stage 模型」约束 | 本仓是 Stage ⇒ **正面**，无需改 |
| `cl.arkts.1`（7.0.0.18）JSVM 基于上游 Chromium/v8 **132 → 144** | Web 内核层，应用侧无需改 |
| `cl.arkts.1`（7.0.0.19）`ConvertXML.fastConvertToJSObject` 丢同级 text 节点 | **零 `convertxml`** |
| `cl.global.1`（7.0.0.21）notofonts 蒙古 / 天城 / 缅甸字体升级、部分数学符号变大 | 字体层，随系统，无代码面 |
| `cl.arkts.1`（7.0.0.24）JSVM **Wasm 解释器使能** | `--jitless` 下 wasm **不再直接报错** ⇒ **潜在利好**，非缺陷（本仓 `jitless` 是既有约束，见 `docs/70`） |

---

## 4 API 26 增量面逐条评估

扫描范围：编译 SDK 的 `openharmony\ets\api\**\*.d.ts` + `openharmony\ets\component\**\*.d.ts`，
共 **285 个文件、4033 条 `@since 26.0.0`**。按文件分布 Top（供后人复查）：
`@ohos.multimedia.image` 210 / `@hms.security.did` 146 / `permissions` 141 / `common` 129 /
`@ohos.multimedia.media` 124 / `@ohos.multimedia.camera` 84 / `@ohos.window` 51 /
`@ohos.arkui.UIContext` 48 / `component/enums` 43 / `component/web` 41 /
`@ohos.arkui.uiMaterial` 37 / `@ohos.data.relationalStore` 37。

按「与本仓相关度」分级。**收益 / 代价 / 是否需真机 / 是否影响三端**四列齐全。

### 4.1 值得接入（**推荐**，2 条）

| 候选 | 落点 | 收益 | 代价 / 风险 | 需真机 | 影响面 |
|---|---|---|---|---|---|
| **`window.setPreferredOrientationWithResult()`** + `OrientationExecutionResult{APPLIED/IGNORED/PENDING}` | `platform\src\main\ets\window\WindowRegistry.ets` 的 `followScreenRotationOnHandheld()`（现用 `setPreferredOrientation(...).then()`，**拿不到执行结果**） | 拿到**真实执行结果** ⇒ 能把「系统旋转锁定 ⇒ IGNORED」与「已生效 ⇒ APPLIED」分开，口径与 `docs/102` 的 `AUTO_ROTATION_RESTRICTED` 语义对齐；排查"旋转锁定时到底发生了什么"不再靠猜 | 需 **target≥26 且设备 API 26**；手持档多为 API 24 ⇒ 必须 `deviceInfo.apiAvailable(26)` / try-catch 守卫，**PC 档走不到这条分支** | 是（手机 + 平板） | 手持档（PC 不变） |
| **`@ohos.arkui.components.ContainerReader`**（全 13 条 `@since 26.0.0` + `@stagemodelonly`；`ContainerReaderInfo{size,widthBreakpoint,heightBreakpoint}` + `BreakpointOptions`） | 设置页「手机横屏多项排布」/ 插件市场「每行 2 / 3 / 4 个」的断点判定 | **组件级容器宽度断点** —— 现在这类判断走 `readDeviceFacts().form` + 窗口宽度，是"全局档位"；组件级断点能按**实际可用宽度**自适应（折叠屏 / 分屏 / PC 窗口缩放） | 全 26.0.0 API ⇒ 需守卫；且会**改布局逻辑**，PC 档同样吃到 ⇒ 回归面大 | 是（手机 / 平板 / 折叠屏） | 三端（**PC 档也会变**） |

> **状态（2026-10-11 追加）**：第 1 条 **`setPreferredOrientationWithResult` 已接入**（用户拍板
> 「两个都接入」；落点 / 守卫 / 回退臂 / 日志口径见 **§13**）。第 2 条 `ContainerReader` **仍未接入**，
> 理由不变：它会改布局判定路径（PC 档同样吃到）、回归面大，且需折叠屏 / 分屏真机。
> 收原始两条列为「候选」的理由（保留作历史）：① 改的是既有可用功能的判定与布局路径，属「改行为」，
> PC 档必须不被改坏；② 都需 API 26 设备真机验证，而平板（API 24）本轮未连接。

### 4.2 候选但**本轮不做**（有明确理由，不是"忘了"）

| 候选 | 为什么不做 |
|---|---|
| `@ohos.arkui.uiMaterial`（37 条，全 26.0.0）：`Material{empty}` / `ImmersiveMaterial` / `isImmersiveMaterialSupported()` / `MaterialInfo` / `getGlobalMaterialLevel()` | 见 §5（材质路线取舍）与 §9 问题 1。**`HarmonyMaterial.IMMERSIVE_ENABLED` 保持 `false`** |
| `component/common.d.ts` 新增 `.systemMaterial(material)` 通用属性（26.0.0） | 同上；它是"组件级关闭材质"的唯一抓手，主力开关还是 metadata（§3.1） |
| `@ohos.window` 其余：`setFloatNavigationAvoidAreaEnabled` / `MaximizeOptions`+`maximizeWithOptions` / `WindowPostureMode{DESKTOP_MODE}` / `getAllWindowLayoutInfo` / `setTouchableAreas` / `setWindowMaskWithAlpha` / `setImageForRecent` / `onApplicationFocusStateChange` / `TYPE_FLOAT_NAVIGATION=5` | `setFloatNavigationAvoidAreaEnabled` 与 `docs/133` / `docs/134`「三键区压住顶栏按钮」同族，但那两处**已按窗口状态变化重放修好**；其余与 PC/手持现有姿态模型不匹配，**引入即改行为** |
| `component/web.d.ts` `WebKeyboardAppearanceMode`（`NONE_IMMERSIVE/IMMERSIVE/LIGHT_IMMERSIVE/DARK_IMMERSIVE`）+ `keyboardAppearance()`（26.0.0）、`scrollbarLayoutPolicy` / `enableScrollDirectionalLock` / `enableFullscreenVideoOverlay` / `enableMediaNetworkProxy` / `aiSessionOptions` | 软键盘沉浸与 `docs/130` 小白条沉浸同族；但 `Web` 是全仓唯一渲染面（`WebApp.ets`），**改它等于改整页观感**，且全 26.0.0 ⇒ 需守卫与三端回归。列为下一轮候选 |
| `@ohos.arkui.UIContext` `SmartGestureController` + `*ActionProposal` + `GestureHandlingResolution` + `registerMonitor`、`InputEventMonitor`、`openOrderOverlay`、`setCustomCursor`、`getSizeLimitation` | 与手持档「左右手势划一下直接回桌面」同族（`check-handheld-back` 门禁）；但 `registerMonitor` 契约未通读，**先确认契约再谈**，否则可能把已修好的手势链改坏 |
| `@ohos.arkui.components.SelectionContainer`（全 26.0.0）+ `SelectionContainerTextJoinStyle` / `SelectionContainerMenuOptions` | 自定义文本选择菜单（跟随 DSHM 主题）；本仓只用了 `copyOption(CopyOptions.LocalDevice)`（`MarkdownRenderer.ets` / `NativePrimitives.ets`），收益是观感，**非缺陷** |
| `@ohos.file.fs` `listFileExt` / `listFileExtSync` + `ListFileExtOptions{recursion,listNum,fileFilter}`、`mmap` 系列 + `FileMapping` + `MappingMode`、`UNCACHE` | `listFileExt` 是 glob 的正规替代（`docs/108` 有 glob 静默失败史），但**会改搜索路径** ⇒ 必须与 `tools/check-fs-fence.mjs`（文件访问范围闸门：允许面 = 应用沙箱 ∪ `~/`，其余读写都拒）**一起评估**，否则可能绕开闸门 |
| `@ohos.resourceschedule.backgroundTaskManager`（27 条）：`requestAuthFromUserByDialog` / `checkSpecialScenarioAuthResult` / `ContinueTaskSuspendReason` / `SuspendMessage` / `ContinuousTaskDetailedCancelReason` / `MODE_NEARLINK=14` | 本仓跑 `dataTransfer` 保活（`KEEP_BACKGROUND_RUNNING`）⇒ 属**诊断向**候选；不解决已知缺陷 |
| `@ohos.app.ability.childProcessManager`（`isArkChildProcessSupported` / `isNativeChildProcessSupported`，全 26.0.0 + `@stagemodelonly`） | 语义与三处分档判据 `shimRunnable()` **同义**，但**只对 target=26 且 OS≥26 可用**，**不能替代分档判据**（手持档多为 API 24，且判据本身是"随包假壳 spawn 不起来 ⇒ 接管"的行为判定，不是能力探测）。**只登记，不接线** |
| `@ohos.arkui.StateManagement`、`component/lazy_for_each.d.ts`（14 条）+ `LazyForEachOptions` / `LazyForEachReleaseStrategy` / `LazyForEachCustomComponentFreezeMode`、`arkui\LazyLayoutAlgorithm.d.ts`（16 条）、`ArkLazyWaterFlowLayout`（12 条）、`ReusableMemOptStrategy` | **全仓零 `LazyForEach`** ⇒ 只能作为"性能向登记"，无现成落点可接 |
| `@ohos.app.ability.appMemoryOptimizer`（`evictFilePages` / `evictModuleFilePages`）、`@ohos.UiTest`（29）、`@ohos.i18n`（65）、`@ohos.data.relationalStore`（37） | 无对应使用面（本仓无 UiTest 依赖、无 relationalStore 用例；i18n 走 ArkUI 文本层） |

### 4.3 明确排除（与产品无关）

`@ohos.multimedia.image`（210）/ `.media`（124）/ `.camera`（84）/ `.audio`（57）、
`@hms.security.did`（146）、`@hms.phoneService.aod.*`（117）、`@hms.collaboration.accessoryAccessManager`（84）、
`@ohos.nearlink.*`（正 80+60+69 = 200+）、`@hms.ai.A2A`（76）、`@ohos.enterprise.*`（70+39）、
`@ohos.window.floatView`（61）、`@ohos.busManager.serial`（46）、`@ohos.FusionConnectivity.ranging`（41）、
`@ohos.geoLocationManager`（34）、`@ohos.security.cert`（53）/`.cryptoFramework`（40），
以及 `graphics3d` / `contact` / `telephony` / `@ohos.net.http`·`connection`·`webSocket`·`web.webview` / `@ohos.hilog`。
**理由**：本仓是"把 dsh 运行时搬到鸿蒙 arm64 上自足运行"的客户端，不涉及 AOD / 星闪 / 企业管控 / 相机 / 位置 /
串口总线 / 3D 图形；这些模块的增量对功能面零收益，接线只会增加体积与攻击面。

---

## 5 两条材质路线的取舍（`uiMaterial` 26 档 vs `hdsMaterial` 23 档）

| 路线 | API 门槛 | 引入代价 | 结论 |
|---|---|---|---|
| `@ohos.arkui.uiMaterial`（**26.0.0**，37 条） | 需 target=26 且设备 API 26 | 小（只是浮层观感开关 + 一处 metadata） | **已开**（2026-10-11 拍板 ⇒ `module.json5` 的 `UIMaterial.state = enable`，见 §13；API 24 设备上被平台忽略） |
| `@hms.hds.hdsMaterial`（**6.1.0(23)**，不需抬 target） | API 23 即可 | 大：要引入 `HdsNavigation` 家族（`@kit.HDSKit`）替换现有导航壳 | **不做**：本仓零 `HdsNavigation`，为材质换整个导航层不划算 |

⇒ 若用户要"沉浸光感"，走 `uiMaterial`（26 档），**不要**走 hds 那套。

---

## 6 订正与推翻（把上一轮的错结论清掉，避免后人照错抄）

**① `@ohos.deviceInfo.apiAvailable(version)` 不能替代 `dshcompat` 的 `checkVersion()`。**
上一轮曾把它列为「API 26 新增的 checkVersion 替代」。**语义无关、不可互替**：
`apiAvailable()` 判的是**设备 OS 版本**（"这台设备够不够 26"）；
`dshcompat\…\CompatIndex.ets` 的 `checkVersion()` 判的是**上游 dsh 核心包（Host）的协议版本**
（`SUPPORTED_VERSIONS` = `0.2.1-alpha.2 … 0.1.2-rc.1` + `PROTOCOL_SKELETON` 三端点探测）。
一个问"系统够不够新"，一个问"对面 Host 的协议够不够"，**两回事**。

**② 上一轮记的「`radius: 0` 由『无阴影』改为『有阴影无模糊』」这条行为变更，在官方 changelog 里查无此条。**
本轮把 7.0.0.17 / .18 / .19 / .20 / .21 / .22 / .24 的 ArkUI 变更标题逐条列出核对，**没有**"阴影半径规格"这一条
（7.0.0.20 只有 4 条：`@ReusableV2` 复用 / 弹层沉浸材质 / 鼠标 rawDelta / 触摸热区）。
⇒ 该结论**降级为"未在官方 changelog 中检到的推断"**。处理方式：
`HarmonyElevation` 的注释补一句**防御性**提示「radius 不要写 0」，并注明来源不是官方 changelog。
（本仓唯一 `.shadow()` 调用点 `NativePrimitives.ets:361` 经 `shadowOf()` 出来的两个取值都 > 0，**现有代码不受影响**。）

**③ 「`EXEC_CLI_TOOL` 可替代 域权限」无证据，不要写成结论。**
API 26 在 `PermissionDefinitions.json` 里**新出现**一批 `availableType: SYSTEM` 权限，逐条实读：

| 权限 | grantMode | availableLevel | since | provisionEnable |
|---|---|---|---|---|
| `ohos.permission.EXEC_CLI_TOOL` | system_grant | system_basic | 26.0.0 | true |
| `ohos.permission.QUERY_CLI_TOOL` | system_grant | system_basic | 26.0.0 | true |
| `ohos.permission.ACCESS_FUNCTION` | system_grant | system_basic | 26.0.0 | true |
| `ohos.permission.AGENT_FILE_ACCESS` | **user_grant** | system_basic | 26.0.0 | true |
| `ohos.permission.LOAD_NATIVE_LIBRARY` | system_grant | system_basic | 26.0.0 | **false** |
| `ohos.permission.REVOKE_FILE_ACCESS_PERSIST` / `GET_FILE_ACCESS_PERSIST` | system_grant | system_core | 26.0.0 | true |

对照本仓已审批的两条：`FILE_ACCESS_PERSIST`（normal / since 11）、`ALLOW_EXTERNAL_NATIVE_CODE`（system_basic / since 23）。
`EXEC_CLI_TOOL` 是"官方 CLI 工具执行"的口子，**看起来**比 域权限 更对口本仓的 bash / 工具链诉求，
但它是 **`availableType: SYSTEM`**（面向系统工具 / CLI 工具包），**能否随应用 ACL 审批到本仓未知**。
⇒ 文档里只能写「**待向 AGC / 官方确认能否申请**」，**不许**写成"能替代 域权限"。
（另：域权限 的**真作用不是文件便利，而是 SELinux 应用域** —— 撤掉它宿主域从
`u:r:develop_tools_debug_hap:s0` 掉到 `u:r:debug_hap:s0`、连应用数据区里的 ELF 都 execve 不了，见 `docs/143` / `docs/144`，
这条已实证、不能混淆。）

---

## 7 「不做」清单与理由（本轮拍板，逐条有依据）

1. **`HarmonyMaterial.IMMERSIVE_ENABLED` 保持 `false`** —— 外观 + 功耗变更（官方明确"耗大量 GPU"），
   且默认 `DEFAULT` 档已经会让 §3.1 那 4 处 `showAlertDialog` 外观变化。**先问（§9-1）。**
2. **不加 `module.json5` 的 `module.metadata`（`ohos.arkui.UIMaterial.state`）** —— 加 `default` 等于没加；
   加 `disable` 会关掉文本选择菜单的默认材质。**这是替用户做外观选择的动作，不做。**
3. **`coreVersion` 不升** —— 本轮不进核心树（`docs/146` 的 `+dshm.32` 不变）。
4. **不实现 §4.1 的两条候选** —— 都会改既有可用功能的判定 / 布局，且需 API 26 真机（平板未连接）。
5. **不引入 `hdsMaterial` / `HdsNavigation`** —— §5。
6. **不改 `compatibleSdkVersion`** —— 用户明确"保持 6.1.1(24)"。

---

## 8 决策文案口径同步（**2026-10-11 追加：已完成**）

下列位置原写着"target 待拍板 / 保持 24"，与抬 target 后的现状不一致。**已就地同步**：

| 位置 | 改法 | 行数变化 |
|---|---|---|
| `README.md`「构建」小节的「SDK 版本口径」段 | 改写成「`compatible` 固定 6.1.1(24) / `target` 已抬 `26.0.0(26.0.0)`」+ 3 条行为变更 + 沉浸材质“产品决定” | 就地 3↔3 |
| `docs/parity-matrix.md`：「API 固定 6.1.1(24) 的决策已入档」与「沉浸光感暂不可用」两处 | 改为「target 已抬 26；仍不启用是产品决定」 | 就地 2↔2 |
| `docs/device-validation.md` D4 的「暂保持 24，沉浸光感因此不可用」 | 改为「后 `targetSdkVersion` 已抬到 26（`docs/147`）」 | 就地 3↔3 |
| `docs/110` §5.1 / §6、`docs/142` §6 | **不改历史拍板本体**，各加一行日期化「2026-10-11 后续变更」注记 | +2 / 0 |

改的都是**就地替换**（不动行数）或**加注记**（不动被引行），故不牵动 `docs/NN:行号` 引用；
改后 `node tools/check-doc-refs.mjs` 仍 exit 0。

- `README.md` 顶层「当前 API 口径」段
- `docs/110`（`compatibleSdkVersion` 拍板档）的「target 与 compatible 一致」表述
- `docs/parity-matrix.md` 的 API 口径行
- `docs/142` §6、`docs/device-validation.md` 的 target 口径行

---

## 9 待用户拍板的两件事（**2026-10-11 已拍板：问题 1 取 `enable`、问题 2 三条全不额外适配**）

> **拍板结果与落实**（原文保留在下面作决策依据）：
> · 问题 1 ⇒ **接入**，档位取 **`enable`**（官方示例值；要改档只动 `module.json5` 那一行 `value`）。
> · 问题 2 ⇒ 维持建议：`cl.arkui.4` 热区只目视回归不改代码、`cl.arkui.1` 文本换行不改。
> 具体接线见 **§13**；用户原话是「两个都接入，弄完推送手机端我测试」。

### 问题 1：`ohos.arkui.UIMaterial.state`（应用级沉浸材质开关）加不加？

| 选项 | 效果 | 代价 |
|---|---|---|
| **不加**（= `default`） | Dialog / Toast / AlphabetIndexer / 文本选择菜单**默认开沉浸材质** ⇒ 4 处 `showAlertDialog` + `bindSheet` / `bindMenu` / `bindContextMenu` 外观会变 | 外观变化（用户可能不喜欢）、浮层耗 GPU |
| 加 `enable` | 在 `default` 基础上**额外**给 Chip/Select/Menu/Toggle/Slider/`bindSheet`/SelectionMenu 默认开，且**材质优先于自设背景色** | 外观变化更大，可能盖掉现有 `$r('sys.color.*')` 配色（`CredentialSheet.ets` 用了 `sys.color.background_secondary`） |
| 加 `disable` | **全关**，与抬 target 前外观一致 | 拿不到官方浮层观感（但本仓本来就 `IMMERSIVE_ENABLED=false`，一致） |

### 问题 2：3 条命中的行为变更，要不要顺手适配？

- `cl.arkui.2` 弹层外观（同问题 1 的开关）
- `cl.arkui.4` 触摸热区 28 → 32vp：**建议只回归目视，不改代码**（风险低）
- `cl.arkui.1` 文本换行优化：**建议不改**（显示更正确，无逻辑面影响）

---

## 10 回归验证计划（抬 target 之后）

1. **重编 debug** 并读产物 `module.json`：确认 `minAPIVersion` 仍 = **60101024**、`targetAPIVersion` = **260000026**。
   （构建必须带四行 env + 先跑 `node tools/place-host-app.mjs`；`assembleApp` 不吃 `--mode module`。）
2. **仓内门禁**（CI 那批，只需仓库内文件）：`assert-cli-shim` / `check-parity` / `assert-exec-fix` /
   `check-fs-fence` / `check-vm-bash` / `check-market-bridge` / `check-profile-pnpm-bridge` /
   `check-decor-button-mode` / `check-doc-refs`（本档 + 索引）等。
3. **需核心树的门禁**（`dist/core/work/dsh-core-0.2.1-alpha.2+dshm.32`）：`check-core-openharmony-patches` /
   `assert-resfile-sync` / `check-resfile-core-zip` 等。
4. **真机三段**：
   - **PC 档（API 26，必须最先做）**：`hdc install -r`（**禁止 uninstall**）⇒ 工具调用 / 侧边栏 / 终端 /
     工作区文件**全部照旧**；§3 三条目视一遍（4 处弹层外观、按钮热区、文本换行）。
   - **手机档（API 26）**：同上 + 手持档专属（左右手势返回、跟屏旋转、市场安装）。
   - **平板档（API 24，关键）**：装得上 = §1 那条"唯一未实证"的实测；装后冒烟各主要功能。
5. 三端任一项 ok → fail，当场修，不允许延后（回归纪律）。

---

## 11 一句话总结

抬 `targetSdkVersion` 到 `26.0.0(26.0.0)`、`compatibleSdkVersion` 保持 `6.1.1(24)`，
**不丢安装面**（产物 `minAPIVersion` 仍 60101024），代价是启用 3 条 ArkUI 行为变更
（弹层沉浸材质 / 触摸热区 / 文本换行）；
API 26 的 4000 余条增量里对本仓**真正值得接入的只有 2 条**（窗口朝向带结果的设置、组件级容器断点），
两条都要 API 26 真机 + 守卫，且会改既有行为。**2026-10-11 用户拍板「两个都接入」** ⇒
`setPreferredOrientationWithResult` 已接入（§13），`ContainerReader` 因「会改布局判定路径 + 回归面大」
仍留候选（§4.1 状态行）；外加应用级 `UIMaterial.state = enable`（§13）。

---

## 12 交叉核对：另一会话给出的 API 26 清单（2026-10-11 追加）

另一会话给出过一份「API 26 值得接入」清单（窗口形态 / ArkUI 输入 / 文件 I/O / 网络 四类）。
本轮按 **SDK `.d.ts` 原文 + `PermissionDefinitions.json` + 本仓落点实测** 逐条核过。
结论：**与 §4 重叠约 2/3**（同一批 API，只是口径不同），差异集中在三处 ——

### 12.1 两条被「拿不拿得到」挡死（§4 未列，本轮新发现）

| API | 26.0.0 | 门槛（实读） | 裁定 |
|---|---|---|---|
| `Window.setImageForRecent` | 是 | `ohos.permission.MANAGE_RECENT_SNAPSHOT`（**system_basic** / system_grant / since 26） | **不接**：要 ACL 审批，收益仅多任务快照图 |
| `Window.setTouchableAreas` | 是 | `ohos.permission.SET_WINDOW_TOUCH_AREAS`（**system_basic** / system_grant / since 26）；文档另写 `@throws 201`「非系统应用调用即拒」，且**「窗口矩形变化后设置失效」** | **不接**：权限面 + 语义脆弱（窗口一变就要重设） |

> 本仓发布 profile 实读（`D:\desktop\release\dshmRelease.p7b`）：
> `apl=normal`、`allowed-acls=[ALLOW_EXTERNAL_NATIVE_CODE, FILE_ACCESS_PERSIST]`
> ⇒ 新增 `system_basic` 权限＝再走一遍 ACL 审批，不是「接线即可」。

### 12.2 一条口径错：`onBarRectChange` 不是应用顶栏

`onBarRectChange(Callback<Frame>)`（`@since 26.0.0`）声明在 `UIContext.d.ts` 的
**`export interface AtomicServiceBar`**（同族 `setIconColor` / `getBarRect`），带 **`@atomicservice`** 标签 ——
它是**元服务**顶栏的矩形回调，**不是**应用窗口标题栏 / 三键区。
本仓 `app-feature=hos_normal_app`（普通应用）⇒ **不适用**。
本仓顶栏与三键让位走的是另一族：`getTitleButtonRect()`（真机恒 0/0，见 `WebApp.ets` 的 `diag-decor-top` 注释）
＋ `window.on('windowStatusChange')` ＋ `on('avoidAreaChange')` ＋ `setWindowDecorVisible`
（`docs/133` / `docs/134` / `docs/138`）。⇒「对自绘顶栏和三键配色链路有价值」**不成立**。

### 12.3 其余条目＝§4.2 的「登记但不接线」（本轮把落点也查明，理由更硬）

| 对方候选 | 落点实测 | 裁定 |
|---|---|---|
| `setFloatNavigationAvoidAreaEnabled` | 与 `docs/133`/`docs/134` 同族，但那两处**已用「窗口状态变化重放」修好** | 不接（引入即改行为） |
| `onApplicationFocusStateChange` | 本仓生命周期桥在 `platform\…\HostEvents.ets` / `HostStore.ets`（走 host 事件），无此回调落点 | 登记 |
| `maximizeWithOptions` / `setSupportedWindowModes` / `isInWindowPostureMode` / `onWindowPostureModeChange` / `WindowPostureMode{DESKTOP_MODE}`（均 26.0.0） | PC 档姿态模型已定（`docs/136` / `docs/138`） | 登记（引入即改 PC 档行为） |
| `addLocalInputEventMonitor` / `removeLocalInputEventMonitor`（26.0.0） | 能 **BLOCK** 原始输入事件；手持档返回手势已按 ArkUI 手势链修好（`docs/132` / `check-handheld-back`） | 不接（风险＞收益） |
| `enableEventPassthrough` / `openOrderOverlay` / `setCustomCursor` / `setTextSelectionClearPolicy` | 本仓是**单一全屏窗口**、零 `OverlayManager`、渲染面是 `Web`（光标来自页面 CSS） | 无落点 |
| `SmartGestureController`（26.0.0：`enableSmartTapAndSlideGestures` + `registerMonitor`） | 与手持返回手势同族；`BaseGestureHandlingProposal` / `GestureHandlingResolution` 契约未通读 | 登记（先通读契约） |
| `mmap` / `FileMapping` / `listFileExt(Sync)` | ArkTS 侧 `fileIo` 只落在 11 个文件、**全是小文件**（picker / 托盘 / 设置）；宿主的 fs 在核心树（Node 层），够不着；`listFileExt` 与 `tools/check-fs-fence.mjs`（文件访问范围闸门）有冲突面 | 不接 |
| 网络：`requestSync` / 结构化 `queryParams` / `usingSocks5Proxy` / `enablePartialChain` / WebSocket `openInfo`·TLS 最低版本 | ArkTS 侧**刻意不走 ArkTS HTTP 栈**（`NodeRuntime.ets` 实测 `http.createHttp()` 15 s 全超时 ⇒ 改 TCP 直连判活），宿主网络走核心树 Node 垫片 ⇒ 这些开关落不到真正跑网络的那一层 | 不接（`requestSync` 还会阻塞 UI） |

### 12.4 净结果

对方清单**没有新增任何一条值得接入的项**；§4.1 的两条（`setPreferredOrientationWithResult` / `ContainerReader`）
仍是唯一候选，其中 **`setPreferredOrientationWithResult` 是两份调研唯一共同点名的那一条**。

---

## 13 本轮落地的两项接入（2026-10-11 拍板「两个都接入」的执行记录）

用户原话：「**两个都接入，弄完推送手机端我测试**」。两项分别落在**平台层**与**打包配置**，
**互不相干、可各自回退**。四项事实先给结论，细节在后：

1. **PC / 2in1 档零改动**：朝向那条在函数第一句就按 `form` 早退（`PHONE`/`TABLET` 之外直接 `return`），
   材质那条走的是 `module.json5` 的 **entry 级 metadata** —— PC 档吃到的只是「API ≥ 26 时浮层默认材质」，
   与 §3.1 已登记的 `cl.arkui.2` 行为变更**同一件事**，不是本轮新引入的行为。
2. **API 24 设备（6.1.1 平板）两条都退化成"零行为"**：朝向走无回执旧路径（本来就有的那条），
   材质被平台忽略（`targetAPIVersion` 满足、但**设备能力**不满足 ⇒ 官方「对不支持传感器旋转的设备 /
   非 26 设备不生效」）。
3. **产物口径未变**：`minAPIVersion` 仍 60101024、`targetAPIVersion` 仍 260000026、权限仍 11 条
   （⚠️ **2026-10-15 勘误（见 `docs/162`）**：权限条数是**当轮**读数；2026-10-14 起恒 8 条）。
4. **coreVersion 未升**（两项都不在核心树里 ⇒ 按 `AGENTS.md` 的口径不进核心树就不升）。

### 13.1 `window.setPreferredOrientationWithResult()` ⇒ 手持档朝向（`+0 权限`）

| 项 | 内容 |
|---|---|
| 落点 | `platform\src\main\ets\window\WindowRegistry.ets` 的 `followScreenRotationOnHandheld()` |
| 判据 | `deviceInfo.apiAvailable('26.0.0')` ⇒ `true` 走**带回执**路径，`false` / 抛错走**无回执旧路径** |
| 设备 | 真机 `62T0225B18039433`（Mate80，API 26）；平板（API 24）待验 |
| 回退臂 | 结果 API 抛 `801` / `1300002` / `1300003` ⇒ 自动退回 `setPreferredOrientation(...).then()`，**"能跟屏"这件事本身不丢** |
| 日志口径 | `APPLIED` → "已生效"；`IGNORED` → "被系统忽略（旋转锁定开启 / 不支持传感器旋转）"；`PENDING` → "待生效" |
| 影响面 | 手持档；PC/2in1 **走不到这条分支** |

**为什么是双路径而不是直接换掉**（三条都是实读 SDK 原文得到的约束，写进代码注释了）：

- `setPreferredOrientationWithResult` `@since 26.0.0`、`@stagemodelonly`、`@atomicservice`、
  `@syscap SystemCapability.Window.SessionManager`、**无权限**；
- **`deviceInfo.apiAvailable()` 自己也是 `@since 26.0.0`** ⇒ 在 API 24 设备上这个属性**不存在**，
  直接调用会 `TypeError` ⇒ 守卫必须**包在 try 里**（返回 false = 走旧路径），**不能**只看返回值。
  这是本轮最容易写错的一处：把它写成 `if (deviceInfo.apiAvailable('26.0.0'))` 会让 API 24 平板在
  启动时抛异常（虽然外层 try 会兜住，但会打一条误导性的"异常"日志）；
- 旧版 `.then()` 的成功**只表示"调用被受理"**，系统旋转锁定开启时平台是**受理但忽略** ⇒ 旧路径照样
  打"跟随屏幕旋转"，与事实相反。这正是本轮接入的**唯一实际收益**：把 `docs/102` 那条
  「锁定就不转、解锁才转」从"靠现象反推"变成"有回执可查"。

### 13.2 `ohos.arkui.UIMaterial.state = enable` ⇒ 应用级沉浸材质（`+0 权限`）

| 项 | 内容 |
|---|---|
| 落点 | `entry\src\main\module.json5` 的 `module.metadata`（**新增该数组**，与 `EntryBackupAbility` 自己的 `ohos.extension.backup` 无关） |
| 取值 | **`enable`**（官方示例值）。要改档只动那一行 `value`：`default` / `enable` / `disable` |
| 生效条件 | **设备 API ≥ 26**；API 24 设备上被平台忽略 |
| 影响面 | **原生浮层**（Dialog / Menu / Sheet / 文本选择菜单）；渲染面是 Web 画布 ⇒ 不给 Web 界面换皮 |

三条必须记住的语义（写进 `HarmonyTheme.HarmonyMaterial` 注释了，都是官方原文）：

- 三档**不是"开 / 关"三档**：不配 = `default`（Dialog / Toast / AlphabetIndexer / 文本选择菜单默认开）；
  `enable` = 在 `default` 之上**额外**覆盖 Chip / Select / Menu / Toggle / Slider / `bindSheet` /
  SelectionMenu，且**材质优先于组件自设的背景色 / 模糊 / 阴影 / 边框**；`disable` = 全关，且
  **会连带封死**主动调 `systemMaterial()` —— 它不"只是默认不开"。
- **光感强弱不是应用定的**：官方原文「同一材质的效果，会受到系统设置应用中**沉浸光感**配置项的影响」
  ⇒ 表现随用户系统设置变化，不随本仓代码变化。排查"为什么没有毛玻璃"要先看系统设置。
- **只有 entry 类型 module 的这条 metadata 生效**（官方原文）。

**顺带订正的代码注释**：`appstate\src\main\ets\ui\HarmonyTheme.ets` 的 `HarmonyMaterial`
原写「`IMMERSIVE_ENABLED` 保持 `false` 是产品决定」⇒ 已改为实况（`true` + 上表三条语义）。
该常量**全仓零读点**（只被 `appstate\src\main\ets\Index.ets` 转导出），故改它**不产生任何行为差异**，
纯"注释与事实对齐"。

### 13.3 本轮验证（已做 / 未做，如实记）

| 项 | 结果 |
|---|---|
| 编译 | `BUILD SUCCESSFUL in 19 s 392 ms`（`73 tasks: 42 executed, 31 up-to-date`） |
| 产物读数 | `minAPIVersion` 60101024（**未变**）/ `targetAPIVersion` 260000026 / `metadata = [{name:"ohos.arkui.UIMaterial.state",value:"enable"}]` / `deviceTypes = phone,tablet,2in1` / 权限 11 条（⚠️ 当轮读数；2026-10-14 起恒 8 条，见 `docs/162`） |
| HAP | `entry-default-signed.hap` **401,798,675 B**（比接入前 401,794,390 B 多 **4,285 B** ⇒ 就是 `module.json` 里多出来的那段 metadata） |
| 仓内门禁 | 21 条 CI 门禁 + 13 条核心树门禁**全绿**（含 `check-doc-refs` / `check-decor-button-mode` / `check-fs-fence` / `check-market-bridge` / `assert-resfile-sync` / `check-core-openharmony-patches`） |
| 装机 | 手机 `62T0225B18039433` `hdc install -r` **覆盖安装成功**（**未 uninstall**，会话 / 插件 / 工作区数据不动） |
| **未做** | ① 手机端**功能目视**（用户手动测：浮层材质观感、旋转锁定 / 解锁两种状态下的朝向日志）；② **PC 档回归**（本轮未连接）；③ **平板档（API 24）装机**（§1 那条"唯一未实证"仍未实证，且本轮两项在 API 24 上都是零行为） |

### 13.4 回退办法（任一项要撤，都是一处）

- 撤朝向：把 `followScreenRotationOnHandheld()` 的 `orientationResultApiReady()` 分支去掉，
  直接调 `applyPreferredOrientationLegacy(win, form)`（或整个函数换回 `docs/102` 那版）。
- 撤材质：删掉 `module.json5` 的 `"metadata": [...]` 那段（= 回到 `default` 受默认材质影响），
  或把 `"value"` 改成 `"disable"`（全关）。

### 13.5 顶栏菜单的材质落地（**2026-10-11 追加**，用户复报后）

用户复报：「应用菜单并未跟随系统沉浸光感的强度」。⇒ 在**同一台** PC/2in1（API 26、系统**浅色**）
上补测 **4 条形态**（落点 = 顶栏「应用」菜单内 2880×1920 原图坐标 x700 y470）：

| # | 形态 | (700,470) | (560,430) | 肉眼 |
|---|---|---|---|---|
| 0 | 元数据 `disable`（旧基线，菜单不挂材质） | 165,166,168 | 164,165,167 | 实色浅灰，无材质 |
| 1 | 元数据 `enable`，菜单**不挂** `systemMaterial` | 165,166,168 | 164,165,167 | **与 0 逐像素相同** ⇒ 只翻总闸不够 |
| 2 | `enable` + 菜单挂 `systemMaterial(THICK)`，无 `WithTheme` | 98,100,99 | 70,71,73 | 深色玻璃（浅色系统下**不对**） |
| 3 | 同 2 + `WithTheme(ThemeColorMode.SYSTEM)` | 98,100,99 | 70,71,73 | 与 2 **逐字节相同** ⇒ `SYSTEM` 仍给深色 |
| 4 | 同 2 + `WithTheme(应用当前 themeMode)` | **254,255,255** | 229,229,229 | **浅色玻璃**，条目文字清晰 |

（另测：`colorInvert: true` + `ImmersiveStyle.THIN` ⇒ 连菜单**自身条目的文字**都被糊掉，**弃用**。）

**结论（三条）**：

1. 应用级 `enable` 只是**总闸**，**不会**让 `Menu` 自己变成材质（形态 1 实证）。官方那段
   「`enable` 额外给 `Menu` 默认开」在 2in1 的**子窗**菜单路径上没兑现（`MenuOptions.showInSubWindow`
   在 2in1 默认 `true`）⇒ 必须在**声明点**显式挂 `systemMaterial`。
2. 菜单的**深浅色**由绑定组件的 `WithTheme` 决定（`ContextMenuOptions.colorMode` 默认 `FOLLOW_TARGET`
   = 跟随绑定组件）；`AnchoredColorMode.FOLLOW_SYSTEM` 与 `ThemeColorMode.SYSTEM` 实测都落到**深色**，
   与本机浅色系统不符 ⇒ 取**跟随应用当前外观**。
3. 材质的**强弱**仍由系统「设置 → 沉浸光感」决定（§13.2 那条官方原文不变）；应用侧只能选**档位**
   （`ImmersiveStyle`）与**深浅色策略**。本次档位取 `THICK`（官方 `menu.md` 示例同档）。

**落地**（`entry\src\main\ets\pages\WebApp.ets`，1 处 + 1 行 import）：

- `import { window, uiMaterial } from '@kit.ArkUI';`
- `@Builder MenuTitle(...)`（顶栏「应用」「编辑」两个菜单共用）：
  - 标题 `Text` 外包 `WithTheme({ colorMode: this.themeMode === 'dark' ? ThemeColorMode.DARK : ThemeColorMode.LIGHT })`；
  - `.bindMenu(items, { systemMaterial: new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.THICK }) })`。

**顶栏布局零变化（实测）**：包一层 `WithTheme` 后，真机截图里「应用 / 编辑」的暗字包围盒
`x=[510..648] y=[321..343]` 与改前**逐像素相同**（同一脚本、同一亮度阈值 120）。

**影响面**：

- `MenuTitle` 只在 `if (!this.handheld)` 的 `TopBar()` 内被调用 ⇒ **手机 / 平板档一个字都不受影响**
  （手持档压根不渲染这两个菜单按钮）。
- **未**铺开到 `bindContextMenu`（消息右键菜单）与其它原生浮层 —— 用户只点名了顶栏菜单，其余**留待拍板**。

**回退**：把 `MenuTitle` 还原成 `.bindMenu(items)`、去掉 `WithTheme` 包裹与 `uiMaterial` import
（元数据那行**不用动**）。

**验证**：编译 `BUILD SUCCESSFUL in 12 s 247 ms`；PC/2in1 `86E0226429000417` `hdc install -r`
覆盖安装（**未 uninstall**）→ `aa force-stop` + `aa start` → `uitest uiInput click 571 335` →
`snapshot_display` 取形态 4 读数 254,255,255（见上表）。**未验**：深色外观下的菜单（`themeMode==='dark'`
分支）、移动端回归（本轮零改动，静态可判）。

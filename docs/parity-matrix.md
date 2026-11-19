# 功能对等矩阵（Parity Matrix）· P0

| 项 | 内容 |
|---|---|
| 文档编号 | `docs/parity-matrix.md` |
| 版本 | v1.0 |
| 日期 | 2026-09-14 |
| 状态 | 生效（P0 交付物） |
| 上位文档 | `docs/00-开发任务书.md`（D1）、`docs/20-产品需求与体验规范.md`（D3）、`docs/50-端侧核心运行架构.md`（D6）；本文是《HarmonyOS 多端开发实施计划》P0 的落地台账 |
| 定位 | **逐功能对等台账**：官方 Web 的每一项能力，在 DSHM 里的状态层/界面/协议/四形态落点与状态。**它是"还差什么"的唯一清单**，不是宣传材料 |
| 门禁 | `node tools/check-parity.mjs`（含注入式自检 `--self-test`）。**本文格式坏了或状态注水，门禁会失败** |

---

## 0. 这份文档是什么、不是什么

**是**：

- 官方 Web 能力面的**全量覆盖表**（行集 = 官方 `@deepseek-ai/dsh-client-ui-*` 的全部 38 个包 + `dsh-client-locale` + 端侧独有能力），每一行给出落地文件与四形态状态；
- 缺口登记处：**任何非 DONE 的行必须在 §6 登记**，含原因与下一步。门禁强制这条。

**不是**：

- 不是"最终验收通过"的声明。**本矩阵的 DONE 只表示"实现侧完成"**；真机验收是另一根轴（§1.3），今天整体是 `PENDING`；
- 不是设计文档。设计口径在 D3；协议事实在 D2/D2b；本文只登记**对等状态**。

---

## 1. 状态口径

### 1.1 四个状态 token（只允许这四个）

| token | 含义 | 判据 |
|---|---|---|
| `DONE` | 实现侧完成，该形态下无已知缺口 | §1.2 的八项判据齐备 |
| `PARTIAL` | 部分可用：有真实实现，但缺项 | 必须在 §6 登记缺什么 |
| `BOUNDARY` | **能力边界**：平台/架构不允许，不是缺陷 | 必须在 §6 写明为什么不可做 |
| `TODO` | 未实现 | 必须在 §6 登记下一步 |

### 1.2 `DONE` 的八项判据（计划 §5）

`Protocol` · `State` · `Functional` · `Interaction` · `Responsive` · `Accessibility` · `Validation`

> 第 7 项 `Validation` 在本环境的含义**限定为"可静态验证"**（门禁、门禁自检、单测、协议往返）——**不包括真机验收**。真机验收见 §1.3。

### 1.3 两根轴：实现侧 vs 设备验证

计划 §5（DONE 要八项齐备）与 §20（无真机时允许开发完成、不允许宣称设备验收完成）并不矛盾，前提是把它们**分成两根轴**：

| 轴 | 取值 | 今天的状态 |
|---|---|---|
| **实现侧** | 本矩阵的 `Status` / 四形态列 | 见 §5 统计 |
| **设备验证** | `PENDING` / `PASS` | **`PASS`（2026-10-05：真机 2in1 已多轮验收；逐条见 §3.2 各块与 `docs/device-validation.md`）**。原先这里写"本环境无模拟器、无真机"是 bring-up 阶段的口径，**已不成立**。⚠ 设备验证是**逐条**结论：row 级仍有 `PENDING`（尤其 phone 档专属路径），读单行时以该行自己的口径为准 |

**硬规则**：任何 `DONE` 行都不得被读作"已在设备上验收通过"；报告里必须同时给出设备验证轴的取值。

### 1.4 门禁强制的五条不变式

| # | 不变式 | 防止的注水 |
|---|---|---|
| A | 行集恰好覆盖官方能力面（38 个 `dsh-client-ui-*` + `client-locale` = 39 个 id 各一行），另有 `dshm-` 前缀的端侧独有行 | 漏项、重复项、覆盖越界 |
| B | 状态 token 合法（只允许 §1.1 的四个）；**任一形态列不是 `DONE` 时，整体 `Status` 不得是 `DONE`** | 用整体 DONE 盖住某个形态的缺口 |
| C | 任何非 `DONE` 的行必须在 §6 缺口登记里有对应行；§6 也不得登记矩阵里不存在的 id | 悄悄降级、只留结论不留原因、幽灵登记 |
| D | §5 统计表必须与矩阵**实算**逐项相等（含合计） | 口径不明导致数字对不上（本项目真实发生过） |
| E | `DONE` 的行不得留在 §6 缺口登记里 | 陈旧登记：台账同时说"已完成"和"缺什么" |

> 五条都有**注入式负测试**（`--self-test`；`check-parity` 为 15 个正/负样例）证明会真的失败。
> 另对**真实矩阵**做过一次端到端注入：把 `workflow-run` 从 `TODO` 谎报成 `DONE` 并顺手改对统计数字——
> 门禁仍以「陈旧登记」点名并退出 1（不变式 E 存在的理由：只靠 D 会被"顺手改统计"掩盖）。

---

## 2. 形态口径（四列的定义）

**这里对计划书的四形态做一处更正**，理由是 HarmonyOS 的实际事实：

> HarmonyOS 的 `deviceType` 只有 `phone` / `tablet` / `2in1`（另有 tv/wearable/car），**没有独立的 `PC`**。
> 计划书里的「PC」与「2-in-1」在系统看来是**同一个 `deviceType = 2in1`**，差别在**窗口模式与输入模态**。

因此四列的定义是「设备族 × 窗口/输入形态」，而不是四个设备类型：

| 列 | 判定 | 典型场景 |
|---|---|---|
| **Phone** | `deviceType=phone`，单栏 | 直板机；折叠屏折叠态 |
| **Tablet** | `deviceType=tablet` | 平板竖屏（双栏）/ 横屏（三栏） |
| **PC** | `deviceType=2in1` + 全屏/最大化窗口、键鼠为主 | 电脑模式、台式二合一接显示器 |
| **2-in-1** | `deviceType=2in1` + 自由窗口/悬停态、触摸为主 | 二合一笔记本、折叠屏悬停 |

**两条落地规则**（与 D3 §2.2 一致，本项目不做例外）：

1. **布局决策只看「窗口宽度 + 输入模态」**，不看 `deviceType`：`layoutModeOf(widthVp)` 是唯一入口。一个 2in1 被拖窄到 500vp，必须与手机同构（单栏）；这是"窗口变化时自动切换布局"的实现方式。
2. **`deviceType` 只用于门控系统能力**（系统文件夹选择器、快捷键提示、拖拽投喂等），且**只允许出现在 Layout/Platform 层**。

---

## 3. 本环境的验证手段口径（可做 / 不可做）

| 手段 | 本环境 | 说明 |
|---|---|---|
| Node 静态门禁（`tools/*.mjs`） | ✅ 可跑 | 已实测：架构门禁、接线回归、上架红线、对等门禁全绿；见 §3.1 |
| **ArkTS 编译（HAR 模块）** | ✅ 可跑 | `devecocli build --modules appstate connection dshcompat hostruntime platform` → **BUILD SUCCESSFUL**（apiVersion 26 SDK，145 任务）。这是**真编译器**，不是解析器 |
| **ArkTS 编译（entry 应用模块）** | ✅ **可跑（Windows 本机已解锁：2026-09-28）** | 两条路：① **只编 UI 层**：`node tools/check-arkts-entry.mjs`（**不需要任何环境变量**，脚本自己解析 DevEco 布局）；或直接 `<CLT>/hvigor/bin/hvigorw.js default@CompileArkTS --mode module -p module=entry@default -p product=default -p buildMode=debug --no-daemon`（Linux 布局需 `DEVECO_CLI_CLT_PATH` + `DEVECO_SDK_HOME=<CLT>/sdk` + `JAVA_HOME`）；② `devecocli build` 全量。**`Index.ets` 与全部 Pane 获得真编译验证**——P1~P3 改 UI 不再是盲改。⚠️ 2026-09-28 之前本行只有在 Linux 机器上成立：`tools/check-arkts-entry.mjs` 写死了四处 Linux 布局，在 Windows 上恒 exit 3（详见 `docs/90-…md` §2.4）|
| **完整打包（HAP）** | ✅ 可跑，**只差签名** | `devecocli build` → `CompileArkTS` ✅ `PackageHap` ✅ `PackingCheck` ✅，最后 `SignHap` 失败：`build-profile.json5` 的 `signingConfigs` 指向 Windows 路径（`C:\Users\hnzy1\.ohos\config\*.p12`）。产出 **`entry/build/default/outputs/default/entry-default-unsigned.hap`（138MB）**，内含 `libs/{arm64-v8a,x86_64}/libdshhost.so`（原生模块真的编出来了）+ 两个核心 zip + 入口脚本。⇒ **签名是纯环境问题**（需要那台机器的证书），与代码无关 |
| **ArkTS 语法错误的守护边界** | ⚠️ 只有真编译器能抓 | **实测**：codelinter **检不出语法错误**（往 `appstate` 注入 `return a +;` 后它一条都不报，而真编译器立刻 BUILD FAILED）⇒ 任何对 `.ets` 的改动都必须过 `default@CompileArkTS`/`devecocli build`，**不能用 lint 代替** |
| **设计令牌棘轮（`check-design-tokens.mjs`）** | ✅ 可跑且**失败已注入验证** | 计划 §6 点名禁止的裸 `fontSize`/`lineHeight`/`borderRadius`/`borderWidth`/颜色字面量：基线 **21 处 / 8 文件**（2026-09-28 重测；旧记"58 处 / 11 文件"是 2026-09-15 的读数），**只许变少**。为什么是棘轮而非一刀切：存量里**图标尺寸的收敛会改变视觉、必须真机验收**，一刀切会立刻几百处红——**永远红的门禁等于没有门禁**。豁免须写明理由（`// token-exempt: …`）；判定器自检 **13 个样例** |
| **纯逻辑执行测试（layout fixtures）** | ✅ 可跑 | `tools/check-layout-fixtures.mjs`：把 `appstate/ui` 的三个**纯逻辑** `.ets` 按 `.ts` 编译后**在本机直接执行**（被测的是同一源文件，不是复制品），断言四形态 + 断点边界 + 让步链三分支，**共 768 条断言**（7 组 fixture；2026-09-28 实测，**2026-09-30 起不再需要外部 junction**——`findTsc()` 已按同族脚本的候选列表补上 Windows 回退，见 §3.2。旧记"共 28 条"是被测断言的早期规模） |
| **ArkTS 静态检查（codelinter）** | ✅ 可跑且**覆盖面已证明** | 直接调用 CLT 的 `codelinter/bin/codelinter -c code-linter.json5 <模块目录>`：**16 条 warning / 0 error**（7 个文件）。覆盖用**注入测试**证明：往一个「无问题」文件注入已知违规，能被检出（见 §3.2） |
| API 兼容扫描（`devecocli check compat`） | ❌ 平台不支持 | CLI 明文：`Unsupported platform: linux. compat only supports macOS and Windows.`——**与 CLT 是否安装无关**，Linux 上永远不可用 |
| 模型/协议往返（`check-model-roundtrip.mjs`） | ✅ **可跑且通过** | `--no-prompt --wait-ms 180000`（Node 22）：真起 Host → 铸 cookie → 读模型目录 → 建会话 → 开 mux → `session/page` → 收到 `follow` 的 snapshot 帧（含 projections） |
| 起真实 Host 的门禁（`check-origin-fence` / `check-plugin-toggle`） | ✅ **可跑且通过**（需 Node < 22，慢机器还要放宽就绪等待） | ① 这三个门禁用 `process.execPath` 起 Host 并传 `--no-experimental-fetch`，该 flag 在 **Node 22+ 已被移除**（fetch 转正）⇒ Node 24 下 Host 直接启动失败（`--no-experimental-fetch is an invalid negation`）。本机备了 **Node v22.23.2**（与端侧同版本）：`/home/node/node22/bin/node`。② **本机 Host 冷启动实测 62,951 ms**（`BOOT_60_HTTP_BIND …(+62951ms)`；Orange Pi 5B + 工作区在 NFS）⇒ `check-origin-fence` 原来的 60 秒就绪等待刚好不够（`check-plugin-toggle` 用 90 秒，所以它一直能过）。已把它改成可放宽（**默认值不变**）：`DSHM_CHECK_READY_MS=180000`。③ 结论：`check-origin-fence` **PASS**（clean/absent/duplicated → 101；foreign → 403；no-cookie → 401）；`check-plugin-toggle` **PASS**（186 条目 → 写用户行 → `ui-deliverables enabled=false`） |
| 在设备上真跑（装机） | ✅ 已达成（本节的状态已过时） | 旧记"只差签名材料"——签名材料已备齐，**真机装机早已跑通**（见 §3.3 与 `docs/device-validation.md` §批次三十六/三十七）。运行期产物 `entry/libs/arm64-v8a/` 含 `libnode.so.137`（**实物是 `.137`，本节旧文字写的 `.127` 是 rc 之前的名字**） |
| **完整 arm64 HAP（未签名）** | ✅ 已产出 | `entry/build/default/outputs/default/entry-default-unsigned.hap` = **312,150,304 B / 297.69 MiB**（110 条目；旧记"138 MB"是阶段一的读数），内含 **`libnode.so.137`(126,809,264 B) + `libkoffi.so`(1,600,112 B) + `libsystem.so`(10,464 B, flock) + `libdshhost.so` + 全套原生库**；三个原生附加件（koffi / flock / dshhost）都在这一台机器上**真的编出来了** |
| 布局/形态真机验收 | ❌ 不可跑 | 无模拟器、无真机 |
| 视觉像素、手势、键盘、触控笔、系统权限、文件选择器 | ❌ 不可跑 | 统一进 `docs/device-validation.md`（P4） |

### 3.1 已实测的基线（2026-09-30 重测）

```
node tools/arch-check.mjs            ✅ 无违规（上游字面量只在 dshcompat，扫描 131 文件）
node tools/check-feature-wiring.mjs  ✅ 18 个功能接线全在（扫描 133 文件，1 条反面规则）
node tools/check-builder-recursion.mjs ✅ 99 文件 / 102 个 @Builder 无自递归（E343）
node tools/check-dead-code.mjs        ✅ 99 文件 / 判定声明 2237 处 / 门面字段 256 个 / 0 死代码（E350）
node tools/check-store-readiness.mjs ✅ PASS
node tools/check-parity.mjs          ✅ 通过（50 行：官方 39 + 端侧 11；DONE 14 · PARTIAL 31 · BOUNDARY 3 · TODO 2；§6 登记 36 个 id）
node tools/check-parity.mjs --self-test ✅ 15 个正负样例全符合预期（门禁自身可信）　← 2026-10-06 由 13 改 15（新增 A2 两条用例）；本行之外的读数仍是 2026-09-30 的
node tools/check-dead-handlers.mjs   ✅ 未发现空实现（2026-09-28 重测；旧记"78 处"是**声明**口径，非死按钮）
node tools/check-native-closure.mjs  ✅ PASS（libpty.so / libsharp 两条 SONAME 告警按路径 dlopen 属可接受）
node tools/check-origin-fence.mjs    ✅ PASS（clean/absent/duplicated ⇒ 101；foreign ⇒ 403；no-cookie ⇒ 401）
                                     ⚠️ 2026-10-04 修掉一处**就绪竞态**：`waitReady` 原把任何 `status > 0` 当就绪、`mintCookie` 随即一次性读 `host-ready.json`；`0.2.1-alpha.1` 上上游改成「先 404 应答、后落盘」⇒ 该门禁 3/3 误报失败。修法 = `waitReady` 后再等文件落盘（`DSHM_CHECK_READY_FILE_MS`，默认 20000）；修后两版核心各 3/3 PASS，另补两条负测试（见 `docs/10-协议兼容事实基线.md` §8.7.25）
node tools/check-plugin-toggle.mjs   ✅ PASS（target=ui-deliverables enabled=false）
node tools/compat-drift.mjs          ✅ 无漂移（核心 0.2.1-alpha.1；基线采集 2026-10-04T13:40:12.375Z；期望 140 / 基线 140）

node tools/check-skill-sync.cjs        ✅ RESULT: 32 passed, 0 failed（A–H 八组；C/D 专测**等长改动**）
node tools/check-compat-exemption.cjs  ✅ RESULT: 48 passed, 0 failed（臂 A 透传 + 臂 B 用**上游自己的** evaluatePluginCompatibility 验挂载决策翻转）
node tools/check-dshm-installer.cjs    ✅ RESULT: 43 passed, 0 failed（含 5a 真幂等 / 5b 版本漂移必重装 / 5c 收敛；另有 GitHub 回退与 monorepo 子包判定 19 例 —— 2026-09-29 由 24 增至 43）
                                       ⚠️ 2026-10-04 本机重跑会**无超时挂住**（该门禁真的走网络：`resolveSpec('ms@^2.0.0', DEFAULT_REGISTRY)`、`installSpec('https://github.com/dsh-market/dsh-market')`）⇒ 与核心升级无关，属本机出网能力问题
node tools/check-doc-refs.mjs          ✅ 通过（21 个文档 / 247 条带行号引用 / 0 处问题；引用数随文档增改漂移）

devecocli build --modules appstate connection dshcompat hostruntime platform   ✅ BUILD SUCCESSFUL（52s）
codelinter -c code-linter.json5 <6 个模块目录>                                  ✅ 16 warn / 0 error
node tools/check-layout-fixtures.mjs                                            ✅ 768 条断言通过（四形态 + 边界 + 让步链 + 模型/呈现/设置域）
node tools/check-layout-fixtures.mjs --self-test                                ✅ 注入的失败被如实报出

hvigorw default@CompileArkTS -p module=entry@default …                          ✅ BUILD SUCCESSFUL（0 error / 32 warn）
devecocli build（全量）                                                           ✅ CompileArkTS/PackageHap/PackingCheck 全过
                                                                                 ❌ SignHap（签名证书在 Windows 那台机器上）
                                                                                 ⇒ 产出 entry-default-unsigned.hap = 138 MB
```

**本机全量实跑退出码分布（2026-10-04 重测，35 条：`32×0 / 2×环境·平台 / 1×门禁自身缺陷〔已修〕`）**
（2026-09-30 的 `22×0 / 1×1` 已过期。2026-10-04 复跑的三条非零：`check-dshm-installer.cjs` 挂在本机出网、
`check-model-roundtrip.mjs` exit 1 是本机缺 koffi（平台差异，见下）、`check-origin-fence.mjs` exit 2 是门禁自身的
就绪竞态——**已修，修后该门禁在新旧两版核心上各 3/3 PASS**。
`check-model-roundtrip.mjs` 带 prompt 时为 exit 1 是**本机缺 koffi**（HAP 专属），加 `--no-prompt` 后 exit 0。
旧记的 `23×0 / 2×3 / 7×1` 更早，`check-arkts-entry.mjs`、`check-web-fetch-jitless.mjs`、`check-fetch-shim.cjs`、`check-dshm-installer.cjs` 均已修至 0。）

```text
# 三条"守护本身可信吗"的注入测试（门禁通过 ≠ 覆盖到了）
注入 `return a +;` 到 appstate → 真编译器 ✅ BUILD FAILED；codelinter ❌ 一条不报（故 codelinter 不能当解析守卫）
把 MAIN_MIN_VP 280→320 → check-layout-fixtures ✅ 立刻红（正好命中"840vp 详情栏被收窄"这条行为回归）
把 workflow-run 谎报成 DONE（并同步改统计）→ check-parity ✅ 以"陈旧登记"点名并退出 1
```

**门禁"通过"不等于"覆盖到了"**（docs/README 纪律 9）：在本环境跑不动的门禁，其覆盖面**是盲区**，不是通过。

> **2026-09-28 复核：这条纪律的"反向"同样成立——"跑不动"必须先查原因，不要直接记成盲区。**
> 原先记入盲区/环境的 5 个门禁里，有 2 个的真实原因是**脚本自己写死了 Linux 布局或传了裸盘符路径**，另有 2 个是**脚本自身的硬缺陷**，还有 1 个（`check-layout-fixtures.mjs`）是**工具链没暴露**（找不到 `tsc`，当时需先 junction 出 Windows 的 `typescript`；**2026-09-30 已把回退写进脚本**）——**五条里没有一条是设备能力不足**：
>
> | 门禁 | 原记录 | 复核结论（2026-09-28） |
> |---|---|---|
> | `check-arkts-entry.mjs` | 盲区（entry 层零编译验证） | **已修 ⇒ exit 0**，日志含 `CompileArkTS` + `BUILD SUCCESSFUL`（四处路径写死：`tool/node/bin/node` 缺 `.exe`、`JAVA_HOME` 默认值、`DEVECO_SDK_HOME`、`PATH` 分隔符用 `:`）|
> | `check-layout-fixtures.mjs` | 盲区（找不到 tsc） | **已修 ⇒ exit 0 / 768 条断言**（2026-09-30：`findTsc()` 补上 Windows IDE 自带 `typescript` 的候选路径，与 `check-arkts-entry.mjs` 同写法 ⇒ **不再需要外部 junction**）|
> | `check-web-fetch-jitless.mjs` | 环境（需特定 flag） | **已修 ⇒ exit 0**（两处硬缺陷：flag 写死的否定形态在 Node 24 无效致**两臂哑火**；loader 传裸盘符路径致 **B 臂从未跑成**）|
> | `check-fetch-shim.cjs` | 环境（需特定 flag） | **已修 ⇒ exit 0**（三处缺陷：前提建在 `--no-experimental-fetch` 的语义上、探针打在**规范禁用端口** `127.0.0.1:9`、取证引用取在装垫片**之后**）。**这条的代价最重——"环境"标签掩盖了一个产品真 bug**：Node 24 自带原生 `FormData` 而 `encodeRequestBody` 只认 `instanceof` ⇒ 请求体被编成字面量 `"[object FormData]"`，直接砸 dsh 附件上传（见 `docs/90-…md` §3.6 末段）|
> | `compat-drift.mjs` | 盲区（缺契约文件） | **可跑**：指向仓库内自带核心树即可（见 §3.1 下方命令）。初始 135/135 无漂移；2026-09-28 升到 `0.2.0-rc.1` 后为 **138/138 无漂移**；2026-09-29 升到 `0.2.0-rc.2` 后为 **140/140 无漂移**（+2：`userQuestions/{answer,attachWait}`，纯新增，见 `docs/40-上游升级手册.md` §4.4）；2026-10-04 升到 `0.2.1-alpha.1` 后仍为 **140/140 无漂移**（**零变化**，连新增都没有；唯一实变在依赖闭包，见 §4.5） |
>
> ⇒ 这五条里没有一条是"本机能力不足"。**把"某台机器的限制"读成"项目盲区"，代价是那一层从此没有自动验证。**

### 3.3 不入库产物清单（新机器上要能编译/装机，需要哪些东西）

> **为什么单列这一节**：2026-09-14 在这儿栽过一次——`entry` 编不过，先被误判成"缺构建产物"，
> 真因却是**一个源码文件从未入库**（见 §3.2 的事故）。源码与产物必须分开讲，否则会朝错的方向找一天。

**① 源码（唯一权威副本在版本库；缺了就是仓库缺陷，不是环境问题）**

| 路径 | 状态 |
|---|---|
| `entry/src/main/ets/runtime/NodeRuntime.ets` | ✅ **已于 2026-09-14 补回版本库**（commit `b906e13`；此前被 `.gitignore` 的裸 `runtime/` 规则吞掉，见 §3.2） |

**② 不入库的产物（字节不进库、方法进库；都要能在本机生成，或从开发机拷贝）**

| 产物 | 路径 | 干什么用 | 产生方式 | 本机状态 |
|---|---|---|---|---|
| Node 头文件 | `entry/src/main/cpp/node-headers/` | CMake 编 `libdshhost`（**只需要它**） | `tools/node-runtime/sync-node-headers.sh`（从 Node v22.23.2 源码树取 `src/*.h` + `deps/v8/include` + `deps/uv/include`） | ✅ 已生成（3.8 MB） |
| koffi 源码 | `third_party/koffi/` | 编 `libkoffi.so`（`subprocess`/`sandbox` 两行插件依赖它） | `node tools/fetch-koffi.mjs` | ✅ 已就位（4.6 MB，随其余产物上传） |
| Host 入口脚本 | `entry/src/main/resources/resfile/resources/app/` | 装机后由原生层跑起 dsh | `node tools/place-host-app.mjs`（源 `hostcore/app/` **在库里**） | ✅ 已就位 |
| 核心包 | `entry/src/main/resources/resfile/*.zip` | 首启解包出端侧核心树 | `node tools/pack-core.mjs --skip-install --place-in-app`；版本在 `hostcore/core-recipe.json` 的 `coreVersion` | ✅ 已就位（**`0.2.1-alpha.1`**，`84,696,273 B` / **30,462 条目**；**resfile 内只留当前版本这一份**，去旧留新）。注：2026-10-05 前此处写 `0.2.0-rc.2` / 78,081,448 B / 29351 条目，已按实物更正 |
| **libnode** | `entry/libs/{arm64-v8a,x86_64}/libnode.so.137` | **运行期**：自建 Node（OHOS）载体；同时是"编不编 koffi"的门 | `tools/node-runtime/build-node-ohos.sh`（本机亦可：容器与真机同为 arm64） | ✅ `arm64-v8a` 已就位（`libnode.so.137` = 126,809,264 B，随其余产物上传）⇒ **koffi 从此会被真正编进 HAP**；**不参与链接**（`CMakeLists.txt` 故意不写进 `DT_NEEDED`，见其注释）。⚠️ 实物是 **`.137`**，本文多处历史行仍写 `.127`（见 D6 开篇「版本口径提示」） |
| 核心树 | `dist/core/work/dsh-core-*` | `pack-core` 的输入；`check-origin-fence` / `check-plugin-toggle` / `check-model-roundtrip` 门禁的前提 | **不需要上传**：`entry/src/main/resources/resfile/dsh-core-*.zip` 本身就是完整树（zip 内 **30,462 条目**，解包后 **27,041 个文件** / 267.0 MB），`unzip` 到 `dist/core/work/` 即物化 |
| 协议契约 | `.research/protocol/contracts.json`（或仓库内自带核心树） | `compat-drift` 门禁的输入 | `node tools/protocol-contract.mjs` + 上游 checkout；**或** `$env:DSH_NODE_MODULES="$PWD\dist\core\work\dsh-core-0.2.1-alpha.1\node_modules"` 直接用仓库内核心树（`dist/core/work/` 已 gitignore，需先由 resfile 里的 zip 解出） | ✅ **可跑**（2026-09-29 在 `0.2.0-rc.2` 上实测 **140/140 无漂移**；2026-10-05 在 **`0.2.1-alpha.1`** 上 `node tools/compat-drift.mjs` 亦 exit 0）⇒ **不再是盲区**。**注意默认快照 `.research/protocol/contracts.json` 必须与新上表同版本**，否则新增端点会被读成"上游移除"（方向反，见 `docs/40-上游升级手册.md` §4.3/§4.4） |
| 签名材料 | `.p12` / `.cer` / `.p7b` | `SignHap` 出可安装的 HAP | DevEco 自动签名（那个 Windows 机器上的 `C:\Users\hnzy1\.ohos\config\`） | ❌ 缺（路径写在 `build-profile.json5`，Linux 上无效） |
| 工具链归档 | `entry/src/main/resources/resfile/toolchain/{python,git}/` | 首启解包出端侧 python3.12 与 git（真身 exec 需签名，见批次备注十二 ③） | `node tools/place-toolchain.mjs`（取 `third_party/python` 与 `third_party/git/packages`） | ✅ 已就位（python 26.4 MB + git 8.1 MB，**已自签名**） |
| **宿主 python3（构建期新增依赖）** | PATH 上的 `python3` / `python` / `py` | `tools/sign-tar-elf.py` 用它改写归档：**只有 Python `tarfile` 能在 Windows 上保住归档内的 symlink**（`bsdtar` 会丢条目、`7z` 会物化） | 官方安装版或 Store 版均可 | ⚠️ 缺则 `place-toolchain` **告警跳过签名**（归档仍可用，只是 git/python 真身继续被 execve 拒） |
| `binary-sign-tool.jar` + JDK | DevEco SDK `.../toolchains/lib/binary-sign-tool.jar` | ELF **自签名**（`-selfSign 1`，走 SelfSignSignProvider，**不需要 keystore 密码**） | 随 DevEco 安装 | ✅ 已就位（`pack-core` 签 core 树的 rg；`place-toolchain` 签工具链归档） |
| `libdshm-gitcompat.so` | `entry/libs/arm64-v8a/` | git 子进程类命令的 **LD_PRELOAD 垫片**（把平台判失败的 `pthread_setcancelstate`/`_sigmask` 改判成功，见批次备注十三 三） | CMake 自建（源码 `entry/src/main/cpp/gitcompat.c` 在库里） | ✅ 随 HAP 分发（5472B，`DT_NEEDED` 仅 libc） |

**工作区在 NFS 上——批量文件操作必须换到本地盘（本轮最大的效率教训）**

| 事实 | 读数 |
|---|---|
| 工作区文件系统 | **NFS**：宿主是 Orange Pi 5B，`/mnt/Develop` 来自 NAS `192.168.3.27:/volume1/Develop`；容器（内层 Docker）以 `/workspace` 挂载它 |
| 逐文件操作代价 | 把核心树（29k 个小文件）解到工作区：**跑了 25 分钟才 6.5k 个文件**（≈4 个/秒，照这速度要数小时） |
| 换到本地盘 | 容器本地 overlay（`/home/node`）实测 **2000 个小文件 0.12 秒**；同一份核心树解到 `/home/node/dshm-cores/` 只用 **4 秒** |
| 做法 | 大批小文件的东西解到**容器本地**，再用软链挂进项目：`ln -sfn /home/node/dshm-cores/dsh-core-0.1.5-rc.2 dist/core/work/dsh-core-0.1.5-rc.2`（`dist/` 已 gitignore，不污染仓库；`existsSync` 会跟随软链，门禁无需改动） |

**从别处拷贝产物时的两个实测坑（2026-09-14 各踩一次）**

| 坑 | 现象 | 核对办法 |
|---|---|---|
| **"上传了目录" ≠ "文件到了"** | `dist/core/work/dsh-core-*` 看起来存在，但 `find … -type f | wc -l` = **0**：只有目录骨架，没有文件 ⇒ Host 报 `找不到 profile-boot 入口（核心树可能不完整）` | 收到目录后用 **`find <dir> -type f | wc -l`** 核对文件数，不只看 `ls` |
| **文件带 +x 位** | 拷进来的 `.ets` / `.cpp` / `.d.ts` 变成 `100755`，与库里的 `100644` 产生**纯模式 diff**（内容逐字节相同） | `git diff --summary` 看 `mode change`；归一化用 `git update-index --chmod=-x <path>`（必要时重写文件以取得属主再 `chmod 644`） |

**结论**：**编译验证不需要任何外部产物**（HAR 模块 + entry 的 ArkTS + 原生 + 打包在这一台机器上全通）；
**装机运行**才需要 `libnode`（+ 签名）。这一点值得写下来，因为"编译过了"与"能装机"经常被混为一谈。

### 3.2 编译器与 codelinter 已实测发现的问题（新能力的第一批产出）

| 发现 | 性质 | 处置 |
|---|---|---|
| `platform/system/Clipboard.ets:33` 读剪贴板需要 `ohos.permission.READ_PASTEBOARD`（since 12），**应用未声明该权限**（声明的是 INTERNET / GET_NETWORK_INFO / KEEP_BACKGROUND_RUNNING） | **真实缺口**：`readText()` 在未声明权限时拿不到数据（源码自己 catch 成空串，表现为"粘贴没反应"） | 见 §4.6 `dshm-clipboard` 行已由 `DONE` 降为 `PARTIAL`；登记在 §6。**这是编译器的功劳——此前矩阵把它记成 DONE** |
| `platform/notify/KeepAlive.ets:76` 同样报权限警告，但 `KEEP_BACKGROUND_RUNNING` **已声明** | 假警报：HAR 编译期看不到宿主 `entry` 的权限声明 | 不改；登记以免下次被当成缺陷 |
| `platform/system/SecretStore.ets:63` `'encode' has been deprecated` | 技术债（可继续用，未来版本会移除） | 进 §6 登记，P2 处理 |
| `platform/window/WindowRegistry.ets:151` `'getContext' has been deprecated` | 同上 | 进 §6 登记，P2 处理 |
| `hostruntime/src/main/ets/Index.ets` 7 条 `export *` 性能规则告警 | 性能建议（`@performance/hp-arkts-no-use-any-export-*`） | 不阻断；P2 视情收敛 |
| **`Circle().fill(...)` 六处**（`view/ConnectPane.ets:273`、`view/SessionListPane.ets:198`、`view/SettingsPane.ets:1144/1678/1754/1819`）：编译器标注 **`The 'fill' API is supported since SDK version 26.0.0`**，而项目 `build-profile.json5` 声明的是 **`compatibleSdkVersion: 6.1.1(24)`** | **✅ 已修（2026-10-06）**：6 处改成视觉等价的 `Row + backgroundColor`（`docs/108` §1.2），`compatibleSdkVersion` 拍板固定 `6.1.1(24)`（`docs/110` §5）⇒ 下面这条降级为**历史判据**（保留它是因为"编译器警告是当时唯一信号源"这个结论仍然成立）。原判据（真实兼容性缺陷，本轮最有价值的编译器产出）：在 API 24 设备上 `fill` 不存在 ⇒ 三个状态点/色点（Host 授权状态、会话运行中脉冲、提供方色点）行为未定义。而这正是 `devecocli check compat` 该抓的东西——它**在 Linux 上不可用**（macOS/Windows only）⇒ **编译器警告是当前唯一的信号源** | 三选一（**需要决策，且要真机看视觉**）：① 改用 API 24 就有的写法（如 `Circle().backgroundColor(...)`，视觉是否等价需真机确认）；② `apiAvailable` 守卫 + 回退；③ 把 `compatibleSdkVersion` 提到 26。**决策前不得当作没问题** |
| `pages/Index.ets` 多处 `'getContext' has been deprecated`（约 12 处）、`'px2vp' has been deprecated`（3 处）、`'pushUrl' has been deprecated`（1 处）；`hostruntime/core/CoreStore.ets:424/430/438` `Function may throw exceptions. Special handling is required.` | 技术债 / 健壮性提示（可继续用，未来版本会移除） | 进 §6 无需登记（非行缺口）；P2 统一收敛 |

**一处端侧运行时缺陷（2026-09-14 实测确证 → 已修复并门禁固化）：`web_fetch` 在 jitless 下永远失败**

| 环节 | 事实（都有对照实验，不是推断） |
|---|---|
| 症状 | `web_search` 正常，`web_fetch` **打不开任何网页、任何 IP** |
| 机制 | 上游 `dsh-web-fetch-http` **不用全局 fetch**：它 `await import("undici")`（`lib/index.js:154`）、自建 `Agent` 并把 `dispatcher` 传进 fetch；而 **undici 的 HTTP 解析器是 WASM**（`lib/llhttp/llhttp-wasm.js`）。`web_search` 走本仓的 http/https 垫片（纯 JS），所以照常工作 —— 这就是"只有一个功能坏"的原因 |
| 为什么 `--jitless` 下没有 WASM | V8 的 `--jitless` 与 `--expose_wasm` 互斥（启动即打印 `disabling flag --expose_wasm`），`typeof WebAssembly === 'undefined'` |
| **对照实验**（同一份真实上游代码、同一个本地 HTTP 服务、同一套端侧 flag） | **A 臂（不注册钩子）**：真 undici 探针报 **`WebAssembly is not defined`**，真实上游 `HttpFetchProvider.fetch()` **4/4 断言全败**（`fetch failed` / `WEB_PROVIDER_ERROR`）—— 即用户报的症状。**B 臂（注册钩子）**：**8/8 全过** |
| 修复（**已接线、已端到端验证**） | `hostcore/app/undici-shim.mjs`（把 `undici` 模块名接到已有 http 垫片，并翻译 `dispatcher → lookup` 以**保住上游的 DNS 钉住/SSRF 防护**）+ `hostcore/app/undici-loader.mjs`（`module.register` 解析钩子）+ `main.js` 里的 `installUndiciNameHook()`（**仅在 `WebAssembly` 不可用时注册**：原生 undici 能用时不该被替换）。**不改上游源码、不改核心树**，只做运行期组合 |
| B 臂验证到的两条**安全语义**（本修复最有价值的部分） | ① 同源跳转仍被上游自己跟到最终 200（依赖 `redirect:'manual'` 语义原样透传）；② **跨源跳转仍被拒为 `WEB_REDIRECT_BLOCKED`**。若当初为了"让它能通"而放开 redirect 或忽略 lookup，这两条会立刻炸 |
| 真实 Host 侧证据 | Host 日志出现 `undici 解析钩子已注册（web_fetch 走本仓垫片，绕开 WASM）`，且 Host 照常启动、目录可读、会话可建（`tools/check-model-roundtrip.mjs --no-prompt`） |
| **固化门禁** | `tools/check-web-fetch-jitless.mjs`：**自带对照实验**——A 臂必须失败且必须给出 WASM 因果证据（否则判"说不出原因的失败"= 门禁报错），B 臂必须 8/8 通过。含 13 条判定器自检 |
| **跑它的 Node 版本** | 必须在 **Node 22**（`/home/node/node22/bin/node`）下跑：它用 `process.execPath` 起带 `--jitless --no-experimental-fetch` 的子进程，而 `--no-experimental-fetch` 在 **Node 22+ 已被移除**（fetch 转正）⇒ 默认的 Node 24 下两臂都失败，输出像"门禁红了"而其实是**环境不对**。2026-09-15 实测：Node 24 ❌（两臂都没有断言产出）/ Node v22.23.2 ✅ PASS（B 臂 8/8） |
| 顺带修掉的两处垫片缺陷（已生效、Host 复验正常） | ① `dshmFetch` 此前**硬编码自动跟 5 跳、忽略 `init.redirect`** ⇒ 上游用 `redirect:'manual'` 实现的"仅同源跟跳 + 跨源拒绝"安全策略会被静默绕过；现按 manual/error/follow 处理。② `lookup` 透传通道（上游的 pinned lookup 与 node 的 lookup 契约本就同构，直接可用） |
| **真机待验收** | `register()` 的钩子跑在 Node 的**独立线程**里；端侧嵌入式运行时是否允许起线程，本环境无法证明。故 `installUndiciNameHook()` 失败时**只降级、不阻断启动** —— 正因如此**必须靠日志主动确认**，不能因为"Host 起来了"就以为生效了。真机两项已登记为 `docs/device-validation.md` 的 **D1（钩子在线程里能否注册）** 与 **D2（真机抓一次网页）** |

**一处同类端侧运行时缺陷（2026-10-04 真机报障 → 已修复并门禁固化）：插件自建 worker 线程拿不到任何 jitless 补齐**

| 环节 | 事实 |
|---|---|
| 症状 | 开发者工具里启用 `@deepseek-ai/dsh-experimental-inspector` 报 `启用失败: dsh: warning: 1 entry did not activate`，栈是 `lazyllhttp … ReferenceError: WebAssembly is not defined`。同一根因在 Windows 侧先表现为 `No usable native binding found for node-addon-require-builtin-win32-x64-msvc` |
| 机制 | worker 是**新线程**：新 globalThis、新 module registry。原先五段补齐（native 重定向 / require-builtin shim / fetch 垫片 / undici 解析钩子 / `node:http` 惰性 getter 封堵）全部内联在 `main.js` ⇒ **只在主线程生效**。而该插件的 `lib/worker.js` 第一行就是 `import "@deepseek-ai/dsh-app-boot/worker/profile-resolution-bootstrap"`（内部 `createRequire(...)("node-addon-require-builtin")`），且它起 worker 时**显式写死 `execArgv: []`**（`lib/index.js:1904`）——连 `--expose-internals` 都不继承 |
| 关键教训 | **"主线程全绿"完全覆盖不了这条路径**：`web_fetch`、模型调用、插件切换全在跑，只有插件自建 worker 里那个世界是"没有补齐的 jitless" |
| 修复 | ① 五段补齐抽成**单份实现** `hostcore/app/jitless-env.cjs`（主线程与 worker 共用，杜绝两份漂移）；② `wrapWorkerThreads()` 包装 `node:worker_threads` 的 `Worker`（并调 `module.syncBuiltinESMExports()`——该插件用的是 **ESM** 具名导入 `import { Worker } from "node:worker_threads"`，只改 CJS 属性它看不见）+ `hostcore/app/worker-bootstrap.cjs` 作为 `--require` preload ⇒ 每个 worker 自动带 `--expose-internals --require …`，且 `--require` 早于 worker 任何 import；③ `tools/place-host-app.mjs` 与 `tools/assert-resfile-sync.mjs` 的清单同步加入这两个文件（漏掉只静默变哑，不报错） |
| 踩到的两个坑（已写进代码注释） | ① **递归**：`module.register()` 会在另一个线程跑钩子，而那线程**继承 worker 的 `execArgv`** ⇒ preload 再 register ⇒ 无限起线程、宿主**静默挂死**。判据：hook 线程 `isMainThread=false` **且 `parentPort === null`**（任何用户 worker 都非 null），据此跳过。② **封 getter 只在 jitless 下做**：WASM 可用（PC 侧 dev-host）时把 `http.maxHeaderSize` 封成 `{}` 会反噬原生 undici（`fetch failed / cause: http module not available or http.maxHeaderSize invalid`） |
| 对照实验（本机 Windows / Node 24.19 / `--jitless`，同一 profile 同一套 flag） | **对照臂**：`DSHM_NO_WORKER_SHIM=1` ⇒ 复现 `dsh: warning: 1 entry did not activate`；**修复臂**：打印 `dsh inspector: devtools://…ws=127.0.0.1:9230/…`（worker ready），worker 侧补齐读数 `{"seal":true,"requireBuiltin":true,"fetch":true,"undiciHook":true,"nestedWorkers":true}` |
| **固化门禁** | `tools/check-worker-jitless.mjs`（自带对照臂 + 8 条判定器自检）：A 臂不注入 ⇒ worker 里 fetch 必须失败且带 WASM 因果证据；B 臂注入 ⇒ worker 里 `require-builtin` 通道 / internal 模块 / `fetch 200` 三件全通 |
| **真机验收（2026-10-05 达成）** | 端侧允许 worker 线程与 `register()`。真机读数：worker 补齐 `{"seal":true,"native":true,"requireBuiltin":true,"internalUndici":true,"fetch":true,"undiciHook":true,"nestedWorkers":true}`；`did not activate` **0 次**；`/api/experimental-inspector/bootstrap` **200**；`dsh inspector: devtools://…ws=127.0.0.1:9230/…`；`home` 的 `links=13`/`size=3440` 装机前后一致（详见下条） |

**一处端侧运行时缺陷（2026-10-05 真机 v2 报告 → 已修复并门禁固化）：Node 内部 require 的内建 undici 在 jitless 下必炸（MessagePort 每条消息投递）**

| 环节 | 事实 |
|---|---|
| 症状 | 即使 worker 补齐已生效（那五项全 true），启用 `experimental-inspector` 仍报 `1 entry did not activate` + `ReferenceError: WebAssembly is not defined`；栈底是 undici 的 `lib/global.js`（**模块初始化**帧，而不是某次 fetch 调用） |
| 机制 | 端侧 Node **v24.2.0** 的内建 undici 在模块初始化阶段就 `new Agent()` ⇒ `--jitless`（无 WASM）下一加载即抛。而 Node **自己内部**会按完整路径 require 它：① `lib/internal/worker/io.js` 的 `onMessageEvent()` **每投递一条 MessagePort 消息**都 `require('internal/deps/undici/undici').createFastMessageEvent`；② `globalThis` 上 `Headers/Request/Response/FormData/MessageEvent/CloseEvent/WebSocket/EventSource` 的惰性 getter 也 require 它。inspector 的 Host 半身正是用 `new MessageChannel()` 做 Host↔Worker 通信（`lib/index.js:1805`）⇒ **第一条消息即炸** → entry 未激活 → `/api/experimental-inspector/bootstrap` 一直 404（**同一条根因的表象，不是第二个 bug**） |
| 为什么前四个垫片入口都拦不到 | 全局 `fetch`、裸说明符 `undici` 的解析钩子、`node:http` 惰性 getter 封堵、`node-addon-require-builtin` 垫片——都在 userland 那一层；而这里是 Node 内部按完整路径的 require |
| **踩到的大坑（第一版只打了日志）** | 第一版把钩子挂在 `Module._load` 上——**Node 内部模块不走 `Module._load`**：它走 `requireBuiltin()` → `BuiltinModule.prototype.compileForInternalLoader()`（`internal/worker/io.js` 的 id 以 `internal/` 开头而非 `internal/deps/`，所以拿到的是 `requireBuiltin`），与 `Module._load` 毫无交集。结果日志说"已安装"、故障一模一样。**教训：拦截类改动的判据必须是运行时行为，不能是"钩子装了没"** |
| 正确拦截层 | `BuiltinModule.map.get('internal/deps/undici/undici')`：把它的 `exports` 预置成垫片并置 `loaded = true` ⇒ `compileForInternalLoader()` 第一行（`if (this.loaded 或 this.loading) return this.exports;`）直接返回垫片。该类在 `--expose-internals` 下借任一 public builtin 的实例取 `constructor` 即可拿到 |
| 修复 | 新增 `hostcore/app/internal-undici-shim.cjs`（纯 JS 替身：`createFastMessageEvent` / `MessageEvent` / `CloseEvent` / `WebSocket` / `EventSource` / `fetch` / `Headers` / `Request` / `Response` / `FormData` / dispatcher 占位），`installInternalUndiciShim()` 在 BuiltinModule 层预置 + 保留 `Module._load` 补充 + **安装期自检**（`exports` 必须指向垫片，否则 fail-loud）；主线程与每个 worker 都装。`createFastMessageEvent` 必须返回**真 Event 实例**——Node 的 `EventTarget.dispatchEvent()` 对非 Event 抛 `ERR_INVALID_ARG_TYPE`（已实测），不能用朴素对象糊弄 |
| 顺带修好 | `globalThis` 上那六个惰性接口内部走同一个 BuiltinModule 路径 ⇒ 一并解析到垫片（安装期自检打 `globalThis.MessageEvent=ok`）；原先每次启动都出现的"已知噪声"日志（`Node 内建 undici 在 --jitless 下初始化失败`）不再新增 |
| 对照实验（本机 Windows / Node 24.19 / `--jitless`） | 对照臂 `DSHM_NO_INTERNAL_UNDICI_SHIM=1` ⇒ 内部 require 不被接管、MessagePort 事件非垫片类；修复臂 ⇒ 由垫片接管、**端口事件确由垫片 `MessageEvent` 构造**、`createFastMessageEvent` 可被 `dispatchEvent` 接受、端口收发无回归 |
| **固化门禁** | `tools/check-internal-undici.mjs`（自带对照臂 + **11 条**判定器自检）。判据特意选**运行时行为**（`onmessage` 事件是不是垫片类），而不是"钩子装了没"——第一版正是被后者放过；另断言安装函数自报 `installReturned:true`（防"返回 false 却恰好通过"的组合） |
| 真机验收（2026-10-05 01:24 修订） | `did not activate` **0 次**；`WebAssembly is not defined` **0 次**；`/api/experimental-inspector/bootstrap` **status=200**；`dsh inspector: devtools://devtools/bundled/devtools_app.html?ws=127.0.0.1:9230/…`；安装期自检 `exports=ok、globalThis.MessageEvent=ok`（主线程 + worker 各一次）；"已知噪声"不再新增；`home` 的 `links=13`/`size=3440` 装机前后一致 |

**本轮收尾自查与审核（2026-10-05 01:40）**

| 项 | 结论 |
|---|---|
| 门禁 | **全绿**（`AGENTS.md` 的「必跑的回归门禁」清单 + `check-native-closure` / `check-plugin-toggle` / `check-dead-code` 三条结构性门禁）。**本条不再写死总数**：清单每加一条就得改一次，而"过期数字"与"漏写"在审核时无法分辨（2026-10-05 文档审核已抓过一次）。另注：`check-skill-sync` 是 `.cjs` 后缀，别按 `.mjs` 跑（本机误跑一次，报 `Cannot find module` 而非门禁失败） |
| 真机验收 | 端侧 01:24 启动：`did not activate` **0**、`WebAssembly is not defined` **0**、`/api/experimental-inspector/bootstrap` **200**、`dsh inspector: devtools://…ws=127.0.0.1:9230/…`；`home` 的 `links=13`/`size=3440` 装机前后一致 |
| 自查：顺序 | `main.js` 里 `installInternalUndiciShim` 排在 `installJitlessFetch` 之前 ⇒ 惰性接口先被垫片接管，`installFetchShim` 的 `defineProperty` 循环随即看到"已定义"而跳过（不覆盖、不打架） |
| 自查：幂等/嵌套 | `installInternalUndiciShim` 有 `Module.__dshmInternalUndiciShim` 幂等位；主线程 + 每个 worker（含嵌套 worker）各装一次，均打印自检 `exports=ok` |
| 自查：fail-loud | 取不到 `BuiltinModule`、map 缺项、自检不通过 → 均**明确记日志并返回 false**，绝不静默"装了但没用"（这正是第一版栽的地方） |
| 自查：PC 侧不回归 | 各安装函数在 `typeof WebAssembly !== 'undefined'` 时直接 no-op；`fetch-shim.js` 的 `defineProperty` 只在原值为 `undefined` 时补，原生可用时不覆盖 |
| 自查：真 Event | `createFastMessageEvent` 返回继承 `globalThis.Event` 的实例；门禁断言它能被 `EventTarget.dispatchEvent()` 接受（朴素对象会抛 `ERR_INVALID_ARG_TYPE`） |
| 环境清理 | `dist/_*` 一次性产物：**归档 484 个文件 + 5 个目录**到 `D:\DSHM-signing-backup\dist-leftovers-20261005\`（含 README），仓库内只留 32 个被文档引用的取证文件；本次构建日志与临时脚本已删/归档 |
| 遗留（非阻塞） | ① 端侧 2026-10-05 实测 `symlink/hardlink` 在 **PC 档允许** —— **已于同轮修掉文案**：实测结论写进 `entry/src/main/resources/resfile/ohos-skills/ohos-pc.md`（本档允许 / 手机档禁止 / 跨档位仍按"可能禁止"兜底、能复制就不建链）与 `ohos-plugin-install.md`（把"含原生模块的插件装不了"的原因从"沙箱禁 symlink"改为**平台产物缺失 + 沙箱 ELF 受代码签名管辖**，并点明链接那条实测事实）；**行为不动**（仍复制本体而非建链）。注：原登记写的是 `ohos-pc` / `ohos-shell` 两份，逐份核对后 `ohos-shell.md` 里**没有**这条表述，实际第二处在 `ohos-plugin-install.md` ② 启动期 1.6–2.0 s 事件循环停顿（同步 `stat/realpath/readFile` 约 4.2 万次/停顿），与本次修复无关 ③ `isKnownJitlessUndiciNoise` 只覆盖 `unhandledRejection`、未设 `Error.stackTraceLimit` —— **已于同轮修掉**：`main.js` 的 `uncaughtException` 现在共用同一条噪声判据（同一个 undici 初始化可能以两种形态出现，此前 uncaught 形态会被当成真故障打满日志），并在两个监听器之前设 `Error.stackTraceLimit = 50`（两轮真机排障都被默认 10 帧截断卡住）④ `sandbox-dlopen` 仍 false（已有扁平重定向兜底）⑤ **`docs/90-DSH鸿蒙原生实现全流程.md` 的多处过期引用 —— 已于 2026-10-05 同轮修掉**（原登记 4 处：`:3635` 的 `AGENTS.md`、"必跑为什么只有 7 条"、`:4345` 的"强制必跑（7 条）"、`:4408`/`:5330` 的"7 条"）。现在该节写"当前 15 条 = 14 条 node + `device-acceptance.ps1`"，并明确"**权威清单始终是 `AGENTS.md`**、本表只逐条解释最早的 7 条"，且不再钉 `AGENTS.md` 的行号（原先钉死行号 ⇒ 清单每加一条就过期一次） |
| 两路独立只读审核（代码 / 文档一致性，2026-10-05 01:40 交卷） | **无阻断项**。当场修掉：① `main.js` 里"只有 `Module._load` 拦得住"的**错误注释**（会把人带回 v1 的错误认知）② `fetch-shim.js` 用 `getOwnPropertyDescriptor` 读惰性属性会**物化** getter（实测：读之前 undici 未加载、读之后已加载）⇒ 拦截万一失效会把 fetch 垫片一起拖垮（改为逐个 `try/catch` 读取 + 失败大声记日志）③ 安装期自检原是**同义反复**（复核自己刚赋的值，恒真）⇒ 改为 `require(ID) === shim` 真断言，并把幂等标志位挪到自检**之后**（失败后仍可重试）④ `fetch-shim.js` 注释"本文件没有 'use strict'"事实错误（第 43 行就是，故旧写法是抛 TypeError 而非静默失败）⑤ 垫片 `super(type)` 丢掉 `init` ⇒ 改 `super(type, init)`；补 `ErrorEvent` 导出、删死导出 `__dshmEventBase`、澄清 dispatcher 是预防性占位 ⑥ 门禁加断言 `installReturned:true`（防"返回 false 却恰好通过"），判定器自检 10 → **11 条** ⑦ 文档：`docs/80` §7 的"仓库外备份"改写指向（**原文指向的暂存目录里真名 `.cer`/`.p7b` 是全零文件**，照搬会重现它自己写的证书链报错）、README 体积单位/包内清单/Node 源码引文、`SHA256SUMS.txt` 同名两条有效校验行、门禁条数、`docs/90` 过期引用 |
| **审核加固版已复验并重出（2026-10-05 10:09，本条为当晚登记的收口）** | 上述 ①–⑥ 的代码改动已重跑 `place-host-app` + `assert-resfile-sync`（13 件同步）与 15 条门禁（全绿），**并已装机复验通过**：`did not activate` 0 次、`/bootstrap` 200、安装期自检含 `require=ok`、`dsh/home` 的 `links=13`/`size=3440` 不变。`dist/sideload/` 已重出为 sha256 `703430ae…`（320,240,597 B / 305.41 MiB），源码与交付产物**重新一致**（详见变更记录 v1.47） |

**`glob` 目录锚定失效（2026-10-05 真机 P1 → 已修复、门禁扩到 58 条、端侧 toybox 语义复核）**

| 环节 | 事实 |
|---|---|
| 症状（真机，cwd 下约 13111 个文件） | `_tool_probe/*` 命中 **13111**（应为 1）、`_tool_probe/*.txt` 命中全局 **8** 条；而 `_tool_probe/hello.*`、`**/hello.txt` 看着正常 —— 与工具文档"include a separator to anchor the depth"正好相反 |
| 根因 | 端侧 `rg` 的 execve 被拒 ⇒ `glob`/`grep` 走 `patchFsSearchFallback` 注入的 **find/grep 降级**路径；而降级返回的 argv 里 `base = globPattern.replaceAll("**/","").split("/").pop()` ⇒ **目录前缀被 pop 掉**，`dir/*` 变成 `find <root> -type f -name '*'` = 全树。**末段带字面前缀时恰好正常**，所以能长期潜伏 |
| 修法（先测端侧 find 能力再定） | **最长字面目录前缀并入 find 起点** + `-maxdepth` 限深 + 末段 `-name`（端侧 toybox 实测支持 `-maxdepth`）；`**` 段或"末段不含 `/`" ⇒ 不加 maxdepth（保持 rg 的任意深度语义）；同起点多花括号展开仍走精确形；起点不同或中间段带通配 ⇒ 退到 `-path` 锚定（POSIX fnmatch 的 `*` **跨 `/`**，实测 `-path '*/dir/*'` 连深层一起命中 ⇒ 只能锚定、做不到限深）。`grep` 侧同类缺陷（只取末段做 `--include`）⇒ 把**搜索根**换到字面目录前缀 |
| 端侧语义复核（真 toybox，夹具 6 文件） | `_tool_probe/*`：**新 2 / 旧 6**；`_tool_probe/*.txt`：**新 1 / 旧 3**；`_tool_probe/hello.*` 2/2；`_tool_probe/*.{txt,md}` 2/2；`**/hello.txt` 1/1；`*.txt` 3/3（任意深度语义未破） |
| 门禁 | `assert-fs-search-fallback.mjs` **42 → 58 条**，新增 16 条锚定用例，含"**find 的起点必须已收窄**"这条不变式断言（不只比 argv 形状） |
| **顺带修掉的隐蔽坑（值得留档）** | 该补丁原先以"见到 `buildFallbackArgv` 就跳过"做幂等 ⇒ **注入块的实现永远无法升级**：本次现场 pack-core 打印"已在，跳过"、树里留的是旧实现、门禁读到旧行为报 16 条红 —— 差点被误判成"门禁写错了"。改为**可重入重打**：未打补丁的原文另存 `dist/core/work/.pack-core-pristine/`（带 `patchedSha256` 校验；只有确认树里那份是我们上次的产物才回滚重打，哈希不符就以上游内容为新原文并记日志，**绝不用旧副本把上游更新降级掉**） |
| **同一天踩的两次模板串地雷（已用自检固化）** | 注入代码以**模板串**书写：① 块注释里出现注释终止符（我写了 `"**/"` 字面量）会提前截断注释；② 反斜杠不写两个会被吃成一个裸 `/`（`/^\.\//` → `/^.//`）。两次都是"注入进树里的 JS 语法坏掉、而 pack-core 只做文本替换不解析"，要等几分钟打包完由门禁才发现 ⇒ 新增**注入后整文件 `node --check` 语法自检**（片段级检查必然假阳性：`try{…}` 被锚点拆开、`await` 在片段里非法） |
| 真机验收（2026-10-05 11:14） | 设备上 `dsh-tool-fs-search/lib/index.js` 含 `splitGlobAnchor`(4 处)/`-maxdepth`(4 处)、**64,953 B**，与仓库核心树**逐字节一致**；`SEARCH_FAILED` **0**、`did not activate` **0**、wasm 报错 **0**、`home` 的 `links=13`/`size=3440` 不变 |
| 未验证（如实） | **工具级 `glob` 复测仍需端侧会话触发**；本轮验到的是"降级代码在位 + 用新实现产出的同一 argv 在端侧真 toybox 上语义正确 + 树/源码逐字节一致" |
| 侧载包 | 重出为 sha256 `47e5721e…`（320,932,820 B / 306.07 MiB） |

**报告 §5「过渡期工具面翻转」的裁定：不是"两条 runtime 并存"，而是预设不同**

| 环节 | 事实 |
|---|---|
| 报告观察 | 同一会话内三态：① `run_code` 在、但报 wasm 错 ② `run_code` → `unknown tool "run_code"`，而 `bash`/`write`/`glob` 可直连 ③ 直连工具报 `only run_code is callable directly`，`run_code` 恢复正常 |
| 裁定 | 这三态**逐字对应"预设不同"**：`standard` 预设下直连工具可用、**没有** `run_code`；`ptc` 预设下反过来。依据是 `dsh-tools/lib/index.js:940,971` —— `ptcRuntime === undefined` 时 `run_code` **仍然存在**（只退回默认 flavor）⇒ "runtime 没注册"**不会**产生 `unknown tool "run_code"`。所以 ② 是当时会话在 `standard` 预设上、③ 是切到 `ptc` 预设之后，属**按设计**的工具面差异（本仓既有笔记早就写明"模型的工具清单由 agent preset 决定"，正因如此 pack-core 才要直接给 preset 文件打 disabled） |
| 对"原子化 preset/runtime 切换"这条建议 | **不需要**：runtime 注册本来就在启动期原子完成（cordis 服务注册，自证行即证据）；预设切换按设计就会改变可调用工具面 |
| 留给端侧确认的一点（如实） | 若要把 ② 彻底闭环，可回看当时的**预设选择时间线**（`agent-preset-registry.selectedDefault` 何时从 `standard` 变成 `ptc`）—— 我这边只能从工具面形态反推，读不到会话历史 |

**PTC 模式全量失效（2026-10-05 真机报告 → 已修复、门禁固化、真机验收）**

| 环节 | 事实 |
|---|---|
| 症状 | PTC 模式下每次 `run_code` 返回 `Error: code run failed (exception): WebAssembly is not defined`（附 `File sandbox: danger-full-access`）；31 个工具全不可达；空程序 / 非法语法 / 重启应用后报错**逐字不变** |
| 根因 | `run_code` 的工具传输依赖 `ctx.ptcRuntime`，端侧原本由官方 `@deepseek-ai/dsh-ptc-runtime-node` 提供，而它在 `--jitless` 下有两条**结构性死路**：① 用 `node:module` 的 `stripTypeScriptTypes`（SWC 的 **WASM** 版）擦类型 —— 真机日志先 `ExperimentalWarning: stripTypeScriptTypes …`、紧接着就是那条错，说明**失败发生在解析/擦除那一刻**（与用户代码无关，空程序同样报）；② 它还要 spawn 一个子 Node 执行程序，端侧 `spawn` 被拒（`EACCES`）、`process.execPath` 是 `/system/bin/appspawn` |
| 修法 | 停用官方那一行，换成自带的**同进程纯 JS** 实现 `@deepseek-ai/dshm-ptc-runtime-inproc`：纯 JS 擦除（vendor `@babel/standalone` 单文件 2.93 MiB、零运行时依赖；仍是官方那套"包进 `async function __dsh_program__()` → 整体擦除 → 切壳"）+ `node:vm` 同进程求值（宿主 binding 直连、入参/返回值无损 JSON 校验与分离副本、命名空间 null 原型、注入错误类在**程序 realm 内**构造）+ `Promise.race([程序, 截止期, abort])` 与五类错误分类（`exception`/`timeout`/`abort`/`invalid-output`/`output-limit`） |
| 契约收窄（如实声明） | `sandboxMode` 返回 `undefined`（**不做文件封闭**）⇒ `dsh-tools` 因此不传 `sandboxPolicy`、也不要求结果带 `sandbox`（缝里 "provider without confinement support" 的语义，不是漏配）；`isolation='in-process'`；`timeout` 默认值照抄官方（`defaultMs 120000` / `maxMs 600000`） |
| 擦除器选型（有实测依据） | `sucrase` **对所有 namespace 形式静默返回空串**（六种组合实测全丢，且不报错）⇒ 淘汰（正是"静默产出坏代码"）；`typescript@5.9.3` 正确但 9.1 MB（2.97×）；最终 `@babel/standalone@7.28.4`（3.07 MB，零依赖，只注册 `transform-typescript`、**不启用 preset** ⇒ 不会降级 `?.`/`??`），且 `retainLines` 默认必须 `false`（否则包壳会被切坏，实测 `ReferenceError: et is not defined`） |
| 接线写法 | profile 里「停用官方行 + `insert` 自己那一行」：`applyEntryPatches` 的普通 patch 只按键覆盖、`name` 字段仅作校验 ⇒ **不能靠改名换实现**；与仓库里 `fs-sandbox → dshm-fs-write-nonchmod` 同形 |
| 固化门禁（3 条，已进 `AGENTS.md` 必跑清单） | ① `check-ptc-ts-strip.mjs`：81 条断言 + **"读 WASM 即抛"的陷阱 getter 全程 0 触发** + vendor 无 `.wasm`/无原生 + 变异自检（证明非永真）② `check-ptc-runtime-inproc.mjs`：166 条断言，**整体跑在 `--jitless` 下**、并走**生产同款挂载路径**（`ctx.plugin(Plugin)` 不带 config，与 profile 那条 `insert` 一致）③ `check-ptc-wiring.mjs`：profile ↔ 打包清单 ↔ 源码树**三处一致** |
| **事故与教训（本轮真实踩坑，值得留档）** | 发布前最后一次打包恰好落在我造变异的中间态（`Config.timeoutMs` 的 `.default(12e4)` 被临时拿掉）⇒ 真机报 `timeoutMs must be positive and finite`、`ctx.ptcRuntime` 注册失败、**PTC 照旧不可用**；而当时仓库里**所有门禁全绿**（它们读的都是源码）。两条处置：① 插件**不再把 schema 默认值当唯一防线**（构造期自带同一份兜底值，缺键才补 —— 真机 Loader 的构造路径 `cordis/lib/index.js:1068` 实测不给 schema 默认值）；② 接线门禁新增"**树里那份必须与源码逐字节一致**"，它当场把这次事故复现成红 |
| 真机验收（2026-10-05 10:54，`-r` 覆盖安装 + 冷启动） | `did not activate` **0**（修复前为 1）、`timeoutMs must be positive and finite` **0**、`stripTypeScriptTypes` **0**、`WebAssembly is not defined` **0**；启动日志出现**运行时自证行** `[ptc] ctx.ptcRuntime = dshm-ptc-runtime-inproc（同进程纯 JS；…language=typescript isolation=in-process sandboxMode=undefined …；typeof WebAssembly=undefined）`；端侧插件文件与仓库源码**逐字节一致**（`index.js` 38,518 B，2026-10-05 复核；此前记 37,227 B 是自证哈希那次改动前的大小）；`home` 的 `links=13`/`size=3440` 安装前后不变 |
| 侧载包 | 重出为 sha256 `edb2a282…`（320,928,726 B / 306.06 MiB）；核心包 80.11 → **80.77 MiB**（+0.66 MiB 即本插件的擦除器 vendor） |
| 未验证项（如实登记） | `run_code` **工具级真实调用**仍需真机由会话触发（本轮验到的是：运行时已注册 + 自证行 + 本地契约 166 条 + 树/源码逐字节一致）；`node:vm` 在端侧 OHOS Node v24.2.0 上只被证明到"加载并注册成功"这一层；同步死循环会阻塞宿主线程、无独立堆、`node:vm` 非安全边界（均已写进插件注释与侧载 README 的"已知边界"） |

**一个把两次验证带偏的环境陷阱（记录下来，避免重犯）：ESM `import 'node:http'` 在 `--jitless` 下会炸**

排查期间我写的两个 harness 都在第一行 `import http from 'node:http'`，于是**测试自己**把进程搞崩，真正的结果被完全遮住，还一度让我得出错误结论。实测：

| 写法（均在 `--jitless --no-experimental-fetch` 下） | 结果 |
|---|---|
| `require('node:http')`（CJS） | ✅ 干净 |
| `import http from 'node:http'`（ESM，静态或动态） | 💥 进程在收尾时抛 internal undici 的 `WebAssembly is not defined`，**退出码 1** |
| `import('node:https')` / `import('node:net')` | ✅ 干净 |
| 同上但不带 `--jitless` | ✅ 干净 |

这是 Node 自身对 `node:http` 的 ESM facade 行为，与我们的代码无关；`dsh-host-webserver` 也是 `type: module` 且 `import { createServer } from "node:http"`，而 Host 是长活进程、被 kill 而非自然退出，故实践上不受影响。**对我们的要求很简单：端侧/jitless 相关的 harness 一律用 CJS `require` 取 `node:http`**（本仓 `main.js` 本来就是这样）。

**一次被编译器揭穿的"仓库不完整"事故（2026-09-14，已修）**

| 环节 | 事实 |
|---|---|
| 症状 | 新克隆的仓库编不过 `entry`：`COMPILE RESULT:FAIL {ERROR:8 WARN:33}` |
| 误判风险 | 第一反应是"缺构建产物"（原生头文件/预编译库）——**方向错了**，会白找很久 |
| 真因 | `entry/src/main/ets/runtime/NodeRuntime.ets` **从未进过版本库**（`git log --diff-filter=A -- '*NodeRuntime*'` 为空），而 3 个已跟踪文件 import 它：`EntryAbility.ets:40`、`Index.ets:134`、`Poc1.ets:21` |
| 根因 | `.gitignore` 第 35 行是裸的 `runtime/`（本意是根目录 172 MB 的 Electron 载荷）。**gitignore 的裸目录名在任意层级都匹配** ⇒ 连 `entry/src/main/ets/runtime/`、`hostruntime/src/main/ets/runtime/` 这类**模块源码目录**也被忽略。文件在开发机上"看得见"，在任何新克隆里"不存在"，**且不报任何错** |
| 8 个错误的构成 | 3× `Cannot find module '../runtime/NodeRuntime'` + 1× Rollup `Could not resolve` + 4× `arkts-no-any-unknown`（无法解析导入后的连带）⇒ **全部可归因到这一个文件**，没有一个是真的代码缺陷 |
| 修法 | ① `.gitignore` 规则锚定为 `/runtime/`（commit `ff6cbc9`）；② 把源码补回版本库（commit `b906e13`）。修后 `default@CompileArkTS` → **BUILD SUCCESSFUL（0 error / 32 warn）** |
| 教训 | ① `.gitignore` 的目录规则要**锚定**，或在路径里带上足够的上层目录；② **"本地能跑" ≠ "仓库完整"**——被忽略的文件只会在别人机器上消失，本地永远无感；③ 遇到"新克隆编不过"时，先问"**源码**齐不齐"，再问"**产物**齐不齐" |

> **工具链的环境坑（实测，必须记住）**：在 Linux 上跑 `devecocli build` 会让 ohpm 重写 **5 个受版本控制的 `oh-package-lock.json5`**（191 行全变），
> 原因是构建机把行尾写成 LF 而仓库在 Windows（`core.autocrlf=true`）下是 CRLF——`git diff --ignore-cr-at-eol` 为空即可确认是纯行尾差异。
> **每次构建后必须 `git checkout --` 回退这些文件**，否则提交里会混进 191 行噪声（本项目对"噪声 diff"有明确纪律）。

---

## 4. 矩阵

列的含义：**Web 行为**取自官方包自述（来源见 §7）；**Harmony 状态层/界面**给落地文件（可核对）；**协议/端点**给命名空间（完整契约在 D2b）；四形态列与整体 `Status` 按 §1 口径。

### 4.1 外壳与架构

| Feature | Web 行为（官方实现） | Harmony 状态层 | Harmony 界面 | 协议/端点 | Phone | Tablet | PC | 2-in-1 | Status |
|---|---|---|---|---|---|---|---|---|---|
| `layout` 外壳与三栏布局 | 三栏 AppFrame + 拖拽手柄；`ctx.layout` 查看态服务（导航 + 面板） | `appstate/ui/Breakpoints.ets`（`layoutModeOf` / `detailPanelAvailable` / `navPresentation`）、**`ui/LayoutController.ets`（P1：形态/几何决策的唯一落点，含让步链 `concedeDetail`）**、`ui/Tokens.ets`（`Sz.NAV_RAIL` / `NAV_PANEL` / `DETAIL_PANEL` / `DETAIL_MIN`） | **`pages/Index.ets` 已改为消费决策**：`applySize` 取 `decideLayout()`，navRail/detailColumn 的宽度取 `navWidthVp()`/`detailWidthVp()`（commit `fad954a`）——本文件不再有第二份断点/几何实现 | 无（纯前端） | DONE | DONE | PARTIAL | PARTIAL | PARTIAL |
| `slots` 槽位注册 | SlotMap 声明合并 + 单次 register 组合 API + 四方共享 props | 无（ArkUI 声明式，无插件槽位系统） | 无 | 无 | BOUNDARY | BOUNDARY | BOUNDARY | BOUNDARY | BOUNDARY |
| `primitives` 基础组件原子 | 纯 React 原子：控件 / 图标 / Markdown / JSON 检查器 | **P1.5 已建层**：`appstate/ui/HarmonyTheme.ets`（Web 语义 → HarmonyOS 视觉的映射：HarmonyColor/Type/Spacing/Radius/Border/Elevation/Motion/Touch + `WEB_TOKEN_MAP`） | `entry/.../view/NativePrimitives.ets`：`NativeChip` / `NativeSectionTitle` / **`NativeCard`** / **`NativeButton`** / **`NativeActionBar`**（+ `harmonySheetOptions` 参数助手）；真实消费者：**消息操作条、Composer 工具行与发送键、待决卡提交、工具卡 / 子代理卡 / 目标任务卡 / 交付物动作行** | 无（纯前端） | — | — | — | — | PARTIAL |
| `renderer` 渲染器与应用根 | React 槽位绑定 + `ctx.uiRenderer` + 组装后的应用根 | ArkUI 声明式 UI 由 `@Entry` 组件承载（无等价服务） | `pages/Index.ets` | 无 | BOUNDARY | BOUNDARY | BOUNDARY | BOUNDARY | BOUNDARY |
| `session` 会话控制器适配 | React 适配 + **会话作用域槽位** | `appstate/store/SessionHub.ets`（模块级单例 + `HubSnapshot` 投影 + subscribe/snapshot） | 各 Pane 订阅 `HubSnapshot` | 复用全部会话端点 | DONE | DONE | DONE | DONE | PARTIAL |
| `brand-official` 品牌槽位 | 侧栏 + 对话 Hero 槽位的官方品牌 | `docs/brand/`（icon/mark）、`AppScope` 图标 | Index 品牌头、连接页 | 无 | DONE | DONE | DONE | DONE | DONE |

### 4.2 会话与轨迹

| Feature | Web 行为（官方实现） | Harmony 状态层 | Harmony 界面 | 协议/端点 | Phone | Tablet | PC | 2-in-1 | Status |
|---|---|---|---|---|---|---|---|---|---|
| `conversation` 会话装配/外壳/输入区/队列 | 目标中立的 Conversation 装配、shell、composer、队列、视图导航 | **回合模型已落地**（`appstate/model/Turns.ets`：`groupTurns` / `hasProcessGroup` / `chatVisibleItems` / `processSummary` / `defaultExpanded`，纯函数 + 15 条断言）；**对话视图已改按回合渲染**：用户消息 → **过程分组（默认折叠、进行中展开）** → 回答（含 ActionStrip）→ 通知；轨迹视图保持全量条目台账。可见集合与折叠默认态都由模型回答（视图不再自写过滤规则） `SessionHub`：`sendPrompt` / `cancelTurn` / `removeQueuedItem` / `steerQueuedItem` / `editQueuedItem` / `selectSession` / `refreshTrajectoryByPage` | `view/ConversationPane.ets` + `view/Composer.ets` | `session/*`、`session/follow`（$events） | DONE | DONE | PARTIAL | PARTIAL | PARTIAL |
| `chat` 对话目标与详情面 | Chat Conversation 目标、节点定义、渲染器、详情面 | `SessionHub.projectWireRecord`（D2 §8.7.7 的 32 种事件）、`model/Detail.ets` | `ConversationPane` + `view/DetailPane.ets` | 事件流 + `session/page` | DONE | DONE | DONE | DONE | DONE |
| `trajectory` 轨迹台账与时间轴 | 轨迹事件台账 + **交互式时间总览**（timing overview） | `model/Trajectory.ets`（8 种 `TrajectoryKind`）、`model/Present.ets` | `ConversationPane` 轨迹区 | 事件流投影 | DONE | DONE | PARTIAL | PARTIAL | PARTIAL |
| `tool` 工具调用树与每工具呈现 | 工具调用树渲染器 + 按工具键的呈现槽位 | `ConversationPane.toolItem` 的 `callId` 合卡、`ToolState` 五态、`Present.previewOutput` 截断 | `ConversationPane` 工具卡 | `tool/call`、`tool/result` | DONE | DONE | PARTIAL | PARTIAL | PARTIAL |
| `subagent` 子代理目录与续跑 | 子代理会话目录、续跑路由 UI、`@` 引用源 | `TrajectoryKind.SUBAGENT`、`subagentCatalog` 投影、`model/Detail.ets` | `ConversationPane` 子代理卡 + `DetailPane` | `subagents/*` | DONE | DONE | PARTIAL | PARTIAL | PARTIAL |
| `deliverables` 交付物 | 产出文件回合尾 + **可点的终答文件引用** | `TrajectoryKind.DELIVERABLE`、`deliverables/presented`、`model/Workspace.ets` 的 `deliverable` 标记 | `ConversationPane.deliverableItem`、`WorkspacePane` 品牌色标记 | `deliverables/*` | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| `goal` 长期目标栏 | GoalBar 停靠在输入区上方，读 goal 会话投影 | `SessionHub.refreshGoal`（E243） | `Index.ets` 目标栏 | `goals/*` | DONE | DONE | DONE | DONE | DONE |
| `jobs` 后台任务清单 | 会话头部的后台任务列表（镜像 `session/jobs` 帧） | `model/Wire.ets` 的 `JOBS` 投影（`SessionJob`） | `ConversationPane` 的 `GOAL`/`JOB` 折叠块 | `session/jobs` 帧 | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| `workflow-run` 工作流运行节点 | 持久 workflow-run 会话节点 + 嵌套成员展开 | 无 | 无 | 无（`dshcompat/Endpoints.ets` 内无 workflow 端点） | TODO | TODO | TODO | TODO | TODO |
| `cordis` 动态插件定义卡 | `cordis_define` 工具行 + run/stop 开关 | 仅有宿主侧端点常量（`dynamicCordisRunner/inventory`、`getClientCode`），**未接 UI** | 无工具行 | 端点已登记、无调用点 | TODO | TODO | TODO | TODO | TODO |
| `skill` 技能引用与技能工具行 | Web 技能引用 + 专用 skill 工具行 | `SessionHub.refreshSkills`（`skills/list`，E135 触发点已修） | 设置页技能清单 | `skills/*` | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| `message-feedback` 消息反馈 | 每消息反馈控件（**类别 → 可选备注 → 提交 → 存储态 → 撤回**） | `SessionHub.putFeedback`（含 `category`）/ `clearFeedback`（撤回，`ifVersion` 做 CAS）/ `refreshFeedback` / `feedbackOf`；类别取值域与请求类型**按上游源码核对**（`dsh-message-feedback/lib/types/types.d.ts`） | 消息操作条：复制 + 有帮助/没帮助 + **类别/备注面板 + 提交 + 撤回评价**；**动作清单只有一份**（`messageActionsOf`），行内操作条与**上下文菜单**共用（长按 ≡ 右键，由 `model/InputPolicy` 决定手势集合）；原先那条**不可点的**"复制/引用/重发"标签行已删除——三个动作现在都真的能用 | `messageFeedback/put`（`ifVersion: string\|null`）、`messageFeedback/delete`（`ifVersion: string`，**幂等**） | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |

### 4.3 输入区与控制器

| Feature | Web 行为（官方实现） | Harmony 状态层 | Harmony 界面 | 协议/端点 | Phone | Tablet | PC | 2-in-1 | Status |
|---|---|---|---|---|---|---|---|---|---|
| `input-trigger` 输入触发管线 | `/` 与 `@` 检测、候选菜单、选路到已注册源 | `SessionHub.refreshCommands` / `refreshReferences` | `Composer` 的 `@`/`/` 弹层 | `commands/*`、`fileReferences/*` | DONE | DONE | DONE | DONE | DONE |
| `commands` 客户端命令面 | 全局目录缓存、`/` 源、**三种命令 UI 类型**、popupSelect 注册表 | `SessionHub.refreshCommands` / `executeCommand` | `Index.ets` 命令面板 | `commands/*` | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| `reference` 引用源 | 统一 Web `@file` 与 `@session` 引用源 | `SessionHub.refreshReferences` + `Wire.fileReferencesPayload` | `Composer` 引用弹层 | `fileReferences/list` | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| `attachment` 附件呈现 | 动态附件呈现：输入区、消息图、轨迹图三类槽位 | `SessionHub.attachLocalFile` / `attachWorkspaceFile` / `removeAttachment` / `clearAttachments` | `Composer` 附件条 | `fileUploads/*` | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| `model-selection` 模型选择 | 共享模型目录 + 会话投影 + `session.selectModel` | `SessionHub.selectSessionModel` / `setDefaultModel` / `refreshProviderCatalog` | `Composer` 模型与强度 chip + 设置页模型页 | `llm/*`、`settings/*` | DONE | DONE | DONE | DONE | DONE |
| `plan` 计划模式控件 | 输入区内的 plan 控件（`conversation.input.plan` 座位）+ `/plan` 通道 | `HubSnapshot.planActive` / `planPending`（判据按官方 chip 语义：`pending ? !active : active`） | `Index.ets` 面板内的计划开关（**不在 Composer 内**） | 计划投影 + 命令通道 | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| `permission-presets` 权限面 | General 里的新会话默认 + 会话内 `/permission` 弹层 | **只读**：`SessionHub.permissionsCurrent` / `permissionsOptions`（源码注明"切换需要 dsh-permission-presets"） | `Index.ets` 如实显示当前模式 | 读 `permissions` 投影；**无切换端点调用点** | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| `approval` 审批 | 审批**接管输入区**，作用于有作用域的 Remote Event 瀑布流 | `SessionHub.handleWaterfall` → `PendingItem`、`Present.sortPending`（危险 > 审批 > 提问） | `view/PendingPane.ets` 审批卡（三选 / 危险动作权重反转 / 原始载荷可展开） | `approval/*`（到达与答复链路已实测） | DONE | DONE | DONE | DONE | PARTIAL |
| `user-questions` 提问 | `ask_user_question` 的输入区接管 + 计划复核呈现 | `SessionHub.answerQuestion`（单选 / 多选 / 自由文本）、`PendingItem` | `PendingPane` 提问卡 | `user-questions/*` | DONE | DONE | DONE | DONE | PARTIAL |
| `agent-preset` 代理预设 | 三种面：后续会话的默认、**本会话座位**、**组合编辑器** | `SessionHub.refreshAgentPresets` / `copyAgentPreset` / `deleteAgentPreset` / `readAgentPreset`（`agentPresets/*`） | `SettingsPane` 预设区 | `agentPresets/*` | DONE | DONE | DONE | DONE | PARTIAL |

### 4.4 侧栏 / 工作区 / 设置

| Feature | Web 行为（官方实现） | Harmony 状态层 | Harmony 界面 | 协议/端点 | Phone | Tablet | PC | 2-in-1 | Status |
|---|---|---|---|---|---|---|---|---|---|
| `sidebar` 会话树 | 会话多级树、**搜索**、分组、状态点 | `model/SessionList.ets`（`pickTitle`、相对时间）、工作区为组 | `view/SessionListPane.ets`（标题/副信息/状态徽标/未读点/选中态） | `session/list` | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| `workspace` 工作区选择器 | 一个 WorkspacePicker 注册进侧栏与空态槽位 | `SessionHub.ensureWorkspace` / `openWorkspace` / `deleteWorkspace` | `view/WorkspacePane.ets` | `workspace/*` | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| `directory-picker-native` 原生目录选择器 | 无渲染的目录流占据者，驱动宿主 OS 选择器 | `platform/system/FilePicker.ets`（`pickFolder`）。**2026-10-06 手机实测修正**：`DocumentSelectMode.FOLDER` 在手机档**可用**（Mate 80 / OH 7.0.0.105 上两次选中均返回目录 URI），原先"仅 2in1"的说法与设备读数不符；真正的手持档约束是**目录授权的生命周期**（picker 授权只活一次进程 ⇒ 需 `persistPermission` + 启动 `activatePermission`，见 `docs/105`） | 由工作区流程触发 | `directoryPicker/*` | DONE | DONE | DONE | DONE | DONE |
| `directory-picker-browse` 应用内目录浏览 | 应用内目录浏览面：渲染宿主列目录与新建原语 | `SessionHub.toggleDirectory` / `openFile` / `closeFilePreview` | `WorkspacePane` 文件树 + 预览 | `workspaceFiles/*` | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| `settings` 设置域基础 | 设置命名空间作用域服务 + 权威设置槽位契约 | `SessionHub.refreshSettings` / `writeSetting` / `unsetSetting`（五种形态可写） | `view/SettingsPane.ets` | `settings/*` | DONE | DONE | DONE | DONE | DONE |
| `settings-general` 通用段 | 通用段 + 外壳触发/头部内容 + 设置词典 + 版本化欢迎通知 | 设置词典按官方译名覆盖（含 `locale.preference`） | `SettingsPane` 通用页 | `settings/*` | DONE | DONE | DONE | DONE | PARTIAL |
| `settings-models` 模型设置 | 模型设置 + 凭据联接 + 共享 onboarding 弹窗 | `SessionHub.setCredential` / `unsetCredential` / `refreshCredentials` | `SettingsPane` 模型页 + 凭据浮层 | `credentials/*` | DONE | DONE | DONE | DONE | DONE |
| `settings-plugins` 插件设置 | 插件段：功能自有页签 + 可配置宿主插件卡 | 用户行叠加（E91：种子 + 用户行，重启生效） | `SettingsPane` 插件页（启停 + 恢复默认） | profile 文件 + 插件清单 | DONE | DONE | DONE | DONE | DONE |
| `settings-plugin-inventory` 插件清单页签 | 只读 Cordis Loader 清单页签 | `model/Core.ets`（`classifyPlugin`）+ `tools/scan-core-plugins.mjs` | `SettingsPane` 插件清单 | 核心树扫描 | DONE | DONE | DONE | DONE | DONE |

### 4.5 主题与本地化

| Feature | Web 行为（官方实现） | Harmony 状态层 | Harmony 界面 | 协议/端点 | Phone | Tablet | PC | 2-in-1 | Status |
|---|---|---|---|---|---|---|---|---|---|
| `theme` 主题 | 插件前调色板 bootstrap + 无 DOM 的 ThemeRuntime（light/dark/system）+ `--dsw-*` 令牌样式 + 外观设置行 | `ui/Tokens.ets`（`Sp`/`Radius`(+`XS`)/`Fs`(+`CAPTION_XS`)/`Lh`/`Dur`/`Sz`/`Border`/`Breakpoint`/`SemanticColor`；`HarmonyColor.MASK` 统一模态遮罩）、`themeModeOf` / `applyThemeMode`；**`tools/check-design-tokens.mjs` 强制「裸值只许变少」**；`HarmonyMaterial.IMMERSIVE_ENABLED = true`（2026-10-11 接入应用级 `UIMaterial.state = enable`；target 已抬 26、设备 API < 26 时被平台忽略，`docs/147` §13） | 各 Pane 直接用 token；设置页外观行 | `settings/*`（外观键） | DONE | DONE | DONE | DONE | PARTIAL |
| `client-locale` 语言 | 宿主偏好 + 可扩展语言目录 + 内置词典 | 跟随系统语言（E117）+ `platform/system/Strings.ets`、`localizedOr` | 设置页「语言」（`locale.preference`） | `settings/*` | DONE | DONE | DONE | DONE | PARTIAL |

### 4.6 端侧独有（无 Web 对应；`dshm-` 前缀）

| Feature | Web 行为（官方实现） | Harmony 状态层 | Harmony 界面 | 协议/端点 | Phone | Tablet | PC | 2-in-1 | Status |
|---|---|---|---|---|---|---|---|---|---|
| `dshm-core` 核心版本管理 | 无（端侧独有） | `hostruntime/CoreStore` + `decideActivation` / `decideRollback` / `evictionCandidates` | `view/CorePane.ets`、`SessionHub.switchTo` / `rollbackTo` | 核心归档 + 事务 | DONE | DONE | DONE | DONE | DONE |
| `dshm-host` 端侧 Host 生命周期 | 无（Web 是浏览器客户端，Host 由 `dsh web` 提供） | `hostruntime/DshHost` + `runtime/NodeRuntime`（E90 协作式停止：本机实测退出码 0） | `CorePane` 起停 | 入口脚本 + `$DSH_HOME` | DONE | DONE | DONE | DONE | DONE |
| `dshm-diag` 运行时与连接诊断 | 无 | `SessionHub.diagnose()` + `connection` 的五项判定 | `view/DiagnosticsPane.ets` | `$events` `ready` 帧 | DONE | DONE | DONE | DONE | PARTIAL |
| `dshm-notify` 系统通知 | 无（Web 用浏览器通知） | `model/Notify.ets`（六类策略/去重撤回键） | `platform/notify/NotificationCenter` | 无 | DONE | DONE | DONE | DONE | PARTIAL |
| `dshm-hosttrust` 记住 Host 与凭据 | 无 | `platform/system/HostStore` + `SecretStore` | `view/ConnectPane.ets` | 认证面 | DONE | DONE | DONE | DONE | DONE |
| `dshm-multiwindow` 多窗口共享单一连接 | 无（一个标签页一个连接） | `SessionHub` 单例 + `platform/runtime/RuntimeSingleton` | 窗口账本（`registerWindow`） | 1 条 mux + 1 条 `$events` | DONE | DONE | DONE | DONE | PARTIAL |
| `dshm-share` 系统分享 | 无 | `platform/system/ShareBoard.ets` | 消息/文件操作 | 无 | DONE | DONE | DONE | DONE | DONE |
| `dshm-read-aloud` 原生朗读 / 分享 | 无（Web 没有系统 TTS / Share） | `platform/system/ReadAloud.ets`（Speech Kit `TextReader` 优先，Core Speech Kit `textToSpeech` 兜底，均离线）+ `ShareBoard.ets` | 官方 `conversation.chat.assistant-actions` 动作条（`dshm-read-aloud` 插件） | `__DSHM_BRIDGES__.readAloud / stopReadAloud / shareText` | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| `dshm-clipboard` 剪贴板 | 无 | `platform/system/Clipboard.ets`：**写**（`copyText` / `clearClipboard`）已接；**读**（`readText`）已实现但**未接线**，且需 `ohos.permission.READ_PASTEBOARD`（未声明） | 消息复制（多处 `copyText`） | 无 | DONE | DONE | DONE | DONE | PARTIAL |
| `dshm-window` 窗口记忆 | 无 | `platform/window/WindowMemory.ets` | 由 `EntryAbility` 驱动 | 无 | DONE | DONE | DONE | DONE | DONE |
| `dshm-shortcuts` 快捷键 | 无（Web 用浏览器快捷键） | `ui/Shortcuts.ets`（13 个规格，含不可绑定项标记） | `view/ShortcutKeys.ets` + `Index` 分派 | 无 | BOUNDARY | DONE | DONE | DONE | PARTIAL |
| `dshm-a11y` 无障碍 | 无（Web 走 ARIA） | `accessibilityText` + `Sz.TOUCH_MIN` | 各 Pane | 无 | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| `dshm-tool-fs-remove` 删除 / 移动 / 发布 | 无（官方 `tool` 面没有 `remove`/`move`/`publish`；端侧也没有可用的 shell 兜底） | `hostcore/plugins/dshm-tool-fs-remove`：`.partial` + `rename` **原子发布**、`displayPath` 与 `processPath` 分离（不给模型看进程路径）、删目录需 `recursive`、`publish` 目标根只认 `DSHM_PUBLIC_DOWNLOAD`（空则如实报错） | 官方工具卡片（无自带界面） | `ctx.fs` 工具契约（`tool-fs-remove` 三个工具） | DONE | DONE | DONE | DONE | DONE |
| `dshm-fs-write-nonchmod` 去 chmod 写入后端 | 无（上游 `dsh-fs-local` 的 `writeFileAtomic()` 三步都 `chmod`，在鸿蒙 hmdfs 的用户可见目录上必 `EPERM`） | `hostcore/plugins/dshm-fs-write-nonchmod`：`extends SandboxedFileSystem`、**只重写 `writeText`/`editText` 的落盘一步**（同目录 `.partial` → `writeFile` → `close` → `rename`，全程不 `chmod`）；其余方法与返回结构与上游逐字同形 | 无（透传官方） | `ctx.fs` 契约（对照表见 `docs/44`） | DONE | DONE | DONE | DONE | DONE |
| `dshm-workspace-claim` 工作区登记撤回 | 无（官方 `initializeDefault()` 在端侧必失败 ⇒ 客户端只弹一条「请通过'选择工作区'选择文件夹」的 warning，工作区由用户在 UI 里显式选择 —— 这正是官方语义） | `hostcore/plugins/dshm-workspace-claim`：**只撤不建**。注册表里若还留着本插件**早先**注入的那条（路径末两段 = `Download/<包名>`），就调官方 `workspaceRegistry.delete(id)` 撤掉（只删注册表一行，目录与任何会话日志都不动；撤完允许为空）；`registry.list()` 读不到则 fail-closed。**它不再登记任何工作区** —— 演变：2026-10-03「每次启动都登记」→ 2026-10-07「只在注册表为空时登记一次」（`docs/113`）→ **2026-10-13 整段删掉登记分支**（`docs/150`：全新安装首启注册表必然为空 ⇒ 又替用户建了一条他没选过的 `下载`；用户口径"不要替用户做选择"） | 无 | 工作区注册表 | DONE | DONE | DONE | DONE | DONE |
| `dshm-office-system-preview` Office 预览（系统预览窗） | 有（官方侧栏用**内置**渲染器预览 `doc/docx/ppt/pptx`；其 `read` 依赖宿主 `remote.officeToPdf`/LibreOfficeKit ⇒ 端侧**结构性不可达**） | `hostcore/plugins/dshm-office-system-preview`：`priority:"extension"` + `loading:"text-pages"`；**认领收窄为 Office-only 9 项**（`lib/client.js:79-93` 的 `EXTENSIONS` = `doc docx ppt pptx xls xlsx odt ods odp`；`ico` 已去掉，`md` 走内置文本渲染），图片 / PDF / HTML / 表格 / SVG **交回上游内联渲染器**；把文件交给**系统 PreviewKit 弹窗**。⚠️ 旧注写的"`workspaceFiles/readBytes` 每次被客户端立刻取消"**已被证伪**——真根因是宿主 undici 垫片 `DshmResponse` 不认 `new Response(FormData)`（见 `docs/97`） | 系统预览窗（`platform/system/FilePreview.ets`） | 侧栏 `open-in-app` 契约 | PARTIAL | PARTIAL | PARTIAL | PARTIAL | PARTIAL |
| `dshm-ptc-runtime-inproc` 同进程 PTC 运行时 | 有（官方 `@deepseek-ai/dsh-ptc-runtime-node`） | 官方实现在端侧**结构性不可用**（`stripTypeScriptTypes` 走 SWC **wasm**；`spawn` 子 Node 必 `EACCES`——`process.execPath` 是 `/system/bin/appspawn`）⇒ `hostcore/plugins/dshm-ptc-runtime-inproc`：`ctx.ptcRuntime` 服务 + `node:vm` 舞台（日志/超时/输出上限）+ **纯 JS** erasable-TS 擦除（vendor `@babel/standalone@7.28.4` 3,069,546 B，带 sha256 溯源） | 无（`run_code` 的工具卡片复用官方渲染） | `ctx.ptcRuntime` 契约（`resolve`/`run`） | DONE | DONE | DONE | DONE | DONE |

---

## 5. 统计（本轮）

| 状态 | 行数 |
|---|---|
| `DONE` | 19 |
| `PARTIAL` | 33 |
| `BOUNDARY` | 2 |
| `TODO` | 2 |
| **合计** | **56** |

> 统计口径：**矩阵 §4 各行 `Status` 列的计数**（56 行 = 39 个官方能力面 id + **17 个 `dshm-` 端侧独有行**）。
> **纪律（docs/README 第 8 条）：统计前先定口径，并把口径写出来。** 本节数字由 `node tools/check-parity.mjs` 实算核对——
> 首版手写的统计（18/22/4/2）与实算不符，正是这条纪律要防的错误；门禁现在会直接报出差额。
> **2026-10-05 补**：`dshm-` 行由 11 增到 16（补登 10/03 起的五个端侧能力面），同时给门禁加了
> **不变式 A2**——`REQUIRED_LOCAL_SURFACE` 里列出的端侧能力面必须各有行，否则红。此前"新增端侧能力"
> 没有任何门禁要求登记，这五行全是审计时才补上的。
> **2026-10-06 补**：`directory-picker-native` 的 Phone 列由 `BOUNDARY` 改 `DONE`（⇒ `DONE` 18→19、
> `BOUNDARY` 3→2），并**从 §6 撤掉**它的缺口登记（不变式 E）。依据是真机读数：手机档的
> `DocumentSelectMode.FOLDER` 两次都返回了目录 URI（`diag-select-returned count=1`），选中后
> 目录经持久授权可读可写、重启后仍可读（`workspaceFiles/{list,stat,readBytes}` 全通，原始读数与
> 时间线见 `docs/105`）。原先记的是"手机不支持系统文件夹选择器（`DocumentSelectMode` 仅 2in1）"
> —— 那是 SDK 注释的读法，**与设备读数相反**，按纪律以实测为准。设备验证轴仍按 §1.3 单独看
> （本次只有 Mate 80 / OH 7.0.0.105 一台手机的读数，平板未测）。

---

## 5.1 当前阶段：官方信息架构对齐（2026-09-14 重定义）

项目所有者于 2026-09-14 重定义本阶段：**停止「缺一个功能 → 加一个组件」，改为先把页面框架搭正确。**
工作令与分步计划见 `docs/ia-parity-plan.md`（P0 AppFrame → P1 Sidebar → P2 Main → P3 Rightbar → P4 Settings 域 → P5 视觉精修）。

判断依据是「**功能不少、页面还是不像官方**」——根因是信息架构没落地，而不是缺按钮：

| 层级 | 现状 |
|---|---|
| Host / 协议 / 会话状态 / 多形态几何 / 输入模态事实 | 🟢 |
| Prompt 泄漏（P0-1） | 🟢 已关闭（结构字段 + 单一判据 + 搜索作用域，388 条 fixture 全过） |
| Conversation 数据模型（回合 / 跟随 / 可见性） | 🟢 |
| **AppFrame / Sidebar 信息架构 / PanelRegistry / Settings 域** | 🟡 **AppFrame 已完成**（`ShellTracks` + `AppShell` 三形态轨道 + `SidebarShell` / `MainHeaderShell` / `RightbarShell` / `TrackResizer` 各有其主 + 浮层门户提到页面根；`Index` 5040 → 4290 行）；🔴 **剩余**：Sidebar 重建（P1）、Conversation（P2）、Settings 域（P4） |
| Markdown | 🟢 **P2-1 已落地**：`appstate/model/Markdown`（纯模型，31 条断言）+ `entry/view/MarkdownRenderer.ets`（`Text > Span` 行内富文本）；正文/思考/过程三处已从 `Text(item.body)` **原文照显**换成渲染。**刻意不做**：HTML、表格、嵌套列表（前者是安全问题，后两者 ArkUI 的 `Text/Span` 表达不了）——缺的部分原文照显，不假装支持 |
| 视觉精修 | 🔴 排最后（框架错则间距 / 颜色 / 动效全白做） |

---

## 6. 缺口登记（任何非 DONE 的行必须在此）

格式：`id` → 缺什么 → 下一步。门禁强制"矩阵里非 DONE 的 id 必须出现在本表"。

| id | 缺什么（对等差距） | 下一步（归属） |
|---|---|---|
| `dshm-office-system-preview` | 端侧**没有 Office 渲染器**，`doc/docx/ppt/pptx` 交**系统预览窗**（PreviewKit 的 `openFilePreview`）⇒ **系统不支持的类型 / 没有可用预览器时只能如实报"不可用"**，这不是本应用的渲染实现；预览窗是系统 UI，工具栏与返回行为不受应用控制。`xls/xlsx/csv/tsv` 仍走内置 Excel 预览（纯客户端，无此限制） | 不追平（端侧不自建 Office 渲染器）；随平台预览器覆盖范围演进自动受益。已写进 `dist/sideload/README.md` 的「已知边界」 |
| `layout` | ⓪ **右栏面板体系已落地（P3-1）**：`selectedRightPanel` 此前在模型里躺了好几轮没有消费者（右栏无条件渲染 `DetailPane`）——现在 `RightbarShell` 按**面板 id** 分派、标题取 descriptor 的 `label`，选择经注册表校验。**同时如实登记了缺口的真实位置**：官方那六个候选（文件/轨迹/工具/子代理/交付物/预览）**席位在、内容视图没做**，按 E110 的口径一律 `available: () => false`（不能填的入口不进选择集，避免"点进去是空面板"）；**右栏面板体系已收口（P3-2…P3-6）**：官方六个候选**全部接上**——**「文件」**（`FileTreePane`，与工作区页签共用）、**「轨迹」（P3-6）**（`TimelineOverview`，与主区轨迹视图共用；右栏只放总览，见模型注释）、**「工具」**（`ToolCard`，与过程流共用）、**「子代理」**（`SubagentCard`）、**「交付物」**（`DeliverableCard`）与 **「预览」**（`FilePreviewPane`）；另有本仓特有的 **「详情」**（`right.detail` = 已投影的 sections 清单，属官方 `conversation.detail` 那一类，**不冒充**「文件」）⇒ 共七个可用面板。可用面板 ≥2 ⇒ 标题行出现**切换器**（只有一个可用面板时不画）。**仍缺**：侧边面板滑入动画、面板自身拖拽调宽、单栏 Sheet 里的切换器。⇒ 后续把某个候选的内容视图做出来，只需把它的 `available` 改成 true，面板体系不用动① **拖拽调宽手柄已落地**（P3）：此前 `decideLayoutWithDetail` 那条"用户想要的宽度"路径在模型里做好、也有 fixture，**却没有 UI 去产生这个宽度**（`decideLayout()` 直接用常量）。现在三栏下栏间把手可拖，宽度存进 `detailWidthDesired`；拖拽策略（可用空间 `detailRoomOf`、夹取不跳变、**左拖变宽**的方向规则、记忆值收窄）全在纯模型里，25 条断言覆盖 ② **宽度记忆已落地**：`platform/LocalPrefs` 只存/取一个数字（平台层**不许**依赖 appstate，判定规则留在模型 `detailWidthOf`），启动读回、拖拽结束落盘；落盘失败给一句轻提示而不是静默失效 ③ **平板侧边浅层面板已落地**（P3 §12）：此前双栏与手机一样弹半模态 Sheet，把列表整个盖住，"边看列表边看详情"这件事就没了。现在详情呈现由模型的三值枚举决定并**真的被视图消费**——`DetailPresentation`：三栏=真右栏 / 双栏=侧边浅层面板 / 单栏=整页（顺带**删掉了此前那个`detailOverlay: boolean`：它算了却没有任何消费点，视图用自己的 `sheetKind()` 判断）。**仍缺**：侧边面板的**滑入动画**（transition 必须挂在面板自身的根上，而它与三栏右栏共用同一个builder，值得专门做而不是顺手加）、侧边面板**自身的拖拽调宽**（目前只沿用记住的宽度）、把手的**键盘调整**（聚焦后用方向键） ④ **待决（需真机）**：D3 §2 只按宽度判定 ⇒ **手机横屏（800vp 宽）会落成双栏**；要不要加高度/方向子句，看真机效果后定。另有一条**已实测的边界事实**：详情栏只在 TRIPLE（≥840vp）并排，而该档可用空间最小 320vp > `DETAIL_MIN`(260vp) ⇒ 让步链的 `DETAIL_CLOSED` 分支**当前不可达**（防御性保留，已钉成断言，将来调阈值时会**有意识地**让这条分支复活） | P3 已做：输入模态真实接入 + 拖拽把手 + 宽度记忆。下一步：平板侧边浅层面板；把手键盘调整；手机横屏档位子句（需真机） |
| `primitives` | ① 原语已落 `NativeChip` / `NativeSectionTitle` / `NativeCard` / `NativeButton` / `NativeActionBar`（+Sheet 参数助手）；**弹层/Dialog/导航**仍未原语化 ② **浮层已全部改原生、且宿主已提到页面根**：六类浮层（详情 / 枚举选择 / 目录 / 凭据 / 文本设置 / 整值设置）统一由**单一浮层宿主**承载——全应用只在**页面根**挂一次 `bindSheet`，`sheetKind()` 从既有状态**派生**当前该显示哪个（不另立字段，避免两个真值来源），`closeSheet()` 一处复位；手写遮罩与"整屏居中卡片"全部删除（遮罩由原生 Sheet 提供）。**修法说明（P0 收尾时发现）**：门户原先挂在**单栏布局的根节点**上，而四类浮层的触发点都在主区内容里（主区三形态都可见）⇒ **双栏/三栏下这些浮层根本打不开**（"不是没做，是够不着"）。提到页面根后与形态无关——这正是官方 Web「portal 挂在 `App` 根、不属于任何 pane」的语义（E292）③ `deliverableItem` 的保存/分享是**禁用+写明原因**（平台无文件保存能力） ④ `WEB_TOKEN_MAP` 目前是**文档化数据 + fixture 可校验**，但还没有"视图必须经映射取色"的强制门禁（现有棘轮只管裸 fontSize/圆角/描边/颜色字面量） | P1.5 已做：HarmonyTheme 语义层 + 前两个原语 + 两处接入（消息操作条、Composer 工具行）。下一步按 P1.5 清单推进（Surface/Button/Card/Popup/Sheet/Dialog/ActionBar/Navigation），每个原语都**当时就接一个真实消费者**，不落没人用的空构件 |
| `slots` / `renderer` | ① 官方是 React + 槽位插件化渲染；ArkUI 无槽位系统，第三方不能贡献 UI ② 但**「页面级 panel 选择」这层必须自建**（官方 `ui-layout` 正是用 panel selection 做统一框架）：`PanelRegistry` 属 `docs/ia-parity-plan.md` 的 P0/P3，与「第三方贡献 UI」是两件事，不要混为一谈 | 架构边界：**不追平**，能力由"构建期装配 + 设置页开关"替代；本条登记以免被当作缺陷反复讨论 |
| `session` | 无"会话作用域槽位"；控制器能力（`SessionHub`）已具备 | 不追平（同上）；控制器本身已 DONE |
| `conversation` | ① 回合渲染已落地（对话视图按回合 + 过程分组折叠/展开），但**轨迹视图仍是条目级台账**——§8 的"统一模型"目前只在对话视图生效 ② PC/2-in-1 列随 `layout` 的缺口 | P1 已做：回合模型（15 条断言）+ 对话视图按回合渲染 + 行数单位收敛 + **sticky-follow 独立成模型**（`model/Follow`，9 条断言；顺带修掉两个真实缺陷——切会话与发消息都不恢复跟随）。下一步：轨迹视图也按回合组织（或明确"它就是全量台账"并在文档里定死）。**更正一条此前的错误判据**：上一轮把"回答本身可折叠"写成缺口是错的——官方折叠的是**过程**，回答是回合的目的、收起它会把这一轮的意义藏起来；故**不做**，此项从缺口移除 | | P1：Conversation 重构（先做模型，再改视图） |
| `trajectory` | ① **交互式时间总览已落地**（`model/Timeline`，47 条断言）：轨迹视图上方给「总计 + 每格比例条 + **水平拖动可聚焦事件**」（官方 `timeline.overviewAria` 原文语义）+ 聚焦格详情（种类 / 第 n 格 / 开始于 / 耗时）。种类与文案**逐字取官方** `dsh-client-ui-trajectory`（`system/user/context/compacted/message/tool/subtool` 七个中文标签、`timeline.total/started/noTimingData` 文案）；比例用**累计起点**摆放（不是浮动相加，避免四舍五入出缝隙），拖动越界夹到首尾。顺带把**投影出来却一直没人显示**的 `sessionStats` 时间四项接上界面（模型用时 / 工具调用用时 / TTFT / TPS）；轮次与步数**不在这里重复**（会话头部那行已有，E125/E129） ② 我方条目→格子的映射有**四类刻意不产生格子**（交付物 / 目标 / 任务 / 错误；官方把错误记在格子上的 `isError`，不是一种 kind），且 `SUBAGENT` 一律算 `TOOL`（官方的 `tool`/`subtool` 之分需要父子调用关系，我方 `TrajectoryItem` 没有该字段） ③ **仍缺**：**逐步计时**（官方的「首 token / 解码」来自官方客户端自己的 metrics，`timingRecorded` 只存在于其 bundle 内，我方投影没有 ⇒ 没有消费者的函数不留，故本模型不提供；要按步显示得先让投影带上这些字段）；**双向联动已做**：条 → 列表（拖动松手/点选后滚到那一格对应的条目，用 `ScrollAlign.START` 对齐，这样"列表首行"与"聚焦格"一致、不会自己抖自己）+ 列表 → 条（滚动时首行对应的格子自动聚焦，拖动条期间关掉这一路以免互相覆盖）；聚焦条目在列表里用**左侧色条**标出（与搜索命中的 brand 色区分，用 `font_emphasize`）。**仍缺**：inspect 意义上的"点格子打开该条详情/参数"（当前只滚过去 + 显示一行摘要）；`SYSTEM`/`CONTEXT`/`COMPACTED`/`SUBTOOL` 四种种类**保留但暂不可达**（我方投影没有对应事件类型，保留是为了标签表与官方一致） | P2 已做：映射规则 + 比例条 + 拖动聚焦 + 统计四项。下一步：投影接逐步 metrics；点格子打开该条详情（真正意义的 inspector） |
| `tool` | ⓪ **`web_fetch` 在端侧 jitless 下曾完全不可用**（根因、修复与对照实验见 §3.2；已由 `tools/check-web-fetch-jitless.mjs` 固化；真机起线程一项仍待验收）① **`ToolPresenter` 已落地**（`model/ToolPresentation`：终端/读取/写入/编辑/搜索/网络/图像/提问 + 通用，17 条断言；图标、语气、展开默认态、无障碍文案都由模型判定，视图只映射）② **路径摘要已落地**（`toolSummaryOf`，12 条断言：终端的命令 / 读取的路径 / 搜索的"模式 · 范围" / 网络的 url；提炼不到才退回清理后的原文——此前这里写着"直接显示参数原文"，是过期描述，已更正）③ **改动对照已落地**（`model/ToolDiff`，45 条断言）：`write`/`edit`/`str_replace_editor` 出加/减行对照并逐行着色，规则逐条对齐官方 `intendedDiff`/`validEscalationFields`（含提权闸门、空 `old_string` 归一成 null、`replace_all` 类型校验、路径 trim 判空），失败/被拒**不出**对照卡（对齐官方 `isError → null`）④ 仍缺：**applied 对照**（官方结束后优先用工具结果 `meta.diffs` 显示"实际落盘"的改动；本仓投影只解析 `TOOL_NAME`/`TOOL_ARGS`/`TOOL_OUTPUT`/`CALL_ID` 四个槽位、**未携带 `meta`** ⇒ 只能显示"意图"）；**嵌套调用不区分**（官方对 `parentCallId !== undefined` 不出对照卡，而 `TrajectoryItem` 无父子关系字段）；结果预览的类别化（图像类应出缩略而非等宽文本）；对照的逐行着色**折叠阈值**是呈现层取舍（官方阈值无证据，未假装对齐） | P2 已做：类别判定 + 每类一个系统符号 + 失败默认展开 + 按类别提炼摘要 + 改动对照卡。下一步：确认事件里 `meta` 的槽位名并接进投影（applied 对照）；图像类结果缩略 |
| `subagent` | 无续跑路由 UI；子代理不作为 `@` 引用源 | P2 |
| `deliverables` | ① **右栏「交付物」面板已落地（P3-4）**：`DeliverableCard` 与过程流共用同一份卡；筛选是纯模型（`itemsOfKind` / `deliverablesOf`：保序 + 同 id 去重）；空态如实说明「本次会话还没有交付物」② 剩余：终答正文内的可点文件引用未接（只有独立交付物条目 + 工作区标记）；「保存 / 分享」因平台没有文件保存能力而**可见但禁用**（原因写在无障碍文案里）| P3-4 已做面板；正文内文件引用待 P2 收尾 |
| `jobs` | ① **会话头的后台任务条已落地（P2-2）**：模型 `appstate/model/Jobs`（40 条断言：live 判定 / 状态点语义 / 五种文案 / 时长三档与小时封顶 / 排序 / 计数 / 定时器按需）此前**一个视图消费者都没有**——中枢一直在维护 `jobs` 字段，界面只在轨迹里显示 `JOB` 行。现在：中枢投影 → `Index` → `MainShell` → 会话头上的任务条（有任务才出现；`Flex(wrap)` 任务块：状态点语义色 + 名称 + 状态文案 + 耗时，live 任务每秒走字，`jobTickerNeeded` 决定要不要开定时器；无障碍整段取自 `jobListA11y`）② 已用 `tools/check-feature-wiring.mjs` 把这条接线**钉成回归**（模型判定 + 中枢投影 + 会话头传参三段）③ 剩余：轨迹里的 `JOB` 行与任务条仍是两处呈现（官方只有一处）；任务详情（参数/输出）未接 | P2-2 已做：任务条。下一步：轨迹 `JOB` 行与任务条收敛为同一处语义；任务详情下钻 |
| `workflow-run` | 完全未实现；**协议侧也无 workflow 端点**（`dshcompat/Endpoints.ets` 内无匹配） | 先确认上游是否暴露 workflow 端点；无端点则本行长期 `TODO`（**不造无协议支持的假后端**） |
| `cordis` | 无 `cordis_define` 工具行与 run/stop 开关；端点已登记但无调用点 | P2/P3：需要 keyed tool row 能力（与 `tool` 同一批） |
| `skill` | 无对话内技能引用；无专用 skill 工具行 | P2 |
| `message-feedback` | ⓪ **面板已拆成独立组件（P2-3）**：`view/MessageFeedback.ets`（表单态归它，每敲一个字不再重绘整个会话列表）；宿主保留"哪条开着 + 回执 + 提交策略"。① **Edit / More 未接**（Retry 已接：用户消息的"重发"走 `session/prompt`，有真实协议面；助手消息的"重跑那一轮"无端点 ⇒ 不给）（§10 列出的其余操作）：它们需要「重跑某一轮 / 改完再发」的协议面，本仓**没有对应端点** ⇒ 不放点了没反应的按钮（假入口），缺口显式留在这里 ② 面板与 chip 的**观感、触摸目标、四形态**均待真机验收 | P1 已做：类别（契约 7 个取值）→ 可选备注 → 提交 → 存储态回显 → **撤回**（`messageFeedback/delete` + CAS）；P2：Retry/Edit 需先确认协议面是否存在 |
| `commands` | 三种命令 UI 类型未细分；`popupSelect` 注册表语义未对齐 | P2 |
| `reference` | `@session` 引用源未确认（`@file` 已通） | P2：与子代理目录同一批 |
| `attachment` | 消息内图片、轨迹图片两类槽位未接（输入区附件已通） | P2 |
| `plan` | **更正一条过期描述**：本行原先写「控件不在 Composer 内／`/plan` 通道未对齐」——实际两件都已就位：`Composer.toolRow()` 里有「计划」chip（官方 `conversation.input.plan` 座位，判据 `pending ? !active : active` 与官方一致），宿主 `togglePlan()` 走的就是 `/plan` 命令（`executeCommand`）。剩余：chip 的观感与触控目标待真机验收 | 已就位（真机验收见 `docs/device-validation.md`） |
| `permission-presets` | **只能显示不能切换**；无 General 里的新会话默认项 | P1：需要 `dsh-permission-presets` 对应端点的调用点；先确认协议（D2b）再接线 |
| `approval` | 交互位置对等差距：官方是**输入区接管**（在对话上下文里答复），DSHM 是独立的「待决」聚合页；`Present.sortPending` 的排序已是官方语义 | P1：`PanelController` + Composer 接管式界面（与提问卡同一批） |
| `user-questions` | 同上：官方是 `ask_user_question` 的输入区接管 + 计划复核呈现，DSHM 落在待决页 | P1：同上（与 `approval` 同一批） |
| `agent-preset` | 缺**组合编辑器**（composition editor）与「后续会话默认」的显式面；复制/删除/查看已有 | P2 |
| `sidebar` | ① **官方 Sidebar 不是「页签栏」**：它承担 Brand / New Session / **Workspace→Session 树** / Panel 列表 / Settings（固定底部）/ 折叠 rail。我方当前页签只有 工作区 / 核心 / 设置（`SESSIONS` 是 `WORKSPACES` 别名、`PENDING` 不占页签），本质仍是**传统 Tab 架构** ② **更正一条过期描述**：本行原先写"我方是 `WorkspacePane` + `SessionListPane` 两个并列 Pane"——`SessionListPane`（221 行）**早就没有任何渲染点**（E108 把「会话」页签并进工作区视图之后，会话列表改由 `workspaceGroup` 渲染；它只剩 Index 里的一条死导入）。P1-1 已**删除该死文件**，并把主区里那棵真实的树（`workspaceHub` + `workspaceGroup`，285 行）抽成 `view/WorkspaceBrowser.ets`（30 门面成员，**一行都不用改名**——它本来就只经显式门面访问宿主）③ **树已挂进侧栏**（P1-3）：`SidebarShell` 的 PANEL 呈现里，树在品牌行与面板入口之间（官方顺序）；窄版行（P1-2）为 240vp 宽改行不改树。三栏下主区的「工作区」页签**不再重复一份**，只说明"列表在左侧"（判据取自 `ShellTracks`，与 AppShell 选轨道同源）。单栏 / 双栏仍由主区承载（底部标签栏 / 图标条放不下树）④ **一级导航已改由注册表驱动**（P1-4）：入口的存在/顺序归 `sidebarEntries` / `sidebarPinnedEntries`（沉底是清单属性 `SIDEBAR_PINNED_ORDER`）、图标与文案归按面板 id 的编译期映射、高亮归宿主；`SidebarShell` 里再无 `NavTab`。`NewSession` 已成为品牌行下方的一级入口；Settings 沉底；核心席位按 E110 标记为不可用（语义写进模型，不再靠视图"恰好没遍历它"）⑤ **单栏已是抽屉**（P1-5）：手机侧栏按官方语义"盖在页面上"（页头根页有导航入口、点外部收起、返回键第一优先级收抽屉、选入口/会话自动收起）；底部标签栏**暂时保留**（过渡，见 `docs/50` E306）。剩余：无会话搜索；无「分组」显式交互（现为工作区为组）；RAIL 上无 NewSession | P1-1…P1-5 已做（树抽出 → 窄版行 → 挂进侧栏 + 主区去重 → 注册表驱动入口 + NewSession + Settings 沉底 → 单栏抽屉）。**下一步（P1-6）**：会话搜索、"分组"、RAIL 上的 NewSession；真机确认后决定手机是否撤掉底部标签栏。真机项见 `docs/device-validation.md` **D11/D12** |
| `workspace` / `directory-picker-browse` | 真实文件树受 `workspaceFileScopeId` 阻塞（D4 已登记的未决来源） | 先确认该 id 的来源（协议事实）再接线 |
| `settings-general` | ① **P4-1：设置分区已进注册表**（`PanelLocation.SETTINGS` + `settingsSections()`；官方四段在前、本仓特有四项标 `owner: 'dshm'` 在后）；分区状态回归 `NavigationState.settingsSection`（视图里的 `@State tab` 已删除）② 版本化欢迎通知未确认 | P2 剩余：欢迎通知；P4-2：设置页按域拆组件 |
| `theme` | ⓪ **沉浸光感（API 26 空间化材质）已接入**：`targetSdkVersion` 已抬到 26，应用级开关 `module.json5` 的 `ohos.arkui.UIMaterial.state = enable`（2026-10-11 拍板，`docs/147` §13）；**设备 API < 26 时被平台忽略**（API 24 平板退回阴影层级）；材质只覆盖**原生浮层**（Dialog/Menu/Sheet/文本选择菜单），渲染面是 Web 画布 ⇒ 不给 Web 界面换皮；光感**强弱由系统设置「沉浸光感」决定**，应用改不了。① 无 `--dsw-*` 等价的**可声明令牌层**——现在是「token 常量 + 棘轮门禁」，不是可被主题切换的声明式变量；无 visual swatch ② **存量裸值 21 处 / 8 个文件**（2026-09-28 重测）已被棘轮冻结——旧记的"58 处 / 11 文件"及其分解（图标字号 46 / 圆角 5-9 / 颜色 14 处）是 2026-09-15 的读数，`tools/design-token-baseline.json` 的 `generatedAt` 仍为 `2026-09-15`、`total: 21`；剩下这些仍需一次设计收敛——**收敛会改变视觉，必须真机验收**，故不塞进机械替换 | P1 已做：token 补齐（`Border.HAIRLINE` / `Radius.XS` / `Fs.CAPTION_XS`）+ **机械替换 36 处**（数值不变 ⇒ 视觉无变化）+ 棘轮门禁。P2：图标档位与圆角的视觉收敛（真机）+ 声明式令牌层 |
| `client-locale` | 语言目录可扩展性未确认（官方支持扩展目录） | P2 |
| `dshm-diag` | 诊断页 `home=` 仍显示桩值 `D:/work`（D4 待收口第 2 项） | 核实 `runDiagnostics()` 与 `getHostHome()` 空值路径 |
| `dshm-notify` | 逐条通知的渠道路由被 SDK 标称枚举不一致阻塞（D4「仍待真机」第 5 项） | 真机阶段验证 |
| `dshm-multiwindow` | "1 条 mux + 1 条 `$events`"的抓包核对待设备 | 真机阶段验证 |
| `dshm-shortcuts` | 表与分类完成；**绑定与实机响应待验收**；Phone 不适用（无实体键盘） | 真机阶段验证 |
| `dshm-a11y` | 朗读文本与触摸目标已实现，**待真机朗读验收** | 真机阶段验证 |
| `dshm-read-aloud` | 原生朗读/分享入口已接线并编译通过；**真机 TextReader 面板/后台/降级与 Share Kit 面板未验收** | 真机阶段验证（手机 / 平板 / 2in1） |
| `dshm-clipboard` | **读**剪贴板不可用：`readText()` 需要 `ohos.permission.READ_PASTEBOARD`（API 12 起），应用未声明该权限；且 `readText` 全仓只有「定义 + 桶导出」2 处 ⇒ 按 E257 判据属**登记了没接**（粘贴入口本就没做）。写（复制）正常 | 决策点：① 若要支持「粘贴到输入区」，需评估声明 READ_PASTEBOARD 对上架/权限最小化策略的影响；② 若不支持，则把 `readText` 从桶导出里摘掉或明确标注为未接。**不允许挂着不动** |

> 与"行"无关的实测发现（构建/静态检查的技术债、以及 `entry` 无编译验证这一环境事实）不放进本表——
> 它们是**工程事实**，写在 §3 / §3.2；本表的每条必须对应 §4 的一个行 id（门禁会拒绝幽灵登记）。

---

## 7. 覆盖与来源

### 7.1 行集来源（可复现）

官方能力面 = 本机安装的 `@deepseek-ai/dsh` 依赖树里**全部 38 个** `dsh-client-ui-*` 包 + `dsh-client-locale`：

```
agent-preset approval attachment brand-official chat commands conversation cordis
deliverables directory-picker-browse directory-picker-native goal input-trigger jobs
layout message-feedback model-selection permission-presets plan primitives reference
renderer session settings settings-general settings-models settings-plugin-inventory
settings-plugins sidebar skill slots subagent theme tool trajectory user-questions
workflow-run workspace            （38 个）
+ client-locale                   （= 39 个官方能力面 id）
```

复现命令（在装着官方 dsh 的机器上）：

```bash
ls -d /opt/dsh/node_modules/@deepseek-ai/dsh-client-ui-* | sed 's#.*/dsh-client-ui-##' | sort
```

### 7.2 来源与版本标注（纪律：每条事实标注出处）

| 事实 | 来源 | 版本 |
|---|---|---|
| 官方能力面清单与各包行为自述 | 本机安装的官方客户端包 `package.json`（`name` / `description` / `dsh.client`） | ⚠️ **0.1.2-alpha.1（落后于当前基线；2026-09-30 已复核，缺口见下方同一性提示）** |
| 各 `Web 行为` 列文案 | 由上述 `description` 意译（不新增未经查证的断言） | 同上 |
| Harmony 落点 | 本仓库源码（行级可核对，见各单元格文件路径） | HEAD `33662bd`（2026-09-30 核对；此前标注的 `af00b0b` 已不在本仓历史中） |

> ⚠️ **同一性提示**：本项目的协议基线是 **0.2.1-alpha.1**（D2 §0 / D5 §4.1），而 §7.1 的能力面清单来自 **0.1.2-alpha.1**。
> 因此 §7.1 的能力面清单**需要用当前基线复核一遍**。**本轮复核已做（rc.2 时），结论是清单确实落后**：核心树
> `dist/core/work/dsh-core-0.2.1-alpha.1/node_modules/@deepseek-ai/` 下有 **53 个** `dsh-client-ui-*`，
> 比清单多 15 个（`open-in-app`、`plugin-manager`、`schedule`、`settings-account`、`settings-agent-loop`、
> `settings-session-log`、`settings-shell`、`settings-subagent`、`settings-web-search`、`shortcuts`、
> `sidebar-browser`、`sidebar-documentpreview`、`sidebar-files`、`sidebar-right`、`sidebar-terminal`）；
> 更稳的基准是 `dsh-web-app/package.json` 的依赖表（`0.2.1-alpha.1` 下 **135 条依赖**，`0.2.0-rc.2` 是 131 条，
> +4 全部来自闭包变化；与清单的差集仍是上面 15 个）。⚠️ 顺带一个**升级中性**的读数：两版核心树的
> `dsh-client-ui-*` **同为 53 个且集合逐条相同** ⇒ 依赖闭包变化没有动 UI 能力面。
> 这 15 个是否各自建行、还是按既有惯例粗化进 `sidebar` / `settings` 行，
> **尚未裁定**（详见 `review-report-2026-09-29.md` 的 6-M7）。
> 复核方法：`node tools/check-parity.mjs` 会在清单与实际行集不等时报出差集。

### 7.3 门禁

```bash
node tools/check-parity.mjs              # 校验本矩阵（覆盖 / token / 不变式 / 缺口登记）
node tools/check-parity.mjs --self-test  # 注入式自检：证明它会失败（未被负测试验证的门禁等于没有门禁）
node tools/check-parity.mjs --list       # 打印解析出的行与状态

node tools/check-layout-fixtures.mjs              # 四形态 + 断点边界 + 让步链（纯逻辑，无需设备）
node tools/check-layout-fixtures.mjs --self-test  # 证明断言器会失败
                                                  # **2026-09-30 起 Windows 直接可跑，不需要任何 shim**：
                                                  # findTsc() 内置了 IDE 自带 typescript 的候选路径
                                                  # （旧法：junction 暴露 <IDE>\tools\hvigor\hvigor\node_modules\typescript，
                                                  #  2026-09-28 曾靠它拿到 768 条断言 / 0 失败）

node tools/check-arkts-entry.mjs              # 编 entry（UI 层）的 ArkTS：P1~P3 改 Index.ets/Pane 的守护
                                              # Windows 本机可直接跑（2026-09-28 修掉四处 Linux 布局写死）
node tools/check-arkts-entry.mjs --clean      # 强制真正重新编译（增量时 CompileArkTS 会被 UP-TO-DATE 跳过）
node tools/check-arkts-entry.mjs --self-test  # 判定器自检（9 个样例，含"hvigor 失败却退出码 0"的真实形态）
```

---

## 附 A：`Index.ets` 依赖关系与拆分基线（P1 输入）

**现状**：`entry/src/main/ets/pages/Index.ets` = **4613 行**、**22 个 `@Builder`**、约 60 个方法，承担五类职责：

| 职责 | 现状落点（Index.ets 内） | 目标归属（计划 §3/§7） |
|---|---|---|
| 布局决策 | `applyWidth`、`layoutModeOf` 调用点、`Sz.NAV_RAIL` 判断 | `LayoutController` |
| 页面装配 | `mainContent`、`tabContent`、`buildSingle/Double/Triple` | `AppShell` + `MainContent` |
| 一级导航 | `bottomTabs`、`navRail`、`navPanel`、`navPanelAction` | `NavigationController` |
| 会话/输入区 | `header`、`hubBanner`、`workspaceHub`、`workspaceGroup`、`coreTabContent` | `Conversation/Composer/Workspace` 控制器 |
| 设置表单与审批 | `textSettingSheet`、`structSettingSheet`、`credentialSheet`、`folderSheet`、`choiceSheet` | `SettingsController` / `PanelController` |

**已经分出去的部分**（不用重做，避免重复实现已有功能）：

| 层 | 文件 | 被谁用 |
|---|---|---|
| 设计令牌 | `appstate/ui/Tokens.ets` | 各 Pane（`Sp`/`Radius`/`Fs`/`Sz`/`SemanticColor`） |
| 断点与档位 | `appstate/ui/Breakpoints.ets` | `Index`（3 个调用文件） |
| 快捷键表 | `appstate/ui/Shortcuts.ets` | `Index` + `view/ShortcutKeys.ets` |
| 设备事实 | `platform/system/DeviceFacts.ets` | 仅 `EntryAbility`（窗口账本）与 `RuntimeSingleton` |
| 系统能力 | `platform/system/*`（文件选择/剪贴板/通知/分享/窗口记忆） | 各 Pane 经 `platform` 桶导入 |

**本轮发现的三处硬事实**（可直接作为 P1 的起点）：

1. **`navPresentation` / `NavPresentation` 只有 2 处引用**：定义（`Breakpoints.ets`）+ 桶导出（`appstate/Index.ets`），**没有任何界面调用点**。
   按项目既定判据（E257：**1 处该删，2 处该登记**），它属于"登记了没接"：**导航呈现决策没有真的走布局层**，`Index.ets` 里自己按宽度与 `Sz.NAV_RAIL` 判。
   → P1 第一刀：让 `LayoutController` 消费 `navPresentation`，否则删掉这个会撒谎的 API（二选一，不允许挂着不动）。

2. **布局决策确实只由窗口宽度驱动**：全仓 `FormFactor` / `readDeviceFacts` 只出现在 `EntryAbility`（窗口账本登记）与 `RuntimeSingleton`，**没有任何 UI 用它做布局分支**。D3 §2.2 的硬规则在实现上是成立的（不需要先修）。

3. **系统能力调用直接落在 `Index.ets` 上**（P3 落点证据）：
   `Index.ets:839 applyThemeMode`、`:1211/:2818/:3094 copyText`、`:1390 pickDocument`、`:1794 pickFolder`。
   官方对等物是 `platform/*`，而计划 §15 要求"业务代码不得直接散落平台判断"。
   → P1 建 `PlatformAdapter` 边界时，先把这 6 个调用点收进适配层；**`deviceType` 判断本身目前没有散落**（这点是好消息）。

**拆分顺序（计划 §7，每次拆完保持门禁全绿）**：

```
1) layout decision    → LayoutController        ✅ 已做（Index 已消费，行为等价，commit fad954a）
2) navigation         → NavigationController    ✅ 已做：返回键 7 级优先级阶梯 + 页签归一化/清栈/静态事实重读
                                                  全部搬出，54 条 fixture 断言覆盖（含"浮层内部先后"）
3) detail/right panel → PanelController         待做
4) command palette    → PanelController         待做
5) composer           → ComposerController      待做
6) conversation       → ConversationController  待做
```

每一步的验收：`arch-check` / `check-feature-wiring` / `check-store-readiness` / `check-parity` /
`check-arkts-entry` / `check-layout-fixtures` / `check-design-tokens` 全绿 + 本矩阵对应行状态**只升不降**（门禁强制）。

> **第 2 步顺带发现的一个坑（值得记住）**：`NavTab.SESSIONS` 是 `'workspaces'` 的**别名**（E108 会话并入工作区），
> 所以"在会话页签"与"在工作区页签"是同一个状态、**不存在 `'sessions'` 这个取值**。
> fixture 第一版把它当独立值用，立刻红了两条——这正是把导航搬成纯函数想要的效果：
> 这类语义坑以前只存在于 `Index.ets` 的内联判断里，没人能单独测它。

---

## 变更记录

> 本文件只保留**当前矩阵与统计**。v1.35–v1.52 的逐轮变更过程已归档到 `docs/archive/`
> （其中引用的 `docs/50`、`docs/105` 等编号文档同样在 `docs/archive/`）。
> 规则：改矩阵只改 §4/§5/§6，并在 `.workbuddy/memory/` 记一行；不再往本文件追加流水账。

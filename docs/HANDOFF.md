# 当前状态（HANDOFF）

> 只写**现在**：在版版本、最新交付、已完成、没做完、下一步。
> 不记过程流水账；过程性内容一律进 `docs/archive/`。
> 版本 / 核心 / 设备面 / 权限以代码与配置为准，本页抄写值仅作对照。

---

## 1. 一眼状态（2026-11-26）

| 项 | 值 | 真源 |
|---|---|---|
| 应用版本 | `1.1.8 / 1010020` | `AppScope/app.json5` |
| 核心 | `0.2.3-alpha.2+dshm.1` | `hostcore/core-recipe.json` |
| 权限面 | entry 19 / phone 9 | `tools/check-permission-surface.mjs` |
| 设备面 | entry: tablet+2in1；phone: phone；hostruntime: 三端 | 各 `module.json5` |
| 全量门禁 | 134 条 / **全过（134/0）**（`dist/acceptance/20261126-full-gates-r4.txt`；较 133 新增 `check-webserver-route-auth`；基线 `…20261126-full-gates.txt`） | `gates.yml` |
| 本机设备 | **本机即该鸿蒙 PC**：MateBook 14 2in1，API 26，无线调试常驻 `127.0.0.1:45595` | `hdc tconn 127.0.0.1:45595` → `devecocli device list` |
| 可侧载包 | `dist/beta/DSHM-beta-1.1.8-1010020-20261125T234348-local/`（**最新**，本机调试签名；容器 `44627a39…`；含 R4 py-site 投放修复；**未装机**，用户手动安装） | 包内 `README-LOCAL.txt` |
| Beta 包 | `dist/beta/DSHM-beta-1.1.8-1010020-20261125T234114/`（**最新 canonical**，容器 `44627a39…`；早前 `…T164248` 无 R4 修复，`…T150452`/`…T152500-local` 为裁剪容器 `dabc48c7…` 已被勘误废弃） | 目录内 `SHA256SUMS` |
| AGC 包 | `dist/release-test/dshm-1.1.8-1010019-dshm.1-AGC-invite-20261119T132959.app`（sha `fb43c767…`，核心 rc.5，含 JD-012/013） | `.app.sha256` |

**版本 1010019（2026-11-19 晚，用户明确要求）：编入 JD-012（平板分屏/小窗装饰链）与 JD-013（手机登录外开/最近任务沉浸），上架预审无本地阻断。**
**1010018 已推送邀请测试（2026-11-19）；正式上架未提审；平板/手机未做本版真机验收；重提前置（控制台）：隐私政策 P0 编辑过审、演示录屏、竖屏复验。**

## 2. 最近完成

0. **真机诊断修复轮（2026-11-26，用户交两台真机诊断报告要求一并修好重出 Beta）**：
   ① **401 修复**：`hostcore/app/main.js` 10 处 + `dshm-pet-host.cjs` 1 处本地 `/dshm-*` 路由补
   `auth:'anonymous'`（0.2.3 webserver 默认 `auth ?? "required"`，走 admission 鉴权即 401；
   真实防护保留 token 检查 + 403 栅栏）；新门禁 `tools/check-webserver-route-auth.mjs`
   （11 路由 + 6 自检变异臂）入 `gates.yml`。② **R8 修复**：PTY dlopen 缓存记录加 `corePath`
   字段，核心更换后探针自动失效，不再指向旧核心路径。③ **office 勘误回滚**：真机硬报
   `Cannot find module '@deepseek-ai/libreoffice-kit-wasm/package.json'` ⇒ 配方删该 prune 规则
   （`$comment_keep_libreofficeKitWasm` 留证），img-sharp-wasm32 维持裁剪；`pack-core
   --force-install --place-in-app` 重打容器 **204.8 MiB / sha `44627a3908e45415…`**
   （关键坑：`--skip-install` 复用已破坏暂存树出假容器，见坑档）；OSS 声明重生成（710 组件）。
   ④ **R4 补修**：`ensurePythonSitePreset()` 原先只挂在「本轮刚解 python」的收尾分支，升级用户
   `py-site` 恒空（诊断 v3 R4）⇒ 稳态 boot 也补投（幂等，仅空目录解）；另加 boot 探针
   `office-kit-wasm`（host-ready natives）防 R3 类回归。
   ⑤ **P2-3 桥探测噪声缓修（带证据）**：methodList 逐项 diff + 全量 grep 证明无跨壳调用、
   全部调用方已守卫；ArkWeb 内部日志应用层不可控；功能面零影响（r51 矩阵绿）⇒ 记录缓修，
   下轮带新 Beta 真机采样（速率/时间戳/UI 状态）再定位。⑥ 全量门禁 **134/0**
   （`dist/acceptance/20261126-full-gates-r4.txt`）；canonical Beta `…T234114`；local-install
   Beta `…T234348-local`（§6.8：16 文件备份 `beta023-local-20261125T234242` → 换身份 →
   `signature generate` → 单 product 构建 143 任务 → 组装 → 逐字还原 sha 16/16 →
   place-host-app + 5 门禁复跑绿；恢复后 prod 身份重建绿；**未装机**，用户手动安装）。

0. **Beta 出包 + 本机侧载（2026-11-25 晚，用户要求出新版 Beta 测试）**：
   ① canonical Beta `dist/beta/DSHM-beta-1.1.8-1010020-20261125T150452/`（§6.3 流程；
   首个携带裁剪后容器 `dabc48c7…` 的包；SHA256SUMS 5/5，beta HSP 内容器实读
   166,419,890 B / `dabc48c7…`；出包核验 §6.6：权限面 19/9、resfile、身份还原全过；
   脚本 WARN：beta Profile 未授权 4 条受限权限（CUSTOM_SANDBOX / READ_PASTEBOARD /
   READ_WRITE_DESKTOP_DIRECTORY / ACCESS_USER_FULL_DISK），debug 可装、授予看系统策略）。
   ② local-install（§6.8）：16 身份文件备份至 `dist/acceptance/beta023-local-20261125T151900/`
   （MANIFEST.sha256）→ beta 身份 → `signature generate` 本机调试签名 → 构建 → 组装
   `dist/beta/DSHM-beta-1.1.8-1010020-20261125T152500-local/` → **HSP + entry HAP 覆盖装机成功**
   （无 9568322）→ 启动冒烟通过（BMS 装包日志含新容器 166,419,890 B；`startHost` 核心
   0.2.3-alpha.2+dshm.1；`DSHM-AUTO ok=true`）→ 16 文件按 MANIFEST 逐字还原（sha 16/16）、
   重放 place-host-app、复跑 4 门禁全绿（permission 19/9、resfile-sync 27、brand 110、
   resfile-core-zip）。勘误：本页应用版本行原写 1010019，实际 AppScope 已是 **1010020**
   （11-25 晨间启动优化轮升版），本轮已修正。
   测试重点见 local 包 `README-LOCAL.txt`：office 优雅降级、img-sharp、常规链路。

0. **0.2.3 审核 §7 九项修复全部执行（2026-11-25 下午）**：①OSS 声明重生成 + AGC 草稿 newFeatures
   （brand 110/110）②AI 标识重冻结（chat `5ceff4bf…` + conversation `1cfde2ff…`，后者此前被 chat
   断言先抛掩盖）③cot 舞台 `PEER_ALIAS` 补 `dsh-brand` ④ws-self-heal harness 补 0.2.3 等价桩
   ⑤兼容面刷 262 端点（`Endpoints.ets` 重生成，compat-drift 无漂移）⑥`check-core-openharmony-patches`
   四组判据同步（**257/0**）；两未注册门禁按 `gates.yml` 头注结构性排除**不注册**，gates.yml 未改
   ⑦裁 `libreoffice-kit-wasm` + `img-sharp-wasm32` 重打容器（加载器先实核条件式：office-kit
   `lookupEntry` 整包缺失优雅降级、sharp `paths` 候选逐项 try/catch）——容器 208.2→**158.7 MiB**、
   条目 64,986→64,920、sha `04cea2c2…`→`dabc48c7…`（−49.5 MiB 与审核预测吻合）；resfile/sync/
   OSS（709 组件，BusyBox 仍登记）/六个核心树门禁全绿 ⑧删 entry busybox 死重复 + 空目录
   （HSP 副本完好，md5 `5a433386…`）⑨清三模块 build 重建（default 143 任务 + phone 81 任务
   BUILD SUCCESSFUL）。修复后全量回放 **133/0**
   （`dist/acceptance/20261125-full-gates-core023-fixes.txt`）；执行记录：audit-report §10。

0. **核心 0.2.3-alpha.2+dshm.1 审核完成（2026-11-25）**：容器（resfile 恰 1 份，sha `04cea2c2…`）、
   权限面（entry 19 / phone 9）、8 类树内补丁锚点、AI 标识 6 token、插件 peer、原生闭环
   （HSP 内 libsystem / libkoffi / libnode.so.147 齐备）全部核验**通过**。
   全量回放 133/6 失败并逐条定性：1 条（bridge-methodlist 缺 `startScan`×2）审核中已修复，
   5 条为声明/判据滞后（OSS 声明 rc.5、AGC 草稿 newFeatures、AI 标识冻结 hash
   `eef53e82…`→`5ceff4bf…`、cot `PEER_ALIAS` 缺 dsh-brand、ws-self-heal harness 缺 0.2.3 符号）。
   资源审计：zip 内 **~49.5 MB jitless 死资产**（libreoffice-kit-wasm 46.1 MB + img-sharp-wasm32 3.4 MB）、
   entry busybox 死重复 1 MB、空目录；两未注册门禁（compat-drift 262 端点、
   core-openharmony-patches 10 条判据过期）当前红。
   完整报告：`dist/acceptance/20261125-core023-audit-report.md`（含 §7 待拍板 9 项）。

0. **三端语音增强 + 移动端文档扫描/表格提取（2026-11-25 13:45）**：落地 `docs/202-三端语音朗读增强与移动端文档扫描.md`。
   ① 三端：既有 `ReadAloud` 已是 Speech Kit（`TextReader` 优先 / TTS 兜底），新增 `listVoices` 音色探测，
   有已装的小艺音色就用它，否则回落 SDK 推荐中文女声 person=13；探测失败不阻断朗读，三端共享 HAR 自动生效。
   ② 手机壳：会话区加号（`input[type=file]`）在 DocScan 能力可用时拦截，弹动作面板「扫描文档 / 提取表格 /
   从文件中选择 / 取消」；`DocumentScanner` 用 `DocType.DOC|SHEET` + `SaveOption.JPG/PDF/EXCEL`；
   结果经 `platform/DocumentScan.persistScanResults()` 把临时 URI 复制进 `<filesDir>/dsh/scans/`
   再 `event.result.handleFileList()` 回传网页，作为附件进入会话区。无 DocScan 能力或取消/失败均显式回退。
   **未申请新权限**（entry 19 / phone 9 未变）；编译 `phone@default` SUCCESS；10 条门禁全绿；
   **无设备，真机交互未验**（详见 `docs/202` §2.5 / §4）。
0. **启动优化收尾 + 全量复核 + 清理（2026-11-25 10:56）**：启动优化定稿（保留 S0–S7 标记、出表工具、
   预热让位、compile-cache 探针；骨架已撤）。全量门禁 **131/133**（2 条为沙箱 sh 限制，非回归）。
   复核中发现并修复一处本轮引入的回归：S6 标记曾插在 `onPageBegin` 的 `cancelNativeCapture()` 之前，
   破坏 `check-native-capture-lifecycle` 的正则与 mutant 4 锚点 —— 已把该调用放回首行、标记移到其后。
   清理：`dist/beta` 13 个历史包 → 1 个（22.72 GB → 1.76 GB）；`dist/core/work` 旧版本按「闭包可复现」
   纪律**保留**（理由见 `docs/201` §12.4）。新 Beta `…20261125T025309`（SHA256SUMS 5/5、verify-app success、
   entry 19/phone 9、两 hap 均不含 `skeletonTint`、身份未变）。
0. **A2 骨架已撤回 / B1 探针保留（2026-11-25 10:02）**：用户 PC 真机截图裁决——进度条下方的
   内容区骨架块「多余」，启动环节不要。已删除骨架块与 `skeletonTint()`/`skeletonEdge()`，
   启动页恢复「品牌标 92 + 线性进度条（上距 40）」。结论：DSHM 的启动页是纯 ArkUI 覆盖层，
   下面没有可对齐的真实布局，"先带结构出现"不成立；重做前提是 Web 带真实首屏骨架
   （见 `docs/201` §11.1 撤回说明）。B1 的 `compile-cache` 可见性探针保留。
   新 Beta `dist/beta/DSHM-beta-1.1.8-1010020-20261125T015954/`（app 647,689,343 B，SHA256SUMS 5/5，
   verify-app success，entry 19/phone 9，两个 hap 的 abc 均不含 `skeletonTint`，身份未变）。
   门禁：arkts-entry / dead-code / brand 110 / feature-wiring / parity / doc-refs / resfile 27 全绿。
1. **A2 骨架 + B1 编译缓存可见化（2026-11-25 第二批，已被上条撤回 A2 部分）**：启动页（`BOOTING || LOADING&&!everReady`）
   在品牌标/进度条下增加内容区中性占位（标题块 + 三 pill + 输入框，`maxWidth 340`，ARGB 5%/7% 淡色），
   不做完整三栏骨架（三端布局差异会导致二次跳变，理由见 `docs/201` §11.1）；`hostcore/app/main.js`
   紧随 BOOT_00 增加 `compile-cache` 可见性探针（`module.getCompileCacheDir()` 只读一次、零 IO）——
   **B1 的 `NODE_COMPILE_CACHE` 接线 2026-11-15 已完成**，本轮补的是"是否真的生效"的判定。
   审核中收敛两处初版问题：删除启动路径上的 `readdirSync` 计数、删除永不触发的 `enableCompileCache` 分支。
   验证：`check-arkts-entry --clean` 0 error / WebApp 零告警；default + phone 编译 SUCCESS；
   门禁 14 条全绿；Beta `dist/beta/DSHM-beta-1.1.8-1010020-20261125T014426/`（app 647,695,115 B，
   SHA256SUMS 5/5，verify-app success，entry 19/phone 9，HSP main.js 含探针，tablet abc 含 skeletonTint，
   身份已还原）。**真机待验**：骨架观感、骨架→真界面是否有闪烁、`compile-cache:` 日志结论。
0. **启动可测化 + 预热让位（2026-11-25，对照 WorkBuddy 启动拆解）**：
   新增 `platform/diagnostics/StartupMarks.ets`（S0–S7 双时间戳 + JSONL + 幂等 + 终态 SUMMARY）、
   `tools/startup-report.mjs`（出表与逐段差值）；`EntryAbility` 埋 S0/S1/S2/S3/S4/S5、
   `WebApp` 埋 S6/S7；`probeNativeBindings()`（纯日志）移出 onCreate 同步段；
   `warmWebEngineOnce()` 让出一个宏任务 —— 依据历史实测 `initializeWebEngine` 占 UI 线程
   **106–118 ms**，原先压住宿主链 Promise 回调。
   验证：`--product default` 与 `--modules phone@default` 均 **BUILD SUCCESSFUL**；
   `check-arkts-entry` / `check-boot-rescue` / `check-startup-work`(+self-test) / `check-brand-surface` /
   `check-dual-shell-parity` / `check-feature-wiring` / `check-dead-code` / `check-doc-refs` / `check-parity` /
   `check-tools-syntax` 全绿。
   **未做真机测量**（当班 `hdc` / `devecocli device list` 均无设备）。上机后取数与对比见 `docs/201` §10.3。
   顺带修复既有失败：`check-startup-work` 的请求条数 6→7、锚点改 `startupWork.request('toolchain'`、
   `ensurePythonBridge` 允许两挂载点（坑档 §2.12）。

1. **核心同步到 0.2.2-rc.5**（2026-11-19）：包集合与端点面无变化（224/224，`compat-drift` 无漂移）；容器重打 sha `61749b16…`（58,505 条目）并入 resfile；`Endpoints`/contracts/OSS 声明均更新为 rc.5；版本升 `1.1.8 / 1010018`（用户明确要求）。待 DevEco 编译与真机验证。

1. **核心同步到 0.2.2-rc.4**：上游 351 包全部升 rc.4；兼容面端点 223 → 224；
   8 个受补丁包与 rc.3 逐字节一致；`Endpoints.ets` 按 rc.4 重生成 224 条。
2. **核心容器重打**：`resfile` 单份容器；sha 与配方一致；pnpm `fieldsParam` 修复入包。
3. **本机侧载冒烟**：临时 beta 身份 + `devecocli signature generate` + 双 product 构建；
   HSP → HAP 覆盖安装成功，数据保留，启动正常，核心 rc.4 已落盘。
4. **竖屏侧栏修正**：平板 / 折叠屏 `<1024` 交官方抽屉，不再写死 280/56（两壳同步）。
5. **AGC 包**：release 签名构建 + 包结构核验（身份 / 设备面 / 18·9 / HSP 内 zip sha / abc 串）。
6. **文档体系重整**：337 篇编号文档归档到 `docs/archive/`；新建功能台账 / 坑档 / 决策表 / 架构。
7. **AGC 重编**：`…20261118T140406.app`（sha `c6b56c2a…`）release 构建并核验（身份 / 设备面 / 18·9 / HSP 单容器 / ffmpeg 完整 / 无 dsh-bili-whale / verify-app），待上传。
8. **版本回退重编（2026-11-19）**：1010017 与 1010018 两包逐字节比对，差异只有 `versionCode`（`pack.info` / 各模块 `module.json`）；
   证书与 Profile 二进制一致（`ca94d463…` / `ea6fe380…`），entry 18 / phone 9 权限逐条一致 ⇒ **不是权限面回归**。
   已按 1010017 重出 `…20261118T173822.app`（sha `0d197b3d…`，profile_acls=8，verify-app 通过）。
9. **1010018 手机端两项修复（2026-11-19 晚，源码已改、未出新包）**：
   - **左下角 DeepSeek 账号点登录不跳浏览器（仅手机）**：核心 rc.3 起账号流帧 / RPC 结果是
     `{type,state:AccountView}` 封套，entry 已剥、phone 垫片漏了 ⇒ `waiting-browser` 永远扫不到。
     已与 entry 对齐（封套剥离 + 普通锚点接管 + 同源放行）；`check-open-link-bridge` 新增
     phone 三条判据与对照臂 N。
   - **最近任务界面不沉浸（仅手机）**：手机从未开启 `setWindowLayoutFullScreen`，任务卡片顶部
     是一条独立底色。已按平板结构补齐：`enterHandheldImmersive()`（全屏 + 状态栏透明）+
     页面 `topInsetVp` 顶部让位；`check-decor-button-mode` 新增成对接线断言。
   验证：`devecocli build --product phone` **BUILD SUCCESSFUL**；`check-open-link-bridge` 37/0、
   `check-decor-button-mode` 9/0 + 131/0、`check-dual-shell-parity`、`check-arkts-entry` 均 PASS。
11. **dsh-pet 桌面环境落地（2026-11-20 晚）**：主工程新增 `PetAbility`（透明子窗加载插件自己的渲染页）、
    宿主伴生层 `hostcore/app/dshm-pet-host.cjs`（`DSH_PET_IN_PROCESS=1` + `/dsh-pet-native/*` 静态路由 + shim）、
    `WINDOW_TOPMOST` 权限（entry 18→19）。Beta：`dist/beta/DSHM-beta-1.1.8-1010019-20261120T144910/`，
    app sha `186f4b03…`；待用户装 dsh-pet 插件后真机验证。
    **权限级别核实（2026-11-21）**：SDK `PermissionDefinitions.json` 里
    `ohos.permission.WINDOW_TOPMOST` = `grantMode: system_grant` / `availableLevel: normal` /
    `provisionEnable: true` ⇒ **不是受控 ACL**，不需要 AGC 审批、也不会被
    `strip-ungranted-acl-perms.mjs` 摘除（该工具只动 `system_basic` / `system_core`）；正式 Profile
    的 8 条 `allowed-acls` 不含它是正常的。上架若被问，按「桌宠透明悬浮窗需保持在其它窗口之上、
    用户可随时关闭」说明即可（非 ACL 审批）。
12. **平板「PC 应用」最小复现 demo（2026-11-20）**：`demo/pc-app-label-repro/` + `demo/pc-app-label-repro-delivery.zip`，单 entry HAP、无业务代码；`deviceTypes=["tablet","2in1"]` 且 `supportWindowMode` 缺省。`tools/switch-variant.py A|B` 提供对照；已构建成功，产物内 HAP 清单核实无误。用于向鸿蒙工程师确认「PC 应用分类 vs supportWindowMode」的归因。
11. **平板分屏/小窗修复 A（2026-11-19 晚，源码已改、未出新包）**：`EntryAbility.afterWindowStageReady()`
   的 `isHandheldForm()` 早分支只写 `pcMode` 与 `publishDecorKeysVisible(false)`，导致平板**整段装饰链**
   （FLOATING 恢复标题栏/三键、`decorPresentOf`、诊断落盘）一次都不执行 ⇒ 探针恒为
   `decor=skip buttons=skip show=false`。已删除该早分支，统一走完整链（`pcMode = 手持 && FLOATING`，
   PC 档恒 false 不变）。`check-decor-button-mode` 改为**禁止早分支**并要求按真实结论发布
   （9/0 + 131/0）。交接单 `JD-012`；真机未验。

## 3. 没做完 / 未验证

| 项 | 状态 | 验收方式 |
|---|---|---|
| 401 / R8 / office / R4 修复真机验收 | 装机载体已就绪（local beta `…T234348-local`，容器 `44627a39…`，**未装机**）：python/browser 不再 401、office 文档功能恢复、诊断 R8 探针指向当前核心 | 用户本机覆盖安装（HSP→HAP）后按 `README-LOCAL.txt` 重点清单实测；平板/手机交用户自测 |
| 0.2.3-alpha.2 真机验收 | 同上（装机载体已就绪，关键路径未过） | 本机 2in1 过关键路径；平板/手机交用户自测 |
| 平板竖屏侧栏 | 代码与门禁已绿，**真机未验** | 平板/折叠竖屏看左栏是否被会话区压住 |
| 碰一碰真实投递 | 本机侧载只能证明注册成功 | 需 AGC 正式分发或真机分享验证 |
| 云同步端到端 | 策略与模型门禁绿，**真实环境未验** | 需华为账号 + 系统云空间开关 |
| AGC 上传 / 审核 | 未做 | 人工在 AGC 控制台操作 |
| 手机 product 真机 | 本机无手机设备 | 用户自测 |
| 手机登录外开修复 | 编译与门禁绿，**真机未验** | 手机点左下角账号 → 登录，应直接拉起系统浏览器授权页 |
| 手机最近任务沉浸 | 编译与门禁绿，**真机未验** | 上滑进最近任务，应用卡片顶部应铺满、状态栏下无独立色带 |
| 平板分屏 / 小窗（修复 A） | 编译与门禁绿，**真机未验** | 冷启动→最近任务/Dock 进悬浮窗→标题栏恢复→三键菜单分屏，需出现 `SPLIT_SCREEN` 且宽度减半 |
| 平板「PC 应用」分类（假设 B） | 官方规则+包内清单已证；设备面结构性修复未立项 | `entry.deviceTypes=[tablet,2in1]` 且无 `phone` ⇒ 系统判 PC 应用、Tablet 上不支持悬浮窗；源码与已构建 HAP 的 `supportWindowMode` 均为**缺省**（默认含 split/floating），显式补该字段不能解除 PC 分类 |

## 4. 下一步建议（按优先级）

1. 用户在本机实测新 Beta（装 `…T234348-local`，HSP→HAP 覆盖安装）：python/browser、office、裸 python3 import、终端、会话、市场。
2. 手机真机装 `…T234348-local/phone/` 面复测 r51 清单（P0-P3 修后应全绿；P2-3 采样留档）。
3. AGC 上传邀请测试包，验证碰一碰与云同步的真实链路。
4. 平板 / 折叠竖屏侧栏真机复验。
5. 每次改功能：先查 `docs/FEATURES.md` 对应行与门禁，再动手。

## 5. 文档入口

- 规范与红线：`AGENTS.md`
- 工具 / 构建 / 发布操作：`AGENT-HANDOFF.md`
- 功能台账（防回归）：`docs/FEATURES.md`
- 坑与红线：`docs/PITFALLS.md`
- 决策记录：`docs/DECISIONS.md`
- 架构：`docs/ARCHITECTURE.md`
- 历史档（只读）：`docs/archive/`


## 6. 交付物台账（AGC）

> 只登记 `dist/release-test/*.app`；每行对应一个文件（`ls` 可逐条核对）。
> sha 取对应 `.app.sha256` 前 16 位；完整值见文件本身与 `SHA256SUMS.txt`。

| 构建时间 | 版本 / 核心 | 大小 (B) | sha256（前 16） | 备注 |
|---|---|---|---|---|
| 20261115T013035 | 1.1.8 / 1010016 / dshm.1 | 660,796,604 | `b420ee344f7f38d3` | 内存修复批次 |
| 20261115T014501 | 1.1.8 / 1010017 / dshm.1 | 660,798,963 | `923e507bf31fd62d` | 冷启动优化 |
| 20261115T020145 | 1.1.8 / 1010017 / dshm.1 | 660,798,892 | `4bc5e8b292eea264` | 上架材料定稿包 |
| 20261115T115001 | 1.1.8 / 1010017 / dshm.1 | 660,840,421 | `990f9c570fb49887` | 当日重编 |
| 20261116T032255 | 1.1.8 / 1010017 / dshm.1 | 663,605,951 | `7ffc33d8c47e1b5c` | 启动优化正式交付前重编 |
| 20261116T033702 | 1.1.8 / 1010017 / dshm.1 | 663,597,163 | `40008a1657ad02ea` | 启动优化正式交付 |
| 20261116T134514 | 1.1.8 / 1010017 / dshm.1 | 663,627,728 | `c709a31783b8a5b5` | 碰一碰侧载轮次对应包 |
| 20261118T120906 | 1.1.8 / 1010017 / dshm.1 | 663,657,429 | `0cd558154faba5fd` | rc.4 首次构建（pnpm 修复） |
| 20261118T124659 | 1.1.8 / 1010017 / dshm.1 | 663,657,430 | `0516c3970c816b0b` | 同日重出 |
| 20261118T140406 | 1.1.8 / 1010017 / dshm.1 | 663,657,430 | `c6b56c2abc217b61` | 历史（文件已不在目录） |
| 20261118T164204 | 1.1.8 / 1010017 / dshm.1 | 663,657,474 | `825657543217f526` | 云调试安装不上（已作废） |
| 20261118T170734 | 1.1.8 / 1010018 / dshm.1 | 663,657,474 | `6b5dae270f3ee9e5` | 未在 AGC 登记，云调试装不上（已作废） |
| 20261118T173822 | 1.1.8 / 1010017 / dshm.1 | 663,657,473 | `0d197b3d7189077c` | **最新**（回退版本重编；未上传、未提审） |

> 2026-11-19 目录内保留 `T164204`/`T170734`/`T173822`；更早文件已不在目录（非本次操作删除）。
> 云测请用 `T173822`（1010017）。若云调试仍拒装，先确认 AGC 侧 1.1.8 版本记录（1010017）是否已换成该包；
> 同版本换包仍被拒时，按 AGC 流程以新 `versionCode` 登记后再云调试，不要继续在本地重编。

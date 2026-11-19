# DSHM 项目交接（结构化）

> 最近整理：2026-11-12。本文只写**当前状态 + 索引 + 边界**；
> 逐轮出包流水账已归档到 [`HANDOFF-2026-11-06-historical.md`](HANDOFF-2026-11-06-historical.md)（只读留档，不作为执行依据）。
> **工作规范与流程的唯一入口是根目录 [`AGENTS.md`](../AGENTS.md)**；编号文档索引见 [`docs/README.md`](README.md)。

---

## 1. 当前状态（以代码/配置为准，不在此抄可漂移值）

核心同步到 `0.2.2-rc.4+dshm.1`（2026-11-18，[`docs/422`](422-核心同步到0.2.2-rc.4（兼容面重生成与全量门禁复核）.md)）：上游包集合不变（351），全部包升 rc.4；兼容面端点 223 → 224（新增 `deepseekChatImport/limits`，0 删除 / 0 形状变化）；8 个被 DSHM 打过补丁的包与 rc.3 逐字节一致，移植补丁继续适用。`Endpoints.ets` 基线此前停在 `0.2.1-rc.2` / 144 条（rc.1→rc.3 从未重生成），本轮按 rc.4 重生成 224 条并同步 `CompatIndex`，`compat-drift` 无漂移。容器重打 193.6 MB / 58,504 条目、sha256 `f6e1c0a3…`，已并入 resfile（只 1 份），OSS 声明随版本更新、`check-brand-surface` 转绿。entry 构建 81 tasks 绿、gates.yml 全量 131 条 0 失败。**版本未升（1.1.8 / 1010017）、未出 Beta / AGC 包**，最新 AGC 包仍是 rc.3 时的 `…20261116T134514.app`。 本机侧载冒烟（2026-11-18）：按「临时 beta 身份 + `devecocli signature generate` + 双产品构建」出可侧载包 `dist/beta/DSHM-beta-1.1.8-1010017-20261118T130350-local/`（tablet/phone 各 hap+hsp + SHA256SUMS + README-LOCAL.txt），MateBook 2in1 覆盖安装成功、数据保留、启动正常，`dsh/cores/0.2.2-rc.4+dshm.1` 已落盘，`diag-knock` 显示 `caps=object,file max=20`；首启宿主就绪 47.3s（首次解包 640 MB 核心），源码与 `build-profile` 已逐字还原、131 条全量门禁复跑 0 失败。

碰一碰修复落地（docs/421）+ Beta 出包（2026-11-17 续）：按 [`docs/421`](421-碰一碰传文件（DSHM端实现与修复方案）.md) 落地 WP1/2/3/5——接收器改按 windowId 一窗一实例（会话窗也注册）、页面销毁只 `detachPage` / 窗口销毁才 `release`、能力面改 `general.object + general.file`（单次上限 20，OBJECT 被拒回退 TEXT+COMPOSITE_OBJECT+ARCHIVE+FILE）、Web shim 按 `defaultPrevented` 判 paste/drop 并对无 composer 场景 60s 内补投；诊断补 `utd` 与 inject 结果。WP4（接收目录收紧）与 WP6 键值格式未做，版本未升（仍 1010017）。entry 构建绿、131 全量门禁 0 失败。Beta `dist/beta/DSHM-beta-1.1.8-1010017-20261117T144135/`（canonical，bundle dshmbeta、entry 18·phone 9）；canonical 侧载仍报 9568322（`build-beta` 的 profile 与证书非同密钥，既有流水线缺口），同目录 `local-install/` 为本机调试签名可侧载 hap/hsp（README-LOCAL.txt 含测试判据）。本机冒烟：覆盖安装成功、数据保留、启动成功、`diag-knock` 显示 `on ok windowId=770 caps=object,file max=20`（OBJECT 被系统接受）。真实投递仍需 AGC 正式分发验证。

沉浸光感混合承载 + 设置面板全形态排除（2026-11-17，同一 Beta 两轮）：① 混合承载（[`docs/419`](419-沉浸光感混合承载落地（entry弹窗材质与网页菜单原生接管）.md)）：entry 4 处 AlertDialog 挂 `systemMaterial: dialogMaterial()`（THICK）；Web 右键/长按菜单原生接管（`openMenu` + THIN `immersiveMaterialOf` + `WithTheme` + Stack 内 1×1 锚点）；Kit 实参求值前 API≥26 守卫；`diag-material`/`diag-webmenu` 探针。② 设置面板修复（用户实测「浅色下设置面板浅黑覆盖」→ [`docs/420`](420-设置面板官方排除扩到全形态（平板浅黑覆盖修复与门禁基线冻结订正）.md)）：玻璃皮肤 `findDialogs` 删 `dshm-desktop` 条件，设置面板及内部 dialog **全形态**排除出玻璃（11-14 只排 PC 桌面标记），官方面板/遮罩 token 复位；顺带 `topBarBg`/`topBarBgNow()` 退役 + `check-pc-settings-chrome`/`check-decor-button-mode` 两门禁改钉。③ 门禁基线冻结订正：本地回放基线停在 11-13 的 113 条、gates.yml 实有 131 条 run，11-16 顶栏改透明导致的红门禁（`check-pc-settings-chrome` 断言 `topBarBgNow`）漏网至本轮；新增 `dist/acceptance/gen-full-yml-gates.py`，全量基线 `dist/acceptance/20261117-full-yml-gates-sweep.txt`（131 条 0 失败），**后续回放基线改用全量报告、改 gates.yml 后重生成**。④ 验证：entry 构建绿、113 回放 `dist/acceptance/20261117-settings-official-exclusion-gates.txt` 0 失败、131 清扫 0 失败；Beta `dist/beta/DSHM-beta-1.1.8-1010017-20261117T024043/`（670MB combined-debug.app，覆盖安装即可）。真机判据：浅色平板设置面板应为官方近白不透明、与标题栏一致（面板后方环形深色=官方 24% 遮罩，dsh 官方设计）；沉浸判据见 docs/419 §5。

碰一碰传文件落地（2026-11-16，PC 档）：手机轻触本机屏幕 → Share Kit 沙箱接收 → base64 注入合成 paste 走官方 file intake，文件以附件 chip 进输入框、不自动发送。范围按用户裁定＝仅 PC 档（desktopForced）注册，普通平板不启用，手机端是系统发送方零改动；权限面 18/9 逐字未动（harmonyShare 全程零 manifest 权限）。实现＝`entry/src/main/ets/system/KnockShareReceiver.ets`（每传输独立空目录、单文件 16 MiB 上限、挂起队列补发）+ `WebApp.ets` 接线（`KNOCK_SHIM_JS` document-start 垫片、`startKnockReceiver` PC 档门控、onPageEnd 补发、aboutToDisappear 注销）。entry 构建全绿、113 条门禁回归 0 失败（基线 `dist/acceptance/upstream-alignment-20261116/gates-titlebar-beta.txt`）。**未真机验收**：ArkWeb 合成 ClipboardEvent 支持度、调试签名可否触发均为首验项，判据与退路见 [`docs/418`](418-碰一碰传文件调研（ShareKit沙箱接收·WorkBuddy逆向对照）.md) §5.2/§6。

启动优化正式交付（2026-11-16）：正式 AGC 包 `dist/release-test/dshm-1.1.8-1010017-dshm.1-AGC-invite-20261116T033702.app` 已成功构建并核验，保留缓存 flush 与 resolve 种子；清除31条设备绝对地址键后随包14586条可移植记录，不分发编译blob。改前/最终113条回归均零失败，CI补充36条命令返回0；种子幂等/已有文件保留/缺目录/关闭开关检查通过。未上传、未审核、未覆盖安装正式应用，正式渠道与三端实际功能验收边界见[正式交付报告](../dist/acceptance/boot-seed-20261116/delivery.md)。本轮临时导出与seed-lab已清理，用户数据及交付留档保留。

落地后已完成[11项上游专项审查](../dist/acceptance/boot-seed-20261116/upstream-review.md)：识别surfaceContext依据过期、重复profile/终端组复制与未使用compile种子分支；workflow、抓取头、注入调度需独立验收。仅记录精简建议，未撤除必要平台适配或用户已确认能力。

AGC 侧已上传并填好（2026-11-15，**未提交审核**）：服务端 App ID 确认 `6917614360926110054`；邀请测试版本 `2084045910064505088`（已绑包、zh-CN 文案、`DSHM邀请测试` 分组、2026-11-16→11-30）；正式版本 `2022732350219131712` 对应的包 `2084047405258424704`（AGC 读回 1.1.8/1010017、权限 18 条中文说明），语言与设备面/隐私/AI/备注已填。两个版本 releaseState=7（草稿）。上传过程中修掉本地 CLI 的分片大小 bug（660 MB 包会超分片上限），补丁与复现记在 `AGC-operations/cli/PATCH-multipart-part-size.md`。升级安全性已核：同包名、同签名证书指纹、versionCode 递增、权限面逐条不变、`check-user-data-preserved` 通过。**截图、年龄分级/备案/主体仍需人工在控制台确认**。

上架材料与 1010017 定稿包（2026-11-15）：按 `app-metadata-audit-skill` 预审后，权限用途说明两条英文文案改为中文、`docs/408` 更新为 1010017 对外口径，并重出 AGC 包 `dist/release-test/dshm-1.1.8-1010017-dshm.1-AGC-invite-20261115T020145.app`（sha256 `4bc5e8b2…`，release / app_gallery / 8 条 ACL，独立验签通过，113/0）。邀请测试与正式审核的待填写材料在 `metadata/agc-app-info-update-1.1.8-1010017.json`、`metadata/agc-1.1.8-1010017-invite-test-info.json`、`metadata/AGC-1.1.8-1010017-{邀请测试提示词,审核备注,推送清单}.md`；**未推送**，等人工确认。仍需人工核对：隐私政策唯一绑定与正文覆盖、手机/平板截图存量、年龄分级/备案/主体、关键词、AI 类型。

启动优化与移动端 pnpm 修复双包（2026-11-15）：真机采样定位冷启动大头是宿主插件图装载（PC Beta 1010016：`aa start`→首帧 0.63 s，宿主就绪 15.37 s，页面 READY 17.5 s）。已落地五项不改变功能的改动：ArkWeb 引擎在宿主线程起跑后预热、entry 首帧后延迟 400→32 ms、端口轮询 1 s→250 ms、token 落盘轮询 500→150 ms、宿主 `NODE_COMPILE_CACHE`。移动端 `pnpm -v` >120 s 的根因是 guest 在 TCG 下每次都要启动 node 并解析 8.8 MB 单文件 bundle；改为版本查询读 `package.json` 直出、真实命令启用字节码缓存并关闭更新检查/版本自管理，另清空 `*.previous-<ts>` 空备份目录。版本按用户要求升至 **1010017**（versionName 仍 1.1.8），核心树已重打。113/0 回归通过，双包已出并核验（Beta `dist/beta/DSHM-beta-1.1.8-1010017-20261115T014318/`、AGC `dist/release-test/dshm-1.1.8-1010017-dshm.1-AGC-invite-20261115T014501.app`）。本机侧载仍被 9568322 拒绝，**未实测真机启动收益与 pnpm 实际耗时**，不宣称已快若干秒；证据见 [门禁](../dist/acceptance/startup-opt-20261115/gates-1010017.txt) 与 `.workbuddy/memory/2026-11-15.md`。

内存生命周期收口（2026-11-15）：修复PTC定时器、标题缓存、usage读取峰值、双壳录音退出回收、guest输出背压与取消监听/PID竞态。完整113/0、四生命周期自检及负控制、36项CI补充通过，双产品编译成功，核心ZIP插件字节及voice v4核验通过。部署因9568286（install provision type not same）被阻止，未卸载或改签名，不宣称真机内存收益。超长usage行保全但统计不完整且暂停压缩；正常长录音仍随时长占用PCM。以[内存审查结果](../dist/acceptance/memory-review-20261114/result.md)与[构建证据](../dist/acceptance/memory-review-20261114/build-result.md)为准，未另出AGC/Beta双包。

内存修复双包（2026-11-15）：Beta合并APP `dist/beta/DSHM-beta-1.1.8-1010016-20261115T000928/DSHM-beta-1.1.8-1010016-combined-debug.app`，AGC `dist/release-test/dshm-1.1.8-1010016-dshm.1-AGC-invite-20261115T001112.app`。双包身份/版本/模块设备面/18·9权限、SHA清单、8组APP/HAP/HSP独立验签、HSP核心ZIP SHA及插件/main.js/ABC/voice v4核验通过；配置摘要确认源码恢复正式身份且未输出签名凭据。Beta debug Profile仅2项ACL，不得视为受控权限已授予；AGC仅经AppGallery/渠道分发，不可本地侧载。未部署、未做UI或真实性能验收。大小、SHA与详细证据见[内存修复双包交付](../dist/acceptance/memory-dual-20261115/delivery.md)。

启动改动测试双包（2026-11-14）：Beta批次 `dist/beta/DSHM-beta-1.1.8-1010016-20261114T123053/`，AGC `dist/release-test/dshm-1.1.8-1010016-dshm.1-AGC-invite-20261114T123308.app`，八组独立包/Profile验签、结构和启动改动入包核验通过。四个生成HAR配置按原摘要恢复，剩余FFmpeg清单generatedAt为明确例外，其他字段一致。交付以 [启动测试双包](../dist/acceptance/cold-start-dual-20261114/delivery.md) 为准；尚未证实冷启动提速，用户自行测试，未部署或上传。下方“尚未出包”描述仅对应此前报告时点。

冷启动追加优化（2026-11-14）：延后非关键诊断、授权恢复4个等待槽并合并在途工作、核心安装检查合并及事务串行保护、HSP路径复用。完整校验和授权恢复前置不变；113/0、12专项、32CI补充及双产品编译通过。基础profile装载仍为主要耗时，隔离A/B未证实稳定加速，真实PC/手机收益未测，不宣称已快若干秒。见 [冷启动结果](../dist/acceptance/cold-start-20261114/result.md)。尚未重新出包或部署，下方双包不包含本次优化。

最新清理双包（2026-11-14）：撤除DSHM专用本地模型/Ollama接入，保留通用模型API及已有用户数据；清理无调用音频/备用运行时/旧主题探针，包含PC设置额外遮罩撤除，并修复并发任务身份与guest终端回收。Beta批次 `dist/beta/DSHM-beta-1.1.8-1010016-20261114T102643/`，AGC `dist/release-test/dshm-1.1.8-1010016-dshm.1-AGC-invite-20261114T103314.app`。113/0、19专项、25条CI补充、双产品编译及八组独立验签通过，包内修复和SHA清单核验通过；生成配置恢复、FFmpeg清单仅生成时间例外见 [清理双包交付](../dist/acceptance/cleanup-local-model-20261114/delivery.md)。云同步按用户选择暂缓，三端真机/UI/guest实际运行未验收；不宣称各项功能全部正常。下方批次为历史记录。

PC设置页顶栏配色追加撤除（2026-11-14）：删除壳层设置dialog触发的原生TopBar黑罩和webModal桥；PC设置dialog不再被壳层玻璃改色，恢复官方面板/遮罩token。保留系统三键跟随实际主题、窗口背景、官方设置遮罩、其他平台dialog行为。entry/default编译通过，113/0、相关专项及负控制通过。Beta所述`preference: light`未在当前源码/物化profile找到；官方缺省为system且持久化用户选择，未强制改主题。新双包未制作、未设备UI验收。证据见 [PC设置诊断](../spec/pc-settings-chrome-20261114/findings.md) 与 `dist/acceptance/pc-settings-chrome-20261114/`。【2026-11-17 范围更新】设置面板的官方排除已扩到全形态（平板同样不再被壳层玻璃改色），非设置弹层维持玻璃；见上方最新条目与 [`docs/420`](420-设置面板官方排除扩到全形态（平板浅黑覆盖修复与门禁基线冻结订正）.md)。

最新诊断修复交付（2026-11-14）：已完成文件检索缺导入、手持工具链进程内解包、task-state兼容副本路径、guest按需工具接线、Python请求目标预算、AI任务尾标及phone玻璃能力诊断。Beta批次 `dist/beta/DSHM-beta-1.1.8-1010016-20261114T071122/`，AGC包 `dist/release-test/dshm-1.1.8-1010016-dshm.1-AGC-invite-20261114T071309.app`；双产品编译、完整113/0回归、八组独立验签及包内修复核验通过，9355项保护摘要恢复。以 [诊断修复交付报告](../dist/acceptance/release-diagnostics-fixes-20261114/delivery.md) 为准。未部署或验收设备UI、guest真实执行及性能；phone玻璃声明为未实现/不适用，平板系统PC标签暂缓，下方批次为历史交付。

最新核心同步（2026-11-13）：已同步 npm `next` 的 DSH `0.2.2-rc.3`，本地 `0.2.2-rc.3+dshm.1`，应用版本不变。Beta批次 `dist/beta/DSHM-beta-1.1.8-1010016-20261113T124121/`，AGC包 `dist/release-test/dshm-1.1.8-1010016-dshm.1-AGC-invite-20261113T124336.app`；同批113/0、CI22及专项15命令全rc0，双包核验与五组独立验签通过，77项原配置/签名摘要恢复。以 [rc.3双包交付](../dist/acceptance/dsh-rc3-sync-dual/delivery.md) 为最新证据；未安装/UI验证，普通平板系统PC标签未修。下方rc.2批次均属历史交付。

最新续作交付：11项审查修复已完成独立终核与双包离线核验；Beta批次 `dist/beta/DSHM-beta-1.1.8-1010016-20261113T074043/`，AGC包 `dist/release-test/dshm-1.1.8-1010016-dshm.1-AGC-invite-20261113T075635.app`。包后门禁113/0、CI补充22命令与专项15命令全rc0，配置及签名物料77项精确恢复。路径、摘要、独立验签和边界以 [双包交付报告](../dist/acceptance/fix-review-dual-release/delivery.md) 与 [验证报告](../dist/acceptance/fix-review-dual-release/verification.md) 为准；本轮未部署、未做UI验证，离线PASS但总体INCOMPLETE，下表旧交付批次仅作历史参考。

| 项 | 唯一出处 |
|---|---|
| 版本 / 包名 | `AppScope/app.json5`（当前 **1.1.8 / 1010017**） |
| 核心版本 | `hostcore/core-recipe.json`（当前 `0.2.2-rc.4+dshm.1`） |
| 模块设备面 | `entry/src/main/module.json5`（tablet + 2in1，**18 权限**，含全盘 `ACCESS_USER_FULL_DISK`）、`phone/src/main/module.json5`（phone，9 权限）、`hostruntime/src/main/module.json5`（三设备面） |
| 权限面判据 | `tools/check-permission-surface.mjs` 的 `EXPECTED` / `PHONE_EXPECTED` |
| 三端归属矩阵 | [`docs/386`](386-三端分离重整方案-PC平板手机各走各的.md)（已落地） |
| 平板侧栏契约 | [`docs/385`](385-平板侧栏回归官方56px图标轨折叠方案.md) + [`docs/386`](386-三端分离重整方案-PC平板手机各走各的.md) + [`docs/390`](390-平板侧栏B语义点外收起与云测遥测域修复.md)（B 语义 / 遥测域） |
| 0.2.2 侧栏 DOM 契约 | [`docs/379`](379-核心0.2.2-rc.1更新日志复核与手机端inert整页清除.md) + [`docs/380`](380-侧栏展开后整屏变灰不可点与终端不可用的根因复核.md) |
| 云空间配置 | [`docs/374`](374-云空间端云同步AGC配置核对与字段改造清单.md)（唯一口径） |
| 最新交付件 | AGC `dist/release-test/dshm-1.1.8-1010017-dshm.1-AGC-invite-20261116T033702.app`（663,597,163 B / sha `40008a16…`，启动优化正式交付已核验，11-16；其后 knock 侧载轮次另有 `…20261116T134514.app`）；Beta `dist/beta/DSHM-beta-1.1.8-1010017-20261117T144135/`（含 docs/421 碰一碰修复；`local-install/` 为可侧载调试签名版）；上一版 `…T024043`（沉浸 + 设置面板，sha `f4abc4bc…`） |
| 最近全量回归 | `dist/acceptance/20261118-rc4-full-gates.txt`（gates.yml 全量 **131/0**，核心 rc.4；生成器 `dist/acceptance/gen-full-yml-gates.py`）；上一轮 `20261117-full-yml-gates-sweep.txt`（131/0）与 113 回放 `20261117-settings-official-exclusion-gates.txt`。真机验证待用户 |

### 三端矩阵（务必分清，历史文档里有多处被推翻的旧口径）

| 平台 | 判定 | 模块 / 权限 | 顶栏 | 左栏 | 终端 |
|---|---|---|---|---|---|
| PC / 2in1 / **Edge / ProMax** | `desktopForced` → DESKTOP | entry / 18 | PC 顶栏 | PC 常驻 | 原生 PTY |
| 平板（不含 Edge/ProMax） | tablet | entry / 18 | **无** | 独立档：展开 280 / 收起 56px 轨 | guest VM |
| 手机 | phone | phone / 9 | 无 | 抽屉（只一颗官方按钮） | guest VM |
| 折叠单屏 | foldable + singleScreen | phone / 9 | 无 | 跟直板机一样（手机抽屉档） | guest VM |
| 折叠多屏（双屏 / 三屏） | foldable + 非 singleScreen | phone / 9 | 无 | **跟 PC 打开一样（桌面档，官方原生窄轨）** | guest VM |

---

## 2. 红线（详细因果链见 `AGENTS.md`，不得绕过）

1. **真机数据**：只允许覆盖安装（`hdc install -r`）；禁止 `hdc uninstall` / `bm uninstall` / 删除 `/data/app/el2/...`。2026-09-25 曾因裸 uninstall 永久丢失 6 会话 / 7 插件 / 2 工作区。
2. **签名物料**：`signing/**`、`.certs/**`、`AGC-operations/release-signing/**`、`build-profile.json5`（含口令）只此一份，永不删除。2026-10-04 事故链见 `AGENTS.md`。
3. **权限面**：entry 恒 18 / phone 恒 9，条数 + 顺序 + reason 逐位钉死；ACL 以发布 Profile 的 `allowed-acls` 为准（当前 8 条，含全盘权限）。**「恒 8 条」「恒 17 条」均已作废**，按旧口径删减会移除 `CUSTOM_SANDBOX` 等 ⇒ 宿主域降级、终端 / 文件 / ELF 全废。
4. **版本号**：只在用户明确说「升到 X」时改，不因换包或内容变化自行加版本。
5. **交付件**：`dist/release-test/*.app`、`dist/beta/*.app`、`dist/core/*.zip`、`dist/acceptance/*`、`dist/frozen/*`、所有 `SHA256SUMS.txt` 一律不删；可清的只有各模块 `build/**` 与旧版 `dist/core/work/**` 缓存。

---

## 3. 标准流程（每次改动都按此走）

1. 确认口径 → 需要时先出方案、等用户确认
2. 改码 → 跑相关门禁 + 变异体自检
3. **改了 `hostcore/plugins/**` 或核心树内容 ⇒ 必须重打核心容器**：
   `CODEBUDDY_SAFE_DELETE_ENABLED=0 node tools/pack-core.mjs --skip-install --place-in-app`
   （静态产物在 `hostruntime/.../resfile/dsh-core-*.zip`，只打包不重打会带旧插件）
4. 全量回归：`python3 dist/acceptance/rerun-gates.py <基线报告> <输出报告>`（当前 103 条）
5. 出 AGC 包：`CODEBUDDY_SAFE_DELETE_ENABLED=0 node tools/build-agc.mjs`
   → `.app` + `.app.sha256` + `SHA256SUMS.txt`（不需要 java，走 hvigor release 签名）
6. 包结构核验：`pack.info` 身份 / 模块设备面 / 权限 18·9 / HSP 内核心 zip sha / 关键 abc 字符串
7. 交付并**分开写**：「包结构核验通过」≠「真机可用」（本机无 hdc）

---

## 4. 环境边界（本机）

- 历史曾无设备通道；2026-11-13通过devecocli探到MateBook14/API26，但本轮Beta覆盖部署被9568322信任来源策略拒绝，UI仍未验证。
- 2026-11-13 Java已可用，SDK工具对本轮Beta APP/HAP/HSP独立验签通过；这不等于设备来源信任或授权通过。
- `AF_UNIX` 全局被禁；`rm` 被 safe-bin shim 接管 ⇒ 删除用 `python3` 的 `os.remove` / `shutil.rmtree` 并回读验证。
- 出包 / 打包命令会撞 safe-delete 批量阈值（50），只对单条构建命令加 `CODEBUDDY_SAFE_DELETE_ENABLED=0`。
- 依据：[`docs/352`](352-本地HDC调用检查…md)、`AGENTS.md` 环境约束段。

---

## 5. 文档体系（单一真源）

| 主题 | 唯一真源 | 历史档处理 |
|---|---|---|
| 工作规范 / 红线 / 流程 | `AGENTS.md` | — |
| 编号文档索引 | `docs/README.md` | 被推翻的方案在索引里标「已回退 / 已推翻」 |
| 三端归属 / 平板几何 | `docs/385` + `docs/386` | `381/382/383/384` 已加作废标记 |
| 0.2.2 侧栏 DOM 契约 | `docs/379` + `docs/380` | — |
| 云空间配置 | `docs/374` | `docs/375` 已回退；`docs/377` 双字段措辞已订正 |
| 权限面 | `AGENTS.md` + `check-permission-surface.mjs` | 含「恒 8 条 / 11 条」的历史档按当时读数保留、文首补时效标记，权威文件写当前口径 |
| 对外发布口径 | [`docs/408`](408-1.1.8更新日志（官方发布口径）.md) | 唯一对外更新说明；只列确认无误、非反复的修复 |
| 项目结构 / 硬约束索引 | `docs/353` | 历史「当前唯一出处」表述已改为「以代码/配置为准」 |

> 规则（见 `AGENTS.md` §7「编号文档编写规约」）：**新增文档只记确认无误的功能修复 / 新增能力**，不记过程与复盘口水账；同一问题只留一篇；已推翻结论删除或就地更正，保留的历史档文首加时效标记；权威文件（AGENTS / README / 353 / HANDOFF / 408）写当前口径。

---

## 6. 归档与历史

- [`HANDOFF-2026-11-06-historical.md`](HANDOFF-2026-11-06-historical.md)：2026-10-20 ~ 11-05 逐轮出包流水账（含互相推翻的结论，只读留档）。
- `HANDOFF-2026-10-21-historical.md`、`HANDOFF-2026-10-23-historical.md`：更早的交接快照。
- [`docs/268`](268-AGENTS.md迁出的编号流水账与历史坑库.md)：编号档位说明与坑库存档。
- `dist/frozen/meeting-mode-20261031T125746/`：已下线 meeting-ai / speech-models 的唯一源码副本，**禁止删除**。

---

## 7. 下次接手先读

1. `AGENTS.md`（规范、红线、流程）
2. 本文件 §1 当前状态 + §2 红线
3. `docs/README.md`（编号索引）
4. 若涉及核心升级：`docs/365` / `docs/366` / `docs/367`
5. 若涉及三端 / 侧栏：`docs/385` / `docs/386` / `docs/379` / `docs/380`

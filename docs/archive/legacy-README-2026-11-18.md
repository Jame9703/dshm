# DSHM 文档导航

> 当前源码基线：**`1.1.8 / 1010017`**（`AppScope/app.json5`）；核心以 `hostcore/core-recipe.json` 为准（当前 `0.2.2-rc.4+dshm.1`）。最新状态与证据一律见 [`HANDOFF.md`](HANDOFF.md)。
> 最后复核：2026-11-18。
>
> 对外发布口径的 1.1.8 更新说明见 [`408-1.1.8更新日志（官方发布口径）.md`](408-1.1.8更新日志（官方发布口径）.md)；
> 1.1.7 → 1.1.8 邀请测试阶段的历史更新见 [`399-1.1.8更新说明（1.1.7邀请测试之后）.md`](399-1.1.8更新说明（1.1.7邀请测试之后）.md)（专用本地模型承诺已撤回）。
>
> 先读 [`HANDOFF.md`](HANDOFF.md)。本文只负责导航，不重复交接状态。
>
> **新增编号文档前先读 `AGENTS.md` §7「编号文档编写规约」**：只记确认无误的功能修复 / 新增能力，
> 同一问题只留一篇，错误结论删除或更正，不再记过程与复盘口水账。

## 1. 事实优先级

文档冲突时按以下顺序判断：

1. 当前源码、配置、HAP 和运行中的设备；
2. 仓库门禁与 `dist/acceptance/` 真机证据；
3. [`HANDOFF.md`](HANDOFF.md)；
4. 本文；
5. 历史编号文档。

历史文档用于追溯根因，不代表当前版本状态。旧文档里的权限数、兼容版本、
包名、核心版本和性能读数在未经复核时不得直接引用。

## 2. 接手阅读顺序

| 顺序 | 文档 | 目的 |
|---|---|---|
| 0 | [`353-项目现状基线（单工作区·交付物·已落地与未落地）.md`](353-项目现状基线（单工作区·交付物·已落地与未落地）.md) | 现状唯一出处：单工作区、交付物、已落地/未落地与三条关闭项 |
| 1 | [`AGENTS.md`](../AGENTS.md) | 单工作区约束、真机数据保全、权限铁律、必跑门禁 |
| 2 | [`HANDOFF.md`](HANDOFF.md) | 当前状态、已完成、未完成、展望、构建和验收 |
| 3 | [`189-历史文档合并与移交索引（DSHM-beta-1.1.4-core+dshm.73）.md`](189-历史文档合并与移交索引（DSHM-beta-1.1.4-core+dshm.73）.md) | 旧结论替代表、历史文档分层、清理记录 |
| 4 | [`50-端侧核心运行架构.md`](50-端侧核心运行架构.md) | 运行时、核心树、权限边界与端侧架构 |
| 5 | [`90-DSH鸿蒙原生实现全流程.md`](90-DSH鸿蒙原生实现全流程.md) | 从构建到验收的端到端流程 |
| 6 | [`70-鸿蒙移植踩坑与修复总览.md`](70-鸿蒙移植踩坑与修复总览.md) | 按主题查历史坑 |
| 7 | [`261-原生PTY回归恢复（共享HSP与权限面）.md`](261-原生PTY回归恢复（共享HSP与权限面）.md) | 2026-10-25 PC / Edge / Pro Max 原生 PTY 恢复与真机证据 |
| 8 | [`262-普通平板PC顶栏回归与侧栏入口接管.md`](262-普通平板PC顶栏回归与侧栏入口接管.md) | 2026-10-25 普通平板 PC 风格顶栏、常驻窄轨与 Web 侧栏按钮接管 |
| 9 | [`263-1.1.7 AGC邀请测试候选与环境清理.md`](263-1.1.7%20AGC邀请测试候选与环境清理.md) | 1.1.7 AGC 邀请测试 APP、权限/迁移/无 APK 复核与 16.45 GiB 环境清理 |
| 10 | [`264-养鱼插件运行环境落地（Node-JIT与随包ffmpeg）.md`](264-养鱼插件运行环境落地（Node-JIT与随包ffmpeg）.md) | 养鱼插件独立 Node、JIT fetch、ffmpeg/ffprobe 闭包采集与运行期落位 |
| 11 | [`267-迁移鸿蒙PC自托管开发缺口与修复方案.md`](267-迁移鸿蒙PC自托管开发缺口与修复方案.md) | 2026-10-28 评审稿：鸿蒙 PC 自托管开发的 12 项缺口与逐项修复方案、验收判据、执行顺序 |
| 12 | [`268-AGENTS.md迁出的编号流水账与历史坑库.md`](268-AGENTS.md迁出的编号流水账与历史坑库.md) | `AGENTS.md` 瘦身（117,748 → 32,757 B）迁出的编号流水账、核心版本逐档沿革与历史坑库（存档） |
| 13 | [`269-修复落地与Beta合并包出包（core-rc.4+dshm.97）.md`](269-修复落地与Beta合并包出包（core-rc.4+dshm.97）.md) | 2026-10-28 落地记录：按 `docs/267` 逐项修复（含 6587 假红真相）、本机构建环境 7 个坑的对策、Beta 合并 APP 交付读数 |
| 14 | [`270-关于菜单与开源组件声明（顶栏入口·逐条清单·Beta重编）.md`](270-关于菜单与开源组件声明（顶栏入口·逐条清单·Beta重编）.md) | 「关于」菜单项（版本 + 逐条开源组件声明 + 源码/版权 + 技术支持）、清单生成器与完整性强校验 |
| 15 | [`271-折叠屏适配（单屏锁竖屏·设置面板手机化·宽度断点）.md`](271-折叠屏适配（单屏锁竖屏·设置面板手机化·宽度断点）.md) | 折叠屏适配：`foldStatus`/`FoldDisplayMode` + 宽度断点；单屏锁竖屏、设置面板手机化；entry 与 phone 两条壳层分支同步（8 臂门禁） |
| 16 | [`272-平板侧栏收口（不干预官方）与自绘顶栏窗口拖动.md`](272-平板侧栏收口（不干预官方）与自绘顶栏窗口拖动.md) | 普通平板侧栏回归「官方默认」（删点击式常驻自愈与 56px 窄轨、0 列规则排除平板）+ 自绘顶栏接 `startMoving()` 修自由窗口拖不动（两道门禁反转） |
| 17 | [`273-2026-10-28修复汇总（构建链·上游同步·文档治理·关于页·折叠屏·平板侧栏·窗口拖动）.md`](273-2026-10-28修复汇总（构建链·上游同步·文档治理·关于页·折叠屏·平板侧栏·窗口拖动）.md) | **当天总入口**：四批改动（`269`–`272`）的归口、构建链 7 个坑、门禁新增/修改、出包链与待办 |
| 18 | [`274-手持档长时任务熄屏就断的两道治理与HDC调用链修正.md`](274-手持档长时任务熄屏就断的两道治理与HDC调用链修正.md) | 手持档保活判据扩到"在途事实"（activeStreams/outbox）+ 系统取消后退避续期 + diag；HDC 调用链"沉默≠没有设备"的诚实分类（含修掉移植坏段） |
| 19 | [`275-链接不跳浏览器（网页侧全量外开接管与原生导航兜底）.md`](275-链接不跳浏览器（网页侧全量外开接管与原生导航兜底）.md) | 垫片接管**所有** http(s) 锚点（原只认 `target=_blank`）+ Web 组件 `onLoadIntercept` 兜底；含"读不到其他目录"的复核留档（按用户指示不实施） |
| 20 | [`276-代码复核与构建产物清理及AGC重编译.md`](276-代码复核与构建产物清理及AGC重编译.md) | 2026-10-29 代码复核：审出并修 2 个真缺陷（主机名前缀绕过 / px→vp 用错密度字段）、8 个点取证确认无问题、清理构建产物 6.42 GiB、21 道门禁全绿、AGC 包全量重编 |
| 21 | [`277-打字顿挫定位（桥方法泄漏×日志写放大）与优化.md`](277-打字顿挫定位（桥方法泄漏×日志写放大）与优化.md) | 2026-10-29 性能定位：`platformPcMode` 漏进 methodList ⇒ 300ms tick 每拍打 6 行 ArkWeb 错误（全链 12.5 万次 / 60% 日志量）；已修 + 新门禁 `check-bridge-methodlist`；清 247 MiB 旧档；两项降频建议待拍板 |
| 22 | [`278-两日修复落实情况复核（独立取证与未闭合项）.md`](278-两日修复落实情况复核（独立取证与未闭合项）.md) | 第三天独立复核：6 大类落地属实、5 项未闭合（P0×1/P1×2/P2×2）；附 toybox grep 静默漏报的检索纪律 |
| 23 | [`279-沉浸光感调研（API26特性可行性与实现方案）.md`](279-沉浸光感调研（API26特性可行性与实现方案）.md) | 沉浸光感 = backgroundBlurStyle+AdaptiveColor+ThemeColorMode 三件套；**强度数值无公开 API**；Web 本体不可挂特效（ArkUI 容器层可全量）；含 278 五项整改结果与三步实现方案 |
| 24 | [`280-沉浸光感二次调研（官方AI方案逐条求证与重新规划）.md`](280-沉浸光感二次调研（官方AI方案逐条求证与重新规划）.md) | **修正 279**：真正 API 是 `uiMaterial`/`systemMaterial`（26.0.0）；官方 AI 22 条逐项求证（"仅标题栏生效"无 SDK 依据且有仓内真机反证；MaterialLevel 是设备算力档非用户设置）；分层重规划三步方案 |
| 25 | [`281-侧栏浏览器卡死与沉浸光感观感复核（端口偏移断链）.md`](281-侧栏浏览器卡死与沉浸光感观感复核（端口偏移断链）.md) | 侧栏浏览器 P0：扩展写死 19390 / beta 宿主听 19391；`startAbility` 假成功；沉浸光感观感复核 |
| 26 | [`282-Web内沉浸光感只读诊断（标记选择器内核全通过卡在白底与旧包）.md`](282-Web内沉浸光感只读诊断（标记选择器内核全通过卡在白底与旧包）.md) | beta 侧只读诊断：标记/选择器/内核三项全通过，卡在「白底×白材质零增量」+「设备跑的垫片比仓库旧一版」 |
| 27 | [`283-Web内沉浸光感（垫片实现·三次失败复盘与最终口径）.md`](283-Web内沉浸光感（垫片实现·三次失败复盘与最终口径）.md) | 三次失败复盘（兄弟节点取不到背景 / A+B 排版错位 / 伪元素被 overflow 裁 + 没重新出包）与垫片最终实现口径 |
| 28 | [`284-深色主题复测（深色玻璃规则从未生效-html应为body）.md`](284-深色主题复测（深色玻璃规则从未生效-html应为body）.md) | 深色复测：深色规则锚 `html[data-ds-dark-theme]`，官方 18 处全锚 `body` ⇒ **深色材质从未生效**，深色下两列成刺眼亮块（`rgb(187,195,210)` 压 `rgb(21,21,23)`）；含原生材质"已移除"的自我更正与 toybox `grep -c` 静默漏报复踩记录 |
| 29 | [`285-深色玻璃复测通过（dark字段把空串属性误报成none）.md`](285-深色玻璃复测通过（dark字段把空串属性误报成none）.md) | 284 三处修法全部落实后复测：**亮暗两档玻璃均实测生效并正确随主题切换**（深 `rgba(38,44,58,0.82)` / 亮 `rgba(214,223,240,0.86)`，切换前后 `cols`·`rect`·`backdrop` 不变、唯 `computedBg` 翻转）；遗留探针 `dark` 字段用 `\|\|` 把 body 空串属性恒报成 `none`（CSS `[attr]` 只看存在性），修法改显式 `=== null` 并区分 `empty`/`absent` |
| 30 | [`286-第三方皮肤被遮（未重启挂载加玻璃important覆盖）.md`](286-第三方皮肤被遮（未重启挂载加玻璃important覆盖）.md) | `@iasiv5/dsh-skins@1.5.19` 不显示的两重原因：**① 装了但未挂载**（宿主 18:12 启动 / 皮肤 18:21:46 装，差 585s，安装器写明需重启）；**② 玻璃 `background:…!important` 短路了皮肤的 `--dsw-alias-bg-base` 变量通路**（皮肤靠变量传导到列、我们直接钉死列背景，86% 不透明只让背景图透出 14%）；含 A/B/C/D 四种取舍与"皮肤存在时玻璃让路"的推荐方案 |
| 31 | [`287-沉浸光感改由皮肤插件实现（能力面调研与规划）.md`](287-沉浸光感改由皮肤插件实现（能力面调研与规划）.md) | 按用户新思路调研"用皮肤插件实现沉浸光感"：垫片"抢列背景+`!important`"注定与主题冲突（用户直觉对了一半）；插件能力面实读（`ctx.theme.overrideTokens` / `ctx.slots.inject` / `<style>` 注入三件套齐备，官方自身用 `--dsw-menu-backdrop-filter` 做菜单毛玻璃）；三条硬约束（变量层赢不了 `!important`、白底模糊无意义、`backdrop-filter` 只能透不能造）；R1 止血 / **R2 推荐（皮肤接管配色+材质+背景）** / R3 生态化，含六步执行顺序与"先有背景再谈材质"的核心结论 |
| 32 | [`288-破案：玻璃挂错了层级（列是底不是浮层）.md`](288-破案：玻璃挂错了层级（列是底不是浮层）.md) | 由用户"输入框滑动时能看到玻璃"破案：`backdrop-filter` 一直有效，但**挂在列的 `background` 上 —— 那是底层板子，模糊到的永远是自身底色，不含其内部滚动内容**；官方输入框能看见是因 `position:absolute`+`z-index:-1` **浮在滚动内容之上**，且其底色 `#f8f9faf0`（**94%**）比我们的 86% **更不透明** ⇒ 透明度与颜色皆非主因，**背后有无内容才是**；修正 282/283 前序结论，给"挂浮层 + 半透明令牌 + 全局背景"的正确做法与对照实验。**⚠️ 其因果归因已被 `docs/289` 作废，技术事实仍有效** |
| 33 | [`289-皮肤玻璃现象复核（Host侧未加载三方皮肤与观察矛盾）.md`](289-皮肤玻璃现象复核（Host侧未加载三方皮肤与观察矛盾）.md) | 用户纠正"是开启第三方皮肤时出现"后复核：`cordis.patch.yml` **48 个运行条目零三方插件**、`pid`/`startedAt` 自 18:12 未变、页面无 `data-dsh-*skin` ⇒ **宿主从未加载皮肤**；判断输入框玻璃实为官方自带（`_7yHdaG_panel:before` + `blur(40px)`）；**如实上报证据与观察的矛盾**并列 5 种可能，给出"关皮肤→滑→开皮肤→滑"四步对照取证方案；同时作废 `docs/288` 的因果结论 |
| 34 | [`290-沉浸光感皮肤插件（方案调研与素材规划）.md`](290-沉浸光感皮肤插件（方案调研与素材规划）.md) | 沉浸光感皮肤插件方案：**不必从零写** —— `@iasiv5/dsh-skins` 框架已实现"会话区铺背景图"（`client.js:433` `backgroundArt`，内嵌 base64 WebP 约 102KB）与完整 skin spec（17 必填 + 7 可选，`riding` 配色/`backgroundArt` 图/`cssSegments` 点缀）；素材三选项（官方库需授权拷贝 / **推荐程序化 CSS 渐变+SVG 2-5KB 零版权** / 第三方有风险），含 Huawei 商标抽象化提醒与四步实施规划、亮暗双档验收判据 |
| 35 | [`291-稳定性与性能完整测试报告（日常使用加开发环境）.md`](291-稳定性与性能完整测试报告（日常使用加开发环境）.md) | 完整测试报告（38 门禁 + 组件矩阵 + 性能实测）：**功能面健康、性能优秀**（bash 52ms/python 98ms/grep 43ms，41min 零崩溃）；**3 个必修缺陷** —— ① `__DSHM_BRIDGES__` **6914 次**报错（6.2% 日志体量，自 `docs/281` 的 4280 次持续增长）② jitless 下**全局 `fetch()` 崩溃**（产品 `dshmFetch` 路径正常，仅第三方代码踩坑，垫片只拦模块解析未拦 HTTP 派发）③ `check-profile-pnpm-bridge` **卡死 rc=124**（插件安装通道失去自动化保护）；含内存 613MB/swap 184MB 警讯与 7 项未覆盖声明 |
| 36 | [`293-包管理环境测试报告（brew缺席与npm假壳pip3实测）.md`](293-包管理环境测试报告（brew缺席与npm假壳pip3实测）.md) | 包管理 20 项实测：**brew 在此环境不存在**（`/usr` 对沙箱不可见，换 `node-brew` 进程读也 ENOENT；**`node-brew` 实为 Node v26.12.1 的 133MB ELF 分发物，非 Homebrew** —— 最易误解点已澄清）；DSHM 实际三件套：**npm/pnpm 假壳**（同一 md5 实现，install/uninstall/版本切换/GitHub 源全通，5 子命令可用 8 个明确拒绝）+ **pip3 26.2.1 真 pip**（装卸 import 全正确，最完整）+ git 2.47.3；**2 个缺陷**：`npm list` 非 profile 目录误报端点不可达且 **rc=0**（根因定位到端点只认 profile 目录）、`npm config` 静默成功；测试残留 left-pad/six 已清理 |
| 37 | [`294-包管理环境复测（293两缺陷已修与291卡死连修）.md`](294-包管理环境复测（293两缺陷已修与291卡死连修）.md) | 复测确认**293 两个缺陷全部修复且无回归**：`npm list` 非 profile 目录改为自动回退 profile（源码 `main.js:2733-2737`，并定位到 busybox `wget` 在 404 与连不上**都返回 rc=1** 的语义陷阱，改用正文开头字符判成功 + 两类失败分开报）③ `npm config` 现输出 `registry=https://registry.npmmirror.com/` 并说明端侧仅此一项；**意外收获**：291 的 `check-profile-pnpm-bridge` 卡死（rc=124 >300s）**已修**（rc=0、47 断言全过、2.9 秒）；**仍存**：`__DSHM_BRIDGES__` 由 780 降至 **420 次/分钟**（未根除，新线索 `permission map is empty` 指向授权问题）、全局 `fetch()` jitless 崩溃未修 |
| 38 | [`303-华为账号登录失败根因（beta包名不在Profile登记范围·1001502003）.md`](303-华为账号登录失败根因（beta包名不在Profile登记范围·1001502003）.md) | 实测读数首行报 **1001502003 `Invalid input parameter value. Invalid clientId or profile`** 的根因取证：AGC Profile 实读 `bundle-name` **只有 `com.dshm.dshclient`**（app-identifier `6917614360926110054` 与 Client ID 逐位一致、设备 2 台均正确），而 beta 出包把 bundleName 改成 **`com.dshm.dshmbeta`**（`build-beta.mjs:243`）⇒ 系统用未登记包名要账号服务被拒；**你已核的 Client ID/指纹/Profile 全对，缺的是"包名"这一维**（不在错误码对照表内）；三条路线：**A 用正式包测（推荐，但跨包名不能 `-r` 覆盖、数据不迁移）** / B AGC 为 beta 单独建应用+新 Client ID（成本高）/ C 临时改回正式包名出包；**并确认上一版"点了没反应"（`{onReceive}` 写法）已修好 —— 现在能报错即回调已通** |
| 39 | [`343-Super-agent环境检测与可修性评估（pnpm构建gh三缺口与平台硬约束）.md`](343-Super-agent环境检测与可修性评估（pnpm构建gh三缺口与平台硬约束）.md) | Super-agent（dsh-superagent 原型）本机环境实测：**语言运行时全达标**（Node v24.2.0 / git 2.47.3 / Python 3.12.14 / 20 核 23.3G / github 与 npm 均 200 / dsh 核心 0.2.1-rc.4 满足 `engines.dsh`）；**4 个真缺口全部实测证明可修** —— ① 真 pnpm（registry 取纯 JS，`pnpm install` 9.3s/289 包）② 构建（**tsdown 的 rolldown 原生 `.node` 被 dlopen 拦** ⇒ 改用 **tsc + esbuild-wasm**，出齐 4 入口、`client.js` 371KB、模块实测可加载）③ 装 profile（官方 `dsh plugin add link:` 被 DSHM 假壳拦 ⇒ profile 内真 pnpm `add -w link:`）④ 启动（裸 node 起不了 dsh：`No usable native binding` ⇒ 必须走 DSHM 宿主 jitless 垫片栈，`DSHM_PROFILE`/`DSHM_PORT` 选 profile）；**两条自我纠正**：受限的是 `.node` 而非所有 ELF（musl 动态 ELF 可跑，`tmux`/`gh` 归 `docs/342` 原生内置），初稿"gh 必须自研垫片"已作废但保留 `gh api` 调用面用于验收；另发现 `ps -o` 在 toybox/busybox 均不支持（控制脚本需垫片）；含 8 项未验证声明与全部测试残留清理记录 |
| 40 | [`344-Super-agent环境复测（tmux-gh已内置与pnpm仍缺）.md`](344-Super-agent环境复测（tmux-gh已内置与pnpm仍缺）.md) | 侧载包复测：**tmux 3.5a 与 gh 2.72.0 已内置**（开发端方向正确），但发现**打包丢了 6 个 SONAME 软链**（实际有 `libevent_core-2.1.so.7.0.2` / `libncursesw.so.6.5`，程序要的是 `.so.7` / `.so.6`）⇒ tmux 起不来；且包装器把「缺库」**误报成「execve 被拒」**（与 `docs/294` 的 npm list 误报同类，建议透传真 stderr）；补链接后 tmux 新建/查询/终止**全通**；**唯一硬缺口仍是 pnpm**（PATH 上是 install-queue 假壳，而 superagent 无构建产物 ⇒ 无 pnpm 一步走不了）；另三处待接线：`dsh` 命令需转发真身、`ps -o` 不支持（控制脚本依赖）、gh 未登录（需专用 Agent 账号 token）；平台两约束未变（原生 `.node` 仍 `No usable native binding`、裸 node 起不了 profile）⇒ 构建仍走 tsc+esbuild-wasm、启动仍走 `DSHM_PROFILE` |
| 41 | [`345-Super-agent环境复测二（tmux-ps-dsh三项已修与pnpm仍缺）.md`](345-Super-agent环境复测二（tmux-ps-dsh三项已修与pnpm仍缺）.md) | Super-agent 复测二：tmux / ps / dsh 三项已修，pnpm 仍缺 |
| 42 | [`346-Super-agent环境复测三（前置全绿与启动无通道）.md`](346-Super-agent环境复测三（前置全绿与启动无通道）.md) | 复测三：前置全绿但启动无通道（含端到端安装实测） |
| 43 | [`347-Super-agent环境复测四（无功能变化与解包软链问题）.md`](347-Super-agent环境复测四（无功能变化与解包软链问题）.md) | 复测四：与上轮无功能变化；解包软链问题 |
| 44 | [`348-超管独立进程实测（判定FAIL·核心树缺superagent种子与卡住空窗口）.md`](348-超管独立进程实测（判定FAIL·核心树缺superagent种子与卡住空窗口）.md) | 超管独立进程实测判定 FAIL：核心树缺 superagent 种子、卡住空窗口 |
| 45 | [`349-双进程双端口实测（能力达成·dsh写死版本与host-ready被抢）.md`](349-双进程双端口实测（能力达成·dsh写死版本与host-ready被抢）.md) | 双进程双端口实测：能力达成但 dsh 写死版本、host-ready 被抢 |
| 46 | [`350-v17验证与日志抓取（附路径bug与启动期崩溃）.md`](350-v17验证与日志抓取（附路径bug与启动期崩溃）.md) | v17 验证与日志抓取：包 sha 一致；附路径 bug 与启动期崩溃 |
| 47 | [`351-dsh-plugin-add-link失败（拒绝者是宿主安装器与dsh再次写死版本）.md`](351-dsh-plugin-add-link失败（拒绝者是宿主安装器与dsh再次写死版本）.md) | dsh plugin add link 失败：拒绝者是宿主安装器与 dsh 再次写死版本 |
| 48 | [`352-本地HDC调用检查（二进制可跑但UDS绑定被拒）.md`](352-本地HDC调用检查（二进制可跑但UDS绑定被拒）.md) | 本地 HDC 调用检查：二进制可跑但 UDS 绑定被拒（本机无 hdc 的依据） |
| 49 | [`365-新版libnode24.9落地复核与核心升级前置评估.md`](365-新版libnode24.9落地复核与核心升级前置评估.md) | 换库后的只读复核：新件 v24.9.0 / 155,408,704 B / 已签名；**P0** 是 23 处 `movz w0,#425/426/427 + bl` 里只有 16 处指向 `syscall@plt`（其余 7 处的 427 是 OpenSSL NID 常量），旧门禁常量停在 24.2.0 布局且广扫「假绿」；npm `latest=0.2.1-rc.5`、`next=0.2.2-rc.1`（要求 `node>=24.9.0`）；96 条门禁基线 10 红；附升级成本与执行顺序 |
| 50 | [`366-新版libnode24.9中性化落地与dshm.114重打.md`](366-新版libnode24.9中性化落地与dshm.114重打.md) | 按「分两步 + 字节中性化重签」落地：16 槽中性化 → 剥离旧 codesign → CLT 原生工具重签 → 门禁常量迁到 24.9 布局（主测 16/0、自检 8/0）；核心重打 `+dshm.114`、resfile 单容器；补齐 OSS 生成器 16 个 guest 包许可证、把 126MB 旧库备份移出随包目录；全量回归 96/10红 → 99/0红、**OK→BAD=0**；附代码审核、遗留风险与回退路径 |
| 51 | [`367-dsh上游同步到0.2.2-rc.1与beta出包实测.md`](367-dsh上游同步到0.2.2-rc.1与beta出包实测.md) | 361 那个「被 Node 引擎卡住」的卡点由 366 解锁后，把基线从 `0.2.1-rc.5+dshm.114` 换到 **`0.2.2-rc.1+dshm.1`**：干净闭包重物化（612 包 / 39,398 文件 / 359.0 MiB）→ 容器 108,498,536 B / 44,871 条 / sha `8709adea…`；**31 个补丁只迁 1 处锚点**（fs-local 发布段双形态）、8 个插件 peer 跟版；契约 144→**193**（+51/−2，被删的两条零调用点）；全量回归 **99/0**、与 dshm.114 逐条对比 **OK→BAD=0**；beta 合并包 608,300,792 B / sha `0863cbb7…`，内含核心容器与中性化后的 libnode 均逐件核过；附 `MergeProfile` 撞 safe-delete 阈值（50）的豁免口径与真机未验/未验签的边界 |
| 61 | [`377-云空间走通清单-权限硬前置与执行顺序.md`](377-云空间走通清单-权限硬前置与执行顺序.md) | 用户定调**继续走云空间**（大众用户自付会员）⇒ 把"走通"拆成可执行顺序：**§0 更正：`DISTRIBUTED_DATASYNC` 属 `DISTRIBUTED_DEVICE` 跨设备，端云同步（`DISTRIBUTED_CLOUD`）不需要它**（用户指出 ACL 里找不到是对的）⇒ 不改权限面 / Profile / ACL，原 §1 的 17→18 整节作废；真正前置是系统「云空间」开关、华为账号、AGC 容器 `DSHM` / 表 `sync_units` / 字段逐字一致；AGC 侧 12 字段表（含新增 `device_id`/`uploaded_at`）；**本地表两列与迁移已完成**；给出 5 条"算走通"的判定（`cloud_gid` 非空、云元数据非 0、时差被覆盖等） |
| 60 | [`376-云同步成本测算（3000-4000用户规模）.md`](376-云同步成本测算（3000-4000用户规模）.md) | 用户指出实际用户已 **3000–4000**（不是内测几个人）⇒ 定量测算：**不优化（每日全量快照、云端不清理）首月 ≈210 元、年末 ≈1,880 元/月且逐月单调增长**；按「增量 + gzip(≈10×) + 每设备 7 天保留 + 手动触发」优化后稳态存储 ≈9 GB、**月费 ≈1 元**；给出四条必须落地的设计约束与横向对比（内网自建合规最好、CFK 最省），并再次提示 **2026-10-28 起云数据库/云存储停止新开发者接入**，先验证能否开通 |
| 59 | [`375-云同步改道CloudFoundationKit方案.md`](375-云同步改道CloudFoundationKit方案.md)（**已回退，勿实施**；唯一口径见 `374`） | 用户确认华为云空间同步**需要会员** ⇒ 改走 **Cloud Foundation Kit**（云数据库存元数据 + 云存储存文件本体）：给出 AGC 侧要开通的两个服务与 **`SyncUnit` 对象类型 12 字段**（主键 `unitId`）、存储实例 `dshm-sync`、zone `dshmsync`、须导出 `schema.json`；鉴权用**华为账号 Access Token 自定义 `AuthProvider.getAccessToken()`**（不引入 AGC 认证 SDK，保留"弹框确认登录+脱敏显示"）；端侧 C1–C8 改造清单（删 `setDistributedTables`/`cloudStructuredDataSyncEnabled`、表迁移 `payload ASSET→cloud_path`、上传编排、合并去重、出错码人话化）；3 个待真机实测点（华为账号 token 是否算认证用户、PC/2in1 自 6.1.0(23) 起支持、>2MB 走云存储）；**374 的容器/表名方案作废** |
| 58 | [`374-云空间端云同步AGC配置核对与字段改造清单.md`](374-云空间端云同步AGC配置核对与字段改造清单.md) | 用官方指南 + 本仓 DDL 核对 AGC 上建的云空间对象：**容器名必须 `DSHM`、数据类型名必须 `sync_units`**（当前叫 `syncdshm` ⇒ 端云同步根本不认这张表，这是 `CLOUD_DISABLED` 的一条直接成因）；字段缺 `kind`/`metadata`、`workspace` 应为 `workspace_id`，且「设备+日期」必须新增 `device_id`/`uploaded_at`（`workspace_id` 是项目路径哈希不含设备、`updated_at` 是内容修改时间不是上传时间）；附 12 列完整表、端侧去重主键勾选、AGC 开关与 6 条端侧改造清单；**提醒生产环境发布后字段不可改** |
| 57 | [`373-云同步改造与平板移动化及三端一致-确认清单与实施方案.md`](373-云同步改造与平板移动化及三端一致-确认清单与实施方案.md) | 确认清单 + 实施方案（未动代码）：云同步四条需求逐条落到实现（账号脱敏取手机号/邮箱、云端 `dshm-sync/<deviceId>/<yyyy-MM-dd>/`、跨设备选"设备+日期"恢复会话+插件清单、`CLOUD_DISABLED schedule=2` 是**系统侧拒绝**不是提示 bug 且"上传成功"文案必须拆成"本机/云端"两态）；平板改移动布局（默认左栏展开、DSHM+折叠按钮常驻、保住自由窗口拖拽）；**确证三端通知不一致**（entry 仅 `id<=0` 播、phone 无条件播）并给三方案；4 个待拍板决策 + S1–S5 排期与出包计划 |
| 56 | [`372-升级Node前七项修复的回归验证与三端处置.md`](372-升级Node前七项修复的回归验证与三端处置.md) | 换核换库后复验升级前那批修改：插件安装/Node 环境/提示音/平板沉浸/托盘图标 5 项结构仍在（未随换核失效），云同步仍未修（缺 `DISTRIBUTED_DATASYNC`）；**挖出并修掉一个一直静默失效的判据**——Host 写 `workload.json` 时读的是 `card.running`/`card.turnActive`（**这两个键从未被写入**），真实形状是 `session.state==='running'` ⇒ `refs` 恒缺"turn 在跑"⇒ 熄屏被判"无保活诉求"（客户「熄屏就停/平板无法后台任务」的宿主侧一半原因）；已改判据 + 新增门禁 `check-workload-refs`（3 个变异体自检）并进 CI；全量回归 99/0 |
| 55 | [`371-客户反馈18条新版核对与处理清单.md`](371-客户反馈18条新版核对与处理清单.md)（其中 #12「平板走 PC 布局」已按 2026-11-06 口径变更） | 客户反馈 18 条（表格无版本列，反馈来自 `1.1.7/1010009 + dshm.109`）对照新版 `1.1.7/1010014 + 0.2.2-rc.1+dshm.1` 逐条核对：**已解决 0**、部分解决 2（#3/#5 熄屏冻结：保活根因已迁 ArkTS 长时任务，但 `KeepAlive.ets:248-267` 判据仍过窄）、未解决 5（#8 翻译 bundle 被 `removeBundles` 移除、#12 平板走 PC 布局属策略、#13/18/19 云同步缺 `DISTRIBUTED_DATASYNC`+登录态不落盘、#16 插件空表+侧栏入口不可滚）、信息不足 11（8 条附件未落盘）；**纠正**「入口列表在壳层」的误判——`更多工具` 实为核心树 `dsh-client-ui-sidebar-right/lib/client.js`；附 P0-1/P0-2/P0-3 计划（影响/依赖/排期/验收）与补件清单 |
| 54 | [`370-AGC上架包编译记录-1.1.7-1010014-核心0.2.2-rc.1.md`](370-AGC上架包编译记录-1.1.7-1010014-核心0.2.2-rc.1.md) | AGC 上架包（`build-agc.mjs`）编译与逐件核验：`dshm-1.1.7-1010014-dshm.1-AGC-invite-20261105T115254.app` = **602,116,181 B / sha `11bc36dd…f695`**；`bundleName com.dshm.dshclient`、entry **17 条**/phone **9 条**、内嵌 Profile `type=release`+`app_gallery`+**`allowed-acls` 7 条**、hsp 内核心容器 `0.2.2-rc.1+dshm.1` 与 `libnode`(带 `.codesign`) 均对上；构建期临时改的 `signingConfig` 已逐字回滚；附上传前待办（versionCode/隐私声明/真机验收/勿作 hdc 侧载） |
| 53 | [`369-换核心后项目复核与代码审核.md`](369-换核心后项目复核与代码审核.md) | 换 `0.2.2-rc.1` 后的复核：全量门禁 **99/0**（复跑）；beta 包**逐件相符**——entry 仍 **17 条权限**（beta 只换身份）、hsp 内核心容器 sha 与 `dist/core` 一致、`libnode` 带 `.codesign`（`docs/358` 的修复确在包里）、容器内 profile 补丁与源**逐字节相同**、11 个 dshm 插件 peer 全等于 `0.2.2-rc.1`、树信息 304 行（11 个 UNKNOWN 全是 `cordis:group` 占位）；`docs/353`–`367` 承诺逐条对到落点；**代码审核 4 条**：8 处 patch id 悬空（既有 `warn-and-skip`，语音走原生桥不受影响）、**`bin/dsh` 用字典序取"最新核心"与宿主 `compareVersions` 不一致（`+dshm.10` 前必须修）**、`docs/355` 版本判据漂移、`_cores` 兜底路径 entry 专用 |
| 52 | [`368-DSHM权限面与内置环境对WorkBuddy环境面的对齐规划.md`](368-DSHM权限面与内置环境对WorkBuddy环境面的对齐规划.md) | 只读梳理 + 规划（**未执行任何变更**）：DSHM entry 17 / phone 9 逐条与 WorkBuddy `electron.hap` 实读的 30 条做集合运算（交集 11 / 仅 DSHM 6 / 仅 WB 19）；**ACL 实况**：上架包（AGC 签名 release profile）7 条齐全、正式调试 7 条、**本地测试 beta 只有 2 条**——beta 用独立 App ID，独立 bundle 沿用不了正式 App ID 的 ACL（`build-beta.mjs` 自己断言），故**沙箱/目录/剪贴板类能力只能在正式签名包上验**，这是测试覆盖边界而非缺陷；环境面实测差距三件——JIT（WB 有 `kernel.ALLOW_WRITABLE_CODE_MEMORY`、DSHM 全 `--jitless`）、原生 ripgrep（DSHM 是纯 JS）、**Node 版本 24.9.0↔24.13.0**（注：`engines.node` 只要 `>=24.9.0`、24.9.0 已合规，升 24.13 是**用户拍板的主动对齐**——与 WB 同版、问题可复现）；给出 A2–A9 逐项调整点（A1 beta ACL 已撤回；A4 Node 升级保留为 P1，含落点/优先级/验收）与**不做清单**（beta ACL、全盘、分布式同步、12 项系统集成），9 条待确认项 |
| 25 | [`281-侧栏浏览器卡死与沉浸光感观感复核（端口偏移断链）.md`](281-侧栏浏览器卡死与沉浸光感观感复核（端口偏移断链）.md) | 侧栏浏览器"正在打开…"根因=扩展写死 `19390` ↔ 宿主 beta 包听 `19391`（端口偏移断链）+ `startAbility` 只报受理不验起来的假成功；沉浸光感**已接入**、看不出系白底×THIN×只挂条带×不碰 Web 画布的必然结果；另记 `__DSHM_BRIDGES__` 报错仍 18 次/分钟 |
| 26 | [`282-Web内沉浸光感只读诊断（标记选择器内核全通过卡在白底与旧包）.md`](282-Web内沉浸光感只读诊断（标记选择器内核全通过卡在白底与旧包）.md) | A–G 七项只读诊断：`dshm-glass-top`/`dshm-glasscol` 已挂、选择器命中、`CSS.supports=yes` 三项全通过 ⇒ 看不出系「`rgba(249,250,251,0.72)` 半透明白叠纯白画布=零增量」；另查出**设备与所有已出包垫片比仓库落后一版**（`150%` vs `180%`，源码 17:06:50 改动晚于 17:02:59 的包）；含 UA/rect/toggle class 四项无读数的通道原因与探针补字段建议 |
| 62 | [`378-账号显示改为昵称或脱敏手机号邮箱（profile scope端侧实现）.md`](378-账号显示改为昵称或脱敏手机号邮箱（profile scope端侧实现）.md) | 客户反馈"显示得很像内部代号" ⇒ 根因是 UI 显示 `****abcd`（脱敏 **UnionID**）。**官方查证**：《获取头像昵称》指南明文「未设置昵称默认返回华为账号绑定的**匿名手机号/邮箱**」且「**此场景无需申请账号权限**」；`phone`/`quickLoginAnonymousPhone`/`email` scope 需 AGC 审批（且「获取您的手机号」仅游戏类+企业开发者），明文手机号 REST 还需开发者服务器 ⇒ 按权限面铁律**一律不接**。落地：`HuaweiCloud.fetchAccountDisplayName()` 只设 `scopes=['profile']`、不设 `permissions`、state 校验、二次脱敏；`SyncEngine` 增 `accountLabel` + 「已登录」兜底，**绝不退回 `****abcd`**；三处 UI 改读新字段；确认框文案从「不会获取头像昵称等资料」订正为如实说明会再请求一次授权且可拒绝；entry/phone/原生面板三条登录路径均接线。门禁从 3 条扩到 **6 条口径 / 10 变异体全判红**，插件门禁 50 条判据通过；顺手修了核心 0.2.2-rc.1 物化后官方设置骨架新增 `ctx.remoteAccess` 导致的测试脚手架漂移。**权限面 17/9 不变、不重签 Profile、不提 ACL**；附首次系统授权页的交互变化与真机验收清单 |

## 3. 当前基线

| 项 | 值 |
|---|---|
| 工作区角色 | `com.dshm.dshclient` 正式/调试多端工程（唯一工作区） |
| 应用版本 | `1.1.8 / 1010017` |
| 核心 | 以 `hostcore/core-recipe.json` 为准（当前 `0.2.2-rc.4+dshm.1`） |
| 最低 API | `6.1.0(23)` |
| 目标 API | `26.0.0` |
| 权限 | entry 18 条 / phone 9 条；release Profile 含 8 条 allowed-acls |
| APK 相关条目 | 0 |

本机只有唯一工作区 `~/data/DSHM-deveco-workspace`；`DSHM-mobile` 已于
2026-11-03 删除，`tools/check-two-project-parity.mjs` 在本机 rc=2 属**环境受限**，不是缺陷。

## 4. 当前权威文档

### 工程与约束

| 文档 | 作用 |
|---|---|
| [`../README.md`](../README.md) | 项目定位、能力、架构、构建、快速开始和数据保全 |
| [`../AGENTS.md`](../AGENTS.md) | 自动化助手和开发者必须遵守的仓库约束 |
| [`HANDOFF.md`](HANDOFF.md) | 项目交接唯一入口 |
| [`189-历史文档合并与移交索引（DSHM-beta-1.1.4-core+dshm.73）.md`](189-历史文档合并与移交索引（DSHM-beta-1.1.4-core+dshm.73）.md) | 历史结论替代关系与清理记录 |

### 契约、架构和方法

| 文档 | 作用 |
|---|---|
| [`00-开发任务书.md`](00-开发任务书.md) | 项目范围与验收的原始任务书；远程客户端定位已由 D6 更正 |
| [`10-协议兼容事实基线.md`](10-协议兼容事实基线.md) | 协议、端点、认证、事件和实测矩阵 |
| [`11-请求载荷契约.md`](11-请求载荷契约.md) | RPC 请求和回复载荷 |
| [`12-设置页契约.md`](12-设置页契约.md) | 设置 schema 与写入契约 |
| [`20-产品需求与体验规范.md`](20-产品需求与体验规范.md) | UI、交互、无障碍和性能体验规范 |
| [`30-技术验证清单.md`](30-技术验证清单.md) | POC 清单和验收方法 |
| [`40-上游升级手册.md`](40-上游升级手册.md) | DSH 上游升级流程、协议漂移和回滚 |
| [`50-端侧核心运行架构.md`](50-端侧核心运行架构.md) | 端侧核心、Node、jitless、执行域和核心版本 |
| [`60-界面重塑-端侧核心.md`](60-界面重塑-端侧核心.md) | 历史界面规范；导航部分已被后续结构取代 |
| [`70-鸿蒙移植踩坑与修复总览.md`](70-鸿蒙移植踩坑与修复总览.md) | 按主题组织的历史坑库 |
| [`80-真机更新与数据保全.md`](80-真机更新与数据保全.md) | 覆盖安装、数据指纹和签名恢复 |
| [`90-DSH鸿蒙原生实现全流程.md`](90-DSH鸿蒙原生实现全流程.md) | 构建、运行时、UI、验收和门禁全流程 |
| [`213-双端工程剥离方案（PC端与移动端拆分·评审稿）.md`](213-双端工程剥离方案（PC端与移动端拆分·评审稿）.md) | PC / 移动双工程拆分的评审稿（方案与决策依据） |
| [`214-双端分离实施记录（PC工程与手机工程）.md`](214-双端分离实施记录（PC工程与手机工程）.md) | 2026-10-21 分离执行记录：两端身份、改动清单、验收步骤、回滚 |
| [`parity-matrix.md`](parity-matrix.md) | 功能对等矩阵和缺口台账 |
| [`device-validation.md`](device-validation.md) | 按批次记录的真机读数和历史验证 |

## 5. 当前 Beta 批次证据

| 文档 | 内容 |
|---|---|
| [`183-API23工作区选择兼容（FolderSelection能力预检与专属目录兜底）.md`](183-API23工作区选择兼容（FolderSelection能力预检与专属目录兜底）.md) | API 23 可安装面与专属工作区兜底 |
| [`184-DSH上游同步0.2.1-rc.2（+dshm.70）.md`](184-DSH上游同步0.2.1-rc.2（+dshm.70）.md) | rc.2 升级、契约零漂移和双端回归 |
| [`185-平板端移除APP顶栏与系统三键（手持档统一窗口壳）.md`](185-平板端移除APP顶栏与系统三键（手持档统一窗口壳）.md) | 平板窗口壳代码收口和待真机项 |
| [`186-新增功能代码审核与双端回归（核心+dshm.72）.md`](186-新增功能代码审核与双端回归（核心+dshm.72）.md) | 卡片、浏览器、快捷方式和双端回归 |
| [`187-手机端底部使用统计与系统手势条避让（Web内容框不再下扩）.md`](187-手机端底部使用统计与系统手势条避让（Web内容框不再下扩）.md) | 手机底部安全区修复 |
| [`188-内测双报告收口与guest SSH客户端（QGA失步复位·分屏视口回正）.md`](188-内测双报告收口与guest SSH客户端（QGA失步复位·分屏视口回正）.md) | QGA、SSH、分屏、键盘输入 |
| [`189-历史文档合并与移交索引（DSHM-beta-1.1.4-core+dshm.73）.md`](189-历史文档合并与移交索引（DSHM-beta-1.1.4-core+dshm.73）.md) | 本次文档合并、旧结论替代与清理 |
| [`190-API26特性可落地清单（基准beta-1.1.4+core0.2.1-rc.2+dshm.74）.md`](190-API26特性可落地清单（基准beta-1.1.4+core0.2.1-rc.2+dshm.74）.md) | API 26 特性可落地清单（只读调研） |
| [`191-2in1电脑模式侧栏入口缺失与仅角点缩放（手持形态+自由窗口的PC模式分档）.md`](191-2in1电脑模式侧栏入口缺失与仅角点缩放（手持形态+自由窗口的PC模式分档）.md) | 2in1 电脑模式保留系统标题栏与四边缩放 |
| [`192-手持档右侧栏打开时左上⊞与标题文字重合（打开右侧栏则藏左侧入口）.md`](192-手持档右侧栏打开时左上⊞与标题文字重合（打开右侧栏则藏左侧入口）.md) | 右栏打开时只藏左侧入口（v2 判据） |
| [`193-手持档右侧栏打开时返回手势直接回桌面（BACK_SHIM增加右侧栏分支）.md`](193-手持档右侧栏打开时返回手势直接回桌面（BACK_SHIM增加右侧栏分支）.md) | 右栏打开时返回先收栏、不回桌面 |
| [`194-系统语音识别长语音Go-No-Go真机结论（PC-2in1，long需滚动会话）.md`](194-系统语音识别长语音Go-No-Go真机结论（PC-2in1，long需滚动会话）.md) | 长语音 Go/No-Go：long 需 18.75s 滚动会话 |
| [`195-会议模式PC端落地与验收（系统语音识别-原生面板-后台录音）.md`](195-会议模式PC端落地与验收（系统语音识别-原生面板-后台录音）.md) | 会议模式 PC 端落地与验收证据 |
| [`196-会议面板UI优化（历史会议与沉浸光感按钮）.md`](196-会议面板UI优化（历史会议与沉浸光感按钮）.md) | 历史会议列表 + API 26 沉浸光感按钮 |
| [`197-会议模式v2调研与方案（AI总结-实时英译-沉浸光感布局）.md`](197-会议模式v2调研与方案（AI总结-实时英译-沉浸光感布局）.md) | 会议 v2 调研：小艺不可接、Host 模型总结/翻译、布局稿 |
| [`198-Host会议AI插件（总结与英译通道）.md`](198-Host会议AI插件（总结与英译通道）.md) | 会议 AI 的 Host 侧通道：文件队列协议、`ctx.llm` 调用形态、失败降级、打包与门禁 |
| [`199-Host同步探测缓存（LOOP-GAP根因与修复）.md`](199-Host同步探测缓存（LOOP-GAP根因与修复）.md) | LOOP-GAP 根因与除根：负结果缓存（治第 2 次）+ 收窄全局模块路径（治第 1 次，摘 `~` 项）、白名单、门禁与真机待验 |
| [`201-手持档首启侧栏缺失的自愈（视口落定复检与一次性自动展开）.md`](201-手持档首启侧栏缺失的自愈（视口落定复检与一次性自动展开）.md) | 内测反馈"首启侧栏缺失、点右上角恢复"：NWeb 早于窗口几何 ⇒ 一次性自动展开（宽视口 + 收起态）+ `onPageEnd` 后 0.9/2.0/4.0s 视口落定复检；带 3 个变异对照臂 |
| [`202-内测三包与APMS-1.1.4分诊及修复对照.md`](202-内测三包与APMS-1.1.4分诊及修复对照.md) | 三包材料 + APMS 1.1.4 的总分诊：症状 21 条、1.1.4 崩溃/冻屏/JS 指标、症状→修复对照、SIGSYS 425 取证修正、真机验收清单 |
| [`200-Python桥异步化（LOOP-GAP根因二）.md`](200-Python桥异步化（LOOP-GAP根因二）.md) | LOOP-GAP 根因二：`pip install` 在主线程跑 CPython；执行搬到 worker 线程（单飞队列 / 超时 terminate / 降级开关 `DSHM_PY_INLINE=1`）、协议与门禁、真机验收读法；顺带修 `git=SKIPPED` 三态 |
| [`203-libnode关io_uring（SIGSYS-425崩溃循环根治）.md`](203-libnode关io_uring（SIGSYS-425崩溃循环根治）.md) | 425 崩溃循环的处置：随包 `libnode.so.137` 的 libuv io_uring **已在系统调用层关闭**（17 个槽 = `mov w0,#-1`）；任务书的 8 字节函数补丁**无落点且有害**故未执行（0 字节改动）；交付 `tools/patch-libnode-io-uring.mjs` + `tools/check-libnode-io-uring.mjs`（17 槽 oracle / 全文件广扫 / 往返逐字节证明 / 对照臂）；包内 61 个 arm64 原生库 0 处活体 ⇒ 425 不来自本仓构建，附三条决定性取证与崩溃循环护栏建议 |
| [`204-DSHM-1.1.4内测更新说明（AGC测试版之后）.md`](204-DSHM-1.1.4内测更新说明（AGC测试版之后）.md) | 给测试组的更新说明（AGC 1.1.4 邀测包之后 → 2026-10-19 侧载包）：系统语音听写、2in1 电脑模式侧栏与缩放、右侧栏重叠与返回手势、卡顿/长任务、首启侧栏、冒烟清单与反馈要求 |
| [`205-MatePad-Edge内存风暴定位与三层收口（PSI-预热-单渲染进程）.md`](205-MatePad-Edge内存风暴定位与三层收口（PSI-预热-单渲染进程）.md) | MatePad Edge 启动 78s 触发 PSI 的定位与收口：Web 单渲染进程、`onMemoryLevel` 释放 ArkWeb 缓存、Host 内存看门狗 + 危急标记安全模式、VM 预热默认关；含下一次真机验证命令与仍未定的图形侧下一步 |
| [`206-内测组复测提示词（MatePad-Edge内存专项）.md`](206-内测组复测提示词（MatePad-Edge内存专项）.md) | 给内测组直接复制的复测提示词：MatePad Edge 3 分钟内存专项 + 10 项冒烟 + 证据采集命令 + 反馈模板 + 已知阻塞项（不夹带内部细节） |
| [`207-MatePad-Edge系列永久desktop与1.1.4回归出包（核心+dshm.77）.md`](207-MatePad-Edge系列永久desktop与1.1.4回归出包（核心+dshm.77）.md) | QXS-* / MatePad Edge 系列永久识别为 desktop；终端只走系统原生路线，Agent bash 保留 guest；含 73 条门禁、签名、权限与 `.77` 侧载包读数 |
| [`208-VM内存分档调度（12G低占用·16G+三端性能档）与真机对照（+dshm.78）.md`](208-VM内存分档调度（12G低占用·16G+三端性能档）与真机对照（+dshm.78）.md) | VM 按 MemTotal 分 economy/performance；12G 保持低占用，16G+ 三端提升 guest/TCG 并默认预热；含 12G Mate80 与 24G MateBook14 真机对照 |
| [`209-MatePad-Edge后台保活根因（DATA_TRANSFER十分钟取消转TASK_KEEPING）.md`](209-MatePad-Edge后台保活根因（DATA_TRANSFER十分钟取消转TASK_KEEPING）.md) | 用 `.78` 完整日志推翻“后台仍 120Hz”的误判；定位 `DATA_TRANSFER` 约 600 秒被系统取消后进程冻结，PC/2in1 改 `TASK_KEEPING`，修 beta 托盘包名，并新增 `diag-keepalive` |
| [`210-平板横屏顶栏与Kirin8020默认工作区兜底（+dshm.78侧载包）.md`](210-平板横屏顶栏与Kirin8020默认工作区兜底（+dshm.78侧载包）.md) | 平板仅横屏显示顶栏、PC/2in1 恒显、手机恒不显；顶栏可见时取消 24vp 让位；Kirin 8020 手持档非取消选择器错误静默落 `Download/<bundle>`；含新侧载包读数 |
| [`211-迁移到DevEco-Studio与鸿蒙PC.md`](211-迁移到DevEco-Studio与鸿蒙PC.md) | 生成可移植 DevEco 工作区：保留源码、原生库、核心/VM/toolchain 资产与 `.git`，排除构建缓存、10GB `dist` 和本机签名材料；含目标机首次打开、自动签名与编译步骤 |
| [`HarmonyOS生态能力接入/2026-10-18-系统语音识别与会议模式施工方案.md`](HarmonyOS生态能力接入/2026-10-18-系统语音识别与会议模式施工方案.md) | 系统语音识别 + 会议模式施工方案（Task 1–10） |

交付和证据：

- `dist/sideload/README.md`
- `dist/sideload/DSHM-beta-1.1.4-更新日志.md`
- `dist/sideload/SHA256SUMS.txt`
- `dist/acceptance/20261018-bottom-safe-area/`
- `dist/acceptance/20261018-terminal-input/`
- `dist/acceptance/20261018-ssh-poc/`

## 6. 历史文档状态

### `95` 到 `171`

主要用于问题台账、调研、根因、发布记录和事故复盘。读这些文档时先检查顶部
是否有“历史/作废/已取代”提示。特别是：

- `108` 的权限数和 API 24 口径已被 `183`、`154`、`161` 取代；
- `110` 的 API 24 下限已被 `183` 取代；
- `119` 是 HiSH PoC 调研，产品化结果见 `120`、`155`、`188`；
- `142`、`143`、`144` 的权限回补结论永久作废，只能作为事故记录；
- `147` 的 API 26 调研仍有效，但 `compatibleSdkVersion` 已由 `183` 改为 23；
- `171` 是 1.1.3 正式同步记录，不是当前 1.1.4 状态。

### `172` 到 `182`

这是 API 26、系统融合、浏览器、卡片、APMS 和升级恢复的连续记录。
功能实现仍有参考价值，当前状态以 `HANDOFF.md` 和 `183` 到 `189` 为准。

### 非编号历史快照

- `review-report-2026-09-29.md`
- `review-report-2026-10-04.md`
- `functional-test-report.md`
- `rc2-workspace-diagnosis.md`
- `ia-parity-plan.md`

这些文件保留用于审计，不应当作当前质量结论。当前质量由最新门禁和
`dist/acceptance/` 证明。

## 7. 文档维护规则

1. 当前状态改 `HANDOFF.md`，不要在历史文档里静默改结论。
2. 新问题按编号追加文档；旧结论被推翻时在原文顶部加替代说明。
3. 契约、事故和真机证据不物理删除，避免破坏审计链和行号引用。
4. 新增或移动文档后跑 `node tools/check-doc-refs.mjs`。
5. 权限相关文档只写当前 **entry 18 条 / phone 9 条**口径（判据 `tools/check-permission-surface.mjs`），不回补已撤条目；历史文档里的「恒 8 条」均为当时读数。
6. API、版本、包名和核心号必须从配置或产物复核后再写。
7. 临时日志、截图和探针只落 `dist/`，交付证据放 `dist/acceptance/`。
8. Harmony应用编译使用 `devecocli build`；Beta使用 `tools/build-beta.mjs --combined-app`，内部委托CLI，身份与签名配置临时切换后逐字恢复。

## 8. 常用入口

```powershell
# 权限面和 APK 面
node tools/check-permission-surface.mjs
node tools/check-no-apk-surface.mjs

# 文档与接线
node tools/check-doc-refs.mjs
node tools/check-feature-wiring.mjs

# 资源快照和核心补丁
node tools/assert-resfile-sync.mjs
node tools/check-core-openharmony-patches.mjs

# 双端一致性：本机不适用（DSHM-mobile 第二工作区已于 2026-11-03 删除）。
# check-two-project-parity.mjs 保留作历史，本机必然 rc=2，不再作为判据。

# 构建与覆盖安装（仅 Windows 开发端；本机无 hdc 服务端，交付证据上限 = 离线门禁 + 包结构）
.\tools\update-device.ps1
```

完整门禁清单见 [`../AGENTS.md`](../AGENTS.md)。

---

## 9. 编号文档全量索引

> 守门：`node tools/check-doc-index.mjs` —— `docs/` 下每个编号文件都必须在本导航里至少出现一次
> （判据是**文件名**，不做内容判等）。本节是全量清单，一行一篇；正文在各文件自身。
> 新增编号文档时**必须同时补一行**，否则门禁判红。

| 编号 | 文档 |
|---|---|
| 00 | [`00-开发任务书.md`](00-%E5%BC%80%E5%8F%91%E4%BB%BB%E5%8A%A1%E4%B9%A6.md) |
| 10 | [`10-协议兼容事实基线.md`](10-%E5%8D%8F%E8%AE%AE%E5%85%BC%E5%AE%B9%E4%BA%8B%E5%AE%9E%E5%9F%BA%E7%BA%BF.md) |
| 11 | [`11-请求载荷契约.md`](11-%E8%AF%B7%E6%B1%82%E8%BD%BD%E8%8D%B7%E5%A5%91%E7%BA%A6.md) |
| 12 | [`12-设置页契约.md`](12-%E8%AE%BE%E7%BD%AE%E9%A1%B5%E5%A5%91%E7%BA%A6.md) |
| 20 | [`20-产品需求与体验规范.md`](20-%E4%BA%A7%E5%93%81%E9%9C%80%E6%B1%82%E4%B8%8E%E4%BD%93%E9%AA%8C%E8%A7%84%E8%8C%83.md) |
| 30 | [`30-技术验证清单.md`](30-%E6%8A%80%E6%9C%AF%E9%AA%8C%E8%AF%81%E6%B8%85%E5%8D%95.md) |
| 40 | [`40-上游升级手册.md`](40-%E4%B8%8A%E6%B8%B8%E5%8D%87%E7%BA%A7%E6%89%8B%E5%86%8C.md) |
| 41 | [`345-Super-agent环境复测二（tmux-ps-dsh三项已修与pnpm仍缺）.md`](345-Super-agent环境复测二（tmux-ps-dsh三项已修与pnpm仍缺）.md) | |
| 42 | [`346-Super-agent环境复测三（前置全绿与启动无通道）.md`](346-Super-agent环境复测三（前置全绿与启动无通道）.md) | |
| 43 | [`347-Super-agent环境复测四（无功能变化与解包软链问题）.md`](347-Super-agent环境复测四（无功能变化与解包软链问题）.md) | |
| 44 | [`348-超管独立进程实测（判定FAIL·核心树缺superagent种子与卡住空窗口）.md`](348-超管独立进程实测（判定FAIL·核心树缺superagent种子与卡住空窗口）.md) | |
| 45 | [`349-双进程双端口实测（能力达成·dsh写死版本与host-ready被抢）.md`](349-双进程双端口实测（能力达成·dsh写死版本与host-ready被抢）.md) | |
| 46 | [`350-v17验证与日志抓取（附路径bug与启动期崩溃）.md`](350-v17验证与日志抓取（附路径bug与启动期崩溃）.md) | |
| 47 | [`351-dsh-plugin-add-link失败（拒绝者是宿主安装器与dsh再次写死版本）.md`](351-dsh-plugin-add-link失败（拒绝者是宿主安装器与dsh再次写死版本）.md) | |
| 48 | [`352-本地HDC调用检查（二进制可跑但UDS绑定被拒）.md`](352-本地HDC调用检查（二进制可跑但UDS绑定被拒）.md) | |
| 353 | [`353-项目现状基线（单工作区·交付物·已落地与未落地）.md`](353-项目现状基线（单工作区·交付物·已落地与未落地）.md) | 2026-11-06 复核：项目结构与硬约束索引；版本/核心/设备面以代码配置为准 |
| 355 | [`355-鸿蒙特性接入清单（1.1.7·core109基线）.md`](355-鸿蒙特性接入清单（1.1.7·core109基线）.md) | 取代 docs/190：只登记代码里真的接了的鸿蒙能力，附落点与复核方式 |
| 356 | [`356-受限权限申请材料（JIT·ALLOW_WRITABLE_CODE_MEMORY）.md`](356-受限权限申请材料（JIT·ALLOW_WRITABLE_CODE_MEMORY）.md) | AGC 受限权限申请材料：主宿主 `--jitless` 与子进程 Node CLI 的口径边界（2026-11-04 校正） |
| 357 | [`357-录屏脚本（JIT权限申请视频）.md`](357-录屏脚本（JIT权限申请视频）.md) | 受限权限申请视频的 6 镜分镜、旁白与提交检查清单 |
| 358 | [`358-exec域随包库加载根因与本轮修复.md`](358-exec%E5%9F%9F%E9%9A%8F%E5%8C%85%E5%BA%93%E5%8A%A0%E8%BD%BD%E6%A0%B9%E5%9B%A0%E4%B8%8E%E6%9C%AC%E8%BD%AE%E4%BF%AE%E5%A4%8D.md) | 真机 A/B：随包 libnode 未签名 ⇒ exec 域 dlopen 被拒（Permission denied），签名后 OK；修法=构建期签名 + strip 排除 + 去 el1 RUNPATH + 全档 ELF 启动器 + 解包互斥回归 |
| 359 | [`359-Web液态玻璃化可行性评估（HarmonyOSLiquidGlass调研）.md`](359-Web%E6%B6%B2%E6%80%81%E7%8E%BB%E7%92%83%E5%8C%96%E5%8F%AF%E8%A1%8C%E6%80%A7%E8%AF%84%E4%BC%B0%EF%BC%88HarmonyOSLiquidGlass%E8%B0%83%E7%A0%94%EF%BC%89.md) | 调研原生 GLES 玻璃库：整屏 XComponent、无 Web 纹理通道 ⇒ 不能直接用于 Web；给出 CSS 结构性玻璃方案、成本/性能红线与三期计划 |
| 360 | [`360-r16与PC-v10对照后的收口与三条纠偏.md`](360-r16%E4%B8%8EPC-v10%E5%AF%B9%E7%85%A7%E5%90%8E%E7%9A%84%E6%94%B6%E5%8F%A3%E4%B8%8E%E4%B8%89%E6%9D%A1%E7%BA%A0%E5%81%8F.md) | r16/PC 对照：验收命令纠偏（绝对路径自检工具）· RUNPATH 误读澄清 · `$ORIGIN` 不支持实测 · 后台 VM 放行 · symlink 收口 · 提示音取证 |
| 361 | [`361-核心同步评估-0.2.2被Node引擎卡住.md`](361-%E6%A0%B8%E5%BF%83%E5%90%8C%E6%AD%A5%E8%AF%84%E4%BC%B0-0.2.2%E8%A2%ABNode%E5%BC%95%E6%93%8E%E5%8D%A1%E4%BD%8F.md) | 上游 latest=rc.5（已同步）；next=0.2.2-rc.1 要求 node>=24.9，宿主 libnode 24.2.0 ⇒ 运行时卡住；给出三选项与迁移清单 |
| 362 | [`362-环境组件补齐与升级规划.md`](362-%E7%8E%AF%E5%A2%83%E7%BB%84%E4%BB%B6%E8%A1%A5%E9%BD%90%E4%B8%8E%E5%8D%87%E7%BA%A7%E8%A7%84%E5%88%92.md) | 组件盘点：签名工具（已切原生）· libnode 24.2 阻塞 0.2.2 · guest 缺 libcurl/pnpm/dsh · vCPU/内存 · 分期与验收口径 |
| 363 | [`363-自建libnode24.9-卡在OHOS-clang15.md`](363-%E8%87%AA%E5%BB%BAlibnode24.9-%E5%8D%A1%E5%9C%A80HOS-clang15.md) | 自建 24.9 实测：源码/补丁/make/C++/configure 全通；V8 需要 clang16+ 的 C++20 隐式 typename，本机原生仅 15.0.4；公开 SDK 为 x86_64 宿主包不可用；给两条出路与产物回收流程 |
| 364 | [`364-ALLOW_WRITABLE_CODE_MEMORY申请理由更新版.md`](364-ALLOW_WRITABLE_CODE_MEMORY%E7%94%B3%E8%AF%B7%E7%90%86%E7%94%B1%E6%9B%B4%E6%96%B0%E7%89%88.md) | 受限权限申请理由 2026-11-05 更新：Node24/V8、171 vs 1232 ms（7.2×）、设备范围仅平板/2in1、安全承诺与边界口径 |
| 50 | [`50-端侧核心运行架构.md`](50-%E7%AB%AF%E4%BE%A7%E6%A0%B8%E5%BF%83%E8%BF%90%E8%A1%8C%E6%9E%B6%E6%9E%84.md) |
| 60 | [`60-界面重塑-端侧核心.md`](60-%E7%95%8C%E9%9D%A2%E9%87%8D%E5%A1%91-%E7%AB%AF%E4%BE%A7%E6%A0%B8%E5%BF%83.md) |
| 70 | [`70-鸿蒙移植踩坑与修复总览.md`](70-%E9%B8%BF%E8%92%99%E7%A7%BB%E6%A4%8D%E8%B8%A9%E5%9D%91%E4%B8%8E%E4%BF%AE%E5%A4%8D%E6%80%BB%E8%A7%88.md) |
| 80 | [`80-真机更新与数据保全.md`](80-%E7%9C%9F%E6%9C%BA%E6%9B%B4%E6%96%B0%E4%B8%8E%E6%95%B0%E6%8D%AE%E4%BF%9D%E5%85%A8.md) |
| 90 | [`90-DSH鸿蒙原生实现全流程.md`](90-DSH%E9%B8%BF%E8%92%99%E5%8E%9F%E7%94%9F%E5%AE%9E%E7%8E%B0%E5%85%A8%E6%B5%81%E7%A8%8B.md) |
| 95 | [`95-issue台账与开源后审计.md`](95-issue%E5%8F%B0%E8%B4%A6%E4%B8%8E%E5%BC%80%E6%BA%90%E5%90%8E%E5%AE%A1%E8%AE%A1.md) |
| 96 | [`96-侧边栏预览竞品调研与落地方案.md`](96-%E4%BE%A7%E8%BE%B9%E6%A0%8F%E9%A2%84%E8%A7%88%E7%AB%9E%E5%93%81%E8%B0%83%E7%A0%94%E4%B8%8E%E8%90%BD%E5%9C%B0%E6%96%B9%E6%A1%88.md) |
| 97 | [`97-readBytes空响应根因与修复.md`](97-readBytes%E7%A9%BA%E5%93%8D%E5%BA%94%E6%A0%B9%E5%9B%A0%E4%B8%8E%E4%BF%AE%E5%A4%8D.md) |
| 98 | [`98-收尾审核与修复（托盘回归·垫片字节·自检扩围）.md`](98-%E6%94%B6%E5%B0%BE%E5%AE%A1%E6%A0%B8%E4%B8%8E%E4%BF%AE%E5%A4%8D%EF%BC%88%E6%89%98%E7%9B%98%E5%9B%9E%E5%BD%92%C2%B7%E5%9E%AB%E7%89%87%E5%AD%97%E8%8A%82%C2%B7%E8%87%AA%E6%A3%80%E6%89%A9%E5%9B%B4%EF%BC%89.md) |
| 99 | [`99-右上角三键不可见：顶栏底色与三键配色的接线漏了一处.md`](99-%E5%8F%B3%E4%B8%8A%E8%A7%92%E4%B8%89%E9%94%AE%E4%B8%8D%E5%8F%AF%E8%A7%81%EF%BC%9A%E9%A1%B6%E6%A0%8F%E5%BA%95%E8%89%B2%E4%B8%8E%E4%B8%89%E9%94%AE%E9%85%8D%E8%89%B2%E7%9A%84%E6%8E%A5%E7%BA%BF%E6%BC%8F%E4%BA%86%E4%B8%80%E5%A4%84.md) |
| 100 | [`100-v1.1.0发布说明（2026-09-30 至 10-05）.md`](100-v1.1.0%E5%8F%91%E5%B8%83%E8%AF%B4%E6%98%8E%EF%BC%882026-09-30%20%E8%87%B3%2010-05%EF%BC%89.md) |
| 101 | [`101-托盘退出残留与插件市场重启横幅的根因与修复.md`](101-%E6%89%98%E7%9B%98%E9%80%80%E5%87%BA%E6%AE%8B%E7%95%99%E4%B8%8E%E6%8F%92%E4%BB%B6%E5%B8%82%E5%9C%BA%E9%87%8D%E5%90%AF%E6%A8%AA%E5%B9%85%E7%9A%84%E6%A0%B9%E5%9B%A0%E4%B8%8E%E4%BF%AE%E5%A4%8D.md) |
| 102 | [`102-手持形态朝向跟随屏幕旋转.md`](102-%E6%89%8B%E6%8C%81%E5%BD%A2%E6%80%81%E6%9C%9D%E5%90%91%E8%B7%9F%E9%9A%8F%E5%B1%8F%E5%B9%95%E6%97%8B%E8%BD%AC.md) |
| 103 | [`103-手持档工作区路径采纳判据.md`](103-%E6%89%8B%E6%8C%81%E6%A1%A3%E5%B7%A5%E4%BD%9C%E5%8C%BA%E8%B7%AF%E5%BE%84%E9%87%87%E7%BA%B3%E5%88%A4%E6%8D%AE.md) |
| 104 | [`104-手机档终端与bash能力判据.md`](104-%E6%89%8B%E6%9C%BA%E6%A1%A3%E7%BB%88%E7%AB%AF%E4%B8%8Ebash%E8%83%BD%E5%8A%9B%E5%88%A4%E6%8D%AE.md) |
| 105 | [`105-手持档工作区目录授权的持久化与跨启动恢复.md`](105-%E6%89%8B%E6%8C%81%E6%A1%A3%E5%B7%A5%E4%BD%9C%E5%8C%BA%E7%9B%AE%E5%BD%95%E6%8E%88%E6%9D%83%E7%9A%84%E6%8C%81%E4%B9%85%E5%8C%96%E4%B8%8E%E8%B7%A8%E5%90%AF%E5%8A%A8%E6%81%A2%E5%A4%8D.md) |
| 106 | [`106-两份端侧自检报告的分诊与探针读数机器可读化.md`](106-%E4%B8%A4%E4%BB%BD%E7%AB%AF%E4%BE%A7%E8%87%AA%E6%A3%80%E6%8A%A5%E5%91%8A%E7%9A%84%E5%88%86%E8%AF%8A%E4%B8%8E%E6%8E%A2%E9%92%88%E8%AF%BB%E6%95%B0%E6%9C%BA%E5%99%A8%E5%8F%AF%E8%AF%BB%E5%8C%96.md) |
| 107 | [`107-手机档插件市场的进程内包管理通道（desktopProfiles-desktopPnpm宿主桥）.md`](107-%E6%89%8B%E6%9C%BA%E6%A1%A3%E6%8F%92%E4%BB%B6%E5%B8%82%E5%9C%BA%E7%9A%84%E8%BF%9B%E7%A8%8B%E5%86%85%E5%8C%85%E7%AE%A1%E7%90%86%E9%80%9A%E9%81%93%EF%BC%88desktopProfiles-desktopPnpm%E5%AE%BF%E4%B8%BB%E6%A1%A5%EF%BC%89.md) |
| 108 | [`108-PC沙箱自检落实与API23向下兼容实证（glob静默失败·errno可读化·fill遮蔽·调试profile设备绑定）.md`](108-PC%E6%B2%99%E7%AE%B1%E8%87%AA%E6%A3%80%E8%90%BD%E5%AE%9E%E4%B8%8EAPI23%E5%90%91%E4%B8%8B%E5%85%BC%E5%AE%B9%E5%AE%9E%E8%AF%81%EF%BC%88glob%E9%9D%99%E9%BB%98%E5%A4%B1%E8%B4%A5%C2%B7errno%E5%8F%AF%E8%AF%BB%E5%8C%96%C2%B7fill%E9%81%AE%E8%94%BD%C2%B7%E8%B0%83%E8%AF%95profile%E8%AE%BE%E5%A4%87%E7%BB%91%E5%AE%9A%EF%BC%89.md) |
| 109 | [`109-沙箱复测两个P1缺口的落实（move-publish裸EPERM·read-remove-edit权限判据）.md`](109-%E6%B2%99%E7%AE%B1%E5%A4%8D%E6%B5%8B%E4%B8%A4%E4%B8%AAP1%E7%BC%BA%E5%8F%A3%E7%9A%84%E8%90%BD%E5%AE%9E%EF%BC%88move-publish%E8%A3%B8EPERM%C2%B7read-remove-edit%E6%9D%83%E9%99%90%E5%88%A4%E6%8D%AE%EF%BC%89.md) |
| 110 | [`110-手持档插件安装卸载的进程内包通道与API24兼容面拍板.md`](110-%E6%89%8B%E6%8C%81%E6%A1%A3%E6%8F%92%E4%BB%B6%E5%AE%89%E8%A3%85%E5%8D%B8%E8%BD%BD%E7%9A%84%E8%BF%9B%E7%A8%8B%E5%86%85%E5%8C%85%E9%80%9A%E9%81%93%E4%B8%8EAPI24%E5%85%BC%E5%AE%B9%E9%9D%A2%E6%8B%8D%E6%9D%BF.md) |
| 111 | [`111-对话框文件上传失败的根因（宿主fetch垫片丢弃流式请求体）与cause可诊断化.md`](111-%E5%AF%B9%E8%AF%9D%E6%A1%86%E6%96%87%E4%BB%B6%E4%B8%8A%E4%BC%A0%E5%A4%B1%E8%B4%A5%E7%9A%84%E6%A0%B9%E5%9B%A0%EF%BC%88%E5%AE%BF%E4%B8%BBfetch%E5%9E%AB%E7%89%87%E4%B8%A2%E5%BC%83%E6%B5%81%E5%BC%8F%E8%AF%B7%E6%B1%82%E4%BD%93%EF%BC%89%E4%B8%8Ecause%E5%8F%AF%E8%AF%8A%E6%96%AD%E5%8C%96.md) |
| 112 | [`112-三端代码审核与正式侧载包.md`](112-%E4%B8%89%E7%AB%AF%E4%BB%A3%E7%A0%81%E5%AE%A1%E6%A0%B8%E4%B8%8E%E6%AD%A3%E5%BC%8F%E4%BE%A7%E8%BD%BD%E5%8C%85.md) |
| 113 | [`113-工作区列表里那条用户没建过的记录（默认工作区登记收窄）.md`](113-%E5%B7%A5%E4%BD%9C%E5%8C%BA%E5%88%97%E8%A1%A8%E9%87%8C%E9%82%A3%E6%9D%A1%E7%94%A8%E6%88%B7%E6%B2%A1%E5%BB%BA%E8%BF%87%E7%9A%84%E8%AE%B0%E5%BD%95%EF%BC%88%E9%BB%98%E8%AE%A4%E5%B7%A5%E4%BD%9C%E5%8C%BA%E7%99%BB%E8%AE%B0%E6%94%B6%E7%AA%84%EF%BC%89.md) |
| 114 | [`114-WorkBuddy手机端的执行外移与DSHM的对照.md`](114-WorkBuddy%E6%89%8B%E6%9C%BA%E7%AB%AF%E7%9A%84%E6%89%A7%E8%A1%8C%E5%A4%96%E7%A7%BB%E4%B8%8EDSHM%E7%9A%84%E5%AF%B9%E7%85%A7.md) |
| 115 | [`115-手持档工具链解包的进程内回退（纯JS解tar.gz，不创建进程）.md`](115-%E6%89%8B%E6%8C%81%E6%A1%A3%E5%B7%A5%E5%85%B7%E9%93%BE%E8%A7%A3%E5%8C%85%E7%9A%84%E8%BF%9B%E7%A8%8B%E5%86%85%E5%9B%9E%E9%80%80%EF%BC%88%E7%BA%AFJS%E8%A7%A3tar.gz%EF%BC%8C%E4%B8%8D%E5%88%9B%E5%BB%BA%E8%BF%9B%E7%A8%8B%EF%BC%89.md) |
| 116 | [`116-分档代码审核与全项目体检·重建侧载包r3.md`](116-%E5%88%86%E6%A1%A3%E4%BB%A3%E7%A0%81%E5%AE%A1%E6%A0%B8%E4%B8%8E%E5%85%A8%E9%A1%B9%E7%9B%AE%E4%BD%93%E6%A3%80%C2%B7%E9%87%8D%E5%BB%BA%E4%BE%A7%E8%BD%BD%E5%8C%85r3.md) |
| 117 | [`117-远程执行主机·飞牛NAS-Docker施工单.md`](117-%E8%BF%9C%E7%A8%8B%E6%89%A7%E8%A1%8C%E4%B8%BB%E6%9C%BA%C2%B7%E9%A3%9E%E7%89%9BNAS-Docker%E6%96%BD%E5%B7%A5%E5%8D%95.md) |
| 118 | [`118-入口侧-cloudflared连不上CF-edge与隧道指向的分叉.md`](118-%E5%85%A5%E5%8F%A3%E4%BE%A7-cloudflared%E8%BF%9E%E4%B8%8D%E4%B8%8ACF-edge%E4%B8%8E%E9%9A%A7%E9%81%93%E6%8C%87%E5%90%91%E7%9A%84%E5%88%86%E5%8F%89.md) |
| 119 | [`119-HiSH虚拟机能否给手持档接上真bash的调研.md`](119-HiSH%E8%99%9A%E6%8B%9F%E6%9C%BA%E8%83%BD%E5%90%A6%E7%BB%99%E6%89%8B%E6%8C%81%E6%A1%A3%E6%8E%A5%E4%B8%8A%E7%9C%9Fbash%E7%9A%84%E8%B0%83%E7%A0%94.md) |
| 120 | [`120-手持档guest虚拟机bash通道产品化（把ctx.subprocess在无可用spawn档改派到QEMU）.md`](120-%E6%89%8B%E6%8C%81%E6%A1%A3guest%E8%99%9A%E6%8B%9F%E6%9C%BAbash%E9%80%9A%E9%81%93%E4%BA%A7%E5%93%81%E5%8C%96%EF%BC%88%E6%8A%8Actx.subprocess%E5%9C%A8%E6%97%A0%E5%8F%AF%E7%94%A8spawn%E6%A1%A3%E6%94%B9%E6%B4%BE%E5%88%B0QEMU%EF%BC%89.md) |
| 121 | [`121-手持档guest虚拟机真机首跑的两个P0与一个P1（worker execArgv·koffi断言·串口取证）.md`](121-%E6%89%8B%E6%8C%81%E6%A1%A3guest%E8%99%9A%E6%8B%9F%E6%9C%BA%E7%9C%9F%E6%9C%BA%E9%A6%96%E8%B7%91%E7%9A%84%E4%B8%A4%E4%B8%AAP0%E4%B8%8E%E4%B8%80%E4%B8%AAP1%EF%BC%88worker%20execArgv%C2%B7koffi%E6%96%AD%E8%A8%80%C2%B7%E4%B8%B2%E5%8F%A3%E5%8F%96%E8%AF%81%EF%BC%89.md) |
| 122 | [`122-手持档guest虚拟机bash通道收口（QGA客户端根因与guest侧三处阻断）.md`](122-%E6%89%8B%E6%8C%81%E6%A1%A3guest%E8%99%9A%E6%8B%9F%E6%9C%BAbash%E9%80%9A%E9%81%93%E6%94%B6%E5%8F%A3%EF%BC%88QGA%E5%AE%A2%E6%88%B7%E7%AB%AF%E6%A0%B9%E5%9B%A0%E4%B8%8Eguest%E4%BE%A7%E4%B8%89%E5%A4%84%E9%98%BB%E6%96%AD%EF%BC%89.md) |
| 123 | [`123-侧边栏终端接入guest虚拟机（-serial通道与认领语义、PL011只有两个的实证）.md`](123-%E4%BE%A7%E8%BE%B9%E6%A0%8F%E7%BB%88%E7%AB%AF%E6%8E%A5%E5%85%A5guest%E8%99%9A%E6%8B%9F%E6%9C%BA%EF%BC%88-serial%E9%80%9A%E9%81%93%E4%B8%8E%E8%AE%A4%E9%A2%86%E8%AF%AD%E4%B9%89%E3%80%81PL011%E5%8F%AA%E6%9C%89%E4%B8%A4%E4%B8%AA%E7%9A%84%E5%AE%9E%E8%AF%81%EF%BC%89.md) |
| 124 | [`124-工作区与垃圾清理·全系统体检（security_model=none撤回与9p旁挂件清扫）.md`](124-%E5%B7%A5%E4%BD%9C%E5%8C%BA%E4%B8%8E%E5%9E%83%E5%9C%BE%E6%B8%85%E7%90%86%C2%B7%E5%85%A8%E7%B3%BB%E7%BB%9F%E4%BD%93%E6%A3%80%EF%BC%88security_model%3Dnone%E6%92%A4%E5%9B%9E%E4%B8%8E9p%E6%97%81%E6%8C%82%E4%BB%B6%E6%B8%85%E6%89%AB%EF%BC%89.md) |
| 125 | [`125-手持档终端多实例与皮肤市场托管安装（virtconsole换通道·两行路径根治·installPlugin的recovery形状）.md`](125-%E6%89%8B%E6%8C%81%E6%A1%A3%E7%BB%88%E7%AB%AF%E5%A4%9A%E5%AE%9E%E4%BE%8B%E4%B8%8E%E7%9A%AE%E8%82%A4%E5%B8%82%E5%9C%BA%E6%89%98%E7%AE%A1%E5%AE%89%E8%A3%85%EF%BC%88virtconsole%E6%8D%A2%E9%80%9A%E9%81%93%C2%B7%E4%B8%A4%E8%A1%8C%E8%B7%AF%E5%BE%84%E6%A0%B9%E6%B2%BB%C2%B7installPlugin%E7%9A%84recovery%E5%BD%A2%E7%8A%B6%EF%BC%89.md) |
| 126 | [`126-WorkBuddy鸿蒙PC端工具与环境自检的对照与可借鉴项.md`](126-WorkBuddy%E9%B8%BF%E8%92%99PC%E7%AB%AF%E5%B7%A5%E5%85%B7%E4%B8%8E%E7%8E%AF%E5%A2%83%E8%87%AA%E6%A3%80%E7%9A%84%E5%AF%B9%E7%85%A7%E4%B8%8E%E5%8F%AF%E5%80%9F%E9%89%B4%E9%A1%B9.md) |
| 127 | [`127-工具链两处缺陷修复与hvigor假ENOENT（指纹脚本token取源·装机脚本第6步·沙箱写不了hvigor缓存）.md`](127-%E5%B7%A5%E5%85%B7%E9%93%BE%E4%B8%A4%E5%A4%84%E7%BC%BA%E9%99%B7%E4%BF%AE%E5%A4%8D%E4%B8%8Ehvigor%E5%81%87ENOENT%EF%BC%88%E6%8C%87%E7%BA%B9%E8%84%9A%E6%9C%ACtoken%E5%8F%96%E6%BA%90%C2%B7%E8%A3%85%E6%9C%BA%E8%84%9A%E6%9C%AC%E7%AC%AC6%E6%AD%A5%C2%B7%E6%B2%99%E7%AE%B1%E5%86%99%E4%B8%8D%E4%BA%86hvigor%E7%BC%93%E5%AD%98%EF%BC%89.md) |
| 128 | [`128-手持档整机冷启动的真根因（restartApp的前置开关没开）与皮肤使用链的端到端修复.md`](128-%E6%89%8B%E6%8C%81%E6%A1%A3%E6%95%B4%E6%9C%BA%E5%86%B7%E5%90%AF%E5%8A%A8%E7%9A%84%E7%9C%9F%E6%A0%B9%E5%9B%A0%EF%BC%88restartApp%E7%9A%84%E5%89%8D%E7%BD%AE%E5%BC%80%E5%85%B3%E6%B2%A1%E5%BC%80%EF%BC%89%E4%B8%8E%E7%9A%AE%E8%82%A4%E4%BD%BF%E7%94%A8%E9%93%BE%E7%9A%84%E7%AB%AF%E5%88%B0%E7%AB%AF%E4%BF%AE%E5%A4%8D.md) |
| 129 | [`129-手持档皮肤市场一键安装（端侧挂载契约由desktop改走市场的CLI分支·预取的--dir落位）.md`](129-%E6%89%8B%E6%8C%81%E6%A1%A3%E7%9A%AE%E8%82%A4%E5%B8%82%E5%9C%BA%E4%B8%80%E9%94%AE%E5%AE%89%E8%A3%85%EF%BC%88%E7%AB%AF%E4%BE%A7%E6%8C%82%E8%BD%BD%E5%A5%91%E7%BA%A6%E7%94%B1desktop%E6%94%B9%E8%B5%B0%E5%B8%82%E5%9C%BA%E7%9A%84CLI%E5%88%86%E6%94%AF%C2%B7%E9%A2%84%E5%8F%96%E7%9A%84--dir%E8%90%BD%E4%BD%8D%EF%BC%89.md) |
| 130 | [`130-手持档底部小白条沉浸（Web扩进系统安全区·页面侧垫底是错的）.md`](130-%E6%89%8B%E6%8C%81%E6%A1%A3%E5%BA%95%E9%83%A8%E5%B0%8F%E7%99%BD%E6%9D%A1%E6%B2%89%E6%B5%B8%EF%BC%88Web%E6%89%A9%E8%BF%9B%E7%B3%BB%E7%BB%9F%E5%AE%89%E5%85%A8%E5%8C%BA%C2%B7%E9%A1%B5%E9%9D%A2%E4%BE%A7%E5%9E%AB%E5%BA%95%E6%98%AF%E9%94%99%E7%9A%84%EF%BC%89.md) |
| 131 | [`131-上游核心升级到0.2.1-alpha.2（+dshm.29）.md`](131-%E4%B8%8A%E6%B8%B8%E6%A0%B8%E5%BF%83%E5%8D%87%E7%BA%A7%E5%88%B00.2.1-alpha.2%EF%BC%88%2Bdshm.29%EF%BC%89.md) |
| 132 | [`132-手持档设置面板手机化与「返回手势」分层消费（官方前端从不碰history·市场自带CSS两处反制）.md`](132-%E6%89%8B%E6%8C%81%E6%A1%A3%E8%AE%BE%E7%BD%AE%E9%9D%A2%E6%9D%BF%E6%89%8B%E6%9C%BA%E5%8C%96%E4%B8%8E%E3%80%8C%E8%BF%94%E5%9B%9E%E6%89%8B%E5%8A%BF%E3%80%8D%E5%88%86%E5%B1%82%E6%B6%88%E8%B4%B9%EF%BC%88%E5%AE%98%E6%96%B9%E5%89%8D%E7%AB%AF%E4%BB%8E%E4%B8%8D%E7%A2%B0history%C2%B7%E5%B8%82%E5%9C%BA%E8%87%AA%E5%B8%A6CSS%E4%B8%A4%E5%A4%84%E5%8F%8D%E5%88%B6%EF%BC%89.md) |
| 133 | [`133-手持档顶部两处让位（三键区下移Web内容·浮动⊞与设置面板标题重叠）.md`](133-%E6%89%8B%E6%8C%81%E6%A1%A3%E9%A1%B6%E9%83%A8%E4%B8%A4%E5%A4%84%E8%AE%A9%E4%BD%8D%EF%BC%88%E4%B8%89%E9%94%AE%E5%8C%BA%E4%B8%8B%E7%A7%BBWeb%E5%86%85%E5%AE%B9%C2%B7%E6%B5%AE%E5%8A%A8%E2%8A%9E%E4%B8%8E%E8%AE%BE%E7%BD%AE%E9%9D%A2%E6%9D%BF%E6%A0%87%E9%A2%98%E9%87%8D%E5%8F%A0%EF%BC%89.md) |
| 134 | [`134-平板端三键区让位第一版未生效的真根因（逐项独立捕获·decorPresentOf·windowStatusChange跟随）.md`](134-%E5%B9%B3%E6%9D%BF%E7%AB%AF%E4%B8%89%E9%94%AE%E5%8C%BA%E8%AE%A9%E4%BD%8D%E7%AC%AC%E4%B8%80%E7%89%88%E6%9C%AA%E7%94%9F%E6%95%88%E7%9A%84%E7%9C%9F%E6%A0%B9%E5%9B%A0%EF%BC%88%E9%80%90%E9%A1%B9%E7%8B%AC%E7%AB%8B%E6%8D%95%E8%8E%B7%C2%B7decorPresentOf%C2%B7windowStatusChange%E8%B7%9F%E9%9A%8F%EF%BC%89.md) |
| 135 | [`135-undici垫片具名导出面补Request（openai7.x-x509通道）与键在值undefined判定.md`](135-undici%E5%9E%AB%E7%89%87%E5%85%B7%E5%90%8D%E5%AF%BC%E5%87%BA%E9%9D%A2%E8%A1%A5Request%EF%BC%88openai7.x-x509%E9%80%9A%E9%81%93%EF%BC%89%E4%B8%8E%E9%94%AE%E5%9C%A8%E5%80%BCundefined%E5%88%A4%E5%AE%9A.md) |
| 136 | [`136-PC顶栏左上角改侧栏按钮与点击卡顿及桌面档取消官方侧栏按钮.md`](136-PC%E9%A1%B6%E6%A0%8F%E5%B7%A6%E4%B8%8A%E8%A7%92%E6%94%B9%E4%BE%A7%E6%A0%8F%E6%8C%89%E9%92%AE%E4%B8%8E%E7%82%B9%E5%87%BB%E5%8D%A1%E9%A1%BF%E5%8F%8A%E6%A1%8C%E9%9D%A2%E6%A1%A3%E5%8F%96%E6%B6%88%E5%AE%98%E6%96%B9%E4%BE%A7%E6%A0%8F%E6%8C%89%E9%92%AE.md) |
| 137 | [`137-文件访问范围闸门（沙箱∪用户目录·读写都掐·三入口一份判据）.md`](137-%E6%96%87%E4%BB%B6%E8%AE%BF%E9%97%AE%E8%8C%83%E5%9B%B4%E9%97%B8%E9%97%A8%EF%BC%88%E6%B2%99%E7%AE%B1%E2%88%AA%E7%94%A8%E6%88%B7%E7%9B%AE%E5%BD%95%C2%B7%E8%AF%BB%E5%86%99%E9%83%BD%E6%8E%90%C2%B7%E4%B8%89%E5%85%A5%E5%8F%A3%E4%B8%80%E4%BB%BD%E5%88%A4%E6%8D%AE%EF%BC%89.md) |
| 138 | [`138-平板端「按钮反色」偶发故障：三键配色收进唯一权威与窗口状态变化时重放.md`](138-%E5%B9%B3%E6%9D%BF%E7%AB%AF%E3%80%8C%E6%8C%89%E9%92%AE%E5%8F%8D%E8%89%B2%E3%80%8D%E5%81%B6%E5%8F%91%E6%95%85%E9%9A%9C%EF%BC%9A%E4%B8%89%E9%94%AE%E9%85%8D%E8%89%B2%E6%94%B6%E8%BF%9B%E5%94%AF%E4%B8%80%E6%9D%83%E5%A8%81%E4%B8%8E%E7%AA%97%E5%8F%A3%E7%8A%B6%E6%80%81%E5%8F%98%E5%8C%96%E6%97%B6%E9%87%8D%E6%94%BE.md) |
| 139 | [`139-上游「向上找项目根」撞上路径闸门：每轮运行失败（面外探测当作没有标记）.md`](139-%E4%B8%8A%E6%B8%B8%E3%80%8C%E5%90%91%E4%B8%8A%E6%89%BE%E9%A1%B9%E7%9B%AE%E6%A0%B9%E3%80%8D%E6%92%9E%E4%B8%8A%E8%B7%AF%E5%BE%84%E9%97%B8%E9%97%A8%EF%BC%9A%E6%AF%8F%E8%BD%AE%E8%BF%90%E8%A1%8C%E5%A4%B1%E8%B4%A5%EF%BC%88%E9%9D%A2%E5%A4%96%E6%8E%A2%E6%B5%8B%E5%BD%93%E4%BD%9C%E6%B2%A1%E6%9C%89%E6%A0%87%E8%AE%B0%EF%BC%89.md) |
| 140 | [`140-release构建的应用域降级（脚本执行被平台拒）——bash=denied的真根因.md`](140-release%E6%9E%84%E5%BB%BA%E7%9A%84%E5%BA%94%E7%94%A8%E5%9F%9F%E9%99%8D%E7%BA%A7%EF%BC%88%E8%84%9A%E6%9C%AC%E6%89%A7%E8%A1%8C%E8%A2%AB%E5%B9%B3%E5%8F%B0%E6%8B%92%EF%BC%89%E2%80%94%E2%80%94bash%3Ddenied%E7%9A%84%E7%9C%9F%E6%A0%B9%E5%9B%A0.md) |
| 141 | [`141-发布签名链路（AGC发布证书与发布profile）与发布profile的ACL面.md`](141-%E5%8F%91%E5%B8%83%E7%AD%BE%E5%90%8D%E9%93%BE%E8%B7%AF%EF%BC%88AGC%E5%8F%91%E5%B8%83%E8%AF%81%E4%B9%A6%E4%B8%8E%E5%8F%91%E5%B8%83profile%EF%BC%89%E4%B8%8E%E5%8F%91%E5%B8%83profile%E7%9A%84ACL%E9%9D%A2.md) |
| 142 | [`142-发布包ACL声明与发布profile不匹配（设备侧PERMISSION_ACL_RULE拒装）与摘除工具.md`](142-%E5%8F%91%E5%B8%83%E5%8C%85ACL%E5%A3%B0%E6%98%8E%E4%B8%8E%E5%8F%91%E5%B8%83profile%E4%B8%8D%E5%8C%B9%E9%85%8D%EF%BC%88%E8%AE%BE%E5%A4%87%E4%BE%A7PERMISSION_ACL_RULE%E6%8B%92%E8%A3%85%EF%BC%89%E4%B8%8E%E6%91%98%E9%99%A4%E5%B7%A5%E5%85%B7.md) |
| 143 | [`143-撤除域权限导致PC档应用域降级（工具与终端与工作区文件全废）与Release SDK重出.md`](143-%E6%92%A4%E9%99%A4%E5%9F%9F%E6%9D%83%E9%99%90%E5%AF%BC%E8%87%B4PC%E6%A1%A3%E5%BA%94%E7%94%A8%E5%9F%9F%E9%99%8D%E7%BA%A7%EF%BC%88%E5%B7%A5%E5%85%B7%E4%B8%8E%E7%BB%88%E7%AB%AF%E4%B8%8E%E5%B7%A5%E4%BD%9C%E5%8C%BA%E6%96%87%E4%BB%B6%E5%85%A8%E5%BA%9F%EF%BC%89%E4%B8%8ERelease%20SDK%E9%87%8D%E5%87%BA.md) |
| 144 | [`144-撤除用户目录权限导致PC档工作区文件与终端全废（回滚142§7与发布链路自动摘除）.md`](144-%E6%92%A4%E9%99%A4%E7%94%A8%E6%88%B7%E7%9B%AE%E5%BD%95%E6%9D%83%E9%99%90%E5%AF%BC%E8%87%B4PC%E6%A1%A3%E5%B7%A5%E4%BD%9C%E5%8C%BA%E6%96%87%E4%BB%B6%E4%B8%8E%E7%BB%88%E7%AB%AF%E5%85%A8%E5%BA%9F%EF%BC%88%E5%9B%9E%E6%BB%9A142%C2%A77%E4%B8%8E%E5%8F%91%E5%B8%83%E9%93%BE%E8%B7%AF%E8%87%AA%E5%8A%A8%E6%91%98%E9%99%A4%EF%BC%89.md) |
| 145 | [`145-发布签名包设备侧拒装（9568322）与手持档release构建实机验收.md`](145-%E5%8F%91%E5%B8%83%E7%AD%BE%E5%90%8D%E5%8C%85%E8%AE%BE%E5%A4%87%E4%BE%A7%E6%8B%92%E8%A3%85%EF%BC%889568322%EF%BC%89%E4%B8%8E%E6%89%8B%E6%8C%81%E6%A1%A3release%E6%9E%84%E5%BB%BA%E5%AE%9E%E6%9C%BA%E9%AA%8C%E6%94%B6.md) |
| 146 | [`146-AGC上架自检三项不通过的根因与修法（target=24口径·CppCrash·性能两项）.md`](146-AGC%E4%B8%8A%E6%9E%B6%E8%87%AA%E6%A3%80%E4%B8%89%E9%A1%B9%E4%B8%8D%E9%80%9A%E8%BF%87%E7%9A%84%E6%A0%B9%E5%9B%A0%E4%B8%8E%E4%BF%AE%E6%B3%95%EF%BC%88target%3D24%E5%8F%A3%E5%BE%84%C2%B7CppCrash%C2%B7%E6%80%A7%E8%83%BD%E4%B8%A4%E9%A1%B9%EF%BC%89.md) |
| 147 | [`147-API26特性深度调研与target抬到26.0.0（compatible保持6.1.1(24)）.md`](147-API26%E7%89%B9%E6%80%A7%E6%B7%B1%E5%BA%A6%E8%B0%83%E7%A0%94%E4%B8%8Etarget%E6%8A%AC%E5%88%B026.0.0%EF%BC%88compatible%E4%BF%9D%E6%8C%816.1.1%2824%29%EF%BC%89.md) |
| 148 | [`148-侧载包与上架包一致（随包Alpine包改名tar.gz·guest虚拟机静默预热降内存·发布链路只保留已审批权限面）.md`](148-%E4%BE%A7%E8%BD%BD%E5%8C%85%E4%B8%8E%E4%B8%8A%E6%9E%B6%E5%8C%85%E4%B8%80%E8%87%B4%EF%BC%88%E9%9A%8F%E5%8C%85Alpine%E5%8C%85%E6%94%B9%E5%90%8Dtar.gz%C2%B7guest%E8%99%9A%E6%8B%9F%E6%9C%BA%E9%9D%99%E9%BB%98%E9%A2%84%E7%83%AD%E9%99%8D%E5%86%85%E5%AD%98%C2%B7%E5%8F%91%E5%B8%83%E9%93%BE%E8%B7%AF%E5%8F%AA%E4%BF%9D%E7%95%99%E5%B7%B2%E5%AE%A1%E6%89%B9%E6%9D%83%E9%99%90%E9%9D%A2%EF%BC%89.md) |
| 149 | [`149-插件持久终端里那条pwsh开关的根因与修复（整组覆盖摘掉冲突子项）.md`](149-%E6%8F%92%E4%BB%B6%E6%8C%81%E4%B9%85%E7%BB%88%E7%AB%AF%E9%87%8C%E9%82%A3%E6%9D%A1pwsh%E5%BC%80%E5%85%B3%E7%9A%84%E6%A0%B9%E5%9B%A0%E4%B8%8E%E4%BF%AE%E5%A4%8D%EF%BC%88%E6%95%B4%E7%BB%84%E8%A6%86%E7%9B%96%E6%91%98%E6%8E%89%E5%86%B2%E7%AA%81%E5%AD%90%E9%A1%B9%EF%BC%89.md) |
| 150 | [`150-移动端全新安装自动生成「下载」工作区（默认工作区登记插件彻底去掉create）.md`](150-%E7%A7%BB%E5%8A%A8%E7%AB%AF%E5%85%A8%E6%96%B0%E5%AE%89%E8%A3%85%E8%87%AA%E5%8A%A8%E7%94%9F%E6%88%90%E3%80%8C%E4%B8%8B%E8%BD%BD%E3%80%8D%E5%B7%A5%E4%BD%9C%E5%8C%BA%EF%BC%88%E9%BB%98%E8%AE%A4%E5%B7%A5%E4%BD%9C%E5%8C%BA%E7%99%BB%E8%AE%B0%E6%8F%92%E4%BB%B6%E5%BD%BB%E5%BA%95%E5%8E%BB%E6%8E%89create%EF%BC%89.md) |
| 151 | [`151-设置面板手机化收窄为直板机专属（折叠屏与平板回官方竖排）与check-doc-refs三位编号与续写距离闸门.md`](151-%E8%AE%BE%E7%BD%AE%E9%9D%A2%E6%9D%BF%E6%89%8B%E6%9C%BA%E5%8C%96%E6%94%B6%E7%AA%84%E4%B8%BA%E7%9B%B4%E6%9D%BF%E6%9C%BA%E4%B8%93%E5%B1%9E%EF%BC%88%E6%8A%98%E5%8F%A0%E5%B1%8F%E4%B8%8E%E5%B9%B3%E6%9D%BF%E5%9B%9E%E5%AE%98%E6%96%B9%E7%AB%96%E6%8E%92%EF%BC%89%E4%B8%8Echeck-doc-refs%E4%B8%89%E4%BD%8D%E7%BC%96%E5%8F%B7%E4%B8%8E%E7%BB%AD%E5%86%99%E8%B7%9D%E7%A6%BB%E9%97%B8%E9%97%A8.md) |
| 152 | [`152-PC档三键关闭改为收进后台（windowWillClose判别器·托盘常驻·左键唤回）.md`](152-PC%E6%A1%A3%E4%B8%89%E9%94%AE%E5%85%B3%E9%97%AD%E6%94%B9%E4%B8%BA%E6%94%B6%E8%BF%9B%E5%90%8E%E5%8F%B0%EF%BC%88windowWillClose%E5%88%A4%E5%88%AB%E5%99%A8%C2%B7%E6%89%98%E7%9B%98%E5%B8%B8%E9%A9%BB%C2%B7%E5%B7%A6%E9%94%AE%E5%94%A4%E5%9B%9E%EF%BC%89.md) |
| 153 | [`153-手持档guest虚拟机bash首装provision超时根因与修复.md`](153-%E6%89%8B%E6%8C%81%E6%A1%A3guest%E8%99%9A%E6%8B%9F%E6%9C%BAbash%E9%A6%96%E8%A3%85provision%E8%B6%85%E6%97%B6%E6%A0%B9%E5%9B%A0%E4%B8%8E%E4%BF%AE%E5%A4%8D.md) |
| 154 | [`154-8权限release下TCG执行页被拒与VM预检止损.md`](154-8%E6%9D%83%E9%99%90release%E4%B8%8BTCG%E6%89%A7%E8%A1%8C%E9%A1%B5%E8%A2%AB%E6%8B%92%E4%B8%8EVM%E9%A2%84%E6%A3%80%E6%AD%A2%E6%8D%9F.md) |
| 155 | [`155-三端终端统一走guest虚拟机与按需冷启动（撤除启动期静默预热）.md`](155-%E4%B8%89%E7%AB%AF%E7%BB%88%E7%AB%AF%E7%BB%9F%E4%B8%80%E8%B5%B0guest%E8%99%9A%E6%8B%9F%E6%9C%BA%E4%B8%8E%E6%8C%89%E9%9C%80%E5%86%B7%E5%90%AF%E5%8A%A8%EF%BC%88%E6%92%A4%E9%99%A4%E5%90%AF%E5%8A%A8%E6%9C%9F%E9%9D%99%E9%BB%98%E9%A2%84%E7%83%AD%EF%BC%89.md) |
| 156 | [`156-PC档冷启动闪退双根因（node-pty socket未赋值·client-hmr轮询风暴）.md`](156-PC%E6%A1%A3%E5%86%B7%E5%90%AF%E5%8A%A8%E9%97%AA%E9%80%80%E5%8F%8C%E6%A0%B9%E5%9B%A0%EF%BC%88node-pty%20socket%E6%9C%AA%E8%B5%8B%E5%80%BC%C2%B7client-hmr%E8%BD%AE%E8%AF%A2%E9%A3%8E%E6%9A%B4%EF%BC%89.md) |
| 157 | [`157-PC档工作区目录重启后读不到的根因与修复（picker授权只活一个进程·三端统一授权链）.md`](157-PC%E6%A1%A3%E5%B7%A5%E4%BD%9C%E5%8C%BA%E7%9B%AE%E5%BD%95%E9%87%8D%E5%90%AF%E5%90%8E%E8%AF%BB%E4%B8%8D%E5%88%B0%E7%9A%84%E6%A0%B9%E5%9B%A0%E4%B8%8E%E4%BF%AE%E5%A4%8D%EF%BC%88picker%E6%8E%88%E6%9D%83%E5%8F%AA%E6%B4%BB%E4%B8%80%E4%B8%AA%E8%BF%9B%E7%A8%8B%C2%B7%E4%B8%89%E7%AB%AF%E7%BB%9F%E4%B8%80%E6%8E%88%E6%9D%83%E9%93%BE%EF%BC%89.md) |
| 158 | [`158-release侧载包与AGC上架包出齐与「内存又炸了」定性（设备系统virus_protection_executor的OOM风暴·本仓零泄漏证据）.md`](158-release%E4%BE%A7%E8%BD%BD%E5%8C%85%E4%B8%8EAGC%E4%B8%8A%E6%9E%B6%E5%8C%85%E5%87%BA%E9%BD%90%E4%B8%8E%E3%80%8C%E5%86%85%E5%AD%98%E5%8F%88%E7%82%B8%E4%BA%86%E3%80%8D%E5%AE%9A%E6%80%A7%EF%BC%88%E8%AE%BE%E5%A4%87%E7%B3%BB%E7%BB%9Fvirus_protection_executor%E7%9A%84OOM%E9%A3%8E%E6%9A%B4%C2%B7%E6%9C%AC%E4%BB%93%E9%9B%B6%E6%B3%84%E6%BC%8F%E8%AF%81%E6%8D%AE%EF%BC%89.md) |
| 159 | [`159-移动端第二进程与皮肤市场一键安装的根因与修复（手持档不挂托盘·市场挂载契约装完重放·+dshm.49侧载包与AGC上架包）.md`](159-%E7%A7%BB%E5%8A%A8%E7%AB%AF%E7%AC%AC%E4%BA%8C%E8%BF%9B%E7%A8%8B%E4%B8%8E%E7%9A%AE%E8%82%A4%E5%B8%82%E5%9C%BA%E4%B8%80%E9%94%AE%E5%AE%89%E8%A3%85%E7%9A%84%E6%A0%B9%E5%9B%A0%E4%B8%8E%E4%BF%AE%E5%A4%8D%EF%BC%88%E6%89%8B%E6%8C%81%E6%A1%A3%E4%B8%8D%E6%8C%82%E6%89%98%E7%9B%98%C2%B7%E5%B8%82%E5%9C%BA%E6%8C%82%E8%BD%BD%E5%A5%91%E7%BA%A6%E8%A3%85%E5%AE%8C%E9%87%8D%E6%94%BE%C2%B7%2Bdshm.49%E4%BE%A7%E8%BD%BD%E5%8C%85%E4%B8%8EAGC%E4%B8%8A%E6%9E%B6%E5%8C%85%EF%BC%89.md) |
| 160 | [`160-插件安装提速与插件市场预览图（镜像失败回退直连·进程内下载缓存·dshm-shot代理）+dshm.50侧载包与装机脚本假红修复.md`](160-%E6%8F%92%E4%BB%B6%E5%AE%89%E8%A3%85%E6%8F%90%E9%80%9F%E4%B8%8E%E6%8F%92%E4%BB%B6%E5%B8%82%E5%9C%BA%E9%A2%84%E8%A7%88%E5%9B%BE%EF%BC%88%E9%95%9C%E5%83%8F%E5%A4%B1%E8%B4%A5%E5%9B%9E%E9%80%80%E7%9B%B4%E8%BF%9E%C2%B7%E8%BF%9B%E7%A8%8B%E5%86%85%E4%B8%8B%E8%BD%BD%E7%BC%93%E5%AD%98%C2%B7dshm-shot%E4%BB%A3%E7%90%86%EF%BC%89%2Bdshm.50%E4%BE%A7%E8%BD%BD%E5%8C%85%E4%B8%8E%E8%A3%85%E6%9C%BA%E8%84%9A%E6%9C%AC%E5%81%87%E7%BA%A2%E4%BF%AE%E5%A4%8D.md) |
| 161 | [`161-上架前最终审核（恒8条权限面·0个安装包扩展名条目·性能与内存实测定性·4条P1残余风险登记）.md`](161-%E4%B8%8A%E6%9E%B6%E5%89%8D%E6%9C%80%E7%BB%88%E5%AE%A1%E6%A0%B8%EF%BC%88%E6%81%928%E6%9D%A1%E6%9D%83%E9%99%90%E9%9D%A2%C2%B70%E4%B8%AA%E5%AE%89%E8%A3%85%E5%8C%85%E6%89%A9%E5%B1%95%E5%90%8D%E6%9D%A1%E7%9B%AE%C2%B7%E6%80%A7%E8%83%BD%E4%B8%8E%E5%86%85%E5%AD%98%E5%AE%9E%E6%B5%8B%E5%AE%9A%E6%80%A7%C2%B74%E6%9D%A1P1%E6%AE%8B%E4%BD%99%E9%A3%8E%E9%99%A9%E7%99%BB%E8%AE%B0%EF%BC%89.md) |
| 162 | [`162-本地项目整理（清理台账·留档口径·文档勘误与门禁实测）.md`](162-%E6%9C%AC%E5%9C%B0%E9%A1%B9%E7%9B%AE%E6%95%B4%E7%90%86%EF%BC%88%E6%B8%85%E7%90%86%E5%8F%B0%E8%B4%A6%C2%B7%E7%95%99%E6%A1%A3%E5%8F%A3%E5%BE%84%C2%B7%E6%96%87%E6%A1%A3%E5%8B%98%E8%AF%AF%E4%B8%8E%E9%97%A8%E7%A6%81%E5%AE%9E%E6%B5%8B%EF%BC%89.md) |
| 163 | [`163-关于页客户端版本改为运行时读取（写死版本号的P0修复）.md`](163-%E5%85%B3%E4%BA%8E%E9%A1%B5%E5%AE%A2%E6%88%B7%E7%AB%AF%E7%89%88%E6%9C%AC%E6%94%B9%E4%B8%BA%E8%BF%90%E8%A1%8C%E6%97%B6%E8%AF%BB%E5%8F%96%EF%BC%88%E5%86%99%E6%AD%BB%E7%89%88%E6%9C%AC%E5%8F%B7%E7%9A%84P0%E4%BF%AE%E5%A4%8D%EF%BC%89.md) |
| 164 | [`164-上游同步alpha.4轮的自带插件被停用根因（session controller不可用）.md`](164-%E4%B8%8A%E6%B8%B8%E5%90%8C%E6%AD%A5alpha.4%E8%BD%AE%E7%9A%84%E8%87%AA%E5%B8%A6%E6%8F%92%E4%BB%B6%E8%A2%AB%E5%81%9C%E7%94%A8%E6%A0%B9%E5%9B%A0%EF%BC%88session%20controller%E4%B8%8D%E5%8F%AF%E7%94%A8%EF%BC%89.md) |
| 165 | [`165-Agent工具面三件（代码视图开关·PTC预设恢复run_code·进程内python工具）.md`](165-Agent%E5%B7%A5%E5%85%B7%E9%9D%A2%E4%B8%89%E4%BB%B6%EF%BC%88%E4%BB%A3%E7%A0%81%E8%A7%86%E5%9B%BE%E5%BC%80%E5%85%B3%C2%B7PTC%E9%A2%84%E8%AE%BE%E6%81%A2%E5%A4%8Drun_code%C2%B7%E8%BF%9B%E7%A8%8B%E5%86%85python%E5%B7%A5%E5%85%B7%EF%BC%89.md) |
| 166 | [`166-六条反馈落地（后台通知·首帧4s·静默预热·插件二级页返回与侧栏重叠）.md`](166-%E5%85%AD%E6%9D%A1%E5%8F%8D%E9%A6%88%E8%90%BD%E5%9C%B0%EF%BC%88%E5%90%8E%E5%8F%B0%E9%80%9A%E7%9F%A5%C2%B7%E9%A6%96%E5%B8%A74s%C2%B7%E9%9D%99%E9%BB%98%E9%A2%84%E7%83%AD%C2%B7%E6%8F%92%E4%BB%B6%E4%BA%8C%E7%BA%A7%E9%A1%B5%E8%BF%94%E5%9B%9E%E4%B8%8E%E4%BE%A7%E6%A0%8F%E9%87%8D%E5%8F%A0%EF%BC%89.md) |
| 167 | [`167-登录后设置引导的手机档适配（onboarding竖屏单列）.md`](167-%E7%99%BB%E5%BD%95%E5%90%8E%E8%AE%BE%E7%BD%AE%E5%BC%95%E5%AF%BC%E7%9A%84%E6%89%8B%E6%9C%BA%E6%A1%A3%E9%80%82%E9%85%8D%EF%BC%88onboarding%E7%AB%96%E5%B1%8F%E5%8D%95%E5%88%97%EF%BC%89.md) |
| 168 | [`168-平板状态栏归属（手持档只在全屏 最大化时由我们设）.md`](168-%E5%B9%B3%E6%9D%BF%E7%8A%B6%E6%80%81%E6%A0%8F%E5%BD%92%E5%B1%9E%EF%BC%88%E6%89%8B%E6%8C%81%E6%A1%A3%E5%8F%AA%E5%9C%A8%E5%85%A8%E5%B1%8F%20%E6%9C%80%E5%A4%A7%E5%8C%96%E6%97%B6%E7%94%B1%E6%88%91%E4%BB%AC%E8%AE%BE%EF%BC%89.md) |
| 169 | [`169-品牌换标（虎鲸抱环）与图标管线重标定.md`](169-%E5%93%81%E7%89%8C%E6%8D%A2%E6%A0%87%EF%BC%88%E8%99%8E%E9%B2%B8%E6%8A%B1%E7%8E%AF%EF%BC%89%E4%B8%8E%E5%9B%BE%E6%A0%87%E7%AE%A1%E7%BA%BF%E9%87%8D%E6%A0%87%E5%AE%9A.md) |
| 170 | [`170-启动期状态栏同色与多任务交还系统（显式透明）.md`](170-%E5%90%AF%E5%8A%A8%E6%9C%9F%E7%8A%B6%E6%80%81%E6%A0%8F%E5%90%8C%E8%89%B2%E4%B8%8E%E5%A4%9A%E4%BB%BB%E5%8A%A1%E4%BA%A4%E8%BF%98%E7%B3%BB%E7%BB%9F%EF%BC%88%E6%98%BE%E5%BC%8F%E9%80%8F%E6%98%8E%EF%BC%89.md) |
| 171 | [`171-正式版同步（beta→DSHM）与1.1.3 AGC APP包.md`](171-%E6%AD%A3%E5%BC%8F%E7%89%88%E5%90%8C%E6%AD%A5%EF%BC%88beta%E2%86%92DSHM%EF%BC%89%E4%B8%8E1.1.3%20AGC%20APP%E5%8C%85.md) |
| 172 | [`172-API26能力全景与系统融合三件套（A2A·意图框架·系统入口）.md`](172-API26%E8%83%BD%E5%8A%9B%E5%85%A8%E6%99%AF%E4%B8%8E%E7%B3%BB%E7%BB%9F%E8%9E%8D%E5%90%88%E4%B8%89%E4%BB%B6%E5%A5%97%EF%BC%88A2A%C2%B7%E6%84%8F%E5%9B%BE%E6%A1%86%E6%9E%B6%C2%B7%E7%B3%BB%E7%BB%9F%E5%85%A5%E5%8F%A3%EF%BC%89.md) |
| 173 | [`173-浏览器自动化调研（PC端直接操作浏览器·千问扩展解剖）.md`](173-%E6%B5%8F%E8%A7%88%E5%99%A8%E8%87%AA%E5%8A%A8%E5%8C%96%E8%B0%83%E7%A0%94%EF%BC%88PC%E7%AB%AF%E7%9B%B4%E6%8E%A5%E6%93%8D%E4%BD%9C%E6%B5%8F%E8%A7%88%E5%99%A8%C2%B7%E5%8D%83%E9%97%AE%E6%89%A9%E5%B1%95%E8%A7%A3%E5%89%96%EF%BC%89.md) |
| 174 | [`174-浏览器自动化PoC（海泰扩展+本地桥·端到端打通）.md`](174-%E6%B5%8F%E8%A7%88%E5%99%A8%E8%87%AA%E5%8A%A8%E5%8C%96PoC%EF%BC%88%E6%B5%B7%E6%B3%B0%E6%89%A9%E5%B1%95%2B%E6%9C%AC%E5%9C%B0%E6%A1%A5%C2%B7%E7%AB%AF%E5%88%B0%E7%AB%AF%E6%89%93%E9%80%9A%EF%BC%89.md) |
| 175 | [`175-浏览器自动化挪进宿主（beta落地·桥入DSHM与browser工具）.md`](175-%E6%B5%8F%E8%A7%88%E5%99%A8%E8%87%AA%E5%8A%A8%E5%8C%96%E6%8C%AA%E8%BF%9B%E5%AE%BF%E4%B8%BB%EF%BC%88beta%E8%90%BD%E5%9C%B0%C2%B7%E6%A1%A5%E5%85%A5DSHM%E4%B8%8Ebrowser%E5%B7%A5%E5%85%B7%EF%BC%89.md) |
| 176 | [`176-浏览器工具随需拉起（Host到ArkTS外开桥·openLink与显式bundle）.md`](176-%E6%B5%8F%E8%A7%88%E5%99%A8%E5%B7%A5%E5%85%B7%E9%9A%8F%E9%9C%80%E6%8B%89%E8%B5%B7%EF%BC%88Host%E5%88%B0ArkTS%E5%A4%96%E5%BC%80%E6%A1%A5%C2%B7openLink%E4%B8%8E%E6%98%BE%E5%BC%8Fbundle%EF%BC%89.md) |
| 177 | [`177-抓取成功率优化（web_fetch的UA·深嵌套HTML兜底·浏览器CDP文本兜底）.md`](177-%E6%8A%93%E5%8F%96%E6%88%90%E5%8A%9F%E7%8E%87%E4%BC%98%E5%8C%96%EF%BC%88web_fetch%E7%9A%84UA%C2%B7%E6%B7%B1%E5%B5%8C%E5%A5%97HTML%E5%85%9C%E5%BA%95%C2%B7%E6%B5%8F%E8%A7%88%E5%99%A8CDP%E6%96%87%E6%9C%AC%E5%85%9C%E5%BA%95%EF%BC%89.md) |
| 178 | [`178-桌面服务卡片（会话进度与余额-token用量）.md`](178-%E6%A1%8C%E9%9D%A2%E6%9C%8D%E5%8A%A1%E5%8D%A1%E7%89%87%EF%BC%88%E4%BC%9A%E8%AF%9D%E8%BF%9B%E5%BA%A6%E4%B8%8E%E4%BD%99%E9%A2%9D-token%E7%94%A8%E9%87%8F%EF%BC%89.md) |
| 179 | [`179-四项收尾（浏览器工具加深·抓取请求头·卡片直达与用量页·清理）.md`](179-%E5%9B%9B%E9%A1%B9%E6%94%B6%E5%B0%BE%EF%BC%88%E6%B5%8F%E8%A7%88%E5%99%A8%E5%B7%A5%E5%85%B7%E5%8A%A0%E6%B7%B1%C2%B7%E6%8A%93%E5%8F%96%E8%AF%B7%E6%B1%82%E5%A4%B4%C2%B7%E5%8D%A1%E7%89%87%E7%9B%B4%E8%BE%BE%E4%B8%8E%E7%94%A8%E9%87%8F%E9%A1%B5%C2%B7%E6%B8%85%E7%90%86%EF%BC%89.md) |
| 180 | [`180-APMS-Connect-API接入与1.1.3问题查询.md`](180-APMS-Connect-API%E6%8E%A5%E5%85%A5%E4%B8%8E1.1.3%E9%97%AE%E9%A2%98%E6%9F%A5%E8%AF%A2.md) |
| 181 | [`181-APMS故障收口（QEMU后台冷启动与资源预留收紧）.md`](181-APMS%E6%95%85%E9%9A%9C%E6%94%B6%E5%8F%A3%EF%BC%88QEMU%E5%90%8E%E5%8F%B0%E5%86%B7%E5%90%AF%E5%8A%A8%E4%B8%8E%E8%B5%84%E6%BA%90%E9%A2%84%E7%95%99%E6%94%B6%E7%B4%A7%EF%BC%89.md) |
| 182 | [`182-升级后工作区与会话不可见的根因与恢复.md`](182-%E5%8D%87%E7%BA%A7%E5%90%8E%E5%B7%A5%E4%BD%9C%E5%8C%BA%E4%B8%8E%E4%BC%9A%E8%AF%9D%E4%B8%8D%E5%8F%AF%E8%A7%81%E7%9A%84%E6%A0%B9%E5%9B%A0%E4%B8%8E%E6%81%A2%E5%A4%8D.md) |
| 183 | [`183-API23工作区选择兼容（FolderSelection能力预检与专属目录兜底）.md`](183-API23%E5%B7%A5%E4%BD%9C%E5%8C%BA%E9%80%89%E6%8B%A9%E5%85%BC%E5%AE%B9%EF%BC%88FolderSelection%E8%83%BD%E5%8A%9B%E9%A2%84%E6%A3%80%E4%B8%8E%E4%B8%93%E5%B1%9E%E7%9B%AE%E5%BD%95%E5%85%9C%E5%BA%95%EF%BC%89.md) |
| 184 | [`184-DSH上游同步0.2.1-rc.2（+dshm.70）.md`](184-DSH%E4%B8%8A%E6%B8%B8%E5%90%8C%E6%AD%A50.2.1-rc.2%EF%BC%88%2Bdshm.70%EF%BC%89.md) |
| 185 | [`185-平板端移除APP顶栏与系统三键（手持档统一窗口壳）.md`](185-%E5%B9%B3%E6%9D%BF%E7%AB%AF%E7%A7%BB%E9%99%A4APP%E9%A1%B6%E6%A0%8F%E4%B8%8E%E7%B3%BB%E7%BB%9F%E4%B8%89%E9%94%AE%EF%BC%88%E6%89%8B%E6%8C%81%E6%A1%A3%E7%BB%9F%E4%B8%80%E7%AA%97%E5%8F%A3%E5%A3%B3%EF%BC%89.md) |
| 186 | [`186-新增功能代码审核与双端回归（核心+dshm.72）.md`](186-%E6%96%B0%E5%A2%9E%E5%8A%9F%E8%83%BD%E4%BB%A3%E7%A0%81%E5%AE%A1%E6%A0%B8%E4%B8%8E%E5%8F%8C%E7%AB%AF%E5%9B%9E%E5%BD%92%EF%BC%88%E6%A0%B8%E5%BF%83%2Bdshm.72%EF%BC%89.md) |
| 187 | [`187-手机端底部使用统计与系统手势条避让（Web内容框不再下扩）.md`](187-%E6%89%8B%E6%9C%BA%E7%AB%AF%E5%BA%95%E9%83%A8%E4%BD%BF%E7%94%A8%E7%BB%9F%E8%AE%A1%E4%B8%8E%E7%B3%BB%E7%BB%9F%E6%89%8B%E5%8A%BF%E6%9D%A1%E9%81%BF%E8%AE%A9%EF%BC%88Web%E5%86%85%E5%AE%B9%E6%A1%86%E4%B8%8D%E5%86%8D%E4%B8%8B%E6%89%A9%EF%BC%89.md) |
| 188 | [`188-内测双报告收口与guest SSH客户端（QGA失步复位·分屏视口回正）.md`](188-%E5%86%85%E6%B5%8B%E5%8F%8C%E6%8A%A5%E5%91%8A%E6%94%B6%E5%8F%A3%E4%B8%8Eguest%20SSH%E5%AE%A2%E6%88%B7%E7%AB%AF%EF%BC%88QGA%E5%A4%B1%E6%AD%A5%E5%A4%8D%E4%BD%8D%C2%B7%E5%88%86%E5%B1%8F%E8%A7%86%E5%8F%A3%E5%9B%9E%E6%AD%A3%EF%BC%89.md) |
| 189 | [`189-历史文档合并与移交索引（DSHM-beta-1.1.4-core+dshm.73）.md`](189-%E5%8E%86%E5%8F%B2%E6%96%87%E6%A1%A3%E5%90%88%E5%B9%B6%E4%B8%8E%E7%A7%BB%E4%BA%A4%E7%B4%A2%E5%BC%95%EF%BC%88DSHM-beta-1.1.4-core%2Bdshm.73%EF%BC%89.md) |
| 190 | [`190-API26特性可落地清单（基准beta-1.1.4+core0.2.1-rc.2+dshm.74）.md`](190-API26%E7%89%B9%E6%80%A7%E5%8F%AF%E8%90%BD%E5%9C%B0%E6%B8%85%E5%8D%95%EF%BC%88%E5%9F%BA%E5%87%86beta-1.1.4%2Bcore0.2.1-rc.2%2Bdshm.74%EF%BC%89.md) |
| 191 | [`191-2in1电脑模式侧栏入口缺失与仅角点缩放（手持形态+自由窗口的PC模式分档）.md`](191-2in1%E7%94%B5%E8%84%91%E6%A8%A1%E5%BC%8F%E4%BE%A7%E6%A0%8F%E5%85%A5%E5%8F%A3%E7%BC%BA%E5%A4%B1%E4%B8%8E%E4%BB%85%E8%A7%92%E7%82%B9%E7%BC%A9%E6%94%BE%EF%BC%88%E6%89%8B%E6%8C%81%E5%BD%A2%E6%80%81%2B%E8%87%AA%E7%94%B1%E7%AA%97%E5%8F%A3%E7%9A%84PC%E6%A8%A1%E5%BC%8F%E5%88%86%E6%A1%A3%EF%BC%89.md) |
| 192 | [`192-手持档右侧栏打开时左上⊞与标题文字重合（打开右侧栏则藏左侧入口）.md`](192-%E6%89%8B%E6%8C%81%E6%A1%A3%E5%8F%B3%E4%BE%A7%E6%A0%8F%E6%89%93%E5%BC%80%E6%97%B6%E5%B7%A6%E4%B8%8A%E2%8A%9E%E4%B8%8E%E6%A0%87%E9%A2%98%E6%96%87%E5%AD%97%E9%87%8D%E5%90%88%EF%BC%88%E6%89%93%E5%BC%80%E5%8F%B3%E4%BE%A7%E6%A0%8F%E5%88%99%E8%97%8F%E5%B7%A6%E4%BE%A7%E5%85%A5%E5%8F%A3%EF%BC%89.md) |
| 193 | [`193-手持档右侧栏打开时返回手势直接回桌面（BACK_SHIM增加右侧栏分支）.md`](193-%E6%89%8B%E6%8C%81%E6%A1%A3%E5%8F%B3%E4%BE%A7%E6%A0%8F%E6%89%93%E5%BC%80%E6%97%B6%E8%BF%94%E5%9B%9E%E6%89%8B%E5%8A%BF%E7%9B%B4%E6%8E%A5%E5%9B%9E%E6%A1%8C%E9%9D%A2%EF%BC%88BACK_SHIM%E5%A2%9E%E5%8A%A0%E5%8F%B3%E4%BE%A7%E6%A0%8F%E5%88%86%E6%94%AF%EF%BC%89.md) |
| 194 | [`194-系统语音识别长语音Go-No-Go真机结论（PC-2in1，long需滚动会话）.md`](194-%E7%B3%BB%E7%BB%9F%E8%AF%AD%E9%9F%B3%E8%AF%86%E5%88%AB%E9%95%BF%E8%AF%AD%E9%9F%B3Go-No-Go%E7%9C%9F%E6%9C%BA%E7%BB%93%E8%AE%BA%EF%BC%88PC-2in1%EF%BC%8Clong%E9%9C%80%E6%BB%9A%E5%8A%A8%E4%BC%9A%E8%AF%9D%EF%BC%89.md) |
| 195 | [`195-会议模式PC端落地与验收（系统语音识别-原生面板-后台录音）.md`](195-%E4%BC%9A%E8%AE%AE%E6%A8%A1%E5%BC%8FPC%E7%AB%AF%E8%90%BD%E5%9C%B0%E4%B8%8E%E9%AA%8C%E6%94%B6%EF%BC%88%E7%B3%BB%E7%BB%9F%E8%AF%AD%E9%9F%B3%E8%AF%86%E5%88%AB-%E5%8E%9F%E7%94%9F%E9%9D%A2%E6%9D%BF-%E5%90%8E%E5%8F%B0%E5%BD%95%E9%9F%B3%EF%BC%89.md) |
| 196 | [`196-会议面板UI优化（历史会议与沉浸光感按钮）.md`](196-%E4%BC%9A%E8%AE%AE%E9%9D%A2%E6%9D%BFUI%E4%BC%98%E5%8C%96%EF%BC%88%E5%8E%86%E5%8F%B2%E4%BC%9A%E8%AE%AE%E4%B8%8E%E6%B2%89%E6%B5%B8%E5%85%89%E6%84%9F%E6%8C%89%E9%92%AE%EF%BC%89.md) |
| 197 | [`197-会议模式v2调研与方案（AI总结-实时英译-沉浸光感布局）.md`](197-%E4%BC%9A%E8%AE%AE%E6%A8%A1%E5%BC%8Fv2%E8%B0%83%E7%A0%94%E4%B8%8E%E6%96%B9%E6%A1%88%EF%BC%88AI%E6%80%BB%E7%BB%93-%E5%AE%9E%E6%97%B6%E8%8B%B1%E8%AF%91-%E6%B2%89%E6%B5%B8%E5%85%89%E6%84%9F%E5%B8%83%E5%B1%80%EF%BC%89.md) |
| 198 | [`198-Host会议AI插件（总结与英译通道）.md`](198-Host%E4%BC%9A%E8%AE%AEAI%E6%8F%92%E4%BB%B6%EF%BC%88%E6%80%BB%E7%BB%93%E4%B8%8E%E8%8B%B1%E8%AF%91%E9%80%9A%E9%81%93%EF%BC%89.md) |
| 199 | [`199-Host同步探测缓存（LOOP-GAP根因与修复）.md`](199-Host%E5%90%8C%E6%AD%A5%E6%8E%A2%E6%B5%8B%E7%BC%93%E5%AD%98%EF%BC%88LOOP-GAP%E6%A0%B9%E5%9B%A0%E4%B8%8E%E4%BF%AE%E5%A4%8D%EF%BC%89.md) |
| 200 | [`200-Python桥异步化（LOOP-GAP根因二）.md`](200-Python%E6%A1%A5%E5%BC%82%E6%AD%A5%E5%8C%96%EF%BC%88LOOP-GAP%E6%A0%B9%E5%9B%A0%E4%BA%8C%EF%BC%89.md) |
| 201 | [`201-手持档首启侧栏缺失的自愈（视口落定复检与一次性自动展开）.md`](201-%E6%89%8B%E6%8C%81%E6%A1%A3%E9%A6%96%E5%90%AF%E4%BE%A7%E6%A0%8F%E7%BC%BA%E5%A4%B1%E7%9A%84%E8%87%AA%E6%84%88%EF%BC%88%E8%A7%86%E5%8F%A3%E8%90%BD%E5%AE%9A%E5%A4%8D%E6%A3%80%E4%B8%8E%E4%B8%80%E6%AC%A1%E6%80%A7%E8%87%AA%E5%8A%A8%E5%B1%95%E5%BC%80%EF%BC%89.md) |
| 202 | [`202-内测三包与APMS-1.1.4分诊及修复对照.md`](202-%E5%86%85%E6%B5%8B%E4%B8%89%E5%8C%85%E4%B8%8EAPMS-1.1.4%E5%88%86%E8%AF%8A%E5%8F%8A%E4%BF%AE%E5%A4%8D%E5%AF%B9%E7%85%A7.md) |
| 203 | [`203-libnode关io_uring（SIGSYS-425崩溃循环根治）.md`](203-libnode%E5%85%B3io_uring%EF%BC%88SIGSYS-425%E5%B4%A9%E6%BA%83%E5%BE%AA%E7%8E%AF%E6%A0%B9%E6%B2%BB%EF%BC%89.md) |
| 204 | [`204-DSHM-1.1.4内测更新说明（AGC测试版之后）.md`](204-DSHM-1.1.4%E5%86%85%E6%B5%8B%E6%9B%B4%E6%96%B0%E8%AF%B4%E6%98%8E%EF%BC%88AGC%E6%B5%8B%E8%AF%95%E7%89%88%E4%B9%8B%E5%90%8E%EF%BC%89.md) |
| 205 | [`205-MatePad-Edge内存风暴定位与三层收口（PSI-预热-单渲染进程）.md`](205-MatePad-Edge%E5%86%85%E5%AD%98%E9%A3%8E%E6%9A%B4%E5%AE%9A%E4%BD%8D%E4%B8%8E%E4%B8%89%E5%B1%82%E6%94%B6%E5%8F%A3%EF%BC%88PSI-%E9%A2%84%E7%83%AD-%E5%8D%95%E6%B8%B2%E6%9F%93%E8%BF%9B%E7%A8%8B%EF%BC%89.md) |
| 206 | [`206-内测组复测提示词（MatePad-Edge内存专项）.md`](206-%E5%86%85%E6%B5%8B%E7%BB%84%E5%A4%8D%E6%B5%8B%E6%8F%90%E7%A4%BA%E8%AF%8D%EF%BC%88MatePad-Edge%E5%86%85%E5%AD%98%E4%B8%93%E9%A1%B9%EF%BC%89.md) |
| 207 | [`207-MatePad-Edge系列永久desktop与1.1.4回归出包（核心+dshm.77）.md`](207-MatePad-Edge%E7%B3%BB%E5%88%97%E6%B0%B8%E4%B9%85desktop%E4%B8%8E1.1.4%E5%9B%9E%E5%BD%92%E5%87%BA%E5%8C%85%EF%BC%88%E6%A0%B8%E5%BF%83%2Bdshm.77%EF%BC%89.md) |
| 208 | [`208-VM内存分档调度（12G低占用·16G+三端性能档）与真机对照（+dshm.78）.md`](208-VM%E5%86%85%E5%AD%98%E5%88%86%E6%A1%A3%E8%B0%83%E5%BA%A6%EF%BC%8812G%E4%BD%8E%E5%8D%A0%E7%94%A8%C2%B716G%2B%E4%B8%89%E7%AB%AF%E6%80%A7%E8%83%BD%E6%A1%A3%EF%BC%89%E4%B8%8E%E7%9C%9F%E6%9C%BA%E5%AF%B9%E7%85%A7%EF%BC%88%2Bdshm.78%EF%BC%89.md) |
| 209 | [`209-MatePad-Edge后台保活根因（DATA_TRANSFER十分钟取消转TASK_KEEPING）.md`](209-MatePad-Edge%E5%90%8E%E5%8F%B0%E4%BF%9D%E6%B4%BB%E6%A0%B9%E5%9B%A0%EF%BC%88DATA_TRANSFER%E5%8D%81%E5%88%86%E9%92%9F%E5%8F%96%E6%B6%88%E8%BD%ACTASK_KEEPING%EF%BC%89.md) |
| 210 | [`210-平板横屏顶栏与Kirin8020默认工作区兜底（+dshm.78侧载包）.md`](210-%E5%B9%B3%E6%9D%BF%E6%A8%AA%E5%B1%8F%E9%A1%B6%E6%A0%8F%E4%B8%8EKirin8020%E9%BB%98%E8%AE%A4%E5%B7%A5%E4%BD%9C%E5%8C%BA%E5%85%9C%E5%BA%95%EF%BC%88%2Bdshm.78%E4%BE%A7%E8%BD%BD%E5%8C%85%EF%BC%89.md) |
| 211 | [`211-迁移到DevEco-Studio与鸿蒙PC.md`](211-%E8%BF%81%E7%A7%BB%E5%88%B0DevEco-Studio%E4%B8%8E%E9%B8%BF%E8%92%99PC.md) |
| 212 | [`212-鸿蒙PC-AppID口径纠正（唯一正式App-ID-6917614360926110054）.md`](212-%E9%B8%BF%E8%92%99PC-AppID%E5%8F%A3%E5%BE%84%E7%BA%A0%E6%AD%A3%EF%BC%88%E5%94%AF%E4%B8%80%E6%AD%A3%E5%BC%8FApp-ID-6917614360926110054%EF%BC%89.md) |
| 213 | [`213-双端工程剥离方案（PC端与移动端拆分·评审稿）.md`](213-%E5%8F%8C%E7%AB%AF%E5%B7%A5%E7%A8%8B%E5%89%A5%E7%A6%BB%E6%96%B9%E6%A1%88%EF%BC%88PC%E7%AB%AF%E4%B8%8E%E7%A7%BB%E5%8A%A8%E7%AB%AF%E6%8B%86%E5%88%86%C2%B7%E8%AF%84%E5%AE%A1%E7%A8%BF%EF%BC%89.md) |
| 214 | [`214-双端分离实施记录（PC工程与手机工程）.md`](214-%E5%8F%8C%E7%AB%AF%E5%88%86%E7%A6%BB%E5%AE%9E%E6%96%BD%E8%AE%B0%E5%BD%95%EF%BC%88PC%E5%B7%A5%E7%A8%8B%E4%B8%8E%E6%89%8B%E6%9C%BA%E5%B7%A5%E7%A8%8B%EF%BC%89.md) |
| 215 | [`215-PC-only重建与CUSTOM_SANDBOX权限升级（移动端清理·JIT与原生执行回归）.md`](215-PC-only%E9%87%8D%E5%BB%BA%E4%B8%8ECUSTOM_SANDBOX%E6%9D%83%E9%99%90%E5%8D%87%E7%BA%A7%EF%BC%88%E7%A7%BB%E5%8A%A8%E7%AB%AF%E6%B8%85%E7%90%86%C2%B7JIT%E4%B8%8E%E5%8E%9F%E7%94%9F%E6%89%A7%E8%A1%8C%E5%9B%9E%E5%BD%92%EF%BC%89.md) |
| 216 | [`216-DevEco-Studio正式调试签名交接（解除原开发端依赖）.md`](216-DevEco-Studio%E6%AD%A3%E5%BC%8F%E8%B0%83%E8%AF%95%E7%AD%BE%E5%90%8D%E4%BA%A4%E6%8E%A5%EF%BC%88%E8%A7%A3%E9%99%A4%E5%8E%9F%E5%BC%80%E5%8F%91%E7%AB%AF%E4%BE%9D%E8%B5%96%EF%BC%89.md) |
| 217 | [`217-终端接线修复（原生PTY优先与随包core更新）.md`](217-%E7%BB%88%E7%AB%AF%E6%8E%A5%E7%BA%BF%E4%BF%AE%E5%A4%8D%EF%BC%88%E5%8E%9F%E7%94%9FPTY%E4%BC%98%E5%85%88%E4%B8%8E%E9%9A%8F%E5%8C%85core%E6%9B%B4%E6%96%B0%EF%BC%89.md) |
| 218 | [`218-右侧栏拖拽导致终端刷屏与右键菜单失效.md`](218-%E5%8F%B3%E4%BE%A7%E6%A0%8F%E6%8B%96%E6%8B%BD%E5%AF%BC%E8%87%B4%E7%BB%88%E7%AB%AF%E5%88%B7%E5%B1%8F%E4%B8%8E%E5%8F%B3%E9%94%AE%E8%8F%9C%E5%8D%95%E5%A4%B1%E6%95%88.md) |
| 219 | [`219-对话失败修复（libsystem缺件与Python-native环境）.md`](219-%E5%AF%B9%E8%AF%9D%E5%A4%B1%E8%B4%A5%E4%BF%AE%E5%A4%8D%EF%BC%88libsystem%E7%BC%BA%E4%BB%B6%E4%B8%8EPython-native%E7%8E%AF%E5%A2%83%EF%BC%89.md) |
| 220 | [`220-按环境自检报告修复（Python工作区脚本与浏览器桥）.md`](220-%E6%8C%89%E7%8E%AF%E5%A2%83%E8%87%AA%E6%A3%80%E6%8A%A5%E5%91%8A%E4%BF%AE%E5%A4%8D%EF%BC%88Python%E5%B7%A5%E4%BD%9C%E5%8C%BA%E8%84%9A%E6%9C%AC%E4%B8%8E%E6%B5%8F%E8%A7%88%E5%99%A8%E6%A1%A5%EF%BC%89.md) |
| 221 | [`221-浏览器任务冷启动与结束后自动关闭验收.md`](221-%E6%B5%8F%E8%A7%88%E5%99%A8%E4%BB%BB%E5%8A%A1%E5%86%B7%E5%90%AF%E5%8A%A8%E4%B8%8E%E7%BB%93%E6%9D%9F%E5%90%8E%E8%87%AA%E5%8A%A8%E5%85%B3%E9%97%AD%E9%AA%8C%E6%94%B6.md) |
| 222 | [`222-PC权限接线复审与设备能力边界（11条权限·Profile·运行取证）.md`](222-PC%E6%9D%83%E9%99%90%E6%8E%A5%E7%BA%BF%E5%A4%8D%E5%AE%A1%E4%B8%8E%E8%AE%BE%E5%A4%87%E8%83%BD%E5%8A%9B%E8%BE%B9%E7%95%8C%EF%BC%8811%E6%9D%A1%E6%9D%83%E9%99%90%C2%B7Profile%C2%B7%E8%BF%90%E8%A1%8C%E5%8F%96%E8%AF%81%EF%BC%89.md) |
| 223 | [`223-ACCESS_USER_FULL_DISK权限申请回复（DSHM-PC本地AI编程工作台）.md`](223-ACCESS_USER_FULL_DISK%E6%9D%83%E9%99%90%E7%94%B3%E8%AF%B7%E5%9B%9E%E5%A4%8D%EF%BC%88DSHM-PC%E6%9C%AC%E5%9C%B0AI%E7%BC%96%E7%A8%8B%E5%B7%A5%E4%BD%9C%E5%8F%B0%EF%BC%89.md) |
| 224 | [`224-当前项目复审与过期文档资源清理.md`](224-%E5%BD%93%E5%89%8D%E9%A1%B9%E7%9B%AE%E5%A4%8D%E5%AE%A1%E4%B8%8E%E8%BF%87%E6%9C%9F%E6%96%87%E6%A1%A3%E8%B5%84%E6%BA%90%E6%B8%85%E7%90%86.md) |
| 225 | [`225-PC工程移除guest-VM与原生执行收口（core+dshm.80覆盖安装验收）.md`](225-PC%E5%B7%A5%E7%A8%8B%E7%A7%BB%E9%99%A4guest-VM%E4%B8%8E%E5%8E%9F%E7%94%9F%E6%89%A7%E8%A1%8C%E6%94%B6%E5%8F%A3%EF%BC%88core%2Bdshm.80%E8%A6%86%E7%9B%96%E5%AE%89%E8%A3%85%E9%AA%8C%E6%94%B6%EF%BC%89.md) |
| 226 | [`226-鸿蒙PC浏览器扩展故障复核与重适配（CUSTOM_SANDBOX后）.md`](226-%E9%B8%BF%E8%92%99PC%E6%B5%8F%E8%A7%88%E5%99%A8%E6%89%A9%E5%B1%95%E6%95%85%E9%9A%9C%E5%A4%8D%E6%A0%B8%E4%B8%8E%E9%87%8D%E9%80%82%E9%85%8D%EF%BC%88CUSTOM_SANDBOX%E5%90%8E%EF%BC%89.md) |
| 227 | [`227-浏览器主动拉起与newtab陷阱修复（core+dshm.84真机验收）.md`](227-%E6%B5%8F%E8%A7%88%E5%99%A8%E4%B8%BB%E5%8A%A8%E6%8B%89%E8%B5%B7%E4%B8%8Enewtab%E9%99%B7%E9%98%B1%E4%BF%AE%E5%A4%8D%EF%BC%88core%2Bdshm.84%E7%9C%9F%E6%9C%BA%E9%AA%8C%E6%94%B6%EF%BC%89.md) |
| 228 | [`228-Codex子智能体安装修复（精确版本与brew-Codex适配）.md`](228-Codex%E5%AD%90%E6%99%BA%E8%83%BD%E4%BD%93%E5%AE%89%E8%A3%85%E4%BF%AE%E5%A4%8D%EF%BC%88%E7%B2%BE%E7%A1%AE%E7%89%88%E6%9C%AC%E4%B8%8Ebrew-Codex%E9%80%82%E9%85%8D%EF%BC%89.md) |
| 229 | [`229-1.1.5邀请测试APP构建与AGC一致性本地复核.md`](229-1.1.5%E9%82%80%E8%AF%B7%E6%B5%8B%E8%AF%95APP%E6%9E%84%E5%BB%BA%E4%B8%8EAGC%E4%B8%80%E8%87%B4%E6%80%A7%E6%9C%AC%E5%9C%B0%E5%A4%8D%E6%A0%B8.md) |
| 230 | [`230-三端多HAP权限接线与移动工程来源复核（上传前）.md`](230-%E4%B8%89%E7%AB%AF%E5%A4%9AHAP%E6%9D%83%E9%99%90%E6%8E%A5%E7%BA%BF%E4%B8%8E%E7%A7%BB%E5%8A%A8%E5%B7%A5%E7%A8%8B%E6%9D%A5%E6%BA%90%E5%A4%8D%E6%A0%B8%EF%BC%88%E4%B8%8A%E4%BC%A0%E5%89%8D%EF%BC%89.md) |
| 231 | [`231-三端统一迁移与PC手机侧载验收（core+dshm.87）.md`](231-%E4%B8%89%E7%AB%AF%E7%BB%9F%E4%B8%80%E8%BF%81%E7%A7%BB%E4%B8%8EPC%E6%89%8B%E6%9C%BA%E4%BE%A7%E8%BD%BD%E9%AA%8C%E6%94%B6%EF%BC%88core%2Bdshm.87%EF%BC%89.md) |
| 232 | [`232-三端API23兼容·登录回跳与官方插件安装命令（core+dshm.88）.md`](232-%E4%B8%89%E7%AB%AFAPI23%E5%85%BC%E5%AE%B9%C2%B7%E7%99%BB%E5%BD%95%E5%9B%9E%E8%B7%B3%E4%B8%8E%E5%AE%98%E6%96%B9%E6%8F%92%E4%BB%B6%E5%AE%89%E8%A3%85%E5%91%BD%E4%BB%A4%EF%BC%88core%2Bdshm.88%EF%BC%89.md) |
| 233 | [`233-API24工作区内置浏览与手持端侧栏首启自愈（1.1.8）.md`](233-API24%E5%B7%A5%E4%BD%9C%E5%8C%BA%E5%86%85%E7%BD%AE%E6%B5%8F%E8%A7%88%E4%B8%8E%E6%89%8B%E6%8C%81%E7%AB%AF%E4%BE%A7%E6%A0%8F%E9%A6%96%E5%90%AF%E8%87%AA%E6%84%88%EF%BC%881.1.8%EF%BC%89.md) |
| 234 | [`234-API23工作区能力误报修正（1.1.9）.md`](234-API23%E5%B7%A5%E4%BD%9C%E5%8C%BA%E8%83%BD%E5%8A%9B%E8%AF%AF%E6%8A%A5%E4%BF%AE%E6%AD%A3%EF%BC%881.1.9%EF%BC%89.md) |
| 235 | [`235-多机型云调试侧栏默认展开修正（1.1.10）.md`](235-%E5%A4%9A%E6%9C%BA%E5%9E%8B%E4%BA%91%E8%B0%83%E8%AF%95%E4%BE%A7%E6%A0%8F%E9%BB%98%E8%AE%A4%E5%B1%95%E5%BC%80%E4%BF%AE%E6%AD%A3%EF%BC%881.1.10%EF%BC%89.md) |
| 236 | [`236-平板侧栏常驻与手机bash沙箱路径修复（1.1.6）.md`](236-%E5%B9%B3%E6%9D%BF%E4%BE%A7%E6%A0%8F%E5%B8%B8%E9%A9%BB%E4%B8%8E%E6%89%8B%E6%9C%BAbash%E6%B2%99%E7%AE%B1%E8%B7%AF%E5%BE%84%E4%BF%AE%E5%A4%8D%EF%BC%881.1.6%EF%BC%89.md) |
| 237 | [`237-手机遥控平板与PC实施方案（鸿蒙原生优先·评审稿）.md`](237-%E6%89%8B%E6%9C%BA%E9%81%A5%E6%8E%A7%E5%B9%B3%E6%9D%BF%E4%B8%8EPC%E5%AE%9E%E6%96%BD%E6%96%B9%E6%A1%88%EF%BC%88%E9%B8%BF%E8%92%99%E5%8E%9F%E7%94%9F%E4%BC%98%E5%85%88%C2%B7%E8%AF%84%E5%AE%A1%E7%A8%BF%EF%BC%89.md) |
| 238 | [`238-Codex子进程环境与文件管理直达（core+dshm.90·1.1.6-r6）.md`](238-Codex%E5%AD%90%E8%BF%9B%E7%A8%8B%E7%8E%AF%E5%A2%83%E4%B8%8E%E6%96%87%E4%BB%B6%E7%AE%A1%E7%90%86%E7%9B%B4%E8%BE%BE%EF%BC%88core%2Bdshm.90%C2%B71.1.6-r6%EF%BC%89.md) |
| 239 | [`239-MatePad-Edge-PC应用识别与多HAP结构改造（1.1.6-r7）.md`](239-MatePad-Edge-PC%E5%BA%94%E7%94%A8%E8%AF%86%E5%88%AB%E4%B8%8E%E5%A4%9AHAP%E7%BB%93%E6%9E%84%E6%94%B9%E9%80%A0%EF%BC%881.1.6-r7%EF%BC%89.md) |
| 240 | [`240-MatePad-Edge内存收口（ArkWeb单渲染时序与原生PTY硬闸门·1.1.6-r8）.md`](240-MatePad-Edge%E5%86%85%E5%AD%98%E6%94%B6%E5%8F%A3%EF%BC%88ArkWeb%E5%8D%95%E6%B8%B2%E6%9F%93%E6%97%B6%E5%BA%8F%E4%B8%8E%E5%8E%9F%E7%94%9FPTY%E7%A1%AC%E9%97%B8%E9%97%A8%C2%B71.1.6-r8%EF%BC%89.md) |
| 241 | [`241-1.1.6-r8-final环境清理、复审与PC手机构建.md`](241-1.1.6-r8-final%E7%8E%AF%E5%A2%83%E6%B8%85%E7%90%86%E3%80%81%E5%A4%8D%E5%AE%A1%E4%B8%8EPC%E6%89%8B%E6%9C%BA%E6%9E%84%E5%BB%BA.md) |
| 242 | [`242-1.1.6-AGC正式候选与更新日志.md`](242-1.1.6-AGC%E6%AD%A3%E5%BC%8F%E5%80%99%E9%80%89%E4%B8%8E%E6%9B%B4%E6%96%B0%E6%97%A5%E5%BF%97.md) |
| 243 | [`243-1.1.6升级数据迁移与多HAP安装修复.md`](243-1.1.6%E5%8D%87%E7%BA%A7%E6%95%B0%E6%8D%AE%E8%BF%81%E7%A7%BB%E4%B8%8E%E5%A4%9AHAP%E5%AE%89%E8%A3%85%E4%BF%AE%E5%A4%8D.md) |
| 244 | [`244-1.1.6修复版独立Beta包与AGC切回边界.md`](244-1.1.6%E4%BF%AE%E5%A4%8D%E7%89%88%E7%8B%AC%E7%AB%8BBeta%E5%8C%85%E4%B8%8EAGC%E5%88%87%E5%9B%9E%E8%BE%B9%E7%95%8C.md) |
| 245 | [`245-DSH-rc.3上游同步与DSHM-Beta重编.md`](245-DSH-rc.3%E4%B8%8A%E6%B8%B8%E5%90%8C%E6%AD%A5%E4%B8%8EDSHM-Beta%E9%87%8D%E7%BC%96.md) |
| 246 | [`246-Edge-ProMax双左侧栏入口去重（原生顶栏优先）.md`](246-Edge-ProMax%E5%8F%8C%E5%B7%A6%E4%BE%A7%E6%A0%8F%E5%85%A5%E5%8F%A3%E5%8E%BB%E9%87%8D%EF%BC%88%E5%8E%9F%E7%94%9F%E9%A1%B6%E6%A0%8F%E4%BC%98%E5%85%88%EF%BC%89.md) |
| 247 | [`247-PC平板手机三档侧栏布局修正（Edge-ProMax按PC接入）.md`](247-PC%E5%B9%B3%E6%9D%BF%E6%89%8B%E6%9C%BA%E4%B8%89%E6%A1%A3%E4%BE%A7%E6%A0%8F%E5%B8%83%E5%B1%80%E4%BF%AE%E6%AD%A3%EF%BC%88Edge-ProMax%E6%8C%89PC%E6%8E%A5%E5%85%A5%EF%BC%89.md) |
| 248 | [`248-MateBook-Pro-S误判平板与PC终端路由修复.md`](248-MateBook-Pro-S%E8%AF%AF%E5%88%A4%E5%B9%B3%E6%9D%BF%E4%B8%8EPC%E7%BB%88%E7%AB%AF%E8%B7%AF%E7%94%B1%E4%BF%AE%E5%A4%8D.md) |
| 249 | [`249-设备互联权限面与AGC申请结论.md`](249-%E8%AE%BE%E5%A4%87%E4%BA%92%E8%81%94%E6%9D%83%E9%99%90%E9%9D%A2%E4%B8%8EAGC%E7%94%B3%E8%AF%B7%E7%BB%93%E8%AE%BA.md) |
| 250 | [`250-内测双日志复核与手持侧栏常驻（Beta合包）.md`](250-%E5%86%85%E6%B5%8B%E5%8F%8C%E6%97%A5%E5%BF%97%E5%A4%8D%E6%A0%B8%E4%B8%8E%E6%89%8B%E6%8C%81%E4%BE%A7%E6%A0%8F%E5%B8%B8%E9%A9%BB%EF%BC%88Beta%E5%90%88%E5%8C%85%EF%BC%89.md) |
| 251 | [`251-环境缓存清理、官方CoT翻译与AGC正式release.md`](251-%E7%8E%AF%E5%A2%83%E7%BC%93%E5%AD%98%E6%B8%85%E7%90%86%E3%80%81%E5%AE%98%E6%96%B9CoT%E7%BF%BB%E8%AF%91%E4%B8%8EAGC%E6%AD%A3%E5%BC%8Frelease.md) |
| 252 | [`252-官方侧栏按钮复原、平板常驻与PC bash修复.md`](252-%E5%AE%98%E6%96%B9%E4%BE%A7%E6%A0%8F%E6%8C%89%E9%92%AE%E5%A4%8D%E5%8E%9F%E3%80%81%E5%B9%B3%E6%9D%BF%E5%B8%B8%E9%A9%BB%E4%B8%8EPC%20bash%E4%BF%AE%E5%A4%8D.md) |
| 253 | [`253-项目清理、官方插件安装回归与AGC净包.md`](253-%E9%A1%B9%E7%9B%AE%E6%B8%85%E7%90%86%E3%80%81%E5%AE%98%E6%96%B9%E6%8F%92%E4%BB%B6%E5%AE%89%E8%A3%85%E5%9B%9E%E5%BD%92%E4%B8%8EAGC%E5%87%80%E5%8C%85.md) |
| 254 | [`254-官方插件页进程内通道与常驻诊断收口.md`](254-%E5%AE%98%E6%96%B9%E6%8F%92%E4%BB%B6%E9%A1%B5%E8%BF%9B%E7%A8%8B%E5%86%85%E9%80%9A%E9%81%93%E4%B8%8E%E5%B8%B8%E9%A9%BB%E8%AF%8A%E6%96%AD%E6%94%B6%E5%8F%A3.md) |
| 255 | [`255-环境收口（Windows遗留清理·Codex工作流退场·DSH单一开发入口）.md`](255-%E7%8E%AF%E5%A2%83%E6%94%B6%E5%8F%A3%EF%BC%88Windows%E9%81%97%E7%95%99%E6%B8%85%E7%90%86%C2%B7Codex%E5%B7%A5%E4%BD%9C%E6%B5%81%E9%80%80%E5%9C%BA%C2%B7DSH%E5%8D%95%E4%B8%80%E5%BC%80%E5%8F%91%E5%85%A5%E5%8F%A3%EF%BC%89.md) |
| 256 | [`256-继承Codex鸿蒙技能与知识库（.dsh-skills落地）.md`](256-%E7%BB%A7%E6%89%BFCodex%E9%B8%BF%E8%92%99%E6%8A%80%E8%83%BD%E4%B8%8E%E7%9F%A5%E8%AF%86%E5%BA%93%EF%BC%88.dsh-skills%E8%90%BD%E5%9C%B0%EF%BC%89.md) |
| 257 | [`257-接入AGC-CLI（tools-agc与签名身份门禁）.md`](257-%E6%8E%A5%E5%85%A5AGC-CLI%EF%BC%88tools-agc%E4%B8%8E%E7%AD%BE%E5%90%8D%E8%BA%AB%E4%BB%BD%E9%97%A8%E7%A6%81%EF%BC%89.md) |
| 258 | [`258-接手验收（构建链与核心树两条硬能力实测）.md`](258-%E6%8E%A5%E6%89%8B%E9%AA%8C%E6%94%B6%EF%BC%88%E6%9E%84%E5%BB%BA%E9%93%BE%E4%B8%8E%E6%A0%B8%E5%BF%83%E6%A0%91%E4%B8%A4%E6%9D%A1%E7%A1%AC%E8%83%BD%E5%8A%9B%E5%AE%9E%E6%B5%8B%EF%BC%89.md) |
| 259 | [`259-DevEco工具链接手与看界面能力落地.md`](259-DevEco%E5%B7%A5%E5%85%B7%E9%93%BE%E6%8E%A5%E6%89%8B%E4%B8%8E%E7%9C%8B%E7%95%8C%E9%9D%A2%E8%83%BD%E5%8A%9B%E8%90%BD%E5%9C%B0.md) |
| 260 | [`260-真机取证落地（hdc端口发现·PC与手机双档启动实读）.md`](260-%E7%9C%9F%E6%9C%BA%E5%8F%96%E8%AF%81%E8%90%BD%E5%9C%B0%EF%BC%88hdc%E7%AB%AF%E5%8F%A3%E5%8F%91%E7%8E%B0%C2%B7PC%E4%B8%8E%E6%89%8B%E6%9C%BA%E5%8F%8C%E6%A1%A3%E5%90%AF%E5%8A%A8%E5%AE%9E%E8%AF%BB%EF%BC%89.md) |
| 261 | [`261-原生PTY回归恢复（共享HSP与权限面）.md`](261-%E5%8E%9F%E7%94%9FPTY%E5%9B%9E%E5%BD%92%E6%81%A2%E5%A4%8D%EF%BC%88%E5%85%B1%E4%BA%ABHSP%E4%B8%8E%E6%9D%83%E9%99%90%E9%9D%A2%EF%BC%89.md) |
| 262 | [`262-普通平板PC顶栏回归与侧栏入口接管.md`](262-%E6%99%AE%E9%80%9A%E5%B9%B3%E6%9D%BFPC%E9%A1%B6%E6%A0%8F%E5%9B%9E%E5%BD%92%E4%B8%8E%E4%BE%A7%E6%A0%8F%E5%85%A5%E5%8F%A3%E6%8E%A5%E7%AE%A1.md) |
| 263 | [`263-1.1.7 AGC邀请测试候选与环境清理.md`](263-1.1.7%20AGC%E9%82%80%E8%AF%B7%E6%B5%8B%E8%AF%95%E5%80%99%E9%80%89%E4%B8%8E%E7%8E%AF%E5%A2%83%E6%B8%85%E7%90%86.md) |
| 264 | [`264-养鱼插件运行环境落地（Node-JIT与随包ffmpeg）.md`](264-%E5%85%BB%E9%B1%BC%E6%8F%92%E4%BB%B6%E8%BF%90%E8%A1%8C%E7%8E%AF%E5%A2%83%E8%90%BD%E5%9C%B0%EF%BC%88Node-JIT%E4%B8%8E%E9%9A%8F%E5%8C%85ffmpeg%EF%BC%89.md) |
| 265 | [`265-1.1.6-AGC邀请测试候选（三端合包与指定设备侧载）.md`](265-1.1.6-AGC%E9%82%80%E8%AF%B7%E6%B5%8B%E8%AF%95%E5%80%99%E9%80%89%EF%BC%88%E4%B8%89%E7%AB%AF%E5%90%88%E5%8C%85%E4%B8%8E%E6%8C%87%E5%AE%9A%E8%AE%BE%E5%A4%87%E4%BE%A7%E8%BD%BD%EF%BC%89.md) |
| 266 | [`266-手机快捷方式目标模块错配与Beta验证（1.1.6）.md`](266-%E6%89%8B%E6%9C%BA%E5%BF%AB%E6%8D%B7%E6%96%B9%E5%BC%8F%E7%9B%AE%E6%A0%87%E6%A8%A1%E5%9D%97%E9%94%99%E9%85%8D%E4%B8%8EBeta%E9%AA%8C%E8%AF%81%EF%BC%881.1.6%EF%BC%89.md) |
| 267 | [`267-迁移鸿蒙PC自托管开发缺口与修复方案.md`](267-%E8%BF%81%E7%A7%BB%E9%B8%BF%E8%92%99PC%E8%87%AA%E6%89%98%E7%AE%A1%E5%BC%80%E5%8F%91%E7%BC%BA%E5%8F%A3%E4%B8%8E%E4%BF%AE%E5%A4%8D%E6%96%B9%E6%A1%88.md) |
| 268 | [`268-AGENTS.md迁出的编号流水账与历史坑库.md`](268-AGENTS.md%E8%BF%81%E5%87%BA%E7%9A%84%E7%BC%96%E5%8F%B7%E6%B5%81%E6%B0%B4%E8%B4%A6%E4%B8%8E%E5%8E%86%E5%8F%B2%E5%9D%91%E5%BA%93.md) |
| 269 | [`269-修复落地与Beta合并包出包（core-rc.4+dshm.97）.md`](269-%E4%BF%AE%E5%A4%8D%E8%90%BD%E5%9C%B0%E4%B8%8EBeta%E5%90%88%E5%B9%B6%E5%8C%85%E5%87%BA%E5%8C%85%EF%BC%88core-rc.4%2Bdshm.97%EF%BC%89.md) |
| 270 | [`270-关于菜单与开源组件声明（顶栏入口·逐条清单·Beta重编）.md`](270-%E5%85%B3%E4%BA%8E%E8%8F%9C%E5%8D%95%E4%B8%8E%E5%BC%80%E6%BA%90%E7%BB%84%E4%BB%B6%E5%A3%B0%E6%98%8E%EF%BC%88%E9%A1%B6%E6%A0%8F%E5%85%A5%E5%8F%A3%C2%B7%E9%80%90%E6%9D%A1%E6%B8%85%E5%8D%95%C2%B7Beta%E9%87%8D%E7%BC%96%EF%BC%89.md) |
| 271 | [`271-折叠屏适配（单屏锁竖屏·设置面板手机化·宽度断点）.md`](271-%E6%8A%98%E5%8F%A0%E5%B1%8F%E9%80%82%E9%85%8D%EF%BC%88%E5%8D%95%E5%B1%8F%E9%94%81%E7%AB%96%E5%B1%8F%C2%B7%E8%AE%BE%E7%BD%AE%E9%9D%A2%E6%9D%BF%E6%89%8B%E6%9C%BA%E5%8C%96%C2%B7%E5%AE%BD%E5%BA%A6%E6%96%AD%E7%82%B9%EF%BC%89.md) |
| 272 | [`272-平板侧栏收口（不干预官方）与自绘顶栏窗口拖动.md`](272-%E5%B9%B3%E6%9D%BF%E4%BE%A7%E6%A0%8F%E6%94%B6%E5%8F%A3%EF%BC%88%E4%B8%8D%E5%B9%B2%E9%A2%84%E5%AE%98%E6%96%B9%EF%BC%89%E4%B8%8E%E8%87%AA%E7%BB%98%E9%A1%B6%E6%A0%8F%E7%AA%97%E5%8F%A3%E6%8B%96%E5%8A%A8.md) |
| 273 | [`273-2026-10-28修复汇总（构建链·上游同步·文档治理·关于页·折叠屏·平板侧栏·窗口拖动）.md`](273-2026-10-28%E4%BF%AE%E5%A4%8D%E6%B1%87%E6%80%BB%EF%BC%88%E6%9E%84%E5%BB%BA%E9%93%BE%C2%B7%E4%B8%8A%E6%B8%B8%E5%90%8C%E6%AD%A5%C2%B7%E6%96%87%E6%A1%A3%E6%B2%BB%E7%90%86%C2%B7%E5%85%B3%E4%BA%8E%E9%A1%B5%C2%B7%E6%8A%98%E5%8F%A0%E5%B1%8F%C2%B7%E5%B9%B3%E6%9D%BF%E4%BE%A7%E6%A0%8F%C2%B7%E7%AA%97%E5%8F%A3%E6%8B%96%E5%8A%A8%EF%BC%89.md) |
| 274 | [`274-手持档长时任务熄屏就断的两道治理与HDC调用链修正.md`](274-%E6%89%8B%E6%8C%81%E6%A1%A3%E9%95%BF%E6%97%B6%E4%BB%BB%E5%8A%A1%E7%86%84%E5%B1%8F%E5%B0%B1%E6%96%AD%E7%9A%84%E4%B8%A4%E9%81%93%E6%B2%BB%E7%90%86%E4%B8%8EHDC%E8%B0%83%E7%94%A8%E9%93%BE%E4%BF%AE%E6%AD%A3.md) |
| 275 | [`275-链接不跳浏览器（网页侧全量外开接管与原生导航兜底）.md`](275-%E9%93%BE%E6%8E%A5%E4%B8%8D%E8%B7%B3%E6%B5%8F%E8%A7%88%E5%99%A8%EF%BC%88%E7%BD%91%E9%A1%B5%E4%BE%A7%E5%85%A8%E9%87%8F%E5%A4%96%E5%BC%80%E6%8E%A5%E7%AE%A1%E4%B8%8E%E5%8E%9F%E7%94%9F%E5%AF%BC%E8%88%AA%E5%85%9C%E5%BA%95%EF%BC%89.md) |
| 276 | [`276-代码复核与构建产物清理及AGC重编译.md`](276-%E4%BB%A3%E7%A0%81%E5%A4%8D%E6%A0%B8%E4%B8%8E%E6%9E%84%E5%BB%BA%E4%BA%A7%E7%89%A9%E6%B8%85%E7%90%86%E5%8F%8AAGC%E9%87%8D%E7%BC%96%E8%AF%91.md) |
| 277 | [`277-打字顿挫定位（桥方法泄漏×日志写放大）与优化.md`](277-%E6%89%93%E5%AD%97%E9%A1%BF%E6%8C%AB%E5%AE%9A%E4%BD%8D%EF%BC%88%E6%A1%A5%E6%96%B9%E6%B3%95%E6%B3%84%E6%BC%8F%C3%97%E6%97%A5%E5%BF%97%E5%86%99%E6%94%BE%E5%A4%A7%EF%BC%89%E4%B8%8E%E4%BC%98%E5%8C%96.md) |
| 278 | [`278-两日修复落实情况复核（独立取证与未闭合项）.md`](278-%E4%B8%A4%E6%97%A5%E4%BF%AE%E5%A4%8D%E8%90%BD%E5%AE%9E%E6%83%85%E5%86%B5%E5%A4%8D%E6%A0%B8%EF%BC%88%E7%8B%AC%E7%AB%8B%E5%8F%96%E8%AF%81%E4%B8%8E%E6%9C%AA%E9%97%AD%E5%90%88%E9%A1%B9%EF%BC%89.md) |
| 279 | [`279-沉浸光感调研（API26特性可行性与实现方案）.md`](279-%E6%B2%89%E6%B5%B8%E5%85%89%E6%84%9F%E8%B0%83%E7%A0%94%EF%BC%88API26%E7%89%B9%E6%80%A7%E5%8F%AF%E8%A1%8C%E6%80%A7%E4%B8%8E%E5%AE%9E%E7%8E%B0%E6%96%B9%E6%A1%88%EF%BC%89.md) |
| 280 | [`280-沉浸光感二次调研（官方AI方案逐条求证与重新规划）.md`](280-%E6%B2%89%E6%B5%B8%E5%85%89%E6%84%9F%E4%BA%8C%E6%AC%A1%E8%B0%83%E7%A0%94%EF%BC%88%E5%AE%98%E6%96%B9AI%E6%96%B9%E6%A1%88%E9%80%90%E6%9D%A1%E6%B1%82%E8%AF%81%E4%B8%8E%E9%87%8D%E6%96%B0%E8%A7%84%E5%88%92%EF%BC%89.md) |
| 281 | [`281-侧栏浏览器卡死与沉浸光感观感复核（端口偏移断链）.md`](281-%E4%BE%A7%E6%A0%8F%E6%B5%8F%E8%A7%88%E5%99%A8%E5%8D%A1%E6%AD%BB%E4%B8%8E%E6%B2%89%E6%B5%B8%E5%85%89%E6%84%9F%E8%A7%82%E6%84%9F%E5%A4%8D%E6%A0%B8%EF%BC%88%E7%AB%AF%E5%8F%A3%E5%81%8F%E7%A7%BB%E6%96%AD%E9%93%BE%EF%BC%89.md) |
| 282 | [`282-Web内沉浸光感只读诊断（标记选择器内核全通过卡在白底与旧包）.md`](282-Web%E5%86%85%E6%B2%89%E6%B5%B8%E5%85%89%E6%84%9F%E5%8F%AA%E8%AF%BB%E8%AF%8A%E6%96%AD%EF%BC%88%E6%A0%87%E8%AE%B0%E9%80%89%E6%8B%A9%E5%99%A8%E5%86%85%E6%A0%B8%E5%85%A8%E9%80%9A%E8%BF%87%E5%8D%A1%E5%9C%A8%E7%99%BD%E5%BA%95%E4%B8%8E%E6%97%A7%E5%8C%85%EF%BC%89.md) |
| 283 | [`283-Web内沉浸光感（垫片实现·三次失败复盘与最终口径）.md`](283-Web%E5%86%85%E6%B2%89%E6%B5%B8%E5%85%89%E6%84%9F%EF%BC%88%E5%9E%AB%E7%89%87%E5%AE%9E%E7%8E%B0%C2%B7%E4%B8%89%E6%AC%A1%E5%A4%B1%E8%B4%A5%E5%A4%8D%E7%9B%98%E4%B8%8E%E6%9C%80%E7%BB%88%E5%8F%A3%E5%BE%84%EF%BC%89.md) |
| 284 | [`284-深色主题复测（深色玻璃规则从未生效-html应为body）.md`](284-%E6%B7%B1%E8%89%B2%E4%B8%BB%E9%A2%98%E5%A4%8D%E6%B5%8B%EF%BC%88%E6%B7%B1%E8%89%B2%E7%8E%BB%E7%92%83%E8%A7%84%E5%88%99%E4%BB%8E%E6%9C%AA%E7%94%9F%E6%95%88-html%E5%BA%94%E4%B8%BAbody%EF%BC%89.md) |
| 285 | [`285-深色玻璃复测通过（dark字段把空串属性误报成none）.md`](285-%E6%B7%B1%E8%89%B2%E7%8E%BB%E7%92%83%E5%A4%8D%E6%B5%8B%E9%80%9A%E8%BF%87%EF%BC%88dark%E5%AD%97%E6%AE%B5%E6%8A%8A%E7%A9%BA%E4%B8%B2%E5%B1%9E%E6%80%A7%E8%AF%AF%E6%8A%A5%E6%88%90none%EF%BC%89.md) |
| 286 | [`286-第三方皮肤被遮（未重启挂载加玻璃important覆盖）.md`](286-%E7%AC%AC%E4%B8%89%E6%96%B9%E7%9A%AE%E8%82%A4%E8%A2%AB%E9%81%AE%EF%BC%88%E6%9C%AA%E9%87%8D%E5%90%AF%E6%8C%82%E8%BD%BD%E5%8A%A0%E7%8E%BB%E7%92%83important%E8%A6%86%E7%9B%96%EF%BC%89.md) |
| 287 | [`287-沉浸光感改由皮肤插件实现（能力面调研与规划）.md`](287-%E6%B2%89%E6%B5%B8%E5%85%89%E6%84%9F%E6%94%B9%E7%94%B1%E7%9A%AE%E8%82%A4%E6%8F%92%E4%BB%B6%E5%AE%9E%E7%8E%B0%EF%BC%88%E8%83%BD%E5%8A%9B%E9%9D%A2%E8%B0%83%E7%A0%94%E4%B8%8E%E8%A7%84%E5%88%92%EF%BC%89.md) |
| 288 | [`288-破案：玻璃挂错了层级（列是底不是浮层）.md`](288-%E7%A0%B4%E6%A1%88%EF%BC%9A%E7%8E%BB%E7%92%83%E6%8C%82%E9%94%99%E4%BA%86%E5%B1%82%E7%BA%A7%EF%BC%88%E5%88%97%E6%98%AF%E5%BA%95%E4%B8%8D%E6%98%AF%E6%B5%AE%E5%B1%82%EF%BC%89.md) |
| 289 | [`289-皮肤玻璃现象复核（Host侧未加载三方皮肤与观察矛盾）.md`](289-%E7%9A%AE%E8%82%A4%E7%8E%BB%E7%92%83%E7%8E%B0%E8%B1%A1%E5%A4%8D%E6%A0%B8%EF%BC%88Host%E4%BE%A7%E6%9C%AA%E5%8A%A0%E8%BD%BD%E4%B8%89%E6%96%B9%E7%9A%AE%E8%82%A4%E4%B8%8E%E8%A7%82%E5%AF%9F%E7%9F%9B%E7%9B%BE%EF%BC%89.md) |
| 290 | [`290-沉浸光感皮肤插件（方案调研与素材规划）.md`](290-%E6%B2%89%E6%B5%B8%E5%85%89%E6%84%9F%E7%9A%AE%E8%82%A4%E6%8F%92%E4%BB%B6%EF%BC%88%E6%96%B9%E6%A1%88%E8%B0%83%E7%A0%94%E4%B8%8E%E7%B4%A0%E6%9D%90%E8%A7%84%E5%88%92%EF%BC%89.md) |
| 291 | [`291-稳定性与性能完整测试报告（日常使用加开发环境）.md`](291-%E7%A8%B3%E5%AE%9A%E6%80%A7%E4%B8%8E%E6%80%A7%E8%83%BD%E5%AE%8C%E6%95%B4%E6%B5%8B%E8%AF%95%E6%8A%A5%E5%91%8A%EF%BC%88%E6%97%A5%E5%B8%B8%E4%BD%BF%E7%94%A8%E5%8A%A0%E5%BC%80%E5%8F%91%E7%8E%AF%E5%A2%83%EF%BC%89.md) |
| 292 | [`292-review发现项落地修复（核心换树回滚·保活接线·插件完整性·门禁补洞）.md`](292-review%E5%8F%91%E7%8E%B0%E9%A1%B9%E8%90%BD%E5%9C%B0%E4%BF%AE%E5%A4%8D%EF%BC%88%E6%A0%B8%E5%BF%83%E6%8D%A2%E6%A0%91%E5%9B%9E%E6%BB%9A%C2%B7%E4%BF%9D%E6%B4%BB%E6%8E%A5%E7%BA%BF%C2%B7%E6%8F%92%E4%BB%B6%E5%AE%8C%E6%95%B4%E6%80%A7%C2%B7%E9%97%A8%E7%A6%81%E8%A1%A5%E6%B4%9E%EF%BC%89.md) |
| 293 | [`293-包管理环境测试报告（brew缺席与npm假壳pip3实测）.md`](293-%E5%8C%85%E7%AE%A1%E7%90%86%E7%8E%AF%E5%A2%83%E6%B5%8B%E8%AF%95%E6%8A%A5%E5%91%8A%EF%BC%88brew%E7%BC%BA%E5%B8%AD%E4%B8%8Enpm%E5%81%87%E5%A3%B3pip3%E5%AE%9E%E6%B5%8B%EF%BC%89.md) |
| 294 | [`294-包管理环境复测（293两缺陷已修与291卡死连修）.md`](294-%E5%8C%85%E7%AE%A1%E7%90%86%E7%8E%AF%E5%A2%83%E5%A4%8D%E6%B5%8B%EF%BC%88293%E4%B8%A4%E7%BC%BA%E9%99%B7%E5%B7%B2%E4%BF%AE%E4%B8%8E291%E5%8D%A1%E6%AD%BB%E8%BF%9E%E4%BF%AE%EF%BC%89.md) |
| 295 | [`295-294复测结论核实与桥探测退避补强.md`](295-294%E5%A4%8D%E6%B5%8B%E7%BB%93%E8%AE%BA%E6%A0%B8%E5%AE%9E%E4%B8%8E%E6%A1%A5%E6%8E%A2%E6%B5%8B%E9%80%80%E9%81%BF%E8%A1%A5%E5%BC%BA.md) |
| 296 | [`296-API26特性清单现状复核与下一阶段（更新190）.md`](296-API26%E7%89%B9%E6%80%A7%E6%B8%85%E5%8D%95%E7%8E%B0%E7%8A%B6%E5%A4%8D%E6%A0%B8%E4%B8%8E%E4%B8%8B%E4%B8%80%E9%98%B6%E6%AE%B5%EF%BC%88%E6%9B%B4%E6%96%B0190%EF%BC%89.md) |
| 297 | [`297-华为账号多端数据同步三条路线调研与选型建议.md`](297-%E5%8D%8E%E4%B8%BA%E8%B4%A6%E5%8F%B7%E5%A4%9A%E7%AB%AF%E6%95%B0%E6%8D%AE%E5%90%8C%E6%AD%A5%E4%B8%89%E6%9D%A1%E8%B7%AF%E7%BA%BF%E8%B0%83%E7%A0%94%E4%B8%8E%E9%80%89%E5%9E%8B%E5%BB%BA%E8%AE%AE.md) |
| 298 | [`298-DriveKit与AccountKit登录及多端同步落地规划.md`](298-DriveKit%E4%B8%8EAccountKit%E7%99%BB%E5%BD%95%E5%8F%8A%E5%A4%9A%E7%AB%AF%E5%90%8C%E6%AD%A5%E8%90%BD%E5%9C%B0%E8%A7%84%E5%88%92.md) |
| 299 | [`299-P0可行性验证（华为账号与云盘）.md`](299-P0%E5%8F%AF%E8%A1%8C%E6%80%A7%E9%AA%8C%E8%AF%81%EF%BC%88%E5%8D%8E%E4%B8%BA%E8%B4%A6%E5%8F%B7%E4%B8%8E%E4%BA%91%E7%9B%98%EF%BC%89.md) |
| 300 | [`300-华为账号接入修正（官方LoginPanel）与AGC配置指引.md`](300-%E5%8D%8E%E4%B8%BA%E8%B4%A6%E5%8F%B7%E6%8E%A5%E5%85%A5%E4%BF%AE%E6%AD%A3%EF%BC%88%E5%AE%98%E6%96%B9LoginPanel%EF%BC%89%E4%B8%8EAGC%E9%85%8D%E7%BD%AE%E6%8C%87%E5%BC%95.md) |
| 301 | [`301-P2落地（会话同步清单与打包）.md`](301-P2%E8%90%BD%E5%9C%B0%EF%BC%88%E4%BC%9A%E8%AF%9D%E5%90%8C%E6%AD%A5%E6%B8%85%E5%8D%95%E4%B8%8E%E6%89%93%E5%8C%85%EF%BC%89.md) |
| 302 | [`302-Beta包复测提示词（华为账号登录与云同步P0）.md`](302-Beta%E5%8C%85%E5%A4%8D%E6%B5%8B%E6%8F%90%E7%A4%BA%E8%AF%8D%EF%BC%88%E5%8D%8E%E4%B8%BA%E8%B4%A6%E5%8F%B7%E7%99%BB%E5%BD%95%E4%B8%8E%E4%BA%91%E5%90%8C%E6%AD%A5P0%EF%BC%89.md) |
| 304 | [`304-依官方回复重新规划（Drive路线与端云同步路线）.md`](304-%E4%BE%9D%E5%AE%98%E6%96%B9%E5%9B%9E%E5%A4%8D%E9%87%8D%E6%96%B0%E8%A7%84%E5%88%92%EF%BC%88Drive%E8%B7%AF%E7%BA%BF%E4%B8%8E%E7%AB%AF%E4%BA%91%E5%90%8C%E6%AD%A5%E8%B7%AF%E7%BA%BF%EF%BC%89.md) |
| 305 | [`305-路线二验证落地（RDB端云同步V1-V3）.md`](305-%E8%B7%AF%E7%BA%BF%E4%BA%8C%E9%AA%8C%E8%AF%81%E8%90%BD%E5%9C%B0%EF%BC%88RDB%E7%AB%AF%E4%BA%91%E5%90%8C%E6%AD%A5V1-V3%EF%BC%89.md) |
| 306 | [`306-向华为提工单（端云同步BLOB2MB读取上限）.md`](306-%E5%90%91%E5%8D%8E%E4%B8%BA%E6%8F%90%E5%B7%A5%E5%8D%95%EF%BC%88%E7%AB%AF%E4%BA%91%E5%90%8C%E6%AD%A5BLOB2MB%E8%AF%BB%E5%8F%96%E4%B8%8A%E9%99%90%EF%BC%89.md) |
| 307 | [`307-官方答复落地分析（Asset资产端云同步架构）.md`](307-%E5%AE%98%E6%96%B9%E7%AD%94%E5%A4%8D%E8%90%BD%E5%9C%B0%E5%88%86%E6%9E%90%EF%BC%88Asset%E8%B5%84%E4%BA%A7%E7%AB%AF%E4%BA%91%E5%90%8C%E6%AD%A5%E6%9E%B6%E6%9E%84%EF%BC%89.md) |
| 308 | [`308-云同步生产界面落地（鸿蒙设计规范）.md`](308-%E4%BA%91%E5%90%8C%E6%AD%A5%E7%94%9F%E4%BA%A7%E7%95%8C%E9%9D%A2%E8%90%BD%E5%9C%B0%EF%BC%88%E9%B8%BF%E8%92%99%E8%AE%BE%E8%AE%A1%E8%A7%84%E8%8C%83%EF%BC%89.md) |
| 309 | [`309-同步范围确认（同步哪些数据）.md`](309-%E5%90%8C%E6%AD%A5%E8%8C%83%E5%9B%B4%E7%A1%AE%E8%AE%A4%EF%BC%88%E5%90%8C%E6%AD%A5%E5%93%AA%E4%BA%9B%E6%95%B0%E6%8D%AE%EF%BC%89.md) |
| 310 | [`310-插件同步（同步清单到端重装）.md`](310-%E6%8F%92%E4%BB%B6%E5%90%8C%E6%AD%A5%EF%BC%88%E5%90%8C%E6%AD%A5%E6%B8%85%E5%8D%95%E5%88%B0%E7%AB%AF%E9%87%8D%E8%A3%85%EF%BC%89.md) |
| 311 | [`311-顶栏云同步独立菜单（修正稿）.md`](311-%E9%A1%B6%E6%A0%8F%E7%8B%AC%E7%AB%8B%E5%9B%BE%E6%A0%87%E5%85%A5%E5%8F%A3%EF%BC%88%E8%B0%83%E7%A0%94%E4%B8%8E%E5%B8%83%E5%B1%80%E8%A7%84%E5%88%92%EF%BC%89.md) |
| 312 | [`312-云同步入口重构（依云调试日志）.md`](312-%E4%BA%91%E5%90%8C%E6%AD%A5%E5%85%A5%E5%8F%A3%E9%87%8D%E6%9E%84%EF%BC%88%E4%BE%9D%E4%BA%91%E8%B0%83%E8%AF%95%E6%97%A5%E5%BF%97%EF%BC%89.md) |
| 313 | [`313-云同步生产功能规划.md`](313-%E4%BA%91%E5%90%8C%E6%AD%A5%E7%94%9F%E4%BA%A7%E5%8A%9F%E8%83%BD%E8%A7%84%E5%88%92.md) |
| 314 | [`314-云同步生产落地（施工与验收报告）.md`](314-%E4%BA%91%E5%90%8C%E6%AD%A5%E7%94%9F%E4%BA%A7%E8%90%BD%E5%9C%B0%EF%BC%88%E6%96%BD%E5%B7%A5%E4%B8%8E%E9%AA%8C%E6%94%B6%E6%8A%A5%E5%91%8A%EF%BC%89.md) |
| 315 | [`315-云同步入口接入官方账号菜单（方案A）.md`](315-%E4%BA%91%E5%90%8C%E6%AD%A5%E5%85%A5%E5%8F%A3%E6%8E%A5%E5%85%A5%E5%AE%98%E6%96%B9%E8%B4%A6%E5%8F%B7%E8%8F%9C%E5%8D%95%EF%BC%88%E6%96%B9%E6%A1%88A%EF%BC%89.md) |
| 316 | [`316-手持档原生云同步入口（方案A失效修正）.md`](316-%E6%89%8B%E6%8C%81%E6%A1%A3%E5%8E%9F%E7%94%9F%E4%BA%91%E5%90%8C%E6%AD%A5%E5%85%A5%E5%8F%A3%EF%BC%88%E6%96%B9%E6%A1%88A%E5%A4%B1%E6%95%88%E4%BF%AE%E6%AD%A3%EF%BC%89.md) |
| 317 | [`317-云同步入口内置官方设置（三端统一）.md`](317-%E4%BA%91%E5%90%8C%E6%AD%A5%E5%85%A5%E5%8F%A3%E5%86%85%E7%BD%AE%E5%AE%98%E6%96%B9%E8%AE%BE%E7%BD%AE%EF%BC%88%E4%B8%89%E7%AB%AF%E7%BB%9F%E4%B8%80%EF%BC%89.md) |
| 318 | [`318-手机端注入修复与面板UI对齐官方设置.md`](318-%E6%89%8B%E6%9C%BA%E7%AB%AF%E6%B3%A8%E5%85%A5%E4%BF%AE%E5%A4%8D%E4%B8%8E%E9%9D%A2%E6%9D%BFUI%E5%AF%B9%E9%BD%90%E5%AE%98%E6%96%B9%E8%AE%BE%E7%BD%AE.md) |
| 319 | [`319-云同步做成插件接进设置UI（settings.section分区）.md`](319-%E4%BA%91%E5%90%8C%E6%AD%A5%E5%81%9A%E6%88%90%E6%8F%92%E4%BB%B6%E6%8E%A5%E8%BF%9B%E8%AE%BE%E7%BD%AEUI%EF%BC%88settings.section%E5%88%86%E5%8C%BA%EF%BC%89.md) |
| 320 | [`320-手机端云同步接通与更名鲸鸿换标开屏弹簧动效.md`](320-%E6%89%8B%E6%9C%BA%E7%AB%AF%E4%BA%91%E5%90%8C%E6%AD%A5%E6%8E%A5%E9%80%9A%E4%B8%8E%E6%9B%B4%E5%90%8D%E9%B2%B8%E9%B8%BF%E6%8D%A2%E6%A0%87%E5%BC%80%E5%B1%8F%E5%BC%B9%E7%B0%A7%E5%8A%A8%E6%95%88.md) |
| 321 | [`321-二次审核-重复入口与登录绕路-修复合集.md`](321-%E4%BA%8C%E6%AC%A1%E5%AE%A1%E6%A0%B8-%E9%87%8D%E5%A4%8D%E5%85%A5%E5%8F%A3%E4%B8%8E%E7%99%BB%E5%BD%95%E7%BB%95%E8%B7%AF-%E4%BF%AE%E5%A4%8D%E5%90%88%E9%9B%86.md) |
| 322 | [`322-三端日志修复与登录静默授权及性能收口.md`](322-%E4%B8%89%E7%AB%AF%E6%97%A5%E5%BF%97%E4%BF%AE%E5%A4%8D%E4%B8%8E%E7%99%BB%E5%BD%95%E9%9D%99%E9%BB%98%E6%8E%88%E6%9D%83%E5%8F%8A%E6%80%A7%E8%83%BD%E6%94%B6%E5%8F%A3.md)（本地模型接入说明已撤回，通用 API 保留） |
| 323 | [`323-登录就地静默与死代码清理.md`](323-%E7%99%BB%E5%BD%95%E5%B0%B1%E5%9C%B0%E9%9D%99%E9%BB%98%E4%B8%8E%E6%AD%BB%E4%BB%A3%E7%A0%81%E6%B8%85%E7%90%86.md) |
| 324 | [`324-彩色品牌标与登录确认及任务完成通知.md`](324-%E5%BD%A9%E8%89%B2%E5%93%81%E7%89%8C%E6%A0%87%E4%B8%8E%E7%99%BB%E5%BD%95%E7%A1%AE%E8%AE%A4%E5%8F%8A%E4%BB%BB%E5%8A%A1%E5%AE%8C%E6%88%90%E9%80%9A%E7%9F%A5.md) |
| 325 | [`325-侧栏常驻-Hero排版对齐-手机首启重试预算-RC5同步.md`](325-%E4%BE%A7%E6%A0%8F%E5%B8%B8%E9%A9%BB-Hero%E6%8E%92%E7%89%88%E5%AF%B9%E9%BD%90-%E6%89%8B%E6%9C%BA%E9%A6%96%E5%90%AF%E9%87%8D%E8%AF%95%E9%A2%84%E7%AE%97-RC5%E5%90%8C%E6%AD%A5.md) |
| 326 | [`326-长时任务熄屏续期修复与1.1.7.md`](326-%E9%95%BF%E6%97%B6%E4%BB%BB%E5%8A%A1%E7%86%84%E5%B1%8F%E7%BB%AD%E6%9C%9F%E4%BF%AE%E5%A4%8D%E4%B8%8E1.1.7.md) |
| 327 | [`327-思考过程翻译端侧真跑门禁.md`](327-%E6%80%9D%E8%80%83%E8%BF%87%E7%A8%8B%E7%BF%BB%E8%AF%91%E7%AB%AF%E4%BE%A7%E7%9C%9F%E8%B7%91%E9%97%A8%E7%A6%81.md) |
| 328 | [`328-会议模式剥离与权限面收口为上架.md`](328-%E4%BC%9A%E8%AE%AE%E6%A8%A1%E5%BC%8F%E5%89%A5%E7%A6%BB%E4%B8%8E%E6%9D%83%E9%99%90%E9%9D%A2%E6%94%B6%E5%8F%A3%E4%B8%BA%E4%B8%8A%E6%9E%B6.md) |
| 329 | [`329-升级不丢用户数据与保全门禁.md`](329-%E5%8D%87%E7%BA%A7%E4%B8%8D%E4%B8%A2%E7%94%A8%E6%88%B7%E6%95%B0%E6%8D%AE%E4%B8%8E%E4%BF%9D%E5%85%A8%E9%97%A8%E7%A6%81.md) |
| 330 | [`330-侧栏常驻修复与连接失败宽限.md`](330-%E4%BE%A7%E6%A0%8F%E5%B8%B8%E9%A9%BB%E4%BF%AE%E5%A4%8D%E4%B8%8E%E8%BF%9E%E6%8E%A5%E5%A4%B1%E8%B4%A5%E5%AE%BD%E9%99%90.md) |
| 331 | [`331-侧栏真实根因-连接过早报错-翻译默认关闭.md`](331-%E4%BE%A7%E6%A0%8F%E7%9C%9F%E5%AE%9E%E6%A0%B9%E5%9B%A0-%E8%BF%9E%E6%8E%A5%E8%BF%87%E6%97%A9%E6%8A%A5%E9%94%99-%E7%BF%BB%E8%AF%91%E9%BB%98%E8%AE%A4%E5%85%B3%E9%97%AD.md) |
| 332 | [`332-侧栏常驻真实根因与连接宽限落地.md`](332-%E4%BE%A7%E6%A0%8F%E5%B8%B8%E9%A9%BB%E7%9C%9F%E5%AE%9E%E6%A0%B9%E5%9B%A0%E4%B8%8E%E8%BF%9E%E6%8E%A5%E5%AE%BD%E9%99%90%E8%90%BD%E5%9C%B0.md) |
| 333 | [`333-三端连接失败真因-垫片打断WebSocket握手.md`](333-%E4%B8%89%E7%AB%AF%E8%BF%9E%E6%8E%A5%E5%A4%B1%E8%B4%A5%E7%9C%9F%E5%9B%A0-%E5%9E%AB%E7%89%87%E6%89%93%E6%96%ADWebSocket%E6%8F%A1%E6%89%8B.md) |
| 334 | [`334-1.1.7更新日志（详细版）.md`](334-1.1.7%E6%9B%B4%E6%96%B0%E6%97%A5%E5%BF%97%EF%BC%88%E8%AF%A6%E7%BB%86%E7%89%88%EF%BC%89.md)（历史发布留档，本地模型承诺已撤回） |
| 335 | [`335-左下角连接异常根治-WS升级失败后自动重试.md`](335-%E5%B7%A6%E4%B8%8B%E8%A7%92%E8%BF%9E%E6%8E%A5%E5%BC%82%E5%B8%B8%E6%A0%B9%E6%B2%BB-WS%E5%8D%87%E7%BA%A7%E5%A4%B1%E8%B4%A5%E5%90%8E%E8%87%AA%E5%8A%A8%E9%87%8D%E8%AF%95.md) |
| 336 | [`336-悬浮物移除与连接排查结论.md`](336-%E6%82%AC%E6%B5%AE%E7%89%A9%E7%A7%BB%E9%99%A4%E4%B8%8E%E8%BF%9E%E6%8E%A5%E6%8E%92%E6%9F%A5%E7%BB%93%E8%AE%BA.md) |
| 337 | [`337-连接异常真根因-ArkWeb回环误判离线导致连接循环永久休眠.md`](337-%E8%BF%9E%E6%8E%A5%E5%BC%82%E5%B8%B8%E7%9C%9F%E6%A0%B9%E5%9B%A0-ArkWeb%E5%9B%9E%E7%8E%AF%E8%AF%AF%E5%88%A4%E7%A6%BB%E7%BA%BF%E5%AF%BC%E8%87%B4%E8%BF%9E%E6%8E%A5%E5%BE%AA%E7%8E%AF%E6%B0%B8%E4%B9%85%E4%BC%91%E7%9C%A0.md) |
| 338 | [`338-应用预加载调研与探针落地.md`](338-%E5%BA%94%E7%94%A8%E9%A2%84%E5%8A%A0%E8%BD%BD%E8%B0%83%E7%A0%94%E4%B8%8E%E6%8E%A2%E9%92%88%E8%90%BD%E5%9C%B0.md) |
| 339 | [`339-插件依赖图与分阶段加载可行性.md`](339-%E6%8F%92%E4%BB%B6%E4%BE%9D%E8%B5%96%E5%9B%BE%E4%B8%8E%E5%88%86%E9%98%B6%E6%AE%B5%E5%8A%A0%E8%BD%BD%E5%8F%AF%E8%A1%8C%E6%80%A7.md) |
| 340 | [`340-AGC邀请测试上传记录-1.1.7.md`](340-AGC%E9%82%80%E8%AF%B7%E6%B5%8B%E8%AF%95%E4%B8%8A%E4%BC%A0%E8%AE%B0%E5%BD%95-1.1.7.md) |
| 341 | [`341-1.1.6到1.1.7完整复盘.md`](341-1.1.6%E5%88%B01.1.7%E5%AE%8C%E6%95%B4%E5%A4%8D%E7%9B%98.md) |
| 342 | [`342-内置tmux与gh（PC原生与移动端guest）规划与施工.md`](342-%E5%86%85%E7%BD%AEtmux%E4%B8%8Egh%EF%BC%88PC%E5%8E%9F%E7%94%9F%E4%B8%8E%E7%A7%BB%E5%8A%A8%E7%AB%AFguest%EF%BC%89%E8%A7%84%E5%88%92%E4%B8%8E%E6%96%BD%E5%B7%A5.md) |
| 303 | [`303-华为账号登录失败根因（beta包名不在Profile登记范围·1001502003）.md`](303-%E5%8D%8E%E4%B8%BA%E8%B4%A6%E5%8F%B7%E7%99%BB%E5%BD%95%E5%A4%B1%E8%B4%A5%E6%A0%B9%E5%9B%A0%EF%BC%88beta%E5%8C%85%E5%90%8D%E4%B8%8D%E5%9C%A8Profile%E7%99%BB%E8%AE%B0%E8%8C%83%E5%9B%B4%C2%B71001502003%EF%BC%89.md) |
| 343 | [`343-Super-agent环境检测与可修性评估（pnpm构建gh三缺口与平台硬约束）.md`](343-Super-agent%E7%8E%AF%E5%A2%83%E6%A3%80%E6%B5%8B%E4%B8%8E%E5%8F%AF%E4%BF%AE%E6%80%A7%E8%AF%84%E4%BC%B0%EF%BC%88pnpm%E6%9E%84%E5%BB%BAgh%E4%B8%89%E7%BC%BA%E5%8F%A3%E4%B8%8E%E5%B9%B3%E5%8F%B0%E7%A1%AC%E7%BA%A6%E6%9D%9F%EF%BC%89.md) |
| 344 | [`344-Super-agent环境复测（tmux-gh已内置与pnpm仍缺）.md`](344-Super-agent%E7%8E%AF%E5%A2%83%E5%A4%8D%E6%B5%8B%EF%BC%88tmux-gh%E5%B7%B2%E5%86%85%E7%BD%AE%E4%B8%8Epnpm%E4%BB%8D%E7%BC%BA%EF%BC%89.md) |
| 345 | [`345-Super-agent环境复测二（tmux-ps-dsh三项已修与pnpm仍缺）.md`](345-Super-agent%E7%8E%AF%E5%A2%83%E5%A4%8D%E6%B5%8B%E4%BA%8C%EF%BC%88tmux-ps-dsh%E4%B8%89%E9%A1%B9%E5%B7%B2%E4%BF%AE%E4%B8%8Epnpm%E4%BB%8D%E7%BC%BA%EF%BC%89.md) |
| 346 | [`346-Super-agent环境复测三（前置全绿与启动无通道）.md`](346-Super-agent%E7%8E%AF%E5%A2%83%E5%A4%8D%E6%B5%8B%E4%B8%89%EF%BC%88%E5%89%8D%E7%BD%AE%E5%85%A8%E7%BB%BF%E4%B8%8E%E5%90%AF%E5%8A%A8%E6%97%A0%E9%80%9A%E9%81%93%EF%BC%89.md) |
| 347 | [`347-Super-agent环境复测四（无功能变化与解包软链问题）.md`](347-Super-agent%E7%8E%AF%E5%A2%83%E5%A4%8D%E6%B5%8B%E5%9B%9B%EF%BC%88%E6%97%A0%E5%8A%9F%E8%83%BD%E5%8F%98%E5%8C%96%E4%B8%8E%E8%A7%A3%E5%8C%85%E8%BD%AF%E9%93%BE%E9%97%AE%E9%A2%98%EF%BC%89.md) |
| 348 | [`348-超管独立进程实测（判定FAIL·核心树缺superagent种子与卡住空窗口）.md`](348-%E8%B6%85%E7%AE%A1%E7%8B%AC%E7%AB%8B%E8%BF%9B%E7%A8%8B%E5%AE%9E%E6%B5%8B%EF%BC%88%E5%88%A4%E5%AE%9AFAIL%C2%B7%E6%A0%B8%E5%BF%83%E6%A0%91%E7%BC%BAsuperagent%E7%A7%8D%E5%AD%90%E4%B8%8E%E5%8D%A1%E4%BD%8F%E7%A9%BA%E7%AA%97%E5%8F%A3%EF%BC%89.md) |
| 349 | [`349-双进程双端口实测（能力达成·dsh写死版本与host-ready被抢）.md`](349-%E5%8F%8C%E8%BF%9B%E7%A8%8B%E5%8F%8C%E7%AB%AF%E5%8F%A3%E5%AE%9E%E6%B5%8B%EF%BC%88%E8%83%BD%E5%8A%9B%E8%BE%BE%E6%88%90%C2%B7dsh%E5%86%99%E6%AD%BB%E7%89%88%E6%9C%AC%E4%B8%8Ehost-ready%E8%A2%AB%E6%8A%A2%EF%BC%89.md) |
| 350 | [`350-v17验证与日志抓取（附路径bug与启动期崩溃）.md`](350-v17%E9%AA%8C%E8%AF%81%E4%B8%8E%E6%97%A5%E5%BF%97%E6%8A%93%E5%8F%96%EF%BC%88%E9%99%84%E8%B7%AF%E5%BE%84bug%E4%B8%8E%E5%90%AF%E5%8A%A8%E6%9C%9F%E5%B4%A9%E6%BA%83%EF%BC%89.md) |
| 351 | [`351-dsh-plugin-add-link失败（拒绝者是宿主安装器与dsh再次写死版本）.md`](351-dsh-plugin-add-link%E5%A4%B1%E8%B4%A5%EF%BC%88%E6%8B%92%E7%BB%9D%E8%80%85%E6%98%AF%E5%AE%BF%E4%B8%BB%E5%AE%89%E8%A3%85%E5%99%A8%E4%B8%8Edsh%E5%86%8D%E6%AC%A1%E5%86%99%E6%AD%BB%E7%89%88%E6%9C%AC%EF%BC%89.md) |
| 352 | [`352-本地HDC调用检查（二进制可跑但UDS绑定被拒）.md`](352-%E6%9C%AC%E5%9C%B0HDC%E8%B0%83%E7%94%A8%E6%A3%80%E6%9F%A5%EF%BC%88%E4%BA%8C%E8%BF%9B%E5%88%B6%E5%8F%AF%E8%B7%91%E4%BD%86UDS%E7%BB%91%E5%AE%9A%E8%A2%AB%E6%8B%92%EF%BC%89.md) |
| 354 | [`354-运行日志一键取证与PI_AI_ERROR定位.md`](354-%E8%BF%90%E8%A1%8C%E6%97%A5%E5%BF%97%E4%B8%80%E9%94%AE%E5%8F%96%E8%AF%81%E4%B8%8EPI_AI_ERROR%E5%AE%9A%E4%BD%8D.md) |
| 379 | [`379-核心0.2.2-rc.1更新日志复核与手机端inert整页清除.md`](379-%E6%A0%B8%E5%BF%830.2.2-rc.1%E6%9B%B4%E6%96%B0%E6%97%A5%E5%BF%97%E5%A4%8D%E6%A0%B8%E4%B8%8E%E6%89%8B%E6%9C%BA%E7%AB%AFinert%E6%95%B4%E9%A1%B5%E6%B8%85%E9%99%A4.md) |
| 380 | [`380-侧栏展开后整屏变灰不可点与终端不可用的根因复核.md`](380-%E4%BE%A7%E6%A0%8F%E5%B1%95%E5%BC%80%E5%90%8E%E6%95%B4%E5%B1%8F%E5%8F%98%E7%81%B0%E4%B8%8D%E5%8F%AF%E7%82%B9%E4%B8%8E%E7%BB%88%E7%AB%AF%E4%B8%8D%E5%8F%AF%E7%94%A8%E7%9A%84%E6%A0%B9%E5%9B%A0%E5%A4%8D%E6%A0%B8.md) |
| 381 | [`381-平板改走手机壳与PC应用标签消除.md`](381-%E5%B9%B3%E6%9D%BF%E6%94%B9%E8%B5%B0%E6%89%8B%E6%9C%BA%E5%A3%B3%E4%B8%8EPC%E5%BA%94%E7%94%A8%E6%A0%87%E7%AD%BE%E6%B6%88%E9%99%A4.md) |
| 382 | [`382-平板侧栏看齐PC与终端回归修复规划-升1.1.8.md`](382-%E5%B9%B3%E6%9D%BF%E4%BE%A7%E6%A0%8F%E7%9C%8B%E9%BD%90PC%E4%B8%8E%E7%BB%88%E7%AB%AF%E5%9B%9E%E5%BD%92%E4%BF%AE%E5%A4%8D%E8%A7%84%E5%88%92-%E5%8D%871.1.8.md) |
| 383 | [`383-平板左栏常驻且仅用户可收起的方案.md`](383-%E5%B9%B3%E6%9D%BF%E5%B7%A6%E6%A0%8F%E5%B8%B8%E9%A9%BB%E4%B8%94%E4%BB%85%E7%94%A8%E6%88%B7%E5%8F%AF%E6%94%B6%E8%B5%B7%E7%9A%84%E6%96%B9%E6%A1%88.md) |
| 384 | [`384-平板左上角按钮去重方案.md`](384-%E5%B9%B3%E6%9D%BF%E5%B7%A6%E4%B8%8A%E8%A7%92%E6%8C%89%E9%92%AE%E5%8E%BB%E9%87%8D%E6%96%B9%E6%A1%88.md) |
| 385 | [`385-平板侧栏回归官方56px图标轨折叠方案.md`](385-%E5%B9%B3%E6%9D%BF%E4%BE%A7%E6%A0%8F%E5%9B%9E%E5%BD%92%E5%AE%98%E6%96%B956px%E5%9B%BE%E6%A0%87%E8%BD%A8%E6%8A%98%E5%8F%A0%E6%96%B9%E6%A1%88.md) |
| 386 | [`386-三端分离重整方案-PC平板手机各走各的.md`](386-%E4%B8%89%E7%AB%AF%E5%88%86%E7%A6%BB%E9%87%8D%E6%95%B4%E6%96%B9%E6%A1%88-PC%E5%B9%B3%E6%9D%BF%E6%89%8B%E6%9C%BA%E5%90%84%E8%B5%B0%E5%90%84%E7%9A%84.md) |
| 387 | [`387-项目全量审计-过期资源与错误引导分类清单.md`](387-%E9%A1%B9%E7%9B%AE%E5%85%A8%E9%87%8F%E5%AE%A1%E8%AE%A1-%E8%BF%87%E6%9C%9F%E8%B5%84%E6%BA%90%E4%B8%8E%E9%94%99%E8%AF%AF%E5%BC%95%E5%AF%BC%E5%88%86%E7%B1%BB%E6%B8%85%E5%8D%95.md) |
| 388 | [`388-全项目独立代码审查报告-分级清单与优先级.md`](388-%E5%85%A8%E9%A1%B9%E7%9B%AE%E7%8B%AC%E7%AB%8B%E4%BB%A3%E7%A0%81%E5%AE%A1%E6%9F%A5%E6%8A%A5%E5%91%8A-%E5%88%86%E7%BA%A7%E6%B8%85%E5%8D%95%E4%B8%8E%E4%BC%98%E5%85%88%E7%BA%A7.md) |
| 389 | [`389-双壳共享化拆分设计（P0-2）.md`](389-%E5%8F%8C%E5%A3%B3%E5%85%B1%E4%BA%AB%E5%8C%96%E6%8B%86%E5%88%86%E8%AE%BE%E8%AE%A1%EF%BC%88P0-2%EF%BC%89.md) |
| 390 | [`390-平板侧栏B语义点外收起与云测遥测域修复.md`](390-%E5%B9%B3%E6%9D%BF%E4%BE%A7%E6%A0%8FB%E8%AF%AD%E4%B9%89%E7%82%B9%E5%A4%96%E6%94%B6%E8%B5%B7%E4%B8%8E%E4%BA%91%E6%B5%8B%E9%81%A5%E6%B5%8B%E5%9F%9F%E4%BF%AE%E5%A4%8D.md) |
| 391 | [`391-平板去PC应用角标与顶栏沉浸收口.md`](391-%E5%B9%B3%E6%9D%BF%E5%8E%BBPC%E5%BA%94%E7%94%A8%E8%A7%92%E6%A0%87%E4%B8%8E%E9%A1%B6%E6%A0%8F%E6%B2%89%E6%B5%B8%E6%94%B6%E5%8F%A3.md) |
| 392 | [`392-平板与折叠屏展开侧栏真常驻.md`](392-%E5%B9%B3%E6%9D%BF%E4%B8%8E%E6%8A%98%E5%8F%A0%E5%B1%8F%E5%B1%95%E5%BC%80%E4%BE%A7%E6%A0%8F%E7%9C%9F%E5%B8%B8%E9%A9%BB.md) |
| 393 | [`393-插件检查通道补齐与侧滑逐级返回.md`](393-%E6%8F%92%E4%BB%B6%E6%A3%80%E6%9F%A5%E9%80%9A%E9%81%93%E8%A1%A5%E9%BD%90%E4%B8%8E%E4%BE%A7%E6%BB%91%E9%80%90%E7%BA%A7%E8%BF%94%E5%9B%9E.md) |
| 394 | [`394-插件页viewProfilePackage补桥与pnpm启动器原子落位.md`](394-%E6%8F%92%E4%BB%B6%E9%A1%B5viewProfilePackage%E8%A1%A5%E6%A1%A5%E4%B8%8Epnpm%E5%90%AF%E5%8A%A8%E5%99%A8%E5%8E%9F%E5%AD%90%E8%90%BD%E4%BD%8D.md) |
| 395 | [`395-注入型补丁语法守卫（viewProfilePackage函数头事故）.md`](395-%E6%B3%A8%E5%85%A5%E5%9E%8B%E8%A1%A5%E4%B8%81%E8%AF%AD%E6%B3%95%E5%AE%88%E5%8D%AB%EF%BC%88viewProfilePackage%E5%87%BD%E6%95%B0%E5%A4%B4%E4%BA%8B%E6%95%85%EF%BC%89.md) |
| 396 | [`396-PC独立壳与平板去PC角标并存.md`](396-PC%E7%8B%AC%E7%AB%8B%E5%A3%B3%E4%B8%8E%E5%B9%B3%E6%9D%BF%E5%8E%BBPC%E8%A7%92%E6%A0%87%E5%B9%B6%E5%AD%98.md) |
| 397 | [`397-PC终端失效根因与桌面数据根统一.md`](397-PC%E7%BB%88%E7%AB%AF%E5%A4%B1%E6%95%88%E6%A0%B9%E5%9B%A0%E4%B8%8E%E6%A1%8C%E9%9D%A2%E6%95%B0%E6%8D%AE%E6%A0%B9%E7%BB%9F%E4%B8%80.md) |
| 398 | [`398-官方DSH移动端适配口径与我们的差异.md`](398-%E5%AE%98%E6%96%B9DSH%E7%A7%BB%E5%8A%A8%E7%AB%AF%E9%80%82%E9%85%8D%E5%8F%A3%E5%BE%84%E4%B8%8E%E6%88%91%E4%BB%AC%E7%9A%84%E5%B7%AE%E5%BC%82.md) |
| 400 | [`400-熄屏定时任务保活（活跃调度计入workload与熄屏前申请）.md`](400-%E7%86%84%E5%B1%8F%E5%AE%9A%E6%97%B6%E4%BB%BB%E5%8A%A1%E4%BF%9D%E6%B4%BB%EF%BC%88%E6%B4%BB%E8%B7%83%E8%B0%83%E5%BA%A6%E8%AE%A1%E5%85%A5workload%E4%B8%8E%E7%86%84%E5%B1%8F%E5%89%8D%E7%94%B3%E8%AF%B7%EF%BC%89.md) |
| 402 | [`402-1.1.8推送后修复三端落实审核报告.md`](402-1.1.8%E6%8E%A8%E9%80%81%E5%90%8E%E4%BF%AE%E5%A4%8D%E4%B8%89%E7%AB%AF%E8%90%BD%E5%AE%9E%E5%AE%A1%E6%A0%B8%E6%8A%A5%E5%91%8A.md) | 历史接线与验证边界；Ollama 入口已撤回，仅保留历史证据 |
| 403 | [`403-2in1终端bash崩溃修复（TERMINFO路径）与上游rc2状态.md`](403-2in1%E7%BB%88%E7%AB%AFbash%E5%B4%A9%E6%BA%83%E4%BF%AE%E5%A4%8D%EF%BC%88TERMINFO%E8%B7%AF%E5%BE%84%EF%BC%89%E4%B8%8E%E4%B8%8A%E6%B8%B8rc2%E7%8A%B6%E6%80%81.md) | 2in1 bash/tmux 的 TERMINFO 路径修复、task-state 兼容写守卫、rc.2 未发版说明 |
| 404 | [`404-发布前回归审核（后台任务·权限·新修复不回退）.md`](404-%E5%8F%91%E5%B8%83%E5%89%8D%E5%9B%9E%E5%BD%92%E5%AE%A1%E6%A0%B8%EF%BC%88%E5%90%8E%E5%8F%B0%E4%BB%BB%E5%8A%A1%C2%B7%E6%9D%83%E9%99%90%C2%B7%E6%96%B0%E4%BF%AE%E5%A4%8D%E4%B8%8D%E5%9B%9E%E9%80%80%EF%BC%89.md) | 后台任务与 1.1.8 逐项比对、新修复增量取证、权限/ACL 与产物 |
| 405 | [`405-全盘ACL落位与恒定条数解禁（权限以发布Profile为准）.md`](405-%E5%85%A8%E7%9B%98ACL%E8%90%BD%E4%BD%8D%E4%B8%8E%E6%81%92%E5%AE%9A%E6%9D%A1%E6%95%B0%E8%A7%A3%E7%A6%81%EF%BC%88%E6%9D%83%E9%99%90%E4%BB%A5%E5%8F%91%E5%B8%83Profile%E4%B8%BA%E5%87%86%EF%BC%89.md) | 切到 11-09 的 8 条 ACL Profile、entry 升 18 条、构建脚本改为按 Profile 校验 |
| 406 | [`406-三端包体瘦身调研与落地方案（HSP按形态拆分）.md`](406-%E4%B8%89%E7%AB%AF%E5%8C%85%E4%BD%93%E7%98%A6%E8%BA%AB%E8%B0%83%E7%A0%94%E4%B8%8E%E8%90%BD%E5%9C%B0%E6%96%B9%E6%A1%88%EF%BC%88HSP%E6%8C%89%E5%BD%A2%E6%80%81%E6%8B%86%E5%88%86%EF%BC%89.md) | 资产归属清单、实测体积、PC -26.6% / 手机 -16.5% 的拆包方案与风险 |
| 408 | [`408-1.1.8更新日志（官方发布口径）.md`](408-1.1.8%E6%9B%B4%E6%96%B0%E6%97%A5%E5%BF%97%EF%BC%88%E5%AE%98%E6%96%B9%E5%8F%91%E5%B8%83%E5%8F%A3%E5%BE%84%EF%BC%89.md) | 对外发布口径：只列最终生效、非反复的用户可感知修复 |
| 410 | [`410-内置救援插件entry-id与外部同名插件解耦.md`](410-%E5%86%85%E7%BD%AE%E6%95%91%E6%8F%B4%E6%8F%92%E4%BB%B6entry-id%E4%B8%8E%E5%A4%96%E9%83%A8%E5%90%8C%E5%90%8D%E6%8F%92%E4%BB%B6%E8%A7%A3%E8%80%A6.md) | 内置救援插件与外部同名插件的 entry id 解耦（`-builtin`）+ 运行期让位，两者永不共存 |
| 411 | [`411-AI生成标识作用域收敛到会话输入座位.md`](411-AI%E7%94%9F%E6%88%90%E6%A0%87%E8%AF%86%E4%BD%9C%E7%94%A8%E5%9F%9F%E6%94%B6%E6%95%9B%E5%88%B0%E4%BC%9A%E8%AF%9D%E8%BE%93%E5%85%A5%E5%BA%A7%E4%BD%8D.md) | 「内容由 AI 生成」只贴在会话输入座位，右栏 / 其它页面一律不显示 |
| 412 | [`412-bin-dsh按cores-current选核心.md`](412-bin-dsh%E6%8C%89cores-current%E9%80%89%E6%A0%B8%E5%BF%83.md) | `bin/dsh` 按 `cores/.current` 选核心（glob 只兜底），修 `+dshm.10` 字典序选错与 phone 档兜底路径 |
| 413 | [`413-终端分档只有PC与Edge-ProMax有原生终端.md`](413-%E7%BB%88%E7%AB%AF%E5%88%86%E6%A1%A3%E5%8F%AA%E6%9C%89PC%E4%B8%8EEdge-ProMax%E6%9C%89%E5%8E%9F%E7%94%9F%E7%BB%88%E7%AB%AF.md) | 终端分档口径：只有 PC / 2in1 / MateBook / MatePad Edge / Pro Max 有原生终端（sh/zsh/bash），其余平板与手机只能走 VM；含 `MRO-W00` 终端故障根因 |
| 414 | [`414-手机端市场列数改写停用与AI标识只挂会话正文.md`](414-%E6%89%8B%E6%9C%BA%E7%AB%AF%E5%B8%82%E5%9C%BA%E5%88%97%E6%95%B0%E6%94%B9%E5%86%99%E5%81%9C%E7%94%A8%E4%B8%8EAI%E6%A0%87%E8%AF%86%E5%8F%AA%E6%8C%82%E4%BC%9A%E8%AF%9D%E6%AD%A3%E6%96%87.md) | 手机端：停用市场列数改写垫片（插件页/市场不再被压成 2 列）；AI 标识排除 hero 与右栏、要求位于会话正文；附 dshmarket discovery 轮询耗时取证 |
| 415 | [`415-手机档市场宽布局闸只恢复一半.md`](415-%E6%89%8B%E6%9C%BA%E6%A1%A3%E5%B8%82%E5%9C%BA%E5%AE%BD%E5%B8%83%E5%B1%80%E9%97%B8%E5%8F%AA%E6%81%A2%E5%A4%8D%E4%B8%80%E5%8D%8A.md) | 手机单屏市场变窄的定论：只恢复 `matchMedia(681px)` 宽布局闸、禁止改列数；含 1010015 与故障包的 ABC 对比 |
| 416 | [`416-恢复自由窗口系统装饰（分屏与拖拽入口）.md`](416-%E6%81%A2%E5%A4%8D%E8%87%AA%E7%94%B1%E7%AA%97%E5%8F%A3%E7%B3%BB%E7%BB%9F%E8%A3%85%E9%A5%B0%EF%BC%88%E5%88%86%E5%B1%8F%E4%B8%8E%E6%8B%96%E6%8B%BD%E5%85%A5%E5%8F%A3%EF%BC%89.md) | 恢复「手持形态 + 自由窗口」的系统装饰与三键：分屏与窗口拖拽入口回来；登记"自由窗口多一条标题栏"的代价 |
| 417 | [`417-输入框钉底与顶部让位不被清零.md`](417-%E8%BE%93%E5%85%A5%E6%A1%86%E9%92%89%E5%BA%95%E4%B8%8E%E9%A1%B6%E9%83%A8%E8%AE%A9%E4%BD%8D%E4%B8%8D%E8%A2%AB%E6%B8%85%E9%9B%B6.md) | 输入框钉底（`will-change:auto` 消合成层 + 覆盖 absolute 分支）与顶部让位不被系统 `topRect=0` 覆盖 |
| 418 | [`418-碰一碰传文件调研（ShareKit沙箱接收·WorkBuddy逆向对照）.md`](418-%E7%A2%B0%E4%B8%80%E7%A2%B0%E4%BC%A0%E6%96%87%E4%BB%B6%E8%B0%83%E7%A0%94%EF%BC%88ShareKit%E6%B2%99%E7%AE%B1%E6%8E%A5%E6%94%B6%C2%B7WorkBuddy%E9%80%86%E5%90%91%E5%AF%B9%E7%85%A7%EF%BC%89.md) | 碰一碰传文件（**已落地 PC 档**）：harmonyShare 沙箱接收**零新增权限**（d.ts 逐条核验）；WorkBuddy 三层逆向对照；落地＝`KnockShareReceiver`（每传输独立空目录、16MiB 上限）+ `KNOCK_SHIM_JS`（合成 paste→官方 intake，退路 drop）+ `WebApp.ets` PC 档门控接线；构建与 113 条门禁全绿；余真机待验＝ArkWeb 合成事件、正式签名说 |
| 419 | [`419-沉浸光感混合承载落地（entry弹窗材质与网页菜单原生接管）.md`](419-%E6%B2%89%E6%B5%B8%E5%85%89%E6%84%9F%E6%B7%B7%E5%90%88%E6%89%BF%E8%BD%BD%E8%90%BD%E5%9C%B0%EF%BC%88entry%E5%BC%B9%E7%AA%97%E6%9D%90%E8%B4%A8%E4%B8%8E%E7%BD%91%E9%A1%B5%E8%8F%9C%E5%8D%95%E5%8E%9F%E7%94%9F%E6%8E%A5%E7%AE%A1%EF%BC%89.md) | 沉浸光感混合承载（**已落地 entry 档**）：4 处 AlertDialog 挂 THICK 材质；Web 右键/长按菜单原生接管（`openMenu` + THIN `immersiveMaterialOf` + `WithTheme` + Stack 内 1×1 锚点）；Kit 实参求值前 API≥26 守卫；`diag-material`/`diag-webmenu` 探针；订正 281 §3.1 entry 行；构建绿，余真机观感待验 |
| 420 | [`420-设置面板官方排除扩到全形态（平板浅黑覆盖修复与门禁基线冻结订正）.md`](420-%E8%AE%BE%E7%BD%AE%E9%9D%A2%E6%9D%BF%E5%AE%98%E6%96%B9%E6%8E%92%E9%99%A4%E6%89%A9%E5%88%B0%E5%85%A8%E5%BD%A2%E6%80%81%EF%BC%88%E5%B9%B3%E6%9D%BF%E6%B5%85%E9%BB%91%E8%A6%86%E7%9B%96%E4%BF%AE%E5%A4%8D%E4%B8%8E%E9%97%A8%E7%A6%81%E5%9F%BA%E7%BA%BF%E5%86%BB%E7%BB%93%E8%AE%A2%E6%AD%A3%EF%BC%89.md) | 设置面板玻璃排除扩到全形态（**已落地**）：`findDialogs` 删 `dshm-desktop` 条件，设置面板及内部 dialog 全形态跳过玻璃、官方面板/遮罩 token 复位；顺带 `topBarBg`/`topBarBgNow()` 退役 + 两门禁改钉；**门禁基线冻结订正**——回放基线停在 113 条致 11-16 红门禁漏网，新增 `gen-full-yml-gates.py` 与 131 条全量基线；131 清扫 0 失败，Beta `20261117T024043`，余真机观感待验 |
| 421 | [`421-碰一碰传文件（DSHM端实现与修复方案）.md`](421-%E7%A2%B0%E4%B8%80%E7%A2%B0%E4%BC%A0%E6%96%87%E4%BB%B6%EF%BC%88DSHM%E7%AB%AF%E5%AE%9E%E7%8E%B0%E4%B8%8E%E4%BF%AE%E5%A4%8D%E6%96%B9%E6%A1%88%EF%BC%89.md) | 碰一碰传文件 DSHM 端**落地任务书（已落地：WP1/2/3/5 + 诊断增强；WP4 与键值格式未做，见 §8）**：现状审计（注册寿命/只注册主窗/UTD 能力表三处缺口）、6 个工作包（注册常驻化、按窗注册、`general.object` 能力面、接收目录、Web 投递 `defaultPrevented` 判据、诊断契约）、真机验收 9 条；更正 418 §6「签名」结论证据不足 |
| 422 | [`422-核心同步到0.2.2-rc.4（兼容面重生成与全量门禁复核）.md`](422-%E6%A0%B8%E5%BF%83%E5%90%8C%E6%AD%A5%E5%88%B00.2.2-rc.4%EF%BC%88%E5%85%BC%E5%AE%B9%E9%9D%A2%E9%87%8D%E7%94%9F%E6%88%90%E4%B8%8E%E5%85%A8%E9%87%8F%E9%97%A8%E7%A6%81%E5%A4%8D%E6%A0%B8%EF%BC%89.md) | 核心同步到 `0.2.2-rc.4+dshm.1`（**已落地**）：包集合不变、端点 223→224（新增 `deepseekChatImport/limits`）、8 个受补丁包逐字节一致；`Endpoints.ets` 基线此前停在 0.2.1-rc.2/144 条，本轮重生成到 rc.4/224；容器重打 `f6e1c0a3…` 并入 resfile；entry 构建 81 tasks、131 条全量门禁 0 失败；版本未升、未出包

# DSHM 项目交接（2026-10-21 历史快照）

> 当前基线：PC 正式包 `1.1.4 / 1010004`，核心 `0.2.1-rc.2+dshm.78`。
> 本文更新于 2026-10-21，是接手项目的首读入口。
>
> 发生冲突时按以下顺序取事实：运行中的代码与配置、仓库门禁与真机证据、本文、
> `docs/README.md`、历史专题文档。历史专题用于追溯原因，不代表当前状态。

## 0. 2026-10-20 新增：DevEco Studio / 鸿蒙 PC 工作区迁移

- 新增 `tools/export-deveco-workspace.ps1`：导出源码完整、可直接由 DevEco Studio
  打开的迁移工作区；保留 `entry/libs`、`resfile`、node headers、`third_party`、
  未提交改动与 `.git`，排除 `dist`、构建缓存、`oh_modules` 和本机签名配置。
- 当前工程已切换到正式包 `com.dshm.dshclient`，release 签名配置和
  AppID 校验见 `docs/215` / `docs/212`。
- 首次启动说明：`tools/START-HERE.dev-eco.md`；完整边界见 `docs/211`。
- 迁移 ZIP 通过压缩包完整性、关键资产哈希、禁用目录和签名泄露检查后再交付。

## 0. 2026-10-20 新增：MatePad Edge 保活 + 平板顶栏 / 工作区兜底

- 平板顶栏恢复为“仅横屏显示”，PC/2in1 恒显，手机恒不显；顶栏可见时不再叠加
  24vp 三键让位。Kirin 8020 手持档除用户取消外的所有文件夹选择错误都静默落到
  `Download/<bundle>`，不弹二次选择。
- 新侧载件：
  `dist/sideload/DSHM-beta-1.1.4-core0.2.1-rc.2+dshm.78-tablet-topbar-picker-arm64-signed.hap`
  （`439,481,607 B / 3AE5A6B0…6F5B6FC3`）。详见 `docs/210`。

- 内测报告写的是 `+dshm.73`，而同日 Beta 完整日志实际跑 `+dshm.78`，两者不能混为一谈。
- `.78` 日志按行号证明 ArkWeb 收到 `OnWindowHide` 后 `SetVsyncEnabled 0`，HIDE 段 vsync=0；
  报告里的“后台仍 120Hz”是误判。
- 真正可复现的是 `DATA_TRANSFER` 长时任务约 **603 秒**被系统取消；
  三次启动/停止分别为 10:29:49→10:39:52、11:12:23→11:22:26、11:38:33→11:48:36。
  取消后 5 秒起，原生心跳与 Host 同步进入 20–25 秒一轮的整进程冻结。
- 修复：PC/2in1 优先 `TASK_KEEPING`、不支持才降级 `DATA_TRANSFER`；托盘后台 Ability
  改用当前 bundle（不再把 beta 指向正式包）；新增 `files/diag-keepalive` 取证。
- 详见 `docs/209`。门禁 `tools/check-memory-guard.mjs` 已扩展到 E1–E6 + M8–M10。

## 0. 2026-10-19 新增（会议 v2 + 会议 AI 插件）

- `docs/197`：会议面板 v2（按停顿分段 + 手动点名、暂停/静音、最小化胶囊、实时英译开关、AI 总结按钮、历史总结卡）；
- `docs/198`：Host 插件 `dshm-meeting-ai`（`$DSH_HOME/meeting-ai` 队列；总结/英译走本机 DSH 模型）；核心升 `+dshm.76`；
- 真机证据见 `docs/197` §5.4：英译 17 行、总结文件双写、历史 `AI 已总结`。

## 0. 2026-10-19 晚新增（内测三包 + APMS 1.1.4：四条根因修复，PC 真机已验）

> 输入：三份内测日志包 + AGC APMS（`docs/202` 总分诊；症状 21 条、`dist/triage/2026-10-19/`）。
> 修复（核心版本仍 `+dshm.76`，**未升**）：

| 文档 | 根因 | 修复 | 门禁 |
|---|---|---|---|
| `docs/199` | Node 模块解析把 `~/.node_modules` 当全局搜索路径，慢存储单次负探测 **192s** ⇒ 周期 LOOP-GAP（67s 一次 8.1s，占 12%） | ① `fs-probe-cache.cjs` 负结果缓存（TTL 30s，写前置空）② `module-path-guard.cjs` 收窄 `Module._initPaths()` 的输入（HOME/NODE_PATH 同步窗口内还原） | `check-fs-probe-cache` 46 项/6 臂；`check-module-path-guard` 36 项/4 臂 |
| `docs/200` | pip/长脚本在主线程跑 CPython ⇒ LOOP-GAP 33s/522s/800s | `python-worker.cjs` + `python-bridge-async.cjs`：执行搬到 worker（单飞、超时 terminate、失败明确报错）；顺带 `git=FAIL`→`SKIPPED` 三态 | `check-python-async-worker` 38 项/6 臂 |
| `docs/201` | 平板首启侧栏缺失（NWeb 早于窗口几何创建 ⇒ 上游按窄视口布局且不再重算） | 手持档「宽视口 + 收起态」一次性自动点开官方 toggle（前 15s）+ `onPageEnd` 后 0.9/2.0/4.0s 视口落定复检 | `check-handheld-sidebar-recover` 3 臂 |
| `docs/203` | APMS 1.1.4 的 `SIGSYS 425` 崩溃循环（1951 次/1 台设备） | **取证后确认不来自随包件**：6 个已发 HAP 的 `libnode.so.137` 逐字节相同且 17 个 io_uring 系统调用槽全部中性化；不做盲改，交付可逆补丁工具 + 守卫门禁 + 取证清单 | `check-libnode-io-uring` 16 项/2 臂 |

**PC 真机验证（`86E0226429000417`，2026-10-19 19:06 装包后）**：
- `全局模块路径已收窄（移除 2 项 ~…）`；本次进程 `~/.node_modules` 命中 **0**（日志里剩的 5 条全是修复前旧记录）；
- `fs 探测缓存已接管 existsSync/statSync/readFileSync`；`python 桥：执行线程=worker`；`git=SKIPPED`；
- 本次进程只有 3 条**启动期** LOOP-GAP（1.5–1.8s），**没有**周期性 8s 停顿；页面 ready 200；进程存活、hilog 无 SIGSYS。

HAP 重出：`dist/sideload/…+dshm.76…hap` = **439,482,409 B / sha256 `B51EAFDF…`**（见 §2）。
> 2026-10-19 19:45 追加：按用户要求**隐藏会议模式**（`MEETING_MODE_VISIBLE=false`、`id_meeting.visible=false`、
> `dshAction=meeting` 忽略；见 `docs/197` §6），HAP 重出为本行 sha。
> 给测试组的更新说明见 `docs/204`（范围 = AGC 1.1.4 邀测包 `+dshm.73` 之后到本侧载包）。
> 2026-10-19 晚追加（MatePad Edge 内存风暴）：`docs/205` —— Web 单渲染进程 + `onMemoryLevel` 释放 ArkWeb 缓存 + Host 内存看门狗/安全模式 + **VM 预热默认关**（`DSHM_VM_PREWARM=on` 才开）。

## 0. 2026-10-18 晚新增：系统语音识别 + 会议模式（PC 端已验）

- 普通听写已切到 **HarmonyOS Core Speech Kit**（`long` + 18.75s 滚动会话；不再依赖 SenseVoice 模型）。
- 新增 **原生会议模式**：菜单/桌面快捷方式进入，录音 + 实时转写 + WAV/Markdown 保存 + 插入当前会话；后台录音长时任务已验 35s。
- Host provider 退出模型下载路径；核心树 `0.2.1-rc.2+dshm.76`。
- 证据与门禁：[`194`](194-系统语音识别长语音Go-No-Go真机结论（PC-2in1，long需滚动会话）.md)、[`195`](195-会议模式PC端落地与验收（系统语音识别-原生面板-后台录音）.md)、`tools/check-meeting-mode.mjs`（已入 CI）。
- 手机端与 AGC 新版本按用户口径**暂不推送**。
## 1. 一句话现状

DSHM 已把 DeepSeek Harness 的 Node Host 与核心树装进 HarmonyOS HAP，
在应用进程内监听 `127.0.0.1`，由 ArkUI / ArkWeb 壳提供界面，
本仓库只服务 PC 工程，支持 tablet、2in1；手机 / 折叠屏由独立工程承载。
核心版本为 `0.2.1-rc.2+dshm.78`。

当前工作区已于 2026-10-21 按用户授权切换为 PC 正式包
`com.dshm.dshclient`。
独立正式目录与备份侧是物理门禁，本工作区不主动读写。

## 2. 当前交付件

| 项 | 值 |
|---|---|
| APP | `dist/release-test/DSHM-1.1.4-PC-dshclient-release-signed.app` |
| HAP | `dist/release-test/DSHM-1.1.4-PC-dshclient-release-signed.hap` |
| 应用版本 | `1.1.4 (1010004)` |
| Bundle | `com.dshm.dshclient` |
| 核心 | `0.2.1-rc.2+dshm.78` |
| 构建模式 | `release` |
| 签名 | AGC release 签名，profile `type=release` |
| 设备类型 | `tablet` / `2in1`（**2026-10-21 双端分离：手机已剥离到独立工程 `DSHM-mobile`**，见 `docs/214`） |
| 最低 API | `60100023`，即 HarmonyOS 6.1.0 / API 23 |
| 目标 API | `260000026` |
| HAP 条目 | 147 |
| 权限 | PC 恒 11 条（3 ACL + 2 kernel + 6 普通） |
| APK 相关条目 | 0 |
| APP SHA256 | `c2d3fdb247cfd13262ed7a8e5e0fa0bdc90da5ab893ef59f67def17bd6da570c` |
| HAP SHA256 | `29bfec3eac241ee6d8ea58db02d5a1a11aef136fd6c3db056dcce4a9ac30364d` |

APP 与 HAP 均已通过 `hap-sign-tool verify-app`，Profile 的
`app-identifier` 为 `6917614360926110054`。

## 3. 工作区、签名与数据边界

| 区域 | 用途 | 规则 |
|---|---|---|
| 当前 PC 工作区 | 正式包测试 | 当前出 `com.dshm.dshclient`；独立正式目录仍作为备份侧，不互相写入 |
| `D:\desktop\ohos\DSHM` | 正式工作区与备份 | 本工作区不写入、不构建、不复制；正式同步必须获得用户明确授权 |
| `C:\Users\Sol\.ohos` | DevEco 调试签名物料 | 永不删除 |
| `D:\DSHM-signing-backup` | 仓库外签名备份 | 永不删除 |
| `D:\desktop\release` | AGC 发布签名物料 | 不移动、不覆盖、不混用 |
| 设备 `el2` 数据 | 会话、工作区、插件、凭据 | 任何卸载或删除命令都禁止 |

日常开发直接点击 Run。若确需 CLI 更新，只允许覆盖安装：

```powershell
hdc install -r <hap>
```

`-r` 只替换 el1 代码与资源，不删除 el2 用户数据。禁止执行
`hdc uninstall`、`bm uninstall` 或任何 `/data/app/el2/**` 删除命令。
签名变化导致覆盖安装失败时，也必须先停下来确认，不能自行卸载。

## 4. 权限面与 APK 红线

当前 PC `requestPermissions` 恒为 11 条：

| 类别 | 权限 |
|---|---|
| 已审批 ACL | `ALLOW_EXTERNAL_NATIVE_CODE`、`FILE_ACCESS_PERSIST`、`CUSTOM_SANDBOX` |
| 2in1 kernel capability | `kernel.IGNORE_LIBRARY_VALIDATION`、`kernel.EXEMPT_ANONYMOUS_EXECUTABLE_MEMORY` |
| 免申请 | `INTERNET`、`GET_NETWORK_INFO`、`KEEP_BACKGROUND_RUNNING`、`PREPARE_APP_TERMINATE`、`STORE_PERSISTENT_DATA`、`MICROPHONE` |

两条 `kernel.*` 是 `normal / system_grant / provisionEnable=false`，直接声明，
不写入 ACL。历史事故中撤掉的两条用户目录权限也不得回补。唯一裁判：

```powershell
node tools/check-permission-surface.mjs
node tools/check-permission-surface.mjs --self-test
```

包内和仓库中禁止出现 APK 相关目录、文件或归档条目。审核端检测到 APK
会直接拦截。唯一裁判：

```powershell
node tools/check-no-apk-surface.mjs
```

## 5. 当前架构

```text
ArkUI / ArkWeb 客户端
        |
        | HTTP /api/*, WebSocket /api/remote.mux, 127.0.0.1
        v
应用进程内的 Node Host
        |
        | DSH_HOME = <应用沙箱>/dsh/home
        v
dsh 核心树版本仓库 dsh/cores/<version>
        |
        +-- 自带插件、市场桥、profile seed
        +-- guest QEMU / QGA / xterm 终端通道
        +-- 卡片、浏览器桥、A2A 骨架
```

关键边界：

- PC Node 默认启用 JIT，并保留显式 jitless 后备；所有上游 `undici` 路径仍由纯 JS 垫片接管。
- Host 只监听回环地址，不向局域网暴露服务。
- 当前 8 权限包没有宿主可执行内存，也没有应用数据区 ELF `execve` 能力。
- 终端和 bash 能力走随包 guest VM、QGA 和 guest 内 userland，不靠新增权限。
- PC / 2in1 恒显 APP 顶栏；平板仅横屏显示；手机不显示。顶栏显示与 24vp
  三键让位互斥，避免双重占位。
- 浏览器自动化仅 PC / 2in1；移动端不注册 `browser_*` 工具。

## 6. 已完成能力

| 模块 | 当前状态 |
|---|---|
| 本地核心 | 随包 Node、核心树、进程内 Host、版本激活与回滚已运行 |
| 会话与工作区 | 会话、工作区、目录授权持久化、升级后恢复已接线 |
| API 23 兼容 | 可安装运行；无 `FolderSelection` 时自动使用 `Download/<包名>` 专属工作区 |
| 终端执行 | `CUSTOM_SANDBOX` 生效时走宿主原生 exec / PTY；权限未生效时平板可回退 guest QEMU |
| SSH 客户端 | guest 内含 `ssh`、`scp`、`dropbearkey`；公钥认证、远端命令、SCP 已真机通过 |
| 插件 | 项目地址安装、插件市场、皮肤市场、进程内包通道、预览图代理均已修复 |
| 桌面卡片 | 会话标题、状态、第 N 步、余额、四档 token 用量和点击直达已接入 |
| 浏览器自动化 | PC / 2in1 海泰扩展桥、按需拉起、任务结束自动收尾、截图、标签、网络与正文工具已接入 |
| 网页抓取 | 浏览器 UA、请求头补齐、深嵌套 HTML / frameset 纯文本兜底、CDP 文本兜底已接入 |
| 系统融合 | 快捷方式、自定义意图、A2A ArkTS 骨架、AgentCard 已落位 |
| 窗口与沉浸 | 手机底部统计栏避让、分屏旋转视口回正、平板手持窗口壳已落位 |
| 键盘终端 | 软键盘期间暂停 xterm resize 注入，连续输入/删除不再乱跳 |
| 质量控制 | 权限面、APK 面、核心补丁、QEMU、Python、卡片、浏览器、文档引用等门禁已建立 |

## 7. 本轮 `1.1.4 / +dshm.73` 的关键变化

1. DSH 上游从 `0.2.1-alpha.4` 同步到 `0.2.1-rc.2`，144 个协议端点零漂移。
2. 最低兼容面从 API 24 下探到 API 23，并为缺失目录选择能力的设备提供专属工作区兜底。
3. 修复升级后 Host 早于目录授权恢复启动导致的会话、工作区不可见竞态。
4. 新增桌面卡片、四档 token 用量、余额和点击直达会话。
5. 浏览器自动化完成 PC-only 收口并修复正文截断、错误假成功、单标签最小化确认。
6. QEMU/QGA 在后台冷启动前检查应用生命周期，guest RAM 和 TCG 预留收紧。
7. QGA 超时无条件断链，重连先同步，迟到回包不会串给下一条命令。
8. guest 增加 Dropbear SSH 客户端闭包；SSH 服务端随包但不自动启动。
9. 手机底部系统手势条不再遮挡 Web 使用统计栏。
10. 分屏 `竖屏 -> 横屏 -> 竖屏` 后右侧空白由视口回正脚本修复。
11. 软键盘弹出期间终端不再反复 `fit -> resize -> SIGWINCH`，输入预览稳定。
12. `python` 工具支持文件路径模式，越界错误回显允许根集合。

## 8. 已完成验证

| 验证 | 结果 |
|---|---|
| ArkTS 编译 | 0 error |
| 仓库 CI 门禁 | 58/58 PASS |
| 布局 fixture | 768/0 |
| 手持返回 | 40/0，含 5 条对照臂 |
| 顶栏 / 三键窗口壳 | 9/0、95/0，A-Q 对照臂通过 |
| 功能接线 | 24 个功能全部有接线 |
| 核心端侧补丁 | 236/0，30 处注入 |
| QEMU / QGA / SSH | 412/412 PASS |
| Python 工具 | 出包前 20/20 PASS；清理 `dist/core/work` 后复跑 19/0，真编译器预检按设计 skip |
| 文档引用 | 118 篇文档、220 条引用通过 |
| 权限面 | PC 恒 11 条 |
| APK 面 | 0 文件、0 目录、0 归档条目 |
| resfile 快照 | 15 件一致 |
| 手机覆盖安装 | `links=11 size=3440` 不变，核心 `.73` 启动 |
| PC 覆盖安装 | `links=10 size=3440` 不变，核心 `.73` 启动 |

证据目录：

- `dist/acceptance/20261018-bottom-safe-area/`
- `dist/acceptance/20261018-terminal-input/`
- `dist/acceptance/20261018-ssh-poc/`
- `dist/sideload/SHA256SUMS.txt`
- `dist/sideload/DSHM-beta-1.1.4-更新日志.md`

## 9. 已验证的 SSH 能力

已在手机 guest 中完成：

- Ed25519 私钥生成与公钥导出；
- 主机指纹校验和变更拒绝；
- 公钥认证；
- 远端命令执行；
- `scp` 上传，返回 `SCP_RC=0`。

证据在 `dist/acceptance/20261018-ssh-poc/`。

未完成的部分：

- 密码式 SSH 的自动化 POC 尚未收口。密码认证需要 PTY，非交互 bash 通道不能作为完整证据。
- SSH 服务端不自动启动，也不应默认开启。
- 用户的主机指纹、私钥、代理和 `known_hosts` 仍由用户自己配置。

## 10. 未完成与当前边界

| 项 | 状态 | 处理建议 |
|---|---|---|
| 平板真机最终窗口壳截图 | 未完成 | 连接平板后确认 `buttons=ok -> present=false`，并补三面截图 |
| HarmonyOS 6.1.0 / API 23 手持真机 | 未复验 | 只验证专属工作区兜底，不要尝试恢复不存在的系统目录选择能力 |
| 分屏旋转完整现场组合 | 未完整留档 | 补 `竖 -> 横 -> 竖`、左右分屏和不同平板尺寸证据 |
| A2A 端到端 | 等平台审核 | 平台审核和应用上线后再联调，不在本地伪造通过 |
| SSH 密码 / 键盘交互 | 未自动化收口 | 需要 PTY 驱动和交互式服务端测试 |
| 长扫描超过 60 秒转后台 | 上游调度策略 | 当前不作为本地 bug 修改；需要时单独评估任务恢复策略 |
| APMS 崩溃趋势 | 仍需持续观察 | 新版发布后按版本过滤 QEMU、libnode、AppFreeze、Leak |
| 最新 AGC `.app` | 已完成 | 见 `dist/release-test/DSHM-1.1.4-PC-dshclient-release-signed.app` |

## 11. 后续展望与可行性

### P0：发布前与内测必做

1. 补平板真机和 API 23 真机验收。
2. 补分屏旋转组合证据。
3. 新版 Beta 发布后观察 APMS 的 QEMU、AppFreeze、Leak 趋势。
4. 保持 PC 权限面恒 11 条、APK 面 0 条、签名和 el2 数据边界不变。

### P1：稳定性和体验

1. 为 SSH 密码 / 键盘交互补 PTY 自动化 POC。
2. 给浏览器自动化补失败重试、反爬错误分类和长时间任务恢复。
3. 给终端冷启动、QGA 往返、内存峰值和热稳定性建长期样本。
4. 平板 UI 继续向 PC 形态对齐，但必须有真机读数后再改断点。
5. 把市场、卡片、浏览器的关键路径加入定期回归。

### P2：API 26 与系统融合

1. A2A、AgentCard 与小艺开放平台联调，前提是平台审核通过。
2. 系统入口、意图框架和桌面卡片深化。
3. 评估 API 26 的窗口、容器宽度断点和系统材质能力。
4. 评估安全的升级检查与分发链路，但不做会触碰 el2 数据的静默更新。

### 可行但不建议现在做

| 方案 | 结论 |
|---|---|
| 在 11 条之外再加权限 | 禁止。任何表外权限都会破坏 ACL/安装边界 |
| 把终端重新改回宿主 ELF / shell | 不建议。当前 8 权限域下不可行，guest VM 已是稳定路径 |
| 在后台高频率静默启动 Core 或 VM | 不建议。会重新引入内存和 QEMU 原生崩溃风险 |
| 用卸载作为升级手段 | 禁止。不可逆破坏 el2 用户数据 |
| 直接把 Beta 工作区同步到正式区 | 需用户明确授权后单独执行，不在本次交接中自动做 |

## 12. 构建、打包与覆盖安装

前置环境：

- DevEco Studio / Command Line Tools，包含 `hvigorw.js`、`ohpm`、SDK；
- JDK（当前环境使用 Harmonybrew OpenJDK；DevEco 自带 JBR 也可）；
- Node.js，用于仓库检查和打包脚本；
- Python 3，用于工具链归档签名与品牌资源构建；
- release 签名物料位于 `.certs/release1012/`（gitignored）。

常用流程：

```powershell
# 日常：DevEco Studio 选择 entry:default，直接点击 Run

# 1. 重新放置随包 Host 与核心资源
node tools/pack-core.mjs --skip-install --place-in-app
node tools/place-host-app.mjs

# 2. 重建工具链归档并自签名
node tools/place-toolchain.mjs

# 3. 构建 AGC 正式 APP
hvigorw assembleApp --mode project -p product=default -p buildMode=release --no-daemon
```

正式 `.app` 走 AGC。日常调试由 DevEco Studio Run 完成，不手工侧载。
调试签名与 App ID/UDID 的一次性交接见 `docs/216`。

核心升级顺序：

1. 在 `hostcore/core-recipe.json` 确定上游版本和 `coreVersion`。
2. 只读评估契约漂移、依赖闭包和自带插件 peer 版本。
3. 执行 `pack-core`，保留旧核心 zip 和 manifest 作为回退。
4. 跑核心补丁、入口、undici、插件、VM 和权限门禁。
5. 构建 PC release `.app`，校验 bundle / App ID / Profile / ACL。
6. 上传 AGC 应用 `6917614360926110054`。

## 13. 数据、签名和回滚

- 不删除 `.certs/`、`signing/` 与仓库外签名备份。
- 不删除 `dist/release-test`、`dist/acceptance`、`dist/backup`、`dist/node`、`dist/core/*.zip` 和 manifest。
- 不删除设备 `el2`、会话、工作区、插件和凭据。
- 代码回滚用版本控制或同身份的替换包，不用卸载。
- 核心回滚保留旧 zip、manifest 和 `dsh/cores` 中已有版本，不做破坏性清理。

## 14. 接手验收清单

1. 读 `AGENTS.md` 的物理门禁、权限面、真机数据保全三节。
2. 执行 `git status --short`，确认现有脏树，不擅自回滚用户改动。
3. 执行权限、APK、文档、接线、resfile 和核心补丁门禁。
4. 核对 `hostcore/core-recipe.json` 与 HAP 内核心版本一致。
5. 核对 HAP 的 bundle、版本、min/target API、权限数和 APK 条目数。
6. 在 DevEco Studio 选择设备后直接 Run；若确需 CLI 覆盖安装，先记录 el2 数据指纹。
7. PC/2in1 验证启动、会话、工作区、插件、原生终端、卡片、浏览器桥。
8. 平板和 API 23 设备单独记录。
10. 所有结论写入 `dist/acceptance/` 或新的编号文档，不口头宣布通过。

## 15. 文档导航

| 文档 | 用途 |
|---|---|
| `AGENTS.md` | 工作约束、门禁、真机数据、权限铁律 |
| `docs/README.md` | 当前文档导航与历史状态 |
| `docs/216-DevEco-Studio正式调试签名交接（解除原开发端依赖）.md` | 在鸿蒙 PC 的 DevEco Studio 中直接 Run，以及一次性完成调试签名主权迁移 |
| `docs/189-历史文档合并与移交索引（DSHM-beta-1.1.4-core+dshm.73）.md` | 旧结论合并表、归档策略、本次清理记录 |
| `docs/183-API23工作区选择兼容（FolderSelection能力预检与专属目录兜底）.md` | API 23 安装与工作区兜底 |
| `docs/184-DSH上游同步0.2.1-rc.2（+dshm.70）.md` | DSH 上游同步与核心 `.70` |
| `docs/186-新增功能代码审核与双端回归（核心+dshm.72）.md` | 新增功能代码审核与双端回归 |
| `docs/187-手机端底部使用统计与系统手势条避让（Web内容框不再下扩）.md` | 手机底部安全区与使用统计避让 |
| `docs/188-内测双报告收口与guest SSH客户端（QGA失步复位·分屏视口回正）.md` | QGA、SSH、键盘和分屏视口修复 |
| `docs/80-真机更新与数据保全.md` | 更新、签名恢复和数据保全事故记录 |
| `docs/70-鸿蒙移植踩坑与修复总览.md` | 按主题查历史坑 |
| `docs/90-DSH鸿蒙原生实现全流程.md` | 端到端实现流程 |

历史文档只用于追溯，不作为当前事实。需要判断“现在怎么样”时，回到源码、
配置、门禁和本交接文档。

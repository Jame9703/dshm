<div align="center">

<img src="docs/brand/app-icon-512.png" alt="DSHM" width="112" />

# DSHM

**在 HarmonyOS 上自足运行 DeepSeek Harness 的应用**

</div>

DSHM 把 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（dsh）的**运行本体**装进一个鸿蒙应用：HAP 内自带 Node 运行时与 dsh 核心树，核心在本机 `127.0.0.1` 上起 Host，客户端默认通过 ArkWeb 加载本地 Host 的 WebUI。

**它不是 PC 上 dsh 的遥控器**，也不需要在电脑上常驻任何服务：装上即用，数据只在本机应用沙箱内。

应用版本见 [AppScope/app.json5](AppScope/app.json5)，端侧核心版本见 [hostcore/core-recipe.json](hostcore/core-recipe.json)。

支持 HarmonyOS 手机 / 折叠屏 / 平板 / 2in1。交付面只有两个：**`entry` = 平板 + 2in1**（PC / Edge / Pro Max 共用）、**`phone` = 手机**；折叠屏按系统上报的形态进入对应档。

> **这是一次平台移植**：把官方面向桌面（Electron）的运行时，搬到 OpenHarmony arm64 上自足运行。
> **两条根本约束**决定了后面几乎所有设计：`jitless ⇒ WebAssembly === undefined`，
> 以及 **execve 受签名域管辖 ⇒ 所有端侧原生二进制必须构建期自签名**。

---

## 桌面 ArkUI 工作台

在桌面分档的主窗口，通过左上角 `…` → **ArkUI 实验工作台** 启用。工作台连接当前本机宿主。

| 功能 | ArkUI 入口 |
|---|---|
| 工作区与会话 | 侧栏可按工作区、工作区树或单列表显示。拖动工作区标题可调整宿主顺序，树形视图支持同级排序。可从工作区标题直接新建会话。支持最近更新和手动排序，拖动时在置顶或普通区段内移动。视图、排序及归档筛选会保存。工作区会话支持分批展开，待审批、待回答、计划待审、子智能体运行和未读会话会自动展开到对应位置。会话行显示待处理状态或最近更新时间。支持搜索、添加和管理工作区，以及会话新建、改名、置顶、已读标记、复制 Session ID、归档和恢复 |
| 对话 | 支持历史、发送和停止、模型与推理等级、文件附件、工具审批和问答。支持权限预设的会话会显示访问模式菜单 |
| 引用 | 在输入框输入 `@` 搜索工作区文件和会话。目录可直接引用，也可用 Tab 或右侧箭头展开。选中的引用在草稿中显示为可整枚选中和删除的行内卡片，切换会话时随各自草稿保留。发送后可点击文件引用预览，右键或长按打开沉浸光感菜单。文件面板也可将引用插入草稿 |
| 计划模式 | 可从输入区切换模式或输入 `/plan`，在会话中审阅计划并要求修改或同意执行，也可在右侧查看计划全文 |
| 工具过程与后台任务 | 在会话中展开工具执行过程、参数和结果。会话头部的后台任务浮层支持跟随输出和确认停止 |
| 斜杠命令与会话日志 | 在输入框输入 `/` 打开指令浮层。模型和权限使用原生选择浮层。会话标题旁的菜单支持复制 Markdown 和下载日志，ZIP 导出通过原生弹窗提示进度并使用系统文件选择器 |
| 长期目标 | 通过 `/goal` 设置目标。输入区上方显示宿主状态，可就地编辑、暂停、恢复或清除 |
| 反馈 | 回合尾部可复制回复、评价或撤回评价。会话菜单和不带正文的 `/feedback` 打开原生反馈弹窗 |
| 会话分叉 | 从回复末尾分叉并打开新会话，或从侧栏分叉最近的已完成回合。分支会话标注继承的历史 |
| 会话归档 | 侧栏可筛选及恢复已归档会话，归档提示支持撤销。宿主报告运行中的工作时，通过居中弹窗列出工作并确认停止 |
| 待发送队列 | 正在回复时可继续发送消息。输入区上方支持查看、编辑、删除排队消息或将消息插入当前回合，沿用宿主的 Enter 发送设置 |
| 图片附件 | 可多选、拖放文件，或在输入框用 Ctrl+V 粘贴剪贴板图片和文件。草稿、队列和会话历史显示缩略图，点击可打开原生图片预览并缩放。GIF 在草稿中原样播放 |
| 设置 | 打开原生设置页，读取宿主设置、模型、凭据状态、技能、预设和设备信息 |
| 快捷键 | 在通用设置或通过 `Ctrl+/` 打开沉浸光感快捷键弹窗。可搜索、录入、移除和恢复键位。设置后在工作台触发会话、侧栏、工作区文件及终端等操作 |
| 账号 | 在居中原生弹窗发起或取消 DeepSeek 登录，经系统浏览器授权。也可从弹窗进入模型设置添加 API Key。登录后在左侧栏底部显示账号通知卡片，可打开账号弹窗或关闭通知 |
| 会话终端 | 在会话右侧打开宿主 PTY，支持新建、切换、改名和关闭终端，也可选择 Shell |
| 工作区文件 | 在会话右侧展开目录、搜索文件、预览文本和 Markdown、用系统预览打开文档，或把文件添加到输入区 |
| 浏览器 | 在右侧栏新建浏览器标签页。支持网址输入、前进、后退、刷新、转到系统浏览器和恢复上次打开的页面。通用设置可选择对话链接在侧栏或系统浏览器打开 |
| 子智能体 | 在会话标题栏用沉浸光感弹窗查看父子会话树及运行状态。可返回父会话、打开同级或嵌套子会话、续聊可继续的子智能体。一次性子智能体提供只读记录。子会话树显示累计用量和活跃耗时。子会话树和普通会话菜单可将会话打开到右栏，也可将普通会话直接拖入指定右栏。草稿与附件按会话保存 |
| 工作流运行 | 在会话中展开工作流、阶段和成员，查看运行、完成、失败、取消和中断状态，并打开正在运行的成员会话。支持历史记录与实时更新 |
| 右侧栏 | 可从侧栏会话菜单选择「在右侧打开」，与主区的当前会话并排查看。文件、终端、独立文件预览、计划和改动审阅可并存。拖动标签可排序、分栏或浮动，浮动面板可移动、调整大小并收回到右侧栏。重启后会话恢复可重新读取的标签、分屏及浮动布局，包括历史计划和宿主记录的改动 |
| 交付物与改动 | 在回合末尾打开交付文件，或在右侧审阅宿主记录的本轮改动。没有回合摘要时可以查看工具记录的片段。支持文件切换、单栏和双栏对比、长行换行与打开完整文件 |
| 插件 | 查看插件包和运行条目，管理宿主允许修改的条目，按包名、仓库或市场索引安装。在配置页编辑宿主提供的网页搜索与获取、Agent 循环、Shell 及子智能体设置。子智能体配置包含委派深度、并行数量和可选模型授权 |
| 自动化任务 | 新建、编辑、暂停、恢复、运行和删除任务，查看投递历史 |

左上角和侧栏底部的 **WebUI 兼容模式** 可打开原有 ArkWeb 界面。会话中的 WebUI 入口会传递当前会话，插件和自动化任务也可以跳转到对应的 WebUI 页面。依赖浏览器的插件界面继续由 ArkWeb 加载。

桌面工作台的菜单与选择器在支持的设备上使用系统沉浸光感材质。

## 为什么需要它：官方没有鸿蒙端

上游 DeepSeek Harness 面向的是**桌面端（Windows / macOS，Electron）与 CLI**。它的运行前提有两条，在鸿蒙应用沙箱里**一条都不成立**：

1. 系统里有可执行的 Node 运行时；
2. 进程能直接 `execve` 任意二进制。

本仓库做的事，就是在官方未覆盖的平台上把这两条前提**逐条补出来**，并提供一个原生宿主：

| 官方形态依赖的前提 | 鸿蒙端侧现状 | 本仓库的补法 |
|---|---|---|
| 系统提供 Node 运行时 | 沙箱内无 Node，且只能执行**自己签名域内**的原生二进制 | 运行时与原生库随包分发（Node、koffi、node-pty、（已移除：语音走系统 Core Speech Kit）、libvips 等），构建期自签名；Host 跑在应用进程内，只监听 `127.0.0.1` |
| 上游直接 `import('undici')` 可用 | 端侧 `jitless ⇒ WebAssembly === undefined`，而 undici 的 HTTP 解析器是 WASM | 增加 `undici` 模块名解析钩子与全局 `fetch` 垫片，**不改上游源码、不改核心树**，由 `tools/check-web-fetch-jitless.mjs` 守着（自带对照实验） |
| 桌面工具链随手可用 | 沙箱里没有可执行文件 | git、Python 3.12、busybox、ripgrep 随包分发并自签名，启动时逐项 `exec` 探测 |
| Electron 提供窗口 / 托盘 / 文件选择器 | 平台是 ArkUI | 由 ArkUI 宿主提供窗口、菜单、托盘、系统文件选择器、剪贴板、通知与多形态布局 |
| 单机单形态 | 手机、折叠屏、平板、2in1 的设备类型不同 | 两个 entry 交付面：`entry`（tablet + 2in1）、`phone`（phone），同一 `.app` 内按设备类型分发；布局形态另由断点判定 |

具体落成四件事：

- **运行时不依赖系统，随包分发。** HAP 内自带 Node 运行时与全部原生库，构建期完成自签名以进入应用签名域。当前 AGC 合并 .app 约 566 MB（2026-11-06 瘦身后；旧读数 417 MiB 已作废），换来"装上就能跑，不必先配环境"。
- **核心树可切换、可回滚。** dsh 核心树以归档形式随包分发，首次启动解包进应用数据目录下的版本仓库（`dsh/cores/<version>`），通过激活事务切换版本，失败可回滚 ⇒ **升级上游 = 换一个核心归档**，App 代码不动。
- **共用宿主，保留两套界面。** 桌面 ArkUI 工作台和官方 WebUI 读取同一宿主。ArkUI 使用鸿蒙的语义色与系统符号，WebUI 由 ArkWeb 加载。
- **上架友好、数据保全优先。** 权限面固定为 **entry 19 条 / phone 9 条**（含 8 条已审批 ACL：`ALLOW_EXTERNAL_NATIVE_CODE`、`FILE_ACCESS_PERSIST`、`CUSTOM_SANDBOX`、`READ_PASTEBOARD`、`ACCESS_USER_FULL_DISK` 与三个目录读写；2026-11-11 全盘权限获批），逐项见 `entry/src/main/module.json5` 与 `phone/src/main/module.json5`；**不接受**任何未获批的受限条目（旧的「恒 8 条」口径已作废，按它删条目会删掉 `CUSTOM_SANDBOX` 导致工具/终端/工作区全废）。装机一律 `hdc install -r` 覆盖安装，应用数据原地保留（详见下文「真机数据保全」）。

端侧与官方的逐项对照（哪些对齐、哪些存在边界）由 `tools/check-parity.mjs` 强制维护。

### 已知边界

- **WASM 缺席是全局前提。** 凡是上游直接 `import('undici')` 的功能都必须走垫片；新接入的上游功能若未覆盖，在端侧会直接失败。垫片覆盖由门禁守住，不靠自觉。
- **API 23 手持档不能选择任意系统目录。** HarmonyOS 6.1.0 没有 `FolderSelection`，应用会退到 `Download/<包名>` 专属工作区；2in1 和 API 26 手持档不受影响。
- **浏览器自动化只在 PC / 2in1 提供。** 移动端没有海泰扩展能力，不注册 `browser_*` 工具。
- **平板与 API 23 仍需真机复验。** 手机和 PC 已覆盖安装验证，不能把两端读数替代缺失设备。
- **A2A 等待平台审核。** 端侧骨架和 AgentCard 已落位，真实协议联调必须等开放平台和应用上线条件满足。
- **QEMU 原生崩溃仍需观察。** 后台冷启动闸门和资源预留已收紧，但 APMS 趋势仍要在新版发布后持续跟踪。

## 能力

| 领域 | 说明 |
|---|---|
| **本地核心** | 内置 Node 运行时（自建、`jitless`）与 dsh 核心树；Host 仅监听 `127.0.0.1`，随应用生命周期起停 |
| **对话与轨迹** | 对话视图（问答，思考过程折叠在回答上方）与轨迹视图（工具调用、子代理、目标/任务、交付物、错误）分开呈现 |
| **工作区** | 工作区为组、会话挂在组下；可在设备上选择文件夹作为工作区（系统文件夹选择器），并在其中浏览文件 |
| **模型与密钥** | 按提供方管理：API 密钥（只写）、`baseURL` 与模型目录；默认模型与推理强度可选 |
| **插件** | 查看随包插件清单与运行阶段；按行启用/禁用，并可恢复部署默认 |
| **核心版本** | 同时安装多个核心版本，一键**切换 / 回滚**（停旧起新，逐版本校验后激活） |
| **多语言** | 界面文案跟随系统语言，默认中文 |
| **上架友好** | 全部按 `jitless` 运行；权限面 **entry 19 / phone 9**（8 条已审批 ACL + 免申请条目），由 `node tools/check-permission-surface.mjs` **两侧逐条**强制（含顺序与 reason 字符串） |

## 架构

```text
┌─ DSHM（一个 HAP）──────────────────────────────────────────────┐
│  ArkUI 原生页面（客户端）                                       │
│        │  HTTP /api/*        WebSocket /api/remote.mux          │
│        ▼                                                        │
│  端侧 dsh Host（Node 运行时运行在**本应用进程内**）              │
│        │  DSH_HOME = <应用沙箱>/dsh/home（跨版本共享的唯一数据）  │
│        ▼                                                        │
│  核心版本仓库（多个版本可并存，切换 = 停旧 + 起新 + 校验）        │
└─────────────────────────────────────────────────────────────────┘
```

同进程带来的是**安全语义的简化**：客户端与 Host 走回环，不需要把服务暴露到局域网，也不需要跨设备转发。

### 端侧运行时的硬约束：`jitless` ⇒ 没有 WASM

不申请 JIT 权限意味着 Host 全程以 `--jitless` 运行，而 V8 的 `--jitless` 与 `--expose_wasm` **互斥**
（启动即打印 `disabling flag --expose_wasm`），因此端侧 `typeof WebAssembly === 'undefined'`——这是恒定的，
不是配置问题。由此推出一条对上游代码的判据：

> **凡是上游直接 `import('undici')` 的功能，在端侧都会失败**，因为 undici 的 HTTP 解析器是 WASM
> （`lib/llhttp/llhttp-wasm.js`）。

已实测证实的一个实例：`dsh-web-fetch-http` 不用全局 `fetch`，而是 `await import('undici')` 自建 `Agent`
再传 `dispatcher`，于是 `web_fetch` 打不开任何网页和 IP，而走本仓纯 JS `node:http` 垫片的 `web_search` 照常工作。
同一核心树、同一个本地 HTTP 服务下，只有 `--jitless` 一个变量就能复现两组结果（有 WASM → 200；
无 WASM → `fetch failed / WebAssembly is not defined`）。

因此新增/升级核心版本时，除了跑既有门禁，还要**搜一遍核心树里对 `undici` 的直接依赖**，并把垫片覆盖率当作一项验收项。

对付它需要**两层**，缺一层就会出现"Host 起来了、模型也能回话，但某个工具静默坏掉"：

| 层 | 做什么 | 不做的后果 |
|---|---|---|
| 全局 fetch 垫片（`fetch-shim.js`） | 用 `node:http/https`（原生 llhttp）重写 `fetch/Request/Response/Headers/FormData` | 调模型就走不通（dsh 调模型就是用 fetch） |
| `undici` **模块名**解析钩子（`undici-shim.mjs` + `undici-loader.mjs`） | 让上游的 `await import("undici")` 拿到同一个垫片，并把 `dispatcher` 翻译成 `lookup` | **`web_fetch` 打不开任何网页**（`web_search` 却正常，因为后者走第一层） |

第二层由 `main.js` 的 `installUndiciNameHook()` 在 `WebAssembly` 不可用时注册；**不改上游源码、不改核心树**。
这条路径由 `tools/check-web-fetch-jitless.mjs` 守着——它自带对照实验：不注册钩子时必须失败（并给出
WASM 因果证据），注册后必须全过，且**跨源跳转仍须被拒**。

## 构建

前置：DevEco Command Line Tools（含 hvigor / ohpm / codelinter / SDK）、JDK 17、Node.js
（仅用于仓库内的构建与检查脚本）、**Python 3**（`tools/sign-tar-elf.py` 用它的 `tarfile`
改写工具链归档——Windows 上只有它能在保住归档内 symlink 的前提下改字节；缺失时
`place-toolchain` 会告警跳过签名，归档仍可用，只是端侧 `git`/`python3.12` 真身继续被执行策略拒绝）。

> **SDK 版本口径**：`compatibleSdkVersion` 为 **`6.1.0(23)`**（2026-10-17 下探）；
> `targetSdkVersion` 为 **`26.0.0`**（API 26 档不带括号）⇒ 产物 minAPIVersion 60100023 / targetAPIVersion 260000026。
> 代价是启用 API 26 的 3 条 ArkUI 行为变更（弹层沉浸材质默认开 / 按钮热区 28→32vp / 内置文本换行优化）；沉浸光感材质**已接入**（`module.json5` 的 `ohos.arkui.UIMaterial.state = enable`，`HarmonyMaterial.IMMERSIVE_ENABLED = true`，2026-10-11 拍板；设备 API < 26 时被平台忽略），另已接入带执行结果的窗口朝向设置。

**不入库的产物（新克隆必须先备齐，否则编不过）**：

| 产物 | 路径 | 说明 |
|---|---|---|
| Node 头文件 | `entry/src/main/cpp/node-headers/` | 编 `libdshhost` 只需要它（`libnode` **不参与链接**） |
| 原生库 | `entry/libs/<abi>/` | 运行期需要（含 `libnode.so.137`）；也是"编不编 koffi/flock"的门 |
| git 兼容垫片 | `entry/libs/arm64-v8a/libdshm-gitcompat.so` | 由 CMake 从 `entry/src/main/cpp/gitcompat.c`（**源码在库里**）编出；git 子进程类命令的 `LD_PRELOAD` 垫片 |
| 核心包 | `entry/src/main/resources/resfile/*.zip` | 首启解包出端侧核心树 |
| 工具链归档 | `entry/src/main/resources/resfile/toolchain/{python,git}/` | 由 `node tools/place-toolchain.mjs` 从 `third_party/` 放置并**自签名**（端侧 execve 只放行带 `.codesign` 的 ELF） |
| 入口脚本 | `entry/src/main/resources/resfile/resources/app/` | 由 `node tools/place-host-app.mjs` 从 `hostcore/app/` 生成 |
| 顶栏按钮 SVG | `entry/src/main/resources/base/media/sidebar_toggle.svg` | 顶栏左上角侧栏开关图标（`Image.fillColor` 按主题着色）。同目录的 `fish_logo.svg`（官方鲸鱼，由 `node tools/gen-fish-logo.mjs` 逐字节复制核心树 primitives 的 path 生成）自 2026-10-10 顶栏改侧栏按钮后不再被运行时引用，保留归档 |

```powershell
# 1) 打完整体（HAP + 原生库 + 内置核心资源）
# 先由 tools/lib/deveco-home.ps1 解析 DevEco 安装根，再调用当前 hvigorw。
# 日常开发推荐直接跑 .\tools\update-device.ps1（仅 Windows 开发端）。本机无 hdc 服务端，装机/UI 验证做不了，交付证据上限 = 离线门禁 + 包结构。
.\tools\update-device.ps1

# 2) 需要重新打包核心树时（素材来自 dist/core/，产物落到应用资源目录）
node tools/pack-core.mjs --skip-install --place-in-app
node tools/place-host-app.mjs

# 2b) 需要重建工具链归档时（放置 + 自签名；会就地改写 resfile/toolchain/ 下的归档）
node tools/place-toolchain.mjs

# 2c) 重建鲸鱼 SVG 功能资源（从核心树的官方 primitives 包逐字节复制路径；内含
#     "真实包围盒 == 官方 viewBox" 与"落盘后仍与官方一致"两条自检，失败即退出）
node tools/gen-fish-logo.mjs

# 2d) 刷新 README 展示图（由 AppScope 的 background + foreground 合成 512²）
python3 -c "from PIL import Image as I;bg=I.open('AppScope/resources/base/media/background.png').convert('RGBA');fg=I.open('AppScope/resources/base/media/foreground.png').convert('RGBA');I.alpha_composite(bg,fg).convert('RGB').resize((512,512),I.LANCZOS).save('docs/brand/app-icon-512.png',optimize=True)"

# 3) 使用已签名 HAP 覆盖安装（不要 uninstall）
hdc install -r <hap>（仅 Windows 开发端；本机不可执行）
```

## 设计体系：Web 语义 + HarmonyOS 原生表达

支持沉浸光感的桌面主窗口会用 ArkUI 显示账号菜单和会话、工作区等位置的简单「更多」菜单。菜单项沿用网页原有动作，设备不支持材质或菜单包含子菜单等复杂控件时会显示网页菜单。

桌面主窗口的模式、模型和工作区下拉选择器由 ArkUI 显示，保留选中态、目录搜索和添加工作区。模型列表与推理等级在原生面板内切换，需要插件自定义界面的模型选项沿用插件界面。
模式选择沿用系统菜单的沉浸光感材质，并显示各模式的说明。
模型、推理等级和工作区的选择面板使用 ArkUI 沉浸光感底板，切换二级页时沿用同一个弹窗。
桌面工作台的动作菜单使用按钮位置作为原生弹出锚点。侧栏“更多”从按钮下方弹出，左下角账号菜单从按钮上方弹出。触控按住按钮时显示圆角底色，键盘操作仍显示焦点提示。

**产品语义对齐官方 Web，视觉与交互用 HarmonyOS 原生表达**——不是把 Web 的 CSS 机械翻译成 ArkUI：

| 层 | 落点 | 作用 |
|---|---|---|
| 尺度原语 | `appstate/ui/Tokens.ets` | `Sp` / `Radius` / `Border` / `Fs` / `Sz` / `Dur`（"有哪些档位"） |
| 语义令牌 | `appstate/ui/HarmonyTheme.ets` | 角色 → 系统语义资源（`sys.color.*`）+ 排版成套角色 + 层级/动效/触控；**`WEB_TOKEN_MAP`** 逐条映射官方 `--dsw-*` |
| 原生原语 | `entry/src/main/ets/view/NativePrimitives.ets` | `NativeChip` / `NativeCard` / `NativeButton` / `NativeActionBar` / `NativeSectionTitle` + Sheet 参数助手 |

**四条已经定下来的规则**（都是踩过或查证后写的，不是偏好）：

1. **浮层用系统形态**：半模态一律 `bindSheet`（`NativePrimitives.harmonySheetOptions` 统一参数），
   不再手写"整屏 Column + 自制遮罩"。原因：原生 Sheet 自带"非全屏、底层父视图可见"、拖拽关闭、
   遮罩与键盘避让——手写那套要逐个补回来，且必然补不全。
   > 注意 `bindSheet` 是**组件属性**，同一节点只能绑一个。本项目因此用**单一浮层宿主**：
   > 全应用只在根节点挂一次 `bindSheet`，由 `sheetKind()`（**从既有状态派生**，不另立字段）
   > 决定显示哪个浮层、`closeSheet()` 一处复位。这样结构上**不可能同时开出两个浮层**，
   > 复位逻辑也只写一次。
2. **遮罩交给系统**：不再手写 `rgba(...)` 遮罩（35% 黑在深色主题下观感就是错的），全部由原生 Sheet 提供。
3. **图标用系统符号**：`SymbolGlyph` 只支持系统预置资源，**不引入 Web SVG**（这条是 API 约束，不是偏好）。
4. **裸值只许变少**：`tools/check-design-tokens.mjs` 是棘轮门禁，管的是
   `fontSize`/圆角/描边/颜色字面量（含 `rgb()/rgba()/hsl()`——首版漏检过，已补）。

## 仓库结构

| 目录 | 作用 |
|---|---|
| `entry/` | 鸿蒙应用入口：ArkUI 页面与视图（含**原生原语** `view/NativePrimitives.ets`）、原生桥（`libdshhost`）、随包资源（核心包与原生库） |
| `hostcore/` | 端侧 Host 的入口脚本与 profile（`cordis.patch.yml`）、`fetch` 垫片，以及为绕开"端侧无 WASM"而做的 `undici` 模块名解析钩子 |
| `hostruntime/` | 核心版本仓库、激活事务、运行时载体（`RuntimePort` → `NodeRuntime`） |
| `appstate/` | 客户端状态中枢与投影（会话、轨迹、工作区、设置、凭据、插件、核心视图）。**纯逻辑层**（不 import ArkUI，可在本机直接测）：设计令牌与布局/导航决策（`ui/Tokens`、`ui/HarmonyTheme`、`ui/Breakpoints`、`ui/LayoutController`、`ui/NavigationController`）、回合与时间线、贴底跟随、输入模态（策略与事实）、工具呈现与改动对照。由 `tools/check-layout-fixtures.mjs` 逐条断言 |
| `platform/` | 系统能力封装（文件选择、剪贴板、通知、窗口记忆等） |
| `dshcompat/` | 与上游协议有关的**全部**事实：端点、参数形状、事件类型与投影键 |
| `tools/` | 构建与检查脚本（核心打包、依赖闭包、上架红线、协议往返、死按钮扫描等） |
| `docs/` | 品牌资源（`docs/brand/`），README 顶部图标即 `docs/brand/app-icon-512.png` |

## 设计原则

1. **不 fork、不魔改 dsh**：端侧差异只通过 dsh 自己的组合面（profile / `cordis.patch.yml` / bundle）表达。
2. **不申请 JIT**：需要它作前提的方案一律不进入选型（这是 `--jitless` 的由来）。当前权限面 entry 19 / phone 9，其中 8 条是已审批 ACL；**不新增未获批的受限条目**（声明了也拿不到，反而让整包按 `PERMISSION_ACL_RULE` 拒装）。
3. **界面不撒谎**：失败必须给出下一步；空态说明"可以做什么"；不可用的动作把原因写在旁边，而不是给一个点了没反应的入口。
4. **上游知识只出现在 `dshcompat`**：字段名、端点形状、事件类型集中一处，升级上游时改一个地方。
5. **产品语义跟 Web，视觉与交互用鸿蒙原生**：信息架构与行为对齐官方 Web（对等矩阵逐行登记），
   但视觉不用 Web CSS 的像素级翻译——用系统语义色、系统符号、原生控件（Sheet/菜单）、触控目标与多窗口语义表达。
   这样官方主题更新时不需要重做整套界面。

## 快速开始

### 只想装上用

当前 Beta 交付件在 `dist/beta/<时间戳>/`（`node tools/build-beta.mjs --combined-app` 产出，含 `SHA256SUMS`）：

```text
DSHM-beta-<version>-<versionCode>-combined-debug.app
```

然后覆盖安装：

```powershell
hdc install -r <当前交付件>（仅 Windows 开发端；本机不可执行）
```

首次启动会解包核心树，期间会显示启动/初始化状态。
下载后请用同目录的 `SHA256SUMS.txt` 校验。

> 该件是 Beta 调试签名侧载包，只用于内测和真机覆盖安装；正式分发走 AGC 发布签名链路。

### 想从源码构建

见上面的「构建」一节。注意**本仓库不含**原生库、核心包、工具链归档、入口脚本、Node 头文件与签名材料
（判据见「不入库的产物」表）—— 它们是构建产物或机器绑定材料，不入库。

## 真机数据保全（动手前务必读）

**绝对不要**执行 `hdc uninstall` / `bm uninstall`，或任何删除 `el2` 下用户数据的命令。
真机 `el2`（`files/dsh/home`）里的**会话 / 插件 / 工作区没有任何可用备份通道**
（`hdc` 读不到、`smode` 被拒、`run-as` 不存在），删掉不可恢复。

装机一律用**覆盖安装** —— 它只换 `el1`（代码与资源），不动 `el2`（用户数据）：

```bash
hdc install -r <hap>
```

判据：这条命令会不会碰 `el2`？会，就是禁止的。

## 许可

见 [`LICENSE`](LICENSE) 与 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。

本项目是**移植**：把官方面向桌面的 dsh 运行时搬到鸿蒙。`dsh` / DeepSeek Harness 的商标与上游代码版权归其各自所有者，
MIT 许可只授予代码权利，不授予商标、Logo、官方背书或合作关系。DSHM 是独立客户端，
用户可见品牌使用 DSHM 自有标识；上游版权和第三方许可见随包声明。

## 赞赏支持

<table>
  <tr>
    <td align="center"><img src="docs/sponsor/wechat.jpg" alt="微信赞赏码" width="320"><br><sub>微信</sub></td>
    <td align="center"><img src="docs/sponsor/alipay.jpg" alt="支付宝赞赏码" width="320"><br><sub>支付宝</sub></td>
  </tr>
</table>

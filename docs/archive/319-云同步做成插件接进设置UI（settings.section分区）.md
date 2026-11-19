# 319 · 云同步做成插件接进设置 UI（官方 `settings.section` 分区）

> 日期：2026-10-30 ｜ 状态：**已实施并出包**（本机门禁 + 产物取证全绿；真机/云端验收待你在设备上跑）
>
> 用户口径：「阅读当前项目，把云服务的功能做成插件接入到设置 UI 里面去，
> 先看清楚就开动，做完自己测试有没有生效，直到它功能正常为止」。
>
> 前序：[`317`](317-云同步入口内置官方设置（三端统一）.md)（DOM 注入入口）、
> [`318`](318-手机端注入修复与面板UI对齐官方设置.md)（`MutationObserver` 兜重渲染），
> 以及 [`313`](313-云同步生产功能规划.md) / [`314`](314-云同步生产落地（施工与验收报告）.md)（同步能力本身）。

---

## 0. 一页结论

| 项 | 结论 |
|---|---|
| 入口形态 | **官方设置面板的一个分区**（`settings.section` 槽位注册），由**官方 React** 渲染，与「通用设置 / 内置插件」完全同构 |
| 为什么不再注 DOM | `318` §7 已经写明边界：注入项不参与官方键盘焦点环与分区切换；这里按那条结论**做完** |
| 功能面 | 账号（登录/退出）、云服务状态、同步开关、上传、拉取并导入、三段进度、内容清单、插件恢复入口 |
| 上一版为何没生效 | **构建真正卡在四个地方**（不只是"代码没写完"）：插件没进暂存核心树、profile 没那一行、`pack-core` 版本判据把复用完死、ArkTS 桥只有只读状态。逐条见 §2 |
| 本机能测到哪 | 官方设置骨架里**真跑**出「云同步」分区、逐动作回调、产物逐字节取证（§5）；**真机/云端双端同步**只有设备能验（§7） |

---

## 1. 插件做成什么样

```text
hostcore/plugins/dshm-cloud-sync/
  package.json          dsh.client = { platform: web } + exports["./client"]
  cordis.patch.yml      宿主行（profile 里 also 有一行 insert，见 §2.3）
  lib/index.js          宿主半边（空 apply；ESM 导出 apply + name）
  src/client.src.js     浏览器半边**源码**（可读、可测）
  lib/client.js         由 tools/gen-cloud-sync-client.mjs 生成的模块（勿手改）
```

### 1.1 为什么"生成"而不是手写 `lib/client.js`

dsh 的客户端模块是浏览器侧 CJS 表：`window.__ModuleLoader__.load({id, factory})`，
`factory(require)` 的返回值才是模块导出。2026-10-30 真机那次事故就是手写时用了
`exports.apply = apply`（CJS 写法），而包是 `"type": "module"`，
`exports` 只是未定义变量 ⇒ 赋值静默失败 ⇒ **材料化得到空模块** ⇒ cordis 拿不到 `apply`
⇒ 插件永不构造 ⇒ 设置里永远不出现。全链路静默，没有任何报错。

现在外层包装由 `tools/gen-cloud-sync-client.mjs` 统一写，并在生成后**真材料化一次**
断言导出 `apply` / `inject`；`--check` 模式用于门禁（源码改了没重新生成 ⇒ 判红）。

### 1.2 分区里有什么

```text
华为账号            未登录：说明 + 「登录华为账号」
                    已登录：展示名 / 脱敏 UnionID / 云服务徽标 / 「退出登录」
云同步              开关（是否允许上云）
                    云服务  状态一句话（登录 ≠ 云服务可用）
                    [上传本机数据]  [拉取并导入]
                    最近一次：…
                    进度（仅在任务进行中）：阶段 + 进度条 + 成功/失败/跳过
同步内容            会话记录与附件（本机 N 个 · 大小）
                    技能
                    插件清单（本机装了哪几个，GitHub 类型单独标注）
                    [从云端恢复插件]
                    同步范围：✓ 会话/附件 ✓ 技能 ✓ 插件清单 ／ ✕ 核心库 ✕ 凭据 ✕ 本机路径
```

**口径纪律**（与 `313` 一致）：只显示真实计数，不显示"云空间剩余容量"这类无来源数字；
失败"下载完成"绝不显示成"同步完成"；登录成功只说明账号身份，云服务状态另行实测。

### 1.3 为什么有两个动作要"跳回原生面板"

| 动作 | 为什么不能在这张分区里做完 |
|---|---|
| 登录 | 官方 `LoginPanel` 是华为账号 SDK 的原生组件，SDK 原文：`LoginPanel can be used only on pages, not on dialog boxes` —— 网页侧没有任何合法办法渲染它 |
| 插件恢复 | 要**逐项多选**，官方设置分区里没有现成的多选控件；原生面板里有完整闭环（检查 → 勾选 → 安装 → 提示重启） |

其余（开关、上传、拉取、退出）都在这张分区里直接完成。点「登录」/「恢复插件」时，
桥打开原生面板（登录那一步自动进入登录态，不必再点一次按钮）。

---

## 2. 上一版没生效的四个真因（逐个取证）

这一节是本轮最有价值的部分：**代码写对了不等于会生效**，链上四个环节都能静默拦住它。

### 2.1 插件根本不在暂存核心树里

```text
$ unzip -l hostruntime/.../dsh-core-...rc.4+dshm.97...zip | grep dshm-cloud-sync
（0 条）
$ grep 'dshm-cloud-sync' dist/core/work/dsh-core-...rc.4+dshm.97/profiles/ondevice/cordis.patch.yml
（0 条）
```

插件源码、`pack-core` 的 `DSHM_PLUGIN_PACKAGES` 清单、profile 里的 insert 行**三处都在**，
但**产物里一个都没有**：`dist/core/work/<ver>` 是增量复用的暂存树，它是在这三处改动**之前**
物化的；不改 `coreVersion` 就永远不会重新物化 ⇒ 出包永远带着一棵没有这个插件的树。
（这正是 `AGENTS.md`「出包与核心树的三个坑」第 2 条。）

**处置**：`coreVersion` `0.2.1-rc.4+dshm.97` → **`0.2.1-rc.4+dshm.98`**，重新 `pack-core --place-in-app`。

### 2.2 `pack-core` 的版本判据把"复用"判成了"不一致"（本轮修掉）

`materialize()` 的复用分支拿 **`@deepseek-ai/dsh/package.json` 的 version** 去比
**`recipe.coreVersion`**：

```text
实际安装：0.2.1-rc.4              ← 上游版本号，npm 装出来的就是这个
配方要的：0.2.1-rc.4+dshm.97      ← +dshm.<n> 是 build metadata，不在包清单里
```

两者**永远不等** ⇒ 每个新版本第一次能装、第二次起一律 `die`。`+dshm.97` 已经被拒过一次，
`+dshm.98` 打包前断言（`writeManifest()` 里同一口径的那条）又判死：

```text
✗ 打包前断言失败：实际安装 0.2.1-rc.4 ≠ 配方 coreVersion 0.2.1-rc.4+dshm.98
```

**修法**（两处同口径）：比较**上游部分**（`split('+')[0]`）—— 那才是"旧核心被打上新标签"的判据；
另外补一条：上游版本相同但**树内清单标签**与本配方不同时，**包清单复用（不重装 npm）、
后续放入插件 / 放入 profile / 注入补丁 / 重写清单照常跑**。否则"升 +dshm.n 让内容生效"这件事
就退化成"每次都重装 300 MB 闭包"。

### 2.3 ArkTS 桥只有"只读状态"

`cloudSyncState()` 只回登录态与几个数字；没有开关、没有最近结果、没有进度，
也没有任何动作入口 ⇒ 就算分区画出来，也只能显示四行死数据。

**处置**：状态扩成完整快照（新增 `enabled` / `lastSyncText` / `busy` / `progress` / `plugins` /
`units`），并新增**一个**动作入口 `cloudSyncAction(action)`（§3）。

---

## 3. 桥面契约（ArkTS ↔ 插件）

| 桥方法 | 形态 | 说明 |
|---|---|---|
| `cloudSyncState()` | 同步，返回 JSON | 一次调用拿全量状态（面板每秒轮询，拆成多个方法就是多倍跨边界开销） |
| `cloudSyncAction(action)` | 同步，返回 `{ok, message}` | **受理即返回**；长任务的结果由下一次 `cloudSyncState()` 反映 |

动作白名单：`login` / `signout` / `enable` / `disable` / `upload` / `pull` / `restore`。

**为什么不给每个动作一个桥方法**：每加一个方法要改两处（`bridges` 定义 + `methodList`），
而 `check-bridge-methodlist` 只能守住"垫片调了但没登记"。一个入口 + 白名单，新增动作不膨胀桥面。

**被拒也照样回**（未登录 / 正忙 / 未开启却上传）⇒ 插件显示原因，不会"点了没反应"。

### 3.1 清单统计的"同步桥 + 异步结果"取舍

`SyncStore` 的按类型统计（会话/附件/技能/插件清单各多少条）是异步查询，而桥是**同步**契约。
做法：每次被读状态时**发起一次刷新**（并发去重），把**上一次算完的结果**一并返回 ——
面板一秒轮询，最多一秒后显示。既不阻塞桥，也不编造数字（不显示假数据）。

---

## 4. 本机怎么测的（不需要设备）

### 4.1 门禁 `tools/check-cloud-sync-plugin.mjs`

不靠"看代码"，而是**真跑**：

1. 读**真实的**官方 `dsh-client-ui-settings-general/lib/client.js`（核心树里那份），
   用最小运行时建出官方设置骨架，确认它声明 `settings.section` 槽位；
2. 材料化本插件的 `lib/client.js` 并 `apply()`，断言它**注册进那个槽位**（id / label / order / locale）；
3. 用桩桥渲染分区，逐分支断言：未登录 / 已登录 / 同步中 / 未开启 / 桥缺失；
4. **点**每个按钮与开关，断言桥收到的动作名与界面文案（上传/拉取/退出/恢复/开关/登录）；
5. 桥缺失时不给按钮、写"尚未就绪"（不假装可用）；
6. 对照臂 `--self-test`：不注册分区 / 动作名写错 / 桥把未登录谎报成已登录 / 回归成 CJS 空模块
   —— 四个变异体**全部必须判红**。

```text
$ node tools/check-cloud-sync-plugin.mjs
✅ 通过：41 条判据（分区注册 / 未登录 / 已登录 / 同步中 / 未开启 / 桥缺失 / 桥拒收）
$ node tools/check-cloud-sync-plugin.mjs --self-test
✅ 自检通过：4 个变异体全部判红
```

> 写这套门禁时踩到的两个坑，记下来避免重犯：
> ① 第一版对照臂只断言"函数返回 true"，根本没把主判定跑一遍 ⇒ 两条臂判不出红（门禁没牙）；
> ② 臂之间共用一张故障表 ⇒ 后一条臂会"借用"前一条臂的失败字样判红（假绿）。
> 现在每条臂：**独立变异 + 完整跑一遍主判定 + 只认自己那条具体的 FAIL**。

### 4.2 产物取证（"生效"的硬判据）

不只看"构建成功"，而是把产物**解开逐字节看**：

| 取证点 | 读数 |
|---|---|
| APP 内 `hostruntime-default.hsp` 的 resfile | `dsh-core-0.2.1-rc.4+dshm.98-openharmony-arm64.zip`（**只有 1 份**容器） |
| 容器内插件目录 | `node_modules/@deepseek-ai/dshm-cloud-sync/{package.json, cordis.patch.yml, lib/index.js, lib/client.js, src/client.src.js}` |
| 容器内 profile | `profiles/ondevice/cordis.patch.yml` 里**有** `- id: dshm-cloud-sync` |
| 容器内 `lib/client.js` | 25,635 B，含 `name: 'settings.section'` 与 `exports.apply = apply` |
| 复跑一次 `pack-core`（同标签） | 走**复用**分支（不重装闭包），产物与首次打包一致 ⇒ 本轮的判据修法在两条分支上都验证过 |

> ⚠️ 复跑 `pack-core` 时若**不带** `--place-in-app`，`dist/core` 会产出一个更新的容器，
> 而 resfile 里仍是旧的那份 ⇒ `check-resfile-core-zip` 立刻判红（本轮就踩了一次，已重新同步并复验）。
> 这条门禁正是为此而设，别把它当噪音。
| `entry-default.hap` 的 `modules.abc` | `cloudSyncState` / `cloudSyncAction` / `refreshCloudStats` / `cloudUnitsJson` / `specKind` 全部在场 |

### 4.3 门禁回归

本轮改动面相关门禁全绿（逐条实跑）：

```text
check-core-openharmony-patches   240 passed / 0 failed（30 处补丁都在）
check-resfile-core-zip           1 份容器，与配方、与本次产出三方一致
check-plugin-toggle / check-bridge-methodlist / check-plugin-module-format
check-feature-wiring / check-dead-code / check-design-tokens / check-sync-model
check-sync-planner / check-plugin-manifest / check-session-sync-scope / check-import-path
check-permission-surface / check-parity / compat-drift / assert-core-entrypoints …（均为 0）
```

---

## 5. 交付件

```text
dist/beta/DSHM-beta-1.1.6-core98-cloudsync/
  DSHM-beta-1.1.6-1010007-combined-debug.app   512,514,220 B
  sha256 f78991be4f5fa755b74046214c737768b59768245ca0d5d75c7ea0a568c29b71
  SHA256SUMS / README.txt（Core: 0.2.1-rc.4+dshm.98，Bundle: com.dshm.dshmbeta）
核心容器：dist/core/dsh-core-0.2.1-rc.4+dshm.98-openharmony-arm64.zip
  sha256 7cdc07aad69c04c15c44dd9a08f3469255bd7e89f6182625b638524f4214b370
  （与 resfile 里那份逐字节一致 · check-resfile-core-zip 通过）
```

> ⚠️ **beta 包名不在 AGC Profile 登记范围**（`docs/303`：`1001502003 Invalid clientId or profile`）⇒
> 用 beta 包登录华为账号会失败。要在真机上验"登录 → 上传 → 换端拉取"，请出**正式包名**的包（或走 AGC 云调试）。
> 这是包名维度的问题，与本插件无关。

---

## 6. 真机验收清单（需要设备）

| # | 场景 | 通过标准 |
|---|---|---|
| 1 | 打开设置（PC / 平板 / 手机三端） | 分区列表里出现**「云同步」**，与「通用设置 / 内置插件」同款行 |
| 2 | 未登录 | 读到"未登录 + 同步范围 + 登录按钮"；点登录 → 弹出官方登录面板 |
| 3 | 已登录 | 显示脱敏账号与云服务徽标；开关可点，状态即时翻转 |
| 4 | 点「上传本机数据」 | 按钮变"进行中…"、出现进度条与阶段名；结束后"最近一次：…"更新 |
| 5 | 点「拉取并导入」 | 拉取与导入两段进度分开出现；新会话出现在列表且**能打开** |
| 6 | 未开启同步时点上传 | 上传按钮禁用（或提示先开启），**不得**假成功 |
| 7 | 点「从云端恢复插件」 | 打开原生面板的插件分组，可勾选安装，装完提示重启 |
| 8 | 断网/杀掉 Host | 分区仍能显示（桥在 ArkTS 侧），操作给出明确失败原因 |

> 第 5 项必须**两个同账号端侧环境**才能验（`314` §6 的同一约束）。

---

## 7. 已知边界（如实记录）

| 项 | 现状 |
|---|---|
| 登录 | 必须由原生面板承载（SDK 限制），插件里只是入口 |
| 插件逐项勾选 | 同样在原生面板里完成 |
| 云端字节级进度 | SDK 不提供，进度以**单元数**为准 |
| 云空间容量 | 无官方接口，**不显示**任何容量数字 |
| 清单统计延迟 | 最多 1 秒（同步桥 + 异步统计，见 §3.1） |
| `AGENTS.md` 的 CI 清单 | 新增门禁 `check-cloud-sync-plugin` 尚未登记进 `.github/workflows/gates.yml`（本轮未改 CI 配置） |

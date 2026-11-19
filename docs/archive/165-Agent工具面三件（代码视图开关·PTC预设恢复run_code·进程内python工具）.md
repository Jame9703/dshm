# 165 · Agent 工具面三件：代码视图开关 · PTC 预设恢复 run_code · 进程内 python 工具

> **一句话**：上一轮把"预设为什么只剩两个"查清后，用户拍板「1 2 3 都做」——
> ① 设备侧打开「显示代码工作视图」（PTC / 极简预设随之恢复可见）；
> ② 只对 **ptc 预设**恢复 `workflow-ptc` / `tool-workflow`（= PTC 模式的 `run_code`）；
> ③ 新增自带插件 `dshm-tool-python`，把模型可见的 `python` 工具接到**主进程内**的 CPython 桥。
> `coreVersion` 升 **`+dshm.55`**；beta 件 `DSHMbeta-…+dshm.55…hap` 已装真机验证。

## 1. 三件事各做了什么

### ① 「显示代码工作视图」= 预设可见性的开关（设备侧，一次性）

设备 `settings/describe` 原文：`ui-settings` 的 `base.enabled=true`（schema 默认开），
`user.enabled=false` —— 是官方引导的「跳过」分支写进去的（`dsh-client-ui-settings-account` 的
`finish()`：`development = reason === "completed" && !office`，`skipped` ⇒ false）。
官方客户端据此隐藏 **ptc / minimal**（`requiresCodingTools()` 只对这两个内置预设为真）。

修法即一条带并发令牌的写：`settings/update {ns:'ui-settings', patch:{enabled:true}, expectedRevision:1}`
⇒ 设备实读 `value={"enabled":true}`。四个预设回到列表。

### ② ptc 预设恢复 `run_code`（`patchPtcPresetWorkflowEnabled()`）

**上游 alpha.4 自己就是关的**（pristine 对照）：bundle 级 `dsh-web-app/cordis.patch.yml` 与
`presets/ptc.patch.yml` 两处都写 `disabled: true`；后者**才是生效的那处**（bundle 那份是根 plane，
预设之下不生效）。而端侧早有同进程 PTC 运行时（`dshm-ptc-runtime-inproc`，
`language === 'typescript'` 正是 `dsh-workflow-ptc` 的硬要求）。

做法：新增只动 **ptc 那一份**的补丁 —— 摘掉两行的 `disabled: true`，原缩进插入标记
`# DSHM_PTC_WORKFLOW_ENABLED`；**standard / cordis 仍由 `patchAgentPresetWorkflow()` 显式停用**
（并让那个函数 `continue` 跳过 ptc，保证第二遍 pack 不会把 disabled 插回来）。
门禁新增一组 ⑧b（标记 ×2 / `DSHM_WORKFLOW_DISABLED` ×0 / 注入片段 / 结构反向）+
变异体 M7b（把 `disabled: true` 塞回标记后面 ⇒ 结构判据必须红）。

真机对照（`.55` 上 `agentPresets/read`）：

| 预设 | `workflow-ptc` | `tool-workflow` |
|---|---|---|
| `ptc` | **启用** | **启用** |
| `standard` | `disabled=true` | `disabled=true` |

### ③ 新增 `dshm-tool-python`：Agent 侧唯一一条不依赖 shell / VM 的 Python 入口

【缺口】宿主内嵌 CPython 一直可用（`/dshm-python/status` ready/stdlib 都真，`print(6*7)` → `42`），
但模型够不到：`bash` 走 guest VM（手机档受 1280 MiB 内存门槛 + guest 里没有 python3）；
`/dshm-python/*` 是回环端点而 `web_fetch` 按 SSRF 策略拒回环；`run_code` 上游停用。

【设计】插件把 `python` 工具接到**主进程内**的桥（与随包 `python3` 垫片同一条通道、同一份 token 口径）：
· 桥的实现住在 `hostcore/app/*.js`（不在核心树里）⇒ 插件够不到那些模块 ⇒ 走 HTTP 回环；
· 端点/token 从 `$DSHM_HOME/host-ready.json` 现读（**当前进程**写出的权威值）；
· `code` 模式打 `/dshm-python/run-get`（内联源码 ≤8 KiB，HTTP 头体积），
  `file` 模式打 `/dshm-python/exec`（argv 以 `\x1f` 分隔，`sys.argv` 对齐真 python3）；
· 超时 1..300 秒（默认 120，与宿主端点同 clamp）；rc `"None"` ⇒ 0；非数字 rc 归 1 并把原值写进 stderr；
· 边界如实写进工具描述：没有子进程（fork/exec 被平台拒）、长任务会卡住宿主事件循环。

【接线】`hostcore/plugins/dshm-tool-python/`（源码）→ `DSHM_PLUGIN_PACKAGES`（打树 + 声明依赖）
→ `hostcore/profile/ondevice/cordis.patch.yml` ⑦b 的 `insert` 行（部署层注册进 global 层 ⇒ 每个 agent 可见）。

【门禁】新增 `tools/check-tool-python.mjs`（离线可跑，**已进 CI**）：静态面（包清单 / peer 钉法 /
profile insert / pack-core 清单 / `inject` 声明）+ 真回环桩 server 的行为面（code/file 两种模式、
超时 clamp、rc 归一、参数互斥与长度上限、`ok:false` / 401 / 缺 host-ready.json 的错误映射）
**+ 4 个变异体**（超时上限改小 / 吞掉 `ok:false` / 去掉 `inject` 的 tools / 删掉 `exitCode` 的 type）
**+ 核心树在时用树里那份真 `dsh-tools` 再注册一遍**（桩抓不到的编译期错误就靠这一臂）。

## 2. 两个只有上了真机才暴露的坑（本轮最大的价值）

| # | 真机原文 | 根因 | 修法（都把这条错误写成了判据） |
|---|---|---|---|
| `.53` | `tool-python (@deepseek-ai/dshm-tool-python): Error: cannot get property "tools" without inject` | Cordis 的服务**按注入放行**：`apply()` 里直接取 `ctx.tools` 必须先声明 `inject` | 补 `const inject = ['tools']` + `export { apply, inject, name }`；门禁的 `loadTool()` **复刻**这条规则，并加变异体 C |
| `.54` | `JsonSchemaError: unsupported JSON schema: schema.properties.exitCode.type must be string/number/… or use oneOf` | `dsh-tools` 编译输出 schema 时**每个字段都要显式 `type`**；我原先把 `exitCode` 写成"只要 required"（想兼容字符串 rc） | schema 改成 `exitCode: { type:'integer' }` + rc 归一（非数字 ⇒ 1 且原文进 stderr）；门禁加"参数/输出字段都必须带 type"判据 + 变异体 D |

**通用教训**：用"桩 `defineTool`"跑离线门禁**证不了** schema/inject 这类**编译期**契约
⇒ 门禁里补了一条"树在时用真 `dsh-tools` 注册一遍"的加强臂（CI 无树时如实 skip）。

## 3. 门禁读数（本轮实跑）

| 门禁 | 读数 |
|---|---|
| `check-core-openharmony-patches` | ✅ **224 通过 / 0 失败**（新增 ⑧b 组与 python 插件镜像判据）；`--self-test` **208 用例 / 0 不合格**（含 M7b） |
| `check-tool-python` | ✅ 19/0；`--self-test` **24/0**（4 变异体 + 真编译器预检） |
| `check-resfile-core-zip` | ✅ resfile 只 1 份容器、与配方/产物 sha 全等（`9a034ff3…`） |
| `assert-core-entrypoints` | ✅ 619 个包根 / 3688 条入口声明全解析 |
| `check-plugin-toggle` | ✅ PASS（宿主离线起一遍，自带行全启用） |
| `check-fs-fence` / `fs-local-permission` / `agent-instructions` / `vm-bash` / `workspace-claim` | ✅ 139 项 / 行为+负控 / 6 臂 / **368** 项 / 14 条 |
| `check-undici-shim-exports` / `check-ptc-runtime-inproc` / `check-ptc-wiring` / `check-native-closure` / `check-market-bridge` | ✅ 全通过（166 断言 / 10 项 / PASS / 140 项） |
| `check-permission-surface` / `no-apk-surface` / `parity` / `feature-wiring` / `doc-refs` / `dead-code` / `arkts-entry` | ✅ 8 条权限恒等 / 0 apk 面 / parity / 23 功能 / 220 引用 / 无死代码 / **ArkTS 0 error** |

## 4. 真机读数（手机 `62T0225B18039433`，覆盖安装，未动用户数据）

| 项 | 读数 |
|---|---|
| 冷启动 | `BOOT_10_ENV_READY … +84ms` → `BOOT_65_AUTH_URL … +13369ms`（pid 24145，port 3121） |
| 核心树 | 设备 `dsh/cores/` = **`0.2.1-alpha.4+dshm.55`**（旧树整目录替换，无残留） |
| 插件行（`pluginInventory/list`） | 7 条自带行 **全部 `enabled=True phase=active`**，含新增的 **`include:tool-python`** |
| 预设组成 | `ptc`：`workflow-ptc` / `tool-workflow` **启用**；`standard`：两条仍 `disabled=true` |
| 症状计数 | `disabling profile plugin row` **0**、崩溃关键字 **0**、`.dshm-boot-failed` **不存在** |
| 设置面 | `ui-settings.value.enabled = true`（PTC / 极简预设恢复可见） |
| Python 桥（PC 侧实调） | `/dshm-python/status` → `ready:true, initialized:true`；`run-get print(6*7)` → `{"ok":true,"stdout":"42\n"}` |

## 5. 产物

| 文件 | 大小（B） | sha256 |
|---|---:|---|
| `dist/beta/DSHMbeta-1.1.2-core0.2.1-alpha.4+dshm.55-arm64-signed.hap` | 442,274,307 | `C18DB555F8C6111103F608C31B72C0D44AE6E92F009E73A229BE7B72BA7BCE88` |
| 容器 `dist/core/dsh-core-0.2.1-alpha.4+dshm.55-openharmony-arm64.zip` | 99,546,464 | `9a034ff3a0978f7f30a07c9dc726449c64f14e9d6f93a81e30bf950771d58ded` |

`.53` / `.54`（插件行 `phase=failed` 的两个中间件）**已删除、不留副本**；`.52` 作为上一批留档件保留。

## 6. 留给用户的验证（本轮到此为止的边界）

1. **PTC 模式的 `run_code` 需要新建一个 PTC 模式会话实测**：本轮验到的是"预设组成里两行已启用 +
   插件行 active"；真正的 `run_code` 工具列表与一次调用要会话起来才看得到。
   若失败，现场在 `node-output.log`（`workflow-ptc` 需要 `ctx.ptcRuntime` 与 subagent 的 `spawn` 提供者）。
2. **`python` 工具要模型实际调一次**：端侧桥与注册都已验证（`phase=active` + 桩/真编译器双门禁），
   但"模型看到的工具描述 + 一次真实调用"要跑一轮对话才能收口。
3. `bash` 仍受 **1280 MiB 内存门槛**约束（实测依据：VM 的 RSS+Swap ≈1.24 GB，见 `docs/161`），
   本轮**没有**下调这个阈值。

**未 commit / 未 push。**

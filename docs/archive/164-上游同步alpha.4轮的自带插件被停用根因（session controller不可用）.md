# 164 · 上游同步 alpha.4 轮：自带插件被停用 ⇒「session controller 不可用」的根因与修复

> **一句话结论**：`0.2.1-alpha.2 → 0.2.1-alpha.4` 升级时，本仓自带插件的
> `peerDependencies` **精确钉法**没跟着内核升（仍写 `0.2.1-alpha.2`）。上游
> `@deepseek-ai/dsh-app-boot` 的兼容闸门逐条判 `semver.satisfies(运行时版本, range, {includePrerelease:true})`
> ⇒ 四条自带行被**整条停用**；其中 `dshm-fs-write-nonchmod` 是端侧 profile 里 **`fs` 服务的唯一提供者**
> （它 replace 掉上游 `fs-sandbox`）⇒ `session-controller` 永远停在
> `pending (waiting for service: fs)`，界面文案就是用户看到的**「session controller 不可用」**。
> `coreVersion` 升 **`+dshm.52`**；闭包锁定机制同轮补上（见 §4）。

## 1. 现象与取证链（都是真机原文，不靠推断）

用户反馈：beta 包冷启动后，界面报「session controller 不可用」。

设备侧 `node-output.log`（`com.dshm.dshmbeta`）两条决定性读数：

```
session-controller (@deepseek-ai/dsh-api-session-controller): pending (waiting for service: fs)
dsh: disabling profile plugin row "fs-write-nonchmod": Plugin @deepseek-ai/dshm-fs-write-nonchmod@0.0.0 is
     incompatible with dsh 0.2.1-alpha.4: requirements {"@deepseek-ai/dsh-fs":"0.2.1-alpha.2",
     "@deepseek-ai/dsh-fs-sandbox":"0.2.1-alpha.2"}. … Exact-version exemption: not active.
```

同批被停用的还有三条：`ptc-runtime-inproc`、`tool-fs-remove`、`dshm-workspace-claim`
（判据同样是 peer 里的 `0.2.1-alpha.2`）。

**判据在哪**（读过树里那份实现，不是猜）：`dsh-app-boot/lib/index.js` 的
`evaluatePluginCompatibility()` → `unmetRequirements()`：`engines.dsh` 优先；没有它时遍历
`peerDependencies` 里每个 `@deepseek-ai/dsh` / `@deepseek-ai/dsh-*`，用
`semver.satisfies(runtimeVersion, range, { includePrerelease: true })` 判。运行时版本取自
`dsh-app-boot/package.json` 的 `version`（本版 = **`0.2.1-alpha.4`**，注意 recipe 的
`coreVersion` 带 `+dshm.NN` 构建元数据，两者不相等）。**精确钉法**只要内核升一档就整条不满足。

**为什么后果是"整个会话面起不来"而不是"少个功能"**：端侧 profile（`hostcore/profile/ondevice/cordis.patch.yml` ⑩）
把上游 `fs-sandbox` 停用、换成我们自己的 `fs-write-nonchmod`；它被停 ⇒ 没有 `fs` 服务提供者 ⇒
依赖 `fs` 的 `session-controller` 永远 pending。

## 2. 修法

1. **8 处 peer 钉法升到当前内核版本**（源码 `hostcore/plugins/*/package.json`）：
   `dshm-fs-write-nonchmod`（dsh-fs / dsh-fs-sandbox）、`dshm-ptc-runtime-inproc`（dsh-ptc-runtime /
   dsh-timeout / dsh-util-values）、`dshm-tool-fs-remove`（dsh-fs / dsh-tools）、
   `dshm-workspace-claim`（dsh-workspace）。
2. **打包层硬闸门**（`tools/pack-core.mjs` 新增 `assertDshmPeerPinsMatchRuntime()`，在 ④b 落树之后跑）：
   运行版本从**树里**的 `node_modules/@deepseek-ai/dsh-app-boot/package.json` 现读，
   任一**精确钉法**与之不等即 `die` 并打印修法。非精确写法（`workspace:*|^|~`、范围）交给上游闸门按 semver 判
   —— 本锁只拦"精确钉法忘了跟着升"这一类。判据面 = **将要进产物的那份字节**。
3. **运行期守卫**（`tools/check-plugin-toggle.mjs` 基线断言，需要核心树）：宿主离线起一遍后，
   `pluginInventory/list` 里四条自带行必须 `enabled: true`，否则判红并直指 peer 钉法。
   本轮实测输出：`baseline: 自带插件行 4/4 启用`。

> **同轮补上一条被漏跑的门禁**：`tools/check-profile-pnpm-bridge.mjs` 的 H5 原来断言"pack-core 里含
> 某段**锚点原文**"，而 alpha.4 给那两句加了 `await`、缩进 4→8 空格 ⇒ 上一轮只跑了核心树门禁、
> 没跑这条离线门禁，红点被带到本轮。已换口径：从 pack-core 源码里取出两条锚点**形状正则**，
> 拿 `alpha.2` 老形态与 `alpha.3+` 新形态**各跑一遍**（两条都要认），并补负控制臂
> 「去掉 `(?:await )?` ⇒ 必红」。实测 `44 通过 / 0 失败`，`--self-test` `50/0`。

## 3. 顺带查清的第二件事：依赖闭包会静默漂移（同轮修掉）

重打 `.52` 时发现新 STAGE 里 `@earendil-works/pi-ai` / `pi-telemetry` 从 **1.2.0 漂到 1.3.0**
（两者差 1 个文件：1.3.0 不再导出 `utils/assistant-message-frame.js`）。原因：新版本目录没有
`package-lock.json`，`npm install` 按 ranges 取"当时最新" ⇒ **同一份 recipe 隔一天重跑，产物闭包就不同**，
既没人评审也没跑过门禁，和 `docs/131` 那种"闭包 +15/−6 逐条登记"的纪律相悖。

修法：`tools/pack-core.mjs` 新增 `reusePreviousLockfile()` —— 本版 STAGE 没有锁时，从**其它
`dsh-core-*` 目录**取最新的一份锁拷进来，`npm install` 以它为准；升级依赖从此是**显式动作**
（更新那份锁 / 改 recipe），不再是 rebuild 的副作用。

结果：`.52` 树与 `.51` 树**文件集逐条相同**（35612 个文件、0 只在 A / 0 只在 B），
版本差只有我们有意改的那 4 个 manifest。

## 4. 门禁读数（本轮实跑）

| 门禁 | 读数 |
|---|---|
| `check-resfile-core-zip` | ✅ resfile 只 1 份容器，与配方、与本次产出 sha 全等（`fe842a4242da8a6b…`） |
| `assert-core-entrypoints` | ✅ 618 个包根 / 3685 条入口声明全部解析 |
| `check-core-openharmony-patches` | ✅ **212 通过 / 0 失败**（27 处注入 + 1 处撤除守卫） |
| `check-plugin-toggle` | ✅ PASS（含新增的 `自带插件行 4/4 启用`） |
| `check-fs-fence` / `check-fs-local-permission` / `check-agent-instructions-scope-walk` | ✅ 137 项 / 8 组行为+负控 / 6 条对照臂 |
| `compat-drift` | ✅ 无漂移（144 端点 = 基线） |
| `check-ptc-runtime-inproc` / `check-ptc-wiring` | ✅ 166 断言 / 10 项接线 |
| `check-profile-pnpm-bridge`（含 `--self-test`） | ✅ 44/0；自检 50/0（H5 换成"形状正则同时认两代锚点"+ 新增负控制臂） |
| `check-undici-shim-exports` / `check-web-fetch-jitless` / `check-worker-jitless` / `check-internal-undici` / `assert-fs-search-fallback` | ✅ 全通过（含各自对照臂） |
| `check-native-closure` | ✅ PASS（61 个库，2 条 soname 警告属既有） |
| `check-permission-surface` / `check-no-apk-surface` / `check-parity` / `check-feature-wiring` | ✅ 8 条权限恒等、0 个 apk 面、parity 完整、23 个功能接线在 |

ArkTS 编译：`BUILD SUCCESSFUL in 15 s 529 ms`（0 error）。

## 5. 真机读数（手机 `62T0225B18039433`，覆盖安装，未动用户数据）

| 项 | 读数 |
|---|---|
| 安装 | `hdc install -r …+dshm.52…hap` → `install bundle successfully` |
| 冷启动 | `BOOT_10_ENV_READY … +156ms` → `BOOT_65_AUTH_URL … +12706ms`；`host-ready.json` port **3121**、新 token、pid 51922 |
| 核心树 | 设备 `dsh/cores/` = **`0.2.1-alpha.4+dshm.52`**（旧树整目录被替换，无残留） |
| `.dshm-boot-failed` | **不存在** |
| `disabling profile plugin row` | **0 处**（修前 4 行 ×2 次） |
| 崩溃关键字（CppCrash / JS_ERROR / AppKilledReporter） | **0 处** |
| 插件行（本机 fport 到 3121 查 `pluginInventory/list` 的原文） | `include:ptc-runtime-inproc` / `include:tool-fs-remove` / `include:dshm-workspace-claim` / `include:fs-write-nonchmod` / `include:dshm-office-system-preview` / `include:dshm-vm-bash` **全部 `enabled=True phase=active`** |
| 关键服务面 | `session-controller` / `terminal-controller` / `workspace-controller` **全部 `enabled=True phase=active`**；`fs-sandbox` `enabled=False`（**预期**：已被 `fs-write-nonchmod` 取代） |
| 终端链 | 宿主日志 `[dshm-vm-bash] 已接管 ctx.subprocess.spawn` + `已接管 ctx.subprocess.spawnTerminal` + `按需冷启动已启用`（插件自检报"VM 资产齐备"） |

## 6. 产物

| 文件 | 大小（B） | sha256 |
|---|---:|---|
| `dist/beta/DSHMbeta-1.1.2-core0.2.1-alpha.4+dshm.52-arm64-signed.hap` | 442,266,114 | `26EFAD53C236250A3FA8F8360B8BD3A998C8CE28B22CBFC21028A41658CD359B` |
| 容器 `dist/core/dsh-core-0.2.1-alpha.4+dshm.52-openharmony-arm64.zip` | 99,538,701 | `fe842a4242da8a6b234a6102d03079fde99699f635a6375f99310a0202ccc927` |

包内实读（从 HAP 里取出 `module.json` / resfile 条目核对，不是看源码）：
`bundleName=com.dshm.dshmbeta`、`versionName=1.1.2`/`versionCode=1010002`、
`minAPIVersion=60101024`、`targetAPIVersion=260000026`、`debug=false`、
`requestPermissions` **8 条**且逐条是老八条；resfile 里的核心容器 sha = 上表容器 sha。

## 7. 未做 / 下次做

- **PC / 2in1 本批未复验**：本轮只有手机在线（`hdc list targets` 无 2in1）。PC 档行为面本轮零改动，
  但按纪律仍要在 PC 上覆盖安装 + 冷启动一次。
- **终端 UI 手测未做**：终端面板在 ArkWeb 里，`uitest dumpLayout` 取不到 Web 内容 ⇒ 无法脚本点击；
  真机上「侧边栏终端」首次打开会按需冷启动 guest VM（约 10–20 s）。
- 插件市场 / 皮肤市场 / 会话读写三条留给用户手测（服务面读数已全绿）。
- AGC 件未出（本轮只要 beta 侧载件）。
- **未 commit / 未 push**。

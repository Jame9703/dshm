# 255 · 环境收口：Windows 遗留清理、Codex 工作流退场、DSH 单一开发入口

> 日期：2026-10-25
>
> 范围：**只动开发环境与仓库卫生，不动应用功能、不动签名物料、不动真机数据。**
>
> 本轮未重编、未安装、未上传。当前已安装 APP 仍是 `.95`。

## 1. 为什么要做这一轮

这条项目的开发端换过三次：

1. Windows 电脑（`D:\desktop\ohos\desktop.ohos.arm64`，PowerShell 工具链）；
2. 打包搬到鸿蒙 PC（MateBook 14，DevEco Studio 鸿蒙版），用 Codex 继续开发；
3. 现在只在 **DSH** 里开发。

每换一次，上一代环境的东西都会**留在仓库里继续误导判断** —— 不是"占点空间"的问题：
`.ps1` 脚本在本机根本没有解释器，却仍写在必跑门禁清单里；IDE 缓存带着旧绝对路径入库；
迁移期的「解包到另一台机器」说明会被当成当前操作手册。这些东西的共性是
**它们看起来仍然有效，实际一条都跑不了**。

## 2. 本机环境实测（基线，2026-10-25）

| 项 | 实测值 |
|---|---|
| 系统 | HarmonyOS，Kernel 1.13.0 aarch64（Toybox shell，`/bin/sh`） |
| Node | `v26.12.1`（`~/.harmonybrew`） |
| npm | `11.20.0` |
| Python | `3.14.7`（`~/.harmonybrew`） |
| DevEco | `/data/service/hnp/hmos-clt.org/hmos-clt_1.0.0`（CLT 布局；`~/devecostudio/Contents` 是指向它的符号链接） |
| hvigorw | `<DevEco>/hvigor/bin/hvigorw.js`（**无** `tools/` 前缀） |
| hdc | `<DevEco>/sdk/default/openharmony/toolchains/hdc`（**无** `.exe`） |
| PowerShell | **不存在**（`pwsh` / `powershell` 均未安装） |
| 设备 | `hdc list targets` = `[Empty]`（本轮无真机在线） |

`node tools/doctor.mjs` 当前输出（只读）：

```text
[ OK ] Node: v26.12.1
[ OK ] hvigorw: /data/service/hnp/hmos-clt.org/hmos-clt_1.0.0/hvigor/bin/hvigorw.js
[INFO] ohpm: not present in this CLT layout (build does not require it)
[ OK ] hdc: /data/service/hnp/hmos-clt.org/hmos-clt_1.0.0/sdk/default/openharmony/toolchains/hdc
[ OK ] DevEco root: /data/service/hnp/hmos-clt.org/hmos-clt_1.0.0
[ OK ] JAVA_HOME: ~/.harmonybrew/opt/openjdk/libexec (openjdk 26.0.2.1)
[ OK ] DEVECO_CLI_CLT_PATH: /data/service/hnp/hmos-clt.org/hmos-clt_1.0.0
[INFO] PowerShell: not installed; Node tools are the supported HarmonyOS PC path
[MISS] 设备: hdc list targets = [Empty]
```

> **`ohpm: not present` 不是缺陷**：CLT 布局里没有 ohpm，`oh_modules/` 已经就位，
> 构建不需要重新装依赖。doctor 自己也是这么写的。

## 3. 删了什么（逐项给判据，不给"感觉没用"）

### 3.1 Windows-only 的 `.ps1`：11 个，全删

判据只有一条：**本机没有 PowerShell，这些脚本一条都执行不了。**

| 文件 | 原本职责 | 为什么删得掉 |
|---|---|---|
| `tools/update-device.ps1` | 真机覆盖安装 | 已有 `tools/update-device.mjs`（忠实移植，判据逐条一致） |
| `tools/device-acceptance.ps1` | 端侧验收采证 | 判据来源是 AGENTS.md「真机读数的三个坑」里那些命令，脚本只是包装 |
| `tools/device-code-fingerprint.ps1` | 设备/本机核心树逐字节比对 | 同上；方法与 `hdc file recv` + `sha256sum` 同在 |
| `tools/sign-release-hap.ps1` | 发布签名 + `verify-app` 复验 | 当前发布链路是 `assembleApp` 直接用 `build-profile.json5` 的 release 签名（见 `docs/242`），不再走这条手工重签 |
| `tools/lib/deveco-home.ps1` | DevEco 根的 PowerShell 解析口 | `tools/lib/deveco-home.mjs` 是同一份候选表，本机是唯一一份 |
| `tools/node-runtime/sign-native.ps1` | 给 `.so` 补代码签名 | `after-libnode.sh` 已实测「随包 `.so` 不需要代码签名」 |
| `tools/electron-runtime/{collect,extract,place-host-app,vendor-web-engine,verify}.ps1` + 其 `README.md` | 阶段一 Electron-on-鸿蒙 载体 | 该阶段已整体移除（D6 E49），`entry` 也不再依赖 `web_engine`；`place-host-app.mjs` 已接管入口脚本放置 |

> **能力损失如实登记**：`device-acceptance` / `device-code-fingerprint` / `sign-release-hap`
> 这三条**没有** node 版。删掉它们意味着本机不再有这三条自动化。
> 判据不会因此丢失（见上表第三列），但**要重新自动化得写新的 `.mjs`**。
> 这条比"文件少了"重要，所以写进 AGENTS.md 的「哪些门禁需要核心树 / 设备」一节。

### 3.2 IDE 缓存与迁移期文件

| 路径 | 是什么 | 判据 |
|---|---|---|
| `.bitfun/`（14 个文件入库） | DevEco 工程缓存：`project.json` / `configs.json` / `.deveco/.cxx/` 下的 clangd 与 cmake 索引 | **机器绑定 + 绝对路径 + 可再生成**。IDE 重开工程会自动重建；入库只会制造"别人以为这是配置"的误解。已改为整目录忽略 |
| `.workbuddy/` | 另一个 AI 助手（WorkBuddy）的记忆文件 | 内容已被 `docs/213` / `docs/214` 覆盖，且有与本仓当前口径矛盾之处（beta 包名、8 条权限） |
| `START-HERE.md`、`tools/START-HERE.dev-eco.md`、`build-profile.portable.json5` | 「把工程打包拷到另一台机器」的三件套 | 现在就在本机开发，不再搬迁；`portable` 那份是**占位签名**的搬运模板，留着只会和 `build-profile.json5` 混淆 |
| `spec/hmpc-dev-adaptation/`（含 `spec/feature.json`） | 迁移期的 spec / plan / tasks | 文件自身标注 `status: superseded`（2026-10-22），结论已落进 `docs/214` / `docs/215` / `docs/222` |

> `.bitfun/` 与 `.workbuddy/` 在删除前已整目录复制到仓库外
> `~/.dshm-cleanup-20261025/ide-cache/`。
> `update-device.ps1` 与 `device-code-fingerprint.ps1` 两个文件在盘上有**未提交改动**
> （相对 HEAD 少了 100 / 9 行），按「先留证再删」把它们的工作区版本单独放进了
> 同目录的 `tools-worktree/`。

### 3.3 本机 git 配置里那条 Windows 路径

`.git/config` 里有一条从 Windows 带过来的：

```text
sshCommand = ssh -i C:/Users/Sol/.ssh/id_ed25519_gitcode -o StrictHostKeyChecking=no
```

后果不会报错，只会**每次静默多打一行告警**，然后回落到默认密钥：

```text
Warning: Identity file C:/Users/Sol/.ssh/id_ed25519_gitcode not accessible: No such file or directory.
```

已删除该条（`git config --local --unset core.sshCommand`）。删除后 `git ls-remote gitcode`
仍然成功，且不再有告警 —— 本机 `~/.ssh/id_rsa` 本来就是被远端接受的那把。

## 4. 同步改了什么（删文件必须跟着改引用）

删掉的路径只要还被门禁/文档引用，就会变成**悬引用**。本轮逐条处理：

| 文件 | 改动 |
|---|---|
| `tools/check-pc-api26.mjs` | 原先把 `build-profile.portable.json5` 当第三个"必须存在"的配置源 ⇒ 删除后会 **ENOENT 崩溃**。已摘掉该项，并把第二条对照臂从"便携配置"改指向仓库模板；另补一条自述注释 |
| `tools/build-beta.mjs` | `TEXT_EDITS` 里含 `build-profile.portable.json5` ⇒ beta 构建会在 `backup()` 时炸。已移除 |
| `tools/check-deveco-paths.mjs` | 扫描范围**保留** `.ps1` / `.bat` / `.cmd`（防御性：日后有人放回 Windows 脚本，写死安装根照样判红），只改掉了指向已删 `deveco-home.ps1` 的提示文案 |
| `tools/lib/deveco-home.mjs` | 注释里"PowerShell 侧是同目录的 `deveco-home.ps1`"已失实，改为"本文件是唯一一份" |
| `tools/lib/hdc-client.mjs` | 同上，去掉对已删 .mjs/.ps1 兄弟工具的指向 |
| `tools/update-device.mjs` | 头注"Windows 原版保留不删、双平台并存"已作废 ⇒ 改为"本文件是唯一装机入口" |
| `tools/place-host-app.mjs`、`entry/src/main/ets/pages/Index.ets` | 指向已删 `electron-runtime/place-host-app.ps1` 的注释改指 `tools/place-host-app.mjs` |
| `tools/node-runtime/README.md` | 「签名回退流程 `sign-native.ps1`」整节重写：保留**判据**（`display-sign` 读数与 `binary-sign-tool` 真实参数），改写成本机可直接执行的 `java -jar …` 命令 |
| `tools/node-runtime/after-libnode.sh` | 那句"sign-native.ps1 仍留着备用"改为"已删除，见 docs/255" |
| `hostcore/app/main.js` | 两处注释引用已删的 `.ps1`（`device-code-fingerprint` / `device-acceptance`）⇒ 改为按**行为**描述判据，不再指向不存在的脚本。改后已跑 `tools/place-host-app.mjs` 重新同步 `resfile/resources/app/` |
| `AGENTS.md` | ① 删掉清单里两条 `.ps1`，换成 `update-device.mjs` / `stage-sideload.mjs`；② 「需要真机 / DevEco」一节改写，并加一段说明**为什么删、能力缺口在哪、要恢复就写 .mjs**；③ 三处 `powershell` 代码围栏改为 `bash`（命令本来就是 hdc / node） |
| `docs/README.md` | 常用入口的 `.\tools\update-device.ps1` → `node tools/update-device.mjs --skip-build --target <connect-key>` |
| `README.md` | 构建块从 `hvigorw …` 改为 `node "$DEVECO_HOME/hvigor/bin/hvigorw.js" …`（本机 `hvigorw` 不在 PATH 上） |
| `.github/workflows/gates.yml` | 排除清单里那条 `device-acceptance.ps1` 的说明改写 |
| `.gitignore` | 新增 `/.bitfun/`、`/.workbuddy/`；删掉原来的 `/.bitfun/.deveco/.cxx/`（被子目录规则覆盖） |
| `.gitattributes` | 补 `*.bat` / `*.cmd` 的 `eol=lf`；`.ps1` 那条保留为防御性声明并注明"仓库里已无 .ps1" |

## 5. 顺手修掉的一条**门禁假红**（先于本轮存在）

`tools/check-worker-jitless.mjs` 在本机是红的，但**不是本轮改动引起的**（该文件本轮未改）。
根因是**环境漂移**，不是逻辑错：

- 门禁的 A 臂判据要求"失败并带 WASM 因果证据"，匹配的词是
  `WebAssembly is not defined`（V8 自己在 `--jitless` 下的原文）。
- 本机 Node 是 **26.12.1**：undici 拿到同一条错误后**换成自己的措辞**再往上抛 ——
  `WebAssembly is not supported in this environment, but is required for HTTP/1 parsing`。
- 于是 A 臂"确实按预期失败、也确实是 WASM 因果"，却被判成"没有 WASM 因果证据" ⇒ 假红。

CI 钉的是 Node 24，所以这个漂移**只在鸿蒙 PC 本机暴露** —— 正是本仓"门禁必须在本机也跑得绿"
那条口径要挡的形态。

修法：判据接受两种措辞，并补一条自测臂把新措辞钉住（自测 8 → 9 条，全过）。
修后本机 `PASS：对照实验成立 —— 同一份 worker，无注入必失败、有注入全通过`。

## 6. 明确**没有**动的东西

按 AGENTS.md 的红线，以下一项都没碰：

- **签名物料**：`.certs/**`（release / debug-local / multihap / beta 四套 p12·cer·p7b）、
  `signing/**`、`~/.ohos`。它们和真机数据同级 —— 私钥没有第二份，删了就只能换身份，
  接着就是"覆盖安装失败 ⇒ 只能卸载 ⇒ 真机数据不可逆丢失"。
- **真机数据**：全程零 `hdc` 写操作、零 `uninstall`、零 `rm -rf el2`。本轮设备也不在线。
- **交付产物**：`dist/release-test/` 的净版 release `.app`、`dist/sideload/` 的三档侧载目录、
  `dist/core/` 的 `.95` 核心 zip、`dist/node/libnode.so.137.orig`（`--restore` 的备份件）
  全部保留。
- **`hostruntime/libs/`、`resfile/` 的 toolchain / vm / busybox / ohos-skills**：构建输入，不动。
- **`third_party/`**：手工取得的原始素材，不动。
- **未提交的在飞改动**：本轮开始时工作区已有 242 项改动（含 `entry/src/main/ets/**`、
  `hostcore/app/main.js` 的业务改动等），一律保留，只在其上做增量编辑。

> 也**没有**做 `git clean` / `git reset --hard` / `git add -A` / `git commit`。
> 全部改动留在工作区，等用户决定怎么提交。

## 7. 现在的开发入口（只有这一套）

```bash
# 环境体检（只读）
node tools/doctor.mjs

# 构建 + 覆盖安装（唯一装机入口，全程只用 hdc install -r）
node tools/update-device.mjs                       # 默认构建 debug
node tools/update-device.mjs --skip-build          # 只装现有产物
node tools/update-device.mjs --module phone        # 显式选手机 entry

# 只构建
node "$DEVECO_HOME/hvigor/bin/hvigorw.js" assembleApp \
  --mode project -p product=release -p buildMode=release --no-daemon

# 侧载目录（一个 entry HAP + 一个共享 HSP）
node tools/stage-sideload.mjs

# 开发主体
#   日常调试：DevEco Studio 选 entry:default 点 Run（debug + 设备绑定签名）
#   改完 hostcore/** 记得：node tools/place-host-app.mjs && node tools/assert-resfile-sync.mjs
```

**Codex 已退场**：本轮没有再引入任何 Codex 专用的开发链路。仓库里剩下的 `codex` 字样
全部是**产品功能**（应用内置的 Codex 子智能体安装/环境同步：`tools/setup-codex-for-dshm.mjs`、
`hostcore/app/dshm-installer.js`），那是给最终用户用的，与"谁来开发这个仓库"无关，故保留。

## 8. 回归读数（本轮改动后实测）

离线门禁（不需要核心树 / 设备）**全绿**，逐条：

```text
assert-cli-shim               40 项全过
assert-resfile-sync           20 件快照全部同步
assert-exec-fix               43 项全过
assert-python-bridge          71 项全过
check-parity                  通过（覆盖完整、无形态注水）
check-doc-refs                219 条引用落点全部一致
check-dead-code               2541 处声明、无死代码
check-deveco-paths            通过（无写死安装根）
check-permission-surface      18 / 10，撤回权限全仓 0 命中
check-pc-only-surface         PASS
check-pc-api26                API 23 / target 26（含 5 条对照臂 5/5）
check-no-apk-surface          PASS
check-store-readiness         PASS
check-feature-wiring          接线完整
check-fs-fence                128 项通过
check-fs-probe-cache          46 项（6 个变异臂全红）
check-module-path-guard       36 项（4 个变异臂全红）
check-python-async-worker     PASS
check-worker-jitless          PASS（本轮修掉假红，见 §5）
check-internal-undici         PASS
check-fetch-shim              全部通过
check-skill-sync              32 passed
check-ptc-ts-strip            通过
check-usage-card              35/0，对照臂 12 组
check-browser-autoclose       26/0，对照臂 10 组
check-browser-screenshot      PASS
check-open-link-bridge        28/0，对照臂 8 组
check-file-location           PASS
check-market-bridge           142 passed
check-profile-pnpm-bridge     56 passed
check-design-tokens           通过
check-decor-button-mode       9/0 + 96/0
check-cot-translation         PASS
check-auth-return             PASS
check-workspace-browser-fallback  2/2
check-vm-bash-sandbox-path    PASS
check-handheld-back           45 passed
check-handheld-sidebar-recover PASS
check-sidebar-shim-css        23/0
check-plugin-render-arity     11 个插件入口、0 违规
check-meeting-mode            PASS
check-meeting-ai-plugin       PASS
check-memory-guard            PASS
check-node-runtime-startup    PASS
check-tool-python             19/0
check-workspace-claim         21 条全绿
check-libnode-io-uring        19 passed
check-edge-desktop-policy     PASS
check-mobile-upgrade-migration PASS (50)
check-install-spec-normalize  PASS
check-icon-assets             6 项
check-tar-extract             42 pass
check-toolchain-sign          2 项
check-user-rows-preflight     93 项
check-builder-recursion       无违规
check-layout-fixtures         四形态全部符合
check-arkts-entry             PASS（ArkTS 编译 0 error）
check-fetch-mirror            PASS
```

### 8.1 非零退出的项，逐条定性（都不是本轮引入）

| 门禁 | rc | 定性 |
|---|---:|---|
| `check-ptc-wiring` | 3 | **环境不具备**：需要核心树 `dist/core/work/dsh-core-<ver>/`，本轮无（构建产物未生成） |
| `check-resfile-core-zip` | 1 | **环境不具备**：`dist/core` 里是 `.95`，而 `core-recipe.json` 已是 `.96` ⇒ 需要先跑 `pack-core --place-in-app`。这是 `docs/HANDOFF.md` 已登记的"源码 .96 / 已装 .95、本轮未重编"状态 |
| `check-sidebar-tab-id-guard` | 2 | 同上，需核心工作树 |
| `check-model-roundtrip` / `check-origin-fence` / `check-custom-api-save` / `check-custom-api-discovery` / `check-compat-exemption` | 2 | 同上（核心树缺失） |
| `check-dshm-installer.cjs` | 124 | **超时**：该脚本含出网用例（npm / GitHub / 镜像回退），本机当前网络下挂住；`docs/253` 记过它 88 passed 的读数，属环境受限 |
| `check-dead-handlers` | 1 | **先于本轮存在**：`entry/src/main/ets/view/MeetingPanel.ets:125` 的 `onTick` 空实现。该文件在本轮开始时就已处于未提交修改状态（会话开始时的 242 项）,本轮未触碰 |

> 口径：**"CI 绿"不等于"全绿"**。核心树与设备相关的那几条必须在有产物的环境里另跑，
> 本文件不把它们算作通过。

## 9. 未做 / 待办

1. **未重编、未安装**：本轮只动环境，`coreVersion` 仍是 `.96`、`dist/core` 仍是 `.95`。
   要出包得走 `pack-core --place-in-app` → `assembleApp` → `update-device.mjs`。
2. **未提交**：改动都在工作区。建议分两次提交 —— 一次是"删 Windows 遗留 + 修引用"，
   一次是"门禁假红修复"，便于回溯。
3. **三条取证能力暂缺自动化**：`device-acceptance` / `device-code-fingerprint` /
   `sign-release-hap` 现在只有手工判据。需要时写 `.mjs`（`tools/lib/hdc-client.mjs` 已就位，
   直接用它调 hdc 即可，不要在脚本里再写一份 hdc 解析）。
4. **历史文档里的 `.ps1` 引用未回改**（65 个文件）：那些是**当时的读数与事故记录**，
   `docs/README.md` §7 明文规定"契约、事故和真机证据不物理删除，避免破坏审计链和行号引用"。
   本轮只清理**面向当前**的文档（AGENTS / README / docs/README / HANDOFF / gates.yml）。

# AGENTS.md — DSHM 开发规范

> 本文件是**唯一规范入口**。红线、流程、工程约束以本文为准；操作细节在 [`AGENT-HANDOFF.md`](AGENT-HANDOFF.md)；
> 当前状态在 [`docs/HANDOFF.md`](docs/HANDOFF.md)；功能与门禁对照在 [`docs/FEATURES.md`](docs/FEATURES.md)。
>
> **阅读顺序**：本文件 → `AGENT-HANDOFF.md` → `docs/HANDOFF.md` → `docs/ARCHITECTURE.md` → `docs/FEATURES.md`。
> 历史文档在 `docs/archive/`，只读、不作为现行口径。

---

## 1. 单一真源（不抄值，去这里读）

| 项 | 唯一出处 |
|---|---|
| 应用版本 / 包名 | `AppScope/app.json5` |
| 核心版本 / 裁剪 / 原生件 | `hostcore/core-recipe.json` |
| 模块设备面 | `entry/`、`phone/`、`hostruntime/` 的 `module.json5` |
| 权限条数 / 顺序 / reason | `tools/check-permission-surface.mjs` 的 `EXPECTED` / `PHONE_EXPECTED` |
| 门禁清单 | `.github/workflows/gates.yml` + 最新 `dist/acceptance/*full-gates*.txt` |
| 三端归属 | 本文 §3.3 |
| 功能 → 实现 → 门禁 | `docs/FEATURES.md` |
| 已知坑 / 决策 | `docs/PITFALLS.md`、`docs/DECISIONS.md` |
| 正式 AGC App ID | `APPID-CHANGE.md` |
| 最低 / 目标 API | `build-profile.json5` |

## 2. 环境与工具

- 环境实跑表、`devecocli` 用法、Beta / AGC 出包、技能目录：见 [`AGENT-HANDOFF.md`](AGENT-HANDOFF.md)。
- **DevEco Code（AI IDE）可用**；**DevEco Studio GUI 不可用**。构建 / 安装 / 看日志一律走 `devecocli` 与 `tools/*.mjs`，不要让用户去点 IDE 菜单。
- **本机即该鸿蒙 PC**（MateBook 14 2in1，API 26）：无线调试常驻 `127.0.0.1:45595`，`devecocli device list` 为空时先 `hdc tconn 127.0.0.1:45595`，随后可直接覆盖安装推送测试。平板 / 手机形态需用户真机自测。
- `rm` 被 safe-bin shim 接管：删除用 `python3` 的 `os.remove` / `shutil.rmtree`，删完回读验证。
- 出包 / 打包会撞 safe-delete 批量阈值：只对**单条**构建命令加 `CODEBUDDY_SAFE_DELETE_ENABLED=0`。

## 3. 工程结构

### 3.1 模型与模块

Stage 模型，多 HAP + 共享 HSP + HAR：

| 模块 | 类型 | 设备面 | 职责 |
|---|---|---|---|
| `entry` | entry HAP | tablet + 2in1 | PC / 平板壳：窗口、顶栏、托盘、侧栏、分享、权限面 18 |
| `phone` | entry HAP | phone | 手机 / 折叠壳：抽屉、返回键、权限面 9 |
| `hostruntime` | shared HSP | 三端 | 宿主：单实例、端口、核心安装、Node 启动 |
| `platform` | HAR | 三端 | 共享能力：设备事实、通知、文件选择、云同步 |
| `appstate` / `dshcompat` / `connection` | HAR | 三端 | 状态恢复 / 兼容面与桥契约 / 网络连接 |
| `hostcore` | 资源与脚本 | — | 核心配方、宿主垫片、11 个自带插件 |

运行时链路、垫片、数据路径见 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)。

### 3.2 目录职责

- `entry/src/main/ets/pages/WebApp.ets`、`phone/src/main/ets/pages/WebApp.ets`：壳层接线与 DOM 垫片。
- `hostruntime/src/main/ets/runtime/`：宿主生命周期；`core/`：核心安装与回滚。
- `hostcore/app/`：宿主 JS 垫片与启动编排；`hostcore/plugins/`：自带插件。
- `tools/`：构建、打包、门禁；`dist/`：交付物与证据；`docs/`：文档（历史在 `docs/archive/`）。

### 3.3 三端归属（唯一口径）

| 平台 | 判定 | 模块 / 权限 | 顶栏 | 左栏 | 终端 |
|---|---|---|---|---|---|
| PC / 2in1 / MatePad Edge / Pro Max | desktopForced | entry / 18 | PC 顶栏（三键 / 托盘） | 常驻 | 原生 PTY |
| 平板（不含 Edge/ProMax） | tablet | entry / 18 | 无自绘顶栏 | 展开 280 / 收起 56，`<1024` 交官方抽屉 | guest VM |
| 手机 | phone | phone / 9 | 无 | 抽屉 + 单颗 ⊞ | guest VM |
| 折叠单屏 | foldable + singleScreen | phone / 9 | 无 | 手机抽屉 | guest VM |
| 折叠多屏 | foldable + 非 singleScreen | phone / 9 | 无 | 平板形态 | guest VM |

**规则：三端互不影响，各改各的。** 共享逻辑放 `platform`，或两壳同构点同时改并跑 `check-dual-shell-parity`。

## 4. 开发流程（SOP）

### 4.1 标准顺序

1. **定位**：在 `docs/FEATURES.md` 找功能行，确认实现位置与门禁；先跑一次相关门禁做基线。
2. **确认口径**：涉及方案切换 / 破坏性操作 / 版本号，先出方案等用户确认。
3. **实现**：只改目标平台分支；临时实验必须在同一次改动内还原。
4. **静态检查**：`.ets` 跑 `check_ets_files`；`.cpp` 跑 `check_cpp_files`。
5. **构建**：`devecocli build --product default`（手机壳另跑 `--product phone`）。**不带 `--product` 会因双 entry 报错**。
6. **门禁**：跑相关门禁；出包或改核心时跑全量回归（§7）。
7. **真机**：本机 2in1 可覆盖安装；平板 / 手机交用户自测。
8. **交付**：包结构核验与真机结论分开写；功能 / 坑 / 决策同步进台账。

### 4.2 默认决策（不要反复问）

| 场景 | 默认做法 |
|---|---|
| 改完 `.ets` / `.cpp` | 静态检查 → `devecocli build --product default` → 相关门禁 |
| 要装到本机 | Beta `local-install`（本机调试签名，见 `AGENT-HANDOFF.md` §3.3） |
| 改完插件 / 核心树没生效 | 重打核心容器（§6.3） |
| 用户没说「出包」 | 只编译 + 门禁，不出包 |
| 用户没说「验证 UI」 | 不跑 `verify_ui` |
| 装不上 / 9568322 / 9568286 | 换同签名、同 provision 的包覆盖安装；**不卸载** |
| 文档写哪里 | 状态改 `docs/HANDOFF.md`；功能改台账；坑改坑档；决策改决策表 |
| API / 权限不确定 | 先查本地知识库与官方文档（`AGENT-HANDOFF.md` §2），再查核心树 |

**必须问用户的只有 4 类**：破坏性操作（卸载 / 清数据 / 删交付件）、改版本号、切换平台归属、上传或提交审核。

## 5. 编码规范

### 5.1 ArkTS

- 按 ArkTS 严格子集写：不要 `any` / `unknown`、不要 `as` 断言、不要结构化类型、不要动态属性访问。
- 对象字面量必须有显式类型上下文。
- 写 `.ets` 前先加载 `arkts-grammar-standards`；报错按 `arkts-error-fixes` 修。
- 资源与字符串：不写死品牌 / 包名；用资源引用。

### 5.2 三端隔离

- 手机 / 折叠只改 `phone`；平板 / PC 只改 `entry`；共享能力改 `platform`。
- 设备分档只认 `DeviceFacts`：`EDGE_FAMILY_TOKENS` **只含 `QXS`**，市场名靠 `MatePad Edge` / `Pro Max` 分词。
  `MRX/MRR/MRD/MRO/DRA` **不得加回**型号族白名单（会把普通平板判成 desktop，终端直接不可用）。
- 终端分档：只有 PC / 2in1 / Edge / ProMax 有原生 PTY；其余走 guest VM。

### 5.3 桥、垫片与核心补丁

- 新桥方法必须同时登记契约（`dshcompat` + `check-bridge-methodlist`），否则不得暴露。
- jitless 是正式形态：不申请 JIT、不解除降级、不依赖 WASM；新能力走既有垫片层。
- 上游补丁必须可核对：锚点缺失要显式告警，不允许静默跳过。
- 改 `hostcore/plugins/**` 或核心树内容 ⇒ 必须重打容器（§6.3）。

### 5.4 权限与资源

- **先实现、后声明**：不得声明没有运行时消费点的权限。
- 权限面 entry 18 / phone 9，条数 + 顺序 + reason 逐位钉死；任何改动必须同步门禁。
- ACL 以发布 Profile 的 `allowed-acls` 为准；不得声明 Profile 未批准的受控权限。
- 不把「删权限」当排障手段；按「声明面 / Profile / 设备实读」三类证据排查。

### 5.5 版本控制

- **代码永不提交**：不执行 `git commit` / `push`，除非用户明确要求。
- 不删 `signing/**`、`.certs/**`、`dist/**` 交付件、`resfile/` 关键资产。

## 6. 构建、签名与发布

> 本节是**构建的唯一真源**。其他文档只做速查并指回本节。
> 所有命令都在工程根执行；脚本会临时改身份并在 `finally` 逐字恢复。

### 6.0 先选对产物

| 目的 | 用哪条命令 | 产物身份 |
|---|---|---|
| 改完代码自检 | `devecocli build --product default` / `--product phone` | 正式包名，debug 签名 |
| 出测试包给别人 | `tools/build-beta.mjs --combined-app` | `com.dshm.dshmbeta`，debug |
| 装到本机看效果 | Beta + `local-install` 重签 | `com.dshm.dshmbeta`，本机调试签名 |
| 上架 / 邀请测试 | `tools/build-agc.mjs` | `com.dshm.dshclient`，release 签名 |
| 只改核心树 / 插件 | `tools/pack-core.mjs --place-in-app` | 更新 `resfile` 容器 |

### 6.1 身份 / 签名矩阵

| 产物 | bundleName | buildMode | signingConfig | 证书 + Profile | 本机可侧载 |
|---|---|---|---|---|---|
| 日常调试构建 | `com.dshm.dshclient` | debug | `debug` | `.certs/debug-local/xiaobai.p12` + `.certs/multihap-20261024/DSHM-multihap-debug-pc-phone-20261024.p7b` | **是**（Profile 的 `device-ids` 含本机 UDID `20DB409A…`，2026-11-18 实测） |
| Beta（canonical） | `com.dshm.dshmbeta` | debug | `debug`，构建期 Profile 临时换成 `signing/debug/default_desktop.ohos.arm64_*.p7b` | 同上证书 + 该 beta debug Profile | **否**（设备侧 9568322） |
| Beta（local-install） | `com.dshm.dshmbeta` | debug | `devecocli signature generate` 生成的 `default` | `~/.ohos/config/` 下本机物料（含本机 UDID） | **是** |
| AGC | `com.dshm.dshclient` | release | `release` | `.certs/release1012/dshm.p12`（alias `ohosdshm`）+ `.certs/release-20261109/DSHM1109Release.p7b` | **否**（release 不可侧载） |

约束：

- AGC Profile 必须是 `type=release`、`app-distribution-type=app_gallery`、`bundle-name=com.dshm.dshclient`、
  `app-identifier=6917614360926110054`，且未过期；entry 声明的受控权限必须全部在 `allowed-acls` 内。
- Beta 用独立 bundle（`com.dshm.dshmbeta`）与独立 App ID（`6918745051729970584`），**不能沿用正式 App ID 的 ACL**；
  beta Profile 缺 ACL 时会直接报错（`--existing-beta-upgrade` 只用于"设备上已有同签名 beta"的覆盖升级，不得分发全新安装）。
- 版本号只在用户明确要求时改；不要为了刷图标或换包自行升 `versionCode`。

### 6.2 工具与前置

| 工具 | 用途 | 调用方式 |
|---|---|---|
| `devecocli` | 唯一构建入口（内部调 hvigor / SDK） | `devecocli build [--product X] [--build-mode debug\|release]` |
| `tools/build-node-cli.mjs` | 生成随包 node CLI | 出包脚本自动调用 |
| `tools/sign-bundled-libs.mjs` | 给随包 `libnode` 补 `.codesign`（否则 exec 域 `dlopen` 被拒） | 出包脚本自动调用 |
| `tools/place-ffmpeg.mjs` | 落位 ffmpeg 资产 | 出包脚本自动调用 |
| `tools/place-host-app.mjs` | 把宿主 JS 垫片写进 `resfile`（身份替换后必须重放） | 出包脚本自动调用；恢复身份后也要重跑 |
| `tools/pack-core.mjs` | 重打核心容器 | 见 §6.5 |
| `tools/build-beta.mjs` | Beta 包（临时身份 + 调 `devecocli` + 校验 + 还原） | 见 §6.3 |
| `tools/build-agc.mjs` | AGC 包（release product + 校验 + 还原） | 见 §6.4 |
| `hap-sign-tool` | 独立验签 | `<SDK>/default/openharmony/toolchains/lib/hap-sign-tool verify-app ...` |
| `devecocli signature generate` | 生成本机调试签名并写入 `build-profile.json5` | 仅 local-install 流程使用 |

前置检查：

1. 会话目录 = 工程根（`build-profile.json5` 所在处）。
2. `DEVECO_HOME` 已导出（本机默认已设；脚本也会回退到 hnp 工具链路径）。
3. 磁盘余量 ≥ 2 GB；`dist/beta`、`dist/release-test` 不要手删。
4. 当前没有别人同时在改 `build-profile.json5` / `AppScope/app.json5`。

> **登录不是构建前置。** `devecocli build`、Beta、AGC 都用仓库内既有签名物料（`debug` / `release` signingConfig），
> **不调用 `signature generate`、不需要 `auth login`**。2026-11-18 用 `DEVECO_CLI_AUTH_SOURCE=deveco-code`
> 模拟未登录实测：`signature generate` 报 `Run devecocli auth login to sign in`（rc=1），
> 而 `devecocli build --product default` **rc=0 / BUILD SUCCESSFUL**。只有 §6.8 的 local-install 重签需要登录。

### 6.3 Beta 包（canonical）

```sh
CODEBUDDY_SAFE_DELETE_ENABLED=0 node tools/build-beta.mjs --combined-app
```

脚本内部顺序（了解即可，不要手工照做）：

1. 校验 beta debug Profile 的 ACL 面；跑 `check-host-port-isolation`。
2. `build-node-cli` → `sign-bundled-libs` → `place-ffmpeg`。
3. `devecocli build clean`。
4. 备份并替换 16 个身份文件：`com.dshm.dshclient` → `com.dshm.dshmbeta`，
   `DSHM` → `DSHM beta`，`Jinghong` → `Jinghong beta`；替换 `build-profile` 里的调试 Profile 路径。
5. 默认注入 `ACCESS_USER_FULL_DISK`（`--no-full-disk` 关闭），仅构建期，`finally` 恢复。
6. 把 `hostruntime` 的 target 临时并入 `default` product，执行
   `devecocli build --product default --build-mode debug`。
7. 校验产物：beta 身份 / `versionCode` / debug 模式 / entry 18 条 / phone 9 条。
8. 把 `tablet/`、`phone/`、三端合一 `.app`、`SHA256SUMS`、`README.txt` 写入输出目录；
   `finally` 逐字还原 16 个文件并重放 `place-host-app`。

产物：`dist/beta/DSHM-beta-<versionName>-<versionCode>-<stamp>/`

```text
DSHM-beta-…-combined-debug.app
tablet/{entry hap, hostruntime hsp, …}
phone/{phone hap, hostruntime hsp, …}
SHA256SUMS
README.txt
```

> `tablet/`、`phone/` 只是便于检视的拆包目录，**签名仍来自 beta Profile，真机侧载必报 9568322**；
> 要装到本机必须走 §6.8 local-install。

参数：

| 参数 | 作用 |
|---|---|
| `--combined-app` | 兼容旧命令，等价默认行为（可省略） |
| `--out <dir>` | 自定义输出目录；目录已存在会拒绝覆盖 |
| `--sideload-only` | 额外把整个输出目录打成 zip |
| `--no-full-disk` | 不注入 2in1 全盘权限 |
| `--existing-beta-upgrade` | 设备已有同签名 beta 的覆盖升级场景，ACL 不齐只告警 |
| `--pc-only` | 已废弃，直接报错 |

### 6.4 AGC 包

```sh
CODEBUDDY_SAFE_DELETE_ENABLED=0 node tools/build-agc.mjs
```

脚本内部顺序：

1. 读 `build-profile.json5` 的 `release` signingConfig，校验证书 / Profile 存在。
2. 解析 Profile：`type`、`bundle-name`、`app-identifier`、`app-distribution-type`、`allowed-acls`、有效期；
   entry 声明的受控权限必须全部被批准，否则当场失败。
3. `build-node-cli` → `sign-bundled-libs` → `place-ffmpeg` → `place-host-app` → `devecocli build clean`。
4. 临时新增 `release` product（`signingConfig=release`、`bundleName=com.dshm.dshclient`），
   保留占位 `default` product（hvigor 要求）。
5. `devecocli build --product release --build-mode release`。
6. 取 `build/outputs/release/DSHM-deveco-workspace-release-signed.app`，逐项校验后写入交付目录，
   生成 `.app.sha256` 并追加 `SHA256SUMS.txt`。
7. `finally` 恢复 `build-profile.json5` 并重放 `place-host-app`。

产物：

```text
dist/release-test/dshm-<versionName>-<versionCode>-<coreTag>-AGC-invite-<stamp>.app
dist/release-test/…app.sha256
dist/release-test/SHA256SUMS.txt
```

校验内容（任一项不符即失败）：

- `pack.info` 的 bundle / versionName / versionCode；
- 模块设备面：entry `tablet,2in1`、phone `phone`、hostruntime 三端；
- 权限：entry 18 / phone 9；
- HSP 内核心容器**恰好 1 份**且版本与 `core-recipe.json` 一致；HSP 不含 ffmpeg 资产；
- 不得内置 `dsh-bili-whale`；
- `hap-sign-tool verify-app` 通过。

**AGC 包只能上传到 AppGallery 分发，不能本地侧载。**

### 6.5 核心容器（先重打，再出包）

触发：改了 `hostcore/plugins/**`、核心树内容、`core-recipe.json`。

```sh
CODEBUDDY_SAFE_DELETE_ENABLED=0 node tools/pack-core.mjs --skip-install --place-in-app
node tools/check-resfile-core-zip.mjs
node tools/assert-resfile-sync.mjs
```

- `--place-in-app` 才写 `hostruntime/.../resfile/`；裸命令只产出 `dist/core/`。
- resfile 只允许 1 份 `dsh-core-*.zip`；旧包必须显式删除，不能只拷新的。
- 顺序：**重打容器 → 出 Beta / AGC**；反过来会带旧插件上线。

### 6.6 出包后核验（必做）

```sh
# 权限面
node tools/check-permission-surface.mjs
# 核心容器
node tools/check-resfile-core-zip.mjs
# 独立验签（java 可用）
/data/service/hnp/hmos-clt.org/hmos-clt_1.0.0/sdk/default/openharmony/toolchains/lib/hap-sign-tool   verify-app -inFile <signed.hap 或 .app> -outCertChain /tmp/v.cer -outProfile /tmp/v.p7b
# 校验和
cd <交付目录> && sha256sum -c SHA256SUMS.txt
```

结论必须分开写：「包结构核验通过」≠「真机可用」。平板 / 手机需用户真机自测。

### 6.7 构建错误码

| 错误 | 含义 | 处置 |
|---|---|---|
| `9568322` | 签名来源不匹配（canonical Beta 典型） | 走 §6.8 local-install 重签，不卸载 |
| `9568286` | provision type 不同（debug / release 混装） | 换同类型包覆盖安装 |
| `956320 no signature file` | 用了从 `.app` 解出的未签名 hap | 改用 module 产物 `*-signed.hap/hsp` |
| `9568267` / `9568287` | 多 entry HAP 数量不合法（`.app` 或扁平目录里出现多个 entry） | 本地安装器一次只收一个 entry；从 `.app` 解包时按 `tablet/`、`phone/` 分开装 |
| `00303107 Invalid storeFile` | 签名物料缺失 / 口令错 | 检查 `signing/**`、`.certs/**`，不要删 |
| `Profile 已过期` | release Profile 过期 | 在 AGC 重新申请，不要改有效期 |

### 6.8 本机可侧载包（local-install）

canonical Beta 的 Profile 与证书不是同一密钥，本机装不上。已验证的替代流程：

0. **先登录**：`devecocli auth status` 确认已登录；未登录先 `devecocli auth login`。`signature generate` 依赖它，本机 2026-11-18 实测未登录会直接失败（`Run devecocli auth login to sign in`）。
1. 备份 16 个身份文件（与 `build-beta.mjs` 的 `TEXT_EDITS` 同集）到
   `dist/acceptance/<批次>/originals/`，写 `MANIFEST` + sha256。
2. 按 Beta 同口径替换包名与字符串；**不注入全盘权限**（生成的 Profile 没有该 ACL）。
3. `devecocli signature generate` → 生成 `default` signingConfig；
   **把 `default` 与 `phone` 两个 product 的 `signingConfig` 都指向它**（工具只自动改第一个）。
4. `node tools/place-host-app.mjs`。
5. `devecocli build --product default` + `devecocli build --product phone`。
6. 从**产物目录**取 `*-signed.hap/hsp`，组装 `tablet/`、`phone/` + `SHA256SUMS` + `README-LOCAL.txt`；
   安装顺序 **HSP → HAP**：`hdc install -r <hsp>` → `hdc install -r <hap>`。

> 为什么这里**不注入** `ACCESS_USER_FULL_DISK`：`devecocli signature generate` 生成的调试 Profile 没有该 ACL，
> 注入了也拿不到，反而会让安装校验更复杂。canonical Beta 用的是 beta Profile（已批该 ACL），所以在 §6.3 注入；
> 两者身份、Profile、用途都不同，不是矛盾。
7. 收尾：16 文件按 MANIFEST 逐字还原（比对 sha）、重跑 `place-host-app`、复跑门禁。

### 6.9 构建禁令

1. 不手工改 `build-profile.json5` 的签名 / 身份后直接出包（脚本会还原，手改会留下脏身份）。
2. 不复用旧 `build/` 产物判断"已构建"；身份变了必须 `build clean`。
3. 不从 `.app` 里解模块安装。
4. 不侧载 AGC release 包。
5. 不因为安装失败就卸载 / 清数据。
6. 不自行升版本号；不在未经用户确认时上传 AGC 或提交审核。

## 7. 测试与门禁

### 7.1 分层

| 层 | 手段 | 何时跑 |
|---|---|---|
| 静态 | `check_ets_files` / `check_cpp_files` / `devecocli check lint` | 每次改完源码 |
| 构建 | `devecocli build --product default`（entry）/ `--product phone`（phone） | 每次改动 |
| 契约门禁 | `tools/check-*.mjs` / `assert-*.mjs` | 按功能域跑；出包跑全量 |
| 包结构 | `check-permission-surface`、`check-resfile-core-zip`、独立验签 | 每次出包 |
| 真机 | 覆盖安装 + 启动 + 关键路径 | 有设备时；平板/手机交用户 |

### 7.2 全量回归

```sh
# 改过 gates.yml：重生成全量基线
python3 dist/acceptance/gen-full-yml-gates.py dist/acceptance/<日期>-full-gates.txt

# 日常回放：只能用最新全量报告
python3 dist/acceptance/rerun-gates.py <基线报告> <输出报告>
```

- 任何 ok→fail 当场修，不许延后；「CI 绿」不等于「全绿」。
- `check-two-project-parity.mjs` 因对端已删必然 rc=2，**不作判据**。
- 新增门禁必须带 `--self-test` 变异体（少一条 / 改 reason / 还原旧形态都必须判红）。
- **门禁必须自洽**：判据不得依赖宿主 `grep/sed/awk/node` 版本差异；要用外部命令就在临时 `PATH` 里桩化
  （先例：`check-guest-terminal-lifecycle` 因宿主 toybox `grep -Fxq` 静默返回 1 而假红，见 `docs/PITFALLS.md` §4.4）。

## 8. 红线

1. **真机数据**：只允许覆盖安装（`hdc install -r`）；禁止 `hdc uninstall` / `bm uninstall` / 删 `el2`。
2. **签名物料**：`signing/**`、`.certs/**`、`AGC-operations/release-signing/**`、含口令的 `build-profile.json5` 永不删除。
3. **权限面**：entry 18 / phone 9；不新增未审批 ACL；不声明无消费点的权限；不靠删权限排障。
4. **版本号**：只在用户明确说「升到 X」时改。
5. **交付件**：`dist/release-test/*.app`、`dist/beta/*`、`dist/core/*.zip`、`dist/acceptance/*`、`dist/frozen/*`、`SHA256SUMS.txt` 一律不删。
6. **代码**：不提交、不推送；不删 `resfile/`、不删自带插件与 toolchain 资产。

## 9. 文档与知识管理

### 9.1 文档分层

| 类型 | 位置 | 规则 |
|---|---|---|
| 规范 | `AGENTS.md` | 只写当前口径 |
| 操作 | `AGENT-HANDOFF.md` | 命令 / 环境变了就改 |
| 状态 | `docs/HANDOFF.md` | 每轮更新；只写现在 |
| 功能台账 | `docs/FEATURES.md` | 改功能必须同步；含历史里程碑 |
| 坑 / 决策 | `docs/PITFALLS.md`、`docs/DECISIONS.md` | 新坑 / 拍板就追加 |
| 契约 | `docs/parity-matrix.md`、`docs/199-*.md` | 由门禁消费，不得删改模式 |
| 跨角色交接 | `JD/` | WorkBuddy 落地后写 `JD/from-workbuddy/`；DevEco 编译/测试/复核后回 `JD/from-deveco/`；看板 `JD/STATUS.md`；不参与 `check-doc-*` |
| 历史 | `docs/archive/` | 只读；不参与门禁；不作为口径 |

### 9.2 写作规则

1. 只记**确认无误的事实**；过程、复盘、审核回合不进权威文档。
2. 一问题一篇；同一问题多篇时合并，其余归档。
3. 不抄可漂移值；引用用节标题或相对链接，**不用行号**。
4. 新功能 ⇒ 台账加行；新决策 ⇒ 决策表加行；新坑 ⇒ 坑档加行。
5. 改完跑 `node tools/check-doc-index.mjs` 与 `node tools/check-doc-refs.mjs`。
6. 归档：`docs/archive/<编号>-*.md`；归档清单在 `docs/archive/MIGRATION.txt`。

### 9.3 跨角色协作（JD）

- **分工**：WorkBuddy 负责开发落地与自测；DevEco 负责编译、测试、复核。
- **通道**：`JD/from-workbuddy/`（交接单）↔ `JD/from-deveco/`（结论）；状态统一记在 `JD/STATUS.md`。
- **规则**：交接单用 `JD/templates/handoff.md`；每项一个 ID（如 JD-001）；门禁红不得写成通过；闭环后移入 `JD/archive/`。
- `JD/` 是协作过程区，**不参与** `check-doc-*` 门禁，也不替代 `AGENTS.md` / `docs/`。

## 10. 变更记录

- 每次实质工作追加 `.workbuddy/memory/YYYY-MM-DD.md`（append-only）。
- 跨会话长期口径写 `.workbuddy/memory/MEMORY.md`。
- 记录：结论、证据路径、取舍、遗留风险；不写临时路径与工具报错。

## 11. 已核事项（2026-11-18 结论）

| 项 | 结论 | 依据 |
|---|---|---|
| `build-agc.mjs --device-sideload` 的指定设备 Profile 是否配套 | **不配套，无明确需求不要用**。该 p7b 是 `inttesting` / `version-name 2.0.0` / `version-code 2`（有效期至 2027-04-24），属 1.1.6 轮次遗留；要用必须按当前版本重新申请 | `.certs/multihap-20261024/DSHM-prod-1.1.6-1010007-specified-device-20261024.p7b` 实读 |
| phone `getUserMedia` 与 CoreSpeechKit 的并存关系 | **并存且有意**：Web 官方语音走 `getUserMedia` → `onPermissionRequest`；原生 ASR 覆盖绕过它，所以两条壳都主动 `requestPermissionsFromUser(MICROPHONE)`。两条路径都需要该权限 | `entry/`、`phone/` 的 `WebApp.ets`（`MIC_PERMISSION` 两处调用） |
| `dist/core/work/.pack-core-pristine/` 用途 | **必须保留**：`pack-core` 可重入补丁的"未打补丁原文 + 上次哈希"。删掉会导致补丁无法安全重打，甚至把上游更新降级 | `tools/pack-core.mjs` 的 pristine 段 |
| `dist/node/` 两个 `pre-*.so` 回退备份 | **保留**：libnode 中性化前后的回退备份，只在 `docs/archive/366-*` 的回退步骤使用，不随包、不被构建读取；按交付件红线不删 | `dist/node/` 实读、`docs/archive/366-*` |
| AGC 元数据与 `AppScope` 品牌一致性 | **一致**：`app_name` / `EntryAbility_label` 均为 `DSHM`；`metadata/*.json` 用 `DSHM`，无「鲸鸿」文案（仅历史文件名含 jinghong） | 实读字符串资源与 metadata |
| `gen-oss-notices.mjs` 空 ohpm 段 | **有意保留**：sherpa 移除后 `OHPM_COMPONENTS` 为空，输出保留空段以兼容既有声明格式；不影响审核文本 | `tools/gen-oss-notices.mjs` 头注 |

## 附录 历史沿革（只读）

事故因果链、权限面沿革、libnode 崩溃链、核心升级逐档记录：
`docs/archive/80-*`、`docs/archive/143-*`、`docs/archive/203-*`、`docs/archive/222-*`、
`docs/archive/365-*`、`docs/archive/366-*`、`docs/archive/367-*`。

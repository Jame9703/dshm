# AGENT-HANDOFF —— 交给下一个 AI 的第一份文件

> 目标：拿到本工作区就能**直接干活**，不用再问「怎么编译」「怎么出包」「用哪个技能」。
> 本文只写**实测过的操作**与**默认决策**。会漂移的值（版本号、核心版本、权限条数、设备面）
> 一律不抄，去单一真源读，见 [`AGENTS.md`](AGENTS.md) §1 与本文附录 B。
>
> 硬规则与红线以 [`AGENTS.md`](AGENTS.md) 为准；本文与它冲突时，**以 AGENTS.md 为准并当场改本文**。

---

## §0 30 秒上手

```sh
# DevEco Code 里先把会话目录切到工程根（MCP 静态检查的前置条件）
switch_cwd ~/data/DSHM-deveco-workspace

hdc tconn 127.0.0.1:45595      # 本机即该鸿蒙 PC，先连回环；device list 为空时必跑
devecocli device list          # 确认有设备（本机常态：MateBook 14 2in1，127.0.0.1:45595）
devecocli build --product default  # entry + 共享 HSP；不带 --product 会因双 entry 报错
devecocli run --skip-build     # 装到设备并启动（覆盖安装，不会清数据）
```

> 工作区根目录就是工程根（`build-profile.json5` 所在处）；`devecocli` 与 `node tools/*.mjs`
> 都在这里执行，不要进子目录跑。


### 60 秒自检（新接手先跑）

```sh
node tools/check-permission-surface.mjs   # 权限面 18/9
node tools/check-doc-index.mjs            # 编号文档索引
node tools/check-doc-refs.mjs             # 文档引用不漂移
node tools/check-resfile-core-zip.mjs     # resfile 只 1 份核心容器
node tools/assert-resfile-sync.mjs        # 宿主垫片与 resfile 同步
```

五条全绿 = 环境与交付面就绪；任一条红，先修它再动代码。

出包只有两条命令，别自己拼 hvigorw：

```sh
# Beta（本地测试用，包名临时切 com.dshm.dshmbeta）
CODEBUDDY_SAFE_DELETE_ENABLED=0 node tools/build-beta.mjs --combined-app

# AGC（正式包，包名 com.dshm.dshclient，出完不可本地侧载）
CODEBUDDY_SAFE_DELETE_ENABLED=0 node tools/build-agc.mjs
```

三条不许做：`git commit`、`hdc uninstall` / `bm uninstall`、删 `signing/` `dist/` `resfile/`。

---

## §1 环境事实（2026-11-18 实跑，非文档转抄）

| 项 | 实测结果 | 备注 |
|---|---|---|
| CLI | `devecocli` 1.3.4，`~/.deveco/bin/devecocli` | 子命令：build / run / device / log / ui / signature / check / docs / skills / create / init |
| 工具链根 | `DEVECO_HOME=/data/service/hnp/hmos-clt.org/hmos-clt_1.0.0` | `tools/lib/deveco-home.mjs` 也按它解析 |
| node | 本机 PATH 上有 `node`（`--version` 自取，不抄） | 脚本统一用 `node tools/*.mjs` |
| java | OpenJDK 26，位于 `~/.harmonybrew/bin`（可能不在 PATH） | `hap-sign-tool`（SDK 全路径）可独立验签，见 §3.7；裸 `java` 若报找不到，把该目录加入 PATH |
| hdc | Ver 3.2.0f（`/data/service/hnp/hmos-clt.org/.../toolchains/hdc`，不在 PATH） | 优先用 `devecocli` 包装；回环调试需先 `hdc tconn` |
| 设备 | **本机即该鸿蒙 PC**（MateBook 14 2in1，API 26），无线调试常驻 `127.0.0.1:45595` | `device list` 为空先 `hdc tconn 127.0.0.1:45595`；随后可直接覆盖安装推送测试；平板 / 手机形态需用户真机自测 |
| IDE | **DevEco Code（AI IDE）可用；DevEco Studio GUI 不可用** | 只有命令行工具链 + CLI，不要让人去点「Project Structure」 |
| 2in1 | **没有 emulator 子命令** | 没设备就让人开无线调试 → `hdc tconn 127.0.0.1:<port>`，别建议启动模拟器 |
| 删除 | `rm` 被 safe-bin shim 接管 | 删除一律 `python3` 的 `os.remove` / `shutil.rmtree`，删完回读验证 |
| 长命令 | 出包 / 打包会撞 safe-delete 批量阈值（50） | 只对**单条**构建命令加 `CODEBUDDY_SAFE_DELETE_ENABLED=0` |

> 历史文档里「本机无 hdc / 无 java」的结论已过期（2026-11-18 实测两者都可用）。
> 仍然成立的是：**AGC release 包不可本地侧载**；canonical Beta 包侧载会报 9568322（见 §3.3）。

---

## §2 工具怎么调

### 2.1 `devecocli` —— 唯一的构建 / 设备入口

| 目的 | 命令 |
|---|---|
| 默认构建（entry 平板/2in1 + 共享 HSP：hostruntime/connection/appstate/dshcompat/platform） | `devecocli build --product default` |
| 手机 product（phone + 共享 HSP） | `devecocli build --product phone` |
| 指定模块（一般不用） | `devecocli build --modules entry@default` |
| 清构建产物 | `devecocli build clean` |
| 装 + 启动 | `devecocli run [--skip-build] [--device <名或序列号>] [--module ...] [--ability ...]` |
| 设备列表 / 详情 | `devecocli device list` / `devecocli device view -t <serial>` |
| 应用日志 / 崩溃 | `devecocli log --bundle-name com.dshm.dshmbeta --crash --follow` |
| 看界面 | `devecocli ui layout` / `ui screenshot` / `ui click` / `ui swipe` / `ui text` |
| Lint | `devecocli check lint <path>` |
| 本机调试签名 | `devecocli signature generate [--force] [--product default]` |
| 官方文档 | ⚠ 本机 `devecocli docs search` 因 better-sqlite3 原生绑定缺失**不可用**；改查本地知识库 `~/data/HarmonyOS-KB`（见 `docs/PITFALLS.md` §4.3） |

**禁用**：直接 `hvigorw`（`devecocli build` 已包装）；有 `devecocli` 包装时直接 `hdc`；`deveco preview`。
任务要「查 ArkTS / ArkUI / 权限 / API 官方说法」时，查本地知识库 `~/data/HarmonyOS-KB`（`catalog/docs.jsonl` + `docs/<alias>/<slug>.md`），不要靠记忆答；不要在 `devecocli docs search` 上反复试（本机不可用）。

### 2.2 静态检查（DevEco Code 内置 MCP）

- `check_ets_files`：改完 `.ets` 立刻跑，比全量构建快，专抓 ArkTS 严格模式违规。
- `check_cpp_files`：改完 `.c/.cpp/.h` 先跑它再全量构建。
- **前置**：会话目录必须等于工程根，否则先 `switch_cwd`。
- 失败后先按 `arkts-error-fixes` / `arkts-grammar-standards` 两个技能修，再 `check_ets_files` → `devecocli build` 复验。

### 2.3 UI 验证（严格 opt-in）

- **只有**用户消息里出现「验证 UI / UI 走查 / 看截图效果 / verify ui / 视觉验收」才可调用 `verify_ui`。
- 「加个页面」「改样式」「修 bug」**不是**触发条件；`devecocli build` 绿就是完成标准。
- 同一目标（同一 testPlan）最多 3 次；第 3 次失败后停下，报告 failPart + 假设，等用户决定。
- 日志回看用 `get_ui_verification_log`，截图落盘用 `save_ui_screenshot`。

### 2.4 设备纪律（红线，别试探）

- 只允许覆盖安装：`hdc install -r <hsp>` → `hdc install -r <hap>`（先 HSP 后 HAP）。
- `hdc` 若不在 PATH（位于 `<SDK>/default/openharmony/toolchains/hdc`）：先 `export PATH="<该目录>:$PATH"`，或改用 `devecocli` 包装；回环调试先 `hdc tconn 127.0.0.1:45595`。
- 禁止 `hdc uninstall` / `bm uninstall` / 删 `/data/app/el2/**`。历史事故：一次裸 uninstall 永久丢失 6 会话 / 7 插件 / 2 工作区。
- 真机安装失败先看错误码：9568322 = 签名来源不匹配；9568286 = provision type 不同；`956320 no signature file` = 用了从 `.app` 里解出来的未签名 hap。

---

## §3 构建配方

> **唯一真源是 [`AGENTS.md`](AGENTS.md) §6**（身份矩阵、脚本内部步骤、校验项、错误码）。
> 本节只做速查；两处冲突时以 AGENTS.md §6 为准并当场修本节。

### 3.1 日常编译

```sh
devecocli build --product default  # entry + 共享 HSP
devecocli build --product phone  # 手机壳
devecocli run --skip-build       # 用已有产物装到设备
```

产物位置（记牢，别去 `.app` 里解）：

- `entry/build/default/outputs/default/entry-default-signed.hap`
- `hostruntime/build/default/outputs/default/hostruntime-default-signed.hsp`
- phone 的 module 产物在 `phone/build/phone/outputs/default/phone-default-signed.hap`（`phone/build/default/` 是旧缓存）

### 3.2 Beta 包（canonical）

```sh
CODEBUDDY_SAFE_DELETE_ENABLED=0 node tools/build-beta.mjs --combined-app
```

- 默认产出三端合一 `.app` + `tablet/` + `phone/` + `SHA256SUMS` + `README.txt`，目录 `dist/beta/DSHM-beta-<ver>-<code>-<stamp>/`。
- `tablet/`、`phone/` 只是检视用拆包，**签名仍是 beta Profile，侧载必报 9568322**；装本机走 §3.3。
- 参数：`--out <dir>`（目录已存在会拒绝覆盖）、`--sideload-only`、`--no-full-disk`（不注入 2in1 全盘权限）、`--existing-beta-upgrade`。
- `--pc-only` 已废弃，别用。
- 脚本在 `finally` 里逐字还原身份与 `build-profile.json5`；**不要手工改完不等它还原**。
- 固定身份替换：`com.dshm.dshclient` → `com.dshm.dshmbeta`，`DSHM` → `DSHM beta`，`Jinghong` → `Jinghong beta`。

### 3.3 要装到本机时：local-install（9568322 的既定走法）

canonical Beta 的 profile（`signing/debug/…p7b`）与 `build-profile.json5` 里的证书**不是同一密钥**，
侧载必报 `9568322`。本机能装的是**本机调试签名重出**的包，流程已验证（2026-11-18）：

0. **先登录**：`devecocli auth status` 显示已登录；否则 `devecocli signature generate` 报 `Run devecocli auth login to sign in`，先 `devecocli auth login`。
1. 备份 16 个身份相关文件（与 `build-beta.mjs` 的 `TEXT_EDITS` 同集）到 `dist/acceptance/<批次>/originals/`，写 `MANIFEST` + sha256。
2. 按 Beta 同口径替换包名与字符串（不注入全盘权限，生成 profile 没有 ACL）。
3. `devecocli signature generate` → 生成 `default` signingConfig；**把 default 与 phone 两个 product 的 signingConfig 都指过去**（工具只自动改第一个 product）。
4. `node tools/place-host-app.mjs`。
5. `devecocli build --product default` + `devecocli build --product phone`。
6. 从**产物目录**取 `*-signed.hap/hsp` 组装 `tablet/` 与 `phone/` 两个目录 + `SHA256SUMS` + `README-LOCAL.txt`，安装顺序 **HSP → HAP**。

坑：

- 从 `.app` 里 `unzip -p` 出来的 HAP/HSP 没有独立签名，装不上（`956320`），必须用 module 产物。
- `--modules phone` 会 1 task 空转不产出，**必须用 `--product phone`**。
- 恢复：16 文件按 MANIFEST 逐字还原（比对 sha）、重跑 `place-host-app`，再复跑门禁。
- 每次 `signature generate` 都会重签（证书序列号变化），设备上旧调试身份会被换掉；debug→debug 覆盖安装仍可用。

### 3.4 AGC 包

```sh
CODEBUDDY_SAFE_DELETE_ENABLED=0 node tools/build-agc.mjs
```

- 产出 `dist/release-test/dshm-<ver>-<code>-dshm.1-AGC-invite-<stamp>.app` + `.app.sha256` + `SHA256SUMS.txt`。
- 走 hvigor **release 签名**，不需要手工签名；脚本构建前自验发布 Profile 的 `allowed-acls`，`finally` 恢复 `signingConfig`。
- **不登录、不上传、不提审**；上传 / 审核是人工动作。
- **release 包不可本地侧载**，真机验证一律用 Beta local-install。
- `--device-sideload` 用的是 1.1.6 轮次的指定设备 Profile，与当前版本不联动；没有明确要求不要加。

### 3.5 核心容器重打（触发条件）

改了 `hostcore/plugins/**` 或核心树内容，**必须**：

```sh
CODEBUDDY_SAFE_DELETE_ENABLED=0 node tools/pack-core.mjs --skip-install --place-in-app
```

- `hostruntime/.../resfile/dsh-core-*.zip` 是静态产物；只出包不重打 = 带着旧插件上线。
- `--place-in-app` 才写 resfile；裸命令只产出 `dist/core/`。
- resfile 只允许 1 份容器：`node tools/check-resfile-core-zip.mjs`。

### 3.6 门禁回归

```sh
# 改过 gates.yml：从工作流现提全部命令，重生成全量基线
python3 dist/acceptance/gen-full-yml-gates.py dist/acceptance/<日期>-full-gates.txt

# 日常回归：按既有全量基线回放
python3 dist/acceptance/rerun-gates.py <基线报告> <输出报告>
```

- 回放基线**只能用最新全量报告**（`dist/acceptance/` 中 mtime 最新的 `*full-gates*.txt`；条数以报告首行为准）。
- 回放旧基线会冻结更早的命令清单，新增门禁漏网（2026-11-16 已发生一次）。
- 任何 ok→fail 当场修，不许延后。
- `check-two-project-parity.mjs` 因对端工作区已删必然 rc=2，**不作判据**。

### 3.7 出包后的包结构核验（必做）

```sh
# 权限面（唯一裁判，含变异体自检）
node tools/check-permission-surface.mjs
# 独立验签（java 可用时）
/data/service/hnp/hmos-clt.org/hmos-clt_1.0.0/sdk/default/openharmony/toolchains/lib/hap-sign-tool \
  verify-app -inFile <signed.hap> -outCertChain /tmp/v.cer -outProfile /tmp/v.p7b
```

逐项核：`pack.info` 身份（bundle / versionName / versionCode）、模块设备面、
权限 entry 18 / phone 9、HSP 内核心 zip 的 sha 与 `hostcore/core-recipe.json` 一致、
两壳关键 abc 字符串、`.app.sha256` 与 `SHA256SUMS.txt` 一致、无 `dshmbeta` 残留。

---

## §4 技能目录（按任务选，不要重复安装）

| 任务 | 技能 | 位置 |
|---|---|---|
| 任何 HarmonyOS 构建 / 运行 / 设备 / 文档 / 技能管理 | `deveco-cli` | `~/.local/share/deveco/skills/deveco-cli` |
| 写 / 改 `.ets` 前（ArkTS 语法约束、组件、状态管理） | `arkts-grammar-standards` | `~/.local/share/deveco/skills/` |
| ArkTS 编译报错 | `arkts-error-fixes` | 同上 |
| 闪退 / 白屏 / jscrash / 无编译错的运行时故障 | `arkts-runtime-fix` | 同上 |
| 改 DevEco Code 自身配置 / 新建 skill | `customize-deveco` | 同上 |
| 内存防劣化、htrace、topdown 对比 | `hmos-memory-anti-regression` | `.deveco/skills/` |
| ArkTS 规则预审（无编译器时） | `arkts-compile-fixing` | `.dsh/skills/` |
| HarmonyOS 官方文档细节（离线 13k 篇） | `harmonyos-docs-kb` | `.dsh/skills/`（库在 `~/data/HarmonyOS-KB`） |
| AGC：登录、建应用、上传、证书 / Profile / ACL、邀请测试 | `hmos-connect-api-cli-skill` | `.dsh/skills/`（同 `AGC-operations/cli/`） |
| 上架元数据合规预审（名称 / 描述 / 关键词 / 隐私链接） | `app-metadata-audit-skill` | `.dsh/skills/` |
| 多设备适配 / 窗口 / 沉浸 / 崩溃分析等华为官方技能 | `hmos-*` | `.opencode/skills/`、`devecocli skills list` |

调用方式：

- DevEco Code：用 `skill` 工具按名字加载。
- 其它 agent：直接读对应目录的 `SKILL.md`（脚本与资源在同目录）。
- 先 `devecocli skills list` / `skills find <关键词>` 再决定要不要 `skills add`；**已有的不要重复装**。

---

## §5 项目硬事实（细节点回 AGENTS.md）

| 事实 | 口径 |
|---|---|
| 三端归属 | PC/2in1/Edge/ProMax → entry（18 权限，原生 PTY）；平板 → entry（18，guest VM）；手机/折叠单屏 → phone（9，guest VM） |
| 权限面 | entry 恒 18 / phone 恒 9，条数+顺序+reason 钉死；ACL 以发布 Profile 的 `allowed-acls` 为准 |
| 版本号 | 只有用户明确说「升到 X」才改；不自作主张 |
| 核心版本 | `hostcore/core-recipe.json`；改了核心树必须重打容器 |
| 交付件 | `dist/release-test/*.app`、`dist/beta/*.app`、`dist/core/*.zip`、`dist/acceptance/*`、`dist/frozen/*`、`SHA256SUMS.txt` 一律不删 |
| 代码 | 永不 `git commit`（用户 2026-11-03 明确） |
| 文档 | 编号文档只记确认无误的结论；同一问题只留一篇；改完跑 `check-doc-index` / `check-doc-refs` |
| 记忆 | 每次实质工作追加 `.workbuddy/memory/YYYY-MM-DD.md`（append-only） |

---

## §6 默认决策表（这些不要再问）

| 场景 | 默认做法 |
|---|---|
| 改完代码怎么验证 | `check_ets_files` → `devecocli build --product default` → 相关门禁 |
| 要不要跑全量门禁 | 改了 `.ets` / 核心 / 权限 / 出包 ⇒ 跑；只改文档 ⇒ 跑 doc 两条 |
| 装设备用什么包 | Beta local-install（本机调试签名）；不用 canonical Beta，不用 AGC 包 |
| 装不上 9568322 | 走 §3.3 重签，不要卸载 |
| 设备上还有旧数据 | 正常，覆盖安装会保留；不要去「清理环境」 |
| 要不要出包 | 用户没说就**不出**；只编译 + 门禁 |
| 要不要升 versionCode | 不升 |
| 改了插件没生效 | 重打核心容器（§3.5） |
| 文档写哪里 | 状态改 `docs/HANDOFF.md`；功能改 `docs/FEATURES.md`；坑改 `docs/PITFALLS.md`；决策改 `docs/DECISIONS.md`；过程性内容进 `docs/archive/` |
| 要不要跑 verify_ui | 用户没明确要求就不跑 |
| 遇到不确定的 API | 查本地知识库 `~/data/HarmonyOS-KB`（`devecocli docs search` 本机不可用），再查 `.dsh/skills/harmonyos-docs-kb` |

**必须问用户的只有 4 类**：破坏性操作（卸载 / 清数据 / 删交付件）、改版本号、切换平台归属、
上传或提交审核。

---

## §7 高频问题（直接照这个答，不要重新推理）

1. **能不能 `hdc uninstall` 重装？** 不能。永久丢用户数据。只能 `install -r`。
2. **为什么装不上（9568322）？** canonical Beta 的 profile 与证书不同密钥。用 §3.3 本机调试签名重出。
3. **为什么 9568286？** provision type 不同（debug/release 混装）。换同类型包，别卸载。
4. **`956320 no signature file`？** 用了 `.app` 里解出来的未签名 hap，改用 module 产物 `*-signed.hap`。
5. **改了插件 / 核心但设备还是旧行为？** 没重打容器，跑 §3.5。
6. **能不能顺手升版本号？** 不能。只在用户明确要求时升。
7. **`dist/` 太大能删吗？** 不能删交付件；只能清各模块 `build/**` 和旧 `dist/core/work/**`。
8. **能 `git commit` 吗？** 不能，用户明令禁止。
9. **`check-two-project-parity` 红了怎么办？** 环境受限（对端工作区已删），不作判据，不改代码。
10. **平板为什么没有原生终端？** 只有 PC/2in1/Edge/ProMax 有；普通平板和手机走 guest VM（`docs/archive/413-*`）。
11. **首启为什么几十秒？** 首次解包 640 MB 核心；二次启动会回落，别当 bug。
12. **`devecocli build` 绿但页面白屏？** 查 `devecocli log --crash`，读 `arkts-runtime-fix`。
13. **要不要跑 `verify_ui`？** 用户没明确要求就不跑；要求了同一目标最多 3 次。
14. **MCP 检查报找不到工程？** 先 `switch_cwd` 到工程根。
15. **手机 product 构建没产物？** 必须 `--product phone`，不能用 `--modules phone`。
16. **AGC 包能装到本机吗？** 不能，release 不可侧载。
17. **`build-beta.mjs` 跑完源码变了吗？** 没有，`finally` 逐字还原；有疑问比对 `git status`。
18. **要不要手工改 `build-profile.json5`？** 不要，含明文口令且由脚本临时改；改完必须复原。
19. **Java 能不能验签？** 能，用 §3.7 的 `hap-sign-tool verify-app`。
20. **文档里版本号对不上？** 以 `AppScope/app.json5` 与 `core-recipe.json` 为准，HANDOFF 可能滞后，见附录 B。
21. **`signature generate` 报 `Run devecocli auth login to sign in`？** 本机未登录华为开发者账号；先 `devecocli auth login`（`auth status` 可查），登录后再重签构建。
22. **构建 Beta / AGC 需要登录吗？** 不需要。构建用仓库内 `debug` / `release` 签名物料；只有 `signature generate`（local-install 重签）需要登录。未登录实测 `build --product default` rc=0。
23. **`devecocli build` 报 “Multiple entry modules found”？** 本工程有 entry + phone 两个 entry；写 `--product default` 或 `--product phone`。

---

## §8 交付口径

- 「包结构核验通过」≠「真机可用」。本机只能证明前者；后者需用户真机反馈。
- 出包结论必须写清：包路径、大小、sha256、身份、权限条数、核心 sha、门禁报告路径。
- Beta canonical 侧载失败、AGC 包不可侧载、phone 未验证等边界要如实写，不许圆成「已验证」。
- 证据落 `dist/acceptance/<批次>/`；临时日志 / 截图也只落 `dist/`，别污染源码树。

---

## 附录 A 一页命令卡

```sh
switch_cwd ~/data/DSHM-deveco-workspace
devecocli device list
devecocli build --product default
devecocli run --skip-build
node tools/check-permission-surface.mjs
python3 dist/acceptance/gen-full-yml-gates.py dist/acceptance/$(date +%Y%m%d)-full-gates.txt
CODEBUDDY_SAFE_DELETE_ENABLED=0 node tools/pack-core.mjs --skip-install --place-in-app
CODEBUDDY_SAFE_DELETE_ENABLED=0 node tools/build-beta.mjs --combined-app
CODEBUDDY_SAFE_DELETE_ENABLED=0 node tools/build-agc.mjs
```

## 附录 B 单一真源（不要抄值，去这里读）

| 项 | 出处 |
|---|---|
| 版本 / 包名 | `AppScope/app.json5` |
| 核心版本 | `hostcore/core-recipe.json` |
| 权限面 | `tools/check-permission-surface.mjs` |
| 设备面 | `entry/` `phone/` `hostruntime/` 的 `module.json5` |
| 门禁清单 | `.github/workflows/gates.yml` + 最新 `dist/acceptance/*full-gates*.txt` |
| 工作规范 / 红线 | `AGENTS.md` |
| 当前状态 | `docs/HANDOFF.md` |
| 文档索引 | `docs/README.md` |
| 功能台账 | `docs/FEATURES.md` |

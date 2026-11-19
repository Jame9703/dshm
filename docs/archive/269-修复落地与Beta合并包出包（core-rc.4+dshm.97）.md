# 269 · 2026-10-28 修复落地与 Beta 合并包出包（core `0.2.1-rc.4+dshm.97`）

> 日期：2026-10-28 ｜ 状态：**已落地**（除"git 相关项"按用户指示不做）
>
> 上位文档：[`docs/267-迁移鸿蒙PC自托管开发缺口与修复方案.md`](267-迁移鸿蒙PC自托管开发缺口与修复方案.md)（本次逐项修复的出处）。
> 上游：DSH `0.2.1-rc.4`（用户已完成同步；本轮的 `recipe` / `dist/core` 容器 / resfile 三方一致，见 §2 P1-2）。
>
> 用户指令原文要点：**git 先不管（短期不会更新）**；把 `docs/267` 的问题都修了；上游已同步；**重编 Beta 版 APP 给我**。

---

## 1. 交付件（Beta 合并 APP）

| 项 | 值 |
|---|---|
| 路径 | `~/Download/com.dshm.dshclient/DSHM-beta-1.1.6-1010007-combined-debug.app` |
| 大小 | `511,527,599 B` |
| SHA-256 | `550b1c1a19c48a77f81bdf478736afa0b71efe13d4b2860a9303e84a647601a3` |
| 工作区留档 | `dist/beta/DSHM-beta-1.1.6-1010007-20261028T081519/`（含 `SHA256SUMS` + `README.txt`） |
| 构建命令 | `DSHM_FFMPEG_REUSE_ON_UNREADABLE=1 node tools/build-beta.mjs --combined-app` |
| 构建读数 | `BUILD SUCCESSFUL in 55 s 515 ms`；143 tasks executed |

**包内结构（逐条实读）**：

| 内层包 | module | type | deviceTypes | 权限 | apk 条目 |
|---|---|---|---|---:|---:|
| `entry-default.hap` | `entry` | entry | `tablet` / `2in1` | **17** | 0 |
| `phone-default.hap` | `phone` | entry | `phone` | **9** | 0 |
| `hostruntime-default.hsp` | `hostruntime` | shared | `phone`/`tablet`/`2in1` | 0 | 0 |

- `pack.info`：bundle `com.dshm.dshmbeta`（Beta 身份）、`1.1.6 / 1010007`；
- 身份还原自检：构建后 `AppScope/app.json5`、`entry/.../string.json` 与构建前**逐字节一致**（`finally` 生效）；
- **签名取证**：文件尾部含 **Beta App ID `6918745051729970584`**、1 份证书与 profile ⇒ 用的是 Beta 调试签名身份；hvigor 的两处签名步骤（`:entry:@SignHap` / `:phone:@SignHap` / `::SignApp`）均 reported finished；
- ⚠️ **未跑 `hap-sign-tool verify-app`**：本机 `PATH` 无 `java`、CLT 下也没有 `hap-sign-tool`，跑不了官方复验 —— 上面那条是**可自证的签名取证**，不等于官方 `verify-app success`。

---

## 2. 按 `docs/267` 逐项落地

| 编号 | 项 | 处置 | 证据 |
|---|---|---|---|
| P0-1 | `.certs/` 与 `.env` 未忽略 | **按用户指示不做**（git 短期不更新） | —— |
| P0-2a | 沙箱 `bin/node` 包装器失效 | ✅ 改 `hostcore/app/node-runtime-provision.cjs`：包装器**优先委托 `node-brew`**，失败才回退随包 `nodecli`；`main.js` 传入 `FULL_NODE_PATH`（由 `DSHM_PUBLIC_DOWNLOAD` 推出） | 探针真跑生成的包装器 ⇒ `v26.12.1`、rc=0；`source=wrapper(full-node→bundled)` |
| P0-2b | Codex `CODEX_HOME` 无人创建 | ✅ 两处：① `dshm-installer.js` 注入块补 `mkdirSync`（别名 import，ESM 安全）；② `main.js` **启动期自愈**（已装插件免重装） | 探针覆盖"首次打补丁 / 升级刷新 / 幂等复打"三条路径，`node --check` 全绿；`dshmMkdirSync` 恰出现 2 次（无重复插入） |
| P1-1 | 双端一致性门禁 6587 处"漂移" | ✅ **查明为假红并修门禁**（详见 §3） | 复跑 `rc=2`，精确列出 12 个 `EPERM` 目录；`--self-test` 臂 2 端到端断言 exit 2 |
| P1-2 | 核心树版本漂移 | ✅ 收口：配方 `rc.4+dshm.97`、`dist/core` 容器、resfile 放置件**三方 sha 一致**（`62371606027d3d70…`）；`rc.3` 残桩与本轮解出的树并存但不再是"配方不一致" | `check-resfile-core-zip` rc=0 |
| P1-3 | `AGENTS.md` 过期且超重 | ✅ **117,748 → 32,757 B**（预算 65,536）；权限口径改为「entry 恒 17 / phone 恒 9」并写明"8 条口径作废 + 删到 8 条=事故"；`beta 专用工作区` 一节换成与当前 PC 工程身份一致的「交付与身份」；流水账与历史坑库整体迁出 | `docs/268`；`grep -c "恒 8 条"` 只剩 1 处（历史沿革句，标明已作废） |
| P1-4 | 文档索引失效 | ✅ 补齐 **186 篇**编号文档全量索引 + 新增守门门禁 `tools/check-doc-index.mjs`（3 条变异臂） | 门禁主跑 ✅；`--self-test` 三臂全判红 |
| P1-5 | 210 项脏树未冻结 | **按用户指示不做**（git 相关） | —— |
| P2-1 | Windows 专属脚本不可移植 | ⚠️ **部分**：新增 `tools/device-code-fingerprint.mjs`（Node 版，判据/三级 token/三态退出码与 PS1 对齐，5 条变异臂自检通过）；`device-acceptance.ps1` **未移植** —— 它需要真机才能验证，本轮无设备，**不做未验证的移植** | 自检输出见 §5 |
| P2-2 | hmfs `chmod` 无效 | ✅ 在 `tools/setup-codex-for-dshm.mjs` 与 `hostcore/app/node-runtime-provision.cjs` 的目标点补注记（判据看"能力"不看权限位） | 语法检查通过 |
| P2-3 | 未忽略的本地目录 | **按用户指示不做**（git 相关） | —— |
| P2-4 | 开发辅助能力缺口 | ⚠️ 环境侧：KB/`.codex` 仍不可读（需在桌面侧授权/搬迁）；`web_search` 与 Hindsight 缺 key | —— |

### 2.1 本轮**新发现并修掉**的问题（`docs/267` 之外）

| # | 现象 | 根因 | 修复 |
|---|---|---|---|
| N1 | `pack-core` 清树后**再也物化不出核心树**：`npm install 失败（exit=null）` | `docs/258 §4.1` 记过的老缺陷**又回到了文件里**：路径被**无条件**加双引号，而 POSIX 上 `shell:false` ⇒ spawn 找一个"名字里带引号"的可执行文件 ⇒ ENOENT/`status=null` | `tools/pack-core.mjs`：引号与 `shell` 同进同退；并把 `r.error` 打进报错 |
| N2 | npm 依然失败：`pnpm(shim): 请给出包名或 GitHub 地址` | `which('npm')` 命中**端侧插件安装假壳**（`~/bin/npm`），不是真 npm | 见 §4 对策（真 npm 转发） |
| N3 | `place-ffmpeg` 必失败：`readelf ... Operation not permitted` | 本机 brew 的 ffmpeg 与闭包库是 `mode 770`（others 无），应用身份属 other ⇒ **读不到**（不是执行问题，是 DAC） | `tools/place-ffmpeg.mjs` 新增**显式**复用通道：`--reuse-existing` / `DSHM_FFMPEG_REUSE_ON_UNREADABLE=1`，且必须**清单校验完整**（`bin/ffmpeg`、`bin/ffprobe`、28 个库大小逐条相符）才放行；默认不生效 |
| N4 | hvigor 报 `00308002 … npm install pnpm execute failed（No stdout output）` | hvigor 按 **Node 可执行文件同目录**解析包管理器（`Bg.NPM_TOOL` + `dirname(process.execPath)`）；我们的 Node 是 `node-brew`，旁边没有 npm | 在 `Download/com.dshm.dshclient/npm` 放一个**真 npm 转发**（用 node-brew 跑 CLT 自带的 npm） |
| N5 | 换 CLT 自带 node（v24.18.1）跑构建 ⇒ **原生崩溃** `Check failed: 12 == (*__errno_location())` rc=133 | CLT node 在本应用域不稳 | 结论：**构建统一用 `node-brew`**（v26.12.1），不碰 CLT node |
| N6 | `CompileArkTS` 报 `EPERM: scandir '~/data'` | `@ohos/hvigor-arkts-compose` 的 `checkFileWithCase()`（由 `strictMode.caseSensitiveCheck` 驱动）**逐级向上列父目录**验证大小写；而 `~/data` 对本应用**不可列**（mode `0o42771`、属主是 `file_manager`）⇒ 致命 | 本机 `build-profile.json5` 置 `caseSensitiveCheck: false`（该文件**机器绑定且 gitignored**；**仓库模板 `tools/build-profile.template.json5` 保持 `true` 未动**）。代价：本机构建不再做大小写一致性校验 |
| N7 | 门禁 `assert-core-entrypoints` 判红：`bowser/package.json exports[./README.md]` 解析不到 | 上游把 **bowser 2.14.1 → 2.15.0**，它新增 `exports["./README.md"]`；而裁剪规则 `**/*.md` 的既定意图就是"包内文档不参与运行" ⇒ README 被删 | `tools/assert-core-entrypoints.mjs`：`exports` 指向 `*.md` 的**文档导出**改记"说明"、不计失败（并新增负控臂 ④：**不得**误伤，且 `*.js/.json` 缺入口仍判红）；`pack-core` 侧另有**定点保留**规则（`PRUNE_KEEP_EXPORTS_README`），下次物化会在包里 |

---

## 3. P1-1 的真相与修复（重要：**推翻了 `docs/267` 的初稿结论**）

`docs/267` 初稿把 `check-two-project-parity` 的 `exit 1 / 6587 处漂移`当成"手机工程落后 PC 工程"的**真漂移**。复测证明**这是错的**：

- 对端工程 `DSHM-mobile` 在本机应用域是 **`stat` 通、`listdir` EPERM**；
- 门禁旧实现 `inventory()` 把 `readdirSync` 的异常**静默吞掉**（`catch { return out }`）⇒ 对端清单恒为空
  ⇒ 每个 PC 文件都被报成"只在 PC 工程有"；门禁还照样打印"修复方式：把该文件同步到另一侧"
  ⇒ **会诱导人去修不存在的问题**。

**修法（fail-closed）**：`ENOENT` 仍按"确实没有"（真漂移）；其余错误记入 `unreadable` 并 **exit 2（无法判定）**，
且**先于**任何漂移清单打印。自检改为两条臂：臂 1 注入漂移判红（对端不可写时**如实 skip**）、
臂 2 **跑真门禁子进程**断言"对端不可枚举 ⇒ exit 2"。

复跑实证：`rc=2`，输出精确到 12 个 `EPERM` 目录；**"6587 处漂移"不存在**。

`docs/267` §3 的 A/B/C 三选项仍然有效，但**没有"6587 处待处理"这回事**：要判断是否真有漂移，
需先把手机工程放到**应用域可枚举**的位置，或给 `DSHM_MOBILE_ROOT` 指一个可读副本再跑。

---

## 4. 本机构建环境：坑与对策（可复用清单）

| 现象 | 根因 | 对策（本轮已落地） |
|---|---|---|
| `node` rc=127 `libc++_shared.so` | 沙箱 `bin/node` 包装器走 `node-cli`+el1 `.so`，在当前域**不可映射** | 包装器改为优先委托 `Download/<bundle>/node-brew`（P0-2a） |
| `npm` 变成插件安装假壳 | PATH 命中端侧 shim | 在 `Download/<bundle>/npm` 放假壳转发 → 真 npm（CLT 自带，用 node-brew 跑） |
| `npm install` 报 `exit=null` | 路径被无条件加引号（POSIX 上 `shell:false`） | 修 `tools/pack-core.mjs`（N1） |
| hvigor 找不到 npm | 它按 `dirname(process.execPath)` 找 | 同上：npm 转发放在 node-brew 旁（N4） |
| `place-ffmpeg` 读不到 brew | brew 目标 `mode 770`，应用属 other | 显式复用 + 清单校验（N3） |
| ArkTS 编译 scandir 父目录 EPERM | `caseSensitiveCheck` 向上列父目录 | 本机置 false，仓库模板不动（N6） |
| CLT node 崩溃 | v24.18.1 在本域不稳 | 构建只用 node-brew（N5） |

> 这些都属于"**本机开发环境**"的对策，**不是产品运行时行为**：产品侧一个字都没改（除 P0-2 的两处修复）。

---

## 5. 门禁读数（本轮实跑，真实 exit code）

| 门禁 | 结果 |
|---|---|
| `check-permission-surface` | ✅ entry 17 / phone 9，逐条 + 顺序 + reason |
| `check-doc-refs` | ✅ 200 篇 / 220 条引用落点一致 |
| `check-no-apk-surface` | ✅ 0 文件 / 0 目录 / 0 归档条目 |
| `assert-resfile-sync` | ✅ 22 件快照全部同步 |
| `check-resfile-core-zip` | ✅ 1 份容器，与配方/产出三方一致（`62371606027d3d70…`） |
| `check-doc-index`（**新增**） | ✅ 186 篇全收录；`--self-test` 3 臂全判红 |
| `check-core-openharmony-patches` / `check-ptc-wiring` / `check-fs-local-permission` / `check-agent-instructions-scope-walk` / `compat-drift` / `check-undici-shim-exports` / `assert-fs-search-fallback` / `check-web-fetch-jitless` | ✅ 全 rc=0 |
| `assert-core-entrypoints` | ✅ PASS（1 条 md 文档导出按口径豁免，已打印说明） |
| `check-feature-wiring` | ✅ 24 个功能接线全在 |
| `check-two-project-parity` | ⚠️ **exit 2（无法判定）** —— 对端不可枚举，**不是**漂移（§3） |
| `device-code-fingerprint.mjs --self-test`（**新增**） | ✅ 5 条变异臂全部按预期判态 |

---

## 6. 未做 / 待办（如实登记）

1. **git 相关三项**（P0-1 `.certs/.env` 忽略、P1-5 冻结脏树、P2-3 本地目录策略）—— 用户明确"git 先不管"。
2. **真机覆盖安装 + 端侧验收**：本轮**未安装、未卸载、未触碰设备数据**（只出包）。
   若要验证：`hdc install -r <app>`（禁止卸载）；届时可跑 `tools/device-code-fingerprint.mjs` 复核"设备在跑本机这份代码"。
3. **`hap-sign-tool verify-app`**：本机无 JDK，未跑；签名取证见 §1。
4. **`device-acceptance.ps1` 的 Node 移植**：需要真机才能验证，未做（不做未验证的移植）。
5. **`caseSensitiveCheck` 的本机放宽**：如需恢复严格校验，得让工程位于**应用域可逐级枚举**的路径下
   （例如沙箱内的副本），或把 `build-profile.json5` 改回 `true` 后从桌面侧构建。
6. **`docs/267` 的其余 P2 环境项**（KB 授权、`.codex` 搬迁、`web_search`/Hindsight key）：属环境配置，未做。
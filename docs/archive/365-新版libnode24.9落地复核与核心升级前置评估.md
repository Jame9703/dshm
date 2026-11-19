# 365 · 新版 libnode 24.9 落地复核与 dsh 核心升级前置评估

> 日期：2026-11-05 11:36–11:50 ｜ 触发：用户「新版 node 环境已经编译进去了，review 完毕后同步升级 dsh 核心到最新」
> 性质：**只读复核 + 升级前基线**，本档写成时未修改任何源码/二进制/配方。
> 证据优先级：实读字节 / 实跑门禁 > 本档 > 历史编号文档。

---

## 0. 结论（先看这一节）

1. **「新版 Node 已编译进去」属实，但只完成「文件替换」，未通过运行期安全门禁。**
   随包 `hostruntime/libs/arm64-v8a/libnode.so.137` 已换成 **Node v24.9.0**（155,408,704 B，
   sha256 `d9f9302b…`），旧件备份在同目录 `.bak-20261105-1121`（126,818,360 B）。
2. **发现 P0 阻断项**：新库里 libuv 的 io_uring 系统调用是**活体**（23 处
   `movz w0,#425/426/427` 后接 `bl`），而 `check-libnode-io-uring` 的常量表仍钉在
   24.2.0 的布局上 ⇒ 门禁 7 项判红，且「全文件广扫 ✅」是**假绿**（`syscallStub` 从旧锚点
   0x4f7e954 反推出错误地址，导致所有 `bl` 都不匹配）。鸿蒙 seccomp 对 425 直接 SIGSYS
   （docs/203：1951 次崩溃循环），**这份库不经中性化就上真机是明确的崩溃风险**。
3. **「升级到最新」的口径已经解锁但仍有歧义**：npm `latest` 仍是 `0.2.1-rc.5`（= 当前基线
   `+dshm.113`）；`next` 是 `0.2.2-rc.1`（`engines.node >= 24.9.0`，新库恰好满足），
   `alpha` 是 `0.2.2-alpha.3`。⇒ 用户意图应为 **0.2.2-rc.1**（docs/361 §5 的解锁项）。
4. **升级成本不是「改个版本号」**：依赖闭包 86 → 90 包，`cordis ~4.0.5 → ~4.1.0`、
   `schemastery ~3.18.5 → ~3.19.0`、`cordis-plugin-loader ~1.0.6 → ~1.1.0`、
   `cordis-plugin-timer ~1.1.7 → ~1.2.0`（预发布联动 ⇒ 自家插件 peer 必须跟版，
   见 docs/40 §4.5 与 docs/325 的 11 处 peer 漂移事故）；`pack-core.mjs` 的 **31 个补丁
   函数**全部靠上游字符串锚点，换版后需逐个迁移。
5. **回归基线已跑并落盘**：96 条 CI 门禁，**10 条在升级前就已判红**（与本次 Node 替换
   直接相关的只有 2 条），详见 `dist/acceptance/20261105-core-upgrade-pre-baseline.txt`。
   按 AGENTS.md 回归纪律，这 10 条是既有欠账，升级后不得出现新的 ok → fail。
6. **「保证功能完全正常」在本机无法完整兑现**：`hdc` 服务端 UDS 绑定被沙箱拒绝
   （docs/352），无法装机 / 取 hilog / 真机复测。本机只能给出「离线门禁全绿 +
   核心树入口与补丁静态/运行时探针」级别的证据，真机三端验收需 PC 端 hdc。

---

## 1. 新版 libnode 的逐项实证

| 项 | 旧件（`.bak-20261105-1121`） | 新件（当前随包） |
|---|---|---|
| 版本字符串 | `v24.2.0` | **`v24.9.0`**（164 处命中） |
| 字节数 | 126,818,360 | 155,408,704（+28.6 MB） |
| sha256 | `befe5d71…` | `d9f9302b…` |
| SONAME | `libnode.so.137` | `libnode.so.137`（ABI 号未变） |
| DT_NEEDED | `libc++_shared.so` + `libc.so` | **仅 `libc.so`**（libc++ 静态链入） |
| `.codesign` 段 | 有 | **有**（已自签名，`shnum=44`） |
| `UV_USE_IO_URING` 字符串 | 1 处 | **0 处** |
| `movz w0,#425/426/427` + `bl` | 17 槽已中性化为 `mov w0,#-1` | **23 处活体 bl**（3 个不同目标，其中 16 处指向同一 syscall 桩 `0x778cb40`） |

**判读**：

- `UV_USE_IO_URING` 字符串消失，是编译期 `fix-uv-io-uring.sh`（`uv__use_io_uring()`
  无条件 `return 0`）生效、死代码被消除的**间接证据**；这比字节补丁更根本，
  **但当前仓库的门禁不认这种修法** —— 它只认「17 个槽字节级中性化」。
- 新库 NEEDED 少了 `libc++_shared.so`，而 `libdshhost.so` 依赖它。Node 的 C API
  边界以 C 结构体为主，风险可控，但**跨 so 的 C++ 对象传递需真机加载才能确证**。
- 体积 +28.6 MB 会直接推高 HAP/APP 体积，出包前需复核 `check-resfile-core-zip`
  与最终包大小。

### 1.1 `check-libnode-io-uring` 判红明细（实跑）

```
A 身份          ❌ 期望 126,809,264 B / sha 09984895…（24.2.0 基线），实到 155,408,704 B
B 7 个定位锚点  ❌ 全部失效（新布局偏移全变）
B 17 个槽       ❌ 0/17，17 处全 UNEXPECTED
B 全文件广扫    ✅ 假绿：syscallStub 由旧锚点反推 ⇒ 所有活体 bl 不匹配
C 幂等          ❌ --check exit 1 / --apply exit 2（拒绝写入，符合预期）
F 回退备份      ❌ dist/node/libnode.so.137.orig 仍是 24.2.0 的中性化件
```

`--self-test` 的 H 往返同样判红。**门禁本身有牙（D/E 对照臂仍判红）**，失效的是
「常量表与真实二进制脱节」，不是判据写错。

---

## 2. 上游版本事实（npm registry 实查，2026-11-05 11:40）

| 通道 | 版本 | 依赖数 | `engines.node` | 与当前运行时 |
|---|---|---:|---|---|
| `latest` | `0.2.1-rc.5` | 86 | 未声明 | ✅ 当前基线（`+dshm.113`） |
| `next` | **`0.2.2-rc.1`** | 90 | **`>=24.9.0`** | ✅ 新库 24.9.0 刚够 |
| `alpha` | `0.2.2-alpha.3` | 90 | `>=24.9.0` | ✅ 但更不稳定 |

依赖闭包差异（rc.5 → 0.2.2-rc.1）：

- **新增 4 包**：`dsh-experimental-forge-bundle`、`dsh-experimental-liveshare`、
  `dsh-official-bundles`、`dsh-personalized-recommendations`；
- **移除 0 包**；其余 80+ 个 `@deepseek-ai/*` 版本整体从 `0.2.1-rc.5` → `0.2.2-rc.1`；
- **基础设施预发布联动**：`@deepseek-ai/cordis ~4.0.5 → ~4.1.0`、
  `@deepseek-ai/schemastery ~3.18.5 → ~3.19.0`、
  `cordis-plugin-loader ~1.0.6 → ~1.1.0`、`cordis-plugin-timer ~1.1.7 → ~1.2.0`、
  `cordis-plugin-include ~1.0.10 → ~1.1.0`。

> 这正是 docs/40 §4.5 记录过的形态：`~4.0.5` 不匹配 `4.1.0`，
> 自家插件（`dshm-office-system-preview` / `dshm-fs-write-nonchmod` /
> `dshm-tool-fs-remove` / `dshm-workspace-claim` / `dshm-ptc-runtime-inproc` 等）
> 的 peer 必须跟版，否则宿主启动时会把自带插件整条停用（docs/325 事故形态）。

---

## 3. 升级前回归基线（96 条，10 红）

报告：`dist/acceptance/20261105-core-upgrade-pre-baseline.txt`

| 判红门禁 | 根因分类 | 与本次 Node 替换的关系 |
|---|---|---|
| `check-libnode-io-uring` / `--self-test` | 新库布局与门禁常量脱节 | **直接相关（P0）** |
| `check-brand-surface` / `--self-test`（各 3 条） | OSS 声明与 AGC 草稿仍写 `+dshm.110`，配方已 `.113` | 无关，既有欠账；**升版后必须同步刷新** |
| `check-meeting-mode` / `check-meeting-ai-plugin` / `check-handheld-sidebar-recover` | `gates.yml` 引用了已删除的门禁脚本（`MODULE_NOT_FOUND`） | 无关，CI 配置残留 |
| `check-feature-wiring --self-test` | 对照臂锚点 `folderGrantsReady` 已改，找不到注入点 | 无关，门禁锚点过期 |
| `assert-exec-fix` (FAIL 33) / `assert-python-bridge` (FAIL 17) | 本机环境静态断言（wrapper 子 shell / libpython 落位） | 无关，本机环境受限 |

**绿的高价值项**：权限面 17/9（含 `--self-test`）、`check-fs-fence` 137 项、
`check-vm-bash` 373/373、`check-python-async-worker` 38 项 + 6 对照臂、
`check-market-bridge` 142 项、`check-node-cli` 42 项、用户数据保全、无 APK 面。

---

## 4. 建议的执行顺序（待确认后执行）

| # | 动作 | 交付/判据 |
|---:|---|---|
| P0-1 | 对新 libnode 做 io_uring 中性化（或改判据），**改字节后必须重签** | 23 处活体清零；`.codesign` 仍在 |
| P0-2 | 把 `patch-libnode-io-uring.mjs` 的 `SHIPPED` / `ANCHORS` / `SITES` 迁到 24.9 布局，重做对照臂与备份 | `check-libnode-io-uring` 主测 + `--self-test` 全绿 |
| P0-3 | 更新 `dist/node/libnode.so.137.orig` 为新版对应备份 | F 段「备份 == 随包件」 |
| U1 | 配方 `coreVersion` → `0.2.2-rc.1+dshm.1`（或继续 `.114` 序列，见口径确认） | `hostcore/core-recipe.json` |
| U2 | 刷 contract 快照 → `compat-drift` → `gen-compat-endpoints` → `CompatIndex.SUPPORTED_VERSIONS` | docs/40 §2 五步，漂移 0 |
| U3 | `pack-core.mjs --place-in-app`：按首个 `die` 逐个迁移 31 个补丁锚点；peer 跟版 | 240+ 项端侧补丁断言全过 |
| U4 | 刷 OSS 声明 / AGC 草稿 / `check-resfile-core-zip` 三方一致 | 品牌面门禁转绿 |
| U5 | 全量门禁复跑，与基线逐项对比；**只允许 10 红减少、不许新增** | `dist/acceptance/20261105-core-upgrade-post.txt` |
| U6 | 代码审核（diff 复核：补丁是否被覆盖、版本写死处、resfile 只有 1 份容器） | 审核结论 |
| U7 | 出包（可选）+ 真机三端复测（**本机 hdc 不可用，需 PC 端**） | 真机日志 `BOOT_10_ENV_READY core=…/0.2.2-rc.1` |

---

## 5. 必须先说清的边界

- **本机不能真机验证**（docs/352：hdc server `bind uds addr fail ret:-13`）。
  因此「功能完全正常」在本轮只能证明到「离线门禁 + 核心树静态/运行时探针」，
  不能代替三端装机验收。任何「全绿」的表述都必须带这条限定。
- **换核心基线会重写 `dist/core/work/` 与 resfile 容器**：旧容器
  `dsh-core-0.2.1-rc.5+dshm.113-*.zip` 与 4 棵旧核心树保留作为回退，不清理。
- **不改权限面 / 不碰签名物料 / 不碰 el2 用户数据 / 不执行 git commit**（AGENTS.md
  与 docs/353 硬规矩）。

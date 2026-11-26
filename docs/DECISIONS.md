# 决策记录（ADR 式）

> 只记**已拍板且影响长期实现**的决策。状态三种：**现行** / **已推翻** / **已关闭**。
> 被推翻的决策保留一行（防止有人按旧结论实施），但不保留旧论证过程。
> 现行口径与代码冲突时，以代码/配置为准并当场修订本表。

---

## 1. 工程与协作

| 决策 | 日期 | 状态 | 现行口径 | 依据 |
|---|---|---|---|---|
| 单一工作区 | 2026-11-03 | 现行 | 只有 `~/data/DSHM-deveco-workspace`；`DSHM-mobile` 已删；`check-two-project-parity` 不作判据 | `AGENTS.md` §2 |
| 代码永不提交 | 2026-11-03 | 现行 | 不执行 `git commit` / `push`，除非用户明确要求 | `AGENTS.md` §2 |
| 版本号只在用户明确要求时升 | 2026-11-06 | 现行 | 不自作主张升 `versionCode` / `versionName` | `AGENTS.md` §4.4 |
| 文档分层 | 2026-11-18 | 现行 | 权威文档 + 功能台账 + 坑档 + 决策表；历史档只读归档 `docs/archive/` | 本文件、`docs/README.md` |
| Beta 身份独立 | 2026-10 起 | 现行 | Beta 用 `com.dshm.dshmbeta`，构建期临时替换、`finally` 逐字还原 | `tools/build-beta.mjs` |
| 正式 AGC App ID | 2026-11 | 现行 | `6917614360926110054` | `APPID-CHANGE.md` |

## 2. 运行架构

| 决策 | 日期 | 状态 | 现行口径 | 依据 |
|---|---|---|---|---|
| 端侧核心 = 随包 libnode + 核心树 | 2026-09-12 | 现行 | Stage 壳 → HSP 宿主 → `libnode.so` → dsh 核心树；不走浏览器 / 远程渲染 | `docs/archive/50-*`、`90-*` |
| 全端 `--jitless` | 2026-09 起 | 现行 | 不申请 JIT 权限；接受 `WebAssembly === undefined`；靠两层垫片补能力 | `docs/archive/50-*` §4.4 |
| 核心树静态随包 + resfile 单容器 | 2026-10 起 | 现行 | `hostruntime/.../resfile/dsh-core-*.zip` 只允许 1 份；改核心必须重打 | `AGENTS.md` §5.3 |
| 核心版本以 `core-recipe.json` 为准 | 2026-11-19 | 现行 | 上游 rc.5；补丁包与配方一致 | `hostcore/core-recipe.json` |
| Guest VM 资源档 | 2026-11-19 | 现行 | 2 vCPU；guest RAM 经济档 512 / 性能档 1024 MiB；TCG buffer 128 / 512 MiB（原 1 vCPU / 256 / 512 / 64 / 256） | `hostcore/plugins/dshm-vm-bash/lib/vm.js`、`check-vm-memory-tier`、`check-vm-bash` |

## 3. 三端与终端

| 决策 | 日期 | 状态 | 现行口径 | 依据 |
|---|---|---|---|---|
| 三端分离（PC / 平板 / 手机各走各的） | 2026-11-06 | 现行 | PC/2in1/Edge/ProMax → entry desktop 档；平板 → entry tablet；手机/折叠单屏 → phone | `AGENTS.md` §3 |
| 设备分档判据 | 2026-11-12 | 现行 | `desktopForced`；`EDGE_FAMILY_TOKENS` 只含 `QXS`；`MRX/MRR/MRD/MRO/DRA` 不得加回 | `docs/archive/413-*`、`check-edge-desktop-policy` |
| 终端分档 | 2026-11-12 | 现行 | 只有 PC/2in1/MateBook/Edge/ProMax 有原生 PTY；其余走 guest VM | `docs/archive/413-*` |
| 平板侧栏几何 | 2026-11 | 现行 | 展开 280 / 收起 56；只在 `min-width:1024px` 生效；窄档交官方抽屉 | `docs/archive/385-*`、`392-*`、`check-sidebar-shim-css` |
| 平板走 PC 布局 | — | **已推翻** | 现为「平板独立档」：无自绘 PC 顶栏 | `docs/archive/371-*` #12、`386-*` |
| 立即启动模拟器 | — | **已关闭** | 2in1 没有 emulator 子命令；没设备就引导无线调试 | `AGENT-HANDOFF.md` §1 |

## 4. 权限与安全

| 决策 | 日期 | 状态 | 现行口径 | 依据 |
|---|---|---|---|---|
| 「恒 8 条 ACL」 | 2026-10-14 | **已推翻** | 按发布 Profile 的 `allowed-acls` 为准；当前 entry 18 / phone 9 | `AGENTS.md` §4.3 |
| 加入全盘访问 `ACCESS_USER_FULL_DISK` | 2026-11-11 | 现行 | entry 18 条；手机不申请；Profile 已批准 | `docs/archive/405-*` |
| `DISTRIBUTED_DATASYNC` | 2026-10 | **已撤** | 无消费点，不声明；端云同步走系统云空间 | `docs/archive/249-*` |
| AI 生成标识 | 2026-11-17 | 现行 | 只挂会话正文输入座位；离开会话页即移除 | `docs/archive/411-*`、`check-ai-disclosure-scope` |
| 全盘 ACL 与 beta | 2026-11-10 | 现行 | Beta 默认不注入全盘；`--no-full-disk` 可关闭 | `tools/build-beta.mjs` 头注 |
| 全盘权限 reason / usedScene | 2026-11-19 | 现行 | 按 AGC 审核驳回①：`reason` 写明「仅 PC / 2in1 本地项目工作区读写」，`usedScene.when=inuse`；权限条数不变（entry 18 / phone 9） | `entry/src/main/module.json5`、`perm_full_disk_reason` |

## 5. 功能取舍

| 决策 | 日期 | 状态 | 现行口径 | 依据 |
|---|---|---|---|---|
| 托盘图标换彩色 | 2026-11-03 | **已关闭** | 三处入口均无效，用户叫停，不再尝试 | `docs/archive/353-*` §4 |
| Super-agent 独立服务 | 2026-11 | **已关闭** | 单进程单 Node；无窗口后台三条官方路全封 | `docs/archive/353-*` §4 |
| 云同步改走 CloudFoundationKit | 2026-11 | **已推翻** | 回到系统云空间；容器 `DSHM` / 类型 `sync_units` | `docs/archive/374-*`、`375-*`（回退） |
| 各端界面统一 | 2026-11 | 现行 | PC 顶栏 / 平板常驻侧栏 / 手机抽屉；不强行统一 | `docs/archive/386-*` |
| 碰一碰收文件范围 | 2026-11-16 | 现行 | 只在 PC 档注册；手机端零改动；只注入不自动发送 | `docs/archive/421-*` |
| 设置面板玻璃排除 | 2026-11-17 | 现行 | 设置面板及内部 dialog 全形态排除玻璃 | `docs/archive/420-*` |
| 侧栏窄视口交官方抽屉 | 2026-11-18 | 现行 | 平板/折叠 <1024 不再写死 280/56 | `docs/HANDOFF.md` §2 与 `check-sidebar-shim-css` |
| 本机可侧载包 | 2026-11-17 | 现行 | 只有本机调试签名 local-install 可装；canonical Beta 报 9568322 | `AGENT-HANDOFF.md` §3.3 |
| P2-3 桥探测噪声缓修 | 2026-11-26 | 现行 | 工作区可验证来源已穷尽（methodList 对齐、无跨壳调用、调用方全守卫、退避已上线）；ArkWeb 内部日志应用层不可控；功能面零影响 ⇒ 缓修，下轮带新 Beta 真机采样（速率/时间戳/UI 状态）再定位 | `docs/archive/295-*`、`dist/acceptance/20261125-core023-audit-report.md` §11、手机 r51 诊断 |
| libreoffice-kit-wasm 维持随包 | 2026-11-26 | 现行 | 真机硬依赖（office 链路 `package.json` 子路径直取），裁剪废弃；img-sharp-wasm32 无真机异常维持裁剪 | `hostcore/core-recipe.json`（`$comment_keep_libreofficeKitWasm`）、`docs/PITFALLS.md` §2.14 |

## 6. 维护规则

1. 新决策：加一行，写清日期与现行口径；涉及推翻旧结论的，旧行改状态并保留。
2. 决策落地后，把**怎么实现**写进 `docs/FEATURES.md`，把**会踩的坑**写进 `docs/PITFALLS.md`。
3. 决策与本表冲突时，先确认代码/配置，再改表；不允许「表里一套、代码一套」长期并存。

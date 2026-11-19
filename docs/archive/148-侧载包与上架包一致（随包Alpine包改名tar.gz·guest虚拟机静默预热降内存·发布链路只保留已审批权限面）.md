# 148 · 侧载包与上架包一致（随包 Alpine 包改名 `.tar.gz` · guest VM 静默预热降内存 · 发布链路只保留已审批权限面）

> 本文是 **2026-10-13** 这一轮的落实记录。用户三条原话：
> ① **「移动端安装不上的原因是包里有 `.apk` 的文件，实际是 Alpine Linux 的包，全部改名 `.tar.gz` 不然审核检测到 apk 字眼就直接安装不上」**；
> ② **「PC 端的 bash 和终端走移动端的方案，三端同步，只是 vm 给静默启动，稍微压低资源占用去启动」**；
> ③ **「只用 release 权限编译新的上架包，只有 2 条已审批的权限和不用申请的权限，沙箱及其他未审批的权限不含在里面」**。
> 随后用户追加 **「侧载包和上架包要一致，可以的话直接安装上架包测试」**，在 A / B 两个选项里选了
> **B —— 侧载包也只声明 8 条权限（与上架包一致），但仍用调试签名（含本机 UDID ⇒ 可 `install -r`）**。

## 0. 一句话结论

- **① `.apk` 字眼已清零**：随包 **19 个** Alpine 包全部改名 `.tar.gz`（`resources/resfile/toolchain/git/` 15 个 ＋ `resources/resfile/vm/guestpkgs/` 4 个），供给侧（`NOTICE.md` / guest 侧 `apk add` 前的补名）同步改写。
- **② 三端同步 + VM 静默**：release 档 PC 也走手持档路径（`docs/140` §4）⇒ 三端 bash / 终端都进 guest VM；`dshm-vm-bash` 改成**应用启动后 1.5 s 后台预热**（不再要 `DSHM_VM_BASH=warm`），默认内存 **512 → 384 MiB**。
- **③ 侧载件 = 上架件的权限面**：侧载 HAP 的 `module.json` 与上架 `.app` 内层 HAP 的 `module.json` **逐字节相同**（sha256 `2e429184e5af09fa…`，各 3,640 B，`requestPermissions` 各 **8 条**）。**"直接安装上架包"技术不成立**（发布 profile 无 UDID ⇒ 必回 `9568322`，见 §5）。
- 真机：PC `86E0226429000417` 覆盖安装成功、**用户数据未丢**、核心树切到 `+dshm.33`；工作区文件与终端的 RPC 均回 **200**（§6）。

---

## 1. 改动 ①：随包 Alpine 包改名 `.apk` → `.tar.gz`

**症状**：`.app` 里含扩展名为 `.apk` 的文件 ⇒ 应用市场 / 安装器按"包内有 apk"直接判**安装失败**（审核报告的两条"手机、平板端安装失败"）。

**内容仍是 apk v2 包，只改扩展名**（改名不改字节）：

| 位置 | 个数 | 改名后 |
|---|---|---|
| `entry/src/main/resources/resfile/toolchain/git/` | 15 | `brotli-libs` / `c-ares` / `ca-certificates-bundle` / `git-2.47.3` / `libcrypto3` / `libcurl` / `libexpat` / `libidn2` / `libpsl` / `libssl3` / `libunistring` / `nghttp2-libs` / `pcre2` / `zlib` / `zstd-libs`（各 `*.tar.gz`） |
| `entry/src/main/resources/resfile/vm/guestpkgs/` | 4 | `bash-5.2.37-r0` / `libncursesw-6.5_p20250503` / `ncurses-terminfo-base-6.5_p20250503` / `readline-8.2.13-r1`（各 `*.tar.gz`） |

**供给侧同步改写**：

- `resources/resfile/vm/NOTICE.md`（表里那一行）把口径写成**为什么**要改名 —— "内容仍是 apk v2 包，扩展名统一成 `.tar.gz` 只为过应用市场审核（包内有 `.apk` 即判'安装失败'）；guest 侧 `apk add` 前会先在 `/tmp` 补一层 `.apk` 名字"。
- `resources/resfile/resources/app/main.js`：解包 / 安装路径按新扩展名走，guest 里 `apk add` 之前先在 `/tmp` 把名字补回 `.apk`。

**校验读数**（本轮实读）：`entry/src/main/resources/resfile` 下 `*.apk` 计数 = **0**，`*.tar.gz` 计数 = **19**；HAP 内对应条目亦然。

> ⚠️ **不要**跑 `tools/place-toolchain.mjs`：它会把 resfile 里这 15 个 `.tar.gz` **重新 gzip**（只有 gzip 头 MTIME 字节 4–7 变，gunzip 后逐字节相同），从而与已出 HAP 失同步 —— 属"出包四坑"之一（见 `AGENTS.md`）。

---

## 2. 改动 ②：三端同步 + guest VM 静默预热 / 降内存

**为什么三端会同步**：release 构建的应用域降级（`docs/140` §4）⇒ PC/2in1 档上"随包脚本不能 `execve`" ⇒ 分档判据（与 `dshm-market-bridge` / `dshm-profile-pnpm` 的 `shimRunnable()` **逐字同源**）判**假** ⇒ `dshm-vm-bash` 把 `ctx.subprocess.spawn` 改派到 guest VM。⇒ 三端的 bash / 终端都进 guest VM，**模型侧工具链一个字都不用改**。

**本轮两处产品化调整**（`hostcore/plugins/dshm-vm-bash/lib/`）：

| 项 | 改前 | 改后 | 落点 |
|---|---|---|---|
| 预热 | 第一次有命令要跑时才拉 VM；`DSHM_VM_BASH=warm` 才在插件装载时预热 | **接管生效 ⇒ 应用启动后 1.5 s 后台预热**（`WARM_DELAY_MS = 1500` ＋ `shouldWarm()`，与 `enabled()` 同源），不再需要用户加环境变量 | `lib/index.js:62`（常量）/ `:139`（`shouldWarm`）/ `:319`（调用）/ `:330`（`setTimeout(...).unref()`） |
| 内存 | 默认 512 MiB | 默认 **384 MiB**（`VM_MEMORY_DEFAULT_MIB = 384`；`DSHM_VM_MEMORY_MIB` 可覆盖；`-object mem0` 与 `-m` 两处同源） | `lib/vm.js:158`（常量）/ `:174`·`:176`（解析回退）/ `:968`（上报） |

**PC/2in1 档的惰性不受影响**：分档判据假 ⇒ 整条插件惰性、一个字节不变（PC 上"随包假壳能 spawn"时早退）。

> 一并保留 `docs/146` 的 `tb-size 256` ＋ `memBudget()` 内存闸门（`SIGABRT` 缓解）—— 本轮未再动。

---

## 3. 改动 ③：发布链路只保留已审批权限面（2026-10-14 起源码也恒 8 条）

- **源码面（2026-10-14 用户拍板后更新）**：`entry/src/main/module.json5` 恒 **8 条**（2 条已审批 ACL + 6 条免申请）。本节此前那句"源码仍全量声明 11 条"**已作废** —— 多出来的三条受限条目**永久删除**，源码 / 包体 / 文档都不再出现，也不再申请。
- **发布 / AGC 档的差异不再靠改源码**：`tools/sign-release-hap.ps1` 的 **[0] 步在签名之前自动摘除**未授权 ACL（对着 profile 比、幂等；`.app` 分支 fail-closed）。已审批的只有 2 条 ACL：`ALLOW_EXTERNAL_NATIVE_CODE` ＋ `FILE_ACCESS_PERSIST`（`docs/141` 实读）。

**产物内 `requestPermissions` = 8 条**（两处同名同序，本轮实读）：

```
ohos.permission.INTERNET / GET_NETWORK_INFO / KEEP_BACKGROUND_RUNNING / PREPARE_APP_TERMINATE
ohos.permission.ALLOW_EXTERNAL_NATIVE_CODE / FILE_ACCESS_PERSIST / STORE_PERSISTENT_DATA / MICROPHONE
```

---

## 4. **B-1**：让侧载件与上架件的权限面也一致（用户选 B）

> ⚠️ **本节做法已永久废除**（2026-10-14 用户拍板）：源码现在就是 8 条，侧载件与上架件在权限面**天然一致**，不再需要任何"临时摘除 / 事后还原"的操作。以下保留原始记录，仅作历史。

**问题**：上架 `.app` 的权限面是 8 条（走在签名前摘除），而**侧载件是调试签名** ⇒ `sign-release-hap.ps1` 的 [0] 步**不适用于它** ⇒ 侧载件当时是 **11 条**。用户要求「侧载包和上架包要一致」。

**B-1 做法（一次性，不留在源码里）**：临时在 `entry/src/main/module.json5` 用块注释把 3 条 `system_basic` 权限对象包起（标记 `/* 【临时·B-1 摘除开始】… */`），**release 构建**（调试签名）⇒ 产物天然 8 条；**源码随后逐字还原**。

**还原与一致性校验**（本轮实读）：

- `entry/src/main/module.json5` 里 `临时·B-1` 标记命中 **0 处**（源码回到 11 条声明）。
- 侧载 HAP 与上架 `.app` 内层 HAP 的 `module.json` **逐字节相同**：各 **3,640 B**，sha256 `2e429184e5af09fa149e493954422c309e790e8fee684ca135d3b7622624ac81`，`requestPermissions` 各 **8 条**。
- ⇒ **"侧载包与上架包一致"在权限面这一层是可证的同字节**，不是"看起来一样"。

**已知代价（B 的代价，登记备查）**：只声明 8 条时，**PC 老装机升级后** `~` 系工作区（`harness` / `data/token`）**读不到**、终端 cwd 打不开；
**全新装机的默认工作区在 `Download/com.dshm.dshclient` 之下，不受影响**。

---

## 5. 为什么"直接安装上架包"不成立（沿用既有结论，`docs/141` / `docs/145`）

| 件 | profile | 设备列表 | ACL | `hdc install` |
|---|---|---|---|---|
| `D:\desktop\release\dshmRelease.p7b`（发布） | `type=release` | **无 UDID** | **2 条** | ❌ `code:9568322 signature verification failed due to not trusted app source` |
| `~/.ohos/config/default_desktop.ohos.arm64_kUlawIWx….p7b`（调试） | `type=debug` | **有 UDID** | 5 条 | ✅ `install -r` |

⇒ 上架件只能走 **AGC 邀请测试 / 上架**；真机上验 release 档行为用 **`…-release-buildMode-signed.hap`**（`buildMode=release` ＋ 调试签名）。

---

## 6. 产物与读数（本轮实读，权威）

### 6.1 侧载件（与上架件权限面一致）

| 文件 | 大小 | sha256 |
|---|---|---|
| `dist/sideload/DSHM-1.1.0-core0.2.1-alpha.2+dshm.33-arm64-signed.hap` | **398,806,449 B** | `46ad91306825d2b5eb49e29e3da6d4859fece0dcaa67e61d67d78bd30c7bb4ac` |
| `dist/release-test/DSHM-…+dshm.33-arm64-release-buildMode-signed.hap` | **398,806,449 B** | 同上（**逐字节相同**） |

**产物读数**：容器条目 **127** / `minAPIVersion=60101024` / `targetAPIVersion=260000026` / `app.debug=false`（`buildMode=release`）/ `versionName=1.1.0` / `versionCode=1010000` / `deviceTypes=phone,tablet,2in1` / **`requestPermissions` = 8 条** / 签名 = 调试证书（含本机 UDID）。

### 6.2 上架 / 发布件（未随 B-1 重建，仍是 15:11 那批）

| 文件 | 大小 | sha256 | 说明 |
|---|---|---|---|
| `dist/release-test/…+dshm.33-arm64-release-signed.app` | 195,344,525 B | `c3ef8164bb9d2804f9354e8225ebd216d7c2a5bc9c89ed7cc2b49c76e978933e` | **上传 AGC 就用它**（发布证书 / 发布 profile；内层 hap 已摘 3 条 ⇒ 8 条） |
| `dist/release-test/…+dshm.33-arm64-release-signed.hap` | 398,806,356 B | `a00e0d60475e2e6022a0076dfe2e2b476273b30bd4c861acacad20c50a280f93` | 单模块 HAP（发布证书）；**不能 `hdc install`** |

> **不必因 B-1 重出这两个**：B-1 改的是**源码头注释**、且事后已还原 ⇒ 源码仍是 11 条声明 ⇒ 重出的 release 件在 [0] 步摘除后与 15:11 那份**内容同构**；差别只在 `sign-app` 的签名时间戳（同 `unsigned` 重签 sha 必变，别拿哈希当"有没有变"的判据）。

### 6.3 留档

旧 11 条权限的调试签名件移到 `dist/sideload/previous-internal-test/…+dshm.33-arm64-signed-11perm.hap`（398,806,450 B，sha256 `47653f05…`）—— 同签名，可直接 `install -r` 回退。

---

## 7. PC 真机取证（`86E0226429000417`，`const.product.devicetype=2in1`）

- **装机**：`hdc install -r`（**未 uninstall**）成功；`bm dump`：`versionCode=1010000` / `versionName=1.1.0` / `updateTime=1791877068136`。
- **核心树已切**：`dsh/cores/` 下**只有一棵** `0.2.1-alpha.2+dshm.33`。
- **用户数据未丢**：`dsh/home` 仍在（`.credentials.yaml` / `host-ready.json` / `install-queue` / `profiles` / `sessions` / `skills` / `speech-to-text` / `storages`）。
- **`host-ready.json`（本轮）**：`workspace=~/Download/com.dshm.dshclient` / `profile=ondevice` / `jitless:true` / `zstd:true` / 端口 **3120**；`natives`：koffi `ok` / sharp `ok` / node-pty `ok`，`sandbox-dlopen=false`、`pty-spawn=false`；`python`：`bridge=true / stdlib=true / ready=true / selftest=ok / stdout="2"`（内嵌 CPython 在宿主进程内可用，不 `execve`）。
- **工作区 / 终端 RPC 全 200**（`dshm-host.log` 原文）：`/api/workspaceFiles/stat` 200、`/api/workspaceFiles/readBytes` 200、`/api/terminal/environment|list|shells|create|resize` 全 200。
- **一个性能读数（登记，属已知未修项）**：`node-output.log` 有 `LOOP-GAP 1662ms`、`SYNC-COUNT 同步调用总耗时 1187ms`（Top：`statSync×15558=596ms` / `spawnSync×7=207ms` / `readFileSync×3540=159ms` / `realpathSync×2027=134ms`），与 `docs/146` §3 同族。

---

## 8. 未做 / 待拍板

1. **PC 档要不要保留原生 spawn**（`docs/140` §5 修法 A）—— 用户本轮要的是"三端同步"，故按 VM 路线做；未做 A，待拍板。
2. **手机 / 平板档本轮未接设备复验**（只连了 PC）。B 的代价之一（`~` 系工作区读不到）**只影响 PC 老装机**，手持档默认工作区在 `Download/` 下，预期不受影响 —— 待手持真机确认。
3. `.app` / `-release-signed.hap` **未因 B-1 重建**（见 §6.2 理由）。

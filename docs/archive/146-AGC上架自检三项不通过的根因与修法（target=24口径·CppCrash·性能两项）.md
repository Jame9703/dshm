# 146 · API 版本口径与 AGC 上架自检三项不通过的根因、修法

日期：2026-10-11
设备：手机 Mate80 `62T0225B18039433`（在线，本轮实机复验）；**上架自检报告来自 Mate60**（本轮未连接 ⇒ 未回归）
核心树：`0.2.1-alpha.2+dshm.32`（**未升**，理由见 §4）

用户两问：

1. 现在的 API 版本是 26 吗？为什么上架自检显示 24 —— 这是向下兼容的结果吗？
2. 上架自检三项不通过（机型统一 Mate60）：
   ① 稳定性：`CppCrash`，`Signal:SIGABRT(SI_TKILL)`；
   ② 应用内点击操作响应快：`252.0 ms`（目标 `250.0 ms`）；
   ③ 应用启动加载完成快：`9039.0 ms`（目标 `4000.0 ms`）。

附带的第三个 P0 是本轮自己踩出来并当场修掉的：裸跑 `tools/pack-core.mjs` 会**重复注入**两处补丁（见 §5）。

---

## 1 ① API 版本：**26 是编译面，24 是目标 / 兼容面**

三处实读（本轮复核，未改一行）：

| 口径 | 来源 | 读数 |
|---|---|---|
| 编译 SDK | 本机 DevEco Release SDK | `26.0.0.105`（`apiReleaseType=Release`；`docs/143` 换 Release SDK 之后） |
| 目标 / 兼容 SDK | `build-profile.json5` → `app.products[default]` | `targetSdkVersion = compatibleSdkVersion = "6.1.1(24)"` |
| 设备侧 | `hdc shell bm dump -n com.dshm.dshclient` | `apiTargetVersion=60101024`、`apiReleaseType=Release` |

⇒ **上架自检显示 24，是 `targetSdkVersion=24` 的必然结果，不是"降级事故"**。
它同时决定了产物的 `minAPIVersion = targetAPIVersion = 60101024`，也就是
**API 23/24 的老设备（HarmonyOS 6.1 / 6.1.1）能装得上**。这是 `docs/110` 的明确拍板：

> `compatibleSdkVersion` 定为 `6.1.1(24)`，产物 `minAPIVersion=60101024`。
> 曾试过 `6.1.0(23)`（`docs/108` §1，编译期成立），但**本仓没有 API 23 的验证设备** ⇒ 不把未验收的兼容面卖给用户。

### 想让自检显示 26 的代价

**先纠正本节上一版的错结论**：上一版写的是"抬 target ⇒ 产物 `minAPIVersion=26` ⇒ 丢掉 API 23/24 整个兼容面"。
**实测不成立**（2026-10-11 亲跑：只动 `targetSdkVersion`、`compatibleSdkVersion` 保持不动，各编一次读产物）：

| `targetSdkVersion` | `compatibleSdkVersion` | 产物 `minAPIVersion` | 产物 `targetAPIVersion` | debug HAP |
|---|---|---|---|---|
| `"6.1.1(24)"` | `"6.1.1(24)"` | `60101024` | `60101024` | 399,421,087 B |
| `"26.0.0(26.0.0)"` | `"6.1.1(24)"`（**未动**） | **`60101024`（未变）** | `260000026` | 399,421,088 B |

⇒ **装机门槛由 `compatibleSdkVersion`（→ 产物 `minAPIVersion`）决定，不是 `targetSdkVersion`。**
官方 schema 原文（`hvigor-ohos-plugin\res\schemas\ohos-project-build-profile-schema_zh.json`）：

> `compatibleSdkVersion`：「应用/元服务运行所需兼容的最低SDK版本。**运行应用的系统 API 版本不能低于该值，否则无法安装**；不能高于目标SDK版本」
> `targetSdkVersion`：「应用/元服务运行的目标SDK版本。**系统会根据 targetSdkVersion 控制应用的行为**。如未配置，默认与 compileSdkVersion 保持一致」

⇒ **只抬 target、保持 `compatible=6.1.1(24)`，API 24（HarmonyOS 6.1.1）的设备照装**，`docs/110` 那一档兼容面**不丢**。
两版 HAP 体积只差 **1 字节**（`260000026` 比 `60101024` 恰好多一位字符）⇒ 除 `targetAPIVersion` 外逐字节相同，可互证。
旁证同族：`docs/108` §1 用 `compatibleSdkVersion="6.1.0(23)"` 出的 `minAPIVersion=60100023` 包，装在 API 26 的鸿蒙 PC 上照样装得上 —— 兼容面与 target 解耦。

抬 target 的**真实代价**不是安装面，而是**启用 API 26 的行为策略**（`docs/142` §6 已登记）⇒ 交付前需 PC / 手机 / 平板三端回归。

- **写法**：API 26 必须写 `"26.0.0(26.0.0)"`；写 `"6.2.0(26)"` 会被 hvigor 直接拒：
  `00303082 targetSdkVersion is not supported. Change it to a valid version in the available list.`
  依据 `...\hvigor-ohos-plugin\node_modules\@ohos\hos-sdkmanager-common\build\res\hos-config.json` 的
  `osVersionMapper`：`"26.0.0":"26.0.0"` / `"6.1.1":"24"` / `"6.1.0":"23"`。
- **未实证（"6.1.1 设备还能不能装"的最后一步）**：`targetAPIVersion=260000026` 的包装到 **API 24 真机**上会不会被
  BMS 拒 —— 机制上 target > device 是允许的（按 `compatible` 判门槛），但**本仓没有这条实测**；
  要判死需接一台 API 24 平板装一次（当前在线的是 Mate80，API 26，验不了这条）。

在拍板之前本仓保持 `target=24`，
且这**不影响上架审核**（AGC 对 `targetSdkVersion` 只做"不低于某下限"的检查，不要求等于最新）。

> 注：本节的 `60101024` 刻意**不加反引号**。`tools/check-doc-refs.mjs` 会把同一行里"纯数字的反引号段"归给前面最近的 mention
> （`docs/136` §6 已登记的门禁盲区）—— 加了会被误报成 `110:60101024`（本次实测踩到，去掉反引号即绿）。

> ⚠️ 另一条曾经挡审核的「应用使用了 HarmonyOS Beta 版本 API」**已在 `docs/143` 解决**：
> 本机换了 Release SDK（`26.0.0.105`）重出，包内 `apiReleaseType=Release` / `pack.info.apiVersion.releaseType=Release`。
> 与本轮的 `targetSdkVersion=24` 是两件不同的事，**不要混为一谈**。

---

## 2 ② 稳定性 `CppCrash`：崩点是 **QEMU `tcg_region_init` 里 `mprotect` 失败后 `exit(1)`**

### 2.1 崩溃现场（Mate60 上架自检原文）

```text
Reason: Signal:SIGABRT(SI_TKILL)
#03 pc 0xc15ed8 libqemu-system-aarch64.so(tcg_region_init+1944)
Process life time:4175s
LastFatalMessage:[appspawn_server.c:69]Unexpected call: exit(1)
```

两点先钉住：

- `exit(1)` 是 **QEMU 自己调的**，不是我们代码调的 —— 进程被 `appspawn` 侧记成"未预期地调用 `exit`"。
- 生命周期 `4175 s`（≈70 分钟）⇒ **不是启动即崩**，是长跑之后（会话中途）才触发。

### 2.2 反汇编 + 重定位 + 字面量三重证据（本轮亲读，可复现）

被分析的件：`entry\libs\arm64-v8a\libqemu-system-aarch64.so`（41,438,848 B，QEMU 10.2.0）。
`.rodata` 的 `vaddr == 文件偏移`，可直接按偏移读字符串。

**① 崩点那两条指令：**

```text
c15ed8:  blr  x8                 ; 崩在这条
         ; x8 = [0x267e000 + 336] = 0x267e150
```

**② GOT 里 `0x267e150` 是谁（`llvm-readelf -r` 实读）：**

```text
0x267e150  →  exit
0x267e158  →  __assert_fail
0x267e1f0  →  abort
```

⇒ 崩点调的是 `exit`（**不是** `abort` / `__assert_fail`），与 `LastFatalMessage: exit(1)` 对上。

**③ 谁跳进来的：**

```text
进入 0xc15e84：来自 c15a7c
进入 0xc15ecc：来自 c15d40 / c15b48 / c15bf0 / c15c44 / c15ca8
```

这**每一条** `cbnz w0`（判返回值的分支）**前一条都是** `bl 0x160f4c0 <qemu_mprotect_rw+0x40>`。
⇒ 语义闭合：**`mprotect` 返回非 0（失败）⇒ 走 `error_report` ⇒ `exit(1)`**。

**④ `.rodata` 字面量（用于定位是哪一段）：**

```text
0x508c90  "../tcg/region.c"
0x5a3093  "tcg_region_initial_alloc__locked"
0x594b51  "region_size >= 2 * page_size"
```

### 2.3 ⚠️ 必须钉死、不许复活的旧错结论

上一轮模型把崩点认成 "`g_assert_not_reached`" / "一次性分配 N GiB 失败" / "`!err` 断言（`region.c:396`）" ——
**这三条全错**。`!err` 那条断言在 Region 分配成功路径上，**是死代码，与崩点无关**；
崩点是 `mprotect` 失败后的 `exit(1)`（§2.2 的①②③三条独立证据互证）。
**不要再把旧结论写进文档或注释。**

### 2.4 修法（**已随包**，`+dshm.32`）

崩点所在的 `tcg_region_init` 要为**翻译缓存（TB cache）**按 region 逐个 `mprotect`。
region 数与 `tb-size` 成正比 ⇒ 地址空间碎片化 / 映射上限触顶的概率跟着涨。

1. **`tb-size 2048 → 256`**（`hostcore/plugins/dshm-vm-bash/lib/vm.js`）：
   region 数 **1280 → 160**（8× 减少）。
   `tb-size` 只决定翻译缓存大小、**不影响正确性**，只是长跑时可能更早重译。
2. **`memBudget()` 内存闸门**：起 VM 之前读 `/proc/meminfo` 的 `MemAvailable`，
   低于 `VM_MIN_AVAILABLE_MIB = 1280` 就**拒绝起 VM 并给人话理由**；
   读不到 ⇒ `fail-open`（不拦截）。用 `MemAvailable` 而不是 `MemFree`，是因为后者不含可回收页缓存。

> **诚实标注**：`tb-size` 降值对 Mate60 那条崩溃是**未实证的缓解**（Mate60 本轮未连接，无法复现）。
> 证据链只到"崩点 = `mprotect` 失败 `exit(1)`"这一步；**具体 errno 未取到**（QEMU 的 `error_report` 走 stderr）。

### 2.5 Mate80 真机复验（本轮，`tb-size=256` 档）

覆盖安装 `+dshm.32` 后冷启动，`node-output.log` 原文节选：

```text
[dshm-vm-bash] 已接管 ctx.subprocess.spawn / spawnTerminal（手持档 + VM 资产齐备）
[dshm-vm-bash] 内存预检通过：MemAvailable 2758 MiB ≥ 阈值 1280 MiB
[dshm-vm-bash] 资产已就位：rootfs 副本 54,493,184 B + guest apk + socket 目录
[dshm-vm-bash] worker: koffi.load 成功 → qemu_system_entry 绑定成功 → 已进入（argc=83）
[dshm-vm-bash] QGA 就绪（+13044 ms）
[dshm-vm-bash] guest 侧已就绪：/bin/bash 可用
[dshm-vm-bash] 终端会话已建立（#1 /dev/hvc0，argv=/bin/sh -i，shell pid=675，前台进程组=675）
[dshm-vm-bash] guest 命令结束：pid=655/670/673/676/688/691/694 全部 rc=0
```

⇒ 降 region 数**没有把 VM 搞坏**：VM 起得来、guest `bash` 可用、终端可用、多条 guest 命令 `rc=0`。

---

## 3 ②③ 两项性能：**只归因，本轮不落代码**（核心树未动）

### 3.1 实读（Mate80 `node-output.log`，冷启动）

启动加载 ≈ **6.94 s**（`BOOT_00_NODE_START` → `BOOT_70_HTTP_READY`），分解：

| 项 | 读数 | 归因 |
|---|---|---|
| 模块加载空档 `LOOP-GAP` | **1680 ms** | `runProfile` 挂载插件树的模块加载 |
| 同步调用总耗时 `SYNC-COUNT` | **1037 ms** | 见下 |
| └ `spawnSync×7` | 474 ms | 那 7 次是**失败的** `busybox` 解包（`EACCES`，PC 档已知，见 `docs/115`） |
| └ `realpathSync×1398` | 160 ms | — |
| └ `readFileSync×1965` | 159 ms | — |
| └ `copyFileSync×81` | 76 ms | — |
| └ `existsSync×2263` | 65 ms | — |
| └ `readSync×83` | 49 ms | — |

### 3.2 已实证的可行优化（**需要改核心树 ⇒ 本轮不做**）

在 DevEco 自带的 node `v24.14.1` 上实测：`--jitless` 下 `module.enableCompileCache(dir)` **可用**
（冷 121 ms → 热 85 ms，约 **30%**，cache 真落盘）。这对 `1680 ms` 的模块加载空档直接有效。

⇒ 但 `main.js` / 核心树入口属"核心树"面，本轮**不动核心树** ⇒ **只登记，不落代码**。
AGC 的 ②③ 两项指标**本轮不可能达标**，出路只有两条（**需用户拍板**）：

1. 允许改核心树（做 compile-cache + 削减同步调用）；
2. 走 AGC 的性能申诉（两项都是**勉强超标**：252 vs 250、9039 vs 4000 —— 前者仅差 2 ms）。

---

## 4 `coreVersion` 为什么**不升**（仍 `0.2.1-alpha.2+dshm.32`）

- `+dshm.31` 是 AGC 上传的那份（崩机包）：其 `vm.js` 里是 **`-accel tcg,thread=multi,tb-size=2048`**。
- 设备上已装的 `+dshm.32` 与重打后的树：**`tb-size=256`** ⇒ **`+dshm.32` 本身就是修复版**。
- 本轮对 `vm.js` 的改动**只有注释订正**（把旧注释里与 §2.3 冲突的措辞改对），
  与仓库先例一致（`docs/115` 记明"注释订正、`coreVersion` 未升"）。
- 代码指纹兜底：设备树与本机树 **13/13 逐字节 sha256 一致**（§7）。

---

## 5 pack-core 的**幂等 bug**（本轮唯一真正的代码缺陷，已修）

### 5.1 现象

裸跑 `tools/pack-core.mjs` 会给**已经打过补丁**的树**重复注入**两条 Scope-Walk / FS-Local 补丁块，
标记数从 2 变 3 ⇒ 函数末尾 `marks !== sites.length` 判红。

### 5.2 根因（读代码定位，非猜测）

`patchAgentInstructionsScopeWalk()` 与 `patchFsLocalPermissionHint()` 里，`site.after` 的形态是
**"before + 追加块"** —— 也就是说 **`before` 是 `after` 的字符串前缀**。
而循环的幂等判据被写在了 `times === 0` 的**内层**：

```js
const times = text.split(site.before).length - 1;
if (times === 0) { if (text.includes(site.after)) continue; /* … */ }  // ← 幂等判据位置错
```

已打过补丁的树里 `before` **仍然出现**（`times === 1`）⇒ 走不到幂等分支 ⇒ 落进重复追加路径 ⇒ 标记数不符。

### 5.3 修法（两处同步改）

把幂等判据提到循环**最前面**：

```js
for (const site of sites) {
  // 幂等判据必须先看 after：本函数 site① 的 after 是"before + 追加块"（before 是 after 的
  // 前缀），若先按 before 计数会得到 1 并**重复注入**（实测 2→3 处标记后判红）。
  if (text.includes(site.after)) continue; // 已打过（幂等）
  const times = text.split(site.before).length - 1;
  if (times === 0) {
    die(`…未找到待替换片段…`);
  }
  // …
}
```

**安全性核实**：全仓只有这 2 处 site 是「`before` 是 `after` 前缀」形态；
其余补丁 site 的 `before` 都不含 MARK ⇒ 新旧判据等价，**改动不改变其它补丁的行为**。

修后重打：权威读数 `node_modules/@deepseek-ai/dsh-agent-instructions/lib/index.js` 里
`DSHM_SCOPE_WALK_TOLERANT` = **2 处**（正确），日志显示「项目根探测容忍补丁已存在（跳过）」。

---

## 6 出包读数（`+dshm.32` release 三件套）

目录：`dist/release-test/`。同一次构建 + 发布签名。

| 文件 | 大小 (B) | sha256 | 是什么 |
|---|---|---|---|
| `DSHM-1.1.0-core0.2.1-alpha.2+dshm.32-arm64-release-signed.app` | 190,301,212 | `09f127f9be2cf52458d4f50a4684134eca964c6a5eecc9fbd4f042aa924165e7` | **app pack**（`buildMode=release` + AGC 发布证书/profile；内层 hap 已按 profile 摘除未授权 ACL ⇒ 实读 `requestPermissions=8`）。**上传 AGC 用这个** ✅ |
| `DSHM-…-release-signed.hap` | 398,461,251 | `6b77845fad140bc0f3b32b2310584b9388ae122ccd03c51a9357b4b1a7306cf5` | 单模块 HAP（发布证书）。AGC 不收，留档用。⚠️ **不能 `hdc install`**（`9568322`，见 `docs/145`） |
| `DSHM-…-release-buildMode-signed.hap` | 398,461,297 | `20c5b64c36c6e6cf05869ef4d3e8e5ea84b16849d18800acc0d27a7c646be43d` | `buildMode=release` + **调试证书**（能 `install -r`，真机验 release 档行为用）；不能上传 |

> `+dshm.31` 那三件（`docs/145` 记录的崩机包口径）**已从 `dist/release-test/` 移除** ——
> 它们的 `vm.js` 是 `tb-size=2048`，留着等于给"传错包"留了个坑；读数已在 `docs/145` 留档。

---

## 7 本轮验证读数（Mate80 实机，只读）

| 项 | 命令 | 结论 |
|---|---|---|
| 端侧验收 | `pwsh -NoProfile -File .\tools\device-acceptance.ps1 -SkipInstall` | **5/5 PASS**（`dist/acceptance/20261011-035357`） |
| 代码指纹 | `pwsh -NoProfile -File .\tools\device-code-fingerprint.ps1` | **一致（13/13）RC=0** —— 设备正在跑的核心树就是本机 `+dshm.32` |
| 运行核心 | `bm dump` / `node-output.log` | `0.2.1-alpha.2+dshm.32`，`profile=ondevice`，`minAPIVersion=60101024` |

回归门禁（改后同一批，全绿）：

```text
node tools\check-resfile-core-zip.mjs            ✅ 配方 +dshm.32；resfile/dist 各 60,808,422 B；sha256 cc953ed0…
node tools\assert-resfile-sync.mjs               ✅ 14 件快照全部同步
node tools\check-core-openharmony-patches.mjs    ✅ 179 passed, 0 failed
node tools\check-vm-bash.mjs                     ✅ PASS 246/246
```

---

## 8 未做 / 留给用户拍板

- **②③ 性能**：本轮**未落代码**（核心树未动）。要么允许改核心树，要么走 AGC 申诉。
- **`targetSdkVersion` 抬 26**：**不影响安装面**（实测 `minAPIVersion` 仍是 `60101024`，见 §1）；真实代价只是
  启用 API 26 行为策略 ⇒ 要抬必须配一轮 PC / 手机 / 平板三端回归，**需拍板**。不抬也不影响审核。
  另：**target=26 包在 API 24 真机上的可装性本仓未实证**（需接 API 24 平板）。
- **Mate60 复现**：Mate60 本轮未连接 ⇒ `tb-size` 降值的实际效果**未实证**。
- **两份 `perfdata`**：`OH_AppTraversal1_2_20261010_222727.perfdata`（2,931,477 B）、
  `OH_AppStart_10_20261010_221738.perfdata`（25,767,938 B）**未解析**。
- **PC 档 / 平板回归**：本轮只做了 Mate80（手机档）。
- **AGC 上传**：由用户决定。
- **`coreVersion` 未升**（仍 `+dshm.32`）；**未 commit / 未建分支 / 未 push**。

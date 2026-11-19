# 143 · 撤除域权限 ⇒ PC 档应用域降级（工具/终端/工作区文件全废）；Release SDK 重出与 DevEco 迁盘收口

> ⚠️ **本文结论已于 2026-10-14 作废（用户拍板，永久生效）**
> 本文 §5 那句「把 域权限 加回源码」**不得再执行**：本包权限面**恒 8 条、不可增**，那三条受限条目
> **永久删除** —— 源码、包体、文档里都不再出现，也不再申请。本文只作事故记录保留（"没有它宿主域
> 掉成 `u:r:debug_hap:s0`、应用数据区 ELF 不能 execve"这条**现象**仍然成立，正是 8 条包必须面对的
> 边界，见 `docs/154`）。规则以 `docs/154` 与 `entry/src/main/module.json5` 的「权限面铁律」为准，
> 门禁 `node tools/check-permission-surface.mjs`。

日期：2026-10-10 夜（承接 `docs/142`）
设备：PC MateBook 14 `86E0226429000417`（鸿蒙 2in1）
产物：`dist/release-test/DSHM-1.1.0-core0.2.1-alpha.2+dshm.31-arm64-release-signed.app`（AGC 上传件）

## 1 本轮两件事

1. **AGC 打回"用了 Beta 版 API"** ⇒ 装 Release 版 DevEco/SDK、重出发布包（§2、§3）。
2. **换出来的 debug 件一装到 PC，PC 档当场瘫**（工具调用 / 终端 / 工作区文件全废）⇒ 查出是
   `docs/142` 二轮"三条 `system_basic` 权限撤掉"里的 **域权限（决定 SELinux 应用域的那条）撤不得**（§4）。
   当时把该条加回源码并真机验证（§5）；**2026-10-14 用户拍板：不再加回** —— 那三条永久删除，
   本包权限面恒 8 条（见文首横幅与 `docs/154`）。

## 2 AGC 打回原文与旧根因

AGC 邀请测试最后审核的原文：

```
经检测发现，您的应用使用了HarmonyOS beta版本的API。
修改建议：为提升消费者使用体验，请使用HarmonyOS release版本的API开发应用，申请上架。
```

旧读数（`docs/142` §7 已钉死）：包内 `module.json.apiReleaseType` / `pack.info.apiVersion.releaseType`
的**唯一来源**是 SDK 自己的 `sdk-pkg.json`（hvigor `merge-profile.js` 的
`apiReleaseType = this.sdkInfo.getReleaseType()`），而当时本机唯一那份 HarmonyOS SDK 是
**`26.0.0.32` / `Beta2`** ⇒ 改 `build-profile.json5` 绕不过去，只能换 SDK。

## 3 换 Release SDK 后重出（本轮读数）

**DevEco 换盘**：旧的那份已从 `C:\Program Files\Huawei\DevEco Studio` 卸载，
新装在 **`D:\Program Files\Huawei\DevEco Studio`**（`C:\Program Files\Huawei` 目录仍在但为空）。
新 SDK（`sdk\default\sdk-pkg.json` 实读）：

| 字段 | 值 |
|---|---|
| `apiVersion` | `26` |
| `displayName` | `HarmonyOS 26.0.0` |
| `releaseType` | **`Release`** |
| `version` | **`26.0.0.105`** |
| `stage` | `Release` |

`default\openharmony\{ets,js,native,previewer,toolchains}\oh-uni-package.json` 与
`default\hms\ets\uni-package.json` 全部 `Release` / `26.0.0.105`。
（注：DevEco 26 随包**不再带** `tools\python\python.exe`。）

**重出命令**（`assembleApp` **不吃** `--mode module`，本轮实测原文：

```
AdaptorError: 00306054 Specification Limit Violation
Error Message: Task [ 'assembleApp' ] was not found in the project desktop.ohos.arm64.
```

⇒ 去掉 `--mode module` 即可）：

```powershell
$ide='D:\Program Files\Huawei\DevEco Studio'
$env:JAVA_HOME="$ide\jbr"; $env:DEVECO_SDK_HOME="$ide\sdk"; $env:DEVECO_CLI_CLT_PATH="$ide\tools"
$env:PATH="$env:JAVA_HOME\bin;$ide\tools\node;$env:PATH"
& "$ide\tools\node\node.exe" "$ide\tools\hvigor\bin\hvigorw.js" assembleApp -p product=default -p buildMode=release --no-daemon
# ⇒ BUILD SUCCESSFUL in 2 min 2 s 485 ms
```

**产物逐项读数**（都是从包里 / 签名器输出里读的，不是源码转述）：

| 项 | 值 |
|---|---|
| unsigned `.app` | 194,963,522 B（`build\outputs\default\desktop.ohos.arm64-default-unsigned.app`） |
| **signed `.app`（AGC 上传件）** | **194,978,342 B / sha256 `e6364fd1b3610e5cc5157d9fbfe9d64a706f5d6bdfac0b694c3e102ad2b4dd1b`** |
| `.app` 内层 `entry-default.hap` | 396,104,632 B |
| signed `.hap`（排障用，AGC 不收） | 398,457,162 B / sha256 `c498bc401adc93c1ca5afa5364b4b9641cabb51ba5b1063998edd0ae46319746` |
| `pack.info` | bundle `com.dshm.dshclient` / 1.1.0(1010000) / `phone,tablet,2in1` / `apiVersion{compatible:24, target:24, releaseType:Release}` |
| `module.json` | `compileSdkVersion 26.0.0.105` / `compileSdkType HarmonyOS` / **`apiReleaseType Release`** / `minAPIVersion = targetAPIVersion = 60101024` / `requestPermissions = 8` |
| `verify-app`（`.app` 与 `.hap` 都跑） | `rc=0`、`verify: Verify success`；内嵌 profile `type=release`、`allowed-acls` 2 条、`uuid 9e469e60-a4a8-4919-b181-82760b3abbe0` |

⇒ **AGC 那条"Beta 版 API"已消除**（`releaseType` 从 `Beta2` → `Release`）。
**注意**：这一版是"8 条声明"那一版的读数；§5 之后源码改成 9 条 ⇒ 这个 `.app` 需**重编重签**才与源码一致。

## 4 P0：域权限 撤掉 = PC 档的应用域被降级

### 4.1 症状

用上面的 Release SDK 编出的 **debug 件**覆盖安装到 PC 后（用户数据未动）：

- 用户可见：**工具调用 / 侧边栏 / 终端 / 工作区文件全废**（终端一直"正在启动"）。
- `update-device.ps1` 第 8 步直接判红：
  `exec 探测未全通（共 10 项）：python3.12=fail(EPERM)，git=缺，git-core/git=缺，git-remote-http=缺，rg=fail(EPERM)，ash=fail(EPERM)，bash=fail(EPERM)，system-sh=缺，git-ls-remote=缺`。

### 4.2 三次读数对照（同一台设备、同一核心树 `+dshm.31`、只换 HAP）

| 项（`dshm-host.log` 原文） | 11 条声明（`dist/sideload` r14，C 盘 Beta2 编） | **8 条声明**（Release SDK 编，撤掉三条） | **9 条声明**（只把 域权限 加回） |
|---|---|---|---|
| 宿主域（`终端能力 toybox域`） | `u:r:develop_tools_debug_hap:s0` | **`u:r:debug_hap:s0`** | `u:r:develop_tools_debug_hap:s0` |
| `exec 探测` | 10/10 全 `ok` | `python3.12/rg/ash/bash = fail(EPERM)`，`git*`/`system-sh = 缺` | 10/10 全 `ok` |
| `终端能力汇总` 的 `toybox-exec-ash` | `rc0` | **`rc126`**（`env: exec …/files/bin/ash: Operation not permitted`） | `rc0` |
| `toybox-stat-sh` | `rc0` | `rc1`（`ls: /system/bin/sh: Permission denied`） | `rc0` |
| `libs-exec` | `err(EACCES)` | `err(EACCES)` | `err(EACCES)`（**三轮都一样**，既有已知项，与本次无关） |

> 三次的 `libs-exec=err(EACCES)` 是不变量 ⇒ 别把它当成本次的症状。

### 4.3 根因（不是推演）

平台按**「有没有 `ohos.permission.域权限`（自定义沙箱）」×「包的 `debug` 标志」**挑应用域：

| 声明 域权限 | 包 `debug` | 应用域 | 数据区里**脚本**能 execve | 数据区里 **ELF** 能 execve |
|---|---|---|---|---|
| 有 | `true` | `u:r:develop_tools_debug_hap:s0` | 能（`docs/140` 量的那一档） | 能 |
| 有 | `false` | `u:r:develop_tools_hap:s0` | 不能（`docs/140`：只有 `bash` 翻 `denied`） | 能 |
| **无** | `true` | **`u:r:debug_hap:s0`** | **不能** | **不能（本轮新增读数）** |

- 前两行是 `docs/140` 已有的读数（当时那份 release 件**仍声明着**这三条权限）。
- 第三行是本轮实测：**没有自定义沙箱时，应用数据区里连 ELF 都 execve 不了** ⇒
  `files/bin/{ash,bash,git,rg,python3}`（脚本垫片）与 `toolchain/python/bin/python3.12`（真 ELF）
  一起 `EPERM`；`files/bin` 下那些 busybox applet 在 `ls` 里显示成 `-?????????`。
- ⇒ **官方答复里那条"沙箱内自建虚拟根（工具链随包解压到 `filesDir`、`HOME` 指过去）平替
  域权限" 是错的**：虚拟根只是**路径约定**，给不了 SELinux 域。
  域权限 的真实作用不是"文件访问的便利项"，而是 **PC/2in1 档能 execve 的前提**。
- ⇒ `docs/142` §"代价"只登记了"`~` 全域读写不再可用"，**漏了这条**，本轮补上。

### 4.4 旁证（同一次安装暴露的第二个、独立缺陷）

那次启动的工具链分支同时暴露了一个**与本 P0 无关**的既有坑（当场留证，待修）：

```
工具链：git 归档已换代（dshm-signed.txt 变化），强制重解以取到已签名的 ELF
工具链：解包前清理失败（本轮跳过，下次启动重试）：Error: ENOTEMPTY, Directory not empty:
        …/files/toolchain/gitroot '…/files/toolchain/gitroot'
```

⇒ 清理走的是**非递归**删（`ENOTEMPTY`），失败后**跳过本轮解包**，且"下次启动重试"是真话
（连开两次都是同一条）⇒ `git*` 一直 `缺`。这解释了 §4.1 里那批 `缺`（与 `EPERM` 成因不同）。

## 5 处置

1. **源码**：`entry/src/main/module.json5` **加回** `ohos.permission.域权限`
   （连着一段写明"为什么撤不得"的注释）；`entry/src/main/resources/base/element/string.json`
   加回 `perm_custom_sandbox_reason`。
   【2026-10-10 深夜订正，见 `docs/144`】本节原写"另两条（用户文件读写权限 /
   全盘访问权限）**仍撤**（官方等价路线：picker 选目录 + `FILE_ACCESS_PERSIST`；
   本仓代码零调用）"—— **已被真机读数推翻，两条也已加回**：撤掉后 `~`
   及其下**一切**回 `EPERM`，而用户**已登记的两个工作区与会话 cwd 都在那里** ⇒ 侧边栏
   「工作区文件」列表空 + 终端 pty 子进程 `chdir(2) failed.: Permission denied`。
   现状：源码 `requestPermissions` = **11 条**（三条受限权限全量声明）。
2. **先回退、后验证**：先把 `dist/sideload` 的 r14（11 条声明）覆盖安装 ⇒
   `exec 探测 10/10`、宿主域回 `develop_tools_debug_hap`、`home` 指纹 `links=14 size=3440` 装前=装后；
   再用"只加回 域权限"的新 debug 件覆盖安装 ⇒ 同样 10/10（§4.2 第三列）。
3. **发布档的后果（已由 `docs/144` 收口）**：发布 profile 的 `allowed-acls` 只有 2 条
   （`ALLOW_EXTERNAL_NATIVE_CODE` / `FILE_ACCESS_PERSIST`）⇒ 声明了 域权限 而
   profile 没授权，按 `docs/142` 的 `PERMISSION_ACL_RULE` 判据**发布档会装不上**。
   ⇒ 修法**不再**是"去 AGC 申请这条 ACL / 或放弃 PC 档"，而是 **源码全量声明 11 条 +
   发布 / AGC 档在签名之前自动摘除**（`tools/sign-release-hap.ps1` 新增 `[0]` 步：
   `.hap` 自动摘、`.app` 先探测后判红；摘除结果与既有发布件逐条相同 ⇒ 上传件无需重出）。

## 6 DevEco 迁盘顺带炸掉的一串写死路径（本轮一并收口）

DevEco 从 C 盘搬到 D 盘，`tools/` 下**12 个脚本**里写死的 `…\Huawei\DevEco Studio\…` 当场全失效：

`sign-release-hap.ps1`、`update-device.ps1`、`device-acceptance.ps1`、`device-code-fingerprint.ps1`、
`pack-core.mjs`、`place-toolchain.mjs`、`strip-ungranted-acl-perms.mjs`、`check-arkts-entry.mjs`、
`check-layout-fixtures.mjs`、`dshtest.py`、`electron-runtime/verify.ps1`、`node-runtime/sign-native.ps1`。

修法 = 收出一个**统一解析口**（**候选根必须真的含 `tools/hvigor/bin/hvigorw.js`** 才算命中
—— 只看目录存在会把卸载残留的空目录当安装根；顺序 `DEVECO_HOME` → `Program Files*`
→ 逐盘符 `X:\Program Files\Huawei\DevEco Studio`、`X:\Huawei\DevEco Studio`）：

- `tools/lib/deveco-home.mjs`（node 侧）
- `tools/lib/deveco-home.ps1`（PowerShell 侧，UTF-8 with BOM + CRLF）

并新增守卫门禁 **`tools/check-deveco-paths.mjs`**：扫 `tools/` 下 `.mjs/.cjs/.js/.ts/.ps1/.sh/.py/.bat/.cmd`，
**只要代码里出现引号包住的、含产品名的 Windows 绝对路径就判红**；注释整块跳过
（解释"当年为什么写死过"恰恰需要在注释里把那两条路径写出来）；`--self-test` 4 个变异体。
实测：`rc=0`（扫 115 个脚本、0 处写死）+ `--self-test` 4/4。

## 7 未做 / 未验

- **手机 / 平板档**：本轮未验（`bash` 仍按 `docs/104` / `docs/120` 走 guest VM 通道）。
- **发布档装机**：未做（发布签名与设备上那份调试签名互斥，只能测试机 + 先卸载 ⇒ 会清 el2 数据，**必须先问用户**）。
- **`dist/release-test` 的 `.app` / `.hap` 与源码已不一致**（那一版 8 条声明，源码现已 9 条）⇒ 需重编重签。
- **`dist/sideload` 的正式件仍是 r14**（11 条声明、Beta2 编）⇒ 需重出 r15。
- **§4.4 那个 `ENOTEMPTY` 清理坑**：只留证，未修。
- **`update-device.ps1` 的一次性误判**：本轮第 5 步 `hdc install -r` 返回**空输出** ⇒ 脚本判"安装失败"，
  而同一条命令手动重跑 `rc=0` + `install bundle successfully`。判据只看 `-match 'successfully'`
  ⇒ 空输出与"没装上"被混为一谈（待修）。
- **`bm dump` 的 `compileSdkVersion` 仍报 `26.0.0.32`**，而包内 `module.json` 是 `26.0.0.105`
  ⇒ 平台侧这个字段的口径待查（`apiReleaseType` 已跟着变成 `Release`，说明包确实换了）。

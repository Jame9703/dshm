# 142 · 发布包「声明了 ACL 权限但发布 profile 没授权」＝设备侧拒装（PERMISSION_ACL_RULE）

> ⚠️ **本文结论已于 2026-10-14 作废（用户拍板，永久生效）**
> 本文所述的「源码全量声明 11 条 / 把三条受限条目加回源码」**一律不得再执行**：本包权限面
> **恒 8 条、不可增**，那三条受限条目**永久删除** —— 源码、包体、文档里都不再出现，也不再申请。
> 本文只作事故记录保留。规则以 `docs/154` 与 `entry/src/main/module.json5` 的「权限面铁律」为准，
> 门禁 `node tools/check-permission-surface.mjs`。

日期：2026-10-10 深夜
上游物料：`D:\desktop\release\`（`dshm.p12` / `dshm.cer` / `dshmRelease.p7b`）
产物：`dist/release-test/DSHM-1.1.0-core0.2.1-alpha.2+dshm.31-arm64-release-agcupload-signed.hap`
新增工具：`tools/strip-ungranted-acl-perms.mjs`

## 1 问题（`docs/141` 留下的那个"未验证"落地了）

`docs/141` §4 登记过一条未知：*"AGC 上传时会不会因 `module.json5` 声明了 profile 未授权的 3 条 ACL 被判不匹配"*。
本轮把**设备侧**那一半钉死了 —— 不是"未必」，是**确定拒装**。

逐条读数：

| 项 | 值 | 来源 |
|---|---|---|
| 包内 `module.json` 的 `requestPermissions` | **11 条** | 从 `entry-default-unsigned.hap` 里读出来的（不是源码转述） |
| 其中 `system_basic` 级 | 4 条：`ALLOW_EXTERNAL_NATIVE_CODE` / 用户文件读写权限 / 全盘访问权限 / 域权限 | `sdk/default/openharmony/toolchains/lib/PermissionDefinitions.json` 的 `availableLevel` |
| 发布 profile `dshmRelease.p7b` 的 `allowed-acls` | **2 条**：`ALLOW_EXTERNAL_NATIVE_CODE` / `FILE_ACCESS_PERSIST` | `verify-app` 导出的 profile |
| ⇒ 声明了但**没被授权**的 | **3 条**：用户文件读写权限 / 全盘访问权限 / 域权限 | 上面两行之差 |

## 2 判据：安装时 BMS 会做 ACL 检查，不在 allowed-acls 里就拒

读的是上游源码（`openharmony/bundlemanager_bundle_framework`，`master`）：

- `services/bundlemgr/src/bundle_permission_mgr.cpp` → `CreateHapPolicyParam()`：
  `hapPolicy.aclRequestedList = innerBundleInfo.GetAllowedAcls();`
  —— **profile 的 allowed-acls 就是这台设备认的 ACL 白名单**，并打日志
  `-n <bundle> apl:<apl> req permission:<N> acls:<M>`。
- 同文件 `BundlePermissionMgr::InitHapToken()`：把这份 hapPolicy 交给
  `AccessToken::AccessTokenKit::InitHapToken(hapInfo, hapPolicy, tokenIdeEx, checkResult)`；
  失败即 `return ret`（安装链随之失败）。
- 同文件 `GetCheckResultMsg()`：`reason == PERMISSION_ACL_RULE` 时回 **`PermissionName: <那个权限>`**
  —— 即失败报文会**点名**是哪条权限越了 ACL 白名单。
- 备注：`X86_EMULATOR_MODE` 下有一条 `ACL_IGNORE_CHECK`（模拟器放行），**真机没有这条豁免**。

⇒ 结论：**发布档 apl=normal + 声明 `system_basic` 权限 + 该权限不在发布 profile 的 allowed-acls 里 = 装不上**
（设备侧呈现为 "grant request permissions failed" 类报错并点名权限）。
调试档之所以一切正常，是因为**调试 profile 有 5 条 ACL**，把这 3 条都覆盖了（`docs/108` 量到的正是这个门）。

> 未做 / 未验：**AGC 上传**那一侧本轮没实测（本机没有 AGC 上传通道）。按上面这条同源判据推断，上传/审核大概率同样会被这 3 条声明挡住；
> 用户上传时若被点名，本档的产物即为对策。这句是推断，不是读数。

## 3 修法：签名**之前**把没被授权的声明摘掉（`tools/strip-ungranted-acl-perms.mjs`）

```powershell
# 1) hvigor 编到未签名那一步（SignHap 会成功，unsigned 中间件照样落在 outputs 下）
# 2) 摘声明
node tools/strip-ungranted-acl-perms.mjs --in entry\build\default\outputs\default\entry-default-unsigned.hap `
    --profile D:\desktop\release\dshmRelease.p7b --out dist\release-test\_unsigned-nograntedacl.hap
# 3) 发布签名（自带 verify-app 复验 + type 判据）
.\tools\sign-release-hap.ps1 -InFile dist\release-test\_unsigned-nograntedacl.hap `
    -OutFile dist\release-test\DSHM-...-release-agcupload-signed.hap
```

工具的判据（**不做猜测**）：

- **必须在签名之前**：签名摘要覆盖 `module.json`，签完再改就是把包改坏。
- 只摘 `availableLevel` 为 `system_basic` / `system_core` **且**不在该 profile `allowed-acls` 里的；
  `normal` / `user_grant` 一律不动（它们不靠 ACL）。
- 权限表里查不到的权限**保留**并告警（fail-open：宁可留下一看就知道的错，也不静默摘掉一条可能有用的）。
- 只改 `module.json` 一个条目，其余条目**逐字节原样搬运**（保留原压缩方式；`--dry-run` 可先看清单）。

## 4 读数（前 / 后，都是原文）

- 正控制（发布 profile，2 条 ACL）→ **摘 3 条**：
  `ohos.permission.用户文件读写权限 [system_basic]`、`ohos.permission.全盘访问权限 [system_basic]`、
  `ohos.permission.域权限 [system_basic]`；保留 8 条。
- 负控制（**调试** profile，5 条 ACL，同一份 unsigned）→ **摘 0 条**，11 条全留
  ⇒ 证明工具不是"见 ACL 就摘"，而是真的对着 profile 比。
- 包体差异：摘前/摘后逐条目比对 **126 个条目里只有 `module.json` 变**（4,070 B → 3,567 B，method=0 两种形态相同），
  其余 125 条 sha256 全等。
- 签名后复验：`Digest verify result: true` / `verify: Verify success` / `verify-app success`；
  内嵌 profile `type=release`、`allowed-acls=ALLOW_EXTERNAL_NATIVE_CODE,FILE_ACCESS_PERSIST`、`uuid=9e469e60-…`；
  包内 `requestPermissions` = **8 条**（11 − 3）。
- 两份发布签名件的逐条目比对：**127 个条目里只有 `module.json` 不同**。
  产物 `dist/release-test/DSHM-1.1.0-core0.2.1-alpha.2+dshm.31-arm64-release-agcupload-signed.hap` =
  **398,452,827 B** / sha256 `05810ccd9fa74ee879a7c726ac6082e20878b5575aa17146a7be13073ce8a8cf`
  （与"不摘"的那份**同字节数**是巧合：HAP 签名块会补位对齐；判等请看逐条目，别拿整包哈希）。

## 5 后果（对功能面意味着什么）

- **发布包**：那 3 条权限没了声明 ⇒ `~` 全域读写、域权限 那套**在发布档不可用**
  ——但这与发布 profile 的能力面**本来就一致**（profile 不授权 ⇒ 即使声明也是死字），所以是**把话说清楚**，不是削功能。
- **调试 / 侧载包**：**一个字都没改**。`module.json5`、`build-profile.json5` 的 `signingConfigs.default`、
  `dist/sideload/**` 全部原样 ⇒ PC / 手机 / 平板三端的既有功能与回归面不受影响。
- 想恢复发布档的那 3 条：去 AGC 申请 ACL → 重新生成发布 profile（新 `.p7b`）→ **这一遍不跑摘除**、直接
  `tools/sign-release-hap.ps1` 签即可（声明与 profile 齐了，工具会摘 0 条）。

## 6 未做 / 待拍板

- **AGC 上传实测未做**（见 §2 注）。
- **发布包未在设备上装机验证**：发布签名与调试签名互斥，主力机（已装调试签名的同包名）必须先卸载 ⇒ 只能在**测试机**上做。
- ~~**`targetSdkVersion` 仍是 `6.1.1(24)`**（`docs/110` 拍板未动）~~ ⇒ **2026-10-11 已做**：抬到 `26.0.0(26.0.0)`（`docs/147`），`compatible` 仍 24。
  用户提出"只要向下兼容 24、实际是 26" ⇒ 要抬的是 `targetSdkVersion`（`compileSdk` 本来就是 26）；
  抬 target 会启用 API 26 的**行为策略**（命中 3 条）⇒ 需 PC / 手机 / 平板三端各跑一轮回归（`docs/147` §10）。
- `docs/140` §5 的 release 档「脚本执行被平台拒（`bash=denied`）」三项修法**仍未做**（与本档同属 release 档差异，待拍板）。

## 7 二轮（同日）：按官方路线把三条从**源码**撤掉

用户读完 §1–§3 后拍板：**按官方路线来，三条删掉**（"先按官方路线来，三条线删掉，保证功能正常的前提下，先编译 APP，我 AGC 上传审核测试"）。
于是本轮不再"签名前打补丁"，而是**改源码**（§3 的摘除工具退化为纯粹的自检手段）。

**改了什么**（三处，代码逻辑零改动）

| 文件 | 改动 |
|---|---|
| `entry/src/main/module.json5` | 三条 `system_basic` 声明（用户文件读写权限 / 全盘访问权限 / 域权限）→ 替换为一段带日期的注释（写明撤除理由、官方零门槛等价路线、代价） |
| `entry/src/main/resources/base/element/string.json` | 三条就此失去引用方的 `reason` 字符串（`perm_user_file_reason` / `perm_full_disk_reason` / `perm_custom_sandbox_reason`）一并删掉，不留孤儿 |
| `platform/src/main/ets/system/FilePicker.ets`、`entry/src/main/ets/pages/WebApp.ets` | 两处**注释订正**（前者补"profile 那 5 条仍是设备侧硬上限、只是我们不再去够"；后者那句"Host 访问用户目录实际依赖 域权限"改掉并指向 2026-10-03 的既有更正） |

**为什么不需要改代码**：这三项在本仓**一处 API 调用都没有**（`rg -g '!docs/**'` 命中全部落在 `module.json5` 声明与注释上）——
package 侧本来就只有"声明"，没有 `requestPermissionsFromUser` 之类。撤声明是纯清单改动。

**读数**

- `module.json5` 的 `requestPermissions`：**11 → 8**（留下的 8 条：`INTERNET` / `GET_NETWORK_INFO` / `KEEP_BACKGROUND_RUNNING` /
  `PREPARE_APP_TERMINATE` / `ALLOW_EXTERNAL_NATIVE_CODE` / `FILE_ACCESS_PERSIST` / `STORE_PERSISTENT_DATA` / `MICROPHONE`）。
- 对**同一份** release unsigned 跑 `tools/strip-ungranted-acl-perms.mjs --dry-run` ⇒ **摘 0 条**
  （源码声明与发布 profile 的 ACL 面已对齐 ⇒ 发布签名**不再需要**任何打补丁步骤，§3 那份"摘 3 条"的产物已被本轮的源码件取代）。

### 7.1 订正（2026-10-10 深夜，见 `docs/144`）：本节**整节作废**

§7「按官方路线把三条从源码撤掉」的**前提不成立**，已回滚：

- **§5 那句「调试 / 侧载包：一个字都没改 ⇒ 三端既有功能不受影响」是错的**（同一轮里 §7 就改了源码，自相矛盾）。
- **三者各自独挡一面**：域权限 决定 SELinux 应用域（撤了 ⇒ `debug_hap`，数据区里的脚本与 ELF 全都 execve 不了，`docs/143`）；
  全盘访问权限 + 用户文件读写权限 是用户目录的通行证（撤了 ⇒ `~` 及其下**一切**回 `EPERM`，
  而用户**已登记的两个工作区与会话 cwd 都在那里** ⇒ 侧边栏「工作区文件」空 + 终端 pty 子进程 `chdir(2) failed.: Permission denied`，`docs/144`）。
- **正解是 §3 那条**（源码全量声明 + 签名前摘除），本轮已把它**自动化**进 `tools/sign-release-hap.ps1` 的 `[0]` 步：
  `.hap` 输入自动摘到临时件再签，`.app` 输入先探测、摘除数 > 0 就判红（fail-closed）。
- 现状：`requestPermissions` **11 条**；对同一份 unsigned 跑摘除 ⇒ **摘 3 条 / 保留 8 条**，与既有发布件逐条相同 ⇒ **AGC 上传件无需重出**。
- 成品包内实读：`requestPermissions=8`、`deviceTypes=phone,tablet,2in1`、`minAPIVersion=targetAPIVersion=60101024`、
  `bundleName=com.dshm.dshclient`、`versionCode=1010000` / `versionName=1.1.0`；
  `verify-app success`、内嵌 profile `type=release`、`allowed-acls=ALLOW_EXTERNAL_NATIVE_CODE,FILE_ACCESS_PERSIST`。
- 产物：`dist/release-test/DSHM-1.1.0-core0.2.1-alpha.2+dshm.31-arm64-release-signed.hap` =
  **398,452,827 B** / sha256 `a408520dad65750619b5c865ee303dcb2054069310fa826c033c34e5aee57797`。
- 门禁：仓内可跑的那套 **23/23 rc=0**（含 `check-store-readiness` → `RESULT: PASS`；`check-doc-refs`/`check-dead-code`/`check-fs-fence` 等全绿）。
  `debug` 与 `release` 两种 `buildMode` 均 `BUILD SUCCESSFUL`。

**代价（三端一致，如实登记）**：`~` 的**全域**读写不再可用 —— 这次是**源码级**撤除，
所以**PC 侧载包（debug）也一样**，不再只是发布档降级。工作区文件能力仍由「沙箱 + 用户已选目录（picker 授权 + `FILE_ACCESS_PERSIST`）」提供。
⇒ `dist/sideload/**` 那份侧载包现在是**旧口径**（11 条），本档**没有**重出；要不要重出并做三端复测，等 AGC 这一步有结论再定。

## 8 三节（同日）：AGC 上传要的是 `.app`（app pack），不是 HAP

用户点出"上传 AGC 需要的是 `.app` 的包"后补齐。**`.app` 与 `.hap` 是两层东西**：前者是 app pack（容器），后者是容器里的一个模块包。

**怎么出**：`hvigorw assembleApp -p product=default -p buildMode=release --no-daemon`
⇒ `build/outputs/default/desktop.ohos.arm64-default-unsigned.app`（194,962,246 B）
与同名 `-signed.app`（194,977,367 B，**用调试证书签的 ⇒ 同样不能上传**）。

**包结构（实读，`assembleApp` 的产物只有 3 个条目）**

| 条目 | 未压缩 | 压缩后 |
|---|---|---|
| `entry-default.hap` | 396,100,555 B | 194,960,851 B |
| `pack.info` | 1,025 B | 1,025 B |
| `pac.json` | 36 B | 36 B |

**关键实测（决定了签法）**：`.app` 里那个内层 `entry-default.hap` 是**未签名**的 ——
`verify-app` 原文 `Verify Hap failed, signature not found.` / `No Hap Signing Block before ZIP Central Directory`；
而 `verify-app` 对 `.app` **本身**能过（`verify: Verify success` / `verify-app success`，实测对 hvigor 出的 `-signed.app` rc=0）。
⇒ **只签容器**，内层 HAP 保持未签名（unsigned 与 signed 两个 `.app` 里的内层 HAP 逐字节相同，`075303a9…`，可互证）。

**签法**：与签 HAP **同一条命令**（`sign-app -mode localSign … -inFile <x.app>`，**不带** `-inForm`）——
这正是 hvigor `SignApp` 的做法（`SignCommandFactory` 对 `SignTypeEnum.APP` 且 `compileSdk≥9` 选 `HapSignCommandBuilder`，
其 `initCommandParams()` 逐项与签 HAP 相同）。`tools/sign-release-hap.ps1` 已扩到 `.app`（输出名跟着输入的扩展名走），用法不变。

**产物**：`dist/release-test/DSHM-1.1.0-core0.2.1-alpha.2+dshm.31-arm64-release-signed.app`
= **194,977,066 B** / sha256 `68166cb5e860bbe8f690c0ae2a70576e5334c79b10124d9add77be7bb3a2fcbd`
（`verify-app success`；内嵌 profile `type=release`、`allowed-acls=ALLOW_EXTERNAL_NATIVE_CODE,FILE_ACCESS_PERSIST`；
内层 HAP 与 unsigned app 里那份**逐字节相同**）。

**包内读数**：`pack.info` → `bundleName=com.dshm.dshclient`、`versionCode=1010000` / `versionName=1.1.0`、
`deviceType=phone,tablet,2in1`、`moduleType=entry`、`apiVersion { compatible:24, target:24 }`；
内层 HAP 的 `requestPermissions` = **8**（§7 的源码改动生效）。

**已确认（2026-10-10，AGC 邀请测试被打回）**：上面那条“待观察（推断）”命中了 ——
`pack.info` 的 `apiVersion.releaseType` = **`Beta2`**，AGC 原文：
「经检测发现，您的应用使用了 HarmonyOS beta 版本的 API……请使用 HarmonyOS release 版本的 API 开发应用，申请上架」
（指 `https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/overview-allversion`）。

**来源已钉死**：本机唯一那份 HarmonyOS SDK 自己就写着 Beta2 ——
`C:\Program Files\Huawei\DevEco Studio\sdk\default\sdk-pkg.json` 与
`sdk\default\openharmony\{ets,js,native,previewer,toolchains}\oh-uni-package.json`、
`sdk\default\hms\ets\uni-package.json` 全部是 `releaseType: Beta2` / `version: 26.0.0.32`；
hvigor 侧这条字段只有一个来源 —— `merge-profile.js` 的 `apiReleaseType=this.sdkInfo.getReleaseType()`
（`make-pack-info.js` 同源），而 `ohos-project-build-profile-schema.json` **没有任何可覆盖它的配置项**
⇒ **改 `build-profile.json5` 绕不过去，必须换 Release 版 SDK 重编**。

**本机现状：一份 Release 版 HarmonyOS SDK 都没有**（已扫全盘 `sdk-pkg.json`，只有 2 处：DevEco 自带 + emulator）。
- `C:\Program Files\Huawei\DevEco Studio\sdk\default\*` = HarmonyOS `26.0.0.32` / **Beta2**（唯一一份 HarmonyOS SDK）。
- `C:\Users\Sol\AppData\Local\OpenHarmony\Sdk\26.0.0\js\oh-uni-package.json` 倒是 `releaseType: Release`
  （`26.0.0.38`）—— 但那是 **OpenHarmony** 组件，且只下了 `js` + `toolchains`（**没有 `ets`/`native`/`previewer`**）
  ⇒ **不能拿来编 ArkTS**，也不能把 `compileSdkType` 变成 HarmonyOS。
- 顺带排除一条：SDK 仓库接口 `POST https://devecostudio-drcn.deveco.dbankcloud.com/sdkmanager/v7/hos/getSdkList`
  （公开可达，`AppId: DevEcoStudio_Lib`）**只返回模拟器系统镜像**（api 13~24），**不含** HarmonyOS SDK 组件 ⇒ 拉不到。

**平台版本 ↔ API 对照**（hvigor 原文 `@ohos/hos-sdkmanager-common/build/res/hos-config.json`）：
`26.0.0→26`、`6.1.1→24`、`6.1.0→23`、`6.0.2→22`、`6.0.1→21`、`6.0.0→20`、`5.1.1→19` …；
同文件 `sdkSufNameMapper`：`Release→""`、`Beta→"B"`、`Developer Beta→"DB"`。

**旁证（6.1.x 线确实有 Release 版 SDK 在流通）**：WorkBuddy 包内读数是
`compileSdkVersion: 6.1.0.105` + `compileSdkType: HarmonyOS` + **`apiReleaseType: Release`**（`docs/114` §2），
而它以 `phone/tablet/2in1` 在 AppGallery 正式分发。

**待办（等 Release SDK 到位）—— 已落实，见 `docs/143`**：用户装好 Release 版 DevEco 之后，
本仓已重出发布包并实读复核：`module.json.apiReleaseType === "Release"`、
`pack.info.apiVersion.releaseType === "Release"`、`compileSdkVersion = 26.0.0.105`，
`minAPIVersion = targetAPIVersion = 60101024`（**不需要**在 `products[0]` 里另写 `compileSdkVersion`
—— SDK 换了 `apiReleaseType` 就跟着换了）。逐项读数、以及**同一轮查出的 P0**
（域权限 撤不得：撤了之后宿主域从 `u:r:develop_tools_debug_hap:s0` 掉成
`u:r:debug_hap:s0`、PC 档的工具/终端/工作区文件全废）见 `docs/143`。
仍成立的两条：**`compileSdkVersion` 必须 ≥ `targetSdkVersion`**、
**不要手改包内 `module.json` 的 `apiReleaseType` 去蒙过 AGC**（伪造元数据，且与
`compileSdkVersion` 交叉可核）。

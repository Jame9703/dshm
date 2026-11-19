# PC-only 重建与 CUSTOM_SANDBOX 权限升级

| 项 | 内容 |
|---|---|
| 文档编号 | `docs/215` |
| 日期 | 2026-10-21 |
| 状态 | 已按用户授权切到 `com.dshm.dshclient`；源码清理、权限升级、release HAP 与正式发布签名完成；日常运行改由 DevEco Studio Run |
| 上位文档 | `docs/214` |

## 1. 结论

PC 工程已切换为新的 11 条权限标准：

| 类别 | 权限 |
|---|---|
| ACL（3） | `ALLOW_EXTERNAL_NATIVE_CODE`、`FILE_ACCESS_PERSIST`、`CUSTOM_SANDBOX` |
| 2in1 kernel（2） | `kernel.IGNORE_LIBRARY_VALIDATION`、`kernel.EXEMPT_ANONYMOUS_EXECUTABLE_MEMORY` |
| 普通（6） | `INTERNET`、`GET_NETWORK_INFO`、`KEEP_BACKGROUND_RUNNING`、`PREPARE_APP_TERMINATE`、`STORE_PERSISTENT_DATA`、`MICROPHONE` |

新 Profile
`~/Download/com.huawei.hmos.browser/DSHMpcRelease.p7b`
已核实：

- `type = release`
- `bundle-name = com.dshm.dshclient`
- `app-identifier = 6917614360926110054`（AGC 唯一正式 App ID）
- `allowed-acls = CUSTOM_SANDBOX / ALLOW_EXTERNAL_NATIVE_CODE / FILE_ACCESS_PERSIST`

## 2. 两条 kernel 权限的实际作用

SDK 的 `PermissionDefinitions.json` 口径：

| 权限 | 级别 / 授权 | 版本 | 设备 | 作用 |
|---|---|---|---|---|
| `kernel.EXEMPT_ANONYMOUS_EXECUTABLE_MEMORY` | normal / system_grant | 23 | 2in1 | 允许匿名可执行内存；V8 JIT 与 QEMU 翻译缓存需要 |
| `kernel.IGNORE_LIBRARY_VALIDATION` | normal / system_grant | 20 | 2in1 | 允许加载未通过系统库签名校验的原生 `.so` |

两者 `provisionEnable=false`，不需要 AGC 审批，不写 Profile ACL，直接写入
`requestPermissions`。它们不是 `ALLOW_WRITABLE_CODE_MEMORY` 的别名。

## 3. 权限恢复后的运行路线

- V8 JIT 已在设备上实测触发 native `CHECK` 崩溃；为保证 Run，Host 当前固定使用
  `--jitless`，`buildHostArgv(entry, false)` 仅保留后续 JIT 验证入口。
- `dshm-vm-bash` 的启用判据恢复为“先探宿主原生 exec”：
  - 可执行：不接管，bash 与侧边栏终端走宿主原生 exec / PTY；
  - 不可执行：平板才继续走随包 guest VM 后备。
- `git`、`rg`、Python、pnpm 假壳等随包工具不再被迫走进程内替代；原进程内实现保留为降级路径。
- `kernel.IGNORE_LIBRARY_VALIDATION` 覆盖本地开发插件和工具自带、未由系统库签名链验证的原生模块。

## 4. 移动端清理

PC 工程保留 `tablet` / `2in1`，删除以下手机专属面：

- `FormFactor.PHONE`、`isPhoneForm()`、`isFoldableDevice()` 的手机分支；
- `SETTINGS_SHIM_JS` 设置页手机横排布局；
- `ONBOARDING_SHIM_JS` 首次引导手机布局；
- `dshm-phone` 类与 `PHONE_CLASS`；
- `check-two-project-parity.mjs` 的双工程逐字节同步要求。

平板仍保留抽屉侧栏、浮动入口、返回消费、跟随旋转和底部手势区适配。

新增 `tools/check-pc-only-surface.mjs`，阻断手机形态、手机 UI 垫片和
`DSHM-mobile` 构建耦合回流；`--self-test` 使用 `FormFactor.PHONE` 变异体证明门禁有牙。

## 5. 构建读数

`entry:default@CompileArkTS`：`BUILD SUCCESSFUL`，0 error。

未签名 release-mode HAP（`assembleApp` 在 `SignHap` 前仍会先产出内层未签名 HAP）：

| 项 | 值 |
|---|---|
| 文件 | `entry/build/default/outputs/default/entry-default-unsigned.hap` |
| 大小 | `437122537` B |
| SHA-256 | `3df8a92f5ce48ac0eb5ce0da4bd15006afbbd9aa2293b55c858c9aaaaa5a4744` |
| bundleName | `com.dshm.dshclient` |
| 版本 | `1.1.4 (1010004)` |
| buildMode / debug | `release / false` |
| deviceTypes | `tablet / 2in1` |
| requestPermissions | 11 条，与上文一致 |
| abilities | `EntryAbility / BackGroundAbility` |
| backgroundModes | `dataTransfer / audioRecording / taskKeeping` |

debug 与 release 两种模式均已通过编译、资源、Native、PackageHap；仅 `SignHap` 因当前
`build-profile.json5` 仍是 DevEco 自动签名占位而失败（`00303107`）。

## 6. 正式包切换与运行方式

用户 2026-10-21 明确授权当前 PC 工作区直接切换正式包。已同步修改：

- `build-profile.json5` 的 product bundleName；
- AppScope bundleName；
- `shortcuts_config.json` 两处 bundleName；
- `agent_config.json` bundleName；
- base / en_US 的 `EntryAbility_label` 与 `BackgroundAbility_label`。

release HAP 已成功打包到 `SignHap` 之前。签名配置已指向：

- p12：`~/data/AGC-operations/release-signing/dshm.p12`
- cer：`~/data/release/release1012/dshm.cer`
- p12 最终改用 `~/data/release/release1012/dshm.p12`（与 AGC-operations 同 sha256）
- profile：`~/Download/com.huawei.hmos.browser/DSHMpcRelease.p7b`
- alias：`ohosdshm`

发布 p12 口令取自父级备份备注；签名已成功：

| 项 | 值 |
|---|---|
| 文件 | `dist/release-test/DSHM-1.1.4-PC-dshclient-release-signed.hap` |
| 大小 | `439395539` B |
| SHA-256 | `25aeb404ca613700bc5f6a4c0dc57f6fe32ab3b1ce0edb190a8dba93884f553f` |
| verify-app | `success` |
| Profile | `release / com.dshm.dshclient` |

完整 `hvigorw assembleApp -p buildMode=release` 也已通过：

| 项 | 值 |
|---|---|
| 正式 APP | `build/outputs/default/DSHM-deveco-workspace-default-signed.app` |
| 大小 | `437139634` B |
| SHA-256 | `c2d3fdb247cfd13262ed7a8e5e0fa0bdc90da5ab893ef59f67def17bd6da570c` |
| verify-app | `success` |

签名物料已收进工程 `.certs/release1012/`（gitignored），并补齐 DevEco
解密所需的同级 `material/`；加密口令由 `encrypt-pwd` 生成后写入本地
`build-profile.json5`，明文未落盘。

另外，`DSHMpcRelease.p7b` 是 release Profile，即使使用对应发布私钥签名，
按既有真机规则它仍不能 `hdc install`；装机测试最终应使用同为
`com.dshm.dshclient` 的 **debug Profile + debug p12** 签出的
release-buildMode HAP。

实测 release 件直接 `hdc install -r` 被系统拒绝：

```text
code:9568322 signature verification failed due to not trusted app source
```

这不是包体错误，也不需要卸载。日常运行不使用 release `.app`，而是在
DevEco Studio 中对 `entry:default` 点击 Run，由 IDE 使用 debug 构建和设备绑定签名。

Windows 原开发端的正式调试身份已同步到 `signing/debug-dshm-official/`；
p12 / cer / keyAlias / 口令和 `material/` 均已在本机校验。该目录随附的 mobile
`.p7b` 只作参考，不能用于 PC。正式 PC debug Profile 由当前 DevEco Studio 的自动签名
生成，或一次性从 AGC 补绑当前设备 UDID；之后跨版本复用，不再依赖原开发端。

完整 Run 交接步骤见 `docs/216-DevEco-Studio正式调试签名交接（解除原开发端依赖）.md`。

## 7. 回归与清理结果

release 构建、APP/HAP `verify-app`、PC 权限面、PC-only、App ID、签名 Profile、
插件开关、VM 后备、文档、功能接线、PTC/fetch/worker 垫片和核心补丁门禁均已通过。

清理策略：

- 保留 `.certs/`、`signing/`、`dist/node/libnode.so.137.orig` 与
  `dist/release-test/`；
- 删除 `.hvigor/`、`entry/build/`、根 `build/`、`dist/core/work/`、
  `dist/localtest/`、`dist/logs/`、`dist/arkts-entry/` 等可再生产物；
- 删除已失效的 beta build-profile 模板和双工程 parity 门禁；
- 保留平板 / API 23 / guest VM 后备门禁，因为它们仍服务 PC 工程中的 tablet。

最终交付见 `dist/release-test/README.md` 与 `SHA256SUMS.txt`。

设备 `MNTXM-24B / 2in1 / 20DB409A…` 已在线。无论后续选哪条路，安装必须使用
`hdc install -r`，不得卸载或触碰 el2 数据。


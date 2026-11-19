# 141 · 发布签名链路（AGC 发布证书 + 发布 profile）与发布 profile 的 ACL 面

> ⚠️ **左列 App ID `6918740027110769940` 为历史错值**：唯一正式 AGC App ID 为 `6917614360926110054`（见 `APPID-CHANGE.md`、`docs/212`）。

日期：2026-10-10 晚
物料：`D:\desktop\release\`（仓库外备份 `D:\DSHM-signing-backup\release-20261010\`）
产物：`dist/release-test/DSHM-1.1.0-core0.2.1-alpha.2+dshm.31-arm64-release-signed.hap`

## 1 物料（实读，不是转述）

| 文件 | 读到的 |
|---|---|
| `dshm.p12` | 密钥库，别名 **`ohosdshm`**（`keytool -list -keystore dshm.p12` 实读；口令见同目录备注文件）。<br>⚠️ 2026-10-14 订正：此前这里写成 `ohosdsh`，那是**错的** —— `sign-release-hap.ps1` 的 `-KeyAlias` 默认值也跟着错，不给参数直接跑必然 `11014001 / sign-app failed`（docs/153 记过现场）；两处默认值已一并改成 `ohosdshm`。 |
| `dshm.csr` | 证书请求（就是上传给 AGC 那一件） |
| `dshm.cer` | 发布证书（AGC → 证书、APP ID 和 Profile → 证书管理 → 新增证书 → 类型=**发布证书**） |
| `dshmRelease.p7b` | 发布 profile：`"type":"release"`、`bundle-name com.dshm.dshclient`、`apl normal` / `app-feature hos_normal_app`、`app-identifier 6917614360926110054`、**无 `debug-info`**（不绑 UDID）、`validity 1791627890→1886322290`（约 3 年）、`issuer app_gallery` |

**与调试 profile 的逐行差异**

| 项 | 调试 profile（`~/.ohos/config/default_desktop.ohos.arm64_kUlaw….p7b`） | 发布 profile（`dshmRelease.p7b`） |
|---|---|---|
| `type` | `debug` | `release` |
| `debug-info.device-ids` | 4 个 UDID | **无** |
| `acls.allowed-acls` | 5 条：全盘访问权限 / 域权限 / `ALLOW_EXTERNAL_NATIVE_CODE` / `FILE_ACCESS_PERSIST` / 用户文件读写权限 | **2 条**：`ALLOW_EXTERNAL_NATIVE_CODE` / `FILE_ACCESS_PERSIST` |
| `app-identifier` | 6918740027110769940 | 6917614360926110054 |

⇒ **发布档拿不到那 3 条受限权限**。而 `docs/108` §① 早就量过：用户目录 node 侧的门是 **profile 的 `allowed-acls`**（不是"`system_basic` 申请不了"）。
⇒ 发布包在"**工作区之外**的用户目录"上没有权限（picker + `FILE_ACCESS_PERSIST` 认领过的目录仍在）。功能降级，自洽。

## 2 为什么不能让 hvigor 直接签

把发布物料照 `signingConfigs` 的格式写进 `build-profile.json5` 后，`hvigorw assembleHap … -p buildMode=release` 在 `SignHap` 判红：

```
00303116 Configuration Error
The length of the storePassword or keyPassword field in the signature configuration is less than 32.
```

即 **hvigor 只接受 DevEco 加密形态的口令**（调试那套是 `0000001B…` 共 72 字符），明文短串被长度判据直接拦下。两条出路：

- **A（本档采用，已落地）**：绕开 hvigor 的 `SignHap`，用 DevEco 自己用的签名器
  `sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar`，对 **未签名** 产物做 `sign-app -mode localSign`，口令明文从参数/备注文件读 ⇒ **不需要 GUI**。
  落成 `tools/sign-release-hap.ps1`：自带复验（`verify-app`）+ 从导出的 profile 读 `type`/`allowed-acls`，`type != release` 直接判红退出。
- B：在 DevEco「签名配置」里 Apply 一次，让 IDE 把口令改写成加密形态；之后 hvigor 也能出发布包。代价是要走 GUI，且 IDE 会重写 `build-profile.json5`。

## 3 产物与判据

`dist/release-test/DSHM-1.1.0-core0.2.1-alpha.2+dshm.31-arm64-release-signed.hap`
= **398,452,827 B** / sha256 `66132e8521a12067024bc5c536059ae4488c43d066c95c9daa462dd501b4759c`

判据（`verify-app` 原文）：`Digest verify result: true` / `verify: Verify success` / `verify-app success`；
内嵌 profile：`type=release`、`allowed-acls=ALLOW_EXTERNAL_NATIVE_CODE,FILE_ACCESS_PERSIST`、`uuid=9e469e60-a4a8-4919-b181-82760b3abbe0`。

> 每次 `sign-app` 的签名块带签名时间 ⇒ **同一份 unsigned 重签得到的 sha256 不同**；本档记的是上面这一份（`tools/sign-release-hap.ps1 -OutFile …` 重出即可，别拿哈希当等价判据）。

## 4 未做 / 待拍板

- **未装机**：发布签名与调试签名**互斥** —— 设备上已装调试签名的同包名应用时 `install -r` 必失败，只能卸载，
  而卸载会清 el2 用户数据（`AGENTS.md` 那条不可逆）。⇒ 本地验证只能在**测试机**上做，本档没做。
- **未申请**那 3 条受限权限：要去 AGC 走 ACL 申请，批准后**重新生成发布 profile**（拿到新 `.p7b` 重签一次即可，命令已备）。
- **未抬** `targetSdkVersion`：仍是 `6.1.1(24)`（`docs/110` 的拍板未动）。
- **未验证**：AGC 上传时会不会因"`module.json5` 声明了 profile 未授权的 3 条 ACL"被判不匹配（没实测过）。
  若被拒，二选一：① 去申请那 3 条 ACL；② 把 `module.json5` 里那 3 条去掉重编（功能按 §1 的降级口径）。

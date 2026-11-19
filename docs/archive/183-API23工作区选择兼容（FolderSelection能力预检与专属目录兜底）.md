# 183 · API 23 工作区选择兼容（FolderSelection 能力预检与专属目录兜底）

> 2026-10-17。用户反馈：6.1.0 设备点击「选择工作区」会提示
> “功能暂不支持，敬请期待”，希望向下兼容到 HarmonyOS 6.1.0 / API 23。

## 1. 结论

**API 23 可以安装和运行，但 6.1.0 手机/平板没有系统文件夹选择能力。**
这不是按钮漏接线，也不是单纯的最低版本号问题。

本机 API 26 SDK 的 `syscap-version.json` 实读：

| 设备形态 | `SystemCapability.FileManagement.UserFileService.FolderSelection` 起始 API |
|---|---:|
| 2in1 | 13 |
| phone | 26.0.0 |
| tablet | 26.0.0 |

因此同一个 API 23 包：

- 2in1 可以继续调用 `DocumentViewPicker` + `DocumentSelectMode.FOLDER`；
- phone / tablet 的 `FolderSelection` 能力不存在，系统无法授予“任意用户目录”；
- 改 `compatibleSdkVersion` 只能让包装得上，**不能让 API 23 手持档凭空长出目录选择授权**。

本包权限面仍恒 8 条，没有为这个问题新增任何权限，也没有恢复已永久删除的受限条目。

## 2. 根因

旧实现有两个问题：

1. `compatibleSdkVersion = 6.1.1(24)`，API 23 设备在安装门槛上就被挡住；
2. `pickFolder()` 和 Web 目录桥都无条件调用 `DocumentSelectMode.FOLDER`，
   没有先查 `FolderSelection` 系统能力。

在 API 23 手持档上，第二条会落到系统的不支持分支。用户看到的是系统提示，
应用此前没有可用兜底。

## 3. 修法

### 3.1 兼容面下探

`build-profile.json5` 与 `tools/build-profile.template.json5`：

```text
compatibleSdkVersion = 6.1.0(23)
targetSdkVersion     = 26.0.0
```

产物实读：

```text
minAPIVersion     = 60100023
targetAPIVersion  = 260000026
compileSdkVersion = 26.0.0.105
```

### 3.2 能力预检

`platform/.../FilePicker.ets` 新增：

```text
FOLDER_SELECTION_SYSCAP =
  SystemCapability.FileManagement.UserFileService.FolderSelection

folderSelectionAvailable()
  → canIUse(FOLDER_SELECTION_SYSCAP)
```

判断的是**设备当前能力**，不是只看 API 数字，也不是只看 `phone/tablet/2in1` 形态。

### 3.3 API 23 手持档兜底

能力缺失时，不拉起必然失败的 FOLDER 选择器，改走官方
`DocumentPickerMode.DOWNLOAD` 建立：

```text
~/Download/<bundleName>
```

这条路径：

- 不需要新增权限；
- 在文件管理器中可见；
- 官方口径具备持久访问能力；
- 宿主 Node / agent 可以正常读写；
- 应用重启后仍可作为工作区使用。

壳层会让 H5 正常拿到该路径并建立工作区，同时通过既有
`EVENT_PICKER_SUBSTITUTED` 提示用户“已改用专属下载目录”。

2in1 和 API 26 手机/平板仍走原来的任意目录选择，行为不变。

## 4. 能力边界

API 23 手机/平板**不能选择任意用户目录**。这是平台能力缺失，不是本应用可以靠代码
绕过的限制；在不新增权限、不伪造 URI 授权的前提下，`Download/<包名>` 是真实可用的
最小完整方案。

“选择工作区”按钮仍可用，但用户得到的是本应用专属工作区，不是任意目录。

## 5. 门禁

新增 `tools/check-picker-api23.mjs`，主跑钉住：

- 本地与模板最低版本均为 `6.1.0(23)`；
- `FolderSelection` 能力预检存在；
- `platform` 正确导出判据；
- Web 目录桥与 ArkTS `pickFolder()` 都有专属目录兜底。

`--self-test` 三条对照臂：

1. 兼容面退回 API 24；
2. 删除 `canIUse` 预检；
3. 删除 H5 目录桥兜底。

三条都必须判红。门禁主跑与自检均已接入 CI。

## 6. 本轮验证

| 项 | 读数 |
|---|---|
| 编译 | `BUILD SUCCESSFUL` |
| HAP | `entry-default-signed.hap`，440,516,052 B / sha256 `A3391265E2D946423913444A360CD11BB2DCB99E26305804D2B4C67919424EF2` |
| 包内最低版本 | `60100023` |
| 包内目标版本 | `260000026` |
| 权限面 | 8 条，逐条未变 |
| 覆盖安装 | `hdc install -r` 成功 |
| PC 启动 | 解锁后 `aa start` 成功，pid 2930；`dsh/home` 指纹 `links=10 size=3440` 不变 |
| 手机覆盖升级 | `1.1.3 / API 24` → `1.1.4 / minAPI 23`；`dsh/home` `links=10 → 11`，核心 `.56 → .69` |
| 手机启动 | 冷启动成功，pid 2549；端侧判据通过 |
| API 26 正常目录路径 | 系统目录选择器打开并选中 `harness`；`diag-select-returned count=1` |
| 目录授权 | `登记=ok persist=ok check=[true]` |
| 手机冷重启 | 新 pid 5753；`restore 1/1 已启用：~/Download/harness=ok` |

API 23 手持档仍需要一台 6.1.0 真机确认
`canIUse=false` 时专属目录路径能建立工作区。

## 7. 改动文件

- `build-profile.json5`
- `tools/build-profile.template.json5`
- `platform/src/main/ets/system/FilePicker.ets`
- `platform/src/main/ets/Index.ets`
- `entry/src/main/ets/pages/WebApp.ets`
- `tools/check-picker-api23.mjs`
- `.github/workflows/gates.yml`
- `docs/README.md`

**未 commit / 未 push。**

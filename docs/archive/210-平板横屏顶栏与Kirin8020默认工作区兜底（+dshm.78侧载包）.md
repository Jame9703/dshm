# 210 · 平板横屏顶栏与 Kirin 8020 默认工作区兜底

> 日期：2026-10-20
> 基线：Beta `1.1.4 / 1010004`，核心 `0.2.1-rc.2+dshm.78`
> 范围：ArkTS 壳层与文件选择器；核心版本不变

## 1. 用户确认的问题

1. 1.1.3 的平板 APP 顶栏在自由窗口里能拖动，但右上角三键会压住 Web 右侧栏按钮。
2. 当前 Beta 为规避重叠，把手机和平板顶栏全部拿掉；结果平板非全屏时没有可拖动区域。
3. Kirin 8020 手机实测无法选择工作区。应用直接进入默认工作区，但没有形成一条对所有
   非取消选择器错误都成立的兜底规则。
4. MatePad Edge / QXS-* 已永久识别为 desktop，但系统原始设备类型仍可能是 tablet；
   顶栏策略不能只看归一后的 form，也不能把所有 desktopForced 都当成普通 PC。

## 2. 顶栏策略

唯一裁决函数：

```ts
function shouldShowAppTopBar(rawType: string, desktopForced: boolean, landscape: boolean): boolean
```

| 设备/模式 | 竖屏/竖窗口 | 横屏 |
|---|---:|---:|
| 手机 | 不显示 | 不显示 |
| 普通平板 | 不显示 | 显示 |
| PC / 2in1 | 显示 | 显示 |
| MatePad Edge / QXS-* 强制 desktop | 不显示 | 显示 |

实现细节：

- 首帧横竖屏从 `readDeviceFacts().screenWidthVp/screenHeightVp` 初始化；
- Web 实际面积变化后按 `width > height` 更新；
- 软键盘展示期间不把键盘压缩后的高度当成旋转结论；
- `diag-decor-top` 增加
  `show/rawType/desktopForced/landscape/w/h/inset/source`，真机一行即可定位分支。

### 2.1 24vp 让位互斥

顶栏显示时，Web 不再额外下移 24vp；顶栏隐藏且系统三键存在时才保留原让位：

```ts
function decorTopInsetVp(
  handheld: boolean, decorPresent: boolean, appTopBarVisible: boolean): number
```

- `appTopBarVisible=true` ⇒ inset 0，避免顶栏与 24vp 双重占位；
- 平板竖屏顶栏隐藏 ⇒ 保持 24vp，继续避开右上角三键；
- PC / 2in1 ⇒ 恒 0；
- 全屏无三键 ⇒ 0。

## 3. Kirin 8020 工作区兜底

能力预检在部分 ROM 上会先返回真，随后 `DocumentViewPicker.select()` 才返回 801、202
或厂商自定义错误。现在统一使用：

```ts
export function shouldAutoFallbackFolderPicker(code: number, handheld: boolean): boolean {
  return handheld && !isFolderPickerCancelCode(code);
}
```

行为：

- 用户主动取消：保持 `CANCELLED`，不启动默认工作区；
- 手持档任意其它选择器错误：直接复用 `Download/<bundle>`；
- 能力预检缺失：同样直接复用 `Download/<bundle>`；
- 成功兜底时 `reason=''`，不发 `EVENT_PICKER_SUBSTITUTED`，不打开目录浮层，
  不要求用户再做一次选择；
- 只有默认工作区本身也建立失败时，才把真实失败原因回传。

对应诊断：

- `diag-picker-capability-fallback`
- `diag-picker-auto-fallback`
- `diag-picker-auto-fallback-failed`

## 4. 实现点

| 文件 | 变化 |
|---|---|
| `entry/src/main/ets/pages/WebApp.ets` | 三端顶栏纯函数、横竖屏状态、Web 面积更新、诊断字段、`resolvePublicWorkspace()` |
| `platform/src/main/ets/system/FilePicker.ets` | 取消码判据、非取消错误自动兜底、默认工作区静默返回 |
| `platform/src/main/ets/Index.ets` | 导出文件选择器判据 |
| `tools/check-decor-button-mode.mjs` | 三端策略、横竖屏、24vp 互斥与 A-Q 对照臂 |
| `tools/check-picker-api23.mjs` | 非取消异常兜底、静默工作区、6 条变异自检 |
| `tools/check-meeting-mode.mjs` | 同步 `backgroundModes` 现有三项能力，保留 M4 反控 |

DevEco 用户目录 skill 已通过仓库自带 `tools/sync-deveco-skills.mjs` 同步：
5 个 skill / 135 个文件，`--check` 为 0 pending。实现按
`arkts-grammar-standards`、`arkts-runtime-fix`、`arkts-error-fixes` 的静态类型约束落地。

## 5. 验证

离线门禁：

- `check-decor-button-mode`：第一组 9/0，第二组 95/0，A-Q 对照臂全部有效；
- `check-picker-api23`：正例通过，自检 6/6 变异均判红；
- `check-feature-wiring`：152 个文件、24 个功能接线通过；
- `check-memory-guard`：`TASK_KEEPING` 正例与 M1-M10 通过；
- `check-edge-desktop-policy`：Edge/QXS 永久 desktop、native-terminal-only 通过；
- `check-vm-memory-tier`：12G economy / 16G+ performance 通过；
- `check-permission-surface` 与 `--self-test`：恒 8 条；
- `check-no-apk-surface` 与 `--self-test`：包内 0 APK；
- `check-arkts-entry`：entry ArkTS 0 error；
- release `assembleHap`：BUILD SUCCESSFUL。
- `.github/workflows/gates.yml` 全量 58/58 PASS。

包体：

| 项 | 值 |
|---|---|
| HAP | `dist/sideload/DSHM-beta-1.1.4-core0.2.1-rc.2+dshm.78-tablet-topbar-picker-arm64-signed.hap` |
| 大小 | `439,481,607 B` |
| SHA256 | `3AE5A6B042BEB5E05F6F52F80C44693E26CED09DB6BFF2E146EF1DFC6F5B6FC3` |
| 签名 | DevEco beta 调试签名，`verify-app success`，profile `type=debug` |
| Bundle | `com.dshm.dshmbeta` |
| 版本 | `1.1.4 (1010004)` |
| API | min `60100023`，target `260000026` |
| HAP 条目 | 147 |
| 权限 | 8 条 |
| APK 条目 | 0 |
| 后台能力 | `dataTransfer / audioRecording / taskKeeping` |

## 6. 真机验收状态

出包时 `hdc list targets` 为 `[Empty]`，本轮没有可安装设备。需要内测组首轮验证：

1. 平板横屏显示顶栏、竖屏隐藏顶栏，旋转两次状态跟随；
2. 横屏顶栏可见时不出现额外 24vp 空白，右上角三键与 Web 按钮不重叠；
3. PC / 2in1 任意窗口比例顶栏始终显示；
4. MatePad Edge 在 PC 和平板模式间切换时，设备身份保持 desktop；
5. Kirin 8020 手机点选择工作区后直接进入默认 `Download/com.dshm.dshmbeta`，
   不出现需要用户操作的二次目录浮层；
6. 回传 `diag-decor-top`、`diag-picker-*`、`dshm-host.log` 与录屏。

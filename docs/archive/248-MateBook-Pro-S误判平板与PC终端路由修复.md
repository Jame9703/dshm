# 248 · MateBook Pro S 误判平板与 PC 终端路由修复

> 日期：2026-10-24
>
> 应用：`1.1.6 / 1010007`
>
> 核心：`0.2.1-rc.3+dshm.93`

## 1. 最新日志

检查最新设备日志：

```text
~/Download/com.huawei.hmos.browser/2026-10-24 19_22_01.log
```

该日志包含 DSHM 的 ArkWeb、窗口和系统侧记录，但没有保留 `DshWebApp` /
`DSHM-NodeRuntime` 的设备事实行。系统侧已经出现 `SCBPcScenePanelManager`，
说明窗口环境是 PC；问题集中在应用自己的设备事实归一化。

## 2. 根因

`DeviceFacts` 此前只强制识别：

- `QXS-*` / `MatePad Edge`；
- `MatePad Pro Max`。

MateBook 产品族没有被包括。只要 MateBook Pro S 的系统原始 `deviceType`
上报为 `tablet` 或 `default`，`formOf()` 就会得到 tablet/unknown，进而：

- `isHandheldForm()` 返回真，Web 走平板布局；
- `platformForm()` 不返回 `desktop`，不挂 `dshm-pc`；
- `nativeTerminalOnly=false`，终端尝试 guest VM 路线；
- 该产品实际是 PC，guest VM 终端不可用，用户看到“终端不可用”。

## 3. 修复

`platform/src/main/ets/system/DeviceFacts.ets` 的 PC 产品族判据增加：

```ts
market.toLowerCase().indexOf('matebook') >= 0
```

因此 MateBook / MateBook Pro S 无论系统原始类型如何上报，都统一得到：

```text
form=desktop
desktopForced=true
nativeTerminalOnly=true
```

同一设备事实会同时驱动：

- `platformForm=desktop`；
- `dshm-pc` 和常驻 PC 顶栏；
- 左侧栏默认展开；
- Host 原生终端路线；
- guest VM 显式关闭。

## 4. 最终布局规则

| 设备 | 顶栏 | 左侧栏 |
|---|---|---|
| PC / MateBook / 2in1 / Edge / Pro Max | 原生 PC 顶栏常驻 | 默认常驻 |
| 平板横屏、折叠屏展开横屏 | 不画原生 PC 顶栏 | 默认常驻 |
| 平板竖屏、折叠屏展开竖屏 | 不画原生 PC 顶栏 | 默认收起，只留入口按钮 |
| 直板手机、折叠单屏 | 无 | 左右栏收起，通过按钮覆盖打开 |

平板竖屏只在进入竖屏时自动收起一次；用户手动打开后不会被巡检反复关闭。

## 5. 产物

AGC 正式签名 release：

```text
dist/release-test/DSHM-1.1.6-1010007-core93-matebook-pc-sidebar-r6-release-20261024.app
size    460,638,243 B
sha256  c8d43b0c019b5fb7b6fb48335e44561f64b764c575630247843ce3aa6a3c1331
```

DSHM Beta 合包：

```text
dist/beta/DSHM-beta-1.1.6-1010007-core93-matebook-pc-sidebar-r6-combined/
  DSHM-beta-1.1.6-1010007-combined-debug.app
size    465,953,851 B
sha256  a44f1c083018b0b67d1a1b8c7608f9729f89cc7c11375e744a8d84d08076b5ec
```

两个 `.app` 均通过 `hap-sign-tool verify-app`。完整 ArkTS release/Beta
构建成功，侧栏、PC 路由、权限面、API 和多 HAP 结构门禁通过。

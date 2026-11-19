# 207 · MatePad Edge 系列永久 desktop 与 1.1.4 回归出包（核心 `+dshm.77`）

> 用户裁决（2026-10-19）：`QXS-* / MatePad Edge` 这个系列全部**永久识别成
> `desktop`**；同一台设备不再在 PC 原生终端和平板 guest 终端两条路线之间切换。

## 1. 问题边界

现场补充确认：

- MatePad Edge 在 PC 模式下有系统原生终端；
- 平板模式下没有同一条原生终端；
- 同一份应用此前会随窗口形态在 `tablet` / `desktop` 之间切换，导致终端路线也切换。

这不是继续调 QEMU 参数能解决的问题。产品口径改成**设备系列决定形态**：

- `productModel` 以 `QXS-` 开头；
- 或市场名包含 `MatePad Edge`；
- ⇒ 不管当前窗口是全屏、自由窗口、最大化还是分屏，应用内都答 `desktop`。

## 2. 实现

### 2.1 ArkTS 设备事实

`platform/src/main/ets/system/DeviceFacts.ets` 新增：

- `productModel` 实读；
- `isEdgePcSeries(productModel, marketName)` 纯判据；
- `desktopForced` / `nativeTerminalOnly`；
- 命中系列时 `form = FormFactor.DESKTOP`。

因此 `isHandheldForm()`、`platformForm()`、`DSHM_DEVICE_FORM` 和所有 PC/2in1 专属路径
都会稳定得到 `desktop`，不再受窗口状态影响。

### 2.2 ArkTS → Host 契约

`RuntimePort.buildHostEnv()` 新增：

```text
DSHM_DEVICE_MODEL=QXS-W20
DSHM_NATIVE_TERMINAL_ONLY=1
```

普通设备仍写 `DSHM_NATIVE_TERMINAL_ONLY=0`。

### 2.3 Host 终端路线

`hostcore/plugins/dshm-vm-bash/lib/index.js` 新增 `terminalTakeoverEnabled()`：

- Edge 系列：不接管 `spawnTerminal` / `terminalEnvironment` / `resolveExecutable`；
  侧边栏终端完整交回系统原生 PTY；
- 其他设备：保持原行为，guest 终端继续可用；
- `ctx.subprocess.spawn`（Agent 的 `bash` 工具）不受这条终端策略影响，需要 guest 时仍可用。

Host 日志会明确打印：

```text
[dshm-vm-bash] 不接管终端：PC 原生终端路线（DSHM_NATIVE_TERMINAL_ONLY=1）
```

## 3. 门禁

新增 `tools/check-edge-desktop-policy.mjs`，并接入 CI：

- QXS / MatePad Edge 系列识别；
- 强制 `desktop`；
- `productModel` / `nativeTerminalOnly` 传递；
- `terminalTakeoverEnabled()` 行为矩阵；
- native-only 时三个终端入口不再包装；
- 普通设备保持兼容。

本轮同时跑完 CI 工作流全部 Node 门禁与核心树门禁：

```text
SUMMARY pass=73 fail=0 total=73
```

覆盖 1.1.4 的主要新增/修复面：

- `docs/199` fs 负结果缓存；
- `docs/199` `Module.globalPaths` 收窄；
- `docs/200` Python worker 异步化；
- `docs/201` 手持档侧栏自愈；
- `docs/203` `libnode` io_uring 中性化；
- `docs/205` Web 单渲染进程、内存回调、Host 看门狗；
- 会议 AI、桌面卡片、浏览器自动关闭、外开桥、权限面、APK 面、核心补丁与入口可达性。

## 4. 产物

| 项 | 值 |
|---|---|
| HAP | `dist/sideload/DSHM-beta-1.1.4-core0.2.1-rc.2+dshm.77-arm64-signed.hap` |
| 应用版本 | `1.1.4 (1010004)` |
| Bundle | `com.dshm.dshmbeta` |
| 核心 | `0.2.1-rc.2+dshm.77` |
| 核心容器 | `dist/core/dsh-core-0.2.1-rc.2+dshm.77-openharmony-arm64.zip` |
| 核心容器 SHA256 | `1034bd02f76a334636c4413f57ea1159fa3d879f52652d9cada5030879db61ee` |
| HAP 大小 | `439,481,615 B` |
| HAP SHA256 | `AA4C2E20149EADD7757FFF9B0D54DBE0BAE62687C07F2AC3C3E4C6FD75033406` |
| 签名 | DevEco beta debug profile；`verify-app success` |
| 权限 | 恒 8 条 |
| APK 条目 | 0 |

## 5. 复测重点

1. PC 模式和全屏平板模式都必须显示桌面布局；
2. 两种模式打开侧边栏终端都必须走系统原生终端；
3. `dshm-host.log` 不应出现该系列设备的 `终端接管请求`；
4. Agent `bash` 工具仍按既有规则可用，不因关闭终端接管而失效；
5. 启动后 3 分钟系统无 PSI / LowMemoryKill，设备系统扫描进程不进入 16 GB 级 OOM；
6. 1.1.4 的会话、文件、插件、卡片、听写、会议、浏览器和侧栏回归按 `docs/206` 执行。


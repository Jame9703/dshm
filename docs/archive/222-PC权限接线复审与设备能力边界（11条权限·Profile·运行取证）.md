# PC 权限接线复审与设备能力边界

> ⚠️ **历史轮次读数（2026-10-22「11 条权限」当时口径，已作废，不得作为现行实施依据）**：
> 现行 **entry 18 / phone 9**，发布 Profile `allowed-acls` **8 条**（含 `ACCESS_USER_FULL_DISK`）。
> 现行口径见 `AGENTS.md` §4.3 与 `docs/405`。本文仅保留当时的接线与取证链。
>
> 日期：2026-10-22 ｜ 适用工程：PC-only `com.dshm.dshclient`

## 1. 结论

11 条权限的声明、发布 Profile 和消费点已重新核对。正式发布 Profile 的
`allowed-acls` 恰好是 `CUSTOM_SANDBOX / ALLOW_EXTERNAL_NATIVE_CODE /
FILE_ACCESS_PERSIST` 三条；两条 `kernel.*` 没有误写入 ACL。

设备上的权限状态为 10 条 `PERMISSION_GRANTED`，仅 `MICROPHONE` 为 `-1`：
它是 `user_grant`，首次真正录音时由系统弹窗授权，属于预期状态。

本轮发现并修复：

- `STORE_PERSISTENT_DATA` 已完成真实消费：`SecretStore` 设置
  `asset.Tag.IS_PERSISTENT = true`；SDK 实读为 normal / system_grant，
  旧文档所述“只对系统应用开放”已作废。
- 权限与 Profile 门禁新增 release ACL 精确集合检查、JIT 生产模式检查和
  `STORE_PERSISTENT_DATA` 消费点检查。
- 海泰浏览器截图改为 fail-fast。该浏览器内核的
  `tabs.captureVisibleTab` 会同步挂住；`Page.captureScreenshot` 只接受
  surface，而 surface 调用同样不返回。继续等待会把扩展 service worker
  一起拖死，因此现在约 115 ms 返回明确“不支持扩展截图”的原因；
  navigate / text / tree / click / type / network / tabs 不受影响。

## 2. Profile 与安装身份

| 项 | 本机 debug Profile | AGC release Profile |
|---|---|---|
| type | `debug` | `release` |
| bundle-name | `com.dshm.dshclient` | `com.dshm.dshclient` |
| app-identifier | `6918740027110769940`（仅本机 Run） | `6917614360926110054`（AGC 正式） |
| UDID | 包含当前 `20DB409A…` | 不适用 |
| allowed-acls | 现有本机调试材料 | 恰好 3 条正式 ACL |

已安装 HAP 内嵌 Profile 与 `build-profile.json5` 指向的 debug Profile
逐字节一致；HAP 由 `hap-sign-tool verify-app` 复验通过。

## 3. 11 条权限的消费与实测

| 权限 | 消费点 / 结论 |
|---|---|
| `INTERNET` | Host、WebView、模型与网络工具 |
| `GET_NETWORK_INFO` | PC 网络诊断能力保留；系统自动授权 |
| `KEEP_BACKGROUND_RUNNING` | KeepAlive 长时任务与 `taskKeeping` |
| `PREPARE_APP_TERMINATE` | EntryAbility / BackGroundAbility 真退出收尾 |
| `ALLOW_EXTERNAL_NATIVE_CODE` | HAP `libs/arm64` 原生件、Python/Node 原生绑定 |
| `FILE_ACCESS_PERSIST` | picker 目录授权持久化与跨启动恢复 |
| `CUSTOM_SANDBOX` | 已实测进入 `u:r:develop_tools_debug_hap:s0`，可执行随包/系统 ELF |
| `kernel.IGNORE_LIBRARY_VALIDATION` | 已授权；当前内核仍拒绝从应用 files 目录 dlopen 复制出的 `.so`，但 HAP libs 原生件正常 |
| `kernel.EXEMPT_ANONYMOUS_EXECUTABLE_MEMORY` | 已授权；当前内核 `mmap(RWX)` 与 `mprotect(RX)` 仍返回 `EINVAL` |
| `STORE_PERSISTENT_DATA` | `SecretStore` 的 Asset `IS_PERSISTENT` 标签 |
| `MICROPHONE` | WebView 授权、原生录音、会议模式；首次使用弹窗 |

两条 kernel 权限在 SDK 定义中确实是 normal / system_grant、
`provisionEnable=false`，不需要 AGC 审批；声明它们不会破坏 Profile。
但“授予”不等于当前内核真正放行上述内存/路径操作，因此不能据此解除 JIT
降级。

## 4. JIT 边界

`CUSTOM_SANDBOX` 已恢复原生 ELF 执行，因此 Python、git、rg、shell 和 PTY
可走主路。匿名可执行内存仍不可用：

```text
mmap(PROT_READ|PROT_WRITE|PROT_EXEC) -> EINVAL
mmap(PROT_READ|PROT_WRITE) + mprotect(PROT_READ|PROT_EXEC) -> EINVAL
```

V8 走 JIT 时会触发 native CHECK，所以 `NodeRuntime` 继续显式传
`buildHostArgv(..., true)`，生产 Host 保持 `--jitless`。这是设备安全策略
下的受控降级，不是权限声明遗漏。

## 5. 构建与真机回归

| 项 | 结果 |
|---|---|
| ArkTS / Native / PackageHap / SignHap | `BUILD SUCCESSFUL` |
| debug HAP | `entry-default-signed.hap` |
| debug HAP SHA-256 | `4e1f6feb806cdbd0f1e33758f9b2f828929b6af4a4e0125f0d3dbe3fb2387760` |
| `verify-app` | success |
| release APP | `dist/release-test/DSHM-1.1.4-PC-dshclient-release-signed.app` |
| release APP SHA-256 | `d11ae562d4e26d8aa8099f596ca3e83bcafd0ba1575d9f4aa6518cba99e6d907` |
| release HAP SHA-256 | `d2e61ffbf334e49f6bd06be6857fab5c6ff5272d040743de500dee7777be3b97` |
| 覆盖安装 | `hdc install -r` 成功，未卸载、未触碰 el2 |
| Host | 启动成功，Python bridge `ready/stdlib=true` |
| 对话闭环 | 带真实 workspaceId 的新会话返回 `pong`（+3144 ms，30 帧） |
| 原生执行域 | `u:r:develop_tools_debug_hap:s0`，subprocess rc=0 |
| 浏览器扩展 | `0.11.1 / dshm-host-bridge-12`，Host 重启后自动回连 |
| 浏览器导航 | example.com `load=complete` |
| 浏览器正文 | 911 字符，内容正确 |
| 浏览器截图 | 内核不支持，约 115 ms 明确失败且桥保持连接 |

## 6. 残余风险

1. `kernel.EXEMPT_ANONYMOUS_EXECUTABLE_MEMORY` 在本机内核上未产生实际
   可执行页放行效果；JIT 继续关闭。需要系统升级后才能受控复验。
2. `kernel.IGNORE_LIBRARY_VALIDATION` 没有解除 files 目录 `.so` 的加载限制；
   随包 HAP libs 路径仍正常。
3. 海泰扩展截图需要浏览器厂商修复 surface 截图或提供受支持的截屏 API；
   当前工具面保留 fail-fast 提示，不让失败拖垮桥。

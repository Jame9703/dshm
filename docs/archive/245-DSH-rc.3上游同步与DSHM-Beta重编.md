# 245 · DSH `0.2.1-rc.3` 上游同步与 DSHM Beta 重编

> 日期：2026-10-24
>
> 应用：`1.1.6 / 1010007`
>
> 核心：`0.2.1-rc.3+dshm.93`

用户已实测上一件 `.92` Beta：PC 与手机侧载均无问题。本轮只在该已验证
应用壳上同步 DSH 核心，不改变 beta 包名、权限面或设备入口结构。

## 1. 上游目标

`@deepseek-ai/dsh` 的 `latest` 仍为 `0.2.1-rc.2`，`next` 已更新到
`0.2.1-rc.3`。本轮按上游当前更新线同步到 `rc.3`。

自带插件的精确 dsh peer 同步改为 `0.2.1-rc.3`，避免上游兼容闸门把
`fs-write-nonchmod` 等插件整行停用。

## 2. 协议兼容

- rc.3 endpoint：144；
- 相对 rc.2：**零漂移**；
- 参数形状、wire 名、流式标记和可取消性逐条一致；
- `dshcompat/src/main/ets/Endpoints.ets` 已按 rc.3 重新生成；
- `CompatIndex.SUPPORTED_VERSIONS` 已加入 `0.2.1-rc.3`；
- `node tools/compat-drift.mjs`：无漂移。

## 3. 端侧补丁

核心树：`dist/core/work/dsh-core-0.2.1-rc.3+dshm.93/`

门禁结果：

- `check-core-openharmony-patches.mjs`：244 passed / 0 failed；
- `check-plugin-toggle.mjs`：PASS，自带插件 5/5 启用；
- `check-meeting-ai-plugin.mjs`：73 passed / 0 failed；
- `check-mobile-upgrade-migration.mjs --existing-beta-upgrade`：
  57 passed / 0 failed。

rc.3 的 fs-search 上游原文发生更新，`pack-core` 已按新原文重新注入
OpenHarmony 搜索降级分支，最终门禁通过。

## 4. 核心容器

```text
dist/core/dsh-core-0.2.1-rc.3+dshm.93-openharmony-arm64.zip
size    99,355,411 B
sha256  124fcdcc65c902130db0f2241d5d8f5c1650024f8fc474d0edd096bbd8064319
```

HSP 内同名容器与上件 SHA-256 完全一致；包含
`node-addon-system-linux-arm64` 平台包和 `musl/glibc system.node` 占位。

## 5. Beta APP

```text
dist/beta/DSHM-beta-1.1.6-1010007-core93-app-r2/
```

| 设备 | 文件 | 大小 | SHA-256 |
|---|---|---:|---|
| Edge / Pro Max | `DSHM-beta-1.1.6-1010007-pc-debug.app` | 442,384,353 B | `f941e0c367a6456574d0f767800e26691adc15f78fe5878030bd9cf0e0b6d396` |
| 手机 | `DSHM-beta-1.1.6-1010007-phone-debug.app` | 439,822,421 B | `24bd5eeb05b6c167f23c9e58e8e536a2aafa6ed6c8f4ab104af6dc6757fe6c7b` |

两个 APP：

- Bundle `com.dshm.dshmbeta`，可见名称 `DSHM Beta`；
- `versionName=1.1.6` / `versionCode=1010007`；
- 各自只有一个 entry；
- `hap-sign-tool verify-app` 均成功；
- HSP 均携带且只携带 `.93` 核心容器。

本批用于已安装同签名 beta 的覆盖升级；不用于全新安装。

### 5.1 合包完整测试 APP

```text
dist/beta/DSHM-beta-1.1.6-1010007-core93-combined/
  DSHM-beta-1.1.6-1010007-combined-debug.app
```

- 大小：`465,946,883 B`
- SHA-256：
  `6679c1480a682d2f213c2c15da38a4700ac128a7903fa930a7b37fd0486e4bc4`
- 包内：`entry-default.hap` + `phone-default.hap` + 一个 `hostruntime-default.hsp`
- 两个 HAP 均显示 `DSHM Beta`，APP/子包验签成功。

该合包用于 AGC/Hokit 完整设备面测试。本地 `hdc` 仍使用上面的单 entry APP。

## 6. 上架自检与 IM 唤端修复

华为上架自检（MatePad Pro / API 23）的 `TypeError: undefined is not callable`
已通过 sourcemap 精确映射到 `.enableDefaultContextMenu(true)`。该属性 since 24，
现改为 `AttributeModifier` 内同时检查 `sdkApiVersion >= 24` 和真实方法存在性；
API 23 不再调用。

`@michengai/dsh-im-connect` 在 jitless 下直接 `new WebSocket()` 时，全局惰性
WebSocket 现优先加载核心树的纯 JS `ws`，保留标准构造器与 `OPEN` 等常量；
只有 `ws` 不可加载时才回退到明确错误。主线程和插件 worker 共用同一垫片。

## 7. 尚未执行

构建时 `hdc list targets` 为空，因此未执行真机覆盖安装。用户侧载后应重点确认：

1. 启动后核心路径切到 `0.2.1-rc.3+dshm.93`；
2. 新会话不再报 `system.node` 或 shared library 缺失；
3. 原会话、工作区和插件仍在；
4. 插件安装/更新正常；
5. Edge、Pro Max 和手机布局与终端路线无回归。

## 8. 正式 AGC release 包

环境清理后重新执行正式 release 构建：

```text
dist/release-test/DSHM-1.1.6-1010007-core93-multihap-release-20261024.app
size    460,633,971 B
sha256  420543a101aadfc16df5097b4bc574532d52c7983782b7a863651ace14caf05b
```

包内实读：

- Bundle `com.dshm.dshclient`；
- App ID `6917614360926110054`；
- Profile `type=release`、7 条 allowed ACL；
- `entry`（tablet/2in1）、`phone`、共享 `hostruntime`；
- 两个 entry 均为 `buildMode=release / debug=false`；
- `hap-sign-tool verify-app` success；
- 核心 `0.2.1-rc.3+dshm.93`；
- 包含 API 23 右键菜单兼容与 jitless 全局 WebSocket `ws` 修复。

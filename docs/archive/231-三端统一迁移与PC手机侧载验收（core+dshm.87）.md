# 231 · 三端统一迁移与 PC / 手机侧载验收（core+dshm.87）

> 日期：2026-10-24
>
> 范围：`com.dshm.dshclient` 的 PC/2in1、手机、平板三个 entry HAP，
> 以及共享 `hostruntime` HSP。
>
> 状态：源码迁移、权限运行时接线、clean release/debug 构建、PC/手机覆盖安装
> 均已完成；平板仍待 AGC 云调试。

## 1. 当前结构

本工作区现在是三端统一交付入口：

| 模块 | 类型 | deviceTypes | 权限数 |
|---|---|---|---:|
| `entry` | entry | `2in1` | 16 |
| `phone` | entry | `phone` | 8 |
| `tablet` | entry | `tablet` | 12 |
| `hostruntime` | shared | `phone/tablet/2in1` | 0 |

`phone` 与 `tablet` 已迁入本仓并统一管理。两者 ETS 壳一致，差异只在
manifest、资源与设备形态；平板不再保留 PC `entry` 的整份页面副本。
独立目录 `~/data/DSHM-mobile` 仅作为历史备份保留，
当前构建不读取、不依赖它。未获明确授权前没有删除该外部目录。

公共 HSP 只保留一份核心、工具链、QEMU 库与 guest VM 资产。三个 entry HAP
不再各自复制核心或 VM。

## 2. 运行时权限与触感

- `READ_PASTEBOARD` 的 `requestPermissionsFromUser` 已接入 PC、手机和平板；
  授权成功后才读取剪贴板。
- `READ_WRITE_DOCUMENTS/DOWNLOAD/DESKTOP_DIRECTORY` 只在 PC/平板用户选中
  对应公共目录时按需申请；手机不申请三条不适用的目录权限。
- `VIBRATE` 已接入复制、粘贴和会议开始/结束三端路径；
  无振动能力时静默降级。
- 同一发布 Profile 覆盖三端全部 ACL，APK 条目仍为 0。

## 3. 共享运行时的分档

核心 `0.2.1-rc.2+dshm.87` 修正了统一后的一处分档回归：

- PC / 2in1 / MatePad Edge 的 `DSHM_NATIVE_TERMINAL_ONLY=1`；
- `dshm-vm-bash` 在该值为 1 时完全不接管 `subprocess.spawn`、
  `spawnTerminal`，也不安排静默预热；
- 手机 / 普通平板保持该值为 0，继续使用共享 HSP 中的 guest VM；
- `DSHM_VM_BASH=force` 仍只作为受控对照入口。

PC 运行日志实读：

```text
[dshm-vm-bash] 不接管：系统原生执行路线（DSHM_NATIVE_TERMINAL_ONLY=1）
exec 探测：python3.12=ok，git=ok，git-core/git=ok，git-remote-http=ok，
rg=ok，ash=ok，bash=ok，system-sh=ok，toybox=ok，git-ls-remote=ok
```

手机运行日志实读：

```text
[dshm-vm-bash] 已接管 ctx.subprocess.spawn
[dshm-vm-bash] QGA 就绪（+6099 ms）
[dshm-vm-bash] guest 侧已就绪：/bin/bash 可用
[dshm-vm-bash] 终端会话已建立（#1 /dev/hvc0，argv=/bin/sh -i）
```

## 4. 构建与交付

最终执行顺序：

1. `clean`
2. release `assembleApp`
3. debug `assembleApp`
4. release/debug `.app`、三端 HAP 与 HSP 全部 `verify-app`

| 项 | 值 |
|---|---|
| App | `com.dshm.dshclient` |
| AGC App ID | `6917614360926110054` |
| 版本 | `1.1.6 / 1010006` |
| 核心 | `0.2.1-rc.2+dshm.87` |
| 核心 zip | `99,345,800 B` |
| 核心 SHA-256 | `b3e0e74949c5b20d4f58c9e258cbdcc7cc3303b24bb6b7644c4d4b68c9f894f0` |
| release `.app` | `dist/release-test/DSHM-1.1.6-multihap-3platforms-20261024-r3.app` |
| release `.app` 大小 | `482,559,497 B` |
| release `.app` SHA-256 | `c34455b8b4664e6dfeab851209049f99b357ffceead16f208210665512f1449e` |

debug 侧载目录：

`dist/sideload/DSHM-1.1.6-multihap-3platforms-debug-20261024/`

目录内包含三端 HAP、共享 HSP、完整 debug `.app`、README 与 `SHA256SUMS`。

## 5. 侧载签名与设备

手机首次安装遇到 `9568423 device is unauthorized`，根因是旧 debug Profile
只绑定 PC。处理方式：

- 不删除旧 Profile；
- 在 AGC 新建 `DSHM-multihap-debug-pc-phone-20261024`
  （Profile id `2067959177023616000`）；
- 使用原 `xiaobai-debug` 证书；
- 设备列表同时包含 PC `20DB…7B7F` 与手机 `CA46…E60E`；
- 保留全部 7 条已批准 ACL；
- 旧 debug/release Profile 与 p7b 均保留。

新 debug Profile 路径：

`.certs/multihap-20261024/DSHM-multihap-debug-pc-phone-20261024.p7b`

SHA-256：

`46a8c7c8aa5d0951fdeca35c2bd1dcf33f86194f0cc2c3436b5707e99a711937`

## 6. 设备验收

### PC

| 项 | 读数 |
|---|---|
| 型号 / API | `MNTXM-24B` / `26` |
| 安装 | debug `1.1.6 / 1010006` |
| 模块 | `entry + hostruntime` |
| 核心 | `0.2.1-rc.2+dshm.87` |
| Host | `127.0.0.1:3120` 已监听 |
| 原生 exec | 10/10 |
| VM | PC 判据不接管；无 QEMU 预热门 |

安装命令为 `hdc -t 127.0.0.1:45595 install -r -p <目录>`，
返回 `install bundle successfully`。

### 手机

| 项 | 读数 |
|---|---|
| 型号 / API | `VYG-AL00` / `26` |
| 安装 | debug `1.1.6 / 1010006` |
| 模块 | `phone + hostruntime` |
| 核心 | `0.2.1-rc.2+dshm.87` |
| Host | `127.0.0.1:3120` 已监听 |
| guest VM | QGA / `/bin/bash` / 终端会话均成功 |

安装命令为 `hdc -t 62T0225B18039433 install -r -p <目录>`，
返回 `install bundle successfully`。

`com.dshm.mobileclient` 旧应用未卸载、未改动；本次只安装新的同 App
`com.dshm.dshclient`。

### 平板

release `.app` 已包含 `tablet` HAP，并由用户从 AGC 云调试验证。
本机没有平板 UDID，因此没有把平板加入当前 debug Profile。

## 7. 门禁

本轮通过：

- `check-permission-surface --self-test`
- `check-permission-surface`（16 / 12 / 8）
- `check-pc-only-surface --self-test`
- `check-pc-only-surface`
- `check-pc-api26 --self-test`
- `check-pc-api26`
- `check-edge-desktop-policy`
- `check-no-apk-surface`
- `check-store-readiness`
- `check-meeting-mode`
- `check-feature-wiring`
- `check-decor-button-mode`
- `check-handheld-back`
- `check-sidebar-shim-css`
- `check-resfile-core-zip`
- `assert-resfile-sync`

## 8. 尚未执行

- 平板上传 AGC 后的云调试；
- 三端人工完整功能回归；
- AGC 邀请测试正式提交与推送；
- 外部 `DSHM-mobile` 历史目录的最终归档/删除，必须另获用户明确授权。

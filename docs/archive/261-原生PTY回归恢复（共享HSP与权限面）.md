# 261 · PC / MatePad Edge / Pro Max 原生 PTY 回归恢复

> 日期：2026-10-25
>
> 版本：`1.1.6 / 1010007`
>
> 核心：`0.2.1-rc.3+dshm.96`

## 1. 现象与证据

PC、MatePad Edge、MatePad Pro Max 的侧栏终端都无法建立。旧构建仍能启动
Host，但宿主域是：

```text
u:r:debug_hap:s0
```

在同一域内 `/usr/bin/zsh`、`python3`、`rg`、`ash` 全部被系统拒绝，
`exec` 探测出现 `EPERM`，`pty-spawn` 无法完成 fork/exec。因而这不是
node-pty 或系统 PTY 本身损坏，而是设备事实、共享 HSP 和权限面同时被回退。

## 2. 根因

历史会话与 17:00 成功构建留下的编译缓存显示，工作区迁移时回退了四处：

1. `DeviceFacts` 只识别 `QXS-* / MatePad Edge`，普通 PC/2in1 与 Pro Max
   被当成 guest VM 档；`nativeTerminalOnly` 也只跟随 `desktopForced`。
2. `RuntimePort` 没有下发 `DSHM_VM_BASH=off`、`DSHM_DEVICE_FAMILY`、
   共享 HSP 原生库与资源目录。
3. HAP 仍引用本地旧 `NodeRuntime`，没有引用共享 `hostruntime` HSP；
   HSP 模块又被错误改回 `har`，APP 因此没有 `hostruntime-default.hsp`。
4. PC entry 权限面被回退成旧 8 条，缺少已获批的
   `CUSTOM_SANDBOX` 及桌面权限，宿主从 `develop_tools_debug_hap`
   降级到 `debug_hap`，原生终端链整体失效。

另外，`hostruntime` 的 oh-package 版本号一旦被写回 `1.0.0`，
entry 编译出的 normalized import 会带 `&1.0.0`，而 HSP 内的模块记录不带
该后缀，表现为：

```text
cannot find record '&hostruntime/Index&1.0.0'
```

因此共享 HSP 的 oh-package 版本字段保持空字符串，entry/HSP 两侧 OHM URL
必须逐字一致。

## 3. 修复

- `DeviceFacts` 恢复 PC / 2in1 / MateBook / Edge / Pro Max / QXS 产品族判据，
  `nativeTerminalOnly = form === DESKTOP`。
- `RuntimePort` 在桌面档同时下发 `DSHM_VM_BASH=off` 和
  `DSHM_BASH_EXECUTABLE=/usr/bin/zsh`，并传递设备型号族、HSP libs/resfile。
- VT 插件用 `nativeExecutionOnly()` 同时守住 `spawn` 与 `spawnTerminal`；
  任一桌面事实命中即完全不接管。
- `hostruntime` 恢复为 shared HSP，导出共享 `NodeRuntime`；entry、phone
  全部改从 HSP 构造宿主。
- PC entry 权限面恢复为 18 条，与现有 7 条 ACL Profile 对齐；
  `CUSTOM_SANDBOX` 不得再被当作“多余第 9 条”删除。
- 核心包、10 个自带插件与 `profiles/ondevice` 从 `.96` 成功构建快照恢复，
  `check-core-openharmony-patches` 为 `240 passed / 0 failed`。

## 4. 真机验收

先使用旧本机 debug Profile 做覆盖验证，确认原生执行链恢复；随后按用户明确
要求执行完整卸载重装。旧 Profile 不含 `ALLOW_EXTERNAL_NATIVE_CODE`，因此最终
改用工程当前 multihap debug Profile（App ID `6917614360926110054`，7 条 ACL）
重编并安装：

```text
hdc uninstall com.dshm.dshclient
hdc install -r hostruntime-default-signed.hsp
hdc install -r entry-default-signed.hap
```

覆盖验证阶段安装前后用户数据指纹一致：

```text
links=11 size=3440
```

冷启动后的宿主读数：

```text
domain = u:r:develop_tools_debug_hap:s0
python3.12=ok  git=ok  git-core/git=ok  git-remote-http=ok
rg=ok  ash=ok  bash=ok  system-sh=ok  toybox=ok
realShell=yes
[dshm-vm-bash] 不接管：DSHM_VM_BASH=off（显式关闭）
```

界面重新打开 `HiShell` 后 PTY 建立成功，命令在同一原生 shell 中正常执行。

最终按用户要求执行了一次完整卸载重装。重装后的冷启动读数：

```text
PID=14128
domain=u:r:develop_tools_debug_hap:s0
python 桥自检通过：print(1+1)=2（1304ms）
exec 探测：python3.12=ok，git=ok，git-core/git=ok，git-remote-http=ok，
           rg=ok，ash=ok，bash=ok，system-sh=ok，toybox=ok，git-ls-remote=ok
host-crash.log=0 B
```

新建终端使用会话工作区 `test`，界面显示 `zsh` 和
`localhost ~/test %` 提示符，PTY 可用。

## 5. 构建与门禁

完整 `assembleApp` 成功，产物包含：

```text
entry-default.hap          tablet, 2in1
phone-default.hap          phone
hostruntime-default.hsp    phone, tablet, 2in1
```

通过：

- `check-edge-desktop-policy.mjs`
- `check-vm-bash.mjs`：`373 / 373`
- `check-pc-only-surface.mjs`
- `check-memory-guard.mjs`
- `check-core-openharmony-patches.mjs`：`240 / 240`
- `check-permission-surface.mjs` 与 `--self-test`
- `check-resfile-core-zip.mjs`
- `assert-resfile-sync.mjs`
- `check-feature-wiring.mjs`
- `check-doc-refs.mjs`
- `check-native-closure.mjs --dir hostruntime/build/release/intermediates/libs/default/arm64-v8a`

最终 release APP：

```text
build/outputs/release/DSHM-deveco-workspace-release-signed.app
size    461,725,004 B
sha256  269c0a8daae3bfa28163c3ba0ff30a0abbebf6cb8827d3adac19de8b08ec4d1c
```

安全侧载包：

```text
dist/sideload/DSHM-1.1.6-1010007-core96-native-pty-repair.zip
size    670,590,170 B
sha256  ab2d188de5d752998e25d5a23e53307f0a08bcb7db2757cbdcfb6813a902bc4a
```


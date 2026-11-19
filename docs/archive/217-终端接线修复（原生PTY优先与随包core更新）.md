# 217 · 终端接线修复（原生 PTY 优先与随包 core 更新）

> 日期：2026-10-21 ｜ 工程：`com.dshm.dshclient` ｜ 设备：鸿蒙 PC `MNTXM-24B`

## 1. 现象

在 DevEco Studio 中运行 PC 工程后，侧边栏终端报错。ArkWeb 到 Host 的请求本身正常：

```text
POST /api/terminal/environment 200
POST /api/terminal/shells      200
POST /api/terminal/create      200
```

因此问题不在 ArkTS/ArkWeb 到 Host 的基础接线，而在终端后端选择。

## 2. 根因

设备实际加载的是随包 core 里的旧版 `@deepseek-ai/dshm-vm-bash`：

```text
已接管 ctx.subprocess.spawnTerminal
```

旧插件把 PC 终端改派到 guest VM。源码里虽然已经改成“原生 exec
探针成功就不接管”，但只改了 `hostcore/plugins/dshm-vm-bash/`，
没有同步替换 `entry/src/main/resources/resfile/` 中的 core zip，
所以 HAP 安装到设备后仍执行旧插件。

另有一个分档缺口：普通 `2in1` 的 `nativeTerminalOnly` 还是 `false`，
只有 MatePad Edge 系列为 `true`。

## 3. 修复

1. `dshm-vm-bash` 以宿主原生 exec 探针优先。`bin/pnpm --version`
   可执行时，`spawn` 与 `spawnTerminal` 都不接管，直接走宿主 PTY。
2. `DeviceFacts.nativeTerminalOnly` 改为 `form === FormFactor.DESKTOP`，
   覆盖所有 desktop / 2in1，而不只覆盖 MatePad Edge。
3. 将修正后的插件的
   `lib/index.js` 最小更新进随包 core zip，再重新构建 debug HAP。

core zip 保持现有 `0.2.1-rc.2+dshm.78` 路径；内置核心安装器按容器
字节大小指纹判断是否需要替换，因此本次启动会重新解包新树。

## 4. 验证

- `hvigorw assembleHap --mode module -p module=entry@default
  -p product=default -p buildMode=debug --no-daemon`：`BUILD SUCCESSFUL`
- HAP 内 core zip 与工作区 resfile 的 sha256 一致
- `hdc install -r`：覆盖安装成功，未卸载应用，el2 用户数据保留
- 新进程插件日志：

```text
[dshm-vm-bash] 不接管：宿主原生 exec 可用（CUSTOM_SANDBOX 已生效）
```

- 原生 exec 探测：`python3.12`、`git`、`rg`、`ash`、`bash`、
  `system-sh`、`toybox` 全部 `ok`
- 终端 RPC：

```text
terminal/environment  ok=true
terminal/shells       ok=true
terminal/create       ok=true, state=running
```

- shell 发现结果包含 `/bin/sh`、`/usr/bin/zsh` 和随包
  `.../files/bin/bash`
- 设备进程表中存在应用的直接子进程 `sh -i` / `bash -i`；
  本次终端测试没有出现 guest VM 接管日志

## 5. 产物

| 产物 | sha256 |
|---|---|
| `entry-default-signed.hap` | `3cc36549a7e543202141ca5a86cca47d1b6d0cc6306d6447153adc092abd7b76` |
| `dsh-core-0.2.1-rc.2+dshm.78-openharmony-arm64.zip` | `d765b00bd5856e33871341d1bf51e0a16949b43374592f0e8b634eb042bbba6e` |

该 HAP 是本地 debug 签名，用于 DevEco Run / 设备调试，不是 AGC
发布件。正式发布身份仍为 `6917614360926110054`。

# 240 · MatePad Edge 内存收口（ArkWeb 单渲染时序与原生 PTY 硬闸门）

> 日期：2026-10-24
>
> 版本：应用保持 `1.1.6 / 1010006`；核心升到
> `0.2.1-rc.2+dshm.91`；本地 debug 修订为 r8。
>
> 范围：MatePad Edge 上一版本的内存异常、ArkWeb 单渲染未生效、Edge/PC
> 误走 guest VM 的三重防线。

## 1. 日志结论

浏览器目录下的 2026-10-24 多份日志中，有七份出现同一条：

```text
SetRenderProcessMode: web engine is nullptr
```

这说明旧代码虽然在 `EntryAbility.onCreate()` 最前面调用了
`setRenderProcessMode(SINGLE)`，但当时 ArkWeb 内核尚未初始化，调用没有生效。
平板 / 2in1 / PC 默认又是多渲染子进程模式，所以 Edge 上仍可能出现多个
`:render`，与此前的内存压力方向一致。

07:49 日志里还可见渲染进程 `7475` 被 `KillRenderProcess`，随后应用 PID
`6582` 进入终止链；08:03 日志里可见进程 `31050`、渲染进程 `31944` 与大量
memmgr 记录。09:23 最新日志没有 `com.dshm.dshclient` 进程记录，不能用于证明
该日志时段发生了 DSHM OOM。

因此本轮不能把责任只归给显存或某一个系统服务。可从旧日志确定的代码缺陷是：

1. ArkWeb 单渲染设置时序错误，实际从未生效；
2. Edge 的原生终端路线还需要 Host 侧硬闸门，不能只依赖 ArkTS 型号判断；
3. 旧版本缺少“请求值 / 实际回读值”的应用侧持久诊断。

## 2. 修复

### 2.1 ArkWeb 先初始化、再设单渲染

`EntryAbility.onWindowStageCreate()` 在 `loadContent('pages/WebApp')` 之前执行：

```text
initializeWebEngine()
→ setRenderProcessMode(SINGLE)
→ getRenderProcessMode() 回读
```

这样既保证 ArkWeb 内核对象存在，又保证第一个 Web 组件创建前配置已经落定。
结果写入 `files/diag-mem`：

```text
web-render-mode=requested-single observed=0 ok=1 api=...
```

若回读不是 `SINGLE(0)`，同一行保留 `ok=0`，不再把“调用过”误报成“已生效”。

### 2.2 Edge / PC 明确关闭 guest VM

原生终端档现在同时写入两项：

```text
DSHM_NATIVE_TERMINAL_ONLY=1
DSHM_VM_BASH=off
```

Host 插件的判据再加一层：

- `DSHM_NATIVE_TERMINAL_ONLY=1`；
- `DSHM_DEVICE_FORM=desktop`；
- `DSHM_DEVICE_MODEL` 包含 `QXS-`。

任一命中都不接管 `spawn` / `spawnTerminal`，也不进入 VM 预热。这样即使某个
启动壳漏掉语义标记，Edge 的 `QXS-*` 型号仍会走系统原生 PTY。

## 3. 构建与校验

本轮实际执行：

```text
node tools/pack-core.mjs --skip-install --place-in-app
node "$DEVECO_HOME/hvigor/bin/hvigorw.js" assembleApp \
  --mode project -p product=default -p buildMode=debug --no-daemon
```

结果：

- hvigor：`BUILD SUCCESSFUL in 30 s 315 ms`；
- entry：`tablet,2in1`；
- phone：`phone`；
- hostruntime：`phone,tablet,2in1`；
- 三件均为 `1.1.6 / 1010006`、`buildMode=debug`、`debug=true`；
- APP / HAP / HSP 均通过 `hap-sign-tool verify-app`；
- 核心 zip 与 HSP 内 resfile 的 SHA-256 一致。

门禁通过：

```text
node tools/check-memory-guard.mjs
node tools/check-edge-desktop-policy.mjs
node tools/check-core-openharmony-patches.mjs
node tools/check-resfile-core-zip.mjs
node tools/assert-resfile-sync.mjs
node tools/check-plugin-toggle.mjs
```

## 4. r8 产物

多端 debug 目录：

```text
dist/sideload/DSHM-1.1.6-multihap-3platforms-debug-20261024-r8/
```

| 项 | SHA-256 |
|---|---|
| debug APP | `39616cc33e5532ebf674fd985344ae0a58c6d3e51962cb3d1f92b4463ca46389` |
| entry HAP | `4f87a7d4c31c09b77f2efd1420299ab39ed57fa530be33601c843136e93cc4fb` |
| phone HAP | `12165790b1f23970a5ab2f1ca0a907d1176764399dfa24559c93dc89718abe65` |
| hostruntime HSP | `c60cd9cfaba78bc6a69b76621839fd95928dfdafe7cfd68f14e9031069cdd5a8` |
| core zip | `85ca1c6fe600263d039274a29a6f7223c7d3bc61192366ab2ed336ccec0d590c` |

Edge / Hokit 两件包：

```text
dist/sideload/DSHM-1.1.6-Edge-Hokit-r8/
  DSHM-1.1.6-Edge-tablet-2in1-debug.hap
  DSHM-1.1.6-Edge-hostruntime.hsp
```

ZIP：

```text
dist/sideload/DSHM-1.1.6-Edge-Hokit-tablet-2in1-r8.zip
SHA-256 d5db8527769a768e3f05942a28551081c6752632ab6e5bf2707c5d94c87c82b9
```

本轮 HDC 在线设备列表为空，未执行覆盖安装；不得卸载或清除 Edge 的应用数据。

## 5. Edge 复验读数

覆盖安装 r8 后，冷启动并保持到此前容易复现内存问题的时间点，再回取：

```text
files/diag-mem
files/dshm-host.log
files/node-output.log
```

验收重点：

1. `diag-mem` 必须出现 `requested-single observed=0 ok=1`；
2. 进程列表只应有一个 DSHM 渲染子进程；
3. Host 日志只应出现
   `不接管：DSHM_VM_BASH=off（显式关闭）` 或原生执行路线，
   不应出现 `已接管 ctx.subprocess.spawn`、`VM 内存档位`、`静默预热开始`；
4. `diag-mem` 的 Host RSS 与系统 MemAvailable 不再持续逼近危险线；
5. 终端仍直接出现 `sh / zsh / bash` 并可秒开。


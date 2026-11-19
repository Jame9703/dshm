# 内测双日志复核与手持侧栏常驻（Beta 合包）

> 日期：2026-10-24
>
> 基线：`1.1.6 / 1010007 / 0.2.1-rc.3+dshm.93`

## 1. 结论

本轮只处理内测反馈中可直接归因到产品代码的两项，并保持正式包身份不变：

1. 平板左右侧栏入口同时常驻；手机/折叠单屏在右栏关闭时保持左侧入口，右栏打开时隐藏，
   避免覆盖式右栏与左上按钮重叠。
2. QXS 产品族同时按 `productModel` 与 `marketName` 识别，避免 `productModel` 读取为空时
   被误判为平板并让 `bash` 进入 guest VM 路线。

## 2. 两条日志的判读

### 2.1 会话中的 `.73` 路径不是当前运行核心

Zip 中的会话创建于 `20:46:27`，运行时上下文固定为 `.73`；该会话在 `21:06:22` 恢复时，
上游 `@deepseek-ai/dsh-harness-dev-context` 按设计**逐字保留会话首次写入的 runtime
context**，不会因随后换核而重写历史提示。MD 中 `21:03:32` 的新启动实际导入的是
`0.2.1-rc.3+dshm.93`。

因此不能用旧会话里的 `.73` 文本判断当前进程跑错核心。`.93` 核心同时包含
`@deepseek-ai/dsh-session-log-export` 包及 `session-log-download` Host 行；旧 `.73`
会话中的 `/api/session.export` 404 不代表 `.93` 仍缺这条路由。

### 2.2 QXS-W20 误走 guest VM

`DeviceFacts` 原先只在 `productModel.startsWith("QXS-")` 时强制 desktop。日志设备可能
只从市场名给出 `QXS-W20`，而 `productModel` 为空，导致 `nativeTerminalOnly=false`，
`bash` 随后撞上 `MemAvailable 1120 MiB < 1280 MiB`。

现改为 `productModel` 或 `marketName` 任一以 `QXS-` 开头都强制 desktop；Host 仍同时下发
`DSHM_NATIVE_TERMINAL_ONLY=1` 与 `DSHM_VM_BASH=off`。

日志中的浏览器扩展 `connected=0` 属于目标浏览器未加载/未启用扩展；`dsh-ops` 的
openharmony-arm64 原生 worker 缺失属于上游发布面限制。两者不在本轮假装修复。

## 3. 手持侧栏入口

`entry` 与 `phone` 的 `SIDEBAR_SHIM_JS` 默认规则为：

```css
html.dshm-handheld #dshm-sidebar-fab { display:flex !important; }
```

手机/折叠单屏另有一条更具体的例外：

```css
html.dshm-compact[data-dshm-right="open"] #dshm-sidebar-fab { display:none !important; }
```

普通平板不会挂 `dshm-compact`，因此右栏打开时左右入口仍同时显示。手持档隐藏侧栏列内的
官方重复按钮，只保留页面内 FAB；官方按钮仍在 DOM 中，继续作为状态读取源与程序化点击目标。
PC / 2in1 仍使用原生顶栏并隐藏 Web 重复入口。

## 4. 门禁与构建

通过：

- `check-handheld-sidebar-recover.mjs`：14 个变异全部判红。
- `check-sidebar-shim-css.mjs --self-test`：9 个变异全部判红。
- `check-edge-desktop-policy.mjs`
- `check-permission-surface.mjs --self-test`
- `check-pc-api26.mjs`
- `check-pc-only-surface.mjs`
- `assert-resfile-sync.mjs`
- `check-resfile-core-zip.mjs`

最终 Beta 合包：

- `dist/beta/DSHM-beta-1.1.6-1010007-core93-sidebar-scope-combined-b2/DSHM-beta-1.1.6-1010007-combined-debug.app`
- 大小：`465,955,478 B`
- SHA-256：`95b49c90b667ecba9fdafac55c124c4adcca10a5ebf3844325f2241b72f96ba9`
- 结构：`entry + phone + hostruntime`

## 5. 手机覆盖安装边界

在线手机现有 beta 的 `appIdentifier` 为 `6918745051729970584`，本轮 Profile 为
`6917619917870725140`；`hdc install -r -p` 被系统以 `9568332 install sign info
inconsistent` 拒绝。未执行卸载，安装前后核验 `phone.hap` 仍为 `1.1.6 / 1010007`，
`el2/.../dsh/home` 与 `dsh/cores` 均仍在。

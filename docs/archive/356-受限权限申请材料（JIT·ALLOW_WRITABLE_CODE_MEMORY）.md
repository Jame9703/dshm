# 356 · 受限权限申请材料：`ohos.permission.kernel.ALLOW_WRITABLE_CODE_MEMORY`

> 用途：向 AGC「上架与运营 / AppGallery Connect / 其他」提交受限权限申请时的**现成材料**。
> 应用：DSHM（`com.dshm.dshclient`），HarmonyOS PC / 2in1 / 平板。
> 本档按客服回复的三项要求组织：① 申请原因说明 ② 使用场景证明材料 ③ 上架时补充的权限说明 + 场景视频。

---

## 0. 一句话版本（填表单「申请原因」用，可整段粘）

```
DSHM 是运行在鸿蒙 PC / 2in1 上的本地 AI 编程工作台，应用内内置完整的 Node.js 运行时
（V8 引擎），用于执行用户在本机安装的 JS/TS 工具链（构建、脚本、插件）。当前因未获该权限，
**主宿主进程**只能以 --jitless 解释模式运行：同一台设备上的 Node 对照实测，纯计算负载
慢 5.5 倍（345ms vs 1902ms），且该进程内 WebAssembly 为 undefined —— 依赖 WASM 的组件
只能退回纯 JS 垫片（内置 fetch 已由垫片接管）。申请该权限仅用于让主宿主进程的 V8 正常
生成并执行 JIT 机器码，不采集、不上传任何用户数据。子进程 Node CLI 的边界见 §1.6。
```

---

## 1. 申请原因说明（详细版）

### 1.1 应用与内置引擎

| 项 | 内容 |
|---|---|
| 应用名 / 包名 | DSHM / `com.dshm.dshclient` |
| 设备形态 | 手机、平板、鸿蒙 PC / 2in1（含 MatePad Edge / MatePad Pro Max） |
| **内置引擎** | **Node.js 24.2.0 + V8 JavaScript 引擎**（随包 `libnode.so`，应用内进程加载） |
| 运行时形态 | 应用内以 ArkTS 宿主线程加载 libnode，起一个本地 HTTP 服务供 Web GUI 与工具调用 |
| 是否含其它虚拟机 | 否（不含 LuaJIT / CEF / Electron / 其它 JS 引擎） |

### 1.2 为什么需要 JIT

V8 的执行路径有两条：

1. **JIT**（默认）：把热点 JS 编译成 ARM64 机器码写入**可写可执行（W+X）匿名内存**并跳转执行；
2. **解释执行（`--jitless`）**：不生成机器码，逐条解释 —— **正是鸿蒙默认禁止 W+X 时的降级路径**。

`ohos.permission.kernel.ALLOW_WRITABLE_CODE_MEMORY` 的作用就是允许应用申请这块 W+X 匿名内存。
**它不是"额外能力"，而是让 V8 回到上游默认工作方式的前置条件。**

### 1.3 性能必要性（本机实测数据，可复现）

在鸿蒙 PC（20 核 / 24 GB）本机实测：

| 负载 | 有 JIT | `--jitless` | 差距 |
|---|---|---|---|
| 纯计算（2×10⁷ 次 `Math.sqrt` + 位运算） | **345 ms** | **1902 ms** | **慢 5.5×** |
| `WebAssembly` 可用性 | `object` | **`undefined`** | 功能缺失 |

复现命令：

```sh
node        -e 'let t=Date.now(),s=0;for(let i=0;i<2e7;i++){s+=Math.sqrt(i)*0.5|0}console.log(Date.now()-t)'
node --jitless -e 'let t=Date.now(),s=0;for(let i=0;i<2e7;i++){s+=Math.sqrt(i)*0.5|0}console.log(Date.now()-t)'
node -e 'console.log(typeof WebAssembly)'; node --jitless -e 'console.log(typeof WebAssembly)'
```

### 1.4 没有 JIT 导致的**功能性**缺陷（不只是变慢）

| 影响范围 | 说明 |
|---|---|
| **主宿主进程内 WASM 不可用** | V8 的 `--jitless` 与 `--expose_wasm` 互斥，该进程内 `typeof WebAssembly === 'undefined'`；依赖 WASM 的代码路径只能退回纯 JS 实现 |
| 主宿主进程内的 HTTP 栈 | Node 内置 `undici` 的解析器依赖 WASM，因此主宿主的 `fetch` 由随包纯 JS 垫片接管（已实现并长期验证） |
| 工具链（部分） | 以 `esbuild` wasm 版为代表、依赖 WASM 加速的 npm 包在当前模式下不可用或变慢；纯 JS 包与已适配的路径不受影响 |
| 用户可见后果 | 经主宿主执行的 JS 计算与部分工具链操作**耗时被放大数倍**（实测见 §1.3） |

### 1.5 权限使用范围（最小化承诺）

- **仅**用于 V8 生成/执行 JIT 机器码，作用域在本应用自身进程内；
- **不**用于加载外部可执行文件、**不**用于动态下发代码、**不**对外提供执行能力；
- 应用不收集、不上传用户代码与会话内容（用户自行配置模型凭据，凭据不出本机）；
- 该权限不涉及任何个人数据读取。

### 1.6 口径边界：主宿主进程 ≠ 全部执行路径（2026-11-04 校正）

本应用有两条 JS 执行路径，本申请只针对主宿主：

| 路径 | 当前模式 | 说明 |
|---|---|---|
| 主宿主（常驻 Node 宿主） | `--jitless` | 本申请要解决的问题；argv 见 `hostruntime/src/main/ets/runtime/RuntimePort.ets` 的 `buildHostArgv` |
| 子进程 Node CLI（插件按需拉起） | 独立 wrapper | 见 `hostcore/app/node-runtime-provision.cjs`：wrapper 注释声明该路径使用 JIT（fetch/undici 需要 WebAssembly）。**该路径不构成本申请论据，其能力边界需单独实测与合规评估** |

因此，旧稿中"WebAssembly 恒定 undefined""Node 自带 HTTP 栈不可用""工具链整条断掉"
都是**把主宿主进程的限制扩大成整个应用**。对外提交时只陈述主宿主事实，不要把子进程
路径写进申请叙事。

---

## 2. 使用场景证明材料（附件清单）

| # | 材料 | 来源 / 生成方式 |
|---|---|---|
| 1 | **性能对比录屏**（见 §4 分镜） | 真机录屏 30–60 s |
| 2 | 实测数据表（§1.3） | 本机执行上面 4 条命令的控制台输出截图 |
| 3 | `WebAssembly` 缺失证据 | `node --jitless -e 'console.log(typeof WebAssembly)'` → `undefined` 截图 |
| 4 | 应用内运行时说明 | 设置 → 关于 → 版本信息（显示 Node 24.2.0 / V8） |
| 5 | 功能现场 | 在应用内跑一次 `pnpm install`（或任意 JS 构建），展示耗时 |
| 6 | 架构说明 | 本文 §1.1 表 + §3 视频脚本 |

---

## 3. 上架时的「权限说明」字段（AGC 表单用，控制在 200 字内）

```
本应用内置 Node.js（V8 引擎）作为本地开发运行时。V8 需要申请可写可执行匿名内存来存放
JIT 编译后的机器码；缺少该权限只能以解释模式运行，实测纯计算负载慢 5.5 倍，且 WebAssembly
不可用（导致 esbuild 等工具与 Node 自带 HTTP 栈失效）。该权限仅用于本机 JS 执行，
不采集、不上传用户数据。
```

---

## 4. 场景视频录制脚本（建议 40–60 秒）

| 时间 | 画面 | 旁白 / 字幕 |
|---|---|---|
| 0–5 s | 打开 DSHM，进入「设置 → 关于」 | 字幕：内置 Node.js 24.2.0 + V8 运行时 |
| 5–15 s | 打开终端面板，执行两条 benchmark 命令 | 字幕：同一台设备：有 JIT 345 ms / jitless 1902 ms（慢 5.5×） |
| 15–22 s | 执行 `node --jitless -e 'console.log(typeof WebAssembly)'` | 字幕：无该权限 ⇒ WebAssembly 不可用 |
| 22–35 s | 在应用内跑一次 `pnpm install`（或 JS 构建） | 字幕：工具链执行被显著拖慢 / 部分 WASM 组件不可用 |
| 35–50 s | 回到应用主界面，展示正常工作流 | 字幕：申请该权限仅为让 V8 恢复 JIT，不涉及任何用户数据 |
| 50–60 s | 结束 | 字幕：DSHM · com.dshm.dshclient |

拍摄要点：**必须有时间戳或同屏对比**；两条 benchmark 要连续执行、不改设备状态。

---

## 5. 若不获批的降级路径（表单「备选方案」可填）

| 方案 | 代价 |
|---|---|
| 维持 `--jitless` | 性能损失约 5.5×，WASM 生态不可用，但**功能可用**（我们已用纯 JS 垫片替代 undici / fetch / worker） |
| 把重型 JS 执行迁到 guest Linux 虚拟机 | 内存 +约 512 MB，且仅手持档可用 |
| 仅对 PC/2in1 启用 JIT | 若审批支持按设备形态授予，可只在这些形态声明该权限 |

> 当前源码基线（1.1.7 / `versionCode 1010009`）声明了**两条** `ohos.permission.kernel.*`
> （`IGNORE_LIBRARY_VALIDATION`、`EXEMPT_ANONYMOUS_EXECUTABLE_MEMORY`，属于 entry 权限面 17 条），
> **未声明**本档申请的 `ALLOW_WRITABLE_CODE_MEMORY`。在此前提下主宿主以 `--jitless` 正常运行 ——
> 这可以作为"不影响基本可用性"的证明。旧稿写"未声明任何 kernel.*"是事实错误，已更正。

---

## 6. 提交前自检

- [ ] 申请表单「申请原因」：用 §0 文案
- [ ] 「权限说明」：用 §3 文案
- [ ] 附件：§2 的 6 项（至少录屏 + 性能对比截图 + WASM 截图）
- [ ] 视频：按 §4 分镜录制，40–60 s
- [ ] 备注：本版本尚未声明该权限，获批后再改 `module.json5` 并去掉 `--jitless`

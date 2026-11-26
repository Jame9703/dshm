# 架构（Architecture）

> 只写**当前生效**的结构与边界。历史演进见 `docs/archive/50-*`、`90-*`。
> 会漂移的值（版本、权限条数、设备面）以代码/配置为准。

---

## 1. 一句话

DSHM 是 **Stage 模型的 ArkTS 外壳 + 随包 libnode 宿主 + 上游 dsh 核心树** 的端侧移植：
ArkWeb 只负责渲染上游 Web UI，真正的会话、工具、插件、终端都在端侧宿主进程里跑。

## 2. 分层

```
┌───────────────────────────────────────────────┐
│ entry (HAP, tablet+2in1)   phone (HAP, phone) │  ArkTS 壳：窗口/侧栏/顶栏/权限/桥
│   ArkWeb ←→ WebApp.ets ←→ 桥方法              │
└───────────────┬───────────────────────────────┘
                │ HSP 依赖
┌───────────────▼───────────────────────────────┐
│ hostruntime (HSP, shared)                     │  宿主：端口、就绪、核心安装、Node 启动
│   DshHost / NodeRuntime / CoreStore           │
└───────────────┬───────────────────────────────┘
                │ libnode.so（--jitless）
┌───────────────▼───────────────────────────────┐
│ 核心树 dsh-core-<ver>（随包 zip，解包到 el2） │  上游 UI/服务 + 11 个 dshm 插件 + 移植补丁
│  main.js / boot-seed / 垫片 / plugins         │
└───────────────────────────────────────────────┘
                │ guest VM（仅平板/手机终端）
┌───────────────▼───────────────────────────────┐
│ QEMU guest（Alpine + bash/toolchain）          │
└───────────────────────────────────────────────┘
```

## 3. 模块职责

| 模块 | 类型 | 设备面 | 职责 |
|---|---|---|---|
| `entry` | HAP（entry） | tablet + 2in1 | PC / 平板壳：窗口、顶栏、托盘、侧栏、沉浸材质、碰一碰、权限面 18 |
| `phone` | HAP（entry） | phone | 手机 / 折叠壳：抽屉、返回键、权限面 9 |
| `hostruntime` | HSP（shared） | phone/tablet/2in1 | 宿主运行时：单实例、端口、就绪探测、核心安装/回滚、Node 启动 |
| `platform` | HAR | 全 | 跨壳共享：设备事实、通知、文件选择、云同步引擎、同步范围 |
| `appstate` | HAR | 全 | 应用状态与恢复相关 |
| `dshcompat` | HAR | 全 | 兼容面：端点基线、桥契约相关定义 |
| `connection` | HAR | 全 | 连接与网络能力封装 |
| `hostcore` | 资源/脚本（非 HAP） | — | 核心树配方、宿主 JS 垫片、11 个自带插件、打包工具输入 |
| `hostkit` | 目录（非模块） | — | 宿主侧工具与产物输入，不单独构建 |

## 4. 启动链路

1. `EntryAbility`（entry/phone）拉起窗口，加载 `pages/WebApp.ets`。
2. `WebApp` 创建 ArkWeb，向 `hostruntime` 请求宿主端口与就绪状态。
3. `DshHost` 确保单实例；`CoreStore` 检查/安装随包核心（`resfile/dsh-core-*.zip` → `el2`）。
4. `NodeRuntime` 以 `libnode.so` + `--jitless` 启动核心 `main.js`，注入垫片与桥。
5. 核心在本地端口提供 HTTP/WS；ArkWeb 加载 `http://127.0.0.1:<port>` 的上游 UI。
6. 桥方法（`dshcompat` 契约）把原生能力（文件、终端、通知、分享）暴露给 Web 侧。

桌面主窗在原生启动页首帧后分阶段准备 ArkWeb，宿主并行恢复目录授权并校验核心。收到本次进程的鉴权地址后，已挂载的控制器导航到正式页面。桌面形态平板在 Web 控件可见后交接工作区。S0–S7 保留窗口、宿主和页面加载事件，真机复测另记录首个 WebSocket 业务帧。

**不要**自绘一套 UI 替代上游；壳只做"窗口 + 原生能力 + 必要的 DOM 垫片"。

## 5. 核心树与容器

- 配方唯一来源：`hostcore/core-recipe.json`（版本、裁剪、原生依赖别名、必须存在的原生件）。
- 容器：`hostruntime/src/main/resources/resfile/dsh-core-*.zip`，**只允许 1 份**。
- 解包位置：设备 `files/dsh/cores/<coreVersion>/`；当前版本由 `bin/dsh` 从脚本自身路径推导。
- 重打：`tools/pack-core.mjs --skip-install --place-in-app`；校验：`check-resfile-core-zip`、`assert-resfile-sync`。
- 回滚：`BundledCore` / `CoreStore` 保留上一版；回滚边界由 `check-bundled-core-rollback` 守。

## 6. 数据与路径

| 路径 | 内容 | 处置 |
|---|---|---|
| `el1`（应用安装区） | 代码、资源、HAP/HSP | 覆盖安装可替换 |
| `el2`（应用数据区） | `files/dsh/home`（会话、插件）、`toolchain`、`workspace`、`profiles` | **禁止删除**；只能覆盖安装保留 |
| `files/dsh/cores/<ver>` | 解包后的核心树 | 可重装；升级保留旧版回滚 |
| `resfile/` | 随包核心 zip、VM、toolchain、ffmpeg、busybox | 仓库内静态资产，禁止删 |

## 7. 垫片层（jitless 的代价与补偿）

| 垫片 | 位置 | 解决什么 |
|---|---|---|
| 模块路径守卫 | `hostcore/app/module-path-guard.cjs` | 限制 `NODE_PATH` / `globalPaths`，防越界加载 |
| fs 探测缓存 | `hostcore/app/fs-probe-cache.cjs` | 减少端侧 stat 风暴；只缓存负结果 |
| fetch / undici | `hostcore/app/fetch-shim.js`、`internal-undici-shim.cjs` | jitless 下提供可用 HTTP；保留流式请求体 |
| Python 桥 | `hostcore/app/python-bridge-async.cjs`、`python-worker.cjs` | 进程内 CPython 执行 |
| 工具链落位 | `tools/place-toolchain.mjs`、`place-ffmpeg.mjs` | 闭包完整、SONAME 软链齐全 |
| 技能单源 | `hostcore/app/dshm-skills.js` | 技能文档只放 HSP，运行期映射 |

## 8. 三端分流

- 判据：`platform/src/main/ets/system/DeviceFacts.ets`。
- desktop 档（PC / 2in1 / MatePad Edge / Pro Max）：PC 顶栏、常驻侧栏、原生 PTY。
- tablet：无自绘顶栏、280/56 侧栏几何（≥1024）、guest VM。
- phone / 折叠单屏：抽屉 + 单颗 ⊞、guest VM。
- 折叠多屏：跟平板形态。
- 规则：**三端互不影响，各改各的**；共享逻辑改 `platform` 或两壳同构点。

## 9. 终端

| 档 | 实现 | 说明 |
|---|---|---|
| PC / 2in1 / Edge / ProMax | 原生 PTY（`entry/src/main/cpp/` + 核心树终端插件） | sh / zsh / bash 三模式；TERMINFO 必须可解析 |
| 平板 / 手机 / 折叠 | `hostcore/plugins/dshm-vm-bash`（QEMU guest） | 一进程一 VM；按需冷启动；内存分档 |

**不要**给普通平板/手机注册原生 PTY；也不要给 desktop 档塞 VM 终端。

## 10. 权限与安全域

- `CUSTOM_SANDBOX` 把宿主域提到 `u:r:develop_tools_debug_hap:s0`；`kernel.*` 仍不允许 JIT。
- 权限面：entry 18 / phone 9；ACL 只以发布 Profile 的 `allowed-acls` 为准。
- 文件访问：沙箱 ∪ 用户目录；读写同判据；picker 授权只活一个进程，必须持久化。
- 分享：只有 PC 档注册「碰一碰」接收器，能力面 `general.object + general.file`。

## 11. 构建与交付

| 目标 | 命令 | 产物 |
|---|---|---|
| 日常 | `devecocli build` / `--product phone` | module 产物 `*-signed.hap/hsp` |
| Beta | `tools/build-beta.mjs --combined-app` | `dist/beta/...`（含三端合一 `.app`） |
| 本机侧载 | `AGENT-HANDOFF.md` §3.3 | `local-install`（本机调试签名） |
| AGC | `tools/build-agc.mjs` | `dist/release-test/*.app` + sha |
| 核心 | `tools/pack-core.mjs --place-in-app` | `resfile/dsh-core-*.zip` |

## 12. 读代码入口

1. `entry/src/main/ets/pages/WebApp.ets` / `phone/.../WebApp.ets`：壳层全部接线与垫片。
2. `hostruntime/src/main/ets/runtime/DshHost.ets`、`NodeRuntime.ets`：宿主生命周期。
3. `hostcore/core-recipe.json`：核心树从哪来、裁剪了什么。
4. `hostcore/app/main.js`：宿主启动与垫片安装顺序。
5. `docs/FEATURES.md`：功能 → 实现位置 → 门禁。

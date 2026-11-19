# 259 · DevEco 工具链接手与「看界面」能力落地

> 日期：2026-10-25 · 状态：**已落地**
> 起因：用户要求把 DevEco Studio 侧的能力也接进来，"结合着一起看"；
> 并追问"就在本机，为什么看不到界面"。
>
> 本文回答三件事：**本机到底装了什么**、**看界面到底靠什么**、
> **以后怎么用**。前两轮曾误判"本机没有截图能力"，结论已在此纠正。

---

## 1. 本机 DevEco 侧的真实组成（逐项实跑验证）

用户口径是"DevEco Studio 就装在鸿蒙 PC 上"。实测拆开是**三层**，
必须分清，否则会像我第一轮那样把 `deveco` CLI 当成 IDE：

| 层 | 实际存在的东西 | 路径 | 实跑验证 |
|---|---|---|---|
| **IDE 本体** | ❌ **没有安装** | — | `bm dump -a` 无 `*deveco*` / `*studio*` 包；全盘无 `product-info.json` |
| **命令行工具链** | ✅ hmos-clt 1.0.0 | `/data/service/hnp/hmos-clt.org/hmos-clt_1.0.0` | 见下表 |
| **AI agent CLI** | ✅ deveco code 0.2.4 | `~/.npm-global/lib/node_modules/@deveco/deveco-code-openharmony-arm64` | `deveco --version` → `0.2.4` |

### 1.1 命令行工具链（这才是真正的"DevEco 侧能力"）

| 工具 | 版本 / 状态 | 路径 |
|---|---|---|
| node | **v24.18.1** | `<R>/node/bin/node` |
| ohpm | **6.0.1** | `<R>/ohpm/bin/ohpm` |
| hvigor | 存在 | `<R>/hvigor/bin/hvigorw.js` |
| hdc | **Ver 3.2.0f** | `<R>/sdk/default/openharmony/toolchains/hdc` |
| SDK `.d.ts` | 齐全 | `<R>/sdk/default/openharmony/ets/api/` |
| codelinter | 存在 | `<R>/codelinter/bin/codelinter` |
| clangd / ace-server | 存在 | `<R>/clangd`、`<R>/ace-server` |

`<R>` = `/data/service/hnp/hmos-clt.org/hmos-clt_1.0.0`
（`tools/lib/deveco-home.mjs` 的 `resolveDevecoRoot()` 返回的正是它）

> **`~/.local/share/devecocli-mcp-server` 只有 `logs/`，没有二进制** ⇒
> 文档里提到的 devecocli MCP 当前不可用。别按它规划工作。

### 1.2 `deveco` CLI 不是 IDE

`~/.npm-global/bin/deveco` → `@deveco/deveco-code-openharmony-arm64/cli.js`，
是个 opencode 系的 AI agent，子命令为 `acp` / `mcp` / `serve` / `run` / `attach` 等。
**没有** `deveco build`、`deveco install` 这类构建命令——构建仍然走 `hvigorw`。

---

## 2. 「看界面」到底是什么在做事

### 2.1 纠正：前一轮的结论是错的

前一轮我探测了 `snapshot_display` / `uitest` / `screencap`，得到"本机不存在"，
于是写成"鸿蒙 PC 没有系统级截图能力"。**这个结论对了一半**：

- ✅ 对的部分：这些命令**确实不在这台机器的 `/bin` 下**，直接执行报
  `exec snapshot_display: No such file or directory`。
- ❌ 错的部分：它们**本来就不该在本机** —— `snapshot_display` / `uitest`
  是**端侧（设备）** 的命令，通过 `hdc shell` 在设备上执行。

### 2.2 正确答案：能力在 deveco code 自带的 UI 验证 MCP 里

```
~/.npm-global/lib/node_modules/@deveco/deveco-code-openharmony-arm64/
    vendor/ui-verification-mcp/uiVerification.mjs      (1,480,282 B)
```

这个文件里封装了完整的"看界面 + 操作界面"链路，全部经 `hdc shell` 发到设备：

| 能力 | 实际下发的命令 |
|---|---|
| 截图 | `snapshot_display -f <path>` / `-w <w> -h <h> -f <path>` |
| 取回图片 | `base64 -w 0 <path>` → 本机解码 |
| UI 树 dump | `uitest dumpLayout -p <path>` |
| 点击 | `uitest uiInput click <x> <y>` |
| 双击 / 长按 | `uitest uiInput doubleClick` / `longClick` |
| 按键 | `uitest uiInput keyEvent <code>` |
| 鼠标 / 滚轮 | `uinput --mouse --move … --click …` / `--scroll …` |
| 屏幕尺寸 | `hidumper -s DisplayManagerService -a -a` |
| 窗口栈 | `hidumper -s WindowManagerService -a '-a'` |
| 设备类型 | `param get const.product.devicetype` |
| 启停应用 | `aa start -a <a> -b <b>` / `aa force-stop <b>` |
| 日志 | `hilog -P <pid>` |

`singleScreenshot()` 的失败处理也值得记：截图**最多重试 5 次**，
每次间隔 `i*100ms`，仍不含 `success` 才抛 `暂时无法截图，请稍后再试`。

### 2.3 所以"看界面"的前提是 hdc 能连上设备

关键区别：

- **Codex 当年**：`hdc -t 62T0225B18039433`（手机）、`-t 127.0.0.1:45595`（另一台设备）
  ⇒ 它也是**隔着 hdc 连外部设备**，不是在本机自截。
- **本机现状**：`hdc list targets` = `[Empty]`；`hdc -m -s` 守护进程在跑，
  但 8710/8711/8712/5555 全部 `ECONNREFUSED`；`tconn 127.0.0.1:<port>` 全部 `[Fail]Connect failed`。

⇒ **鸿蒙 PC 自己连不上自己**（无 USB、无无线调试配对）。
要让 `uiVerification` 这条链路真正跑起来，必须有一个 hdc 可达的目标设备。

---

## 3. 已落地的技能

`arkts-compile-fixing` 已从 `~/.workbuddy/skills/` 复制进工作区：

```
.dsh/skills/arkts-compile-fixing/SKILL.md
```

它的价值和本机工具链正好互补。技能里给的 SDK 路径示例是
`~/.harmonybrew/Cellar/ohos-sdk/<version>/ets/api/`，**本机实际是**
`/data/service/hnp/hmos-clt.org/hmos-clt_1.0.0/sdk/default/openharmony/ets/api/`
——读 `.d.ts` 核实 API 时按后者找。

技能里最该记住的三条：

1. **先分类再动手**：`10505001 Property 'x' does not exist` 是**API 不存在**，
   必须读 `.d.ts` 核实；`10605xxx` 带 `arkts-` 规则名才是**语法限制**。
   两类混淆是最大的时间黑洞。
2. **catch 变量不是 `Error`**：`throw e` 非法、`e.message` 非法；
   且错误码会丢，正确做法是在**最内层** catch 把 `code`/`message` 摊平进消息文本。
3. **不要赌检查器实现**：`Object` 收窄后当 string、`isNaN`/`Number(objectTyped)`
   这类写法能不能过取决于未文档化行为，一律显式 `as` 绕开。

当前工作区技能清单（`.dsh/skills/`）：

```
README.md
app-metadata-audit-skill
arkts-compile-fixing          ← 本次新增
harmonyos-docs-kb
hmos-connect-api-cli-skill
```

---

## 4. 现在怎么用

### 4.1 编译 / 构建（不依赖 IDE）

```sh
node tools/build-beta.mjs          # 三端 beta
node tools/package-release.mjs     # AGC 签名 .app
```

工具链由 `tools/lib/deveco-home.mjs` 解析，**不要写死 DevEco 安装根**
（`check-deveco-paths.mjs` 会把写死的 Windows 绝对路径判红）。

### 4.2 核实 ArkTS API

```sh
ls /data/service/hnp/hmos-clt.org/hmos-clt_1.0.0/sdk/default/openharmony/ets/api/ \
  | grep -i huks            # 例：@ohos.security.huks.d.ts
```

### 4.3 看界面（需要 hdc 可达的设备）

```
设备经 USB / 无线调试连上 → hdc list targets 有输出
  → uiVerification.mjs 的 snapshot_display / uitest dumpLayout 才可用
```

本机自连不可行（已验证），这条路径要么接真机、要么接模拟器。

---

## 5. 没做的事（如实登记）

- **没有安装 bsk / BrowserSkill**：`bsk` CLI 不在 PATH，BrowserSkill 只有
  `aarch64-apple-darwin` / `aarch64-unknown-linux-musl` / `x86_64-*` 预编译，
  **没有 aarch64-openharmony**；本机也没有 Chromium/Edge 可附着（只有
  `com.huawei.hmos.browser` 应用进程）。⇒ browser-skill 在本机当前不可用。
- **没有装 DevEco Studio IDE**：本机只有 CLT。用户若要 IDE 本体，需另行安装。
- **没有改任何构建产物 / 签名物料 / 真机数据**。本文是纯只读勘察 + 技能复制。

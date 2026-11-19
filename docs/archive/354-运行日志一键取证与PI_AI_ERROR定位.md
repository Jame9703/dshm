# 354 · 运行日志一键取证与 `PI_AI_ERROR` 定位

> 日期：2026-11-05 ｜ 触发：用户反馈「模型执行到一半报 `PI_AI_ERROR`」，并要求
> 「DSHM 直接抓本地 APP 日志，方便调试」
>
> 本轮**只读**设备与日志；未卸载、未删除 el2 数据、未改权限面。

---

## 0. 结论先行

| 问题 | 结论 |
|---|---|
| `PI_AI_ERROR` 是什么 | **模型流中途被上游终止**，且终止文本无法被适配层归类（实测就是一句 `aborted`），于是被判成**不可重试**的通用错误，整轮直接失败 |
| 是不是我们的编译/插件 bug | **不是**。宿主事件循环全程存活（`LOOP-ALIVE` 每 20 s 一拍，错误时刻照常跳），崩溃/冻结可以排除 |
| hdc 为什么"不通" | 应用沙箱**根本没有 hdc 服务端能力**：UDS 固定绑 `/data/hdc/hdc_debug/hdc_server`（目录不存在 ⇒ `bind ret:-13`），`/dev/bus/usb` 也不可见（本轮复核：`Permission denied`）；`-s` 选项不支持。见 `docs/352` |
| 怎么"直接抓日志" | 新增 `tools/dshm-logs.mjs`：**本机直读**（不依赖 hdc），一次产出脱敏日志包到 `Download/com.dshm.dshclient/dshm-logs/` |
| 装到别的设备 | 在 **DevEco 终端**（沙箱外）用 hdc：USB 直连，或目标设备开无线调试后 `hdc tconn <ip>:<port>` |

---

## 1. `PI_AI_ERROR` 的证据链

### 1.1 错误码从哪来

`dsh-llm-pi-ai` 把模型流的终止原因映射成 harness 的 finish reason：

```js
// node_modules/@deepseek-ai/dsh-llm-pi-ai/lib/index.js
function classifyPiAiError(message) {
  if (/\b(?:401|403)\b/.test(message)) return "AUTH";
  if (isQuotaExceededError(message)) return QUOTA_EXCEEDED_CODE;
  if (/\b429\b|rate.?limit/i.test(message)) return "RATE_LIMIT";
  ...
  if (/\b(?:network|connection|socket|fetch)\b|ECONN[A-Z]+|terminated|premature close/i.test(message)) return "TRANSPORT";
  return "PI_AI_ERROR";     // ← 兜底：认不出来的都归这里，且**不可重试**
}
```

`mapStopReason()` 里还有两条直接产出 `PI_AI_ERROR` 的分支：
`pending`（流结束但状态仍是 pending）与 `deferred`（上游要求延迟响应，适配层不支持）。

### 1.2 真机现场（会话记录，不在宿主 stdout）

`node-output.log` 里 `PI_AI_ERROR` 出现 **0 次** —— 这个错误只落在会话文件里，
所以必须解码 `session.v4.jsonl.zstd` 才能看见（这也是本工具的动因之一）：

```text
session-f6c292ac-…（工作区 DSHM-deveco-workspace）
turn=11  失败：PI_AI_ERROR×4，aborted×1
  PI_AI_ERROR @ 2026-11-04T15:34:07.292Z：aborted
  PI_AI_ERROR @ 2026-11-04T15:42:08.841Z：aborted
  PI_AI_ERROR @ 2026-11-04T15:54:34.476Z：aborted
  PI_AI_ERROR @ 2026-11-04T16:11:02.997Z：aborted
```

四轮的耗时（turn/start → turn/end）：

| turn | 时长 | 结束文本 |
|---:|---:|---|
| 5 | 19 分 21 秒 | `aborted` |
| 6 | 6 分 44 秒 | `aborted` |
| 7 | 3 分 35 秒 | `aborted` |
| 9 | 5 分 8 秒 | `aborted` |

### 1.3 同一时刻宿主是活的

`dshm-host.log` 在 15:33–15:35 区间只有心跳与正常收尾：

```text
[15:33:08] LOOP-ALIVE 第 10800 拍
[15:34:07] card-state: 余额刷新（turn-end）¥9.44      ← 该轮在此结束
[15:34:08] LOOP-ALIVE 第 10860 拍
[15:34:09] [worker-shim] 已注入 worker 线程 …
```

⇒ **主线程没有卡死、进程没有崩**（心跳间隔始终 20 s）。
所以 `aborted` 不是我们本地 abort 产生的：pi-ai 的 `stopReason` 会是 `aborted`
（映射成 `ABORTED`），而这里拿到的是 `kind: error` + `message: "aborted"`，
即**上游/中转发来的错误事件**。

### 1.4 为什么"看起来像模型执行到一半"

上游把 SSE 流中断在半途（长回答、长工具链最容易触发；中转层也可能有自己的空闲
超时/账号切换），适配层收到的是终止事件而不是正常 `stop`。
`classifyPiAiError("aborted")` 不匹配任何已知模式 ⇒ `PI_AI_ERROR` ⇒ 不可重试 ⇒ 整轮失败。
用户侧的感受就是"跑到一半忽然报错"。

### 1.5 还有哪些失败码（同一台设备，历史会话累计）

| 失败码 | 次数 | 典型文本 | 含义 |
|---|---:|---|---|
| `aborted` | 8 | — | 客户端/会话侧主动中止（正常） |
| `PI_AI_ERROR` | 4 | `aborted` | **本轮要治的那种** |
| `INVALID_REQUEST` | 5 | `codearts: model request failed with HTTP 400` | 请求体被上游拒 |
| `AUTH` | 3 | `workbuddy upstream session_dead (http 403) …` | 账号池会话失效 |
| `RATE_LIMIT` | 2 | `every account is rate-limited for model glm-5.3` | 账号冷却 |
| `QUOTA_EXCEEDED` | 1 | `GLM-5.3-Flash 额度已用尽` | 额度耗尽 |
| `CONTEXT_WINDOW_EXCEEDED` | 1 | `gpt-6.1-sol` 上下文溢出 | 工作集过大 |
| `UNKNOWN` | 3 | `WebAssembly is not defined` | 宿主 `--jitless` 下的 WASM 路径 |

> 结论：这台机的模型通道是**多账号池 + 中转**（Channel Pack），失败码里
> `AUTH/RATE_LIMIT/QUOTA` 都出现过。`PI_AI_ERROR` 是同一族问题里**最不透明**的一条，
> 因为它把"上游中断"翻译成了一个既不像网络、也不像额度的死码。

### 1.6 修复方向（需要重建核心树，未在本轮落地）

1. `classifyPiAiError` 把裸 `aborted` / `abort` 归为 `TRANSPORT`（可重试语义）；
2. 在适配层对**尚未产出任何内容块**的 `TRANSPORT` 做一次有界自动重试；
3. 会话 UI 上把这类中止呈现为「连接中断，可继续」，而不是 `PI_AI_ERROR` 死码。

落点：`tools/pack-core.mjs` 增加对 `@deepseek-ai/dsh-llm-pi-ai/lib/index.js` 的补丁 +
`coreVersion` 递增；同时把判据加进 `tools/check-core-openharmony-patches.mjs`。
⚠️ 这会要求重出核心容器与安装包，**本轮不动**（用户正在装测试包）。

---

## 2. `tools/dshm-logs.mjs`：一键取证

### 2.1 为什么不是 hdc

`docs/352` 已实测：沙箱内 hdc 的**服务端起不来**——

```text
[F] libusb_init failed ctxUSB is nullptr
[W] SetUdsListen:279 bind uds addr fail! ret:-13      ← /data/hdc 在沙箱里不存在
$ hdc -s 127.0.0.1:18710 list targets
[E001105] Unsupport option [s]
```

本轮复核补充：`/dev/bus/usb` **Permission denied**。
且 hdc 的失败是**静默**的（`list targets` 空、`rc=0`），最容易误判成"没有设备"。
所以工具把 hdc 明确标注为"沙箱外通道"，并在沙箱内自动识别 + 回退本机直读。

### 2.2 用法

```bash
# 最常用：本机（DSHM 就跑在这台设备上），抓默认 6 MB 尾部
node tools/dshm-logs.mjs

# 抓更多 / 指定落点 / 只看通道状态
node tools/dshm-logs.mjs --tail 15
node tools/dshm-logs.mjs --out /tmp/logs
node tools/dshm-logs.mjs --list

# 沙箱外（DevEco 终端）连别的设备
hdc tconn 192.168.1.23:5555
node tools/dshm-logs.mjs --hdc --target 192.168.1.23:5555

# 自检（脱敏 / 失败码统计 / 命中行）
node tools/dshm-logs.mjs --self-test
```

### 2.3 产物

```text
Download/com.dshm.dshclient/dshm-logs/DSHM-logs-<stamp>/
├── SUMMARY.md          结论页：会话失败码直方图 + 样本 + 命中行 + 建议
├── SUMMARY.json        同事实的机器可读版
├── host-ready.json     pid/port/runtime（token 与带 token 的 URL 都去掉）
├── node-output.log     宿主 stdout 尾部
├── dshm-host.log       ArkTS/原生侧日志尾部
├── host-crash.log      崩溃现场（有则全量）
├── diag-*              端侧诊断标记（tray / keepalive / notify / mem …）
└── sessions/           最近两个会话的原始 zstd + 解码出的失败摘要
```

### 2.4 安全与脱敏

- **全程只读**：不删设备文件、不写设备端任何路径、不碰签名与 el2 用户数据；
- 输出统一过 `redact()`：`?token=`、`api[-_]key`、`Authorization/Bearer`、`cookie`、
  `password`、`sk-…` 一律 `<redacted>`；`host-ready.json` 改为**按字段重建**（不整段正则，
  避免把 JSON 弄坏）；
- 不抓取会话正文内容，只统计 `turn/end` 的失败码与错误文本。

> 自检里踩过一次真实的坑：先跑键值规则会把 `Authorization: Bearer xxx` 里的
> `Bearer` 吃掉，剩下的 token 逃过脱敏 ⇒ 现在**先处理认证头**再跑键值规则，
> `--self-test` 把这条钉住了。

---

## 3. 想装到"各种鸿蒙设备"

| 场景 | 做法 |
|---|---|
| 手机 / 平板 / 2in1 走 USB | 在 **DevEco 终端**（沙箱外）`hdc list targets` → `hdc install -r <hap>`；本仓用 `node tools/update-device.mjs`（恒 `-r`，禁止卸载） |
| 无线调试 | 目标设备：设置 → 系统 → 开发者选项 → **无线调试**；沙箱外 `hdc tconn <ip>:<port>` 后再装 |
| 应用内自装 | ❌ 不可行：沙箱内 hdc 无服务端（`docs/352`），且不允许为排障改权限面 |

> 应用内能做的替代：本工具把本机日志**直接落到可见的 `Download/<包名>/`**，
> 你随时可在文件管理里取走，不需要 hdc。

---

## 4. 验证记录（本轮）

| 项 | 结果 |
|---|---|
| `node tools/dshm-logs.mjs --self-test` | PASS（脱敏 / 直方图 / 命中行去重 / 建议） |
| 实跑（本机 4 MB 尾部） | ✔ 32 项文件、32 MB，`PI_AI_ERROR×4` 被正确统计 |
| `--list` | 正确报出"沙箱内 hdc 起不来（`bind ret:-13`）"，并给出替代路径 |
| 沙箱内 `--hdc` | 识别 UDS 失败 ⇒ **自动回退本机通道**（不再谎报"没有设备"） |
| 脱敏抽查 | `dshm-host.log` 中 25 处 token/cookie/Bearer 全部 `<redacted>`；`host-ready.json` 仍是合法 JSON |
| 设备改动 | 无：未安装、未卸载、未删除、未改权限 |

---

## 5. 下一步（按收益排序）

1. **复现 `PI_AI_ERROR` 时先跑 `node tools/dshm-logs.mjs`**：摘要页会直接给
   模型、轮次、耗时和失败文本；若再出现，把该包发我即可。
2. 若想根治：按 §1.6 给 pi-ai 加分类 + 有界重试补丁（需重建核心树、重出包）。
3. 多账号池的 `AUTH/RATE_LIMIT/QUOTA` 建议在 Channel Pack 面板巡检后再跑长任务。
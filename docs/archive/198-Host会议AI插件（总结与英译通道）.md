# 198 · Host 会议 AI 插件（AI 总结与实时英译通道）

> 2026-10-19。用户口径（`docs/197`）：「每次会议结束加入 AI 总结，看看能不能接入小艺；实时转写加入英文翻译支持」。
> `docs/197` 已把方向定死：**小艺没有公开的摘要/翻译 API**（`@hms.ai.A2A` 是"我们被小艺调用"、`textProcessing`
> 只有实体识别与分词、系统侧翻译 API 零命中）⇒ 两项能力走 **Host 侧本机模型**（`ctx.llm`，包 `@deepseek-ai/dsh-llm`）。
>
> 本篇是**该项实现的说明与证据**：插件 `hostcore/plugins/dshm-meeting-ai/`、协议、模型调用形态、失败降级、打包与门禁。
> 面板/会话/录音那一半（`entry/`、`platform/` 的 ArkTS）不在本篇范围，见 `docs/195`/`196`。

---

## 1. 一分钟看懂

```
原生会议面板 (ArkTS)                     Host (Node)
─────────────────────                    ─────────────────────────────────────────────
写 $DSH_HOME/meeting-ai/<id>.req   ─────▶  插件 dshm-meeting-ai 每 300ms 扫目录
  {kind:'summary', text:'…'}                · kind=summary  → 三段中文 Markdown
  {kind:'translate',text:'…',seq:12}        · kind=translate→ 只输出英文译文
                                              ↓ ctx.llm.prepareCall() + call.stream()
读 <id>.done / <id>.fail           ◀─────  写结果（先隐藏 .tmp 再 rename，原子）
读后自行删除结果文件                      处理完删除 <id>.req
```

| 事实 | 值 |
|---|---|
| 插件 | `@deepseek-ai/dshm-meeting-ai`（源码 `hostcore/plugins/dshm-meeting-ai/`） |
| 队列目录 | `$DSH_HOME/meeting-ai/`（端侧 = `<filesDir>/dsh/home/meeting-ai`） |
| 服务依赖 | `llm`（模型）+ `agentDefaultModel`（route 来源） |
| 单条超时 | **60s**（同时 `AbortController.abort()` 掐掉模型调用） |
| 并发 | 最多 3 条在飞，其中 **summary 同期 1 条** |
| 总结输入上限 | 取**尾部** 12000 字（并在 prompt 里明说只给了结尾） |
| 英译输入上限 | 6000 字（超了**如实失败**并要求分段，不静默截断） |
| `coreVersion` | `0.2.1-rc.2+dshm.76` |

---

## 2. 协议（三侧逐字一致，门禁钉死）

ArkTS 侧对端：`entry/src/main/ets/speech/MeetingAiBridge.ets`（`MeetingAiBridge.request(kind, text, seq)`）。
**字段一个都不能改**：两边各写一份字符串，改了一边另一边不报错，只是面板永远解析不到（本仓 `HostEvents.ets`
头注记的就是这类事故）。

| 文件 | 时机 | JSON |
|---|---|---|
| `<id>.req` | ArkTS 写 | `{"kind":"summary","text":"…"}` / `{"kind":"translate","text":"…","seq":12}` |
| `<id>.done` | 插件写（成功） | `{"ok":true,"kind":"summary","seq":0,"text":"…"}` |
| `<id>.fail` | 插件写（失败） | `{"ok":false,"message":"AI 总结失败：…"}` |

约定与边界：

- `<id>` 由 ArkTS 生成（当前形态 `meeting-<kind>-<毫秒>-<自增>`）；插件只按 `<id>.req` 认请求。
- **插件处理完删 `.req`**；`.done`/`.fail` **保留**，ArkTS 读到后自己删（它已实现。
  `readAndRemove`）。这样"结果写成功但删除失败"只会多一个文件，不会丢结果。
- 结果**先写同目录隐藏 `.tmp` 再 `rename`**：ArkTS 250ms 轮一次、看到文件就整读 `JSON.parse`，
  直接写有概率被读到半截 ⇒ 面板报"解析失败"而 Host 认为成功。
- 坏请求（非法 JSON / 未知 `kind` / 空 `text`）⇒ 写 `.fail` **并删 `.req`**：不重试（否则每 300ms
  烧一次，且永远不会成功）。
- 过期清理（都是插件自己的临时产物，不是用户数据）：启动时 + 每 60s 一拍
  - `.req` mtime > **5 分钟** ⇒ 删。那是上次宿主崩溃/停机的残余，请求方（英译 30s / 总结 120s）早已超时，
    重跑只白烧 token。
  - `.done`/`.fail` > **6 小时** ⇒ 删；总量超过 **500** 个时按最旧淘汰（`.done/.fail` 正常由 ArkTS 读后删）。

---

## 3. 模型调用形态（照官方模板，刻意少两样）

模板 = `dist/core/.../node_modules/@deepseek-ai/dsh-session-title-llm/lib/index.js` 的
`executeSessionTitleLlm()`：

```js
const call = await ctx.llm.prepareCall({ provider, model, maxTokens }, signal, (controls) => controls);
const messages = [createUserMessage({ content: [{ type: 'text', text }], source: { kind: 'dshm-meeting-ai' } })];
const assembler = new BlockAssembler();
for await (const chunk of call.stream({ ...call.config, messages, system, signal })) assembler.push(chunk);
// finish.kind === 'stop' | 'max-tokens' → 取 text 块；'error' | 'aborted' → 抛错
```

**route（provider/model）来自 `ctx.agentDefaultModel.currentSelection()`** —— 与
`dsh-api-session-controller` 在"会话还没有 logged header"时的兜底同源；**每条请求现读一次**，
所以会中在「设置 → 模型」切模型能立刻生效。行 config 里也能显式给 `provider`/`model`（优先）。

**刻意没抄的两处**（都有类型/语义依据，不是省略）：

| 不传 | 原因 |
|---|---|
| `purpose` | `GenerateOptions.purpose` 的类型是封闭联合 `'compaction' \| 'session-title'`（`@deepseek-ai/dsh-llm` 声明）。会议总结不属于其中任何一种 ⇒ 不伪造一个值 |
| `sessionId` | 本通道不属于任何会话（会议面板是原生 UI）。硬塞一个 id 只会在会话日志里造出一条对不上的辅助请求 |

终止原因处理：`error`/`aborted` **一律抛错**（把 `failure.code`/`failure.message` 带进 `.fail`）；
`max-tokens` 只记录（截断的总结仍是总结），但**空文本算失败**（绝不写空 `.done` 骗面板）。

### 3.1 summary 的 prompt 约束

system prompt 硬要求（门禁逐条断言）：

1. **只输出三段**、标题逐字 `### 进度` / `### 决策` / `### 待办`、顺序固定；
2. **只使用转写里出现过的事实，绝不编造**人名/数字/日期/结论，没提到就写「（未提及）」；
3. 每条一行短句、每段 ≤5 条、三段合计 ≤400 字；不要复述寒暄、不要整段引用原文；
4. 不要代码块围栏、不要前后缀，正文**直接以 `### 进度` 开头**。

输入侧：超长时**取尾部** 12000 字，并明说「全文共 N 字，为避免超长只给了结尾 12000 字，前面已省略；
**不要推测省略部分的内容**」。为什么取尾部：会后关心的是"最后定了什么、还差什么"；取头部会把决议与待办丢掉
（对照臂 B 就是把这个方向改反，必须判红）。

用户输入形态：

```
以下是这场会议转写的**结尾部分**：全文共 17432 字，为避免超长只给了结尾 12000 字，前面已省略；不要推测省略部分的内容。

<transcript>
…（正文）…
</transcript>
```

### 3.2 translate 的 prompt 约束

1. **只输出英文译文本身**：不解释、不加引号、不加「译文：」前缀、不要 Markdown/代码块；
2. 产品名/专有名词/缩写可保留原样；夹带的英文单词与数字原样保留；
3. **输入是半句就照原样翻完，不补全、不续写**（识别器切出来的片段很常见）；
4. 用户输入就是**正文本身**，不套 `<text>` 之类标签（单句翻译加标签容易被模型照抄进译文）。

超长（>6000 字）**如实失败**并要求分段：`英译输入过长（6123 字，上限 6000），请按句分段发送`。
静默截断是更坏的选择 —— 面板会把半截译文当成整句的译文贴上去。按 `docs/197` §2.4 的"只翻稳定整句"分批，
正常不会触发这条上限。

---

## 4. 失败降级（每一条都是"如实失败"）

| 情况 | 现象 | 面板看到 |
|---|---|---|
| 未配模型 / 未登录 / 断网 | `currentSelection()` 为空或模型调用抛错 | `.fail`「AI 总结失败：没有可用的默认模型（请先在「设置 → 模型」里选择）」/ 模型原始错误码与文案 |
| 单条 >60s | 定时器触发 `abort()`，落 `.fail` | `.fail`「…失败：处理超时（60000 ms，已放弃并写 .fail）」 |
| 模型流被中止 / provider 报错 | `finish.kind` = `aborted`/`error` | `.fail`「模型返回失败（<code>）：<message>」 |
| 模型返回空文本 | 视为失败 | `.fail`「模型没有返回任何文本」 |
| 请求 JSON 坏 / 未知 kind / 空 text | 写 `.fail` 并删 `.req` | `.fail`「请求不合法：…」 |
| 宿主正在停止 | 在飞请求被 abort | `.fail`「…失败：宿主正在停止，请求未完成（请重试）」 |
| `DSHM_HOME` 缺失 | 插件整条惰性（只打一行日志） | 请求超时（面板自己的 120s/30s） |
| 插件 `apply()` 任何准备失败 | 只打一行 `未启用：…` | 同上，**绝不影响宿主启动** |

两条铁律：**绝不写空 `.done`**；**绝不把异常抛给宿主**（端侧 boot 对"任何一行 activate 失败"是整体失败，
附加能力不能拖垮启动）。

---

## 5. 打包与接线（三处，缺一不可）

| # | 位置 | 内容 |
|---|---|---|
| ① | `tools/pack-core.mjs` 的 `DSHM_PLUGIN_PACKAGES` | `{ name: '@deepseek-ai/dshm-meeting-ai', dir: 'dshm-meeting-ai' }` ⇒ 落进核心树 `node_modules/@deepseek-ai/` 并在 `@deepseek-ai/dsh-web-app` 的 dependencies 里声明（loader 才按名字解析得到） |
| ② | `hostcore/profile/ondevice/cordis.patch.yml` ⑭ | `- insert: - id: dshm-meeting-ai / name: '@deepseek-ai/dshm-meeting-ai'` ⇒ 真的被装载 |
| ③ | `tools/check-meeting-ai-plugin.mjs` + `.github/workflows/gates.yml` | 离线门禁（带 2 个变异对照臂） |

打包命令（与 `docs/HANDOFF.md` §12 同款，**必须带 `--place-in-app`**，否则 resfile 里还是旧容器）：

```powershell
# 1) 新版本的 stage：把上一代核心树整棵复制成新版本名（--skip-install 复用它的 node_modules）
robocopy dist\core\work\dsh-core-0.2.1-rc.2+dshm.75 dist\core\work\dsh-core-0.2.1-rc.2+dshm.76 /E /MT:16
# 2) 改 hostcore/core-recipe.json 的 coreVersion
# 3) 出包 + 同步 resfile
node tools/pack-core.mjs --skip-install --place-in-app
```

本次实读：

- `coreVersion` = `0.2.1-rc.2+dshm.76`；
- 容器 `dist/core/dsh-core-0.2.1-rc.2+dshm.76-openharmony-arm64.zip`
  **99,358,342 B / 40,770 条目 / sha256 `61c691801615f287d4f3bab16b21c9a375ca5e62c8954ec1348f08da8c37dbe8`**；
- `entry/src/main/resources/resfile/` 只有这一份（旧的 `.75` 已被 `--place-in-app` 清掉），
  与 `dist/core` 的本次产出**逐字节相同**（`check-resfile-core-zip` 判据）；
- `.75` 的 zip 与 manifest 仍留在 `dist/core/` 作为回退件。

### 5.1 与上一代树的逐文件对照（证明"只动了该动的"）

同一份脚本对 `.75` / `.76` 两棵树按相对路径比 sha256（35,627 → 35,630 文件）：

- **只在 `.76`**：`node_modules/@deepseek-ai/dshm-meeting-ai/{package.json,lib/index.js,lib/meeting-ai.js}`（3 个）；
- **内容变化**：`dshm-core.json`（`builtAt` + 插件版本/清单）、`node_modules/@deepseek-ai/dsh-web-app/package.json`
  （+1 条依赖声明）、根 `package.json`（容器版本串）、`profiles/ondevice/cordis.patch.yml`（新增 ⑭ 节）—— 4 个；
- **其它 35,623 个文件逐字节相同**（含上一版注入过的 `dsh-tool-fs-search`：从 pristine 重打后字节完全一致）。

---

## 6. 门禁

```powershell
node tools/check-meeting-ai-plugin.mjs        # 本插件（A 接线 / B 行为 / C 对照臂）
node tools/check-resfile-core-zip.mjs         # resfile 唯一且与 dist/core、配方三方一致
node tools/check-core-openharmony-patches.mjs # 树内补丁 + 自带插件逐字节副本（新增 meeting-ai 一条）
node tools/check-plugin-toggle.mjs            # 宿主离线起一遍：自带插件行 5/5 启用
node tools/assert-core-entrypoints.mjs        # 裁剪后 623 个包根的入口可达
```

`tools/check-meeting-ai-plugin.mjs` 的三层（离线，不需要核心树与模型）：

- **A 接线层**（43 条；干净克隆里没有核心 zip 时 41 条）：清单/ESM/peer 钉法、`ctx.llm.prepareCall` 与 `call.stream` 的**代码形态**
  （去掉注释后再判 —— 头注里逐字写着模板调用形态，只看原文会"实现被删、注释还在"也判绿）、**不伪造
  `purpose`/不传 `sessionId`**、`apply()` 不抛、`ctx.effect` 生命周期、prompt 约束、**ArkTS 侧协议逐字一致**、
  pack-core/profile/CI 三处接线、配方与产物（干净克隆没有 zip ⇒ 只打 SKIP 不判红）。
- **B 行为层**（30 条）：临时目录 + 假 `callModel` 真跑 —— 成功/失败/超时（含"真的 abort 了"）/坏 JSON/
  空 text/截断方向/英译超长/并发（summary ≤1 且英译优先起跑）/stop/过期清理/原子写。
- **C 对照臂**（2 条）：把 `lib/meeting-ai.js` 的**源码副本**改一处再真跑：
  - 臂 A：`.done` 的 `text` 字段改名成 `content`（模拟跨侧字段漂移）⇒ 必须判红；
  - 臂 B：截断从"取尾部"改成"取头部"（模拟方向写反）⇒ 必须判红。

本次读数：

- `check-meeting-ai-plugin` → **73 条判据 73 通过 / 0 失败 + 2 个对照臂都有效**，`RESULT: PASS`；
- `check-resfile-core-zip` → `✅ 通过：resfile 只有 1 份容器，且与配方、与本次产出完全一致。`
- `check-core-openharmony-patches` → `RESULT: 240 passed, 0 failed`（其中
  `node_modules/@deepseek-ai/dshm-meeting-ai 与 hostcore/plugins/dshm-meeting-ai 逐字节一致（反向判据）`）；
- `check-plugin-toggle` → `baseline: 自带插件行 5/5 启用` / `RESULT: PASS`；
- `assert-core-entrypoints` → `结果：PASS —— 所有运行期入口声明都解析得到包内文件`。

---

## 7. 设备侧验证步骤（**离线端到端已做；真机未做**）

### 7.1 已做的离线端到端（真宿主 + 真核心树 + 假 `DSH_HOME`）

不用设备也能证明"插件真的被装载、队列真的被扫、失败真的落成 `.fail`"：用
`hostcore/app/main.js` 起一个真宿主（`--jitless --experimental-sqlite --expose-internals`，
`DSHM_CORE_DIR` 指向 `.76` 树、`DSHM_HOME` 指向临时目录），往 `meeting-ai/` 写一条
`summary` 与一条 `translate` 请求。本次实读（本机没有模型凭据，所以走的是**失败路径**）：

```
[dshm-meeting-ai] 已启用：队列 …\meeting-ai（超时 60000 ms，并发 3/总结 1，输出上限 2048/1024 tokens）
队列目录： e2e-sum.fail, e2e-tr.fail
e2e-sum.fail => {"ok":false,"message":"AI 总结失败：模型返回失败（MISSING_CREDENTIAL）：llm-deepseek: no API key …"}
e2e-tr.fail  => {"ok":false,"message":"英译失败：模型返回失败（MISSING_CREDENTIAL）：llm-deepseek: no API key …"}
[dshm-meeting-ai] 已停止（本次处理 0 条，失败 2 条）
```

这一条同时证明：`inject` 的两个服务都在位、`currentRoute()` 取到了真实 route
（`deepseek-official`）、`prepareCall()`/`call.stream()` 真的走到了 provider、失败文案可读、
`ctx.effect` 的清理器在宿主停止时被调用。

### 7.2 真机四步（待做）

1. 覆盖安装新 HAP（`tools/update-device.ps1`），**不要卸载**（会丢 el2 用户数据）。
2. 宿主日志应出现一行 `[dshm-meeting-ai] 已启用：…`（同 §7.1 的形态）。
3. 先在「设置 → 模型」配好凭据，然后在会议面板触发一次「AI 总结」/打开「EN 译文」，
   看设备上 `files/dsh/home/meeting-ai/` 是否出现 `<id>.done`（正例）或 `<id>.fail`（负例）。
4. 负向验证：把凭据删掉再触发一次，面板应显示「未生成 / 翻译失败」，目录里出现 `.fail`。

---

## 8. 已知边界与风险（如实登记）

1. **模型没登录 / 断网 ⇒ 两项能力都不可用**。面板必须把开关置灰或显示失败，不能假装有结果。
2. **把转写发给模型属于"用户数据出端"**：面板侧需要明确提示（建议：一次性的说明 + 设置里可关）。
   本插件只负责"发出去/收回来"，不做脱敏。
3. **并发上限 3（summary 1）**：极端情况下（会中同时有多条英译 + 会后总结）英译可能排队 ~1 条时长。
   ArkTS 侧英译只等 30s ⇒ 若出现英译超时，优先看是不是队列积压（宿主日志有每条的完成/失败行）。
4. **`.done/.fail` 没有"已读"标记**：靠 ArkTS 读后删除 + 插件的 6h/500 个兜底清理。若 ArkTS 某版忘了删，
   目录会缓慢增长到 500 个后开始淘汰最旧的。
5. **单实例假设**：两个 Host 进程指向同一个 `$DSH_HOME` 会重复处理同一批 `.req`（结果覆盖写、无害，但
   白烧 token）。端侧同一时刻只有一个宿主，风险仅限开发期手动起两个。
6. **`dshm-core.json` 的 `plugins` 数组里不会出现本插件**：那个数组只扫 `dsh-base`/`dsh-web-app` 两个
   bundle 的 patch 行，不扫 profile 的 `cordis.patch.yml`（pack-core 里已有同款说明）。"要出现在端侧
   「插件」页就必须先落到树上"这条因果**不成立**；本插件是 profile 行 ⇒ 能加载、但不进那个数组。
7. **真机验收未做**：本轮做了离线门禁 + 离线端到端（§7.1）+ 出包，**真机四步见 §7.2**；
   另外 `docs/HANDOFF.md` §2 里那份 HAP 仍是 `.75` 核心（本轮没有重出 HAP，下次出包时会带上 `.76`）。

---

## 9. 关掉它（三条路，都不动用户数据）

- 用户层 `$DSH_HOME/cordis.patch.yml` 写 `- id: dshm-meeting-ai` + `disabled: true`（端侧「插件」页的
  「停用」写的就是这个文件）；
- 环境变量 `DSHM_MEETING_AI=off`（调试用，`apply()` 直接返回）；
- 彻底移除：删掉 profile ⑭ 的 insert 行 + `tools/pack-core.mjs` 的清单项 + 插件目录，重打核心树。

---

## 10. 文件索引

| 文件 | 作用 |
|---|---|
| `hostcore/plugins/dshm-meeting-ai/package.json` | 包清单（ESM，peer `@deepseek-ai/dsh-llm: 0.2.1-rc.2`） |
| `hostcore/plugins/dshm-meeting-ai/lib/index.js` | cordis 行：`apply()` / `callModelViaLlm()` / `currentRoute()` / `readConfig()` |
| `hostcore/plugins/dshm-meeting-ai/lib/meeting-ai.js` | 纯逻辑：`createMeetingAiEngine()`、prompt、截断、协议载荷、原子写、过期清理 |
| `entry/src/main/ets/speech/MeetingAiBridge.ets` | ArkTS 侧对端（协议消费方，见 `docs/195`/`196` 的会议面板） |
| `tools/check-meeting-ai-plugin.mjs` | 本篇门禁（A/B/C 三层 + 2 对照臂） |
| `tools/pack-core.mjs` | `DSHM_PLUGIN_PACKAGES` 登记项 |
| `hostcore/profile/ondevice/cordis.patch.yml` | ⑭ insert 行 |
| `.github/workflows/gates.yml` | CI 接线（`check-meeting-ai-plugin`） |

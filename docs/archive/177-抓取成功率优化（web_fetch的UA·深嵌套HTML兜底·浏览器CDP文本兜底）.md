# 177 · 抓取成功率优化（web_fetch 的 UA · 深嵌套 HTML 兜底 · 浏览器 CDP 文本兜底）

> 用户 2026-10-17：「很多网站都有反爬，经常被封或者直接抓不到数据了，看下会话记录里面的报错，
> 继续优化一下提高抓取数据的成功率」。
> 做法：把会话里的真实失败逐条分诊（不是泛泛调参），按"能修的修、修不了的如实标注"推进。
> **未 commit / 未 push。**

## 1. 会话分诊（harness 会话 `session-0aed3274`，406 帧全解，125 次工具调用）

| # | 实录报错 | 定性 |
|---|---|---|
| ① | `web_fetch https://data.stats.gov.cn/easyquery.htm?...` → **HTTP 403** | 站点 WAF（下面②同源） |
| ② | `browser_text`（同一 URL）→ `403 Forbidden Client IP: 39.128.1.37 … reason:UrlACL` | **WAF UrlACL**：真浏览器打开同样 403 ⇒ 站点侧封禁，客户端无解 |
| ③ | `web_fetch https://www.stats.gov.cn/sj/ndsj/2025/indexch.htm` → HTTP 200 但 `[HTML content omitted: unable to convert safely.]` | **整页被转换器丢弃**（可修；本地复现见 §2.2：该页是 **frameset**，深度并未超限 ⇒ 触发的是 turndown 抛错那一支，两支共用同一句文案） |
| ④ | `web_fetch https://bulletin.cebpubservice.com/.../search/bulletin.html?...` → **HTTP 405** | 该检索端点要 POST；web_fetch 只有 GET（如实标注，走浏览器路） |
| ⑤ | `browser_text`（cebpubservice 检索页）→ `脚本注入失败（text，已重试一次）：api-timeout: executeScript` ×2 | 重页面 scripting 挂死（可修） |
| ⑥ | 早期 `browser_navigate` 的一串失败（无扩展 / attach 挂死 / 无活动网页） | 已由 docs/175 §6 与 docs/176 的 v4–v6 修复，本轮不计 |

## 2. 三项修复

### 2.1 web_fetch 的 User-Agent（profile 配置，一行生效）

- **根因**：`dsh-web-fetch-http` 默认 UA = `deepseek-harness/0.0.1 (+https://github.com/deepseek-ai)`
  （上游注释原文"never a browser disguise"）—— 对反爬中间件等于自报家门。
- **A/B 实测（只换 UA，同一时刻同一 URL）**：

  | URL | bot UA | 浏览器 UA |
  |---|---|---|
  | `https://www.xiaohongshu.com/explore` | **302**（被跳走） | **200** |
  | `https://www.zhihu.com/` | **403** | **302**（正常登录跳转） |
  | `https://data.stats.gov.cn/easyquery.htm…` | 403 | 403（WAF UrlACL，见 §1②） |

  （上表在**本机**与**设备自身网络**各跑一次，读数一致 —— 设备侧用 `/dshm-python` 桥的
  urllib 探针复现，`ssl._create_unverified_context()` 只因该探针不信任网络里的自签证书链。）
- **修法**：`hostcore/profile/ondevice/cordis.patch.yml` ⑪ 给 `web-fetch-http` 配
  `userAgent = 本机 ArkWeb 的真实 UA`（从宿主日志 `ua=` 字段读回：Chrome/144 + ArkWeb/7.0.0.109，
  不编造别的浏览器）。provider 的 Config 里 UA 是唯一这类可调项，其余上限保持默认。

### 2.2 深嵌套 HTML 的兜底纯文本（`dsh-tool-web` 补丁 ⑳）

- **根因**：`renderBody()` 在两条失败路径（词法深度 > `MAX_CONVERSION_DEPTH=512` / turndown 抛错）
  把**整页**替换成一句 "HTML content omitted"。深度上限必须保留（turndown 对深树超线性：
  depth 2000≈2s / 20000≈5s，会把事件循环占死），但"丢弃"不是唯一选项。
- **修法**：新增 `salvageDeepHtmlText()` —— 线性扫一遍标签（先整块删 `script/style/noscript/
  template/svg`，再删注释与标签）+ 反转义 `&nbsp;&lt;&gt;&quot;&#39;&amp;`，输出带
  `[Shallow text fallback …]` 前缀（如实告诉模型这是低保真兜底）。**再顺带**：页里有
  `<frame src=…>` 时把帧页地址前缀进输出（`Frameset srcs (fetch these directly): …`，≤5 条）——
  老政府站的 frameset 页从此有"下一步抓哪"的线索。**只改这两条失败分支**，正常路径一个字节不动。
- **真页面复现（从补丁后的树里原样切函数跑）**：
  `https://www.stats.gov.cn/sj/ndsj/2025/indexch.htm`（GB2312，860 字）→
  `exceedsConversionDepth=false`（即触发的是 catch 支）→ 兜底输出 209 字、无原始标签：
  `[Shallow text fallback …] Frameset srcs (fetch these directly): top.htm, left.htm, notepyrightch.htm, bottom.htm. 中国统计年鉴2025 此网页使用了框架…`
- **接线**：`tools/pack-core.mjs` 的 `patchWebToolDeepHtmlFallback()`（锚点不唯一即 `die()`），
  门禁 `tools/check-core-openharmony-patches.mjs` 第 28 处：标记 ×1 + 兜底函数在 +
  两条分支都改走兜底（×2）+ 上游字面量必须在树里 **×0**。

### 2.3 浏览器路径的 CDP 文本兜底（扩展 v7）

- **根因**：`get_text` 走 `chrome.scripting.executeScript`，个别重页面会让该 API **挂死**
  （§1⑤：8s×2 重试全超时 ⇒ 抓取失败）。
- **修法**：`background.js` 新增 `pageTextViaCdp()`（`chrome.debugger` 的
  `Runtime.evaluate`，`document.body.innerText` 清洗后取 20000 字），`get_text` 在 scripting
  失败后**自动转 CDP**，返回值带 `via:"script"|"cdp"` 便于诊断。
  ⚠ 只用于纯文本：CDP 在**主世界**求值、`buildTree()` 的 ref 表在隔离世界 ⇒ tree/click 的 ref
  不能跨世界复用（如实写进注释）。

## 3. 读数（beta 工作区）

| 项 | 读数 |
|---|---|
| 打包 | **+dshm.62**（收尾版，含 frameset 增强；dshm.61 是首个可跑盘）：40746 条目 / 94.9MB，resfile ↔ dist sha256 `215a6becf408b55f…` 一致（`check-resfile-core-zip` ✅） |
| 补丁门禁 | `check-core-openharmony-patches`：**229 passed / 0 failed**，28 处注入补丁齐全（新补丁 5 条判据全绿） |
| 设备树 | `cores/0.2.1-alpha.4+dshm.62/` 唯一；树内 `dsh-tool-web` 兜底标记 ×1 / frameset 增强 ×1 / 上游字面量 ×0；profile 里 `ArkWeb/7.0.0.109` 在 |
| UA 对照（设备网络） | 小红书 bot=302 / browser=**200**；知乎 bot=403 / browser=302（§2.1 表） |
| 构建装机 | `assembleHap` BUILD SUCCESSFUL → `hdc install -r` ✅ → 冷启动解包（`host-ready.json` 新 pid 25133） |
| 扩展 | v7（`0.7.0` / `dshm-host-bridge-7`）已部署到 `<下载>/com.dshm.dshmbeta/dshm-browser-ext-v7`（逐文件 sha256 双匹配） |

## 4. 边界与未竟（如实）

- **POST-only 端点（§1④ 405）**：web_fetch 只有 GET（上游形态）；这类站点走**浏览器路**
  （`browser_navigate` + `browser_text`，v7 后重页面也有 CDP 兜底）。
- **WAF UrlACL / IP 级封禁（§1①②）**：站点侧行为（真浏览器同样 403），客户端无法修复；
  模型应换路径（换 URL 变体 / 官方下载件 / 浏览器路）而不是重试同一 URL。
- **Accept-Language / Cookie**：本轮未加（无证据说它们是瓶颈）；如再遇 403 可按 §2.1 同一行
  config 继续加。
- **待验（需用户）**：扩展 v7 重新加载；模型侧一轮真实抓取（小红书/知乎类 UA 敏感站点 +
  统计局的深嵌套目录页）作为端到端验收。

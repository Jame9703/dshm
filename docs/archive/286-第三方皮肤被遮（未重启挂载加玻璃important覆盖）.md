# 286 · 第三方皮肤被遮（未重启挂载 + 玻璃 `!important` 覆盖）

> 日期：2026-10-29 18:25 ｜ 状态：**只读诊断，未改任何代码**
>
> 用户口径：「现在加了第三方皮肤也是不显示，看下为啥，完全被遮住了」
>
> 关联：[`283`](283-Web内沉浸光感（垫片实现·三次失败复盘与最终口径）.md)（垫片实现）、
> [`284`](284-深色主题复测（深色玻璃规则从未生效-html应为body）.md) / [`285`](285-深色玻璃复测通过（dark字段把空串属性误报成none）.md)（玻璃生效验收）。

---

## 0. 一页结论：**两个独立原因，后者即使重启也不会自动好**

| # | 原因 | 性质 | 是否要重启才暴露 |
|---:|---|---|---|
| **①** | 皮肤**装了但从未挂载** —— 宿主 18:12:00 启动，皮肤 18:21:46 才装，**差 585 秒**；安装器明确提示"重启应用后生效" | 操作时序 | 重启即解决 |
| **②** | 我们的玻璃规则 `background: rgba(...) !important` **直接覆盖列背景**，而皮肤的整套配色靠 `--dsw-alias-bg-base` 变量传导到列上 ⇒ **`!important` 把变量通路整个劫持** | **设计冲突** | **重启也不会好** |

**⇒ 只重启，皮肤可能依旧"不显示"（或只显示一半）。两件事必须一起处理。**

---

## 1. 皮肤装了什么、怎么生效

**包**：`@iasiv5/dsh-skins@1.5.19`（"DSH Web 皮肤插件：多套品牌皮肤侧栏热切换"）

**已正确安装并登记**（不是安装失败）：

```json
// dsh/home/profiles/ondevice/package.json
"dependencies": {
  "dshmarket": "github:dsh-market/dsh-market",
  "@iasiv5/dsh-skins": "1.5.19"
},
"dsh": { "profile": { "bundles": [ … , "dshmarket", "@iasiv5/dsh-skins" ] } }
```

**安装日志**（`node-output.log`，逐字）：

```text
[2026-10-29T10:21:46.210Z] [dshm-host]   [installer] 下载 @iasiv5/dsh-skins@1.5.19 …
[dshm-host]   [installer] bundle 型包已登记进 dsh.profile.bundles：@iasiv5/dsh-skins（重启应用后挂载生效）
[dshm-host] 插件安装完成：@iasiv5/dsh-skins@1.5.19（1 个包，重启应用后生效（bundle 型插件已登记，启动时随 profile 挂载））
```

### 1.1 皮肤的实现机制（`lib/client.js` 实读）

| 机制 | 证据 |
|---|---|
| 作用域 | `SCOPE = "body[data-dsh-meirenzhi-skin]"`（`:643` 附近；`bodyAttribute: "dshMeirenzhiSkin"`） |
| **核心手法：覆写主题变量** | `"--dsw-alias-bg-base": { light: ["250, 249, 246", 35], dark: ["18, 18, 26", 35] }`（`:3087`） |
| 变量挂载点 | `const body = document.body;` —— 挂在 `<body>` 上，靠 CSS 继承下发 |
| 背景图 | `${selector}::before{content:"";position:fixed;inset:0;z-index:-1;background-image:…}`（`:574`） |
| 第二层叠加 | `${selector}::after{content:"";position:fixed;inset:0;z-index:-1;background-image:…}`（`:580`） |
| 注入载体 | `document.head.appendChild(tag)`（`:561`、`:2132`） |

**关键**：皮肤**不直接给列写颜色**，而是改 `--dsw-alias-bg-base` 等变量，
再由官方规则 `_centerCol{background:var(--dsw-alias-bg-base)}` 把颜色**传导**到列上。

---

## 2. 原因①：皮肤从未挂载（时序）

| 事件 | 时刻 |
|---|---|
| 宿主启动（`host-ready.json` `startedAt`） | **18:12:00** |
| 皮肤安装完成 | **18:21:46** |
| **差值** | **585 秒（9 分 45 秒）** |

宿主 pid **31795 从 18:12 起未变** ⇒ **本次会话根本没有加载过皮肤**。

`node-output.log` 中 `grep -i skin` **除安装那 5 行外零命中** —— 没有任何"已挂载/已注册"
的运行期记录，与"未重启"完全吻合。

**⇒ 这一条重启即可解决。** 但请注意 §3：重启后未必就正常。

---

## 3. 原因②：玻璃 `!important` 劫持了皮肤的变量通路（重启也修不好）

### 3.1 冲突的两条规则

**皮肤的通路（靠变量继承）**：

```css
/* 皮肤在 <body> 上设变量 */
body[data-dsh-meirenzhi-skin] { --dsw-alias-bg-base: rgba(250,249,246,0.35) }   /* 示意 */
/* 官方规则消费该变量 */
pI_x6G_centerCol { background: var(--dsw-alias-bg-base) }
```

**我们的规则（硬编码 + `!important`）**，`WebApp.ets:1151-1156`：

```js
'html.dshm-glass-top .dshm-glasscol, html.dshm-glass-top .dshm-glassside{'
  + 'backdrop-filter:blur(40px) saturate(180%);'
  + 'background:rgba(214,223,240,0.86) !important;'   // ← 直接写死颜色，并 !important
  + 'box-shadow:inset -1px 0 0 rgba(120,140,180,0.28)}'
```

### 3.2 为什么皮肤必败

```text
皮肤改的是「变量」→ 需要官方规则 var(--dsw-alias-bg-base) 去消费 → 才落到列上
我们的规则直接改「列本身的 background」，且带 !important
```

CSS 层叠顺序：**`!important` 的声明胜过任何普通声明**，无论皮肤把变量改成什么，
`.dshm-glasscol` 的 `background` 都被我们这条 `!important` **钉死**。
皮肤的变量即便正确下发，**在这一层被完全短路**。

### 3.3 视觉结果 —— 正是用户说的"完全被遮住了"

| 层 | 谁画的 | 是否可见 |
|---|---|---|
| 皮肤背景图（`#root::before/::after`，`z-index:-1`） | 皮肤 | 在**根容器背后** |
| 列的 background | **我们的 `rgba(214,223,240,0.86)`（86% 不透明）** | **盖在最上层** |

皮肤背景图 `z-index:-1` 在 `#root` 背后，而我们的列背景**不透明 86%** 铺在列上 ——
**透过去只剩 14%**，背景图被压到几乎不可见。**这就是"完全被遮住"的机制。**

> 附带：即便玻璃是 0.72 或更低，皮肤也只是"隐隐透出"，**永远达不到皮肤设计的观感**
> —— 因为皮肤假设的是"列背景 = 它给的变量值"，而不是"列背景 = 别人写死的半透明白"。

---

## 4. 判断：谁该让路？

**这是产品取舍，不是纯技术 bug，必须你来定：**

| 方案 | 做法 | 优点 | 代价 |
|---|---|---|---|
| **A. 皮肤优先（推荐）** | 检测到皮肤作用域 `body[data-dsh-meirenzhi-skin]`（或任一 `data-dsh-*-skin`）时，**玻璃规则整体不注入** | 皮肤完整呈现；两者不打架 | 该皮肤下无玻璃 |
| **B. 玻璃优先** | 现状 | 玻璃始终可见 | 皮肤形同虚设（当前状态） |
| **C. 融合** | 玻璃底改成 `color-mix(in srgb, var(--dsw-alias-bg-base) 86%, transparent)`，**让皮肤变量参与**玻璃底色计算 | 皮肤色调能透出来，玻璃也还在 | 需要验证 ArkWeb 对 `color-mix` 的支持 |
| **D. 分层** | 玻璃只做 `backdrop-filter`，**不写 `background`**（或写到很低不透明度） | 皮肤底色完全保留，玻璃只负责模糊 | 白底上模糊看不出（回到 282 的老问题） |

**我的建议**：**A 作为默认**（皮肤是用户显式选择，优先级应高于自动玻璃），
**C 作为可选增强**（若产品要"皮肤 + 玻璃"共存）。

---

## 5. 开发端落实清单

| # | 事项 | 判据 | 优先级 |
|---:|---|---|---|
| 1 | **先重启应用**，让皮肤真正挂载 | 日志出现皮肤挂载记录；`<body>` 上有 `data-dsh-meirenzhi-skin` 等属性 | **P0（立即可做）** |
| 2 | 重启后**再取一次探针**，确认皮肤与玻璃谁压倒谁 | 见 §6 判据 | **P0** |
| 3 | 按 §4 拍板方案并实现（推荐 A：皮肤存在时让玻璃让路） | 皮肤生效时玻璃规则不注入 | **P1** |
| 4 | 若选 C：验证 `color-mix` 在 ArkWeb 的支持 | `CSS.supports('color','color-mix(in srgb,red 50%,transparent)')` | P2 |
| 5 | 玻璃规则加"皮肤共存"验收用例（避免再次回归） | 门禁里加一条：存在 `data-dsh-*-skin` 时玻璃规则应让路 | P2 |

### 5.1 判据：怎么确认"皮肤真的挂上了"

```bash
cd /data/storage/el2/base/haps/entry/files

# ① 宿主是否重启过（startedAt 应晚于 18:21:46）
grep -o '"startedAt":"[^"]*"' dsh/home/host-ready.json

# ② 日志里应出现皮肤挂载（不是只有 installer 那几行）
grep -a -i "skin" node-output.log | tail -10

# ③ 探针里 body 属性（需先把 dark 字段修好，见 docs/285 §3）
grep -a "glass diag" diag-web-console | tail -1
```

**期望**：重启后日志出现 `@iasiv5/dsh-skins` 的挂载/注册记录，
且 `<body>` 上出现 `data-dsh-meirenzhi-skin`（具体名以皮肤配置为准）。

---

## 6. 一句话交接

**皮肤"完全不显示"有两个独立原因**：
**① 它压根没挂载** —— 宿主 18:12 启动、皮肤 18:21:46 才装（差 585 秒），安装器自己写明"重启应用后生效"；
**② 即使重启，我们的玻璃也会把它盖住** —— 玻璃用 `background:rgba(214,223,240,0.86) !important`
**直接钉死列背景**，而皮肤的整套配色靠 `--dsw-alias-bg-base` **变量传导**到列上，
`!important` 把这条通路**整体短路**，皮肤背景图（`z-index:-1`，在根容器背后）只能透过 14% 露出来。

**先重启验证皮肤本身是否正常；再决定玻璃是否该在皮肤存在时让路（推荐让路）。**

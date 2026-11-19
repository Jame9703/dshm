# 284 · 深色主题复测：深色玻璃规则从未生效（`html[...]` 应为 `body[...]`）

> 日期：2026-10-29 17:35 ｜ 状态：**只读诊断 + 一处自我更正**，未改任何代码
>
> 用户口径：「切到深色模式了，再复测然后写进文档开发端继续落实，我肉眼感觉依旧没有生效，
> 沉浸光感更是一点边不沾」。
>
> 关联：[`282`](282-Web内沉浸光感只读诊断（标记选择器内核全通过卡在白底与旧包）.md)（亮色诊断，本文是它的深色续篇）、
> [`283`](283-Web内沉浸光感（垫片实现·三次失败复盘与最终口径）.md)（开发端实现与验收清单）、
> [`196`](196-会议面板UI优化（历史会议与沉浸光感按钮）.md)（染蓝边界）。

---

## 0. 一页结论

| 项 | 结果 |
|---|---|
| 亮色材质上机了吗 | **是**（`saturate(1.8)` / `rgba(214,223,240,0.86)`，`docs/282` 的 P0 已闭环） |
| 深色材质生效了吗 | **否 —— 从未生效过一次** |
| 根因 | 深色规则写成 **`html[data-ds-dark-theme]`**，而官方把该属性挂在 **`<body>`** 上 ⇒ 选择器**永不匹配** |
| 证据强度 | 官方 18 处深色选择器**全是 `body[...]`**，`html[...]` **0 处** |
| 用户观感 | **正确**。深色下两列是**亮色块**（合成 `rgb(187,195,210)`）压在暗界面（`rgb(21,21,23)`）上，割裂刺眼 |
| 顺带更正 | 我曾在对话中说"原生材质已移除"，**这是错的**（源于 toybox `grep -c` 静默漏报）；原生 `systemMaterial` 15 处仍在 §§4 |

---

## 1. 复测动作与原始读数

**动作**：用户将系统切到深色主题，探针（`diagGlass`，每 60s 一拍）继续产出。

**切深色后 3 条最新读数（原始，未加工）**：

```text
2026-10-29T09:28:49.426Z glass diag: cssSupports=yes glassTop=13 cols=1 computedBackdrop=blur(40px) saturate(1.8) computedBg=rgba(214, 223, 240, 0.86)
2026-10-29T09:29:49.421Z glass diag: cssSupports=yes glassTop=13 cols=1 computedBackdrop=blur(40px) saturate(1.8) computedBg=rgba(214, 223, 240, 0.86)
2026-10-29T09:30:49.420Z glass diag: cssSupports=yes glassTop=13 cols=1 computedBackdrop=blur(40px) saturate(1.8) computedBg=rgba(214, 223, 240, 0.86)
```

**关键判读**：

- `computedBg` 恒为 **`rgba(214, 223, 240, 0.86)`** —— 这是**亮色**材质；
- 若深色规则生效，此处必须是 **`rgba(38, 44, 58, 0.82)`**；
- **它从头到尾没出现过一次。** 深色材质形同虚设。

**主题切换确实到达了 Web**（不是"没收到通知"）：

```text
node-output.log 中 method name 统计：
  1224 method name: platformPcMode
  1224 method name: platformForm
     2 method name: onThemeMode      ← 主题变更通知，确实发了
```

⇒ **不是通知没到，是我们的选择器对不上号。**

---

## 2. 根因：选择器写错元素（决定性）

### 2.1 垫片写法

`entry/src/main/ets/pages/WebApp.ets:1156-1157`：

```js
+ 'html[data-ds-dark-theme].dshm-glass-top .' + GLASS_COL_CLASS + ','
+ 'html[data-ds-dark-theme].dshm-glass-top .' + GLASS_SIDEBAR_CLASS + '{'
+ 'background:rgba(38,44,58,0.82) !important;'
+ 'box-shadow:inset -1px 0 0 rgba(150,170,210,0.22)}'
```

### 2.2 官方写法（权威）

`@deepseek-ai/dsh-client-ui-theme/lib/client.js` 实读：

| 写法 | 出现次数 |
|---|---|
| **`body[data-ds-dark-theme]`** | **18** |
| `html[data-ds-dark-theme]` | **0** |

官方样本（节选，均以 `body` 开头）：

```css
body[data-ds-dark-theme]{--dsw-alias-bg-base: …}
body[data-ds-dark-theme] [data-menu-material]{--dsw-elevation-stroke-color: …}
body[data-ds-dark-theme]{--dsw-linear-gradient-think: …}
body[data-ds-dark-theme]{--shiki-token-constant:#4dabf7; …}
html[data-platform=darwin] body[data-ds-dark-theme]{--dsw-specific-menu: …}
```

**`data-ds-dark-theme` 挂在 `<body>` 上。** 垫片写成 `html[data-ds-dark-theme]`
⇒ 要求 `<html>` 上也有这个属性 ⇒ **永远不成立**。

### 2.3 为什么前几轮全部漏掉

| 测试主题 | 命中的规则 | 探针表现 | 是否发现问题 |
|---|---|---|---|
| 亮色（282、以及 283 实现时） | `html.dshm-glass-top …`（**不带** `[data-ds-dark-theme]`） | `cols=1`、`computedBg` 有值 | **看不出问题，一路绿灯** |
| **深色（本轮）** | 该命 `html[data-ds-dark-theme]…`，**不匹配** | 值仍是亮色那份 | **只有这一步能照出来** |

⇒ 深色分支是**唯一使用 `html[...]` 前缀的规则**，也是**唯一从未被测过的分支**。
`docs/282` §9 建议「优先在深色主题下验收」正是为此，本轮验证了它的必要性。

---

## 3. 这如何解释用户观感（量化）

深色主题下，官方通过 `body[data-ds-dark-theme]` 把画布换成深色；
但两列上铺的仍是**亮色材质**（因选择器不匹配，深色块从未覆盖它）：

```text
深色画布 rgb(21, 21, 23) 上铺 rgba(214, 223, 240, 0.86)
→ 合成 rgb(187, 195, 210)      ← 一块亮色，在暗界面里非常刺眼

若深色规则能命中，本该是：
rgba(38, 44, 58, 0.82) 叠深底
→ 合成 rgb(35, 40, 52)         ← 与暗底接近，才是玻璃观感
```

**用户看到的是：整个界面变暗了，唯独侧栏列和会话列还是一大块亮灰蓝。**
既不像玻璃，也破坏了深色主题一致性 —— 正是「一点边不沾」的直观来源。

> 这也说明：**当前状态比"完全没有玻璃"更糟**。没有玻璃时两列跟随主题（深色下是深色）；
> 现在它们是固定的亮色块，**深色模式下反而成了视觉伤疤**。

---

## 4. 自我更正：原生材质**并未移除**

我在本轮对话中曾口头断言"`systemMaterial` / `dialogMaterial` 在 `WebApp.ets` 里 0 命中，
原生侧材质已被移除，沉浸光感只剩 Web 垫片一条腿"。

**该断言是错的。** 复核（用 grep 工具，非 shell `grep -c`）：

`WebApp.ets` 共 **15 处**命中：

| 行 | 内容 |
|---|---|
| 75 | `import { …, dialogMaterial, shellMaterial } from 'platform';` |
| 3663 | `private topBarShellMaterial: uiMaterial.ImmersiveMaterial \| undefined = shellMaterial();` |
| 3972 / 4002 / 4081 | `systemMaterial: dialogMaterial(),`（三处弹窗） |
| 6069 / 6074 | `const material = dialogMaterial();` … `systemMaterial: material` |
| 6258 / 6259 | `.backgroundColor(…Color.Transparent)` + `.systemMaterial(this.topBarShellMaterial)` |

⇒ **原生侧（280 那套）与 Web 垫片（283 这套）两条腿都在**，
"沉浸光感一点边不沾"是**深色选择器失效**造成的，**不是原生材质被删**。

**失误成因（必须记下来）**：
`grep -c "systemMaterial" file` 在本机 toybox 下返回 **0**，而 `grep -rl` 同一文件却命中，
工具型 grep 更是 15 处 —— **toybox grep 静默漏报**（`docs/278` §1.2 已立此纪律，
本轮我又踩了一次）。**凡涉及"是否存在"的判定，一律用 grep 工具，不得用 shell `grep -c` 的零命中作证。**

---

## 5. 开发端落实清单

> 我未做任何改动（只读口径）。以下为建议。

### 5.1 P0 · 修选择器（一行级改动）

**把深色规则的 `html[data-ds-dark-theme]` 改成 `body[data-ds-dark-theme]`**：

```js
/* 现在（永不匹配） */
+ 'html[data-ds-dark-theme].dshm-glass-top .' + GLASS_COL_CLASS + ','
+ 'html[data-ds-dark-theme].dshm-glass-top .' + GLASS_SIDEBAR_CLASS + '{'

/* 应改为（与官方 18 处一致） */
+ 'html.dshm-glass-top body[data-ds-dark-theme] .' + GLASS_COL_CLASS + ','
+ 'html.dshm-glass-top body[data-ds-dark-theme] .' + GLASS_SIDEBAR_CLASS + '{'
```

> 写法说明：`.dshm-glass-top` 仍锚在 `html`（我们自己的标记），
> `[data-ds-dark-theme]` 锚在 `body`（官方事实）。两者用**后代组合符**连接。

**风险提示**：若 `<body>` 与 `<html>` 的层级关系在任何页面态下不同（如 iframe），
建议同时保留 `html[data-ds-dark-theme]` 作为兼容分支，构成双选择器。

### 5.2 P0 · 深色材质要重声明 `backdrop-filter`

当前深色块**只改 `background` 与 `box-shadow`，没有重声明 `backdrop-filter`**
（`WebApp.ets:1156-1160`）。因为亮色块已单独声明该属性、且选择器互斥，
**修好 `body` 前缀后此点不成问题**；但**若将来拆成两个独立样式块，必须各自声明**，
否则深色块会丢失 `blur`。建议现在就补上，消除隐患：

```js
+ 'backdrop-filter:blur(40px) saturate(180%);-webkit-backdrop-filter:blur(40px) saturate(180%);'
```

### 5.3 P0 · 验收必须**亮暗各一轮**（本轮最大教训）

`docs/283` §4 的验收清单只验了亮色。**建议加一条硬性判据**：

```bash
# 亮色下取一次
grep -a "glass diag" ~/diag-web-console | tail -1
#   期望 computedBg 含 "214, 223, 240"

# 切深色后再取一次
grep -a "glass diag" ~/diag-web-console | tail -1
#   期望 computedBg 含 "38, 44, 58"   ← 本轮这一条不成立，就是缺陷
```

**判据**：同一会话内，深色读数必须与亮色读数**不同**；
若两者相同 ⇒ 深色分支未生效。

### 5.4 P1 · 探针补「当前主题态」字段（本轮痛点的直接解药）

`diagGlass()` 目前**不输出主题状态**，所以只能靠 `computedBg` 反推。
建议在探针里补两项：

```js
+ ' dark=' + (document.body && document.body.hasAttribute('data-ds-dark-theme') ? 'yes' : 'no')
+ ' bodyAttr=' + (document.body ? (document.body.getAttribute('data-ds-dark-theme') || '-') : 'no-body')
```

有了这两项，**"规则没命中"与"属性没挂上"当场可分**，不必再间接推理。

同时补 `docs/282` §9 已建议但未落地的四项：`navigator.userAgent`、
命中元素 `getBoundingClientRect()`、`CSS.supports('-webkit-backdrop-filter',…)`、button `className`。

### 5.5 P1 · 染蓝/刺眼边界（深色修复后仍需盯）

亮色材质 `rgba(214,223,240,0.86)` 叠白 = `#dbe3f2`（通道差 R-30 G-23 B-9）；
但它叠在**深色**画布上 = `rgb(187,195,210)`，**这就是当前刺眼的原因**。
修好深色分支后，深色下会变成 `rgb(35,40,52)`（正常）。
**请一并检查：主题切换瞬间是否有一帧"亮块闪一下"**（属性更新与样式重算的时序差）。

---

## 6. 复现命令

```bash
cd /data/storage/el2/base/haps/entry/files

# 1) 切深色后应变化的读数（本轮实际不变）
grep -a "glass diag" diag-web-console | tail -3

# 2) 官方深色选择器写法（权威，必须 body）
grep -o "body\[data-ds-dark-theme\]" \
  dsh/cores/0.2.1-rc.4+dshm.97/node_modules/@deepseek-ai/dsh-client-ui-theme/lib/client.js | wc -l
# → 18

grep -o "html\[data-ds-dark-theme\]" \
  dsh/cores/0.2.1-rc.4+dshm.97/node_modules/@deepseek-ai/dsh-client-ui-theme/lib/client.js | wc -l
# → 0

# 3) 垫片当前写法（错）
sed -n '1156,1157p' ~/data/DSHM-deveco-workspace/entry/src/main/ets/pages/WebApp.ets

# 4) 主题通知确实到达（证明不是通知问题）
grep -o "method name: [a-zA-Z]*" node-output.log | sort | uniq -c | sort -rn | head
# → onThemeMode 2 次

# 5) 原生材质仍在（15 处；勿用 shell grep -c）
```

---

## 7. 一句话交接

**亮色已修好（`saturate(1.8)` / `214,223,240` 上机），但深色规则把 `data-ds-dark-theme` 锚在
`html` 上，而官方 18 处全锚在 `body` ⇒ 深色材质一次都没生效，深色模式下两列变成刺眼的亮色块
（合成 `rgb(187,195,210)` 压 `rgb(21,21,23)` 暗底），这正是"一点边不沾"的实体。
修法是一行级：`html[data-ds-dark-theme]` → `html.dshm-glass-top body[data-ds-dark-theme]`，
并把"亮暗各取一次探针、两次读数必须不同"写进验收清单。**

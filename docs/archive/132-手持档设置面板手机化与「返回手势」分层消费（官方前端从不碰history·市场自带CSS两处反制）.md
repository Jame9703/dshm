# 132 · 手持档「设置面板手机化 + 市场多列」与「返回 / 手势」的分层消费

> 本轮用户的两句话（原话）：
>
> 1. 「改一下设置里面的UI布局，以适配手机端横向比较窄的问题，打开设置全盘展示，设置菜单项目放在UI
>    顶部横置，点击每项在上方展示和修改，适配各种手机屏幕尺寸，比如插件市场和皮肤市场的预览列表
>    每行显示2个，手机屏幕宽的有余量可以显示3个，折叠屏显示4个，这样去设计，看看怎么落实」
> 2. 「移动端有手势操作，响应左右手势返回上一页，现在左右手势划一下直接回到桌面了」
>
> 两件事都在**同一份文件**里落地：`entry/src/main/ets/pages/WebApp.ets`（纯 ArkTS 垫片 + 原生
> 返回链）。**`hostcore/**` 与 `hostcore/core-recipe.json` 一字未动 ⇒ `coreVersion` 不升**
> （仍 `0.2.1-alpha.2+dshm.29`，见 `docs/131`）。新增门禁 `tools/check-handheld-back.mjs`。

> **⚠️ 已收窄（2026-10-13，见 `docs/151`）**：本档落地的「设置面板手机化」**只对直板手机**成立；
> **折叠屏**（`isFoldableDevice()` 为真）与平板一样走**官方竖排**设置面板，但**仍属手持档**
> （抽屉 / ⊞ / 朝向跟随 / 小白条沉浸 / 市场多列照旧）——即折叠屏拿 `dshm-handheld`、
> **不拿** `dshm-phone`。下文凡写「手持档」处，**设置面板那一条**请按此口径读
> （其余手持档能力不受影响）。原判据是两档（`phone`/`tablet`），`docs/151` 扩成四档。

---

## 0. 一句话结论

| # | 请求 | 结论 | 根因（都不是"我们的界面写错了"） |
|---|---|---|---|
| 1 | 设置面板手机化 | 已落地并真机验 | 官方那套设置面板是按**桌面竖向 188px 侧栏**设计的；手持档屏幕高度/宽度都不够 |
| 1b | 市场预览多列 | 已落地并真机验 | 插件自己写了**窄屏摞一列**的 CSS，且其 JS 分栏与 CSS 分栏**互相打架** |
| 2 | 返回 / 手势 | 已落地并真机验（三种状态各一条） | 官方 web 前端是纯 SPA 且**从不碰 history**（`pushState` / `replaceState` 各 **0 处**）⇒ 原生 `accessBackward()` **恒假** ⇒ 返回直接落到系统默认（最小化回桌面） |

---

## 1. 请求 1 —— 设置面板手机化（`SETTINGS_SHIM_JS`，`WebApp.ets:1039`）

### 1.1 官方设置面板的真实结构（先把"改的是什么"钉死）

核心树里那份设置 UI（`@deepseek-ai/dsh-client-ui-settings-general/lib/client.js`）用 CSS Modules
哈希前缀（本轮实测前缀 `VOzbGW_`），结构与类名是：

```
overlay                       ← 居中弹窗的容器（portal 直接父）
 ├ mask[aria-hidden=true]     ← 点击外部关闭用的遮罩
 └ panel[data-shortcut-modal="settings"]
    ├ nav      (navTitle + navList)     ← 左侧竖向导航（188px）
    └ div      (header + actions/close + options)
```

- `navCell[aria-current="true"]` = 选中项（**官方自己的选中态属性，别自己造**）；
- 真正的滚动容器是 `.options`（`flex:1;min-height:0;overflow-y:auto`）；
- **`.nav` 不该消失** —— 它只是"在手机上没有位置"，不是"该被隐藏"。

### 1.2 做法（四条，都写进垫片头注）

1. **侧栏列 → 顶部横向胶囊 tab 条**：`nav` 从"占一列"改成"占一行"，`navList` 变
   `overflow-x:auto` 的横排胶囊；选中态沿用官方的 `[aria-current="true"]`。
2. **面板铺满视口**：`width:100vw` + `height:100%` + 去圆角。
3. **覆盖层必须钉到视口**（`position:fixed;inset:0`）：官方那层 `.overlay` 是"居中弹窗"的容器，
   不改它的话面板的 `height:100%` 落在**没有定高的父**上 ⇒ 面板跟着内容长高 ⇒ **整块面板能被拖动，
   顶部横条会被拖走**（第一版真机就是这个症状）。
4. **fail-closed**：`nav` 与内容 div **各命中一个**才挂 `dshm-set-ready`；所有 CSS 规则**全部**以
   `html.dshm-handheld .dshm-set-panel.dshm-set-ready` 起头 ⇒ 结构没认全（换版本、插件改结构）时
   整套规则**一条都不生效**，退回官方原样，而不是叠出一套半成品布局。

读数：`globalThis.__DSHM_SETTINGS__.state()` ⇒ `'ready' | 'raw' | 'none'`
（`raw` = 面板在但结构没认全 ⇒ 该去看官方包是不是改了结构）。

### 1.3 ⚠️ 市场自带 CSS 的反制（本轮真机查出来的坑，必读）

dshmarket 自己的 CSS 里有一条：

```css
@media (max-width:560px){ [role=dialog]:has([data-dsh-market-root]) > nav{display:none} }
```

它判的就是"**设置面板里嵌着市场**"这件事：手机档宽度必然 ≤560px ⇒ 命中 ⇒ **把顶部那条 tab 条
整条藏掉**（用户再也切不了页签）。修法是**显式写死 `display:flex`**：

```css
html.dshm-handheld .dshm-set-panel.dshm-set-ready > .dshm-set-nav{display:flex; ...}
```

本选择器比它**高一档**（类 + 类 + 子选择器 vs 属性 + `:has`），写回 `flex` 即可。
证据：修前 s17（插件市场档下**没有**顶部条）／修后 s22（顶部条回来，且卡片仍是 2 列）。

> **这一条要记住的是方法论**：给别人的界面写覆盖样式时，**不能只写"我要的"**，还要找
> "对方在窄屏下写了什么来对抗我" —— 对方的 `@media` 里可能正好有一条针对本场景的 `display:none`。

---

## 2. 请求 1b —— 市场预览多列网格（`HANDHELD_GRID_SHIM_JS`，`WebApp.ets:1216`）

### 2.1 两条修法（缺一不可）

| # | 修法 | 为什么必须两条 |
|---|---|---|
| A | **包装 `window.matchMedia`**，手持档让 `(min-width:681px)` 恒真 | dshmarket 的 `useMediaWide()` 用这个查询决定"要不要按两列瀑布流渲染"；不改它，插件 JS 只渲染一列，CSS 再改也没东西可分 |
| B | 扫 `style[data-plugin-css]`，把**窄屏 @media 块里的**分栏声明按元素宽度回正 | 插件自己的 CSS 在窄屏下把网格压成一列（`.masonry` 甚至**JS 分了两列、CSS 却摞成一列**，插件注释里自己写着"两边打架会出错"） |

### 2.2 只挑"对称分栏"（回正判据）

- `grid-template-columns` 且值**对称**（`1fr` / `minmax(0,1fr)` / `repeat(n, minmax(0,1fr))`）
  ⇒ 按元素自身宽度重写成 `repeat(N, minmax(0,1fr))`；
- `flex-direction:column` 且**同一选择器的基准规则声明了 `display:flex` 又没写 `flex-direction`**
  ⇒ 说明这条是"窄屏把横向容器摞起来"，回正成 `row`；
- **非对称分栏一律跳过**（`minmax(0,1fr) auto` 是工具栏、`138px minmax(0,1fr)` 是详情头，
  改成等分就散架）；`repeat(var(--x),…)` 这类"插件自己按宽度算的"也跳过。

### 2.3 不写死一个哈希类名

官方与插件的类名都是 CSS Modules 哈希（`.nUhMVa_grid` / `.VqXecW_discoveryGrid`），换版本就变。
垫片只认"**插件自己写的那条窄屏规则**"这一事实，选择器**从它自己的 CSS 文本里读**。
作用域限定在两个市场根（`[data-dsh-market-root]` / `[data-dsh-skin-market]`，都是插件 JSX 里的
字符串字面量、压缩不改名）**内部** ⇒ 设置面板其它页签（账户的两栏表单、模型列表、内置插件清单）
一个字节都不碰。

### 2.4 列数口径（用户原话：手机 2、宽的有余量 3、折叠屏 4）

按**元素自身宽度** W：`W<480 ⇒ 2`；`480≤W<900 ⇒ 3`；`W≥900 ⇒ 4`；且**不超过子项个数**。

读数：`globalThis.__DSHM_GRID__.state()` ⇒ `'off'`（非手持档）或
`'root=1 rules=2 cols=3 row=1'`（市场根数 / 认出的窄屏规则数 / 已改列数元素数 / 已回正成横向的元素数）。

### 2.5 ⚠️ 两个 CSS 解析器坑（同一个下午踩的，都写进代码注释了）

1. **规则体必须括号配对找结尾**：用 `indexOf('}')` 找第一条规则的结尾，遇到 `@keyframes`
   这种"顶层夹嵌套块"就会**读串位**（把后面的规则当成本条规则体的一部分）。
2. **顶层要逐个配对，不能整块当一条规则体**：`@media` 块内部还有自己的嵌套，整块读会把
   里面所有规则粘成一条。

---

## 3. 请求 2 —— 返回 / 手势的分层消费（本轮核心）

### 3.1 根因（已坐实，且**与本仓库无关**）

官方 web 前端是纯 SPA 且**从不碰 history**：

```
grep pushState  → 0 处（全仓，含 dsh-web-frontend 与全部已装插件）
grep replaceState → 0 处
```

⇒ Web 自己的后退栈**恒空** ⇒ 旧 `onBackPress()` 的 `controller.accessBackward()` **恒假**
⇒ 返回落到系统默认（**把应用最小化回桌面**）。也就是说：**开着设置面板 / 市场 / 抽屉时划返回，
也一样直接退出** —— 用户看到的"划一下直接回桌面"就是这个。

### 3.2 修法一：网页侧回答"这一记返回该关掉什么"（`BACK_SHIM_JS`，`WebApp.ets:1547`）

`globalThis.__DSHM_BACK__.consume()` 的顺序**固定**为：

1. **顶层可见浮层** —— 官方与插件都用 react-aria 的 Overlay 栈，落点属性各不同
   （设置面板 `data-shortcut-modal`，菜单 / 对话框 `role=menu|dialog|listbox`）。
   关它走**官方自己的关法**：朝浮层内的 `[data-modal-autofocus]`（退化取浮层自身）派发一个
   `KeyboardEvent('keydown',{key:'Escape'})` —— react-aria 在 `document` 上听 `Escape` 并调
   顶层 `close()`，与真人按 Esc **等价**，不用猜关闭按钮长什么样。
   两个细节：`keyCode` / `which` 是**只读遗留属性**（构造参数喂不进去）⇒ 用
   `Object.defineProperty` 显式补 `27`（老式判据只认它）；派发点取浮层内自动聚焦点 ⇒
   **不会把 Esc 误交给编辑器**（那里 Esc 是"取消编辑"）。
2. **移动端抽屉**（`__DSHM_SIDEBAR__.state()==='expanded'`）—— 直接 `toggle()` 收起。
3. 都没有 ⇒ 回 `'none'`，**由原生补做系统默认（最小化）**。

**"绝不吞返回"**（`docs/50` 的 E94 立的规矩）：只有 `overlay` / `drawer` 两个裁决算"网页已消费"。
Esc 之后 **320ms 回查**顶层浮层是否换人/消失；**还是它**说明这层不吃 Escape（插件自绘的 dialog）
⇒ 调 `__DSHM_BRIDGES__.requestSystemBack()` 把系统默认补上 —— 宁可退回"退出到桌面"，
**也不能让返回变成没反应**。

### 3.3 修法二：原生侧同步吞下、异步裁决（`WebApp.ets:3153`）

`onBackPress()` 是**同步契约**（要立刻回 `true/false`），而"现在有没有可关的浮层"只有 DOM 知道
（`runJavaScript` 是异步的）⇒ 先**同步吞下**这记返回，再按网页回话决定要不要补系统默认：

```
onBackPress() {
  accessBackward() → backward(); return true;   // ① 仍先走 Web 自己的后退栈（给将来兜底）
  if (!this.handheld) { return false; }         // ② PC / 2in1 早退 ⇒ 行为逐字不动
  this.consumeWebBack(); return true;           // ③ 手持档：先吞，回调再裁决
}
```

四条路收敛到 `finishWebBack()`，由 `backSettled` 去重（**不会既关了面板又最小化**）：
网页回话 / 桥缺失 / 表达式抛错 / **1200ms 兜底超时**。
兜底取 1200ms 而不是更短：宁可晚一点，也不能在"网页其实已经关掉面板"之后**又叠一次最小化**
（`runJavaScript` 走本地 IPC，正常几十毫秒内回调）。

`moveAbilityToBackground()` **全文件只允许出现一次**（在 `minimizeToBackground()` 里）——
它只在手机/平板有效，其它设备回 `16000061`。

### 3.4 诊断读数（下一次真机排障全靠这两行）

| 落点 | 内容 |
|---|---|
| `files/diag-web-console` | 每拍一行 `[dshm-back] consume: overlay div[shortcut=settings][role=dialog].VOzbGW_panel (visible overlays=1)` / `consume: drawer` / `consume: none`；含浮层**身份**与**可见层数** |
| `files/diag-web-back` | `finishWebBack()` 收口时写 `<ISO 时间> <裁决>`，**不随冷启动截断** ⇒ 可跨多次返回回看整条序列 |

`describe()` / `countOverlays()` 是**为下一次排障加的**：没有它们只能看到 `consume: overlay`
这种无从追问的行。

---

## 4. 门禁（新增 `tools/check-handheld-back.mjs`）

- **判据三条**：分层顺序（浮层在抽屉之前）／绝不吞（只有 overlay/drawer 算消费）／
  **PC 逐字不动**（新链只在 handheld 上跑；`moveAbilityToBackground` 全文件只 1 次且在 `minimizeToBackground` 内）。
- **对照臂三条**（内存变异，必须各自判红）：① 删掉 `handheld` 早退；② `consume()` 不再读顶层浮层；
  ③ `methodList` 里删掉 `'requestSystemBack'`（桥静默失效）。
- 读数：**29 passed / 0 failed**，对照臂三条全部有效（各 `fail=1`）。
- 离线门禁：只读仓库内文件，**不需要核心树、不需要设备** ⇒ 已加进 `.github/workflows/gates.yml`
  与 `AGENTS.md` 的"必跑门禁"清单（CI 计数 **18 → 19**）。

> 本轮先踩的坑：第 ④ 条断言写成 `back.indexOf('consumeWebBack()') < back.indexOf('return true;')`，
> 而切片区里**第一个** `return true;` 属于上面那段 `accessBackward()` 分支 ⇒ 断言本身是错的
> （**不是产品代码错**）。改成断言真实形态 `consumeWebBack();\n    return true;`（两行紧邻）后 rc=0。
> 教训：`indexOf` 取序的断言要**限定切片区起点**，否则会被"更早出现的同名片段"命中。

---

## 5. 真机验收（手机 `62T0225B18039433`，1280×2832，`1vp=3.5px`）

装机走唯一入口 `tools/update-device.ps1`（`hdc install -r`）：`home` 指纹 `links=8 size=3440`
**装前=装后**，核心树 `0.2.1-alpha.2+dshm.29` 在。

### 5.1 返回链（`uitest uiInput keyEvent 2`，逐状态）

| 起始状态 | `diag-web-back` | 画面 | 判定 |
|---|---|---|---|
| 抽屉展开 | `drawer` | 抽屉收起、**应用仍在前台** | ✓ |
| 设置面板打开 | `overlay` | 面板关掉、**应用仍在前台**（抽屉仍在，符合层序） | ✓ |
| 根状态（无层） | `none` | 系统默认 ⇒ 回桌面 | ✓ |

### 5.2 设置面板手机化

- 结构：全屏铺满 + **顶部横向胶囊 tab**（通用设置 / 模型 / 内置插件 / Ag…），内容在下方；
- 插件市场档下顶部条**在**（1.3 那条 `display:flex` 修复的守卫）；
- 市场卡片 **2 列**（插件市场、皮肤市场「已安装」与「发现更多」各一次）。

### 5.3 ⚠️ 手势本身没能自动验（如实记录）

`uitest` 在屏幕边缘的 swipe **不触发**系统返回手势（`swipe 2 1400 1000 1400` 无反应）⇒ 上面
三条全走**返回键**（与手势**同一条** `onBackPress` 通道）。
**最终应由用户用真实手势复验**（左/右边缘划动）。

---

## 6. 未做 / 遗留

- **PC / 2in1 回归**：代码按 `this.handheld` 收口、`consume()` 在桌面档直接回 `'off'` ⇒
  按设计一个字节不改，但**没有设备实测**（纪律要求）。
- **用户手势复验**（见 5.3）。
- 设置面板里**其它页签**（账户 / 模型 / 内置插件）在手机档的观感：本轮只保证"不散架 + 顶部条在"，
  逐页签打磨未做。
- `dist/sideload/` 的正式包未同步（本轮产物是 debug HAP）。

---

## 7. 教益（写给下一次）

1. **"我们的界面坏了"未必是我们的界面坏了**：两件事的根因都在上游（前端不碰 history、
   插件 CSS 打架）。先把"权威事实"找出来（`grep pushState`、`grep @media`），再动手。
2. **给别人的界面写覆盖，要找"对方的对抗样式"**：`@media (max-width:560px) :has(...)>nav{display:none}`
   这条不改，顶部条会**静默消失**（不是报错，是"看起来本来就没这功能"）。
3. **绝不吞返回**：异步裁决的返回链必须留"兜底补系统默认"，否则退化成"按返回没反应"，
   比"直接回桌面"更难排查。
4. **`indexOf` 取序类断言必须限定切片区**（§4 那条假红）。
5. **诊断行要带身份**：`consume: overlay` → `consume: overlay div[shortcut=settings][role=dialog].VOzbGW_panel (visible overlays=1)`
   这一改，同一行读数的可用性差一个量级。

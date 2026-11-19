# 134 · 平板端「三键区让位」第一版未生效的真根因（逐项独立捕获 · `decorPresentOf` · `windowStatusChange` 跟随）

> 起因：`docs/133` A 项（手持档整块 Web 内容按三键区高度下移）在**手机**上验过（`keys=false` / `inset=0`
> —— 手机是全屏、无三键 ⇒ **符合预期**），但**平板 MatePad Edge 真机上没生效**（用户报"之前我们的修改未生效"）。
> 平板端自检报告 `DSHM-UI边界与定位自检报告.md` 给出的关键读数是
> `2026-10-10T03:56:49.133Z handheld=true keys=false rect.w=0 rect.h=0 inset=0`（另一条 `03:59:23.143Z` 同）。
> 本档记的是这一轮的真根因、修法、门禁与装机后应当看到的读数。

---

## 0. 一句话结论

`EntryAbility.afterWindowStageReady()` 里那三行窗口装饰调用 ——
`setWindowDecorVisible(false)` / `setWindowDecorHeight(38)` / `setDecorButtonStyle(...)` ——
在**同一个 `try`** 里，而平板**自由窗口**上中间那条抛 **`801 Capability not supported`**
（SDK 明文：能力受限的设备上不支持该 API）⇒ 整串落进 `catch` ⇒ 发布 `keys=false` ⇒ 页面让位恒 0。

**标题栏其实早已隐藏**（Web 内容顶到窗口第一行、系统三键浮在内容之上 = 沉浸已生效）——也就是说
`decorHiddenOk` 本应为真、`keys` 本应为真。报告把根因猜成"装饰探测取不到值 / 浮层口径"是**偏的**：
探测这一侧（`diag-bottom-inset` 探针链）在同一份报告里是好的。

本轮修法三条：

1. 三行**各自独立捕获**：只有 `setWindowDecorVisible(false)` 决定"标题栏是否已沉浸"（`decorHiddenOk`），
   后两条降级为**可选步骤**，各吞各的 801；
2. "三键在不在"交给纯函数 `decorPresentOf(decorHiddenOk, decorHeightVp, statusFloating)` ——
   **窗口状态可读时以 `windowStatus === FLOATING` 为唯一权威**（真机三张截图证明最大化态右上角没有系统按钮），
   状态读不到（801）才退回"装饰高度 > 0"的保守推测；
3. 高度经**新通道** `dshDecorHeightVp`（`getWindowDecorHeight()`）交给页面，并新增
   `windowStatusChange` 上的**动态跟随**（**只在手持档挂**）与 `files/diag-decor-caps` 逐项落盘。

**PC / 2in1 逐字不变**：非手持的让位恒为 0（`decorTopInsetVp` 的第一条），监听根本不挂。

---

## 1. 现象与真机读数（MatePad Edge）

| 读数 | 含义 |
|---|---|
| `handheld=true keys=false rect.w=0 rect.h=0 inset=0`（`diag-decor-top`，两条） | 新通道**被读到过**（`handheld` 对），但结论是"没有三键" ⇒ 让位 0 |
| 自由窗口：系统三键右偏移 186 / 113 / ~41–69 px；应用自绘两枚 `⋯` 97–105、`▢│` ~32 px | 三键**浮在内容之上**，`✕` 与 `▢│` 相交 **13×16 px ≈ 6.8×8.4 vp** |
| 最大化对照（三张截图一致，右边界 x=2525） | 右上角**只有**应用自己的两枚图标 ⇒ **系统三键只在自由窗口出现** |
| 1 vp ≈ 1.9125 px | 由 `diag-bottom-inset` 的 `63px / 32.94vp` 反推 |
| `diag-bottom-inset` = `sysBottom=0 indicatorBottom=63 → apply bottomPx=63 vp=32.94` | **对照臂**：探针链本身工作正常（不是"探测取不到值"） |

> 「沉浸已生效」的证据是截图：Web 内容顶到窗口第一行、自绘的两枚图标也在第一行 —— 标题栏那 38vp
> 已经没人画（手持档不渲染自绘顶栏，见 `docs/132`/`docs/133`）。

---

## 2. 根因

改前的形态（`entry/src/main/ets/entryability/EntryAbility.ets`）：

```ts
try {
  win.setWindowDecorVisible(false);
  win.setWindowDecorHeight(38);       // ← 平板自由窗口上抛 801
  win.setDecorButtonStyle({ ... });   // ← 同上
  AppStorage.setOrCreate<boolean>(KEY_DECOR_KEYS_VISIBLE, true);
} catch (err) {
  AppStorage.setOrCreate<boolean>(KEY_DECOR_KEYS_VISIBLE, false);   // ← 于是写了 false
}
```

- **为什么平板会抛 801**：`setWindowDecorHeight` 的 SDK 文档明写「能力受限的设备上不支持该 API」。
  平板自由窗口正是这种形态：三键**在**（系统画的），但**高度不可设**。
- **为什么"标题栏已隐藏"仍成立**：`setWindowDecorVisible(false)` 的文档语义是"窗口内容区接管原标题栏的
  空间" ⇒ 它成功就是沉浸；截图里内容顶到第一行 ⇒ 它确实成功了。被 801 带走的是**它的结论**，不是它的效果。
- **为什么页面侧救不回来**：页面侧只有两条信息源 —— `getTitleButtonRect()`（本机实测**恒 0/0**，三键可见时
  也是 0）与能力层那条 `AppStorage` 通道。前者不可用，后者被上面的 `catch` 写成了 `false` ⇒ 页面既不知道
  "三键在不在"，也拿不到"该让多少"。

---

## 3. 修法

### 3.1 三行拆开：只有第一行决定 `decorHiddenOk`

| 调用 | 语义 | 失败（801）时的处置 |
|---|---|---|
| `setWindowDecorVisible(false)` | **标题栏是否已沉浸**（这条是沉浸链真正的那一跳） | `decorHiddenOk = false` ⇒ 不让位（真机实测：手机**不是**这一路 —— 手机是 `visible=ok`，走下面的状态判据） |
| `setWindowDecorHeight(38)` | 高度**偏好**（写哪个值上去） | 只记录 `set=err=<code>`；**不得**影响"三键在不在" |
| `setDecorButtonStyle({...})` | 纯外观（三键配色） | 只记录；不降级 |
| `getWindowDecorHeight()` | 高度**真值**读取 | 读不到保持 0 ⇒ 页面退回 `TOP_BAR_HEIGHT`(=38) |
| `getWindowStatus()` | **三键在不在**的权威判据 | 读不到记 `status=err=<code>` ⇒ 判据退回"高度 > 0" |

### 3.2 判据 `decorPresentOf`：状态可读时它是唯一权威

```ts
function decorPresentOf(decorHiddenOk: boolean, decorHeightVp: number,
  statusFloating: boolean | undefined): boolean {
  if (!decorHiddenOk) { return false; }
  if (statusFloating !== undefined) { return statusFloating; }
  return decorHeightVp > 0;
}
```

真值表（与门禁里的求值断言逐条对应）：

| `decorHiddenOk` | `decorHeightVp` | `statusFloating` | 结果 | 场景 |
|---|---|---|---|---|
| false | 38 | true | **false** | 手机全屏：标题栏没隐藏 ⇒ 不让位 |
| true | 0 | true | **true** | **真因复现**：高度读不到但自由窗口 ⇒ 仍让位 |
| true | 38 | false | **false** | 最大化 / 全屏：右上角没有系统按钮 ⇒ 不白空 38vp |
| true | 38 | undefined | **true** | 状态读不到（801）+ 有装饰高度 ⇒ 保守让位 |
| true | 0 | undefined | **false** | 两条都读不到 ⇒ 不让位（最后兜底） |

> **为什么"最大化态 = 不让位"要单独占一条**：若把"高度 > 0"也当作"三键在"的证据，那么平板最大化时会白空出
> 一条 38vp 的底色带（系统那里并没有按钮）。真机三张截图是这条裁定的依据。

### 3.3 高度三级取用（新通道 `dshDecorHeightVp`）

> ⚠️ **本节已在 §7.2 被撤除**：让位量改成常量后，这条 AppStorage 通道没有读者了（`getWindowDecorHeight()` 的读取留在能力层，仅给 `decorPresentOf` 兜底）。

页面侧 `decorTopInsetNow()` 现算：

```ts
const height = this.decorRectHeightVp > 0 ? this.decorRectHeightVp : this.decorHeightFromAbility;
return decorTopInsetVp(this.handheld, this.decorKeysVisible, height);
```

三级 = 页面自己的 `getTitleButtonRect().height`（PC 有值、平板恒 0）→ 能力层 `getWindowDecorHeight()`
（`AppStorage` 键 **`dshDecorHeightVp`**）→ `TOP_BAR_HEIGHT`(38)。**纯函数 `decorTopInsetVp` 一个字没改**
（仍三输入、仍"非手持恒 0"），取用点在调用点 ⇒ 门禁里那 9 条求值断言逐字不变。

### 3.4 动态跟随：`windowStatusChange`（只在手持档）

`bindGeometry()` 里，**手持档**才挂 `win.on('windowStatusChange', ...)` → `refreshDecorCaps(win)`：
重读高度与窗口状态、重算 `decorPresentOf`、重新发布两个键。`unbindGeometry()` 对称解绑。
读失败时**沿用上一次读数**（不是归零）—— 801 是常态，归零会让让位在切换瞬间闪一下。
`if (!isHandheldForm()) return;` 放在挂监听之前 ⇒ **PC/2in1 一个字节不动**。

### 3.5 自证：`files/diag-decor-caps`

每次探测/刷新追加一行（与 `FolderGrants.ets` 的 diag 同款写法）：

```
<ISO 时间> visible=ok set=err=801 get=err=801 style=err status=FLOATING -> present=true
<ISO 时间> refresh H=0 status=FLOATING -> present=true
```

装机后 `hdc shell cat /data/app/el2/100/base/com.dshm.dshclient/haps/entry/files/diag-decor-caps`
即可把"哪个调用抛了什么码"钉死 —— 上一轮就是因为这条证据缺失，只能靠截图反推。

### 3.6 为什么 PC / 2in1 逐字不变

- 让位：`decorTopInsetVp` 第一条 `if (!handheld || !decorPresent) return 0;` ⇒ PC 恒 0（与第一版相同）；
- 监听：`bindGeometry` 里 `if (!isHandheldForm()) return;` 在 `win.on('windowStatusChange', ...)` **之前**；
- 发布：PC 档三个调用都成功 ⇒ `decorPresent=true`（与第一版同），且即便为假也不影响恒 0 的让位。

---

## 4. 门禁

`tools/check-decor-button-mode.mjs` 第二组 **19 → 36 项**（第一组 9 项不变），新增的断言：

- `decorPresentOf` 的**求值行为** 5 条（上表 5 行，含"真因复现"与"最大化不让位"两条核心）；
- 结构：`setWindowDecorVisible` 与 `setWindowDecorHeight` **不在同一个 `try`**（判据 = 两者之间出现 `} catch`）；
- 两条通道的键名两侧**同名同值**（`dshDecorKeysVisible` / `dshDecorHeightVp`）；
- 两个调用点（启动 + 状态刷新）都发布结论与高度（计数 = 2）；
- 高度三级取用 + `@StorageProp(KEY_DECOR_HEIGHT_VP)` 接线；
- `refreshDecorCaps` 存在、`windowStatusChange` 在 `if (!isHandheldForm())` **之后**才挂、`off` 对称。

**对照臂 A–F**（每个变异体必须判红，验过有牙）：

| 臂 | 变异体 | 判红的是 |
|---|---|---|
| A | 去掉 `!handheld \|\| !decorPresent` 守卫 | 纯函数行为（4 红） |
| B | 删掉 `.padding({ top: decorTopInsetNow() })` | 接线（1 红） |
| C | 删掉能力层启动路径那次结论发布 | 计数（1 红） |
| D | `decorPresentOf` 只看装饰高度（丢掉"自由窗口"真判据） | 求值行为（2 红） |
| E | 三个装饰调用并回同一个 `try` | 结构（1 红） |
| F | 页面不再消费能力层的高度真值 | 接线（2 红） |

"只需仓库内文件"的 19 条 CI 门禁本轮全绿（`assert-cli-shim` / `check-parity` / `assert-exec-fix` /
`assert-python-bridge` / `check-doc-refs` / `check-dead-code` / `check-decor-button-mode` /
`check-skill-sync` / `check-ptc-ts-strip` / `check-internal-undici` / `check-worker-jitless` /
`check-market-bridge` / `check-profile-pnpm-bridge` / `check-denial-hints` / `check-vm-bash` /
`check-handheld-back` / `check-fetch-shim` / `check-workspace-claim` / `check-feature-wiring`）。

产物：debug HAP **401,742,679 B** / sha256 `964776259c4e3cb4dc458f0d5b2918c1a1ccefd5cf3322b1c2124be568d37b24`
（= 本目录正式件 **r9**；相对 r8 的 401,729,303 B 只多出本轮两文件与门禁的代码体积）。
`coreVersion` **未动**（仍 `0.2.1-alpha.2+dshm.29`，本轮纯 ArkTS，核心树逐字节不变）。

---

## 5. 真机

### 5.1 手机 `62T0225B18039433`（`const.product.devicetype=phone`，本轮**已做** —— r9）

| 项 | 读数 |
|---|---|
| 装机（唯一入口 `tools/update-device.ps1 -Hap <r9> -SkipRebuild`） | 覆盖安装成功；`home` 指纹 `links=8 size=3440` **装前=装后**；核心树仍 `0.2.1-alpha.2+dshm.29` |
| **`diag-decor-caps`（本轮新档，首次真机读数）** | `visible=ok set=ok get=H=0 style=err status=1 -> present=false`，紧接一行 `refresh H=0 status=other -> present=false` |
| `diag-decor-top` | `handheld=true keys=false rect.w=0 rect.h=0 ability.h=0 inset=0`（与 r8 的可见行为一致） |
| 端侧验收 `tools/device-acceptance.ps1`（`dist/acceptance/20261010-125338`） | **5/5 PASS**（设备在线 / 核心已启动 / 客户端已接入 / 平台标识=ohos / 无异常退出） |
| 代码指纹 `tools/device-code-fingerprint.ps1` | **10/10 一致 / RC=0**（设备跑的就是本机这棵树）；token 来源 `host-ready.json`（长度 43） |

**这两行读数把一处旧注释证伪了，也顺手解释了一个"结果对、原因错"的历史**：

- 手机上 `setWindowDecorVisible(false)` 与 `setWindowDecorHeight(38)` **都是 `ok`**，真正失败的是
  `setDecorButtonStyle`（`style=err`）；`getWindowDecorHeight()` 写成功但**读回 0**；`getWindowStatus()`=1=`FULL_SCREEN`
  ⇒ 判据给出 `present=false` ⇒ 不让位（全屏本来就没有三键）。
- 旧注释写「手机全屏模式没有窗口装饰：调用抛 801 属预期」是**不准的**：r8 之前那串调用在手机上确实
  落进了 `catch`，但那是被 `setDecorButtonStyle` 带下去的 —— 结论 `keys=false` 恰好正确，理由是错的。
- `refresh` 行出现 ⇒ **手持档的 `windowStatusChange` 监听确实挂上并跑过一次**（PC 档不挂，所以那行是
  手持档特有的证据）。

### 5.2 仍未做：平板（本档的正题）与 PC

本轮**没有平板上手**：**平板 MatePad Edge 的复验未做**，PC 回归也未做。装机后应看到：

| 设备 | 期望读数 |
|---|---|
| 平板（自由窗口） | `diag-decor-top` = `handheld=true keys=true rect.w=0 rect.h=0 ability.h=<系统真值或 0> inset=38`（38 或系统真值），右上角三键与页面那排按钮不再重叠 —— 🔁 **让位量已由 §7.2 改成常量 24（`ability.h=` 字段也没了）** |
| 平板（最大化） | `keys=false` / `inset=0`（右上角本来就没有系统按钮） |
| 平板（拖大拖小 / 最大化来回切） | `diag-decor-caps` 出现 `refresh … -> present=…` 若干行，且 `diag-decor-top` 的 `inset` 跟着变 |
| 手机 | `handheld=true keys=false … inset=0`（与 r8 相同，**不变**） |
| PC / 2in1 | `handheld=false … inset=0`；`diag-decor-caps` 里**没有** `refresh` 行（监听没挂） |

---

## 6. 待办（用户复验清单）

1. 平板 MatePad Edge（自由窗口）：右上角三键与页面那排按钮不再重叠；
2. 平板（最大化 ↔ 自由窗口来回切）：让位跟着变，且最大化态**不**留 38vp 空带；
3. 手机：`diag-decor-top` 仍是 `handheld=true keys=false … inset=0`（不回归）；
4. PC：启动正常、`inset=0`、`diag-decor-caps` 无 `refresh` 行。

### 6.1 给平板端 AI 的自检提示词（⚠️ 已被 §7.4 的更新版取代 —— 读数里的 `inset=38` 现为 `24`、`ability.h=` 已撤）

> 请对 `com.dshm.dshclient` 做一次**只读**自检并原样回贴结果，不要卸载、不要清数据：
>
> 1. `hdc shell "cat /data/app/el2/100/base/com.dshm.dshclient/haps/entry/files/diag-decor-caps"`
>    —— 逐行贴出（尤其 `visible=` / `set=` / `get=` / `status=` / `present=` 与 `refresh` 行）；
> 2. `hdc shell "tail -3 /data/app/el2/100/base/com.dshm.dshclient/haps/entry/files/diag-decor-top"`
>    —— 期望最后一行含 `handheld=true keys=true` 且 `inset=38`（或系统真值）；
> 3. 把窗口**从自由窗口最大化、再拖回自由窗口**，重复第 1、2 步：
>    期望 `diag-decor-caps` 新增 `refresh` 行，且最大化态 `present=false` / `inset=0`；
> 4. 截图右上角（自由窗口态）：确认系统三键与页面那排按钮（最右那颗「面板 / 预览」）**不重叠**。
>
> 若 `diag-decor-caps` 里 `visible=err=<code>`，请把 `<code>` 与 message 原样贴出；
> 若 `keys=true` 而界面仍重叠，请补一张带像素标尺的截图（或给出三键与应用按钮的 y 区间）。

---

## 7. 第三轮：让位量收窄成常量（2026-10-10，用户实测"偏宽"）

### 7.1 触发与量算

用户拿着 r9 的平板截图说「三键和 web 右上角稍微有点宽了，可以缩小一点，但是不要重叠」——
即**不许回到重叠、也不许留那么宽的空档**。把上一节的读数换算成"到底需要多少"：

| 量 | 值 | 来源 |
|---|---|---|
| 系统三键带在装饰条里的位置 | **纵向居中**（条高 38vp ⇒ 中心 ≈19vp） | §1 截图读数（`✕` y218–246，中线 232 ≈ 内容上缘 196 + 18.8vp） |
| 三键下缘距内容上缘 | ≈ **26vp** | 同上（246−196 = 50px ÷ 1.9125） |
| 官方壳那排按钮**天然**距内容上缘 | ≈ **18vp**（顶边） | 同上（231−196 = 35px ÷ 1.9125） |
| ⇒ 不重叠所需的最小让位 | ≈ **8vp** | 26 − 18 |
| r9 实际让位 | 38vp（= 系统装饰高度） | `decorTopInsetVp` 照搬读数 |
| ⇒ 空档（三键下缘 → 按钮顶边） | ≈ 30vp | 38 + 18 − 26 |

**为什么要 3 倍余量（24 而非 12）**：这条让位是**一整块内容的位移**，而"官方壳那排按钮距内容上缘多少"
是按截图量出来的（页面侧 `getTitleButtonRect()` 恒 0，量不到真值）⇒ 不同机型 / 朝向 / 缩放比下它会动。
24vp = 最小需求的 3 倍，即便那个 18vp 换成别的数也不会相交；同时相对 38vp 收掉约 **37%**（用户要的"缩小一点"）。

### 7.2 改动（两个 `.ets`，核心树零改动）

| 位置 | 改动 |
|---|---|
| `WebApp.ets` | 新增命名常量 **`HANDHELD_DECOR_INSET_VP = 24`**；纯函数 `decorTopInsetVp(handheld, decorPresent)` 改**两输入**（第三个入参 = 高度**删掉**）；`decorTopInsetNow()` 只传两输入 |
| `WebApp.ets` | **撤掉** `KEY_DECOR_HEIGHT_VP` 常量与 `@StorageProp(KEY_DECOR_HEIGHT_VP) decorHeightFromAbility`（高度不再参与让位 ⇒ 这条通道没有读者）；`decorRectHeightVp` 保留但**降级为诊断读数**（只进 `diag-decor-top` 的 `rect.last=`） |
| `WebApp.ets` | 两条 `diag-decor-top` 去掉 `ability.h=`（高度真值仍由能力层自己的 `diag-decor-caps` 留证） |
| `EntryAbility.ets` | **撤掉** `KEY_DECOR_HEIGHT_VP` 常量与两个调用点的 `AppStorage.setOrCreate<number>(KEY_DECOR_HEIGHT_VP, …)`；`getWindowDecorHeight()` 的读取**保留**（`decorPresentOf` 在窗口状态读不到时用它兜底 + 自证落盘） |

> **为什么不留"只有诊断用途的通道"**：本仓把这叫 E346b（`settingsStates` 那条"从头到尾没人读的死链"）——
> 一条 AppStorage 通道，发布端与接收端都在"忠实转发一个没人要的字段"。要留证就留在**同一侧**（`diag-decor-caps`）。

### 7.3 门禁（改口径，不加数量）

第二组仍是 **38 项**（第一组 9 项不变），但内容换了：

- 求值：非手持恒 0 / 手持 + 三键在 ⇒ **常量** / 手持 + 三键不在 ⇒ 0（4 条）+ 1 条"常量不是判据的替代"；
- **新增常量上下限**：`HANDHELD_DECOR_INSET_VP >= 12`（盖住实测的 8vp 重叠、留 4vp 余量）且 `< TOP_BAR_HEIGHT`（否则等于退回"偏宽"那一版）；
- **新增"通道已撤"**：两侧源码里都不许再出现标识符 `KEY_DECOR_HEIGHT_VP`；
- **新增"调用点不许再传第三个参数"**（正向精确匹配 + 反向断言各一条）；
- 旧的"高度三级取用 / `@StorageProp(KEY_DECOR_HEIGHT_VP)`"两条**删掉**（它们盯的东西已经不存在）。

对照臂 A–H（每个变异体都验过会判红）：A 守卫 / B 接线 / C 结论发布 / D `decorPresentOf` 真判据 /
E 三个调用一个 `try` / **F 常量压到下限以下（8vp）** / G `@Watch` / **H 把撤掉的通道塞回来**。

### 7.4 真机复验清单（本轮未做：设备不在线）

`hdc list targets` 为空（`[Empty]`）⇒ 本轮**没有装机**。接上设备后应看到：

| 设备 | 期望 |
|---|---|
| 平板（自由窗口） | 右上角三键与页面那排按钮**不重叠**，且两排之间的空档比 r9 明显收窄（r9 是 30vp 量级 ⇒ 现在 16vp 量级） |
| 平板（最大化 ↔ 自由窗口来回切） | 让位跟着变（`diag-decor-top` 的 `inset` 在 `24` / `0` 之间切）；最大化态**不**留空带 |
| 手机 | `diag-decor-top` = `handheld=true keys=false rect.w=0 rect.h=0 inset=0`（**与 r8/r9 相同，不变**） |
| PC / 2in1 | `handheld=false … inset=0`；`diag-decor-caps` 里**没有** `refresh` 行 |

> ⚠️ `diag-decor-top` 里**不再有** `ability.h=` 字段（通道已撤）；要三键区高度真值看 `diag-decor-caps` 的 `get=H=` / `refresh H=`。

给平板端 AI 的自检提示词（§6.1 的更新版）：

> 请对 `com.dshm.dshclient` 做一次**只读**自检并原样回贴，不要卸载、不要清数据：
>
> 1. `hdc shell "tail -5 /data/app/el2/100/base/com.dshm.dshclient/haps/entry/files/diag-decor-top"`
>    —— 期望最后一行是 `handheld=true keys=true rect.w=0 rect.h=0 inset=24`（**注意：不再有 `ability.h=`**）；
> 2. 截图右上角（自由窗口态），并报出系统三键与页面那排按钮（最右那颗「面板 / 预览」）的 **y 区间**；
>    期望两者**不相交**，且空档比上一版（r9）小；
> 3. 把窗口最大化、再拖回自由窗口，重复第 1 步：期望 `inset` 在 `24`（自由窗口）与 `0`（最大化）之间切换；
> 4. `hdc shell "tail -3 /data/app/el2/100/base/com.dshm.dshclient/haps/entry/files/diag-decor-caps"`
>    —— 原样贴出（三键区高度真值在这里）。

### 7.5 产物 r10

| 项 | 值 |
|---|---|
| HAP | `DSHM-1.1.0-core0.2.1-alpha.2+dshm.29-arm64-signed.hap` |
| 大小 / sha256 | **401,735,000 B** / `49880e04b802fb7f8a596b9b19e30cfb7a4f5738c75eb42325b24bcab254e79f` |
| 与 r9 的差 | 逐条目比 **只差 3 个**（`ets/modules.abc` / `ets/sourceMaps.map` / `.pages.info`；127 个条目其余逐字节相同）⇒ 重编后的 `modules.abc` 里 `ability.h=` 与 `dshDecorHeightVp` **已消失**（复现：把 HAP 当 zip 解开，`modules.abc` 按 UTF-8 找这两个串，r9 在 / r10 不在） |
| `coreVersion` | **未动**（仍 `0.2.1-alpha.2+dshm.29`；本轮纯 ArkTS，核心树逐字节不变） |
| 门禁 | "只需仓库内文件"的 19 条 CI 门禁 + 核心树那 11 条全绿；`check-decor-button-mode` 第二组 38/38 + 对照臂 A–H 全部判红有效 |
| 退役件 | r9（401,742,679 B / `964776259c…`，2026-10-10 12:52 定稿）→ `dist/sideload/previous-internal-test/…-20261010-1252-…`（同签名可直接 `install -r` 回退） |
| 真机 | **未验**（`hdc list targets` 为空） |

### 7.6 顺带的审核发现（**未修**，登记待拍板）

本轮把"体检组"门禁全跑了一遍，唯一一条判红的是 **`tools/check-undici-shim-exports.mjs`**（它**不在** CI 名单里）：

> `FAIL 垫片缺具名导出 Request —— 需要它的文件：dist\core\work\dsh-core-0.2.1-alpha.2+dshm.29\node_modules\openai\internal\auth\x509-transport-capability.mjs`

- **来路**：上游核心升级 `0.2.1-alpha.1 → 0.2.1-alpha.2`（`docs/131`）把 `openai` 从 **6.40.0 → 7.19.0**；7.x 新增
  `internal/auth/x509-transport-capability.mjs`，它在**第 4 行**写死 `import { Agent, ProxyAgent, Request, fetch } from 'undici'`，
  而 `openai/client.mjs` **静态**引用 `auth/x509-transport.mjs` ⇒ 该模块图一旦被加载，解析期就失败。
- **为什么在端侧必然踩到**：`hostcore/app/undici-loader.mjs` 把 `undici` 整个指到本仓的纯 JS 垫片
  （`hostcore/app/undici-shim.mjs`），而垫片的具名导出里**没有 `Request`**。实测（本机一行命令即可复现）：
  `node --input-type=module -e "import { Request } from 'file:///…/hostcore/app/undici-shim.mjs'"`
  ⇒ `SyntaxError: … does not provide an export named 'Request'`。
- **影响面**：`@earendil-works/pi-ai` 的 `api/*.lazy.js` 是**动态 import** ⇒ 只有真正用到 OpenAI 系 provider 的路径才会踩；
  DSH 自身（`@deepseek-ai/*`）**没有**直接 `import 'openai'`。
- **本轮为什么不修**：修它要给垫片补一个**能用**的 `Request`（不是空壳：那条路径会 `new Request(url, options)` 再 `fetch(request, …)`），
  属于"改垫片 ⇒ 必须重出核心树 + 真机验收"的改动，而**现在没有设备在线**（`AGENTS.md` 纪律：不允许没验就发布）。
  登记在这里，等下一轮有设备时按"补 `Request` + 跑 `check-undici-shim-exports` 自证 + 真机验一次 OpenAI 系 provider"来做。

### 7.7 本轮清理台账

| 项 | 动作 | 量 |
|---|---|---|
| `%TEMP%\dshm*`（门禁临时舞台 `dshm-skills-*` / `dshm-fsloc-gate-*`，以及上一轮留下的 `dshm-find.json`、`dshm-decor-patch.txt` 等） | **删除** | 59 项 / ~108 KB |
| `dist/_poc_build.log` · `_sideload_build.log` · `_t1_build.log` · `_upgrade_build.log` · `_build_overlap.log`（构建日志；逐名在 `docs/` + `AGENTS.md` + `README.md` + `dist/**/*.md` 里搜过，**0 处引用**） | **删除** | 5 个 / 55 KB |
| `dist/acceptance/{20261007-150835, 20261007-151317, 20261008-213809, 20261009-123259, 20261010-092911, plugin-analysis}`（同判据：0 处引用；其余 8 个会话目录与 `webapp-*` 有文档引用 ⇒ **留**） | **删除** | 6 个目录 / 55.6 MB |
| `D:\temp` 下本会话与上一会话的临时脚本 / 探针输出（`*.cjs` / `*.ps1` / 探针 txt / 放大截图） | **删除** | 39 个 / ~90 KB |

合计回收 **≈ 54.4 MiB**。**刻意保留**（删了会断链或缺证据）：

- `dist/sideload/**`（交付物，含 `previous-internal-test/` 的回退档）、`dist/core/**`（核心树与打包缓存，重建要十几分钟）；
- `dist/acceptance` 里**有引用**的那几个会话目录；`dist/localtest` / `review` / `verify1` / `routeaudit` / `plugsrc` /
  `backup` / `ccache` / `arkts-entry` / `layout-fixtures` / `poc-hish-vm`（被 `docs/95`/`100`/`116`/`119` 等按名引用，或只是被文档按路径引用的空目录）；
- `entry/build/` 与 `entry/.cxx/`（构建缓存：下次增量构建与"装机直接从 `entry/build` 取件"都要用）；
- `C:\Users\Sol\.ohos`（**签名物料，绝不删** —— `AGENTS.md` 最高优先级）；
- `D:\temp\DSHM-117-回执2-NAS修复单.md` 与 `D:\temp\DSHM-118-入口侧修复单.md`（**是交给飞牛 NAS 的施工单正文，不是垃圾**）。

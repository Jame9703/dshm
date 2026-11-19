# 151 · 设置面板「手机化」收窄为**直板机专属**（折叠屏与平板回官方竖排）· 以及 `check-doc-refs` 的两位→三位编号与「续写距离」闸门

> 本轮用户原话：
>
> 「如果可以改，设置的UI手机只是直板机是横着的，折叠机也是PC竖着的UI」
>
> 即：`docs/132` 那套「设置面板铺满 + 导航改顶部横条」只对**直板手机**成立；
> **折叠屏**与**平板**一样走官方「左导航 + 右内容」竖排形态，但它们**仍属手持档**
> （抽屉侧栏 / 浮动 ⊞ / 朝向跟随屏幕 / 小白条沉浸 / 市场多列 **全部保留**）。
>
> 这一轮是 `docs/132`（手机化）→ 第 63 轮（收窄到「手机 vs 平板」）之后的**再一次收窄**：
> 把「手机」细分出「直板机（`phone`）」与「折叠屏（`foldable`）」，只有前者拿 `dshm-phone`。
>
> 改动面全是宿主侧（`platform` + `entry` 的 ArkTS 垫片），**`hostcore/**` 与核心树一字未动
> ⇒ `coreVersion` 不升**（仍 `0.2.1-alpha.2+dshm.37`，见 `docs/150`）。

---

## 0. 一句话结论

| # | 请求 | 结论 | 依据 |
|---|---|---|---|
| 1 | 折叠屏**不要**手机化设置面板 | 已落地（待真机复核） | `isFoldable()` 是设备级能力（`@ohos.display.d.ts:209`）；折叠屏展开后宽度与平板相当，官方竖排本就放得下 |
| 1b | 折叠屏**仍属手持档** | 已落地 | 侧栏垫片的手持判据由两档（`phone`/`tablet`）扩成三档（`phone`/`tablet`/`foldable`）⇒ 折叠屏仍拿 `dshm-handheld` |
| 2 | `check-doc-refs` 门禁误报 | 已修 | 编号只认 2 位 + 裸数字无条件归前一个 mention ⇒ `docs/142`、台账序号被错切 |

---

## 1. 请求 1 —— 为什么 `docs/132` 的手机化「切宽了」

### 1.1 手机化的判据原来是**两档**，装不下折叠屏

`docs/132` 落地的设置垫片（`entry/src/main/ets/pages/WebApp.ets` 的 `SETTINGS_SHIM_JS`）**只读**
`html.dshm-phone` 这一个类；而 `dshm-phone` 由侧栏垫片的 `applyHandheld()`（`WebApp.ets:1026`）
按原生桥 `platformForm()` 的答复挂上。收窄前那套是三档：

```
platformForm() ⇒ 'phone' | 'tablet' | 'desktop'
   ├ phone   ⇒ 挂 dshm-handheld + dshm-phone   （设置面板手机化）
   ├ tablet  ⇒ 只挂 dshm-handheld              （官方竖排）
   └ desktop ⇒ 只挂 dshm-desktop               （官方竖排）
```

问题在于 `platformForm()` 的原生源 `isPhoneForm()` 只判 `FormFactor.PHONE`——而**折叠屏在
`@ohos.deviceInfo.deviceType` 上就是 `phone`** ⇒ 折叠屏被归进 `phone` 档 ⇒ 拿到了 `dshm-phone`
⇒ 设置面板被铺满 + 顶部横条，这在展开态的大屏上属于**过度适配**（明明放得下官方两栏）。

### 1.2 修法（两处判据 + 一处读数）

1. **新增设备事实** `platform/src/main/ets/system/DeviceFacts.ets` 的 `isFoldableDevice()`
   （`:106`）：`display.isFoldable()`，读不到（`1400003` 等）⇒ `false`。
   判据是**设备级**能力（不是当前折叠态）——`@ohos.display.d.ts:209` 明确：小折叠的**外屏只作
   辅助显示**时 `isFoldable()` 恒回 `false`（那一类本来就跟直板机一样窄，按直板机处理正确）。
   `platform/src/main/ets/Index.ets:41` 导出。
2. **收窄 `isPhoneForm()`** `platform/src/main/ets/system/FilePicker.ets:346`：
   判据由 `form === FormFactor.PHONE` 改为 **`form === FormFactor.PHONE && !isFoldableDevice()`**。
3. **读数分段（三档 → 四档）**：`WebApp.ets:2547` 的桥 `platformForm()` 改成
   `phone ? 'phone' : (!handheld ? 'desktop' : (foldable ? 'foldable' : 'tablet'))`。
   `foldable` 这一档**只作读数与自证**（宿主日志 `platform form = foldable`），行为与 `tablet`
   等价；`applyHandheld()`（`WebApp.ets:1026`）的手持判据随之改成
   `form === 'phone' || 'tablet' || 'foldable'`（⇒ 折叠屏**仍进手持档**），
   只有 `form === 'phone'` 才**额外**挂 `dshm-phone`（`WebApp.ets:1044`）。

### 1.3 为什么"折叠屏仍进手持档但拿不到 `dshm-phone`"是对的

`dshm-handheld` 与 `dshm-phone` 是**两个正交的开关**：

- `dshm-handheld` = 「这是一台手持设备」⇒ 抽屉侧栏 / 浮动 ⊞ / 朝向跟随屏幕 / 小白条沉浸 / 市场多列；
- `dshm-phone` = 「屏幕窄到要把设置面板铺满 + 导航搬去顶部」。

折叠屏**同时**满足第一条、**不**满足第二条，所以只摘 `dshm-phone`、保留 `dshm-handheld`
正是用户在两句原话里要的那个组合（"仍是手持 App，但设置像 PC 那样竖着放"）。

---

## 2. 为什么这样切安全（PC / 平板一个字节不变）

- **桌面档判据未动**：`applyHandheld()` 的 `else { isDesktop = true; addClass(DESKTOP_CLASS) }`
  分支一字未改；`platformForm()` 答 `desktop` 的唯一条件仍是 `!this.handheld`
  （`private handheld = isHandheldForm()`，`WebApp.ets:2432`）⇒ PC / 2in1 路径**完全不变**。
- **平板路径不变**：`tablet` 档本来就拿不到 `dshm-phone`，本轮 `foldable` 只是"多一个同样拿不到
  `dshm-phone` 的档"，平板读数与行为都不受影响。
- **只缩小适配面**：`isFoldableDevice()` 读失败一律 `false` ⇒ `isPhoneForm()` 回 `true`
  ⇒ 折叠屏判据**绝不会**因为读失败把一台直板机误判成平板 / 桌面（保守方向）。
- **垫片 fail-closed 未动**：设置垫片那套 CSS 仍**全部**以
  `html.dshm-phone .dshm-set-panel.dshm-set-ready` 起头（`WebApp.ets:1252`）⇒ 结构没认全时一条都
  不落地、退回官方原样，这条不变量与 `docs/132` 一致。

---

## 3. 门禁

### 3.1 `check-doc-refs` 的三条误报根因与修法（本轮唯一的门禁改动）

**三条根因**（都已核实）：

1. `tools/check-doc-refs.mjs` 的 `NAME` 短式分支与 `FULLNAME` 只认 **2 位**编号，而 `docs/` 已涨到
   `150` ⇒ `docs/142` 被切成 `docs/14` + 尾数 `2`；
2. `parseLine()` 把「独立成反引号段的裸数字」**无条件**归给本行前一个 mention ⇒ 在 `AGENTS.md`
   里那条 **2.4 万字符**的单行台账上，几万字符外的台账序号（`` `146` `` / `` `99` ``）被当成
   `docs/142` 的行号 ⇒ 假报 B；
3. 顺带发现 `docs/README.md` 里 `` `103` `` / `` `403` `` / `` `0700` `` 这类裸数字也被误认。

**修法**：

- `FULLNAME` / `NAME` / `byNum` 正则与判据 → `[0-9]{2,3}`（2 位或 3 位）；
- 新增「续写距离」闸门 `CONT_GAP`：裸反引号段**只归给紧接**（gap 只含反引号 / 空格 / 分隔符且
  长度 ≤6）的前一条 mention，否则**不解析**（少检查而不是假报）；
- 自检新增 3 条用例（紧接续写仍报 C / 远处裸数字不报 / 三位编号不报 B）。

**读数**（修前 307 → 修后 217 条带行号引用）：`AGENTS.md` 42→1、`README.md` 11→0、
`review-report-2026-09-29.md` 59→38、`90-DSH鸿蒙原生实现全流程.md` 180→172、
`136-PC顶栏…md` 0→**+1**（`117:403` 新认出，是三位编号修正的**正收益**）。
被新闸门拒绝的 **87 条**逐样本判读**没有一条是真续写**（形态都是「`docs/NN` 引文 + 夹散文 + 裸数字
是别的含义」——E 编号 / `main.js:613` / `28.5.2` / `v5.1.3` / `0700` / `403` HTTP 码 / 台账序号）。

### 3.2 本轮实测跑过的门禁（全 rc=0）

`check-doc-refs`（`--self-test` 19/19 + 主流程 217 条）、`check-worker-jitless`、
`check-market-bridge`、`check-profile-pnpm-bridge`、`check-denial-hints`、`check-vm-bash`、
`check-fs-fence`、`check-deveco-paths`、`check-workspace-claim`、`check-layout-fixtures`、
`check-handheld-back`、`check-sidebar-shim-css`、`check-feature-wiring` 均 rc=0。

---

## 4. 出包

- 纯 ArkTS + `platform` 改动 ⇒ **`coreVersion` 不升**；只需 `hvigorw assembleHap`（debug 构建）出侧载件。
- 装机**只经** `.\tools\update-device.ps1`（覆盖安装，`-r` 语义，不动 el2 用户数据）。

---

## 5. 真机判据（待连机复核）

| 机型 | `platform form` 日志 | `__DSHM_SETTINGS__.state()` | 顶部横条 |
|---|---|---|---|
| 直板手机 | `phone` | `ready` | 在 |
| 平板 | `tablet` | `none` | 无 |
| 折叠屏 | `foldable` | `none` | 无 |
| PC / 2in1 | `desktop` | `none` | 无 |

> `state()` 的取值口径见 `docs/132` §1.2（`ready` / `raw` / `none`）。

---

## 6. 未做 / 待观察

- **真机复核**（手机 / 平板 / 折叠屏 / PC 四档读数）——本轮只落了代码与门禁，尚未连机。
- 折叠屏实测：本机当前无折叠屏设备接入 ⇒ `foldable` 档的真机读数**未取证**。
- `foldable` 档目前与 `tablet` 行为等价（只多一行日志）；若后续要给折叠屏**展开态**单独做布局，
  可在此档上加挂类，但**本轮刻意不加**（避免与官方竖排形态冲突）。

---

## 7. 门禁修复与台账同步

- `tools/check-doc-refs.mjs`：三位编号 + 续写距离闸门（见 §3.1）。
- `docs/README.md`：编号区间 `95–150` → `95–151` + 末尾新增本档条目。
- `AGENTS.md`（单行台账）：最大编号 `150` → `151` + 末尾追加本档条目。
- `docs/132-手持档设置面板手机化…md`：就地补注「**已收窄为直板机专属（平板 / 折叠屏除外）**」，
  指向本档（契约台账**只标不删**）。

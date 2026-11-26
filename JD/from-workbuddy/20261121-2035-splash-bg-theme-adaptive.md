# JD-032 交接单：启动背景跟随系统深浅色自适应

- 提交方：WorkBuddy
- 接收方：DevEco（构建 + 真机验证）
- 时间：2026-11-21 20:35
- 关联：独立于桌宠相关 JD（JD-021~JD-031）；本单不涉及桌宠代码
- 版本：**不改版本号**（仍 1.1.8 / 1010019），是否随下一版 Beta 出包由 DevEco 决定

---

## 0. 一句话交付

应用启动一直是白底。本单把**启动视图、启动期状态栏、启动期窗口底色**从固定 `#FFFFFF` 改为**按系统当前深浅色自适应**：浅色 `#FFFFFF`、深色 `#151517`，且系统启动窗与页面首帧同源，深色下不再「先白后深」。

**entry（PC/2in1/平板主壳）与 phone（手机）两端已同构改完，本地编译与门禁均通过，需 DevEco 构建并真机复验。**

---

## 1. 根因（三处叠加）

| # | 根因 | 位置 |
|---|---|---|
| 1 | 启动视图 + 启动期状态栏/窗口底色都用固定常量 `SPLASH_BG = '#FFFFFF'` | `entry/src/main/ets/pages/WebApp.ets`（原 4051）、`phone/.../WebApp.ets`（原 3682） |
| 2 | `EntryAbility.appearanceMode()` 在页面尚未上报外观时**默认 `'light'`** ⇒ 深色系统冷启动建窗/重放也是浅色 | `entry/.../EntryAbility.ets:3390`、`phone/.../EntryAbility.ets:2711` |
| 3 | `start_window_background` 的 dark 值是 `#000000`，与深色窗口色 `#151517` 不一致 ⇒ 系统启动窗与首帧有色差 | `entry/src/main/resources/dark/element/color.json`、`phone/.../dark/element/color.json` |

`SPLASH_BG` 的来历：2026-10-16 真机（手机 `62T0225B18039433`）观察到启动期系统把状态栏固定画白，为避免「白状态栏 + 浅灰启动页」的台阶，反过来让启动页取白。本次按新产品要求改为跟随系统。

---

## 2. 改动清单

### 2.1 两端颜色资源：dark 统一为 `#151517`

`entry/src/main/resources/dark/element/color.json`
`phone/src/main/resources/dark/element/color.json`

```json
{ "name": "start_window_background", "value": "#151517" }
```

> base 仍是 `#FFFFFF`，与 `windowChromeFor('light').bg` 同值。

### 2.2 `EntryAbility.appearanceMode()`：无页面上报时回退系统色

`entry/src/main/ets/entryability/EntryAbility.ets:3390`、`phone/src/main/ets/entryability/EntryAbility.ets:2711`（两端同构）

```ts
private appearanceMode(): string {
  const v: string | undefined = AppStorage.get<string>(KEY_APPEARANCE_MODE);
  if (v === 'dark' || v === 'light') {
    return v;
  }
  // 页面还没上报（冷启动首帧）：按系统当前深浅色，而不是默认浅色
  try {
    return this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      ? 'dark'
      : 'light';
  } catch (e) {
    return 'light';
  }
}
```

### 2.3 `WebApp`：新增系统取色 + 启动页资源 + 启动期三件同源

`entry/src/main/ets/pages/WebApp.ets`、`phone/src/main/ets/pages/WebApp.ets`（两端同构，行号见下）

| 改动 | entry 行号 | phone 行号 |
|---|---|---|
| 删除 `const SPLASH_BG = '#FFFFFF'`，注释改为「跟随系统」说明 | 原 4051 | 原 3682 |
| 新增 `@State splashDark: boolean = false` | 4057 | 3688 |
| `aboutToAppear` 首行初始化 `this.splashDark = this.systemAppearance() === 'dark'` | 5578 | 5006 |
| 新增 `systemAppearance()` | 6896 | 6099 |
| `splashUp` 三件改用 `windowChromeFor(systemAppearance())` | 6941-6944 | 6144-6147 |
| 启动视图底色改资源 + 进度条随深浅 | 8166-8174 | 6823-6833 |

关键代码：

```ts
/** 系统当前深浅色：web 主题上报前直接读 Configuration.colorMode */
private systemAppearance(): string {
  try {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (ctx !== undefined
      && ctx.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK) {
      return 'dark';
    }
  } catch (e) {
    // 取不到按浅色（与官方 boot 的 color-scheme:light 一致）
  }
  return 'light';
}

// applySystemBarTheme 内：
const splashChrome = windowChromeFor(this.systemAppearance());
const barBg: string = splashUp ? splashChrome.bg : chrome.bg;
const lightIcon: boolean = splashUp ? splashChrome.lightIcon : chrome.lightIcon;
const contentColor: string = splashUp ? splashChrome.content : chrome.content;

// 启动视图：
.color(this.splashDark ? '#FFFFFF' : '#1c2430')
.backgroundColor(this.splashDark ? '#2A2A2E' : '#e4e7ec')
// ...
.backgroundColor($r('app.color.start_window_background'))
```

### 2.4 门禁同步（否则会红）

`tools/check-decor-button-mode.mjs` 第五组：

- 新增读取 `entry/src/main/resources/dark/element/color.json`（`colorDarkSrc`，`inspectTopInset` 第 5 参数）；
- 断言改为：启动视图用 `$r('app.color.start_window_background')`、`systemAppearance()` 读 `config.colorMode`、`splashChrome = windowChromeFor(systemAppearance())`、`barBg/lightIcon/contentColor` 三件接线；
- 新增资源值校验：base == `windowChromeFor('light').bg`，dark == `windowChromeFor('dark').bg`；
- 对照臂 P 语义保留：把 base 改成 `#F3F7FB` 必须判红。

---

## 3. 行为口径

| 场景 | 期望 |
|---|---|
| 系统浅色 + 冷启动 | 启动窗 / 启动视图 / 状态栏均 `#FFFFFF`，无异常 |
| 系统深色 + 冷启动 | 三者均 `#151517`，状态栏浅色图标，**无白闪** |
| 应用内固定「浅色」，系统深色 | 跟随应用外观 = 浅色（`appearanceMode` 读到页面发布值优先） |
| 应用内固定「深色」，系统浅色 | 跟随应用外观 = 深色 |
| 首帧就绪后 | 仍由 `onPhaseChanged` 切到应用外观色（原逻辑不变） |
| 桌宠 `PetAbility` 子窗 | 不受影响（子窗底色仍 `#00000000` 透明） |

---

## 4. DevEco 验证清单

### 4.1 构建

```sh
cd <workspace>
devecocli build --product default --build-mode debug
```

- 期望：`BUILD SUCCESSFUL`；`entry:default@CompileArkTS` 与 `phone:default@CompileArkTS` 均执行。
- WorkBuddy 本地基准：**BUILD SUCCESSFUL 57s**，产物 `entry/build/default/outputs/default/entry-default-signed.hap`。

### 4.2 门禁

```sh
node tools/check-decor-button-mode.mjs
```

- 期望：`RESULT: PASS —— 第一组 9/0、第二组 134/0，对照臂 A–X 有效`。
- WorkBuddy 本地基准：**134/0 PASS**。

### 4.3 真机测点（必测）

1. **深色系统冷启动**（先杀进程，再启动）：从首帧开始录屏，确认启动页/状态栏/应用首帧均为深色，无白色闪帧。
2. **浅色系统冷启动**：同上，确认全白且无异常。
3. **应用内固定外观**：设置→外观切「浅色」「深色」各冷启动一次，确认跟随应用设置而非系统。
4. **两端覆盖**：entry（PC/2in1/平板主壳）+ phone（手机）至少各一台。
5. **不回归**：
   - 旋转 / 分屏 / 最大化 / 自由窗口下状态栏归属（原 `statusBarOwnedByApp` 逻辑未动）；
   - 桌宠 `display=desktop` 时子窗仍正常（`PetAbility` 背景透明未动）；
   - 启动页 → 应用界面切换无色差跳变。

### 4.4 证据回填

- 设备型号 / 系统版本 / API；
- 系统外观（深/浅）与测试时间；
- 冷启动录屏（含首帧）；
- `devecocli build` 结果与门禁输出；
- 若异常：`hilog | grep -E "entry/pet|状态栏|appearance"` 与截图。

---

## 5. 已知取舍 / 待真机确认

- **启动期系统状态栏可能仍被系统画白**：2026-10-16 手机实测存在此现象（我们写的 `statusBarColor` 在该阶段不被采用）。若本机仍如此，深色启动页会出现「白状态栏 + 深启动页」的台阶——这是「跟随系统」与「启动期状态栏不可控」的取舍，需真机复看后决定是否接受，或改为启动期暂不扩 top（交还系统）。
- 本次只改「颜色取源」，未改 `expandSafeArea` / 状态栏归属 / 桌宠链路；如真机出现新形态，优先按「取色 vs 布局」二分定位。

---

## 5.1 补充修复：移动端状态栏沉浸（2026-11-21 20:58，用户反馈）

### 反馈

DevEco 构建后用户手动装机：**手机跟随系统切深色后，状态栏没有沉浸，与页面割裂**。

### 根因

`layout-fullscreen` + 透明状态栏本身已开启（`EntryAbility.enterHandheldImmersive`），但状态栏透明后**露出的底色**是：

- 窗口/根容器用的固定 `windowChromeFor` 色（深 `#151517`），与官方 Web **自己的实际背景**有色差 ⇒ 深色下一条与页面不同的色带；
- 且根容器/Stack 只 `expandSafeArea` 了 **bottom**，状态栏那条不由页面底色绘制。

### 修复（仅 phone 壳，PC/平板逻辑不动）

1. **采样网页真实背景色**：`WebApp.onPageEnd` 里 `runJavaScript` 读
   `getComputedStyle(document.body).backgroundColor`（兜底 `documentElement`），
   解析 `rgb()/rgba()` → hex，写入 `pageBg`，并作为 `windowBg` 与 `setWindowBackgroundColor`；
   `applySystemBarTheme` 改为 `pageBg` 优先。⇒ 状态栏与页面**天然同色**，不依赖固定色假设。
2. **页面底色铺到状态栏下**：手持档把根容器 / Stack / ERROR 覆盖层的 `expandSafeArea` 增加 **TOP**
   （与启动视图同款三元表达式；PC 保持原样）。
3. 幂等：`pageBg` 相同则跳过；`onPageEnd` 立即采一次 + 400 ms 再采一次（样式可能稍晚稳定）。

### 验证

- `node tools/check-decor-button-mode.mjs` → **134/0 PASS**（含「手机沉浸 layout-fullscreen + topInset 成对接」）。
- `devecocli build --product default --build-mode debug` → **BUILD SUCCESSFUL**。

### 真机测点（手机）

1. 系统深色 → 冷启动：状态栏与页面顶部**无缝**，无独立色带；切浅色再冷启动同样无缝。
2. 应用内切外观后：状态栏随之同色。
3. 页面滚动到顶/底：状态栏那条不跳动、不变色。
4. 最近任务卡片：顶部不再是割裂色带（原 `topInsetVp` 让位仍保留）。
5. 若采不到（body/documentElement 均透明）：回退 `windowChromeFor` 色，需在 hilog 看
   `页面背景采样：...` 是否出现。

## 5.2 补充修复：启动期状态栏白条（2026-11-21 21:16，用户真机复测）

### 反馈

手机深色模式下**启动 APP 时**：APP 区已是黑色，但**状态栏还是白色**，仍然割裂（发生在启动页阶段，不是首帧后）。

### 根因

`enterHandheldImmersive()` 挂在 `loadContent` 回调**之后**（`afterWindowStageReady`），且原实现只设了
`statusBarColor = 透明`，**没有设窗口底色** ⇒ 状态栏透明后露出窗口默认白底；同时也没设
`isStatusBarLightIcon` / `statusBarContentColor`。于是启动页（约 7s）期间 = 黑页面 + 白状态栏。

### 修复（phone `EntryAbility.ets`）

1. **`onWindowStageCreate` 在 `loadContent` 之前**：`windowStage.getMainWindowSync()` 取窗后立即
   `setWindowBackgroundColor(windowChromeFor(appearanceMode()).bg)` + `setWindowLayoutFullScreen(true)` +
   透明状态栏 + 图标明暗（`isStatusBarLightIcon` / `statusBarContentColor`）。
2. **`enterHandheldImmersive()`** 同步补齐：先设窗口底色，再设 layout-fullscreen + 透明 + 图标明暗。
3. `appearanceMode()` 在页面上报前回退系统 `config.colorMode`（JD-032 首轮已加）⇒ 深色系统启动即取 `#151517`。

### 验证

- `devecocli build --product default --build-mode debug` → **BUILD SUCCESSFUL**。
- `node tools/check-decor-button-mode.mjs` → **134/0 PASS**。

### 真机复测点

1. 深色系统 → 杀进程冷启动：**从系统启动窗到启动页全程**状态栏不应再是白条；启动页背景与状态栏同色。
2. 浅色系统冷启动：全白，无异常。
3. 启动页 → 首页切换：不发白闪。
4. 若启动窗极早期（应用窗口创建前）仍白：那是系统 splash 窗口阶段，应用无法控制，需以「进入启动页后是否白」为准。

## 6. 边界

- 不升版本号、不动 `module.json5` 的 `startWindowBackground` 引用（仍 `$color:start_window_background`）。
- 不影响 JD-021~JD-031 的桌宠工作；两件事可同包验证，也可分开。
- 若 DevEco 出包，请回报包路径与 app sha256，WorkBuddy 更新 `JD/STATUS.md` 与交付记录。

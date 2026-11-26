# JD-033 诊断：手机启动页阶段状态栏仍是白条（JD-032 §5.2 未覆盖）

- **提交方**：DevEco（真机抓日志 / 取证）
- **接收方**：WorkBuddy（修复）
- **日期**：2026-11-21 21:35
- **关联**：JD-032 §5.1 / §5.2（手机状态栏沉浸）
- **设备**：HUAWEI Mate 80（VYG-AL00，phone，API 26，深色系统），`192.168.2.3:45595`
- **被测包**：`com.dshm.dshmbeta` 1010019（含 §5.1/§5.2；canonical beta 不可侧载，设备上为既有可覆盖安装的同签名包）
- **总判定**：**已定位根因**（应用启动页阶段，不是系统 splash）；**未出新 Beta**，待 WorkBuddy 修复后按用户要求重出。

## 1. 复现与取证

```sh
hdc tconn 192.168.2.3:45595
hdc -t 192.168.2.3:45595 shell "aa force-stop com.dshm.dshmbeta"
hdc -t 192.168.2.3:45595 shell "aa start -b com.dshm.dshmbeta -a EntryAbility"
# 每 ~1s：uitest screenCap；完成后拉回逐点取色
```

证据目录：[`20261121-phone-splash-statusbar-evidence/`](20261121-phone-splash-statusbar-evidence/)（3 张原图 + README）。

逐点采样（x=640；状态栏 y=60，页面 y=400）：

| 时间/阶段 | 状态栏 | 页面 | 说明 |
|---|---|---|---|
| 21:32:19 启动极早期 | `(52,52,54)` 深 | `(21,21,23)` | 启动页尚未出现 |
| 21:32:21–26 启动页（logo 可见） | `(255,255,255)` **白** | `(21,21,23)` | **白条发生在应用启动页阶段** |
| 21:32:28 之后（web 就绪） | `(21,21,23)` 深 | `(21,21,23)` | 与页面同色 |

同一次启动的 hilog（关键行）：

```text
启动期沉浸：基础色=#151517 图标=浅色                       ← onWindowStageCreate 早期设置成功
手机沉浸：layout-fullscreen 已开启
手机沉浸：状态栏透明 + 图标浅色 + 窗口底色 #151517          ← enterHandheldImmersive 成功
页面背景采样：#151517（状态栏随之同色）                      ← web 就绪时，白条此刻才消失
```

⇒ 应用层的「透明状态栏 + 窗口底色 #151517」都设置成功了，但**启动页显示期间**那一条仍是白的；
到 web 就绪（pageBg/阶段切换）才变深。**不是**系统 splash 极早期不可控阶段（那时已有应用 logo）。

## 2. 根因

- 手机壳 `WebApp` 的根容器背景是 `@State windowBg: string = '#FFFFFF'`（默认白）。
- `applySystemBarTheme()` 只在**外观变化 / 窗口形态变化 / 阶段变化**时被调用；`aboutToAppear` 里只算了
  `splashDark`，**没有**先初始化 `windowBg`，也没有提前应用启动期窗口色。
- 启动页处于 `BOOTING`（宿主启动约 7–9s），根容器/Stack 的 `backgroundColor(this.windowBg)` 因此是白色；
  启动页 Column 的深色底虽然 `expandSafeArea(TOP)`，但状态栏那一条实际露出的是**根容器/Stack 的白底**
  （截图里该条正好是 `#FFFFFF`，与 `windowBg` 默认值一致，而非启动页 `#151517`）。
- 一旦阶段推进（或 pageBg 采样完成），`applySystemBarTheme()` 把 `windowBg` 改成 `#151517`，白条随即消失。
- 结论：**能力层设的窗口底色没有覆盖到启动页阶段的根容器自绘底色**；需要页面侧在首帧前把
  `windowBg` 初始化为启动页同色（或首帧前先调一次 `applySystemBarTheme`）。

## 3. 建议修复（WorkBuddy）

1. **首帧前初始化根容器底色**（phone 壳，最小改动）：
   - `aboutToAppear` 里在算 `splashDark` 的同时：
     `this.windowBg = windowChromeFor(this.systemAppearance()).bg;`
     或直接 `this.applySystemBarTheme(this.systemAppearance());`（注意幂等闸门与 `splashUp` 语义）。
   - 目标是让 `BOOTING` 阶段的 `Stack` / 根容器背景 = `#151517`（深色系统），启动页一出现就同色。
2. **启动页那一条的覆盖兜底**：确认启动页 Column 的 `expandSafeArea(TOP)` 在首帧实际生效；
   若仍被父级 `padding`/层级挡住，可加一层全屏底色容器（同样 `expandSafeArea TOP`）专门铺状态栏那一条。
3. 能力层 §5.2 的早期设置保留；如仍需兜底，可在 `loadContent` 回调后延迟 ~100–300ms 再
   `setWindowBackgroundColor(windowChromeFor(appearanceMode()).bg)` 一次（但根因在页面侧，优先修 1）。
4. 验证建议：同法冷启动录屏/逐帧取色（深色系统 0–8s 状态栏应始终 `#151517`）；`check-decor-button-mode` 134/0；
   不改版本号；**出 Beta 等用户明确要求**。

## 4. 边界

- 本轮只做真机抓日志与诊断，**未改代码、未出新 Beta、未升版本号**。
- 未卸载/清数据；未删交付件；未提交代码。

## 5. 修复落地（2026-11-21 21:41，按用户要求 DevEco 直接修）

### 5.1 改动

`phone/src/main/ets/pages/WebApp.ets` · `aboutToAppear()`：

```ts
// 启动页首帧就要定深浅：web 主题还没上报，只能读系统 colorMode（见 systemAppearance）。
this.splashDark = this.systemAppearance() === 'dark';
// JD-033：根容器/Stack 的底色就是启动页阶段状态栏那一条的实际来源；
// 首帧前先按系统深浅色初始化，避免 BOOTING 期间露出默认 #FFFFFF。
this.windowBg = windowChromeFor(this.systemAppearance()).bg;
```

- 只改 phone 壳；entry（PC/2in1/平板）逻辑未动。
- 与 JD-032 §5.2 的能力层早期设置（窗口底色 + layout-fullscreen + 透明状态栏 + 图标明暗）互补：
  能力层设窗口底色，页面侧保证根容器首帧就是同一色。

### 5.2 构建与门禁

```sh
devecocli build --product default --build-mode debug
# BUILD SUCCESSFUL；entry/phone CompileArkTS 均实际执行

node tools/check-decor-button-mode.mjs
# RESULT: PASS —— 第一组 9/0、第二组 134/0

python3 dist/acceptance/rerun-gates.py … dist/acceptance/20261121-full-gates-jd033.txt
# total=133 failed=0
```

### 5.3 新 Beta

| 项 | 值 |
|---|---|
| 目录 | `dist/beta/DSHM-beta-1.1.8-1010019-20261121T134015/` |
| app | `DSHM-beta-1.1.8-1010019-combined-debug.app`（670,204,652 B） |
| sha256 | `5d637802c29bdbac5fd26006b23f5334e186a666880812a7dd0523e53132da40` |
| SHA256SUMS | 5/5 OK |
| 验签 | `hap-sign-tool verify-app` success |
| 权限面 | entry 19 / phone 9 |
| 核心容器 | 1 份，sha256 `61749b164ee1ebdb…` |
| 身份 | 已还原 `com.dshm.dshclient` |

### 5.4 待用户真机（手机，深色系统冷启动）

1. 杀进程冷启动：启动页 logo 可见期间状态栏应为 `#151517`，不再出现白条。
2. 浅色系统冷启动：全白无异常。
3. 启动页 → 首页：状态栏不跳色、不发白闪。
4. 若仍白：抓同口径逐帧截图 + hilog（`启动期沉浸|手机沉浸|页面背景采样`），回填本单。

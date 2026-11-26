# JD-032 结论：启动背景跟随系统深浅色自适应 —— 构建 / 门禁 / Beta

- **接收**：[`from-workbuddy/20261121-2035-splash-bg-theme-adaptive.md`](../from-workbuddy/20261121-2035-splash-bg-theme-adaptive.md)（2026-11-21 20:35）
- **执行**：DevEco，2026-11-21 20:36–20:43，本机（MateBook 14 2in1 / API 26）
- **总判定**：**构建与门禁 PASS，Beta 已出**；真机「深/浅色冷启动无白闪」待用户复验（需切系统主题 + 录屏，属用户侧动作）。

## 1. 构建

```sh
devecocli build --product default --build-mode debug
# Build completed successfully
```

- 增量构建中 `entry` / `phone` 的 `CompileArkTS` 为 UP-TO-DATE（与 WorkBuddy 本地基准同源码同产物）。
- Beta 打包脚本内部执行了 `devecocli build clean` + 全量构建，因此**出包本身就是一次干净编译**；`entry:default@CompileArkTS` 与 `phone:default@CompileArkTS` 均进入产物。
- 未改版本号：仍 1.1.8 / 1010019。

## 2. 门禁

```sh
node tools/check-decor-button-mode.mjs
# RESULT: PASS —— 第一组 9/0、第二组 134/0，对照臂 A–X 有效

python3 dist/acceptance/rerun-gates.py \
  dist/acceptance/20261119-full-gates-jd012-013.txt \
  dist/acceptance/20261121-full-gates-jd032.txt
# total=133 failed=0
```

- 第五组（启动期取色）按交接单同步；对照臂 P（base 改成 `#F3F7FB`）仍判红。
- 权限面：entry 19 / phone 9、reason 无孤儿（未新增权限）。
- 核心容器：resfile 仅 1 份，与配方/本次产出一致（sha256 `61749b164ee1ebdb…`）。

## 3. Beta 产物

| 项 | 值 |
|---|---|
| 目录 | `dist/beta/DSHM-beta-1.1.8-1010019-20261121T124120/` |
| app | `DSHM-beta-1.1.8-1010019-combined-debug.app`（670,194,392 B） |
| sha256 | `c0f092c81a7784b2a16ce2d11cdbd86980f8b828fc4dd95b8014396f7256bde7` |
| SHA256SUMS | 5/5 OK |
| 验签 | `hap-sign-tool verify-app` success |
| 权限面 | entry 19 / phone 9 |
| 身份 | 已还原 `com.dshm.dshclient`（无 beta 残留） |
| 安装目录 | `tablet/`（entry hap + hostruntime hsp）、`phone/`（phone hap + hostruntime hsp） |

> canonical Beta 不能直接侧载（9568322）；本机测试走 local-install 重签，不卸载。

## 4. 复核记录

- 三处根因改动均在位：`SPLASH_BG` 常量已删、启动视图用 `$r('app.color.start_window_background')`、`systemAppearance()` 读 `config.colorMode`、启动期三件（barBg/lightIcon/contentColor）取 `windowChromeFor(systemAppearance())`；两端同构。
- dark 资源：entry / phone 的 `start_window_background` 均为 `#151517`；base 仍 `#FFFFFF`。
- `EntryAbility.appearanceMode()` 在无页面上报时回退系统 `colorMode`，有页面值优先（应用内固定外观不被系统覆盖）。
- 未触及桌宠链路（`PetAbility` 背景仍透明）、未改 `expandSafeArea` / 状态栏归属 / `module.json5` 引用。

## 5. 待用户真机复验（交接单 §4.3）

1. 系统深色 + 冷启动：启动页/启动视图/首帧均深色，无白色闪帧（录屏含首帧）。
2. 系统浅色 + 冷启动：全白无异常。
3. 应用内固定「浅色/深色」各冷启动一次：跟随应用设置。
4. entry（PC/2in1/平板）+ phone 至少各一台。
5. 不回归：旋转/分屏/最大化/自由窗口状态栏归属；桌宠 `display=desktop` 子窗正常；启动页→应用界面无色差跳变。

已知取舍（交接单 §5）：启动期系统状态栏可能仍被系统画白；若真机仍是「白状态栏 + 深启动页」，需决定接受或启动期不扩 top。

## 6. 边界与红线

- 未升版本号；未 `git commit`；未 `hdc uninstall` / 清数据；未删交付件；未新增权限。
- 本次只出 Beta，**未上传 AGC、未提交审核**。

## 7. 补充：§5.1 手机状态栏沉浸修复后的重编与重出包（2026-11-21 21:12）

WorkBuddy 于 20:58 按用户真机反馈补了 §5.1（仅 phone 壳：采样网页真实 `body` 背景色 → 状态栏/窗口同色；手持档 `expandSafeArea` 增 TOP）。DevEco 按要求重编重出。

### 7.1 构建（phone 实际重编）

```sh
devecocli build --product default --build-mode debug
# BUILD SUCCESSFUL；:phone:default@CompileArkTS 6.1s 实际执行（entry up-to-date，源码未变）
```

### 7.2 门禁

```sh
node tools/check-decor-button-mode.mjs
# RESULT: PASS —— 第一组 9/0、第二组 134/0

python3 dist/acceptance/rerun-gates.py … dist/acceptance/20261121-full-gates-jd032b.txt
# total=133 failed=0
```

### 7.3 新 Beta（替代 7.3 之前的 `…T124120`）

| 项 | 值 |
|---|---|
| 目录 | `dist/beta/DSHM-beta-1.1.8-1010019-20261121T131122/` |
| app | `DSHM-beta-1.1.8-1010019-combined-debug.app`（670,201,221 B） |
| sha256 | `500a51b479ec6b9ba0c7f75c49461b2e69cb8299b87cf5e40d56926894ea2ce4` |
| SHA256SUMS | 5/5 OK |
| 验签 | `hap-sign-tool verify-app` success |
| 权限面 | entry 19 / phone 9 |
| 核心容器 | 1 份，sha256 `61749b164ee1ebdb…` |
| 身份 | 已还原 `com.dshm.dshclient` |

### 7.4 待用户真机（手机，交接单 §5.1）

1. 系统深色冷启动：状态栏与页面顶部无缝、无独立色带；切浅色再冷启动同样无缝。
2. 应用内切外观后状态栏随之同色。
3. 页面滚到顶/底：状态栏那条不跳动、不变色。
4. 最近任务卡片顶部不再出现割裂色带。
5. 若采不到网页背景（body/documentElement 均透明）：回退 `windowChromeFor` 色，观察 hilog `页面背景采样` 是否出现。

## 8. 补充：§5.2 启动期状态栏白条修复后的重编与重出包（2026-11-21 21:24）

WorkBuddy 于 21:16 按手机真机复测补 §5.2（`onWindowStageCreate` 在 `loadContent` **之前**先设窗口底色 + layout-fullscreen + 透明状态栏 + 图标明暗；`enterHandheldImmersive` 同步补窗口底色）。

### 8.1 构建与门禁

```sh
devecocli build --product default --build-mode debug
# BUILD SUCCESSFUL（与 WorkBuddy 本地同源同产物，CompileArkTS up-to-date；Beta 脚本内部 clean + 全量构建）

node tools/check-decor-button-mode.mjs
# RESULT: PASS —— 第一组 9/0、第二组 134/0

python3 dist/acceptance/rerun-gates.py … dist/acceptance/20261121-full-gates-jd032c.txt
# total=133 failed=0
```

### 8.2 新 Beta（替代 `…T131122`）

| 项 | 值 |
|---|---|
| 目录 | `dist/beta/DSHM-beta-1.1.8-1010019-20261121T132317/` |
| app | `DSHM-beta-1.1.8-1010019-combined-debug.app`（670,204,479 B） |
| sha256 | `6ef2094595dc919c80ac0e4e9c0e2c550ca9f1ca992ad043ae63cc788dc3d596` |
| SHA256SUMS | 5/5 OK |
| 验签 | `hap-sign-tool verify-app` success |
| 权限面 | entry 19 / phone 9 |
| 核心容器 | 1 份，sha256 `61749b164ee1ebdb…` |
| 身份 | 已还原 `com.dshm.dshclient` |

### 8.3 待用户真机（手机，交接单 §5.2）

1. 深色系统 → 杀进程冷启动：从系统启动窗到启动页全程状态栏不再是白条，启动页与状态栏同色。
2. 浅色系统冷启动：全白无异常。
3. 启动页 → 首页切换：不发白闪。
4. 若应用窗口创建前的系统 splash 阶段仍白：该阶段应用不可控，以「进入启动页后是否白」为准。

# 交接单：平板分屏/小窗修复 A（恢复手持档装饰启动链）

- **ID**：JD-012
- **提交方**：WorkBuddy
- **接收方**：DevEco（编译 / 真机验证）
- **日期**：2026-11-19 20:36
- **状态**：待编译

## 1. 背景与根因

用户 2026-11-19 平板实测：分屏 / 小窗入口不可用；探针恒为
`status=1 FULL_SCREEN、free=false、desired=system decor=skip buttons=skip show=false`；
窗口状态历史从未出现 `SPLIT_SCREEN`；10-26~11-08 曾为 `show=true`，11-12 起变 `false`。

源码核实（强于“装饰被隐藏”）：

`entry/src/main/ets/entryability/EntryAbility.ets` 的 `afterWindowStageReady()` 在 11-12 落地
`docs/416` 时多出一层早分支：

```ts
if (isHandheldForm()) {
  // 只写 pcMode + publishDecorKeysVisible(false)
} else {
  // 原完整链：读窗口状态 / setWindowDecorVisible(true|false) /
  // showTitleButtons / decorPresentOf / writeDecorCapsDiag / reassertWindowChrome
}
```

手持档（平板）因此**整段装饰链一次都不执行**：FLOATING 恢复装饰的调用不存在，
三键显隐不执行，探针也不落盘 ⇒ 与真机读数完全一致。

## 2. 本次改动

| 文件 | 改动 |
|---|---|
| `entry/src/main/ets/entryability/EntryAbility.ets` | 删除 `isHandheldForm()` 早分支与 `else` 包裹，统一走完整链；`pcMode = 手持 && FLOATING`（PC 档 `isHandheldForm()` 为假 ⇒ 恒 false，行为逐字不变） |
| `tools/check-decor-button-mode.mjs` | 旧断言原本钉住“手持只发布 false”的半成品结构，已改为：禁止早分支 + 必须按 `decorPresentOf` 结论发布；对照臂 C 锚点同步改为 `publishDecorKeysVisible(decorPresent)` |

**行为边界**：
- 全屏（FULL_SCREEN）：仍隐藏装饰、保持沉浸（不变）；
- 自由窗口（FLOATING）：恢复系统标题栏 + 三键（本次修复的核心）；
- PC / 2in1：`pcMode` 恒 false，逐字不变；
- 手机：走 `phone` 壳，本次未改。

## 3. 本地验证（WorkBuddy，已执行）

```sh
CODEBUDDY_SAFE_DELETE_ENABLED=0 devecocli build --product default  # ✅ BUILD SUCCESSFUL
node tools/check-arkts-entry.mjs        # ✅ entry ArkTS 编译通过（0 error）
node tools/check-decor-button-mode.mjs # ✅ 第一组 9/0、第二组 131/0，对照臂 A–X 全有效
node tools/check-window-mode.mjs       # ✅ 27/0
node tools/check-dual-shell-parity.mjs # ✅ 7 个共享文件逐字节一致
node tools/check-bridge-methodlist.mjs # ✅ 通过
```

已知无关项：`tools/check-free-window-decor.mjs` 在**改动前基线**上也抛
`ReferenceError: KEY_MAIN_WINDOW_ID is not defined`（脚本 harness 自身问题），本次未修，
不作为本单判据。

## 4. 请 DevEco 执行

### 4.1 编译

```sh
CODEBUDDY_SAFE_DELETE_ENABLED=0 devecocli build --product default
CODEBUDDY_SAFE_DELETE_ENABLED=0 devecocli build --product phone
```

（phone 未改，但共享 HSP/双 product 需一起过；版本号不变，仍 `1.1.8 / 1010018`。）

### 4.2 必跑门禁

```sh
node tools/check-decor-button-mode.mjs
node tools/check-window-mode.mjs
node tools/check-arkts-entry.mjs
node tools/check-dual-shell-parity.mjs
```

### 4.3 平板真机验证（按顺序记录，缺一项都不算闭环）

1. **冷启动后的探针**：应仍为 `status=1 FULL_SCREEN`、`decor=skip`（全屏本就隐藏装饰，正常）；
   但 `diag-decor-caps` 必须**开始有落盘行**（此前手持档整段跳过，连诊断都不写）。
2. **进入自由窗口**：用系统入口（最近任务长按 / Dock / 多窗手势）进入悬浮窗，**不要只试标题栏菜单**。
   进入后读 `diag-decor-caps`：期望 `pc=yes`、`visible=ok`、`buttons=ok`、`present=true`
   （对应 `decor=restore`），屏幕上应出现系统标题栏与三键。
3. **从自由窗口分屏**：用标题栏三键菜单「分屏」或拖到屏幕边缘；
   判据：`getWindowStatus()` 出现 `SPLIT_SCREEN(5)` **且** 窗口宽度约为整屏一半。
4. **PC / 2in1 回归**：自由窗口拖拽、三键、托盘行为与上一包一致。
5. **手机回归**：冷启动、登录外开（见 JD-013）不受影响。

### 4.4 同时核对假设 B（不改代码，只取证）

在同一台平板的多任务里确认应用是否带 **「PC 应用」角标**；若是，说明
`entry.deviceTypes=["tablet","2in1"]` 命中官方“PC 应用”判定（Tablet 上 PC 应用不支持智慧多窗悬浮窗），
属独立于本修复的结构性问题，请在结论里明确记录，不要与 A 混为一谈。

## 5. 产物核验（若出包）

- `pack.info`：`bundleName=com.dshm.dshclient`、`versionName=1.1.8`、`versionCode=1010018`；
- entry `deviceTypes=[tablet,2in1]`、phone `[phone]`、hostruntime 三端；
- 权限 entry 18 / phone 9 不变；
- HSP 内核心容器仍为 `dsh-core-0.2.2-rc.5+dshm.1-*.zip` 单份。

## 6. 红线声明

- 未改版本号；未 `git commit` / `push`；未动 `signing/**`、`.certs/**`、`dist/**`；
- 未改核心树与插件，无需重打容器；
- 门禁结果如实记录，红的项不回填成绿。

## 7. 完成后

- 结论写入 `JD/from-deveco/20261119-tablet-split-decor-result.md`；
- 更新 `JD/STATUS.md`（JD-012）；
- 回复格式：`JD-012 结论：PASS/FAIL + 产物路径 + 门禁结果 + 真机四项读数`。

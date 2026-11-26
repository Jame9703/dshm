# 交接单：手机端两项修复（登录不跳浏览器 / 最近任务不沉浸）

- **ID**：JD-013
- **提交方**：WorkBuddy
- **接收方**：DevEco（编译 / 真机验证）
- **日期**：2026-11-19 20:38
- **状态**：待编译

## 1. 问题与根因

| # | 现象（仅手机） | 根因 |
|---|---|---|
| 1 | 左下角 DeepSeek 账号点「登录」不拉起系统浏览器；平板 / PC 正常 | `phone/.../WebApp.ets` 的 `OPEN_LINK_SHIM_JS` 落后 entry：① 未剥核心 rc.3 起的 `{type, state: AccountView}` 封套 ⇒ `scanAccount` 永远扫不到 `attempt.phase === 'waiting-browser'`；② 点击拦截只认 `target="_blank"`，普通锚点不接管 |
| 2 | 上滑进最近任务，应用卡片顶部不沉浸（一条独立底色） | 手机壳从未调用 `setWindowLayoutFullScreen(true)`；面板/PC 走 entry，已有该能力 |

## 2. 本次改动

| 文件 | 改动 |
|---|---|
| `phone/src/main/ets/pages/WebApp.ets` | `scanAccount` 与 WS 诊断先剥 `view.state`；锚点改为接管全部 http(s) 并新增 `isSameOriginAsApp`；新增 `topInsetVp`（`TYPE_SYSTEM.topRect`）与 `applyTopInsetPx`，内容 padding = `decorTopInsetNow() + topInsetVp`；owning 分支状态栏底色改为透明 |
| `phone/src/main/ets/entryability/EntryAbility.ets` | 新增 `enterHandheldImmersive()`：主窗就绪后 `setWindowLayoutFullScreen(true)` + 状态栏透明；`reassertWindowChrome` 手持档 owning 分支写透明 |
| `tools/check-open-link-bridge.mjs` | 门禁扩到 phone：封套剥离 / 全锚点 / 同源三条判据 + 对照臂 N |
| `tools/check-decor-button-mode.mjs` | 新增「layout-fullscreen + topInset 成对」断言 |

## 3. 本地验证（WorkBuddy，已执行）

```sh
CODEBUDDY_SAFE_DELETE_ENABLED=0 devecocli build --product phone   # ✅ BUILD SUCCESSFUL
node tools/check-open-link-bridge.mjs      # ✅ 主体 37/0，对照臂 13 组
node tools/check-decor-button-mode.mjs     # ✅ 9/0 + 131/0，A–X 有效
node tools/check-arkts-entry.mjs           # ✅ 0 error
node tools/check-dual-shell-parity.mjs     # ✅
```

## 4. 请 DevEco 执行

1. 随 JD-012 的 `--product default` / `--product phone` 一起编译（无需额外参数）。
2. 跑上表四条门禁。
3. 手机真机：
   - **登录外开**：设置 → 左下角账号 → 登录；应在**无确认框**的情况下直接拉起系统浏览器授权页；
     若失败，抓 `files/diag-openlink`（期望 `auto https://platform.deepseek.com/dsh/authorize?...`）
     与 `diag-web-console` 的 `[dshm-link] ws item attempt=waiting-browser url=yes`。
   - **最近任务沉浸**：应用前台 → 上滑停留；卡片顶部应铺满、状态栏下无独立色带。
   - **前台无回归**：状态栏图标明暗正确、内容没有被状态栏压住（顶部让位生效）。
4. 平板 / PC 回归：本次未改 entry 页面与 phone 以外代码，只需冒烟。

## 5. 红线声明

- 未改版本号；未 `git commit` / `push`；未动 `signing/**`、`.certs/**`、`dist/**`；
- 未改核心树与插件，无需重打容器。

## 6. 完成后

- 结论写入 `JD/from-deveco/20261119-phone-login-immersive-result.md`；
- 更新 `JD/STATUS.md`（JD-013）；
- 回复格式：`JD-013 结论：PASS/FAIL + 门禁结果 + 两项真机读数`。

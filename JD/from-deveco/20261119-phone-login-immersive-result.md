# JD-013 编译结论：手机端两项修复（登录外开 / 最近任务沉浸）

- **执行方**：DevEco
- **时间**：2026-11-19 21:20
- **对应**：JD-013（`from-workbuddy/20261119-2038-phone-login-immersive.md`）
- **结论**：**编译 PASS、门禁全绿、包结构核验通过；手机真机两项读数待用户自测**

## 1. 编译与产物

- 源码改动确认在树：`phone/.../WebApp.ets`（20:23 落盘，含 `isSameOriginAsApp` / `topInsetVp` / `applyTopInsetPx` / 封套剥离）；`phone/.../EntryAbility.ets`（20:20 落盘，含 `enterHandheldImmersive()`）。
- 编译：随 AGC 出包干净构建（`build-agc.mjs` 内部 `devecocli build clean` + release 构建，143 任务 BUILD SUCCESSFUL）；`check-arkts-entry` 0 error。
- 产物（含本修复 + JD-012）：初编入 `…1010018…T125442.app`；**21:30 版本升 1010019（用户明确要求）后重出**：

```text
dist/release-test/dshm-1.1.8-1010019-dshm.1-AGC-invite-20261119T132959.app
size   663,664,417 B
sha256 fb43c767e67c91ac526c82dcc35dacb9a232247efebc2c55a781353d4959e352
```

（与 T125442 内容一致，仅 `versionCode` 不同；beta 分发载体 `dist/beta/…T131404/` 为 1010018 身份。）

## 2. 门禁

| 门禁 | 结果 |
|---|---|
| `check-open-link-bridge.mjs` | ✅ 主体 37/0，对照臂 13 组（含变异体 36 passed / 1 failed ⇒ 判据有牙） |
| `check-decor-button-mode.mjs` | ✅ 9/0 + 131/0；「layout-fullscreen + topInset 成对接线」PASS |
| `check-arkts-entry.mjs` | ✅ 0 error |
| `check-dual-shell-parity.mjs` | ✅ 7 个纯共享 ArkTS 文件逐字节一致 |
| 全量重放（今晨基线 133 项） | ✅ **total=133 failed=0**：`dist/acceptance/20261119-full-gates-jd012-013.txt` |

## 3. 包结构核验（随 T125442）

- `pack.info` 1010018 / 1.1.8；phone `[phone]`；权限 entry 18 / phone 9 不变；HSP 单份 rc.5 容器 ✓
- 独立验签 `verify-app success` ✓；出包后身份还原 ✓

## 4. 真机验证（待用户手机自测）

1. **登录外开**：设置 → 左下角账号 → 登录，应无确认框直接拉起系统浏览器授权页；失败则抓 `files/diag-openlink`（期望 `auto https://platform.deepseek.com/dsh/authorize?...`）与 `diag-web-console` 的 `[dshm-link] ws item attempt=waiting-browser url=yes`。
2. **最近任务沉浸**：应用前台 → 上滑停留；卡片顶部铺满、状态栏下无独立色带。
3. **前台无回归**：状态栏图标明暗正确、内容未被状态栏压住（顶部让位生效）。

平板 / PC 冒烟：本次未改 entry 页面与 phone 以外代码（JD-012 改的是 entry Ability 装饰链，另单验证）。

## 5. 红线

未改版本号；未 `git commit` / `push`；未卸载；未删交付件；未动核心树与插件（无需重打容器）。

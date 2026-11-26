# JD-012 编译结论：平板分屏/小窗修复 A（恢复手持档装饰启动链）

- **执行方**：DevEco
- **时间**：2026-11-19 21:20
- **对应**：JD-012（`from-workbuddy/20261119-2036-tablet-split-decor.md`）
- **结论**：**编译 PASS、门禁全绿、包结构核验通过；平板真机四项（§4.3）待用户自测；假设 B（「PC 应用」角标取证）待平板确认**

## 1. 编译与产物

- 源码改动确认在树：`entry/.../EntryAbility.ets`（20:34 落盘）`afterWindowStageReady()` 早分支已删、统一走完整链（`pcMode = 手持 && FLOATING`，`publishDecorKeysVisible(decorPresent)`）。
- 编译：随 AGC 出包干净构建（`build-agc.mjs` 内部 `devecocli build clean` + release 构建，143 任务 BUILD SUCCESSFUL）；`check-arkts-entry` 0 error。
- 产物（含本修复 + JD-013）：初编入 `…1010018…T125442.app`；**21:30 版本升 1010019（用户明确要求）后重出**：

```text
dist/release-test/dshm-1.1.8-1010019-dshm.1-AGC-invite-20261119T132959.app
size   663,664,417 B
sha256 fb43c767e67c91ac526c82dcc35dacb9a232247efebc2c55a781353d4959e352
```

（与 T125442 内容一致，仅 `versionCode` 不同；beta 分发载体 `dist/beta/…T131404/` 为 1010018 身份。）

## 2. 门禁（§4.2 全跑）

| 门禁 | 结果 |
|---|---|
| `check-decor-button-mode.mjs` | ✅ 第一组 9/0、第二组 131/0，对照臂 A–X 有效（禁止早分支 + 按 `decorPresentOf` 发布） |
| `check-window-mode.mjs` | ✅ 27/0 |
| `check-arkts-entry.mjs` | ✅ 0 error |
| `check-dual-shell-parity.mjs` | ✅ 双壳 7 个纯共享 ArkTS 文件逐字节一致 |
| `check-bridge-methodlist.mjs` | ✅ 通过 |
| 全量重放（今晨基线 133 项） | ✅ **total=133 failed=0**：`dist/acceptance/20261119-full-gates-jd012-013.txt` |

已知无关项照旧：`check-free-window-decor.mjs` harness 自身 `ReferenceError`（改动前基线同样抛），不作判据。

## 3. 包结构核验（随 T125442）

- `pack.info`：`com.dshm.dshclient` / 1.1.8 / 1010018；entry `[tablet,2in1]`、phone `[phone]`、hostruntime 三端 ✓
- 权限 entry 18 / phone 9 不变；HSP 单份 `dsh-core-0.2.2-rc.5+dshm.1`（203,023,707 B，`61749b16…`）✓
- 独立验签 `hap-sign-tool verify-app`：`verify-app success` ✓
- 出包后身份还原（`AppScope/app.json5` bundleName=`com.dshm.dshclient`）✓

## 4. 真机验证（待用户平板自测，缺一项不算闭环）

1. 冷启动探针：`status=1 FULL_SCREEN`、`decor=skip` 可接受；`diag-decor-caps` 必须开始有落盘行。
2. 系统入口进自由窗口（最近任务长按 / Dock / 多窗手势，不要只试标题栏菜单）：期望 `pc=yes`、`visible=ok`、`buttons=ok`、`present=true`（`decor=restore`），屏幕出现系统标题栏与三键。
3. 自由窗口分屏：`getWindowStatus()` 出现 `SPLIT_SCREEN(5)` 且窗口宽度约半屏。
4. PC / 2in1 回归：本机 2in1 现装为用户 DevEco 签名件（repo 证书 `8A765053…` 与之 `9568332` 不一致，无法覆盖安装验证），自由窗口拖拽 / 三键 / 托盘由用户在下次安装 T125442 系产物后确认。
5. 假设 B 取证：同一平板多任务里确认应用是否带「PC 应用」角标；结论里单独记录，不与修复 A 混看。

## 5. 红线

未改版本号；未 `git commit` / `push`；未卸载；未删交付件；未动核心树与插件（无需重打容器）。

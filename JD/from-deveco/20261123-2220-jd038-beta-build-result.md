# JD-038 邀测反馈四项修复 — 编译与 Beta 出包结论

- 提交方：DevEco
- 对应交接单：`JD/from-workbuddy/20261123-2123-pet-pax-touch-statusbar-wake.md`
- 时间：2026-11-23 22:20
- 结论：**五项修复全部落地并已编入 Beta；交接单 §2.4 有一处真实编译错误已由 DevEco 修复；Beta 已出，待真机测试。**

---

## 1. 修复落地核验（逐项实证）

| # | 修复 | 核验证据 |
|---|---|---|
| 1 | PAX 解包按字节 | `hostcore/app/tar-gz.cjs` `parsePax(buf)` Buffer 化 + 两处 `parsePax(tarBuf.subarray(...))` 调用点；resfile 同步 27/27；离线回归 6/6 PASS（tar-slip / symlink / PAX 中文名可落盘 / size 正确 / 控制字符坏名拒绝） |
| 2 | 桌宠透明区穿透 | `PetWeb.ets` `applyTouchableAreas()`（201/801/1300016 自动降级整窗可触；2px 容差 + 120ms 节流；`setBounds` settle / `setInputRegions` / `onPageEnd` 三触发点）；`SET_WINDOW_TOUCH_AREAS` 已声明为 entry 第 20 条（reason=`pet_touch_areas_reason`） |
| 3 | 平板状态栏沉浸 | `WebApp.ets` `isTabletForm()`（6922）+ 平板分支恒 `SYSTEM_BAR_HANDOFF_BG`（7031-7033）；`EntryAbility.enterTabletImmersive()` 图标明暗改 `windowChromeFor(appearanceMode()).lightIcon`（2996-3007） |
| 4 | 亮屏回前台 | `EntryAbility.ensureWindowShown()`（2393）只在 `WindowStatusType.MINIMIZE` 才 `restore()`；不再兜底 `showWindow()` |
| 5 | Alt+Tab 空白卡片 | `PetAbility.ets` host（198）与 sub（222）均 `setWindowFocusable(false)`；`module.json5` `PetAbility.excludeFromMissions: true`（421），**已核入包** |

## 2. DevEco 补齐的两类缺口

### 2.1 交接单代码错误：`getWindowStatus()` 误用 Promise（编译必炸）

- 交接单 §2.4 原实现写 `target.getWindowStatus().then(...)`。SDK 实证（`@ohos.window.d.ts:8452`）：
  `getWindowStatus(): WindowStatusType` 是**同步** API（@since 12，读不到抛 801/1300002），不是 Promise。
  `check_ets_files` 报 severity=1（`Property 'then' does not exist on type 'WindowStatusType'`），hvigor 编译必失败。
- **已修**（`EntryAbility.ets:2400-2427`）：改为 try/catch 同步读取（与本文件 `readWindowStatusOf` 同口径），
  读失败按「不动作」记 debug 日志；语义与交接单一致（只有 MINIMIZE 才恢复）。
- 修复后 `devecocli build --product default` BUILD SUCCESSFUL。

### 2.2 交接单遗漏的门禁/构建脚本同步（entry 19 → 20）

WorkBuddy 声明了第 20 条权限但没同步判据，导致三条链路红/炸：

- `tools/check-permission-surface.mjs`：`EXPECTED` 补 `SET_WINDOW_TOUCH_AREAS`（第 20 位）+ 自检样本
  `pet_touch_areas_reason` + 文案 19→20。真跑 PASS + `--self-test` 12 变异体全过。
- `tools/build-beta.mjs`：`wantEntryPerms` 19→20（否则 beta 核验步必炸）+ README 文案。
- `tools/build-agc.mjs` **未动**：其 ACL 校验（`build-agc.mjs:384`）要求 entry 全部 system_basic 声明都在
  release Profile 的 `allowed-acls` 里 ⇒ **在 AGC 批 `SET_WINDOW_TOUCH_AREAS` ACL 之前，AGC 包会被硬阻断**。
  交接单 §2.2 所说「strip-ungranted-acl-perms.mjs 会在签名前摘掉」**不在 build-agc 流程里**
  （该脚本仅 `tools/sign-release-hap.ps1` 引用），此认知需要修正。

## 3. 门禁与构建记录

| 项 | 结果 |
|---|---|
| `check-permission-surface`（真跑 + --self-test） | PASS（entry 20 / phone 9；12/12 变异体） |
| `check-decor-button-mode` | PASS（9/0 + 134/0） |
| `check-auth-return` / `check-feature-wiring` / `check-sidebar-shim-css` / `check-market-bridge`（142/0） / `check-open-link-bridge`（37/0+13） | 全 PASS |
| `check-dshm-installer.cjs` 离线段（§1/§2/§2b，同门禁源码内联） | 6/6 PASS |
| `check-dshm-installer.cjs` 全量 | **本机不可跑**：§4 起 `installSpec('debug@4.3.4')` 等真实下载 npm 包，本机网络挂起（>10min）。属环境限制，非代码问题 |
| `place-host-app` + `assert-resfile-sync` | 27/27 一致 |
| `devecocli build --product default` | BUILD SUCCESSFUL（1 min 07 s） |
| Beta Profile ACL WARN | 5 条未授权（CUSTOM_SANDBOX / READ_PASTEBOARD / READ_WRITE_DESKTOP / ACCESS_USER_FULL_DISK / **SET_WINDOW_TOUCH_AREAS**）——既有 WARN 机制，debug 实测可安装；新权限运行期 201 自动降级 |

## 4. Beta 产物

```text
dist/beta/DSHM-beta-1.1.8-1010020-20261123T141229/
├── DSHM-beta-1.1.8-1010020-combined-debug.app   669,937,094 B
│   sha256 7a8290865eff3bef1fcbb9f7136d1622f3c67136f9b72b511a3c07e2f6f8f101
├── tablet/  entry-debug.hap + hostruntime-debug.hsp
├── phone/   phone-debug.hap + hostruntime-debug.hsp
├── SHA256SUMS（5/5 OK）
└── README.txt
```

- 版本：1.1.8 / **1010020**（沿用用户已拍板的 AGC r50 版本号；Beta 身份 `com.dshm.dshmbeta` / debug）
- 独立验签：`hap-sign-tool verify-app` 成功
- entry 包内：20 条权限（含 `SET_WINDOW_TOUCH_AREAS`）；`PetAbility.excludeFromMissions=true` 已核入
- phone 包内：9 条权限
- HSP 内 `tar-gz.cjs` 与修复源码**逐字节一致**（PAX 修复确定随包）
- 构建后身份还原核验：`AppScope/app.json5` = `com.dshm.dshclient`，权限面门禁在还原身份上复跑仍绿

## 5. 真机测点（沿用交接单 §6）

五组测点照原单执行：6.1 PAX/桌宠安装链、6.2 透明区穿透（注意本包 ACL 未批 ⇒ 预期走 201 降级，
日志出现「setTouchableAreas rejected: 201，降级整窗可触」属**预期**）、6.3 平板状态栏、6.4 亮屏回前台、6.5 Alt+Tab。

## 6. 遗留与提示

1. **AGC 出包前置**：需先在 AGC 申请 `SET_WINDOW_TOUCH_AREAS` 的 ACL 并重发 release Profile，
   否则 `build-agc.mjs` 按 ACL 敏感表硬失败（见 §2.2）。批下来之前 AGC 包出不了。
2. `check-dshm-installer.cjs` 的联网段（§4+）在有外网的机器上应复跑一次全量。
3. 交接单口径修正：「签名前摘除」机制不在 build-agc / build-beta 流程内，勿再据此推断 AGC 可编译。

## 7. 台账同步（DevEco 收尾补记）

- `AGENTS.md`：权限面引用 19→20（§3.1 / §3.3 两处 / §5.4 / §6.3 / §6.4 / §8 红线，共 7 处）。
- `docs/FEATURES.md`：§1 版本头 1010019→1010020；权限面行 entry 18→20；dsh-pet 行补穿透 / 降级 / excludeFromMissions 判据。
- `docs/README.md` §9：补录 `docs/200-ACCESS_USER_FULL_DISK必要性说明`（JD-034 遗留未索引，`check-doc-index` 曾红，已修）。
- 复跑：`check-doc-index` / `check-doc-refs` / `check-permission-surface` 全部 rc=0。

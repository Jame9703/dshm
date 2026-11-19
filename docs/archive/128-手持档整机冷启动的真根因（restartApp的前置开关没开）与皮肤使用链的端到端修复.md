# 128 · 手持档「整机冷启动」的真根因（`restartApp()` 的前置开关没开）与皮肤「使用」链的端到端修复

> 承接 `docs/125`（皮肤市场托管安装把 `installPlugin` 补上）与第 57 轮（`dshm-market-bridge` 给已安装的
> `dsh-skin-market` 就地补 `restartAvailable`）。用户这一轮原话是
> 「手机已连接，继续测试一下在手机端的情况，然后接着修手机平板端的问题」。
> 本轮把**点击「使用」→ 重启**这一步修到底：`restartAvailable:true` 已让按钮能用，但真机点下去
> **App 直接变砖**（Host 已退、界面停在「连接已断开」、同进程再也起不回 Host）。
> **性质：两处 ArkTS 侧改动**（`AppAbilityStage.ets` 开恢复开关 + `EntryAbility.ets` 兜底窗口 3 s→5 s 与注释订正）；
> `hostcore/**`、`core-recipe.json` **未动** ⇒ `coreVersion` **未升**（仍 `0.2.1-alpha.1+dshm.27`，理由见 §4）。
> 真机：手机 `62T0225B18039433`（`const.product.devicetype=phone`），覆盖安装、数据未动。

---

## 0. 一句话结论

| # | 事 | 结论 |
|---|---|---|
| 1 | 点「使用」为什么变砖 | 皮肤市场的重启走 `appExit` → 宿主写 `host-exit-mode=app-restart` 后**干净退出**，ArkTS 侧 watcher 收到后调 `appRecovery.restartApp()` —— 而**平台在没调过 `enableAppRecovery()` 时会让它静默地什么都不做**（`AppRecovery::ScheduleRecoverApp()` 里 `return false`，**不抛异常**）⇒ 进程 pid 不变、Host 已死。见 §1 |
| 2 | 真根因（不是调用姿势） | `isEnable_` **只**由 `enableAppRecovery()` 置真；`setRestartWant` / `restartApp()` 的调用方式都没错。补一行开关即通。见 §1.2 |
| 3 | 修法 | 开关放在 `AppAbilityStage.onCreate()`（早于任何 ability 创建 ⇒ 平台上按 flag 建的恢复记录才吃到我们的档），档位取 **`RESTART_WHEN_JS_CRASH`**（最窄的非 `NO_RESTART` 档；`NO_RESTART` 会把**手动**重启也一起废掉）。见 §1.3 |
| 4 | 兜底仍在 | 开关补上后 `restartApp()` 仍有三条不生效的路（1 分钟限流 / 无前台 ability / 平台侧失败），而它**连失败都不抛** ⇒ 保留「N ms 后进程还在就干净退出」的兜底，窗口 3 s → **5 s**（给平台「杀进程→拉新实例」留余量）。见 §1.4 |
| 5 | 为什么不"同进程重起 Host" | 原生层 `g_started` 确实会在 `node::Start` 返回后复位（`docs/119` 的 E119），所以那条路在原生层是通的；但手持档有更硬的约束——**同一进程只能初始化一次 QEMU** ⇒ 同进程重起的 Host 起不回 guest 虚拟机 bash 通道。整机冷启动是这里唯一正确的语义。见 §1.5 |
| 6 | 皮肤链的另一半 | `installation:"missing"` 不是安装失败，而是启动自愈 `quarantineAfterBootFailure()` 把 `package.json` 的 `dependencies` 清空（第 57 轮事故的连带副作用，**保留是 by design**）；按代码自带的手工恢复路径抄回即可。见 §2 |
| 7 | 另一条容易被误读的读数 | `POST /dsh-skin-market/restart` 回 **409** 不是重启坏了，而是**还没点「使用」**（`canRestartSkin()` 只认 `activation ∈ {active, restart-required}`）。判据与话术见 §3.1 |

---

## 1. 缺陷 A：`appRecovery.restartApp()` 是**静默的 no-op**

### 1.1 真机读数（三个时刻，全部是 hilog 原文）

**① 修复前，且**已经**补过 `setRestartWant`（2026-10-09 13:52:02，pid 46299 全程不变）：**

```text
13:52:02.769 46299 I A00000/com.dshm.dshclient/entry/ability: DSHM-RESTART 收到整机冷启动请求，转入整机冷启动
13:52:02.770 46299 I A00000/com.dshm.dshclient/entry/ability: DSHM-RESTART 已指定重启目标：com.dshm.dshclient/EntryAbility
13:52:02.772 46299 I A00000/com.dshm.dshclient/entry/ability: DSHM-RESTART 已请求整机冷启动（进程应被平台重启）
13:52:05.774 46299 E A00000/com.dshm.dshclient/entry/ability: DSHM-RESTART 冷启动未生效（3000 ms 后进程仍在，调用已发出=true），退回干净退出以免停在死态
13:52:05.774 46299 I A00000/com.dshm.dshclient/entry/ability: 开始退出应用：整机冷启动未生效（兜底退出）
```

这一跑的价值在于**排除法**：`setRestartWant` 已经调了、日志也如实打出来了，**平台还是一动不动**
⇒ 缺的**不是** `setRestartWant`，而是别的东西。同一次读数还证明：Host 那边早已 `process.exit(0)` 干净退出
（`dshm-host.log` 的 `!! process.exit(0)：停止路径放行，真正退出`），所以界面停在「连接已断开」。

**② 修复后（2026-10-09 13:59:01，**pid 52485 → 53399**）：**

```text
13:59:01.527 52485 I .../entry/ability:      DSHM-RESTART 收到整机冷启动请求，转入整机冷启动
13:59:01.528 52485 I .../entry/ability:      DSHM-RESTART 已指定重启目标：com.dshm.dshclient/EntryAbility
13:59:01.531 52485 I .../entry/ability:      DSHM-RESTART 已请求整机冷启动（进程应被平台重启）
13:59:01.889 53399 I .../entry/abilitystage: DSHM-RESTART 已开启应用恢复（restartApp 生效的前置条件）
13:59:01.890 53399 I .../entry/abilitystage: onAcceptWant → 实例 key = main
13:59:08.709 53399 I .../entry/ability:      DSHM-AUTO 启动 Host：ok=true url=http://127.0.0.1:3120 note=核心 0.2.1-alpha.1+dshm.27 已启动
```

**同一条 hilog 流里 pid 从 52485 跳到 53399**，且新进程打的是 `entry/abilitystage` 的
`AbilityStage.onCreate` ⇒ 平台真的把旧进程杀掉、在**全新进程**里拉起了 `EntryAbility`。
没有出现兜底行 ⇒ 这次重启是**平台自己的重启**，不是我们的兜底退出。

落盘读数同步：

| 读数 | 修复前 | 修复后 |
|---|---|---|
| `host-ready.json` 的 `pid` | 46299（不变） | 52485 → **53399** |
| `host-ready.json` 的 `startedAt` | 未变 | `05:58:31.142Z` → **`05:59:08.955Z`** |
| `ps -ef` 里的 dshclient | 还在（死态） | 新 pid / 新 render 进程 |
| `GET /dsh-skin-market/state` | — | `installation=installed`、`activation=active`、`primary=true`、`restartAvailable=true` |

### 1.2 平台源码判据（这才是真根因）

`frameworks/js/napi/app/recovery/app_recovery_api.cpp` 里 `restartApp()` 落到的就是一句话：

```cpp
napi_value OnRestartApp(...) { AppRecovery::GetInstance().ScheduleRecoverApp(StateReason::DEVELOPER_REQUEST); ... }
```

而 `frameworks/native/ability/native/recovery/app_recovery.cpp`：

```cpp
bool AppRecovery::ScheduleRecoverApp(StateReason reason)
{
    if (!ShouldRecoverApp(reason)) { return false; }          // restartFlag_ == NO_RESTART 时这里就 false
    if (!isEnable_) {                                        // ← 没调过 enableAppRecovery() 就是这支
        if (GetParameter("const.dfx.sub_health_recovery.enable", "") == "true") { DoRecoverMainApp(reason); return true; }
        return false;                                        // 静默返回：JS 侧得到 undefined，不抛、不打日志
    }
    if (abilityRecoverys_.empty()) { return false; }          // "null ability"
    ...
}

void AppRecovery::EnableAppRecovery(uint16_t restartFlag, uint16_t saveFlag, uint16_t saveMode)
{ isEnable_ = true; restartFlag_ = restartFlag; ... }         // isEnable_ 只在这里被置真
```

`ShouldRecoverApp()` 的第一行是 `if (restartFlag_ == RestartFlag::NO_RESTART) return false;`，
而 `StateReason::DEVELOPER_REQUEST`（我们的手动路径）在**任何**非 `NO_RESTART` 档下都 `ret = true`
⇒ 结论有两条：

- **不开 `enableAppRecovery()` ⇒ 手动重启也是 no-op**（本次真机 100% 复现）；
- **`NO_RESTART` 档会把手动重启一起废掉** ⇒ 兜底开关不能用它。

还有一条同源但容易踩的：`DoRecoverApp()` 只对**处于前台**的 ability 生效
（`abilityRecoverys_.front()->IsOnForeground()`），后台时调用同样不重启 —— 一并记进 §7。

### 1.3 修法：在 `AppAbilityStage.onCreate()` 打开开关

`entry/src/main/ets/abilitystage/AppAbilityStage.ets`：

```ts
appRecovery.enableAppRecovery(appRecovery.RestartFlag.RESTART_WHEN_JS_CRASH,
  appRecovery.SaveOccasionFlag.SAVE_WHEN_ERROR, appRecovery.SaveModeFlag.SAVE_WITH_FILE);
```

三个选择各有依据：

- **为什么放 `AbilityStage` 而不是 `EntryAbility.onCreate`**：平台是按**ability 创建当时**的 flag
  给该 ability 建恢复记录的（`AppRecovery::AddAbility()` 里 `EnableAbilityRecovery(useAppSettedValue_, ...)`），
  而 `AbilityStage.onCreate` **早于任何 ability 创建** ⇒ 只有在这里开，能力才吃到我们的档。
  本类与 HAP 一一对应，只跑一次，符合平台口径。
- **为什么 `RESTART_WHEN_JS_CRASH`（0x0001）**：非 `NO_RESTART` 档里**最窄**的一个，既满足手动重启的
  前置条件，又只把「JS 崩溃自动拉起」这一种崩溃语义带进来，不额外打开 `APP_FREEZE` / `CPP_CRASH` 的自动恢复。
- **不写死默认值**：三个参数全部显式给，避免平台默认值将来变化时行为漂移。

### 1.4 兜底退出保留，窗口 3 s → 5 s

`EntryAbility.restartWholeApp()` 的结构**不变**（`setRestartWant` → `restartApp()` → 超时兜底），
只把 `RESTART_FALLBACK_MS` 从 `3000` 提到 `5000`：平台的「杀进程 → 拉起新实例」需要一点时间，
3 s 有与它抢同一个进程的风险。语义仍是「窗口过去进程还在 ⇒ 重启没生效 ⇒ 走已验证的干净退出」
（`exitApp`：摘托盘 → 通知托盘进程 → 停核心 → `terminateSelf`）；冷启动真生效时进程直接消失，
定时器永不触发。函数头注释同时订正了旧稿的一处**事实错误**（原文写「`g_started` 闩永不复位」，
而 `hostruntime/src/main/cpp/dshhost.cc` 的 E119 注释与代码都表明它**会**在 `node::Start` 返回后复位）。

### 1.5 为什么不走「同进程重起 Host」（更快的路，但不成立）

`dshhost.cc` 的 E119 修过 `g_started` 的复位，所以"停掉再起"在原生层是允许的，看起来更优雅
（省掉整机冷启动）。但手持档有一条更硬的约束：**同一进程只能初始化一次 QEMU**（`docs/119`）
⇒ 同进程重起的宿主会起不回 guest 虚拟机 bash 通道；再加 WebView 侧的端口/令牌也要重新落地。
**整机冷启动是这里唯一正确的语义**，这条理由已写进 `EntryAbility.ets` 的函数头注释。

---

## 2. 缺陷 B（承第 57 轮）：`installation:"missing"` 是启动自愈清了 `dependencies`

皮肤装上、`GET /state` 却报 `"installation":"missing"`。取证链是完整的：

```text
[2026-10-09T05:33:01.059Z] 【启动自愈】上次启动失败（2026-10-09T05:18:04.099Z stage=BOOT_40_PROFILE_BOOT
  reason=启动失败：Error: dsh: host preparation failed: service "appExit" has been registered at <root>…）。
  package.json 的 dependencies/peerDependencies 已清空（共 3 行，原文件备份为 package.json.quarantine-1791523981039）。
```

- 那条 `.dshm-boot-failed` 标记来自**第 56 轮我自己**的 `provide("appExit")` 撞名事故
  （`docs/107`/`dshm-market-bridge` 头注里记着：cordis 的 `provide` 撞名会抛，且抛在 boot 回调期间 ⇒ 整个 Host 起不来）。
- 「回到纯种子才叫自愈」是 `dshm-user-rows.js` 里 `quarantineAfterBootFailure()` 的**设计**，所以**不改它**。
- 处置按代码自带的手工恢复路径：用宿主 Python 桥把隔离件里的 `dependencies` 抄回 live `package.json`
  （先备份 `package.json.pre57backup`，断言两侧只差 `dependencies` 一个字段）。三包磁盘版本实测与备份逐字一致：
  `{'dshmarket':'1.66.9','dsh-skin-market':'0.1.57','dsh-theme-macintosh':'0.1.2'}`。
**本轮复验**：`dsh/home/.dshm-boot-failed` **不存在**，`dshm-host.log` 里最后一次自愈仍是 05:33 那一次
⇒ 修好重启链之后，这一轮冷启动是干净的，缺陷没有复发。

---

## 3. 修后真机复验（读数为证）

### 3.1 先分清 409 与"重启坏了"

第一次拿 API 直连复现时收到的是 **409**：

```text
POST /dsh-skin-market/restart  { "skinId": "fengb3.dsh-theme-macintosh" }  →  409
{"error":"请先选择并使用此皮肤，再重新启动 DeepSeek Harness"}
```

判据在 `dsh-skin-market/lib/routes.js`：`canRestartSkin(state)` 只认 `activation ∈ {active, restart-required}`。
当时 `GET /state` 是 `activation=inactive`（自愈清 `dependencies` 的余波）⇒ **409 是"还没点使用"，不是重启坏了**。
`POST /activate` 回 202、轮询到 `activation=active` 之后再 `POST /restart` 才进入 §1.1 ② 那条链。
这一条要写进自检脚本的话术里，否则下次很容易把 409 误判成重启缺陷。

### 3.2 端到端结果

`注销`（安装皮肤）→ `使用`（activate，202）→ 重启（`POST /restart`）：

- 连接在宿主退出瞬间被切断（`Invoke-WebRequest` 报 send error，属预期——宿主先退再拉新实例）；
- 新进程 pid 53399 起、`AbilityStage` 打印恢复开关已开、`Host` 6.5 s 后起来；
- `GET /state`：`installation=installed`、`activation=active`、`primary=true`、`installedVersion=0.1.2`、`restartAvailable=true`；
- 皮肤 macintosh **肉眼已生效**（顶栏/侧栏 mac 风格）——这一条是用户在 57 轮前的肉眼读数，本轮不重复截图。

### 3.3 自带插件在重启后全部重新接管（回归面）

冷启动后的 `node-output.log`（05:59）：

```text
[05:59:03.462Z] [dshm-market-bridge] 皮肤市场 desktop 分支的 restart：已是打过补丁的形态（跳过）
[05:59:03.462Z] [dshm-market-bridge] 已接管市场包操作：profile=ondevice，队列=…/install-queue（原因：随包假壳无法 spawn）
[05:59:05.964Z] [dshm-vm-bash] 已接管 ctx.subprocess.spawn（手持档（spawn 不可用）且 VM 资产齐备）
[05:59:05.964Z] [dshm-vm-bash] 已接管 ctx.subprocess.spawnTerminal（手持档（spawn 不可用）且 VM 资产齐备）
[05:59:08.565Z] [dshm-workspace-claim] 注册表里已有 1 条工作区 ⇒ 本次不新增（本插件只在注册表为空时登记一次）
```

⇒ 整机冷启动这条链把「Host 侧重启后所有自带插件重新挂载」也一并验过了。

### 3.4 装机过程（纪律）

一律 `.\tools\update-device.ps1`（构建 → `hdc install -r` 覆盖安装 → 校验用户数据 → 端侧就绪）：
`home 指纹 links=8 size=3440` 装前=装后、核心树 `+dshm.27` 在位、exec 探测手持档判据通过。
**无卸载、无删数据。** 注意该脚本第 6 步自己会 `aa start` 把 App 拉回来 ⇒ 上一轮的"变砖现场"
是靠**重装包**解掉的，不是靠修好的代码；本轮才是真正用修好的代码验的（§1.1 ②）。

---

## 4. `coreVersion` 判定：**未升**

本轮两处改动都在 **ArkTS 侧**（`entry/src/main/ets/abilitystage/AppAbilityStage.ets`、
`entry/src/main/ets/entryability/EntryAbility.ets`），`hostcore/**` 与 `hostcore/core-recipe.json`
**一个字节都没动** ⇒ 按 `AGENTS.md` 的口径（核心树内容有变才递增）**不升**，仍 `0.2.1-alpha.1+dshm.27`。

---

## 5. 门禁

本轮**没有**新增/修改 `tools/` 下的任何门禁脚本，改动是纯 ArkTS 两文件；`AGENTS.md` 列的
"只需仓库内文件"那 18 条不受影响（未跑；本轮改动不在它们的覆盖面内）。本轮新增的两条注释级
事实订正（§1.4）也只落在 ArkTS 注释里，不触及任何门禁的锚点。

---

## 6. 清理

- 删 `dist/_t57/`（本轮临时：`patch-entry.mjs` / `py.mjs` / `hilog*.txt` / `skin-*.js` / `*.jpeg` 等 19 项 / 5.1 MB）
  与 `dist/_t55/`（第 55/56 轮残留 34 项 / 0.7 MB）——两者都不被任何文档引用（已 `rg` 确认）。
- 删 `dist/localtest/`（11.1 MB，早期门禁脚本的运行工作区，`rg` 确认无引用）。
- 清 `%TEMP%\dshm*` 残留 **37 项**（门禁脚本自己留下的 `dshm-fsloc-gate-*` / `dshm-skills-*` / `dshm-vm-gate-*`
  工作目录，与第 116 轮同类）。删除前逐个校验父目录就是 `%TEMP%` 且不含非本仓产物。
- `dist/sideload/`（正式侧载包）与 `dist/acceptance/`（验收留档）**未动**。

---

## 7. 已知限制与下一步

**已知限制（都写进了代码注释，避免下次当新 bug 查）**

1. `restartApp()` 有**1 分钟限流**：两次调用间隔 ≤ 1 分钟 ⇒ 平台**只退出不重启**。用户在这个窗口内
   连点两次「使用」，会落到兜底退出（App 退出、重开即生效），**不会**留在死态。
2. `DoRecoverApp()` 只对**前台** ability 生效 ⇒ 应用在后台时请求重启同样不重启，仍由兜底接住。
3. 本轮顺带把「JS 崩溃 ⇒ 自动重启」这一种崩溃语义带进来了（`RESTART_WHEN_JS_CRASH` 的必然结果）。
   这是**刻意的**最窄选择：会话/工作区都在磁盘上，崩了能回来比原地死掉好；且不打开
   `APP_FREEZE` / `CPP_CRASH` 的自动恢复。

**下一步（真机待验 / 待用户决定）**

1. **用户在手机上点一次「使用」**（走 UI，不经 API），确认：皮肤切过去、App 自己回来、不出现「连接已断开」死态。
2. **PC 档回归**：PC 走的是同一条 `host-exit-mode=app-restart` → `restartWholeApp()` 链，
   `enableAppRecovery()` 的开关是**所有档共用**的 ⇒ PC 上也要确认皮肤/插件「重启后生效」正常、且托盘/三键不受影响。
3. `dist/sideload/` 未更新：本轮产物是 debug HAP（`entry/build/default/outputs/default/entry-default-signed.hap`，381.6 MiB），
   正式侧载包需另走 release 签名流程。

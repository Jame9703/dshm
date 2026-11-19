# 159 移动端「两个进程」与皮肤市场「一键安装」两条回归的根因与修复 + 本批 AGC 上架件（`+dshm.49`）

## 结论

本轮两件事，都是用户真机报的回归，各自修在**唯一一处**根因上；末尾用户追加
「再出 agc 的 APP 包」，同批 `.app` 也已出并复核（§3）。

1. **移动端后台冒出两个进程** —— 根因在托盘那条链：`StatusBarTray.hold()` 是全仓
   **唯一**一处 `processMode = NEW_PROCESS_ATTACH_TO_STATUS_BAR_ITEM` 用法，而手持档
   （手机 / 平板）上 `addToStatusBar` **每次都会成功**（关键事实：不是"系统拒绝、
   挂不上所以没有第二个进程"）⇒ 每次启动都真的多拉一个独立 Ability 进程贴图标。
   修法是一条分档判据 + 一处早退：`StatusBarTray.applicable()` /
   `EntryAbility.setupTray()`；**PC / 2in1 档一个字节不变**。见 §1。
2. **皮肤市场的皮肤全部都要手动安装** —— 根因是**补丁时机**：市场挂载契约补丁只在
   **启动那一刻**贴一次（`pack-core` 注入的 boot 回调），而皮肤市场几乎总是**启动之后**
   经「设置 → 插件 → 项目地址」装进来的 ⇒ 那次贴到的是 `未安装（ENOENT…）`，落盘的
   `dsh-skin-market/lib/index.js` 永远是上游原形 ⇒ 市场把宿主当官方 Desktop
   （`hostKind:'desktop'`）⇒ 目录里 `review=verified` 而 `install.desktop.mode=manual-only`
   的那批皮肤全被挡成「需手动安装」（同一缺陷的**首次**修复见 `docs/129`，本次是它的
   **重放**缺口）。修法是**装完重放**：新增 `hostcore/app/dshm-market-patch.cjs`
   （`replayMarketContractPatch()`），在安装成功之后、`<id>.done` 写出之前，
   用与 boot **同一份判据函数**再贴一次。`coreVersion` → `+dshm.49`。见 §2。
3. **本批 AGC 上架件**：`+dshm.49` 的 `.app` 已出，`verify-app success`、
   `type=release`、权限恒 **8 条**、容器 3 条目、0 个 apk 条目。见 §3。

## 1. 移动端「两个进程」：手持档不挂托盘

### 1.1 现场与根因

用户报的形态是"移动端后台会冒出两个进程、卡"。取证落在两处：

- **手持档上托盘挂载其实是成功的**：手机 `62T0225B18039433` 的
  `files/diag-tray`，2026-10-14 08:50～13:14 约 **50 行 `install ok：addToStatusBar 成功`**
  ⇒ 这条链在手持档不是"挂了但没用上"，而是**每一步都真的走通了**。
- **`hold()` 是唯一能凭空造出第二个进程的地方**：全仓 `processMode` 只有
  `StatusBarTray.hold()` 这一处用法（`NEW_PROCESS_ATTACH_TO_STATUS_BAR_ITEM` +
  `STARTUP_HIDE`），它的存在意义是"窗口收进后台后，让主进程不被挂起回收"。

而这两件事在手持档都**没有对应的需求**：

1. 托盘第一职责是"窗口收进后台 → 左键唤回"的回程入口，而手持档三键「关闭」是
   系统官方行为 = 退出应用（`EntryAbility.handleWindowWillClose` 手持档第一行就返回），
   不存在"收进后台"这个状态，也就没有需要唤回的对象；
2. 手持档的后台保活由 `KeepAlive` 长时任务统一承担 ⇒ 这个进程在手持档上纯属多一份
   常驻内存，并且是用户在进程列表里能看到的那个"第二个 DSHM 进程"。

### 1.2 修法（两处改动，PC / 2in1 逐字不变）

| 落点 | 改动 |
|---|---|
| `entry/src/main/ets/system/StatusBarTray.ets` | 新增 `static applicable(context)`：`!isHandheldForm()` ⇒ `true`；手持档 ⇒ 做**一次性摘残留**（`removeFromStatusBar`，成功 / 失败都写 `diag-tray`）后返回 `false` |
| `entry/src/main/ets/entryability/EntryAbility.ets` | `setupTray()` 首行 `if (!StatusBarTray.applicable(ctx)) { hilog…; return; }` —— 手持档**不 install 也不 hold** |

三条纪律：

- **判据只有一条**：`isHandheldForm()`（与 `bindGeometry` / `handleWindowWillClose`
  等处同源），PC / 2in1 档拿到的仍是原来的整条链；
- **摘残留必须有**：系统侧的状态栏注册是按 bundle 存的 ⇒ 老版本（手持档还挂的那一版）
  或异常退出可能留下一个没人管的图标，而手持档既然不再 `install`，就再没有别的路径去摘它；
- **"跳过"也要留痕**：跳过与"尝试挂但失败"必须事后可分，故两条分支都写 `diag-tray`。

### 1.3 真机读数（手机 `62T0225B18039433`，覆盖安装后冷启动）

```
files/diag-tray 尾部：
2026-10-14T13:14:00.544Z install ok：addToStatusBar 成功          ← 旧版本（还会挂）
2026-10-14T13:31:15.279Z install skip：手持档（手机/平板）不挂托盘，不拉后台 Ability 进程
2026-10-14T13:33:21.672Z install skip：手持档（手机/平板）不挂托盘、不拉后台 Ability 进程（顺带摘掉了上次遗留的注册）

ps -ef | grep dshclient：
com.dshm.dshclient          pid 44273
com.dshm.dshclient:render   pid 44802   ← Web 引擎渲染进程（系统按需创建，不是本应用拉起的 Ability）
（**没有** :entry:BackGroundAbility）
```

## 2. 皮肤市场「一键安装」：装完重放挂载契约补丁

### 2.1 根因（补丁贴早了）

端侧皮肤市场的"一键安装"取决于市场自己的**挂载契约分支**：`hostKind` 判成官方
Desktop 时，`install.desktop.mode=manual-only` 的那批皮肤一律只给"手动安装"
（机制与首次修复见 `docs/129`）。让市场判成 `dsh` 的那处就地改写
（`patchMarketCliBranch()`，在 `hostcore/plugins/dshm-market-bridge/lib/index.js`）
由 `pack-core` 注入核心树的 **boot 回调**，也就是**只在启动那一刻贴一次**。

而皮肤市场本身是"设置 → 插件 → 项目地址"装进来的一个包 —— 真机
`node-output.log` 留下的原话（本轮唯一证据，12:27:13）：

```
[dshm-market-bridge] 皮肤市场挂载契约改写：未安装（ENOENT: …/profiles/ondevice/node_modules/dsh-skin-market/lib/index.js）
[dshm-market-bridge] 已接管市场包操作：profile=ondevice，队列=…/dsh/home/install-queue
```

市场是 12:35:09 才装进来的 ⇒ **boot 那次必然贴空**，落盘的市场文件永远是上游原形。

### 2.2 修法（装完重放，位置有讲究）

- 新增 `hostcore/app/dshm-market-patch.cjs`（`replayMarketContractPatch(profileDir, { coreDir })`）：
  它**不自己判断形状**，而是 `import` 核心树里那份桥模块的 `patchMarketCliBranch` ——
  与 boot 那处**同一份判据函数**，于是桥自带的那套纪律照旧生效：幂等（已是目标形态则
  逐字节不写）、锚点唯一才写、失败一个字节都不写、认得上一代补丁整段并就地升级
  （不叠加 `const`，否则语法错 ⇒ 市场整个挂不起来）。
- 接线位置：`hostcore/app/main.js` 的安装队列，`installSpec()` **成功之后**、
  `<queue>/<id>.done` 写出**之前**。放 `.done` 之前是有意义的：写入方拿到 `.done`
  就可能立刻去挂载，那一刻读到的必须已经是改写过的文件；万一它已经挂载过，
  改写也仍然落盘、下次冷启动生效。
- 失败面：任何异常只变成一行 reason 返回，**绝不抛给安装队列** ——
  "皮肤的挂载契约"与"插件装没装上"是两件事，后者不该被前者带下水；市场不在这个
  profile 时返回 `null`（静默）。
- 清单同步：`tools/place-host-app.mjs` 与 `tools/assert-resfile-sync.mjs` 两处一起改
  （`assert-resfile-sync` 15 件快照全部同步）。

### 2.3 门禁与真机读数

- `node tools/check-market-bridge.mjs`：**113 passed / 0 failed**（L 段新增 9 条：
  模块导出 / 市场不在则静默 / 幂等 / 上游形状变了不猜着改 / 桥缺失只回 reason /
  `main.js` require 与调用点在 `.done` 之前 / 只在安装成功时调 / 落点取安装器实际用的目录 /
  coreDir 与 loader 同源；另有 L10a/L10b 两条清单接线的反向判据）。
- `node tools/check-core-openharmony-patches.mjs`：**212 passed / 0 failed**
  —— **27 处**注入补丁 + 1 处撤除守卫（门禁总数口径见 `AGENTS.md`）。
- 真机（手机）：市场 `state` 实读 `hostKind="dsh"` + `restartAvailable=true`；
  用户上手实测皮肤市场一键安装正常。

## 3. 本批产物（`+dshm.49`）

版本面：`versionName=1.1.2` / `versionCode=1010002` /
`coreVersion=0.2.1-alpha.2+dshm.49` / `minAPIVersion=60101024` /
`targetAPIVersion=260000026` / `deviceTypes=phone,tablet,2in1` /
权限恒 **8 条** / 随包被审核端拦截的安装包扩展名 **0** 条目。
核心树容器：`dist/core/dsh-core-0.2.1-alpha.2+dshm.49-openharmony-arm64.zip`
= 60,951,916 B / sha256 `72AC35ADDCE43C39221A176816E91E9DA50C3FB1A565EF628DAEFF87CB9CE7F6`
（与 resfile 那份逐字节同源，`check-resfile-core-zip` 判绿）。

| 产物 | 大小（B） | sha256 | 用途 / 安装口径 |
|---|---:|---|---|
| `dist\sideload\DSHM-1.1.2-core0.2.1-alpha.2+dshm.49-arm64-signed.hap` | 403,653,603 | `9AB915A0B9AC0BB4B665515B4881CB552D1DB7360A1F5A830D003FF154D962E6` | **侧载**：release 构建 + 调试签名 ⇒ `hdc install -r` 覆盖安装（不动 el2 用户数据） |
| `dist\release-test\DSHM-1.1.2-core0.2.1-alpha.2+dshm.49-arm64-release-signed.app` | 196,336,183 | `DE021CA45919661B9FFAE322422C5513D96911890325EA778D76393FFB09428E` | **AGC 上传件**：发布证书签名 |

### 3.1 AGC `.app` 复核（实读，均为本轮命令输出）

- `verify-app success`（`hap-sign-tool.jar`，rc=0）；内嵌 profile `type=release`、
  `uuid=0bbda76e-e5dd-46f5-9b93-3cda1d87ac84`、
  `allowed-acls="ohos.permission.ALLOW_EXTERNAL_NATIVE_CODE","ohos.permission.FILE_ACCESS_PERSIST"`
  （**2 条**，与 `requestPermissions` 里两条受控条目对齐）。
- 容器实读 **3 条目**：`pac.json`(36) / `pack.info`(1027) / `entry-default.hap`(401,307,331)，
  **0 个 apk 条目**。
- 发布签名脚本 `[0]` 步（fail-closed）：`requestPermissions: 共 8 条`、`摘掉 0 条`、
  `.app 内层声明与发布 profile 对齐`。
- 内层 HAP 的 `module.json`（实读）：`bundleName=com.dshm.dshclient`、`versionName=1.1.2`、
  `versionCode=1010002`、`minAPIVersion=60101024`、`targetAPIVersion=260000026`、
  `compileSdkVersion=26.0.0.105`、`buildMode=release`、`deviceTypes=phone,tablet,2in1`、
  `requestPermissions` **8 条**。
- **与侧载件同源核对**（逐条目比 name/length/CRC，不需要解包比对内容）：
  内层 HAP 127 条 vs 侧载 HAP 128 条；侧载多一条 `.pages.info`（组包形态差异），
  唯一**内容**差异是 `pack.info`（组包元数据）⇒ 含 `module.json`、`ets/modules.abc`
  在内的其余 126 条逐条目一致。

### 3.2 真机安装（手机 `62T0225B18039433`，覆盖安装）

- 走 `.\tools\update-device.ps1 -Hap <侧载件> -SkipRebuild -Target 62T0225B18039433`：
  覆盖安装成功（**未 uninstall**），`files/dsh/home` 指纹装前 = 装后（`links=9 / size=3440`）。
- 冷启动后 `dsh/cores` = `+dshm.49`；
  `diag-tray` 出现 §1.3 那条 `install skip`；`ps -ef` 只剩主进程 + `:render`。
- 本包**不能**用 `.app` 装机：发布 profile 无 UDID ⇒ 设备侧拒装（`9568322`，见 `docs/145`），
  AGC 件只用于上传 / 送审。

## 4. 门禁与预检（本轮实跑）

| 门禁 | 读数 |
|---|---|
| `check-core-openharmony-patches.mjs` | 212 passed / 0 failed（27 处注入 + 1 处撤除守卫） |
| `check-market-bridge.mjs` | 113 passed / 0 failed |
| `check-permission-surface.mjs` | 8 条恒等；已删除的三条受限条目 2998 个文本文件 **0 命中** |
| `check-no-apk-surface.mjs` | 39735 个目录 **0** 命中、9 个归档 **0** 条 apk 条目 |
| `assert-resfile-sync.mjs` | 15 件快照全部同步 |
| `check-resfile-core-zip.mjs` | resfile 1 个容器 = 配方 = `dist/core`（逐字节同源） |
| `check-decor-button-mode.mjs` | 第一组 9/0、第二组 50/0，对照臂 A–K 全部有效 |
| `check-feature-wiring.mjs` | 137 个文件 / 23 个功能 / 2 条反面规则全绿 |
| `check-handheld-back.mjs` | 正例 29/0，三条对照臂全部如期判红 |
| `check-doc-refs.mjs` | 88 个文档 / 217 条带行号引用全绿 |

## 5. 未做 / 待办（如实登记）

- **PC / 2in1 档真机回归未做**：本轮的托盘改动按分档早退，PC 档拿到的是原链，
  但没有在本轮重新装机复验（PC 当前不在线）。
- **手机端 UI 肉眼复验**：用户口头确认"皮肤市场实测过了，没问题"；
  逐条皮肤的按钮复验未逐项截图留档。
- `dist/sideload/` 里仍躺着 `+dshm.46/47/48` 三件旧 HAP，`dist/release-test/` 里
  仍有 `+dshm.46` 的 `.app` / `.hap`：都是仓库产物，**未经用户确认不删**。
- 同批**发布签名 HAP 未出**（用户只要求 AGC 的 APP 包）；需要时可用
  `entry\build\default\outputs\default\entry-default-unsigned.hap`（401,307,010 B）
  走 `tools/sign-release-hap.ps1` 的 `.hap` 分支另签一件。
- **未 commit / 未 push**。

## 6. 红线遵守（本轮）

- 全程**未 uninstall**、未删任何真机 el2 数据；装机只走 `update-device.ps1`（覆盖安装）。
- 未动 `C:\Users\Sol\.ohos` 签名物料（发布口令取自 `D:\DSHM-signing-backup\`）。
- 权限面**恒 8 条**，被永久删除的三条受限条目全仓 0 命中（含文档）。
- 全仓 **0 个 apk 扩展名文件 / 0 个 apk 目录 / 归档 0 条 apk 条目**。

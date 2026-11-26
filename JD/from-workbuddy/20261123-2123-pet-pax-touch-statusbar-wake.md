# JD-038 邀测反馈四项修复：PAX 解包 / 桌宠穿透 / 平板沉浸 / 亮屏顶窗（含 Alt+Tab）

- 提交方：WorkBuddy
- 接收方：DevEco（编译 AGC 邀测包）
- 时间：2026-11-23 21:23
- 关联：JD-035 / JD-036（同一个 AGC 包）；本单为邀测反馈的增量修复
- 版本：1.1.8 / versionCode `1010020`

---

## 1. 反馈来源

| # | 反馈 | 材料 |
|---|---|---|
| 1 | 插件市场装 `dsh-pet` 后桌面看不到动画，中文素材 404，部分文件只有原大小的 1/10 | `DSHM-dsh-pet-桌宠桌面显示-根因与开发端修复-2026-11-23.md` |
| 2 | 桌宠在桌面的**透明区域**点不透，点不到后面的内容 | 用户反馈 + 官方博客（按区域可触方案） |
| 3 | 启动画面已跟随系统明暗，但进入 App 后若 **App 内明暗 ≠ 系统明暗**，App 内状态栏不沉浸 | 用户反馈 |
| 4 | 息屏后亮屏，DSHM 自己跳到前台 | `DSHM-亮屏回前台-诊断报告.zip` |
| 5 | 桌宠显示后 **Alt+Tab 失效/切到空白**，切换器里多一个 `PetAbility` 卡片 | `dshm-pet-alt-tab-20261121-1940.zip` |

---

## 2. 根因与修复

### 2.1 PAX 解包：中文文件名损坏 + 文件截断（通用安装器问题）

**根因**：`hostcore/app/tar-gz.cjs` 的 `parsePax(text)` 按 JS 字符串（UTF-16 码元）切，而 PAX 记录的 `len` 是 **UTF-8 字节数**。值里有一个汉字就多 2 字节 ⇒ 切片越过本条记录、切进下一条：
- `path` 尾部粘上 `\nmtime=...` ⇒ 141 个中文文件名被写坏；
- 紧随其后的 `size` 记录被切掉最后一位 ⇒ 6 个文件只写 1/10 内容。

**修复**（`hostcore/app/tar-gz.cjs`）：

1. `parsePax(buf)` 改为 Buffer 入参，长度判断 / `indexOf` / `subarray` 全部按字节；
2. 调用点改传 `tarBuf.subarray(off, off + size)`（`x` 与 `g` 两类 PAX 各一处）；
3. 新增 `pax size` 与 header size 一致性校验（>8GB 巨型文件 header=0 除外），不一致直接拒绝解包；
4. 条目名含 `\u0000-\u001f\u007f` 直接拒绝（坏名铁证）；
5. 落盘后 `statSync` 复核字节数，不等则删除半成品并抛错。

**同步**：已跑 `node tools/place-host-app.mjs`，`assert-resfile-sync` 27 件一致；**DevEco 若构建脚本会重跑 place-host-app，直接跑即可**。

**回归用例**：`tools/check-dshm-installer.cjs` 新增 §2b：
- 含中文 `path` + `size` 的 PAX tar 必须解出 `assets/webm/三球抛接.webm`，且 size 正确；
- 条目名含 `\n` 必须抛错。

本地实测：中文名与 size 均正确；size 不一致、坏名两类负向用例均按预期抛错。

---

### 2.2 桌宠透明区域点击穿透

**根因**：`entry/src/main/ets/pages/PetWeb.ets` 的 `setInputRegions()` 是空实现；`setInteractive/setInputBusy` 都走整窗 `setWindowTouchable(true)`，620×620 窗口里除宠物本体外的透明区也会吃掉点击。

**修复**：

- 新增 `applyTouchableAreas()`：按 `PetWindowHolder.boxX/boxY/boxSize`（宠物本体屏幕物理 px）结合窗口 rect 算出窗口内矩形，调 `window.setTouchableAreas([rect])`；区域外由系统透传到桌面/下层应用。
- 触发点：`setBounds()` 的 `moveWindowTo`/`resize` 都 settle 后；`setInputRegions()` 与页面 `onPageEnd` 各补一次。
- SDK 明确「窗口矩形变化后设置失效」⇒ 每次移动/缩放后重设；2px 容差 + 120ms 节流，避免动画每帧调用。
- 降级：`setTouchableAreas` 抛错（201 / 801 / 1300016）时回退整窗 `setWindowTouchable(true)`，宠物仍可点。

**权限（2026-11-23 用户裁决：暂不申请）**：`window.setTouchableAreas` 需要
`ohos.permission.SET_WINDOW_TOUCH_AREAS`
（`system_basic`、`system_grant`、`deviceTypes:["2in1"]`、`@since 26`）。

- 已从 `module.json5` 移除该权限声明（`requestPermissions` 回到 19 条），同步删除 `pet_touch_areas_reason`；
- **代码保留** `applyTouchableAreas()`：无权限时 API 返回 201，自动降级为整窗可触（宠物可点、透明区继续吃点击），不影响其余功能；
- 后续若获批 ACL，只需把权限声明加回，无需再改代码。

---

### 2.3 平板状态栏不沉浸（App 明暗 ≠ 系统明暗）

**根因**：两处写同一套窗口属性，互相覆盖：
- 能力层 `EntryAbility.reassertWindowChrome()` 对平板写透明（`SYSTEM_BAR_HANDOFF_BG`）；
- 页面侧 `entry/.../WebApp.ets → applySystemBarTheme()` 却写不透明的 `barBg`（App 外观色）。

页面已 `setWindowLayoutFullScreen(true)` 铺到状态栏下方，于是顶部出现一条与页面不同色的不透明带。App 主题与系统一致时颜色接近、不易察觉；不一致时最明显。

**修复**：

1. `WebApp.ets` 新增 `isTabletForm()`（`readDeviceFacts().form === FormFactor.TABLET`，与能力层同判据）；
2. `applySystemBarTheme` 对平板恒用 `SYSTEM_BAR_HANDOFF_BG`，图标明暗仍按 `chrome.lightIcon` 跟随外观；手机 / PC 分支不变；
3. `EntryAbility.enterTabletImmersive()` 去掉写死的 `isStatusBarLightIcon:false`，改为 `windowChromeFor(this.appearanceMode()).lightIcon`。

---

### 2.4 亮屏自动回前台

**根因**：`EntryAbility.onForeground()` 无条件调 `ensureWindowShown()`；未最小化的窗口 `restore()` 失败后兜底 `showWindow()`，把窗口顶到最前。

**修复**：`ensureWindowShown()` 先 `getWindowStatus()`，**只有 `MINIMIZE` 才 `restore()`**；删除 `showWindow()` 兜底；读状态失败则不动作（只记 debug 日志）。

---

### 2.5 Alt+Tab 出现空白 PetAbility / 按键被桌宠吃掉

**根因**：`PetAbility` 是独立 mission；`DshPet` 子窗 `Focusable:true`。切过去只有一个透明窗，按键落进 ArkWeb。

**修复**：

1. `PetAbility.ets`：宿主主窗与 `DshPet` 子窗都 `setWindowFocusable(false)`（保留 `setWindowTopmost(true)` 与 `setWindowTouchable`）；
2. `module.json5` 的 `PetAbility` 增加 `"excludeFromMissions": true`（SDK module schema 已确认该字段合法）。

---

### 2.6 Node 26 升级评估（2026-11-23 实测）

| 项 | 结果 |
|---|---|
| brew Node | **26.13.1**，`node -v` 正常，`process.versions.modules=147`、`napi=10` |
| 插件 CLI 供给 | `node-runtime-provision.cjs` 的 `candidateSources()` 已自动包含 `~/.harmonybrew/Cellar/node/26.13.1/bin/node`；`probeNode()` 返回 `{ok:true, version:"26.13.1"}`，**无需改代码** |
| Node 26 下跑门禁 | `assert-resfile-sync` / `check-decor-button-mode`(9/0+134/0) / `check-auth-return` / `check-node-runtime-startup` 全过 |
| dsh 核心 | `dsh --version` → `0.2.2-rc.5` 正常；`dsh web` 纯 CLI 起不来，报缺 `node-addon-require-builtin-openharmony-arm64` 原生绑定——这是 App 内运行时专属环境，不是 Node 26 语法不兼容 |

**结论与阻塞**：

- App 内嵌运行时仍是 **Node 24.9**：`hostruntime/libs/arm64-v8a/libnode.so.137`（`NODE_MODULE_VERSION=137`）；Node 26 是 **147**，不能直接替换。
- 全盘没有 `libnode.so.147`。要真正把 App 内 Node 升到 26，必须用 `tools/node-runtime/build-node-ohos.sh` 交叉编译 `--shared` 版 libnode（需 Node 26 源码 + OHOS SDK）。
- **本机不具备构建条件**：无宿主 `gcc/g++/ar`（`toolchain-env.sh` 的 `CC_host` 解析为空），`MemAvailable` 仅约 3.9 GB；现有 `libnode.so.137` 是早前在带宿主编译器的环境产出后拷入的。
- 升级还需同步三处：`dshhost.cc` 的 `kLibnodeCandidates` 增加 `libnode.so.147`；所有 OHOS 原生 addon（`node-addon-require-builtin-openharmony-arm64` 等）按 ABI 147 重编；`nodecli` 的 soname 口径核对。

**给 DevEco（Linux x64 构建机）**：

```bash
cd <repo>
NODE_VER=v26.13.1 JOBS=8 bash tools/node-runtime/build-node-ohos.sh
# 产物 out/Release/libnode.so.147 → hostruntime/libs/arm64-v8a/
# 然后：dshhost.cc candidates 加 .147 → 重编 libdshhost.so → 编 HAP
```

> 本轮**不改** libnode：权限已按裁决移除，Node 26 的 CLI/工具链路径已验证可用；内嵌运行时升级需按上面在构建机执行。

---

## 3. 改动文件清单

| 文件 | 改动 |
|---|---|
| `hostcore/app/tar-gz.cjs` | `parsePax` 改 Buffer；size/坏名/落盘校验 |
| `hostruntime/src/main/resources/resfile/resources/app/tar-gz.cjs` | 由 `place-host-app.mjs` 同步（已一致） |
| `tools/check-dshm-installer.cjs` | 新增 PAX 中文名 / 坏名回归用例 |
| `entry/src/main/ets/pages/PetWeb.ets` | `applyTouchableAreas()` + 触发点 + 降级 |
| `entry/src/main/ets/entryability/PetAbility.ets` | host/sub `setWindowFocusable(false)` |
| `entry/src/main/ets/entryability/EntryAbility.ets` | `ensureWindowShown` 只在 MINIMIZE 恢复；平板沉浸图标跟随外观 |
| `entry/src/main/ets/pages/WebApp.ets` | 新增 `isTabletForm()`；平板状态栏恒透明 |
| `entry/src/main/module.json5` | `PetAbility.excludeFromMissions`；`SET_WINDOW_TOUCH_AREAS` 未申请（保持 19 条权限） |
| `entry/src/main/resources/base/element/string.json` | 删除未使用的 `pet_touch_areas_reason` |
| `entry/src/main/resources/base/element/string.json` | 新增 `pet_touch_areas_reason` |

---

## 4. 本地已跑的门禁

| 项 | 结果 |
|---|---|
| `node tools/check-decor-button-mode.mjs` | PASS（第一组 9/0、第二组 134/0） |
| `node tools/check-auth-return.mjs` | PASS |
| `node tools/assert-resfile-sync.mjs` | 27 件快照全部同步 |
| `node --check hostcore/app/tar-gz.cjs` | 语法 OK |
| `node tools/check-dshm-installer.cjs` | **54 passed / 0 failed**（含新增 §2b：PAX 中文名可落盘且 size 正确、坏名含 `\n` 必须拒绝） |
| PAX 单独负向用例 | size 不一致、控制字符坏名均按预期抛错 |
| `node tools/check-host-toolchain-fallback.mjs` | **HEAD 上既红**（`finishes[0] undefined`），与本次改动无关，未动 |

> 注：`check-dshm-installer.cjs` 含镜像/直连网络对照用例，本机跑完约 37 分钟；DevEco 侧可只跑其中的 tar/安装段落，或直接以「54 passed / 0 failed」为基线。

> 本机没有可用的 ArkTS 编译入口，需要 DevEco 编译验证。

---

## 5. DevEco 执行

```bash
# 1) 同步 hostcore → resfile（若构建脚本未自动做）
node tools/place-host-app.mjs
node tools/assert-resfile-sync.mjs

# 2) 编译（沿用现有 AGC 包身份）
devecocli build --product default --build-mode release
```

预期：
- 编译通过；
- 若发布 profile 未含 `SET_WINDOW_TOUCH_AREAS`，`strip-ungranted-acl-perms.mjs` 会打印摘除该权限，属**预期**，不影响安装与其余功能；
- 不要为了让它通过而手工删 `module.json5` 里的声明（签名前摘除是既有机制）。

---

## 6. 真机测点

### 6.1 桌宠安装链路（PC / 2in1）
1. 卸载 `dsh-pet` 后重装 `0.4.9`，**不做任何手工改名/补文件**；
2. 检查插件目录：无任何文件名含换行；`assets/webm/吃冰淇淋融化.webm` 等中文素材经插件 HTTP 路由返回 200 且 `content-length` 与文件一致；
3. `display: desktop` → 桌面出现宠物，10s 内有待机动画，点一下有反应、拖拽跟手；
4. 切 `web` → 桌面窗消失；切回 `desktop` → 窗口重建、动画恢复；
5. 冷启动应用后重复第 3 条仍通过。

### 6.2 透明区穿透（2in1）
1. 宠物旁边（窗口内但非本体）点击桌面图标 / 其他应用 → **应能点到**；
2. 点宠物本体 → 宠物正常响应；
3. 拖动宠物时透明区不误触；
4. 若 ACL 未授予：日志出现 `setTouchableAreas rejected: 201，降级整窗可触`，属预期降级。

### 6.3 平板状态栏沉浸
1. 系统 **深色**、App 内设为 **浅色**：启动 → 进 App，状态栏应与页面同色/透明，无独立色带；
2. 系统 **浅色**、App 内设为 **深色**：同上；
3. 系统与 App 同色：仍沉浸；
4. 旋转 / 最大化 / 还原后状态栏不出现白条或黑条。

### 6.4 亮屏回前台
1. App 切后台 → 息屏 → 亮屏：**不应**自动跳到前台；
2. 手动把窗口最小化 → 点任务栏/托盘图标：应正常恢复；
3. hilog 中亮屏后**不应**再出现「主窗已从最小化恢复」。

### 6.5 Alt+Tab
1. 桌宠显示中，焦点放浏览器，按 Alt+Tab：切换器**不再出现** `PetAbility` 空白卡片；
2. 连续 Alt+Tab 可正常在两个普通应用间切换，按键不被桌宠 webview 吃掉；
3. 宠物本体点击 / 拖拽仍正常（焦点关闭不影响指针）。

---

## 7. 边界

- 不改 dsh-pet 插件本身，不内置插件；
- 不做「安装后自动改名/补文件」的兜底；
- 手机壳（`phone`）本轮不动；
- `SET_WINDOW_TOUCH_AREAS` 按用户裁决**暂不申请**：权限声明已移除，代码保留降级路径；透明区穿透在获批 ACL 前不会生效。
- Node 26：本轮只验证 brew CLI 与工具链；App 内嵌 `libnode` 仍为 24.9，升级需在 Linux 构建机按 §2.6 执行。

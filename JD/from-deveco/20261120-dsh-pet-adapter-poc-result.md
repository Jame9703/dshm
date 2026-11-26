# 结论：dsh-pet 桌面宿主适配 POC（JD-018）

- **ID**：JD-018
- **提交方**：WorkBuddy · **接收方**：DevEco（编译 / 安装 / 真机取证）
- **日期**：2026-11-20 22:05
- **判定**：**PARTIAL**（宠物出现且是插件自己的动画；窗口跟随、置顶、穿透、菜单均实测有效；拖动仅在鼠标注入下可用且位移比例异常；`setInteractive` 回切通道缺失导致空闲后永久穿透）
- **证据库**：`JD/from-deveco/20261120-dsh-pet-adapter-poc-evidence/`（17 截图 + 3 a11y 树 + 2 窗口样本 + hilog 摘录，`SHA256SUMS` 全绿，44 MB）

```
JD-018 结论：PARTIAL
产物 sha256：
  WorkBuddy 原产物  build/outputs/default/dsh-pet-adapter-poc-default-signed.app
                    cab9124b838354946152a112448fc650f95167e8a271b8daba7a4574763e4563（57,505 B，核验一致）
  本地重构建签名 HAP entry/build/default/outputs/default/entry-default-signed.hap
                    c0ca25fd42d53d41…（修复 1300002 后重建；.app 内解出的 HAP 未签名，见异常码）
设备/系统：MateBook 14 2in1（API 26），2880×1920，density 1.75，无线调试 127.0.0.1:45595
```

## 1 启动：PASS（截图 11/12）

- 透明子窗出现插件自己的「蓝毛小女仆」：a11y 元素 `蓝毛小女仆` 可读，像素簇着色与 JD-017 一致；动画帧间有差（视频在播）。
- `hilog DshPetHost`：`onCreate` → `pet subwindow ready, url=http://127.0.0.1:3090/dsh-pet-native/probe.html?...&openTarget=web`。
- 宿主 320×100vp 黑条（`dsh-pet host` 白字）居中垫在宠物下 182px 处，不越出宠物轮廓；主窗不能离屏（交接单 §6 已知边界，记录不判失败）。
- 首跑失败已修复：`setup failed: 1300002 This window state is abnormal.[window][setWindowBackgroundColor]` —— 适配层把 `setWindowBackgroundColor` 放在 `setUIContent` 之前（JD-015 已知坑）。修复：移到 `setUIContent` 后并 try/catch（本 SDK 该 API 返回 void，不可 `.catch`）。截图 `10-broken-1300002.jpeg` / `11-poc-launch.jpeg`。

## 2 窗口跟随：PASS

- `setBounds` dispatcher 记录 **13,539 行**（≈4,513 次调用），首调 `20:47:04.762`（启动 +0.7s），全程无 `setBounds move rejected` / `resize rejected`（`rejected` 检索 0 行）。
- 窗口位置样本（物理像素）：`[2174,1070]`（出生）→ `[2163,-209]` → `[1997,-209]` → `[1945,-209]` → `[1898,-209]`（run1 漫游左移）；run2 `[2163]`→`[1914]`；run3 `[1852]`。
- 4 秒双拍（`13-move-a`/`14-move-b.jpeg`）子窗 x +14px，宿主同步 +15px（居中偏移 180/181 恒定），宠物区域有帧间动画、桌面静止 —— 漫游与跟随同时成立。

## 3 拖动：PARTIAL

- **鼠标拖拽可用**（`uinput -M -g` 真鼠标事件）：`[2282]→[2117]`、`[2117]→[1869]`，窗口与宠物跟随鼠标方向移动；`[dsh-pet] grab vx=0` 控制台日志与 pointerdown 一一对应。
- **位移比例异常**：指针位移 500/700px，窗口仅位移 165/248px ≈ 指针位移 ÷ 1.75²。与 DPR 失配同源（页面按 CSS px 算 → 桥层再按物理 px 落位），阶段 2 需单点化坐标换算。
- **触摸拖拽不可用**：`uitest uiInput drag` 注入触摸，pointerdown 到达页面（grab 日志在），pointermove 被 Chromium 默认 touch-action 滚动判定取消（页面 `.pet-hit` 未设 `touch-action:none`）。真机用户走鼠标/触控板不受影响；若要支持触摸需补该样式。
- 第 1 次触摸拖拽起点计算失误（宠物漫游 250px 未复算），落在窗外，无副作用。

## 4 穿透：PASS（能力）/ FAIL（回切）

- **穿透有效**：点击宠物身体 `(2631,524)` 未触发插件任何反应，直接落到下层桌面天气/日历组件并**打开了日历应用**（a11y `app-layout4.json` 全树实证，含 日历账户/订阅服务/消息中心）。已用返回键关闭，桌面复原。
- **回切死锁（关键发现）**：`setInteractive` 全程仅 **3 次**调用 —— run1 `20:55:54.619`（启动 +8m50s，空闲翻转）、run2 `21:35:52.812`（长按弹出菜单前，疑似 true）、run2 `21:37:33.410`（菜单交互后，疑似 false）、run3 零调用。一旦进入 `false`（`setWindowTouchable(false)`），HarmonyOS 无 `forward:hover` 等价物 ⇒ 页面收不到 hover ⇒ 永远不会再调 `true` ⇒ **空闲后永久不可点击/拖动/右键**。
- a11y 曝光与 `setWindowTouchable` 状态强相关（可触期暴露宠物与菜单节点，穿透期整棵 Web 子树消失），取证时注意别把「a11y 无宠物」误判成「宠物不渲染」。

## 5 菜单 / 气泡：菜单 PASS（有裁切）/ 气泡未渲染

- **菜单由插件自己渲染**：长按宠物（触摸长按 → contextmenu）弹出插件菜单，a11y `app-layout7.json`：`打开网站Ctrl+左键`、`查看余额`（`OPEN_LABEL.web` + `OPEN_SHORTCUT_HINT` 与 `sprite/menu.js` 一致）。
- **裁切**：菜单跟随宠物落在屏幕右缘，只露出左侧 ~23px（a11y bounds 被钳在 2880），后续项在窗口外 —— 与宠物贴右缘裁切同一 DPR 根因。
- **气泡未渲染**：点「查看余额」后 2s 内无气泡（`20-bubble.jpeg` 宠物上方白色像素 11，阈值 25）。独立宿主无 `/balance` 端点，与 JD-017 `pose/report 403` 同属 standalone 受限面；菜单动作派发链本身正常（点击后菜单关闭）。
- **漫游由插件驱动**：宠物左右走动、窗口实时跟走，`onDisplays` 下发后插件按显示区自行寻路。

## 6 置顶：PASS

- `hidumper`：`dshdemo0` z=114、`DshPet` z=115，恒在最上层；`decorEnabled:false` 子窗随 topmost 宿主骑顶。
- 跨场景实测：浏览器（用户关闭前 z 112/113）→ 桌面 → 用户自开 HiShell → 穿透测试打开的日历 → 桌面，宠物始终在最上层（每次 a11y 都有 `dsh-pet host`；宠物像素浮于日历之上 `x2300..2690 y454..646`，`17-over-calendar.jpeg`）。
- 浏览器被用户中途关闭后，宿主+子窗不受影响（与 JD-015「父窗 minimize 连坐」不同：此处父窗是 topmost 宿主，从不最小化）。

## 7 无 Electron：PASS

- 设备侧 `com.dshm.dshdemo` 进程树（pid 41248）：主进程 + `:gpu` + 2×`:render`（ArkWeb），无 electron 子进程（`hilog-extract.txt`）。
- 设备 `ps` 中出现的 electron 属 `/data/storage/el1/bundle/electron/…`（用户 WorkBuddy 环境包，08:46 启动），与本 demo 无关 —— 取证时勿误读。
- 页面由 PC 侧纯 node 宿主（`lib/standalone.js --port 3080`）+ 同源代理（`tools/pet-proxy.mjs --port 3090`）提供。

## 异常码 / 控制台原文

| 项 | 原文 | 处置 |
|---|---|---|
| 窗口底色 | `setup failed: 1300002 This window state is abnormal.[window][setWindowBackgroundColor]`（20:41:09） | 已修：`setUIContent` 之后调用 + try/catch |
| 安装 | `code:9568320 error: no signature file` | `.app` 内解出的 HAP 未签名；改用模块产物 `entry-default-signed.hap` |
| 桥拒绝 | 无 `setBounds move rejected` / `resize rejected` / `setInteractive rejected` / `deliverDisplays failed` | — |
| 桥告警 | `[dsh-pet] 实况上报未送达 pet=main`（`sprite.js:157`） | 独立宿主 403，设计内（同 JD-017） |
| 安装假象 | `hdc install` 错误行打印在 `AppMod finish` **之前** | 装机结论以 `bm dump` updateTime 为准，勿 `tail -1` |

## 阶段 2 建议（按优先级）

1. **DPR 统一（最高）**：ArkWeb 内容与插件坐标统一到同一空间 —— 要么 `controller` 内容缩放 1/1.75 让 CSS px == 物理 px，要么在 shim 单点换算（含 setBounds/setInteractive 命中区/拖拽 delta）。当前宠物 1.75× 放大+偏移 ⇒ 贴右缘裁切、菜单裁切、拖拽比例 ÷1.75² 全部同源。
2. **交互回切（最高）**：无 `forward:hover` ⇒ 候选 (a) 周期 `setInteractive(true)` + 自身命中检测后立即回置；(b) 双窗（小命中窗 + 大穿透渲染窗）；(c) 明确降级为「仅展示宠物」并把菜单入口移到宿主黑条。三选一需用户拍板。
3. **触摸兼容**：`.pet-hit` 补 `touch-action:none`（触摸拖拽当前被滚动判定吃掉）。
4. **余额气泡**：独立宿主补 `/balance` 或菜单项按能力面隐藏（当前点了无反馈）。

## 附：工作区改动

- `demo/dsh-pet-adapter-poc/entry/src/main/ets/entryability/EntryAbility.ets`：修 1300002 顺序坑（保留，阶段 2 基线用）。
- 其余文件未动；运行环境（node 宿主 / 代理 / /tmp 探测目录 / 设备侧 demo 进程）已全部清理。

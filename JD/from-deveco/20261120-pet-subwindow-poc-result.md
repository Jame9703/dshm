# JD-015 pet-subwindow-poc 真机验证结论

- 日期：2026-11-20
- 设备：HUAWEI MateBook 14（MNTXM-24B）本机 2in1，OpenHarmony 7.0.0.109（API 26），2880x1920，密度 1.75
- 交接单：`JD/from-workbuddy/20261120-1510-pet-subwindow-poc.md`
- 证据库：`JD/from-deveco/20261120-pet-subwindow-evidence/`（16 文件 + SHA256SUMS 全绿）
- 验证方式：`devecocli build` → `hdc install -r` → 冷启动 → uitest 注入（click/swipe）+ hilog + hidumper WindowManagerService + a11y dump + 像素采样四重取证

## 结论：PARTIAL

子窗透明、圆掩码、圆外点击穿透、子窗拖动四项全部成立（Q2/Q3/Q5 PASS，Q4 经旗标修正后 PASS）；
但宿主主窗**无法完全离屏也无法隐藏**（Q1 FAIL），且**宿主最小化会连坐隐藏子窗**（Q6 FAIL）。
架构可用，宿主窗口的可见性管理是遗留难题。

## 产物 sha256（构建→安装→取证链）

| 轮次 | 时机 | HAP sha256（前 16 位） | 说明 |
|---|---|---|---|
| WorkBuddy 交接 .app | 15:10 前 | `271af150…`（55,898B） | 交接原件，未直接安装（.app 需拆） |
| 第 1 轮 | 15:16 | `75709faa…` | 初版源码，首启即 1300002 |
| 第 2 轮 | 15:27 | `ac5a2b87…` | 子窗调用顺序修复（setUIContent 先行） |
| B1 | 16:00 | `ffc16b81…` | `zLevelAboveParentLoosened` 反转为 false |

## 窗口几何（物理像素）

- 宿主：resize(320,72)vp → 实际 320x100vp（高钳 100vp 最小值）= 560x175；moveWindowTo(-2000,-2000) → x 钳 -250（保留 310px 可见）、y 钳 70（工作区顶）；二次尝试无效（静默持续钳制）
- 子窗：576x576，掩码半径 0.48x576=276.5px，圆心=窗心

## 六问判定

| # | 问题 | 判定 | 关键证据 |
|---|---|---|---|
| Q1 | 宿主主窗能否完全离屏 | **FAIL** | x 钳 -250 / y 钳 70，残条 310x175 topmost 遮挡左侧内容 (50,150)=(0,0,0)；无 hide API，minimize 连坐（见 Q6）→ 宿主必然可见 |
| Q2 | 子窗透明+圆掩码（无 1300004、像素级无容器底色） | **PASS** | `sub.bgColor(#00000000)` ok、`sub.mask(circle 0.48)` ok 无 1300004；圆外像素逐字节透出下层微信 (224,235,246)，无方卡（对照 JD-014 主窗方案圆外恒 (64,64,64)） |
| Q3 | 圆外点击穿透 | **PASS** | 受控双分支：掩码区 (150,150) 点击 → `host touch` Down+Up + `host click#1`、零 pet touch（穿透落宿主收据）；圆内 (388,200) → `pet touch` Down+Up、零 host touch（圆内自消费） |
| Q4 | 父窗 topmost 能否让独立子窗跨应用置顶 | 原架构 **FAIL** → B1 **PASS** | 原旗标 true：子窗 z125 < 微信 pc3 z127 < 宿主 z128，被盖不可交互；反转为 false（恢复默认"子窗在父上"约束）：PetSub z129 > 宿主 128，骑 topmost 带 |
| Q5 | 子窗拖动 startMoving | **PASS** | swipe(2477,1402→388,388) 后 rect (2189,1114)→(100,100)，增量 (-2089,-1014) 与手势逐位一致；touch 流 6 事件完整 |
| Q6 | 宿主切后台 30s 子窗是否还在渲染 | **FAIL** | `host.minimize()` → PetSub 与宿主同 z=-1 摘出 z 序、像素消失，满 30s 不恢复；onBackground 始终未触发、进程前台存活；`aa start` 恢复可逆（z 回 130、交互健全） |

## 异常码原文

- `1300002`：首启 `setup failed: 1300002 This window state is abnormal.[window][setWindowBackgroundColor]` —— 根因：子窗在 `setUIContent` 之前调 `setWindowBackgroundColor`（无内容态）；修正顺序后消失
- `1300004`：**本次子窗掩码未复现**（JD-014 主窗掩码的 1300004 在子窗路径不存在）

## 给 WorkBuddy 的必修项与发现

1. **`zLevelAboveParentLoosened` 旗标传反**：官方义为"是否放宽『子窗 z 必须位于父窗之上』的约束"（`@ohos.window.d.ts` since 26）。传 `true` 恰好允许子窗落到父窗与被抬升应用之下（实测 z125 < 微信 127 < 宿主 128，宠物被盖）。**桌宠必须去掉该旗标（默认 false）**，子窗即骑上父窗 topmost 带（z129/130）。
2. **子窗调用顺序**：`setUIContent` 必须先于 `setWindowBackgroundColor` / `setWindowMaskWithAlpha`，否则 1300002。
3. **宿主可见性是硬约束**：自由窗离屏被钳制（x≥-(width-310)、y≥工作区顶），Window 无 `hide()` API（仅 `showWindow`），`minimize()` 连坐子窗。宿主只能缩小贴边，残条可被宠物不透明圆体遮挡（拖走后暴露），无法根除。
4. **宿主 minimize 连坐**：主窗最小化时独立子窗同被隐藏（z=-1）；恢复（任务栏/`aa start`）子窗随之回屏。"不跟随主窗前后台切换"对 minimize 场景不成立。
5. **自动化坑**：注入点击触发 `startMoving` 后，窗口可能跳随**真实鼠标**光标（共享实机实测跳位 [-35,751]）；单指真机无此问题。uitest `uiInput` 坐标为物理像素。
6. **hilog 格式坑**：TouchEvent 回调里 `event.type`（TouchType 枚举）作 `%{public}s` 参数导致后续 `%{public}f` 占位符输出 `}f`、坐标丢失；日志行前缀与时序仍可用，取证以 hidumper/像素为准。

## 遗留

- 宿主残条遮挡与 minimize 连坐无 API 级解法；若产品化需评估"接受残条贴角 + 禁止宿主最小化"，或改用其他窗口方案。
- B1 修复后的长时稳定性（>30min 悬浮）未测。

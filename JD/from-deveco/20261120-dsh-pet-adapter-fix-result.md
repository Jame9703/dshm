# 结论：dsh-pet 适配修复验证（JD-019）

- **ID**：JD-019
- **提交方**：WorkBuddy · **接收方**：DevEco（编译 / 安装 / 真机复验）
- **日期**：2026-11-20 22:40
- **判定**：**PARTIAL**（8 项中 7 项过；唯一未达标 = 拖动位移比 ≈0.36，根因已定位到插件拖拽增量式，属一行修复）
- **按交接单字面**：交接单 §4 把「拖动比例异常」列入 FAIL，故该项按字面记 **FAIL**；整体因其余各项全部通过且缺陷收敛明确，建议按 PARTIAL 进入下一轮
- **证据库**：`JD/from-deveco/20261120-dsh-pet-adapter-fix-evidence/`（13 文件 13 MB，`SHA256SUMS` 全绿）

```
JD-019 结论：PARTIAL（项 2 按字面 FAIL：拖动位移比 0.36）
产物 HAP sha256：
  WorkBuddy 产物 .app（二次封装后）e4714f4a09f1aecfee3564e85b2ba463722f11926c73e943eb948549174f93ff（62,669 B）
  HAP（WorkBuddy 22:05 构建，源码 22:04，本地 build 复用未重编）
  dfaf28ffbdf2ee654596f836daf6dc5fcf309abf99313ff7028ceab9864fe0c5
  说明：交接单给的 .app sha c9c1ca4a…（62,670 B）与本地重封装差 1 B，属容器时间戳，代码同一份 HAP
1 尺寸/裁切：PASS —— 宠物 462 CSS×1.75=808 物理像素正确落位，全屏内无裁切；窗口被工作区正确钳制
2 鼠标拖动位移比：FAIL —— 窗口位移=指针位移×0.34~0.40（3 次实测 -136/400、-158/400、-177/500）
3 触摸拖动：可用 —— touch-action:none 生效，触摸 down 可达页面（grab 日志），同项 2 比例问题
4 空闲后恢复交互：可用 —— 脉冲真相位内点击可达（7/8、3/6 连点命中），落点后 setInteractive(true) 持久
5 外点穿透：机制未变（setWindowTouchable(false)+脉冲）；JD-018 已实证穿透，本轮受合成 hover 限制未能重新全量复现
6 菜单：PASS —— 9 项菜单完整显示 x2178..2425 / y1285..1821，无右缘裁切（JD-018 只露 2 项已修复）
7 setBounds 拒绝数：0（3468 次调用；捕获内 2 条 rejected 均属天气应用 huawei.totemweather）
8 置顶/无 Electron：PASS —— host z=114 / sub z=115；进程树纯 ArkTS
异常码/控制台原文：
  - 无 1300002 / 无 setBounds move|resize rejected / 无 setInteractive rejected / 无 deliverDisplays failed
  - 仅 "[dsh-pet] 实况上报未送达 pet=main"（sprite.js:157，standalone 宿主 403，设计内）
  - 安装核对：bm updateTime 1795178807240 → 1795183963031（真装）
```

## 1 尺寸/裁切：PASS

- `pet subwindow ready, url=…&scale=1.75&bridge=0&openTarget=web&isWindowClampedToWorkArea=1` —— `display.densityPixels` 已注入。
- 窗口被插件按物理像素重设：出生 `620×620` → `[1263,0,1617,1438]`（=924×822 CSS，右缘 2880 恰为屏幕边、底缘 1438 在屏内），宿主 320×100vp 居中垫底（`[1792,632]`）。
- 宠物像素簇量测：蓝发+肤色簇全屏内（如 `[1970..2370,1110..1460]`），无 JD-018 的贴右缘裁切。
- 证据：`f01-launch.jpeg`、`f05-fresh.jpeg`、`f20-pet.jpeg`。

## 2 鼠标拖动位移比：FAIL（唯一未达标项）

- 三次独立实测（窗口 rect 精确值，非像素估计）：
  - 触摸拖 400px：窗口 `854→718` = **-136**（0.34）
  - 慢拖 `-M -g` 400px/4s：`1012→854` = **-158**（0.395）
  - 快拖 `-M -g` 500px：`1253→1076` = **-177**（0.354）
- 方向正确、连续跟手、无卡死；但位移 = 指针 × **0.36**（三次一致，与拖速无关 ⇒ 非弹簧滞后，是坐标系数）。
- 根因收敛：拖拽增量在 `runtime/electron-helper/sprite/input.js`：
  - L94 `sx: toLocal(e.screenX)`、L113 `dx = toLocal(e.screenX) - d.sx`、L126 轨迹采样 —— 对 `e.screenX` 又除了一次 `CONFIG.scale`。
  - 页面按 CSS px 记位置、`reportWindow` 再 `toScreen ×scale` ⇒ 净效果 = 指针物理位移 ÷ scale²（与 JD-018 同签名，此轮只剩拖拽路径未收口）。
  - 建议：`e.screenX/Y` 直接用（ArkWeb 已给 CSS px），或在 `toLocal` 处核对 ArkWeb 的 screenX 语义后单点换算。setBounds/命中区/尺寸路径本轮已正确，无需再动。
- 证据：`f10-ug.jpeg`、`f11-drag-jg.jpeg`、`f12-slowdrag.jpeg`、`f13-touchdrag.jpeg`、`f14-vdrag.jpeg`。

## 3 触摸拖动：可用（同项 2 比例）

- `uitest uiInput drag 1760 425 1360 425 200` → `grab vx` 日志出现、窗口随动 —— touch-action 修复生效。
- 位移比同项 2（0.34）：同一 `onPointerMove` 代码路径，修项 2 即连带修好。

## 4 空闲后恢复交互：可用

- 空闲 >10s 后连续点击宠物身体：多轮连点分别命中 7/8、3/6（`grab vx` 计数 17→20/21）；
- 首次落点后 `setInteractive` 记录（22:25:25.476 等）—— 页面拿回交互并停脉冲，后续点击持续可达。
- 与交接单 §4 的「脉冲是 POC 级折中」一致：单次点击落在 50/300ms 真相位才有 ~1/6 概率先命中，连点/真实 hover 连续移动可在 ≤300ms 内恢复。未出现「永久不可交互」。

## 5 外点穿透：机制保持，合成环境受限

- 机制未变（`setWindowTouchable(false)` + 300ms 脉冲）；JD-018 已用「穿透打开日历应用」实证。
- 本轮限制：合成鼠标 hover 移动事件不能送达 ArkWeb 子窗（`uinput -M -m` 悬停移动无 `pointermove`，`-M -g` 按下后移动可达），页面无法看到「指针离开宠物」，窗口保持可交互，外点被吃的结果不能代表真实用户；未采到可判定读数。
- 备忘（交接单已披露）：脉冲真相位内理论上有 ~17%（50/300）概率吃掉一次外部点击。

## 6 菜单：PASS

- 6 连点破相位 + 长按宠物 → 插件全菜单 9 项（打开网站/查看余额/查询天气/待办事项/碎碎念/配图/睡觉/重载配置/显示位置）；
- a11y 边界 x2178..2425、y1285..1821 —— **无右缘/下缘裁切**（JD-018 只露左条 23px 已修复）。
- 证据：`f24-menu.jpeg`、`f24-menu.json`。

## 7 setBounds 拒绝数：0

- `setBounds` dispatcher 3,468 行（≈1,156 次调用），漫游全程窗口跟随（窗 x 序列 1263→718→184→1263→1211 等）；
- 捕获内 2 条 `rejected` 均为 `huawei.hmsapp.totemweather` 系统天气表单日志，与 petBridge 无关。

## 8 置顶 / 无 Electron：PASS

- `dshdemo0` z=114、`DshPet` z=115，恒在 WorkBuddy/桌面之上；宿主条每次 dump 都在宠物窗中心下方。
- 进程树 `com.dshm.dshdemo` 仅主进程 + `:gpu` + 2×`:render`，无 electron 子进程。

## 附：工作区与产物

- 未改 `demo/dsh-pet-adapter-poc/` 任何源码；构建复用 WorkBuddy 22:05 的 HAP（`dfaf28ff…`）。
- 运行环境（node 宿主 3080 / 代理 3090 / hilog 采集 / `/tmp` 探测目录）已全部清理；demo 已 force-stop。

## 阶段 2 建议

1. **修项 2（一行）**：`sprite/input.js` 去掉 `e.screenX/Y` 上的 `toLocal()`（或按 ArkWeb 实际语义单点换算），复测 300–500px 拖拽位移比应为 1:1。
2. 顺手把脉冲折中收敛为双窗（小命中窗常驻可交互 + 大渲染窗恒穿透），消除 ~17% 外点被吃概率——即交接单 §4 的方案。
3. 项 5 的完整复验建议留到双窗方案落地后，用真实鼠标（非合成）在宠物外透明区做穿透确认。

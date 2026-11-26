# 交接单：dsh-pet 适配修复验证（DPR / 交互回切 / 触摸）

- **ID**：JD-019
- **提交方**：WorkBuddy
- **接收方**：DevEco（编译 / 安装 / 真机复验）
- **日期**：2026-11-20 22:10
- **状态**：待编译 / 待测试
- **前置**：JD-018 PARTIAL —— DPR 1.75 失配、`setInteractive(false)` 后无 hover 回切、触摸拖拽被 touch-action 吃掉。

## 1. 本次修复

| # | 问题 | 修复 |
|---|---|---|
| 1 | `scale` 固定为 1，ArkWeb CSS px ≠ 窗口物理 px | 能力层按 `display.densityPixels` 动态生成 `scale`（本机 1.75），`setBounds`/命中区/拖拽全部走物理 px |
| 2 | `setUIContent` 之前设背景色 → 1300002 | 已按 JD-018 修复：`setUIContent` 之后设，try/catch |
| 3 | `setWindowTouchable(false)` 后无 hover，永久不可点 | `setInteractive(false)` 期间每 300ms 临时 true 50ms，让页面拿回一次 hover；页面判在身体内会调 true 停脉冲 |
| 4 | 触摸拖拽被 touch-action 吃掉 | shim 注入 `.pet-hit{touch-action:none!important}`（同源外部脚本，CSP 允许 style） |

产物：
`demo/dsh-pet-adapter-poc/build/outputs/default/dsh-pet-adapter-poc-default-signed.app`
62,670 B，sha256 `c9c1ca4a2ddd59adb963c375fcec05b092d12369e9d8e9c2c43425edb8a897b7`
（HAP 以模块产物 `entry-default-signed.hap` 为准，避免 JD-018 的 `.app` 内 HAP 未签名问题。）

## 2. 验证环境

与 JD-018 相同：

```sh
# 1) dsh-pet 纯 Node 宿主
mkdir -p /tmp/dsh-pet-home
DSH_HOME=/tmp/dsh-pet-home DSH_PET_IN_PROCESS=1 \
  node /tmp/dsh-pet-probe/pkg/lib/standalone.js --port 3080

# 2) 同源代理
cd demo/dsh-pet-adapter-poc
node tools/pet-proxy.mjs --plugin /tmp/dsh-pet-probe/pkg --upstream 3080 --port 3090

# 3) 编译安装
CODEBUDDY_SAFE_DELETE_ENABLED=0 devecocli build --product default
devecocli run --skip-build
```

## 3. 重点复验（按 JD-018 的失败项）

| # | 操作 | 期望 | 记录 |
|---|---|---|---|
| 1 | 启动后量宠物尺寸/位置 | 不再是 1.75× 放大；宠物完整在屏内，右缘不裁切 | 截图 + 窗口 rect |
| 2 | 鼠标拖动 300–500px | 窗口位移与指针 1:1（不再 ÷1.75²） | 前后坐标 + 位移比 |
| 3 | 触摸拖动 | 可拖（touch-action 修复） | 录屏/日志 |
| 4 | 空闲 > 10s 后把指针移到宠物身体上 | 300ms 内恢复可拖/可右键；不再永久穿透 | `setInteractive` 调用次数 / 交互结果 |
| 5 | 空闲时点击宠物身体外 | 仍穿透到桌面/下层窗口 | 录屏/前后截图 |
| 6 | 长按/右键菜单 | 菜单完整显示，不被右缘裁切 | 截图 |
| 7 | 漫游 10s | 子窗跟随，无 `setBounds rejected` | hilog |
| 8 | 置顶 / 无 Electron | 同 JD-018 PASS | 截图/ps |

重点日志（tag `DshPetHost`，domain `0xD004`）：
- `pet subwindow ready, url=...scale=1.75...`（确认 scale 已按密度）；
- `setBounds move rejected` / `resize rejected`（应为 0）；
- `setInteractive rejected`；
- 页内 `probe: ...` 计数（如仍能拿到）。

## 4. 判定

- **PASS**：1–8 全过，尤其拖动 1:1、空闲后可恢复交互、菜单不裁切；
- **PARTIAL**：DPR/触摸已修，但交互脉冲造成"宠物外点击偶发被窗口吃掉"或恢复延迟 >1s；
- **FAIL**：仍 1.75× 放大、拖动比例异常、或空闲后永久不可交互。

若 PARTIAL 且脉冲有副作用，请记录：外点被吃掉的频率/位置、恢复延迟、`setInteractive` 次数；下一步改"双窗（小命中窗 + 大穿透渲染窗）"。

## 5. 边界

- 只改/只装 `demo/dsh-pet-adapter-poc/`；不改主工程、不升版本、不 `git commit`。
- 宿主主窗残条仍为已知边界（不判失败）。
- 气泡/余额仍受 standalone 宿主能力面限制（无 `/balance`），不属本单。
- 若 DevEco 侧有本地代码改动，请以当前工作区为准重编，并在结论中注明 HAP sha。

## 6. 完成后

结论写入 `JD/from-deveco/20261120-dsh-pet-adapter-fix-result.md`：

```
JD-019 结论：PASS/PARTIAL/FAIL
产物 HAP sha256：
1 尺寸/裁切：
2 鼠标拖动位移比：
3 触摸拖动：
4 空闲后恢复交互：
5 外点穿透：
6 菜单：
7 setBounds 拒绝数：
8 置顶/无 Electron：
异常码/控制台原文：
```

并更新 `JD/STATUS.md`（JD-019）。

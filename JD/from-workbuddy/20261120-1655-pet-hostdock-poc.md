# 交接单：宿主藏底桌宠 POC（JD-015 遗留项收口）

- **ID**：JD-016
- **提交方**：WorkBuddy
- **接收方**：DevEco（编译 / 安装 / 真机取证）
- **日期**：2026-11-20 16:55
- **状态**：待编译 / 待测试
- **前置**：JD-015 PARTIAL —— 子窗透明/掩码/穿透/拖动 PASS；宿主主窗无法离屏或隐藏（x 钳 -250、min 320×100vp），minimize 连坐子窗。

## 1. 本单要解决什么

JD-015 已证子窗方案视觉成立，唯一遗留是宿主主窗必然可见（310×175px 残条）。本 POC 的取舍：

- 宿主不尝试离屏/隐藏，缩到系统最小 320×100vp（实际约 560×175px）；
- 宠物子窗放大到 **640px 圆**，宿主居中藏在圆体下方（几何：宿主半对角线约 294px < 圆半径 320px）；
- 每 100ms 读子窗 rect，把宿主居中跟随，避免拖动后露出黑条；
- 子窗**不传** `zLevelAboveParentLoosened`（JD-015 修正：true 会让子窗落到父窗下面）；
- `setUIContent` 先于背景/掩码（JD-015 修正：否则 130002）。

## 2. 源码与产物

| 项 | 值 |
|---|---|
| 工程 | `demo/pet-hostdock-poc/` |
| bundleName | `com.dshm.dshdemo`（复用本机 debug 签名，覆盖同名 demo） |
| 权限 | 仅 `WINDOW_TOPMOST` |
| 宿主 | `resize(320,100)` + 隐藏装饰/三键 + `setWindowTopmost(true)`，居中藏在宠物下 |
| 子窗 | 640px、`decorEnabled:false`、透明背景、圆形 alpha 掩码 |
| 同步 | 100ms 轮询子窗 rect → 宿主居中跟随（`host moved to x,y` 日志） |
| 产物 | `build/outputs/default/pet-hostdock-poc-default-signed.app`，59,415 B，sha256 `b3735f36a0ba0b207ea2f9624a30025fc3e5253fc1a21e95afae3df6a6c441fb` |

## 3. 编译安装

```sh
cd demo/pet-hostdock-poc
CODEBUDDY_SAFE_DELETE_ENABLED=0 devecocli build --product default
devecocli device list
devecocli run --skip-build
```

签名说明同 JD-014/015：bundle 固定 `com.dshm.dshdemo`；本机 profile 不可用时用 DevEco Studio 生成调试签名，bundle 不变。

## 4. 验证项（7 项）

| # | 操作 | 预期 | 记录 |
|---|---|---|---|
| 1 | 启动 | 右下角 640px 圆宠；宿主黑条**不可见** | 截图；`host init rect` / `sub rect` |
| 2 | 切浏览器/微信 | 宠物仍最上层 | 截图（重叠区像素） |
| 3 | 宠物圆外点击 | 穿透 | 录屏/前后截图 |
| 4 | 拖动宠物 | 宿主跟随，黑条不露出；记录是否抖动/滞后 | 拖动中录屏 + `host moved to` 日志 |
| 5 | 拖到屏幕边缘 | 记录宿主被钳制时黑条是否露出 | 截图 + host/sub rect |
| 6 | 宿主最小化 | 记录子窗是否隐藏（JD-015 已知会；本次确认是否可接受） | 截图 + `ps` |
| 7 | 右键退出 | 子窗/宿主一起消失 | 截图 |

重点日志（tag `PetDockPoc`，domain `0xD003`）：
- `host init rect=` / `sub rect=`；
- `host moved to x,y`（频率/是否抖动）；
- `host move rejected`（钳制）；
- 任何 `401/801/1300002/1300004`。

## 5. 判定口径

- **PASS**：1–4、7 全过，且拖动过程中宿主黑条不露出；
- **PARTIAL**：宠物显示/置顶/穿透/拖动均过，但拖动同步有明显抖动或边缘露出黑条；
- **FAIL**：宿主黑条始终可见、或子窗无法显示/透明/穿透。

第 6 项不单独作为 PASS/FAIL：它是已知产品取舍（最小化 = 收起桌宠）。请记录实际行为。

## 6. 边界与红线

- 只改/只装 `demo/pet-hostdock-poc/`；不改主工程 `entry`/`phone` 权限面、版本号、交付件。
- 不 `git commit` / `push`；不动 `signing/**`、`.certs/**`、`dist/**`。
- 安装会覆盖 `com.dshm.dshdemo`。

## 7. 完成后

结论写入 `JD/from-deveco/20261120-pet-hostdock-poc-result.md`：

```
JD-016 结论：PASS / PARTIAL / FAIL
产物：路径 + sha256
设备：型号 / 系统版本
1 启动：截图 + host/sub rect
2 置顶：截图/像素
3 穿透：结果
4 拖动跟随：是否露出/抖动
5 边缘：host 是否被钳制
6 最小化：子窗是否隐藏
7 退出：结果
异常码：401/801/1300002/1300004 原文
```

并更新 `JD/STATUS.md`（JD-016）。

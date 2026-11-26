# PC/2in1 宿主藏底桌宠 POC

针对 JD-015 的遗留问题：宿主主窗无法离屏/隐藏（x 钳 -250，min 320×100vp），minimize 连坐子窗。

本 POC 的取舍：**宿主不隐藏，直接藏在 640px 宠物圆体下方**，每 100ms 把宿主居中到子窗下方，残条不应露出。

## 与 JD-015 的修正

- `zLevelAboveParentLoosened` **不传**（默认 false）；JD-015 实测 true 会让子窗落到父窗/被抬升应用之下。
- `setUIContent` **先于** `setWindowBackgroundColor` / `setWindowMaskWithAlpha`；JD-015 首启 1300002 的根因。
- 宿主 320×100vp（实际约 560×175px）；宠物 640px 圆，宿主矩形半对角线约 294px < 圆半径 320px，几何上应完全遮住。

## 验证项

| # | 操作 | 预期 |
|---|---|---|
| 1 | 启动 | 右下角圆形宠物，宿主黑条不可见 |
| 2 | 切其他应用 | 宠物仍在最上层 |
| 3 | 宠物圆外点击 | 穿透 |
| 4 | 拖动宠物 | 宿主跟随，黑条不露出；记录是否抖动/滞后 |
| 5 | 拖到屏幕边缘 | 记录宿主是否被钳制、黑条是否露出 |
| 6 | 宿主最小化 | 记录子窗是否隐藏（JD-015 已知会） |
| 7 | 右键退出 | 正常退出 |

## 构建

```sh
cd demo/pet-hostdock-poc
CODEBUDDY_SAFE_DELETE_ENABLED=0 ~/.deveco/bin/devecocli build --product default
devecocli run --skip-build
```

bundle 复用 `com.dshm.dshdemo`，会覆盖同名 demo；仅 `deviceTypes:["2in1"]`，权限仅 `WINDOW_TOPMOST`。

# PC/2in1 独立子窗桌宠 POC

目的：验证「主窗不透明」的替代架构——**独立子窗**（`zLevelAboveParentLoosened: true`，API 26）。

## 架构

- 宿主主窗：`supportWindowMode: ["floating"]`，缩到 320×72 并移到屏幕外；只负责 `setWindowTopmost(true)` 与作为子窗父级。
- 桌宠子窗：`createSubWindowWithOptions(..., { decorEnabled:false, zLevelAboveParentLoosened:true })`；
  `setWindowBackgroundColor('#00000000')` + `setWindowMaskWithAlpha(圆形掩码)`。
- 独立子窗特性（官方）：自由窗口下可超出主窗范围；**不跟随主窗前后台切换**，仅随主窗销毁。

## 验证项

| # | 操作 | 预期 |
|---|---|---|
| 1 | 启动 | 屏幕右下角出现圆形宠物；宿主主窗不可见（或仅极窄边缘） |
| 2 | 切到其他应用 | 宠物仍在最上层（父窗 topmost） |
| 3 | 桌面/其他窗口在宠物圆外点击 | **应穿透**（掩码 0=透明且不可交互） |
| 4 | 按住宠物拖动 | 子窗跟随移动 |
| 5 | 右键宠物 | 菜单可退出/记录状态 |
| 6 | 宿主失焦/后台 30s | 宠物仍在（独立子窗不跟随前后台） |
| 7 | 读 hilog `PetSubPoc` | `host rect=` 是否被吸附回屏内；`sub rect=`；无 1300004 |

## 构建安装

```sh
cd demo/pet-subwindow-poc
CODEBUDDY_SAFE_DELETE_ENABLED=0 ~/.deveco/bin/devecocli build --product default
devecocli run --skip-build
```

- bundle 复用 `com.dshm.dshdemo`（本机 debug 签名），会覆盖同名 demo。
- 仅 `deviceTypes: ["2in1"]`；只新增 `WINDOW_TOPMOST`，不需要 `SET_WINDOW_TRANSPARENT`。
- 若宿主主窗被系统吸附回屏幕内，记录 `host rect`，后续改为“贴边隐藏”或评估 `hide()` 对独立子窗的影响。

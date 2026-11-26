# PC/2in1 悬浮桌宠 POC

目的：在**不改主工程**的前提下，验证 PC 端桌宠窗口的公开能力边界。

## 验证项与预期

| # | 操作 | 预期 |
|---|---|---|
| 1 | 启动后切到其他应用 | 桌宠窗口仍在最上层（`WINDOW_TOPMOST`） |
| 2 | 观察窗口四角 | 真透明、无窗口阴影、无标题栏/三键 |
| 3 | 按住宠物拖动 | `startMoving()` 可移动窗口 |
| 4 | 点击透明四角 | **预计仍会拦截**（主窗不支持 `setWindowMaskWithAlpha`，见复核报告） |
| 5 | 右键宠物 → 退出桌宠 | 退出 |
| 6 | 窗口失焦 / 最小化主窗口 | 观察宠物动画与进程是否继续 |

## 构建与安装（仅本机 2in1）

```sh
cd demo/pet-float-poc
CODEBUDDY_SAFE_DELETE_ENABLED=0 ~/.deveco/bin/devecocli build --product default
~/.deveco/bin/devecocli run --skip-build
```

说明：
- bundleName 复用 `com.dshm.dshdemo`，会覆盖本机已有的同名 demo 应用；这是为了复用现有本机调试签名（当前设备未登录 DevEco，无法生成新 profile）。
- 权限仅在本 POC 的 `module.json5` 声明：`WINDOW_TOPMOST`、`SET_WINDOW_TRANSPARENT`；**主工程权限面未改动**。
- 仅 `deviceTypes: ["2in1"]`；平板/手机不在本 POC 范围。

## 已知边界（来自复核报告）

- 主窗不能逐像素点击穿透：`setWindowMaskWithAlpha` 仅子窗/全局悬浮窗可用。
- 全局悬浮窗 `TYPE_FLOAT` 需要受限权限 `SYSTEM_FLOAT_WINDOW`，桌宠场景不适用。
- `excludeFromMissions` 对三方应用无效，桌宠会出现在最近任务/Dock。
- 透明 ArkWeb 有 GPU 合成功耗风险；本 POC 用原生 ArkUI 图形，不引入 Web。

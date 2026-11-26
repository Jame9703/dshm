# dsh-pet 桌面宿主适配 POC（阶段 2）

不改 dsh-pet、不自绘宠物：把插件自己的 `runtime/electron-helper/index.html` 装进 ArkTS 透明子窗，用 `petBridge` 映射窗口 API。

## 运行前置

1. 按 JD-017 起 dsh-pet 独立宿主（纯 node，无 Electron）：

```sh
mkdir -p /tmp/dsh-pet-home
DSH_HOME=/tmp/dsh-pet-home DSH_PET_IN_PROCESS=1 \
  node /tmp/dsh-pet-probe/pkg/lib/standalone.js --port 3080
```

2. 起同源代理（3090）：

```sh
cd demo/dsh-pet-adapter-poc
node tools/pet-proxy.mjs --plugin /tmp/dsh-pet-probe/pkg --upstream 3080 --port 3090
```

3. 编译安装 POC：

```sh
CODEBUDDY_SAFE_DELETE_ENABLED=0 devecocli build --product default
devecocli run --skip-build
```

## 验证

- 透明子窗出现 dsh-pet **自己的**「蓝毛小女仆」动画，不是 DSHM 画的圆；
- 宠物可拖动、右键菜单、气泡、漫游由插件自己驱动；
- `setBounds` 驱动窗口移动/缩放；`setInteractive` 控制点击穿透；
- 注意 CSP：shim 必须同源外部脚本（代理已注入）。

## 已知边界

- 宿主主窗仍受最小尺寸/不能离屏限制，本 POC 用 320×100 宿主藏在宠物下，边缘可能露出；
- 首版只映射 7 个同步方法；`onDisplays` 由 `runJavaScript` 下发；`onPointerLeft/onPetHit/onFlightStates/reportCollide` 暂 no-op；
- 多宠物、`captureScreen`、碰撞后续再接。

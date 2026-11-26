# 交接单：dsh-pet 桌面宿主适配 POC（阶段 2，ArkTS）

- **ID**：JD-018
- **提交方**：WorkBuddy
- **接收方**：DevEco（编译 / 安装 / 真机取证）
- **日期**：2026-11-20 18:15
- **状态**：待编译 / 待测试
- **前置**：JD-017 PASS —— dsh-pet 自己的渲染页可在纯 Node 宿主中跑出宠物；本单验证 ArkTS 透明子窗 + `petBridge` 映射。

## 1. 本单验证什么

把 dsh-pet 的 `runtime/electron-helper/index.html` 装进 ArkTS 透明子窗，验证：

1. 出现的是**插件自己的**「蓝毛小女仆」动画，不是 DSHM 画的宠物；
2. `petBridge.setBounds` 能驱动子窗移动/缩放（宠物漫游时窗口跟随）；
3. `setInteractive` 能控制整窗点击穿透（身体内可拖、身体外穿透）；
4. 右键菜单/气泡/漫游由插件自己渲染；
5. 宿主主窗 topmost 能带起子窗；
6. 全程无 Electron 进程。

## 2. 工程与产物

| 项 | 值 |
|---|---|
| 工程 | `demo/dsh-pet-adapter-poc/` |
| bundleName | `com.dshm.dshdemo`（复用本机 debug 签名，覆盖同名 demo） |
| deviceTypes | `["2in1"]` |
| 权限 | `INTERNET` + `WINDOW_TOPMOST` |
| 窗口 | 宿主 320×100vp 置于宠物下；透明子窗（decor=false，无掩码，背景 `#00000000`） |
| 页面 | `pages/PetWeb`：ArkWeb 加载 `http://127.0.0.1:3090/dsh-pet-native/probe.html?...` |
| 桥 | `__DSHM_PET_BRIDGE__` 同步 7 方法；`onDisplays` 由 `runJavaScript` 下发；shim 由代理注入 |
| 产物 | `build/outputs/default/dsh-pet-adapter-poc-default-signed.app`，57,505 B，sha256 `cab9124b838354946152a112448fc650f95167e8a271b8daba7a4574763e4563` |

关键文件：
- `demo/dsh-pet-adapter-poc/entry/src/main/ets/entryability/EntryAbility.ets`
- `demo/dsh-pet-adapter-poc/entry/src/main/ets/pages/PetWeb.ets`
- `demo/dsh-pet-adapter-poc/entry/src/main/ets/pages/PetWindowHolder.ets`
- `demo/dsh-pet-adapter-poc/tools/pet-proxy.mjs`
- `demo/dsh-pet-adapter-poc/tools/pet-bridge-shim.js`
- `demo/dsh-pet-adapter-poc/README.md`

## 3. 运行前置（同一台 2in1）

1. 按 JD-017 准备 dsh-pet 包；若临时目录已清理，重新：

```sh
mkdir -p /tmp/dsh-pet-probe && cd /tmp/dsh-pet-probe
npm pack dsh-pet@0.4.9
mkdir -p pkg && tar -xzf dsh-pet-0.4.9.tgz -C pkg --strip-components=1
```

2. 起纯 Node 宿主（3080）：

```sh
mkdir -p /tmp/dsh-pet-home
DSH_HOME=/tmp/dsh-pet-home DSH_PET_IN_PROCESS=1 DSH_PET_LOG_DEBUG=1 \
  node /tmp/dsh-pet-probe/pkg/lib/standalone.js --port 3080
```

3. 起同源代理（3090）：

```sh
cd demo/dsh-pet-adapter-poc
node tools/pet-proxy.mjs --plugin /tmp/dsh-pet-probe/pkg --upstream 3080 --port 3090
```

4. 浏览器先自检代理：

```
http://127.0.0.1:3090/dsh-pet-native/probe.html?configUrl=http://127.0.0.1:3090/dsh-pet-7340/config&petIndex=0&scale=1&bridge=0&openTarget=web
```

应能看到插件自己的宠物（与 JD-017 相同）；看不到先修代理/CSP，不要继续装 POC。

5. 编译安装 POC：

```sh
cd demo/dsh-pet-adapter-poc
CODEBUDDY_SAFE_DELETE_ENABLED=0 devecocli build --product default
devecocli run --skip-build
```

## 4. 验证项

| # | 操作 | 预期 | 记录 |
|---|---|---|---|
| 1 | 启动 | 透明子窗出现插件自己的宠物；宿主黑条不可见或仅窄边 | 截图 + `hilog DshPetHost` |
| 2 | 观察 10s | 宠物漫游/呼吸，窗口跟随（`setBounds`） | 录屏 + `setBounds rejected` 日志 |
| 3 | 按住宠物拖 | 宠物跟随手指，窗口同步 | 前后截图 |
| 4 | 点击身体外透明区 | 穿透到桌面/下层窗口 | 录屏/前后截图 |
| 5 | 右键宠物 | 插件自己的菜单/气泡 | 截图 |
| 6 | 切浏览器/微信 | 宠物仍在最上层 | 截图 |
| 7 | 进程检查 | 无 Electron 子进程 | `ps` 片段 |

重点日志：tag `DshPetHost`（domain `0xD004`）。
- `pet subwindow ready`；
- `setBounds move rejected` / `resize rejected`（1300002/1300004/801）；
- `setInteractive rejected`；
- `deliverDisplays failed`；
- 任何 CSP/网络 401/404（Web 控制台）。

## 5. 判定

- **PASS**：1–7 全过，且宠物是插件自己的动画、可拖、可穿透；
- **PARTIAL**：宠物出现但拖动/穿透异常（记录 `setBounds`/`setInteractive` 错误、窗口是否卡住）；
- **FAIL**：空白/宠物不出现（CSP、代理、Web 加载失败）或子窗无法透明。

## 6. 已知边界

- 宿主主窗不能离屏/最小化，本 POC 用 320×100 藏在宠物下；边缘可能露出，不作为本单失败项，记录即可。
- 首版只映射 7 个同步方法；`captureScreen` 返回 null，`onPointerLeft/onPetHit/onFlightStates/reportCollide` no-op；多宠物/聊天语音后续再接。
- `setInteractive(false)` 期间整窗不可交互，这是预期；若宠物身体内也点不动，检查渲染页是否把身体命中区算错（`setBounds` 的 box/margin 参数是否被正确传递）。

## 7. 完成后

结论写入 `JD/from-deveco/20261120-dsh-pet-adapter-poc-result.md`：

```
JD-018 结论：PASS/PARTIAL/FAIL
产物 sha256：
设备/系统：
1 启动：截图
2 窗口跟随：录屏/日志
3 拖动：结果
4 穿透：结果
5 菜单/气泡：截图
6 置顶：截图
7 无 Electron：ps 片段
异常码/控制台原文：
```

并更新 `JD/STATUS.md`（JD-018）。

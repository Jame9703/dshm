# 交接单 / DevEco 提示词：dsh-pet 桌面宿主可行性探测（JD-017）

- **ID**：JD-017
- **提交方**：WorkBuddy
- **接收方**：DevEco
- **日期**：2026-11-20 17:15
- **状态**：待执行
- **性质**：只验证「dsh-pet 插件自己的渲染页能否在非 Electron 宿主里跑起来」；**不写自研桌宠**。

## 背景

用户明确：不是让我们画桌宠，而是给 `dsh-pet` 插件提供它需要的桌面宿主环境。已核对 `dsh-pet@0.4.9`：

- `DSH_PET_IN_PROCESS=1` 会让插件不 spawn Electron、也不下载 Electron；
- 插件自己的渲染页是 `runtime/electron-helper/index.html`；
- 渲染页从 `configUrl` 拉 `/dsh-pet-7340/config` 与素材，并通过 `window.petBridge` 控制窗口；
- 宿主只需提供「透明窗口 + petBridge 映射 + 同源路由」，不参与宠物 UI。

完整方案见 `outputs/DSHM-dsh-pet接入方案-20261120.md`。

## 本次只做阶段 1（宿主可行性）

**目标**：证明不装 Electron 也能让插件渲染页正常跑出它自己的宠物。

### 步骤

1. 准备插件包（不要用 Electron）：

```sh
mkdir -p /tmp/dsh-pet-probe && cd /tmp/dsh-pet-probe
npm pack dsh-pet@0.4.9
mkdir -p pkg && tar -xzf dsh-pet-0.4.9.tgz -C pkg --strip-components=1
```

2. 用独立模式起宿主，强制 in-process：

```sh
mkdir -p /tmp/dsh-pet-home
DSH_HOME=/tmp/dsh-pet-home DSH_PET_IN_PROCESS=1 DSH_PET_LOG_DEBUG=1 \
  node /tmp/dsh-pet-probe/pkg/lib/standalone.js --port 3080
```

3. 确认没有 Electron：

- 进程列表无 `electron`；
- 日志无 `electron helper started` / 下载；
- `$DSH_HOME/dsh-pet/standalone-runtime.json` 有 `port/token/pluginRoot`。

4. 读 token，确认配置与路由：

```sh
TOKEN=$(python3 -c "import json;print(json.load(open('/tmp/dsh-pet-home/dsh-pet/standalone-runtime.json'))['token'])")
curl -s -H "x-dsh-pet-token: $TOKEN" http://127.0.0.1:3080/dsh-pet-7340/config | head -c 800
```

若返回 401/403，记录实际鉴权方式（header/query/cookie）并继续。

5. 把「插件路由」与「渲染页静态文件」放到**同一个 origin**（避免跨源/令牌问题）。写一个最小 Node 代理 `probe-proxy.mjs`：

- `/dsh-pet-7340/*` → `http://127.0.0.1:3080`，自动带 `x-dsh-pet-token`；
- `/dsh-pet-native/*` → `/tmp/dsh-pet-probe/pkg/runtime/electron-helper/*`；
- 监听 `3090`。

6. 复制 `index.html` 为 `probe.html`，在原有脚本之前插入一个最小 `window.petBridge`（全部方法先做 no-op，`setBounds` 只打日志）：

```js
window.petBridge = {
  setBounds(){}, setInteractive(){}, setInputBusy(){}, setInputRegions(){},
  requestKeyboardFocus(){}, openDshSite(){}, focusDshHost(){},
  captureScreen(){ return Promise.resolve(null); },
  onFlightStates(){}, reportCollide(){}, onPetHit(){}, onDisplays(){}, onPointerLeft(){}
};
```

7. 把配置里第一只宠物设为桌面可见（`$DSH_HOME/dsh-pet/main-config.jsonc`，字段 `display: "desktop"` 或 `"both"`），重启宿主，浏览器打开：

```
http://127.0.0.1:3090/dsh-pet-native/probe.html?configUrl=http://127.0.0.1:3090/dsh-pet-7340/config&petIndex=0&scale=1&bridge=0&openTarget=web
```

### 判定

- **PASS**：页面出现插件自己的宠物（视频动画），无 Electron 进程；控制台无致命错误；
- **PARTIAL**：配置/素材能取到，但渲染页因缺少某个 `petBridge` 能力报错；请记录**缺哪个方法/哪一行**；
- **FAIL**：`/config` 无法鉴权、素材 404、渲染页无法执行、或插件仍强依赖 Electron。

### 必须回填

```
JD-017 结论：PASS/PARTIAL/FAIL
dsh-pet 版本：
DSH_HOME：
宿主端口 / 代理端口：
鉴权方式（header/query/cookie）：
/config 状态码 + 前 200 字符：
渲染页截图：
宠物是否出现（插件自己的动画）：
Electron 进程：无/有
控制台错误原文：
缺少的 petBridge 方法：
```

结论写入 `JD/from-deveco/20261120-dsh-pet-probe-result.md`，并更新 `JD/STATUS.md` JD-017。

## 边界

- 不写自研宠物、不改 DSHM 主工程、不升版本号、不 `git commit`；
- 不安装/下载 Electron；
- 不把 `DSH_PET_IN_PROCESS=1` 写进正式包环境，仅本次探测；
- 阶段 2（ArkTS 透明子窗 + petBridge 映射）由 WorkBuddy 接续，DevEco 完成阶段 1 即可回填。

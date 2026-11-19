# 226 · 鸿蒙 PC 浏览器扩展故障复核与重适配（CUSTOM_SANDBOX 后）

> **本工程实施结果（2026-10-22）**：已按本文完成扩展 `0.11.2` /
> build `dshm-host-bridge-13`、扩展 `screenshot=false`、Host 默认不注册
> `browser_screenshot`，核心 `+dshm.84` 已构建并覆盖安装。新的
> `dshm-browser-ext-v012` 已由用户在海泰扩展管理页加载，设备实读连接为
> `0.11.2 / dshm-host-bridge-13`，能力工具列表不含 screenshot。真实
> `navigate` / `get_text` / `tabs` / `get_tree` / `network` / `cdp_eval` /
> `click` / `type` / `select_tab` / `close` 均已通过；截图兼容调用 11 ms
> 内 fail-fast。
>
> 后续冷启动复核发现旧实现只有 `browser_navigate` 会拉起浏览器，模型先调用
> `browser_status` 时会直接得到 `clients=[]`。现在所有浏览器工具在发现无客户端时
> 都会主动拉起海泰并打开 Host 提供的普通 http 启动页
> `/dshm-browser/start`，避免只得到 `chrome://newtab`。`browser_navigate`
> 遇到“扩展在线但无候选 tab”也会强制按目标 URL 再拉起一次并重试。
>
> `.84` 冷启动实测：海泰停止后，真实 `browser_status` 3.6 秒返回
> `launch=launched-and-connected`；`browser_tabs` 立即看到活动页为
> `http://127.0.0.1:3120/dshm-browser/start`，随后 `browser_navigate`
> 1.7 秒内复用该标签完成 `https://example.com` 的 CDP 导航。

> 日期：2026-10-22
>
> 范围：PC-only 工程 `com.dshm.dshclient`
>
> 结论先说：`CUSTOM_SANDBOX` 已生效，Host loopback、WebSocket、固定 token、
> 海泰扩展回连、CDP 导航、正文读取和标签页读取均正常。当前真实失败面是
> `browser_screenshot`；海泰内核不支持扩展截图。当前 0.11.1/build 12 已经正确
> fail-fast，但扩展仍把 `screenshot` 声明为可用能力，Host 插件也无条件注册
> `browser_screenshot`，导致模型持续调用一个必然失败的工具，看起来像“浏览器扩展
> 整体失效”。
>
> 本文给出两条结论：
>
> 1. 立即可做：0.11.2/build 13 删除海泰的 `screenshot` 能力并停止注册该工具，
>    导航、读树、点击、输入、正文、标签页和网络能力保持；
> 2. 后续可选：如果必须自动截取海泰画面，只能新做 ArkTS 系统屏幕捕获桥，并申请
>    `ohos.permission.CUSTOM_SCREEN_CAPTURE`。这会打破当前 PC 恒 11 权限面，
>    必须另行做 Profile、AGC 隐私和审核评估，不能顺手加。

## 1. 现场基线

| 项 | 实读值 |
|---|---|
| 设备 | 鸿蒙 PC，HDC `86E0226429000417` |
| 工程实际路径 | `/storage/media/100/local/files/Docs/data/DSHM-deveco-workspace` |
| 用户侧下载目录 | `~/Download/com.dshm.dshclient` |
| Bundle | `com.dshm.dshclient` |
| 版本 | `1.1.4 / 1010004` |
| 构建 | `debug=true` |
| 本机调试 appIdentifier | `6918740027110769940` |
| AGC 正式 App ID | `6917614360926110054` |
| SELinux 域 | `u:r:develop_tools_debug_hap:s0` |
| Host PID（取证时） | `21641` |
| Host HTTP | `http://127.0.0.1:3120` |
| 浏览器桥 WS | `ws://127.0.0.1:19390/browser-bridge` |
| Host 形态变量 | `DSHM_DEVICE_FORM=desktop` |
| 核心版本 | `0.2.1-rc.2+dshm.80` |
| PC 权限面 | 恒 11 条：3 条 ACL + 2 条 kernel + 6 条普通权限 |
| 海泰扩展版本 | `0.11.1`，build `dshm-host-bridge-12` |
| PC 工程扩展路径 | `/storage/media/100/local/files/Docs/data/DSHM-deveco-workspace/hostcore/browser-extension` |
| 当前部署目录 | `~/Download/com.dshm.dshclient/dshm-browser-ext-v011` |

注意区分两个 identity：

- 设备本机调试签名使用 `appIdentifier=6918740027110769940`；
- AGC 正式发布使用 App ID `6917614360926110054`。

不要把本机 debug Profile 的 appIdentifier 写进 AGC 发布件，也不要据此重新建应用。
详见 `docs/212`、`docs/222`。

## 2. 现场事实：桥本身是通的

### 2.1 Host 与扩展回连

`GET http://127.0.0.1:3120/dshm-browser/status` 实读：

```json
{
  "ok": true,
  "port": 19390,
  "clients": [
    {
      "id": "ws_1",
      "info": {
        "extensionVersion": "0.11.1",
        "build": "dshm-host-bridge-12",
        "browserType": "chromium",
        "displayName": "DSHM Browser Bridge"
      }
    }
  ]
}
```

日志中扩展 WebSocket 来源为 Chromium 扩展 origin，Host 打印
`browser-bridge: extension connected` 与 `extensionInfo`，不是“扩展没连上”。

### 2.2 四个正常能力

`navigate` 实读：

```json
{
  "ok": true,
  "result": {
    "ok": true,
    "tabId": 1960788069,
    "url": "https://example.com",
    "load": "complete",
    "via": "cdp-pagenavigate"
  }
}
```

`get_text` 实读成功，且 `via="script"`，正文是 Example Domain 的真实页面文本。

`tabs` 实读成功，返回活动页：

```json
{
  "id": 1960788069,
  "title": "Example Domain",
  "url": "https://example.com/",
  "active": true
}
```

Host 日志统计到 51 次 `/dshm-browser/invoke`，其中：

| 工具 | 次数 |
|---|---:|
| `navigate` | 14 |
| `get_text` | 7 |
| `tabs` | 9 |
| `get_tree` | 1 |
| `network` | 1 |
| `screenshot` | 19 |

全部 51 次都有对应完成记录；除一次旧 token 导致的 401 外，Host HTTP 层都返回 200。
浏览器工具当前不是“全部失败”，而是 `screenshot` 反复失败。

### 2.3 CUSTOM_SANDBOX 不是浏览器桥故障源

`CUSTOM_SANDBOX` 已把进程放入 `u:r:develop_tools_debug_hap:s0`。
本次 Host 原生执行读数同时显示：

```text
python3.12=ok，git=ok，git-core/git=ok，git-remote-http=ok，rg=ok，
ash=ok，bash=ok，system-sh=ok，toybox=ok，git-ls-remote=ok
```

浏览器扩展在海泰进程里运行，只通过 `127.0.0.1:19390` 回连 DSHM Host。
这条 loopback 已实测通，`CUSTOM_SANDBOX` 没有阻断它。

`host-ready.json` 中 `runtime.natives.sandbox-dlopen=false` 表示：

```text
从应用 files 目录复制出的 ELF/.so 仍会被内核拒绝 dlopen
```

它与浏览器扩展无关，不能据此判断 `CUSTOM_SANDBOX` 没生效，也不能拿它解释
WebSocket 或 CDP 失败。当前随包 HAP libs 原生件正常，浏览器桥不需要 dlopen。

## 3. 根因

### 3.1 P0 真根因：海泰内核不支持扩展截图

海泰 Chromium 内核实测：

| 路径 | 行为 |
|---|---|
| `chrome.tabs.captureVisibleTab` | Promise 与 callback 都可能同步/长时间挂住 |
| CDP `Page.captureScreenshot(fromSurface=false)` | 明确拒绝，只允许 surface |
| CDP `Page.captureScreenshot(fromSurface=true)` | Promise 与 callback 都不返回 |

历史上 19 次截图请求中，多条日志出现：

```text
screenshot captureVisibleTab 失败：
captureVisibleTab: Tabs cannot be edited right now (user may be dragging a tab).
```

以及：

```text
screenshot surface-callback start
... 20s 后宿主超时
```

继续等待只会把扩展 Service Worker 一起拖死，随后用户看到扩展掉线，误以为是
token、WebSocket 或 `CUSTOM_SANDBOX` 又坏了。当前 0.11.1/build 12 已把路径改成
立即抛出明确错误，方向正确。

当前直接调用扩展 `screenshot` 的实读结果：

```json
{
  "ok": false,
  "error": "[TOOL_ERROR] 当前海泰浏览器内核不支持扩展截图：tabs.captureVisibleTab 会同步挂起；Page.captureScreenshot 仅允许 surface，而 surface 调用也不返回。导航、读树、点击、输入、正文和网络工具不受影响；需要截图时请用系统截图工具。"
}
```

### 3.2 剩余适配缺陷：能力声明与实际支持不一致

当前扩展的 `TOOLS` 仍包含 `screenshot`，所以 `extensionInfo.capabilities.tools`
也会把它报成可用：

```text
navigate, get_tree, click, get_text, cdp_eval, close, screenshot,
type, tabs, select_tab, network
```

同时 Host 插件 `dshm-tool-browser` 无条件注册 `browser_screenshot`。
这会让模型认为该能力存在，尤其在任务提到“看一下页面”“截图”“检查渲染”时反复调用。
每次调用都失败，用户体验就会表现为“浏览器扩展一直失败”。

这不是权限问题，而是**能力协商缺失**：

- 扩展知道自己不能截图；
- Host 仍把截图工具放进模型工具面；
- 两边没有在注册前完成 capability negotiation。

0.11.2 必须同时修扩展和 Host，不能只改其中一个。

### 3.3 同目录热改导致的海泰缓存干扰

海泰对“加载已解压的扩展程序”存在目录级缓存。历史取证中出现过同一版本号、同一
`dshm-browser-ext-v011` 目录里替换 `background.js` 后，Service Worker 仍执行旧代码的
现象，表现为：

- 明明已经写入 fail-fast；
- 日志仍显示 `captureVisibleTab` 或 `surface-callback` 长时间运行；
- 多次点“重新加载”后行为才切换。

以后任何扩展代码变化都必须：

1. 升 `manifest.version`；
2. 升 `extensionInfo.build`；
3. 部署到新目录，例如 `dshm-browser-ext-v012`；
4. 在海泰扩展页重新加载新目录；
5. 保留旧目录只用于回滚，不能把新文件覆盖进旧目录。

### 3.4 两个仍然存在的运行边界

#### debugger 独占

海泰 `chrome.debugger` 与 WorkBuddy/Ultron 等其它调试器扩展互斥。日志里出现过：

```text
Cannot attach to this target.
```

若导航、读树或点击开始报 attach 失败，先把其它占用调试器的扩展停掉。当前这次
取证中 CDP `Page.navigate` 成功，说明当时没有独占冲突。

#### 必须有普通 http(s) 页面

海泰不允许扩展创建/控制扩展管理页等特殊页面。自动化目标必须是一个普通
`http://` 或 `https://` 标签页。扩展管理页、`haitai://` 页面不能作为 `get_tree`
或 `get_text` 的目标。

## 4. 为什么不能直接给扩展补系统截图权限

HarmonyOS 官方能力边界如下（本地文档快照 V244，抓取于 2026-10-15）：

| API | 能力 | 当前约束 |
|---|---|---|
| `screenshot.pick()` | PC/2in1 可选择区域截图 | 无权限，但需要用户框选，不是静默自动截图 |
| `screenshot.capture()` | 全屏/指定 display 截图 | 需要 `CUSTOM_SCREEN_CAPTURE` 或 `CUSTOM_SCREEN_RECORDING` |
| `window.snapshot()` | 当前应用自己的窗口截图 | 不能截外部海泰窗口 |
| `window.getMainWindowSnapshot()` | 指定主窗截图 | 只覆盖本应用窗口，并需要 `CUSTOM_SCREEN_CAPTURE` |
| 闪控球 + `screenshot.capture()` | 应用退后台后由闪控球触发截图 | 还要 `USE_FLOAT_BALL`，且 AGC 要求有真实跨应用场景 |
| UI Test `Driver.screenCap()` | 自动化测试截图 | 只属于测试框架，不是产品运行 API |

官方参考：

- <https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/js-apis-screenshot>
- <https://developer.huawei.com/consumer/cn/doc/capabilities/screenshot-and-privacy-mode>
- <https://developer.huawei.com/consumer/cn/doc/dev-faq/faqs-arkui-1053>

因此当前不能把“扩展截图失败”修成“偷偷给扩展加一个系统截图权限”：

1. 当前 PC 权限面是恒 11 条，`CUSTOM_SCREEN_CAPTURE` 不在其中；
2. 新增权限需要修改 `module.json5`、debug/release Profile、AGC 权限说明和隐私说明；
3. `screenshot.pick()` 虽然无需权限，但必须用户参与框选；
4. 用户没有要求“每次截图都弹选择器”，不能擅自把自动化工具改成人工操作；
5. 自动截取外部浏览器属于隐私敏感能力，审核风险明显高于当前 loopback 浏览器桥。

结论：在当前权限与产品口径下，海泰扩展自动截图应当明确标记为不支持。

## 5. 推荐重适配方案

### 5.1 P0：0.11.2/build 13 做能力收口

#### 扩展侧

文件：

```text
hostcore/browser-extension/manifest.json
hostcore/browser-extension/background.js
```

改动：

1. `manifest.json` 的 `version` 改为 `0.11.2`；
2. `extensionInfo` 的 `extensionVersion` 改为 `0.11.2`，`build` 改为
   `dshm-host-bridge-13`；
3. `TOOLS` 删除 `screenshot`；
4. 在 `extensionInfo` 增加明确能力字段：

```js
capabilities: {
  tools: TOOLS.map((t) => t.name),
  screenshot: false,
  screenshotReason: 'haitai-kernel-unsupported'
}
```

5. `runTool('screenshot')` 保留兼容分支，但只返回稳定的不支持错误，
   不再尝试 `captureVisibleTab` 或 `Page.captureScreenshot`；
6. 部署目录改为：

```text
~/Download/com.dshm.dshclient/dshm-browser-ext-v012
```

#### Host 插件侧

文件：

```text
hostcore/plugins/dshm-tool-browser/lib/index.js
```

改动：

1. 新增开关，默认关闭截图：

```js
export function browserScreenshotEnabled(env = process.env) {
  return String(env.DSHM_BROWSER_SCREENSHOT || '').trim().toLowerCase() === 'on';
}
```

2. `apply()` 中只在开关为 `on` 时注册 `browser_screenshot`；
3. PC 当前不设置这个环境变量，因此模型工具面根本不出现截图工具；
4. 以后换成支持截图的 Chromium 或完成 ArkTS 截图桥后，再显式打开；
5. `browser_status` 可附带：

```text
connected=1; screenshot=unsupported(haitai-kernel)
```

这样模型和开发者都能区分“扩展在线”和“截图不可用”。

6. 所有浏览器工具在调用前检查 `clients`；为空时通过 `/dshm-open-link`
   打开 Host 本地 `/dshm-browser/start`。这是普通 http 页面，扩展可直接附着；
   `browser_status` 不再只是被动查询。
7. `browser_navigate` 捕获“没有可驱动的网页标签页 / 无候选 tab”后，
   强制带上目标 URL 再拉起一次，修复已连接但停留在 `chrome://newtab` 的状态。

#### 核心版本

插件代码变化必须升核心版本：

```text
0.2.1-rc.2+dshm.80 -> 0.2.1-rc.2+dshm.84
```

否则设备可能继续使用已安装的 `.80` 旧插件。扩展源码变化还要同步部署目录，
不能只替换 HAP。

### 5.2 P1：如果确实要自动截图，另做系统截图桥

这条路不是本轮必须项，也不能直接复用浏览器扩展：

```text
Agent browser_screenshot
  -> Host /dshm-screen-capture
  -> ArkTS 文件队列
  -> screenshot.capture({ displayId: 0 })
  -> PNG 写入 $DSH_HOME/screenshots
  -> Host 返回绝对路径
```

前置条件：

1. 产品负责人明确需要截取海泰等其它应用窗口；
2. 申请 `ohos.permission.CUSTOM_SCREEN_CAPTURE`；
3. debug/release Profile、`module.json5`、AGC 权限说明和隐私声明同步；
4. PC 权限面从 11 条升到 12 条需要单独评审，不得在浏览器修复中夹带；
5. 截图必须只由用户的明确任务触发，文件名和保留策略要有上限；
6. 完成后新增屏幕截图桥门禁，验证权限拒绝、成功、PixelMap 释放和超时。

在此之前，正确行为是“工具不出现或立即说明不支持”，不是 20 秒超时。

## 6. 实施顺序

### 6.1 备份

在 PC 工程中先备份以下对象：

```text
hostcore/browser-extension/
hostcore/plugins/dshm-tool-browser/
dist/release-test/
dist/sideload/
```

不要删除：

```text
C:\Users\Sol\.ohos
signing/
.certs/
/data/storage/el2/base/haps/entry/files/dsh/home
/data/storage/el2/base/haps/entry/files/dsh/cores
```

### 6.2 修改与版本

1. 扩展升 `0.11.2` / `dshm-host-bridge-13`；
2. Host 插件默认不注册 `browser_screenshot`；
3. `coreVersion` 升 `+dshm.81`；
4. 重新生成核心 zip，并同步 `entry/src/main/resources/resfile/`；
5. 扩展部署到新目录 `dshm-browser-ext-v012`；
6. 旧 `dshm-browser-ext-v011` 保留作为回滚，不覆盖。

### 6.3 构建与覆盖安装

命令行基线（以 PC 工程当前 `docs/HANDOFF.md` 为准）：

```bash
export DEVECO_CLI_CLT_PATH=/data/service/hnp/hmos-clt.org/hmos-clt_1.0.0
hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
```

只允许覆盖安装。禁止：

```text
hdc uninstall com.dshm.dshclient
bm uninstall -n com.dshm.dshclient
rm -rf /data/app/el2/.../com.dshm.dshclient
```

### 6.4 扩展部署与加载

部署：

```bash
mkdir -p "$HOME/Download/com.dshm.dshclient/dshm-browser-ext-v012"
cp hostcore/browser-extension/manifest.json \
   hostcore/browser-extension/background.js \
   "$HOME/Download/com.dshm.dshclient/dshm-browser-ext-v012/"
```

然后只在海泰扩展管理中把加载目录切到 `dshm-browser-ext-v012`。这是浏览器自身
对未上架解压扩展的安装边界，不是 DSHM 每次启动都要求用户操作。切换一次后，
后续由扩展 alarms / startup / tabs 事件自动保活和回连。

## 7. 验收

### 7.1 桥状态

```powershell
Invoke-RestMethod http://127.0.0.1:3120/dshm-browser/status
```

必须看到：

```text
clients=1
extensionVersion=0.11.2
build=dshm-host-bridge-13
capabilities.tools 不含 screenshot
capabilities.screenshot=false
```

### 7.2 工具面

在一个真实 Agent 会话中依次验证：

| 用例 | 预期 |
|---|---|
| `browser_status` | `connected=1`，明确显示 screenshot 不支持 |
| `browser_navigate` 打开 example.com | `load=complete`，`via=cdp-pagenavigate` |
| `browser_text` | 返回 Example Domain 正文 |
| `browser_tabs` | 返回当前活动页 |
| `browser_tree` | 返回可交互元素树 |
| `browser_screenshot` | 工具不存在；若兼容调用，必须 <1s 返回明确不支持 |

### 7.3 冷启动与自动关闭

1. 强制停止海泰；
2. 确认 `/dshm-browser/status` 为 `clients=[]`；
3. 发起真实 `browser_navigate`；
4. 确认 `/dshm-open-link` 成功拉起 `com.haitai.htbrowser`；
5. 确认 15 秒内扩展回连；
6. 确认导航成功；
7. 任务 `turn/end` 后确认自动关闭逻辑执行：
   - 多标签页只关闭本次标签；
   - 单标签页窗口只最小化，绝不删除最后一页。

### 7.4 日志判据

日志文件：

```text
/data/storage/el2/base/haps/entry/files/dshm-host.log
/data/storage/el2/base/haps/entry/files/node-output.log
```

需要满足：

- `browser-bridge: extension connected` 出现；
- `extensionInfo` 为 0.11.2/build 13；
- 没有 `不注册浏览器工具`；
- `navigate` / `get_text` / `tabs` 有完成记录；
- 不再出现新的 `screenshot surface-callback start`；
- 不再出现 `Page.captureScreenshot` 20 秒等待；
- 不再因为截图超时导致扩展 `disconnected`。

## 8. 故障分诊表

| 现象 | 最可能原因 | 正确处理 |
|---|---|---|
| `browser_status` 显示 `clients=[]`，但浏览器没开 | 旧实现只让 `browser_navigate` 拉起浏览器 | `.84+` 会主动拉起并打开 `/dshm-browser/start`；导航遇到 newtab 会按目标 URL 自愈 |
| `/dshm-browser/invoke` 返回 401 | 使用旧 Host token | 重新从当前 `host-ready.json` 取 token，不重启应用硬猜 |
| 扩展一直不显示回连 | 加载的是旧目录/旧 Service Worker | 新版本换 `dshm-browser-ext-v012` 目录，重新加载 |
| 海泰启动后连的是别的浏览器 | 系统默认浏览器不是海泰 | 保持 `bundle=com.haitai.htbrowser`，不要在壳层写死其它浏览器 |
| `Cannot attach to this target` | 其它扩展占用 debugger | 停用 WorkBuddy/Ultron 等调试器扩展后重试 |
| `debugger.attach` 超时 | 目标页不在活动位 | `navigate` 先激活标签页；仍失败则手动切到普通网页标签 |
| `no tab` / `Cannot access haitai://...` | 没有普通 http(s) 页面 | 先打开一个普通网页标签 |
| `Tabs cannot be edited right now` | 海泰截图内核不支持 | 立即停止，不重试；截图能力保持关闭 |
| `surface-callback start` 后 20 秒超时 | CDP 全屏截图不返回 | 立即停止，不能靠加大 timeout |
| 工具列表里没有 `browser_*` | `DSHM_DEVICE_FORM` 不是 `desktop` | 检查 Host 环境变量；当前实读已是 `desktop` |
| 工具能调用但正文一直为空 | 目标页未加载完成或页面无正文 | 先 `load=complete`，再读正文；必要时重试一次 |
| `sandbox-dlopen=false` | 内核拒绝从 files 目录 dlopen 复制件 | 登记为独立原生边界，不与浏览器桥混为一谈 |

## 9. 明确不做的事

1. 不新增浏览器相关权限；
2. 不把 `CUSTOM_SCREEN_CAPTURE` 偷加进当前 11 条权限；
3. 不修改 `CUSTOM_SANDBOX` 或 3 条 ACL Profile；
4. 不把 `19390` 改成 Host 主端口，也不把 `/dshm-browser/status` 挂到
   `19390`；
5. 不改固定 token 或 WebSocket 协议来“修截图”；
6. 不通过延长 `screenshot` timeout 掩盖海泰内核不返回；
7. 不卸载 `com.dshm.dshclient`，不删除 el2 用户数据；
8. 不删除签名材料和 `host-ready.json` 所在 home；
9. 不用旧 beta 工作区的 `0.11.0` 扩展覆盖 PC 工程的 `0.11.1`；
10. 不把截图失败归类为 `CUSTOM_SANDBOX` 失败。

## 10. 最终判断

### 已经证实正常

- `CUSTOM_SANDBOX` 生效；
- Host loopback 正常；
- 浏览器 WebSocket 正常；
- 0.11.1/build 12 扩展自动回连正常；
- CDP 导航、读正文、标签页正常；
- 外开桥可拉起海泰；
- debugger 冲突不是本轮主因。

### 需要改

- 扩展把不支持的 `screenshot` 声明为支持；
- Host 无条件注册 `browser_screenshot`；
- 版本升级仍使用同一部署目录，容易触发海泰缓存；
- 面板/模型提示应明确 screenshot 不在当前 PC 能力面。

### 结论

当前不是“浏览器扩展整体坏了”，而是“海泰内核不支持扩展截图，且工具面还把它当成
可用能力”。按 `0.11.2/build 13 + core .81 + 新扩展目录` 收口后，浏览器自动化
主链可保持完整，截图能力则明确降级为系统截图或未来获批的 ArkTS 截图桥。

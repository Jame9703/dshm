# 135 · undici 垫片的具名导出面：补 `Request`（openai 7.x 的 X.509 通道）与「键在、值 undefined」判定

| 项目 | 内容 |
|---|---|
| 触发 | 用户裁决：「修一下这个隐患，重新真机测试」—— 即 `docs/134` §7.6 登记的那条**未修**发现 |
| 症状 | `node tools/check-undici-shim-exports.mjs` 判 **1 项失败**：`垫片缺具名导出 Request —— 需要它的文件：…/openai/internal/auth/x509-transport-capability.mjs` |
| 结论 | 同族**第三次**事故，且是**两条**真缺口：① `undici-shim.mjs` 缺 `Request` 具名导出；② `fetch-shim.js` 漏导出 `DshmRequest` ⇒ **内建 undici 垫片的 `Request` 是 `undefined`**（一直被"缺哪个补哪个"掩盖） |
| 影响面 | ①**当前潜伏**（静态可达性实测：从 `openai/index.mjs` 走 199 个文件**到不了**那个文件）；②真存在、被掩盖，且掩盖**依赖调用顺序** |
| 改动 | 宿主侧 **2 个文件**（`hostcore/app/undici-shim.mjs`、`hostcore/app/fetch-shim.js`）+ **2 处门禁**（`check-undici-shim-exports.mjs`、`check-internal-undici.mjs`） |
| 版本 | `coreVersion` **未动**（核心树逐字节不变；随包 zip 里**没有**宿主 app 文件，见 §3.3） |
| 产物 | **r11** = 401,739,100 B / sha256 `3e65cde3…`（与 r10 逐条目比**只差 2 个**：两个宿主垫片文件） |

## 0. 一句话结论

`undici` 这个**模块名**在端侧被 `undici-loader.mjs` 指到本仓垫片，于是垫片的**具名导出面**就是端侧 `undici` 的全部真相：

- ESM 具名导入在**解析期**校验导出存在性 ⇒ **缺一个名字**就让**整个模块图** `failed to import`，而 loader 只打一行 `failed to import`、**不给 reason**（本仓已踩三次）；
- 反向的坑是**名字在、值是 `undefined`**（键存在 ⇒ 解析期不报错 ⇒ 运行期 `new Request(...)` 才炸），比缺名字更难查 —— 本轮**两条都补上了，并且都给门禁加了牙**。

## 1. 症状与发现路径

上一轮（`docs/134` §7.6）在收尾审核时顺手跑了一条**不在 CI 名单**的门禁：

```
node tools/check-undici-shim-exports.mjs
  FAIL 垫片缺具名导出 `Request` —— 需要它的文件：dist\core\work\dsh-core-0.2.1-alpha.2+dshm.29\
       node_modules\openai\internal\auth\x509-transport-capability.mjs
       （ESM 具名导入解析期即失败 ⇒ 这些包的整个模块图 `failed to import`，而 loader 不打印 reason）
  RESULT: 1 项失败
```

**为什么这条门禁值得单独存在**：这类故障的症状是**不说话**的 —— 插件/包「装了、重启了、还是不生效」，日志里只有一行 `failed to import`。历史上已经踩过两次：

| 时间 | 缺的名字 | 后果 |
|---|---|---|
| 2026-09-24 | `EnvHttpProxyAgent` | `dshmarket` 整行 `failed to import` |
| 2026-10-03 | `Pool` / `ProxyAgent` | `dsh-codearts-auth` 0.2.1003 新增 `opencode-proxy.js` 后整行不激活 |
| **2026-10-10（本轮）** | **`Request`** | 上游 `openai` 6.40 → **7.19** 引入 `internal/auth/x509-transport-capability.mjs` |

## 2. 根因（两条）

### 2.1 `undici-shim.mjs` 缺 `Request`（第三次同族）

上游核心升到 `0.2.1-alpha.2` 时 `openai` 从 6.40 升到 **7.19**，7.x 新增的 `internal/auth/x509-transport-capability.mjs` **第 4 行**写死：

```js
import { Agent, ProxyAgent, Request, fetch } from 'undici';
```

该名字在文件里的用法是 `sendX509Request()`（第 146~165 行）：

```js
const request = new Request(normalizedTarget, requestOptions);
const response = await fetch(request, { dispatcher, redirect: 'manual' });
```

`Request` 是**真被构造**的（不是只为过解析期的陪衬）⇒ 补的名字必须**能用**，不能是空壳。

**它能被谁走到（静态可达性实测，含对照）** —— 用一段静态遍历从 `openai/index.mjs` 出发（遍历 199 个文件）：

| 文件 | 是否可达 |
|---|---|
| `client.mjs`（对照：必须可达） | ✅ 可达 |
| `internal/auth/x509-workload-identity-auth.mjs`（对照：必须可达） | ✅ 可达 |
| `internal/auth/x509-transport-capability.mjs`（本缺陷所在） | ❌ **不可达** |
| `auth/x509-transport.mjs`（public 子路径）、`internal/auth/x509-token-exchange.mjs` | ❌ 不可达 |

⇒ **这条今天不会让用户看到故障**（且全仓没有任何包 import `openai/auth/...` 子路径），它是**地雷**：一旦走 X.509 工作负载身份那条入口（`openai/auth/x509-transport`、`openai/live` 系列以后改走它、或 pi-ai 换入口）就是"整个 openai 模块图 import 失败"。

> ⚠️ 但 `openai` 本身是 `@earendil-works/pi-ai` 的**直接依赖**（`dependencies.openai = 7.19.0`），且 pi-ai 的 `dist/api/openai-completions.js` / `openai-responses.js` / `openrouter-images.js` / `azure-openai-responses.js` 都**静态** `import OpenAI from "openai"` ⇒ `openai/index.mjs` 是**真被加载**的。所以"地雷"离现实只有一条 import 边。

### 2.2 伴生的真缺口：`fetch-shim.js` 漏导出 `DshmRequest`

`internal-undici-shim.cjs`（内建 undici 的纯 JS 替身）第一段就是**解构**：

```js
const { dshmFetch, DshmHeaders, DshmRequest, DshmResponse, DshmFormData, DshmBlob, DshmFile } = fetchShim;
```

而 `fetch-shim.js` 的 `module.exports` 里**没有 `DshmRequest`** ⇒ 那里拿到 `undefined` ⇒ 内建 undici 的导出面里 **`Request: undefined`** ⇒ Node 的惰性全局（`exposeLazyInterfaces(globalThis, 'internal/deps/undici/undici', …)`）**物化出 `undefined`** ⇒ `new Request(...)` 抛 `TypeError`。

**为什么今天没炸（掩盖链，且它是脆的）**：

1. `main.js:720` 先 `installInternalUndiciShim()`、`main.js:736` 才 `installJitlessFetch()`（该顺序在 `main.js:714` 的注释里写明"**是承重的**"）；
2. `installFetchShim()` 的六个 Web 接口是「**缺哪个补哪个**」：读 `globalThis.Request` 拿到 `undefined` ⇒ 补上 `DshmRequest`。

⇒ 终值是对的，但**正确性依赖"谁先跑"**：任何在这两步之间读 `globalThis.Request` 的代码、或任何从**内建模块**（而非 `globalThis`）取 `Request` 的消费者，拿到的就是 `undefined`。

### 2.3 为什么门禁此前抓不到 2.2（"信息性"的那一格）

`check-internal-undici.mjs` 夹具的 ④ 只**打印**现状：

```js
lazy[k] = (globalThis[k] === shim[k]) ? 'shim' : typeof globalThis[k];
```

`Request` 两边都是 `undefined` ⇒ `undefined === undefined` ⇒ 显示 **`"Request":"shim"`**（看着像"已由垫片接管"）。判定一个字节都没有 ⇒ 本次把它改成**判定**（§3.3）。

## 3. 修法

### 3.1 `undici-shim.mjs`：补 `Request`（**复用** `DshmRequest`）

```js
const { dshmFetch, DshmRequest } = require('./fetch-shim.js');
…
export const Request = typeof globalThis.Request === 'function' ? globalThis.Request : DshmRequest;
```

- **为什么不另写一个类**：端侧的 `globalThis.Request` 本来**就是** `DshmRequest`（`installFetchShim()` 装的；`internal-undici-shim.cjs` 给的也是同一个类）⇒ 复用保证「经 `undici` 名字拿到的 Request」与「全局 Request」是**同一实现、同一语义**。
- **为什么不是空壳**：`dshmFetch` 会把 Request 形态展开成 init（读 `input.url / method / headers / body / signal / redirect`）⇒ `fetch(new Request(url, {method, headers, body}))` 是**真发 POST、真带体**（§4.2 的回环探针断言它）。
- **取值口径**：原生可用就用原生（开发机 Node 24 上是真正的 undici `Request`）；端侧 jitless 下就是 `DshmRequest` —— 两种形态都能被 `dshmFetch` 正确消费。
- 顺手把 `Request` 加进 `export default { … }`（有的包写 `undici.default?.X`）。

### 3.2 `fetch-shim.js`：导出面补 `DshmRequest`

`module.exports` 补 `DshmRequest`，并在导出行上方写明来路（`internal-undici-shim.cjs` 解构它；漏了就会让内建 undici 的 `Request` 变成 `undefined`）。

### 3.3 门禁两处加牙

**A. `tools/check-undici-shim-exports.mjs`（4 处改动）**

| # | 改动 | 判据 |
|---|---|---|
| 1 | 新增 **④ 请求方向探针** | `fetch(new Request(url, {method:'POST', headers, body}))` 打到**本地回环**（`127.0.0.1:0`），断言服务端看到的 **method / 自定义头 / 请求体逐字一致** + 响应 `200/pong` |
| 2 | ④ 的**对照臂** | 一个吞掉 method/body 的假 `Request`（`method='GET'`、`text()` 返回空）**必须被判红**，否则"Request 可用"那条没有牙 |
| 3 | `Request` 进「已修复缺口」清单 | 与 `Pool`/`ProxyAgent`/`EnvHttpProxyAgent` 同列：缺了判红 + 必须进 default 导出 |
| 4 | 头部注释补 ④ | 让"它测什么"与实现一致 |

**B. `tools/check-internal-undici.mjs`（④ 由"信息性"改"判定"）**

- 夹具新增两个读数：`shimSurface`（内建垫片导出面里 `Headers/Request/Response/FormData/Blob/File` **必须是函数**）、`globalSurface`（`globalThis` 上那四个名字**必须物化出函数**）；
- `classify()` 的 fixed 臂新增两条判定（`shimSurface`/`globalSurface` 非 ok ⇒ FAIL）；`lazy` 那行**保留**为信息性；
- `--self-test` **14 → 16** 例（新增"内建垫片具名导出坏 ⇒ fail""globalThis 没物化出 Request ⇒ fail"），其余 9 条 fixed 用例补上两个新字段（否则它们会**因新判据而假绿**）。

## 4. 验证

### 4.1 门禁（全绿）

| 组 | 读数 |
|---|---|
| 仓库内 CI 20 条（含 `check-internal-undici`、`check-fetch-shim.cjs`） | 全绿 |
| `check-undici-shim-exports.mjs` | `RESULT: 全部通过`（被请求的 7 个名字全在，含 `Request`；回环探针 PASS；对照臂如期判红） |
| `check-internal-undici.mjs --self-test` | `16/16 判定成立` |
| `check-decor-button-mode` / `check-market-bridge` / `check-vm-bash` / `check-handheld-back` 等周边 | 逐条 rc=0（见 §4.4 台账） |

### 4.2 变异测试（两处，**当次还原并核对 sha256**）

| 变异 | 期望 | 实测 |
|---|---|---|
| 把 `undici-shim.mjs` 的 `export const Request = …` 整行删掉 | `check-undici-shim-exports` 判红 | **3 项失败**（缺具名导出 / 历史缺陷复发 / 缺可用导出）✓ |
| 把 `fetch-shim.js` 的 `DshmRequest` 从 `module.exports` 撤掉（= 修复前状态） | `check-internal-undici` 判红 | `[fixed] FAIL 内建垫片的具名导出里有非函数值…`，control 臂仍 ok ✓ |

两次变异都用**字节备份 + sha256 前后比对**还原（`True`）。

### 4.3 包内实测（对**已签名的 HAP 里那两个文件**做的，不是对工作区）

- 从 HAP 抽出 `resources/resfile/resources/app/{undici-shim.mjs,fetch-shim.js}` → 断言新取值行与 `default` 键都在、旧 `require` 行不在；
- 用**包内那份 shim** 起本地回环实测：`status/body = 200 "pong"`、服务端看到 `POST "1" "包内实测-体"` ⇒ **PASS**；
- r11 与 r10 逐条目比（127 条）：**只差 2 个**（两个宿主垫片文件），其余逐字节相同 ⇒ 不可能连带改动别的东西。

**为什么不用重打核心树**：随包核心 zip（`entry/src/main/resources/resfile/dsh-core-…zip`）里**没有**宿主 app 文件（实测 17077 条目里 `undici-shim|fetch-shim|resources/app` 命中 0）—— 它们是 `entry/src/main/resources/resfile/resources/app/` 下的**松散件**，由 `tools/place-host-app.mjs` 从 `hostcore/app/` 拷入、随 HAP 走。故：核心容器 sha 不变、`coreVersion` 不变、`check-resfile-core-zip` 不受影响；装机 (`install -r`) 后**下次启动即生效**。

### 4.4 本轮跑的完整门禁台账

`place-host-app` → `assert-resfile-sync`（14 件全同步）→ CI 20 条 → `check-undici-shim-exports`；另抽查 `check-decor-button-mode`（38/0 + 对照臂 A–H）、`check-market-bridge`（87/0）、`check-profile-pnpm-bridge`（42/0）、`check-vm-bash`（233/233）、`check-handheld-back`（29/0）、`check-fetch-shim.cjs`（全通过）、`check-internal-undici`（两臂 PASS）—— **逐条 rc=0**。

## 5. 诚实边界（这条修的是什么、不是什么）

- **修的是导出面**：`undici` 的具名导入不再缺名字 ⇒ 走 `openai/auth/x509-transport` 那条入口不会再"整个模块图 import 失败"。
- **不是把 X.509 传输功能修好了**：`createX509Transport()` 还要 `runtime:'node'` + `certificateIdentity:'static'` 的**调用方声明**、以及调用方自己的 `Agent`/`ProxyAgent`；端侧 jitless 下真 undici 不可用（WASM），本仓的降级 `ProxyAgent` **继承 `Agent`** ⇒ 平台上 `dispatcher instanceof Agent` 为真，`proxy: 'http-connect'` 那支会抛一句**可读的** `An X.509 CONNECT proxy requires an Undici ProxyAgent.`（明确失败 > 静默错语义，符合本仓约定）。DSH 自身**不调用**这条通道。
- **仍然刻意不补**的三个名字：`request` / `stream` / `interceptors`（降级会**静默改变返回值类型 / 关掉调用方的拦截逻辑**，比缺导出更难查 —— 与 `undici-shim.mjs` 里那段注释一致）。

## 6. 未做 / 遗留

- **真机复验**：本轮构建了 r11，设备在线情况见 §7；复验要点 = ① 装机后宿主不掉档（`dshm-host.log` 无 `failed to import`）② 用 OpenAI 系 provider 跑一次对话（`openai/index.mjs` 真加载）③ `undici` 具名导入那条入口（`openai/auth/x509-transport`）能**加载成功**（不要求功能可用）。
- **`check-undici-shim-exports.mjs` 仍不在 CI**：它要扫核心树（干净克隆里没有）⇒ 只能"有产物的环境"里跑。已加进 `AGENTS.md` 的「需要核心树」清单。
- **未 commit / 未 push**（用户裁决）。

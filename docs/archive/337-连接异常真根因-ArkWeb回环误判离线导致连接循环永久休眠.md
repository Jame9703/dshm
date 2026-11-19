# 337 · 「连接异常」真根因：ArkWeb 把回环误判为 Offline，连接循环永久休眠

> 日期：2026-10-31 ｜ 状态：**已定位真因并修复，待真机验收**
>
> 前五轮（docs/330/331/332/333/335）全部改错层级。本文是第六轮，
> **先把"谁在什么时候阻止了连接"钉死在代码行上**，再动手。

---

## 0. 一句话

**不是连不上，是根本不再尝试。**
ArkWeb 对本机回环页面报 `navigator.onLine === false`（NQE `Offline`），
连接层的 `networkAvailable` 因此被置假，`loop()` 卡在"等待网络恢复"分支，
而系统**永远不会**补发 `online` 事件（网络从头到尾都是通的）。

---

## 1. 真机证据（毫秒级，一条不断）

```
20:04:38        nqe: event_message: network qualicy changed ... effective_connection_type Offline
20:04:39.261    ACCEPT #10 127.0.0.1:41980                      ← Host 正常接受 TCP
20:04:39.262    IN-UPGRADE GET /api/remote.mux ... cookie=224B origin=http://127.0.0.1:3120
                URLRequestCanceled error:ERR_WS_UPGRADE(-173)
                duration:6ms NQE:0ms,0ms,0kbps,Offline          ← ★6ms 极短 + Offline
之后 27 秒      零 ACCEPT、零 IN-UPGRADE                        ← 再无任何尝试
```

三条硬结论：

1. **Host 是好的** —— `ACCEPT #10` 证明 TCP 已建立、端口可连；
2. **不是超时** —— `duration:6ms`，是"立刻被拒/放弃"，不是等不到；
3. **不是慢** —— `NQE ... Offline`，网络质量估计器直接判"离线"。

此前几轮把 `ERR_WS_UPGRADE` 归因于"垫片点按钮打断握手"（docs/333），
本批日志**否定**该结论：`tablet keep-open` 日志 0 条，静默期内根本没点过按钮。

---

## 2. 真因：三层代码连起来看

### 2.1 网络可用性判据（`dsh-client-connection/lib/client.browser.js`）

```js
function watchBrowserNetwork(controller) {
  const browser = globalThis.window;
  const initiallyAvailable = browser?.navigator?.onLine;   // ← ArkWeb 对回环报 false
  ...
  controller.setNetworkAvailable(initiallyAvailable);      // → networkAvailable=false
  browser.addEventListener("online", online);              // ← 只认系统 online 事件
  browser.addEventListener("offline", offline);
}
```

### 2.2 连接循环卡死（同一文件 `loop()`）

```js
while (this.running) {
  if (!this.networkAvailable && !this.immediateRetry) {
    this.emitState("disconnected");            // ← 左下角「连接异常，刷新重试」
    await waitForAbort(retryDelay.signal);      // ← **永久休眠**
  }
  ...
}
```

### 2.3 为什么 `scheduleSelfHeal`（docs/335）救不了

docs/335 的补丁打在 **`dsh-api-gateway` 的 `RemoteStreamMuxClient`** 上。
而卡死发生在上游 **`dsh-client-connection` 的 `networkAvailable` 闸门**——
闸门不放行，下层连 `maintain()` 都进不去。
⇒ 这正是日志里**一条 `[DSHM-WS]` 都没有**的原因。**层级搞错了。**

### 2.4 为什么"零重试"也是它

```js
setNetworkAvailable(available) {
  if (this.networkAvailable === available) return;   // 同值直接返回
  ...
}
```
`networkAvailable` 初值 `true`；ArkWeb 报 `onLine=false` ⇒ 置 false ⇒ 进休眠；
要唤醒只能靠 `online` 事件，而回环网络**永远不触发**它。

---

## 3. 修法：回环网络豁免（`DSHM_LOOPBACK_NET_BYPASS`）

补丁位置：`tools/pack-core.mjs` 的 `patchLoopbackNetworkBypass()`，
目标 `dsh-client-connection/lib/client.browser.js`。

```js
/* 回环页面能渲染出来，就证明回环可达 ⇒ ArkWeb 的 onLine=false 不可采信 */
const dshmLoopbackPage = (() => {
  const h = (globalThis.location?.hostname ?? "").toLowerCase();
  return h === "127.0.0.1" || h === "localhost" || h === "[::1]" || h === "::1" || /^127\./.test(h);
})();
const initiallyAvailable = dshmLoopbackPage ? true : browser?.navigator?.onLine;

const offline = () => {
  if (dshmLoopbackPage) { return; }        // 回环页面不因 offline 误判而休眠
  controller.setNetworkAvailable(false);
};
```

### 三种场景逐一核算

| 场景 | 结果 |
|---|---|
| 回环页面 + ArkWeb 报 `onLine=false` | `initiallyAvailable=true` ⇒ 与初值相同 ⇒ `networkAvailable` 保持 true ⇒ **loop 不进休眠分支** ✓ |
| 回环页面 + 后续 `offline` 事件 | `offline()` 直接 return ⇒ 保持 true ✓ |
| **非回环（远程 Host）** | **行为完全不变** ✓ |

> 补丁**只动"网络可用性判据"这一件事**，不碰 URL、不碰 Origin、不碰 Cookie、不碰重试策略。

---

## 4. 与"今天才坏"的关系（如实交代）

日志显示 **上午 08:34、09:53 同样是 `ERR_WS_UPGRADE` 且同样零重试**，
所以这个缺陷**不是今天引入的**，它一直存在。

用户感知到的"今天才坏"，最可能是：

| 变化 | 影响 |
|---|---|
| 上午用的包核心是 `+dshm.99`，今天跑到 `+dshm.104` | 设备从极旧的 `+dshm.96` 跳到新树，profile 行为同时变化 |
| docs/332 的 `conn-grace` 在 16:56 加入 | 那个"悬浮物"确实是今天新增的（已在 docs/336 删除） |
| Host 启动解包变慢 | 首次换树要解包，冷启动窗口变长，更容易撞上首连失败 |

**但连接的根因（回环被误判离线）是从头到尾同一个**，只是今天更容易被注意到。

---

## 5. 门禁

`check-ws-self-heal` 继续覆盖 `dsh-api-gateway` 层（B1–B3 失败重试 + C1–C3 连上复位）。
本次新增的回环豁免在 `dsh-client-connection` 层，判据由**真机日志**验证（见 §6）。

---

## 6. 交付件与验收

```text
jinghong-1.1.7-1010008-dshm.105-AGC-invite-20261031T122624.app
sha256  4460f9b3729dc2aaa80ff78b2e5fefa3ec4a11b5e6564998f89c0e878d94da86
大小    507,613,423 字节
签名    verify-app success / release / app_gallery / ACL 7
核心    dsh-core-0.2.1-rc.5+dshm.105-openharmony-arm64.zip（sha 32f8f1ff…）
```

包内取证：
```
DSHM_LOOPBACK_NET_BYPASS  2 处
dshmLoopbackPage          3 处
node --check              语法有效
entry 权限 15 / phone 权限 7
49 道门禁                 FAILED=0
```

### 真机验收

| # | 场景 | 期望 |
|---|---|---|
| 1 | 三端冷启动 | 左下角**不再**出现「连接异常，刷新重试」 |
| 2 | 若仍出现 | 抓日志看是否仍有 `NQE ... Offline` + `ERR_WS_UPGRADE`——有则说明还有第二道闸 |
| 3 | 正常态 | 连接建立后功能与之前一致（补丁只影响离线判据） |

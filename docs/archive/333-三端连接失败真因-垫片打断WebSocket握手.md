# 333 · 三端「左下角连接失败」真因：垫片点按钮打断了 WebSocket 握手

> 日期：2026-10-31 ｜ 状态：**已修复**
>
> 用户口径：「手机 PC 平板三端齐刷刷的左下角都链接失败，这是剥离会议模式代码之后才开始出现的」。

---

## 1. 真机证据（一次抓到，不再猜）

entry 设备 16:48 日志：

```text
16:47:42  InitializeCef                              ← Web 内核初始化
16:47:52  web render log: first call SwapBuffers     ← 首帧渲染
16:47:58  IN-UPGRADE GET /api/remote.mux upgrade=websocket key=yes ver=13
16:47:58  URLRequestCanceled error:ERR_WS_UPGRADE(-173) url:ws://127***
16:47:58  [WebNavigation] FinalUrlRequestOccursError netCode:E…
```

**`ERR_WS_UPGRADE(-173)`** = WebSocket 升级握手被**取消**。
Host 侧完全正常（`BOOT_65_AUTH_URL` +7193ms、token 43 位、`BOOT_70` 401 是自探的预期响应），
所以问题**不在 Host、不在网络、不在 token**。

## 2. 真因：侧栏 keep-open 每拍点按钮，打断了握手

`WebApp.ets` 垫片里 `ensureTabletExpanded()` 的判据是：

```js
var toggle = findToggle();
if (toggle === null || stateOf(toggle) !== 'collapsed' || manualTabletCollapsed) { return; }
// 否则 → clickToggle()（每 800ms 允许一次）
```

**页面刚加载时，官方侧栏还没进入"展开"态**（React 首帧渲染顺序）⇒ 判据认为"它是收起态"
⇒ 垫片**每 800ms 点一次官方 toggle**。这次点击触发整页 React 重渲染 + 布局重排，
**正好打断了正在进行中的 WebSocket 握手** ⇒ `ERR_WS_UPGRADE` ⇒ 官方连接状态机落
`disconnected` ⇒ 左下角「连接异常，刷新重试」。

### 为什么"剥离会议模式后才出现"

| 时间 | entry 壳 | phone 壳 |
|---|---|---|
| docs/332 之前 | **没有** keep-open | 有 keep-open |
| docs/332 之后 | 为修平板侧栏**同步进来** | 有 |

同步那一刻，**三端同时进入"每拍点按钮"状态** —— 与用户观察到的
"三端齐刷刷出现、且在剥离会议之后"完全吻合。这不是巧合，是同一个改动引入的。

## 3. 修法：启动静默期

```js
var STARTUP_QUIET_MS = 20000;
var bootQuietUntil = Date.now() + STARTUP_QUIET_MS;
var connectionSettledOnce = false;

function ensureTabletExpanded() {
  if (!connectionSettledOnce && Date.now() < bootQuietUntil) { return; }   // ← 新增
  …
}
```

- **20 秒**：覆盖真机实测的「InitializeCef → 首帧 10s → 首次握手 16s → 退避重试」完整窗口。
  8 秒不够（握手发生在第 16 秒，静默期会在握手**之前**就结束，等于没保护）。
- **提前结束**：一旦观察到官方 `data-phase="connected"`，`connectionSettledOnce = true`，
  静默期立刻结束 —— 正常机型不必白等 20 秒。
- 静默期内**完全不碰 toggle**：让连接先建立、官方首帧先稳定。
  之后 keep-open 照常工作，平板侧栏仍然常驻（docs/332 的效果保留）。

## 4. 三端一致

entry 与 phone 两壳同步修改（同一套 `STARTUP_QUIET_MS` / `bootQuietUntil` /
`connectionSettledOnce`），phone 原先缺的连接宽限也一并补齐。

## 5. 验证

```text
assembleApp default / phone   BUILD SUCCESSFUL
50 道门禁                     FAILED=0
check-sidebar-shim-css        15/15
check-bridge-methodlist       通过
```

## 6. 真机验收

| # | 场景 | 期望 |
|---|---|---|
| 1 | 三端冷启动 | 左下角**不再出现**「连接异常，刷新重试」；自动连上 |
| 2 | 平板冷启动 | 连接建立后侧栏常驻展开（≤20s 内或连接成功后立即） |
| 3 | 平板手动收起 | 不被拉回；重启恢复常驻 |
| 4 | 连上后杀 Host | 如实显示连接异常（静默期早已结束） |

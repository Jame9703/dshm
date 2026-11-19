# 176 · 浏览器工具「随需拉起」：Host → ArkTS 外开桥（openLink + 显式 bundle）

> 用户 2026-10-17 口径：「现在要调用浏览器必须是提前打开浏览器的APP，能不能没启动的状态，
> 直接拉起，像 登录账号时候一样，直接拉起海泰浏览器」。
> 结果：`browser_navigate` 在"桥上一个扩展客户端都没有"时，会请求 ArkTS 壳层**显式拉起海泰**
> （`startAbility` + `viewData/browsable`；失败回退系统 `openLink`），再等扩展回连后照常走
> CDP 导航。**未 commit / 未 push。**

## 1. 为什么需要一座新桥

- `browser_*` 工具链依赖**浏览器里的 DSHM Browser Bridge 扩展**回连宿主 WS（`127.0.0.1:19390`）；
  浏览器没起来 ⇒ 没有客户端 ⇒ 工具只能报「没有已连接的浏览器扩展」（docs/175 §6 的现状）。
- 「把 https 链接交给系统打开（没有浏览器就拉起它）」是 **ArkTS 的 `openLink`**（登录外开授权页
  走的就是它，见 `platform/src/main/ets/system/OpenLink.ets`）——Host 里的 Node 进程**调不到**。
- 项目里 Host ↔ ArkTS 没有直接通道，但已有成熟的**文件队列范式**：
  `host-stop-request` / `host-exit-mode`（EntryAbility 1.5s 巡检）/ 语音桥 `HmsSpeechBridge`
  （Host 写 `.req`，ArkTS 轮询执行"只有 ArkTS 能做的事"，回写 `.done/.fail`）。
  外开桥（本文）是同一范式的第三个实例。

## 2. 协议（三侧逐字一致；`tools/check-open-link-bridge.mjs` 钉死）

```
$DSH_HOME/open-link/            （真机 = <filesDir>/dsh/home/open-link）
  Host   写 <id>.req   —— 先写 <id>.wreq 再改名（原子）
         载荷 { url, bundle?, requestedAt }；url 必须 http(s)；bundle 为可选的点分标识符
  壳层   写 <id>.done  —— { ok:true, detail }（先写 .tmp 再改名）
  壳层   写 <id>.fail  —— { ok:false, error }
```

| 侧 | 文件 | 关键点 |
|---|---|---|
| Host | `hostcore/app/main.js` `registerOpenLinkEndpoint()` | `GET /dshm-open-link?token&url&bundle&timeout`：token 鉴权（与其它 `/dshm-*` 同源）、http(s) 白名单、bundle 形态校验、**等到 `.done/.fail` 再作答**（不把失败藏到下一步）、用完清理本条全部中间文件；`BOOT_62C_OPEN_LINK` 阶段读数 |
| 壳层 | `entry/src/main/ets/system/OpenLinkBridge.ets` | 500ms 巡检（与语音桥同值）；**显式传 UIAbilityContext**（onCreate 语境下 `getContext()` 不可靠）；陈旧回收**包含 `.req`**（半截请求堵死队列的语音桥实证）；心跳文件 `<filesDir>/open-link-bridge-heartbeat`（追加 + 64KB 轮转） |
| 壳层 | 同上，执行序 | **有 `bundle` ⇒ 先 `startAbility({bundleName, action:'ohos.want.action.viewData', entities:['entity.system.browsable'], uri})`**（不钉 abilityName，由系统在该 bundle 内按 skills 解析）；失败/无 bundle ⇒ 回退 `openExternalUrl`（系统默认浏览器） |
| 入口 | `entry/src/main/ets/entryability/EntryAbility.ets` | `startOpenLinkBridge(this.context.filesDir, this.context)` 常驻启动（与语音桥同处） |
| 插件 | `hostcore/plugins/dshm-tool-browser/lib/index.js` | `ensureClient(url)`：无客户端 ⇒ 请求 `/dshm-open-link`（带 `bundle`）→ 轮询 `/dshm-browser/status` 等回连（1s × 15s）；`browser_navigate` 执行前调用；另有"僵尸客户端"竞态下的一轮重试 |

## 3. 两条真机实测决定的设计取舍

1. **默认浏览器不是海泰**：只调 `openLink` 时，系统拉起的是 `com.huawei.hmos.browser`
   （ps 实录：openLink 后 `com.huawei.hmos.browser:render` 新进程起、海泰无进程、扩展 15s 不回连）。
   查 `bm dump -n com.haitai.htbrowser` 确认其 `EntryAbility` 声明了
   `ohos.want.action.viewData` + `entity.system.browsable` + `http/https` scheme ⇒ 改为
   **显式 `startAbility` 优先**，`openLink` 只作兜底。目标 bundle 由插件侧给
   （`PREFERRED_BROWSER_BUNDLE = env.DSHM_BROWSER_BUNDLE || 'com.haitai.htbrowser'`），换浏览器不用改壳层。
2. **`/dshm-browser/status` 的"僵尸客户端"窗口**：浏览器进程被杀后，loopback 连接可能先半开
   （对端已死、本地还没收到 FIN/RST）—— 实测窗口约 10s：此间 `status` 仍列着该客户端，
   而 `invoke` 已经选不中它（报"没有已连接的浏览器扩展"）。两处硬化：宿主保活 `15s → 5s`
   （更早触发 drop）+ 插件在 invoke 报"没有已连接"时**重来一轮"拉起 + 等回连"**再重试一次。

## 4. 读数

| 项 | 读数 |
|---|---|
| 打包 | `+dshm.59`（首版）/ **`+dshm.60`**（含 bundle 显式拉起 + 两处硬化）：40746 条目 / 94.9MB，resfile ↔ dist sha256 一致（`check-resfile-core-zip` ✅） |
| 构建装机 | `assembleHap` BUILD SUCCESSFUL（ArkTS 侧新文件编译通过）→ `hdc install -r` ✅ 覆盖安装（数据未动） |
| 壳层桥心跳（真机） | `open-link-bridge-heartbeat`：`started dir=/…/dsh/home/open-link` → `alive ticks=20/40/60/80`（500ms 一轮，活着） |
| 外开（dshm.59 真机） | `GET /dshm-open-link?url=https://www.baidu.com` → `{"ok":true,"detail":"launched"}`（0.8s）；壳层回执与 Host 清理都发生 —— **文件队列本身端到端通** |
| 拉起对象（dshm.59 真机） | 同一次调用后 `ps`：新起 `com.huawei.hmos.browser:render`（默认浏览器）而**不是**海泰 —— 直接促成 §3.1 的显式 bundle 方案 |
| 门禁 | `check-open-link-bridge` **22 项断言 / 0 失败 + 6 个变异对照臂**（改目录名 / 改回执后缀 / 摘启动行 / 摘插件调用 / 改 want action / 摘 bundle 全部如期判红）；仓库内 28 条口径全绿 |

## 5. 待验（解锁屏幕后）

- **海泰不在运行**状态下：`/dshm-open-link?bundle=com.haitai.htbrowser` 是否把海泰拉起来；
  扩展是否在预算内回连（`clients:1`）；随后 `navigate`（激活 + attach + CDP）是否成功。
- 模型侧一轮真实会话（浏览器未启动 → 「调用浏览器打开baidu.com」）作为最终验收。

## 6. 边界（如实）

- 只对 `browser_navigate` 做随需拉起（它本身就要打开一个 URL）；`browser_tree/click/text`
  在浏览器没起时仍如实报错（没有可读的页面，拉起一个空白页没有意义）。
- 拉起目标是**装了扩展的那个浏览器**；本 beta 默认海泰（可用 `DSHM_BROWSER_BUNDLE` 覆盖）。
  若扩展根本没装进目标浏览器，会如实报"扩展 Ns 内没有回连"，不假装成功。
- `startAbility` 拉起别的应用**不需要新权限**（8 条权限面未动；`check-permission-surface` 恒 8 条 ✅）。

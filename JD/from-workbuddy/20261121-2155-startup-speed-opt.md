# JD-033 交接单：三端冷启动提速（只优化，不改功能）

- 提交方：WorkBuddy
- 接收方：DevEco（构建 + 真机计时）
- 时间：2026-11-21 21:55
- 范围：entry（PC/2in1/平板）+ phone（手机），共用宿主层 `hostcore/app/main.js`
- 约束：**只优化启动时序，不改任何业务功能、不删能力**

---

## 0. 一句话

把 4 个「非首屏必需」的 HTTP 端点注册从 `DSHM_READY` 之前移到之后（下一 tick），
让端口就绪信号更早发出，ArkTS 更早加载 Web。其中 `card-state` 注册时会**同步读最多 2 万条**账本，
是明确的大头。

---

## 1. 现状启动链路（已有埋点）

```
BOOT_00_NODE_START
BOOT_10_ENV_READY
BOOT_20_CORE_FOUND
BOOT_30_PROFILE_READY
BOOT_40_PROFILE_BOOT      ← runProfile 开始（插件图挂载，耗时大头）
BOOT_50_DSH_INIT          ← runProfile 返回
BOOT_60_HTTP_BIND         ← 端口已绑
  └─ 原来这里串行执行：python / browser / open-link / pet-host / card-state / registry / packages / shot
DSHM_READY                ← ArkTS 收到后开始加载 Web
BOOT_70_HTTP_READY        ← 自探端口（已在 ready 之后）
```

ArkTS 侧已做过首帧优化（`HOST_START_DELAY_AFTER_FIRST_FRAME_MS = 32`，宿主启动排在首帧后），
所以本次只动**宿主 READY 前**的关键路径。

---

## 2. 本次改动

文件：`hostcore/app/main.js`（已同步到 `hostruntime/.../resfile/resources/app/main.js`）

### 2.1 4 个非首屏注册延后到 READY 之后

```js
const deferRegister = (label, fn) => {
  const run = () => { try { fn(); } catch (e) { diag('[defer] ' + label + ' 注册失败：' + ...); } };
  try { setTimeout(run, 0); } catch (e) { run(); }
};
deferRegister('card-state', () => registerCardState(ctx));
deferRegister('registry-view', () => registerRegistryViewEndpoint(ctx));
deferRegister('packages-list', () => registerPackageListViewEndpoint(ctx));
deferRegister('shot-proxy', () => registerShotProxyEndpoint(ctx));
```

| 端点 | 用途 | 为什么可延后 |
|---|---|---|
| `card-state` | 桌面服务卡片（会话进度/余额/用量） | 注册时**同步读** `card-usage.jsonl`（最多 2 万条）并可能 compact 写回；首屏不请求 |
| `registry-view` | 插件市场 `pnpm view` 转发 | 用户打开市场才用；注册时 `require('./fetch-shim.js')` |
| `packages-list` | 插件市场包清单 | 同上 |
| `shot-proxy` | 市场缩略图/灯箱代理 | 同上 |

### 2.2 明确**不动**的部分（避免功能风险）

- `registerPythonHttpBridge`：轻量注册，保留在关键路径。
- `registerBrowserBridge` / `registerOpenLinkEndpoint`（仅 PC/2in1）：会开 ws server + 端口，
  但 defer 失败会降级浏览器自动化 ⇒ 为满足「功能不受影响」，本轮**保持同步**。
- `petHost.registerPetHost`：`PetAbility` 启动前会预检 `/dsh-pet-native`，必须保留在关键路径。
- `recoverOrphanLocks` / `runtimeFacts`：在 `runProfile` 之前且涉及死锁恢复/原生预热，不动。
- `probeNativeBindings`：`onCreate` 最早处的原生库探测（诊断 + Host 前置），不动。

---

## 3. 为什么安全

- 4 个端点都是**增量能力**，失败原本就只 `diag`，不影响已验证的 Web 服务链路；
- 延迟是 `setTimeout(..., 0)`：READY 同步发出后、下一 tick 注册，页面真正用到它们时（毫秒级后）已就绪；
- 不改变任何函数内部逻辑，只改调用时序；
- ArkTS 侧零改动。

---

## 4. 预期收益与量化方法

- 直接省掉：`card-state` 读账本 + 可能的 compact（经验值 50–200 ms，随 `card-usage.jsonl` 大小增长）；
- 另省 3 个 `require` 子模块（约 10–60 ms）；
- **合计预计 READY 提前 ~100–300 ms**（需真机确认）。

真机计时口径（已有日志，无需新增埋点）：

```sh
hilog | grep -E "BOOT_50_DSH_INIT|BOOT_60_HTTP_BIND|DSHM_READY|Host 已就绪"
```

对比同一台设备、同一次冷启动（杀进程后启动）的 `BOOT_60 → DSHM_READY` 间隔；
另看 `diag-host-boot` 的 `成功：N s（BOOTING→READY）` 端到端值。

---

## 5. 验证清单（DevEco）

1. 编译：`devecocli build --product default --build-mode debug` → BUILD SUCCESSFUL。
2. 门禁：`node tools/check-decor-button-mode.mjs` → 134/0 PASS（本轮已跑）。
3. 真机三端各一次冷启动：
   - PC/2in1、平板、手机；
   - 记录 `BOOT_10/20/30/40/50/60` 与 `DSHM_READY` 时间戳、`diag-host-boot` 成功秒数；
4. 功能回归（重点确认延后的 4 项）：
   - 桌面服务卡片仍能刷新余额/用量；
   - 插件市场「详情/安装」仍正常（`registry-view` / `packages-list`）；
   - 市场缩略图仍能加载（`shot-proxy`）；
   - 若任一项失败，看 `[defer] xxx 注册失败` 日志。

---

## 6. 进一步候选（本轮**未做**，需真机数据再决定）

| 候选 | 预期 | 风险 |
|---|---|---|
| `recoverOrphanLocks` 收窄扫描（跳过 `sessions` 等大目录 / 降 visited 上限） | 可能 100–500 ms | **漏锁会导致下次写入失败**，需先确认锁的实际分布 |
| ArkTS 首帧前 `setupNotifications` / `keepAlive.attach` 后移 | 几十 ms | 小；但 `setupScreenWatcher` 与 `topInsetVp` 初始化耦合，不能动 |
| `runProfile` 插件懒加载 / 并行 | 可能秒级 | **会改功能**，超出本轮「不影响功能」边界 |
| 核查 `NODE_COMPILE_CACHE` / 解析缓存命中率（温启动 vs 冷启动） | 依数据 | 仅测量，不改代码 |

> 建议 DevEco 先用第 5 节的 `BOOT_*` 读数判断瓶颈在 `BOOT_40→50`（插件装载）还是 `BOOT_60→READY`（注册收尾）。
> 若瓶颈在 40→50，本轮改动收益有限，需要另行评估插件懒加载（需产品/功能确认）。

---

## 7. 边界

- 不改版本号；不改任何端点实现；不改 ArkTS 首帧逻辑。
- 已同步 HSP resfile（`cmp` 与 `hostcore/app/main.js` 一致）。
- 出包仍按「用户明确要求才出 Beta」口径。

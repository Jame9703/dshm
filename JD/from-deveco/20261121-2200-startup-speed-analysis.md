# JD-034 启动速度：手机 / PC 冷启动实测与优化方案（待评审）

- **提交方**：DevEco（真机实测 / 取证 / 方案）
- **接收方**：WorkBuddy（方案评审与落地）
- **日期**：2026-11-21 22:00
- **范围**：手机（Mate 80 / VYG-AL00 / phone / API 26）与 PC（MateBook 14 2in1 / 本机 / `entry` 壳）两端
- **被测包**：两端均为 `com.dshm.dshmbeta` 1010019（含 JD-032 §5.1/§5.2、JD-033 状态栏修复）
- **判定**：**瓶颈已定位在宿主 profile/插件启动（占 60–75%）**；本轮只出方案，**未改启动代码、未出新 Beta**。

## 1. 测量方法与原始数据

```sh
hdc -t <device> shell "aa force-stop com.dshm.dshmbeta"
hdc -t <device> shell "aa start -b com.dshm.dshmbeta -a EntryAbility"
# 等 ~20s 后取文件：
#   files/diag-host-boot       BOOTING→READY 总耗时（历史逐次）
#   files/diag-web-load        页面 200 就绪时刻
#   files/dshm-host.log        宿主启动分段 + LOOP-GAP + SERVER-LISTENING
```

两端的关键证据：

| 端 | 最新一次 BOOTING→READY | 历史区间 | 证据 |
|---|---|---|---|
| 手机 Mate 80 | **9.0s** | 8.5–18.3s | `diag-host-boot` @13:49:25Z；同次 `diag-web-load` |
| PC 2in1（beta） | **14.0s** | 10.0–17.4s | `diag-host-boot` @13:48:07Z；同次 `diag-web-load` |

> 14–18s 的个别样本集中在应用更新 / 插件安装后的首次启动（代码缓存与插件图重建），日常冷启动主要落在 9s（手机）/ 12–14s（PC）。

## 2. 分段耗时（宿主日志实测）

### 2.1 手机（2026-11-21T13:49Z，总 9.0s）

| 阶段 | 时间点 | 耗时 |
|---|---|---|
| 宿主进程启动（main.js） | 16.892 | — |
| 基础装配（fs 缓存 / worker / seed / CLI / 工具链 wrapper） | 16.892 → 17.073 | **0.18s** |
| **profile / 插件启动（事件循环整段阻塞）** | 17.073 → 22.88 | **≈5.8s（LOOP-GAP 5973ms）** |
| HTTP 监听 + host-ready | 22.758 / 23.151 | 0.4s |
| Web 页面加载 → READY | 23.151 → 25.231 | **2.1s** |
| （就绪后）exec 探测 | 27.176 | 3.6s（不挡 READY，但阻塞宿主事件循环） |

### 2.2 PC 2in1（2026-11-21T13:48Z，总 14.0s）

| 阶段 | 时间点 | 耗时 |
|---|---|---|
| 宿主进程启动 | 54.549 | — |
| 基础装配 | 54.549 → 54.840 | **0.29s** |
| profile 启动第一段 | 54.840 → 56.341 | 1.8s（LOOP-GAP 1776ms） |
| **profile 启动第二段** | 56.341 → 65.123 | **8.8s（LOOP-GAP 8782ms）** |
| SERVER-LISTENING / host-ready | 64.667 / 65.397 | 0.7s |
| Web 页面加载 → READY | 65.397 → 67.896 | **2.5s** |
| 工具链 / 自检 / exec 探针 | 71.4+ | 就绪后后台 |

两端共同点：**真正的墙是宿主 profile/插件启动**（手机 ≈5.8s、PC ≈10.6s），其后 Web 页面还要 2.1–2.5s；基础装配只有 0.2–0.3s。

## 3. 瓶颈排序

| # | 瓶颈 | 手机 | PC | 说明 |
|---|---|---|---|---|
| 1 | **宿主 profile / 插件启动**（阻塞事件循环） | ≈5.8s | ≈10.6s | PC 额外装了 `dsh-pet`（日志 `/dsh-pet-native 已注册`）+ 市场插件；手机未装 dsh-pet |
| 2 | **Web 页面加载** | 2.1s | 2.5s | 宿主 host-ready 之后才开始；可与 #1 重叠 |
| 3 | 就绪后 exec 探测（不挡 READY） | 3.6s | 常见 | 阻塞宿主事件循环，影响首屏后的 API 响应 |
| 4 | 首次启动（更新/装机后）代码缓存 + 插件图重建 | 偶发 14–18s | 偶发 17.4s | 持久 ESM 解析缓存已装（14615 条），但 V8 代码缓存首跑仍冷 |
| 5 | 工具链 wrapper 重铺（PC 偶发 EPERM 重试） | — | 有 | 非主因，可顺手消除 |

## 4. 优化方案（按收益排序）

### P0：把 profile/插件启动从关键路径上拿掉（预计 -2.5～-8s）

1. **先监听、后加载插件**：宿主在基础装配后立即 `SERVER-LISTENING` 并发布 host-ready/token；插件/profile 初始化改为后台异步，API 在未就绪时返回明确 `503 booting`。
   - 页面可立刻加载 Web 壳并显示启动页，**Web 页面加载（2.1–2.5s）与插件启动重叠**。
   - 风险：依赖“profile 未就绪即有 API 调用”的路径要逐项确认（登录、插件路由）。
2. **插件懒加载 / 分档**：按需激活，至少把 `dsh-pet`（PC 特有，约 3s 量级）与市场改为“用到才启”；手机侧 9 个用户插件逐项量耗时后决定懒加载集合。
   - 需要 profile 启动器支持 lazy 行（上游能力或 host 侧白名单）；先做 feature flag + 回退。
3. **插件启动逐项计时**：在 profile-boot 外层包 per-plugin `performance.now()`，落到 `diag-host-boot` 扩展字段；先拿到“每个插件多少毫秒”再定懒加载名单（避免拍脑袋）。

### P1：Web 页面加载与首屏（预计 -1～-2s）

4. **提前预热 WebView**：宿主启动前（ArkTS 首帧后）就创建/预载 WebView，并先加载本地 boot 壳；host-ready 后只做导航/握手，页面资源与插件启动并行。
5. **首屏骨架与真实就绪解耦**：host-ready 后即允许切出启动页（页面可先渲染官方 Web 壳），插件 API 用 loading 态渐进补齐；避免“插件全就绪才敢出启动页”。

### P2：就绪后的后台任务（不缩短 READY，但提升“可用体感”）

6. **exec 探测 / 工具链自检移出主线程**：放进 worker 或按 idle 分片；手机 3.6s 的探测不应在首屏后阻塞宿主事件循环。
7. **首次启动优化**：V8 代码缓存（compile cache）+ 解析缓存持续命中；应用更新后首跑预热一次；减少首跑插件图重建。
8. **清理 PC 的 wrapper EPERM 重试**：已存在且内容正确时跳过重写（幂等），避免每次启动的删除重铺。

## 5. 目标与验收口径

| 指标 | 现状 | 目标（P0+P1 后） |
|---|---|---|
| 手机 BOOTING→READY（日常冷启动） | 9.0s | **≤5.0s** |
| PC BOOTING→READY（日常冷启动） | 14.0s | **≤7.0s** |
| 更新后首次启动 | 14–18s（手机）/ 17.4s（PC） | ≤10s |
| 宿主 LOOP-GAP（启动窗口） | 5.8s / 10.6s | ≤2s |
| 页面加载（host-ready 后） | 2.1–2.5s | 与插件启动重叠，感知 ≤0.5s |

验收方法：两端各跑 **3 次日常冷启动 + 1 次更新后首启**，记录 `diag-host-boot`/`diag-web-load` 与 `dshm-host.log` 的 LOOP-GAP/SERVER-LISTENING；功能门禁全量 133/0、`check-decor-button-mode` 134/0 不回归；需出包时按用户明确要求。

## 6. 边界

- 本轮只做实测与方案；**未改启动代码、未出新 Beta、未升版本号**。
- 未卸载/清数据；未删交付件；未提交代码。
- 证据：两端 `diag-host-boot` / `diag-web-load` 与对应时段的 `dshm-host.log` 摘录见 [`20261121-startup-speed-evidence/`](20261121-startup-speed-evidence/)；关键行已摘录于本文。

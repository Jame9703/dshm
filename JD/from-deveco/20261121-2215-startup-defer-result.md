# JD-035 结论：三端冷启动提速（非首屏端点延后注册）

- **接收**：[`from-workbuddy/20261121-2155-startup-speed-opt.md`](../from-workbuddy/20261121-2155-startup-speed-opt.md)（自标 JD-033；与看板既有 JD-033「手机状态栏诊断」重号，按提交时间顺延为 **JD-035**）
- **执行**：DevEco，2026-11-21 22:05–22:15
- **总判定**：**构建与门禁 PASS，改动可合入**；**端到端真机计时待可部署包**（canonical Beta 不可侧载），且按实测账本规模，本轮收益预计 **<50ms**，显著小于交接单估的 100–300ms；启动大头仍是 profile/插件装载（见 JD-034）。

## 1. 构建与门禁

```sh
devecocli build --product default --build-mode debug
# Build completed successfully（ArkTS 未变，宿主 JS 已同步 resfile）

node tools/check-decor-button-mode.mjs
# RESULT: PASS —— 第一组 9/0、第二组 134/0

python3 dist/acceptance/rerun-gates.py … dist/acceptance/20261121-full-gates-jd035.txt
# total=133 failed=0
```

门禁修整：`tools/check-market-bridge.mjs` 的 **M6b** 原判据只认
`registerShotProxyEndpoint(ctx);` 直接调用；延后注册后是
`deferRegister('shot-proxy', () => registerShotProxyEndpoint(ctx));`。
已把判据改为「直接调用 **或** deferRegister 回调里调用」两种形态都接受，
仍保留「启动台阶里真的调用 + `BOOT_64_SHOT_PROXY` 阶段在」的反死代码语义。
修后该门禁 **142/0 PASS**，全量 133/0。

## 2. 改动复核

- 仅延后 4 项非首屏注册：`card-state` / `registry-view` / `packages-list` / `shot-proxy`，
  统一 `setTimeout(run, 0)`，失败只 `diag('[defer] …')`。
- `registerPetHost` 仍留在关键路径（PetAbility 启动前预检 `/dsh-pet-native`）；
  `python` / `browser` / `open-link` 保持同步（与交接单一致）。
- 未改端点实现、未改 ArkTS、未升版本号；resfile 同步（`cmp` 一致）。

## 3. 收益复核（关键）

交接单预期主要来自 `card-state` 注册时同步读最多 2 万条账本。实测设备上的账本规模：

| 端 | `card-usage.jsonl` | 行数 |
|---|---|---|
| 手机 Mate 80 | 18,812 B | **481 行** |

- 481 行 / 18 KB 的同步读取通常在 **<10ms** 量级，不是 50–200ms；另 3 个 `require` 注册也小。
- 因此本轮端到端收益预计 **<50ms**（远小于 100–300ms 的估算）。
- JD-034 实测的启动大头未变：**手机 profile/插件装载 ≈5.8s、PC ≈10.6s**；Web 页面 2.1–2.5s。
  若目标是「明显变快」，需要 P0（先监听后加载插件 / 插件懒加载/分档），本轮改动只能算安全的小优化。

## 4. 真机计时（待部署）

- 既有基线（JD-034）：手机 BOOTING→READY **9.0s**，PC **14.0s**。
- 本次改动在宿主 JS；canonical Beta 手机/PC 均不可直接侧载（9568322）。
  要拿到「改后」读数，需要 local-install 重签或用户明确要求出 Beta；**本轮未出包**。
- 部署后按交接单 §5 记录：`BOOT_10/20/30/40/50/60`、`DSHM_READY`、`diag-host-boot` 秒数；
  并回归 4 项延后能力：桌面卡片余额/用量、插件市场详情/安装、缩略图代理。

## 5. 边界

- 未改版本号；未 `git commit`；未出 Beta；未卸载/清数据；未删交付件。
- 门禁工具只改了 M6b 的调用形态判据（语义不变），全量已复跑到 133/0。

## 6. Beta 已出（2026-11-21 22:13，按用户测试要求）

| 项 | 值 |
|---|---|
| 目录 | `dist/beta/DSHM-beta-1.1.8-1010019-20261121T141148/` |
| app | `DSHM-beta-1.1.8-1010019-combined-debug.app`（670,204,955 B） |
| sha256 | `246db744f81283f4c53b40e0e24798a4d189802f7df9edcef9d93d7466bd2235` |
| SHA256SUMS | 5/5 OK |
| 验签 | `hap-sign-tool verify-app` success |
| 权限面 | entry 19 / phone 9 |
| 核心容器 | 1 份，sha256 `61749b164ee1ebdb…` |
| 身份 | 已还原 `com.dshm.dshclient` |
| 内容 | 包内 HSP `main.js` 含 `deferRegister`（5 处），即本轮端点延后注册 |

真机计时建议（部署后）：
1. 杀进程冷启动，取 `files/diag-host-boot` 的 `成功：N s`，与基线（手机 9.0s / PC 14.0s）对比；
2. 宿主日志看 `SERVER-LISTENING`/`Host 已就绪` 与 `LOOP-GAP`（本轮只影响 READY 前的收尾，LOOP-GAP 主体仍是 profile 装载）；
3. 回归 4 项延后能力：桌面卡片余额/用量、插件市场详情/安装、缩略图代理；失败看 `[defer] … 注册失败`。

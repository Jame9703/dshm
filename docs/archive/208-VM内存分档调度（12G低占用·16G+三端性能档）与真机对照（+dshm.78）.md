# 208 · VM 内存分档调度（12G 低占用 · 16G+ 三端性能档）与真机对照（`+dshm.78`）

> 用户裁决（2026-10-19）：VM 调度按物理内存分两档；12G 保持现状低资源占用，
> 16G 及以上设备三端统一开放性能档，保证终端和 guest 命令速度。

## 1. 分档规则

Linux 的 `MemTotal` 会低于标称容量，因此用 **14 GiB** 作为 12G / 16G 产品的实际分界：

```text
MemTotal < 14 GiB       => economy
MemTotal >= 14 GiB      => performance
读取失败 / 未知         => economy（保守回退）
```

| 档位 | guest 内存 | TCG buffer | 启动 MemAvailable 地板 | 预热 |
|---|---:|---:|---:|---|
| `economy`（12G） | 256 MiB | 64 MiB | 1280 MiB | 默认关 |
| `performance`（16G+） | 512 MiB | 256 MiB | 1792 MiB | 默认开，延迟 60s |

显式覆盖仍然优先：

- `DSHM_VM_MEMORY_MIB` 可覆盖 guest 内存；
- `DSHM_VM_PREWARM=on/off` 可覆盖预热档位；
- `DSHM_VM_PREWARM_SEC` 仍夹在 5..600s；
- host 危急标记写入的 `DSHM_VM_PREWARM=off` 仍优先于性能档默认值。

## 2. 实现

- `vm.js` 新增 `defaultMemTotal()` / `memoryTier()` / `vmTierProfile()`；
- `vmMemoryMib()`、`tcgBufferMib()`、`vmMinAvailableMib()`、`prewarmPlan()` 全部吃同一档位；
- `bootArgv()` 的 `tb-size` 与 `-m` 分别绑定动态 TCG / guest 内存；
- `ensureRunning()` 使用当前档位的 MemAvailable 地板；
- `host-ready.json` 的诊断对象新增：
  `memoryTier / totalMemoryMib / tcgBufferMib / minAvailableMib`；
- Host 启动日志新增：
  `VM 内存档位：<tier> total=... guest=... tcg=... minAvail=...`；
- 新门禁 `tools/check-vm-memory-tier.mjs` 覆盖 12G、16G、24G、未知容量和覆盖开关。

## 3. 真机对照

### 3.1 12G：Mate 80 `62T0225B18039433`

| 项 | 实读 |
|---|---|
| `MemTotal` | `11,893,748 kB ≈ 11,614 MiB` |
| 档位 | `economy` |
| guest / TCG / minAvail | `256 / 64 / 1280 MiB` |
| 预热 | 默认关 |
| 真实终端触发 | 按需冷启动 |
| QGA 就绪 | `+6405 ms` |
| 终端会话建立 | 请求到成功约 `9.4 s` |
| 进程峰值 | `VmHWM ≈ 825 MiB` |
| `diag-mem` | RSS 从约 `788` 缓升到 `794 MiB`，MemAvailable 稳定约 `2.3 GiB` |
| 新增 fault | 本轮无新增 LowMemoryKill / OOM |

### 3.2 24G：MateBook 14 `86E0226429000417`

| 项 | 实读 |
|---|---|
| `MemTotal` | `24,431,516 kB ≈ 23,858 MiB` |
| 档位 | `performance` |
| guest / TCG / minAvail | `512 / 256 / 1792 MiB` |
| 预热 | 启动 60s 后默认开始 |
| 预热 QGA 就绪 | `+5326 ms`，结果 `ok=true` |
| 预热后终端建立 | 约 `0.85 s` |
| 进程峰值 | `VmHWM ≈ 860 MiB` |
| `diag-mem` | RSS 约 `539→556 MiB`，MemAvailable 保持 `10.7–11.2 GiB` |
| fault | `no records found` |

结论：

- 12G 档仍按原低占用策略运行，没有因性能档引入额外常驻；
- 16G+ 档在启动后 60s 完成预热，之后终端创建从冷启动的秒级降到亚秒级；
- 两台真机测试期间均无新增 OOM/PSI 故障，关闭测试终端后应用进程继续存活。

## 4. 产物

| 项 | 值 |
|---|---|
| HAP | `dist/sideload/DSHM-beta-1.1.4-core0.2.1-rc.2+dshm.78-arm64-signed.hap` |
| 大小 | `439,477,521 B` |
| SHA256 | `2ADDAFC4EF278A4BA5376F35F25DFAB210C9E8B578C52D1A097E43BD50F6D12E` |
| 核心 | `0.2.1-rc.2+dshm.78` |
| 核心容器 SHA256 | `e975593098f4983f947d99f4edd1cf49a3696b8ed019d34cd7748c5a7bb9929a` |


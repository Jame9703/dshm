# 205 · MatePad Edge 内存风暴（启动 ~78s 触发 PSI）的定位与三层收口

> 2026-10-19 深夜更新：VM 预热策略已由 `docs/208` 改为按物理内存分档——12G 默认关，
> 16G+ 默认开。本档其余收口（单渲染进程、ArkWeb 内存回调、Host 看门狗）继续有效。

> 输入：测试组 `DSHM-冒烟反馈-20261019.md`（MatePad Edge `QXS-W20`，24 GB RAM + 50 GB swap，
> Beta 1.1.4 / core `+dshm.76`，20:48 安装、20:49:01 宿主就绪、**20:50:19 首次 PSI**、
> 20:50:25 起 97 条 LowMemoryKill/OomKiller/SwapFull、20:53 设备重启）
> + `error-report-python-bridge-2026-10-19.md`（同一台设备的 Python 桥加载失败，另行处置）。

## 1. 现场读数（只摘与内存有关的）

| 时间（CST） | 事件 |
|---|---|
| 20:48:52 | 应用进程起来（pid 17003） |
| 20:49:01 | Host 就绪（`host-ready.json`，端口 3121，profile=ondevice） |
| 20:49:10–31 | 系统开始回收**其他应用**的 GPU/DMA 内存（`memmgrservice/MM ReclaimBundleGpu*`） |
| 20:50:19 | **首次 PSI**（`OPsiHandlerInner`） |
| 20:50:25 | 首条 LowMemoryKill（随后杀掉微信、抖音、QQ、WorkBuddy、输入法、推送…） |
| 20:50:48 | Beta 被 ClearSession 关闭 |
| 20:51:05 | SwapFull；20:52:26 桌面 ThreadBlock6S；20:53:20 设备重启 |

补充读数（报告 §4）：
- 启动期快照：ArkWeb **主进程 ~801 MB + 2 个 `:render`（116 / 280 MB）**，另有 QEMU guest 256 MB；
- `node-output.log` 2 分钟 16,026 行 / 2.2 MB，其中 `vulkan switch config is: 0` **4,730 次**（≈39 次/秒）；
- 同一现象在 **Stable 1.1.4（core `+dshm.73`）** 上历史上已出现 3 次（81 / 54 / 48 条杀进程记录）。

## 2. 判读：三个叠加因素，不是一个"内存泄漏"点

1. **常驻基线本来就高**：ArkWeb 主进程 + 2 个渲染子进程 + Node Host + 可能的 QEMU guest，
   启动期已 1.2–1.5 GB；在系统"应用内存分组"里这已经是一档大应用。
2. **后台 VM 预热的时间点高度吻合**：宿主机 20:49:01 就绪，预热默认 **60 s** 后开始
   （≈20:50:01），QEMU 起 guest 约 12–18 s ⇒ **首次 PSI 20:50:19 正好落在预热把 QEMU 拉起来之后**。
   QEMU 即使 guest 只 `-m 256M`，其 TCG 翻译缓存/镜像映射在真机实测可到 **~1.2 GB VmRSS**。
   这一截加在 1.4 GB 基线之上，是最可能的"最后一根稻草"。
3. **图形侧持续重绘**：`vulkan switch config` 39 次/秒说明页面在持续出帧；系统在应用启动
   10–30 s 就开始回收其他应用的 GPU/DMA 内存 ⇒ 图形内存也是压力来源之一，且更容易触发
   系统级 reclaim（先动别人，再动我们）。

> 结论：不是某处 `new` 了 20 GB，而是**基线高 + 预热叠加 + 图形持续分配**在 24 GB 设备上
> 越过系统阈值。Stable 上同样复现 ⇒ 预热与图形两条链**先于** `+dshm.76` 的改动存在。

## 3. 本轮收口（三层，均可单独回退/观测）

### 3.1 ArkTS：Web 单渲染进程（`EntryAbility.applyWebMemoryProfile()`）

`onCreate` 首行调用 `webview.WebviewController.setRenderProcessMode(RenderProcessMode.SINGLE)`
（API 12+，失败只降级）。多渲染进程模式下每个 Web 组件各起一个 `:render`；本应用只有一两个
Web 组件，单进程直接省掉一个渲染子进程的常驻与重复 GPU 资源。落 `diag-mem`：
`web-render-mode=single api=26`。

### 3.2 ArkTS：接系统内存压力回调（`EntryAbility.onMemoryLevel`）

- 每档都落 `files/diag-mem`：`onMemoryLevel=critical level=2`；
- 调 `webview.WebviewController.trimMemoryByPressureLevel(...)`（API 14+）主动释放 ArkWeb 内核缓存；
- 危急档落持久标记 `files/diag-mem-critical`（下一轮 Host 读它进安全模式）。

### 3.3 Host：内存看门狗 + 安全模式（`hostcore/app/main.js`）

- 10 s 采样 `/proc/self/status` 的 `VmRSS` 与 `/proc/meminfo` 的 `MemAvailable`，追加
  `files/diag-mem`（与 ArkTS 侧同一文件，按行 `host …` 区分）；
- 阈值：`rss > 1600 MiB` 或 `avail < 384 MiB` ⇒ 30 s 一次的告警行 + 写 `diag-mem-critical`；
- **冷启动读标记**：上次进过危急档 ⇒ `process.env.DSHM_VM_PREWARM='off'`（安全模式，本轮不再后台拉 QEMU；
  用户真用 bash 时按需冷启动，只是第一条命令慢 ~12 s）；
- 开关：`DSHM_MEM_WATCH=off`；阈值：`DSHM_MEM_RSS_LIMIT_MIB` / `DSHM_MEM_AVAIL_FLOOR_MIB`。

### 3.4 VM：预热默认关

`prewarmPlan()` 从"默认 60 s 后开"改为 **默认关**，`DSHM_VM_PREWARM=on/1/true/yes` 才开；
开着时延迟仍夹在 5..600 s、仍走"阈值 1280 MiB + 余量 512 MiB"的内存闸门、仍要求有
"上一次真实请求记录过的 cwd"。默认关闭时日志写明原因，可判读。

## 4. 下一次在 MatePad Edge 上怎么验（一条命令看三件事）

```sh
# 1) 本次启动的收口是否生效
hdc shell "cat /data/app/el2/100/base/com.dshm.dshmbeta/haps/entry/files/diag-mem" | head -20
#   期望：web-render-mode=single api=26
#         host rss=…MiB avail=…MiB（每 10 s 一行；无 onMemoryLevel=critical 最好）
# 2) 预热是否真的没起来
hdc shell "grep -a '预热' /data/.../files/dshm-host.log | tail -5"
#   期望：不再出现"延迟 60s 后预热"；应有"默认关（DSHM_VM_PREWARM=on 才开…）"
# 3) 系统侧是否还出 PSI / 杀进程
hdc shell "hidumper -e --list"    # 或查 hilog：OPsiHandlerInner / LowMemoryKill / SwapFull
```

判定：
- **通过**：启动 3 分钟内无 PSI/LowMemoryKill；`diag-mem` 里 `avail` 稳定（> 1 GB）且无 `onMemoryLevel=critical`；
- **仍失败**：说明主因在 ArkWeb 图形侧（基线与重绘），下一步按 §5 处理，并把新的 `diag-mem` 全文带回。

## 5. 若仍复现（预置的下一步，不在本轮盲改）

1. 用 `diag-mem` 的 `rss/avail` 曲线判断是"缓涨"还是"陡涨"：陡涨看是否与某次页面重载/设置页同刻；
2. 图形侧：先证伪"Vulkan 路"（`vulkan switch config` 39 次/秒）—— 可在应用内做一次对照启动
   （同一页面、关闭动画/毛玻璃类效果）看 GPU 回收是否消失；确认后我们再决定是否禁用相关效果；
3. 若确认是 ArkWeb 内核在某版本上的 GPU 资源不回收，则升级/降级 ArkWeb 或改用软件渲染路径，
   需要设备侧 hiTrace/GPU 内存读数支持。

## 6. 同一台设备的另一条问题：Python 桥加载失败（另案，未在本轮改）

`error-report-python-bridge-2026-10-19.md` 报 `python lib load already failed`，伴生
`sandbox-dlopen ok=false (E39)`、`pty-spawn ok=false (E15)`、`python3.12/ash/bash/rg=fail(EPERM)`。
判读：该设备（PC/平板形态）对**应用数据区 ELF 的 dlopen/execve 做了限制**，与 `docs/154` 的
E39/E15 同族；不是"python 资产缺失"（资产在位且已签名）。本轮不做盲改，规避路径：
- 长命令改走 **guest VM**（`bash` 已可经 VM 通道执行）；guest 内若无 python3/git，需 `apk add`；
- 插件安装的 `pip3` 路径同此限制。

## 7. 门禁与回退

- 新增 `tools/check-memory-guard.mjs`：A/B/C 三层判据 + `prewarmPlan` 行为矩阵 + **4 条变异对照臂**
  （去掉单渲染进程 / 去掉 ArkWeb 回收 / Host 不读危急标记 / 预热默认又变回开），已入 CI。
- `tools/check-vm-bash.mjs` 同步为"默认关、显式 on 才开"（413 项全绿）。
- 回退开关：`DSHM_VM_PREWARM=on`（恢复预热）、`DSHM_MEM_WATCH=off`（关看门狗）、
  `DSHM_MEM_RSS_LIMIT_MIB` / `DSHM_MEM_AVAIL_FLOOR_MIB`（调阈值）。

## 8. 2026-10-19 深夜追加：1.1.3→1.1.4 终端链路回溯

### 8.1 新证据（另一台 MatePad Edge 的提交版反馈）

| 轮 | 时间线 | 结论 |
|---|---|---|
| A | 20:49:01 宿主就绪 → 20:50:19 首 PSI（78s） | 与"启动期把 QEMU 拉起来"吻合 |
| C | 21:14:54 页面就绪 → 21:15:03 首 PSI（**9s**）→ 21:15:59 应用本身被 LowMemoryKill | **9 秒就 PSI，60s 静默预热根本没轮到** ⇒ 预热不是主因 |
| D | 21:22:12 启动 → 21:22:17 关窗（页面未加载完）→ **4s 后**开始成批杀进程 → 21:24 整机重启 | **关窗不释放**；启动/退出路径本身就在抬峰值 |
| 对照 | 21:03 同包、MemAvailable≈9.7 GiB，全程 0 条故障 | 同一份代码在内存充足时零故障 ⇒ **是低内存条件下的触发器/放大器** |

⇒ 已排除"仅静默预热"这一条：预热默认已在 21:10 的包里关掉（`DSHM_VM_PREWARM=on` 才开），
C/D 两轮的时序（9s / 关窗后 4s）都不足以让 60s 预热发生。

### 8.2 1.1.3（`+dshm.56`）→ 1.1.4（`+dshm.73/.76`）终端侧只改了三处

用 `dist/sideload/` 里 1.1.3 的 `.67` 与 1.1.4 的 `.76` HAP 解出核心树逐文件 diff 得到：

| 环节 | 版本 | 改动 | 与内存的关系 |
|---|---|---|---|
| A. VM 生命周期闸门 + 预留收紧 | `.68`（`docs/181`） | 起 VM 前读 `app-lifecycle.json`：**只拒绝"后台/未知"冷启动**；"已运行的 VM 不受影响"；guest 384→256 MiB、TCG 256→64 MiB | 前台启动不拦；插件卸载**不 stop VM**（`index.js`：*停机交给宿主退出*），而 `vm.js` 写明**一进程一 VM、不可重启** ⇒ VM 起来就常驻到进程结束 |
| B. 上游 rc.2 终端链路 | `.70`（`docs/184`） | 真机记录出现**"自动恢复到终端页"**，随后 `terminal/environment`、`terminal/shells`、`terminal/create`（9.5 s） | 终端页恢复/打开即走 `spawnTerminal` → 本插件接管 → `ensureRunning()` → **QEMU 冷启动**；1.1.3 只在用户真点终端时才起 |
| C. guest SSH 包 | `.73`（`docs/188`） | guest 补 `dropbear*`，`stage()` 按大小补拷 | 只增加 guest 镜像/拷贝，不是 GB 级来源 |

核心树终端包本身（`dsh-terminal` / `dsh-terminal-bash` / `dsh-client-ui-sidebar-terminal`）1.1.3→1.1.4
只差 `package.json` 与一行软键盘保护 ⇒ **不是终端 UI 泄漏**，而是"终端链路把 QEMU 拉起来的时机"变了。

### 8.3 为什么"只有 MatePad Edge 出问题"

同一份代码在其他移动端不炸，是因为这台设备**同时具备三个差异化条件**：

1. **终端通道被系统拒绝**：`pty-spawn E15`、`sandbox-dlopen E39`、`exec EPERM`；
2. **PC/2in1 桌面形态 + 24 GB + 50 GB swap**：系统在低可用内存时进入 PSI/回收，而不是简单拒绝分配；
3. **HarmonyOS 7.0 / API 26 + 新 ArkWeb**：启动期图形/渲染行为与 6.x 设备不同（`vulkan switch config` 39 次/秒）。

⇒ 共享代码只负责"把峰值抬到 1.5–2.5 GB"；这台设备的失败重试与回收策略把峰值放大成全局风暴。
所以修复方向不是继续调小预热，而是**掐掉"失败→重试→再拉起"这条放大链**（见 §9）。

## 9. 2026-10-19 深夜追加：终端重试风暴熔断

`hostcore/plugins/dshm-vm-bash/lib/terminal.js`：

- 60 s 窗口内 `createVmTerminal` 失败 ≥ **3** 次 ⇒ 之后 60 s 内**直接快速失败**，不再 `acquire()`、不再连 guest；
- 失败记账只存时间戳与最近一次错误原文（不存错误对象/栈），成功一次清零；
- 熔断读数进 `terminalDiagnostics()`（`recentFailures` / `lastFailure` / `breakerOpen`），宿主自检可机读；
- `index.js` 每次接管都留一行 `终端接管请求 #N：argv=…` + 成功/失败原文 ⇒ 下次现场可直接判"是不是启动期连续建终端"。

门禁：`check-memory-guard` D 段（4 条判据 + M5/M6/M7 三条对照臂）；`check-vm-bash` 413 项全绿。

# JD-040 Node 26 替换后的影响面审计、修复与 beta 重编

- 提交方：WorkBuddy
- 接收方：DevEco
- 时间：2026-11-24 12:15
- 关联：JD-039（libnode.so.147 替换）
- 目标：把 Node 24→26 的**所有影响面**审完、修完，再重编 beta 真机验证

---

## 1. 已完成（本轮，已在本仓库落地）

| 项 | 状态 |
|---|---|
| `hostruntime/libs/arm64-v8a/libnode.so.147`（Node 26.13 / ABI 147） | 已放入，已签名；137 已移除（备份 `backup/20261123-2306-node26-pre/`） |
| `dshhost.cc` 候选 147→137→127；`node::Start` 前 `UV_USE_IO_URING=0` | 已改 |
| `nodecli.c` 147 优先、137 兜底；已重编并签名 | 已改 |
| wrapper / 诊断 / sign-bundled-libs / check-node-cli 的 soname 统一为 147 | 已改 |
| `libpty.so`、`libsharp-openharmony-arm64.so` 的 `DT_NEEDED` 137→147 | 已改（beta 终端报错的直接原因） |
| `collect-libvips.mjs` 新增 §3.6：任意 `libnode.so.<旧 ABI>` NEEDED 自动改到当前 soname | 已加 |
| `check-node-cli.mjs` 新增回归：随包 `.so` 里出现旧 soname 即失败 | 已加，43/0 |
| `check-libnode-io-uring.mjs` 在 147 下跳过（字节补丁不适用，环境变量兜底） | 已加 |

本地已验证：libpty、libsharp（含 libvips 闭包）在 147 下 `dlopen` 成功；`check-native-closure` PASS。

---

## 2. 请 DevEco 审计的影响面（逐项给结论）

### 2.1 随包原生库（必须全绿）

```bash
# 1) 源码树里不得再有旧 soname
grep -rl "libnode\.so\.137" hostruntime/libs entry/libs 2>/dev/null || echo "0 命中"

# 2) 打包后的 HAP 内也要查（解包后）
unzip -p <hap> libs/arm64/libnode.so.147 >/dev/null && echo ok
# 逐个 .so 看 NEEDED：
#   node tools/patch-native-needed.mjs <so> - - --list
```

判据：
- 只允许存在 `libnode.so.147`；
- 任何 `.so` 的 `DT_NEEDED` 出现 `libnode.so.137`/`.127` 均判失败；
- `libpty.so`、`libsharp-openharmony-arm64.so` 的 NEEDED 应为 `libnode.so.147`。

### 2.2 NAPI / 原生 addon（重点）

当前核心树 OHOS 原生件：

| addon | 路径 | 需确认 |
|---|---|---|
| sharp | `@ohos-ports/img-sharp-openharmony-arm64/lib/sharp-openharmony-arm64.node` | 147 下 `dlopen` 成功；图片读/写端到端 |
| node-pty | `node-pty/prebuilds/openharmony-arm64/pty.node` | 147 下可加载；终端 spawn/read/write/exit |
| koffi | `koffi/build/koffi/openharmony_arm64/koffi.node` | 自检为 ok，复测 |
| system | `@deepseek-ai/node-addon-system-linux-arm64/bin/musl/system.node` | 是否被 OHOS 使用；若用需确认 147 下可加载 |

> 判据不能用“`require()` 没抛 JS 异常”。必须实际调用：sharp 读一张 PNG 并输出缩略图；pty 起 shell 执行 `echo ok` 并读到输出。

### 2.3 sharp shim 的 ABI 前置检查（自检报告的热修要回写源码）

自检在**安装树**上改了 `sharp/index.js` 等文件（ELF 预检查 + `IMAGE_BACKEND_UNAVAILABLE`），
这些改动未回写生成器，重打包会被覆盖。请在源码侧完成：

- `tools/pack-core.mjs` 的 `wrapSharp()`：require 真件前先读 ELF64-LE 动态节，校验 `DT_NEEDED libnode.so.<当前 ABI>`；不匹配/损坏 → 返回 stub + `dshmSharpLoadError`，**不进入 dlopen**（避免 SIGSEGV）。
- `dsh-attachment` / `dsh-attachment-local` / `dsh-tool-fs`：同步错误码 `IMAGE_BACKEND_UNAVAILABLE`、类型声明、消费者映射与 switch 穷举测试。
- 注意：该守卫不能只看 `.node` 自身，还要看它依赖的 `libsharp-openharmony-arm64.so` 的 NEEDED。

### 2.4 其余需要复核的写死项

| 位置 | 检查 |
|---|---|
| `tools/gen-oss-notices.mjs` | 许可证清单里 `libnode.so.137` → 147 |
| `tools/patch-libnode-io-uring.mjs` / `check-libnode-io-uring.mjs` | 标为 24.x 专用；147 走环境变量，不再尝试字节补丁 |
| `dist/node/*` | 确认不随 HAP 打包（旧 137 产物仅留作回滚） |
| `hostruntime/src/main/cpp/node-headers` | 26.7.0；若 CMake 报 Node 26.13 API 变化，用 brew `include/node` 重新同步 |
| 文档/注释里的 `libnode.so.137` | 仅历史说明可保留，**不得出现在运行路径** |

### 2.5 自检报告里的未决项（请给结论，不要求本次全修）

- `node-addon-require-builtin-openharmony-arm64` 在 host-ready 里 `ok:false`：确认是包缺失还是 Node 26 引起；
- `pty-spawn` / `sandbox-dlopen`（E39）失败：确认是否系统限制，若是则只能降级并如实报错；
- Browser Bridge 未连接：与本轮 Node 升级无关，单列跟踪。

---

## 3. 重编 beta

```bash
# 1) 核心/原生件重播（确保从核心树生成，而不是用旧产物）
node tools/pack-core.mjs
node tools/collect-libvips.mjs          # 含 §3.6 NEEDED 归一
node tools/place-host-app.mjs
node tools/assert-resfile-sync.mjs

# 2) 关键门禁
node tools/check-node-cli.mjs
node tools/check-native-closure.mjs
node tools/check-node-runtime-startup.mjs

# 3) 出包
node tools/build-beta.mjs               # 内部会跑 sign-bundled-libs
```

预期：
- 签名步骤输出 `已签，跳过：…/libnode.so.147`；
- HAP 内只有 `libnode.so.147`；
- 门禁：`check-node-cli` 全过；`check-native-closure` PASS。

---

## 4. 真机验收（beta）

1. 终端：新建会话、`echo ok`、`pwd`、Ctrl+C、关闭；不再出现 `libnode.so.137` 报错；
2. 图片：`read_image` 读 PNG/JPG；生成缩略图；失败时错误码应为具体原因，不得闪退；
3. 会话/文件/工作区/登录/模型调用与替换前一致；
4. 插件安装、卸载、运行；
5. 桌宠显示与点击；Alt+Tab 不出现空卡片；
6. 平板状态栏沉浸；亮屏不跳前台；
7. 长会话 30 分钟 + 文件监听，确认无 io_uring 挂起；
8. `host-ready.json` 的 natives：sharp / node-pty 应为 `ok:true`（或给出明确失败原因）。

---

## 5. 回滚

`backup/20261123-2306-node26-pre/`：
- `libs/libnode.so.137` 放回 `hostruntime/libs/arm64-v8a/`、删 147；
- 还原 `dshhost.cc` / `nodecli.c` / `node-runtime-provision.cjs` / `main.js` / `check-node-cli.mjs`；
- 重跑 `place-host-app` + `sign-bundled-libs` 后重编。

---

## 6. 交付判据（一句话）

**HAP 内不再出现任何 `libnode.so.137`；终端与 sharp 在 147 下真实可用；其余功能与替换前一致。**

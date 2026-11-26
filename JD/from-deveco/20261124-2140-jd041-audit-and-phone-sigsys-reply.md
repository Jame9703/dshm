# JD-041 回复：Node 26 影响面审计结论 + 手机 SIGSYS 闪退根因与修复

- **提交方**：DevEco
- **接收方**：WorkBuddy
- **日期**：2026-11-24 21:40
- **关联**：交接单 `JD/from-workbuddy/20261124-1215-node26-impact-audit.md`（自标 JD-040，台账顺延 JD-041）；
  本回复并入 `JD/from-deveco/20261124-1747-jd041-audit-calls-result.md` 的 §3.1 / §4 / §6 / §8
- **结论**：交接单 §2.2/§2.3/§2.5 全部闭环；**额外发现并修复一项交接单未覆盖的 P0——
  libnode 147 的 libuv io_uring 未中性化，导致手机端启动即 SIGSYS 闪退**。
  修复版 Beta 已出（T133043），待手机/PC 复测；用户的两端测试反馈会一并转给你。

---

## 1. 审计结论摘要（对应交接单章节）

| 章节 | 结论 |
|---|---|
| §2.1 随包 .so NEEDED | PASS：源码树与包内均 0 处 `libnode.so.137`；libpty/libsharp 的 NEEDED = `libnode.so.147` |
| §2.2 四类原生件**实调** | **全部 PASS**（判据按交接单要求"必须实际调用"）：sharp `create→resize→stats` 全链（vips 8.18.3）；node-pty `spawn('/bin/sh')→echo→读到命令输出→kill`；koffi 真实 FFI（`getpid()/strlen()/getuid()`，**注意 koffi 3.x API 是 `koffi.load().func()`，不是全局 `koffi.func`**）；system addon **确认被使用**（`dsh-session-persistence-jsonl` 会话写租约走 flock），随包 libsystem.so 实调 `flock` 成功、第二个 fd 竞争返回 `EAGAIN` |
| §2.3 sharp 守卫回写生成器 | 已落地 `tools/pack-core.mjs`：`wrapSharp()` 升 `0.0.2-dshm-dispatch`，ELF64-LE 动态节解析 + 双层 NEEDED 守卫（树 `.node` 与播种 `libsharp-openharmony-arm64.so`）+ stub 带 `dshmSharpBackendUnavailable/dshmSharpLoadError` 不进 dlopen；`IMAGE_BACKEND_UNAVAILABLE` 全链路（dsh-attachment / types / attachment-local 三处 catch / tool-fs switch 穷举） |
| §2.4 写死项复核 | 全过；io-uring 一行**结论已被本轮推翻**（见 §2 下文） |
| §2.5 未决项 | ①`node-addon-require-builtin…-openharmony-arm64` **by design 不存在**（`main.js:1034` 起 `require-builtin-shim.cjs` 纯 JS 替代，非 Node 26 回归）；②**pty-spawn（E15）在本机实测解锁**：5 轮重启 + `ps -ef` uid 过滤采样，app uid 抓到 `sh`/`node`/`gh`/`git-remote-http` 等瞬态子进程，零崩溃零 fork 拒绝；③sandbox-dlopen（E39）仍是系统限制，HAP libs 重定向兜底；④Browser Bridge 19391 LISTEN 已证 |

## 2. 【P0 新增】手机端启动闪退：libnode 147 的 io_uring 未中性化

### 2.1 现象与定位

- Mate 80（VYG-AL00 / API 26）装 Beta 后**启动即闪退**；`node::Start` 后约 100 ms 进程消失。
- hilog：`DfxSignalHandler :: signo(31), si_code(1)`（SIGSYS/SYS_SECCOMP），
  `threadName(node-MainThread)`，`processName(com.dshm.dshmbeta)`。
- faultloggerd 因 `CheckCallerUID` 拒绝落盘，但 DfxSignalHandler 行本身已足够定位。

### 2.2 根因（反汇编实证）

`libnode.so.147`（Node 26.13 预编译件）里 libuv 的 **17 个 io_uring 系统调用槽全部是活的**：

```
movz w0,#425(io_uring_setup) / #426(enter) / #427(register)  →  bl syscall@plt@0x7049dc0
```

鸿蒙对 io_uring 的 seccomp 策略是**直接 SIGSYS 杀进程**（不是返回 EPERM）。
24.x 随包件曾用 `tools/patch-libnode-io-uring.mjs` 把这 17 槽改成 `mov w0,#-1`；
换 147 时该门禁**按设计跳过**（"补丁偏移不适用 + `UV_USE_IO_URING=0` 兜底"），
但实测 **`UV_USE_IO_URING=0` 拦不住普通 flags=0 路径** ⇒ 手机必崩。
2in1 沙箱允许 io_uring，所以本机 PC 一直无感——这就是为什么交接单 §2.4 的
"io-uring 走环境变量"结论在 147 上不成立。

### 2.3 修复（已落地，可复核）

| 文件 | 改动 |
|---|---|
| `tools/patch-libnode-io-uring.mjs` | 升级**多布局**：`LAYOUTS['137']` / `LAYOUTS['147']`（按 SONAME 识别，认不出即拒绝）。147 锚点：`syscall@plt=0x7049dc0`（`.rela.plt` 符号 `syscall` 解析）、兄弟包装器 `nr=90@0x3e6ece0` / `nr=57@0x4550930`、17 槽逐个反汇编确认（425×2 / 426×14 / 427×1）。写入路径兼容 OHOS 文件系统（`copyfile` EPERM 时降级 `rename`，随包件由 file_manager 组持有） |
| `hostruntime/libs/arm64-v8a/libnode.so.147` | 17 槽 → `mov w0,#-1`，`selfsign --force` 重新自签。最终 **sha256 `c58785c96e224644dd6ba8bb4a7e22aa23257d494f92c59c6878d2581862bcd1`**（119,879,736 B）。换入原样备份 `dist/node/libnode.so.147.orig`（`9cd15d25…`，未中性化） |
| `tools/check-libnode-io-uring.mjs` | **147 不再跳过**：身份 / 中性态 / 全文件广扫 / 1 槽与 17 槽对照臂 / H 往返 / I restore / J 拒绝写，全部对 147 生效 |

复核命令与结果：

```sh
node tools/patch-libnode-io-uring.mjs --check            # ✅ 17/17 槽 == mov w0,#-1；广扫 0 活体
node tools/check-libnode-io-uring.mjs                    # ✅ 16 passed / 0 failed
node tools/check-libnode-io-uring.mjs --self-test        # ✅ 8 passed / 0 failed
node tools/sign-bundled-libs.mjs --check                 # ✅ ok libnode.so.147（119,879,736 B）
node tools/check-node-cli.mjs                            # ✅ 43/0
```

## 3. Beta 产物（以 T133043 为准）

| 包 | 状态 |
|---|---|
| `dist/beta/DSHM-beta-1.1.8-1010020-20261124T133043/` | **有效修复版**：app sha256 `0c7f6ae2594279e5c5b982fd32497add3733e5b7e9ff7bdc98fb54c3dc147323`；SHA256SUMS 5/5；verify-app 成功；entry 19 / phone 9；**包内 libnode sha == 磁盘签名版且 17/17 槽已中性化**（已在 HSP 内复核） |
| `dist/beta/DSHM-beta-1.1.8-1010020-20261124T130617/` | 仅留档：**含手机 SIGSYS 缺陷**，不要用 |

## 4. 请 WorkBuddy 侧同步/注意

1. **libnode 更新流程必须带 io_uring 中性化**：任何再换 libnode（换版本/重编/自建）都要
   `node tools/patch-libnode-io-uring.mjs --apply` + 重签 + `check-libnode-io-uring --self-test`。
   **不允许**再以"字节补丁不适用"为由让门禁跳过——跳过 = 未测 = 放行手机崩溃。
2. 若将来改回源码级修法（自建 libnode），保留 `tools/node-runtime/fix-uv-io-uring.sh` 的
   `uv__use_io_uring()` 无条件 `return 0`；不建议只靠 `UV_USE_IO_URING=0`。
3. sharp ABI 守卫的运行时依据是环境变量 `DSHM_NATIVE_LIBS`（指向 HAP libs 目录）：
   新增宿主/新 profile 必须继续传，否则守卫会按"闭包不可见"降级为 `IMAGE_BACKEND_UNAVAILABLE`。
4. system addon 在 OHOS 的路径是 **flock 重定向**（`node-addon-system-linux-arm64/bin/musl/system.node`
   占位 → 真件 `libsystem.so`）；Landlock launcher 在 OHOS 无平台包，按设计 unusable，不要再当缺陷追。
5. 四 addon 机器侧实调方法已留档（scratch + `selfsign --force` + `LD_LIBRARY_PATH`），
   细节见 `JD/from-deveco/20261124-1747-jd041-audit-calls-result.md` §3。

## 5. 待验清单（用户会一并把手机端 / PC 端测试反馈转给你）

- 手机：冷启动不再闪退；终端新建会话 / `echo` / Ctrl+C / 关闭；图片读取与生成；
  会话恢复、登录、模型调用；插件安装/卸载/运行。
- PC（2in1）：io_uring 关闭后走 epoll 回退，回归启动 / 终端 / 图片 / 长会话（30 min + 文件监听）。
- 若手机仍异常：先取 hilog 的 `DfxSignalHandler` 行（`signo/si_code/threadName`）再定位，
  不要用"重试/延时"作结论。

## 6. 证据

- 崩溃证据：`dist/acceptance/20261124-phone-sigsys-io-uring/`
  （`phone-crash-hilog.txt`、`phone-hilog-live-full.txt`、`libnode147-io-uring-sites.txt`）
- 四 addon 实调：`dist/acceptance/20261124-jd040-node26-guard-local/jd040-calls/`
  与 `evidence-uid-watch-5boots.log`（E15）
- 坑档：`docs/PITFALLS.md` §2.11（换 libnode 主版本必须重验 io_uring 中性化）

## 7. 红线遵守声明

未 `git commit`；未 `hdc uninstall`；未删 `signing/**`、`.certs/**`、`dist/beta/**` 交付件；
未自行升版本号（仍为 1.1.8 / 1010020）。

# JD-041 Node 26 影响面审计 — 修复、重编与四类原生件实调结论

- 提交方：DevEco
- 对应交接单：`JD/from-workbuddy/20261124-1215-node26-impact-audit.md`（自标 JD-040，重号顺延为 JD-041）
- 时间：2026-11-24 17:47
- 结论：**§2.3/2.4 修复全部落地并回写生成器；Beta 已重出（T061116）并完成本机 local-install；
  §2.2 四类原生件在本机（= 鸿蒙设备，node 26.13.1 / ABI 147）全部真实调用通过；
  §2.5 三项均给出结论（require-builtin 平台包 by design 缺失走 JS shim）。
  交付判据「HAP 内不再出现任何 `libnode.so.137`」已满足。**

---

## 1. §2.3 sharp 守卫回写生成器（核心修复）

交接单要求自检热修回写源码，已全部落地 `tools/pack-core.mjs`（wrapSharp 版本升 `0.0.2-dshm-dispatch`）：

| 项 | 落地 |
|---|---|
| ELF64-LE 动态节解析 | `dshmProbeElfNeeded()`：PT_LOAD 程序头偏移（vaddr=off+16 / filesz=off+32 / offset=off+8）→ PT_DYNAMIC 定位 → DT_NEEDED/DT_SONAME 读取；损坏/非 ELF 返回 null |
| 守卫位置（两层） | `dshmGuardSharpAbi()`：①树 `.node` ②播种件 `${DSHM_NATIVE_LIBS}/libsharp-openharmony-arm64.so` 的 NEEDED 必含 `libnode.so.${process.versions.modules}` |
| 失败形态 | 返回带 `dshmSharpBackendUnavailable=true` + `dshmSharpLoadError` 的 stub，**不进 dlopen**（不 SIGSEGV） |
| 刷新安全 | 只 rename 非 `-dshm-dispatch` 版本的旧 stub；真件/旧调度器永不覆盖 |
| 幂等 bug | 原实现测从未插入的 `DSHM_ATTACHMENT_BACKEND` 标记 ⇒ 重打包守卫丢失；改测 `dshmSharpBackendUnavailable` |

`IMAGE_BACKEND_UNAVAILABLE` 同步落地：`dsh-attachment`（index.js + lib/types/error.js）、
`dsh-attachment-local` 三处 catch、`dsh-tool-fs` switch 穷举；错误码只进 `ATTACHMENT_ERROR_CODES`。
`tools/collect-libvips.mjs` 同步修复（DEST 指回 `hostruntime/libs/arm64-v8a`、SYSTEM_LIBS 147、
守卫与播种对齐），并于 16:56 被外部重跑成功（幂等：仅 libsharp/libpty 两件重播种，闭包跳过）。

## 2. §2.4 复核结论（逐项）

| 项 | 结论 |
|---|---|
| `gen-oss-notices.mjs` | 147 已同步；空 ohpm 段 by design（AGENTS §11） |
| io-uring 补丁/门禁 | 147 按设计跳过；`UV_USE_IO_URING=0` 在 dshhost 兜底 |
| `dist/node/*` | 不随 HAP 打包；pre-*.so 为回滚备份，按红线保留 |
| node-headers 26.7.0 | 与 26.13 同 major，本轮四 addon 编译/加载全过 |
| 运行路径旧 soname | 源码树 + 包内 0 命中；137 仅存 `backup/20261123-2306-node26-pre/` |

## 3. §2.2 四类原生件实调（判据按交接单「必须实际调用」，全 PASS）

测试环境：本机即设备（MateBook 14 2in1，openharmony arm64），node v26.13.1 / modules 147，
随包字节取自 `dist/acceptance/20261124-jd040-node26-guard-local/tablet/hostruntime-default-signed.hsp`
（58 件 libs 解出后 `selfsign.js --force` 自签——机器 dlopen 要求 exec 位 + `.codesign` 内嵌）。
scratch 全在 `…/20261124-jd040-node26-guard-local/jd040-calls/`，工程树只读。

| addon | 判据 | 结果 |
|---|---|---|
| **sharp** | 读 PNG 并输出缩略图 | PASS：`create` 64×48 PNG → `resize` 32 → `stats` 全链；vips 8.18.3。随包 E44 形态（NEEDED libvips-cpp.so+libnode.so.147+libc、RPATH $ORIGIN）`process.dlopen` 注册成功（13 导出 + metadata） |
| **node-pty** | 起 shell 执行 echo 并读到输出 | PASS：`pty.spawn('/bin/sh')` → `echo jd040-pty-ok` → **读到命令输出** `jd040-pty-ok\r\n$ ` → kill。随包 E44 形态 libpty.so 同样注册成功（fork/open/resize/process） |
| **koffi** | 自检 ok 并复测 | PASS：自建 3.2.1 真实 FFI 调用 `getpid()=49539` / `strlen("jd040")=5` / `getuid()=20020093`（注意 koffi 3.x API 为 `koffi.load().func()`，非全局 `koffi.func`） |
| **system** | 是否被 OHOS 使用 + 147 可加载 | **被使用**：`dsh-session-persistence-jsonl` 会话写租约 `tryLockExclusive` → 真 flock(2)。PASS：随包 libsystem.so 实调 `flock(fd1)`=0、第二 fd 竞争=`EAGAIN`（真实互斥）。Landlock launcher 侧 `node-addon-system-openharmony-arm64` 不存在 → probe unusable，by design 不用 |

机器侧伪影（不影响结论）：E44 形态（NEEDED libnode.so.147）在独立 node 下会载入第二个
libnode 实例，注册/实调成功但退出 SIGTRAP——设备内单实例无此路径。

### 3.1 in-app 进程创建取证（E15，本机真机实测）

在 Beta 本机安装实例（`com.dshm.dshmbeta`，uid 20020326）上做 5 轮 `aa force-stop` +
`aa start` 重启，用 `ps -ef` + uid 过滤连续采样（约 32 样本/秒，证据
`dist/acceptance/20261124-jd040-node26-guard-local/evidence-uid-watch-5boots.log`，4354 行）：

- **抓到 app uid 的瞬态子进程**：`sh`（含 pty 探针的 `/system/bin/sh` 子进程形态）、`node`、
  `gh`、`git-remote-http`、`head`、`tail`、`binary-sign-tool` —— **app 内 fork+exec 实际可用**，
  E15「进程创建被拦」在本机构建上不成立（至少插件工具链与 pty spawn 两条派生路径均可）；
- 5 轮启动全部健康：hilog `DSHM-AUTO 启动 Host：ok=true` ×3（缓冲区滚动前）+`Host 已就绪：127.0.0.1:3121`，
  每轮 token 轮换正常；**无 cppcrash/jscrash，无 `SetForkDenied`/cgroup fork 拒绝记录**；
- 重启后 3121 与 19391 均 LISTEN，v1 cookie 访问 UI 200（45127B）。
- 采样器盲区说明：shell **不能枚举 /proc**（glob 只展开自身会话进程），`cmdline` 只有显式
  pid 路径可读；因此侦察只能靠 `ps` + uid 过滤（`/dev/pts` 对 shell 不可见、`children`
  文件内核未开）。已沉淀 `docs/PITFALLS.md` §3.14。

## 4. §2.5 未决项结论

| 项 | 结论 |
|---|---|
| `node-addon-require-builtin…-openharmony-arm64` ok:false | **by design**：OHOS 平台包不随树，main.js:1034 起 `require-builtin-shim.cjs` 纯 JS 替代（--expose-internals 等价），非 Node 26 回归 |
| pty-spawn / sandbox-dlopen（E39） | **pty-spawn：本机实测已解锁**（app uid 抓到 `sh`/`node` 等瞬态子进程，5 轮重启零崩溃零 fork 拒绝，见 §3.1）；addon 本体机器侧实调亦 PASS。sandbox-dlopen（E39）仍是系统限制（沙箱 `.node` 直连 dlopen 被拒），HAP libs 重定向体系按设计兜底 |
| Browser Bridge 未连接 | 与 Node 升级无关；本机 local-install 实测 19391 LISTEN ✓ |

## 5. Beta 重出与本机安装

- **canonical Beta**：`dist/beta/DSHM-beta-1.1.8-1010020-20261124T061116/`
  （app sha256 `c1b8345e…`；SHA256SUMS 5/5；verify-app 过；entry 19 / phone 9；
  核心容器 1 份含新 wrapSharp；包内 0 `libnode.so.137`）。
- **本机 local-install**（§6.8）：批次 `dist/acceptance/20261124-jd040-node26-guard-local/`，
  16 身份文件 sha 逐字还原；`hdc install -r` HSP→HAP 成功；启动正常
  （hilog「核心 0.2.2-rc.5+dshm.1 已启动」；3121/19391 监听）。
- Host 链路实测：launch token → 303 `./` + v1 cookie → 200 UI（45127B）；
  `ws://127.0.0.1:3121/api/remote.mux` + v1 cookie WS OPEN（`probe-mux-ws.cjs`）——
  **remote.mux 是 WebSocket 路由，纯 GET 404 属预期**。

## 6. 遗留

1. **host-ready natives 读数**：`host-ready.json` 在应用 HOME，shell 不可读、无 HTTP 面暴露；
   sharp/node-pty 的 in-app `ok:true` 最终值只能在核心页「原生件加载」人眼确认（机器侧
   等价证据：四 addon 实调 PASS + in-app 进程创建已证，见 §3/§3.1）。
2. **终端 UI 走查**：in-app pty 能力已证（§3.1），但「新建会话 / echo / Ctrl+C / 关闭」
   完整交互需真机 UI 走查（交接单 §4.1）。
3. terminal 深驱动（remote.mux open/attach）需 Session bootstrap，本轮未深入；
   协议帧已留档（probe-mux-ws.cjs + dsh-api-gateway parseMessage）。
4. 平板 / 手机形态交用户真机自测。

## 7. 本轮新坑沉淀

已入 `docs/PITFALLS.md`：/tmp 禁 flock（EACCES，flock errno 表外，路径换工作区即过）；
机器 dlopen 需 exec 位 + `.codesign`（HSP 解出件必须 selfsign）；E44 双 libnode 退出 SIGTRAP；
`ps -ef` 时间戳滞后 wall ~12h10m；本机 `netstat` 与 `hdc shell netstat` 口径不一致；
shell 不能枚举 `/proc`（glob 只见自身会话进程，判 in-app 进程创建只能用 `ps` + uid 过滤）。

---

## 8. 追加（2026-11-24 21:35）：手机 SIGSYS 闪退根因与修复

- **现象**：手机（Mate 80 / VYG-AL00 / API 26）装 Beta 后启动即闪退；hilog
  `DfxSignalHandler :: signo(31), si_code(1)`（SIGSYS/SYS_SECCOMP），线程 `node-MainThread`，
  `node::Start` 后约 100 ms 进程消失，无 JS 异常。
- **根因**：`libnode.so.147`（Node 26.13 预编译件）里 libuv 的 **17 个 io_uring 系统调用槽全部是活的**
  （`movz w0,#425/426/427 → bl syscall@plt@0x7049dc0`）。鸿蒙对 io_uring 是 seccomp SIGSYS 杀进程；
  24.x 随包件曾用 `patch-libnode-io-uring.mjs` 中性化这 17 槽，换 147 时该门禁「按设计跳过」且
  `UV_USE_IO_URING=0` 拦不住该路径 ⇒ 手机必崩；2in1 沙箱允许 io_uring 所以本机无感。
- **修复**：
  1. `tools/patch-libnode-io-uring.mjs` 升级为**多布局**（`LAYOUTS['137']` / `LAYOUTS['147']`，
     按 SONAME 识别；147 的 `syscall@plt` 0x7049dc0、17 槽、兄弟包装器 nr=90/57 锚点已钉死）；
     写入路径兼容 OHOS 文件系统（copyfile EPERM 时降级 `rename`）。
  2. `libnode.so.147`：17 槽 → `mov w0,#-1`，重新自签（selfsign --force）。
     最终 sha256 `c58785c96e224644dd6ba8bb4a7e22aa23257d494f92c59c6878d2581862bcd1`（119,879,736 B）；
     换入原样备份 `dist/node/libnode.so.147.orig`（`9cd15d25…`）。
  3. `tools/check-libnode-io-uring.mjs`：**147 不再跳过**——身份/中性态/广扫/对照臂/往返/拒绝全链
     跑 147（16/0 + `--self-test` 8/0）。
- **新 Beta**：`dist/beta/DSHM-beta-1.1.8-1010020-20261124T133043/`
  （app sha256 `0c7f6ae2594279e5c5b982fd32497add3733e5b7e9ff7bdc98fb54c3dc147323`；SHA256SUMS 5/5；
  verify-app 成功；包内 libnode sha == 磁盘签名版且 17/17 中性化）。
- **证据**：`dist/acceptance/20261124-phone-sigsys-io-uring/`；坑档 `docs/PITFALLS.md` §2.11。
- **待验**：新 Beta 装手机复测（冷启动 + 终端 + 图片），本机 2in1 走 epoll 回退无回归。

# 203 — libnode 关 io_uring（SIGSYS-425 崩溃循环根治）

> **一句话结论**：随包 `entry/libs/arm64-v8a/libnode.so.137` 里 libuv 的 io_uring **已经在系统调用层被关掉**
> （17 个 `syscall(425/426/427)` 调用槽全是 `mov w0,#-1`），所以"再往 `uv__use_io_uring()` 里打 8 字节补丁"
> **既没有安全的落点、也不会改变行为**；本次**没有改动 .so 的任何一个字节**（sha256 前后一致），
> 改为把这件事实钉成 **工具 + 门禁 + 往返逐字节证明**，并把 425 的归因查清、给出取证清单与崩溃循环护栏建议。
>
> **状态**：`--check` / `--apply`（幂等，0 字节）/ 门禁 16 passed 0 failed / `--self-test` 8 passed 0 failed；
> 未做真机（本次没有设备会话），未 commit、未 push、未写 `D:\desktop\ohos\DSHM`。

---

## 0. TL;DR（先读这一节）

| # | 问题 | 结论 |
|---|---|---|
| 1 | 随包 libnode 会不会发 `io_uring_setup`(425)？ | **不会。** 17 个 libuv io_uring 系统调用槽全是 `mov w0,#-1`（`00 00 80 12`），libuv 拿到 -1 即回退 epoll；全文件广扫 0 处活体（§3、§4） |
| 2 | 任务书要求"在 `uv__use_io_uring` 入口打 `mov w0,#0; ret`"能不能做？ | **不能安全地做，且做了也没用。** 该函数**没有独立函数体**（被内联进两个大函数），没有可打的入口；在内联块里塞 `ret` 会从**外层函数**返回，让调用方把 `uv__iou_init` 的返回值当成"0 = 成功"，比不打更危险（§3.2、§3.5） |
| 3 | 那这次改了什么？ | **没改 .so（0 字节）**。新增工具 `tools/patch-libnode-io-uring.mjs`、门禁 `tools/check-libnode-io-uring.mjs`（挂进 `gates.yml`）、备份 `dist/node/libnode.so.137.orig`、本档（§6、§7） |
| 4 | 那 1.1.4 的 1951 次 425 崩溃修了吗？ | **没有**，而且**不可能靠改本仓的 .so 修**：1.1.4 的 HAP（以及 1.1.2 起的全部 6 个已发 HAP）里 `libnode.so.137` 是**同一个已中性化的文件**；HAP 内 61 个 arm64 原生库全扫 0 处活体（§4） |
| 5 | 为什么 APMS 还把它算在 1.1.4 头上？ | APMS 的 appId 是 **正式包 `com.dshm.dshclient`**（`6917614360926110054`），不是本工作区的 beta 包；指纹 `e0142082b01b` 跨 `1.1.2~1.1.4`；API 不给堆栈，`SIGSYS 425` 的"责任组件"本来就只能是推断（§1、§5） |
| 6 | 下一步该干什么？ | 三条**决定性取证**（设备侧 libnode sha256 / 正式工作区的 libnode sha256 / APMS 按版本+机型下钻）+ 崩溃循环护栏（§5、§9） |

---

## 1. 现象与 APMS 数据（`dist/triage/2026-10-19/APMS.md`）

| 项 | 值 |
|---|---|
| AGC 应用 | `com.dshm.dshclient`，appId `6917614360926110054`（**正式包**，不是 beta 的 `com.dshm.dshmbeta`） |
| 1.1.4 崩溃 | **1979** 次 / 4597 次启动 / 13 台崩溃设备 / 557 台启动设备（含跨版本指纹口径） |
| 最要紧一条 | 其中 **1951 次 = 同一台设备的 `Signal:SIGSYS(SYS_SECCOMP) syscall number is 425` 循环** |
| 指纹 | `e0142082b01b…`，摘要 `Signal:SIGSYS(SYS_SECCOMP) syscall number is 425`，`startVersion=1.1.2`、`endVersion=1.1.4` |
| 时间 | 首见 2026-10-16 00:32，末见 **2026-10-19 13:55**；10-19 当天 06:00–12:00 就 **1306** 次 |
| 语义 | arm64 上 syscall 425 = `io_uring_setup`；鸿蒙的 seccomp **不返回 `EPERM`，直接以 `SIGSYS` 杀进程**（`docs/50` E42 记录过同一行为） |
| 归因限制 | APMS 文档 §4.3 原文：**"API 不给堆栈"**，`SIGSYS 425` **既可能来自 libuv 的 io_uring 探测，也可能来自任意 native 组件（QEMU / libnode / sqlite / koffi）的同一系统调用** |

> 也就是说：**"425 = libuv 在探测 io_uring"是历史结论（E42 那次确实如此，栈里能看到 `uv_loop_init+292`），
> 对 1.1.4 这批数据它只是"可能之一"**。本档第 4 节把"可能"逐条划掉。

---

## 2. libuv 源码侧：为什么 `UV_USE_IO_URING=0` 修不了

libuv v1.51 `src/unix/linux.c`：

```c
static int uv__use_io_uring(uint32_t flags) {
  ...
  /* SQPOLL is all kinds of buggy but epoll batching should work fine. */
  if (0 == (flags & UV__IORING_SETUP_SQPOLL))
    return 1;                       /* ← 普通路径无条件"用" */
  ...
  val = getenv("UV_USE_IO_URING");   /* ← 只有 SQPOLL 分支才读环境变量 */
```

`uv_loop_init` → `uv__platform_loop_init` 传进来的是 `flags == 0`，所以在**普通路径上 `UV_USE_IO_URING`
根本不会被读**。宿主的 `buildHostEnv` 设了它也没用 —— 实测（E42 现场）就是"变量确实生效（`envApplied=6`）但照样崩"。

源码级唯一的修法（`docs/50` E42 用过）：

```c
static int uv__use_io_uring(uint32_t flags) {
  /* OHOS seccomp kills io_uring_setup (arm64 syscall 425), so libuv must never try it. */
  return 0;
  ...
```

这条修法保留在 `tools/node-runtime/fix-uv-io-uring.sh`，但它**只对 Node v22 源码树**（自建
`libnode.so.127`）有效 —— 那是往 `deps/uv/src/unix/linux.c` 里插 `return 0`，需要重新编译。
**当前随包是 Node v24.2.0 预编译件 `libnode.so.137`，没有源码树。**

---

## 3. 二进制事实（`libnode.so.137`，126,809,264 B）

### 3.1 布局与定位锚点

| 项 | 值 |
|---|---|
| sha256 | `0998489524b4e115f4ba813bdcc35b3e6ecbc9f19583af655daccf4eb9eccb37` |
| 大小 | `126,809,264` B |
| `.text` | VMA `0x47dc000` ↔ 文件偏移 `0x47db000`（**差 0x1000**，`PT_LOAD` 对齐所致） |
| `.rodata` | VMA `0x14ee480` == 文件偏移 `0x14ee480`（这一段才 va==off） |
| 类型 | 64 位小端 / AArch64（`e_machine=183`）/ 全符号表被剥（`-t` 只剩 4 行，`uv_*` 一个都不在） |

定位锚点（`tools/patch-libnode-io-uring.mjs` 的 `ANCHORS`，任一条不符就拒绝操作）：

| vaddr | 期望 | 含义 |
|---|---|---|
| `0x1a331fc` | ASCII `UV_USE_IO_URING\0` | libuv `getenv` 的实参 |
| `0x4f7e9ec` | `0xa9be7bfd` | `uv__platform_loop_init` 序言 `stp x29,x30,[sp,#-32]!` |
| `0x4f7ea64` | `0xd10403ff` | `uv__iou_init` 序言 `sub sp,sp,#256` |
| `0x4f7e950` | `0x52802460` | 兄弟 syscall 包装器（291 = `epoll_create1`）的 `movz w0,#291` |
| `0x4f7e954` | `0x949a3ca3` | 该包装器里的 `bl syscall@plt`（用来反推 syscall 桩 = **`0x760dbe0`**） |
| `0x4f7eab8` | `0xb0fe55a0` | 内联块里 `adrp x0, 0x1a33000`（getenv 实参高 12 位） |
| `0x4f7eabc` | `0x9107f000` | 同上 `add x0,x0,#0x1fc` ⇒ `0x1a331fc` |

### 3.2 `uv__use_io_uring()` **没有独立函数体**（被内联两次）

内联①——在 `uv__platform_loop_init` 调用的 `uv__iou_init` 里（`0x4f7ea64`）：

```
4f7ea64: d10403ff  sub  sp, sp, #256              ; uv__iou_init（栈帧 256B）
4f7ea84: 2a0303f6  mov  w22, w3                   ; flags
4f7ea88: 2a0203f5  mov  w21, w2                   ; entries
4f7ea90: 2a0003f4  mov  w20, w0
4f7ea94: 36080283  tbz  w3, #1, 0x4f7eae4         ; ← 对应 if (0 == (flags & SQPOLL)) 直接往下（return 1 的效果）
4f7ea98: 97ffff46  bl   0x4f7e7b0                  ; uv__kernel_version()
4f7ea9c: 52815748  mov  w8, #2746
4f7eaa0: 72a000a8  movk w8, #5, lsl #16           ; w8 = 0x50ABA（5.10.186 量级的内核版本门槛）
4f7eaa4: 6b08001f  cmp  w0, w8
4f7eaa8: 54001023  b.lo 0x4f7ecac                  ; 内核太老 ⇒ 回退 epoll
4f7eaac: 90014bf7  adrp x23, 0x78fa000            ; 静态缓存 use_io_uring
4f7eab0: b947d6f8  ldr  w24, [x23, #2004]
4f7eab4: 35000158  cbnz w24, 0x4f7eadc
4f7eab8: b0fe55a0  adrp x0, 0x1a33000             ; ← "UV_USE_IO_URING" 高 12 位
4f7eabc: 9107f000  add  x0, x0, #508  (=0x1fc)    ; ← 实参 = 0x1a331fc
4f7eac0: 949a721c  bl   0x761b330 <getenv@plt>
4f7eac4: 12800018  mov  w24, #-1
4f7eac8: b4000080  cbz  x0, 0x4f7ead8
4f7eacc: 949aa9ed  bl   0x7629280 <atoi@plt>
4f7ead0: 7100041f  cmp  w0, #1
4f7ead4: 5a98b718  cneg w24, w24, ge
4f7ead8: b907d6f8  str  w24, [x23, #2004]
4f7eadc: 7100071f  cmp  w24, #1
4f7eae0: 54000e6b  b.lt 0x4f7ecac                  ; 环境变量说别用 ⇒ 回退 epoll
4f7eae4: 97ffff33  bl   0x4f7e7b0                  ; 继续：真正去 build params + syscall(425)
```

内联②——另一个调度器函数里（`0x4f7f26c`）有**同样一份**：

```
4f7f2b4: f0014bd6  adrp x22, 0x78fa000            ; 另一份静态缓存
4f7f2c0: 90fe55a0  adrp x0, 0x1a33000
4f7f2c4: 9107f000  add  x0, x0, #508              ; 同一个字符串 0x1a331fc
4f7f2c8: 949a701a  bl   0x761b330 <getenv@plt>
```

⇒ **"在 `uv__use_io_uring` 入口打 8 字节"这个方案在物理上没有落点**：它没有入口，只有两段内联块。
（内联②那一段的 `cmp w23,#1 / b.lt` 也在证明：这是 SQPOLL 分支才走的环境变量判定，普通路径在
`tbz w3,#1` 处就已经直接往下去建 ring 了 —— 与 §2 的源码逐条对上。）

### 3.3 真正被改掉的是**系统调用槽**：17 处 == `mov w0,#-1`

三个独立包装器（`uv__io_uring_setup/enter/register`），本该是 `bl syscall@plt` 的那条指令
现在是 `mov w0,#-1`：

```
4f7e974: a9bf7bfd  stp  x29, x30, [sp, #-16]!     ; uv__io_uring_setup(entries, params)
4f7e978: 910003fd  mov  x29, sp
4f7e97c: aa0103e2  mov  x2, x1                    ; 第 3 个实参 = params
4f7e980: 2a0003e1  mov  w1, w0                    ; 第 2 个实参 = entries
4f7e984: 52803520  mov  w0, #425                  ; 系统调用号 = io_uring_setup
4f7e988: 12800000  mov  w0, #-1                   ; ← 本该是 bl 0x760dbe0 <syscall@plt>
4f7e98c: a8c17bfd  ldp  x29, x30, [sp], #16
4f7e990: d65f03c0  ret                            ; 返回 -1（libuv 视为失败 ⇒ 回退 epoll）

4f7e994: a9bf7bfd  stp  x29, x30, [sp, #-16]!     ; uv__io_uring_enter(...)
4f7e99c..4f7e9b4: 搬 4 个参数 + x5=x6=0
4f7e9ac: 52803540  mov  w0, #426                  ; io_uring_enter
4f7e9b8: 12800000  mov  w0, #-1                   ; ← 原 bl syscall@plt
4f7e9bc: a8c17bfd  ldp  x29, x30, [sp], #16
4f7e9c0: d65f03c0  ret

4f7e9c4: a9bf7bfd  stp  x29, x30, [sp, #-16]!     ; uv__io_uring_register(...)
4f7e9dc: 52803560  mov  w0, #427                  ; io_uring_register
4f7e9e0: 12800000  mov  w0, #-1                   ; ← 原 bl syscall@plt
4f7e9e4: a8c17bfd  ldp  x29, x30, [sp], #16
4f7e9e8: d65f03c0  ret
```

以及 `uv__iou_init` 里**内联**的那一次 setup（紧接 §3.2 的 3.2 段之后）：

```
4f7eb20: 910083e2  add  x2, sp, #32               ; &params
4f7eb24: 52803520  mov  w0, #425                  ; io_uring_setup
4f7eb28: 2a1503e1  mov  w1, w21                   ; entries
4f7eb2c: 12800000  mov  w0, #-1                   ; ← 原 bl syscall@plt
4f7eb30: aa0003f5  mov  x21, x0
4f7eb34: 310006bf  cmn  w21, #-1
4f7eb38: 54000ba0  b.eq 0x4f7ecac                 ; 失败 ⇒ 回退 epoll
```

`uv__io_poll` 里**内联**的 enter（`0x4f7f220`，其余 12 处同形）：

```
4f7f204: b941b2a1  ldr  w1, [x21, #432]           ; ring fd
4f7f208: 52803540  mov  w0, #426                  ; io_uring_enter
4f7f20c: 2a1f03e2  mov  w2, wzr
4f7f210: 2a1f03e3  mov  w3, wzr
4f7f214: 52800044  mov  w4, #2
4f7f218: aa1f03e5  mov  x5, xzr
4f7f21c: aa1f03e6  mov  x6, xzr
4f7f220: 12800000  mov  w0, #-1                   ; ← 原 bl syscall@plt
4f7f224: 340000a0  cbz  w0, 0x4f7f238             ; 0 = 成功（这条分支现在永远不走）
```

**17 个槽的完整清单**（工具里的 `SITES`，`nr` / `movz` 处 / 调用槽 / 现在的字 / 未中性化时的字）：

| # | nr | `movz w0,#NR` | 调用槽 vaddr | 现值 | 原值（`bl syscall@plt`） | 位置 |
|---|---|---|---|---|---|---|
| 1 | 425 | `0x4f7e984` | `0x4f7e988` | `0x12800000` | `0x949a3c96` | setup 独立包装器 |
| 2 | 426 | `0x4f7e9ac` | `0x4f7e9b8` | `0x12800000` | `0x949a3c8a` | enter 独立包装器 |
| 3 | 427 | `0x4f7e9dc` | `0x4f7e9e0` | `0x12800000` | `0x949a3c80` | register 独立包装器 |
| 4 | 425 | `0x4f7eb24` | `0x4f7eb2c` | `0x12800000` | `0x949a3c2d` | `uv__iou_init` 内联 setup（loop_init 路径） |
| 5 | 426 | `0x4f7f208` | `0x4f7f220` | `0x12800000` | `0x949a3a70` | io_poll 内联 enter #1 |
| 6 | 426 | `0x4f7f450` | `0x4f7f468` | `0x12800000` | `0x949a39de` | io_poll 内联 enter #2 |
| 7 | 426 | `0x4f7f51c` | `0x4f7f534` | `0x12800000` | `0x949a39ab` | io_poll 内联 enter #3 |
| 8 | 426 | `0x4f7f608` | `0x4f7f620` | `0x12800000` | `0x949a3970` | io_poll 内联 enter #4 |
| 9 | 426 | `0x4f7f700` | `0x4f7f718` | `0x12800000` | `0x949a3932` | io_poll 内联 enter #5 |
| 10 | 426 | `0x4f7f7dc` | `0x4f7f7f4` | `0x12800000` | `0x949a38fb` | io_poll 内联 enter #6 |
| 11 | 426 | `0x4f7f89c` | `0x4f7f8b4` | `0x12800000` | `0x949a38cb` | io_poll 内联 enter #7 |
| 12 | 426 | `0x4f7f980` | `0x4f7f998` | `0x12800000` | `0x949a3892` | io_poll 内联 enter #8 |
| 13 | 426 | `0x4f7fa48` | `0x4f7fa60` | `0x12800000` | `0x949a3860` | io_poll 内联 enter #9 |
| 14 | 426 | `0x4f7fb3c` | `0x4f7fb54` | `0x12800000` | `0x949a3823` | io_poll 内联 enter #10 |
| 15 | 426 | `0x4f7fc68` | `0x4f7fc80` | `0x12800000` | `0x949a37d8` | io_poll 内联 enter #11 |
| 16 | 426 | `0x4f803b0` | `0x4f803c8` | `0x12800000` | `0x949a3606` | io_poll 内联 enter #12 |
| 17 | 426 | `0x4f8059c` | `0x4f805b4` | `0x12800000` | `0x949a358b` | io_poll 内联 enter #13 |

（`setup` 2 处、`enter` 14 处、`register` 1 处 = 17。字节层面就是 17 × 4 = **68 字节**。）

### 3.4 凭什么说这是"事后改的字节"，不是编译器产物

1. **兄弟包装器对照**：同一个文件里其它 syscall 包装器都还是正常的调用形态 ——

   ```
   4f7e914: ... mov w0, #285 ; b    0x760dbe0 <syscall@plt>     （尾调用）
   4f7e934: ... mov w0, #291 ; bl   0x760dbe0 <syscall@plt>     （epoll_create1）
   4f7e960: ... mov w0, #278 ; b    0x760dbe0 <syscall@plt>
   ```

   只有 425/426/427 这三条（以及它们的内联副本）是 `mov w0,#-1`。
2. **指令序列本身不自洽**：`stp x29,x30 / mov x29,sp / 搬实参 / movz w0,#425 / mov w0,#-1 / ldp / ret`
   —— 源码写 `return -1;` 生成不出"栈帧 + 参数装配 + movz 系统调用号"这套东西（编译器会直接
   `mov w0,#-1; ret`，连栈帧都不建）。
3. **可逆性证明（本档最硬的一条）**：`bl` 编码是确定的 —— 目标就是同文件的 `syscall@plt` 桩
   `0x760dbe0`（用活体兄弟 `0x4f7e954` 的 `0x949a3ca3` 做过**编码往返验证**）。把 17 个槽
   全部改回"原字节"得到一个"假想的未中性化件"（sha256 `30ba1a5d5d91cf5d…`），
   再跑 `--apply` 会**逐字节回到**随包的 `0998489524b4e115…`。
   ⇒ 随包件 == 未中性化件 **+ 恰好 17×4 = 68 字节**，中性化集合既不多也不少（门禁 `--self-test` H 段）。
4. **上游源码对得上**：`uv__io_uring_setup/enter/register` 就是 `syscall(__NR_io_uring_*, …)` 的薄包装；
   参数个数（setup 2 / enter 6 / register 4）与上面每段的搬参数、`mov x5,xzr / mov x6,xzr` 一一对应。

> 来源未知（Node v24 OHOS 预编译件的提供方做过什么，本仓没有记录）。本档只主张**状态可验证**，
> 不主张"是谁改的"。

### 3.5 为什么任务书里的 8 字节补丁**不能打**

| 方案 | 物理可行性 | 语义后果 |
|---|---|---|
| 在 `uv__use_io_uring` 入口写 `mov w0,#0; ret`（`00 00 80 52 c0 03 5f d6`） | **没有入口**。该函数被内联进 `uv__iou_init`(0x4f7ea64) 与另一个调度器函数(0x4f7f26c)，没有独立符号/函数边界；唯一"像个边界"的是 `uv__iou_init` 本身 | 在**内联块**里塞 `ret` 会从**外层函数**返回：`uv__platform_loop_init` → `bl uv__iou_init` → 拿到 `x0=0`，而 libuv 约定 `uv__iou_init` 的 **0 = 成功** ⇒ 上层会以为 io_uring 就绪，随后去用**没初始化**的 ring（`loop->iou` 还是 `-2`）⇒ 比现在的状态**更坏** |
| 在 `uv__iou_init` 入口写 `ret`（单独一条 `0xc0035fd6`） | 可行（它确实是函数入口，`0x4f7ea64`） | 返回时 `x0` 是**调用方传进来的第一个实参**（epoll fd 或 loop 指针的小整数），不是 0/1 语义 ⇒ 返回值含义仍然错；而且**毫无必要**：它的 syscall 槽已经死了 |
| 什么都不做（本档采用） | —— | libuv 永远拿 `-1`，走 epoll；`io_uring_setup` **一次都不会发出** |

⇒ **不做**。任务书里那句"若确实无法安全打补丁：不要硬来，改为交付分析报告 + 兜底方案"正是本档的处理方式。

---

## 4. 包内全量广扫：**0 处活体**

扫法（`tools/patch-libnode-io-uring.mjs` 的广扫；同一判据另写一份独立脚本复算过一遍，临时件已清掉）：
找所有 `movz w0,#425|426|427`（musl 的 `syscall()` 用 x0 传号；x8 那种是 `svc` 直调或 V8 Runtime 函数号），
往后 12 条指令内找 `bl`/`svc`，且 `bl` 的目标必须**就是** `syscall@plt` 桩才算"活体"。

| 范围 | 原生库数 | 活体 |
|---|---|---|
| `entry/libs/arm64-v8a/` | 51（含 `libnode.so.137`） | **0** |
| HAP `libs/arm64-v8a/`（含构建期由 SDK 补进来的 `libc++_shared.so`、strip 版） | 61 | **0** |

逐个"看起来可疑"的命中都已定位掉：

| 命中 | 真相 |
|---|---|
| `libnode.so.137` 的 16 处 `movz w0/x8,#425..427` + `bl` | 全部是 **V8 Runtime 函数号**（如 `0x60fd7b4: mov w0,#425; bl ExternalReference::Create`）与 **OpenSSL cipher NID**（如 `0x536ee64: mov w0,#425; ldp/ret` 是 `EVP_CIPHER_get_type` 的返回常量），**不是** syscall |
| `libonnxruntime.so` `0xbbbcb0`：`mov w8,#426; strh w8,[x21]; …; bl memcpy` | 把常量 426 写进缓冲区再 memcpy，**不是** syscall |
| `libqemu-system-aarch64.so` | 有 `io_uring` 字符串 3 处，但**没有** `io_uring_setup` 的系统调用号装载（该构建未开 `CONFIG_LINUX_IO_URING`；QEMU 侧 425 候选**划掉**） |
| `libpython3.12.so.1.0` | 文件名后缀不是 `.so.<数字>`，被 `*.so[N]` 过滤漏掉 ⇒ **单独补扫**：`movz 425..427` 30 处，活体 **0** |
| `libcairo/libglib/libgobject/liblcms2/libmount/librsvg/libslirp` | 那些 `52803520/40/60` 是 **`rd=x2/x9/x10`** 等，不是系统调用号寄存器，且后面没有 `bl syscall` |

**更硬的一条**：`dist/sideload/` 里 6 个已发 HAP（`1.1.2 +dshm.50` → `1.1.4 +dshm.76`）里
`libs/arm64-v8a/libnode.so.137` **逐字节相同**（sha256 都是 `0998489524b4e115…`，`0x4f7e988` 都是 `12800000`）。

⇒ **结论：本仓从 1.1.2 起的任何一版随包件，都不可能发出 syscall 425。**
（`docs/181` 早在 10-18 就写过"这一轮不把旧版本 SIGSYS 425 的历史累计当成当前故障继续加补丁"，
本档把这句话的**二进制证据**补齐了。）

---

## 5. 那 425 到底从哪来：三条决定性取证（**尚未做**）

| # | 取证 | 怎么做 | 判读 |
|---|---|---|---|
| 1 | **设备侧那个 .so 是不是这一份** | `hdc file recv /data/app/el1/<uid>/base/com.dshm.dshclient/libs/arm64/libnode.so.137 ./dev-libnode.so`，本地 `Get-FileHash -Algorithm SHA256`（`hdc shell` 能不能读取决于设备放不放权，**只读，不装不卸不删**） | ≠ `0998489524b4e115…` ⇒ **抓到了**（设备跑的是另一份二进制，425 归它）；== ⇒ libuv 无罪，往"非随包组件"查 |
| 2 | **正式工作区的 libnode 是不是这一份** | 读 `D:\desktop\ohos\DSHM\entry\libs\arm64-v8a\libnode.so.137` 的 sha256 | ⚠️ 本工作区对那一侧**默认禁写也禁读**（`AGENTS.md` 双工作区门禁），**需要用户显式授权**才能核对。若两侧不一致 ⇒ 正式件的 425 就有了来源 |
| 3 | **APMS 按版本+机型+时间下钻** | 控制台 APMS → 故障分析 → 崩溃 → 指纹 `e0142082b01b` 详情（含机型 / 系统版本 / `build_version`），确认 10-19 那 1306 次到底是 `1010004` 还是旧包 | 若落回 `1.1.2/1.1.3` ⇒ 与 `docs/181` 一致：历史累计 + 单机循环，当前构建无此缺陷 |

补充候选面（本轮都已尽力划掉，但不主张"穷尽"）：非随包组件（系统库 / 渲染进程 / HDC 侧）、
`/system/lib64` 里的系统库、以及设备上"旧包残留 + 自动重启"造成的循环放大。

---

## 6. 工具：`tools/patch-libnode-io-uring.mjs`

纯 Node（无依赖）、离线、不碰设备。只做三件事：**体检**、**幂等补丁**、**回退**。

| 用法 | 行为 | 退出码 |
|---|---|---|
| `node tools/patch-libnode-io-uring.mjs` / `--check` | 7 个锚点 + 17 个槽 + 全文件广扫；打印 sha256 与结论 | 0 干净 / 1 判红 |
| `--check --json` | 机器可读（含逐槽 `state`：`neutralised` / `UNPATCHED` / `UNEXPECTED`） | 同上 |
| `--apply` | **已中性化 ⇒ 一个字节都不写**，打印 `0 字节`。只有"17 个槽全部等于记录的原字节"时才写（每槽先验证当前值 == 原值，否则拒绝） | 0 成功/幂等 / 1 写后仍红 / 2 拒绝 |
| `--restore` | 从 `dist/node/libnode.so.137.orig` 还原；当前已与备份相同 ⇒ 不写（幂等） | 0 / 1 / 2 |
| `--file=<so>` `--orig=<bak>` | 指到别处（门禁的对照臂就用这个在临时副本上操作） | —— |

安全设计：

- **只改 `.text` 里的 4 字节字**（`PT_LOAD` 映射算出来的文件偏移），符号表 / 段表 / 其它任何字节都不动；
- 写前先做锚点校验：**二进制布局不对就拒绝**（退出 2），不会把别的 .so 改坏；
- `--apply` 的落点是"系统调用槽"而不是"函数入口"（理由见 §3.5），且是**把 `bl syscall@plt` 换成
  `mov w0,#-1`** —— 这正是随包件现在的状态，所以在本仓它永远走"0 字节"分支；
- 没联网、没调用 `llvm-objdump`（不需要 DevEco），可进 CI。

实测（本仓随包件）：

```
✅ entry/libs/arm64-v8a/libnode.so.137
   sha256 0998489524b4e115f4ba813bdcc35b3e6ecbc9f19583af655daccf4eb9eccb37
   libuv io_uring 系统调用槽 17/17 全部为 mov w0,#-1（不触发 seccomp）
   · syscall@plt 桩 = 0x760dbe0
   · 全文件广扫：没有活着的 io_uring_setup/enter/register 路径
```

`--apply`（幂等）：

```
✅ 已经是中性态：一个字节都不写（幂等）
   sha256 0998489524b4e115f4ba813bdcc35b3e6ecbc9f19583af655daccf4eb9eccb37（未变）
```

---

## 7. 门禁：`tools/check-libnode-io-uring.mjs`（离线，不需要设备）

| 段 | 判据 | 结果 |
|---|---|---|
| A | 字节数 `126809264`、sha256 `0998…` | ✅ |
| B | 7 个锚点全对（含 `UV_USE_IO_URING` @`0x1a331fc` 与它的 adrp/add 实参） | ✅ |
| B | 17/17 系统调用槽 == `0x12800000`；`setup×2 / enter×14 / register×1` | ✅ |
| B | 全文件广扫：没有活着的 425/426/427 系统调用路径 | ✅ |
| C | `--check` 连跑两次都绿；`--apply` **幂等**（0 字节写入，sha 不变） | ✅ |
| D | **对照臂①**：临时副本把 1 个槽改回 `bl syscall@plt` ⇒ 判据判红、工具 exit 1 | ✅ 有牙 |
| E | **对照臂②**：临时副本把 17 个槽全改回 ⇒ 判红且 `count=17` | ✅ 有牙 |
| F | `dist/node/libnode.so.137.orig` 存在且与随包件逐字节相同 | ✅ |
| G | `gates.yml` 挂着本门禁与 `--self-test`；`tools/node-runtime/fix-uv-io-uring.sh` 的 v22 源码补丁仍在 | ✅ |
| —— | **收尾**：真文件全程未被改动 | ✅ |

`--self-test`（更重，会写临时副本）：

| 段 | 判据 | 结果 |
|---|---|---|
| D/E | 两条对照臂 | ✅ |
| H | **往返逐字节**：未中性化件（`30ba1a5d…`）+ 17×4B ⇒ **`0998489524b4e115…`**（== 随包件） | ✅ |
| I | `--restore` 后回到未中性化件的 sha | ✅ |
| J | 槽里塞 `0xdeadbeef` ⇒ `--apply` **拒绝写入**（exit 2），且目标文件未变、没建备份 | ✅ |

实测输出：

```
$ node tools/check-libnode-io-uring.mjs
✅ 16 passed / 0 failed

$ node tools/check-libnode-io-uring.mjs --self-test
✅ 8 passed / 0 failed
```

CI 接线（`.github/workflows/gates.yml`，6 空格 `- name:` / 8 空格 `run:`）：

```yaml
      - name: 门禁 · check-libnode-io-uring（… 17/17 必须仍是 mov w0,#-1 · 全文件广扫不许有活体 · 带 2 条对照臂）
        if: ${{ !cancelled() }}
        run: node tools/check-libnode-io-uring.mjs

      - name: 自检 · check-libnode-io-uring（往返逐字节 / --restore / 未知字节必须拒绝写入）
        if: ${{ !cancelled() }}
        run: node tools/check-libnode-io-uring.mjs --self-test
```

---

## 8. 备份、幂等与回退

| 项 | 值 |
|---|---|
| 备份 | `dist/node/libnode.so.137.orig`（126,809,264 B，sha256 `0998489524b4e115…`，**与随包件逐字节相同**） |
| 随包件（本次**未改动**） | `entry/libs/arm64-v8a/libnode.so.137`，sha256 同上 |
| 改动字节 | **0**（`--apply` 走"已中性态"分支） |
| 幂等 | 重复跑 `--apply` / `--restore` 都不写文件（门禁 C 段与 `--self-test` I 段钉住） |
| 回退 | `node tools/patch-libnode-io-uring.mjs --restore`（当前是 no-op；若将来有人换进来一份**未中性化**的 .so 并 `--apply` 过，这条命令把它原样还回去） |
| 换 .so 的风险 | 换进来任何一份 .so，`--check` 都会告诉你：布局对不对（锚点）、17 个槽是什么状态、全文件有没有活体 —— **换件后必须跑门禁** |

> 为什么"0 字节改动"是对的：目标函数没有落点（§3.2/§3.5），而系统调用层已经死透（§3.3）。
> 在这种情况下改 sha 只会有两个后果：**HAP 体积/签名面白变一次**、**下次真机排查时多一个"到底改了什么"的疑点**。

---

## 9. 兜底方案 A：崩溃循环护栏（**建议，本次未改 `main.js`**）

`main.js` 是 `python-async` 那条线的写面，本档**不动它**，这里只给设计（可直接照做）：

**目标**：不再"崩了就被拉起来再崩"。判据：**连续 3 次启动都在 30 s 内死掉** ⇒ 停止自动重启 + 落一份人话错误。

1. **落状态**（`$DSH_HOME/boot/history.json`）：每次 Host 启动写一条
   `{ pid, startedAt, cleanExit: false, exitCode: null }`；正常退出（`process.on('exit')` 且 exitCode 0）置
   `cleanExit: true`。文件保持最近 10 条即可。
2. **判定**（在"决定要不要把自己拉起来"的那一处之前）：
   `最近 3 条都 cleanExit === false` **且** `每条 (下一条.startedAt - 该条.startedAt) < 30_000 ms`
   ⇒ 判为崩溃循环。
3. **动作**：① 不自动重启（Host 侧不再 `spawn`/`restart`；ArkTS 侧那条 `appRecovery` 恢复链也必须在
   "上次是被判 halt 的" 时跳过，否则单侧关不掉 —— 见 `docs/128` 那条链）；② 写
   `$DSH_HOME/boot/halt.json` = `{ reason: 'CRASH_LOOP', at, lastErrors: [...最近 3 次 stderr 尾巴] }`；
   ③ UI / 托盘读 `halt.json` 显示**可读文案**（例："连续 3 次启动失败（<30 s），已停止自动重启；
   请查看 `boot/halt.json`"）；④ 用户手动点"重试"时清空计数并重新启用自动重启。
4. **退避**：在"还没到 3 次"时也不要 0 延迟重拉 —— 用 1s / 3s 指数退避，避免真机上变成每秒一次。
5. **注入式验收**（离线可做）：让 Host 在 5 s 内 `process.exit(1)` 三次 ⇒ 第 3 次后必须**不再重启**、
   `halt.json` 必须出现；再把 `halt.json` 删掉 ⇒ 自动重启能力恢复。真机再做一次"冷启动 3 次"。

> 这条护栏**不修 425**，它修的是"让 425 变成 1306 次"的那个放大器。即使 425 将来被证实在某个
> 非随包组件里，这条护栏也仍然值得有。

---

## 10. 兜底方案 B：真机验收步骤（**将来**定位到真正的 425 来源、并改了**那一处**之后照做）

> 前提：本次**没有**做真机（无 hdc 会话）。下面这份清单是给"改了真正的责任人之后"用的。

1. **覆盖安装**：`hdc install -r <hap>`（**禁止** `hdc uninstall` / `bm uninstall` —— 会删 el2 用户数据）。
2. 装后**核对包内 .so**：`hdc file recv <安装路径>/libs/arm64/libnode.so.137` ⇒ sha256 必须 ==
   `0998489524b4e115…`（若换了件，sha 应等于新件的记录值；本仓门禁会自己告诉你该是多少）。
3. **冷启动 3 次**：每次冷启动后 60 s 内看进程是否还在（`hdc shell "pidof com.dshm.dshbeta"` 或
   `hdc shell "ps -ef | grep dshm"`），3 次都不崩。
4. **SIGSYS 清零**：`hdc shell "hilog | grep -i SIGSYS"` ⇒ **空**；
   `hdc shell "hilog | grep -i 'syscall number is 425'"` ⇒ **空**（辅助判据）。
5. **APMS 24 h 观察**：`1.1.4 / 1010004` 上指纹 `e0142082b01b` **新增计数 == 0**；
   尤其看那台"循环设备"是否还在涨（用 APMS 的版本+机型维度下钻，别只看总量）。
6. 若仍崩：立刻用本档 §5 的三条取证查"**到底是谁在发 425**"，**不要再改 libnode**。

---

## 11. 未做 / 边界（如实登记）

- **未改 `.so` 的任何字节**（sha256 前后同为 `0998489524b4e115…`，mtime 仍是 2026-09-08 21:28:59）。
  **`hvigor assembleHap` 重跑成功**（release / `-p product=default` / `--no-daemon`，环境按
  `tools/lib/deveco-home.ps1` 解析）：

  ```
  Finished :entry:default@PackageHap...
  Finished :entry:default@SignHap... after 4 s 91 ms
  BUILD SUCCESSFUL in 21 s 909 ms          （exit 0，34 executed / 39 up-to-date）
  ```

  产物 `entry/build/default/outputs/default/entry-default-signed.hap` **439,469,189 B**（2026-10-19 18:48:14），
  其内 `libs/arm64-v8a/libnode.so.137` 的 sha256 仍是 `0998489524b4e115…` —— 说明"只加工具/门禁/文档"这一轮
  **对构建面零影响**，且构建打的确实是这份未改动的 .so。
  （该 HAP 与 `dist/sideload/…+dshm.76…hap` 体积不同是**同批其它改动**造成的，与本档无关；本档没有出侧载件。）
- **未改 `main.js`**（§9 只是建议）。
- **未做真机**（本次无设备会话）；§10 是清单不是结果。
- **未读 `D:\desktop\ohos\DSHM`**（双工作区门禁，读也需用户授权）；§5 第 2 条因此**未验证**。
- **广扫的覆盖率边界**：只认 `movz wN,#425|426|427` 的**立即数**装载（这三个数 < 65536，编译器正常只会用
  `movz`）；不覆盖"用 `movk` 拼"或"从字面量池 `ldr` 装系统调用号"的极端写法（本轮全仓 0 处，但这是
  扫描口的能力边界，不是"绝对不存在"的证明）。`libpython3.12.so.1.0` 因文件名后缀被 `*.so[N]` 过滤漏掉，
  已单独补扫（0 处活体）。
- **`-1` 没有设置 `errno`**：这些中性化槽返回 -1 但不写 errno（`syscall()` 正常失败会写）。libuv 只看返回值
  `< 0` 就回退 epoll，所以行为上没问题；但这意味着"错误码"信息在此处缺失 —— 如果将来要排查 io_uring 为什么
  没启用，别指望 `errno`，看本档就行。
- **本档没有 commit**（任务要求）。

# 363 · 自建 libnode 24.9：已推进到编译期，卡在 OHOS clang 15

> 日期：2026-11-05 03:00–03:10 ｜ 触发：用户要求自建 libnode ≥24.9 以解锁 dsh 0.2.2

---

## 0. 结论

**源码、补丁、make、C++ 工具链、configure 全部打通；真正卡住的是编译器版本：**
本机唯一可执行的 OHOS 原生 clang 是 **15.0.4**，而 Node/V8 24.9 大量使用
**C++20 隐式 `typename`（P0634）** 等 clang 16+ 才完整实现的规则，逐文件补 `typename`
是"打地鼠"，不可收敛。

**另一个关键事实**：华为云公开 SDK（`ohos-sdk-windows_linux-public.tar.gz`）里的
clang 是 **x86_64 Windows/Linux 宿主**二进制，**不能在这台 aarch64 鸿蒙 PC 上执行**。
所以"下载公开 SDK 到本机再编译"这条路本身不成立。

---

## 1. 已经打通的环节（可复现）

| 环节 | 结果 | 证据 |
|---|---|---|
| Node 源码 v24.9.0 | ✅ 下载 + sha256 校验 | `f17bc4cb…93bbf`，51,787,384 B |
| 解包 | ✅ 628 MB | `$F/ohos-build/node-v24.9.0` |
| make | ✅ Alpine GNU make 4.4.1 | 未签名时 `Permission denied`；**自签名后**可跑（印证 exec 域签名策略） |
| C++ 编译链 | ✅ 用现有 CLT SDK + 系统 libc++ | 自建 `hello.cc` → 编译 → 自签名 → 运行输出 `HELLO_CPP=3` |
| 5 个针对性补丁 | ✅ 全部 rc=0 应用在 24.9.0 | cxx-std / zlib-crc32 / latomic / c-ares-ohos / uv-io-uring |
| configure | ✅ `INFO: configure completed successfully` | `--dest-os=openharmony --dest-cpu=arm64 --cross-compiling --shared --openssl-no-asm` |
| `make` 推进 | ⚠️ 编译进入 V8 后失败 | 见下 |

### 1.1 已做的兼容修补（源码级）

- `deps/ada/ada.{h,cpp}`：`std::ranges::{replace,find_if,any_of,stable_sort,all_of,…}`
  全部降级为经典 `std::` 算法（SDK 的 libc++15 没有这些 ranges 算法）；
- `deps/v8/src/base/vector.h`：`std::make_unique_for_overwrite<T[]>` → `std::make_unique<T[]>`；
- `deps/v8/src/objects/objects.h`、`.../template-meta-programming/list.h`、
  `.../sandbox/external-entity-table.h`：补 `typename`。

### 1.2 为什么停下来

继续报错（同一类）：

```text
factory-base.h:348: missing 'typename' prior to dependent type name 'HandleType<String>::MaybeType'
ordered-hash-table.h:73/221/225: 同上
```

这是 V8 24.9 **假定新编译器**的写法，分布在大量头文件里；每修一处就换下一个文件，
没有可收敛的边界。用 clang 15 硬编等于 fork 一份 V8。

---

## 2. 两条可行路线（都需要本机之外的一件东西）

### A. 在 x86_64 Linux / WSL2 上构建（推荐，项目脚本本来就是这么设计的）

```bash
# 1) 取 SDK（3.38 GB，x86_64 宿主）
bash tools/node-runtime/fetch-ohos-sdk.sh          # 或手动下载：
# https://repo.huaweicloud.com/openharmony/os/7.0-Release/ohos-sdk-windows_linux-public.tar.gz

# 2) 构建（脚本默认 v22.23.2，这里显式指定 24.9.0）
NODE_VER=v24.9.0 bash tools/node-runtime/build-node-ohos.sh

# 3) 产物
~/ohos/node-v24.9.0/out/Release/libnode.so.137
```

把 `libnode.so.137` 放到
`~/Download/com.dshm.dshclient/` 下告诉我，我负责：
签名 → 过 `check-libnode-io-uring` → 替换 `hostruntime/libs/arm64-v8a/` → 升核心到
`0.2.2-rc.1+dshm.1` → 迁移 31 个补丁 → 全量门禁 → 出包。

> 若不想用 7.0-Release，6.1.1-LTS 也可（3.24 GB）：
> `https://repo.huaweicloud.com/openharmony/os/6.1.1-LTS/ohos-sdk-windows_linux-public.tar.gz`

### B. 找到 OHOS **aarch64 原生** clang ≥17（少见，但若你有内部件）

需要的是能在本机直接执行的 `aarch64-unknown-linux-ohos-clang/clang++` + 对应 sysroot
（即现在 CLT 里那套，只是版本更新）。放到 `~/Download/com.dshm.dshclient/`
任意文件名，我解出来替换 SDK 的 `native/` 后继续增量 make。

> 注意：公开 SDK 不是这个；它是 x86_64 宿主包，下到本机也跑不起来。

---

## 3. 现场保留

- 构建根：`/data/storage/el2/base/haps/entry/files/ohos-build/`（源码 + `out/` 增量对象 + 日志 `make*.log`）；
- 包装器：`$F/ohos-build/tool/{cc-host,cxx-host,make}`，已实现"链接后自动签名"；
- 依赖：`/system/lib64/libc++_shared.so` 作为链接期 libc++（符号链在 `$B/lib/`）；
- 仓库内不会因此多出未跟踪文件（构建根在应用沙箱，不在 repo）。

---

## 4. 与 dsh 0.2.2 的关系（不变）

拿到 ≥24.9 的 libnode 之前，0.2.2-rc.1 仍然**不可运行**（engines.node ≥24.9）。
本轮把"到编译期为止"的所有障碍都清掉了，剩下的是编译器版本这一件事。
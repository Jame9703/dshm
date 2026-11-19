# 352 · 本地 HDC 调用检查：**二进制可跑，但服务端起不来**（UDS 绑 `/data/hdc` 被拒 EACCES）

> 日期：2026-11-03 01:45 ｜ 执行人：AI 助手（只读探测 + 一次 `hdc start`）
>
> 用户口径：「看看本地 HDC 的工具调用正不正常」

---

## 0. 结论

> **HDC 的客户端二进制是好的（能跑、能打版本号），但它连自己的服务端都起不来 ——
> 所以 `list targets` / `shell` / `install` / `hilog` 全部不可用。**
>
> **不是二进制问题，是沙箱权限**：hdc 要把 UDS 绑到 **`/data/hdc/hdc_debug/hdc_server`**，
> 而本沙箱里 **`/data/hdc` 根本不存在** ⇒ `bind()` 返回 **`ret:-13`（EACCES）**。

---

## 1. 找到了 hdc（不在 PATH 里）

| 项 | 值 |
|---|---|
| 路径 | `/data/service/hnp/hmos-clt.org/hmos-clt_1.0.0/sdk/default/openharmony/toolchains/hdc` |
| 大小 | 4,143,296 B |
| 类型 | `ELF shared object, 64-bit LSB arm64, dynamic (/lib/ld-musl-aarch64.so.1), stripped` |
| **可执行性** | ✅ **能跑** |
| 版本 | **`Ver: 3.2.0f`** |
| 同目录 | `hdc`、`hdc_change`（同大小，应为版本切换副本） |
| 是否有服务端可执行 | ❌ 无 `hdcd` |

> `command -v hdc` 为空；`/bin`、`/system/bin`、`/usr/bin`、`/data/service/hnp/bin`、随包 `bin/` 均无 hdc。

---

## 2. 实测结果：命令"成功返回"但**什么都没做**

```text
$ hdc -v
Ver: 3.2.0f                                     ← 二进制正常
$ hdc list targets
(空)
[rc=0]
$ hdc shell echo HDC-OK
(空)
[rc=0]
$ hdc start
(空)
[rc=0]
```

⚠️ **`rc` 恒为 0、输出为空** —— 这是最容易踩的坑：**不能用退出码判断 hdc 是否成功**。
`list targets` 输出 0 字节、`shell` 输出 `[]`，却都返回 0。

---

## 3. 失败根因（hdc 自己的日志给得很清楚）

`~/.hdc/hdc.log`（每次调用都会落一份，01:41–01:42 共 4 份）：

```text
[I] Program running. Ver: 3.2.0f Pid:59603
[D] set UV_THREADPOOL_SIZE:128
[F] libusb_init failed ctxUSB is nullptr                                    ← ① USB 不可用
[F] IsEncryptedPEM:1045 open private key file failed!error code: 1113209355  ← ② 私钥读不到
[F] Initial:378 Listen string initial failed
[W] SetUdsListen:279 bind uds addr fail! ret:-13                            ← ③ UDS 绑定被拒
[F] Initial:386 SetUdsListen failed
[F] InitialServerForClient:93 clsServerForClient Initial failed
[D] main:652 !!!!!!!!!Main finish main
```

| # | 失败点 | 含义 |
|---:|---|---|
| ① | `libusb_init failed ctxUSB is nullptr` | 沙箱拿不到 USB 栈 ⇒ 无法发现 USB 设备 |
| ② | `open private key file failed! error 1113209355` | 读不到 hdc 的认证私钥 |
| ③ | **`bind uds addr fail! ret:-13`** | **`-13 = EACCES`**：UDS 绑定被拒 —— **决定性的那条** |

### 3.1 它想绑到哪里

从二进制里取出的编译期路径：

```text
/data/hdc/hdc_debug/hdc_server            ← 服务端 UDS
/data/hdc/hdc_huks/hdc_credential.socket  ← 凭据 UDS
/tmp/hdc-ut                               ← 单测用
```

实测：

```text
$ ls -la /data/hdc
ls: /data/hdc: No such file or directory
```

⇒ **目录不存在**（属 root/系统侧），沙箱内 `bind()` 必然 EACCES。
（对照：`/tmp` 可写 ✓，`/data/local/tmp` **不可写 ✗**。）

### 3.2 想绕开 UDS 也不行

hdc 的 `-s [ip:]port | uds`（改监听配置）在这个构建里**不支持**：

```text
$ hdc -s 127.0.0.1:18710 list targets
[E001105] Unsupport option [s], please try command in HiShell.
```

⇒ 无法把监听改到 TCP 或可写目录。

---

## 4. 这对测试有什么实际影响

| 场景 | 影响 |
|---|---|
| `hdc install -r`（覆盖率安装） | ❌ 不可用 —— 我这侧无法装包，必须你在 PC 端/应用内执行 |
| `hdc shell hilog -x`（抓 hilog） | ❌ 不可用 ⇒ **启动期崩溃（`docs/350` §4.3 那 8 次 SIGABRT）我定位不了**，仍需你提供 |
| `hdc file recv`（取文件） | ❌ 不可用 —— 但**不阻塞**：我已用 `cp` 把日志拷到 `Download/com.dshm.dshmbeta/logs/`（`docs/350` §3） |
| `hdc list targets` 判断设备在线 | ❌ 无意义（恒空） |

**结论**：凡是要"越过应用沙箱去驱动设备"的能力，本会话里**都没有**；
能做的只有**应用沙箱内**的文件读写与进程视图。

---

## 5. 如果想让它能用（供参考，不建议现在动）

| 方案 | 做法 | 风险/代价 |
|---|---|---|
| A. 用 PC 端 hdc | 在电脑上装 SDK 的 hdc，USB 连设备 | **最标准**；`hilog`、`install`、`file recv` 都能用 |
| B. 让 `/data/hdc` 对应用可见 | 改沙箱/挂载策略 | 触碰权限面（`AGENTS.md`：**不准为排障改权限面**） |
| C. 走应用内已有通道 | 应用已经把日志写到 `Download/<包名>/` | 已有（`docs/350`），够用 |

> 我倾向 **A**：你要的 `hilog.txt` 只有 PC 端 hdc 或 root 终端能拿。

---

## 6. 一句话交接

**HDC 二进制没问题**（`Ver: 3.2.0f`，musl 动态 ELF 能正常执行），
但**它的服务端在沙箱里起不来**：`bind uds addr fail! ret:-13`，
因为它固定要绑 **`/data/hdc/hdc_debug/hdc_server`**，而 **`/data/hdc` 在沙箱里不存在**；
同时 `libusb_init failed`、私钥也读不到，`-s` 选项又不被支持 ⇒ **没有任何绕开路径**。

**所以本会话内 `hdc install / shell / hilog / list targets` 全部不可用**，
且注意 **`rc` 恒为 0、输出为空**，不要用退出码判断成功。

需要 hilog 或装包时，请走 **PC 端 SDK 的 hdc**（USB 连设备），或者用应用内已有通道
（日志我已按 `docs/350` §3 拷到 `Download/com.dshm.dshmbeta/logs/`）。

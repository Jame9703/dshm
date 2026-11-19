# 342 · 内置 tmux / gh（PC 原生 + 移端 guest）—— 规划与施工记录

> 日期：2026-11-02 ｜ 状态：**进行中（本轮完成可行性验证与包采集，未接线）**
>
> 目标：为 `dsh-superagent` 所需的两个环境（`tmux`、`gh`）打通安装路径
> —— **PC/平板走原生内置，手机走 guest 虚拟机内置**，并验证能真正跑起来。

---

## 1. 为什么要做（上游事实）

`dsh-superagent`（GitHub: `deepseek-ai/dsh-superagent-prototype`）是研究原型，
其 `SETUP.md` 的前置探针要求：Node 22.19+/24+、pnpm、git 2.32+、**tmux**、Python 3.8+、
**GitHub CLI 2.48+**，并用 `scripts/dsh-superagent status`（通常基于 tmux 会话）做生命周期管理。

补充事实（已核）：该仓库 `private: true` 且**不含 `lib/` 构建产物**（`main: lib/index.js` 靠 `pnpm build`），
所以它也不能按普通 npm 包安装 —— 本仓只负责**提供它需要的环境**，不负责把它装起来。

## 2. 关键可行性结论（全部实测，2026-11-02）

| 结论 | 证据 |
|---|---|
| **设备有 musl 加载器**，Alpine aarch64 二进制能跑 | 随包 `git` 是 `ELF 64-bit LSB arm64, dynamic (/lib/ld-musl-aarch64.so.1)`，实测 `git version 2.47.3` 正常 |
| **PTY 可用** | `pty.openpty()` 成功，slave `/dev/pts/0`，读写回环 `b'hello\r\n'` |
| **fork 可用** | `os.fork()` + `waitpid` 正常 |
| **Unix socket 可用** | `AF_UNIX` bind 到沙箱 cache 目录成功 |
| **terminfo 存在** | `/usr/share/terminfo`、`/system/usr/share/terminfo` 均在 |
| **设备侧无 CA 信任库** | 常见 4 个路径全无；`ssl` 默认校验直接 `CERTIFICATE_VERIFY_FAILED` |
| **CA 可复用随包 git 那份** | `toolchain/gitroot/etc/ssl/certs/ca-certificates.crt`（181,724 B）；用它拉 Alpine 索引 **HTTP 200** |
| **两端权限差异（决定路径）** | entry 15 条含 `CUSTOM_SANDBOX` / `ALLOW_EXTERNAL_NATIVE_CODE`；**phone 7 条，两条都没有** |
| **包内已有 guest 环境** | `libqemu-system-aarch64.so`、`rootfs_aarch64.qcow2`(53.5 MB)、`kernel_aarch64`(13 MB)、`guestpkgs/`（bash 5.2.37 等） |
| **`dshm-vm-bash` 已启用** | `hostcore/profile/ondevice/cordis.patch.yml:780` |

> ⚠️ **纠正一条旧结论**：此前把「node-pty 不可用」当成「PTY 不可用」。
> 实际是 node-pty 需要 `execve` 同目录的 `spawn-helper`（exec 受限），**PTY 本身是可用的**。

## 3. 方案

### 3.1 PC / 平板（entry）—— 原生内置

与现有 `git`/`python` 工具链**完全同构**：

1. 从 Alpine v3.22 aarch64 采集 `tmux` + 依赖，解到 `toolchain/tmuxroot/`
2. 重打成 `resfile/toolchain/tmux/*.tar.gz`，构建期**自签名 ELF**（复用 `tools/sign-tar-elf.py`）
3. 运行期由 `hostcore/app/main.js` 解包到 `<SANDBOX_HOME>/toolchain/tmuxroot`
4. 布置 `bin/tmux` wrapper（照 `bin/git` 的写法：`LD_LIBRARY_PATH` + `TERMINFO` + exec 真身）
5. `gh` 同理，`toolchain/ghroot/` + `bin/gh`；**CA 复用 gitroot 那份**（`GH_CONFIG_DIR` 单独给）

### 3.2 手机（phone）—— guest 内置

手机端**不能原生 exec**（权限表缺两条），但 guest 是完整 Linux：

1. 把 `tmux` / `github-cli` 及其依赖放进 `resfile/vm/guestpkgs/`
2. guest 启动时按现有机制装入 rootfs（与 `bash-5.2.37-r0.tar.gz` 同一套）
3. 用户经 `dshm-vm-bash` 通道在 guest 里直接用 `tmux` / `gh`

## 4. 已完成（本轮）

**新增采集器**：`tools/fetch-alpine-toolchain.mjs`

- 拉 `main` + `community` 的 `APKINDEX.tar.gz`，做**依赖闭包**解析；
- 关键修正：第一版把 `so:` 依赖直接丢弃 ⇒ 只解析出 4 个包、且缺 `libevent`/`ncurses`。
  现改为**从索引的 `p:`（provides）反查 soname → 提供者**；
- 排除表：`musl` / `git` / `busybox` / `scanelf` / `ca-certificates-bundle`（设备已有，不重复打包）；
- CA 优先用端侧 gitroot 那份（与 git 同源），可用 `DSHM_ALPINE_CA` 覆盖。

**实测产出**（`dist/alpine-stage/`，7 个包，下载 15.9 MB，解出 63 MB）：

| 包 | 版本 | 来源 |
|---|---|---|
| tmux | 3.5a-r1 | main |
| github-cli | 2.72.0-r6（约 40 MB） | community |
| ncurses-terminfo-base | 6.5_p20250503-r0 | main |
| libevent | 2.1.13-r0 | main |
| libncursesw | 6.5_p20250503-r0 | main |
| libcrypto3 | 3.5.9-r0 | main |
| libssl3 | 3.5.9-r0 | main |

## 5. 待办（12:00 后继续）

| # | 事项 | 落点 |
|---|---|---|
| 1 | 采集结果**重打包 + 签名**为 `resfile/toolchain/tmux|gh/*.tar.gz` | 扩 `tools/place-toolchain.mjs` |
| 2 | 运行期解包与 `tmuxReady()/ghReady()` 判据、归档换代重解 | `hostcore/app/main.js`（照 `GIT_ROOT` 三处改） |
| 3 | 布置 `bin/tmux`、`bin/gh` wrapper | 同上（照 `bin/git` 写法） |
| 4 | guest 侧：把包塞进 `resfile/vm/guestpkgs/` | 纯物料 |
| 5 | 门禁：ELF 签名、可执行性、包体上限 | `tools/check-*` |
| 6 | 真机验证：PC `tmux -V`/`tmux new -d`；手机 guest 内同测 | 需设备 |

## 6. 代价与风险

| 项 | 说明 |
|---|---|
| **包体** | +约 48 MB 未压缩（gh 占 40 MB）；压缩打包后预计 +20~25 MB。当前包 507 MB |
| **风险 1** | `gh` 是动态链接（依赖 `libssl3`/`libcrypto3`），**必须**把这几个 .so 一起带，否则端侧 `Error loading shared library` |
| **风险 2** | `gh auth login` 默认走浏览器 device flow；端侧应改用 `gh auth login --with-token` |
| **风险 3** | tmux 默认 socket 目录在 `/tmp` 或 `$HOME`，沙箱下需显式 `TMUX_TMPDIR` 指向可写目录 |
| **风险 4** | 装了 tmux/gh **仍不等于** superagent 能跑：它还缺独立 profile、3082 端口、`pnpm build`、管理 API |

## 7. 恢复入口

```bash
# 采集（幂等，可重复跑）
node tools/fetch-alpine-toolchain.mjs --out dist/alpine-stage
# 只解析依赖不下载
node tools/fetch-alpine-toolchain.mjs --dry-run
```


---

## 8. 2026-11-02 13:00 追加：签名阻塞已解除（含一条我自己的错判）

### 8.1 先纠正一个概念混淆

「AGC 包能编译」与「工具链 ELF 能签名」是**两套工具**：

| 用途 | 工具 | 本机状态 |
|---|---|---|
| APP/HAP 包签名（每天都在跑） | hvigor 内置签名 → **`hap-sign-tool`（原生）** | ✅ 正常，从不碰 java |
| 随包 ELF 自签名（工具链） | **`binary-sign-tool`** | ✅ 原生工具在，只是调用姿势写错/未接 |

⇒ `tools/build-agc.mjs` **根本不调 `place-toolchain`**（grep 0 命中），
所以这几天出包从没走到 ELF 签名那一步 —— 归档是历史上（Windows + JDK 时代）
签好后留在 `third_party/` 的。我要**新增** tmux/gh 归档，才第一次在本机触发这条路径。

### 8.2 我上一轮说「签不了」是错的

我试了 `sign -mode localSign …`、`localSign`、`sign-elf`、`elfsign`、`signhap` 等 6 种，
全报 `is not trust command`，于是下了"本机没签名能力"的结论 —— **结论错了**。

真正的原因是**参数顺序**：原生工具解析严格，`-selfSign` 必须放在 `-inFile/-outFile` **之后**，
且**不能带** jar 专有的 `-mode localSign` / `-signAlg`。正确形式：

```bash
binary-sign-tool sign -inFile <in> -outFile <out> -selfSign 1
# → add codesign section success / write code sign data success
binary-sign-tool display-sign -inFile <out>
# → permission is not found / code signature is self-sign
```

### 8.3 已改的两处

1. `tools/place-toolchain.mjs`：`findBinarySignTool()` 改为**原生优先**（旧实现只认 `.jar` + `java`，
   而本机既无 jar 也无 JDK ⇒ 永远走"跳过签名"）。`docs/225` 记着这条曾修过，但代码里没留下，现补回。
2. `tools/sign-tar-elf.py`：按"路径是否以 `.jar` 结尾"分派两种调用形态（原生 / jar）。

### 8.4 实测结果

```
resign: tmux-alpine.tar.gz        signed 1/1 ELF
resign: libevent-alpine.tar.gz    signed 5/5 ELF
resign: libncursesw-alpine.tar.gz signed 1/1 ELF
resign: github-cli-alpine.tar.gz  signed 1/1 ELF
resign: libssl3-alpine.tar.gz     signed 1/1 ELF
resign: libcrypto3-alpine.tar.gz  signed 6/6 ELF
sign  : tmux=dshm-signed-v1+823237  gh=dshm-signed-v1+15860907
```

从归档里取出真身复核：
`usr/bin/tmux`（800,384 B）与 `usr/bin/gh`（40,949,696 B）均为 **`code signature is self-sign`**。

### 8.5 剩余

`main.js` 接线（`TMUX_ROOT`/`GH_ROOT` 解包 + `bin/tmux`/`bin/gh` wrapper）尚未做；
当前 `resfile/toolchain/{tmux,gh}` 已就位（约 +17 MB），但端侧还不会解包使用。


---

## 9. 2026-11-02 13:20 · PC 侧接线完成并出包

### 9.1 代码改动（`hostcore/app/main.js`）

| 位置 | 改动 |
|---|---|
| 常量 | 新增 `TMUX_ROOT` / `GH_ROOT` + 表驱动 `EXTRA_TOOLCHAINS`（name/root/probe 三元组） |
| 就绪判据 | `extraReady(spec)` —— 只看"真身在不在"，与 `gitReady()` 同口径 |
| 解包 | `scheduleToolchainExtraction` 里按 root 独立算 `need`/`stale`，`tar xmzf` 到各自 root，再 `chmod 755` 真身 |
| wrapper | `toolchainWrapperScript` 新增 `tmux`/`gh` 分支；`names` 列表按 resfile 是否带该目录**动态**追加 |

wrapper 的端侧要点（都写进注释了）：
- **tmux**：显式 `TMUX_TMPDIR`（默认 `/tmp` 在端侧不可写，否则 `tmux new` 直接 "server exited unexpectedly"）；`TERMINFO` 指向随包 `ncurses-terminfo-base`。
- **gh**：复用 gitroot 的 CA（`SSL_CERT_FILE` / `CURL_CA_BUNDLE`）—— 端侧没有系统信任库。

### 9.2 两个被我这次改动踩红的门禁（已修）

1. **`check-no-apk-surface`**：`dist/alpine-stage/*.apk` 扩展名命中。改 `fetch-alpine-toolchain.mjs` 为**解包后即删 .apk**。
2. **`check-mobile-upgrade-migration`**：`entry/libs/arm64-v8a/libpython3.12.so.1.0` 重复携带（+22MB）。
   根因是 `place-toolchain` 里那段"el1 dlopen 通道"仍在往 entry 写，而判据早就改成"HSP 只一份"。已删该段。

### 9.3 一个更隐蔽的错误：工具链放错了模块

`place-toolchain` 的 `DEST` 原本指向 **entry** 的 resfile，而端侧 `main.js` 的
`RES_ROOT = resolve(__dirname,'..','..')` —— main.js 装在 **HSP** 里 ⇒ 它读的是 HSP 的 resfile。
第一版把 tmux/gh 放进 entry，包能出、端侧**永远找不到**（且 entry 还多背了 26.4MB python 副本）。
已把 `DEST` 改到 `hostruntime/src/main/resources/resfile/toolchain`，并把跑错的副本清掉。

### 9.4 最终包（PC 侧 tmux/gh 已可用）

```
dist/release-test/dshm-1.1.7-1010008-dshm.105-AGC-invite-20261102T051823.app
sha256  bb5f78367e8a5347bb7738466dc13d55f5bf646fa3ff1427f0ce33a8ff5dcaa4
大小    524,345,782 B     （基线 507,650,930 B ⇒ +16.7MB，恰为 tmux 0.8 + gh 15.9）
签名    verify-app success（证书链/Profile 与上一版逐字节一致）
门禁    15 道全绿
包内    hostruntime.hsp: tmux 归档 5 / gh 归档 4 / libpython 1；entry 与 phone 均为 0
```

### 9.5 仍未做

**手机 guest 侧**（§5 第 4 项）：尚未把 tmux / github-cli 的 apk 放进 `resfile/vm/guestpkgs/`。
手机端 `tmux` / `gh` 目前**不存在**（手机不 exec 随包 ELF，必须走 guest）。

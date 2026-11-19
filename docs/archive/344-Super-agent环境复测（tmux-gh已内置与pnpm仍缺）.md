# 344 · Super-agent 环境复测（侧载包已内置 tmux/gh · 剩 pnpm 与两处接线）

> 日期：2026-11-02 19:00 ｜ 检测人：AI 助手（只读为主 + 一处设备侧临时修复，见 §5）
>
> 用户口径：「开发端编译了侧载包，测试一下现在 super agent 的环境可以了没」
>
> 前序：[`343`](343-Super-agent环境检测与可修性评估（pnpm构建gh三缺口与平台硬约束）.md)（首测，4 缺口）、
> [`342`](342-内置tmux与gh（PC原生与移动端guest）规划与施工.md)（tmux/gh 内置方案）。
>
> 环境变更：核心树 `0.2.1-rc.4+dshm.97` → **`0.2.1-rc.5+dshm.106`**；宿主 pid 41314（18:56 重启）。

---

## 0. 结论：**还差一步（pnpm），其余已就绪**

| 官方要求（`SETUP.md` §1） | 首测（343） | 本次实测 | 判定 |
|---|---|---|---|
| Node 22.19+ / 24+ | v24.2.0 | **v24.2.0** | ✅ |
| **pnpm** | 假壳 | **仍是假壳** `10.0.0 (dshm install-queue shim)` | ❌ **唯一硬缺口** |
| git 2.32+ | 2.47.3 | **2.47.3** | ✅ |
| **tmux** | 缺失 | **`tmux 3.5a`**（须补链接，见 §2） | 🟡 **已内置，有打包缺陷** |
| Python 3.8+ | 3.12.14 | **3.12.14** | ✅ |
| **GitHub CLI 2.48+** | 缺失 | **`gh 2.72.0`** | ✅ **已内置** |
| dsh（`engines.dsh ^0.2.1-alpha.2`） | rc.4 | **真身 `0.2.1-rc.5`**；PATH 仍是假壳 | 🟡 见 §3 |
| `lark-cli`（仅飞书） | 缺失 | 缺失 | 🟡 可选 |

**⇒ 开发端这一版把 tmux 与 gh 都内置了，方向正确。**
**但离"能装 superagent"还差 3 件事**：① 真 pnpm ② `dsh` 命令要能转发真身 ③ `ps` 支持（控制脚本）。

---

## 1. 本次实测读数（官方 probe 原样）

```text
node -v            → v24.2.0
pnpm -v            → 10.0.0 (dshm install-queue shim)      ← 假壳
git --version      → git version 2.47.3
tmux -V            → tmux 3.5a                              ← 新！需补链接后才可用
python3 --version  → Python 3.12.14
gh --version       → gh version 2.72.0 (2026-01-15)         ← 新！直接可用
dsh --version      → dsh 0.1.7-rc.1 (dshm install-queue shim)
```

版本约束核对：

| 约束 | 要求 | 实测 | 判定 |
|---|---|---|---|
| `engines.node` | `^22.19.0 \|\| >=24.0.0` | v24.2.0 | ✅ |
| `engines.dsh` | `^0.2.1-alpha.2` | 核心树 **0.2.1-rc.5** | ✅ |

---

## 2. 🟡 tmux：内置成功，但**库的 SONAME 链接丢了**（关键发现）

### 2.1 现象：包装器报"execve 被拒"，**但那是误判**

```text
$ tmux -V
tmux：该设备系统策略禁止运行第三方原生二进制（execve 被拒），暂不可用
```

### 2.2 真实原因：**不是权限，是缺符号链接**

绕过包装器直接执行真身：

```text
$ LD_LIBRARY_PATH=$T/usr/lib $T/usr/bin/tmux -V
Error loading shared library libevent_core-2.1.so.7: (needed by …/usr/bin/tmux)
Error relocating …: tiparm_s: symbol not found
```

目录里**有**库、但**没有 SONAME 软链**：

| 实际文件（存在） | 程序需要（缺失） |
|---|---|
| `libevent_core-2.1.so.7.0.2` | **`libevent_core-2.1.so.7`** |
| `libncursesw.so.6.5` | **`libncursesw.so.6`** |

`tmux` 的 NEEDED（`strings` 实读）：`libc.musl-aarch64.so.1`、`libevent_core-2.1.so.7`、`libncursesw.so.6`。
`tiparm_s` 符号**确实在** `libncursesw.so.6.5` 里（`strings` 命中），纯粹是找不到文件。

### 2.3 验证：补上链接后**完全可用**

```sh
cd .../toolchain/tmuxroot/usr/lib
for p in libevent-2.1.so.7 libevent_core-2.1.so.7 libevent_extra-2.1.so.7 \
         libevent_openssl-2.1.so.7 libevent_pthreads-2.1.so.7; do
  ln -s "$p.0.2" "$p"
done
ln -s libncursesw.so.6.5 libncursesw.so.6
```

补完后实测**全绿**：

```text
tmux -V                          → tmux 3.5a                    ✓
tmux new-session -d -s t -c /tmp 'sleep 8'  → rc=0               ✓
tmux has-session -t =t           → rc=0                         ✓
tmux ls                          → t: 1 windows (created …)     ✓
tmux kill-session -t =t          → rc=0                         ✓
```

⇒ **tmux 能力本身没问题**，缺的是打包时保留 SONAME 链接。

### 2.4 给开发端的三个修点

1. **打包/解包时保住软链**：`AGENTS.md` 已警告「Windows tar 会破坏 symlink」——
   `bsdtar` 丢弃、`7z` 物化。本次现象正是**链接被丢**（不是被物化，否则会有同名副本）。
   建议：用 Python `tarfile` 打/解（本仓既有做法），或打包后断言
   `tar tzvf` 里 `libevent_core-2.1.so.7 -> …` 是**链接项**。
2. **加一条门禁**：解包后断言
   `[ -e .../usr/lib/libevent_core-2.1.so.7 ] && [ -e .../usr/lib/libncursesw.so.6 ]`，
   比"tmux -V 能不能跑"更早暴露问题。
3. **修掉包装器的误报**（这条最容易误导排障）：现在任何执行失败都归因成
   "该设备系统策略禁止运行第三方原生二进制（execve 被拒）"。
   实测真实原因是缺库 ⇒ 应把 `exec` 的真实 stderr 透传出来（哪怕只带第一行），
   否则排障方向会被带歪 —— 与 `docs/294` 修掉的 `npm list` 误报是同一类问题。

> **持久性提醒**：三个 root（`gitroot`/`ghroot`/`tmuxroot`）都是 18:56 首次解包的，
> 说明**归档换代才会重解**。我 18:58 补的链接**能扛普通重启**，
> 但**下次工具链换版会被覆盖** ⇒ 必须在打包源头修。

---

## 3. 🟡 `dsh` 命令：真身在，但 PATH 上不转发

| 项 | 实测 |
|---|---|
| PATH 上的 `dsh` | 安装队列假壳，只认 `plugin install/remove/allow-version/version-exemptions` |
| `dsh superagent --dump-config` | `dsh(shim): …（收到：superagent --dump-config）` ⇒ **不转发** |
| 真身可用性 | `node <core>/lib/bin.js --version` → **`0.2.1-rc.5`** ✅ |

**影响**：`SETUP.md` 第 4/5 条命令依赖 `dsh`：

```sh
dsh superagent --from-default-profile web --dump-config > /dev/null
dsh plugin --profile superagent add "link:$PWD"
```

**现状**：第一条假壳直接拒绝；第二条即使转发到真 dsh，也会落到 DSHM 的 pnpm 假壳上
（`docs/343` §2.3 已实测：`link:` 形式被拒）。

**建议**：给 `dsh` 假壳加转发 —— 只拦截 `plugin <sub>`，其余参数 `exec` 真 dsh：

```sh
case "$1" in
  plugin)  # 保持现有安装队列投递
           ;;
  *)       exec node "$CORE/node_modules/@deepseek-ai/dsh/lib/bin.js" "$@" ;;
esac
```

> ⚠️ 但**转发真 dsh 并不能让它启动**：裸 node 起 profile 仍会失败（§4）。

---

## 4. ❌ 两处平台约束未变（与 `docs/343` §3 一致）

### 4.1 原生 `.node` 仍加载不了

```text
$ node -e "require('<core>/node_modules/node-addon-require-builtin')"
✗ No usable native binding found for node-addon-require-builtin-openharmony-arm64 (auto)
```

⇒ **构建仍必须走 `tsc` + `esbuild-wasm`**（`docs/343` §2.2 已实测通过），
rolldown/tsdown 的原生绑定依旧不可用。

### 4.2 裸 node 起 profile 仍不可行

`--dump-config` 能出配置（只组合、不启动），但**真正 boot 仍在 host preparation 处失败**
（同一原生 addon，`docs/343` §3.1 已实测报错）。

⇒ **必须走 DSHM 宿主的 jitless 垫片栈**，用 `DSHM_PROFILE` / `DSHM_PORT` 选 profile
（`hostcore/app/main.js:1431-1432`）。

> 附带一个观察（供参考，未展开）：裸 node 跑 `--profile ondevice --dump-config` 时，
> 报了 3 条 `patch: entry "terminal-bash"/"terminal-pwsh"/"optional-persistent-terminals" not found` ——
> 那是 DSHM 注入项在宿主外不存在导致的，**不影响 superagent 的独立 profile**，此处仅记录。

---

## 5. ⚠️ 我做的设备侧改动（**一处，可回退**）

| 改动 | 位置 | 原因 | 持久性 |
|---|---|---|---|
| 建 6 个 SONAME 软链 | `toolchain/tmuxroot/usr/lib/` | 验证 §2 的诊断（不经此步 tmux 不可用） | 扛普通重启；**换工具链版本会被覆盖** |

```sh
# 回退（如需恢复到开发端交付时的原状）
rm -f .../toolchain/tmuxroot/usr/lib/{libevent-2.1.so.7,libevent_core-2.1.so.7,\
libevent_extra-2.1.so.7,libevent_openssl-2.1.so.7,libevent_pthreads-2.1.so.7,libncursesw.so.6}
```

**未改动**：`ondevice` profile、宿主进程、用户数据、源码。

---

## 6. 还缺什么（按优先级）

| # | 事项 | 归谁 | 说明 |
|---:|---|---|---|
| 1 | **真 pnpm** | 开发端（建议内置）或按 `343` §2.1 自取 | **唯一的功能硬缺口**；不解决 `pnpm install/build` 全部无法进行 |
| 2 | **tmux SONAME 链接** | 开发端（打包） | 见 §2.4；当前靠我临时补 |
| 3 | **`dsh` 转发真身** | 开发端 | 见 §3 |
| 4 | **`ps -o` 支持** | 开发端 | 控制脚本 `start/status` 用 `ps -ww -o pid=,ucomm=,args=` 与 `ps -ax`；toybox/busybox **都不支持**，无 `bin/ps` |
| 5 | **gh 登录** | **操作端** | `gh auth status` → `not logged into any GitHub hosts`；需**专用 Agent 账号**的 token（`gh auth login --with-token`） |
| 6 | 仓库 + 白名单 | 操作端 | github.com 仓库（不支持 GHES）、允许提问的账号列表 |
| 7 | `lark-cli` | 操作端（仅飞书） | 选 GitHub-only 可跳过 |

---

## 7. 判定

> **"环境可以了没"** —— **接近了，但还不能。**
>
> **已就绪**：node / git / python3 / **gh 2.72.0** / **tmux 3.5a**（补链接后）/ 网络 / dsh 核心版本。
> **卡点**：**`pnpm` 仍是假壳** —— 这是唯一一个"挡住全部后续步骤"的硬缺口，
> 因为 superagent 仓库不含构建产物（`main: lib/index.js`），**没有 pnpm 就一步都走不了**。
>
> **一旦 pnpm 就位**，按 `docs/343` 已验证的路径即可推进：
> 真 pnpm → `tsc` + `esbuild-wasm` 构建 → profile 内 `pnpm add -w link:` → 宿主 `DSHM_PROFILE=superagent` 启动。

---

## 8. 一句话交接

**开发端把 tmux 与 gh 都内置进包了，实测 `gh 2.72.0` 直接可用、`tmux 3.5a` 补上 6 个 SONAME 软链后
新建/查询/终止会话全通** —— 但打包**丢了 symlink**，且包装器把"缺库"**误报成"execve 被拒"**
（建议改成透传真 stderr，否则排障会被带歪）。

**真正还差的只有一件：真 pnpm**（PATH 上仍是 `dshm install-queue shim`）。
另有两处接线待补：`dsh` 命令要转发真身、`ps` 要支持 `-o`（控制脚本依赖）。
gh 已可用但**未登录**，需你用**专用 Agent 账号**跑 `gh auth login --with-token`。

平台两个硬约束（原生 `.node` dlopen、裸 node 起不了 profile）**未变**，
所以构建仍走 `tsc + esbuild-wasm`、启动仍走 DSHM 宿主 `DSHM_PROFILE`。

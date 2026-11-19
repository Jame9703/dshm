# 345 · Super-agent 环境复测（二）：tmux/ps/dsh 三项已修 · **只剩 pnpm**

> 日期：2026-11-02 19:30 ｜ 检测人：AI 助手（**本次无任何设备侧改动**）
>
> 用户口径：「再复测一次」
>
> 前序：[`344`](344-Super-agent环境复测（tmux-gh已内置与pnpm仍缺）.md)（复测一）、
> [`343`](343-Super-agent环境检测与可修性评估（pnpm构建gh三缺口与平台硬约束）.md)（首测）。
>
> 环境变更：核心树仍 `0.2.1-rc.5+dshm.106`；宿主 19:27:48 重启（pid 4236）；**工具链 19:27:37 重新解包**。

---

## 0. 结论：**上轮 4 个待办修了 3 个，只剩 pnpm**

| 官方要求 / 上轮问题 | 上轮（344） | 本次实测 | 判定 |
|---|---|---|---|
| Node 22.19+ / 24+ | v24.2.0 | **v24.2.0** | ✅ |
| git 2.32+ | 2.47.3 | **2.47.3** | ✅ |
| Python 3.8+ | 3.12.14 | **3.12.14** | ✅ |
| gh 2.48+ | 2.72.0（未登录） | **2.72.0**（仍未登录） | ✅ / 登录待操作端 |
| tmux | 3.5a，**缺 SONAME 软链**（靠我临时补） | **3.5a，打包已修**（不依赖我的补丁） | ✅ **已修** |
| `ps -o` / `ps -ax` | **不支持** | **支持**（新增 `bin/ps` 垫片 893 B） | ✅ **已修** |
| `dsh` 命令 | **假壳，不转发** | **转发真身**（`dsh 0.2.1-rc.5` 真用法） | ✅ **已修** |
| **`pnpm`** | 假壳 | **仍是假壳**（`install`/`run` 都不支持） | ❌ **唯一硬缺口** |
| `lark-cli`（仅飞书） | 缺失 | 缺失 | 🟡 可选 |
| 原生 `.node` 加载 | 不可 | **仍不可**（平台约束未变） | ❌ 平台限制 |

> **⇒ 现在离"能装 superagent"只差一样：真 pnpm。**

---

## 1. 本次实测读数（官方 probe 原样）

```text
node -v            → v24.2.0
pnpm -v            → 10.0.0 (dshm install-queue shim)      ← 仍是假壳
git --version      → git version 2.47.3
tmux -V            → tmux 3.5a                              ← 打包已修
python3 --version  → Python 3.12.14
gh --version       → gh version 2.72.0 (2026-01-15)
dsh --version      → dsh 0.1.7-rc.1 (shim)                  ← 版本串仍是 shim，但下面 §3 证明它已转发
```

---

## 2. ✅ tmux：开发端把软链**物化成了真实文件**（不再依赖我的补丁）

**关键验证**：本次 `tmuxroot` **19:27:37 重新解包**，我上轮补的 6 个软链**已不存在**，
而 tmux **依然可用** ⇒ 是开发端在打包侧修好了。

解包后 `usr/lib` 里现在是**成对的真文件**（不是软链）：

```text
libevent-2.1.so.7          337472 B   ← 与下一行同大小
libevent-2.1.so.7.0.2      337472 B
libevent_core-2.1.so.7     206400 B   ← 与下一行同大小
libevent_core-2.1.so.7.0.2 206400 B
libncursesw.so.6           403008 B   ← 与下一行同大小
libncursesw.so.6.5         403008 B
```

**这是"软链被物化成副本"**（`7z` 式行为）—— 功能上等价，代价是多占约 1.2 MB。

**功能实测（全绿）**：

```text
tmux -V                                     → tmux 3.5a      ✓
tmux new-session -d -s t2 -c /tmp 'sleep 5' → OK             ✓
tmux has-session -t =t2                     → OK             ✓
tmux kill-session -t =t2                    → OK             ✓
```

> **遗留小建议**（不影响可用性）：物化后体积翻倍，若能保住软链更省；
> 若刻意选择物化，建议在打包处加一行注释说明这是**有意为之**，
> 免得后人当 bug "优化"回去。

---

## 3. ✅ `dsh` 已转发真身（这个改动解决了官方安装第 4/5 条命令）

```text
$ dsh --help
Usage: dsh [--profile] <name> [options] [app-args...]
       dsh plugin --profile <name> <pnpm-args...>
Arguments: …            ← 真 dsh 的完整用法（不再是 shim 提示）

$ dsh superagent --dump-config
Error: profile "superagent" does not exist;
       create it with 'dsh plugin --profile superagent add <package>'
                        ← 已跑进真 dsh 逻辑（profile 不存在，符合预期）
```

⇒ 官方 `dsh superagent --from-default-profile web --dump-config` 现在**可以真跑**。

---

## 4. ✅ `ps`：补了垫片，控制脚本的两个原语都通了

```text
ps -ww -o pid=,ucomm=,args=  → OK ✓
ps -ax                        → OK ✓
```

`bin/ps` 垫片：893 B，2026-11-02 19:27。

**并且我实测了 `scripts/dsh-superagent` 真正依赖的两个原语**：

| 原语 | 实测结果 |
|---|---|
| `tmux new-session -d -P -F '#{pane_pid}' -n server -c <cwd> <cmd>` | **`pane_pid=5599`**（纯数字，脚本 `pane.isdigit()` 判据通过）✓ |
| `ps -ww -o pid=,ucomm=,args=` | 输出 `pid ucomm args` 三段，`line.split(None, 2)` 可解析 ✓ |

⇒ **官方控制脚本 `start/status/stop` 的前置条件已满足**（除 §5 的 pnpm）。

---

## 5. ❌ 唯一硬缺口：`pnpm` 仍是假壳

```text
$ pnpm install            （裸命令，仓库构建必需）
pnpm(shim): 请给出包名或 GitHub 地址（端侧不支持无参 install）

$ pnpm run build
pnpm(shim): 端侧只收 add/install <包名|GitHub地址> 或 rm <包名>（收到：run）
```

**为什么这是硬缺口**：superagent 仓库**不含构建产物**（`main: lib/index.js`），
必须 `pnpm install && pnpm build` 才能得到 `lib/`。
没有真 pnpm ⇒ **安装与构建一步都走不了**，后面 profile 安装也跟着断。

**两条解法**（任选，`docs/343` §2.1 已验证可行性）：

**方案 A（推荐，开发端内置）**：照 tmux/gh 的同一套，把 pnpm 也内置。
pnpm 是**纯 JS**，不需要 ELF 签名、不需要跨平台绑定，比 tmux/gh 简单得多：

- 采集：从 registry 取 `pnpm-<ver>.tgz`（4.3 MB 包，解出 `bin/pnpm.cjs`）
- 落位：`toolchain/pnpmroot/`（或直接 `resfile/pnpm/`）
- 包装器：`bin/pnpm` → `exec node <pnpmroot>/bin/pnpm.cjs "$@"`（node 已在 PATH）
- 注意：**必须让 `pnpm` 与 `npm` 分开**（现有 `bin/npm` 是安装队列假壳，D8 渠道不能动）

**方案 B（不改包，手动）**：按 `docs/343` §2.1 自己取一份纯 JS pnpm 放 `~/.local/bin`，
并把该目录**前置**到 PATH。缺点：非交付形态、换机要重做。

---

## 6. ❌ 平台两约束未变（不影响"环境就绪"判定，但影响做法）

| 约束 | 实测 | 后果 |
|---|---|---|
| 原生 `.node` 加载 | `No usable native binding found for node-addon-require-builtin-openharmony-arm64` | `pnpm build`（tsdown/rolldown）**永远不可用** ⇒ 构建必须走 **`tsc` + `esbuild-wasm`**（`docs/343` §2.2 已实测出全套产物） |
| 裸 `node` 起 profile | 仍会在 host preparation 处失败（同一 addon） | 启动必须走 **DSHM 宿主 + `DSHM_PROFILE`/`DSHM_PORT`** |

---

## 7. 操作端（只有你能做）

| # | 事项 | 现状 |
|---:|---|---|
| 1 | **gh 登录**（专用 Agent 账号） | `gh auth status` → **not logged into any GitHub hosts** |
| 2 | 仓库（github.com，不支持 GHES） | 待定 |
| 3 | 允许提问的账号白名单 | 待定 |
| 4 | 飞书（可选） | 缺 `lark-cli` |

---

## 8. 判定

> **"环境可以了没"** —— **除 pnpm 外，全部就绪。**
>
> 本轮开发端修好了三处（tmux 打包软链、`ps -o`、`dsh` 转发），
> 加上上轮已内置的 `gh 2.72.0`，**官方 probe 的 7 项里已有 6 项通过**（node/git/tmux/python3/gh/dsh）。
>
> **唯一未过的是 `pnpm`** —— 而它是"卡住全部后续步骤"的那一项：
> 没有它，`pnpm install && pnpm build` 跑不了 ⇒ `lib/` 出不来 ⇒ profile 装不上。
>
> **一旦 pnpm 就位，按已验证路径即可推进**：
> `pnpm install` → `tsc` + `esbuild-wasm` 出 4 入口 → `pnpm add -w link:` 装进 profile
> → `DSHM_PROFILE=superagent DSHM_PORT=3082` 由宿主启动 → `curl /orchestrator/api/state` 判健康。

---

## 9. 一句话交接

**这版修得很到位**：tmux 重新解包后软链已物化成真文件（不再依赖我上轮的临时补丁），
`ps -o`/`-ax` 有了垫片，`dsh` 也真的转发到 `0.2.1-rc.5` ——
我实测了控制脚本真正依赖的两个原语（`tmux -F '#{pane_pid}'` 拿到纯数字 pid、`ps -o` 输出三段可解析），**都通**。

**只剩 `pnpm`**：仍是 `dshm install-queue shim`，`pnpm install` / `pnpm run build` 都被拒。
它是纯 JS，内置起来比 tmux/gh 简单（无需 ELF 签名），建议照同一套加 `toolchain/pnpmroot` + `bin/pnpm`，
但**别动现有 `bin/npm`**（那是安装队列渠道）。

平台约束两条照旧：`.node` 加载不了 ⇒ 构建走 `tsc`+`esbuild-wasm`；裸 node 起不了 profile ⇒ 启动走 `DSHM_PROFILE`。

**gh 已可用但未登录**，需要你用专用 Agent 账号跑一次 `gh auth login --with-token`。

# 2in1 终端 bash 崩溃修复（TERMINFO 路径）与上游 rc.2 状态

> 日期：2026-11-11 22:30–23:00
> 输入：`~/Download/dsh-shell-diagnosis.log`（2026-11-11 22:23 生成）
> 范围：2in1 原生终端（entry 壳）交互式 bash / tmux；task-state 兼容副本刷错；上游 dsh 版本核对

---

## 0. 结论

| 项 | 结果 |
|---|---|
| 崩溃根因 | **TERMINFO 指错目录**：Alpine 的 `ncurses-terminfo-base` 装到 `etc/terminfo`，wrapper 写的是 `usr/share/terminfo`（不存在） |
| 影响 | `TERM=xterm-256color` 时交互式 bash 6 次里 5 次 `SIGSYS(-31)` 静默退出；tmux 同类（`terminal not found`） |
| 修复 | bash / tmux wrapper 双路径探测 terminfo，并按 TERM 条目是否存在回退 `xterm` |
| 附带修复 | 2in1 上 `files/` 根只读导致 `task-state.json` 兼容副本每 turn 刷 EACCES ⇒ 改为探测一次、不可写就跳过 |
| 新门禁 | `check-bash-terminfo`（4 变异）、`check-task-state-compat`（3 变异） |
| 上游 | GitHub 已有 **dsh-v0.2.2-rc.2** 标签，但 **npm 未发布**（`latest`/`next` 仍 `0.2.2-rc.1`）；端侧核心只能从 npm 物化，**本轮无法合入** |

---

## 1. 诊断日志读到的三件事

### 1.1 `TERM=xterm-256color` 下 bash 被 SIGSYS 杀死

```
TERM=xterm-256color  启动成功 1/6   ['-31','alive','-31','-31','-31','-31']
TERM=xterm           启动成功 6/6
TERM=screen/linux/vt100 启动成功 6/6
terminfo 数据库 bashroot/usr/share/terminfo 存在: False
```

- 同一二进制、同一沙箱，只有 `xterm-256color` 稳定死 ⇒ 不是权限、不是 execve，而是**终端能力库**路径。
- 查随包归档：`hostruntime/src/main/resources/resfile/toolchain/bash/ncurses-terminfo-base-alpine.tar.gz`
  的真实布局是 **`etc/terminfo/x/xterm-256color`**（Alpine 约定），`usr/share/terminfo` 根本不存在。
- 旧 wrapper 把 `TERMINFO` 指向不存在的 `usr/share/terminfo` ⇒ 查不到条目；`xterm-256color`
  走的是与 `xterm` 不同的初始化分支，最终被内核以 SIGSYS 终止（其余 TERM 有内建兜底，所以活着）。

### 1.2 直接执行真 bash 缺库

`[5]` 段：不经 wrapper 直接跑 `bashroot/bin/bash` 报 `libreadline.so.8` 缺失 —— 这是**预期行为**，
wrapper 负责自举 `LD_LIBRARY_PATH`，不属于缺陷。

### 1.3 `task-state` 兼容副本 EACCES

```
task-state: 兼容副本写失败（不影响主链路）：EACCES: permission denied, open '../task-state.json'
```

- 兼容副本路径 = `files/task-state.json`（`DSH_BASE/../task-state.json`），主链路是 `dsh/home/task-state.json`。
- 2in1 上 `files/` 根目录对宿主进程只读 ⇒ 每次 turn 都失败一次并写日志，纯噪音。

---

## 2. 修复

### 2.1 bash wrapper（`hostcore/app/main.js`）

```sh
_ti=""
if [ -d "$R/etc/terminfo" ]; then _ti="$R/etc/terminfo"
elif [ -d "$R/usr/share/terminfo" ]; then _ti="$R/usr/share/terminfo"; fi
if [ -n "$_ti" ]; then TERMINFO="$_ti"; export TERMINFO; fi
if [ -n "$TERM" ]; then
  _fc=${TERM%${TERM#?}}
  if [ -z "$_ti" ] || [ ! -e "$_ti/$_fc/$TERM" ]; then TERM=xterm; export TERM; fi
fi
```

- **优先 `etc/terminfo`**（真实位置），保留 `usr/share/terminfo` 兼容旧归档；
- 当前 TERM 在库里没有条目（或库整个缺失）时退到 `xterm` —— 日志实测 xterm 6/6 成功。

### 2.2 tmux wrapper（同一文件）

同样的双路径探测与 TERM 回退。tmux 缺条目会直接报 `terminal not found`，与 bash 同源。

### 2.3 task-state 兼容副本

新增 `compatWritable()`：用 `fs.accessSync(dir, W_OK)` 探测一次并缓存；不可写时整轮跳过，
只记一条 `task-state: 兼容副本跳过（目录不可写，只有主链路）`。主链路写入逻辑未动。

---

## 3. 门禁

| 门禁 | 判据 | 自检 |
|---|---|---|
| `tools/check-bash-terminfo.mjs` | 两个 wrapper 必须探测 `etc/terminfo`、保留 `usr/share` 兜底、含 `TERM=xterm` 回退；三处随包归档必须真有 `etc/terminfo/x/xterm-256color` 与 `xterm` | 4 变异全红（回退旧写法 / 去掉 bash 回退 / 去掉 tmux 回退 / 归档缺 xterm） |
| `tools/check-task-state-compat.mjs` | 兼容副本写入必须在 `if (compatWritable())` 之下；必须 `W_OK` 探测并缓存 | 3 变异全红（去判定 / 改 F_OK / 去缓存） |

两条都已接入 `.github/workflows/gates.yml`。归档检查用 Node 自带的 `zlib` 解析 tar，
不依赖系统 `tar`，离线可跑。

---

## 4. 上游 dsh：rc.2 为什么这轮合不进来

### 4.1 事实

- GitHub 仓库 `deepseek-ai/deepseek-harness` 已有标签 **`dsh-v0.2.2-rc.2`**，根 `package.json`
  `"version": "0.2.2-rc.2"`，`engines.node >= 24.9.0`（本机满足）。
- npm 侧（`registry.npmjs.org` 与 npmmirror 双查）：
  - `dist-tags`：`latest = 0.2.2-rc.1`、`next = 0.2.2-rc.1`、`alpha = 0.2.2-alpha.3`
  - `0.2.2-rc.2`：**不存在**；registry `time.modified = 2026-11-05`
- GitHub 源码归档可直接下载（`codeload`，41 MB / 23,924 个文件），但**不含任何构建产物**
  （`/dist/` 0 个、`node_modules` 0 个），是 pnpm monorepo 源码。

### 4.2 为什么不能从源码直接物化

端侧核心树由 `tools/pack-core.mjs` 用 **npm install `@deepseek-ai/dsh@<version>`** 物化
（`--os=openharmony --cpu=arm64` + 三个原生移植 overrides）。GitHub 标签只有源码：

- 需要 `pnpm@11.28.5` 安装整个 workspace（数千包），再跑 `tsc` + `tsdown` + web 前端构建；
- 本机只有 npm/corepack，npm registry 连接间歇性 `SSL_ERROR_SYSCALL`；
- 构建产物布局与 npm 包不同，`pack-core` 的裁剪/原生校验规则需要重做；风险远高于收益。

**结论：rc.2 目前是"有标签、未发版"。** 端侧要合，必须等 `@deepseek-ai/dsh@0.2.2-rc.2`
出现在 npm（或用官方发布的构建产物）。

### 4.3 rc.2 一旦发版的最短路径

1. 改 `hostcore/core-recipe.json` 的 `coreVersion` 为 `0.2.2-rc.2+dshm.1`；
2. `node tools/pack-core.mjs`（物化 → 裁剪 → 原生校验 → 打包）；
3. `node tools/check-core-openharmony-patches.mjs`（31 个补丁锚点，上一轮只迁 1 处）；
4. `CompatIndex.SUPPORTED_VERSIONS` 增加 `0.2.2-rc.2`，跑契约回归；
5. 重编 Beta + AGC，再做三端真机。

---

## 5. 验证与边界

- `node --check hostcore/app/main.js`：通过；`tools/place-host-app.mjs` + `assert-resfile-sync`：22 件全部同步。
- `check-bash-terminfo`：PASS，自检 4/4 判红；`check-task-state-compat`：PASS，自检 3/3 判红。
- `check-tools-syntax`：164 个脚本语法全过。
- **未做**：本机无 2in1 设备，未复跑真机终端；TERM 回退与 SIGSYS 消失需在 2in1 上复测
  （建议直接跑同一份诊断脚本，期望 `xterm-256color` 6/6 存活，且 `etc/terminfo` 探测为 True）。
- **未做**：rc.2 核心物化与合并（npm 未发版，原因见 §4）。

### 5.1 PC / 2in1 实测反馈（2026-11-11 22:50，Beta 20261111T144008）

| 检查 | 结果 |
|---|---|
| TERMINFO 目录可读、`x/xterm` 与 `x/xterm-256color` 存在（3980 / 4074 B） | 通过 |
| `TERM=xterm-256color` 连续 6 次交互式 bash | **6/6 ALIVE，rc=0，无 rc=159** |
| `TERM=xterm` 对照 3 次 | 3/3 通过 |
| tmux 3.5a 建会话并列出 | 通过 |
| 宿主日志 `task-state` 最近 20 行 | 无"兼容副本写失败"；仅 1 条"兼容副本跳过（EACCES）"，守卫生效 |
| `task-state.json` | 合法 JSON，`active/seq/at` 均在 |
| 管道 / 架构 / python / node / git | 全部正常（aarch64 / 24.9.0 / 2.47.3） |
| `infocmp` | **未随包**（见下） |

**关于 `infocmp`**：它属于 Alpine 的 `ncurses-bin`，本仓只随包 `ncurses-terminfo-base`（数据）与
`libncursesw`（库），没有二进制诊断工具 —— 属**既有打包口径，不是本次修复的回归**。验收不该把它
当必过项。要用自动化替代，可直接校验 terminfo 条目的魔数（不需要任何额外二进制）：

```sh
python3 -c "import os;b=open(os.path.join(os.environ['TERMINFO'],'x','xterm-256color'),'rb').read(4);print(b[:2].hex(), b[:2] in (b'\x1a\x01', b'\x1e\x02'))"
# 期望：1a01 True（或 1e02 True，扩展格式）
```

**关于 `TERM=dumb`**：验收器自身的 shell 是 `bash` 工具通道，故意设 `dumb` 以避免 ANSI 转义污染输出；
交互式终端标签页走 node-pty，`name` 仍是 `xterm-256color`。因此第 4 项必须显式带 `TERM=...` 才有效。

**可选增强（未做）**：若要给用户补 `clear` / `tput` / `infocmp`，需要额外采集 Alpine `ncurses-bin`
并加入 bashroot 归档（约百余 KB），再重跑 `place-toolchain` 与出包；不属于本次崩溃修复的必要条件。

### 5.2 手机 guest 实测反馈（2026-11-11 22:46–23:05，r22）

| 检查 | 结果 | 判定 |
|---|---|---|
| `/etc/terminfo/x/xterm-256color` 存在（4074 B） | 存在；`/usr/share/...` 不存在 | 通过（与包装口径一致） |
| `TERM=xterm-256color` 连续 6 次 `bash -ic` | 6/6 ALIVE、rc=0（仅 `Not a tty` 警告） | **通过** |
| `TERM=xterm` 对照 3 次 | 3/3 rc=0 | 通过 |
| tmux 3.5a new/ls/kill | 全部 rc=0 | 通过 |
| 文件写读回环 | 写 rc=0、读回 `MCHK-OK` | 通过 |
| `infocmp` | 未安装 | 非缺陷（同 §5.1，属 `ncurses-bin`，从未随包） |
| `python3` | `command not found` | **文档口径问题，见下** |
| `兼容副本写失败` 计数 | 29（全文件累计） | **不能据此判失败，需按时间窗复核，见下** |

#### 关于 `python3`

`docs/399` 自身有两处矛盾：第 90 行写"手机 guest：bash / git / Python"，而第 57 行的平台对照表
只承诺"guest 环境（bash / tmux / gh）"。实际随包 `resfile/vm/guestpkgs/` 里**没有任何 python 包**
（逐包列过），guest 也确认 `command not found`。

结论：**这不是本次修复引入的回归**，但更新说明对手机 guest 的 Python 表述过宽，应改成
"bash / git / tmux / gh"；若产品口径确实要求手机 guest 带 Python，则需要新增 Alpine
`python3` 闭包（约 50 MB 级），属于独立的裁剪决策，不在本轮范围。

#### 关于 `兼容副本写失败 = 29`

- 该计数是**整个 `dshm-host.log` 的历史累计**，不区分安装批次；29 条完全可能全部来自修复前的版本。
- 修复后的行为应表现为：启动后出现**一条** `兼容副本跳过（目录不可写，只有主链路）`，
  之后不再出现 `兼容副本写失败`。
- 本次手机测试**未能确认应用版本**（报告原文：设置-关于不可达、日志里 `1.1.8`/`1010015` 命中 0 次），
  因此不能判定 29 条是否包含新包产生的记录。

复核命令（按时间窗，而不是全文件计数）：

```sh
# 1) 两类消息各自的最后 5 条（带行号，行号大的是新记录）
grep -n '兼容副本' "$LOG" | tail -5

# 2) 只看最近 300 行：新包应当 0 条"写失败"
tail -n 300 "$LOG" | grep -c '兼容副本写失败'

# 3) 新包启动后应至少有一条"跳过"
tail -n 300 "$LOG" | grep -c '兼容副本跳过'
```

判据：②=0 且 ③≥1 ⇒ 守卫生效；②>0 且 ③=0 ⇒ 跑的仍是旧包（先确认安装版本再谈缺陷）。

#### 顺带发现：手机宿主事件循环长停顿

同段日志里 `LOOP-GAP` 最长 **67.8 s**、多次 20–60 s。这与终端修复无关（终端 A/B 项全部秒回），
但会直接表现为"命令像卡住"。属独立问题，建议单独立项（先看 `node-output.log` 同期在做什么），
本轮不混入终端修复的验收结论。

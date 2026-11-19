# 346 · Super-agent 环境复测（三）：**前置条件全绿**，卡在"服务没有启动通道"

> 日期：2026-11-02 22:20 ｜ 检测人：AI 助手（含一次**端到端安装实测**；测试残留已清理）
>
> 用户口径：「再次复测环境」
>
> 前序：[`345`](345-Super-agent环境复测二（tmux-ps-dsh三项已修与pnpm仍缺）.md)（复测二）、
> [`344`](344-Super-agent环境复测（tmux-gh已内置与pnpm仍缺）.md)、
> [`343`](343-Super-agent环境检测与可修性评估（pnpm构建gh三缺口与平台硬约束）.md)（首测）。
>
> 环境变更：核心树仍 `0.2.1-rc.5+dshm.106`；宿主 22:12:12 重启（pid 59321）；
> **工具链新增 `pnpmroot` / `npmroot`**。

---

## 0. 结论

> **前置条件全部到位了（官方 probe 7/7 通过），安装链路也已实测走通，
> 但"把服务真正跑起来"这一步目前没有通道 —— 这是本轮新的、也是唯一的**结构性**障碍。**

| 层 | 判定 |
|---|---|
| **① 前置依赖**（SETUP.md §1 的 7 项） | ✅ **7/7 通过**（pnpm 已真：**9.15.9**） |
| **② 安装链路**（clone → install → 构建 → 装 profile） | ✅ **实测走通**（1 处需绕行，见 §3） |
| **③ 服务启动** | ❌ **无可用通道**（宿主在 HAP 内，沙箱起不了，见 §4） |
| **④ 操作端** | 🟡 gh 未登录、仓库/账号待定 |

---

## 1. 官方 probe：**7/7 通过**

```text
node -v            → v24.2.0                          ✅ 需 22.19+ / 24+
pnpm -v            → 9.15.9                            ✅ 真 pnpm（随包纯 JS）
git --version      → git version 2.47.3                ✅ 需 2.32+
tmux -V            → tmux 3.5a                         ✅
python3 --version  → Python 3.12.14                    ✅ 需 3.8+
gh --version       → gh version 2.72.0 (2026-01-15)     ✅ 需 2.48+
dsh --version      → 0.1.7-rc.1 (shim 串)              ✅ 转发真身 0.2.1-rc.5（§2 已验）
```

**pnpm 这次是真的**：`toolchain/pnpmroot`（`bin/pnpm.cjs`）+ `bin/pnpm` 包装器 306 B：

```sh
#!/system/bin/sh
# DSHM pnpm wrapper：随包纯 JS 实现（不再走安装队列假壳）
R=.../toolchain/pnpmroot; E="$R/bin/pnpm.cjs"
exec node "$E" "$@"
```

附带 `npm 11.21.1` 也变真了（`toolchain/npmroot`）。
`ps -o` / `-ax` 仍正常（回归通过）。

---

## 2. 端到端安装实测（本轮新增，全部实跑）

### 2.1 clone + `pnpm install` ✅

```text
git clone --depth 1 …dsh-superagent-prototype.git
pnpm install --ignore-scripts
→ Done in 1m 6.7s using pnpm v9.15.9     ✓（289 包，含 tsdown/typescript/react）
```

> 注：仓库 `packageManager: pnpm@11.7.0`，随包 9.15.9 **没有**强行拒绝，正常装完。

### 2.2 `pnpm build` ❌（平台约束，非环境缺失）

```text
pnpm build → ELIFECYCLE Command failed with exit code 1
原因：@rolldown/binding-openharmony-arm64/…node → Permission denied
      （原生 .node 无法 dlopen，与 docs/343 §3.1 同一约束）
```

### 2.3 替代构建 ✅（`tsc` + `esbuild-wasm`，本轮在随包 pnpm 下重验）

```text
pnpm add -D esbuild-wasm          → Done in 22.2s ✓
node node_modules/typescript/bin/tsc -p tsconfig.build.json   → rc=0 ✓
node build-client-wasm.cjs        → lib/client.js 362.7kb (1058ms) ✓
补两个转发入口 → lib/github-watch.js / lib/feishu-watch.js
```

四个必需入口全部就位：

| 入口 | 大小 |
|---|---|
| `lib/index.js` | 1,679 B |
| `lib/client.js` | **371,376 B** |
| `lib/github-watch.js` | 36 B |
| `lib/feishu-watch.js` | 36 B |

**模块加载实测**：

```text
node -e "import('./lib/index.js')"  →  ✓ loaded, name= dsh-superagent, inject= 11
```

### 2.4 建 profile ✅（官方第 4 条命令现在能跑）

```text
dsh superagent --from-default-profile web --dump-config   → rc=0 ✓
profiles/: ondevice  superagent
```

### 2.5 装插件：官方命令仍被拦，profile 内直接装 ✅

```text
$ dsh plugin --profile superagent add "link:$PWD"
dsh(shim): 安装失败：无法识别的插件标识：link:…
```

**原因不是 pnpm**，是 **`dsh` 假壳把 `plugin` 子命令劫持成安装队列投递**，
队列协议只认 npm 包名 / GitHub 地址，不认 `link:`。

**绕行（实测通过）**：

```sh
cd $DSH_HOME/profiles/superagent
pnpm add -w --ignore-scripts "link:<checkout>"    # → + dsh-superagent 0.1.0 ✓
# 手工登记 bundle
node -e "…p.dsh.profile.bundles.push('dsh-superagent')…"
```

### 2.6 真 dsh 组合配置验证 ✅（安装正确的铁证）

```text
$ dsh --profile superagent --dump-config | grep -E "dsh-superagent|stateDir|port:"
    port: 3082
- id: dsh-superagent
  name: dsh-superagent
    stateDir: /data/storage/el2/base/haps/entry/files/dsh/home/state/superagent
- id: dsh-superagent-github
  name: dsh-superagent/github-watch
- id: dsh-superagent-feishu
  name: dsh-superagent/feishu-watch
- id: dsh-superagent-worker-preset
    id: dsh-superagent-worker
```

⇒ **插件被正确解析、子路径入口可解析、机器配置生效、端口 3082**。

---

## 3. ⚠️ 安装链路的唯一绕行点

| 官方步骤 | 现状 | 绕行 |
|---|---|---|
| `dsh plugin --profile superagent add "link:$PWD"` | ❌ 被 `dsh` 假壳的安装队列拦（不认 `link:`） | ✅ profile 内 `pnpm add -w "link:…"` |

**建议**：给 `dsh` 假壳的 `plugin` 分支加一条放行 ——
`link:` / `file:` 这类**本地路径标识**直接透传给真 dsh（或直接执行 pnpm），
因为本地 link 不涉及下载与审核，走安装队列没有意义。

---

## 4. ❌ 本轮新发现的结构性障碍：**服务没有启动通道**

### 4.1 裸 node 启动必失败

```text
$ dsh --profile superagent --no-open
dsh: fatal uncaught exception: Error: dsh: host preparation failed:
  No usable native binding found for node-addon-require-builtin-openharmony-arm64 (auto)
    at boot (@deepseek-ai/dsh-app-boot/lib/index.js:4575:9)
```

⇒ dsh 必须由 **DSHM 宿主的 jitless 垫片栈**启动
（`hostcore/app/main.js` 里的 `require-builtin-shim` / undici 钩子 / fetch 垫片 / native redirect）。

### 4.2 但宿主入口在沙箱内**不可达**

| 探测 | 结果 |
|---|---|
| 设备 `files/` 下是否有 `hostcore/app/main.js` | ❌ 无 |
| 全盘找 `require-builtin-shim.cjs` / `jitless-env.cjs` / `worker-bootstrap.cjs` | ❌ **零命中** |
| `/data/app/el1/bundle/public/`（HAP 内 resources） | ❌ `No such file or directory` |
| 运行中宿主的 cmdline | 只有 `com.dshm.dshmbeta`（**是应用进程本身**，不是外部 node） |

⇒ **宿主是 ArkTS 应用进程内嵌的**，其入口 JS 与垫片都在 **HAP（el1）内**，
沙箱既读不到也起不了。**所以现在没有任何办法从沙箱启动第二个 profile。**

### 4.3 三种可行方向（需开发端定夺）

| 方案 | 做法 | 评价 |
|---|---|---|
| **A. 宿主支持多 profile**（推荐） | ArkTS `RuntimePort` 增加"以 `DSHM_PROFILE=superagent` / `DSHM_PORT=3082` 再起一个宿主进程"的能力；`main.js:1431-1432` 已读这两个环境变量，**宿主侧几乎不用改** | 最符合官方"独立 profile、独立重启"的设计 |
| B. 把 superagent 装进 `ondevice` | 少一个进程，但**违背官方建议**：插件会改进程级 PATH 与 git 配置，且它自己要 3082、要独立重启 | 仅适合"先看看效果" |
| C. 暴露宿主入口给沙箱 | 把 `main.js` + 垫片落到 `files/` 并允许沙箱 node 启动 | 等于把宿主引导面放出沙箱，**安全面变化大**，不建议 |

> **注意**：方案 A 是唯一能满足"superagent 与我的工作 profile 隔离"的做法 ——
> 官方明确要求"**Keep it separate from the profile you work in**：the plugin changes
> process-wide `PATH` and git settings"。

---

## 5. ⚠️ 顺带发现一处"判据已过期"

宿主启动时打这条日志：

```text
[dshm-market-bridge] 随包 bin/pnpm 假壳可执行 ⇒ 不接管（市场走已验收的假壳链路）
```

但 **`bin/pnpm` 现在已经是真 pnpm（9.15.9），不是假壳了**。

实读 `dshm-market-bridge/lib/index.js:120-132`：

```js
function shimRunnable() {
  const shim = join(sandbox, "bin", "pnpm");
  if (!existsSync(shim)) return false;
  const result = spawnSync(shim, ["--version"], {…});
  return result.status === 0;          // ← 只判「能跑」，不判「是不是假壳」
}
```

⇒ **行为上没错**（真 pnpm 也能跑 ⇒ 同样"不接管"），
但**语义与文案已经不准**：日志说的"假壳链路"现在其实是"真 pnpm 链路"，
而真 pnpm 会**绕过**安装队列原有的审批/版本豁免闸门。

**建议**（不紧急，但该记一笔）：
1. 把 `shimRunnable()` 改名/改判据（例如显式检测 shim 标记串 vs 真 pnpm）；
2. 更新那句日志文案；
3. 复核"市场安装是否仍需经安装队列"——若仍需，就不该只靠"pnpm 能跑"来放弃接管。

---

## 6. 操作端（只有你能做）

| # | 事项 | 现状 |
|---:|---|---|
| 1 | **gh 登录**（专用 Agent 账号，`gh auth login --with-token`） | ❌ `not logged into any GitHub hosts` |
| 2 | github.com 仓库（不支持 GHES） | 待定 |
| 3 | 允许提问的账号白名单 | 待定 |
| 4 | 飞书（可选，需 `lark-cli`） | 未装 |

---

## 7. 测试残留（已全部清理）

| 我创建的 | 处置 |
|---|---|
| `.scratch-sa2`（clone + node_modules，**181 MB**） | ✅ 已删 |
| `$DSH_HOME/profiles/superagent` | ✅ 已删（`profiles/` 只剩 `ondevice`） |
| `~/.local/{share,state}`（pnpm store，**153 MB**） | ✅ 已删 |
| `/tmp/pnpmtest`、`/tmp/sa2-profile.txt` | ✅ 已删 |
| 你的 `ondevice` profile | ✅ **未改动**（依赖仍是 `dshmarket, @iasiv5/dsh-skins, dsh-skin-market`） |
| 宿主进程 | ✅ 正常（pid 59321 / 3121 / ondevice） |

---

## 8. 判定：**环境"就绪"，但"跑不起来"**

> **前置条件已全部满足**（官方 probe 7/7），**安装链路已实测走通**
> （clone → install 1m6.7s → tsc+esbuild-wasm 出 4 入口 → link 装进 profile → dsh 组合配置正确）。
>
> **但"把服务跑起来"这一步没有通道**：dsh 需要宿主的 jitless 垫片才能启动，
> 而宿主入口与垫片都在 **HAP（el1）内**，沙箱读不到、起不了；宿主本身是应用进程内嵌的，
> cmdline 里只有包名。
>
> ⇒ **下一步必须由开发端加一个"启动第二个 profile"的通道**（方案 A），
> 或在拿到明确同意后临时装进 `ondevice`（方案 B）。

---

## 9. 一句话交接

**环境这次真的齐了**：pnpm 9.15.9 是真身（随包纯 JS），加上 tmux 3.5a / gh 2.72.0 / ps 垫片 / dsh 转发，
官方 probe **7/7 通过**。我把它端到端走了一遍——`pnpm install` 1 分 6 秒通过、
构建用 `tsc` + `esbuild-wasm` 出齐 4 个入口（`client.js` 371 KB）、模块实测可加载、
`dsh superagent --from-default-profile` 建 profile 通过、`pnpm add -w link:` 装入后
`dsh --profile superagent --dump-config` **正确组合出插件与 `stateDir`/3082 端口**。

**只剩两件事**：
1. **服务启动没有通道**（新的结构性障碍）—— dsh 裸 node 起不来（原生 addon），
   而宿主入口与 jitless 垫片全在 HAP 内，沙箱不可达 ⇒ **需要开发端给"第二 profile 启动"能力**；
2. **`dsh plugin add link:` 仍被安装队列拦**（不认 `link:`）⇒ 建议对本地路径标识放行。

另发现一处**判据过期**：`dshm-market-bridge` 的 `shimRunnable()` 只判"bin/pnpm 能跑"，
而 pnpm 已从假壳变真身，日志文案与"市场走假壳链路"的语义都该复核。

测试残留已全部清理（181 MB clone + 153 MB pnpm store + 临时 profile），你的 `ondevice` 未改动。

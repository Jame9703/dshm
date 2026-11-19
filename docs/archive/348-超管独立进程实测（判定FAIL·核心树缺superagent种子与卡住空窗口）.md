# 348 · 超管独立进程实测：**判定 FAIL**（核心树缺 `profiles/superagent` 种子 + 卡住空窗口 + 失败标记全局污染）

> 日期：2026-11-02 23:40 ｜ 执行人：AI 助手（只读取证；`touch` 标记与临时 profile 由本轮创建）
>
> 任务：测试 `dist/sideload/DSHM-beta-1.1.7-1010008-combined-debug-v11.app` 的超管（superagent）独立进程能力，并回归既有环境。
>
> 关联：[`346`](346-Super-agent环境复测三（前置全绿与启动无通道）.md)（方案 A 的建议来源）、
> [`347`](347-Super-agent环境复测四（无功能变化与解包软链问题）.md)（上一轮）。

---

## 0. 判定：**FAIL**

| 判据 | 结果 |
|---|---|
| 第 1 段 9 条全绿 | ✅ **9/9 通过** |
| profile 建出（ondevice + superagent） | ✅ 通过 |
| 日志出现"宿主已启动：ok=true" | ❌ **宿主在 `BOOT_20_CORE_FOUND` 就 fatal 退出，从未到 ok=true** |
| `host-ready.json` 里 `port=3082` | ❌ **仍是 `3121 / ondevice`** |

**失败根因（一行）**：

> `ensureProfile()` 要求**核心树**里有 `profiles/<PROFILE>` 种子目录，
> 而核心树只随包了 `profiles/ondevice`；`superagent` 是由
> `dsh --from-default-profile web` 建在 **`$DSH_HOME/profiles/superagent`** 的
> ⇒ 第二进程的宿主一启动就在 `BOOT_20_CORE_FOUND` fatal。

**用户观察到的"卡住的 DSHM beta 窗口"就是这个失败的直接表现**（见 §5）。

---

## 1. 安装包核对

| 项 | 值 |
|---|---|
| 路径 | `dist/sideload/DSHM-beta-1.1.7-1010008-combined-debug-v11.app`（556,298,695 B，23:27） |
| **sha256** | **`92b99ac8d868ad4b148650810504ea107ae9e8034d25d2cde154e454e778cc88`** ✅ **与给定值逐位一致** |

> ⚠️ **安装与重启由用户完成**：本沙箱**没有 hdc**，且 `bm dump` 被拒、`aa dump -a` 无权限，
> 无法执行 `install -r`，也无法代为重启/拉起 ability。

---

## 2. 第 1 段：环境回归（9/9 通过，原始输出）

```text
$ node -v
v24.2.0

$ pnpm -v
9.15.9

$ npm -v
11.21.1

$ git --version
git version 2.47.3

$ tmux -V
tmux 3.5a

$ gh --version
gh version 2.72.0 (2026-01-15)
https://github.com/cli/cli/releases/tag/v2.72.0

$ python3 --version
Python 3.12.14

$ dsh --version
dsh 0.1.7-rc.1 (dshm install-queue shim)

$ ps -ww -o pid=,ucomm=,args= | head -5
17575 m.dshm.dshmbeta com.dshm.dshmbeta
17680 GroundAbility:5 com.dshm.dshmbeta…:entry:BackGroundAbility:5
18836 ash /data/storage/el2/base/haps/entry/files/bin/ash -c cd /data/storage/el2/base/haps/entry/files; …
18842 ps /system/bin/sh /data/storage/el2/base/haps/entry/files/bin/ps -ww -o pid=,ucomm=,args=
18843 head head -5
```

`dsh --version` 显示壳串属**正常**（判据已注明）；接着的 `dsh --help` **给出真 dsh 用法**：

```text
$ dsh --help
Usage: dsh [--profile] <name> [options] [app-args...]
       dsh plugin --profile <name> <pnpm-args...>

dsh: boot a DeepSeek Harness profile — an ordered stack of plugin-bundle patch
layers under your own overrides.

Arguments:
  args                           arguments for the booted profile's app (see:
                                 dsh --profile <name> --help)

Options:
  -V, --version                  output the version number
  --profile <name>               the profile under $DSH_HOME/profiles to boot
  --from-default-profile <name>  replace a custom profile with a fresh copy of a
                                 shipped profile template
  --patch <path>                 extra patch-list overlay applied after the
                                 profile layer (repeatable)
  --dump-config                  print the composed profile tree and exit
  --dump-config-schema           print JSON Schema for profile entries and
                                 patches without mounting
  --dump-default-config          print the profile tree without its user layer
                                 or --patch overlays and exit
```

**判据逐项**：node ✅ / pnpm ✅ / npm ✅ / git ✅ / tmux ✅ / gh ✅ / python ✅ / ps ✅ / dsh 真用法 ✅

---

## 3. 第 2 段：建 profile（通过）

```text
$ dsh superagent --from-default-profile web --dump-config
[rc=0]
```

```text
$ ls /data/storage/el2/base/haps/entry/files/dsh/home/profiles/
ondevice
superagent
```

---

## 4. 第 3 段：触发（已执行，触发链本身**是通的**）

```text
$ touch /data/storage/el2/base/haps/entry/files/start-superagent.request
-rw-rw-rw- 1 20020318 20020318 0 2026-11-02 23:32 …/start-superagent.request
```

用户重启后：

| 检查 | 结果 |
|---|---|
| 标记是否被消费 | ✅ **已删除** ⇒ `EntryAbility.startSuperagentIfRequested()` 走到了 |
| 是否起了第二进程 | ✅ **`20611 beta:superagent com.dshm.dshmbeta:superagent`** |

⇒ **标记机制与独立进程声明（`"process": ":superagent"`）都正常工作。**

---

## 5. 第 4 段取证

### 5.1 段4.1 日志：**没有 "ok=true"，而是宿主 fatal 退出**

沙箱读不到 hilog（`hilog -x` 空、`Errno 13`），但 **`Node 侧留下了更硬的证据**：

**(a) `.dshm-boot-failed`（23:33:06，`$DSH_HOME/.dshm-boot-failed`）全文**：

```text
2026-11-02T15:33:06.088Z stage=BOOT_20_CORE_FOUND reason=启动失败：Error: DSHM host fatal: 核心树里没有 profiles/superagent：/data/storage/el2/base/haps/entry/files/dsh/cores/0.2.1-rc.5+dshm.106/profiles/superagent
    at fail (/data/storage/el1/bundle/hostruntime/resources/resfile/resources/app/main.js:1931:9)
    at ensureProfile (…/app/main.js:7222:5)
    at start (…/app/main.js:7405:3)
    at Object.<anonymous> (…/app/main.js:7901:1)
    at Module._compile (node:internal/modules/cjs/loader:1734:14)
    at Module._extensions..js (node:internal/modules/cjs/loader:1899:4)
    at Module.load (node:internal/modules/cjs/loader:1476:32)
    at Module._load (node:internal/modules/cjs/loader:1286:12)
    at TracingChannel.traceSync (node:diagnostics_channel:322:14)
    at wrapModuleLoad (node:internal/modules/cjs/loader:309:5)
    at Module.executeUserEntryPoint [as runMain] (node:internal/modules/run_main:152:5)
```

**(b) `host-exit.log`**：

```text
node::Start returned rc=0 pid=20611 at=1793633589
```

**(c) `node-output.log`（pid=20611 的最后几行）**：

```text
[2026-11-02T15:33:09.520Z] 探针读数已暂存（host-ready.json 仍属于上一次进程 pid=17575，本进程是 20611）：runtime.exec
[2026-11-02T15:33:09.747Z] 终端能力汇总：宿主域=u:r:develop_tools_debug_hap:s0，toybox域=rc0，…
[2026-11-02T15:33:09.784Z] !! beforeExit code=0 exitCode=undefined（loop 已排空） handles=0[] requests=0[]
[2026-11-02T15:33:09.784Z] !! process 'exit' event, code=0 exitCode=undefined
[2026-11-02T15:33:09.785Z] [dshm-host] fs 探测缓存 stats：enabled=true TTL=30000ms …
```

⇒ 第二进程的 Node 宿主**确实启动了、跑了探针**，然后因 `ensureProfile` fatal 而 **rc=0 退出**。
所以 `SuperagentAbility 宿主已启动：ok=true` **不会出现**（代码路径走的是 `.catch` 分支）。

### 5.2 段4.2 `host-ready.json`（全字段，token 打码）

```json
{
  "url": "http://127.0.0.1:3121/?token=Y3K1g7s5tdXdSwchvMFADpwIEvKz9j6m1fZo8sPGI1w",
  "baseUrl": "http://127.0.0.1:3121",
  "token": "***sPGI1w",
  "port": 3121,
  "profile": "ondevice",
  "pid": 20378,
  "startedAt": "2026-11-02T15:33:15.081Z",
  "workspace": "~/Download/com.dshm.dshmbeta"
}
```

> **`port=3121 / profile=ondevice` ⇒ 判据不满足。**
> 原因：第二宿主在写 `host-ready.json` **之前**就 fatal 了，所以文件仍归主宿主。
> （若它成功起来，就会覆盖成 3082 —— 那个覆盖问题见 §6.2。）

**端口实测**：

```text
http://127.0.0.1:3082/orchestrator/api/state  → 000（连不上）
http://127.0.0.1:3121/                        → 303（正常）
/proc/net/tcp 里查 :0C0A(3082)                → 无条目（未监听）
```

### 5.3 段4.3 `profiles/superagent/` 列表

```text
total 49152
drwxrwxrwx 2 20020318 20020318 3440 2026-11-02 23:31 .
drwxrwxrwx 2 20020318 20020318 3440 2026-11-02 23:31 ..
-rw-rw-rw- 1 20020318 20020318  217 2026-11-02 23:31 cordis.patch.yml
-rw-rw-rw- 1 20020318 20020318  223 2026-11-02 23:31 cordis.yml
-rw-rw-rw- 1 20020318 20020318  214 2026-11-02 23:31 package.json
-rw-rw-rw- 1 20020318 20020318   61 2026-11-02 23:31 pnpm-workspace.yaml
```

`cordis.patch.yml` 内容仍是**空模板**：

```yaml
# Your patch layer for this dsh profile, applied after every bundle layer:
# a top-level YAML array of loader patch entries (id-targeted config
# overrides, disables, and insert lists; `!!js` expressions allowed).
[]
```

> **注意**：这里**没有 `stateDir`**。即便修好种子问题，`dsh-superagent` 插件自身也会因缺 `stateDir` 拒绝启动
> （官方 `docs/006-deployment.md`：Machine configuration 的 `stateDir` 为 required）。
> 所以 §7 的修复必须**连 `stateDir` 一起**物化。

### 5.4 段4.4 `ps` 尾部（确认多了一个进程）

```text
$ ps -ww -o pid=,ucomm=,args= | tail -20
20378 m.dshm.dshmbeta com.dshm.dshmbeta
20557 GroundAbility:6 com.dshm.dshmbetacom.dshm.dshmbeta:entry:BackGroundAbility:6
20611 beta:superagent com.dshm.dshmbeta:superagent
22232 ash /data/storage/el2/base/haps/entry/files/bin/ash -c cd /data/storage/el2/base/haps/entry/files; …
22233 ps /system/bin/sh /data/storage/el2/base/haps/entry/files/bin/ps -ww -o pid=,ucomm=,args=
22234 tail tail -20
```

**`20611 beta:superagent` 就是多出来的独立进程**（27 线程 / RSS 106 MB / State=S）。
RSS 只有 106 MB 而主宿主约 600 MB —— **说明它里面的 Node 宿主已退出**（宿主活着时会占数百 MB）。

---

## 6. 三个缺陷（按严重度）

### 6.1 🔴 P0：核心树没有 `profiles/superagent` 种子 ⇒ 第二进程必定 fatal

实读 `hostcore/app/main.js:7219-7223`：

```js
function ensureProfile() {
  const src = path.join(CORE_DIR, 'profiles', PROFILE);   // ← 只认核心树种子
  if (!fs.existsSync(src)) {
    fail('核心树里没有 profiles/' + PROFILE + '：' + src);
  }
  const dest = path.join(HOME_DIR, 'profiles', PROFILE);  // ← 再拷到 HOME
  …
}
```

实测布局：

| 位置 | 内容 |
|---|---|
| `cores/0.2.1-rc.5+dshm.106/profiles/` | **只有 `ondevice`** |
| `$DSH_HOME/profiles/` | `ondevice` + `superagent` |

⇒ **CLI（`dsh --profile superagent`）能跑，宿主（`ensureProfile`）跑不了** —— 两者对 profile 的来源不一致。
这就是"第 2 段能建 profile、第 3 段却起不来"的根因。

### 6.2 🟡 P1：失败后留下**卡住的空窗口**（用户观察到的现象）

`SuperagentAbility` 是 `UIAbility`，`onWindowStageCreate()` 里只 `this.startHost()`，
**既不 `loadContent`，失败也不 `terminateSelf()`**：

```ts
onWindowStageCreate(): void {
  this.startHost();          // 失败仅 hilog.error，不收窗口
}
```

⇒ 宿主 fatal 退出后，窗口仍留着 = 用户看到的"**后台多出来一个卡住的 DSHM beta 窗口**"。
（直接因：宿主没起来却没有收尾。）

### 6.3 🟡 P1：失败标记是**全局**的，会污染主 profile

`quarantineAfterBootFailure(profileDir, homeDir)` 读的是 **`homeDir/.dshm-boot-failed`**（`dshm-user-rows.js:1119`），
**不区分 profile**。本次 superagent 的失败把标记写进了共享的 `$DSH_HOME`：

```text
-rw-rw-rw- 1 … 1173 2026-11-02 23:33 dsh/home/.dshm-boot-failed
```

⇒ **主宿主下次启动会读到它，并把 `ondevice/.dshm-plugin-rows.yml` 隔离**（用户插件开关被重置为种子）。
本次未显现，仅因为 `ondevice` 目前**没有** `.dshm-plugin-rows.yml`（从未改过插件开关）。

**这是跨 profile 的污染路径，建议按 profile 分文件**（如 `.dshm-boot-failed.<profile>`）。

> ⚠️ 该标记现在仍在。要不要删由你们定；**我不擅自删**（它也是本次取证的原始材料）。

### 6.4 附：`host-ready.json` 双写（修好种子后会立刻暴露）

`host-ready.json` 写在 `HOME_DIR`（`main.js:1821`），**两个宿主共用同一个 `DSH_HOME`**。
第二宿主一旦成功起来就会把它改成 `port=3082 / profile=superagent`，
而主宿主/WebView 靠它取 token 接入（`main.js:1504`）⇒ 主界面可能连错端口/取错 token。

代码里只对 `runtime` 探针补写做了 pid 防护（`main.js:1864-1889`「仍属于上一次进程 pid=…」），
**主写入没有**。建议：按 profile 分文件（`host-ready.<profile>.json`）或加 pid/profile 守卫。

---

## 7. 修复建议（按最小改动排序）

| # | 改动 | 落点 | 说明 |
|---:|---|---|---|
| 1 | **随包物化 `profiles/superagent` 种子** | `tools/pack-core.mjs`（核心树 `profiles/`） | 与 `ondevice` 同构：把 `web` 模板 + `examples/profile.cordis.patch.yml` 的 `stateDir` 填好一起放进核心树种子。这样 `ensureProfile` 直接可用，**且顺带解决 §5.3 的缺 stateDir** |
| 2 | **或**让 `ensureProfile` 回退 | `hostcore/app/main.js:7219` | 核心树没种子时，若 `$DSH_HOME/profiles/<PROFILE>` 已存在则直接用它（并把缺 `stateDir` 报成可读的 setup 提示） |
| 3 | **失败即收窗口** | `SuperagentAbility.ets` | `startHost()` 的 `.catch` 里调 `this.context.terminateSelf()`（或至少 `windowStage.loadContent` 一个错误页），别留空窗口 |
| 4 | **失败标记按 profile 分开** | `hostcore/app/dshm-user-rows.js:98,1119` | 避免第二 profile 的失败隔离主 profile 的用户行 |
| 5 | **`host-ready.json` 按 profile 分开** | `hostcore/app/main.js:1821` | 避免两宿主互相覆盖 token/port |

---

## 8. 判定与下一步

> **判定：FAIL** —— 第 1 段 9/9 ✅、profile 建出 ✅、
> 但 **没有"宿主已启动：ok=true"**（宿主在 `BOOT_20_CORE_FOUND` fatal）、
> **`host-ready.json` 不是 3082**（仍 3121/ondevice）。
>
> **但"独立进程"这件事本身是成功的**：标记机制触发成功、`beta:superagent` 进程真的起来了。
> 失败的是**进程里那个 Node 宿主**——它缺核心树种子。

**下一步只需改一处就能过**：把 `profiles/superagent` 种子（含 `stateDir`）随包进核心树。
之后再复测时，请一并观察 §6.2（空窗口）、§6.3（失败标记污染）、§6.4（host-ready 双写）这三条。

---

## 9. 本轮遗留状态

| 项 | 状态 |
|---|---|
| `$DSH_HOME/profiles/superagent` | 保留（第 2 段的产物，供下一轮复测直接用） |
| 第二进程 `20611 beta:superagent` | **仍在**（空转，需用户关掉那个卡住的窗口才会退） |
| `$DSH_HOME/.dshm-boot-failed` | **保留**（取证材料；注意 §6.3 的污染风险） |
| 主宿主与用户数据 | 未改动（`pid=20378 / port=3121 / profile=ondevice`） |
| hilog | 沙箱不可读（`Errno 13`），本次用 `host-exit.log` + `.dshm-boot-failed` + `node-output.log` 替代取证 |

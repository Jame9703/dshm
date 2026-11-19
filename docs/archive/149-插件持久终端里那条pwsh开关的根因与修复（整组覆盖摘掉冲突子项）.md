# 149 · 插件「持久终端」里那条 `@deepseek-ai/dsh-terminal-bash` 开关点不动（根因与修复）

> 本文是 **2026-10-13** 这一轮的落实记录。用户原话：
> **「已修复，现在修插件-持久终端-@deepseek-ai/dsh-terminal-bash无法启用的问题」**
> （指「设置 → 插件」里 `持久终端` bundle 下那条标题为 `@deepseek-ai/dsh-terminal-bash` 的开关，
> 它的真 id 是 `optional-terminal-pwsh`。）

## 0. 一句话结论

- **症状**：拨那条开关时，端侧日志报
  `optional-terminal-pwsh (@deepseek-ai/dsh-terminal-bash): TerminalError: a PTY backend named "shell" is already registered`
  （bundle 级 `dsh: warning: 1 entry did not activate`）。
- **根因**：用户后加的 bundle `dsh-experimental-terminal-bundle` 在 `optional-persistent-terminals`
  这个 group 里放了**两个同名条目**（`optional-terminal-bash` 与 `optional-terminal-pwsh`，
  两行 `name` 都是 `@deepseek-ai/dsh-terminal-bash`，靠 `disabled: !!js process.platform === 'win32'`
  二选一）。鸿蒙没有 PowerShell ⇒ pwsh 那条**本质不可用**；而它的 `backendType` 默认与 bash 行
  同为 `"shell"` ⇒ `@deepseek-ai/dsh-terminal` 的 `registerBackend` 按 type 去重 ⇒ `DUPLICATE_BACKEND`。
- **修法**：在端侧 profile 种子里**整组覆盖** `optional-persistent-terminals` 的 `config`
  （只留 registry / bash / tool-terminal 三条）⇒ 合成后的挂载树里**根本不存在** `optional-terminal-pwsh`
  这个 id ⇒ 那条开关不再出现（点不到，自然炸不了）；比"灰掉"更彻底。
- **真机**：PC `86E0226429000417` 覆盖安装成功、**用户数据未丢**、核心树切到 `+dshm.35`；
  `pluginManager.listPlugins` **221 → 220 行**，**唯一差异就是 `include:optional-terminal-pwsh`**（无新增行）；
  组内三条 `enabled=true / fiberPhase=active`；宿主日志 `grep -E "did not activate|DUPLICATE_BACKEND|TerminalError|already registered"` **零命中**。

---

## 1. 为什么是"整组覆盖"而不是"把 pwsh 那条 disabled 掉"

种子 `hostcore/profile/ondevice/cordis.patch.yml` 里原先（`+dshm.34` 及以前）是两行：

```yaml
- id: optional-terminal-pwsh
  disabled: true
```

这条路实测**不够**：`applyEntryPatches` 对非 insert 行走 `target[key] = value`
（**整键覆盖，不是深合并**），而 `entryMap` 由 `buildMap` **递归**收录 group.config 里的 id
⇒ 顶层那两行能改到组内子项。于是"只改 `disabled`"会得到一条 **`disabled=true` 但仍在合成树里**的行；
它虽然不再被拨亮，但**它本身仍是一次 `registerBackend('shell')` 的尝试来源**（用户点它时 `!!js`
会被压成字面量），冲突面没有真正消失。

**改成整组覆盖**后：

```yaml
- id: optional-persistent-terminals
  config:
    - id: optional-terminal-registry
      name: '@deepseek-ai/dsh-terminal'
    - id: optional-terminal-bash
      name: '@deepseek-ai/dsh-terminal-bash'
      disabled: false
    - id: optional-tool-terminal
      name: '@deepseek-ai/dsh-tool-terminal'
```

合成树里**没有** `optional-terminal-pwsh` 这个子项 ⇒ 开关不出现 ⇒ 那条必然 `ENOENT` 的行
再也无法被拨动。其余三条与上游逐字一致，bash 行显式按端侧意图启用（鸿蒙不是 win32）。

> 幂等性：本文件每次启动由种子**整文件覆盖**；`dshm-user-rows.js` 的 carry 只保「种子没有的顶层键」
> ⇒ 不累积。上游若给该组加第四条，这里要同步补上（门禁会红）。

### 1.1 名字里那两条 `pwsh` 行不受影响（故意留着）

种子里还有另外两处 pwsh（`pwsh-sandbox`、`tool-pwsh`），它们是**别的副本**，本来就
`disabled: true` ⇒ 渲染成"灰掉的项"是正确产品语义，**不在本次改动面内**。

---

## 2. 设备上仍可能存在的旧行怎么处理

用户层 / 市场层里若还写着那两个 id 的**字面量行**，由 `hostcore/app/dshm-user-rows.js` 的
`PLATFORM_GUARD_ROWS = new Set(['optional-terminal-pwsh', 'optional-terminal-bash'])`
在 **prefilter**（`:333`）与 **carry**（`:527-529`）两处丢弃（否则会与种子打架）。

该名单**这次没动**：它现在只兜两类来源 ——

1. 设备上现存的旧 `cordis.patch.yml`（新种子已无此 key，但 carry 会把用户层里那条捞回来）；
2. 用户层 / 市场的字面量行。

---

## 3. 门禁：新判据 + 一条"被自己的注释顶红"的教训

`tools/check-core-openharmony-patches.mjs` 的 ④ 组（端侧 profile）本轮加了：

- `markers`：`['\n- id: optional-terminal-pwsh', 0]` 与 `['\n    - id: optional-terminal-pwsh', 0]`
  （**锚定 YAML 行首**：列 0 的顶层行，与 group config 里的 4 空格子项，两种形态都盖）。
- `forward`：`"- id: optional-persistent-terminals\n  config:"`（证明整组覆盖真的在）。

### 3.1 本轮踩的坑（值得记）

第一版判据写的是**裸字面量** `['- id: optional-terminal-pwsh', 0]`，**一上去就红**：
`- id: optional-terminal-pwsh 出现 1 次，规定 0 次`。

原因是本文件上方那段 D52 说明注释里**就写着这个字面量**（"这里断言 ×0"）——
**判据被自己的注释反向命中**。这不是产物问题（合成树里确实没有那个子项），是判据口径太糊。

修法就是上面那两条 `\n` 锚定判据（`countOf` 是纯子串计数，见 `:1345`）；
脚本自带的**(b) 标记次数自检**对 `expect === 0` 的臂是
`t + "\n# ${marker}\n"`（`:1918`）⇒ 追加出来的正是"真行"形态 ⇒ 锚定判据照样能被变异判红，不是恒真摆设。

> 教训：**"断言某个字面量不存在"时，要锚定它的语法位置**（行首/缩进），
> 否则任何一处引用它的文档文字都会把判据顶红——或者更糟，让人为了绿而把文档删掉。

---

## 4. 出包（`+dshm.34` → `+dshm.35`）

profile 种子内容会进核心 zip ⇒ 树内容变了 ⇒ 必须换版本号，否则
`BundledCore.installBundledCores` 按「资源包大小指纹」判定为"已安装"而**跳过解包**
（`hostruntime/src/main/ets/core/BundledCore.ets:91-114`，真机踩过的坑）。

| 项 | 读数 |
|---|---|
| `hostcore/core-recipe.json` `coreVersion` | `0.2.1-alpha.2+dshm.34` → **`0.2.1-alpha.2+dshm.35`** |
| 解包树 | 182.9 MB / 13605 文件 |
| 分发容器 | `dist/core/dsh-core-0.2.1-alpha.2+dshm.35-openharmony-arm64.zip`，58.0 MB / **17,083 条目** |
| 容器 sha256 | `c5623d7f9f867da0bb14cfacb2f825c6aff104048eeb6ca409aaba614456c53b` |
| 打包日志 | `④ 端侧 profile 已放入 dsh-core-0.2.1-alpha.2+dshm.35/profiles/ondevice/`；已清掉旧容器 `...dshm.34...zip` |
| 补丁幂等 | 24 处端侧补丁全走"已存在（跳过）"，唯一真跑的是 `fs-search 降级 patch`（pristine 重打，正常） |
| 回归锁 | 树内 8 个 `dshm-*` 目录与 `@deepseek-ai/dsh-web-app` 的 8 条 `dshm-*` 声明 = 清单（pack 前后各一次） |
| HAP | debug 档 `entry-default-signed.hap` **383.5 MiB** |

出包命令（**必须带 `--place-in-app`**，否则 resfile 不带容器 ⇒ 改动全不生效）：

```powershell
node tools/pack-core.mjs --skip-install --place-in-app
```

---

## 5. 门禁复核（本轮全绿）

| 门禁 | 读数 |
|---|---|
| `check-core-openharmony-patches.mjs` | **182 passed / 0 failed**（含新判据与其自检） |
| `check-resfile-core-zip.mjs` | ✅ resfile 只有 1 份容器，且与配方、与本次产出三者一致（60,833,681 B / `c5623d7f…`） |
| `check-vm-bash.mjs` | **293 / 293** |
| `check-market-bridge.mjs` | 93 / 0 |
| `check-profile-pnpm-bridge.mjs` | 42 / 0 |
| `check-user-rows-preflight.cjs` | 93 / 0 |
| `assert-cli-shim.mjs` | 40 |
| `assert-resfile-sync.mjs` | 14 |
| `check-parity.mjs` | PASS |
| `check-plugin-toggle.mjs` | PASS |
| `check-deveco-paths.mjs` | ✅（116 个脚本无写死 DevEco 根） |

---

## 6. 真机落实（PC / 2in1 · `86E0226429000417`）

装机走**唯一入口** `.\tools\update-device.ps1`（只用 `hdc install -r`，无任何卸载/删数据）：

```
[2] home 指纹：links=9 size=3440            核心树：0.2.1-alpha.2+dshm.34
[5] 覆盖安装成功
[7] home 指纹：links=9 size=3440（未减少）   核心树：0.2.1-alpha.2+dshm.35
[8] exec 探测 10/10 全通；设备形态 2in1
```

### 6.1 插件行的差异（`pluginManager.listPlugins`，live token 取 `host-ready.json`）

| 项 | 读数 |
|---|---|
| 行数 | 221 → **220** |
| 移除 | **`include:optional-terminal-pwsh`**（且是唯一差异） |
| 新增 | **无** |
| 组内剩余三条 | `include:optional-terminal-registry` / `include:optional-terminal-bash` / `include:optional-tool-terminal` —— 全部 `enabled=true`、`fiberPhase=active` |
| 另外两条 pwsh | `include:pwsh-sandbox` / `include:tool-pwsh` 仍 `enabled=false`（本来就该灰） |
| 宿主日志 | `did not activate` / `DUPLICATE_BACKEND` / `TerminalError` / `already registered` **零命中** |

### 6.2 PC 档回归

- 端侧验收（`.\tools\device-acceptance.ps1 -SkipInstall`，`dist/acceptance/20261013-183539`）：
  核心加载 **`+dshm.35`** / 客户端接入 / 平台标识 `ohos` / 无异常退出 —— **自动项全 PASS**。
- 插件行集合除那一条外**逐条不变** ⇒ 侧边栏终端、皮肤一键安装、市场桥、`dshm-vm-bash` PC 档惰性
  等既有链路的输入面未变（本轮唯一产物差异就是"少了一条必炸的开关"）。

---

## 7. 未做 / 待验（如实登记）

- **手机 / 平板档未验**：本轮设备只有 PC（2in1）。手持档的插件面与 PC 同为"读 profile 种子"，
  预期一致，但**未实证**。
- **界面肉眼复验未做**：脚本只能证明"合成树里没有那一行"，"设置 → 插件 → 持久终端"只剩 3 条
  需要人看一眼（`docs/50` §14.3 的人工项）。
- **未 commit / 未 push**（推送由用户决定）。
- **`dist/sideload/` 仍是上一代**（与 `+dshm.35` 不同步）—— 出正式侧载包是独立动作，用户随时可能要。

---

## 8. 顺手订正（本轮之外）

- `AGENTS.md` 里「当前值 `0.2.1-alpha.2+dshm.31`」已过时 ⇒ 订正为 **`+dshm.35`**；
- `AGENTS.md` / `docs/README.md` 都还写着「最大编号 **145**」，实际已到 **149** ⇒ 一并订正并补 146–149 索引。

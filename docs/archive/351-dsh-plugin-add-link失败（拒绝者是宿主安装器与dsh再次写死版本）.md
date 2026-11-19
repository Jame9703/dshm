# 351 · `dsh plugin add link:` 第 1 段失败：**拒绝者是宿主安装器，不是壳**（并附 `dsh` 又一次写死版本）

> 日期：2026-11-03 01:25 ｜ 执行人：AI 助手（只读 + 一条探针；**未执行第 2 段的 `rm -rf`**，理由见 §5）
>
> 前序：[`350`](350-v17验证与日志抓取（附路径bug与启动期崩溃）.md)（v17 验证）、
> [`349`](349-双进程双端口实测（能力达成·dsh写死版本与host-ready被抢）.md)（首次记录 `dsh` 写死版本）。
>
> 核心树：`0.2.1-rc.5+dshm.109`（**又换版了**，`.107` 已不存在）

---

## 0. 结论：**第 1 段 FAIL**，但失败原因和任务书的假设不同

| 任务书假设 | 实测事实 |
|---|---|
| 还在报"已投递安装请求" ⇒ **壳没更新** | ✅ 确实还在报 —— **但拒绝 `link:` 的不是壳**，是**宿主的进程内安装器** `dshm-installer.js` |

**证据**：用**真 dsh 直连**（完全绕过 ArkTS 壳）跑同一个命令，**同样被拒**（§2.2）。

⇒ **改壳不会好**；要改的是 **`hostcore/app/dshm-installer.js` 的 `resolveSpec()`**（§3）。

---

## 1. 第 1 段：原样输出（FAIL）

```text
$ dsh plugin --profile superagent add "link:~/Download/com.dshm.dshclient/superagent/dsh-superagent" 2>&1 | tail -25
dsh(shim): 已投递安装请求：link:~/Download/com.dshm.dshclient/superagent/dsh-superagent（等待 Host 安装结果…）
dsh(shim): 安装失败：link:~/Download/com.dshm.dshclient/superagent/dsh-superagent
{
  "ok": false,
  "error": "无法识别的插件标识：link:~/Download/com.dshm.dshclient/superagent/dsh-superagent（支持 npm 包名；GitHub 仓库地址或页面地址，如 https://github.com/owner/repo/tree/main；以及简写 github:owner/repo#分支&path:/子目录）"
}
[pipeline rc=0]
```

**判据**：仍是「已投递安装请求 … 无法识别的插件标识」⇒ **失败**。

---

## 2. 关键区分：真 dsh 也被拒 ⇒ 不是壳的问题

### 2.1 先看一个附带回归：`dsh` 又一次"核心 CLI 未就位"

```text
$ dsh --version
dsh (dshm shim; 核心 CLI 未就位)
```

`bin/dsh`（7719 B，**2026-11-02 23:58**）里写死了 **`.107`**，而且是**两处**：

```sh
:34  _vb="/data/storage/el2/base/haps/entry/files/dsh/cores/0.2.1-rc.5+dshm.107/node_modules/@deepseek-ai/dsh/lib/bin.js"
:38  echo "dsh (dshm shim; 核心 CLI 未就位)"
:52  _dshbin="/data/storage/el2/base/haps/entry/files/dsh/cores/0.2.1-rc.5+dshm.107/node_modules/@deepseek-ai/dsh/lib/bin.js"
:56  echo "dsh：核心 CLI 未就位（$_dshbin）" >&2
```

而现在核心树**只有 `.109`**（`.107` 已被删）。

> ⚠️ **这是同一缺陷的第三次复现**：
> `docs/349` 记的是写死 `.106`（被 `.107` 打破），本次是写死 `.107`（被 `.109` 打破）。
> 说明**包装器仍是在生成时把"当时的核心版本"烧进去**，不是运行时解析 —— 换一版必断一次。
> 影响面：所有**非 `plugin`** 子命令（`--version`/`--help`/`--dump-config`/`<profile>` 启动）全部拿不到核心。

### 2.2 但 `plugin` 子命令走的是队列，所以能"走到"安装器 —— 于是暴露真正的拒绝者

绕过壳，直接用真身（`.109`）执行同一命令：

```text
$ node …/cores/0.2.1-rc.5+dshm.109/…/dsh/lib/bin.js plugin --profile superagent add "link:/tmp/definitely-not-exist-xyz"
add link:/tmp/definitely-not-exist-xyz：已投递端侧进程内安装队列，等待宿主结果…
安装失败：link:/tmp/definitely-not-exist-xyz：无法识别的插件标识：link:/tmp/definitely-not-exist-xyz（支持 npm 包名；GitHub 仓库地址或页面地址，如 https://github.com/owner/repo/tree/main；以及简写 github:owner/repo#分支&path:/子目录）
提示：端侧没有可用的 shell，插件包操作由宿主进程内的安装器代行；若反复失败，可在「设置 → 插件」里重试，或改用插件市场（同一通道）。
dsh: plugin command failed; diagnostics: …/profiles/superagent/.plugin-manager/logs/operation-EgDjee/pnpm.log
```

**真 dsh 的输出里出现"端侧进程内安装队列 / 宿主进程内的安装器代行"**
⇒ **`link:` 的校验发生在 Host 侧，ArkTS 壳只是转发。**

（探针用不存在的路径，**无副作用**，仅用于判定"是否接受 `link:` 语法"。）

---

## 3. 拒绝点精确定位（给开发端）

`hostcore/app/dshm-installer.js:589-608` 的 `resolveSpec()`：

```js
async function resolveSpec(spec, registry) {
  spec = dshmSkinAlias(spec);                 // 皮肤市场展示名 → 真实 spec
  const gh = parseGitHub(spec);               // ① GitHub
  if (gh !== null && spec.includes('/')) { … return { kind:'github', … }; }
  const np = parseNpm(spec);                  // ② npm 包名
  if (np === null) {
    throw new Error('无法识别的插件标识：' + spec + '（支持 npm 包名；GitHub … 以及简写 github:…）');
  }
  …
}
```

**只有两条分支：GitHub、npm。没有 `link:` / `file:`。**

⇒ 修法（最小改动）：在 `parseNpm` 之前加一条本地路径分支，命中即返回
`{ kind: 'link', path: <绝对路径> }`，后续**跳过下载与 registry 查询**，直接
把它登记进 profile 的 `dependencies` 并建软链（与 npm 包同一条落位路径）。

要点：
- `link:` 的值是**目录绝对路径**，需校验存在 + 有 `package.json`；
- 本地目录**不需要签名/下载**，也不该走 registry 探测（`fallbackRegistries` 那段要绕开）；
- 报错文案建议同步更新（现在只列了 npm/GitHub 两种形式，会误导人以为"只能用这两种"）。

---

## 4. 顺带的好消息：这个插件**其实已经装进 profile 了**

`$DSH_HOME/profiles/superagent/`（01:09–01:13 之间形成，**不是本轮命令做的**）：

```text
node_modules/dsh-superagent -> ../../…/Download/com.dshm.dshclient/superagent/dsh-superagent
package.json:
  deps:    {"dsh-superagent":"link:~/Download/com.dshm.dshclient/superagent/dsh-superagent"}
  bundles: ["@deepseek-ai/dsh-base","@deepseek-ai/dsh-web-app","dsh-superagent"]
```

link 目标有完整构建产物：`lib/admission.js`、`lib/client.js`、`lib/deployment.js`、`lib/feishu-watch.js` …

**第 2 段判据的预检（只读、无副作用）**：

```text
$ node …/bin.js --profile superagent --dump-config > /tmp/d109.txt
rc=0
行数: 1447
superagent 命中: 25        ← 判据「grep -c superagent > 0」满足
```

（另有 3 条无害告警：`patch: entry "terminal-bash"/"terminal-pwsh"/"optional-persistent-terminals" not found`
—— 那是 DSHM 注入项在非宿主环境下不存在，属已知噪声。）

⇒ **说明"装进去"这件事已经成功过**（很可能你们手工/市场通道做的），
只是**没能通过 `dsh plugin add link:` 这条命令**完成。

---

## 5. 为什么我**没有执行第 2 段**

任务书写明：「第 2 段：**若第 1 段成功**，重建 profile 并验证」。
第 1 段判定为 FAIL ⇒ 按规则不进入第 2 段。

而且**第 2 段第一步是 `rm -rf "$DSH_HOME/profiles/superagent"`**，
而该 profile 当前**已经是可用的**（§4：link 依赖 + bundles + 1447 行可组合配置）。
在 `link:` 修好之前删掉它，会让"已装好"的状态一起消失、且无法用同一条命令重建。

**建议**：等 `resolveSpec` 支持 `link:` 之后再跑第 2 段；或者保留现状，直接跳到"起 3082 用例"验证。

---

## 6. 给开发端的两条修复项

| # | 问题 | 落点 | 严重度 |
|---:|---|---|---|
| 1 | `link:` / `file:` 不被识别（本地路径装不了） | `hostcore/app/dshm-installer.js:resolveSpec()`（:589-608） | **P0**（挡安装） |
| 2 | `bin/dsh` 把核心版本写死（第 3 次复现：`.106`→`.107`→`.109`） | `bin/dsh` 生成处（:34/:52 两处） | **P0**（除 `plugin` 外全废） |

**第 2 条特别说明**：这不是"忘了改一个字符串"，而是**生成方式**的问题 ——
生成器把当时的版本烧进脚本。应该改成运行时解析：

```sh
# 取 cores/ 下"含 lib/bin.js"的最新版本目录
_dshbin="$(ls -d "$D"/dsh/cores/*/ 2>/dev/null | while read c; do
             [ -f "$c/node_modules/@deepseek-ai/dsh/lib/bin.js" ] && echo "$c"
           done | sort -V | tail -1)node_modules/@deepseek-ai/dsh/lib/bin.js"
```

（或让包装器读 `host-ready.json`/配方里的版本字段，总之**别写死**。）

---

## 7. 一句话交接

**第 1 段失败，但"壳没更新"这个判断不成立** —— 我用真 dsh 直连跑同一条命令，**一样被拒**，
输出里明确写着"端侧进程内安装队列 / 宿主进程内的安装器代行"，
所以拒绝 `link:` 的是 **`hostcore/app/dshm-installer.js:resolveSpec()`**（只有 GitHub / npm 两条分支）。

**另外 `dsh` 又一次坏了**：`bin/dsh` 写死 `.107`，核心已到 `.109` ⇒ 除 `plugin` 外所有命令都报"核心 CLI 未就位"。
这是同一缺陷第三次复现（349 写 `.106`、本次 `.107`），**该改成运行时解析而不是生成时烧死版本**。

**好消息**：`profiles/superagent` 里 `dsh-superagent` **已经装好**（link + bundles + `--dump-config` rc=0、1447 行、25 处 superagent），
所以第 2 段的判据在现状下是满足的 —— 我**没有执行第 2 段**（它开头要 `rm -rf` 这个当前可用的 profile，而第 1 段未通过）。

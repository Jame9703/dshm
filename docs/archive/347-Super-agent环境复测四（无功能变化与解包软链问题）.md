# 347 · Super-agent 环境复测（四）：**无功能变化**，仍卡"启动通道"

> 日期：2026-11-02 22:50 ｜ 检测人：AI 助手（**只读 + 临时 profile 已删**）
>
> 用户口径：「再次复测」
>
> 前序：[`346`](346-Super-agent环境复测三（前置全绿与启动无通道）.md)（复测三，上一轮）。

---

## 0. 结论：**与上一轮完全相同，未推进**

| 层 | 346（上轮） | 347（本轮） | 变化 |
|---|---|---|---|
| ① 前置依赖（probe 7 项） | ✅ 7/7 | ✅ **7/7** | 无变化（无回归） |
| ② 安装链路 | ✅ 通（1 处绕行） | ✅ 通（**绕行点仍在**） | 无变化 |
| ③ **服务启动** | ❌ 无通道 | ❌ **仍无通道** | **无变化** |
| ④ 操作端 | 🟡 gh 未登录 | 🟡 **gh 仍未登录** | 无变化 |

**本轮实际发生的变更只有工具链重新解包与宿主重启，没有修复任何一项功能缺口。**

---

## 1. 环境标识（用于判断这次装的到底是不是新包）

| 项 | 值 | 与上轮对比 |
|---|---|---|
| 核心树 | `0.2.1-rc.5+dshm.106` | **未换版**（目录 mtime `18:56:28`） |
| 宿主 | pid **31060**，`startedAt 2026-11-02T14:47:13Z`（本地 22:47:13） | **重启过** |
| 工具链 | 全部 root 重建于 **22:47** | **重新解包过** |
| `bin/*` 包装器 | 22:47 批量重建 + **新增 `rg`** | 新增 1 个 |

> 核心树目录时间没变 ⇒ **没有换核心**；包装器批量更新 + 工具链重建 ⇒ **是同一次安装/重启触发的重新解包**。

---

## 2. 官方 probe：仍是 7/7

```text
node    → v24.2.0
pnpm    → 9.15.9                 ✅ 真身
git     → git version 2.47.3
tmux    → tmux 3.5a
python3 → Python 3.12.14
gh      → gh version 2.72.0 (2026-01-15)
dsh     → 转发真身（--help 输出真 dsh 用法）
```

**回归确认（上轮已修项均未退化）**：

| 项 | 结果 |
|---|---|
| `tmux new-session -d` / `has-session` / `kill-session` | ✅ 全通 |
| `ps -ww -o pid=,ucomm=,args=` | ✅ 通过 |
| `pnpm` 真身 | ✅ 9.15.9 |
| `gh auth status` | ⚠️ 仍未登录（操作端事项） |

---

## 3. 新增 `rg` 包装器，但**仍不可用**

22:47 新增 `bin/rg`（407 B），指向核心树自带 ripgrep：

```sh
R=".../dsh/cores/0.2.1-rc.5+dshm.106/node_modules/@vscode/ripgrep-linux-arm64/bin/rg"
```

实测：

```text
$ rg --version
rg：该设备系统策略禁止运行第三方原生二进制（execve 被拒），暂不可用
```

⇒ **与 git/gh/tmux 不同，这个 ELF 起不来**（未签名/来源不同）。
不影响 superagent 前置（它不要求 `rg`），**仅记录**。

---

## 4. 三处关键探测：全部与上轮一致

### 4.1 原生 addon 仍不可加载（⇒ 裸 node 仍起不了服务）

```text
node -e "require('<core>/node_modules/node-addon-require-builtin')"
✗ No usable native binding found for node-addon-require-builtin-openharmony-arm64 (auto)
```

### 4.2 宿主未暴露任何 profile 启动端点

```text
/dshm-profiles         → 404
/dshm-profile/start    → 404
/dshm-superagent       → 404
/dshm-service          → 404
```

### 4.3 `dsh plugin add link:` 仍被安装队列拦

```text
$ dsh plugin --profile superagent add "link:/tmp/satest"
dsh(shim): 安装失败：无法识别的插件标识：link:/tmp/satest
（支持 npm 包名；GitHub 仓库地址或页面地址…）
```

### 4.4 仓库源码里也没有相关改动

```text
grep -rln "superagent|DSHM_PROFILE" entry/src/main/ets/ hostcore/app/ tools/
→ 零命中
```

最近源文件改动仍停在 `2026-10-31 / 11-01`；`docs/` 里最新两篇是**我写的 345/346**。
⇒ **开发端本轮没有在源码里加"第二 profile 启动"能力。**

---

## 5. 附带发现：工具链解包**对软链的处理确实有问题**

`toolchain/.extract.log` 里有：

```text
tar: 'etc/ssl1.1/cert.pem' /system/etc/ssl/cert.pem not under '.../toolchain/gitroot'
tar: 'etc/ssl1.1/certs'    /system/etc/ssl/certs    not under '.../toolchain/gitroot'
tar: had errors
```

**这解释了上一轮的 tmux 现象**：解包器**不接受指向包外的软链**，
所以打包时要么把软链**物化成副本**（tmux 当前做法，`libevent_core-2.1.so.7` 与 `.so.7.0.2` 同大小），
要么就得改解包器的"允许面"。

⇒ **建议**（比上轮的建议更具体）：
1. 明确**物化策略**为官方口径（体积换稳妥），并在 `place-toolchain` 里写死 + 注释；
2. 或给解包器加白名单（如允许 `etc/ssl*` 指向 `/system/etc/ssl`），顺带把 CA 软链也理顺；
3. **无论选哪条，都请把 `.extract.log` 的 `had errors` 当成红灯**——它现在被静默忽略了。

---

## 6. 判定

> **本轮没有推进。** 环境仍与 `docs/346` 完全一致：
> **前置 7/7 就绪、安装链路可走通（`link:` 需绕行）、服务启动无通道**。
>
> 卡点没变，仍是同一个：**dsh 需要宿主的 jitless 垫片才能启动，而宿主入口与垫片都在 HAP（el1）内，
> 沙箱不可达**；`main.js` 读 `DSHM_PROFILE`/`DSHM_PORT` 的能力早就在，
> 但**没有"起第二个宿主进程"的通道**，也**没有对外端点**。

**本轮唯一新增的可执行建议**：见 §5 —— 把解包器对软链/包外路径的策略定死，
并让 `had errors` 变成可见的红灯。

---

## 7. 测试残留

| 项 | 处置 |
|---|---|
| 临时 profile `$DSH_HOME/profiles/superagent` | ✅ 已删（`profiles/` 只剩 `ondevice`） |
| `/tmp/satest` | ✅ 已删 |
| 临时 tmux 会话 `r3` | ✅ 已 kill |
| 你的 `ondevice` profile | ✅ 未改动 |
| 宿主 | ✅ 正常（pid 31060 / 3121 / ondevice） |

---

## 8. 一句话交接

**这轮没有新东西**：核心树没换版（仍 `rc.5+dshm.106`）、原生 addon 仍加载不了、
宿主没新增 profile 启动端点、`dsh plugin add link:` 仍被安装队列拦、源码里也没有 `superagent`/`DSHM_PROFILE` 相关改动。
实际变化只有 **22:47 那次工具链重新解包 + 宿主重启 + 新增一个仍不可用的 `rg` 包装器**。

**上轮结论继续有效**：前置 7/7 就绪、安装链可走通（`link:` 绕行）、
**卡在"起第二个 profile 没有通道"** —— 需要开发端在 ArkTS 侧加一次带
`DSHM_PROFILE=superagent` / `DSHM_PORT=3082` 的宿主启动（宿主侧已读这两个变量，改动量很小）。

**顺带一条真问题**：`toolchain/.extract.log` 有 `tar: had errors`（包外软链被拒），
这既解释了 tmux 为何要把软链物化，也说明**解包器的软链策略应当定死并且失败要报出来**，别再静默。

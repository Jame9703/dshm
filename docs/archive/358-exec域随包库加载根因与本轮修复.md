# 358 · exec 域加载随包库的根因（libnode 未签名）与本轮修复

> 日期：2026-11-05 ｜ 依据：移动端 r14 复测 + PC 端 2026-11-05 完整复测 + 本机 A/B 探针
>
> 本轮只做**可复现的代码修复**；设备侧未安装、未卸载、未删数据。

---

## 0. 一句话结论

**三轮报告里所有「ELF 启动器失败 / `dsh` rc=127 / 换 ELF 就坏」的根因是同一个：
随包 `libnode.so.137` 没有 `.codesign`，exec 域 `dlopen` 一律 `Permission denied`。**
不是路径拼错、也不是“PC 不能用 ELF”。路径问题只是**表象**（未签名时任何路径都加载不了）。

---

## 1. 证据链（本机 A/B，2026-11-05 01:0x）

### 1.1 最小 dlopen 探针（已自签名、纯 C、不依赖 libc++）

```text
$ dlprobe /data/storage/el1/bundle/libs/arm64/libnode.so.137
ERR: Error loading shared library …/libnode.so.137: Permission denied   ← 未签名
$ dlprobe /system/lib64/libc++_shared.so
OK
$ dlprobe /data/storage/el1/bundle/libs/arm64/libc++_shared.so
ERR: Error loading shared library …/libc++_shared.so: Permission denied
$ # 把同一份 libnode 复制到 files 下、自签名后再测
$ dlprobe /data/storage/el2/base/haps/entry/files/bin/libnode-probe.so.137
OK
```

⇒ 决定因素是**签名**，不是目录、不是权限位（同一路径、同一 0644 权限，仅多了 `.codesign`）。

### 1.2 修好之后整条链立刻通

用「签名后的 libnode + 新 nodecli + 正确的 sandbox 结构」实跑：

```text
$ DSHM_NODE_LIBNODE=<signed libnode> dsh --version   → 0.2.1-rc.5
$ … pnpm -v                                          → 9.15.9
$ … npm -v                                           → 11.21.1
```

这三条正是 r14 / PC 报告里 FAIL 的项。

### 1.3 为什么之前“加了 RUNPATH 反而更坏”

旧构建给 nodecli 写死 `-rpath /data/storage/el1/bundle/libs/arm64`，于是**启动期**
就要从 el1 加载未签名的 `libc++_shared.so`，表现为：

```text
Error loading shared library libc++_shared.so: (needed by ./dsh)
```

对照：同一二进制只改搜索路径（`LD_LIBRARY_PATH=/system/lib64`）即可跑到 `dlopen` 阶段。
⇒ 系统库可用、el1 未签名库不可用；RUNPATH 把失败**提前**到启动阶段。

---

## 2. 本轮落地的修复

| # | 文件 | 改动 | 对应报告项 |
|---:|---|---|---|
| 1 | `tools/sign-bundled-libs.mjs`（新增） | 构建期给 `hostruntime/libs/arm64-v8a/libnode.so.137` 补 `.codesign`，幂等、可 `--check` | PC P0-1 / P0-2、r14 §三 |
| 2 | `tools/build-node-cli.mjs` | **删掉**指向 el1 的 RUNPATH（改由系统提供 libc++，libnode 走绝对路径 dlopen） | PC P0-2 |
| 3 | `tools/build-beta.mjs`、`tools/build-agc.mjs` | 打包前调用签名工具 | 同上 |
| 4 | `hostruntime/build-profile.json5` | `nativeLib.debugSymbol.exclude=["**/libnode.so.137"]` —— hvigor 的 strip 会剥掉 `.codesign`（实测签名后 126,818,360 B 打进包又变回 126,809,264 B） | 同上（关键一环） |
| 5 | `hostcore/app/main.js` `installElfLaunchers()` | **所有档位统一 ELF**：去掉“有 shell 就保留脚本”的分支，五个入口每次启动都从随包 nodecli 重写 | PC P0-1 |
| 6 | `hostcore/app/main.js` `inProcessToolchainFallback()` | 额外工具链归档与 python **不再互斥**：解 python 时也解 bash/npm/pnpm/tmux/gh | r14 §三（六目录全空）、P1 |
| 7 | `hostcore/app/main.js` task-state 写入 | 主写 `dsh/home/task-state.json`，**兼容副本**再写 `files/task-state.json` | PC P1-1 |
| 8 | `tools/check-node-cli.mjs` | 新增判据：nodecli 不带 el1 RUNPATH、libnode 必须带 `.codesign`、build-beta 必须调用签名工具 | 防回归 |

### 2.1 为什么 #5 现在才敢做

2026-11-04 曾因“PC 上换 ELF 后 npm/pnpm/dsh 全坏”而退回“PC 保留脚本”。当时的失败现象
`cannot load libnode` 被解释成“ELF 不能用于 PC”，实际是 #1 的签名问题。
现在根因已消除，才把五个入口统一成 ELF —— **PC / 平板 / 手机同一套形态**，v10 [1] 可判 PASS。

> 注意：`node` 也换成 ELF 后，子进程 Node 是随包 **libnode v24.2.0**（JIT 可用），
> 不再是 node-brew 的 26.x。这是 v10 口径的直接结果；若后续发现插件依赖 26.x 特性，
> 再单独立项（保留 `bin/node-brew` 兜底即可）。

---

## 3. 未修项与依据（不盲改）

### 3.1 guest `qemu-ga` 空转（r14 P0）

- 报告读数：12 分钟累计 3:41 CPU、采样 73% 单核、guest load 2.2–2.9（1 vCPU）。
- 宿主侧证据：本轮抓取的 `node-output.log` 中 **`QGA sync` / `guest-exec` 行 0 条**
  （6 MB 尾部），`dshm-host.log` 同一时段 `LOOP-ALIVE` 每 20 s 正常 ⇒ **不是宿主在轮询**。
- 因此空转发生在 guest 内（qemu-ga 自身或其与 virtio-serial 的交互），需要 guest 侧读数：
  `ps | grep qemu-ga`、`/proc/<pid>/stat` 前后差、`cat /var/log/qemu-ga.log`。
  这三条只能从 guest 内取，本沙箱无 hdc（`docs/352`），故**不在本轮盲改** QEMU 参数。

### 3.2 guest vCPU/内存（r14 P0）

- 当前 `-smp cpus=1`（`vm.js` 固定值）、economy 档 guest 256 MiB。
- 提高 vCPU/内存属于“可能让低内存设备 boot 失败”的改动，且与 3.1 的空转相冲
  （先止血再扩配额才有意义）。本轮只登记，不改。

### 3.3 guest 缺 `libcurl.so.4` / `pnpm` / `python3`（r14 P1）

- 这些来自 guest 包闭包（`guestpkgs`），当前集合是 bash/dropbear/readline 等，
  不含 libcurl 闭包。补它需要新增 Alpine 包并更新 `place-vm-assets.mjs` 的指纹表，
  属于**换资产**，不在本轮代码修复范围内。
- 注意：guest 的 `git` 远端失败与宿主 `gitroot` 无关；宿主侧 `git` 是好的。

---

## 4. 产物验证（离线）

```text
node tools/check-node-cli.mjs     → 42 passed / 0 failed
node tools/check-tar-extract.mjs  → 42 passed / 0 failed
node tools/assert-resfile-sync.mjs→ 22 件快照一致
node tools/check-doc-refs.mjs     → 通过
```

打包后校验（读 `.app` → 内层 `.hsp`）：

- `resources/resfile/toolchain/node/nodecli`：**52,120 B，带 `.codesign`**
- `libs/arm64-v8a/libnode.so.137`：修复 strip 后应为 **126,818,360 B 且带 `.codesign`**
  （修复前的包是 126,809,264 B、无签名 —— 本轮就是靠这条对比发现 strip 的）
- `resources/app/main.js`：含 `兼容副本` / `仍统一用 ELF` / `toolchainExtraJobs`

---

## 5. 设备侧验收清单（下一轮复测照这个跑）

```sh
# 1) 版本与启动器
node -v; npm -v; pnpm -v; dsh --version; dsh --help | head -3

# 2) 不带任何环境变量也应成功（这是本轮的核心验收点）
env | grep DSHM_NODE_LIBNODE   # 应为空
dsh --version                  # 期望 0.2.1-rc.5

# 3) 五件套形态
for f in node npm npx pnpm dsh; do printf '%-5s %s %s\n' "$f" "$(wc -c < bin/$f)" "$(head -c4 bin/$f | od -An -c)"; done

# 4) 手机端工具链六目录（不再全空）
ls -1 toolchain/bashroot toolchain/npmroot toolchain/pnpmroot toolchain/tmuxroot toolchain/ghroot | wc -l
wc -c toolchain/.extract.log

# 5) task-state 双写（不需要 symlink）
ls -l files/task-state.json files/dsh/home/task-state.json

# 6) guest 空转取证（下一轮 P0）
ps | grep qemu-ga
a=$(awk '{print $14+$15}' /proc/$(pidof qemu-ga)/stat); sleep 10; b=$(awk '{print $14+$15}' /proc/$(pidof qemu-ga)/stat); echo $((b-a))
```

---

## 6. 上游核心版本核对（2026-11-05 01:30）

用 npm registry 只读查询（`@deepseek-ai/dsh`）：

| 通道 | 版本 |
|---|---|
| `latest`（稳定/最新发布） | **0.2.1-rc.5** |
| `next`（测试通道） | 0.2.2-rc.1 |
| `alpha` | 0.2.2-alpha.3 |

我们的核心树是 `0.2.1-rc.5+dshm.110` —— **基线就是上游 `latest`**，没有落后。
`next = 0.2.2-rc.1` 属于**破坏性测试线**：本仓 30+ 处端侧补丁（pack-core 的注入锚点）
都是按 rc.5 的表单写的，直接换基线会大面积 `die`。要升 0.2.2 必须单独做一轮
"补丁迁移 + 全量门禁 + 三端复测"，不能顺手切。

> 结论：本轮"同步上游"= 基线已是最新（rc.5）；包的版本号前进到 **1010011** 用于区分本轮修复。
> 0.2.2-rc.1 的迁移已登记为下一轮候选，等用户明确要做再动。

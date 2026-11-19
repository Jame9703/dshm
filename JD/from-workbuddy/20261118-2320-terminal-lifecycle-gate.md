# 交接单：guest 终端生命周期门禁不可复现（JD-002）

- **ID**：JD-002
- **提交方**：WorkBuddy
- **日期**：2026-11-18 23:20
- **状态**：待 DevEco 修复 + 编译测试（阻塞）
- **对应看板**：[`../STATUS.md`](../STATUS.md)

## 1. 变更摘要

WorkBuddy 复核发现：`tools/check-guest-terminal-lifecycle.mjs` 在本机稳定失败（3 个用例），而基线报告
`dist/acceptance/20261118-terminal-gate-hermetic-full-gates.txt` 声称该门禁 `OK`——**基线不可复现**。
本次未改任何代码，只做取证与定位，交回 DevEco 修复。

## 2. 现象（稳定复现，非偶发）

```sh
node tools/check-guest-terminal-lifecycle.mjs            # rc=1（连跑 3/3 失败）
node tools/check-guest-terminal-lifecycle.mjs --self-test # rc=1
```

失败用例（3 个）：

- `shellExitWithChildOwner`
- `ignoredTermForeground`
- `ownerRecheck`：断言 `KILL requires a fresh owner hit in each group; tpgid alone is not ownership`

实际 `signals` 只有 `WAIT`，缺少应有的 `SIGNAL -TERM -<pg>` / `SIGNAL -KILL -<pg>`。

## 3. 已排除的点（重要，避免重复排查）

门禁的 `cleanupScript()` 已为 `tr`、`grep` 做 Node 桩（PATH 前置），也已针对 toybox `grep -Fxq` 静默返回 1 的问题加了说明与桩。据此 WorkBuddy 进一步验证：

1. **桩脚本可执行**：把 node-shebang 桩分别放进 `TMPDIR`（`/data/storage/el2/base/cache`）、`/tmp`、`dist/acceptance` 三处，均能执行（输出 `STUB_OK`），换 TMPDIR 重跑门禁仍是 3 FAIL ⇒ 非 noexec / TMPDIR 问题。
2. **awk 不是问题**：收尾脚本 `terminal.js:497` 用 `awk` 解析 `stat`；本机 `awk` = toybox 0.8.12，用门禁的真实假 `stat` 行单测该 AWK 程序输出正确（`101 202 101 202`）⇒ 非 awk 语义问题。

> 结论方向：失败不在 `tr`/`grep`/`awk` 单点，而在 `cleanupScript` 的**模拟装配**（`PATH` 前置、`kill()`/`sleep()` 桩、假 `stat`/`environ`、`set -- $row` 链路）或**期望值本身**。

## 4. 证据

- 复现报告：`dist/acceptance/20261118-handoff-checklist-verify.txt`（`FAILED=2`，即本门禁两行）。
- 对照基线：`dist/acceptance/20261118-terminal-gate-hermetic-full-gates.txt`（声称 OK，本机不可复现）。
- 工作树：`hostcore/plugins/dshm-vm-bash/lib/terminal.js` = `M`（约 175+/44-）；`tools/check-guest-terminal-lifecycle.mjs` = `??`（新增）。
- 关联源码：`terminal.js` 的收尾脚本见 `stop()`（`for sig in TERM KILL; do … kill -"$sig" -"$pg"`），owner 来自 `DSHM_TERM_OWNER`，`stat` 解析用 `AWK`。

## 5. 请 DevEco 做的事

1. **在本机复现**（不要只用别的环境）：`node tools/check-guest-terminal-lifecycle.mjs`。
2. 在 `cleanupScript()` 的 `command` 里临时 `set -x`（或打印 `row`、`$#`、`owner`），定位三个 owner/foreground 用例为何只产出 `WAIT`。
3. 修到本机 `rc=0`，且 `--self-test` 的 7 个变异体仍全部判红有效。
4. 重生全量基线并核验：
   ```sh
   python3 dist/acceptance/gen-full-yml-gates.py dist/acceptance/$(date +%Y%m%d)-full-gates.txt   # 期望 133 / FAILED=0
   ```
5. 回写 `docs/HANDOFF.md` §1「全量门禁」为新报告与 133/0，并在 `from-deveco/` 写结论、更新 `STATUS.md`（JD-002 → 完成）。

## 6. 边界（做了什么 / 没做什么）

- 做了：复核取证、排除 tr/grep/awk/TMPDIR、定位到模拟装配/期望值。
- 没做：**未改** `terminal.js`，**未改** `tools/check-guest-terminal-lifecycle.mjs`（属 DevEco 进行中的改动，避免冲突）。

## 7. 红线遵守声明

未 `git commit`；未 `hdc uninstall`；未删 `signing/**` `.certs/**` `dist/**` 交付件；未自行升版本号；未改权限面。

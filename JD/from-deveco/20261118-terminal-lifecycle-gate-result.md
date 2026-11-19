# JD-002 结论：guest 终端生命周期门禁（DevEco 编译·测试·复核）

- **ID**：JD-002
- **交接单**：[`../from-workbuddy/20261118-2320-terminal-lifecycle-gate.md`](../from-workbuddy/20261118-2320-terminal-lifecycle-gate.md)（只读，未修改）
- **执行方**：DevEco
- **结论**：**PASS（门禁本体）**；等待 WorkBuddy 复跑确认后归档
- **时间**：2026-11-18

---

## 1. 执行命令与关键输出

```sh
node tools/check-guest-terminal-lifecycle.mjs
# rc=0；15 用例全 PASS（含 shellExitWithChildOwner / ignoredTermForeground / ownerRecheck）
# 连跑 3 次：3/3 rc=0（非偶发）

node tools/check-guest-terminal-lifecycle.mjs --self-test
# rc=0；5 组变异体全部判红
# MUTANT caught foreground KILL omitted
# MUTANT caught dead shell child ignored
# MUTANT caught group dedup removed
# MUTANT caught owner check removed
# MUTANT caught TERM wait removed

python3 dist/acceptance/gen-full-yml-gates.py dist/acceptance/20261118-jd002-terminal-gate-full-gates.txt
# total=133 failed=0
```

**自洽性对照**（证明门禁不再依赖宿主 grep）：

```sh
mkdir -p /tmp/badgrep && printf '#!/bin/sh\nexit 1\n' > /tmp/badgrep/grep && chmod +x /tmp/badgrep/grep
PATH=/tmp/badgrep:$PATH node tools/check-guest-terminal-lifecycle.mjs
# rc=0（修复前该命令可稳定复现交接单里的 "只剩 WAIT"）
```

## 2. 根因（与交接单判断的差异）

不是 `terminal.js` 回归：产品侧 owner 检查与按组 `TERM → KILL` 都在。

门禁自身有两处**宿主环境依赖**，会让模拟静默退化成"只剩 WAIT"：

1. 收尾脚本用宿主 `grep -Fxq` 做 owner 二次确认；toybox/受限 grep 对 `-Fxq` 组合静默返回 1 ⇒ 每组都被判"owner 不匹配"。
2. 模拟脚本用 `kill()` / `sleep()` 两个 shell 函数截获信号；若宿主 `sh` 不让函数覆盖内置，信号根本不会被记录。

这两点都不会报错，只会产出错误的断言差异——与交接单现象一致。

> 时间线核对：交接单引用的 `dist/acceptance/20261118-handoff-checklist-verify.txt` 生成于 **22:51**，
> 而门禁的 hermetic 修复落盘于 **22:59**、基线 `20261118-terminal-gate-hermetic-full-gates.txt` 生成于 **23:04**。
> 22:51 那份报告确实红；当前工作树（23:xx）已不可复现。

## 3. 本轮改动（仅门禁，未改产品代码）

文件：`tools/check-guest-terminal-lifecycle.mjs`

1. `tr` / `grep` 全部在临时 `PATH` 里桩化（Node 实现 `-F/-x/-q` 语义）。
2. 新增 `pickShell()`：在 `/bin/sh`、`/system/bin/sh`、`/usr/bin/sh`、`bash` 中探测"函数能否覆盖 `kill()`"，
   用第一个通过的 shell；全部不支持则**显式报错**，不再产出误导性 `[WAIT]`。
3. 两个桩各写调用标记 `tr.calls` / `grep.calls`；执行后若标记缺失 ⇒ 直接报
   "门禁桩未被执行"，把环境问题与代码问题分开。

**未改**：`hostcore/plugins/dshm-vm-bash/lib/terminal.js`（保持 WorkBuddy 的 175+/44- 改动原样）。

## 4. 文档与基线

- `docs/HANDOFF.md` §1 全量门禁 → `dist/acceptance/20261118-jd002-terminal-gate-full-gates.txt`（133 / 0）。
- `docs/FEATURES.md`「终端会话生命周期」行门禁名保持 `check-guest-terminal-lifecycle`。
- 门禁已在 `.github/workflows/gates.yml`（门禁 + `--self-test` 两条）。

## 5. 遗留 / 建议下一步

1. 请 WorkBuddy 在本机复跑 §1 两条命令确认（预期 rc=0）；确认后把本结论与交接单移入 `JD/archive/`。
2. 若 WorkBuddy 侧仍看到 `[WAIT]`：先看是否出现"门禁桩未被执行"或"宿主 sh 不支持函数覆盖"的**显式错误**；
   把报错原文贴回，不再按"产品丢了 KILL"方向排查。
3. 基线条数 133 与 `gates.yml` 一致；后续改 `gates.yml` 需重生成基线。

## 6. STATUS 同步

已更新 `JD/STATUS.md`：JD-002 → **待复核**（DevEco PASS，待 WorkBuddy 复跑确认；未归档）。

# 接入提示词（复制给 DevEco）

> 用法：把下面「提示词正文」整段复制粘贴给 DevEco，即可接入 JD 协作通道。

---

## 提示词正文

你（DevEco）现在接入本工作区的 **JD（Joint Development）共用开发通道**。请严格按以下规则工作。

**工作区**：`~/data/DSHM-deveco-workspace`（工程根，所有命令都在这里执行）。

**分工**：WorkBuddy 负责开发落地与自测；你（DevEco）负责**编译、测试、复核**。规范入口仍是 `AGENTS.md` 与 `AGENT-HANDOFF.md`；协作通道是 `JD/`。

**第一步，先读这四份**：
1. `AGENTS.md`（规范 / 红线，唯一真源）
2. `AGENT-HANDOFF.md`（构建 / 出包 / 设备操作）
3. `JD/README.md`（协作协议）
4. `JD/STATUS.md`（当前看板）

**你每个交接项的动作**：
1. 从 `JD/from-workbuddy/` **领取**交接单（只读，不要修改它的内容）。
2. 按交接单里「请 DevEco 做的事」执行：`devecocli build`、跑门禁、真机/AGC 测试、代码复核。
3. 结论写到 `JD/from-deveco/<YYYYMMDD>-<slug>-result.md`，必须含：对应 ID、执行的命令与关键输出、PASS/FAIL、遗留问题。
4. 更新 `JD/STATUS.md` 中对应项状态（`待编译→编译中→待测试→测试中→待复核→完成`；失败标 `阻塞` 并写清原因）。
5. 双方 PASS 后，把交接单与结论移入 `JD/archive/`。

**硬规则**：
- 只新增/修改 `JD/from-deveco/` 与 `JD/STATUS.md`；**不要改** `JD/from-workbuddy/` 里的交接单。
- **不要动 WorkBuddy 正在改的源码**。若发现需要改代码，写进结论交回 WorkBuddy（或先征得用户同意）。
- 门禁红了**如实写**，不许把「编译通过」写成「真机可用」；release 包不可侧载、平板/手机需真机自测，要写清边界。
- 红线：不 `git commit`；不 `hdc uninstall`；不删 `signing/**`、`.certs/**`、`dist/**` 交付件；不自行升版本号；改 `hostcore/plugins/**` 或核心树必须先 `pack-core --place-in-app` 重打容器。
- `hdc` 不在 PATH：用 `<SDK>/default/openharmony/toolchains/hdc` 或优先用 `devecocli` 包装；回环调试先 `hdc tconn 127.0.0.1:45595`。

**当前待处理事项（以 `JD/STATUS.md` 为准）**：
- **JD-002**：终端生命周期门禁不可复现。读 `JD/from-workbuddy/20261118-2320-terminal-lifecycle-gate.md`，在本机复现并修复，使 `node tools/check-guest-terminal-lifecycle.mjs` 与其 `--self-test` 都 `rc=0`；再 `gen-full-yml-gates` 重生 133 条基线、回写 `docs/HANDOFF` §1；结论写 `JD/from-deveco/`。
- **JD-003**：Beta 本机可侧载包。当前阻塞于 `devecocli auth login` 与设备回环；解除后按 `AGENT-HANDOFF.md` §3.3 出包并覆盖安装。

**回复格式**：每处理一个事项，先回「我已认领 JD-00X，开始执行」；结束后回「JD-00X 结论：PASS/FAIL + 证据路径」，并确认已更新 `JD/STATUS.md`。

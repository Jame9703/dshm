# JD — Joint Development（WorkBuddy × DevEco 共用开发通道）

> 目的：两人共用一个工作区开发同一项目，避免跨会话/跨工具丢信息。  
> 约定：**WorkBuddy 负责开发落地，DevEco 负责编译、测试与复核**；所有交接都在本目录留痕。

## 角色

- **WorkBuddy（本 agent）**：写代码、落地、跑相关门禁与编译自测，产出交接单。
- **DevEco**：对交接项做编译、真机/AGC 测试、代码复核，回填结论。

## 目录

| 路径 | 用途 |
|---|---|
| `from-workbuddy/` | WorkBuddy 落地完成后写的交接单（等待 DevEco 编译·测试·复核） |
| `from-deveco/` | DevEco 的编译结果、测试证据、复核结论 |
| `STATUS.md` | 看板：每个交接项的唯一状态来源 |
| `templates/handoff.md` | 交接单模板 |
| `archive/` | 双方 PASS、已闭环的交接单与结论 |

## 流程（每个事项一个 ID，如 JD-001）

1. **WorkBuddy**：落地代码 → 跑相关门禁 → 按模板写 `from-workbuddy/<YYYYMMDD-HHmm>-<slug>.md` → 在 `STATUS.md` 登记为 `待编译`。
2. **DevEco**：认领 → 编译/测试/复核 → 写 `from-deveco/<YYYYMMDD>-<slug>-result.md`（含命令与证据）→ 更新 `STATUS.md`。
3. **WorkBuddy**：按回填修 → 重新交接（引用上一次结论）。
4. 双方 PASS → 状态 `完成`，文件移入 `archive/`。

## 状态取值

`待编译` / `编译中` / `待测试` / `测试中` / `待复核` / `完成` / `阻塞`

## 交接单必含

- 变更摘要
- 涉及文件（真实路径，不写行号）
- 验证命令与结果（原始输出摘要）
- 边界：做了什么 / 没做什么
- **请 DevEco 做的事**（编译 / 测试 / 复核，具体到命令）
- 红线遵守声明

## 红线（与 `AGENTS.md` 一致，不在此重复解释）

- 不 `git commit`；不 `hdc uninstall`；不删 `signing/**` `.certs/**` `dist/**` 交付件；不自行升版本号。
- 改 `hostcore/plugins/**` 或核心树 ⇒ 先重打容器（`pack-core --place-in-app`）再出包。
- 门禁红了如实写，不许圆成“通过”。

## 与正式文档的关系

- 规范、红线、构建的唯一真源仍是 `AGENTS.md` 与 `AGENT-HANDOFF.md`；`JD/` 只承载**跨角色交接**，不替代它们。
- `docs/` 是项目正式文档；`JD/` 是协作过程区，**不参与** `check-doc-*` 门禁。

# 文档导航

> 文档只分四类：**规范 / 操作 / 台账 / 历史**。当前状态见 [`HANDOFF.md`](HANDOFF.md)；
> 会漂移的版本、权限、设备面一律以代码与配置为准。
> 最后整理：2026-11-18（历史文档已归档到 `docs/archive/`，现有 350 个 `.md`）。

## 1. 权威文档（先读这些）

| 文档 | 作用 | 维护方式 |
|---|---|---|
| [`../AGENTS.md`](../AGENTS.md) | 开发规范：工程结构、流程、红线、文档与门禁规则 | 改流程才改；当前口径 |
| [`../AGENT-HANDOFF.md`](../AGENT-HANDOFF.md) | 操作手册：工具、Beta / AGC、技能、默认决策、FAQ | 命令或环境变了就改 |
| [`HANDOFF.md`](HANDOFF.md) | 当前状态：在版版本、最新交付、已完成、没做完、下一步 | 每轮实质工作更新 |
| [`FEATURES.md`](FEATURES.md) | **功能台账**：功能 → 实现位置 → 契约 → 门禁 | 改功能必须同步 |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | 架构：分层、模块、启动链、垫片、三端、终端 | 结构变化才改 |
| [`PITFALLS.md`](PITFALLS.md) | 坑与红线：可复现的故障与不可逆操作 | 新踩坑就补 |
| [`DECISIONS.md`](DECISIONS.md) | 决策记录（ADR）：现行 / 已推翻 / 已关闭 | 拍板后追加 |
| [`parity-matrix.md`](parity-matrix.md) | 功能对等矩阵（`check-parity` 强制维护） | 由门禁守 |
| [`199-Host同步探测缓存（LOOP-GAP根因与修复）.md`](199-Host同步探测缓存（LOOP-GAP根因与修复）.md) | 契约文档：fs 探测缓存开关与真机待验（两道门禁消费） | 改实现前先读 |

## 2. 写作与维护规则

1. **一问题一篇**；同一问题多篇时合并到权威文档，其余归档。
2. **只写确认无误的事实**；过程、复盘、审核回合进 `docs/archive/`，不进权威文档。
3. **不抄可漂移值**：版本、核心、权限条数、设备面、性能读数一律指向真源。
4. **引用不用行号**：用节标题或相对链接，避免漂移。
5. **改完跑门禁**：`node tools/check-doc-index.mjs`、`node tools/check-doc-refs.mjs`。
6. 新增功能 ⇒ `FEATURES.md` 加行；新决策 ⇒ `DECISIONS.md` 加行；新坑 ⇒ `PITFALLS.md` 加行。

## 3. 归档说明

历史编号文档（`0`–`422`）与历史交接 / 评审报告全部移入 [`archive/`](archive/)：

- 归档文档 **只读**，不代表当前口径，不参与门禁扫描。
- 原 `docs/<编号>-*.md` 的引用，统一映射为 `docs/archive/<编号>-*.md`。
- 需要追溯某个结论的来龙去脉时，按编号去 `archive/` 查；**不要**据此改当前实现。
- 归档清单：`docs/archive/MIGRATION.txt`。

## 9. 编号文档全量索引

当前 `docs/` 顶层只剩两份编号文档（各被门禁消费），必须保留：

- [`199-Host同步探测缓存（LOOP-GAP根因与修复）.md`](199-Host同步探测缓存（LOOP-GAP根因与修复）.md)
- [`200-ACCESS_USER_FULL_DISK必要性说明（会话授权完全控制）.md`](200-ACCESS_USER_FULL_DISK必要性说明（会话授权完全控制）.md)
- [`201-WorkBuddy启动加载顺序拆解与借鉴.md`](201-WorkBuddy启动加载顺序拆解与借鉴.md)
- [`202-三端语音朗读增强与移动端文档扫描.md`](202-三端语音朗读增强与移动端文档扫描.md)
- [`203-DSH核心升级-0.2.3-alpha.2.md`](203-DSH核心升级-0.2.3-alpha.2.md)

其余编号文档均已归档：`docs/archive/<编号>-*.md`（归档目录共 350 个 `.md`，
含旧版 README / HANDOFF 两份快照与归档说明；逐篇清单见 `docs/archive/MIGRATION.txt`）。

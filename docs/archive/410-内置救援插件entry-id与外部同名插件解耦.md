# 410 内置救援插件 entry id 与外部同名插件解耦

**问题**：用户从插件市场安装了 `dshm-boot-rescue@1.1.0`（「安全中心」带备份 / 恢复 / 扩展诊断）。升级 DSHM 后安全中心消失；插件页里它仍显示「已启用」，开关切不动运行版本。

**根因（三处代码 + 真机日志）**

1. `@deepseek-ai/dsh-app-boot` 读 bundle patches 时明确「apply before the profile patch file」⇒ 外部包的 insert 先应用。
2. 同包 `applyPatches()` 里 `insert` 一律 `data.push(...clone)`，**不按 id 去重**。
3. `@deepseek-ai/cordis-plugin-loader` 用 `tree.store[options.id]` 按 id 建实体索引 ⇒ **同 id 后写者覆盖前者**。

而外部包的行 id 与包名一致（`dshm-boot-rescue`），我们的种子 insert 也用同一个字符串 ⇒ 后写的内置 1.0.0 顶掉外部 1.1.0：外部 `apply()` 永不执行、安全中心不存在；插件页的启停写的是同一个 id，所以「切不动版本」。

真机证据：`$DSH_HOME/dshm-boot-rescue.log` 165 行全部是 `[dshm-boot-rescue@1.0.0]`，自 2026-11-03 至 11-12 从未出现 1.1.0；`node-output` 里没有任何 patch 冲突告警（**静默覆盖**）。

**改动**

| 位置 | 改动 |
|---|---|
| `hostcore/profile/ondevice/cordis.patch.yml` ⑮ | insert 的 `id: dshm-boot-rescue` → `dshm-boot-rescue-builtin`（`name` 不变） |
| `hostcore/plugins/dshm-boot-rescue/cordis.patch.yml` | 同一 id（市场重装同一份内置包时不得再撞一次） |
| `hostcore/plugins/dshm-boot-rescue/lib/index.js` | `SELF_ENTRY_ID` 同步为 `-builtin`；`PACKAGE_NAME` 仍是包名（node_modules 路径 / 日志前缀 / 显示名）；两者都在 forbidden 名单里，救援中心永不停用任何一个救援实现 |
| `hostcore/app/dshm-user-rows.js` | 新增 `resolveRescueYield()`：读 `profile/node_modules/dshm-boot-rescue/package.json` 的 `version`，**外部在且版本不低于内置**时拼一行 `- id: dshm-boot-rescue-builtin` + `disabled: true` 让内置让位；否则内置生效。让位行排在市场行之后、用户行之前（用户显式重开仍最后生效）。同时 `migrateRescueRows()` 把历史上指向裸 id 的停用行迁到 `-builtin`（仅当外部不存在；先备份 `.dshm-migrate.bak`） |

**为什么用 `disabled` 行而不是裁 YAML**：`- id: X / disabled: true` 是 loader 官方语义，对已存在条目生效，不依赖文本裁剪，换核心版本不会失效。

**结果**：外部 1.1.0 正常挂载，安全中心恢复；内置以「已禁用」出现在插件列表里，作为外部缺失 / 损坏 / 更旧时的兜底；两者永不共存，也不会双注册 `/dshm-boot-rescue` 路由。

**门禁**：`tools/check-boot-rescue-id.mjs`（主检 4 条 + 5 个变异体，含「id 退回裸名」「版本常量与包版本漂移」必须判红）。

**边界**：外部 1.1.0 的源码不在公开仓库（`main` 仍是 1.0.0、无 tag / release），因此本轮**没有**把内置升级为 1.1.0 的能力，只做 id 解耦与让位。若后续拿到 1.1.0 源码，可再并入内置。

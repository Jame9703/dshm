# 395-注入型补丁语法守卫（viewProfilePackage 函数头被删导致三端 pluginManager 挂起）

- 日期：2026-11-07
- 输入：`2026-11-07 20_07_06.log`（平板端）、用户反馈「选择工作区报错 4；新建会话失败：agent-preset/invalid: tool-plugin-manager(@//deepseek-ai/dsh-plugin-manager/tools): waiting for pluginManager」
- 状态：**已修复**（core 补丁模板 + 语法守卫 + 门禁 + 重出包）
- 影响范围：**115626 那版 AGC 包三端都不可用**，请勿安装/回退到该包

---

## 1. 现象与根因

三端都报同一句：`tool-plugin-manager(@//deepseek-ai/dsh-plugin-manager/tools)` 一直
`waiting for pluginManager` —— 说明**插件管理器的某个模块没能完成加载**，服务永远不 ready。

根因是**上一轮注入模板的缺陷**：`viewProfilePackage()` 的注入锚点包含了函数声明行

```js
async function viewProfilePackage(dir, spec, options) {
	const result = await execa(options.command ?? "pnpm", [
```

而注入片段只回写了锚点里 `const result …` 之后的部分，**没有回写函数头**。于是磁盘上的文件变成：

```js
/* DSHM_PLUGIN_MANAGER_BRIDGE:view-profile … */
{
  const dshmBridge = await import(…);
  if (dshmViewed !== undefined) return dshmViewed;   // ← return 出现在函数外
}
const result = await execa(…)
```

`return` 落在模块顶层 ⇒ **整个模块 SyntaxError** ⇒ `@deepseek-ai/dsh-plugin-manager` 加载失败
⇒ 依赖它的 `tool-plugin-manager` 永远等不到 `pluginManager` ⇒ 新建会话 / 选择工作区全部失败。

两处同源实现（`lib/index.js`、`lib/types/operations.js`）都被这样破坏了，所以是**三端全崩**。

## 2. 修复

1. **模板修正**：`pack-core` 的 `viewProfilePackage` 两处站点改为
   捕获并**逐字回写函数头**（含 `export ` 前缀），注入块缩进到函数体内，
   `const result = await execa(...)` 保持在函数内。
2. **语法守卫（关键）**：`patchPluginManagerInspectBridge()` 写回后，对两个文件跑
   `node --check`；不通过直接 `die`，绝不让坏树进入产物。
3. **门禁**：`check-core-openharmony-patches` 增加两条
   「注入后语法可解析（node --check）」断言 —— 纯文本断言看不出这类破坏。
4. 已就地修复被破坏的两份文件（补回函数头），并重打 core 容器。

## 3. 为什么之前没发现

- `pack-core` 只做文本注入，从不校验产物能否被解析；
- 门禁只断言"标记在 / 调用在"，删掉函数头后这些字符串**依然存在**；
- 上一包（115626）出包与校验都"成功"，问题只在端侧运行到加载核心时才暴露。

⇒ 本次把「注入后必须能 `node --check`」提升为**构建期硬失败**，同类问题不会再出包。

## 4. 验收

| 项 | 判据 |
| --- | --- |
| 构建 | `pack-core` 输出「index.js / operations.js 语法自检通过」 |
| 门禁 | `check-core-openharmony-patches` 含两条 node --check 断言且全绿 |
| 包内 | 解包后对两份 `viewProfilePackage` 所在文件 `node --check` 通过 |
| 端侧 | 新建会话 / 选择工作区正常；插件页不再 `waiting for pluginManager` |

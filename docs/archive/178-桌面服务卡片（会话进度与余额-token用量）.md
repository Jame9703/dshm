# 178 · 桌面服务卡片：当前会话进度 + 余额 / token 用量

> 用户 2026-10-17：先看实况窗 →「目前是个人，那就不考虑了，那就做卡片可以么，显示当前在沟通的
> 会话进度和大模型账户余额」→ 补充「**有余额就显示余额；余额取不到时才显示 token 用量**
> （今天 / 近五小时 / 近一周 / 近一个月）」。
> 结果：Form Kit 桌面卡片（ArkTS 动态卡片）落地进 beta，**未 commit / 未 push**。

## 1. 为什么卡片可行、为什么不做实况窗

- 实况窗（Live View Kit）是 **AGC 权益审批**（Beta、按场景准入；推送实况窗还要企业账号）——
  当前是个人账号，**不做**（详见上一轮调研结论）。
- 桌面服务卡片走 **Form Kit**：官方支持 Phone / Tablet / PC/2in1 / TV / Wearable；
  **标准桌面卡片不需要那套权益审批**（锁屏卡片/待机屏保卡片才要另申请，本文不做）。
- 不新增 manifest 权限：**8 条权限面原样**（`check-permission-surface` 恒 8）。

## 2. 卡片内容（用户口径）

| 区域 | 内容 |
|---|---|
| 会话 | 当前/最近会话标题 + 状态（空闲 / 执行中 / 已完成）+「第 N 步」 |
| 余额 | **可用时显示**（`¥x.xx`，多钱包用 ` / ` 连接）；不可用时整行省略 |
| 用量 | **始终显示**为**四档横向条形图**（今日 / 5h / 7天 / 30天，归一化到最大值，数值标在右侧）；余额不可用时它就是主信息 |
| 点击 | `postCardAction` router → `EntryAbility`（回 DSHM 主窗） |

## 3. 数据流（三侧）

```
Host（Node，main.js registerCardState）
  session/event(turn/start|step/start|step/end|turn/end|session/title)  → 会话进度
  assistant/message.usage(inputTokens/outputTokens)                    → card-usage.jsonl（逐条）
  ctx.deepseekAccount.getBalance({version,locale,timezoneOffsetSeconds}) → 余额
        ↓ 原子写
$DSH_HOME/card-state.json   { updatedAt, session, balance, usage{today,last5h,last7d,last30d} }
        ↓
FormExtensionAbility（UsageFormAbility）onAddForm/onUpdateForm 读它出首帧/周期刷新
主应用 CardStateWatcher（2s，仅当存在已添加卡片）→ formProvider.updateForm 推进度
卡片 UI（UsageCard.ets）：useBalance ? 余额 : 用量；点击回主窗
```

- **历史用量回填**：首次（没有 `card-usage.jsonl`）异步扫描现有 `sessions/**/session.v4.jsonl.zstd`，
  结构扫描 zstd 帧 → 逐帧解压 → 抽 `assistant/message.usage`（35 天内，去重 `session:turn:step`），
  这样"今天/7天/30天"从第一天就是全的；之后只追加实时事件。
- **余额节流**：启动后 5s 首次、每 10 分钟、`turn/end` 时各刷一次（60s 节流）。
- **卡片五元组**（bundle/module/ability/formName/dimension）上线后不要改：改了系统会删掉已添加卡片。

## 4. 读数（真机 beta）

| 项 | 读数 |
|---|---|
| 打包 | `+dshm.65`：40746 条目 / 94.9MB，resfile ↔ dist sha256 `9dd40c6be0531112…` 一致 |
| 构建 | `assembleHap` BUILD SUCCESSFUL；HAP 内 `resources/base/profile/form_config.json` 在场，`module.json` 含 `UsageFormAbility` / `type=form` / `form_config` |
| 装机 | `hdc install -r` 成功 → 冷启动 → 设备核心树 **0.2.1-alpha.4+dshm.65（唯一）** |
| 宿主状态 | `card-state.json`：`session=idle`；**`balance.available=true, display="¥1.36"`**；`usage={today:572394,last5h:572394,last7d:651161,last30d:651161}` |
| 用量账本 | `card-usage.jsonl` **153 条**（首次回填现有会话日志所得，最早 `{t:1792136188938,in:900,out:75}`） |
| 门禁 | `check-usage-card` **23 断言 / 0 失败 + 5 变异臂**（摘余额 / 摘用量四档 / 改 form src / 摘推送 / 余额判据写反 全部如期判红）；仓库内 30 条口径 |

## 5. 边界与待验

- **只在主应用进程活着时推送更新**（CardStateWatcher 在主应用内）；应用被杀时卡片保持最后一次数据，
  重新打开 DSHM 后恢复实时。
- 没添加卡片时 **零读取**（watcher 先看 form-ids 列表）。
- **待验（用户操作）**：长按桌面 DSHM beta 图标 → 「卡片」→ 选「DSHM 会话」→ 添加到桌面；
  核对①余额显示 ¥1.36；②跑一轮任务时卡片出现"执行中 · 第 N 步"；③（可选）临时让余额不可用
  （未登录/断网）时卡片回退到四档 token 用量。
- 锁屏卡片 / 待机屏保卡片 / 实况窗：都需要额外权益申请，本轮不做。

## 6. 第二轮修订（2026-10-17 用户实测反馈后）

用户反馈：**"有会话了，但是桌面卡片只显示执行中，并未抓到会话的进度，并且只有余额，
并未显示4档token使用情况，纯黑色的卡片背景稍微有点单调"**。逐条修：

| 反馈 | 根因 | 修法 |
|---|---|---|
| 只显示"执行中"、无标题/第几步 | ① 老会话的 `session/title` 事件发生在**上一次进程**，新宿主不重放 ⇒ 标题空；② 进度文案只在 `running && step>0` 时显示，且真机当时 step 还是 0 | ① `titleOf()`：实时事件没有就**回看 `session.log`** 里最后一条 `session/title`（真机现有会话 `session-0aed…` 就是这种情况）；② 进度改为 `step>0` 即显示（执行中/已完成都显示"第 N 步"） |
| 只有余额、没有 4 档用量 | 初版按"余额优先、不可用才显示用量"做成了**二选一**；用户实际要的是余额与用量**同时显示** | `usageText` 改为**始终渲染**（两行：今日/5h、7天/30天）；余额可用时作为上方一行并列，不可用时只保留用量 |
| 纯黑背景单调 | `#151517` 纯色底 | 深蓝灰渐变（`#1E2A3A → #12161E`）+ 左侧青绿色强调条 + 状态胶囊（执行中为绿底） |

**卡片五元组未变**（name/尺寸不变），已添加的卡片会随新 HAP 原地更新，**不用重新添加**。

读数：`+dshm.66`（resfile sha256 `5639f57927933a6c…`）装机冷启；设备核心树唯一
`0.2.1-alpha.4+dshm.66`；`card-state.json` → `balance.display="¥1.36"`、
`usage={today:810575,last5h:810575,last7d:889342,last30d:889342}`。

## 7. 第三轮修订（2026-10-17 用户第二次实测反馈后）

用户反馈：**"卡片做出白色底吧，纯黑色不太好看，四档用量可以做成其他图表的形式展示，
现在蠢问题，相对单调，更新频适当降低，DSHM不运行的时候停止更新，只有在DSHM启动的时候才会自动更新"**。

| 反馈 | 修法 |
|---|---|
| 纯黑不好看 | 卡片改为**白底**（`#FFFFFF → #F4FAF7` 极淡渐变）+ 青绿强调条/状态胶囊 + 深色文字（`#111827` / `#6B7280`） |
| 四档用量单调 | 四档改成**横向条形图**：每档一条（今日 / 5h / 7天 / 30天），宽度按四档最大值归一化（有数据至少 4% 可见），右侧标 `k/w` 数值；绑定数据从文字改为**数值**（`usageToday/usage5h/usage7d/usage30d`） |
| 更新频降低 | `CardStateWatcher` 轮询 **2s → 5s**（宿主仍然只在事件变化时写状态文件，推送随之最多 12 次/分钟） |
| DSHM 不运行停止更新 | `form_config.json` 改 **`updateEnabled: false`** 并删除 `updateDuration` ⇒ **系统不再定时拉起 FormExtension 刷新**；卡片内容只由**主应用运行时的 `CardStateWatcher` 推送**更新。DSHM 被关闭后卡片保持最后一次数据，完全静止 |

**卡片五元组仍未变**（同一 form name / 尺寸），已添加卡片原地更新，不用重加。
门禁 `check-usage-card` 扩到 **27 断言 + 9 变异臂**（新增：重开系统定时刷新 / 轮询回到 2s /
去掉条形图 / 背景改回纯黑 —— 全部如期判红）。

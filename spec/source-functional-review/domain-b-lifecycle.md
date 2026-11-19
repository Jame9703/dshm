# B 启动、会话及后台（T004）

## 深读与链路

- 两壳 EntryAbility 的 onCreate、字段及启动入口；phone `915–1138` 启动恢复/发布 token、`1689–1878` 后台对账；entry `2012–2116` 申请释放。
- `DshHost.ets` 全文；`NodeRuntime.ets:250–649`；`KeepAlive.ets:1–450`；`NotificationCenter.ets:70–369`。
- 实际核心 session-controller `lib/index.js:1058–1068,2572–2631`：cancel 实际调用 agent.cancel 并保留 inbox；follow 先绑定监听再取 snapshot/cursor，finally dispose。不能把断开观察流等同取消任务。
- `hostcore/app/main.js:5677–5777,5913–6129` 状态生产；启动 runProfile `8423–8447`；退出 `8504–8587`。
- 启动失败并非直接永久失败：phone `981–1014` 在 runtime 仍运行时重试；NodeRuntime token pid+port 守卫、DshHost 复捡句柄、发布端补票均存在。剔除“慢启动一次超时必永久401”的泛化候选。

## B-01：失败 acquire 的引用泄漏（P2 确认缺陷，系统表现待真机）

根因 `platform/src/main/ets/notify/KeepAlive.ets:364–385`：refs 在请求前 ++，请求失败不回退。phone `EntryAbility.ets:1776–1782` 失败后 held=false，后台轮询每隔至少30秒可再次申请（1771–1775）；每次失败累加 refs。最后成功后前台 `1799–1805` 只释放一次；KeepAlive `429–440` 见 refs>0 直接返回，不停止。

预期：多次失败再成功只对应一个持有；实际：例如两次失败一次成功 refs=3，回前台一次 release 后 refs=2，无法走停止分支。影响 phone/折叠；entry 的失败申请也不配平（2070–2074），跨后台周期可累积。无须假定某系统一定拒绝，只需条件为一次或多次申请失败后后续成功。

反证：generation 守卫只处理晚到成功，不清失败已经增加的 refs；userStopped 在 ++ 前返回，用户取消拒绝本身不算这条泄漏。active 判据不能清 refs；不能因类注释说“多窗口共用”就当全局单例，当前字段为每实例。

建议：配平失败请求引用或把引用拥有权与平台请求状态分开；不要在本轮改实现。

## 已剔除 B-R1：完成通知静音降级字段“未消费”

初读通用 publish 的 `300–304` 仍固定 SERVICE_INFORMATION；进一步追消费者发现专用 `publishCompletion:400–455` 在435确实读取 completionSlotType。故剔除“完成通知降级永不生效”，不能凭同文件一处分支泛化全部通知路径。通用 publish 与专用完成通知是否应统一不作为本轮缺陷；声音仍需真机。

## 未覆盖

未全文审查会话发送、审批/问答、mux transport重连和队列、通知点击全链、迁移实现、多会话并行。main 的 card current 为单一当前对象，不证明聚合所有运行会话；phone 以它作保活判据存在多会话覆盖风险，尚需独立追实时并行入口，不列确认项。

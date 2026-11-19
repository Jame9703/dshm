# C 终端与VM（T005）

## 证据链与范围

深读 RuntimePort 全文；vm-bash `index.js:75–431`、`terminal.js` 全文、`handle.js:25–330`、`qga.js:100–629`；vm `1370–1635` 启动后段和关机。原生 `dshhost.cc:400–609`。实际核心 terminal-controller `lib/index.js:1150–1319,1380–1569`，以及工作树 vm-bash index `305–419` / vm `1521–1570`，核实不是只有开发源目录出现。

DeviceFacts→NodeRuntime.start→buildHostEnv:204–253→nativeExecutionOnly/enabled→runtime.spawn / spawnTerminal 包装。profile `terminal-controller:161–173` 没固定 shell，只给候选 sh/zsh/bash；VM 的 terminalEnvironment 默认 sh，resolveExecutable 只替 guest 中明确支持的 sh/ash/bash。因此剔除“profile 固定 zsh 导致所有手机终端不能起”的误报；terminal-bash 独立旧链配置不等于现在控制器默认 shell。

取消反证：核心 terminal-controller 传 signal（1555–1567），spawn 后检查 signal（1569）；不能只因为 createVmTerminal 没读 signal 就断言上游一定泄漏已返回终端。handle 在 acquire 后检查 cancelled/settled，QGA onPid 也补杀；但 terminate 只TERM及子进程组语义未全面闭合。

## C-01：关机 Promise 可因QMP连接关闭提前成功（P1 风险）

位置 `hostcore/plugins/dshm-vm-bash/lib/vm.js:1523–1568`；实际工作树相同行。链 `index.js:251–254,428–430` 注册shutdown → `hostcore/app/main.js:8533–8587` 等hook → 1.5秒后process.exit（8555–8558）。

根因：stop 既监听 worker.exit，也把 qmp.close/end 接到同一个finish；任何首个 data 就主动destroy（1557–1561）。因此QMP问候/响应到达就可能resolve，且清除8秒timer，不代表worker已退出。预期宿主等待VM关闭，实际只需连接结束就通过；worker仍跑超过后续1.5秒时会被宿主退出截断。影响所有启用VM端，通常普通平板/phone/折叠。

反证：宿主确实await allSettled并有10秒guard，不是“没await”；worker.exit也可正常先到；正常快速quit可能在1.5秒内结束，故不报必现数据损坏。QMP问候及worker刷盘真实时序未做真机，确认的是早完成窗口，数据损伤只列风险。

建议：完成信号以worker终止为准，协议响应与关闭不当刷盘完成；保留有界超时但明确超时状态。

## C-R2：卸载回调引用块外终端计数（P2 风险）

`index.js:312–314` 的 let takenTerminal/delegatedTerminal 仅在if块内，`413–414` 的 effect清理函数却块外引用，执行时会ReferenceError；工作树相同行存在。不是常规新建终端即抛，只在清理回调运行时；Cordis effect清理异常如何影响其他释放未重读，因此不升级宿主崩溃。建议把计数作用域与回调一致，下一阶段检查实际插件卸载调用。

## 边界

未审全VM资产stage/provision、9p/QEMU C实现、rootfs内容、native PTY实现及实际设备支持；未启动VM，未模拟socket，未把源码工作树视为随包zip逐字一致。

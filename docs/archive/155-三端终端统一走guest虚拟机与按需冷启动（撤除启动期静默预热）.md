# 155 三端终端统一走 guest 虚拟机与按需冷启动（撤除启动期静默预热）

## 结论

- PC、手机、平板三端统一由 `dshm-vm-bash` 接管 `spawn` / `spawnTerminal` / `resolveExecutable`，终端和模型侧 bash 都落在随包 QEMU guest。
- 不做启动期静默预热，也不做任何后台保活。guest VM 只在第一条真实 bash 或终端请求时启动；启动失败由这次请求如实报错。
- `docs/154` 的“QEMU 前可执行页预检”不恢复：该预针漏了 `MFD_EXEC`，会在可运行设备上恒判失败。VM 能不能起，交给 QEMU 的真实启动结果判定。
- 行为变化进入包体，`coreVersion` 升到 `0.2.1-alpha.2+dshm.43`。

## 修改

1. `hostcore/plugins/dshm-vm-bash/lib/index.js`
   - 删除 `WARM_DELAY_MS`、`shouldWarm()`、`warmCwd()` 和加载路径上的 `setTimeout` 预热。
   - 加载日志改为“按需冷启动已启用：首条 bash / 终端请求时才拉 guest VM”。
   - 保留 `enabled()` 的三端接管判据：`DSHM_VM_BASH=off` 显式关闭，`DSHM_VM_BASH=force` 显式开启，端侧且 VM 资产齐备则默认开启。
2. `hostcore/plugins/dshm-vm-bash/lib/vm.js`
   - 生命周期注释改为三端同一口径：`ensureRunning()` 只由真实请求触发。
3. `tools/check-vm-bash.mjs`
   - 新增“按需冷启动（禁止启动期预热）”门禁：旧预热函数、加载路径 `setTimeout`、旧“静默预热完成”日志都不许复活。
   - 既有 `cwdMiss` 门禁改为确认 `warmCwd()` 已删除。

## 验证

- `node tools/check-vm-bash.mjs`：`305/305 PASS`。
- 仓库登记的 22 条离线门禁批量执行：`ALL PASS`。
- `index.js` 模块导入语法检查：`ok`。

## 设备验收

- 本轮使用覆盖安装 `hdc install -r`，不卸载应用、不删除用户数据。
- PC 与手机真机验收结果见文末追加记录。

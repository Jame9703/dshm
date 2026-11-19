# 154 · 8 权限 release 下 TCG 执行页被拒与 VM 预检止损

> ⚠️ **历史轮次读数（2026-10-14 当时口径，不得作为现行实施依据）**：「8 权限」已作废，历经 11 条、17/9，**当前 entry 18 / phone 9**（Profile `allowed-acls` 8 条，含全盘权限）。现行口径见 `AGENTS.md` §4.3。

> 2026-10-14。三端 `+dshm.40` 包在 Mate60 / Mate80 / PC 上进入页面或触发 VM 预热后闪退，本文记录根因、修复口径与验收约束。

## 结论

- 真机崩溃栈一致指向 `libqemu-system-aarch64.so(tcg_region_init)`：`split-wx=off` 时 `mprotect(RWX)` 被拒，`split-wx=on` 时 `memfd + PROT_EXEC` 映射也被拒。
- 这是 8 权限 release 应用域的平台安全策略限制；`ALLOW_EXTERNAL_NATIVE_CODE` 只覆盖原生库加载，不等于允许 QEMU 生成可执行页。
- 不继续用 QEMU 参数绕过；**也永不加回那三条受限条目**（2026-10-14 用户拍板：永久删除，源码 / 包体 / 文档里都不再出现）。
- 产品行为改为 fail-closed：进入 QEMU 前先做执行映射预检；失败则本进程永久禁用 VM，bash / 终端返回明确错误，不允许原生 `exit(1)` 拖死宿主。
- 三端路线不变：PC / 手机 / 平板的 bash 与终端仍统一走 guest VM。旧文档里的「PC/2in1 惰性」口径作废。

## 修复

1. `vm-worker.cjs` 在 `qemu_system_entry()` 前用 koffi 调 `memfd_create` / `pwrite` / `mmap(PROT_READ|PROT_EXEC)` 复现 QEMU `split-wx=on` 的关键能力；失败则不进入 QEMU。
2. `vm.js` 收到 `exec-probe` 失败后置 `execBlocked = true`；`ensureRunning()` 与 `startGate()` 双入口止损，预热和真实命令都不会再重试。
3. `diagnostics()` 暴露 `execProbe` 与 `execBlocked`，上架自检可直接读到失败原因。
4. `enabled()` 不再按宿主假壳 spawn 结果区分 PC 与手持：三端统一由端侧 VM 接管；探针保留为诊断能力。

## 门禁

`node tools/check-vm-bash.mjs`：315/315 通过，新增覆盖：

- 预检在 `qemu_system_entry` 之前；
- 预检失败不调用 QEMU 原生入口；
- `execBlocked` 双入口止损；
- 失败读数进入 diagnostics；
- 旧「PC 惰性」断言改为「三端同接管」。

## 权限与产物约束

权限面**恒 8 条，且不可增**（用户 2026-10-14 拍板）：2 条已审批受控权限 `ALLOW_EXTERNAL_NATIVE_CODE`、`FILE_ACCESS_PERSIST`，加 6 条无需申请权限（`INTERNET` / `GET_NETWORK_INFO` / `KEEP_BACKGROUND_RUNNING` / `PREPARE_APP_TERMINATE` / `STORE_PERSISTENT_DATA` / `MICROPHONE`）。

⇒ **任何第 9 条都不得写进源码、包体或文档**；没有审批的 `system_basic` / `system_core` 受限条目声明了也拿不到，反而让整包按 `PERMISSION_ACL_RULE` 拒装。门禁钉死这一条（`module.json5` 的"权限面铁律"是同一条规则的注释版）：

```powershell
node tools/check-permission-surface.mjs
```

包内不得出现 `.apk` 文件名。

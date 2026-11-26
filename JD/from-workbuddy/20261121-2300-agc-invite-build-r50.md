# JD-035 AGC 邀请/云调试包构建（r50，PC+手机终测后）

- 提交方：WorkBuddy
- 接收方：DevEco（编译 AGC 包）
- 时间：2026-11-21 23:00
- 输入：
  - PC 终测：`~/Download/DSHM-环境与工具自检-2026-11-21.md`（MNTXM-24B，API 26）
  - 手机终测：`DSHM-上架前终检-r49.md`（VYG-AL00，phone 档）
- 目标：构建 **AGC 邀请测试 / 云调试** 用发布包（不是 beta 包），供用户上传 AGC 云调试。

---

## 0. 结论

**两份终测均无 P0 阻断**，可以编译 AGC 云调试包：

- PC：环境正常，44 个工具中实测 25 个**全部通过**；启动 13.6 s（P2 体验项）。
- 手机：**有条件放行**，无 P0；3 个 P1 属「需产品确认或写入用户须知」，不阻断云调试。
- 报告里的 PC「P0 包名 `com.example.ohpocketpal`」是 **`Download/` 里的旧占位产物**，不是本工程构建物；本工程包名恒为 `com.dshm.dshclient`（见 §2）。同理「DSHM 1.1.0 / 9 月旧包」也是 Download 里的旧文件。

---

## 1. 本轮已并入的改动（相对上一 AGC 包 `…T132959`）

| 项 | 位置 | 状态 |
|---|---|---|
| 启动背景跟随系统深浅色 | `entry/phone` WebApp + dark color + EntryAbility | 已编译过 |
| 手机状态栏沉浸（首帧后 + 启动期两轮） | `phone/.../EntryAbility.ets`、`WebApp.ets` | 已编译过 |
| 启动提速：4 项非首屏注册延后 | `hostcore/app/main.js`（已同步 HSP resfile） | 已编译过 |
| 全盘权限 `reason` 二次强化 | `entry/.../base|en_US/element/string.json`、`module.json5` | 已编译过 |
| `WINDOW_TOPMOST` 级别核实 | 非 ACL（normal/system_grant），无需审批 | 文档记录 |

> 上述均已在本地 `devecocli build --product default --build-mode debug` 通过；`check-permission-surface` 19/9 PASS；`check-decor-button-mode` 134/0 PASS。

---

## 2. 包身份（必须保持不变）

| 项 | 值 |
|---|---|
| bundleName | `com.dshm.dshclient` |
| versionName / versionCode | `1.1.8` / `1010019` |
| 核心 | `0.2.2-rc.5+dshm.1` |
| 发布 Profile | `./.certs/release-20261109/DSHM1109Release.p7b`（**allowed-acls 8 条**） |
| 权限面 | entry **19** / phone **9** |

> `WINDOW_TOPMOST` 为 `normal` / `system_grant`，**不在** ACL 8 条里属正常；`strip-ungranted-acl-perms` 不会摘它。

---

## 3. 构建

```sh
cd <workspace>
node tools/build-agc.mjs
```

- 该脚本：临时把 product 切 `release` + `signingConfig=release`，编 entry + phone + hostruntime，结束**逐字恢复** `build-profile.json5` 并重放正式 Host 资源。
- 预期产物：`dist/release-test/dshm-1.1.8-1010019-dshm.1-AGC-invite-<时间>.app` + `.sha256` + `SHA256SUMS.txt`。

---

## 4. 本单要求 DevEco 核验

1. 包名 / 版本：`com.dshm.dshclient`、`1.1.8`、`1010019`；
2. 权限：entry 19 / phone 9；`ACCESS_USER_FULL_DISK` 的 `reason` 是**新文案**（含「会话工作区 + 全部子目录 + 重启恢复」）；
3. ACL：与 `DSHM1109Release.p7b` 的 8 条一致，无「多出未登记 ACL」；
4. `verify-app` 通过、`SHA256SUMS` 全 OK；
5. 包内 `hostcore/app/main.js` 与源一致（`deferRegister` 4 项）；
6. 回报：包路径、app sha256、权限条数、verify 结果。

---

## 5. 终测结论摘要（供 AGC 说明）

### PC（MNTXM-24B / API 26）

- 环境：Node 24.9.0 jitless、Python 3.12.14、git/rg/tmux/gh/curl 全可用；外网 200。
- 工具：44 个中实测 25 个，**25/25 通过**。
- 启动：BOOTING→READY **13.6 s**；监听前一次 8.66 s 主线程停顿（P2，本轮启动提速只覆盖宿主注册收尾，插件装载仍是主因）。
- 已知：Browser Bridge `connected=0`（需装扩展）；`host-crash.log` 是 11-02 旧 pid 的历史记录，本次无新增。

### 手机（VYG-AL00 / phone 档）

- 冷启动无 FATAL；Web 服务 / token 鉴权正常；Python 桥 selftest ok。
- guest VM（Alpine 3.22）健康：bash/node/python/git/pnpm 可用，外网正常。
- 工作区双读双写、publish 往返一致；插件市场 dshmarket 1.75.0 已启用。

---

## 6. 非阻断项（需用户/产品知悉，不挡云调试）

| 级别 | 项 | 处置建议 |
|---|---|---|
| P1 | 手机 9p `.virtfs_metadata` 旁挂目录 | 云调试不受阻；上架说明注明或 Host 侧过滤 |
| P1 | 工作区语义：cwd ≠ 认领目录；guest `/storage` 非宿主 | 用户须知写明；界面显示「当前会话工作区 / publish 落点」 |
| P1 | `office_*` 工具在 web profile 未注册（技能有、工具无） | 产品决策：并入 web bundle 或改技能文案 |
| P2 | python `argv[0]` / `__file__` 语义偏差、脚本须在沙箱 | 工具描述注明或后续修 |
| P2 | `job_kill` 终态延迟（分钟级） | 帮助文档说明 |
| P2 | 重 I/O 导致 LOOP-GAP（guest grep 大文件 4–5 s） | 说明避免大文件 grep；后续 I/O 分片 |
| P2 | PC 启动 13.6 s / 8.66 s 停顿 | 已交付 JD-033 首轮提速；若仍慢，下一步需评估插件懒加载（会改功能，需另行确认） |

---

## 7. 边界

- **不改版本号、不改核心版本**（保持 1.1.8 / 1010019 / rc.5）；若要「去 rc 正式号」需用户单独拍板。
- 不修 §6 的 P1/P2（云调试不需要）。
- 只编 AGC 包，不自动上传 AGC。
- 编译后若 `build-profile.json5` 未逐字恢复，属脚本异常，需立即回报。

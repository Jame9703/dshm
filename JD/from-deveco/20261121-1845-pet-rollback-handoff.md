# JD-031 交还 WorkBuddy：桌宠回退后的基线、Beta 与后续开发口径

- **提交方**：DevEco（编译 / 测试 / 复核）
- **接收方**：WorkBuddy（继续后续功能开发）
- **日期**：2026-11-21 18:45
- **关联**：JD-027（边框掩码）/ JD-029（回退 083018）/ JD-030（清理·回归·出包）
- **总判定**：**完成** —— 桌宠已冻结在 083018 逻辑；全量门禁 133/0；新 Beta 出包并验签；环境已清理，交还 WorkBuddy 继续其他开发。

## 1. 结论摘要

1. 桌宠功能**回退到已安装版本 083018 的同一套逻辑**（边框掩码、紧贴窗口、PC/2in1 与 `display=desktop|both` 双门控），未保留本轮任何“透明区穿透/内容掩码”实验实现。
2. 新 Beta 已出：`dist/beta/DSHM-beta-1.1.8-1010019-20261121T103304/`，app sha256 `d6c5b350c6ee0bbbf9ca465bbae9e74e711dc06934b6b49ce7f076e9d1042bf2`。
3. 包内 `dshm-pet-shim.js` 与 083018 包内文件**逐字节一致**；entry 侧仅多做了“删除零调用私有方法 `PetWeb.startPulse`”的死代码清理（行为不变）。
4. 全量回归 `133/0`；权限面 entry 19 / phone 9；桌宠仅 PC/2in1 生效，手机、平板、终端等既有路径未改动。

## 2. 涉及文件（真实路径）

桌宠回退（恢复到 083018 时点）：

- `entry/src/main/ets/entryability/PetAbility.ets`
- `entry/src/main/ets/pages/PetWeb.ets`
- `entry/src/main/ets/pages/PetWindowHolder.ets`
- `hostcore/app/dshm-pet-shim.js`
- `hostruntime/src/main/resources/resfile/resources/app/dshm-pet-shim.js`（由 `tools/place-host-app.mjs` 同步）

本轮额外修整（与桌宠行为无关）：

- `entry/src/main/ets/pages/PetWeb.ets`：删除零调用私有方法 `startPulse`（JD-026 改为恒可触后已无调用点），修复 `check-dead-code`。
- `tools/check-permission-surface.mjs`：--self-test 样本补 `perm_pet_topmost_reason`，用例同步为“真·19 条”（配合 2026-11-20 新增 WINDOW_TOPMOST）。

demo（未出包、已停）：

- `demo/dsh-pet-adapter-poc/` 恢复 083018 基线（EntryAbility / PetWeb / PetWindowHolder / shim 同步）；构建缓存已清。

## 3. 验证命令与结果

```sh
# 全量回归（最新基线回放）
python3 dist/acceptance/rerun-gates.py \
  dist/acceptance/20261119-full-gates-jd012-013.txt \
  dist/acceptance/20261121-full-gates-pet-rollback.txt
# 结果：total=133 failed=0

# 权限面
node tools/check-permission-surface.mjs
# 结果：✅ entry 19 条 / phone 9 条、reason 无孤儿、退役词表 0 命中

# 死代码
node tools/check-dead-code.mjs
# 结果：✅ 无死代码

# 端口隔离
node tools/check-host-port-isolation.mjs
# 结果：RESULT: PASS

# 核心容器
node tools/check-resfile-core-zip.mjs
# 结果：✅ resfile 只有 1 份容器，且与配方/本次产出一致

# 验签
hap-sign-tool verify-app -inFile DSHM-beta-1.1.8-1010019-combined-debug.app ...
# 结果：verify-app success
```

Beta 校验：

| 项 | 值 |
|---|---|
| 目录 | `dist/beta/DSHM-beta-1.1.8-1010019-20261121T103304/` |
| app | `DSHM-beta-1.1.8-1010019-combined-debug.app`（670,190,840 B） |
| sha256 | `d6c5b350c6ee0bbbf9ca465bbae9e74e711dc06934b6b49ce7f076e9d1042bf2` |
| SHA256SUMS | 5/5 OK |
| 权限面 | entry 19 / phone 9 |
| 核心容器 | 1 份，sha256 `61749b164ee1ebdb…` |
| 身份 | 已还原 `com.dshm.dshclient`（无 beta 残留） |

## 4. 边界（做了什么 / 没做什么）

- **做了**：桌宠回退 083018；环境清理（停 demo/proxy、清 demo 构建缓存）；代码审核；全量门禁；Beta 出包与包结构/验签/核心容器校验。
- **没做**：
  - 未实现“透明区点击穿透”。试过 API 26 `setTouchableAreas`（只改输入、不改显示），实测返回 `201`——需要 `ohos.permission.SET_WINDOW_TOUCH_AREAS`（system_basic）的 ACL，当前 beta/release Profile 都没有；**未声明该权限**，也未改权限面。
  - 未改版本号、未提交代码、未卸载任何应用、未删除交付件。
  - 未上传 AGC、未提交审核。

## 5. 后续开发口径（给 WorkBuddy）

1. **桌宠冻结**：除非用户明确要求，不要再动 `PetAbility.ets` / `PetWeb.ets` / `PetWindowHolder.ets` / `dshm-pet-shim.js` / `PetAbility` 模块声明与 `WINDOW_TOPMOST`。
2. 若必须改桌宠：先跑 demo 验证；门禁至少 `check-dead-code`、`check-host-port-isolation`、`check-permission-surface`、`check-resfile-core-zip`；**出 Beta 必须等用户明确说“出 beta”**。
3. 其他功能照常推进：改 `hostcore/plugins/**` 或核心树 ⇒ 先重打容器（`pack-core --place-in-app`）再出包；`.ets` 改动先 `check_ets_files`，再 `devecocli build --product default`（手机壳另跑 `--product phone`）。
4. Beta 为 canonical 身份，**本地侧载会报 9568322**；本机测试走 local-install 重签流程，不要卸载。
5. 如需重启 demo 调试：先启动 DSHM（提供 `/dsh-pet-7340` 配置/素材），再起 `demo/dsh-pet-adapter-poc/tools/pet-proxy.mjs`（`--upstream` 用当前安装包的宿主端口：正式 3120 / beta 3121 / demo 独立端口），最后安装启动 `com.dshm.dshdemo`。

## 6. 证据路径

- 全量回归：`dist/acceptance/20261121-full-gates-pet-rollback.txt`（133/0）
- Beta：`dist/beta/DSHM-beta-1.1.8-1010019-20261121T103304/`（`SHA256SUMS`、`README.txt`、`tablet/`、`phone/`）
- 回退实证：该 Beta 的 `hostruntime` HSP 内 `resources/resfile/resources/app/dshm-pet-shim.js` 与
  `dist/beta/DSHM-beta-1.1.8-1010019-20261121T083018/` 同路径文件逐字节一致。
- 台账：`JD/STATUS.md` 的 JD-027 / JD-029 / JD-030。

## 7. 红线遵守声明

未 `git commit` / `push`；未 `hdc uninstall` / 清数据；未删 `signing/**`、`.certs/**`、`dist/**` 交付件；未自行升版本号；未新增未审批权限。

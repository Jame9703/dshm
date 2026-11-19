# 全盘 ACL 落位与「恒定条数」解禁（权限以发布 Profile 为准）

> 日期：2026-11-11 23:10–23:20
> 触发：用户指出 AGC 包缺少已获批的 `ACCESS_USER_FULL_DISK`；要求以**最新 Profile** 的 ACL 为准，
> 去掉「恒定 N 条」的硬限制，并清空全部 Beta / AGC 产物后重编 Beta。

---

## 1. 根因：用错了 Profile

| 项 | 旧（本轮之前） | 新（本次切换） |
|---|---|---|
| 文件 | `.certs/multihap-20261024/DSHM-multihap-release-20261024-newacl.p7b` | `.certs/release-20261109/DSHM1109Release.p7b` |
| 签发/落盘 | 2026-10-24 | **2026-11-09** |
| ACL 数 | 7 | **8** |
| `ACCESS_USER_FULL_DISK` | 无 | **有** |
| bundle / type / 渠道 | `com.dshm.dshclient` / release / app_gallery | 同左 |
| 有效期 | 2029-10-12 | 2029-10-12 |

11-09 的 Profile 是华为按申请新批的，包含全盘访问；旧构建脚本却仍在用 10-24 的 7 条文件，
并且用 `EXPECTED_ACLS` **逐字等于** 7 条来硬校验 —— 于是「新 Profile 反而构建失败」，
只能继续出 7 条包。这就是 AGC 包没有全盘权限的直接原因。

---

## 2. 改动

1. **Profile 切换**：`build-profile.json5` 的 `release.material.profile` 指向
   `./.certs/release-20261109/DSHM1109Release.p7b`（新文件已落 `.certs/release-20261109/`）。
2. **entry 声明补全**：`entry/src/main/module.json5` 增加
   `ohos.permission.ACCESS_USER_FULL_DISK`（`usedScene: EntryAbility / always`），
   entry 权限面 17 → **18** 条；中英文 `reason` 同步补齐（`perm_full_disk_reason`）。
3. **去掉恒定条数**（`tools/build-agc.mjs`）：
   - 删除 `EXPECTED_ACLS` 常量与「ACL 列表必须逐字等于它」的断言；
   - 改为：**Profile 的 `allowed-acls` 是唯一事实源**；只校验
     「entry 声明的受控权限 ⊆ Profile 已批准」；
   - 打印 `ACL：Profile N 条；entry 受控声明 M 条，全部在 Profile 内`，Profile 增批不需要改脚本。
4. **权限门禁同步**（`tools/check-permission-surface.mjs`）：
   entry 期望 18 条；`ACCESS_USER_FULL_DISK` 移出退役词表（原先它是"永远不许出现"的静态禁令）；
   末尾提示改为「ACL 以发布 Profile 为准」。
5. **Beta 构建**（`tools/build-beta.mjs`）：`wantEntryPerms` 恒为 18（全盘已是正式声明），
   `--no-full-disk` 不再试图降回 17。
6. **铁律文档**（`AGENTS.md` §4.3）：17/9 → **18/9**，并写明"以 Profile 的 allowed-acls 为准"。

---

## 3. 核对结果

| 检查 | 结果 |
|---|---|
| `check-permission-surface` | PASS：entry 18 / phone 9，reason 无孤儿，退役词表 0 命中 |
| 新 Profile 解析 | 8 条 ACL，含 `ACCESS_USER_FULL_DISK`；bundle/type/渠道/有效期正确 |
| `check-store-readiness` | PASS（仍禁止 `kernel.*` / `ALLOW_WRITABLE_CODE_MEMORY`） |
| `check-pc-tablet-parity` / `check-agc-wiring` | PASS |
| `check-mobile-upgrade-migration` | PASS（清理前执行） |
| 脚本语法 | `build-agc` / `build-beta` / `check-permission-surface` 均 `node --check` 通过 |

---

## 4. 产物清理

按要求删除全部历史包（释放约 **12.3 GB**）：

- `dist/beta/`：6 个版本目录，全部删除；
- `dist/release-test/`：5 个 `.app` + 5 个 `.sha256` + `SHA256SUMS.txt`，全部删除。

清理后两个目录均为空。**本轮只重编 Beta**；AGC 包等真机测试通过后再出。

---

## 5. 边界

- 本文件记录的是配置与声明层修正；**ACL 是否真正生效仍取决于设备授予**（系统设置里可能还要手动开）。
- Beta 用的是 debug 签名/profile，与新正式 Profile 无签名关系；Beta 包能装不代表正式包的 ACL 已授予。
- 清理历史包导致后续无法再对旧包做逐字节对照；本轮需要的基线（1.1.8 的 ABC / HSP）已在审核阶段取过。

---

## 6. 版本号与最终包（2026-11-11 23:59）

- 用户要求：**versionName 保持 1.1.8，只升 versionCode** ⇒ `1010015 → 1010016`（`AppScope/app.json5`）。
- 原因是 11-09 Profile 带来新 ACL、且安装包结构/权限面变化，同版本号覆盖安装可能被系统拒绝。
- AGC 包：`dist/release-test/dshm-1.1.8-1010016-dshm.1-AGC-invite-20261111T155942.app`
  （540 MB / sha256 `4d6ef6e8…adc5`，profile_acls=8）。
- 核验：entry 18 条（含全盘）/ phone 9 条；AGC 无 Beta 包名残留；HSP main.js 与源码逐字节一致。

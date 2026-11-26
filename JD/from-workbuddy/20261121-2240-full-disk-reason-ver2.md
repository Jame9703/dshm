# JD-034 全盘文件权限二次驳回响应（会话授权完全控制）

- 提交方：WorkBuddy
- 接收方：DevEco / 用户（AGC 申诉）
- 时间：2026-11-21 22:40
- 关联：JD-009（首次 reason 合规化）、`docs/archive/223`（首次申请回复）、`docs/200`（本次说明）

---

## 1. 驳回原文（要点）

> 应用申请了 `ohos.permission.ACCESS_USER_FULL_DISK`，但应用内**未见必须使用此权限的功能场景**，不符合法律法规要求。
> 要求按最小化原则，仅申请业务必要权限，并在 `requestPermissions` 的 `reason` 中填写**实际使用该权限的功能场景**。

结论：上一版 reason（「读写用户选为工作区的文件夹」）仍被判定为「不够必须」。本次按评审工程师口径补上**会话授权完全控制**这一强需求。

---

## 2. 论证核心：为什么必须（会话授权完全控制）

用户选定一个本地文件夹作为**会话工作区**后：

1. **整段会话持续**：一次会话几十次工具调用（读/改/跑测试/产物），不能每次弹 picker；
2. **目录树**：任意深度子目录都要遍历（`src/`、`build/`、依赖目录）；
3. **写操作**：新建 / 删除 / 重命名 / 覆盖；
4. **符号链接**：项目内 symlink 需跟随；
5. **重启恢复**：长任务中断后恢复会话，仍需访问同一工作区。

系统 picker 只给「单次 / 单文件 / 单目录」授权，**上述任一条都覆盖不了** ⇒ 全盘权限是唯一可行实现，且仅用于用户主动选择的工作区。

---

## 3. 本轮改动

### 3.1 `reason` 文案（两端资源）

- `entry/src/main/resources/base/element/string.json` → `perm_full_disk_reason`（中文 161 字符）
- `entry/src/main/resources/en_US/element/string.json` → 同 key（英文 253 字符，≤256 上限）

中文新文案：

> 用户将本地文件夹选定为会话工作区后，该会话内的文件浏览与编辑、全文搜索、Python 及构建工具需对已授权目录及其全部子目录持续读写（含符号链接、新建/删除/重命名），并在会话恢复或应用重启后继续可用；系统的单次/单文件授权无法覆盖整段会话的完全访问，故需全盘文件权限。仅访问用户主动选择的工作区，不上传、不读取其他目录。

英文新文案：

> User-picked session workspace: in-session editing, search, Python/build need continuous read/write on it and all subfolders (incl. symlinks, create/delete/rename) and after restart; per-use grants can't cover one session. Only that workspace; no upload.

### 3.2 `module.json5` 注释

`entry/src/main/module.json5` 的该权限条目注释追加「2026-11-21 二次驳回」说明，记录会话级完全控制口径与 `docs/200` 指引。

### 3.3 给 AGC 的说明与截图口径

新增 `docs/200-ACCESS_USER_FULL_DISK必要性说明（会话授权完全控制）.md`：

- 权限用途与最小化边界；
- picker 模型 vs 会话需求的逐条对比；
- 代码事实（`isPathWithin` 限界、`restoreFolderGrants` 重启恢复）；
- **截图建议 5 张**：选择工作区 / 会话内读取（路径在工作区）/ 会话内写入（文件变化）/ 重启恢复后仍可读写 / 子目录或 symlink。

---

## 4. 验证

| 项 | 结果 |
|---|---|
| `node tools/check-permission-surface.mjs` | **PASS**：entry 19 条 / phone 9 条、reason 无孤儿、退役词 0 命中 |
| `devecocli build --product default --build-mode debug` | **BUILD SUCCESSFUL** |
| `reason` 长度 | 中文 161 / 英文 253 字符（≤256） |

---

## 5. 边界

- **不新增/删除权限**（entry 19 / phone 9 不变）；
- `usedScene.when` 保持 `inuse`（最小化，非 always）；
- 不改任何业务代码，仅资源文案 + 注释 + 文档。

---

## 6. 待用户操作（AGC 申诉）

1. 用本轮构建的包重新提交；
2. 申诉附 `docs/200` 的论证 + 5 张截图（尤其「重启恢复后仍能读写同一工作区」——这是「会话授权完全控制」最直接的证据）；
3. 若审核仍追问，补充会话内工具调用轨迹（显示绝对路径落在所选工作区内）。

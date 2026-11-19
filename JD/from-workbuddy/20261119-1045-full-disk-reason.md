# 交接单：响应 AGC 驳回项① — 全盘权限 reason/usedScene 合规化

- **ID**：JD-009
- **提交方**：WorkBuddy
- **日期**：2026-11-19 10:45
- **状态**：待 DevEco 编译 / 出 AGC 包 / 重提审核
- **对应看板**：[`../STATUS.md`](../STATUS.md)

## 1. 背景（AGC 审核反馈，releaseState=1 上架审核不通过）

驳回项①原文要求：申请 `ohos.permission.ACCESS_USER_FULL_DISK` 需遵循**最小化原则**，并在 `module.json5` 的 `requestPermissions` 里把该权限的 `reason` 字段填写**实际使用该权限的功能场景**。

> 其余两项（② 演示录屏、③ 竖屏 UX）由用户自行处理，不在本单范围。

## 2. 已落地改动（开发侧）

| 文件 | 改动 |
|---|---|
| `entry/src/main/module.json5` | 该权限 `usedScene.when`：`always` → **`inuse`**（仅功能使用时）；补审核来源注释 |
| `entry/src/main/resources/base/element/string.json` | `perm_full_disk_reason` 中文文案改为具体场景 |
| `entry/src/main/resources/en_US/element/string.json` | 对应英文文案 |

**新 reason（中文）**：
> 仅用于 PC / 2in1：读写用户选为项目工作区的本地文件夹（含符号链接）并运行随包工具链；不访问其他目录。

**英文**：
> PC / 2in1 only: reads and writes the local folder the user selects as the project workspace (including symlinks) and runs the bundled toolchain; no other directories are accessed.

## 3. 消费点证据（证明"必须使用"的场景真实存在）

- `platform/src/main/ets/system/FilePicker.ets` 的 `pickFolder()`：`DocumentViewPicker` 选任意本地文件夹 → URI 转真实路径 → 持久授权为工作区。
- `hostcore/plugins/dshm-tool-fs-remove/lib/fs-fence.js`：`SCOPE_USER_ROOT = "~"`，"该前缀之下全域可读写"——全盘权限的运行时消费点。
- `hostcore/app/main.js`：`DEVICE_SANDBOX_PREFIXES = ['/data/storage','/storage/Users']`。

## 4. 验证（开发侧已跑）

- `node tools/check-permission-surface.mjs` → **PASS**（entry 18 / phone 9、reason 无孤儿、退役词表 0 命中）。
- `node tools/check-permission-surface.mjs --self-test` → **PASS**（少一条/加一条/换序/坏 reason 均判红）。

## 5. 请 DevEco 做的事

1. 编译（`devecocli build --product default`），确认资源与 manifest 正常。
2. 出 AGC 包：`CODEBUDDY_SAFE_DELETE_ENABLED=0 node tools/build-agc.mjs`（当前源码版本 `1.1.8 / 1010018`）。
3. 上传 AGC 并**重新提交审核**；审核备注建议写明：「全盘权限仅用于 PC / 2in1 的本地项目工作区读写，平板与手机不触发该能力」。
4. AGC 侧当前被驳回版本为 `1.1.8 / 1010017`（`versionId=2022732350219131712`），新包请按 1010018 提交。
5. 结论写 `JD/from-deveco/20261119-rc5-sync-result.md` 或新文件，更新 `STATUS.md`（JD-009）。

## 6. 边界与风险

- **未改权限条数**（entry 恒 18 / phone 9，门禁钉死）；未拆 HAP（Edge/ProMax 双形态必须 `[tablet,2in1]`）。
- `ACCESS_USER_FULL_DISK` 为 `deviceTypes=['2in1']` 的受限权限，随 entry（tablet+2in1）声明；reason/usedScene 已在文案层明确"仅 PC/2in1"。若审核仍要求物理隔离，需产品层面拆 2in1 专用 HAP（结构改动，需另行拍板）。

## 7. 红线

未 `git commit`；未卸载；未删交付件；未改版本号（1010018 为用户此前明确要求）。

## 8. 上架前预检结果（2026-11-19 10:55，WorkBuddy 已执行）

**本地门禁（全绿）**
- `check-permission-surface`：entry 18 / phone 9、reason 无孤儿（含 `--self-test`）
- `check-brand-surface`：110/0；`check-store-readiness`：PASS
- `check-sidebar-shim-css`：32/0；`check-phone-sidebar-core-compat`：PASS；`check-dual-shell-parity`：OK；`check-window-mode`：27/0

**竖屏适配核查（代码层已落地）**
- `<1024`：`tagLayout()` 补 `data-sidebar-drawer`，交官方抽屉浮层；写死 280/56 只在 `@media (min-width:1024px)` 生效。
- `tick()` 由 `setInterval(tick, 300ms)` 驱动，内部调用 `tagLayout()` ⇒ 横竖屏切换后 ≤300ms 自动补/摘 drawer 属性。
- 审核所报竖屏问题针对旧包（1010017）；新包需在 MatePad Pro 11（API 24）竖屏复验。

**AGC 只读预检**
- `qual-dependent`：资质项均 `required=0`（仅可选授权书），**无强制资质缺口**。
- `version-voc`：total=0（无未解决 VOC）。
- `compile-status`：`successStatus=0`（编译/解析成功）。
- `app-info`：`releaseState=1`（**仍为驳回状态**，等待新包重提）。

**权限可用性结论**
- SDK `ACCESS_USER_FULL_DISK`：`system_basic` + `grantMode=manual_settings` ⇒ 用户在设置中手动开启，`usedScene.when` 不参与授予，**改 `inuse` 不影响功能**。
- `build-agc.mjs` 不改 `when`（AGC 包保留 `inuse`）；`build-beta.mjs` 注入写死 `always`，仅影响本地测试包、不进审核。

## 9. AGC 隐私协议核对（2026-11-19 11:00）

**现状**：最新隐私协议 `id=2068131051053539008`（`versionCode=4`，`status=2` 已发布，`lastAuditResult` 通过），更新 2026-11-12 10:28:38；旧版 `id=2058241561019327424`（v1）。

**已声明权限（仅 5 条）**：Documents / Download / Desktop 三个公共目录、麦克风、剪贴板。
**manifest 声明 18 条** ⇒ 差集 13 条。

### P0 必须补
1. **`ACCESS_USER_FULL_DISK` 未在隐私协议声明**（与驳回项①同一权限）。且"文件夹"组只写三个公共目录，未写"用户选择的任意本地文件夹（项目工作区）"。
   - 建议（groupId=15 文件夹组）：`ACCESS_USER_FULL_DISK`，说明「仅在 PC / 2in1 上读写您主动选为项目工作区的本地文件夹（含符号链接）；平板与手机不触发」。
2. **"所有数据均存储在设备本地，不上传云端"与事实不符**（AI 模型服务、自建 Host、华为云同步）。
   - 建议改：「会话记录、工作区文件与配置默认保存在本机；当您主动配置并使用第三方模型服务或自建 Host 时，相关对话内容会发送到您指定的服务，以其隐私政策为准；云同步为可选项，开启后经华为云空间同步。」

### P1 建议补（避免声明面与隐私政策不一致）
3. `FILE_ACCESS_PERSIST`（持久授权，同属文件夹组）。
4. 网络：`INTERNET` / `GET_NETWORK_INFO` —— 说明"连接您指定的 Host/模型服务、检测网络状态"。
5. 后台：`KEEP_BACKGROUND_RUNNING` / `PREPARE_APP_TERMINATE` —— 长任务保持运行、关闭窗口后台继续。
6. `VIBRATE` / `STORE_PERSISTENT_DATA` / `RUNNING_LOCK` —— 在权限清单或正文说明。
7. 开发工具受限权限（`ALLOW_EXTERNAL_NATIVE_CODE` / `CUSTOM_SANDBOX` / `kernel.*`）——模板若无分组，至少在正文写明"本地 AI 编程工具，需加载随包原生工具链"。

### P2 数据收集场景不足
8. 现仅声明"文字信息 / 实现应用功能"。建议补：语音输入（音频转写、不存录音）、剪贴板（用户主动粘贴）、本地文件（工作区读写）、会话内容（发送至用户配置的模型服务）、配置/日志（本地）。
9. `managePersonalInfo.infoAccess.personalSettingPath` 现值「设置-应用和云服务-dshm-文件和文件夹」建议核对与实际一致。

### 流程提醒
隐私协议修改后需 `privacy-submit` 提交**隐私协议审核**，通过后再提应用审核；否则应用审核会因隐私政策不完整再次驳回。修改属提审类动作，需用户确认后在 AGC 控制台或 CLI 执行。

## 10. 隐私协议更新执行结果（2026-11-19 11:10）

**结论：API 无法更新，需在 AGC 控制台编辑。**

- `PUT /api/publish/v2/agreement` → HTTP 200 但业务错误 `204144850 agreement not allow update`
  （官方说明：协议被在架版本关联时，API 不允许直接编辑，需控制台编辑后提交运营审核）。
- 按 `SubAgreement.srcAgreementId` 尝试派生：`POST /api/publish/v2/agreement` 返回 `id=2086962591854238464`，
  但随后 `agreement/list`（含 `status=1/2、id` 过滤）与 `GET ?id=` 均**查不到该记录**（404 / total 仍 2）
  ⇒ 派生记录未生效、API 不可见，不可用。
- 未执行 `privacy-submit`（提审由用户人工做）。

**已准备好的变更内容**（存档 `AGC-operations/agc/privacy-update-20261119.json`）：
1. 「文件夹」组追加两条：
   - `ohos.permission.ACCESS_USER_FULL_DISK` — 允许应用访问公共目录外的本地文件夹（仅 PC / 2in1）
   - `ohos.permission.FILE_ACCESS_PERSIST` — 允许应用持久保存您授权访问的目录
   - 组 reason：「允许应用访问公共目录下的 Documents、Download、Desktop 目录；在 PC / 2in1 上，允许读写您主动选为项目工作区的本地文件夹（含符号链接），并持久保存该授权；平板与手机不触发全盘访问。」
2. `storageInfo.storagePeriod` →
   「会话记录、工作区文件与配置默认保存在本机；当您主动配置并使用第三方模型服务或自建 Host 时，相关对话内容会发送到您指定的服务，以其隐私政策为准；云同步为可选项，开启后经华为云空间同步。」
3. `abstracts` →
   「本应用不设立自有服务端账户体系；会话记录、工作区文件与配置数据默认保存在您的设备本地。AI 功能需您自行配置模型服务凭据，仅在您主动使用时将相关对话发送至该服务。」

**请在控制台执行**：协议服务 → 隐私政策 → 编辑（会生成新版本）→ 按上面三项填写 → 提交运营审核。

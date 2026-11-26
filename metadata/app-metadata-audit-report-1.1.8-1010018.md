# DSHM 1.1.8（1010018）AGC 元数据预审（出包前）

- 审查日期：2026-11-19
- 依据：`app-metadata-audit-skill`（华为应用市场审核规范）+ 本地发布元数据 + 当前源码 / 包结构
- 审查对象：
  - `metadata/agc-listing-1.1.8-1010017-zh-CN.json`（基础 listing， appName / briefInfo / appDesc / appRemark / 设备面 / 隐私政策绑定）
  - `metadata/agc-listing-1.1.8-rc2-zh-CN.json`（1010018 / rc.5 新版本特性草稿）
  - `metadata/agc-app-info-update-1.1.8-1010017.json`（sensitivePermissionDesc 18 条）
  - `AppScope/app.json5`、`entry|phone module.json5` + 18/9 条 reason 字符串、`AGC-operations/agc/privacy-update-20261119.json`
- 前置事实：AGC 现存 `1.1.8 / 1010017` 为 `releaseState=1` 驳回（驳回项① 全盘权限 reason 最小化，② 演示录屏，③ 竖屏 UX）；本包为 1010018 重提件。

## 一、结论表

| 字段 | 状态 | 审查结论 | 建议 |
|---|---|---|---|
| 应用名称 | 🟢 | `DSHM` 4 字符；包内 `app_name` / `EntryAbility_label` / `AppScope` 全部一致为 `DSHM`，无「鲸鸿」文案；无泛词、价格、占位符、特殊符号、竞品名 | 保持 |
| 一句话简介 | 🟢 | 「本地运行的 AI 编程工作台」14 字符，与能力一致 | 保持 |
| 应用介绍 | 🟢 | 496 字符（贴近 500 上限）；只描述实际能力；无禁用词、竞品名、夸大宣传、个人信息 | 保持；若再改注意上限 |
| 新版本特性 | 🟢 | 1010018 用 rc2 草稿（156 字符）：版本 1010018 / 核心 0.2.2-rc.5+dshm.1 与包一致；终端分档（PC / 2in1 / MatePad Edge / Pro Max 原生，其余 guest VM）与 `DeviceFacts` 口径一致 | 推送时**删除草稿句**「此文件为发布草稿，不代表已出包或真机验收通过。」；若 1010017 未上架，可改为 8 项完整文案 + rc.5 对齐说明（推送时拍板） |
| 权限用途说明（包内） | 🟢 | entry 18 / phone 9 条 reason 全中文，逐条与 AGC 侧 `sensitivePermissionDesc` 一致；FULL_DISK reason 已按驳回项①改为最小化场景 + `when=inuse`（JD-009） | 保持 |
| 权限用途说明（AGC 侧） | 🟡 | `sensitivePermissionDesc.ACCESS_USER_FULL_DISK` 仍为旧文案「（该受限权限已通过应用市场审批）」 | 重提时建议改为与新包 reason 同口径：「仅用于 PC / 2in1：读写用户选为项目工作区的本地文件夹（含符号链接）并运行随包工具链；不访问其他目录。平板与手机不触发该能力」 |
| 设备类型 | 🟢 | 手机 4 / 平板 5 / PC·2in1 19；包内 `entry`(tablet,2in1) + `phone`(phone) + `hostruntime`(三端) 匹配 | 保持 |
| 隐私政策（绑定） | 🟢 | 仅绑定 `2068131051053539008`（v4，status=2 已发布）；URL 可达（HTTP 200，JS 渲染页） | 保持单一绑定 |
| 隐私政策（内容） | 🔴 | **P0 缺口未闭环**：`ACCESS_USER_FULL_DISK` 未声明；「所有数据均存储在设备本地，不上传云端」与 AI 模型服务 / 自建 Host / 云同步事实不符。变更内容已备好（`AGC-operations/agc/privacy-update-20261119.json`），API 无法改（`204144850 agreement not allow update`），**须控制台编辑 → 隐私协议审核通过后再提应用审核**，否则将再次驳回 | 用户在控制台按已备内容执行（JD-009 §10） |
| 截图 | 🟡 | 本地素材齐（手机 4 / 平板 3 / 2in1 3）；最近一次上传记录（1.1.7）只列 PC 3 张，手机 / 平板为更早存量 | 控制台核对手机 / 平板截图仍在且方向正确、内容不重复 |
| 演示录屏（驳回项②） | 🔴 | 本地无演示视频素材；审核要求需提供（特殊运行环境场景） | 用户补录并上传（与隐私政策修复同为重提前置） |
| 竖屏 UX（驳回项③） | 🟡 | 代码层已落地（`<1024` 交官方抽屉）；需 MatePad Pro 11 竖屏真机复验 | 用户真机自测后重提 |
| 测试账号 / 审核备注 | 🟢 | 无自有账号体系；`appRemark` 已说明可跳过云同步、模型凭据自备、三端测试建议 | 保持 |
| AI 生成声明 | 🟢 | `isAiGenerate=1`、`aiTypes=[1]`；会话界面有「内容由 AI 生成」标识 | 控制台核对是否需补语音类枚举（沿旧结论） |
| 年龄分级 / 备案 / 主体 | 🟡 | 本地无判定依据；前次提交已在控制台存量 | 重提前逐项核对 |
| 关键词 | 🟡 | 本地无关键词字段 | 控制台确认存量；不堆砌热词 |

## 二、结论

- **本地 / 包结构：无阻断项。** 名称、简介、介绍、权限面（18/9 全中文且与 AGC 侧一致）、设备面、品牌一致性、版本号（1010018 / rc.5）全部合规，可以出包。
- **重提前置（控制台动作，不阻塞出包）**：
  1. 隐私政策按 `privacy-update-20261119.json` 控制台编辑并过隐私协议审核（P0，不做必再驳回）；
  2. 补演示录屏（驳回项②）；
  3. 竖屏真机复验（驳回项③）；
  4. 推送时 FULL_DISK 的 AGC 侧描述同步为新口径；新版本特性删除草稿句。

## 三、与包结构的一致性核验（2026-11-19 出包后实测）

- AGC 包：`dist/release-test/dshm-1.1.8-1010018-dshm.1-AGC-invite-20261119T125442.app`（663,664,417 B，sha256 `7b9422bb…`，`.app.sha256` + `SHA256SUMS.txt` 已记）
- `pack.info`：`com.dshm.dshclient` / `1.1.8` / `1010018`；模块 entry-default.hap（tablet,2in1）+ phone-default.hap（phone）+ hostruntime-default.hsp（三端）
- `check-permission-surface`：entry 18 / phone 9、reason 无孤儿、退役词表 0 命中 ✅
- `check-resfile-core-zip` + `assert-resfile-sync`：恰 1 份 rc.5 容器（203,023,707 B，sha256 `61749b16…`，与配方一致）；27 件宿主 JS 快照全同步 ✅
- `hap-sign-tool verify-app`：独立验签通过（`verify-app success`）✅
- 出包后身份已还原（`AppScope/app.json5` bundleName=`com.dshm.dshclient`）✅

> 说明：本报告只基于本地文件与公开可达性检查；截图内容、隐私政策正文、年龄分级与主体资质只能在 AGC 控制台确认，本地无法替代。

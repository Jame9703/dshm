# 189 · 历史文档合并与移交索引

> 2026-10-18。本文记录 DSHM 从长期开发态转入 Beta 维护与交接态时的文档收口：
> 哪些旧结论已经过时、当前事实在哪里、哪些历史材料必须保留、哪些本地产物可以清理。
>
> 当前基线：Beta `1.1.4 / 1010004`，核心 `0.2.1-rc.2+dshm.73`。

## 1. 为什么合并

项目前期采用“每个坑一篇编号文档”的记录方式。这种方式保住了根因和真机读数，
但到 188 篇时出现了三个问题：

1. `HANDOFF.md` 长期停留在 2026-10-04，仍写旧包名、旧核心和已修复问题。
2. 根 `README.md` 仍写“11 条权限 / 5 条 ACL”，与当前恒 8 条权限冲突。
3. `docs/README.md` 变成超大流水账，当前入口、历史证据和过时结论混在一起。

本次不删除契约和事故证据，而是重新分层：

- 当前状态放到 `docs/HANDOFF.md`；
- 导航放到 `docs/README.md`；
- 旧结论和归档规则放到本文；
- 被后续结论推翻的专题文档在原文顶部加“历史/已取代”提示；
- 只删除可重建的本机构建和调试产物。

## 2. 当前事实入口

发生冲突时按以下顺序取事实：

1. 当前源码、配置、构建产物和运行中的设备；
2. 仓库门禁与 `dist/acceptance/` 真机证据；
3. `docs/HANDOFF.md`；
4. `docs/README.md`；
5. 本编号区间的历史专题文档。

当前交付件：

| 项 | 值 |
|---|---|
| HAP | `dist/sideload/DSHM-beta-1.1.4-core0.2.1-rc.2+dshm.73-arm64-signed.hap` |
| 版本 | `1.1.4 / 1010004` |
| 核心 | `0.2.1-rc.2+dshm.73` |
| 包名 | `com.dshm.dshmbeta` |
| 最低 API | `60100023` |
| 目标 API | `260000026` |
| 权限 | 8 条 |
| APK 条目 | 0 |
| 大小 | `437,399,349 B` |
| SHA256 | `B22B8C5558ABA3D13BB7DECA5AF1311A0D071115E10AB64DCB854B677242FA91` |

## 3. 旧结论与当前替代

| 旧说法 | 状态 | 当前替代 |
|---|---|---|
| 权限共 11 项，其中 5 项 ACL | 作废 | 恒 8 条：2 条已审批 ACL + 6 条免申请；见 `AGENTS.md`、`docs/154`、`docs/161` |
| 最低兼容版本 `6.1.1(24)` | 已更新 | `6.1.0(23)`；手持档无 `FolderSelection` 时使用 `Download/<包名>` 专属工作区；见 `docs/183` |
| 目标版本写作 `26.0.0(26.0.0)` | 作废 | 当前必须是 `targetSdkVersion = "26.0.0"`，不带括号；见 `build-profile.json5` |
| 当前版本 `1.1.0 / alpha.1 / +dshm.13` | 过时 | `1.1.4 / 1010004 / 0.2.1-rc.2+dshm.73` |
| 手机和平板没有 shell，终端不可用 | 历史边界 | 当前走 guest QEMU，侧边栏终端和 bash 工具可用；见 `docs/155`、`docs/188` |
| 侧载包约 300 MiB | 过时 | 当前 HAP 为 `437,399,349 B` |
| PC 和手持档各自走不同终端实现 | 已收口 | 当前产品路径统一使用 guest VM 能力；不再依赖宿主 ELF 执行 |
| 长连接抖动必须调大心跳 | 未复现的旧假设 | 当前恢复官方默认；没有现场读数前不得重新覆盖 |
| 启动约 40 秒自杀仍待定位 | 旧版本历史问题 | 当前版本未再复现；作为残余风险观察，不作为当前已证 bug |
| 浏览器自动化三端可用 | 已收口 | 只支持 PC / 2in1；移动端不注册 `browser_*` |
| API 23 可以直接支持任意目录选择 | 平台不成立 | 只能使用专属目录兜底，不能伪造系统能力 |
| 历史受限权限可以重新加回 | 永久禁止 | 第 9 条永不写；源码、包体和文档都不回补 |

## 4. 文档分层

### 当前权威

| 文档 | 用途 |
|---|---|
| `AGENTS.md` | 工作约束、物理门禁、权限铁律、必跑门禁 |
| `README.md` | 项目定位、架构、构建、数据保全 |
| `docs/HANDOFF.md` | 当前交接总览 |
| `docs/README.md` | 文档导航与状态说明 |
| `docs/183` | API 23 安装与工作区兜底 |
| `docs/184` | DSH `0.2.1-rc.2` 上游同步 |
| `docs/185` | 平板手持窗口壳 |
| `docs/186` | 新增功能代码审核与 PC / 手机双端回归 |
| `docs/187` | 手机底部系统手势条与 Web 统计栏 |
| `docs/188` | QGA、SSH、分屏视口与键盘输入 |
| `docs/189` | 本文，历史合并和交接索引 |

### 契约与长期方法

`docs/00`、`10`、`11`、`12`、`20`、`30`、`40`、`50`、`60`、`70`、`80`、`90`
以及 `parity-matrix.md`、`device-validation.md` 继续保留。它们是协议、架构、
流程、事故和真机读数基线，不应为了“目录干净”删除。

### 历史专题

`docs/95` 到 `docs/182` 是问题台账、调研、根因和修复记录。它们仍然有价值：

- 查到某个历史结论时，先看该文档顶部是否有作废提示；
- 当前状态回到 `docs/HANDOFF.md` 或更新的编号文档；
- 不要从旧文档直接复制权限数、API 版本、包名、核心版本和性能读数；
- 文档之间的行号引用由 `tools/check-doc-refs.mjs` 校验，不应随意改编号或删段。

### 非编号历史快照

以下文件是历史快照，不是当前入口：

- `docs/review-report-2026-09-29.md`
- `docs/review-report-2026-10-04.md`
- `docs/functional-test-report.md`
- `docs/rc2-workspace-diagnosis.md`
- `docs/ia-parity-plan.md`

需要评估当前质量时，应重新跑门禁并读取最新验收目录，不能把旧审核结论直接当成现状。

## 5. 为什么不物理删除所有旧文档

旧文档同时承担审计证据和行号引用基线。直接删除会带来三类风险：

1. 破坏 `tools/check-doc-refs.mjs` 中已有的 `文件:行号` 证据链。
2. 丢失事故根因，接手人可能重复添加错误权限或重复走已证伪方案。
3. 无法区分“当时测过但后来被推翻”和“从未验证”。

因此本次采用“保留原文 + 顶部标记 + 索引收口”的方式清理内容。
真正删除的对象只限可重建的构建缓存、临时探针、调试日志和确认不再引用的中间产物。

## 6. 本次本地清理

清理原则：

- 删除前先把路径解析为绝对路径并确认位于本工作区；
- 不跟随目录联接去删除工作区外目标；
- 不删除签名物料、侧载包、AGC 历史件、验收证据、核心 zip / manifest、工具链和 `third_party`；
- 不碰设备数据和 `D:\desktop\ohos\DSHM`。

实际释放约 **11.2 GiB**，删除项：

- `entry/build/`
- `entry/.cxx/`
- `.hvigor/`
- `appstate/build/`、`connection/build/`、`dshcompat/build/`、
  `hostruntime/build/`、`platform/build/`
- `dist/core/work/`，可由核心 zip 和 manifest 重新物化
- `dist/arkts-entry/`、`dist/layout-fixtures/`
- `dist/dbg/` 中非验收文件；10 个现场图已先迁入
  `dist/acceptance/20261017-ui-debug/`
- `dist/beta/` 中 4 个重复历史 HAP；目录内说明和校验文本保留，
  当前侧载历史仍在 `dist/sideload/`
- 本轮构建、探针、浏览器排查和品牌预览临时文件

明确保留：

- `dist/sideload/`
- `dist/acceptance/`
- `dist/backup/`
- `dist/core/*.zip` 与 `*.manifest.json`
- `dist/release-test/`
- `dist/apms/`
- `dist/cert-check/`
- `dist/agentcard/`
- `dist/plugsrc/`、`dist/localtest/`、`dist/pcverify-156/` 等仍被历史文档或工具引用的材料
- `third_party/`、`entry/libs/`、`entry/src/main/resources/resfile/`
- `C:\Users\Sol\.ohos`、`D:\DSHM-signing-backup`、正式工作区和设备数据

清理后，核心树门禁需要先跑 `node tools/pack-core.mjs --skip-install --place-in-app`
重新物化 `dist/core/work/`；这是预期行为，不是缺文件。

## 7. 交接人下一步

1. 先读 `docs/HANDOFF.md`。
2. 再读 `AGENTS.md` 的物理门禁、权限面、真机数据三节。
3. 跑 `git status --short`，不要回滚当前脏树。
4. 跑权限、APK、文档、接线、resfile、核心补丁门禁。
5. 需要真机时只使用 `hdc install -r`。
6. 平板和 API 23 必须单独验收，不能用手机或 PC 读数替代。
7. 新结论写入新的编号文档或 `dist/acceptance/`，不要静默改写历史结论。


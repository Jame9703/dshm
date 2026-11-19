# 157 PC 档工作区目录「重启后读不到」的根因与修复（picker 授权只活一个进程 · 三端统一授权链）

## 结论

用户「重启后，之前选定的工作区文件目录又读不到了」「工作区目录文件依旧不给读」这条，
在 PC（2in1）档上**与手持档 `docs/105` 逐字同构**：系统 picker 给目录的授权**只活一次进程**，
进程一结束就没了；宿主（Node / `dsh-fs-local` 的裸 `node:fs`）与应用**同 UID 同进程**，
它能不能 `readdir` 那个目录完全取决于这份授权还在不在。

而 PC 档此前在这条链上**缺两环**：

1. **不登记**：`WebApp.doPick()` 里自己写了一遍 `persistPermission`，但**没有**把这次选择
   记进偏好库（`platform/.../FolderGrants.ets` 的 `addStoredGrant`）；`FilePicker.pickFolder()`
   的 PC 分支干脆整段不做持久化（判据只看 `probePathWritable()`，而探写用的是**当次进程**的临时授权
   ⇒ 选完必然为真，看不出"重启后就没了"）。
2. **不启用**：`EntryAbility` 的启动恢复 `restoreFolderGrants()` 包在 `if (isHandheldForm())` 里，
   PC 档**一次都没跑过** ⇒ 即便登记写下了，重启后也没人 `activatePermission()`。

⇒ 结果是一条**必然复现**的链：选完当场能读 → 重启后同一条路径 `Errno 1 Operation not permitted`
→ 用户只能再选一次（`diag-folder-grants` 里能看到每轮开机都是"无已登记目录"）。

修法是把三端收敛到**同一条授权链**：**登记 → persist → check**（选的时候）+
**activate**（每次启动）。PC 档额外保留 `probePathWritable()` 作为"能读不能写"的第二道判据。

## 现场读数（PC 单机 `86E0226429000417`，`const.product.devicetype=2in1`）

### 1. 注册表里有两条工作区，两条都读不到

`dsh/home/storages/workspace.json`（经进程内 python 桥以应用身份读，2026-10-14）：

| id | path | title | createdAt |
|---|---|---|---|
| `e3df2165-…` | `~/harness` | harness | `2026-10-14T10:23:07.599Z` |
| `cdd9005d-…` | `~/test` | test | `2026-10-14T10:37:34.214Z` |

### 2. 授权现场：只有"按包名归属"的那条活着

同一进程内 python（`uid 20020303`，`2026-10-14T10:55:36Z`）逐条 `os.listdir`：

```
~                              ERR PermissionError [Errno 1] Operation not permitted
~/Download                     ERR PermissionError [Errno 1] Operation not permitted
~/Download/com.dshm.dshclient   OK n=14
~/harness                      ERR PermissionError [Errno 1] Operation not permitted
~/test                         ERR PermissionError [Errno 1] Operation not permitted
```

**读法**：`Download/<包名>/` 那条能列（官方 FAQ `faqs-local-file-manager-67` 口径：按包名归属的
路径级授权**跨重启有效**），另外三条都 `EPERM`。⇒ 不是"整个用户目录不可达"，
而是**用户自己选的目录失权**。

### 3. 旧行为的时间线（证明"每次重启都得重选"）

`filesDir/diag-*`（同一台机、同一个装机件之前的几轮）：

```
diag-pick-called        2026-10-14T10:23:03.667Z id=…
                        2026-10-14T10:37:25.568Z id=…     ← 两次"选择文件夹"，跨两次启动
diag-resolve-dispatched 2026-10-14T10:23:07.593Z path=~/harness
                        2026-10-14T10:37:34.206Z path=~/test
```

### 4. 本轮装机件（含修法）的启动读数

```
diag-folder-grants      2026-10-14T10:53:53.348Z restore：无已登记目录（跳过）
```

这一行同时说明两件事：

- ✅ **修法在设备上生效**：PC 档启动期**真的跑了** `restoreFolderGrants()`（旧装机件不会有这一行）；
- ❌ **但设备上一条持久登记都没有**（`preferences/` 目录为空），所以**没有东西可启用**。

`persistPermission()` 只能对**picker 当次返回的 URI** 生效 —— 没有用户的一次真实选择，
这一条**在平台层面造不出来**。⇒ 本轮修法要真正闭环，**必须由用户在界面上重选一次目录**
（侧边栏 → 工作区面板 →「选择文件夹」）。这一次之后：登记进偏好库、`activatePermission()`
每次开机重新启用，**不用再选第二次**。

## 修改

| 文件 | 改动 |
|---|---|
| `platform/src/main/ets/system/FilePicker.ets` | `pickFolder()` 三端**都** `await rememberFolderGrant(context, uri, realPath)`；PC 档采纳判据由"只看探写"改成 `granted.persisted \|\| probePathWritable(realPath)`；头注更正"PC 档本来就读得到 picker 目录"这条已失效的旧口径 |
| `entry/src/main/ets/pages/WebApp.ets` | `doPick()` 删掉自己那份"只 persist、不 check、不登记"的内联块，改走 `rememberFolderGrant()`（登记 + persist + check，每步 3 s 看门狗）；`diag-persist-done` / `diag-persist-skip` 两个标记**名字不动**（现场排查一直在用），内容换成 `granted.note` 原始读数 |
| `entry/src/main/ets/entryability/EntryAbility.ets` | 去掉 `if (isHandheldForm())` 闸门，`restoreFolderGrants(this.context)` **三端都跑**；`isHandheldForm` 在本文件另有 4 处用途，import 保留 |
| `tools/check-feature-wiring.mjs` | 新增正向功能 `目录授权跨启动恢复（三端）`（4 条接线 pattern）+ 多行反面规则 `三端授权链不得按形态排除`（覆盖上述 3 个文件）+ `hint`；`stripComments` 改为**等量空白**以保留行号；新增 `--self-test` 3 条对照臂（退回启动闸门 / 退回 pick 分叉 / 退回只看探写） |
| `.github/workflows/gates.yml` | 把 `check-feature-wiring` 接进 CI（主跑 + `--self-test` 两条）。此前**不在 CI 里** ⇒ 新加的反面规则等于只在本地有牙 |

### 门禁读数

```
node tools/check-feature-wiring.mjs            → rc 0（137 文件 / 23 功能 / 2 条反面规则）
node tools/check-feature-wiring.mjs --self-test → 3/3 对照臂判红，rc 0
```

三条对照臂各自把修法**退回一个版本**并断言门禁必红：

1. 把启动恢复重新包进 `isHandheldForm()` 闸门 ⇒ 命中 `EntryAbility.ets:544` 反面规则；
2. 把 pick 处的授权登记退回"非手持档不记授权" ⇒ 命中 `FilePicker.ets:208` 反面规则；
3. 把 PC 支的采纳判据退回"只看探写" ⇒ 正向功能缺接线（`granted.persisted || probePathWritable(path)` 0 处）。

## 真机验证

**第一轮**（2026-10-14 早些时候，覆盖安装）：装机件 `entry-default-signed.hap` 406,912,861 B /
sha256 `F4E16AE638E65125797D383CEC6F637425715B454C236DB402C42A268F33FA9E`，冷启动成功、
home 数据指纹 `links=8 size=3440` **未变**、核心树仍 `+dshm.46`，启动期出现
`restore：无已登记目录（跳过）` ⇒ PC 档恢复链已接上，但当时设备上**一条持久授权都没有**
⇒ 闭环只能等一次真实选择，本轮没有替用户造授权、也没有动注册表。

**第二轮 = 全新装 + 闭环**（2026-10-14 19:00，同一装机件，sha256 与上轮**逐字节相同**）：

> 起因是**用户自己手抖把应用卸载了**（`bm dump -n com.dshm.dshclient` 已查不到、
> `/data/app/el{1,2}/100/base/com.dshm.dshclient` 两个目录都不在）。本仓**没有**发起任何卸载
> —— 唯一允许的装机入口 `tools/update-device.ps1` 第 0 步就会扫描自身、调不出卸载命令。
> 于是这一轮变成"**从零数据区**做三端授权链的完整验证"，比覆盖安装更狠：
> 没有旧偏好库、没有旧注册表、没有旧持久授权可以兜底。

| # | 判据 | 现场读数 |
|---|---|---|
| 0 | 全新装冷启动 | 新数据区建出；`--- boot pid=37809`；核心树 `0.2.1-alpha.2+dshm.46` 就位 |
| 1 | 首启无授权可恢复（预期） | `11:00:35.285Z restore：无已登记目录（跳过）` |
| 2 | 选完目录：登记 + persist + **实测**回读 | `11:01:12.125Z remember persisted=true path=~/harness uri=file://docs~/harness 登记=ok persist=ok check=[true]` |
| 3 | 重启把授权启用回来 | `aa force-stop`（pidof 置空）→ `aa start` → `--- boot pid=39085` → `11:01:26.198Z restore 1/1 已启用：~/harness=ok` |
| 4 | **新进程**里以应用身份真读 | python 桥（`/dshm-python/run-get`，token 取新进程 `host-ready.json`）：`LIST OK n=44 sample=['.devlink', '.dsh_env_probe.txt', '.dshm-cap-demo', …]` |
| 5 | 写也通（排除"只读假绿"） | 同一脚本内 `WRITE OK` + `CLEANUP OK`（临时文件当场删除，未留残留） |

> **判据为什么必须是第 2 行的 `check=[true]`**：它出自 `checkPersistentPermission()` 的实测回读。
> `persistPermission()` 没抛错**不等于**成功（本机有"永不 settle"前科），`probePathWritable()` 在
> 当次临时授权下**必然**为真 —— 这两条正是旧版"选完能用、重启就废"的假绿来源（见 §3）。

**顺带读数（全新装特有）**：`toolchain/python` 这次由**进程内解包**落地（日志
`工具链：解包子进程 spawn 失败：Error: spawn EPERM` → `改用进程内解包` → 4 s 内落 3482 个文件），
随后 `python 桥：ready=true / stdlib=true / selftest=ok`；`toolchain/gitroot` 只落标记
（`本档 execve 被拒 ⇒ git 真身起不来，解它只占磁盘`）⇒ 与 `docs/115`/`docs/154` 的既有口径一致。
装机脚本第 8 步那条 `exec 探测未全通` 属**既有**边界（`rg/ash/bash=fail(EPERM)`，
python/git 那几项是探针跑在解包完成之前），见下节。

**第三轮复验（同一数据区，未再装机）**：会话里又起过一次（`11:03:19` `--- boot pid=40121`），
`diag-folder-grants` 第三条依旧 `restore 1/1 已启用：~/harness=ok`
⇒ 恢复链**幂等**、不是一次性的假象；同期 `/data/log/faultlog/faultlogger` 无本包条目
（排除"崩溃后被恢复拉起"这条误读）。同一时刻应用身份（python 桥）读注册表：

```json
{"global":{"initialized":true,"workspaceIds":["72110a69-3e87-46cb-bea5-ce70e527f282"]},
 "tables":{"workspaces":{"72110a69-3e87-46cb-bea5-ce70e527f282":{
   "path":"~/harness","title":"harness",
   "sessionIds":["session-5434beba-68ca-4dab-a6f8-c5f245771e92"],
   "createdAt":"2026-10-14T11:01:12.135Z"}}}}
```

—— 全新装后**只有这一条**（用户自己选的那个），没有 `docs/113` 那条"用户没建过的
`com.dshm.dshclient`"；`os.listdir('~/harness')` 同拍复读仍 44 条。

## 顺带记两条读数（都不是本轮改动引入的）

1. **exec 探测的 EPERM 是既有状态**：`dshm-host.log` 按 `--- boot pid=` 分段，
   `10:08:23`（**本轮改动之前**的那一轮）就已经是
   `rg=fail(EPERM)，ash=fail(EPERM)，bash=fail(EPERM)`，此后每一轮逐字相同。
   ⇒ 与本次"纯 ArkTS 授权链"改动无关，属 8 条权限面的既有边界（`module.json5` 权限面铁律那一段）。
2. **"内存炸了"的归因**：本轮采样宿主 RSS ≈ 990 MB、整机 `MemFree` 14 GB、无爬升；
   上一轮整机被压死的主因是设备系统进程 `virus_protection_executor` 的 OOM 循环
   （RSS 曾 16.5 GB），细节与当时的宿主读数见 `docs/156` 的"归因要说清"一节。

## 未做

- **手机 / 平板档复验**：修法改动是"把 PC 档并进手持档本来的链"，手持档行为应逐字不变，
  但本轮设备只有 PC 单机，未跑；
- **正式侧载件**：本轮产物是 `hvigor` debug 直接装机件，未重出 `dist/sideload/`；
- **VM 共享根**：会话里偶见的 `[dshm-vm-bash] 本会话的 cwd … 在 guest 里不可达`
  （`terminal.js:388` / `vm.js:882`）**不是本轮这处缺陷**：guest 的二份 9p 是
  `stage()` 那一刻按"首个请求的 cwd"定死的（`vm.js:909` `state.extraShare = extraShareRoot(cwd, share)`，
  一进程一 VM 的硬约束见 `docs/119`），**就绪之后**再换 cwd 才会命中那条告警。
  ⇒ 全新装首开终端时 cwd 就是当前工作区，会被正常挂上；`vm/shared-roots.json`（`docs/124`）
  只用于旁挂件清扫、不参与挂载。**同一会话中途换工作区**要换共享根，属另一处改动，本轮未动；
- **未 commit / 未 push**。

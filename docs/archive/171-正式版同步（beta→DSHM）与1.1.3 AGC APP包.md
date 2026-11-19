# 171 · 正式版同步（beta → DSHM）+ 版本号 1.1.3 + AGC `.app` 出包

> **历史状态说明（2026-10-18）**：本文记录的是 1.1.3 正式同步和当时的 AGC 件，
> 不是当前 Beta 基线。当前基线为 `1.1.4 / 1010004 / 0.2.1-rc.2+dshm.73`，
> 见 `docs/HANDOFF.md` 与 `docs/189`。本文不得作为再次跨工作区写入的授权。

> 用户 2026-10-16：**"整理一下新版内容，同步正式版，版本号升一下编译 AGC APP"** ——
> 本档记录**跨工作区同步**（门禁另一侧）、版本号、以及 AGC 上传件的完整读数。

## 1. 双工作区门禁与本次授权

`AGENTS.md` 最高优先级条款：本（beta）工作区**一律不许写** `D:\desktop\ohos\DSHM`；
用户上述指令被本档按**显式授权**处理，同步**只做增量**（不删无关文件），并且**只在 B 侧**做
构建与出包。B 侧改动清单见 §3。

## 2. 同步范围（逐文件 sha256 比对得出，不靠目录时间戳）

两侧都是同一个 git HEAD + 各自未提交脏树；排除 `.git / oh_modules / build / dist / .hvigor /
third_party / .research / tmp-wslscript / .cxx` 后逐文件比对：

- **内容不同 61 项 / 只在 beta 74 项 / 只在 B 12 项** ⇒ 归一成 **52 件要拷**（含新核心包、
  docs/164–170 七篇、entry/platform/hostcore/tools/media 全部增量）+ **B 侧 1 件要替换**
  （旧核心包 `dsh-core-0.2.1-alpha.2+dshm.50…zip` 删掉，换 `…alpha.4+dshm.56…zip`）。
- **刻意不拷的 7 项**（同步后复比：剩余差异恰好只有这 7 项）：
  `build-profile.json5`（两侧各自的签名/包名配置，门禁要求互不覆盖）、
  5× `*/BuildProfile.ets`（hvigor 生成物：A=release / B=debug，构建时各自重生成）、
  `entry/.../string.json`（beta="DSHM beta" vs 正式="DSHM"，**拷完在 B 侧还原成 "DSHM"**）。
- 顺手清掉本工作区根下我自己留下的垃圾文件 `-D`（早期一条 curl 命令把 `-D` 写成输出文件留下的响应头转储）。

## 3. B 侧落地与两个坑（本轮最值钱的两条）

| 动作 | 结果 |
|---|---|
| 拷贝 52 件（含新核心包）+ 删旧核心包 + `string.json` 还原 `DSHM` | ✅ |
| 版本号 `1.1.2/1010002` → **`1.1.3/1010003`**（`AppScope/app.json5`，**两侧同升**） | ✅ |

**坑①：`entry/oh_modules` 在 B 侧是"真目录副本"，A 侧是指向源码的 junction。**
同步完直接编 B 报 `Module '"platform"' has no exported member 'windowChromeFor'` —— 清 `build/` 也没用；
根因是 B 的 `entry/oh_modules/platform` 是上次 `ohpm install` 拷进去的**旧副本**（A 侧同一路径是指向
`../platform` 的 junction，所以 A 永远读活源码）。修法：在 B 跑一次 **`ohpm install --all`**
（DevEco 自带 `tools\ohpm\bin\ohpm.bat`）⇒ 8 个本地依赖全部重建为 junction，编译即通。
> 教训：**"同步源码"不等于"同步依赖视图"** —— 本地 `file:` 依赖若被拷贝成实体目录，改源码不会生效。

**坑②：`signingConfig: "release"` 会让 hvigor 直接死在 `SignHap`（`00303116`）。**
hvigor 拒收**明文**口令（docs/141 已记）；出发布包本来就走 `tools/sign-release-hap.ps1`。
本轮做法：把 B 的 `build-profile.json5` **备份后临时摘掉那一行** ⇒ `assembleApp` 只出
`-unsigned.app`（正是要签的那份）⇒ 签完**按 sha256 还原**该文件（还原后 `3215DFC0…` 逐字节相同）。

## 4. AGC `.app` 出包与读数

```powershell
# 1) 依赖视图对齐（见坑①）
& "$ide\tools\ohpm\bin\ohpm.bat" install --all
# 2) 出 app 包（不吃 --mode module，docs/143）
& "$ide\tools\node\node.exe" "$ide\tools\hvigor\bin\hvigorw.js" assembleApp -p product=default -p buildMode=release --no-daemon
# 3) 用 AGC 发布物料签名（脚本自带 verify-app + release profile 判据；口令备注文件在备份目录里）
.\tools\sign-release-hap.ps1 -InFile build\outputs\default\DSHM-default-unsigned.app -OutFile dist\release-test\DSHM-1.1.3-core0.2.1-alpha.4+dshm.56-arm64-release-signed.app -NoteFile D:\DSHM-signing-backup\release-20261010\新建文本文档.txt
```

| 项 | 读数 |
|---|---|
| unsigned `.app` | `build/outputs/default/DSHM-default-unsigned.app` **228,594,604 B** |
| **signed `.app`（AGC 上传件）** | `dist/release-test/DSHM-1.1.3-core0.2.1-alpha.4+dshm.56-arm64-release-signed.app` **228,609,426 B / sha256 `eccd28d31f1db699a8626ef6b68f157e3363d5c1d669dee535bbdfdc8931e4d0`** |
| `.app` 条目 | `pac.json`(36) + `pack.info`(1,027) + `entry-default.hap`(440,003,283) —— 与 docs/142 的"只签容器"结构一致 |
| `pack.info` | bundle **`com.dshm.dshclient`** / **1.1.3 (1010003)** / deviceTypes **phone,tablet,2in1** / `apiVersion{compatible:24, target:26, releaseType:Release}` |
| 内层 `module.json` | `minAPIVersion=60101024` / `targetAPIVersion=260000026` / **`apiReleaseType=Release`** / `requestPermissions` **8 条**（与发布 profile 的 `allowed-acls` 对齐：摘除 **0** 条）/ **0 个 `.apk` 条目** |
| 签名自验 | `verify-app success`；内嵌 profile `type=release`、`allowed-acls=ALLOW_EXTERNAL_NATIVE_CODE,FILE_ACCESS_PERSIST`、uuid `0bbda76e-e5dd-46f5-9b93-3cda1d87ac84` |

> 发布签名与调试签名**互斥** ⇒ 本件**不能**在已装调试签名同包名的机器上 `install -r`（只能卸载，而卸载清 el2 数据）。
> 本轮**没有**在真机上安装这个 `.app`（它是 AGC 上传件，装机验证继续用 beta 侧载件）。

## 5. 本版（1.1.3）新版内容 · 面向审核 / 用户

1. **内核同步到上游 `0.2.1-alpha.4`**：修掉同步后自带插件被整条停用导致的
   「session controller 不可用」（会话打不开 / 一直卡住）；会话、终端、工作区三个服务恢复；
   依赖闭包锁定，避免同类静默停用复发。
2. **Agent 能力补齐**：恢复「显示代码工作视图」开关；PTC 预设恢复 `run_code`；
   新增 **`python` 工具**（进程内 CPython，不依赖 shell / 虚拟机，手机平板同样可用）。
3. **启动更快**：宿主启动链后置到首帧之后，首屏不再等内核（`docs/166`）。
4. **终端更好用**：延迟静默预热（进 APP 约 1 分钟后、内存充足时把执行环境悄悄拉起，
   第一次开终端不用再等十几秒）；内存不足自动跳过（`docs/166`）。
5. **后台通知收敛**：不再常驻「正在运行数据传输任务」，只在真有任务时出现（`docs/166`）。
6. **返回手势分层**：插件二级页 → 插件列表 → 会话逐层退；插件页直接返回 = 回会话页；
   面板打开时侧栏按钮不再压住面板标题（`docs/166`）。
7. **平板适配**：三键可见时内容整体下移避让；登录后的「设置引导」在手机上竖屏单列可用
   （原先要横过来才点得了）；**状态栏归属收窄**——只有全屏 / 最大化时才由应用着色，
   自由窗口 / 分屏 / 切后台一律交还系统（`docs/167` / `168` / `170`）。
8. **状态栏沉浸两处修正**：启动时状态栏与启动页同色；切到后台任务时状态栏透明、露出壁纸（`docs/170`）。
9. **新品牌标（虎鲸抱环）**：桌面图标、启动页标识、启动窗口图标与 PC 托盘图标全部换新，
   由 `tools/make-icon.py` 从母版一键产出、镜像对逐字节一致（`docs/169`）。

## 6. 产物清单（本轮）

| 件 | 位置 | 读数 |
|---|---|---|
| **AGC 上传件（.app）** | B 侧 `dist/release-test/DSHM-1.1.3-core0.2.1-alpha.4+dshm.56-arm64-release-signed.app` | 228,609,426 B / `eccd28d3…` |
| beta 侧载件 | A 侧 `dist/beta/`（版本号同步升到 1.1.3 后重出） | 见该目录 `README.md` / `SHA256SUMS.txt` |

**B 侧未 commit / 未 push；A 侧同样未 commit / 未 push。**

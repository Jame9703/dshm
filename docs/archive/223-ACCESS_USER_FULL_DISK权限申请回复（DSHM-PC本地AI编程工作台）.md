# ACCESS_USER_FULL_DISK 权限申请回复

> 日期：2026-10-22
>
> 适用应用：DSHM PC 工程 `com.dshm.dshclient`
>
> 申请权限：`ohos.permission.ACCESS_USER_FULL_DISK`
>
> 本文是给 AGC / 权限评审人的申请回复与内部事实底稿。它不代表权限已经获批，
> 也不改变当前源码、Profile 或交付包；获批前不得把该权限写入
> `entry/src/main/module.json5`。

## 1. 结论

本次接受评审意见：`ohos.permission.READ_WRITE_USER_FILE` 已进入日落流程，
DSHM 后续不再申请或依赖该权限，改按评审建议申请
`ohos.permission.ACCESS_USER_FULL_DISK`。

申请定位不是“通用文件管理器读取整台设备”，而是：

> HarmonyOS PC / 2in1 上的本地 AI 编程工作台。用户可以在任意用户目录中
> 打开代码项目，应用内置的 Node Host、Git、ripgrep、Python、shell/PTY
> 需要以真实路径访问并原位修改该项目。

现有 `DocumentViewPicker + FILE_ACCESS_PERSIST` 路线已经接入，但只能覆盖
应用对本次选择 URI/目录的文件 API 访问，不能完整解决以下开发工具语义：

- 任意位置的代码项目必须直接以 POSIX 路径交给本地 Node Host 和子进程；
- 递归检索、批量修改、Git diff、依赖解析和构建要求整棵项目树可遍历；
- Git、Python、ripgrep、shell 等子进程要继承同一工作区路径；
- 历史会话保存的是绝对 cwd，不能要求用户为每个文件、每次重启重新选择；
- 将项目复制进沙箱会破坏原位编辑、Git 状态、符号链接和增量构建语义。

## 2. 应用与权限事实

| 项 | 值 |
|---|---|
| 应用名称 | DSHM |
| Bundle Name | `com.dshm.dshclient` |
| AGC App ID | `6917614360926110054` |
| 当前版本 | `1.1.4 / 1010004` |
| 设备档 | HarmonyOS PC / 2in1 |
| 最低 API | HarmonyOS API 26 |
| 目标 API | API 26 |
| 本次申请 | `ohos.permission.ACCESS_USER_FULL_DISK` |
| 不再申请 | `ohos.permission.READ_WRITE_USER_FILE` |

本地 SDK 的 `PermissionDefinitions.json` 对该权限的定义为：

```text
name             = ohos.permission.ACCESS_USER_FULL_DISK
grantMode        = manual_settings
availableLevel   = system_basic
availableType    = NORMAL
since            = 22
provisionEnable  = true
deviceTypes      = [2in1]
```

其中 `manual_settings` 表示该能力需要用户在系统设置中手动开启，不是安装后
静默自动授予；`deviceTypes=[2in1]` 与本次 PC 开发工具场景一致。

## 3. 可直接提交的回复正文

以下内容可直接发送给评审人，或按需求模板拆分填写。

---

您好，感谢二次评审。我们接受 `READ_WRITE_USER_FILE` 进入日落流程的结论，
后续不再申请或依赖该权限，愿意按建议申请
`ohos.permission.ACCESS_USER_FULL_DISK`。下方按模板补充说明。

### 【应用及申请信息】

- 应用名称：DSHM
- Bundle Name：`com.dshm.dshclient`
- AGC App ID：`6917614360926110054`
- 当前版本：`1.1.4 / 1010004`
- 申请权限：`ohos.permission.ACCESS_USER_FULL_DISK`
- 使用设备：HarmonyOS PC / 2in1
- 权限场景：本地 AI 编程开发工具操作开发者指定的本地代码工作区

### 【原始场景】

DSHM 是运行在 HarmonyOS PC 上的本地 AI 编程工作台，产品定位类似内置 AI
Agent 的 IDE/开发工具。应用内置 Node.js、Git、ripgrep、Python、shell/PTY
等开发工具，用户可以在应用中打开本地代码仓库，让 AI 对项目进行分析、
检索、修改、重构和构建。

典型交互流程如下：

1. 用户启动 DSHM，选择或恢复一个本地代码目录作为工作区。
2. 工作区路径被保存为当前会话的项目根目录，新会话的终端 cwd 也指向该目录。
3. 用户发起编程任务后，AI 根据任务对项目执行递归检索、读取、编辑、新建、
   移动和删除文件，例如 `glob`、`grep`、读取源码、修改源码、处理
   `.gitignore`、`package.json`、配置文件及依赖声明。
4. 用户也可以打开内置终端，在同一个工作区执行 `git status`、`git diff`、
   `rg`、Python 脚本、构建和测试命令。
5. 修改结果必须原位写回用户项目，并能通过 Git 查看差异、继续构建和运行。

问题发生在用户已经选中工作区、开始执行文件工具或终端命令的时候：

- 系统文件夹选择器给应用的是针对所选目录的 URI 授权，主要服务于应用的
  `fileIo` 调用。
- DSHM 的 Agent 文件和命令运行在本地 Node Host 及 Git、Python、ripgrep、
  shell 等子进程中。这些工具直接使用 POSIX 路径和原生文件系统调用，
  需要真实目录路径访问能力，而不仅是单个 URI 句柄。
- 用户项目可能位于当前用户目录下的任意位置，并涉及多级子目录、符号链接、
  相邻配置目录、依赖目录及终端工作目录。逐一选择文件或逐个选择目录无法
  覆盖正常项目工作流。
- 权限不足时，应用层直接读取目录、递归搜索和写入文件会出现 `EPERM`；
  终端子进程设置工作目录时会出现
  `chdir(2) failed.: Permission denied`，导致终端无法启动或无法在当前
  项目中执行命令。
- 已有会话保存的是项目绝对路径。关闭该能力后，用户即使重新打开应用，
  历史工作区和会话目录也可能再次不可访问，只能反复重选目录，已有工作流
  和会话上下文会被破坏。

因此，这不是普通的“多选几个文件”场景，而是开发工具需要对用户选择的代码
目录执行完整、持续、原位且可被子进程继承的路径级读写能力。

### 【影响】

这个问题直接影响 DSHM 在当前 `1.1.4 / 1010004` 正式版中的核心功能验收和
发布。工作区文件浏览、AI 代码修改、终端、Git、Python、搜索和构建都属于
产品主流程，不是边缘功能。

使用频率属于高频核心场景。用户每次打开项目、继续历史会话或发起一个编程
任务时，都会调用工作区文件或命令执行能力，而不是偶尔导入一次文件。

系统提供的 `DocumentViewPicker + FILE_ACCESS_PERSIST` 方案我们已经在产品中
接入并持续验证，但它仍不能完整替代本申请：

- 该方案通常只覆盖用户本次选择的一个目录，无法自然覆盖项目可能需要的
  多个相关根目录和相邻依赖。
- 它主要解决应用自身文件 API 对选中 URI 的访问，不能完整解决本地 Node
  Host、Git、Python、ripgrep、shell 等子进程直接使用 POSIX 路径时的权限
  继承问题。
- 要求用户每处理一个文件都重新选择，或者反复选择多个目录，不符合
  IDE/开发工具的正常交互方式。
- 将用户项目先复制到应用沙箱，再同步回原目录，会破坏原位编辑、Git 工作
  状态、符号链接、增量构建和外部工具路径语义，并带来大文件复制、磁盘占用
  和项目一致性问题。
- 第三方库无法绕过操作系统的文件访问控制。该问题的根因是系统路径授权和
  子进程权限继承，而不是缺少某个普通 SDK 或第三方实现。

如果后续版本才提供该能力，返工量较大：需要调整工作区模型、文件访问后端、
会话路径恢复、终端子进程启动、Git/Python/ripgrep 集成、项目复制和同步
机制，并补充数据迁移和完整回归。这不是修改一个配置开关能够解决的问题，
也不适合在当前发布版本内临时规避。

如果后续系统提供新的、可覆盖用户指定工作区、且能被本地子进程继承的路径
授权方案，我们愿意及时迁移并进行权限收敛。

### 【权限边界和保护措施】

- 该权限只在 PC / 2in1 开发工具场景申请，不用于手机端普通文件管理。
- `ACCESS_USER_FULL_DISK` 为需要用户手动开启的权限，不会静默自动获取；
  用户可以随时在系统设置中关闭。
- DSHM 仅在实际打开项目、继续会话或执行用户发起的任务时访问工作区，
  不会因启动应用就在后台扫描用户全盘文件。
- 对应用内置文件工具、`glob/grep` 和发布写入入口，我们已增加代码级路径
  白名单，仅允许应用沙箱和用户目录；对其他应用沙箱、系统配置区、系统数据区
  和挂载点会直接返回权限错误，防止工具层越界。
- 文件修改和命令执行均发生在用户明确打开的工作区，并显示在会话轨迹和
  终端中。
- 权限获批后，我们可按要求在 2in1 真机上补充验证并提交结果，包括：用户
  目录访问、嵌套代码仓库递归读取和写入、文件新建/修改/移动/删除、
  Git diff、Python/ripgrep 执行、终端 cwd、应用重启后的工作区恢复，以及
  系统目录访问被拒绝等用例。

综上，DSHM 申请 `ACCESS_USER_FULL_DISK` 是为了让本地 AI 编程工具能够在用户
指定的代码工作区内完成与 IDE 等价的文件操作和命令执行，并非为了提供通用
全盘文件浏览功能。若获得批准，我们会在发布 Profile 中增加对应 ACL，完成
重新签名和真机验收后再提交正式版本。

---

## 4. 技术举证

### 4.1 为什么 Picker 只解决一部分问题

Picker 返回的是 URI 及本次选择对应的授权。它能解决 ArkTS `fileIo` 对单个
目录的直接访问，也能通过 `FILE_ACCESS_PERSIST` 恢复已登记目录的授权。

但 DSHM 不是只在一个 ArkTS 页面里查看文件。它的主链路是：

```text
ArkUI 工作区选择
    ↓
Node Host 以绝对路径登记 session cwd
    ↓
AI 文件工具 / Git / Python / ripgrep / PTY 子进程
    ↓
直接在原项目目录读取、修改、重命名、删除和构建
```

URI 授权不能自动变成任意本地子进程都继承的路径授权；用户不重新选择时，
历史会话 cwd 也不能凭存量路径自行恢复。

### 4.2 已实测的失败形态

历史设备实验已经观察到以下同因失败：

```text
读取目录
PermissionError: [Errno 1] Operation not permitted

PTY 子进程切换到项目目录
进程已退出 (1)
chdir(2) failed.: Permission denied
```

失败点不是模型请求，也不是网络调用，而是本地 Host 或子进程开始访问项目
路径时。用户看到的结果是：

- 工作区文件列表为空或无法打开；
- AI 能看到会话，但不能读取或修改项目；
- 内置终端一启动就退出；
- Git、Python、ripgrep、构建和测试命令无法在项目 cwd 执行。

### 4.3 为什么复制到沙箱不是等价替代

| 方案 | 表面可行性 | 实际问题 |
|---|---|---|
| 每次用 Picker 选择文件 | 能取得单文件授权 | 无法支撑递归搜索、批量重构和构建 |
| Picker 选择目录后只走 ArkTS 文件 API | 可浏览和简单读写 | 本地子进程仍需真实路径权限 |
| 复制整个项目到应用沙箱 | 沙箱内可读写 | 破坏原位编辑、Git 状态、符号链接、外部依赖与增量构建 |
| 修改后整体同步回用户目录 | 似乎能保留原项目 | 大项目复制慢、冲突难处理，构建和外部工具看到的是副本 |
| 引入第三方文件库 | 无 | 第三方库不能绕过系统 DAC/沙箱和子进程权限边界 |

### 4.4 当前安全收敛

当前工程不把 `ctx.fs`、`glob/grep` 和 `publish` 暴露成无边界的系统文件
访问器。文件工具面已经实现路径闸门：允许应用沙箱和
`~`，面外的系统目录、其他应用沙箱和挂载点返回
`FS_PERMISSION_DENIED`。

该闸门是产品内部第二道边界，和系统权限不是同一层。申请时不应把“系统权限
覆盖范围”和“产品实际使用范围”混为一谈：系统权限用于让真实 IDE 工作流可用，
产品行为仍限定在用户主动打开的工作区。

## 5. 获批后的执行顺序

权限获批不等于可以直接出包。必须按以下顺序执行：

1. 确认 AGC 正式 App ID `6917614360926110054` 对应应用的
   `allowed-acls` 已加入 `ohos.permission.ACCESS_USER_FULL_DISK`；
2. 重新生成绑定该 App ID 的 release Profile，并在内嵌 Profile 中核对 ACL；
3. 获批后再把权限写入 `entry/src/main/module.json5` 并补充
   `reason`、`usedScene`；
4. 更新权限门禁和发布 Profile 门禁，使源码声明、Profile ACL、包内声明三者
   一致；
5. 构建 2in1 测试包，使用 `hdc install -r` 覆盖安装，禁止卸载和删除 el2
   用户数据；
6. 完成下节验收后，再生成 AGC 正式上传件。

获批前不要提前声明该权限。当前平台会在安装期要求包内每条 ACL 都存在于
Profile 的 `allowed-acls` 中；提前声明会进入 `PERMISSION_ACL_RULE` /
`grant request permissions failed` 拒装路径。

## 6. 获批后的验收项

| 类别 | 验收动作 | 预期 |
|---|---|---|
| 权限状态 | 系统设置手动开启后读取 App 权限状态 | `ACCESS_USER_FULL_DISK` 已授权 |
| 用户目录 | 列出 `~` | 成功，不出现 `EPERM` |
| 嵌套仓库 | 在任意项目根递归执行 `glob`/`grep` | 正确返回子目录文件 |
| 文件修改 | 新建、写入、编辑、移动、删除 | 原位成功 |
| 会话恢复 | 杀进程后重开并继续历史会话 | 原 workspace/cwd 仍可访问 |
| 终端 | 以项目目录为 cwd 创建 PTY | 状态为 running，无 `chdir` 失败 |
| 开发工具 | 执行 `git status/diff`、Python、ripgrep | 在项目 cwd 成功 |
| 安全闸门 | 文件工具访问 `/etc`、`/system`、其他应用沙箱 | `FS_PERMISSION_DENIED` |
| 数据保全 | 记录 el2 home 指纹，覆盖安装前后比对 | 用户数据不变 |

## 7. 提交时的措辞边界

建议保留：

- “PC / 2in1 本地 AI 编程工作台”；
- “用户主动打开的项目工作区”；
- “Node Host 和本地子进程需要路径级访问”；
- “Picker 已接入，但只覆盖选中目录的应用文件 API”；
- “permission is `manual_settings`，需用户在系统设置中开启”；
- “获批后做真机验收，并按新 ACL 重签 Profile”。

不要让评审形成以下误解：

- 不要写成“应用需要读取用户全盘所有内容做上传或分析”；
- 不要写成“只是想少弹几次 Picker”；
- 不要把“系统权限范围”描述成“应用实际会无差别扫描全盘”；
- 不要说第三方库可以绕过该问题；
- 不要在 Profile 尚未放行时提前修改 `module.json5` 出包。

## 8. 相关依据

- `platform/src/main/ets/system/FilePicker.ets`：Picker、目录授权、探写与
  `FILE_ACCESS_PERSIST` 接线；
- `hostcore/profile/ondevice/cordis.patch.yml`：工作区、文件工具、终端和
  subprocess 的端侧组合；
- `hostcore/plugins/dshm-fs-write-nonchmod/lib/fs-fence.js`：文件工具范围闸门；
- `hostcore/plugins/dshm-tool-fs-remove/lib/index.js`：`remove`、`move`、
  `publish` 与本地子进程路径语义；
- `docs/137`：文件访问范围闸门与历史 `EPERM` 证据；
- `docs/144`：撤除用户目录访问后工作区文件与终端同时失效的事故记录；
- `docs/157`：Picker 授权生命周期、重启恢复与历史失败读数；
- `docs/222`：当前 PC 权限、Profile 和设备能力边界。


# DSHM 1.1.8（1010017）审核备注（供 AGC 审核填写）

## 一、应用说明

DSHM 是本地运行的 AI 编程工作台，面向 HarmonyOS PC / 2in1、平板与手机：

- 会话与执行轨迹：多轮对话，并展示每一步工具调用与结果。
- 本地工作区：用户通过系统选择器授权目录后，可浏览、预览、编辑项目文件。
- 内置开发环境：随应用提供终端、Git、ripgrep 与 Python；PC / 2in1 使用系统原生终端，平板与手机通过随包 guest 环境提供 bash。
- 插件扩展与浏览器自动化：按需启用插件，浏览器任务结束后自动收尾。
- 语音输入（可选）：仅用于本次转写，不写入会话记录。
- 云同步（可选）：使用华为账号标识作为同步归属，不保存登录凭据；不开启不影响本地使用。

## 二、测试账号

应用无自有账号体系，**无需注册或登录即可使用全部本地功能**。
AI 能力需用户自行配置模型服务凭据（第三方模型服务地址/密钥），未配置时不影响会话浏览、工作区、插件、终端与设置等功能。

## 三、首次启动与本轮验证重点

- 首次启动需解包随包核心，可能需要数十秒；应用内会显示进度与说明。
- 本轮重点：启动流程并行化（Web 引擎预热与宿主启动重叠、探测粒度加细）、手机 / 平板 guest 终端 `pnpm` 修复、权限用途说明中文化。以上均不改变权限面与数据处理方式。

## 四、权限使用说明（与包内声明一致）

| 权限 | 用途 |
|---|---|
| `ohos.permission.INTERNET` | 连接用户指定的本机/局域网 Host 以收发会话与事件 |
| `ohos.permission.GET_NETWORK_INFO` | 读取网络类型与连通状态，离线时直接降级而非等待超时 |
| `ohos.permission.KEEP_BACKGROUND_RUNNING` | 后台维持与 Host 的长连接，避免错过审批/提问事件 |
| `ohos.permission.RUNNING_LOCK` | 解包核心、启动宿主、安装插件等长任务期间保持 CPU 不休眠 |
| `ohos.permission.PREPARE_APP_TERMINATE` | 自由窗口点关闭时改为退到后台继续执行任务 |
| `ohos.permission.CUSTOM_SANDBOX` | 在动态沙箱执行域运行随包已签名的 git、rg、shell、Python |
| `ohos.permission.ALLOW_EXTERNAL_NATIVE_CODE`、`ohos.permission.kernel.IGNORE_LIBRARY_VALIDATION` | 加载随包携带的原生模块与工具 |
| `ohos.permission.kernel.EXEMPT_ANONYMOUS_EXECUTABLE_MEMORY` | 核心运行时与本地虚拟机的可执行内存 |
| `ohos.permission.ACCESS_USER_FULL_DISK` | **仅 PC / 2in1**：把用户选择的项目目录与随包工具链作为工作区读写（已获审批） |
| 三条目录权限（Desktop / Documents / Download） | 用户授权后把对应公共目录中的项目作为工作区 |
| `ohos.permission.FILE_ACCESS_PERSIST` | 持久化用户授权的目录访问，跨会话可用 |
| `ohos.permission.STORE_PERSISTENT_DATA` | 在沙箱持久区保存核心运行时数据，避免每次重复解包 |
| `ohos.permission.MICROPHONE` | 语音输入录音（用户确认后开始，仅用于转写） |
| `ohos.permission.READ_PASTEBOARD` | 用户主动粘贴时读取剪贴板纯文本 |
| `ohos.permission.VIBRATE` | 复制/粘贴等操作轻触反馈 |

手机端不申请全盘、目录与原生代码相关权限，权限面为 9 条。

## 五、AI 生成内容

应用在会话界面展示「内容由 AI 生成」标识（仅会话输入框上方），其他页面不显示。已按平台要求声明 AI 生成（文本生成）。

## 六、建议验证路径

1. PC / 2in1：冷启动 → 选择工作区 → 终端执行命令 → 插件安装 → 浏览器任务收尾。
2. 平板：侧栏入口与布局 → guest 终端 → `pnpm -v`。
3. 手机：冷启动 → 工作区选择 → 语音输入 → 可选云同步。

## 七、其他

- 隐私政策：https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=2068131051053539008
- 应用不采集与业务无关的个人信息；不上传用户会话内容到自有服务器（模型请求由用户自行配置的服务处理）。
- 联系邮箱：1185128119@qq.com

# 生产逻辑测试契约

> 后续批准：子代理可先实施ETS，专用check_ets_files由父会话首次full build前执行；下文早期接口缺失不再是实现前阻塞，仍不得报告静态通过。

## 基线与范围

- 当前实跑 `dist/acceptance/fix-review-dual-release/before.txt`：113条，0失败。
- 当前CI补充 `before-ci.txt`：22条，退出码均0。补充脚本的已知集合引用旧固定113条，因此与当前113条有重复（例如CoT），不得将135解释为135个唯一门禁。
- 原门禁绿并不反证本轮11个候选不存在；修复必须另测真实生产函数，不把原门禁覆盖夸大为问题复现。

## 测试入口

生产JS由真实模块或提取真实函数体、注入边界依赖执行。ArkTS只允许从真实源码做可审计的类型擦除后执行生产函数；不得另写同构算法作为被测实现。系统API mock仅替代平台边界，记录调用顺序、参数及故障注入；不将mock当ROM实测。

安全fixture限本次唯一拥有目录，或内存FS/worker/数据库。禁止真实账号云写入、用户profile包替换、真机数据操作；独立临时对象的清理仅依据本次拥有权。新门禁应提供 `--self-test`，在内存中变异生产源码或依赖，逐个证实应失败而失败；报告正常用例和变异用例分别计数。

## 候选验收矩阵

| ID | 正常路径及必须反证的失败路径 |
|---|---|
| DR1 | 预存固定同名文件字节不变；成功；mkdir/open/write/close失败；授权短路；创建目录失败仅表示未确认 |
| E01 | name+版本、scoped、npm alias、Git来源往返；默认保留本机不同版本 |
| B01 | 失败→成功→一次release归零；并发失败；取消晚到成功；caller held/generation；PC持有不变 |
| E04 | 每个await前后代次/身份/root隔离；runner文件/数据库/请求提交及UI完成回调；旧finally不能解新锁；相同root重复attach不淘汰 |
| E02 | 已有非空映射后新增目录；零候选和未映射必须区分；未知目录不写；两桥/原生/云client反馈 |
| D01 | 真实manager remove→install→recover；普通卸载不复活；新版下载/验证/落位/enable失败；新旧双失败本地保旧；失败remove不覆盖最初备份；tmp原错误 |
| E03 | 暂存SHA失败拒绝；目标等SHA幂等；同长异内容冲突不覆盖；缺SHA拒绝；不附加未知官方格式限制 |
| E05 | demo/SKILL.md与demo_SKILL.md；同unit多快照；hash/size从同一不可变副本；登记后不盲删 |
| C01 | greeting、QMP close/error/end不等于exit；捕获原worker；重复stop；8秒超时未确认；Host10秒不变 |
| FR1 | 同长异内容；旧/缺/坏stamp（包括缺stamp跨尺寸）；只有成功commit认证；profile数据保护 |
| CR2 | dispose统计可求值；Cordis逐项异常隔离不变 |

## API及官方依据

- 本轮已尝试 `devecocli docs search mkdtempSync --format json`，因better-sqlite3本地绑定缺失失败；没有有效documentId，因此不伪造docs read。不修全局CLI。
- DR1应复读当前SDK `@ohos.file.fs.d.ts` 的mkdtempSync/OpenMode，禁止猜EXCL/native值。
- 已直接复读当前SDK的mkdtempSync声明：返回唯一目录，API since 9。此为SDK声明证据，不是ROM测试。内容检索也定位到CREATE/TRUNC枚举，无公开EXCL枚举证据。
- Asset消费时点未知：采用不可变路径，不宣称insert已复制文件。
- 官方manager的previous恢复、防重复、会话格式及Cordis隔离以当前work源码及随包一致性为准；必要官方diff必须记录本地扩展为何不足。
- 修改ETS前加载语法skill；修改后需要实际 `check_ets_files` 检查；若当前工具接口不提供该能力须记录阻塞，不能把0 files或普通文本检查当通过。C++同理。
- 当前子代理工具接口没有 `check_ets_files` / `check_cpp_files`。探测 `devecocli check --help` 仅提供lint；实际运行 `devecocli check lint platform/src/main/ets/system/FilePicker.ets --format json` 返回 `Files checked: 0`。此结果明确不算通过。T004之前需由父代理提供可实际检查ETS的接口，不应擅用应用build替代（本阶段禁止）。

## 后续回归

T017与当前before逐命令比较，CI补充及新行为/变异分开记。核心/插件修改后先pack物化再核源/zip/resfile/OSS。应用构建、签名应用包及部署仅属后续验证阶段。本契约建立不表示矩阵已经执行。

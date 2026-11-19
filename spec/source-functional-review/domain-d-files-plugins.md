# D 文件、工作区及插件（T006）

## 深读范围与入口

FilePicker `20–446`、FolderGrants `100–248`、FilePreview 全文；两壳目录桥选取片段（entry `3470–3574`，phone `3190–3269`）。实际 workspaceFiles `lib/index.js:30–274,470–624`，list有workspace confine，文件read允许外部路径为当前显式契约，不能只因read未限制在cwd就报越权。

插件：`dshm-installer.js:1–1088,1110–1194,1300–1729`（输出截断后的未读中间区不当全文）；tar-gz `70–260`；market-bridge `290–489`；profile-pnpm `110–479`；main队列 `8830–8887`。随资源 installer `1415–1444`复查一致。安装失败由main写.fail，桥消费者读ok/.fail，不能说所有失败都吞掉。

## D-01：升级先删可用旧包，下载/校验失败无恢复（P1 确认缺陷）

`hostcore/app/dshm-installer.js:1385–1435`：已装版本与请求版本漂移，即使 userRowLoadable为空（可用），也在1418 rm旧dest；之后才await下载1421、校验1428、gunzip1434。任何网络失败/完整性不符/坏gzip会从1306–1311返回失败，旧目录已无，未暂存备份或回滚。main `8838–8858`只回执失败，不能重建旧包。影响所有端经设置/市场升级已装用户插件；预期失败保留原可用版本，实际原包先被移除，profile依赖登记仍指向旧包，后续启动/加载受影响。最坏程度依插件用途而变，不夸大为所有App必崩。

反证：市场prefetch可能提前下载，有缓存也不能覆盖直接profile安装及下载失败；loadable保护只对 !drifted有效；落位校验失败“回滚”只是删新目录1540–1543，没有旧目录恢复。顶层installSpec catch只包错误。

同链附属错误：1429–1431在const tmp声明1435之前引用tmp，完整性失败会以TDZ ReferenceError遮盖校验原因；随资源相同行。它仍失败，不说成完整性绕过。建议下载/验包/stage完成后事务换包，失败保旧，并修正错误分支清理对象。

## D-R1：固定名探写会破坏同名用户文件（P1 风险，待官方API核验）

`FilePicker.ets:162,385–418` 固定 dshm-write-probe.tmp，CREATE|READ_WRITE|TRUNC后unlink；entry可达3554–3555（非handheld且persist失败），phone自身非handheld路径也可达。若用户目录已有同名文件，预期不动原数据，实际存在截断/删除风险。persist=true短路会避开探写，因此并非每次选目录都会触发。官方文档检索失败，本轮不把TRUNC具体API运行语义当已官方核验事实。建议独占随机临时名/不覆盖已有项；仅列方向。

## 未覆盖/不主张

未深审removeSpec全部、fs-local所有读写删、workspaceRegistry、安装命令解析全文、网络及市场远端、预览代理取文件链。tar路径拒绝..与绝对路径、跳过link已读；manifest.name与monorepo子路径的额外边界疑点未形成完整反证链，不列确认安全漏洞。

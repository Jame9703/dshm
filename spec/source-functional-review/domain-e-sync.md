# E 账号与云同步（T007）

## 阅读/调用链

深读 SyncEngine 全文、ImportRunner全文、SyncPlanner全文、UploadRunner `100–275`、SyncStore `65–374`、PluginManifest `30–220`、PluginRestore `90–236`、SyncActions全文、SyncState `70–141`；HuaweiCloud `170–318`、SessionSyncScope `140–299`、CloudSyncSettings `390–855`、phone WebApp `3967–4162`；云插件index全文、client动作/开关/恢复 `190–254,550–664`。entry桥仅相关定位，不把它余下千行全部计为深读。

设置分区client→cloudSyncAction→decideCloudAction→SyncEngine→runner/store；上传规划读取当前session目录；导入则SQL发现→映射→runImport。System RDB云隔离由平台控制，不能把UnionID未出现在SQL直接定性跨华为账号数据泄漏。

## E-01 插件恢复将版本号当包名（P1 确认缺陷）

生产：`PluginManifest.ets:109,134–157` 保存 {name, spec: dependencies[name]}，如foo→^1.2.3；消费：`PluginRestore.ets:173–177`仅把s.spec投installOne→req:114–123；main→installer.resolveSpec:590–631把请求当完整包标识。因此npm用户插件恢复请求是`^1.2.3`而非`foo@^1.2.3`，会查错包/失败；精确版本同理。预期恢复原包，实际丢失包名。所有端云插件恢复受影响。

反证：GitHub spec本身含完整仓库，能成立，不泛化为所有插件恢复失败；r.name=s.name仅修改结果显示，发生在投递之后不修请求；toInstallPayload保存name也未被消费组合。建议按spec类型重建完整安装请求，保留别名语义。

## E-02 新设备不同路径的工作区被静默过滤（P1 确认缺陷）

`SyncEngine.ets:433–435,458–477`仅从本地sessions已有 --…-- 目录生成hash映射；`SyncPlanner:66–75` ID来自本地路径编码hash；`ImportRunner:143–159`远端ws不在mapped直接continue。新设备无会话目录或路径不同→候选空→runImport `200–204,377–388`“0项可用”且ok=true，UI报拉取并导入完成。没有公开映射设置方法/UI可把远端ID映到本地。预期用户可建立目标或获明确未映射反馈，实际零项成功并不可恢复该工作区。

反证：两设备路径编码相同且本地已有该工作区可导入；不是所有导入失败。安全拒绝未知映射合理，缺陷是没有建立映射通路且无未导入反馈。建议发现阶段保留未映射项并提供确认映射，不猜路径。

## E-03 导入不校验摘要/格式且同尺寸即判相同（P1 风险；校验缺失为确认事实）

`ImportRunner.ets:240–267`仅检查sha字符串形态和size；`273–288`已有目标同尺寸就skip；`309–315,331–363`新文件只复验size及能读64字节，未计算sha、解压或核验session header。上传确实计算sha（UploadRunner:135–168），消费者没有使用值。

触发：候选资产同长度内容错误/不同，或本地同长度但不同内容。预期完整性/冲突识别，实际可成功导入不可读/不相符内容或隐藏冲突。反证：大小不同会拒绝，已有目标不主动覆盖，不能说静态证明覆盖了活跃会话；平台Asset是否已保证具体摘要不可证明，所以损坏到达条件列风险。建议摘要与格式核验，已有目标比较摘要，不用size冒充同内容。

## E-04 退出不取消在途任务，旧任务可回写退出后的状态（P2 确认缺陷；云归属风险不定性）

`SyncActions:91–94`允许busy时signout；client `561`退出按钮不禁用；WebApp `3988–3990`调用SyncEngine.signOut。`SyncEngine:271–281`只清登录/显示/开关，任务 `351–377,421–447`没有epoch/signal或await后的身份检查。退出后原runner仍继续写数据/云调用并在结束重新写lastSync/cloudOk，和已退出状态矛盾。原生面板745同样可在busy退出。

反证：syncNow入口检查enabled/unionId防止新任务，不能取消已越过入口的任务；UI某些按钮busy禁用不包括退出。没有证据证明系统华为账号同时切换或跨账号上传，不报确认泄漏。建议任务代次/取消/退出等待与隔离，回调按代次丢弃。

## E-05 上传资产名不是单元唯一（P1 风险）

`SyncPlanner:259–270`路径a/b与a_b可生成相同assetName；`SyncStore:207–215`再安全化/截断并直接删除同名目标，`UploadRunner:146–176`把路径存入不同unit。skill和attachment都用global且资产共用同一目录，跨kind同相对名也碰撞。预期每unit自己的字节，实际后项覆盖前项payload所指文件；其sha仍为前项值。反证：unitId含kind/rel不会冲突，但Asset路径不含unitId；云平台是否即时复制可缓解具体上云表现，不能抹掉本地同路径覆盖。建议内容寻址或unit唯一资产路径。

## 其他边界

- pull发现SQL只kind=session（ImportRunner150–152）；附件/技能有上传，无本轮读到的正式导入通路。未把“云端已有”说成“完整恢复”。
- runCloudSync仅固定等待后看lastCode=0，未要求最终schedule（315–333）；官方API检索不可用，列待独立核验，不主张确定谎报成功。
- 插件清单在runUpload完成云同步后才upsert（SyncEngine359,505–563）；autoSync=true可能最终上传，不报永不上传。
- 账号资料late callback未按unionId隔离（WebApp4080–4083、面板431–434）；并入E-04异步隔离方向，不另凑一条。
- 未深读云插件ScopeList、全部远端合并语义、账号API前段、云控制台配置或私有数据库；没有真云请求。

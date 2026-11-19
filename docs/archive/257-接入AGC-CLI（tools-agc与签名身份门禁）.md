# 257 · 接入 AGC CLI

> 日期：2026-10-25
>
> 范围：把华为 AppGallery Connect 的 CLI 接进本仓库，提供**唯一入口**
> `tools/agc.mjs` 与门禁 `tools/check-agc-wiring.mjs`。
> 只读命令已实测可用；**未做**任何写操作（未上传、未发布、未建/改证书与 profile）。

## 1. 现状：CLI 在哪、能不能用

CLI 来自继承的 Codex 技能（`docs/256`），本仓路径：

```text
.dsh/skills/hmos-connect-api-cli-skill/scripts/connect-api-cli.js   # v1.1.4，375 KB，与上游 sha256 逐字节一致
```

实测（2026-10-25）：

| 项 | 读数 |
|---|---|
| `--version` | `1.1.4` |
| 登录态 | `Auth mode: oauth`、`Client ID: 117427577`、`Team ID: 260086000057314119`、`Token cached: yes` |
| token 缓存 | `$HOME/.connect-api-cli-token.json`（含 `accessToken` / `refreshToken` / `expiresAt`，**权限 0600**） |
| token 实际到期 | `expiresAt=1792893390642` → 2026-10-25 09:56:30（北京时间） |

## 2. 接入时踩到的第一件事：CLI 按 **cwd** 读 `.env`

这是本次接线的**根因**，也是 `tools/agc.mjs` 存在的理由。

复现（实测）：

```bash
# 在仓库根 —— 成功
$ cd ~/data/DSHM-deveco-workspace
$ node .dsh/skills/.../connect-api-cli.js publish app-id -p com.dshm.dshclient
{ "ret": { "code": 0 }, "appids": [{ "key": "DSHM", "value": "6917614360926110054" }] }

# 换到 /tmp —— 直接报缺凭证
$ cd /tmp
$ node /…/connect-api-cli.js publish app-id -p com.dshm.dshclient
Request failed: Missing AGC credentials. Please set AGC_CLIENT_ID and AGC_CLIENT_SECRET environment variables.
```

关键点：**token 缓存与 cwd 无关**（在 `$HOME`），凭证/模式却只从 cwd 的 `.env` 或已导出的环境变量来。
所以"报缺凭证"和"没登录"是两件事，混为一谈就会去重新登录（而 oauth 登录要人工开浏览器）。

验证假设：

```bash
$ cd /tmp && AGC_AUTH_MODE=oauth node /…/connect-api-cli.js publish app-id -p com.dshm.dshclient
{ "ret": { "code": 0 }, "appids": [ … ] }      # ← 只要环境里有 AGC_AUTH_MODE 就通了
```

**接法**：`tools/agc.mjs` 固定 `cwd = 仓库根`，环境变量原样透传。于是从任何目录跑都一样。

## 3. 第二件事：`auth status` 的 `Expires in` 会误导

我第一轮看到：

```text
Token cached: yes
Expires in: 0m 0s
```

据此在 `docs/256` 里写了"token 已过期上，403 是过期导致"。**这是错的**，已在 `docs/256` 与技能里改正。
实际上当时 `expiresAt` 距现在还有 **3438 秒（57 分钟）**，`Expires in: 0m 0s` 只是 CLI 的显示问题。

⇒ `tools/agc.mjs status` 现在**直接读缓存文件的 `expiresAt`**，给出权威到期时刻与剩余分钟，
不再只信 `Expires in`。

## 4. 第三件事：403 不是过期，是**接口级无权限**

token 新鲜（剩 57 分钟）时逐条实测：

| 命令 | 结果 |
|---|---|
| `publish app-id -p com.dshm.dshclient` | **成功** → `6917614360926110054` |
| `provision cert-list` | **成功** → 4 张证书 |
| `provision profile-list -a 6917614360926110054` | **成功** → 8 条 profile |
| `project list` | **403** |

⇒ 403 是"该 API 客户端对 `project` 这个接口无权限"，不是登录失效。
`references/troubleshooting.md` 的原话就是这个意思（"token 有效，但该 API 客户端对此应用/团队无权限"）。
**重试无意义**；要权限就去 AGC 控制台调客户端权限，或换有权限的账号。

`tools/agc.mjs` 把这三类失败（`Missing AGC credentials` / `401` / `403`）**分开报**，
不让人再走我走过的弯路。

## 5. 第四件事（最重要）：**文件名 ≠ AGC 上的 profile 名**

我第一版在这里判断**反了**，如实记录：

- 仓里 `build-profile.json5` 的 release 指向 `.certs/multihap-20261024/DSHM-multihap-release-20261024-newacl.p7b`；
- AGC 的 profile 列表里**没有**任何叫 `*-newacl` 的条目 ⇒ 我一度写"仓里配的这份不在 AGC 上"；
- 实际：逐条把 AGC 上 4 条 `type=2` release **下载回来算 sha256**，结果是——

| 本地文件 | sha256（前 16） | AGC 上对应的 profile 名 |
|---|---|---|
| `DSHM-multihap-release-20261024-newacl.p7b` | `18a9a3da0fd0735e` | **`dshm_three`** |
| `DSHM-multihap-release-20261024.p7b` | `ee4a510bba8ede80` | `DSHM-multihap-release-20261024` |
| —（无本地件） | `f9cbab73e35b4f8a` | `DSHMpc` |
| —（无本地件） | `d3477b86ba335fd5` | `dshm` |

**两个本地文件各对应 AGC 上一条，都合法**；只是磁盘文件名和 AGC 上的名字对不上。
⇒ **判据只能是字节（sha256），不是名字**。这条已做成门禁 L2 的判据。

> 顺带纠正 `docs/256` 里一句错话（说 403 是过期）。技能里的说明本轮已同步改对。

## 6. 接线产物

### 6.1 `tools/agc.mjs` —— 唯一入口

```bash
node tools/agc.mjs status      # 登录态 + 缓存 token 的真实到期时刻
node tools/agc.mjs app-id      # 用 AppScope/app.json5 的 bundleName 查 App ID
node tools/agc.mjs profiles    # 本应用 profile 列表（标出 0 ACL 的危险条目）
node tools/agc.mjs certs       # 证书列表
node tools/agc.mjs raw <...>   # 原样透传（仍固定 cwd=仓库根）
```

设计要点：

- **cwd 固定仓库根**（本封装存在的理由）；
- **包名从 `AppScope/app.json5` 读**，不写死（配置是唯一事实源）；
- **字段名按实测**：profile 列表是 `provisionList` / `provisionName`，**不是** `profileList`
  （我第一次按 `profileList` 汇总，静默得到"0 条"，差点又误判）；
- 失败分三类给可行动的话；
- **不写凭证、不打印 token**；写操作不封装，必须显式发起。

### 6.2 `tools/check-agc-wiring.mjs` —— 门禁

两层，默认只跑离线层：

| 层 | 判据 | 需要 |
|---|---|---|
| **L1 离线**（默认，进 CI） | 包名 == `com.dshm.dshclient`；release profile 文件存在且可解析；`type=release`；`bundle-name` / `app-identifier` 对得上；`allowed-acls` 与 AGENTS.md 的 7 条一致（缺失判红、表外判 warn）；未过期 | 什么都不需要 |
| **L2 联网**（`--online`） | AGC App ID == `6917614360926110054`；8 条 profile 无 0 ACL；**下载 AGC 上的 release profile 算 sha256，与本仓那份逐字节比对** | 登录态 |

L2 在未登录 / 403 时按 **exit 3（环境不具备）** 退出，**绝不报成通过** —— 这是本仓既有口径
（"CI 绿"不等于"全绿"，见 `AGENTS.md`）。

自检 13 条全过（`--self-test`），其中 4 条专钉 P7B 解析器：
能从二进制里夹出 provision、嵌套花括号能配平、截断 JSON 返回 null、无 JSON 返回 null。

## 7. 实测读数（本轮）

```text
$ node tools/agc.mjs status
Auth mode: oauth / Client ID: 117427577 / Team ID: 260086000057314119
Token cached: yes / Auto-refresh: enabled
token 实际有效至 2026/10/25 09:56:30（还剩 54 分钟）
登录态可用（是否真有权限取决于具体 API，见 403 说明）

$ node tools/agc.mjs app-id
bundleName: com.dshm.dshclient
App ID: 6917614360926110054  （DSHM）

$ node tools/agc.mjs profiles
# App 6917614360926110054 的 profile（共 8 条）
  DSHM-prod-1.1.6-1010007-specified-device-20261024  release(指定设备)  ACL=7  设备=4  到期=2027/4/24
  dshm_three                                         release           ACL=7  设备=0  到期=2029/10/12
  DSHM-multihap-debug-pc-phone-20261024              debug             ACL=7  设备=2  到期=2027/6/20
  DSHM-multihap-debug-20261024                       debug             ACL=7  设备=1  到期=2027/6/20
  DSHM-multihap-release-20261024                     release           ACL=7  设备=0  到期=2029/10/12
  DSHM-PC-debug-20DB409A-20261021                    debug             ACL=3  设备=1  到期=2027/10/21
  DSHMpc                                             release           ACL=3  设备=0  到期=2029/10/12
  dshm                                               release           ACL=2  设备=0  到期=2029/10/12

$ node tools/agc.mjs certs
# 证书（共 4 张）
  xiaobai-debug                        到期=2027/6/20
  hokit_debug                          到期=2027/10/1
  dshm                                 到期=2029/10/12
  auto_debug_260086000057314119.cer    到期=2027/10/21
```

与仓内签名链对照：`build-profile.json5` 的 debug 用 `xiaobai-debug` 证书 + `DSHM-multihap-debug-pc-phone-20261024`；
release 用 `dshm` 证书 + `newacl`（= AGC `dshm_three`）。**都在 AGC 上真实存在**。

## 8. 红线与未做

**没做**（都需要你明确发起）：

- 未上传任何包、未提交审核、未发布；
- 未创建/删除证书、未创建/修改/删除 profile、未加设备；
- 未 `auth logout` / `auth login`（会中断当前可用登录态，且 oauth 需人工浏览器授权）；
- 未写任何凭证文件。

**红线**（写进 `tools/agc.mjs` 头注与 `.dsh/skills/README.md`）：

- 凭证只在 `.env`（已在 `.gitignore`），**绝不入库、绝不打印**；
- 本封装只封装只读命令；写操作必须显式发起并逐条确认；
- 真机装机仍只走 `node tools/update-device.mjs`（`hdc install -r`，禁止卸载）——
  AGC CLI 的 `hdc` 相关子命令**不替代**它。

## 9. 后续怎么用

| 场景 | 命令 |
|---|---|
| 发版前确认签名身份没串 | `node tools/check-agc-wiring.mjs --online` |
| 看登录还剩多久 | `node tools/agc.mjs status` |
| 确认包名 → App ID | `node tools/agc.mjs app-id` |
| 查/profile 是否 0 ACL | `node tools/agc.mjs profiles` |
| 需要某个 CLI 子命令 | `node tools/agc.mjs raw <子命令> …` |
| 上架前审元数据 | 技能 `app-metadata-audit-skill`（`docs/256`） |

未决：`project list` 恒 403。若以后要用 `app-create`（需要 projectId）就得先解决客户端权限；
目前所有只读核对都走 `publish` / `provision` 两条，不受影响。

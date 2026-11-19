# 256 · 继承 Codex 的鸿蒙开发技能与知识库

> 日期：2026-10-25
>
> 范围：把原 Codex 开发端的鸿蒙专属技能与文档知识库**继承进本仓库**，
> 使后续在 DSH 内的开发可以直接调用。**不动应用功能、不动签名物料、不动真机数据。**

## 1. 先找到：Codex 那边到底有什么

技能根 `~/.codex/skills/` 下共 8 个目录，其中**鸿蒙相关 3 个**、其余 5 个是通用内置件
（`imagegen` / `openai-docs` / `review-agent` / `skill-creator` / `skill-installer`，与鸿蒙无关，不继承）。

| 技能 | 文件数 | 大小 | 职责 |
|---|---:|---:|---|
| `harmonyos-docs-kb` | 1 | 8 KB | 指向本地**离线文档知识库**（13,002 篇华为官方 Markdown） |
| `hmos-connect-api-cli-skill` | 12 | 506 KB | 内嵌 `connect-api-cli.js`（375 KB，v1.1.4）操作 AGC：登录、上传 APP、证书/Profile、真机 hdc |
| `app-metadata-audit-skill` | 2 | 16 KB | 上架前元数据（名称/描述/隐私链接）合规预审 |

**知识库本体**另有位置：`~/data/HarmonyOS-KB`

- 正文 **13,002 篇 / 116 MB**（27 个大类），目录 1.05 GB（含 `node_modules` 与目录树 JSON）
- 检索工具 `tools/search.mjs`（依赖 `rg`，本机 `~/.harmonybrew/bin/rg` = ripgrep 15.2.0）
- 更新工具 `tools/enumerate.mjs` / `tools/fetch-docs.mjs`
- 它**本来就在仓库之外**，自己也这么写（`<KB>/README.md`："不要往仓库里拷"）

## 2. 落在哪：DSH 的技能根

查了 DSH 自己的发现逻辑（`@deepseek-ai/dsh-skill-filesystem` 的 `roots()`），它按 rank 从小到大扫：

| rank | 路径 | source |
|---:|---|---|
| 100 | `<项目根>/.dsh/skills/` | `project-dsh` |
| 200 | `<项目根>/.agents/skills/` | `project-agents` |
| 300 | 自定义目录 | `custom` |
| 400 | `~/.dsh/skills/` | `user-dsh` |
| 500 | `~/.agents/skills/` | `user-agents` |
| 600 | 内置 bundled | `bundled` |

按用户 2026-10-25 的决定：**落在仓库内 `.dsh/skills/`**（rank 100，随 git 走，换机/新会话自动就有），
**知识库本体不拷**，技能里只引外部路径。理由见 `.dsh/skills/harmonyos-docs-kb/SOURCE.md`。

## 3. 落地结果

```text
.dsh/skills/
├── README.md                          # 技能根说明：发现顺序 / SKILL.md 判据 / 三个技能的边界
├── harmonyos-docs-kb/
│   ├── SKILL.md                       # 重写（见 §4）
│   └── SOURCE.md                       # 新增
├── hmos-connect-api-cli-skill/
│   ├── SKILL.md                       # 上游原文 + 顶部「环境适配」块
│   ├── SOURCE.md                       # 补继承记录
│   ├── references/{commands,troubleshooting,workflows}.md   # 原样
│   ├── scripts/connect-api-cli.js      # 原样（sha256 与上游逐字节一致）
│   └── test-cases/*.md                 # 原样
└── app-metadata-audit-skill/
    ├── SKILL.md                       # 上游原文 + 顶部「环境适配」块
    └── SOURCE.md                       # 补继承记录
```

不写进 `.gitignore`（`git check-ignore` 实测未命中）⇒ `.dsh/` 会随仓库入库。

## 4. 继承时修掉的三个真问题（不是美化）

### 4.1 `harmonyos-docs-kb` 的 frontmatter 坏了 ⇒ 技能被**静默丢弃**

原文第 3 行是 ` description: …`（**行首多一个空格**）。YAML 里这就从顶层键变成了 `name` 的子键，
而 DSH 的 `parseSkillFile()` 明确要求**顶层**有 `name` 与 `description`：

```js
const name = stringField(parsed.data, "name");
const description = stringField(parsed.data, "description");
if (name === void 0 || description === void 0) {
    ctx.logger.warn(`skill file ${path} ignored: frontmatter requires name and description`);
    return;
}
```

⇒ 只 `warn`、不报错，技能目录还在，但技能列表里**根本没有它**。

**这是怎么发现的**：先把三个目录拷进来，接着技能目录只刷出了 `app-metadata-audit-skill` 与
`hmos-connect-api-cli-skill` 两个，`harmonyos-docs-kb` 缺席。查 frontmatter 才看到那个空格。
改顶格后立即出现 —— 说明"拷贝完成"不等于"继承成功"，**必须看技能目录里有没有它**。

### 4.2 知识库路径少一级 ⇒ 所有命令 ENOENT

原文写 `/storage/Users/current/data/HarmonyOS-KB`，实测是
`~/data/HarmonyOS-KB`（少 `User`）。已按实测改写。

### 4.3 全是 PowerShell 命令 ⇒ 本机一条都跑不了

三个技能都从 Windows 继承，原文的检索命令是 `powershell` 代码块、`Get-Content`、
`$env:USERPROFILE`。本机没有 PowerShell（`docs/255` 已因此删掉 11 个 `.ps1`）。
处理方式按"上游原文可核对"这个前提分两种：

- `harmonyos-docs-kb`：**整篇重写**（它只有 1 个文件、64 行，改写成本低，且路径本来就错）；
- 另两个：**保留上游原文**，在 `SKILL.md` 顶部加「⚠️ 本副本的环境适配」表格，
  逐条给出本机替换写法（PowerShell→bash、`C:\`→`/`、`$env:VAR`→`$VAR`、
  `encrypt-pwd` 的 `--config-dir`、`DEVECO_HOME` 已知值）。
  好处：`scripts/connect-api-cli.js` 的 sha256 仍与上游 `C92DCB2E…` 逐字节一致，
  日后比对上游只需看那一个文件。

## 5. 可用性实测（继承不是"放进去就算"，逐条跑过）

| 项 | 读数 | 判定 |
|---|---|---|
| 三个 `SKILL.md` 是否符合 DSH 判据 | 用复刻判据的脚本逐个校验：`name` kebab-case、顶层 `name`+`description`、name 与目录一致 | **3/3 通过** |
| DSH 技能目录是否识别 | 会话内技能列表出现全部三个 | **3/3 出现** |
| `docs-kb` 能否检索 | `search.mjs "FontWeight" --alias references` → 命中 156 篇，首条为 `Class (TextMenuController)`，附目录路径与官方 URL | **可用** |
| `docs-kb` 大类别命中 | `search.mjs "分布式软总线"` → 命中 4 篇（含 `capabilities/distributed-fs-overview.md`） | **可用** |
| AGC CLI 版本 | `--version` → `1.1.4` | **可用** |
| AGC CLI 与上游一致性 | `sha256sum scripts/connect-api-cli.js` → `c92dcb2e…` = 上游记录值 | **逐字节一致** |
| AGC 登录态 | `auth status` → `Auth mode: oauth`、`Client ID: 117427577`、`Team ID: 260086000057314119`、`Token cached: yes` | **已登录且 token 有效**（见下方校正） |
| AGC 真实请求（只读） | `publish app-id` ✅、`provision cert-list` ✅、`provision profile-list` ✅、`project list` ❌ 403 | **接口级无权限**，不是过期（见下方校正） |

### 5.1 403 的定性 —— **本条原先写错了，已校正**

第一版这里写的是"`Expires in: 0m 0s` ⇒ token 已过期 ⇒ 需重新登录"。**这是错的**，
`docs/257` 接入 AGC CLI 时查清了：

1. `Expires in: 0m 0s` 只是 CLI 的**显示问题**。直接读 `$HOME/.connect-api-cli-token.json`
   的 `expiresAt`，当时距现在还有 **3438 秒（57 分钟）** —— token 是新鲜的。
2. 403 与过期无关：同一时刻 `publish app-id`、`provision cert-list`、`provision profile-list`
   **全部成功**，只有 `project list` 回 403 ⇒ 是**接口级无权限**。
3. `references/troubleshooting.md` 原本就写着 403 = "token 有效，但该 API 客户端对此应用/团队无权限"，
   我第一版把它读成了过期。

⇒ 纠正后的口径：**401 才是登录失效**（要 `auth logout && auth login`）；
**403 是权限问题，重试无意义**，去 AGC 控制台调 API 客户端权限或换账号。
本机当前登录态**可用**，日常只读核对走 `tools/agc.mjs`（`docs/257`）。

**仍未做**：没有跑 `auth logout` / `auth login`（会中断当前可用登录态，且 oauth 需人工浏览器授权），
也没有改用 `.env` 的 `AGC_CLIENT_ID/SECRET`（本仓 `.env` 是 oauth 模式、没填密钥）。

## 6. 后续怎么用（正常调用）

技能在会话里是**自动可发现**的，按意图触发即可：

| 场景 | 触发的技能 |
|---|---|
| "查一下 `Navigation` 的官方 API 签名" / "这个权限官方怎么说的" | `harmonyos-docs-kb` |
| "上传 APP 到 AGC" / "查 App ID" / "cert-list / profile-list" / "邀请测试" | `hmos-connect-api-cli-skill`（先登录） |
| "上架前审一下我填的元数据" | `app-metadata-audit-skill` |
| "跑一遍门禁" | **不是技能**，是 `tools/check-*.mjs`（清单见 `AGENTS.md`） |

也可以主动加载：`skill` 工具 + 技能名。

### 边界（写在 `.dsh/skills/README.md` 里，也是纪律）

- **技能不是门禁**：判代码/配置对不对，跑 `tools/check-*.mjs`；技能只给知识与方法。
- **技能不改包**：装机仍只走 `node tools/update-device.mjs`（全程 `hdc install -r`，禁止卸载）；
  构建仍走 `node "$DEVECO_HOME/hvigor/bin/hvigorw.js" assembleApp ...`。
- **权威顺序**：本仓实测（`docs/` + 门禁）> 官方文档知识库 > 技能里的上游说明。
  三者冲突时以本仓为准，并把差异登记在技能里（已在两个技能顶部这么做）。

## 7. 未做 / 待办

1. **AGC 登录未执行**（需要你在浏览器点授权）。要用 AGC 功能前先跑一次 `auth login`。
2. **知识库未刷新**。它最后一次抓取是 2026-10-20（`catalog/docs.jsonl` 13,002 篇）。
   要更新就 `enumerate.mjs` + `fetch-docs.mjs`，之后把 `docs-kb/SKILL.md` 里的篇数一起改。
3. **未提交**：`.dsh/` 目前是 untracked（`git status` 显示 `?? .dsh/`）。
4. **另外 5 个 Codex 内置技能未继承**（`imagegen` / `openai-docs` / `review-agent` /
   `skill-creator` / `skill-installer`）：与鸿蒙开发无关，且属 Codex 生态专用，按需再议。

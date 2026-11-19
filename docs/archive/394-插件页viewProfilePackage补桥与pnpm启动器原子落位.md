# 394-插件页真正的 spawn 点（viewProfilePackage）补齐 + pnpm 启动器原子落位

- 日期：2026-11-07
- 输入：`2026-11-07 19_44_38.log`、手机端「添加插件」报错截图
- 状态：**已落地**（core 补丁 + Host 启动器落位 + 门禁 + AGC 包）

---

## 1. 上一轮为什么没修好：补丁打偏了函数

截图报错的命令是：

```
pnpm view dsh-plugin-whale-pet name version description dsh --json '--config.fetch-retries=0'
```

`name version description dsh` 这组字段来自 **`inspect()`**：

```
inspect() → askRegistries(spec, ['name','version','description','dsh'], …)
          → viewProfilePackage(dir, spec, { fields, registry, … })
          → execa('pnpm', ['view', spec, ...fields, '--json', …])
```

而上一轮注入的是 **`namedSpecManifest()`**（安装前兼容性预检，参数是
`name version engines peerDependencies`）——两个不同函数。所以补丁在包里，UI 这条路径一次都没走到它。

## 2. 真正的 spawn 点（两处，此前都没有桥）

| 文件 | 位置 |
| --- | --- |
| `dsh-plugin-manager/lib/index.js` | `viewProfilePackage()` |
| `lib/types/operations.js` | `viewProfilePackage()` |

## 3. 改动

### A. 给 `viewProfilePackage()` 注入进程内桥（两处）

在两处 `const result = await execa(...)` 之前插入：

```js
{
  const dshmBridge = await import("@deepseek-ai/dshm-profile-pnpm");
  const dshmViewed = await dshmBridge.bridgeViewProfilePackage(dir, spec, options, process.env);
  if (dshmViewed !== undefined) return dshmViewed;
}
```

- 返回形状与 execa 分支一致（`exitCode/stdout/stderr/timedOut`）；
- 桥内部先判 `bridgeEnabled()`：PC/2in1 能真跑 pnpm ⇒ 返回 `undefined` ⇒ 继续 execa，**PC 零变化**；
- 失败时给出 registry 侧的中文原因，不再是裸 `spawn pnpm EACCES`。

同时修掉 `patchPluginManagerInspectBridge()` 的"整段跳过"缺陷：旧判据只要 `lib/index.js`
有标记就 `return`，新站点永远注入不进去（`operations` 的 view 桥、本轮的 `viewProfilePackage`
都是被它挡掉的）。现在**逐站点按 tag 判重**。

### B. 让 `bin/pnpm` 真正可执行

1. **原子落位**：`installElfLaunchers` 不再直接覆盖目标，改为
   写 `bin/.<name>.new`（新 inode）→ `chmod 755` → 校验 `X_OK` + ELF 魔数 →
   `renameSync` 覆盖 → 再校验。任一失败才退回"删除重铺"。
   针对的是 hmfs 上"曾布置过的文件进入封存态：覆盖写与 chmod 都被拒"这一真机现象
   （`docs/110` 的原始证据）——它会让盘上一直留着 `#!/system/bin/sh` 的假壳，spawn 必 EACCES。
2. **可观测**：启动后对 `node/npm/npx/pnpm/dsh` 再扫一遍，写一行
   `CLI launcher: pnpm=ELF-ok`（或 `ELF-noexec` / `script-stale`）到 Host 诊断文件。
   以后再看 EACCES，先看这一行即可定位是"没落位"还是"落位了但 exec 被拒"。
3. **解释器兜底**：CLI 假壳首行不再写死 `#!/system/bin/sh`，改成
   `#!<binDir>/ash`（busybox 的 ash 副本，与 bash 垫片同一份）——在 ash 可执行的档位
   （平板 / PC），即使 ELF 没落位，`pnpm view` 也能直接跑起来。

### C. 门禁

`check-core-openharmony-patches` 新增：

- 两个 `viewProfilePackage()` 必须各有 `DSHM_PLUGIN_MANAGER_BRIDGE:view-profile*` 标记与桥调用；
- `lib/index.js` 的标记计数由 3 调整为 4（view / viewProfilePackage / registry / git）。

### 施工注意：Host 代码的唯一真源是 `hostcore/app/main.js`

`build-agc` 的 `placed: main.js` 会把 `hostcore/app/main.js` **覆盖**到
`hostruntime/src/main/resources/resfile/resources/app/main.js`。本轮第一次改错了副本
（改了 resfile 那份），构建后新代码被原样盖掉、包内一个符号都没有 —— 已在最终包里核对纠正。
以后改 Host 一律只改 `hostcore/app/main.js`。

## 4. 不影响面

- `nodecli` 二进制与其 `argv[0]` 分派逻辑**未改**，只改落盘方式；
- `node/npm/npx/dsh` 与 pnpm 用同一份字节，行为一致；
- PC/2in1 的 pnpm 真身路径不变（桥返回 undefined）；
- 包体不变（未新增资源），权限面、`deviceTypes`、core 版本号都没动
  （核心容器大小变了 127 B，端侧的 `.dshm-bundled-stamp` 会判定"容器已更换"并重解包）。

## 5. 验收

| 项 | 判据 |
| --- | --- |
| 插件页 | 输入 `dsh-plugin-whale-pet` 能读到包信息；失败也应是中文原因 |
| pnpm 本体 | `pnpm -v` → `9.15.9` |
| 启动器 | Host 诊断出现 `CLI launcher: pnpm=ELF-ok` |
| 其他 | `node -v` / `npm -v` / `dsh --version` 正常；PC 档不变 |

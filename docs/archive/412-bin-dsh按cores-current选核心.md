# 412 bin/dsh 按 cores/.current 选核心

**问题**：`bin/dsh` 用 `"$_cores"` 下的 glob 展开取「最后一个」当作最新核心。glob 按**字符序**排序，`0.2.2-rc.1+dshm.10` 排在 `+dshm.9` **之前** ⇒ 一旦升到 dshm.10，壳会静默选中旧核心。另外兜底路径无条件写死 `haps/entry/...`，phone 档会指到另一档的目录。

**改动**

1. `hostcore/app/main.js` 新增 `publishCurrentCore()`：每次启动把**实际在跑的核心目录名**（`path.basename(CORE_DIR)`）原子写到 `$DSH_BASE/cores/.current`；值不变则跳过写；失败只记 diag，不阻塞启动。
2. `bin/dsh` 壳改为**先读 `.current`**（`read` 是 shell 内建，不依赖端侧缺失的 `ls`/`sort`/`awk`），路径存在且 `lib/bin.js` 在才采用；读不到再退回原有 glob 循环 —— 旧版宿主没写过 `.current` 时行为与旧版一致。
3. 兜底目录按档位推导：`$_sb` 含 `haps/phone` 时先试 phone 档，其余先试 entry 档，再交叉试另一个。

**结果**：升级到 `+dshm.10` 后壳仍指向当前核心；phone 档不再指向 entry 档目录。

**门禁**：`tools/check-dsh-cli-current-core.mjs` —— 除文本断言外**真跑一次**：造两个名字满足「字典序与版本序相反」的核心目录（`+dshm.9` / `+dshm.10`），`.current` 指向 `+dshm.10` 时必须选中 `+dshm.10`；删掉 `.current` 时必须退回选中 `+dshm.9`（证明兜底没被误删）。4 个变异体必须判红。

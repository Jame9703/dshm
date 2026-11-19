# 交接单：<主题>

- **ID**：JD-00X
- **提交方**：WorkBuddy
- **日期**：YYYY-MM-DD HH:MM
- **状态**：待编译

## 1. 变更摘要

（一两句话说明这次做了什么、为什么。）

## 2. 涉及文件（真实路径）

- `path/to/file1`
- `path/to/file2`

## 3. 验证命令与结果

```sh
# 命令
node tools/<gate>.mjs
# 结果：rc=0 / PASS（附关键输出一行）
```

## 4. 边界（做了什么 / 没做什么）

- 做了：
- 没做：

## 5. 请 DevEco 做的事

1. 编译：`devecocli build`（必要时 `--product phone`）
2. 测试：<具体命令 / 真机步骤>
3. 复核：<关注点>
4. 结论写到 `from-deveco/<YYYYMMDD>-<slug>-result.md` 并更新 `STATUS.md`。

## 6. 红线遵守声明

未 `git commit`；未 `hdc uninstall`；未删 `signing/**` `.certs/**` `dist/**` 交付件；未自行升版本号。

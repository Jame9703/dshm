# 219 · 对话失败修复（`libsystem.so` 缺件与 Python native 环境）

> 日期：2026-10-21 ｜ 工程：`com.dshm.dshclient` ｜ 设备：鸿蒙 PC `MNTXM-24B`

## 1. 现象

发送对话后本轮直接失败：

```text
Error loading shared library
/data/storage/el2/base/haps/entry/files/dsh/cores/0.2.1-rc.2+dshm.78/
node_modules/@deepseek-ai/node-addon-system-linux-arm64/bin/musl/system.node:
No such file or directory
```

同时启动日志里 Python 桥加载成功但自检失败：

```text
python 桥：worker 已加载 bridge=true ready=false initialized=false
python 桥自检失败：error=DSHM_PYTHON_LIB 未设置
```

## 2. 根因

### 2.1 会话所需 flock addon

core 树里的 `bin/musl/system.node` 是占位文件，`.node` 加载钩子会把它重定向到
HAP 的 `libs/arm64-v8a/libsystem.so`。但 debug CMake 缓存是在
`dist/core/work` 还不存在时生成的，配置阶段的 glob 没有识别到
`node-addon-system/src/flock.c`，因此 debug HAP 没有构建和打入
`libsystem.so`。占位文件存在，但重定向目标不存在，会话持久化加载 flock
时本轮直接失败。

### 2.2 Python native 环境

`python-worker.cjs` 在线程内部设置 `process.env.DSHM_PYTHON_LIB/HOME`。
worker 的 `process.env` 是 JS 环境副本，不能可靠同步到进程的 native
`environ`；`libpython_runner.so` 的 `EnsurePythonInit()` 用 `getenv()`
读取时仍为空。

### 2.3 核心补丁门禁缺归属件

core zip 裁剪时删掉了
`dshm-ptc-runtime-inproc/lib/vendor/babel-standalone/PROVENANCE.md`。
它不是业务依赖，但属于必须保留的归属证明。

## 3. 修复

- 触发 debug CMake 重新 configure，并确认生成
  `libs/arm64-v8a/libsystem.so`。
- `check-native-closure` 新增必需运行库断言：
  `libdshhost.so`、`libkoffi.so`、`libnode.so.137`、`libpty.so`、
  `libsystem.so` 缺一即红。
- `getPyWorkerBridge()` 在**主线程创建 worker 之前**设置
  `DSHM_PYTHON_LIB` / `DSHM_PYTHON_HOME`，保证 native `getenv()` 可见。
- `check-python-async-worker` 与 `assert-python-bridge` 新增上述顺序断言。
- core 裁剪豁免表加入 `provenance`，并补回缺失的 `PROVENANCE.md`。

## 4. 验证

- debug HAP 构建成功，包内确认存在：

```text
libs/arm64-v8a/libsystem.so
```

- `check-native-closure`：61 个库，依赖闭合，`RESULT: PASS`
- `check-core-openharmony-patches`：244 passed / 0 failed
- `check-python-async-worker`：39/0
- `assert-python-bridge`：70 项全过
- Python 桥启动自检：

```text
python 桥自检通过：print(1+1)=2（844ms），内嵌 CPython 可用（执行线程=worker）
python=ok(bridge=true，stdlib=true)
```

- Python HTTP 实际执行 `print(6*7)`：

```text
{"ok":true,"stdout":"42\n","stderr":"","rc":"None"}
```

- 对话端到端：`session/prompt` 被接受，`turn/end reason=completed`，
  助手回复 `OK`，会话事件中无 shared-library 错误。

## 5. 产物

| 产物 | sha256 |
|---|---|
| `entry-default-signed.hap` | `3cc36549a7e543202141ca5a86cca47d1b6d0cc6306d6447153adc092abd7b76` |
| `dsh-core-0.2.1-rc.2+dshm.78-openharmony-arm64.zip` | `d765b00bd5856e33871341d1bf51e0a16949b43374592f0e8b634eb042bbba6e` |

测试只做了覆盖安装和 `aa force-stop` 进程重启；没有卸载应用，也没有修改
el2 用户数据。

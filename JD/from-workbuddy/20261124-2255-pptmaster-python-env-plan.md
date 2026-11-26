# JD-042 让 DSHM 像 WorkBuddy 一样「clone 下来就能跑 ppt-master」——环境补齐方案

- 提交方：WorkBuddy
- 接收方：DevEco / 端侧环境负责人
- 时间：2026-11-24 22:55
- 目标：`git clone ppt-master` 后，`python3 skills/ppt-master/scripts/svg_to_pptx.py ...` 直接可用

---

## 1. 为什么 WorkBuddy 能跑、DSHM 不能

| 项 | WorkBuddy（本会话） | DSHM 端侧 |
|---|---|---|
| Python | 3.12.9（Electron 随包） | 3.12.14（`toolchain/python/cpython-3.12.14-aarch64-musl.tar.gz`） |
| site-packages | 能读 `~/.local/lib/python3.12/site-packages`，**pptx/lxml/PIL/yaml/openpyxl/requests/bs4/mammoth/fitz/uharfbuzz/pathops/edge-tts/flask 全都在** | 只有 pip/setuptools，**没有第三方包** |
| HOME | `~`（用户目录） | 应用沙盒（看不到用户级 site-packages） |
| pip 网络 | 可用（此前装过 edge-tts） | 直连 PyPI **4 分钟无响应**（实测），且无 certifi/代理配置 |
| 扩展后缀 | `-linux-ohos` | `-linux-musl`（`sysconfig.get_config_var('EXT_SUFFIX')`） |

**关键结论**：不能把 WorkBuddy 的 `~/.local` 包直接拷给 DSHM——两者 ABI 后缀不同（ohos vs musl），必须用 **musllinux_1_2_aarch64** 轮子。

已验证：随包 Python 本体可跑（需 `LD_LIBRARY_PATH=$P/lib`），`pip 24.3.1` 在包内；但 `pip install lxml` 在端侧因网络卡死，不可作为主路径。

---

## 2. 目标拆解

`ppt-master` 的「clone 即跑」需要同时满足：

1. `python3` / `pip3` 在 bash PATH 里（DSHM 已有 wrapper，见 `main.js` 的 `name === 'python'/'pip3'`）；
2. `site-packages` 内有：`python-pptx、lxml、Pillow、PyYAML、openpyxl、requests、beautifulsoup4、mammoth、PyMuPDF、uharfbuzz、skia-pathops、edge-tts、XlsxWriter`；
3. `numpy` 可用（当前缺 `libopenblas.so.0`；brew 有 `openblas 0.3.34`）；
4. 字体：`/system/fonts` 已含 194 个 CJK 字体，够用；
5. 外部程序：
   - `git` 已有（DSHM 自带）；
   - `LibreOffice` / `pandoc` 仅部分格式需要，可不带；
   - `Chromium/Playwright` 仅 visual review，端侧不做；
   - 视频导出必须 **Windows PowerPoint**（官方硬约束），端侧只交付 PPTX。

---

## 3. 方案对比

| 方案 | 做法 | 优点 | 缺点 | 结论 |
|---|---|---|---|---|
| **A. 离线 site-packages 包** | 构建期下载 musllinux 轮子，打成 `dshm-pysite.tar.gz`；首次启动解包到 `$DSHM_HOME/python-site`，注入 `PYTHONPATH` | 不依赖端侧网络；版本可复现；手机桥模式也能用 | 体积 +25~40MB（压缩）、解包 +80~120MB | **推荐** |
| B. 端侧在线 pip | 首次 `pip install -r requirements.txt` | 不增包体 | 端侧 PyPI 不通/极慢；版本漂移；无 certifi | 不可行（实测） |
| C. guest VM 跑 | Alpine 装 py3-* 包 | 隔离 | TCI 慢 5–20 倍；QEMU 内存紧张 | 仅备选 |

---

## 4. 方案 A 落地步骤

### 4.1 构建期：生成 musllinux wheelhouse（在网络好的机器）

```bash
python3 -m pip download -d wheelhouse \
  --only-binary=:all: \
  --platform musllinux_1_2_aarch64 --python-version 3.12 --implementation cp \
  python-pptx lxml Pillow PyYAML openpyxl requests beautifulsoup4 \
  mammoth PyMuPDF uharfbuzz skia-pathops edge-tts XlsxWriter
```

- `numpy`：需要 OpenBLAS；两个选择
  1. 选带 `numpy.libs/libopenblas*.so` 的 wheel（manylinux 版通常自带），或
  2. 用 brew `openblas 0.3.34` 的 `libopenblas.so.0` 一并打包。
- 可选（按需）：`curl_cffi`（微信抓取）、`flask`（SVG 编辑器）、`google-genai`（AI 配图）。

### 4.2 打包成端侧资源

- 产物：`hostruntime/src/main/resources/resfile/toolchain/python/dshm-pysite.tar.gz`
- 内容：`site-packages/{pptx,lxml,PIL,...}` + `wheelhouse/*.whl`（给用户后续 `pip install` 离线用）
- 预估压缩后 **25–40MB**。

### 4.3 运行时：解包 + 注入

在 `hostcore/app/main.js` 里 Python 解包流程（`PYTHON_TARBALL_REL` 之后）追加：

1. 解 `dshm-pysite.tar.gz` → `$DSHM_HOME/python-site`（幂等：按包内 `manifest.json` 的版本标记判断是否重解）；
2. `python` / `python3` wrapper 增加：
   ```sh
   export PYTHONPATH="$DSHM_HOME/python-site:$P/lib/python3.12/site-packages"
   ```
3. `pip3` wrapper 增加离线源：
   ```sh
   export PIP_NO_INDEX=1
   export PIP_FIND_LINKS="$DSHM_HOME/python-site/wheelhouse"
   ```
4. `python-worker.cjs` / `python-bridge-async.cjs` 的 `pyEnv` 同步 `PYTHONPATH`（桥模式也要能看到包）。
5. 加一个启动自检（只记日志，不阻断）：`python3 -c "import pptx,lxml,PIL,yaml"`，失败时在 `host-ready.json` 的 `natives` 里置 `python-pptmaster:false` 并给原因。

### 4.4 字体

- 不需要额外安装；`/system/fonts` 已够。
- `ppt-master` 若走 LibreOffice wasm，沿用 JD-041 的 `office-kit.fontDirectories: ['/system/fonts']`。

---

## 5. 改动清单（预估）

| 文件 | 改动 |
|---|---|
| `tools/fetch-python-wheels.mjs`（新增） | 构建期下载/校验 musllinux wheelhouse，生成 `manifest.json` |
| `hostruntime/src/main/resources/resfile/toolchain/python/dshm-pysite.tar.gz`（新增产物） | site-packages + wheelhouse |
| `hostcore/app/main.js` | 解包 pysite；python/pip wrapper 注入 `PYTHONPATH`、`PIP_NO_INDEX/PIP_FIND_LINKS`；启动自检 |
| `hostcore/app/python-worker.cjs` / `python-bridge-async.cjs` | `pyEnv` 注入 `PYTHONPATH` |
| `tools/pack-core.mjs` / `place-toolchain.mjs` | 把 pysite 纳入打包清单与体积校验 |
| `tools/check-pptmaster-env.mjs`（新增门禁） | `import` 全部依赖 + `svg_to_pptx.py --help` + 最小 SVG→PPTX |
| `docs/` 一篇 | 端侧 Python 扩展包说明（版本、来源、如何加包） |

---

## 6. 体积与性能

- HAP：压缩后 +25~40MB；解包后 +80~120MB（沙盒）。
- 启动：解包只在首启或版本变化时做；用流式解包 + 标记文件，避免每次启动 IO。
- 内存：python 进程按需加载，生成 13 页 PPTX 实测在本机约 1–2 分钟（WorkBuddy 侧）。

---

## 7. 验证清单

**P0（能跑起来）**
1. `python3 -c "import pptx,lxml,PIL,yaml,openpyxl,requests,bs4,mammoth,fitz,uharfbuzz,pathops,edge_tts"` 全过；
2. `python3 skills/ppt-master/scripts/svg_to_pptx.py --help` 正常；
3. `git clone` 一个 ppt-master 到工作区后可直接执行。

**P1（跑通生成）**
4. 3 页样例：`svg_quality_checker.py --quick-generate` + `svg_to_pptx.py --quick-generate` 产出 pptx；
5. 13 页真实项目重跑一次（含模板/图片）；
6. 逐页旁白：`notes_to_audio.py`（edge-tts 需外网；失败只影响 audio）。

**P2（可选）**
7. PDF/Word 源转换（PyMuPDF/mammoth）；
8. visual review 暂不做；视频导出仍在桌面 PowerPoint。

---

## 8. 风险与回退

- **musllinux wheel 在 OHOS 的兼容性**：lxml/Pillow/numpy 有 C 扩展，需实测；不兼容时改用 OHOS 专用轮子或源码交叉编译。
- **numpy/OpenBLAS**：必须一起带，否则 `import numpy` 直接失败（当前就是缺 `libopenblas.so.0`）。
- **体积**：若不可接受，退方案 B（桌面生成）或只带 `python-pptx + lxml + Pillow + yaml` 的最小集（约 30MB 未压缩）。
- **回退**：pysite 包是独立资源，删掉即回到「只有标准库」的现状，不影响其它功能。


---

## 9. 实施结果（2026-11-24 23:05，PC 环境已落地）

### 9.1 已改代码

| 文件 | 改动 |
|---|---|
| `hostcore/app/main.js` | `python3` 包装器：`LD_LIBRARY_PATH=$P/lib` + `PYTHONPATH=$PY_SITE` + 枚举 `*.libs`；`pip3` 包装器：镜像源、musllinux 平台参数、`--only-binary --target`、`constraints.txt`、装完自动 `selfsign.js` 签名 |
| `main.js` 解包收尾 | 把 `toolchain/python/selfsign.js` 投放到 `$P/selfsign.js` |
| `hostruntime/.../toolchain/python/selfsign.js` | 新增（自签名工具随包） |
| `hostruntime/.../toolchain/python/constraints.txt` | 新增，锁定 `Pillow==10.4.0` |
| `tools/check-python-env.mjs` | 新增门禁（14 项） |

### 9.2 端侧实测（用随包 CPython 3.12.14 musl）

| 项 | 结果 |
|---|---|
| `pip3 install lxml` | 从阿里云拉 `lxml-6.1.3-cp312-musllinux_1_2_aarch64` → 自动签名 → `import lxml.etree` OK |
| `pip3 install python-pptx Pillow PyYAML openpyxl` | OK；`import pptx/PIL/yaml/openpyxl` OK |
| `pip3 install numpy` | `numpy 2.5.5` 可导入（wheel 自带 OpenBLAS） |
| `svg_to_pptx.py --quick-generate` | **成功产出 pptx（12,895 B）**，postflight `passed-with-warnings` |
| 门禁 | `check-python-env` 14/0；`assert-resfile-sync` 27 件一致 |

### 9.3 两个必须记住的端侧约束

1. **Pillow 必须钉 10.4.0**：13.x 的 musllinux 轮子自带 `libtiff-*.so`，与 `lxml/pptx` 同进程加载会报 `libtiff... not found`；10.4.0 实测共存。
2. **pip 必须显式平台参数**：随包 CPython 的 tag 是 `harmonyos_hongmeng_kernel_..._aarch64`，pip 默认匹配不到 PyPI 的 `musllinux` 轮子，只会去编 sdist。

### 9.4 仍未覆盖

- 手机上若 Python 走**桥模式（不能 exec）**，`pip3` 的安装流程不可用；需要在真机确认是否能 exec，不能则仅支持「预置包」。
- visual review（Chromium）、视频导出（Windows PowerPoint）仍不在端侧范围内。
- `edge-tts`、`skia-pathops`、`uharfbuzz` 未逐一实测；按同一 pip 口径应可安装，失败会明确报错。

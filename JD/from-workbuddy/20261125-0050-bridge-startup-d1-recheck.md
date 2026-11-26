# JD-045 Python 桥对照、启动提速与 D1 复判

- 提交方：WorkBuddy
- 接收方：DevEco
- 时间：2026-11-25 00:50
- 依据：《DSHM-诊断报告-v2-开发端-2026-11-25》
- 关联：JD-043（Python 环境）、JD-044（编译单）

---

## 1. WorkBuddy 的 Python 是怎么做的（对照）

拆 `app.asar`（`main/ohos-main-bootstrap.cjs` → `main/index.js`）得到的事实：

- **没有 in-process 桥**：它的 Python 是**托管运行时**（`python.tar.gz`，`3.13.12`），
  解到受管目录后按需 `spawn` 子进程；Node 侧只是启动器。
- 运行时资产与 node 一样走 `managed: true` + `verifyPath: bin/python3`，即**文件存在即可用**，
  不涉及 `dlopen` 嵌入。
- 因此它天然绕开「ELF 加载策略」问题——所有 Python 代码都在**独立进程**里跑。

DSHM 的形态不同，且其实**两种都有**：

| 通道 | 实现 | 适用 |
|---|---|---|
| 进程内桥 | `python-bridge-async.cjs` + `python-worker.cjs` + `libpython_runner.so`（dlopen libpython） | 手持档不能 exec 时 |
| exec 直跑 | `bin/python3` 包装器：能 exec 就 `exec $P/bin/python3.12` | PC / 能 exec 的设备 |

结论：不需要照搬 WorkBuddy 的托管 Python；DSHM 的桥 + exec 双通道是对的，
**只缺「可加载的 .so」**（见 §3）。

---

## 2. WorkBuddy 的启动顺序（可借鉴的部分）

从 `main/index.js` 的 `startupLog('Phase: ...')` 还原：

```
setAppUserModelId → 配置 app/GPU 降级 → 预注册 IPC/深链
→ early preflight → 单实例锁 → await app.whenReady()
→ PAC 代理预热（不 await，fire-and-forget）
→ prewarmMainChunks（不 await）
→ await onReady()（bootstrapMainProcess）
→ 建主窗口（可与 bootstrap 并行）
→ 迁移/migrationDone（窗口之后再 await）
→ STARTUP COMPLETE
```

可借的三条：

1. **窗口优先**：重活不挡窗口；
2. **预热 fire-and-forget**：代理、chunk 都不 await；
3. **迁移后置**：等窗口稳定后再做耗时迁移。

### 已落到 DSHM 的改动

`hostcore/app/main.js`：

| 改动 | 说明 |
|---|---|
| 工具链解包改为 `startupWork.request('toolchain', …)` | READY 之后静默 3 s 再解 26 MB Python + 25 MB extras，不再与 BOOT_40→50 的核心树装载抢 IO |
| 解包完成后 `ensurePythonBridge()` 补挂 | 因为 `startupWork` 的 python 任务可能因 `pythonReady=false` 被跳过 |
| `startupWork.activity()` | 解包结束后通知调度器重新进入 idle，继续跑后面的低优先级任务 |

稳态启动（已有解包产物）本来就不解包，**这条只影响首启/升级后第一次启动**。
首启期间 `python3`/`bash` 可能短暂报「稍后重试」，解包完成后自动恢复。

验证方式：对比首启日志里 `BOOT_50_DSH_INIT` 与 `工具链：进程内解包完成` 的先后；
现在应当是 **BOOT_50 在前**（此前解包与核心装载交错）。

---

## 3. D1 复判：真正的判据是 `.codesign`，不是「谁编的」

v2 报告的实验矩阵里：

| 样本 | 来源 | 结果 |
|---|---|---|
| `libtcl9tk9.0.so` / `libpython3.so` | OH 工具链（**构建时已签名**） | 可加载 |
| 同文件复制到 py-site | OH 构建 | 可加载 |
| `_speedups…linux-musl.so`（MarkupSafe） | PyPI wheel（**未签名**） | Permission denied |
| `objectify…linux-musl.so`（lxml） | PyPI wheel（**未签名**） | Permission denied |

报告把变量归为「构建工具链」，但矩阵里 **OH 产物都带 `.codesign`，PyPI wheel 都不带**，
这两个变量没有分离。我们在本机做的对照把签名这一维隔离出来了：

1. 未签名 musllinux `lxml` → `Permission denied`；
2. 同一文件 `selfsign.js --force` 补 `.codesign` → `import lxml.etree` **成功**；
3. `numpy 2.5.5` 的 musllinux wheel（含 `libopenblas`）签名后也可导入；
4. 路径、`libc.musl-aarch64.so.1` 依赖都不是障碍（加载器能解析）。

所以结论修正为：**PyPI wheel 的 ELF 可以加载，前提是补 `.codesign`**。
这正是 JD-043 已经在做的：pip 安装后自动签名 + 手机预设包预签名。

### 下轮验证时请按这个顺序确认

```bash
# 1) 预设里的 .so 是否带签名
python3 - <<'PY'
import subprocess,glob
for p in glob.glob('/data/storage/el2/base/haps/entry/files/py-site/lxml/*.so'):
    out=subprocess.run(['grep','-c','.codesign',p],capture_output=True,text=True)
    print(p, out.stdout.strip() or 0)
PY

# 2) 直接 import
python3 -c "import lxml.etree as e; print('lxml', e.LXML_VERSION)"
python3 -c "import pptx; print('pptx', pptx.__version__)"
```

若仍报 `Permission denied`，请把该 `.so` 的 `readelf -S | grep codesign` 与 `readelf -d` 一起回传，
即可判定是「未签名」还是「其它策略」。

---

## 4. v2 报告其余项状态

| ID | 状态 | 说明 |
|---|---|---|
| D2a 字体 | 已修 | 报错已从 `No usable fonts` 变为引擎错误 |
| D2b 转换引擎 | 上游限制 | wasm LibreOffice；需错误透出，非本仓可修 |
| D3 浏览器桥 | 未动 | 依赖外部扩展与内核截图能力 |
| D4 内存 | 未动 | 系统级；本轮未增加常驻（预设只在首启解包，之后不占） |
| D5 dsh-pet | 未动 | 安装器校验与插件分支属后续 |
| D8 ppt-master | 依赖 D1 | D1 修复后应可直接 `svg_to_pptx.py` |

---

## 5. 门禁

`tools/check-python-env.mjs` 扩到 **18 项**：

- 新增「工具链解包延后到 READY 之后」
- 新增「解包后补挂 Python 桥」

本地：**18 passed / 0 failed**；`assert-resfile-sync` 27 件一致。

---

## 6. 下轮测试建议

1. 首启日志：`BOOT_50` 应早于 `工具链：进程内解包完成`（启动顺序改动生效）；
2. `python3 -c "import lxml,etree"` / `import pptx`（预设 + 签名）；
3. `pip3 install <带 .so 的包>` 后再 import（在线安装 + 自动签名）；
4. 若 D1 仍失败，按 §3 的 `readelf` 取证。

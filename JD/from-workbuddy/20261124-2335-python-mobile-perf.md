# 端侧 Python 环境手机性能测试（2 核近似）

- 时间：2026-11-24 23:35
- 方法：用 `taskset 3` 把进程限制在 **2 个 CPU 核**，模拟手机档（比本机 20 核更保守）
- 环境：随包 CPython 3.12.14（musl）+ `py-site`（pptx 1.0.2 / Pillow 10.4 / lxml 6.1.3 / numpy 2.5.5 / PyYAML / openpyxl）
- 对象：ppt-master 的 `svg_to_pptx.py`

## 结果

| 项目 | 2 核实测 | 说明 |
|---|---|---|
| 冷启动 `import pptx,PIL,lxml,yaml,openpyxl,numpy` | **0.95 s** | 单进程一次导入 |
| 13 页项目 `--quick-generate` | **26.6 s**（带采样约 35.8 s） | 含 13 张 SVG、图片、postflight |
| 1 页项目 `--quick-generate` | **17–22 s** | 固定开销约 15 s（字体/后处理），不是合成本身 |
| 内存峰值（13 页） | **85 MiB** | 远低于手机可用内存 |
| Node 启动（签名用） | 0.08 s | |
| 单 `.so` 签名 | 0.13 s | 一个包 20 个 `.so` ≈ 2.6 s |
| `pip install lxml` | 下载约 11 s（423 KB/s）+ 安装/签名约 2 s | 受网络影响最大 |

## 结论

- **手机端可接入**：13 页 30 s 左右、85 MiB，属于可接受范围；瓶颈是固定 ~15 s 的字体/后处理，不是合成本身。
- **pip 安装是网络瓶颈**：包体下载占大头；镜像已固定阿里云，弱网下建议先装常用包。
- **签名开销可接受**：0.13 s/文件，只在安装时发生。
- 仍有一个前置条件：手机端 Python 必须能 **exec**；若走桥模式，`pip3` 不可用，只能预置包。

## 可选优化（不急）

1. 固定 15 s 开销来自字体扫描/postflight；可在端侧限制 `fontDirectories` 或跳过 visual postflight，缩短到 5 s 内。
2. 批量签名：把 selfsign 改成一次进程处理多个文件，可把 20 文件从 2.6 s 降到 0.3 s。

## 复现

```bash
SITE=$DSHM_SANDBOX_HOME/py-site
P=<python 前缀>
LD="$P/lib"; for d in "$SITE"/*.libs; do [ -d "$d" ] && LD="$LD:$d"; done
time taskset 3 env PYTHONPATH="$SITE" LD_LIBRARY_PATH="$LD" PYTHONHOME="$P" \
  "$P/bin/python3.12" -s skills/ppt-master/scripts/svg_to_pptx.py <project> --quick-generate -o out.pptx
```

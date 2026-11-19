#!/usr/bin/env python3
"""
从用户给的品牌源件生成**图标母版** `third_party/brand-source/foreground-1024.png`。

────────────────── 为什么单独一个脚本（2026-10-30）──────────────────
`tools/make-icon.py` 只管"从母版出 12 件物料"，母版本身是**手工放置的素材**
（`third_party/` 不入库）。可这次源件是**白底位图**（`Desktop/logo.png`），
从"白底图"到"透明底母版"这一步有两个必须做对的地方，写死在人手里迟早出错：

  ① **只抠背景白，不抠设计里的浅色面**
     「鲸鸿」标的鲸身内侧有一大块**浅蓝**（原画的高光面）。若按"离白有多远"
     一刀切（旧实现），这块浅色会被当成背景挖成透明 —— 在白底上肉眼看不出来，
     一放到启动页 / 深色桌面上立刻是一个洞。
     ⇒ 判据：像素**每个通道都 ≥ `NEAR_WHITE`** 才算背景白；且只从**画布四边**
       泛洪（flood fill）到连通的背景，设计内部的白色细节（若有）不受影响。

  ② **几何口径与上一代一致**
     墨迹（alpha>128）紧包围盒的最长边 = 画布 73.9%，居中放置。
     这条口径决定了后续 APP 图标 / 启动画面 / 托盘的 `RATIO` 常数，
     换标时**不要改它**（`tools/make-icon.py` 的自检就是按它判的）。

用法：
    python3 tools/make-brand-master.py                      # 用默认源件
    python3 tools/make-brand-master.py --src <logo.png>     # 指定源件
"""
import os
import sys
from collections import deque

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(HERE, 'lib'))

import tinypng as T  # noqa: E402

try:
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')
except Exception:
    pass

SRC_DIR = os.path.join(ROOT, 'third_party', 'brand-source')
DEFAULT_SRC = os.path.join(SRC_DIR, 'jinghong-1254-source.png')
OUT_FG = os.path.join(SRC_DIR, 'foreground-1024.png')

CANVAS = 1024
MASTER_LONG_RATIO = 0.739   # 墨迹最长边占画布（与上一代同一几何口径）
NEAR_WHITE = 248            # 每个通道都 ≥ 它 才算"背景白"（253/254 的白底稳过，浅蓝面不会）
EDGE_ALPHA = 24             # 抠白后 alpha ≤ 它 视为"背景"，泛洪不越过


def _flood(w, h, rgba, seeds, bg, inner_white):
    """
    从 `seeds` 出发，把"背景白"标记进 `bg`（1=背景）。

    【第二档：设计内部的封闭白】环内 / 鲸身与环之间那些**四边泛洪进不去**的纯白
    同样是原画留白（环是"穿过"鲸身的，环圈住的白不是背景的一部分）。
    它们与背景的区别是：**四邻全是白色**。⇒ 纯白像素里，凡是四邻也全是纯白的，
    标成 `inner_white`（合成时不透明、颜色纯白）；剩下的（贴着彩色边缘的）才是抗锯齿过渡，
    照常按"离白距离"给 alpha，于是边缘依旧是平滑的。
    """
    q = deque(seeds)
    while q:
        x, y = q.popleft()
        if x < 0 or y < 0 or x >= w or y >= h:
            continue
        i = y * w + x
        if bg[i]:
            continue
        r, g, b = rgba[i * 4], rgba[i * 4 + 1], rgba[i * 4 + 2]
        if not (r >= NEAR_WHITE and g >= NEAR_WHITE and b >= NEAR_WHITE):
            continue
        bg[i] = 1
        q.append((x + 1, y))
        q.append((x - 1, y))
        q.append((x, y + 1))
        q.append((x, y - 1))
    # 设计内部的纯白（四邻皆纯白）→ 原画留白，保持不透明
    def is_white(i):
        return (rgba[i * 4] >= NEAR_WHITE and rgba[i * 4 + 1] >= NEAR_WHITE
                and rgba[i * 4 + 2] >= NEAR_WHITE)

    for y in range(1, h - 1):
        for x in range(1, w - 1):
            i = y * w + x
            if bg[i]:
                continue
            if not is_white(i):
                continue
            if is_white(i - 1) and is_white(i + 1) and is_white(i - w) and is_white(i + w):
                inner_white[i] = 1


def matte_background(w, h, rgba):
    """把**连通的背景白**抠掉（从四边泛洪），保留设计内部的浅色面与抗锯齿边缘。

    返回新的 RGBA（背景 alpha=0）。
    """
    out = bytearray(rgba)
    bg = bytearray(w * h)          # 1 = 背景
    inner_white = bytearray(w * h)  # 1 = 设计内部的纯白（原画留白）
    seeds = []
    for x in range(w):
        seeds.append((x, 0))
        seeds.append((x, h - 1))
    for y in range(h):
        seeds.append((0, y))
        seeds.append((w - 1, y))

    def is_white(i):
        return (rgba[i * 4] >= NEAR_WHITE and rgba[i * 4 + 1] >= NEAR_WHITE
                and rgba[i * 4 + 2] >= NEAR_WHITE)

    _flood(w, h, rgba, seeds, bg, inner_white)
    # 背景写透明；背景与墨迹之间的**过渡像素**（非纯白但紧邻背景）按"离白距离"给 alpha
    for i in range(w * h):
        if bg[i]:
            out[i * 4 + 3] = 0
            out[i * 4] = out[i * 4 + 1] = out[i * 4 + 2] = 0
            continue
        if inner_white[i]:
            continue               # 原画留白：保持原样（不透明纯白）
        r, g, b, a = out[i * 4], out[i * 4 + 1], out[i * 4 + 2], out[i * 4 + 3]
        d = max(255 - r, 255 - g, 255 - b)
        if d <= 255 - NEAR_WHITE:
            continue               # 设计内部的纯白（若有）：原样保留（不透明或原 alpha）
        # 只在"贴着背景"的浅色过渡像素上按距离给 alpha，避免把鲸身浅蓝面削薄
        x, y = i % w, i // w
        near_bg = False
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and bg[ny * w + nx]:
                near_bg = True
                break
        if not near_bg:
            continue
        alpha = min(255, max(0, int(round(d * 255 / (255 - NEAR_WHITE)))))
        out[i * 4 + 3] = min(a, alpha)
    return bytes(out)


def main():
    src = DEFAULT_SRC
    argv = sys.argv[1:]
    if '--src' in argv:
        src = argv[argv.index('--src') + 1]
    if not os.path.exists(src):
        print(f'[brand-master] ✗ 源件不存在：{src}', file=sys.stderr)
        return 2
    w, h, rgba = T.read_png(src)
    print(f'[brand-master] 源件 {src}  {w}×{h}')

    matted = matte_background(w, h, rgba)
    box = T.ink_bbox(w, h, matted, 128)
    if box is None:
        print('[brand-master] ✗ 抠白后没有任何墨迹（阈值把整张图吃掉了？）', file=sys.stderr)
        return 1
    cw, ch = box[2] - box[0], box[3] - box[1]
    print(f'[brand-master] 抠白后墨迹外接框 {box} = {cw}×{ch}')

    cwt, cht, cropped = T.crop(w, h, matted, box)
    scale = (CANVAS * MASTER_LONG_RATIO) / max(cwt, cht)
    rw, rh = max(1, int(round(cwt * scale))), max(1, int(round(cht * scale)))
    small = T.resize_rgba(cropped, cwt, cht, rw, rh)
    out = T.composite(bytes(CANVAS * CANVAS * 4), CANVAS, CANVAS,
                      small, rw, rh, (CANVAS - rw) // 2, (CANVAS - rh) // 2)
    T.write_png_rgba(OUT_FG, CANVAS, CANVAS, out)

    mb = T.ink_bbox(CANVAS, CANVAS, out, 128)
    opaque = sum(1 for i in range(CANVAS * CANVAS) if out[i * 4 + 3] > 128)
    print(f'[brand-master] ✓ 母版 {OUT_FG}')
    print(f'[brand-master]   墨迹 {mb[2] - mb[0]}×{mb[3] - mb[1]}，'
          f'长边占画布 {(mb[2] - mb[0]) / CANVAS:.3f}（口径 {MASTER_LONG_RATIO}）')
    print(f'[brand-master]   覆盖率 {100 * opaque / (CANVAS * CANVAS):.2f}%，'
          f'{os.path.getsize(OUT_FG) // 1024}KB')
    return 0


if __name__ == '__main__':
    sys.exit(main())

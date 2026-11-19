#!/usr/bin/env python3
"""
生成「鲸鸿」的**品牌物料**（APP 图标 / 启动画面 / 托盘 / 展示图）。

───────────────────────────── 设计 ─────────────────────────────
· 主体：**鲸鸿**品牌标 —— 蓝鲸剪影 + 环绕光环 + 星芒（2026-10-30 用户换标；
  源件 `Desktop/logo.png` 1254×1254 白底）。
  · 抠白时**只抠"近白背景"**（与纯白的最大通道差 ≤ `MATTE_WHITE_BAND`），
    鲸身内侧那块浅蓝面是**原画的一部分**，保留。
    （2026-10-16 虎鲸那轮源件本身就是 RGBA 透明底，没有这一幕；白底源件必须显式
     区分"背景白"与"设计里的浅色面"，否则会把鲸肚子挖空 —— 本文件是唯一判据点。）
· 背景：纯白（分层图标的 background 层，也是启动窗口 `startWindowBackground`）。

──────────────────────── 母版（源，手工放置） ────────────────────────
| 文件 | 内容 |
|---|---|
| `third_party/brand-source/foreground-1024.png` | 1024×1024 **RGBA、透明底**（墨迹紧包围盒 **757×400**） |
| `third_party/brand-source/jinghong-1254-source.png` | 1254×1254 用户原始件留档（换标的**再生成起点**） |
| `third_party/brand-source/background-1024.png` | 1024×1024 纯白 |

母版与 `third_party/brand-original/` 同性质：**本地素材**，`/third_party/` 不入库。
**母版缺失时本脚本直接退出**（不猜、不退化）。母版由 `tools/make-brand-master.py` 从源件生成。

──────────────────────── 产物（12 个） ────────────────────────
| 路径 | 尺寸 | 说明 |
|---|---|---|
| `AppScope/resources/base/media/foreground.png`   | 1024 | 分层图标前景（系统遮罩） |
| `AppScope/resources/base/media/background.png`   | 1024 | 分层图标背景（纯白） |
| `entry/src/main/resources/base/media/foreground.png` | 1024 | 同上（**必须与 AppScope 逐字节一致**） |
| `entry/src/main/resources/base/media/background.png` | 1024 | 同上 |
| `entry/src/main/resources/base/media/startIcon.png` | 512 | **启动窗口图标**（`startWindowIcon`） |
| `entry/src/main/resources/base/media/logo_dark.png` | 512 | **启动页大标识**（与 startIcon 同图） |
| `docs/brand/jinghong-icon.png` | 512 | README 展示图（白底合成） |
| `docs/brand/jinghong-mark.png` | 256 | 纯标记（透明底，物料用） |
| `docs/brand/jinghong-icon-1024.png` | **1024** | **AGC 商店图标上传件**（白底、正方形、无烘圆角） |
| `docs/brand/jinghong-icon-216.png` | **216** | 同上（AGC 允许的另一档尺寸） |
| `entry/src/main/resources/rawfile/web_brand_mark.png` | 96 | **Web UI 左上角品牌标·浅色主题用**（黑色剪影） |
| `entry/src/main/resources/rawfile/web_brand_mark_dark.png` | 96 | **Web UI 左上角品牌标·深色主题用**（白色剪影） |
| `entry/src/main/resources/rawfile/web_brand_color.png` | 96 | **Web UI 彩色品牌标**（垫片 base64 内联，docs/324） |
| `entry/src/main/resources/rawfile/tray_white.png` | 72 | **系统托盘图标·深色栏用**，纯白剪影 |
| `entry/src/main/resources/rawfile/tray_black.png` | 72 | **系统托盘图标·浅色栏用**，纯黑剪影 |

> **为什么全部由本脚本产出**：母版就是"透明底 + 墨迹占画布 73.9%"，
> APP 图标、启动画面、AGC 商店图标、托盘只是同一母版的**不同口径**；
> 手搓其中任何一张，等于把"所有品牌物料由脚本生成"这条规矩开个口子。

──────────────── 🔴 为什么不再依赖 Pillow / numpy（2026-10-30） ────────────────
旧版依赖 `PIL` + `numpy`，而本机（鸿蒙 PC，arm64 上的 Python 3.12）**没有**这两件：
PyPI 没有 openharmony-arm64 的预编译轮子，源码编译 numpy 在引导期就失败（实测）。
⇒ 位图运算改用 `tools/lib/tinypng.py`（纯标准库：PNG 读写 / 预乘缩放 / 合成 / 抠白），
本脚本因此**在任何装了 Python 3 的机器上都能跑**。

────────────────── 托盘图标为什么是"单色剪影" ──────────────────
`statusBarManager.StatusBarIcon` 要求**同一图案给两份**（`white` / `black`），
由系统按状态栏明暗二选一 ⇒ 托盘在定义上就是**单色剪影**，不能是彩色图。
这里取品牌标的 **alpha 剪影**，只在 72px 画布里按"长边占画布 `TRAY_RATIO`"居中。

────────────────────────── 三个必须注意的点 ──────────────────────────
1. **几何判据一律用"墨迹外接框"**，不用像素计数覆盖率 —— 后者与抗锯齿口径强相关，
   换渲染器就会假红（旧版踩过）。
2. **启动画面按"墨迹最长边占画布 `SPLASH_RATIO`"居中**，不拉满画布。
3. **自检全部跑完才写盘**：任一失败则**一个文件都不写**。

用法：
    python3 tools/make-brand-master.py   # 首次/换标：从源件生成母版
    python3 tools/make-icon.py           # 出 12 件物料
前置：`third_party/brand-source/{foreground,background}-1024.png` 存在。
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(HERE, 'lib'))

import tinypng as T  # noqa: E402  （纯标准库实现，见 tools/lib/tinypng.py）

"""
【为什么强制 stdout 用 UTF-8】本机控制台默认编码可能不是 UTF-8，脚本里的中文与
勾叉符号（✓ / ✗）会触发 UnicodeEncodeError 而中断 —— 那是**输出编码**问题，
不是逻辑问题。这里显式重配，让脚本在任何控制台都能跑完。
"""
try:
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')
except Exception:
    pass

SRC_DIR = os.path.join(ROOT, 'third_party', 'brand-source')
MASTER_FG = os.path.join(SRC_DIR, 'foreground-1024.png')
MASTER_BG = os.path.join(SRC_DIR, 'background-1024.png')

CANVAS = 1024
INK_ALPHA_MIN = 128              # 判"墨迹"的 alpha 阈值
MASTER_LONG_RATIO = 0.739        # 母版口径：墨迹最长边占画布（与上一代同一几何口径）

# ── 品牌标识（只影响产物命名；换标时改这一处）──
BRAND_SLUG = 'jinghong'

# ── APP 图标前景：调色板量化 ──
PALETTE_COLOURS = 256
CORE_COLOURS = 192               # 实心体（渐变要够细）
RIM_COLOURS = 63                 # 抗锯齿边缘（白底合成空间聚类）

# ── 启动画面（startIcon / logo_dark）──
# 品牌标是**横长**的（757×400 ≈ 1.89:1）：按长边 0.90 落方画布后上下各留约 23% 空白，
# 启动页上观感正好；拉满 1.0 会顶到边缘。
SPLASH_PX = 512
SPLASH_RATIO = 0.90

# ── 托盘（状态栏）图标参数 ──
TRAY_PX = 72                     # 官方建议 24vp×24vp；实产 72px 供高分屏
TRAY_RATIO = 0.861
# 墨迹外接框期望值（**真正的判据**）：宽 62 = 0.861 × 72；
# 高 36 是新标（鲸鸿）的**实测量**：母版墨迹 757×444（含光环与下垂的浅色鳍尖，
# 比"鲸身主体"高），62 / (757/444) = 36.4 ⇒ 36。旧虎鲸是 62×52，别沿用。
TRAY_BBOX_W = 62
TRAY_BBOX_H = 36

# ── Web UI 品牌标（docs/322）──
# 96px 供 24px 显示位（4x 超采样）；长边占画布 0.92 —— 侧栏槽位是 24x24 方框，
# 横长的标要尽量吃满宽度，否则在方形槽位里显得小。
WEB_BRAND_PX = 96
WEB_BRAND_RATIO = 0.92

# ── AGC 商店图标（正方形、216 或 1024、PNG ≤ 3MB / WEBP ≤ 100KB；不烘圆角）──
AGC_ICON_PX = [1024, 216]
AGC_ICON_MAX_BYTES = 3 * 1024 * 1024


def load_master():
    if not os.path.exists(MASTER_FG):
        print(f'[make-icon] ✗ 缺品牌母版 {MASTER_FG}', file=sys.stderr)
        print('  先跑 `python3 tools/make-brand-master.py` 从源件生成母版；母版缺失时不猜。',
              file=sys.stderr)
        return None, None, None
    w, h, rgba = T.read_png(MASTER_FG)
    if (w, h) != (CANVAS, CANVAS):
        print(f'[make-icon] ✗ 母版尺寸 {w}×{h} 不是 {CANVAS}×{CANVAS}', file=sys.stderr)
        return None, None, None
    bg = None
    if os.path.exists(MASTER_BG):
        bw, bh, brgba = T.read_png(MASTER_BG)
        if (bw, bh) == (CANVAS, CANVAS) and all(brgba[i] > 250 for i in range(0, len(brgba), 4)):
            bg = bytes(b'\xff' * (CANVAS * CANVAS * 4))
        else:
            print(f'[make-icon] ⚠ 背景母版不是纯白 {bw}×{bh}，背景层退回纯白', file=sys.stderr)
    else:
        print(f'[make-icon] ⚠ 缺 {MASTER_BG}，背景层退回纯白', file=sys.stderr)
    if bg is None:
        bg = bytes(b'\xff' * (CANVAS * CANVAS * 4))
    return (w, h, rgba), bg, None


# ───────────────────── APP 图标前景（调色板量化）─────────────────────
def build_foreground(w, h, rgba):
    """256 项调色板 PNG（体积可控，且不让渐变变块状）。

    对 (R,G,B,A) 做**单次联合**量化会把大部分调色板条目花在抗锯齿边缘上，
    使实心体渐变变块状。所以两个域**分开量子化**：实心体保 alpha=255；
    边缘簇在**白底合成空间**聚类（均值色 + 均值 alpha），再反解回 (颜色, alpha) 对。
    """
    core = {}
    rim = {}
    for i in range(w * h):
        a = rgba[i * 4 + 3]
        if a == 0:
            continue
        r, g, b = rgba[i * 4], rgba[i * 4 + 1], rgba[i * 4 + 2]
        if a >= 250:
            key = (r >> 2, g >> 2, b >> 2)
            slot = core.get(key)
            if slot is None:
                core[key] = [1, r, g, b]
            else:
                slot[0] += 1
                slot[1] += r
                slot[2] += g
                slot[3] += b
        else:
            aa = a >> 3
            cr = (r * a + 255 * (255 - a)) // 255
            cg = (g * a + 255 * (255 - a)) // 255
            cb = (b * a + 255 * (255 - a)) // 255
            key = (aa, cr >> 4, cg >> 4, cb >> 4)
            slot = rim.get(key)
            if slot is None:
                rim[key] = [1, r, g, b, a]
            else:
                slot[0] += 1
                slot[1] += r
                slot[2] += g
                slot[3] += b
                slot[4] += a

    core_sorted = sorted(core.items(), key=lambda kv: -kv[1][0])
    palette = [(0, 0, 0, 0)]
    core_index = {}
    for key, (n, sr, sg, sb) in core_sorted[:CORE_COLOURS]:
        palette.append((sr // n, sg // n, sb // n, 255))
        core_index[key] = len(palette) - 1
    # 被截断的桶并入最接近的已保留色（欧氏距离）
    for key, (n, sr, sg, sb) in core_sorted[CORE_COLOURS:]:
        r, g, b = sr // n, sg // n, sb // n
        best, best_d = 1, 1 << 30
        for pos in range(1, len(palette)):
            r2, g2, b2, _a2 = palette[pos]
            d = (r - r2) ** 2 + (g - g2) ** 2 + (b - b2) ** 2
            if d < best_d:
                best, best_d = pos, d
        core_index[key] = best

    rim_sorted = sorted(rim.items(), key=lambda kv: -kv[1][0])
    rim_index = {}
    for key, (n, sr, sg, sb, sa) in rim_sorted[:RIM_COLOURS]:
        if len(palette) >= PALETTE_COLOURS - 1:
            break
        palette.append((sr // n, sg // n, sb // n, sa // n))
        rim_index[key] = len(palette) - 1
    for key, (n, sr, sg, sb, sa) in rim_sorted:
        if key in rim_index:
            continue
        if len(palette) >= PALETTE_COLOURS:
            rim_index[key] = 0        # 极端情况下宁可丢掉最细的边缘，也不越界
            continue
        palette.append((sr // n, sg // n, sb // n, sa // n))
        rim_index[key] = len(palette) - 1

    index = bytearray(w * h)
    for i in range(w * h):
        a = rgba[i * 4 + 3]
        if a == 0:
            continue
        r, g, b = rgba[i * 4], rgba[i * 4 + 1], rgba[i * 4 + 2]
        if a >= 250:
            index[i] = core_index[(r >> 2, g >> 2, b >> 2)]
        else:
            aa = a >> 3
            cr = (r * a + 255 * (255 - a)) // 255
            cg = (g * a + 255 * (255 - a)) // 255
            cb = (b * a + 255 * (255 - a)) // 255
            index[i] = rim_index[(aa, cr >> 4, cg >> 4, cb >> 4)]
    palette = (palette + [(0, 0, 0, 0)] * PALETTE_COLOURS)[:PALETTE_COLOURS]
    return bytes(index), palette


# ───────────────────────── 缩放/合成工具 ─────────────────────────
def place_centred(w, h, rgba, canvas_px, ratio):
    """把墨迹按"最长边占画布 ratio"缩放到 canvas_px 方画布正中（透明底）。"""
    box = T.ink_bbox(w, h, rgba, INK_ALPHA_MIN)
    if box is None:
        return bytes(canvas_px * canvas_px * 4), 0, 0
    cw, ch, cr = T.crop(w, h, rgba, box)
    scale = (canvas_px * ratio) / max(cw, ch)
    rw, rh = max(1, int(round(cw * scale))), max(1, int(round(ch * scale)))
    small = T.resize_rgba(cr, cw, ch, rw, rh)
    out = T.composite(bytes(canvas_px * canvas_px * 4), canvas_px, canvas_px,
                      small, rw, rh, (canvas_px - rw) // 2, (canvas_px - rh) // 2)
    return out, rw, rh


def make_silhouette(w, h, rgba, px, ratio):
    """墨迹的 alpha 缩成单色剪影（保留抗锯齿），返回画布尺寸的 alpha 数组。"""
    box = T.ink_bbox(w, h, rgba, INK_ALPHA_MIN)
    cw, ch, cr = T.crop(w, h, rgba, box)
    scale = (px * ratio) / max(cw, ch)
    rw, rh = max(1, int(round(cw * scale))), max(1, int(round(ch * scale)))
    small = T.resize_rgba(cr, cw, ch, rw, rh)
    alpha = bytearray(px * px)
    ox, oy = (px - rw) // 2, (px - rh) // 2
    for y in range(rh):
        for x in range(rw):
            alpha[(oy + y) * px + ox + x] = small[(y * rw + x) * 4 + 3]
    return alpha


def tint(alpha, colour):
    out = bytearray(len(alpha) * 4)
    for i in range(len(alpha)):
        out[i * 4] = colour[0]
        out[i * 4 + 1] = colour[1]
        out[i * 4 + 2] = colour[2]
        out[i * 4 + 3] = alpha[i]
    return bytes(out)


def encoded(w, h, payload, kind):
    """在内存里编码一次（体积判据要用它），返回 PNG 字节。"""
    tmp = os.path.join(HERE, f'.tmp-brand-{kind}-{w}.png')
    if kind == 'rgba':
        T.write_png_rgba(tmp, w, h, payload)
    elif kind == 'rgb':
        T.write_png_rgb(tmp, w, h, payload)
    else:
        T.write_png_palette(tmp, w, h, payload[0], payload[1])
    with open(tmp, 'rb') as f:
        blob = f.read()
    os.remove(tmp)
    return blob


# ───────────────────────── main ─────────────────────────
def main():
    master, bg_rgba, _ = load_master()
    if master is None:
        return 2
    mw, mh, master_rgba = master

    fg_png = encoded(mw, mh, build_foreground(mw, mh, master_rgba), 'pal')
    bg_png = encoded(CANVAS, CANVAS, bg_rgba, 'rgba')

    splash_rgba, sw, sh = place_centred(mw, mh, master_rgba, SPLASH_PX, SPLASH_RATIO)
    splash_png = encoded(SPLASH_PX, SPLASH_PX, splash_rgba, 'rgba')

    showcase = T.flatten_on_white(512, 512, T.resize_rgba(master_rgba, mw, mh, 512, 512))
    showcase_png = encoded(512, 512, showcase, 'rgb')
    mark_png = encoded(256, 256, T.resize_rgba(master_rgba, mw, mh, 256, 256), 'rgba')
    # Agent 图标：512 透明底品牌标（在系统里当应用形象出现，构图与启动标识同口径）
    agent_png = encoded(512, 512, T.resize_rgba(master_rgba, mw, mh, 512, 512), 'rgba')
    agc = []
    for px in AGC_ICON_PX:
        rgb = T.flatten_on_white(px, px, T.resize_rgba(master_rgba, mw, mh, px, px))
        agc.append((px, encoded(px, px, rgb, 'rgb')))

    sil = make_silhouette(mw, mh, master_rgba, TRAY_PX, TRAY_RATIO)
    tray_w = tint(sil, (255, 255, 255, 255))
    tray_b = tint(sil, (0, 0, 0, 255))
    tray_w_png = encoded(TRAY_PX, TRAY_PX, tray_w, 'rgba')
    tray_b_png = encoded(TRAY_PX, TRAY_PX, tray_b, 'rgba')

    # ── Web UI 品牌标（docs/322）──────────────────────────────────────────
    # 上游侧栏 `sidebar.brand.mark` 槽位画的是官方鲸鱼（SVG，24px）。垫片把它隐藏后
    # 用背景图盖上去，所以要出**两档**：浅色主题黑色剪影、深色主题白色剪影。
    # 96px（4× 于 24px 显示尺寸）保证高分屏不糊。
    # 【2026-10-31 改彩色（docs/324）】用户口径："左上角品牌 logo 不用做成黑色，直接彩色的接入"。
    # 彩色图无法用 SVG path 表达（那只能是单色剪影）⇒ 改为**内联 base64 PNG**。
    # 为什么要内联：ArkWeb 页面拿不到 `rawfile`，垫片只能自带数据。
    # 尺寸取 2× 显示位（24px → 48px 足够清晰，文件仅数 KB）。
    web_sil = make_silhouette(mw, mh, master_rgba, WEB_BRAND_PX, WEB_BRAND_RATIO)
    web_brand_black = encoded(WEB_BRAND_PX, WEB_BRAND_PX, tint(web_sil, (0, 0, 0, 255)), 'rgba')
    web_brand_white = encoded(WEB_BRAND_PX, WEB_BRAND_PX, tint(web_sil, (255, 255, 255, 255)), 'rgba')
    # 彩色版：母版直接缩放（保留原色与透明底），96px 供侧栏 24px / Hero 44px 两处使用
    web_brand_color = encoded(WEB_BRAND_PX, WEB_BRAND_PX,
                              T.resize_rgba(master_rgba, mw, mh, WEB_BRAND_PX, WEB_BRAND_PX), 'rgba')

    outs = [
        ('AppScope/resources/base/media/foreground.png', fg_png),
        ('AppScope/resources/base/media/background.png', bg_png),
        ('entry/src/main/resources/base/media/foreground.png', fg_png),
        ('entry/src/main/resources/base/media/background.png', bg_png),
        ('entry/src/main/resources/base/media/startIcon.png', splash_png),
        ('entry/src/main/resources/base/media/logo_dark.png', splash_png),
        # 手机 HAP 是**另一套资源目录**（phone/src/main/resources/…）：门禁
        # `check-brand-surface` 要求 entry 与 phone 的图标逐字节一致 —— 只写 entry
        # 就会出现"平板新标、手机旧标"。所以每个图标都要写两份（原图与启动标识各一）。
        ('phone/src/main/resources/base/media/foreground.png', fg_png),
        ('phone/src/main/resources/base/media/background.png', bg_png),
        ('phone/src/main/resources/base/media/startIcon.png', splash_png),
        ('phone/src/main/resources/base/media/logo_dark.png', splash_png),
        # 【2026-10-31 删除（docs/323）】这里原本产出 platform 的 brand_icon.png，
        # 供共享面板里官方 LoginPanel 的 appInfo.appIcon 使用。登录改静默授权后
        # LoginPanel 已整体移除 ⇒ 该素材零引用，连 platform/src/main/resources 一并删除。
        # Agent 图标（A2A 智能体在系统里的形象）同样两份，且与品牌标同源（512 透明底）
        ('entry/src/main/resources/rawfile/common/dshm_agent_icon.png', agent_png),
        ('phone/src/main/resources/rawfile/common/dshm_agent_icon.png', agent_png),
        (f'docs/brand/{BRAND_SLUG}-icon.png', showcase_png),
        (f'docs/brand/{BRAND_SLUG}-mark.png', mark_png),
        (f'docs/brand/{BRAND_SLUG}-icon-1024.png', agc[0][1]),
        (f'docs/brand/{BRAND_SLUG}-icon-216.png', agc[1][1]),
        ('entry/src/main/resources/rawfile/tray_white.png', tray_w_png),
        ('entry/src/main/resources/rawfile/tray_black.png', tray_b_png),
        # Web UI 左上角品牌标（浅色主题黑剪影 / 深色主题白剪影，docs/322）
        ('entry/src/main/resources/rawfile/web_brand_mark.png', web_brand_black),
        ('entry/src/main/resources/rawfile/web_brand_mark_dark.png', web_brand_white),
        # 彩色版（Web 垫片内联用；docs/324）
        ('entry/src/main/resources/rawfile/web_brand_color.png', web_brand_color),
    ]

    # ── 写盘前把所有自检跑完 ──
    failures = []

    # 【自检①】前景：体积带 + 墨迹长边占画布（几何判据，与抗锯齿无关）+ 四角透明
    fg_kb = len(fg_png) / 1024
    box = T.ink_bbox(mw, mh, master_rgba, INK_ALPHA_MIN)
    bw, bh = box[2] - box[0], box[3] - box[1]
    long_ratio = max(bw, bh) / CANVAS
    print(f'[make-icon] 前景 {CANVAS}px 体积 {fg_kb:.1f}KB（预期 15~400KB），'
          f'墨迹 {bw}×{bh}，长边占画布 {long_ratio:.3f}（预期 {MASTER_LONG_RATIO}±0.02）')
    if not (15 <= fg_kb <= 400):
        failures.append(f'前景体积 {fg_kb:.1f}KB 不在 15~400KB 带内')
    if abs(long_ratio - MASTER_LONG_RATIO) > 0.02:
        failures.append(f'前景墨迹长边占画布 {long_ratio:.3f} 偏离 {MASTER_LONG_RATIO}'
                        ' —— 母版缩放口径错了')
    for (x, y) in [(4, 4), (CANVAS - 5, 4), (4, CANVAS - 5), (CANVAS - 5, CANVAS - 5)]:
        if master_rgba[(y * mw + x) * 4 + 3] > INK_ALPHA_MIN:
            failures.append(f'前景四角有墨（({x},{y})）—— 品牌标溢出/填充范围错')
            break

    # 【自检②】启动画面：墨迹最长边占比（同时能拦"没画上"与"拉满/溢出"）+ 四角透明
    sbox = T.ink_bbox(SPLASH_PX, SPLASH_PX, splash_rgba, INK_ALPHA_MIN)
    if sbox is None:
        failures.append('启动画面整张全透明 —— 品牌标根本没画上去')
    else:
        span = max(sbox[2] - sbox[0], sbox[3] - sbox[1])
        got = span / SPLASH_PX
        print(f'[make-icon] 启动画面 {SPLASH_PX}px 墨迹最长边 {span}（占比 {got:.3f}，'
              f'预期 {SPLASH_RATIO}±0.03），落位 {sw}×{sh}')
        if abs(got - SPLASH_RATIO) > 0.03:
            failures.append(f'启动画面墨迹占比 {got:.3f} 偏离预期 {SPLASH_RATIO}')
        for (x, y) in [(4, 4), (SPLASH_PX - 5, 4), (4, SPLASH_PX - 5), (SPLASH_PX - 5, SPLASH_PX - 5)]:
            if splash_rgba[(y * SPLASH_PX + x) * 4 + 3] > INK_ALPHA_MIN:
                failures.append('启动画面四角有墨（带上了白底方块或溢出）')
                break

    # 【自检③】托盘：白/黑 alpha 逐像素相同；颜色纯粹（白图纯白、黑图纯黑）
    shape_diff = sum(1 for i in range(TRAY_PX * TRAY_PX) if tray_w[i * 4 + 3] != tray_b[i * 4 + 3])
    bad_color = 0
    for i in range(TRAY_PX * TRAY_PX):
        if tray_w[i * 4 + 3] > INK_ALPHA_MIN and (tray_w[i * 4], tray_w[i * 4 + 1], tray_w[i * 4 + 2]) != (255, 255, 255):
            bad_color += 1
        if tray_b[i * 4 + 3] > INK_ALPHA_MIN and (tray_b[i * 4], tray_b[i * 4 + 1], tray_b[i * 4 + 2]) != (0, 0, 0):
            bad_color += 1
    print(f'[make-icon] 托盘 白/黑 alpha 差异像素 {shape_diff}（必须 0）；'
          f'非纯色像素 {bad_color}（必须 0）')
    if shape_diff != 0:
        failures.append(f'托盘 white/black 形状不一致（alpha 差异 {shape_diff} 像素）')
    if bad_color != 0:
        failures.append(f'托盘图标含非纯色像素（{bad_color} 个）—— 状态栏明暗适配会失准')

    # 【自检④】托盘外接框（±1px）、不贴边、框内有透明（是剪影不是色块）
    tbox = T.ink_bbox(TRAY_PX, TRAY_PX, tray_w, INK_ALPHA_MIN)
    if tbox is None:
        failures.append('托盘图标整张全透明 —— 品牌标根本没画上去')
    else:
        tw_, th_ = tbox[2] - tbox[0], tbox[3] - tbox[1]
        print(f'[make-icon] 托盘 墨迹外接框 {tw_}×{th_}（预期 {TRAY_BBOX_W}×{TRAY_BBOX_H}，±1）'
              f' x[{tbox[0]}..{tbox[2] - 1}] y[{tbox[1]}..{tbox[3] - 1}]')
        if abs(tw_ - TRAY_BBOX_W) > 1 or abs(th_ - TRAY_BBOX_H) > 1:
            failures.append(f'托盘外接框 {tw_}×{th_} 偏离预期 {TRAY_BBOX_W}×{TRAY_BBOX_H}（±1）'
                            ' —— 缩放/留边算错')
        if tbox[0] < 1 or tbox[1] < 1 or tbox[2] > TRAY_PX - 1 or tbox[3] > TRAY_PX - 1:
            failures.append(f'托盘贴边（x[{tbox[0]}..{tbox[2] - 1}] y[{tbox[1]}..{tbox[3] - 1}]）'
                            ' —— 状态栏里会被裁掉边缘')
        inside = 0
        total = tw_ * th_
        for y in range(tbox[1], tbox[3]):
            for x in range(tbox[0], tbox[2]):
                if sil[y * TRAY_PX + x] <= INK_ALPHA_MIN:
                    inside += 1
        pct = 100.0 * inside / total
        print(f'[make-icon] 托盘 外接框内透明像素 {inside}/{total}（{pct:.1f}%，须 > 30%）')
        if inside < total * 0.30:
            failures.append(f'托盘外接框内透明像素仅 {pct:.1f}% —— 会被当成一块色斑')

    # 【自检⑤】AGC 商店图标：正方形 + PNG ≤ 3MB
    for px, blob in agc:
        print(f'[make-icon] AGC 商店图标 {px}px PNG {len(blob) / 1024:.1f}KB（规范上限 3MB）')
        if len(blob) > AGC_ICON_MAX_BYTES:
            failures.append(f'AGC 商店图标 {px}px PNG {len(blob) / 1024:.1f}KB 超过 3MB 上限')

    if failures:
        for f in failures:
            print(f'[make-icon] ✗ {f}', file=sys.stderr)
        print('[make-icon] 自检未过 —— **未写任何文件**', file=sys.stderr)
        return 1

    # ── 全部自检通过，写盘 ──
    for rel, blob in outs:
        p = os.path.join(ROOT, rel.replace('/', os.sep))
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, 'wb') as f:
            f.write(blob)
        print(f'[make-icon]   {rel}  {len(blob) // 1024}KB')

    # 【落盘后】三对必须逐字节相同
    pairs = [
        ('AppScope/resources/base/media/foreground.png',
         'entry/src/main/resources/base/media/foreground.png'),
        ('AppScope/resources/base/media/background.png',
         'entry/src/main/resources/base/media/background.png'),
        ('entry/src/main/resources/base/media/startIcon.png',
         'entry/src/main/resources/base/media/logo_dark.png'),
        # 手机 HAP 与平板 HAP 必须同图（check-brand-surface 的两条硬判据）
        ('entry/src/main/resources/base/media/foreground.png',
         'phone/src/main/resources/base/media/foreground.png'),
        ('entry/src/main/resources/base/media/background.png',
         'phone/src/main/resources/base/media/background.png'),
        ('entry/src/main/resources/base/media/startIcon.png',
         'phone/src/main/resources/base/media/startIcon.png'),
        ('entry/src/main/resources/rawfile/common/dshm_agent_icon.png',
         'phone/src/main/resources/rawfile/common/dshm_agent_icon.png'),
    ]
    for a, b in pairs:
        pa = os.path.join(ROOT, a.replace('/', os.sep))
        pb = os.path.join(ROOT, b.replace('/', os.sep))
        with open(pa, 'rb') as f1, open(pb, 'rb') as f2:
            same = f1.read() == f2.read()
        print(f'[make-icon]   {"✓ 一致" if same else "✗ 不一致"} '
              f'{os.path.basename(a)} ↔ {os.path.basename(b)}')
        if not same:
            print(f'[make-icon] ✗ {a} 与 {b} 落盘后不一致', file=sys.stderr)
            return 1

    # 【护栏·反向断言】启动画面**不得**回退成历史鲸鱼（留档在 brand-original/）
    orig_dir = os.path.join(ROOT, 'third_party', 'brand-original')
    for base in ['startIcon.png', 'logo_dark.png']:
        org = os.path.join(orig_dir, base)
        if not os.path.exists(org):
            print(f'[make-icon] ⚠ 缺历史归档 {org}，跳过 {base} 的回退判据', file=sys.stderr)
            continue
        cur = os.path.join(ROOT, 'entry', 'src', 'main', 'resources', 'base', 'media', base)
        with open(cur, 'rb') as f1, open(org, 'rb') as f2:
            same = f1.read() == f2.read()
        print(f'[make-icon]   {"✗ 仍是历史鲸鱼" if same else "✓ 已非历史鲸鱼"} {base}')
        if same:
            print(f'[make-icon] ✗ {base} 仍等于历史鲸鱼 —— 品牌标未生效', file=sys.stderr)
            return 1

    return 0


if __name__ == '__main__':
    sys.exit(main())

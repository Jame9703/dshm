#!/usr/bin/env python3
"""
纯标准库的位图小工具（PNG 读写 + 缩放 + 合成），**零第三方依赖**。

────────────────── 为什么不用 Pillow / numpy（2026-10-30） ──────────────────
品牌物料要由 `tools/make-icon.py` 生成，而它必须在**构建机**上跑得起来。
本机（鸿蒙 PC，arm64 上的 Python 3.12）没有 Pillow：PyPI 上 pillow / numpy **没有**
openharmony-arm64 的预编译轮子，源码编译 numpy 也会在引导期失败（实测）。
旧版 `make-icon.py` 依赖这两件 ⇒ 换标时就地跑不起来。

而图标产物必须**每次都能重新生成**（AGENTS.md：脚本生成、产物入库），不能靠
"某台机器手工拼一次"。因此这里只用标准库实现真正需要的三件事：
  · PNG 解码（IHDR / IDAT / PLTE，支持 8 位 RGB / RGBA / 灰度 / 调色板，含 tRNS）；
  · 高质量缩放（**面积平均**降采样 / **双线性**升采样，预乘 alpha，避免白边）；
  · RGBA 画布合成与抠白（把纯白底的图变成透明底并保留抗锯齿边缘）。

**刻意不做**的事：不追求通用图片库的完整度（不支持 16 位色深、隔行扫描、
色彩管理）。母版是我们自己的 PNG（8 位、非隔行），这条边界写清楚即可。

@module tools/lib/tinypng
"""
import struct
import zlib


# ───────────────────────── 解码 ─────────────────────────

def _paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def read_png(path):
    """读 PNG → `(width, height, rgba_bytes)`（每像素 4 字节，非预乘）。

    支持色型 0（灰度）/ 2（RGB）/ 3（调色板）/ 6（RGBA），位深 8，非隔行。
    """
    with open(path, 'rb') as f:
        data = f.read()
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError(f'不是 PNG：{path}')
    pos = 8
    width = height = bit_depth = colour_type = interlace = 0
    palette = b''
    trns = b''
    idat = bytearray()
    while pos < len(data):
        length = struct.unpack('>I', data[pos:pos + 4])[0]
        ctype = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if ctype == b'IHDR':
            width, height, bit_depth, colour_type, _comp, _filt, interlace = struct.unpack('>IIBBBBB', body)
        elif ctype == b'PLTE':
            palette = body
        elif ctype == b'tRNS':
            trns = body
        elif ctype == b'IDAT':
            idat += body
        elif ctype == b'IEND':
            break
    if bit_depth != 8:
        raise ValueError(f'只支持 8 位色深（该文件是 {bit_depth} 位）：{path}')
    if interlace != 0:
        raise ValueError(f'不支持隔行扫描：{path}')

    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[colour_type]
    stride = width * channels
    raw = zlib.decompress(bytes(idat))
    out = bytearray(height * stride)
    prev = bytearray(stride)
    pos = 0
    for y in range(height):
        filt = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        pos += stride
        if filt == 1:      # Sub
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif filt == 2:    # Up
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif filt == 3:    # Average
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif filt == 4:    # Paeth
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                up = prev[i]
                upleft = prev[i - channels] if i >= channels else 0
                line[i] = (line[i] + _paeth(left, up, upleft)) & 0xFF
        elif filt != 0:
            raise ValueError(f'未知行过滤器 {filt}（第 {y} 行）')
        out[y * stride:(y + 1) * stride] = line
        prev = line

    rgba = bytearray(width * height * 4)
    n = width * height
    if colour_type == 6:
        rgba[:] = out
    elif colour_type == 2:
        for i in range(n):
            rgba[i * 4] = out[i * 3]
            rgba[i * 4 + 1] = out[i * 3 + 1]
            rgba[i * 4 + 2] = out[i * 3 + 2]
            rgba[i * 4 + 3] = 255
    elif colour_type == 0:
        for i in range(n):
            v = out[i]
            rgba[i * 4] = rgba[i * 4 + 1] = rgba[i * 4 + 2] = v
            rgba[i * 4 + 3] = 255
    elif colour_type == 3:
        for i in range(n):
            k = out[i]
            rgba[i * 4] = palette[k * 3]
            rgba[i * 4 + 1] = palette[k * 3 + 1]
            rgba[i * 4 + 2] = palette[k * 3 + 2]
            rgba[i * 4 + 3] = trns[k] if k < len(trns) else 255
    else:
        raise ValueError(f'不支持的色型 {colour_type}：{path}')
    return width, height, bytes(rgba)


# ───────────────────────── 编码 ─────────────────────────

def _chunk(ctype, body):
    return (struct.pack('>I', len(body)) + ctype + body
            + struct.pack('>I', zlib.crc32(ctype + body) & 0xFFFFFFFF))


def write_png_rgba(path, width, height, rgba):
    """写 8 位 RGBA PNG（每行用 Up 过滤器，配合 zlib 最高压缩）。"""
    stride = width * 4
    raw = bytearray()
    prev = bytearray(stride)
    for y in range(height):
        line = rgba[y * stride:(y + 1) * stride]
        raw.append(2)  # Up
        raw += bytes((line[i] - prev[i]) & 0xFF for i in range(stride))
        prev = bytearray(line)
    body = (b'\x89PNG\r\n\x1a\n'
            + _chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
            + _chunk(b'IDAT', zlib.compress(bytes(raw), 9))
            + _chunk(b'IEND', b''))
    with open(path, 'wb') as f:
        f.write(body)


def write_png_palette(path, width, height, indices, palette):
    """写 8 位调色板 PNG（`palette` 为 `[(r,g,b,a), …]`，最多 256 项）。"""
    plte = bytearray()
    trns = bytearray()
    last_nonzero = -1
    for i, (r, g, b, a) in enumerate(palette[:256]):
        plte += bytes((r, g, b))
        trns.append(a)
        if a != 255:
            last_nonzero = i
    trns = trns[:last_nonzero + 1]
    stride = width
    raw = bytearray()
    prev = bytearray(stride)
    for y in range(height):
        line = indices[y * stride:(y + 1) * stride]
        raw.append(2)
        raw += bytes((line[i] - prev[i]) & 0xFF for i in range(stride))
        prev = bytearray(line)
    body = (b'\x89PNG\r\n\x1a\n'
            + _chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 3, 0, 0, 0))
            + _chunk(b'PLTE', bytes(plte))
            + (_chunk(b'tRNS', bytes(trns)) if trns else b'')
            + _chunk(b'IDAT', zlib.compress(bytes(raw), 9))
            + _chunk(b'IEND', b''))
    with open(path, 'wb') as f:
        f.write(body)


def write_png_rgb(path, width, height, rgb):
    """写 8 位 RGB PNG（展示图 / AGC 商店图标这类不透明图）。"""
    stride = width * 3
    raw = bytearray()
    prev = bytearray(stride)
    for y in range(height):
        line = rgb[y * stride:(y + 1) * stride]
        raw.append(2)
        raw += bytes((line[i] - prev[i]) & 0xFF for i in range(stride))
        prev = bytearray(line)
    body = (b'\x89PNG\r\n\x1a\n'
            + _chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
            + _chunk(b'IDAT', zlib.compress(bytes(raw), 9))
            + _chunk(b'IEND', b''))
    with open(path, 'wb') as f:
        f.write(body)


# ───────────────────────── 变换 ─────────────────────────

def resize_rgba(src, sw, sh, dw, dh):
    """RGBA 缩放（**预乘 alpha** 后做面积平均降采样 / 双线性升采样）。

    【为什么必须预乘】直接对 (r,g,b,a) 各自插值，会把"透明区域的黑色"混进边缘，
    PNG 在深色背景上就出现一圈黑边（品牌标最常见的瑕疵）。
    预乘后插值 = 物理上正确的颜色混合，最后再反预乘回直通 alpha。
    """
    if (sw, sh) == (dw, dh):
        return src
    # 预乘
    pm = [0.0] * (sw * sh * 4)
    for i in range(sw * sh):
        a = src[i * 4 + 3] / 255.0
        pm[i * 4] = src[i * 4] * a
        pm[i * 4 + 1] = src[i * 4 + 1] * a
        pm[i * 4 + 2] = src[i * 4 + 2] * a
        pm[i * 4 + 3] = a
    out = [0.0] * (dw * dh * 4)
    if dw <= sw and dh <= sh:
        # 面积平均：每个目标像素覆盖源图的一块矩形，按覆盖面积加权
        for dy in range(dh):
            y0 = dy * sh / dh
            y1 = (dy + 1) * sh / dh
            iy0, iy1 = int(y0), min(sh, int(y1 + 0.999999))
            for dx in range(dw):
                x0 = dx * sw / dw
                x1 = (dx + 1) * sw / dw
                ix0, ix1 = int(x0), min(sw, int(x1 + 0.999999))
                acc = [0.0, 0.0, 0.0, 0.0]
                wsum = 0.0
                for sy in range(iy0, iy1):
                    wy = min(y1, sy + 1) - max(y0, sy)
                    if wy <= 0:
                        continue
                    for sx in range(ix0, ix1):
                        wx = min(x1, sx + 1) - max(x0, sx)
                        if wx <= 0:
                            continue
                        w = wx * wy
                        wsum += w
                        j = (sy * sw + sx) * 4
                        acc[0] += pm[j] * w
                        acc[1] += pm[j + 1] * w
                        acc[2] += pm[j + 2] * w
                        acc[3] += pm[j + 3] * w
                o = (dy * dw + dx) * 4
                if wsum > 0:
                    out[o] = acc[0] / wsum
                    out[o + 1] = acc[1] / wsum
                    out[o + 2] = acc[2] / wsum
                    out[o + 3] = acc[3] / wsum
    else:
        # 双线性（放大）：目标像素反算回源坐标
        for dy in range(dh):
            fy = (dy + 0.5) * sh / dh - 0.5
            y0 = max(0, min(sh - 1, int(fy)))
            y1 = min(sh - 1, y0 + 1)
            ty = max(0.0, min(1.0, fy - y0))
            for dx in range(dw):
                fx = (dx + 0.5) * sw / dw - 0.5
                x0 = max(0, min(sw - 1, int(fx)))
                x1 = min(sw - 1, x0 + 1)
                tx = max(0.0, min(1.0, fx - x0))
                o = (dy * dw + dx) * 4
                for c in range(4):
                    p00 = pm[(y0 * sw + x0) * 4 + c]
                    p10 = pm[(y0 * sw + x1) * 4 + c]
                    p01 = pm[(y1 * sw + x0) * 4 + c]
                    p11 = pm[(y1 * sw + x1) * 4 + c]
                    top = p00 + (p10 - p00) * tx
                    bot = p01 + (p11 - p01) * tx
                    out[o + c] = top + (bot - top) * ty
    # 反预乘
    res = bytearray(dw * dh * 4)
    for i in range(dw * dh):
        a = out[i * 4 + 3]
        res[i * 4 + 3] = max(0, min(255, int(round(a * 255))))
        if a <= 1e-6:
            res[i * 4] = res[i * 4 + 1] = res[i * 4 + 2] = 0
        else:
            for c in range(3):
                res[i * 4 + c] = max(0, min(255, int(round(out[i * 4 + c] / a))))
    return bytes(res)


def flatten_on_white(width, height, rgba):
    """RGBA 合成到纯白（展示图 / AGC 商店图标），返回 RGB 字节。"""
    rgb = bytearray(width * height * 3)
    for i in range(width * height):
        a = rgba[i * 4 + 3] / 255.0
        for c in range(3):
            rgb[i * 3 + c] = max(0, min(255, int(round(rgba[i * 4 + c] * a + 255.0 * (1 - a)))))
    return bytes(rgb)


def ink_bbox(width, height, rgba, alpha_min=128):
    """墨迹紧包围盒 `(x0, y0, x1, y1)`（右/下为开区间）；无墨迹返回 None。"""
    xs0, ys0, xs1, ys1 = width, height, -1, -1
    for y in range(height):
        row = y * width * 4
        for x in range(width):
            if rgba[row + x * 4 + 3] > alpha_min:
                if x < xs0:
                    xs0 = x
                if x > xs1:
                    xs1 = x
                if y < ys0:
                    ys0 = y
                if y > ys1:
                    ys1 = y
    if xs1 < 0:
        return None
    return xs0, ys0, xs1 + 1, ys1 + 1


def crop(width, height, rgba, box):
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    out = bytearray(w * h * 4)
    for y in range(h):
        src = ((y + y0) * width + x0) * 4
        out[y * w * 4:(y + 1) * w * 4] = rgba[src:src + w * 4]
    return w, h, bytes(out)


def composite(dst, dw, dh, src, sw, sh, ox, oy):
    """把 src 叠到 dst 的 (ox, oy)（dst 是 bytes，返回新的 bytes；source-over）。"""
    out = bytearray(dst)
    for y in range(sh):
        dy = oy + y
        if dy < 0 or dy >= dh:
            continue
        for x in range(sw):
            dx = ox + x
            if dx < 0 or dx >= dw:
                continue
            s = (y * sw + x) * 4
            sa = src[s + 3] / 255.0
            if sa <= 0:
                continue
            d = (dy * dw + dx) * 4
            da = out[d + 3] / 255.0
            oa = sa + da * (1 - sa)
            if oa <= 0:
                continue
            for c in range(3):
                out[d + c] = int(round((src[s + c] * sa + out[d + c] * da * (1 - sa)) / oa))
            out[d + 3] = int(round(oa * 255))
    return bytes(out)


def white_to_alpha(width, height, rgba, threshold=245):
    """
    把**纯白底**的 RGB 图转成透明底 RGBA（保留抗锯齿边缘）。

    做法：把"离白有多远"当作 alpha 的来源（`a = 1 - min(r,g,b)/255` 太粗，
    会连浅蓝也压成半透明），改用**与白的距离**：`d = max(255-r, 255-g, 255-b)`；
    边缘像素的 d 介于 0..255 之间 ⇒ alpha = d。颜色则按 alpha 反解回"原色"
    （`c = (px - (1-a)*255) / a`），于是半透明边缘在白底上合成回去仍是原像素。
    """
    out = bytearray(width * height * 4)
    for i in range(width * height):
        r, g, b = rgba[i * 4], rgba[i * 4 + 1], rgba[i * 4 + 2]
        d = max(255 - r, 255 - g, 255 - b)
        if d <= 255 - threshold:
            continue  # 几乎纯白 ⇒ 全透明
        a = min(255, d) / 255.0
        out[i * 4 + 3] = int(round(a * 255))
        for c, v in enumerate((r, g, b)):
            out[i * 4 + c] = max(0, min(255, int(round((v - (1 - a) * 255.0) / a))))
    return bytes(out)

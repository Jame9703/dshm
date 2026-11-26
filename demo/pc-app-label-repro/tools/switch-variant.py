#!/usr/bin/env python3
"""切换复现变体：A=PC 应用（tablet+2in1），B=普通平板（仅 tablet）。

用法：python3 tools/switch-variant.py A|B
注意：切换后需重新构建，且两个变体不要同时安装在同一台设备。
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODULE = ROOT / 'entry' / 'src' / 'main' / 'module.json5'

VARIANTS = {
    'A': ['tablet', '2in1'],
    'B': ['tablet'],
}

def main() -> None:
    if len(sys.argv) != 2 or sys.argv[1] not in VARIANTS:
        print('usage: python3 tools/switch-variant.py A|B')
        raise SystemExit(2)
    variant = sys.argv[1]
    text = MODULE.read_text(encoding='utf-8')
    values = VARIANTS[variant]
    replacement = '"deviceTypes": [\n      ' + ',\n      '.join('"' + v + '"' for v in values) + '\n    ]'
    new, count = re.subn(r'"deviceTypes":\s*\[[\s\S]*?\]', replacement, text, count=1)
    if count != 1:
        raise SystemExit('deviceTypes anchor not found')
    MODULE.write_text(new, encoding='utf-8')
    print('switched to variant', variant, 'deviceTypes=', values)

if __name__ == '__main__':
    main()

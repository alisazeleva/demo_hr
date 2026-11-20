"""Cut the ChatGPT contact sheets into one profile picture per employee.

Reads   images/sheets/sheet_01.png ... sheet_10.png   (4 x 4 grid, cell 1 top-left, then left to right, top to bottom)
and     images/sheet_map.csv                          (Sheet, Cell, EmployeeNumber, Gender, Nationality, Age)
Writes  images/profiles/EMP-000001.jpg ...            (160 x 160 px, JPEG under 20 KB)

Only the cells listed in sheet_map.csv are cut, so the empty cells 8 to 16 of sheet 10 are skipped.
A sheet that is not square is reported (its cells are still cut, each cropped to a centred square).

Usage (from the repo root):
    python images/crop_sheets.py
    python images/crop_sheets.py --margin 0.06       # cut 6 % off every side of each cell
    python images/crop_sheets.py --size 160 --max-kb 20

Needs: pip install pillow
"""
import argparse
import csv
import io
import os
import sys
from collections import defaultdict

try:
    from PIL import Image
except ImportError:
    sys.exit('Pillow is missing: pip install pillow')

GRID = 4


def cell_box(width, height, cell, margin):
    """Box (left, top, right, bottom) of a cell, shrunk by the margin and made square around its centre."""
    row, col = divmod(cell - 1, GRID)
    cw, ch = width / GRID, height / GRID
    cx, cy = (col + 0.5) * cw, (row + 0.5) * ch
    side = min(cw, ch) * (1 - 2 * margin)
    half = side / 2
    return (round(cx - half), round(cy - half), round(cx + half), round(cy + half))


def save_jpeg(img, path, max_bytes):
    """Save as JPEG with the highest quality that keeps the file under max_bytes; return (bytes, quality)."""
    data, quality = b'', 90
    for quality in range(90, 29, -5):
        buf = io.BytesIO()
        img.save(buf, 'JPEG', quality=quality, optimize=True, progressive=True)
        data = buf.getvalue()
        if len(data) <= max_bytes:
            break
    with open(path, 'wb') as f:
        f.write(data)
    return len(data), quality


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--root', default=here, help='images folder (default: the folder of this script)')
    ap.add_argument('--margin', type=float, default=0.03, help='inner margin per cell side as a fraction of the cell (default 0.03)')
    ap.add_argument('--size', type=int, default=160, help='output size in pixels (default 160)')
    ap.add_argument('--max-kb', type=float, default=20, help='maximum JPEG size in KB (default 20)')
    args = ap.parse_args()
    if not 0 <= args.margin < 0.5:
        sys.exit('--margin must be from 0 to 0.49')

    sheets_dir = os.path.join(args.root, 'sheets')
    out_dir = os.path.join(args.root, 'profiles')
    os.makedirs(out_dir, exist_ok=True)
    max_bytes = int(args.max_kb * 1024)

    by_sheet = defaultdict(list)
    with open(os.path.join(args.root, 'sheet_map.csv'), encoding='utf-8', newline='') as f:
        for r in csv.DictReader(f):
            by_sheet[int(r['Sheet'])].append((int(r['Cell']), r['EmployeeNumber']))

    written = problems = 0
    for sheet in sorted(by_sheet):
        path = os.path.join(sheets_dir, f'sheet_{sheet:02d}.png')
        if not os.path.exists(path):
            print(f'sheet {sheet:02d}: {path} not found, skipped')
            problems += 1
            continue
        img = Image.open(path).convert('RGB')
        w, h = img.size
        if w != h:
            print(f'sheet {sheet:02d}: NOT SQUARE ({w} x {h}); check the picture before using it')
            problems += 1
        for cell, emp in sorted(by_sheet[sheet]):
            face = img.crop(cell_box(w, h, cell, args.margin)).resize((args.size, args.size), Image.LANCZOS)
            size, quality = save_jpeg(face, os.path.join(out_dir, f'{emp}.jpg'), max_bytes)
            written += 1
            if size > max_bytes:
                print(f'{emp}: {size / 1024:.1f} KB is over the limit even at quality {quality}')
                problems += 1
        print(f'sheet {sheet:02d}: {len(by_sheet[sheet])} faces cut')
    print(f'{written} pictures written to {out_dir}; {problems} problem(s)')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())

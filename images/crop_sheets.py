"""Cut the ChatGPT contact sheets into one profile picture per employee.

Reads   images/sheets/sheet_01.png ... sheet_10.png   (4 x 4 grid, cell 1 top-left, then left to right, top to bottom)
and     images/sheet_map.csv                          (Sheet, Cell, EmployeeNumber, Gender, Nationality, Age)
Writes  images/profiles/EMP-000001.jpg ...            (240 x 240 px, JPEG under 20 KB)

Only the cells listed in sheet_map.csv are cut, so the empty cells 8 to 16 of sheet 10 are skipped.
A sheet that is not square is reported (its cells are still cut, each cropped to a centred square).

Usage (from the repo root):
    python images/crop_sheets.py
    python images/crop_sheets.py --margin 0.06       # cut 6 % off every side of each cell (default 0.01)
    python images/crop_sheets.py --top-pad 0.12      # more empty space above the head (default 0.05)
    python images/crop_sheets.py --top-pad 0         # no extra space
    python images/crop_sheets.py --size 240 --max-kb 20

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


def background_colour(img, left, top, side):
    """Median colour of two small patches in the top corners of a cell (the plain grey backdrop)."""
    patches = [(left + 0.02 * side, left + 0.14 * side), (left + 0.86 * side, left + 0.98 * side)]
    px = []
    for x0, x1 in patches:
        patch = img.crop((round(x0), round(top + 0.02 * side), round(x1), round(top + 0.06 * side)))
        pix = patch.load()
        px.extend(pix[x, y] for x in range(patch.width) for y in range(patch.height))
    return tuple(sorted(c[i] for c in px)[len(px) // 2] for i in range(3))


def cut_cell(img, cell, margin, top_pad):
    """Cut one cell as a square of side L = cell side minus the margin on both sides, then add top_pad * L of empty
    backdrop above the head. The sheets leave almost no room above the heads, so the space is painted with the
    cell's own background colour (with a soft edge) and the same amount is dropped from the bottom (shoulders)."""
    w, h = img.size
    row, col = divmod(cell - 1, GRID)
    cw, ch = w / GRID, h / GRID
    side = min(cw, ch)
    left, top = col * cw + (cw - side) / 2, row * ch + (ch - side) / 2
    length = round(side * (1 - 2 * margin))
    x0 = round(left + (side - length) / 2)
    pad = round(length * top_pad)
    bg = background_colour(img, left, top, side)
    out = Image.new('RGB', (length, length), bg)
    # the photo part: from the top of the cell (no margin there, the padding replaces it) down to fill the square
    piece = img.crop((x0, round(top), x0 + length, round(top) + length - pad))
    mask = Image.new('L', piece.size, 255)
    fade = max(1, round(length * 0.03))
    for y in range(min(fade, piece.height)):
        mask.paste(round(255 * (y + 1) / (fade + 1)), (0, y, piece.width, y + 1))
    out.paste(piece, (0, pad), mask)
    return out


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
    ap.add_argument('--margin', type=float, default=0.01, help='inner margin per cell side as a fraction of the cell (default 0.01)')
    ap.add_argument('--top-pad', type=float, default=0.05, help='empty space added above the head as a fraction of the picture (default 0.05)')
    ap.add_argument('--size', type=int, default=240, help='output size in pixels (default 240)')
    ap.add_argument('--max-kb', type=float, default=20, help='maximum JPEG size in KB (default 20)')
    args = ap.parse_args()
    if not 0 <= args.margin < 0.5:
        sys.exit('--margin must be from 0 to 0.49')
    if not 0 <= args.top_pad < 0.5:
        sys.exit('--top-pad must be from 0 to 0.49')

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
            face = cut_cell(img, cell, args.margin, args.top_pad).resize((args.size, args.size), Image.LANCZOS)
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

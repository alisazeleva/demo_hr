# Profile pictures

The 151 profile pictures are fictional faces made in an image tool (ChatGPT), 16 per contact sheet, then cut into one JPEG per employee and loaded into Power BI. The database stores only the file names (`EMP-######.jpg`, set by `sql/12_assign_profile_pictures.sql`).

| Path | What it is |
| --- | --- |
| `prompts/sheet_01.txt` ... `sheet_10.txt` | The prompt for each sheet (16 people per sheet, sheet 10 has 7 people and 9 empty cells) |
| `sheet_map.csv` | Maps Sheet and Cell to EmployeeNumber (cell 1 is top-left, then left to right, top to bottom) |
| `sheets/sheet_NN.png` | The sheet saved from the image tool |
| `crop_sheets.py` | Cuts the sheets into pictures |
| `profiles/EMP-######.jpg` | The pictures: 240 x 240 px, JPEG, under 20 KB (the circle on page 7 is 120 px wide, so this is sharp on high-resolution screens; the sheets hold about 313 px per face, which is the most they can give) |

## Add a sheet

1. **Make the sheet.** Paste the whole of `prompts/sheet_NN.txt` into ChatGPT and ask for the image. It must be **square with exactly 4 x 4 faces** (sheet 10: 7 faces in cells 1 to 7, the rest empty plain grey). If a sheet has the wrong count or a bad face, ask again; one face cannot be swapped without redoing the sheet.
2. **Save it** as `images/sheets/sheet_NN.png` (two digits, for example `sheet_02.png`).
3. **Cut it.** From the repository root:
   ```
   python images/crop_sheets.py
   ```
   It needs `pip install pillow`. It cuts every sheet that exists in `images/sheets/`, skips the missing ones, and rewrites `images/profiles/` for them (re-running is safe and gives identical files). It reports a sheet that is not square.
   - The sheets leave almost no room above the heads, so the script adds empty backdrop above them: `--top-pad` (default 0.05, taken from the bottom of the picture) and trims the sides with `--margin` (default 0.01). For example `python images/crop_sheets.py --top-pad 0.07`. Use the same values for every sheet so the faces look alike.
4. **Look at the result.** Open `images/profiles/` and check that each face is whole and matches its prompt line (gender, rough age, hair, glasses or beard). The first pictures of a sheet, such as `EMP-000017.jpg` to `EMP-000032.jpg` for sheet 2, are the quickest check.
5. **Copy the pictures to the folder Power BI reads**, `C:\DemoHR\profiles` (a folder outside the repo, so that no personal path is stored in the model):
   ```
   Copy-Item images\profiles\*.jpg C:\DemoHR\profiles\
   ```
6. **Refresh in Power BI Desktop.** Press Refresh (or refresh only the `ProfilePictures` table). The table gets one row per file; employees without a file simply have no picture.
7. **Check page 7.** Drill through to an employee from the new sheet and see the picture in the circle. Then save with no slicer or drill-through selection left active.
8. **Nothing to commit for the pictures.** Both `images/sheets/` and `images/profiles/` are git-ignored: the sheets are 2 to 3 MB each, and the cut pictures can be rebuilt from the sheets. Only the prompts, `sheet_map.csv` and `crop_sheets.py` are in git. Run `python -m pytest tests -q` before committing other changes. The pictures exist only on your computer, so **keep a backup** of `images/sheets/` (the copies in `C:\DemoHR\profiles` already back up the cut pictures). Check the image tool's terms before sharing the pictures in any other way.

## How it is wired in Power BI

- `ProfilePicturesFolder` (parameter, `C:\DemoHR\profiles`) is the folder with the JPEGs.
- The `ProfilePictures` table reads every `.jpg` there with Power Query and turns each into a base64 text (`data:image/jpeg;base64,...`) with data category Image URL. It is related many-to-one to `DimEmployee[ProfileImageFileName]`, so the selected employee filters it.
- The measure `Profile Picture` (`SELECTEDVALUE(ProfilePictures[Picture])`) is the image fill of the circle in the page 7 header.
- A model text cell holds about 32,000 characters and base64 adds a third, so keep every JPEG small (the script keeps them under 20 KB; typical files are 6 to 8 KB).

## If something goes wrong

- **No pictures after Refresh:** check that the files are in `C:\DemoHR\profiles`, are named exactly `EMP-######.jpg`, and that the parameter points there.
- **"Duplicate value" when opening the project:** the saved data cache is out of date. Close Desktop and delete `Acme HR Demo.SemanticModel/.pbi/cache.abf` (it is git-ignored and is rebuilt on Refresh).
- **A face is cut at the top or bottom:** change `--top-pad` and `--margin`, and run the script again for all sheets.
- **Wrong face on a person:** the map in `sheet_map.csv` follows the prompt order. Check the prompt line for that cell, then redo the sheet.

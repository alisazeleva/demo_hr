# tools

Helper scripts for the Power BI report (Python 3). They only read and write files in this repository.

| Script | Purpose |
| --- | --- |
| `validate_pbir.py` | Validates every PBIR JSON file against Microsoft's published schemas. Run after every report edit: `python tools/validate_pbir.py`. Needs `pip install jsonschema referencing` and internet access (schemas are downloaded). |
| `build_career.py` | Generates the visuals of page 3 (Career) and copies the page shell from page 2. Template for building new pages. It overwrites the page's visuals. |
| `build_home.py` | First draft of page 0 (Home) from `desing/0 Home@1x.png`: left menu and info pop-up copied from Workforce, header banner, seven page cards, how-to card, Info ON/OFF bookmarks. Deletes and rewrites the Home page; do not run it over the page after hand adjustments. |
| `build_comp.py`, `build_perf.py`, `build_leave.py`, `build_profile.py` | First drafts of pages 4 to 7. The pages were adjusted by hand afterwards; do not run them over the current pages. The drafts use fixed years (for example 2024 to 2026) in visual filters and subtitles; the current pages use `DimDate[Years Before Reference]` instead (see CLAUDE.md). |
| `build_org.py` | Earlier generator of page 2 (Organization), kept as a template. The page was adjusted by hand afterwards; do not run it over the current page. |

See "Power BI working notes" in `CLAUDE.md` for the workflow (model changes through the MCP server, export to TMDL, close Desktop without saving).

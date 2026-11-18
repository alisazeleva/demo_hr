# tools

Helper scripts for the Power BI report (Python 3). They only read and write files in this repository.

| Script | Purpose |
| --- | --- |
| `validate_pbir.py` | Validates every PBIR JSON file against Microsoft's published schemas. Run after every report edit: `python tools/validate_pbir.py`. Needs `pip install jsonschema referencing` and internet access (schemas are downloaded). |
| `build_career.py` | Generates the visuals of page 3 (Career) and copies the page shell from page 2. Template for building new pages. It overwrites the page's visuals. |
| `build_org.py` | Earlier generator of page 2 (Organization), kept as a template. The page was adjusted by hand afterwards; do not run it over the current page. |

See "Power BI working notes" in `CLAUDE.md` for the workflow (model changes through the MCP server, export to TMDL, close Desktop without saving).

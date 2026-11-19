# demo_hr


## Validation note

`sql/99_full_validation.sql` runs 49 checks. The 3 picture checks are expected to fail (46 of 49 pass) because the profile pictures are not created: script 12 is skipped and the database stores only the `EMP-######.jpg` file names.

# SCAD Reporting Transformation - Data Integrations

This repository contains the transformation scripts (`.sql`, `.py`, `.ipynb`) that perform data processing for SCAD reporting.

**Important Note on Orchestration:**
The scripts in this repository are executed by the Databricks jobs defined in the upstream orchestration repository (`scad_reporting_transformation`). The orchestrator dynamically discovers and runs these files based on their location.

## Directory Structure

All transformation scripts must be placed within the `transformations/` directory, organized by schedule and execution phase:

```
transformations/
└── <schedule_group>/         # e.g., hourly, daily, weekly
    └── <phase_prefix>_<custom_name>/  # e.g., pre_sdp_data_prep, sdp_01, post_sdp_cleanup
        ├── my_query.sql
        └── my_script.py
```

### Execution Details

1. **Schedule Group (`<schedule_group>`):** Dictates *when* the transformations run (e.g., `hourly`, `daily`, `weekly`).
2. **Phase Prefix (`<phase_prefix>`):** Dictates the *stage* within the job. Valid prefixes are `pre_sdp_`, `sdp_`, and `post_sdp_`. The `<custom_name>` suffix is optional (e.g. `pre_sdp_1`, `pre_sdp_2`).
3. **Concurrent Execution:** Files located in the *same* phase folder (e.g., `transformations/hourly/pre_sdp_1/`) are executed **concurrently** by the orchestrator. They must be completely standalone and cannot depend on the output of other scripts in the same folder.
4. **Parameters:** The orchestrator passes the `{catalog}` name to all scripts.
   - For `.sql` files, use string formatting directly: `SELECT * FROM {catalog}.schema.table`.
   - For `.py` or `.ipynb` files, grab it via widgets: `catalog = dbutils.widgets.get("catalog")`.

## Developing New Transformations

When building new transformations:
- Ensure the script runs independently.
- Do not import other scripts from this repository (they are not deployed as a standard python package).
- For local testing, mock the `{catalog}` parameter accordingly.

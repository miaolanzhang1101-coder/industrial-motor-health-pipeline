# Motor Fault ETL

Python ETL pipeline for converting raw motor vibration signals into structured features stored in PostgreSQL.

## Pipeline

1. Read CWRU-style `.mat` vibration files.
2. Extract the drive-end vibration signal.
3. Segment signals into overlapping windows.
4. Calculate statistical and frequency-domain features.
5. Store source-file metadata and signal features in PostgreSQL.
6. Run SQL analysis against the resulting dataset.

## PostgreSQL

The pipeline uses PostgreSQL as its persistent analytical database.

`schema.sql` creates:

- `source_files` — source-file metadata and pipeline load status
- `signal_windows` — extracted features for each signal window

The tables are connected through a foreign key:

`source_files.file_id → signal_windows.file_id`

The schema also uses unique constraints and indexes to prevent duplicate windows and support common query paths.

## Run

Install dependencies:

```bash
python3 -m pip install -r requirements.txt

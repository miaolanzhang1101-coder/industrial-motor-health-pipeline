# Industrial Motor Health Pipeline

An end-to-end data pipeline for processing industrial motor vibration signals and preparing structured data for fault analysis and classification.

The pipeline extracts CWRU-style MATLAB vibration data, transforms raw signals into fixed-size windows and statistical/frequency-domain features, and loads the results into PostgreSQL for analysis.

## PostgreSQL

PostgreSQL is used as the analytical store for the pipeline.

The database is organized into two related tables:

- `source_files` — tracks source files, processing status, machine condition, and window counts.
- `signal_windows` — stores extracted signal features for each processed window.

The schema uses primary keys, foreign keys, unique constraints, indexes, and status fields to support reliable loading and downstream analysis.

The ETL pipeline connects to PostgreSQL through SQLAlchemy and performs batched inserts. Reprocessing a source file replaces its existing windows rather than creating duplicate records.

## Pipeline

CWRU MATLAB files  
→ signal extraction  
→ windowing  
→ feature extraction  
→ PostgreSQL  
→ SQL analysis

## Repository

```text
motor-fault-etl/
  etl_pipeline.py      ETL pipeline
  schema.sql            PostgreSQL schema
  queries.sql           Analytical SQL queries
  download_cwru.sh     Dataset download
  requirements.txt      Python dependencies
  README.md             Pipeline documentation

5005-Project02.ipynb    Data processing and exploration
5005-P02-classification.ipynb
                        Fault classification
part01.md               Project notes

# Industrial Motor Health Pipeline

An end-to-end data pipeline for transforming raw industrial motor sensor data into structured datasets for fault analysis and machine learning.

The project uses CWRU bearing vibration data and covers data ingestion, transformation, validation, feature preparation, and SQL-based storage.

## Pipeline

Raw `.mat` sensor files are downloaded and processed into structured records that can be queried and used for downstream fault classification.

The pipeline handles signal extraction, metadata normalization, transformation, and loading into a PostgreSQL database.

## Stack

**Python**  
NumPy · SciPy · pandas

**Data Engineering**  
ETL · Data validation · Data transformation · Feature preparation

**Database**  
PostgreSQL · SQL · Relational data modeling

**Infrastructure**  
Shell · Docker / Dev Container

## Repository

```text
motor-fault-etl/
  download_cwru.sh     Dataset download
  etl_pipeline.py      ETL processing pipeline
  schema.sql            Database schema
  queries.sql           Analysis queries
  requirements.txt      Python dependencies
  README.md             Pipeline documentation

5005-Project02.ipynb     Data processing and exploration
5005-P02-classification.ipynb
                         Fault classification


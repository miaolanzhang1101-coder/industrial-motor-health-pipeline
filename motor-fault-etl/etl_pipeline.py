"""
Motor Fault Detection — End-to-End ETL Pipeline
=================================================

Extract  : read raw vibration signals from CWRU-style .mat files
Transform: segment signals into fixed-size windows, extract time/frequency-domain features
Load     : write a dimension row per source file and a fact row per window into Postgres

Design notes (for interview talking points):
- Idempotent: re-running on the same file is a no-op if it's already loaded successfully.
  This matters because a real pipeline gets re-triggered (retries, backfills, scheduler
  restarts) and should never silently duplicate data.
- Batched writes: features are buffered and inserted in batches rather than row-by-row,
  since row-by-row inserts are the most common beginner mistake that kills pipeline
  throughput at any real scale.
- Failure isolation: one malformed file should not take down the whole run. Each file's
  outcome (loaded / failed / reason) is recorded in `source_files`, not just printed to
  stdout — that's the difference between a script and a pipeline you can operate.

Usage:
    python etl_pipeline.py --data-dir data/raw --db-url postgresql://user:pass@localhost:5432/motors
"""

import argparse
import logging
import os
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.io import loadmat
from scipy.stats import kurtosis
from sqlalchemy import create_engine, text

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
)
log = logging.getLogger("motor_etl")


# ---------------------------------------------------------------------------
# EXTRACT
# ---------------------------------------------------------------------------

def load_signal(filepath: Path):
    """Read the drive-end vibration channel out of a .mat file, with a fallback
    to the first non-metadata array if the expected key isn't present."""
    mat = loadmat(filepath)

    de_keys = [k for k in mat.keys() if "DE_time" in k]
    if de_keys:
        return mat[de_keys[0]].flatten()

    for key in mat:
        if not key.startswith("__"):
            data = np.array(mat[key]).squeeze().reshape(-1)
            if len(data) > 0:
                return data

    return None


def get_label(filepath: Path) -> str:
    name = filepath.stem.upper()
    if name.startswith("NORMAL") or name.isdigit():
        return "normal"
    elif any(x in name for x in ["IR", "OR", "B", "BALL"]):
        return "fault"
    return "normal"


# ---------------------------------------------------------------------------
# TRANSFORM
# ---------------------------------------------------------------------------

def segment_signal(signal, window_size: int = 2048, stride: int = 512):
    if signal is None:
        return []

    signal = np.asarray(signal).flatten()
    if len(signal) < window_size:
        return []

    return [
        signal[start:start + window_size]
        for start in range(0, len(signal) - window_size + 1, stride)
    ]


def extract_features(segment, sampling_rate: int = 12000) -> dict:
    segment = np.asarray(segment).flatten()
    features = {}

    rms = np.sqrt(np.mean(segment ** 2))
    peak = np.max(np.abs(segment))

    features["mean"] = float(np.mean(segment))
    features["std"] = float(np.std(segment))
    features["rms"] = float(rms)
    features["peak"] = float(peak)
    features["crest_factor"] = float(peak / (rms + 1e-10))
    features["kurtosis"] = float(kurtosis(segment))

    fft_vals = np.fft.rfft(segment)
    magnitude = np.abs(fft_vals)
    fft_freq = np.fft.rfftfreq(len(segment), d=1 / sampling_rate)

    min_len = min(len(magnitude), len(fft_freq))
    magnitude = magnitude[:min_len]
    fft_freq = fft_freq[:min_len]

    features["peak_freq"] = float(fft_freq[np.argmax(magnitude)])
    features["spectral_energy"] = float(np.sum(magnitude ** 2))

    return features


# ---------------------------------------------------------------------------
# LOAD
# ---------------------------------------------------------------------------

def already_loaded(engine, filename: str) -> bool:
    """Idempotency check — skip files that loaded successfully in a prior run."""
    with engine.connect() as conn:
        result = conn.execute(
            text("SELECT 1 FROM source_files WHERE filename = :fn AND load_status = 'loaded'"),
            {"fn": filename},
        ).fetchone()
    return result is not None


def upsert_source_file(engine, filename: str, machine_condition: str,
                        sampling_rate: int, n_windows: int, n_skipped: int,
                        status: str, error: str | None = None) -> int:
    """Insert or update the dimension row for a file; returns file_id."""
    with engine.begin() as conn:
        conn.execute(
            text("""
                INSERT INTO source_files
                    (filename, machine_condition, sampling_rate_hz, n_windows, n_skipped,
                     load_status, load_error, loaded_at)
                VALUES
                    (:filename, :condition, :rate, :n_windows, :n_skipped, :status, :error, now())
                ON CONFLICT (filename) DO UPDATE SET
                    machine_condition = EXCLUDED.machine_condition,
                    sampling_rate_hz  = EXCLUDED.sampling_rate_hz,
                    n_windows         = EXCLUDED.n_windows,
                    n_skipped         = EXCLUDED.n_skipped,
                    load_status       = EXCLUDED.load_status,
                    load_error        = EXCLUDED.load_error,
                    loaded_at         = now()
            """),
            {
                "filename": filename, "condition": machine_condition, "rate": sampling_rate,
                "n_windows": n_windows, "n_skipped": n_skipped, "status": status, "error": error,
            },
        )
        file_id = conn.execute(
            text("SELECT file_id FROM source_files WHERE filename = :fn"),
            {"fn": filename},
        ).scalar_one()
    return file_id


def load_windows(engine, file_id: int, rows: list[dict]):
    """Batch-insert feature rows for one file. Clears any prior windows for that
    file first, so re-processing a file is a clean replace, not an append."""
    if not rows:
        return

    df = pd.DataFrame(rows)
    df.insert(0, "file_id", file_id)

    with engine.begin() as conn:
        conn.execute(text("DELETE FROM signal_windows WHERE file_id = :fid"), {"fid": file_id})
        df.to_sql("signal_windows", conn, if_exists="append", index=False, method="multi", chunksize=1000)


# ---------------------------------------------------------------------------
# ORCHESTRATION
# ---------------------------------------------------------------------------

def process_file(engine, filepath: Path, window_size: int, stride: int,
                  sampling_rate: int, skip_if_loaded: bool) -> None:
    filename = filepath.name

    if skip_if_loaded and already_loaded(engine, filename):
        log.info("SKIP (already loaded): %s", filename)
        return

    try:
        signal = load_signal(filepath)
        if signal is None or len(signal) == 0:
            upsert_source_file(engine, filename, get_label(filepath), sampling_rate,
                                0, 0, status="failed", error="empty or unreadable signal")
            log.warning("Skipped (no signal): %s", filename)
            return

        segments = segment_signal(signal, window_size, stride)
        if not segments:
            upsert_source_file(engine, filename, get_label(filepath), sampling_rate,
                                0, 0, status="failed", error="too short to segment")
            log.warning("Skipped (too short): %s", filename)
            return

        label = get_label(filepath)
        rows = []
        for i, seg in enumerate(segments):
            feats = extract_features(seg, sampling_rate)
            feats["window_index"] = i
            feats["label"] = label
            rows.append(feats)

        file_id = upsert_source_file(engine, filename, label, sampling_rate,
                                      n_windows=len(rows), n_skipped=0, status="loaded")
        load_windows(engine, file_id, rows)
        log.info("Loaded %s: %d windows", filename, len(rows))

    except Exception as e:
        upsert_source_file(engine, filename, get_label(filepath), sampling_rate,
                            0, 0, status="failed", error=str(e))
        log.error("Error processing %s: %s", filename, e)


def run_pipeline(data_dir: str, db_url: str, window_size: int = 2048,
                  stride: int = 512, sampling_rate: int = 12000,
                  incremental: bool = True):
    engine = create_engine(db_url)

    with engine.begin() as conn:
        conn.execute(text(Path(__file__).with_name("schema.sql").read_text()))

    mat_files = list(Path(data_dir).rglob("*.mat"))
    log.info("Found %d .mat files in %s", len(mat_files), data_dir)

    for filepath in mat_files:
        process_file(engine, filepath, window_size, stride, sampling_rate,
                     skip_if_loaded=incremental)

    with engine.connect() as conn:
        total_windows = conn.execute(text("SELECT count(*) FROM signal_windows")).scalar_one()
        total_files = conn.execute(text("SELECT count(*) FROM source_files WHERE load_status = 'loaded'")).scalar_one()
    log.info("Run complete: %d files loaded, %d total windows in signal_windows", total_files, total_windows)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Motor fault detection ETL pipeline")
    parser.add_argument("--data-dir", required=True, help="Directory containing .mat files")
    parser.add_argument("--db-url", required=True, help="SQLAlchemy Postgres URL")
    parser.add_argument("--window-size", type=int, default=2048)
    parser.add_argument("--stride", type=int, default=512)
    parser.add_argument("--sampling-rate", type=int, default=12000)
    parser.add_argument("--full-reload", action="store_true",
                         help="Reprocess all files, even ones already loaded")
    args = parser.parse_args()

    run_pipeline(
        data_dir=args.data_dir,
        db_url=args.db_url,
        window_size=args.window_size,
        stride=args.stride,
        sampling_rate=args.sampling_rate,
        incremental=not args.full_reload,
    )
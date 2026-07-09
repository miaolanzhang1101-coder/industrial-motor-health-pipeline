-- Motor Fault Detection ETL — Schema
-- Dimension table: one row per source .mat file
CREATE TABLE IF NOT EXISTS source_files (
    file_id            SERIAL PRIMARY KEY,
    filename           TEXT NOT NULL UNIQUE,
    machine_condition  TEXT NOT NULL,          -- inferred label: 'normal' or 'fault'
    sampling_rate_hz   INTEGER NOT NULL DEFAULT 12000,
    n_windows          INTEGER NOT NULL DEFAULT 0,
    n_skipped          INTEGER NOT NULL DEFAULT 0,
    load_status        TEXT NOT NULL DEFAULT 'pending',  -- pending | loaded | failed
    load_error         TEXT,
    loaded_at          TIMESTAMP DEFAULT now()
);

-- Fact table: one row per signal window (segment) extracted from a file
CREATE TABLE IF NOT EXISTS signal_windows (
    window_id        BIGSERIAL PRIMARY KEY,
    file_id           INTEGER NOT NULL REFERENCES source_files(file_id),
    window_index      INTEGER NOT NULL,        -- position of this window within its file
    mean              DOUBLE PRECISION,
    std               DOUBLE PRECISION,
    rms               DOUBLE PRECISION,
    peak              DOUBLE PRECISION,
    crest_factor      DOUBLE PRECISION,
    kurtosis          DOUBLE PRECISION,
    peak_freq         DOUBLE PRECISION,
    spectral_energy   DOUBLE PRECISION,
    label             TEXT NOT NULL CHECK (label IN ('normal', 'fault')),
    created_at        TIMESTAMP DEFAULT now(),

    UNIQUE (file_id, window_index)              -- guards against duplicate re-loads
);

CREATE INDEX IF NOT EXISTS idx_signal_windows_file_id ON signal_windows(file_id);
CREATE INDEX IF NOT EXISTS idx_signal_windows_label    ON signal_windows(label);
CREATE INDEX IF NOT EXISTS idx_signal_windows_energy   ON signal_windows(spectral_energy);
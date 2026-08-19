-- Industrial Motor Health Pipeline
-- PostgreSQL schema for source files and extracted signal windows

CREATE TABLE IF NOT EXISTS source_files (
    file_id            SERIAL PRIMARY KEY,
    filename           TEXT NOT NULL UNIQUE,
    machine_condition  TEXT NOT NULL
        CHECK (machine_condition IN ('normal', 'fault')),
    sampling_rate_hz   INTEGER NOT NULL DEFAULT 12000,
    n_windows          INTEGER NOT NULL DEFAULT 0,
    n_skipped          INTEGER NOT NULL DEFAULT 0,
    load_status        TEXT NOT NULL DEFAULT 'pending'
        CHECK (load_status IN ('pending', 'loaded', 'failed')),
    load_error         TEXT,
    created_at         TIMESTAMP NOT NULL DEFAULT now(),
    loaded_at          TIMESTAMP
);

CREATE TABLE IF NOT EXISTS signal_windows (
    window_id        BIGSERIAL PRIMARY KEY,
    file_id          INTEGER NOT NULL
                     REFERENCES source_files(file_id),
    window_index     INTEGER NOT NULL,
    mean             DOUBLE PRECISION,
    std              DOUBLE PRECISION,
    rms              DOUBLE PRECISION,
    peak             DOUBLE PRECISION,
    crest_factor     DOUBLE PRECISION,
    kurtosis         DOUBLE PRECISION,
    peak_freq        DOUBLE PRECISION,
    spectral_energy  DOUBLE PRECISION,
    label             TEXT NOT NULL
                     CHECK (label IN ('normal', 'fault')),
    created_at       TIMESTAMP NOT NULL DEFAULT now(),

    UNIQUE (file_id, window_index)
);

CREATE INDEX IF NOT EXISTS idx_signal_windows_file_id
    ON signal_windows(file_id);

CREATE INDEX IF NOT EXISTS idx_signal_windows_label
    ON signal_windows(label);

CREATE INDEX IF NOT EXISTS idx_signal_windows_file_label
    ON signal_windows(file_id, label);

CREATE INDEX IF NOT EXISTS idx_signal_windows_energy
    ON signal_windows(spectral_energy);

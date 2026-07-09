-- Motor Fault Detection ETL — Example Analytical Queries
-- Each query maps to a specific interview competency, noted in the comment above it.

-- ============================================================
-- 1. Aggregation / GROUP BY — "Do fault windows look different from normal ones?"
--    Validates whether the extracted features actually separate the two classes.
-- ============================================================
SELECT
    label,
    COUNT(*)                           AS n_windows,
    ROUND(AVG(kurtosis)::numeric, 3)   AS avg_kurtosis,
    ROUND(AVG(crest_factor)::numeric, 3) AS avg_crest_factor,
    ROUND(AVG(spectral_energy)::numeric, 1) AS avg_spectral_energy
FROM signal_windows
GROUP BY label
ORDER BY label;


-- ============================================================
-- 2. JOIN + GROUP BY — "Which source files carry the most fault windows?"
--    Fact table joined back to its dimension for a file-level rollup.
-- ============================================================
SELECT
    sf.filename,
    sf.machine_condition,
    COUNT(*) FILTER (WHERE sw.label = 'fault') AS fault_windows,
    COUNT(*)                                    AS total_windows,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE sw.label = 'fault') / COUNT(*), 1
    ) AS fault_pct
FROM signal_windows sw
JOIN source_files sf ON sf.file_id = sw.file_id
GROUP BY sf.filename, sf.machine_condition
HAVING COUNT(*) FILTER (WHERE sw.label = 'fault') > 0
ORDER BY fault_pct DESC;


-- ============================================================
-- 3. Percentile / statistical threshold — "Which windows look anomalous
--    even within files labeled 'normal'?" (a data-quality / QA style query)
-- ============================================================
WITH thresholds AS (
    SELECT
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY spectral_energy) AS p95_energy
    FROM signal_windows
    WHERE label = 'normal'
)
SELECT sw.window_id, sf.filename, sw.window_index, sw.spectral_energy
FROM signal_windows sw
JOIN source_files sf ON sf.file_id = sw.file_id
CROSS JOIN thresholds t
WHERE sw.label = 'normal'
  AND sw.spectral_energy > t.p95_energy
ORDER BY sw.spectral_energy DESC
LIMIT 20;


-- ============================================================
-- 4. Window function (LAG) — "Is spectral energy trending upward across
--    consecutive windows within the same file?" — an early-warning signal,
--    the kind of query that would back a "watch" severity tier in a console.
-- ============================================================
SELECT
    file_id,
    window_index,
    spectral_energy,
    spectral_energy - LAG(spectral_energy) OVER (
        PARTITION BY file_id ORDER BY window_index
    ) AS energy_delta
FROM signal_windows
ORDER BY file_id, window_index;


-- ============================================================
-- 5. Data quality / pipeline health — "How healthy was the last load run?"
--    The kind of query an operator would run against the pipeline's own
--    metadata, not the feature data itself.
-- ============================================================
SELECT
    load_status,
    COUNT(*)              AS n_files,
    SUM(n_windows)         AS total_windows,
    SUM(n_skipped)         AS total_skipped
FROM source_files
GROUP BY load_status;
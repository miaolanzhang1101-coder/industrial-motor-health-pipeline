#!/bin/bash
# CWRU Bearing Dataset — batch downloader
# Covers: Normal Baseline + 12k Drive End Fault Data (Inner Race, Ball, Outer Race@6:00)
#         for fault diameters 0.007", 0.014", 0.021" across all 4 load levels (0-3 HP)
# Total: 4 normal + 36 fault files = 40 files, ~500MB
#
# Usage: bash download_cwru.sh
# Files land in ./data/raw/

set -e
OUT_DIR="data/raw"
mkdir -p "$OUT_DIR"
BASE="https://engineering.case.edu/sites/default/files"

# --- Normal Baseline Data ---
NORMAL_IDS=(97 98 99 100)

# --- 0.007" fault diameter ---
IR007=(105 106 107 108)
B007=(118 119 120 121)
OR007_6=(130 131 132 133)

# --- 0.014" fault diameter ---
IR014=(169 170 171 172)
B014=(185 186 187 188)
OR014_6=(197 198 199 200)

# --- 0.021" fault diameter ---
IR021=(209 210 211 212)
B021=(222 223 224 225)
OR021_6=(234 235 236 237)

ALL_IDS=(
    "${NORMAL_IDS[@]}"
    "${IR007[@]}" "${B007[@]}" "${OR007_6[@]}"
    "${IR014[@]}" "${B014[@]}" "${OR014_6[@]}"
    "${IR021[@]}" "${B021[@]}" "${OR021_6[@]}"
)

echo "Downloading ${#ALL_IDS[@]} .mat files to $OUT_DIR ..."

for id in "${ALL_IDS[@]}"; do
    dest="$OUT_DIR/${id}.mat"
    if [ -f "$dest" ]; then
        echo "SKIP (already exists): ${id}.mat"
        continue
    fi
    echo "Downloading ${id}.mat ..."
    curl -sSf -o "$dest" "$BASE/${id}.mat" || echo "FAILED: ${id}.mat"
    sleep 0.5  # be polite to the server
done

echo "Done. $(ls "$OUT_DIR" | wc -l) files in $OUT_DIR"
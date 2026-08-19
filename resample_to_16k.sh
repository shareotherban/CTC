#!/usr/bin/env bash
#
# resample_to_16k.sh
#
# Batch-converts all .wav files in a folder to 16kHz mono PCM using
# FFmpeg's soxr (SoX Resampler) engine — high-quality polyphase
# resampling with proper anti-aliasing. Skips files already at 16kHz
# (just copies them) so you can safely re-run this on a mixed folder.
#
# Usage:
#   ./resample_to_16k.sh /path/to/my_voice [/path/to/output_folder]
#
# If no output folder is given, it creates one alongside the source,
# named "<source>_16k", so your originals are never overwritten.

set -euo pipefail

SRC_DIR="${1:-./my_voice}"
OUT_DIR="${2:-${SRC_DIR%/}_16k}"

if [ ! -d "$SRC_DIR" ]; then
    echo "Error: source folder not found: $SRC_DIR" >&2
    exit 1
fi

command -v ffmpeg  >/dev/null 2>&1 || { echo "Error: ffmpeg not found on PATH." >&2; exit 1; }
command -v ffprobe >/dev/null 2>&1 || { echo "Error: ffprobe not found on PATH." >&2; exit 1; }

if ! ffmpeg -version | grep -qi "enable-libsoxr"; then
    echo "Warning: this ffmpeg build does not report --enable-libsoxr."
    echo "The soxr resampler may be unavailable; falling back could error out."
    echo "You can check with: ffmpeg -version | grep libsoxr"
fi

mkdir -p "$OUT_DIR"

total=0
converted=0
skipped=0
failed=0

shopt -s nullglob
for f in "$SRC_DIR"/*.wav; do
    total=$((total + 1))
    fname=$(basename "$f")

    src_rate=$(ffprobe -v error -select_streams a:0 \
        -show_entries stream=sample_rate -of csv=p=0 "$f" || echo "")

    if [ -z "$src_rate" ]; then
        echo "  [FAIL] Could not read sample rate: $fname"
        failed=$((failed + 1))
        continue
    fi

    if [ "$src_rate" = "16000" ]; then
        echo "  [SKIP] Already 16kHz: $fname"
        cp "$f" "$OUT_DIR/$fname"
        skipped=$((skipped + 1))
        continue
    fi

    echo "  [CONVERT] $fname (${src_rate} Hz -> 16000 Hz)"
    if ffmpeg -y -loglevel error -i "$f" \
        -af "aresample=resampler=soxr:precision=28:cutoff=0.97:dither_method=triangular" \
        -ar 16000 -ac 1 -sample_fmt s16 \
        "$OUT_DIR/$fname"; then
        converted=$((converted + 1))
    else
        echo "  [FAIL] ffmpeg error on: $fname"
        failed=$((failed + 1))
    fi
done

echo ""
echo "Done."
echo "  Total files:  $total"
echo "  Converted:    $converted"
echo "  Already 16k:  $skipped"
echo "  Failed:       $failed"
echo "  Output dir:   $OUT_DIR"

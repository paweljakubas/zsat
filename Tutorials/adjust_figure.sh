#!/usr/bin/env bash
# adjust_figure.sh — Resize and pad a zsat-generated PNG to match tutorial figure style.
#
# Usage:
#   ./adjust_figure.sh <input.png> [output.png]
#
# If output.png is omitted, it overwrites input.png in place.
#
# The tutorial figures have:
#   • Size: 332×332 pixels
#   • A light grey border (rgb(246,248,250)) around a white 288×288 canvas
#   • 24-bit RGB format (no alpha channel)

set -euo pipefail

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "Usage: $0 <input.png> [output.png]"
    exit 1
fi

INPUT="$1"
OUTPUT="${2:-$INPUT}"

if [ ! -f "$INPUT" ]; then
    echo "Error: file not found: $INPUT"
    exit 1
fi

# Resize drawing to 288×288, then pad with grey to 332×332, output as 24-bit RGB.
convert "$INPUT" \
    -resize 288x288 \
    -background '#f6f8fa' \
    -gravity center \
    -extent 332x332 \
    PNG24:"$OUTPUT"

echo "Adjusted: $OUTPUT"

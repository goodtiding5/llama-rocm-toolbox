#!/usr/bin/env bash
set -euo pipefail

# Save a snapshot (tar.gz) of /opt/rocm from a distrobox toolbox
# Usage: --dir DIR --name NAME --toolbox TOOLBOX_NAME

print_usage() {
  cat <<EOF
Usage: $0 --dir DIR --name NAME --toolbox TOOLBOX_NAME

Options:
  --dir DIR            Directory to place the snapshot (will be created if missing)
  --name NAME          Base name for the snapshot (timestamp will be appended)
  --toolbox NAME       Name of the distrobox toolbox to snapshot
  -h, --help           Show this help

Example:
  $0 --dir ~/rocm-cache --name rocm-gfx1151-2026-01 --toolbox rocm-llama
EOF
}

if [ $# -eq 0 ]; then
  print_usage
  exit 1
fi

DIR=""
NAME=""
TOOLBOX=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR="$2"; shift 2;;
    --name) NAME="$2"; shift 2;;
    --toolbox) TOOLBOX="$2"; shift 2;;
    -h|--help) print_usage; exit 0;;
    --) shift; break;;
    *) echo "Unknown arg: $1" >&2; print_usage; exit 2;;
  esac
done

if [ -z "$DIR" ] || [ -z "$NAME" ] || [ -z "$TOOLBOX" ]; then
  echo "Missing required arguments" >&2
  print_usage
  exit 2
fi

mkdir -p "$DIR"

if ! command -v distrobox >/dev/null 2>&1; then
  echo "distrobox not found in PATH. Please install distrobox or run this script on the host where distrobox is available." >&2
  exit 3
fi

# Check toolbox exists
if ! distrobox list | grep -qw "${TOOLBOX}"; then
  echo "Toolbox '${TOOLBOX}' not found (distrobox list does not show it)." >&2
  exit 4
fi

TIMESTAMP=$(date +%F_%H%M%S)
OUTFILE="${DIR%/}/${NAME}_${TIMESTAMP}.tar.gz"
TMPFILE="${OUTFILE}.part"

echo "Saving snapshot of toolbox '${TOOLBOX}' to '${OUTFILE}'"

# Attempt to create the tarball by running tar inside the toolbox and streaming to stdout
# Target path inside container: /opt/rocm
set -o pipefail
if distrobox enter "${TOOLBOX}" -- bash -lc "sudo tar -C / -czf - opt/rocm" > "$TMPFILE" 2>/dev/null; then
  mv "$TMPFILE" "$OUTFILE"
  echo "Snapshot saved: $OUTFILE"
  exit 0
else
  echo "Streaming tar inside toolbox failed; trying without sudo (in case container user is root)" >&2
fi

if distrobox enter "${TOOLBOX}" -- bash -lc "tar -C / -czf - opt/rocm" > "$TMPFILE" 2>/dev/null; then
  mv "$TMPFILE" "$OUTFILE"
  echo "Snapshot saved: $OUTFILE"
  exit 0
fi

rm -f "$TMPFILE" || true
echo "Failed to create snapshot from toolbox '${TOOLBOX}'." >&2
exit 5

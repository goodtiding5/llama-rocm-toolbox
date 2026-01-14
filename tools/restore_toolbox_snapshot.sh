#!/usr/bin/env bash
set -euo pipefail

# Restore a snapshot tarball into / on the host or inside the toolbox root
# Usage: --dir DIR --file SNAP_FILE --toolbox TOOLBOX_NAME [--force]

print_usage() {
  cat <<EOF
Usage: $0 --dir DIR --file SNAP_FILE --toolbox TOOLBOX_NAME [--force]

Options:
  --dir DIR            Directory where snapshots are stored (used to verify file exists)
  --file FILE          Snapshot file name (basename or path under --dir)
  --toolbox NAME       Name of the distrobox toolbox to restore into
  --force              Stop and remove an existing toolbox with the same name before restoring
  -h, --help           Show this help

Example:
  $0 --dir ~/rocm-cache --file rocm-gfx1151-2026-01_2026-01-13_123456.tar.gz --toolbox rocm-llama --force
EOF
}

if [ $# -eq 0 ]; then
  print_usage
  exit 1
fi

DIR=""
FILE=""
TOOLBOX=""
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR="$2"; shift 2;;
    --file) FILE="$2"; shift 2;;
    --toolbox) TOOLBOX="$2"; shift 2;;
    --force) FORCE=1; shift;;
    -h|--help) print_usage; exit 0;;
    --) shift; break;;
    *) echo "Unknown arg: $1" >&2; print_usage; exit 2;;
  esac
done

if [ -z "$DIR" ] || [ -z "$FILE" ] || [ -z "$TOOLBOX" ]; then
  echo "Missing required arguments" >&2
  print_usage
  exit 2
fi

SNAP_PATH="$FILE"
if [ ! -f "$SNAP_PATH" ]; then
  # try joining with DIR
  SNAP_PATH="${DIR%/}/$FILE"
fi

if [ ! -f "$SNAP_PATH" ]; then
  echo "Snapshot file not found: $SNAP_PATH" >&2
  exit 3
fi

if ! command -v distrobox >/dev/null 2>&1; then
  echo "distrobox not found in PATH. Please install distrobox or run this script on the host where distrobox is available." >&2
  exit 4
fi

# If force, stop and remove the toolbox container if it exists
if [ "$FORCE" -eq 1 ]; then
  if distrobox list | grep -qw "${TOOLBOX}"; then
    echo "Stopping and removing existing toolbox '${TOOLBOX}'"
    distrobox stop "${TOOLBOX}" || true
    distrobox rm "${TOOLBOX}" || true
  fi
fi

# Ensure toolbox does not exist (we'll create a fresh one to populate /opt/rocm)
if distrobox list | grep -qw "${TOOLBOX}"; then
  echo "Toolbox '${TOOLBOX}' already exists. Use --force to remove it first." >&2
  exit 5
fi

# Create a temporary container (toolbox) to extract into, then snapshot it as a toolbox
# We'll create the toolbox, extract the tar into /, then stop it. Use distrobox create + enter to run the extraction.

echo "Creating toolbox '${TOOLBOX}' (minimal Ubuntu)"
# Create distrobox with default image; user can customize later
if ! distrobox create --name "${TOOLBOX}"; then
  echo "Failed to create toolbox '${TOOLBOX}'." >&2
  exit 6
fi

# Extract snapshot into the toolbox filesystem by entering and extracting to /
# We'll copy the snapshot into the toolbox first to avoid dealing with host path mounts complexities
TMP_COPY="/tmp/$(basename "$SNAP_PATH")"

# Use distrobox-enter to run commands inside the newly created toolbox
echo "Copying snapshot into toolbox and extracting (this may require sudo)"

distrobox enter "${TOOLBOX}" -- bash -lc "set -e; cat > \"$TMP_COPY\" <<'__EOF__'\n$(base64 -w0 "$SNAP_PATH")\n__EOF__"

# Now inside toolbox, decode and extract
if distrobox enter "${TOOLBOX}" -- bash -lc "set -e; base64 -d '$TMP_COPY' > '$TMP_COPY.dec' && sudo tar -xzf '$TMP_COPY.dec' -C / && rm -f '$TMP_COPY' '$TMP_COPY.dec'"; then
  echo "Snapshot restored into toolbox '${TOOLBOX}'. Running ldconfig inside toolbox."
  distrobox enter "${TOOLBOX}" -- bash -lc "sudo ldconfig || true"
  echo "Restore complete. Toolbox '${TOOLBOX}' is ready."
  exit 0
else
  echo "Failed to extract snapshot inside toolbox. Cleaning up." >&2
  distrobox rm "${TOOLBOX}" || true
  exit 7
fi

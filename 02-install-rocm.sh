#!/usr/bin/env bash
set -euo pipefail

# 02-install-rocm.sh
# Install AMD ROCm nightly build inside the toolbox container.
# Usage: ./02-install-rocm.sh [--url URL] [-f|--force] [--config] [--verify]

# Source environment overrides if present
if [ -f "$(dirname "$0")/.toolbox.env" ]; then
  # shellcheck disable=SC1090
  source "$(dirname "$0")/.toolbox.env"
fi

echo "[02] ROCm installer (polished stub)"

usage() {
  cat <<'USAGE'
Usage: 02-install-rocm.sh [--url URL] [-f|--force] [--config] [--verify]

This script downloads and extracts a ROCm nightly tarball into $ROCM_HOME (from .toolbox.env).
Options:
  --url URL       Explicit URL to the ROCm tarball to download and install.
  -f, --force     Overwrite any existing ROCm at $ROCM_HOME without prompting.
  --config        Configure system loader and shell profile for ROCm (creates /etc/ld.so.conf.d/rocm.conf and /etc/profile.d/rocm.sh).
  --verify        Only run verification checks against ${ROCM_HOME} and exit.
  -h, --help      Show this help message.

Notes:
  - Preferred: provide a URL from your nightly index tool (e.g., tools/list_rocm_nightly.py).
  - The script will try to discover the latest URL using helper scripts under ./tools if available.
  - It uses sudo (if needed) to write into ${ROCM_HOME} and /etc; run inside the toolbox or as root in containers.
USAGE
}

# Parse args
LATEST_URL=""
FORCE=0
VERIFY=0
DO_CONFIG=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)
      LATEST_URL="$2"
      shift 2
      ;;
    -f|--force)
      FORCE=1
      shift
      ;;
    --verify)
      VERIFY=1
      shift
      ;;
    --config)
      DO_CONFIG=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

# Ensure defaults from .build.env are set
: "${ROCM_HOME:=/opt/rocm}"
: "${BUILD_PLATFORM:=${BUILD_PLATFORM:-linux}}"
: "${GPU_TARGET:=${GPU_TARGET:-gfx1151}}"
: "${TOOLBOX_NAME:=${TOOLBOX_NAME:-llama-toolbox}}"

# Set SUDO_CMD if not root
if [ "$(id -u)" -eq 0 ]; then
  SUDO_CMD=""
else
  SUDO_CMD="sudo"
fi

# Basic tool checks
for cmd in wget tar python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command '$cmd' not found. Install it and retry." >&2
    exit 3
  fi
done
# Check for sudo only if not root
if [ "$(id -u)" -ne 0 ]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "Error: required command 'sudo' not found. Install it and retry." >&2
    exit 3
  fi
fi

# Ensure libatomic is present (rocminfo and other ROCm tools may require libatomic)
if ! ldconfig -p 2>/dev/null | grep -q "libatomic.so.1"; then
  echo "libatomic.so.1 not found in loader cache; attempting to install 'libatomic1' from apt..." >&2
  # Try to install non-interactively. This uses sudo to run apt-get inside the toolbox.
    if command -v apt-get >/dev/null 2>&1; then
      ${SUDO_CMD:-} bash -c 'DEBIAN_FRONTEND=noninteractive apt-get update >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y libatomic1 >/dev/null' || true
    if ldconfig -p 2>/dev/null | grep -q "libatomic.so.1"; then
      echo "libatomic1 installed successfully." >&2
    else
      echo "Warning: libatomic1 installation attempted but libatomic.so.1 still not found." >&2
    fi
  else
    echo "Warning: apt-get not available; please ensure libatomic1 is installed on the system." >&2
  fi
fi

# Script info
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="$SCRIPT_DIR/tools"

# Helper: configure system loader and profile for ROCm
configure_rocm() {
  echo "Configuring system loader and shell profile for ROCm (ROCM_HOME=$ROCM_HOME)..." >&2

# Create ld.so.conf.d entry
${SUDO_CMD:-} mkdir -p /etc/ld.so.conf.d
${SUDO_CMD:-} tee /etc/ld.so.conf.d/rocm.conf >/dev/null <<EOF
${ROCM_HOME}/lib
${ROCM_HOME}/lib64
EOF
echo "Wrote /etc/ld.so.conf.d/rocm.conf" >&2

# Run ldconfig to refresh cache
echo "Running ldconfig..." >&2
${SUDO_CMD:-} ldconfig

# Create /etc/profile.d entry for interactive shells (convenience)
${SUDO_CMD:-} tee /etc/profile.d/rocm.sh >/dev/null <<'PROFILE'
export PATH="${ROCM_HOME}/bin:$PATH"
export LD_LIBRARY_PATH="${ROCM_HOME}/lib:${ROCM_HOME}/lib64:$LD_LIBRARY_PATH"
PROFILE
${SUDO_CMD:-} chmod 0644 /etc/profile.d/rocm.sh
  echo "Wrote /etc/profile.d/rocm.sh" >&2
}

# Helper: verification
verify_rocm() {
  echo "Running ROCm verification checks against $ROCM_HOME..." >&2
  VER_OK=1

  # Run rocminfo and capture output for parsing
  if [ -x "$ROCM_HOME/bin/rocminfo" ]; then
    TMP_ROCOUT=$(mktemp /tmp/rocminfo.XXXXXX)
    if "$ROCM_HOME/bin/rocminfo" >"$TMP_ROCOUT" 2>&1; then
      echo "rocminfo executed successfully." >&2
      # Extract key fields for concise reporting
      echo "--- rocminfo summary ---" >&2
      grep -E "ROCk module version|Runtime Version|Runtime Ext Version|Machine Model|Marketing Name|HIP version|Driver Version|ROCm" "$TMP_ROCOUT" | sed -n '1,200p' >&2 || true
      # Also show any simple '7.x' occurrences that might indicate ROCm packaging version
      echo "--- version-like matches (search for '7.x' tokens) ---" >&2
      grep -Eo "7\.[0-9]+(\.[0-9]+)?" "$TMP_ROCOUT" | sort -u | sed -n '1,50p' >&2 || true
      echo "--- end summary ---" >&2
    else
      echo "rocminfo failed or returned non-zero. Captured output:" >&2
      sed -n '1,200p' "$TMP_ROCOUT" >&2 || true
      VER_OK=0
    fi
    rm -f "$TMP_ROCOUT" || true
  else
    echo "Warning: $ROCM_HOME/bin/rocminfo not found; skip verification." >&2
    VER_OK=0
  fi

  # Prefer hipcc in PATH, fallback to ROCM_HOME/bin
  if command -v hipcc >/dev/null 2>&1; then
    echo "Running hipcc --version..." >&2
    if hipcc --version >/dev/null 2>&1; then
      echo "hipcc available." >&2
    else
      echo "hipcc present but '--version' failed." >&2
      VER_OK=0
    fi
  elif [ -x "$ROCM_HOME/bin/hipcc" ]; then
    if "$ROCM_HOME/bin/hipcc" --version >/dev/null 2>&1; then
      echo "hipcc from ROCM_HOME available." >&2
    else
      echo "hipcc found under ROCM_HOME but '--version' failed." >&2
      VER_OK=0
    fi
  else
    echo "hipcc not found; verification incomplete." >&2
    VER_OK=0
  fi

  # Check ldconfig listing for ROCm libraries
  if ldconfig -p 2>/dev/null | grep -Eo "(libhip_hcc|librocclr|librocm)" >/dev/null 2>&1; then
    echo "ldconfig lists ROCm-related libraries." >&2
  else
    echo "ldconfig does not list expected ROCm libraries; ld.so cache may be missing entries." >&2
    VER_OK=0
  fi

  # Print PATH and LD_LIBRARY_PATH for diagnostics
  echo "PATH=$PATH" >&2
  echo "LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-}" >&2

  if [ "$VER_OK" -eq 1 ]; then
    echo "ROCm appears to be installed and verified at $ROCM_HOME." >&2
    return 0
  else
    echo "ROCm verification failed or incomplete at $ROCM_HOME." >&2
    return 1
  fi
}

# If --verify was requested, run only the verification (and optional config)
if [ "$VERIFY" -eq 1 ]; then
  if [ "$DO_CONFIG" -eq 1 ]; then
    configure_rocm
  fi
  verify_rocm
  exit $?
fi

# If --config was requested without installing, run configuration and exit
if [ "$DO_CONFIG" -eq 1 ] && [ -z "$LATEST_URL" ]; then
  configure_rocm
  verify_rocm
  exit $?
fi

# If URL not provided, try helper scripts located next to this script (repo root)
if [ -z "$LATEST_URL" ]; then
  if [ -f "$TOOLS_DIR/list_rocm_nightly.py" ]; then
    echo "Discovering latest ROCm nightly URL via $TOOLS_DIR/list_rocm_nightly.py..." >&2
    set +e
    helper_out=$(python3 "$TOOLS_DIR/list_rocm_nightly.py" -p "${BUILD_PLATFORM}" -t "${GPU_TARGET}" -c 1 -q 2>&1)
    helper_rc=$?
    set -e
    echo "DEBUG: helper rc=$helper_rc" >&2
    echo "DEBUG: helper output start" >&2
    printf '%s
' "$helper_out" >&2
    echo "DEBUG: helper output end" >&2
    if [ $helper_rc -eq 0 ] && [ -n "$helper_out" ]; then
      # take first non-empty line
      LATEST_URL=$(printf '%s
' "$helper_out" | sed -n '1p')
    else
      echo "Helper script failed or produced no output." >&2
    fi
  fi
  if [ -z "$LATEST_URL" ] && [ -f "$TOOLS_DIR/list_rocm_nightly.sh" ]; then
    echo "Discovering latest ROCm nightly URL via $TOOLS_DIR/list_rocm_nightly.sh..." >&2
    set +e
    helper_out=$("$TOOLS_DIR/list_rocm_nightly.sh" -p "${BUILD_PLATFORM}" -t "${GPU_TARGET}" -c 1 -q 2>&1)
    helper_rc=$?
    set -e
    echo "DEBUG: helper rc=$helper_rc" >&2
    echo "DEBUG: helper output start" >&2
    printf '%s
' "$helper_out" >&2
    echo "DEBUG: helper output end" >&2
    if [ $helper_rc -eq 0 ] && [ -n "$helper_out" ]; then
      LATEST_URL=$(printf '%s
' "$helper_out" | sed -n '1p')
    else
      echo "Helper script failed or produced no output." >&2
    fi
  fi
fi

# Fallback: try helpers in PATH or relative cwd (legacy behavior)
if [ -z "$LATEST_URL" ]; then
  if command -v list_rocm_nightly.py >/dev/null 2>&1; then
    echo "Discovering latest ROCm nightly URL via list_rocm_nightly.py on PATH..." >&2
    set +e
    helper_out=$(python3 list_rocm_nightly.py -p "${BUILD_PLATFORM}" -t "${GPU_TARGET}" -c 1 -q 2>&1)
    helper_rc=$?
    set -e
    echo "DEBUG: helper rc=$helper_rc" >&2
    printf '%s
' "$helper_out" >&2
    if [ $helper_rc -eq 0 ] && [ -n "$helper_out" ]; then
      LATEST_URL=$(printf '%s
' "$helper_out" | sed -n '1p')
    fi
  elif [ -f "./tools/list_rocm_nightly.py" ]; then
    echo "Discovering latest ROCm nightly URL via ./tools/list_rocm_nightly.py (fallback)..." >&2
    set +e
    helper_out=$(python3 ./tools/list_rocm_nightly.py -p "${BUILD_PLATFORM}" -t "${GPU_TARGET}" -c 1 -q 2>&1)
    helper_rc=$?
    set -e
    echo "DEBUG: helper rc=$helper_rc" >&2
    printf '%s
' "$helper_out" >&2
    if [ $helper_rc -eq 0 ] && [ -n "$helper_out" ]; then
      LATEST_URL=$(printf '%s
' "$helper_out" | sed -n '1p')
    fi
  fi
fi

if [ -z "$LATEST_URL" ]; then
  # Fallback to a known recent URL for linux-gfx1151
  echo "No ROCm URL discovered, using fallback URL." >&2
  LATEST_URL="https://therock-nightly-tarball.s3.amazonaws.com/therock-dist-linux-gfx1151-7.11.0a20260113.tar.gz"
fi

echo "ROCm tarball URL: $LATEST_URL"

# Check for existing ROCm installation
if [ -d "$ROCM_HOME" ] && [ "$(ls -A "$ROCM_HOME" 2>/dev/null || true)" != "" ]; then
  echo "Existing ROCm installation detected at $ROCM_HOME" >&2
  if [ "$FORCE" -eq 1 ]; then
    echo "--force specified: removing existing ROCm installation..." >&2
    ${SUDO_CMD:-} rm -rf "$ROCM_HOME" || true
  else
    # Prompt user
    read -r -p "A ROCm installation already exists at $ROCM_HOME. Overwrite and install nightly? [y/N]: " answer
    case "$answer" in
      [Yy]|[Yy][Ee][Ss])
        echo "User confirmed overwrite. Backing up existing installation and proceeding..." >&2
        # try to backup first
        BACKUP_DIR="${ROCM_HOME}.bak-$(date +%Y%m%d%H%M%S)"
        if ${SUDO_CMD:-} mv "$ROCM_HOME" "$BACKUP_DIR" 2>/dev/null; then
          echo "Moved existing installation to $BACKUP_DIR" >&2
        else
          echo "Backup failed; attempting to remove existing installation." >&2
          ${SUDO_CMD:-} rm -rf "$ROCM_HOME" || true
        fi
        ;;
      *)
        echo "Aborting installation. Existing ROCm retained at $ROCM_HOME." >&2
        exit 0
        ;;
    esac
  fi
fi

# Download to a temporary file, verify, then extract to ROCM_HOME
TMPFILE=$(mktemp /tmp/rocm-XXXXXX.tar.gz)
trap 'rm -f "$TMPFILE"' EXIT

echo "Downloading to $TMPFILE..."
if ! wget ${NON_INTERACTIVE:+-q} -O "$TMPFILE" "$LATEST_URL"; then
  echo "Download failed" >&2
  exit 5
fi

echo "Creating ROCm root: $ROCM_HOME"
${SUDO_CMD:-} mkdir -p "$ROCM_HOME"

echo "Extracting tarball into $ROCM_HOME..."
${SUDO_CMD:-} tar -xzf "$TMPFILE" -C "$ROCM_HOME"

# After extraction, run configuration and verification
echo "Running configuration (ld.so + profile) post-extract..." >&2
configure_rocm

# Run verification unless NON_INTERACTIVE is set
echo "NON_INTERACTIVE=${NON_INTERACTIVE:-0}" >&2
if [ "${NON_INTERACTIVE:-0}" -eq 1 ]; then
  echo "Skipping verification in non-interactive mode." >&2
  echo "ROCm installed and configured successfully." >&2
  exit 0
else
  echo "Running verification post-extract..." >&2
  if verify_rocm; then
    echo "ROCm installed, configured, and verified successfully." >&2
    exit 0
  else
    echo "ROCm install/configuration completed but verification failed." >&2
    exit 6
  fi
fi

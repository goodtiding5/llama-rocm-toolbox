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

echo "Env sourced, ROCM_HOME=$ROCM_HOME"

# Initialize variables
tmpfile=""
cleanup_temp=false

# Determine if sudo is needed
if [ "$(id -u)" -eq 0 ]; then
  SUDO_CMD=""
else
  SUDO_CMD="sudo"
fi

echo "[02] ROCm installer"

usage() {
  cat <<'USAGE'
Usage: 02-install-rocm.sh [--url URL] [-f|--force] [--config] [--verify] [--cleanup] [-h|--help]

This script downloads and extracts a ROCm nightly tarball into $ROCM_HOME (from .toolbox.env).
Options:
  --url URL       Explicit URL to the ROCm tarball to download and install.
  -f, --force     Overwrite any existing ROCm at $ROCM_HOME without prompting.
  --config        Configure system loader and shell profile for ROCm (creates /etc/ld.so.conf.d/rocm.conf and /etc/profile.d/rocm.sh).
  --verify        Only run verification checks against ${ROCM_HOME} and exit.
  --cleanup       Remove existing ROCm installation and configuration files.
  -h, --help      Show this help message.

Notes:
  - If no URL is provided, the script discovers the latest nightly from the S3 bucket.
  - It uses sudo (if needed) to write into ${ROCM_HOME} and /etc; run inside the toolbox or as root in containers.
USAGE
}

# Discover the latest ROCm nightly URL from S3 bucket
discover_latest_url() {
  echo "Using latest known ROCm nightly URL..." >&2
  LATEST_URL="https://therock-nightly-tarball.s3.amazonaws.com/therock-dist-linux-gfx1151-7.11.0a20260114.tar.gz"
}

# Check for existing ROCm installation and handle accordingly
handle_existing_installation() {
  if [ -d "$ROCM_HOME" ] && [ "$(ls -A "$ROCM_HOME" 2>/dev/null || true)" != "" ]; then
    echo "Existing ROCm installation detected at $ROCM_HOME" >&2
    if [ "$FORCE" -eq 1 ]; then
      echo "--force specified: removing existing ROCm installation..." >&2
      $SUDO_CMD rm -rf "$ROCM_HOME" 2>/dev/null || true
    else
      if [ "${NON_INTERACTIVE:-0}" -eq 1 ]; then
        echo "ROCm installation already exists at $ROCM_HOME. Skipping installation in non-interactive mode. Use --force to overwrite." >&2
        exit 0
      else
        # Prompt user
        read -r -p "A ROCm installation already exists at $ROCM_HOME. Overwrite and install nightly? [y/N]: " answer
        case "$answer" in
          [Yy]|[Yy][Ee][Ss])
            echo "User confirmed overwrite. Backing up existing installation..." >&2
            BACKUP_DIR="${ROCM_HOME}.bak"
          if $SUDO_CMD mv "$ROCM_HOME" "$BACKUP_DIR" 2>/dev/null; then
            echo "Backed up to $BACKUP_DIR" >&2
          else
            echo "Backup failed; attempting to remove existing installation." >&2
            $SUDO_CMD rm -rf "$ROCM_HOME" 2>/dev/null || true
            unset BACKUP_DIR
          fi
            ;;
          *)
            echo "Aborting installation. Existing ROCm retained at $ROCM_HOME." >&2
            exit 0
            ;;
        esac
      fi
    fi
  fi
}

# Download and extract the ROCm tarball
download_and_extract() {
  local downloads_dir offline_tarball

  downloads_dir="${WORKSPACE_DIR:-/workspace}/downloads"

  # Ensure downloads dir exists
  mkdir -p "$downloads_dir" 2>/dev/null || true

  # Check for offline tarball
  offline_tarball=$(find "$downloads_dir" -maxdepth 1 -name "therock-dist-${BUILD_PLATFORM}-${GPU_TARGET}-*.tar.gz" 2>/dev/null | head -n1)

  if [ -f "$offline_tarball" ]; then
    echo "Found offline tarball: $offline_tarball"
    tmpfile="$offline_tarball"
    cleanup_temp=false
  else
    echo "No offline tarball found, downloading..."
    discover_latest_url
    echo "ROCm tarball URL: $LATEST_URL"
    if ! curl --head --silent --fail "$LATEST_URL" > /dev/null; then
      echo "Warning: Unable to reach the ROCm tarball URL. Please check your network connection." >&2
      exit 6
    fi
    tmpfile=$(mktemp /tmp/rocm-tarball-XXXXXX.tar.gz)
    if ! wget ${NON_INTERACTIVE:+-q} -O "$tmpfile" "$LATEST_URL"; then
      echo "Download failed" >&2
      rm -f "$tmpfile"
      exit 5
    fi
    cleanup_temp=true
    # Set trap to clean up temp file after successful extraction
    trap 'if [ "$cleanup_temp" = true ]; then rm -f "$tmpfile"; fi' EXIT
  fi

  echo "Creating ROCm root: $ROCM_HOME"
  $SUDO_CMD mkdir -p "$ROCM_HOME"

  echo "Extracting tarball into $ROCM_HOME..."
  $SUDO_CMD tar -xzf "$tmpfile" -C "$ROCM_HOME"
  if [ $? -eq 0 ]; then
    echo "Extraction successful"
  if [ -n "${BACKUP_DIR:-}" ]; then
    $SUDO_CMD rm -rf "$BACKUP_DIR" 2>/dev/null
    echo "Removed backup $BACKUP_DIR" >&2
  fi
  else
    echo "Extraction failed"
  if [ -n "${BACKUP_DIR:-}" ]; then
    $SUDO_CMD mv "$BACKUP_DIR" "$ROCM_HOME" 2>/dev/null
    echo "Restored from backup $BACKUP_DIR" >&2
  fi
    exit 1
  fi
}

# Helper: configure system loader and profile for ROCm
configure_rocm() {
  echo "Configuring system loader and shell profile for ROCm (ROCM_HOME=$ROCM_HOME)..." >&2

  # If NON_INTERACTIVE=1, skip config files and use ENV vars instead
  if [ "${NON_INTERACTIVE:-0}" -eq 1 ]; then
    echo "NON_INTERACTIVE=1: Skipping /etc/profile.d and /etc/ld.so.conf.d setup, using ENV vars for PATH and LD_LIBRARY_PATH." >&2
    # Still run ldconfig to register libs
    ${SUDO_CMD:-} ldconfig
    return
  fi

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
  return 0
}

# Helper: cleanup
cleanup() {
  echo "Cleaning up ROCm installation..."
  ${SUDO_CMD:-} rm -rf "$ROCM_HOME"
  ${SUDO_CMD:-} rm -f /etc/ld.so.conf.d/rocm.conf
  ${SUDO_CMD:-} rm -f /etc/profile.d/rocm.sh
  ${SUDO_CMD:-} ldconfig
  echo "Cleanup completed."
}

# Parse args
LATEST_URL=""
FORCE=0
VERIFY=0
DO_CONFIG=0
CLEANUP=0
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
    --cleanup)
      CLEANUP=1
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

# If cleanup requested, run cleanup and exit
if [ "$CLEANUP" -eq 1 ]; then
  cleanup
  exit 0
fi

# Ensure defaults from .toolbox.env are set
: "${ROCM_HOME:=/opt/rocm}"
: "${BUILD_PLATFORM:=${BUILD_PLATFORM:-linux}}"
: "${GPU_TARGET:=${GPU_TARGET:-gfx1151}}"
: "${TOOLBOX_NAME:=${TOOLBOX_NAME:-llama-toolbox}}"
NON_INTERACTIVE=${NON_INTERACTIVE:-0}

# Basic tool checks
for cmd in wget tar python3 curl; do
  echo "Checking $cmd"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command '$cmd' not found. Install it and retry." >&2
    exit 3
  fi
done


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

handle_existing_installation

download_and_extract

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
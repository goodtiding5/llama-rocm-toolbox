#!/usr/bin/env bash
set -euo pipefail

# 01-prepare-env.sh
# Prepare the environment with basic packages for other tasks
# Usage: ./01-prepare-env.sh

# Source environment overrides if present
if [ -f "$(dirname "$0")/.toolbox.env" ]; then
  # shellcheck disable=SC1090
  source "$(dirname "$0")/.toolbox.env"
fi

usage() {
  cat <<'USAGE'
Usage: 01-prepare-toolbox.sh

  -h, --help     Show this help and exit

This script will install essential packages.
USAGE
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -* )
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
done

# Determine if sudo is needed
if [ "$(id -u)" -eq 0 ]; then
  SUDO_CMD=""
else
  SUDO_CMD="sudo"
fi

echo "[01] Preparing toolbox container"

echo "Installing base dependencies..."
${SUDO_CMD} apt-get update

${SUDO_CMD} apt-get install -y --no-install-recommends ca-certificates wget curl python3 python3-pip git unzip gnupg xz-utils jq libatomic1

${SUDO_CMD} apt-get clean
${SUDO_CMD} rm -rf /var/lib/apt/lists/*

echo "[01] Preparation complete."

#!/usr/bin/env bash
set -euo pipefail

# 01-prepare-toolbox.sh
# Prepare the toolbox container with the needed basic pakcages
# Usage: ./01-prepare-toolbox.sh

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

echo "[01] Preparing toolbox container"

echo "Installing base dependencies..."
sudo apt-get update

sudo apt-get install -y --no-install-recommends ca-certificates wget curl python3 python3-pip git unzip gnupg xz-utils jq

sudo rm -rf /var/lib/apt/lists/*

echo "[01] Preparation complete."

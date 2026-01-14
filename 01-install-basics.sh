#!/usr/bin/env bash
set -euo pipefail

# 01-install-basics.sh
# Prepare the toolbox container with the needed basic packages
# Usage: ./01-install-basics.sh

# Source environment overrides if present
if [ -f "$(dirname "$0")/.build.env" ]; then
  # shellcheck disable=SC1090
  source "$(dirname "$0")/.build.env"
fi

usage() {
  cat <<'USAGE'
Usage: 01-install-basics.sh

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
apt-get update

apt-get install -y --no-install-recommends ca-certificates wget curl python3 python3-pip git unzip gnupg xz-utils jq cmake ninja-build ccache build-essential

rm -rf /var/lib/apt/lists/*

echo "[01] Preparation complete."
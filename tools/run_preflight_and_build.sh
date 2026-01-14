#!/usr/bin/env bash
set -euo pipefail

# Preflight checks and run build for llama.cpp
# Run this from the repo root inside the toolbox.

if [ -f ./.toolbox.env ]; then
  # shellcheck disable=SC1091
  source ./.toolbox.env || true
fi

printf "PRELIGHT: ROCM_HOME=%s\n" "${ROCM_HOME:-<unset>}"
printf "PRELIGHT: WORKSPACE_DIR=%s\n" "${WORKSPACE_DIR:-/workspace}"

if command -v hipconfig >/dev/null 2>&1; then
  echo "PRELIGHT: hipconfig output:"; hipconfig -p || true
else
  echo "PRELIGHT: hipconfig not found"
fi

if [ -x "${ROCM_HOME:-/opt/rocm}/llvm/bin/clang" ]; then
  echo "PRELIGHT: Found ROCm clang at ${ROCM_HOME}/llvm/bin/clang"
else
  echo "PRELIGHT: ROCm clang not found at ${ROCM_HOME:-/opt/rocm}/llvm/bin/clang"
  if command -v clang >/dev/null 2>&1; then
    echo "PRELIGHT: system clang found at $(command -v clang)"
  fi
fi

for cmd in cmake ccache ninja clang; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "PRELIGHT: $cmd -> $(command -v $cmd)"
  else
    echo "PRELIGHT: $cmd NOT found"
  fi
done

# Check for .bc files in common candidate locations
echo "PRELIGHT: checking for .bc files under ${ROCM_HOME:-/opt/rocm}"
CANDIDATES=("${ROCM_HOME:-/opt/rocm}/lib/llvm/amdgcn/bitcode" "${ROCM_HOME:-/opt/rocm}/lib/clang" "${ROCM_HOME:-/opt/rocm}/lib/clang/*/lib/linux" "${ROCM_HOME:-/opt/rocm}/lib/amdgcn" "${ROCM_HOME:-/opt/rocm}/amdgcn/bitcode")
for p in "${CANDIDATES[@]}"; do
  for d in $p; do
    if [ -d "$d" ] && ls "$d"/*.bc >/dev/null 2>&1; then
      echo "PRELIGHT: found .bc files in: $d"
    fi
  done
done

WS="${WORKSPACE_DIR:-/workspace}"
if [ -w "$WS" ]; then
  echo "PRELIGHT: workspace $WS writable"
else
  echo "PRELIGHT: workspace $WS not writable by current user (uid=$(id -u))"
fi

df -h "$WS" || true

# Run the build step (configure + build)
echo "\n=== Running: ./03-build-llamacpp.sh --run-build ===\n"
bash ./03-build-llamacpp.sh --run-build

exit 0

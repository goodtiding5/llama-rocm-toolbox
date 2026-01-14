#!/usr/bin/env bash
set -euo pipefail

# 04-validate-inference.sh
# Run a short inference using the built llama.cpp binary and a small GGUF model.
# Usage: ./04-validate-inference.sh /path/to/llama/build /path/to/model.gguf

# Source environment overrides if present
if [ -f "$(dirname "$0")/.toolbox.env" ]; then
  # shellcheck disable=SC1090
  source "$(dirname "$0")/.toolbox.env"
fi

# Default environment variables for Docker/release layout
ROCM_HOME="${ROCM_HOME:-/opt/rocm}"
LLAMA_HOME="${LLAMA_HOME:-/opt/llama}"
WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set up paths for ROCm and Llama
export PATH="$PATH:$ROCM_HOME/bin:$LLAMA_HOME/bin"
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$ROCM_HOME/lib:$ROCM_HOME/lib64"

# If NON_INTERACTIVE=1, skip validation for Docker builds
if [ "${NON_INTERACTIVE:-0}" -eq 1 ]; then
  echo "[04] NON_INTERACTIVE=1: Skipping inference validation for automated builds."
  exit 0
fi

# Export environment variables for model caching and transfer
export LLAMA_CACHE="${LLAMA_CACHE:-/workspace/models}"
export HF_HUB_ENABLE_HF_TRANSFER=1

LLAMA_BIN="${1:-llama-cli}"
MODEL_PATH="${2:-${SCRIPT_DIR}/models/gemma-3-1b-it-UD-Q4_K_XL.gguf}"

echo "[04] Validating inference"

echo "Checking ROCm installation..."
if command -v hipconfig >/dev/null 2>&1; then
  hipconfig
else
  echo "Warning: hipconfig not found, ROCm may not be properly installed"
fi

if command -v rocm-smi >/dev/null 2>&1; then
  rocm-smi --showid --showproductname --showuniqueid --showvgapciid --showbus --showserial --showtemp --showfan --showpower --showvoltage --showclock --showmeminfo vram --showmeminfo vis_vram --showmemuse --showmemvendor --showmemtype --showmemclock --showmemvoltage --showuse --showmclkrange --showmemclkrange --showvoltage --showcurrentlinkinfo --showgpubusy --showuniquepmu --showperflevel --showclocks --showtemp --showfan --showpower --showvoltage 2>/dev/null || echo "rocm-smi available but some options may not work"
else
  echo "Warning: rocm-smi not found"
fi

echo "LLAMA_BIN=${LLAMA_BIN}"
echo "MODEL_PATH=${MODEL_PATH}"

if ! command -v "$LLAMA_BIN" >/dev/null 2>&1; then
  echo "Error: llama binary not found in PATH: $LLAMA_BIN" >&2
  exit 2
fi

echo "Listing available devices with llama-cli..."
"$LLAMA_BIN" --list-devices

if [ ! -f "$MODEL_PATH" ]; then
  echo "Error: model file not found: $MODEL_PATH" >&2
  exit 2
fi

# Example run using llama-cli for non-interactive inference with GPU
"$LLAMA_BIN" -m "$MODEL_PATH" -p "What is the capital of France?" -n 32 -ngl 99 2>&1 | tee validation-output.txt

echo "Validation output saved to validation-output.txt"

echo "[04] Validation stub complete. Inspect logs for GPU detection and runtime behavior."

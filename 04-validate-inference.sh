#!/usr/bin/env bash
set -euo pipefail

# 04-validate-inference.sh
# Run a short inference using the built llama.cpp binary and a small GGUF model.
# Usage: ./04-validate-inference.sh /path/to/llama/build /path/to/model.gguf

# Source environment overrides if present
if [ -f "$(dirname "$0")/.build.env" ]; then
  # shellcheck disable=SC1090
  source "$(dirname "$0")/.build.env"
fi

# Export environment variables for model caching and transfer
export LLAMA_CACHE="${LLAMA_CACHE:-/workspace/models}"
export HF_HUB_ENABLE_HF_TRANSFER=1

LLAMA_BIN="${1:-llama-simple}"
MODEL_PATH="${2:-/workspace/models/unsloth_gemma-3-1b-it-GGUF_gemma-3-1b-it-UD-Q4_K_XL.gguf}"

echo "[04] Validating inference"

echo "LLAMA_BIN=${LLAMA_BIN}"
echo "MODEL_PATH=${MODEL_PATH}"

if ! command -v "$LLAMA_BIN" >/dev/null 2>&1; then
  echo "Error: llama binary not found in PATH: $LLAMA_BIN" >&2
  exit 2
fi

if [ ! -f "$MODEL_PATH" ]; then
  echo "Error: model file not found: $MODEL_PATH" >&2
  exit 2
fi

# Example run using llama-simple for non-interactive inference
"$LLAMA_BIN" -m "$MODEL_PATH" -n 32 "What is the capital of France?" 2>&1 | tee validation-output.txt

echo "Validation output saved to validation-output.txt"

echo "[04] Validation stub complete. Inspect logs for GPU detection and runtime behavior."

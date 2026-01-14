#!/usr/bin/env bash
set -euo pipefail

# 05-package-rocm.sh
# Create a trimmed ROCm runtime layout suitable for container deployment.
# Usage: ./05-package-rocm.sh [--restore] [--no-archive]

# Source environment overrides if present
if [ -f "$(dirname "$0")/.toolbox.env" ]; then
  # shellcheck disable=SC1090
  source "$(dirname "$0")/.toolbox.env"
fi

# Ensure defaults
NON_INTERACTIVE=${NON_INTERACTIVE:-0}

# Determine if sudo is needed
if [ "$(id -u)" -eq 0 ]; then
  SUDO_CMD=""
else
  SUDO_CMD="sudo"
fi

ROCM_ROOT="${ROCM_HOME:-/opt/rocm}"
RUNTIME_DIR="${ROCM_ROOT}.runtime"
LLAMA_BIN="${LLAMA_BIN:-llama-simple}"
LLAMA_SERVER_BIN="${LLAMA_SERVER_BIN:-llama-server}"
MODEL_PATH="${MODEL_PATH:-/workspace/models/unsloth_gemma-3-1b-it-GGUF_gemma-3-1b-it-UD-Q4_K_XL.gguf}"

# Parse arguments
RESTORE=0
NO_ARCHIVE=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --restore) RESTORE=1; shift;;
    --no-archive) NO_ARCHIVE=1; shift;;
    -h|--help) echo "Usage: $0 [--restore] [--no-archive]"; echo "  --restore     Restore full ROCm from archive if available"; echo "  --no-archive  Remove full ROCm archive after trimming (saves space)"; exit 0;;
    *) echo "Unknown option: $1" >&2; exit 2;;
  esac
done

# Handle restore
if [ "$RESTORE" -eq 1 ]; then
  ARCHIVE_DIR="${ROCM_ROOT}.archive"
  if [ -d "$ARCHIVE_DIR" ]; then
    echo "[05] Restoring full ROCm from $ARCHIVE_DIR to $ROCM_ROOT"
    ${SUDO_CMD} rm -rf "$ROCM_ROOT" 2>/dev/null || true
    ${SUDO_CMD} mv "$ARCHIVE_DIR" "$ROCM_ROOT"
    ${SUDO_CMD} ldconfig
    echo "[05] ROCm restored successfully."
  else
    echo "[05] No archive found at $ARCHIVE_DIR. Nothing to restore."
    exit 1
  fi
  exit 0
fi

# Add llama install dir to PATH
export PATH="${LLAMA_HOME:-/opt/llama}/bin:$PATH"

echo "[05] Trimming ROCm runtime from ${ROCM_ROOT} into ${RUNTIME_DIR}"

# Remove any existing incomplete runtime directory
${SUDO_CMD} rm -rf "$RUNTIME_DIR" 2>/dev/null || true

# Create runtime directory
${SUDO_CMD} mkdir -p "${RUNTIME_DIR}/lib"

# Copy ALL ROCm shared libraries to runtime directory
echo "Copying ALL ROCm shared libraries (*.so and *.so.*) to runtime directory..."
echo "This ensures no required libraries are missed."

# Copy all shared libraries from ROCm installation (preserving symlinks)
echo "Finding all shared libraries in $ROCM_ROOT/lib..."
find "$ROCM_ROOT/lib" -name "*.so" -o -name "*.so.*" | while read -r lib; do
  echo "Copying $(basename "$lib")"
   ${SUDO_CMD} cp -a "$lib" "${RUNTIME_DIR}/lib/" 2>/dev/null || true
done

# Also copy device libraries if present
if [ -d "${ROCM_ROOT}/lib/llvm/amdgcn/bitcode" ]; then
  ${SUDO_CMD} mkdir -p "${RUNTIME_DIR}/lib/llvm/amdgcn"
  ${SUDO_CMD} cp -r "${ROCM_ROOT}/lib/llvm/amdgcn/bitcode" "${RUNTIME_DIR}/lib/llvm/amdgcn/"
fi

# Copy BLAS library folders for tuned kernels
if [ -d "${ROCM_ROOT}/lib/rocblas/library" ]; then
  ${SUDO_CMD} mkdir -p "${RUNTIME_DIR}/lib/rocblas"
  ${SUDO_CMD} cp -r "${ROCM_ROOT}/lib/rocblas/library" "${RUNTIME_DIR}/lib/rocblas/"
  echo "Copied rocblas/library for tuned BLAS kernels"
fi

if [ -d "${ROCM_ROOT}/lib/hipblaslt/library" ]; then
  ${SUDO_CMD} mkdir -p "${RUNTIME_DIR}/lib/hipblaslt"
  ${SUDO_CMD} cp -r "${ROCM_ROOT}/lib/hipblaslt/library" "${RUNTIME_DIR}/lib/hipblaslt/"
  echo "Copied hipblaslt/library for tuned BLASLt kernels"
fi

# Copy hipconfig and rocminfo for verification
${SUDO_CMD} mkdir -p "${RUNTIME_DIR}/bin"
${SUDO_CMD} cp "${ROCM_ROOT}/bin/hipconfig" "${RUNTIME_DIR}/bin/" 2>/dev/null || true
${SUDO_CMD} cp "${ROCM_ROOT}/bin/rocminfo" "${RUNTIME_DIR}/bin/" 2>/dev/null || true

echo "[05] Runtime trimmed to ${RUNTIME_DIR}"

# Create environment script for trimmed runtime
${SUDO_CMD} tee "${RUNTIME_DIR}/llama.sh" > /dev/null <<EOF
# Environment script for trimmed ROCm runtime
export PATH="${ROCM_ROOT}/bin:\$PATH"
export LD_LIBRARY_PATH="${ROCM_ROOT}/lib:\${LD_LIBRARY_PATH:-}"
EOF
${SUDO_CMD} chmod +x "${RUNTIME_DIR}/llama.sh"
echo "Created environment script at ${RUNTIME_DIR}/llama.sh"

# Test the trimmed runtime (skip in non-interactive mode)
if [ "${NON_INTERACTIVE:-0}" -eq 1 ]; then
  echo "[05] Skipping runtime tests in non-interactive mode."
else
  echo "[05] Testing trimmed runtime..."
  ORIGINAL_LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"
  ORIGINAL_PATH="${PATH:-}"

  # Source the new environment script
  source "${RUNTIME_DIR}/llama.sh"

  # Verify rocminfo works
  if command -v rocminfo >/dev/null 2>&1; then
    echo "Testing rocminfo..."
    rocminfo >/dev/null 2>&1 && echo "rocminfo OK" || echo "rocminfo failed"
  else
    echo "rocminfo not in PATH"
  fi

  # Test llama inference with trimmed libs
  if [ -f "$MODEL_PATH" ]; then
    echo "Testing llama-simple inference..."
    "$LLAMA_BIN" -m "$MODEL_PATH" -n 16 "Hello world" >/dev/null 2>&1 && echo "Inference OK with trimmed runtime" || echo "Inference failed with trimmed runtime"
  else
    echo "Model not found, skipping inference test"
  fi

   # Restore environment
   export PATH="$ORIGINAL_PATH"
   export LD_LIBRARY_PATH="$ORIGINAL_LD_LIBRARY_PATH"
 fi

# Rename directories: archive old, promote runtime
echo "[05] Archiving full ROCm and promoting trimmed runtime"
ARCHIVE_DIR="${ROCM_ROOT}.archive"
${SUDO_CMD} mv "$ROCM_ROOT" "$ARCHIVE_DIR"
${SUDO_CMD} mv "$RUNTIME_DIR" "$ROCM_ROOT"
if [ "$NO_ARCHIVE" -eq 1 ]; then
  echo "[05] Removing archive to save space (--no-archive)"
  ${SUDO_CMD} rm -rf "$ARCHIVE_DIR"
else
  echo "[05] Full ROCm archived at ${ARCHIVE_DIR}"
fi
${SUDO_CMD} ldconfig

echo "[05] Packaging complete. Trimmed runtime now at ${ROCM_ROOT}"

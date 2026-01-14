#!/usr/bin/env bash
set -euo pipefail

# 05-package-rocm.sh
# Create a trimmed ROCm runtime layout suitable for container deployment.
# Usage: ./05-package-rocm.sh

# Source environment overrides if present
if [ -f "$(dirname "$0")/.build.env" ]; then
  # shellcheck disable=SC1090
  source "$(dirname "$0")/.build.env"
fi

# Determine if sudo is needed
if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
else
  SUDO="sudo"
fi

ROCM_ROOT="${ROCM_HOME:-/opt/rocm}"
RUNTIME_DIR="/opt/rocm.runtime"
LLAMA_BIN="${LLAMA_BIN:-llama-simple}"
MODEL_PATH="${MODEL_PATH:-/workspace/models/unsloth_gemma-3-1b-it-GGUF_gemma-3-1b-it-UD-Q4_K_XL.gguf}"

# Add llama install dir to PATH
export PATH="${LLAMA_INSTALL_DIR:-/opt/llama}/bin:$PATH"

echo "[05] Trimming ROCm runtime from ${ROCM_ROOT} into ${RUNTIME_DIR}"

# Archive existing profile scripts
ARCHIVE_DIR="/workspace/archive"
${SUDO} mkdir -p "${ARCHIVE_DIR}"
if [ -f /etc/profile.d/rocm.sh ]; then
  ${SUDO} cp /etc/profile.d/rocm.sh "${ARCHIVE_DIR}/"
  echo "Archived /etc/profile.d/rocm.sh to ${ARCHIVE_DIR}"
fi
if [ -f /etc/profile.d/llama.sh ]; then
  ${SUDO} cp /etc/profile.d/llama.sh "${ARCHIVE_DIR}/"
  echo "Archived /etc/profile.d/llama.sh to ${ARCHIVE_DIR}"
fi

# Create runtime directory
${SUDO} mkdir -p "${RUNTIME_DIR}/lib"

# Identify minimal runtime libraries by checking llama-simple dependencies
echo "Analyzing dependencies of ${LLAMA_BIN}..."
if ! command -v "$LLAMA_BIN" >/dev/null 2>&1; then
  echo "Error: ${LLAMA_BIN} not found in PATH" >&2
  exit 1
fi

# Get ROCm-related libraries from ldd
ROCMLIBS=$(ldd "$(which "$LLAMA_BIN")" 2>/dev/null | grep -E "(rocm|hip|amd|blas)" | awk '{print $3}' | grep "^${ROCM_ROOT}" | sort -u)

if [ -z "$ROCMLIBS" ]; then
  echo "No ROCm libraries found in dependencies. Checking manually..." >&2
  # Fallback: copy common ROCm libs
  ROCMLIBS="${ROCM_ROOT}/lib/libhip_hcc.so ${ROCM_ROOT}/lib/librocclr.so ${ROCM_ROOT}/lib/libamdhip64.so ${ROCM_ROOT}/lib/librocblas.so ${ROCM_ROOT}/lib/librocsolver.so"
fi

echo "Copying ROCm libraries: $ROCMLIBS"
for lib in $ROCMLIBS; do
  if [ -f "$lib" ]; then
    ${SUDO} cp -v "$lib"* "${RUNTIME_DIR}/lib/" 2>/dev/null || true
  fi
done

# Also copy device libraries if present
if [ -d "${ROCM_ROOT}/lib/llvm/amdgcn/bitcode" ]; then
  ${SUDO} mkdir -p "${RUNTIME_DIR}/lib/llvm/amdgcn"
  ${SUDO} cp -r "${ROCM_ROOT}/lib/llvm/amdgcn/bitcode" "${RUNTIME_DIR}/lib/llvm/amdgcn/"
fi

# Copy BLAS library folders for tuned kernels
if [ -d "${ROCM_ROOT}/lib/rocblas/library" ]; then
  ${SUDO} mkdir -p "${RUNTIME_DIR}/lib/rocblas"
  ${SUDO} cp -r "${ROCM_ROOT}/lib/rocblas/library" "${RUNTIME_DIR}/lib/rocblas/"
  echo "Copied rocblas/library for tuned BLAS kernels"
fi

if [ -d "${ROCM_ROOT}/lib/hipblaslt/library" ]; then
  ${SUDO} mkdir -p "${RUNTIME_DIR}/lib/hipblaslt"
  ${SUDO} cp -r "${ROCM_ROOT}/lib/hipblaslt/library" "${RUNTIME_DIR}/lib/hipblaslt/"
  echo "Copied hipblaslt/library for tuned BLASLt kernels"
fi

# Copy hipconfig and rocminfo for verification
${SUDO} mkdir -p "${RUNTIME_DIR}/bin"
${SUDO} cp "${ROCM_ROOT}/bin/hipconfig" "${RUNTIME_DIR}/bin/" 2>/dev/null || true
${SUDO} cp "${ROCM_ROOT}/bin/rocminfo" "${RUNTIME_DIR}/bin/" 2>/dev/null || true

echo "[05] Runtime trimmed to ${RUNTIME_DIR}"

# Create environment script for trimmed runtime
${SUDO} tee "${RUNTIME_DIR}/llama.sh" > /dev/null <<EOF
# Environment script for trimmed ROCm runtime
export PATH="${RUNTIME_DIR}/bin:\$PATH"
export LD_LIBRARY_PATH="${RUNTIME_DIR}/lib:\${LD_LIBRARY_PATH:-}"
EOF
${SUDO} chmod +x "${RUNTIME_DIR}/llama.sh"
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

echo "[05] Packaging complete. Trimmed runtime at ${RUNTIME_DIR}"

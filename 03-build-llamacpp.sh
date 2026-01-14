#!/usr/bin/env bash
set -euo pipefail

# 03-build-llamacpp.sh
# Clone/update llama.cpp and build with ROCm support for the configured GPU target.
# Usage: ./03-build-llamacpp.sh [--force] [--install-toolchain] [-h|--help]

print_usage() {
  cat <<EOF
Usage: $0 [--force] [--install-toolchain] [--config] [--install] [--cleanup] [-h|--help]

Options:
  --force               Remove existing workspace directory before cloning (use with care)
  --install-toolchain   Install required build toolchain packages via apt
  --config              Configure system loader and shell profile for Llama (creates /etc/ld.so.conf.d/llama.conf and /etc/profile.d/llama.sh)
  --install             Install pre-built binaries and configure system (assumes build is done)
  --cleanup             Remove llama.cpp installation and configuration files
  -h, --help            Show this help
EOF
}

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
FORCE=0
INSTALL_TOOLCHAIN=0
CLEANUP=0
CONFIG=0
INSTALL=0
WORKSPACE_BASE="${WORKSPACE_DIR:-/workspace}"
TARGET_DIR="${WORKSPACE_BASE}/llama.cpp"
LLAMA_HOME="${LLAMA_HOME:-/opt/llama}"

# Parse arguments
while [ "$#" -gt 0 ]; do
  case "$1" in
    --force) FORCE=1; shift;;
    --install-toolchain) INSTALL_TOOLCHAIN=1; shift;;
    --config) CONFIG=1; shift;;
    --install) INSTALL=1; shift;;
    --cleanup) CLEANUP=1; shift;;
    -h|--help) print_usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; print_usage; exit 2;;
  esac
done

echo "[03] Workspace base: ${WORKSPACE_BASE}"
echo "[03] Target clone dir: ${TARGET_DIR}"
echo "[03] Install prefix: ${LLAMA_HOME}"

# Ensure git is available
if ! command -v git >/dev/null 2>&1; then
  echo "Error: git not found in PATH. Install git in the toolbox or host environment." >&2
  exit 3
fi

# Function to handle workspace creation and permissions
setup_workspace() {
  WORKSPACE_BASE="${WORKSPACE_BASE%/}"
  TARGET_DIR="${WORKSPACE_BASE}/llama.cpp"

  CUR_UID=$(id -u)
  CUR_GID=$(id -g)

  if mkdir -p "$WORKSPACE_BASE" 2>/dev/null; then
    :
  else
    echo "[03] Warning: cannot create '$WORKSPACE_BASE' as current user. Trying with sudo..."
    if command -v ${SUDO_CMD} >/dev/null 2>&1; then
      if ${SUDO_CMD} mkdir -p "$WORKSPACE_BASE" 2>/dev/null; then
        echo "[03] Created '$WORKSPACE_BASE' with sudo. Attempting to fix ownership to the current user ($CUR_UID:$CUR_GID)."
        if ${SUDO_CMD} chown "$CUR_UID:$CUR_GID" "$WORKSPACE_BASE" 2>/dev/null; then
          echo "[03] Ownership updated. Workspace is now writable by the current user."
        else
          echo "[03] Warning: failed to chown '$WORKSPACE_BASE'. Will attempt sudo-based operations later." >&2
        fi
      else
        echo "[03] sudo mkdir failed. Falling back to user-writable directory."
        FALLBACK="$HOME/workspace"
        mkdir -p "$FALLBACK"
        WORKSPACE_BASE="$FALLBACK"
        TARGET_DIR="${WORKSPACE_BASE}/llama.cpp"
        echo "[03] Using fallback workspace: $WORKSPACE_BASE"
      fi
    else
      echo "[03] sudo not available. Falling back to user-writable directory."
      FALLBACK="$HOME/workspace"
      mkdir -p "$FALLBACK"
      WORKSPACE_BASE="$FALLBACK"
      TARGET_DIR="${WORKSPACE_BASE}/llama.cpp"
      echo "[03] Using fallback workspace: $WORKSPACE_BASE"
    fi
  fi

  NEED_SUDO_CLONE=0
  if [ ! -w "$WORKSPACE_BASE" ]; then
    echo "[03] Workspace base '$WORKSPACE_BASE' is not writable by current user. Will use sudo for operations and then fix ownership."
    NEED_SUDO_CLONE=1
  fi
}

# Function to extract offline tarball
extract_offline_tarball() {
  DOWNLOADS_DIR="${WORKSPACE_DIR:-/workspace}/downloads"
  LLAMA_TARBALL=$(find "$DOWNLOADS_DIR" -name "llama.cpp-*.tar.gz" -o -name "llama.cpp-*.tgz" 2>/dev/null | head -n1)

  if [ -f "$LLAMA_TARBALL" ]; then
    echo "[03] Found offline tarball: $LLAMA_TARBALL"
    echo "[03] Extracting llama.cpp from tarball into $TARGET_DIR"

    if [ "$NEED_SUDO_CLONE" -eq 1 ]; then
      echo "[03] Running 'sudo tar' into protected path. This will create files owned by root which will be chowned back to the current user."
      ${SUDO_CMD} mkdir -p "$TARGET_DIR"
      ${SUDO_CMD} tar -xzf "$LLAMA_TARBALL" -C "$TARGET_DIR" --strip-components=1
      ${SUDO_CMD} chown -R "$CUR_UID:$CUR_GID" "$TARGET_DIR" || true
    else
      mkdir -p "$TARGET_DIR"
      tar -xzf "$LLAMA_TARBALL" -C "$TARGET_DIR" --strip-components=1
    fi

    TARBALL_BASENAME=$(basename "$LLAMA_TARBALL")
    VERSION_INFO="${TARBALL_BASENAME%.tar.gz}"
    VERSION_INFO="${VERSION_INFO%.tgz}"
    echo "$VERSION_INFO" > "$TARGET_DIR/build-version.txt"
    echo "[03] Version recorded: $VERSION_INFO -> $TARGET_DIR/build-version.txt"
    COMMIT_HASH="${VERSION_INFO}"
    return 0
  fi
  return 1
}

# Function to clone repository
clone_repository() {
  if [ ! -d "$TARGET_DIR/.git" ]; then
    echo "[03] Cloning llama.cpp into $TARGET_DIR"
    if [ "$NEED_SUDO_CLONE" -eq 1 ]; then
      echo "[03] Running 'sudo git clone' into protected path. This will create files owned by root which will be chowned back to the current user."
      ${SUDO_CMD} git clone https://github.com/ggml-org/llama.cpp.git "$TARGET_DIR"
      ${SUDO_CMD} chown -R "$CUR_UID:$CUR_GID" "$TARGET_DIR" || true
    else
      git clone https://github.com/ggml-org/llama.cpp.git "$TARGET_DIR"
    fi
  fi

  COMMIT_HASH=$(git -C "$TARGET_DIR" rev-parse --short HEAD)
  echo "$COMMIT_HASH" > "$TARGET_DIR/build-commit.txt"
  echo "[03] Commit recorded: $COMMIT_HASH -> $TARGET_DIR/build-commit.txt"
}

# Function to install toolchain
install_toolchain() {
  echo "[03] Installing toolchain packages via apt-get"
  REQUIRED_PACKAGES=(cmake ccache ninja-build build-essential llvm clang libssl-dev pkg-config libomp-dev libcurl4-openssl-dev)
  if command -v apt-get >/dev/null 2>&1; then
    if [ "$(id -u)" -eq 0 ]; then
      DEBIAN_FRONTEND=noninteractive apt-get update -y
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${REQUIRED_PACKAGES[@]}"
    else
      ${SUDO_CMD} bash -lc "DEBIAN_FRONTEND=noninteractive apt-get update -y && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ${REQUIRED_PACKAGES[*]}"
    fi
  else
    echo "[03] apt-get not found; cannot install toolchain packages. Please install manually: ${REQUIRED_PACKAGES[*]}" >&2
    exit 5
  fi
  echo "[03] Toolchain installation complete."
}

# Function to configure system for llama
configure_llama() {
  INSTALL_PREFIX="${LLAMA_HOME:-/opt/llama}"
  echo "[03] Configuring system for Llama at ${INSTALL_PREFIX}"

  # If NON_INTERACTIVE=1, skip config files and use ENV vars instead
  if [ "${NON_INTERACTIVE:-0}" -eq 1 ]; then
    echo "[03] NON_INTERACTIVE=1: Skipping /etc/profile.d and /etc/ld.so.conf.d setup, using ENV vars for PATH and LD_LIBRARY_PATH."
    # Still run ldconfig to register libs
    ${SUDO_CMD} ldconfig || true
    return
  fi

  # Register library path and set environment
  if [ "$(id -u)" -eq 0 ]; then
    echo "${INSTALL_PREFIX}/lib" > "/etc/ld.so.conf.d/llama.conf"
    ldconfig || true
    echo "[03] Registered ${INSTALL_PREFIX}/lib with ldconfig"
    cat > /etc/profile.d/llama.sh <<EOF
export PATH="\$PATH:${INSTALL_PREFIX}/bin"
export LD_LIBRARY_PATH="\$LD_LIBRARY_PATH:${INSTALL_PREFIX}/lib"
EOF
    echo "[03] Created /etc/profile.d/llama.sh for environment setup"
  else
    if [ -n "$SUDO_CMD" ]; then
      ${SUDO_CMD} sh -c "echo '${INSTALL_PREFIX}/lib' > /etc/ld.so.conf.d/llama.conf && ldconfig"
      echo "[03] Registered ${INSTALL_PREFIX}/lib with ldconfig (via sudo)"
      ${SUDO_CMD} sh -c "cat > /etc/profile.d/llama.sh <<EOF
export PATH=\"\\\$PATH:${INSTALL_PREFIX}/bin\"
export LD_LIBRARY_PATH=\"\\\$LD_LIBRARY_PATH:${INSTALL_PREFIX}/lib\"
EOF"
      echo "[03] Created /etc/profile.d/llama.sh for environment setup (via sudo)"
    else
      if [ -f /etc/profile.d/llama.sh ]; then
        echo "[03] System-wide profile /etc/profile.d/llama.sh exists; skipping creation of ${INSTALL_PREFIX}/env/llama_env.sh"
      else
        mkdir -p "${INSTALL_PREFIX}/env"
        cat > "${INSTALL_PREFIX}/env/llama_env.sh" <<EOF
# Source this to add Llama install to your environment
export PATH="${INSTALL_PREFIX}/bin:\$PATH"
export LD_LIBRARY_PATH="${INSTALL_PREFIX}/lib:\${LD_LIBRARY_PATH:-}"
EOF
        chmod +x "${INSTALL_PREFIX}/env/llama_env.sh"
        echo "[03] Created environment script at ${INSTALL_PREFIX}/env/llama_env.sh"
        echo "[03] To use installed binaries, run: source ${INSTALL_PREFIX}/env/llama_env.sh"
      fi
    fi
  fi
}

# Function to install pre-built llama
install_llama() {
  INSTALL_PREFIX="${LLAMA_HOME:-/opt/llama}"
  echo "[03] Installing pre-built Llama binaries to ${INSTALL_PREFIX}"

  # Assume build is done, TARGET_DIR exists
  if [ ! -d "$TARGET_DIR" ]; then
    echo "[03] Error: Build directory $TARGET_DIR not found. Run full build first."
    exit 7
  fi

  BUILD_DIR="$TARGET_DIR/build"
  if [ ! -d "$BUILD_DIR" ]; then
    echo "[03] Error: Build dir $BUILD_DIR not found. Run cmake configure and build first."
    exit 7
  fi

  # Install
  echo "[03] Running installation to ${INSTALL_PREFIX}"
  if [ "$(id -u)" -eq 0 ]; then
    cmake --install "$BUILD_DIR" --prefix "${INSTALL_PREFIX}"
  else
    if [ -n "$SUDO_CMD" ]; then
      echo "[03] Running install with sudo (will chown back to current user afterwards)"
      ${SUDO_CMD} cmake --install "$BUILD_DIR" --prefix "${INSTALL_PREFIX}"
      ${SUDO_CMD} chown -R "$CUR_UID:$CUR_GID" "${INSTALL_PREFIX}" || true
    else
      echo "[03] Error: cannot install to ${INSTALL_PREFIX} without root privileges or sudo. Please run this script as root or re-run with --install-toolchain followed by sudo." >&2
      exit 6
    fi
  fi
  echo "[03] Installed to ${INSTALL_PREFIX}"

  # Move shared libraries
  mkdir -p "${INSTALL_PREFIX}/lib" "${INSTALL_PREFIX}/bin"
  bash -c 'shopt -s nullglob; set -e; moved=0; for f in "'"${INSTALL_PREFIX}"'"/bin/*.so*; do if [ -f "$f" ]; then echo "[03] Moving shared lib $f -> '${INSTALL_PREFIX}'/lib/"; mv "$f" "'"${INSTALL_PREFIX}"'"/lib/ || '${SUDO_CMD}' mv "$f" "'"${INSTALL_PREFIX}"'"/lib/ || true; moved=1; fi; done; if [ "$moved" -eq 1 ]; then echo "[03] Shared libraries moved to '${INSTALL_PREFIX}'/lib"; fi'

  # Register library path and set environment
  configure_llama
}

build_llama() {
  echo "[03] Configuring and building llama.cpp (commit: $COMMIT_HASH)"
  BUILD_DIR="$TARGET_DIR/build"
  mkdir -p "$BUILD_DIR"

  GPU_TARGET="${GPU_TARGET:-gfx1151}"
  INSTALL_PREFIX="${LLAMA_HOME:-/opt/llama}"

  # Check for required toolchain commands
  MISSING=()
  for cmd in cmake ninja ccache; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      MISSING+=("$cmd")
    fi
  done

  # Prefer ROCm clang if present
  ROCM_CC="${ROCM_HOME:-/opt/rocm}/llvm/bin/clang"
  ROCM_CXX="${ROCM_HOME:-/opt/rocm}/llvm/bin/clang++"
  if [ ! -x "$ROCM_CC" ]; then
    if command -v clang >/dev/null 2>&1; then
      ROCM_CC="$(command -v clang)"
      ROCM_CXX="$(command -v clang++)"
    else
      MISSING+=("clang")
    fi
  fi

  if [ ${#MISSING[@]} -gt 0 ]; then
    echo "[03] Missing required tools: ${MISSING[*]}"
    echo "[03] Installing missing tools..."
    install_toolchain
    # Recheck
    MISSING=()
    for cmd in cmake ninja ccache; do
      if ! command -v "$cmd" >/dev/null 2>&1; then
        MISSING+=("$cmd")
      fi
    done
    if [ ! -x "$ROCM_CC" ]; then
      MISSING+=("clang")
    fi
    if [ ${#MISSING[@]} -gt 0 ]; then
      echo "[03] Still missing after install: ${MISSING[*]}"
      exit 4
    fi
  fi

  # Detect ROCm device library path
  ROCM_DEVICE_LIB_PATH=""
  if [ -n "${ROCM_HOME:-}" ]; then
    CANDIDATES=("${ROCM_HOME}/lib/llvm/amdgcn/bitcode" "${ROCM_HOME}/lib/clang" "${ROCM_HOME}/lib/clang/*/lib/linux" "${ROCM_HOME}/lib/amdgcn" "${ROCM_HOME}/amdgcn/bitcode")
    for c in "${CANDIDATES[@]}"; do
      for d in $c; do
        if [ -d "$d" ] && ls "$d"/*.bc >/dev/null 2>&1; then
          ROCM_DEVICE_LIB_PATH="$d"
          break 2
        fi
      done
    done
  fi

  if [ -z "$ROCM_DEVICE_LIB_PATH" ]; then
    echo "[03] Warning: could not auto-detect ROCm device library path under ${ROCM_HOME:-/opt/rocm}. You may need to set ROCM_DEVICE_LIB_PATH to the directory containing .bc files."
  else
    echo "[03] Detected ROCm device library path: $ROCM_DEVICE_LIB_PATH"
  fi

  # Export HIP_DEVICE_LIB_PATH and set device lib flag
  if [ -n "$ROCM_DEVICE_LIB_PATH" ]; then
    export HIP_DEVICE_LIB_PATH="$ROCM_DEVICE_LIB_PATH"
    DEVICE_LIB_FLAG="--rocm-device-lib-path=${ROCM_DEVICE_LIB_PATH}"
  else
    DEVICE_LIB_FLAG=""
  fi

  # Set ROCM_PATH and HIP_PLATFORM
  export ROCM_PATH="${ROCM_HOME:-/opt/rocm}"
  if command -v hipconfig >/dev/null 2>&1; then
    HIPCFG_PLATFORM=$(hipconfig --platform 2>/dev/null || true)
    if [ -n "$HIPCFG_PLATFORM" ]; then
      export HIP_PLATFORM="$HIPCFG_PLATFORM"
      echo "[03] Detected HIP_PLATFORM from hipconfig: $HIP_PLATFORM"
    else
      export HIP_PLATFORM=amd
      echo "[03] Warning: hipconfig did not report a platform; defaulting HIP_PLATFORM=amd"
    fi
  else
    export HIP_PLATFORM=amd
    echo "[03] Warning: hipconfig not found in PATH; defaulting HIP_PLATFORM=amd"
  fi

  # Configure the build
  echo "[03] Running cmake configure (source: $TARGET_DIR, build: $BUILD_DIR)"
  cmake -S "$TARGET_DIR" -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_C_COMPILER="$ROCM_CC" \
    -DCMAKE_CXX_COMPILER="$ROCM_CXX" \
    -DCMAKE_C_COMPILER_LAUNCHER=ccache \
    -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
    -DCMAKE_C_FLAGS="-I${ROCM_HOME:-/opt/rocm}/include" \
    -DCMAKE_CXX_FLAGS="-I${ROCM_HOME:-/opt/rocm}/include" \
    -DCMAKE_HIP_FLAGS="${DEVICE_LIB_FLAG}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
    -DGPU_TARGETS="${GPU_TARGET}" \
    -DGGML_HIP=ON \
    -DGGML_HIP_ROCWMMA_FATTN=OFF \
    -DBUILD_SHARED_LIBS=ON \
    -DLLAMA_BUILD_TESTS=OFF \
    -DGGML_OPENMP=OFF \
    -DLLAMA_CURL=ON \
    -DGGML_NATIVE=ON \
    -DGGML_CCACHE=ON 2>&1 | tee "$TARGET_DIR/build-cmake.log"

  # Build
  echo "[03] Running build: cmake --build $BUILD_DIR --config Release -j$(nproc)"
  cmake --build "$BUILD_DIR" --config Release -j"$(nproc)" 2>&1 | tee "$TARGET_DIR/build-make.log"
  echo "[03] Build completed. Logs: $TARGET_DIR/build-cmake.log, $TARGET_DIR/build-make.log"

  # Install
  echo "[03] Running installation to ${INSTALL_PREFIX}"
  if [ "$(id -u)" -eq 0 ]; then
    cmake --install "$BUILD_DIR" --prefix "${INSTALL_PREFIX}"
  else
    if [ -n "$SUDO_CMD" ]; then
      echo "[03] Running install with sudo (will chown back to current user afterwards)"
      ${SUDO_CMD} cmake --install "$BUILD_DIR" --prefix "${INSTALL_PREFIX}"
      ${SUDO_CMD} chown -R "$CUR_UID:$CUR_GID" "${INSTALL_PREFIX}" || true
    else
      echo "[03] Error: cannot install to ${INSTALL_PREFIX} without root privileges or sudo. Please run this script as root or re-run with --install-toolchain followed by sudo." >&2
      exit 6
    fi
  fi
  echo "[03] Installed to ${INSTALL_PREFIX}"

   # Move shared libraries
   mkdir -p "${INSTALL_PREFIX}/lib" "${INSTALL_PREFIX}/bin"
    bash -c 'shopt -s nullglob; set -e; moved=0; for f in "'"${INSTALL_PREFIX}"'"/bin/*.so*; do if [ -f "$f" ]; then echo "[03] Moving shared lib $f -> '${INSTALL_PREFIX}'/lib/"; mv "$f" "'"${INSTALL_PREFIX}"'"/lib/ || '${SUDO_CMD}' mv "$f" "'"${INSTALL_PREFIX}"'"/lib/ || true; moved=1; fi; done; if [ "$moved" -eq 1 ]; then echo "[03] Shared libraries moved to '${INSTALL_PREFIX}'/lib"; fi'

   # Register library path and set environment
   configure_llama

   # Clean up
   echo "[03] Cleaning up build directory: $BUILD_DIR"
   rm -rf "$BUILD_DIR"
   echo "[03] Cleaning up source repository: $TARGET_DIR"
   rm -rf "$TARGET_DIR"
   echo "[03] Build complete, directories cleaned."
}

# Function to cleanup
cleanup() {
  echo "[03] Cleaning up llama.cpp installation..."
  # Remove target dir
  if [ -d "$TARGET_DIR" ]; then
    rm -rf "$TARGET_DIR" 2>/dev/null || ${SUDO_CMD} rm -rf "$TARGET_DIR" 2>/dev/null || true
    echo "[03] Removed $TARGET_DIR"
  fi
  # Remove install dir
  if [ -d "$LLAMA_HOME" ]; then
    ${SUDO_CMD} rm -rf "$LLAMA_HOME" 2>/dev/null || true
    echo "[03] Removed $LLAMA_HOME"
  fi
  # Remove config files
  ${SUDO_CMD} rm -f /etc/ld.so.conf.d/llama.conf 2>/dev/null || true
  ${SUDO_CMD} rm -f /etc/profile.d/llama.sh 2>/dev/null || true
  ${SUDO_CMD} ldconfig 2>/dev/null || true
  echo "[03] Cleanup completed."
}

# If cleanup requested, run cleanup and exit
if [ "$CLEANUP" -eq 1 ]; then
  cleanup
  exit 0
fi

# If config requested, run config and exit
if [ "$CONFIG" -eq 1 ]; then
  configure_llama
  exit 0
fi

# If install requested, run install assuming build is done
if [ "$INSTALL" -eq 1 ]; then
  install_llama
  exit 0
fi

# Main logic
setup_workspace

# Handle existing target
if [ -d "$TARGET_DIR/.git" ]; then
  if [ "$FORCE" -eq 1 ]; then
    echo "[03] --force specified: removing existing directory $TARGET_DIR"
    rm -rf "$TARGET_DIR"
  else
    echo "[03] Repository already exists at $TARGET_DIR. Pulling latest changes."
    git -C "$TARGET_DIR" fetch --all --prune
    git -C "$TARGET_DIR" pull --ff-only || true
  fi
fi

# Try offline tarball first
if ! extract_offline_tarball; then
  clone_repository
fi

# Install toolchain if requested
if [ "$INSTALL_TOOLCHAIN" -eq 1 ]; then
  install_toolchain
  # If only toolchain install, exit
  echo "[03] --install-toolchain specified: exiting after toolchain install."
  exit 0
fi

# Build and install
build_llama

#!/usr/bin/env bash
set -euo pipefail

# 03-build-llamacpp.sh
# Clone/update llama.cpp and build with ROCm support for the configured GPU target.
# Usage: ./03-build-llamacpp.sh [--force] [--workspace DIR] [--no-build] [--run-build] [--run-install] [--run-clean] [--install-toolchain]

print_usage() {
  cat <<EOF
Usage: $0 [--force] [--workspace DIR] [--no-build] [--run-build] [--run-install] [--run-clean] [--install-toolchain]

Options:
  --force               Remove existing workspace directory before cloning (use with care)
  --workspace DIR       Base workspace directory (overrides WORKSPACE_DIR from .toolbox.env)
  --no-build            Do not run the build step (skip configure+build)
  --run-build           Run configure + build (does NOT run 'cmake --install')
  --run-install         Run configure + build and then install binaries to LLAMA_INSTALL_DIR
  --run-clean           Reset the repo to a clean state matching origin HEAD
  --install-toolchain   Install required build toolchain packages via apt
  -h, --help            Show this help
EOF
}

# Source environment overrides if present
if [ -f "$(dirname "$0")/.build.env" ]; then
  # shellcheck disable=SC1090
  source "$(dirname "$0")/.build.env"
elif [ -f "$(dirname "$0")/.toolbox.env" ]; then
  # shellcheck disable=SC1090
  source "$(dirname "$0")/.toolbox.env"
fi

FORCE=0
NO_BUILD=0
RUN_BUILD=0
RUN_INSTALL=0
RUN_CLEAN=0
INSTALL_TOOLCHAIN=0
WORKSPACE_BASE="${WORKSPACE_DIR:-/workspace}"

# simple arg parsing
while [ "$#" -gt 0 ]; do
  case "$1" in
    --force) FORCE=1; shift;;
    --no-build) NO_BUILD=1; shift;;
    --run-build) RUN_BUILD=1; shift;;
    --run-install) RUN_INSTALL=1; shift;;
    --run-clean) RUN_CLEAN=1; shift;;
    --install-toolchain) INSTALL_TOOLCHAIN=1; shift;;
    --workspace) WORKSPACE_BASE="$2"; shift 2;;
    -h|--help) print_usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; print_usage; exit 2;;
  esac
done

WORKSPACE_BASE="${WORKSPACE_BASE%/}"
TARGET_DIR="${WORKSPACE_BASE}/llama.cpp"

# Default install dir from .build.env or fallback
LLAMA_INSTALL_DIR="${LLAMA_INSTALL_DIR:-/opt/llama}"

echo "[03] Workspace base: ${WORKSPACE_BASE}"
echo "[03] Target clone dir: ${TARGET_DIR}"
echo "[03] Install prefix: ${LLAMA_INSTALL_DIR}"

# Ensure git is available
if ! command -v git >/dev/null 2>&1; then
  echo "Error: git not found in PATH. Install git in the toolbox or host environment." >&2
  exit 3
fi

# If the repo exists and we requested a clean, perform a hard reset and clean
if [ -d "$TARGET_DIR/.git" ] && [ "$RUN_CLEAN" -eq 1 ]; then
  echo "[03] --run-clean specified: cleaning repository at $TARGET_DIR"
  git -C "$TARGET_DIR" fetch --all --prune
  DEFAULT_BRANCH=$(git -C "$TARGET_DIR" remote show origin | sed -n 's/.*HEAD branch: //p' | tr -d '\r')
  if [ -z "$DEFAULT_BRANCH" ]; then
    DEFAULT_BRANCH="main"
  fi
  echo "[03] Resetting to origin/$DEFAULT_BRANCH"
  git -C "$TARGET_DIR" reset --hard "origin/$DEFAULT_BRANCH"
  git -C "$TARGET_DIR" clean -fdx
  echo "[03] Repository cleaned to origin/$DEFAULT_BRANCH"
  exit 0
fi

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

# Ensure workspace base exists
CUR_UID=$(id -u)
CUR_GID=$(id -g)
if mkdir -p "$WORKSPACE_BASE" 2>/dev/null; then
  :
else
  echo "[03] Warning: cannot create '$WORKSPACE_BASE' as current user. Trying with sudo..."
  if command -v sudo >/dev/null 2>&1; then
    if sudo mkdir -p "$WORKSPACE_BASE" 2>/dev/null; then
      echo "[03] Created '$WORKSPACE_BASE' with sudo. Attempting to fix ownership to the current user ($CUR_UID:$CUR_GID)."
      if sudo chown "$CUR_UID:$CUR_GID" "$WORKSPACE_BASE" 2>/dev/null; then
        echo "[03] Ownership updated. Workspace is now writable by the current user."
      else
        echo "[03] Warning: failed to chown '$WORKSPACE_BASE'. Will attempt sudo-based clone later." >&2
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

# Ensure variables reflect any change
WORKSPACE_BASE="${WORKSPACE_BASE%/}"
TARGET_DIR="${WORKSPACE_BASE}/llama.cpp"

# Check writability; if not writable we will perform sudo clone and then fix ownership
NEED_SUDO_CLONE=0
if [ ! -w "$WORKSPACE_BASE" ]; then
  echo "[03] Workspace base '$WORKSPACE_BASE' is not writable by current user. Will use sudo for cloning and then fix ownership."
  NEED_SUDO_CLONE=1
fi

# Clone if missing
if [ ! -d "$TARGET_DIR/.git" ]; then
  echo "[03] Cloning llama.cpp into $TARGET_DIR"
  if [ "$NEED_SUDO_CLONE" -eq 1 ]; then
    echo "[03] Running 'sudo git clone' into protected path. This will create files owned by root which will be chowned back to the current user."
    sudo git clone https://github.com/ggml-org/llama.cpp.git "$TARGET_DIR"
    sudo chown -R "$CUR_UID:$CUR_GID" "$TARGET_DIR" || true
  else
    git clone https://github.com/ggml-org/llama.cpp.git "$TARGET_DIR"
  fi
fi

# Record commit hash
COMMIT_HASH=$(git -C "$TARGET_DIR" rev-parse --short HEAD)
echo "$COMMIT_HASH" > "$TARGET_DIR/build-commit.txt"

echo "[03] Commit recorded: $COMMIT_HASH -> $TARGET_DIR/build-commit.txt"

# If requested, install toolchain packages via apt
if [ "${INSTALL_TOOLCHAIN:-0}" -eq 1 ]; then
  echo "[03] Installing toolchain packages via apt-get"
  REQUIRED_PACKAGES=(cmake ccache ninja-build build-essential llvm clang libssl-dev pkg-config libomp-dev libcurl4-openssl-dev)
  if command -v apt-get >/dev/null 2>&1; then
    if [ "$(id -u)" -eq 0 ]; then
      DEBIAN_FRONTEND=noninteractive apt-get update -y
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${REQUIRED_PACKAGES[@]}"
    else
      sudo bash -lc "DEBIAN_FRONTEND=noninteractive apt-get update -y && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ${REQUIRED_PACKAGES[*]}"
    fi
  else
    echo "[03] apt-get not found; cannot install toolchain packages. Please install manually: ${REQUIRED_PACKAGES[*]}" >&2
    exit 5
  fi

  echo "[03] Toolchain installation complete."

  # If install-toolchain was requested without any build/install/clean flags, exit now.
  if [ "${RUN_BUILD:-0}" -eq 0 ] && [ "${RUN_INSTALL:-0}" -eq 0 ] && [ "${RUN_CLEAN:-0}" -eq 0 ] && [ "${NO_BUILD:-0}" -eq 0 ]; then
    echo "[03] --install-toolchain specified alone: exiting after toolchain install."
    exit 0
  fi

  echo "[03] Continuing with requested actions..."
fi

# Determine whether to run build or install
if [ "$RUN_INSTALL" -eq 1 ]; then
  ACTION="install"
elif [ "$RUN_BUILD" -eq 1 ]; then
  ACTION="build"
elif [ "$NO_BUILD" -eq 1 ]; then
  echo "[03] --no-build specified and no --run-build/--run-install: skipping build steps."
  exit 0
else
  # default: run build only (but do not run install)
  ACTION="build"
fi

if [ "$ACTION" = "build" ] || [ "$ACTION" = "install" ]; then
  echo "[03] Configuring and building llama.cpp (commit: $COMMIT_HASH)"
  BUILD_DIR="$TARGET_DIR/build"
  mkdir -p "$BUILD_DIR"

  # Respect GPU target from env if present
  GPU_TARGET="${GPU_TARGET:-gfx1151}"

  # Use install prefix from .toolbox.env or default
  INSTALL_PREFIX="${LLAMA_INSTALL_DIR:-/opt/llama}"

  # Check for required toolchain commands
  MISSING=()
  for cmd in cmake ninja ccache; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      MISSING+=("$cmd")
    fi
  done

  # prefer ROCm clang if present
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
    echo "[03] Please install the missing packages in the toolbox and re-run."
    exit 4
  fi

  # Attempt to detect ROCm device library path (bitcode files)
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

  # Export HIP_DEVICE_LIB_PATH for other tools and add device lib flag to compiler flags
  if [ -n "$ROCM_DEVICE_LIB_PATH" ]; then
    export HIP_DEVICE_LIB_PATH="$ROCM_DEVICE_LIB_PATH"
    DEVICE_LIB_FLAG="--rocm-device-lib-path=${ROCM_DEVICE_LIB_PATH}"
  else
    DEVICE_LIB_FLAG=""
  fi

  # Ensure ROCM_PATH and HIP_PLATFORM are set for CMake/hip-config
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

  # Configure the build (generate into BUILD_DIR)
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

  # Build step: use cmake --build on the build directory and then stop (install happens in --run-install)
  echo "[03] Running build: cmake --build $BUILD_DIR --config Release -j$(nproc)"
  cmake --build "$BUILD_DIR" --config Release -j"$(nproc)" 2>&1 | tee "$TARGET_DIR/build-make.log"

  echo "[03] Build completed. Logs: $TARGET_DIR/build-cmake.log, $TARGET_DIR/build-make.log"

  # If install requested, perform installation step now (cmake --install on the build dir)
  if [ "$ACTION" = "install" ]; then
    echo "[03] Running installation to ${INSTALL_PREFIX}"
    # If not root, try using sudo for installation and then fix ownership
    if [ "$(id -u)" -eq 0 ]; then
      cmake --install "$BUILD_DIR" --prefix "${INSTALL_PREFIX}"
    else
      if command -v sudo >/dev/null 2>&1; then
        echo "[03] Running install with sudo (will chown back to current user afterwards)"
        sudo cmake --install "$BUILD_DIR" --prefix "${INSTALL_PREFIX}"
        sudo chown -R "$CUR_UID:$CUR_GID" "${INSTALL_PREFIX}" || true
      else
        echo "[03] Error: cannot install to ${INSTALL_PREFIX} without root privileges or sudo. Please run this script as root or re-run with --install-toolchain followed by sudo." >&2
        exit 6
      fi
    fi
    echo "[03] Installed to ${INSTALL_PREFIX}"

    # Ensure standard layout: move shared libraries into lib and executables into bin
    mkdir -p "${INSTALL_PREFIX}/lib" "${INSTALL_PREFIX}/bin"
    # Move any shared libs accidentally installed into bin into lib
    bash -c 'shopt -s nullglob; set -e; moved=0; for f in "'"${INSTALL_PREFIX}"'"/bin/*.so*; do if [ -f "$f" ]; then echo "[03] Moving shared lib $f -> '${INSTALL_PREFIX}'/lib/"; mv "$f" "'"${INSTALL_PREFIX}"'"/lib/ || sudo mv "$f" "'"${INSTALL_PREFIX}"'"/lib/ || true; moved=1; fi; done; if [ "$moved" -eq 1 ]; then echo "[03] Shared libraries moved to '${INSTALL_PREFIX}'/lib"; fi'

    # Register library path with ldconfig if we have privileges, otherwise create an env script
    if [ "$(id -u)" -eq 0 ]; then
      echo "${INSTALL_PREFIX}/lib" > "/etc/ld.so.conf.d/llama.conf"
      ldconfig || true
      echo "[03] Registered ${INSTALL_PREFIX}/lib with ldconfig"
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

  echo "[03] Commit recorded in: $TARGET_DIR/build-commit.txt"
fi

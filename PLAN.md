# Implementation Plan

Purpose
- This document describes how to implement the objectives described in `OBJECTIVE.md`. It contains step-by-step actions, commands, verification steps, and expected artifacts for each phase.

Prerequisites
- Host: Ubuntu 24.04 with a Strix Halo GPU and 128 GB RAM.
- Access to the latest AMD ROCm nightly builds (network access required).
- Permissions to create and run distrobox/toolbox containers with GPU passthrough.
- Repository root includes `.toolbox.env` which is sourced by provisioning scripts for configurable defaults.

Phases & Steps

1) Toolbox provisioning
- Create a distrobox/toolbox container using a plain `ubuntu:24.04` image with GPU passthrough enabled. Ensure container runtime supports the following additional args at creation/start time: `--privileged --device /dev/kfd --device /dev/dri`.
- After container creation, install essential packages from the Ubuntu repositories to support the workflow:
  - `git`, `curl`, `wget`, `unzip`, and common build tools (`build-essential`, `cmake`, `python3`, `python3-pip`) as needed.
- Verification:
  - Confirm the container has GPU device nodes present (e.g., `/dev/kfd`, `/dev/dri`).
  - Confirm basic tools installed: `git --version`, `curl --version`, `wget --version`, `unzip -v`.
- Deliverables:
  - A container definition or set of commands used to create the toolbox.
  - The provisioning script `01-provision-toolbox.sh` sources `.toolbox.env` and accepts an optional `-f|--force` flag to force recreation of an existing toolbox; by default it will refuse to overwrite an existing toolbox to prevent accidental destruction.
  - A short provisioning script or checklist.

  Note: Add `LLAMA_INSTALL_DIR` to `.toolbox.env` to control where `llama.cpp` will be installed by `03-build-llamacpp.sh`. Example entry in `.toolbox.env`:

  ```bash
  # Where `cmake --install` places built binaries/libraries. Use a path writable by the toolbox user or ensure sudo is available.
  LLAMA_INSTALL_DIR=/opt/llama
  ```

  If you choose a system path (like `/opt/llama`) ensure the toolbox user has permission to write there or the script will use `sudo` during install. For per-user installs consider `LLAMA_INSTALL_DIR=$HOME/.local/llama`.

2) ROCm installation
- Install the latest ROCm nightly build from AMD within the toolbox.
- Steps should include adding AMD repositories (if needed), installing required ROCm packages, and configuring environment variables per ROCm instructions.
- How to run the `02-install-rocm.sh` script inside the toolbox (example):
  - Ensure the repository workspace (containing `02-install-rocm.sh` and `tools/`) is accessible inside the toolbox (distrobox mounts the calling user's home by default). If needed, copy or bind-mount the project directory into the toolbox.
  - Run the installer interactively from the host:
    - `distrobox enter "$TOOLBOX_NAME" -- bash -lc "bash 02-install-rocm.sh"`
  - Or run the installer non-interactively while piping the discovered tarball directly into `tar` to avoid temporary files (recommended for Dockerfile-friendly flows):
    - `distrobox enter "$TOOLBOX_NAME" -- bash -lc "python3 tools/list_rocm_nightly.py -p linux -t ${GPU_TARGET} -c 1 -q | xargs -I {} sh -c 'wget -O - {} | sudo tar -xzf - -C ${ROCM_HOME}'"`
  - Notes:
    - `02-install-rocm.sh` accepts `--url <tarball-url>` if you prefer to pass the tarball URL directly.
    - Running `wget -O - <URL> | sudo tar -xzf - -C /opt/rocm` avoids writing the tarball to disk and keeps container image layers smaller when used in Dockerfile `RUN` steps.
    - NOTE FOR DOCKERFILES: Prefer the streaming `wget | tar` pattern when constructing Dockerfiles later to minimize intermediate image layer size and avoid creating large temporary files in image layers.
- Verification:
  - Run `rocminfo` (e.g., `${ROCM_HOME}/bin/rocminfo`) and `ldconfig` checks to ensure ROCm is recognized.
  - Confirm `hipcc --version` or `clang` with ROCm support is available.
- Deliverables:
  - Installation commands and versioned package list.
  - Logs capturing successful installation and basic ROCm checks.

3) Build llama.cpp with ROCm
- Clone `https://github.com/ggml-org/llama.cpp.git` at the latest commit (record the commit hash for reproducibility).
- Build steps:
  - Configure the build for ROCm/`gfx1151` target. Set any required environment variables or CMake flags to enable ROCm and `rocWMMA` if available.
  - Run the build and capture build logs.
- Verification:
  - Confirm the produced binary/library links with ROCm libraries.
  - Run a simple GPU detection example (if provided by `llama.cpp`) or run the binary with `--device gpu` (or repository-specific flags) to ensure it selects the GPU.
- Deliverables:
  - Build artifacts (binaries), build logs, and the commit hash used.

4) Validation (inference)
- Acquire a small GGUF model such as `unsloth/gemma-3-1b-it-GGUF` and place it in the toolbox workspace.
- Run an inference using the ROCm-enabled `llama.cpp` build with GPU selected.
- Capture logs including GPU selection, memory usage, and basic output from the model.
- Verification:
  - Confirm inference runs to completion and produces textual output.
  - Record minimal performance metrics (time, memory) and note any errors/warnings.
- Deliverables:
  - Validation log, example model output, and a short verification report.

5) Packaging / trimming ROCm
- Identify the minimal set of ROCm runtime files/libraries required to run inference with the built `llama.cpp` binary.
- Create a trimmed container layout or instructions to produce a minimal runtime image containing only the needed files.
- Verification:
  - Run the inference in a fresh container built from the trimmed layout to confirm functionality.
- Deliverables:
  - List of included runtime files, packaging instructions, and a test showing the trimmed runtime works.

Snapshot / caching

- Save the extracted ROCm layout as a compressed snapshot to avoid re-downloading and re-extracting the tarball. Example (run on the host or inside the toolbox where `/opt/rocm` is already populated):

  ```bash
  sudo tar -C / -czf /path/to/artifacts/rocm-<tag>-$(date +%F).tar.gz opt/rocm
  ```

  Restore the snapshot on a new machine or toolbox with:

  ```bash
  sudo tar -xzf /path/to/artifacts/rocm-<tag>-2026-01-13.tar.gz -C /
  sudo ldconfig
  ```

- Build an OCI/base image that already includes `/opt/rocm` and push it to a registry to reuse across CI and developer machines. Example `Dockerfile` snippet:

  ```dockerfile
  FROM ubuntu:24.04
  COPY rocm-<tag>.tar.gz /tmp/
  RUN tar -xzf /tmp/rocm-<tag>.tar.gz -C / \
      && ldconfig \
      && rm /tmp/rocm-<tag>.tar.gz
  ```

  This approach avoids repeated downloads and extraction during image builds and lets you pull a ready-to-use image in CI or on developer hosts.

- For `distrobox` workflows, keep a host-side cache directory (e.g. `~/rocm-cache/`) and copy or rsync the populated `/opt/rocm` there. When creating or entering a toolbox, bind-mount the cached directory into the toolbox so the installer can skip download/extract steps:

  ```bash
  mkdir -p "$HOME/rocm-cache/rocm-<tag>"
  sudo rsync -aHAX /opt/rocm/ "$HOME/rocm-cache/rocm-<tag>/"
  # Create distrobox using bind mount or copy the cached directory into the toolbox root
  ```

- CI caching: store the tarball (or the extracted `/opt/rocm` tree) as a CI artifact/cache keyed by ROCm tag + GPU target so pipeline jobs can restore it quickly.

Notes:
- Preserve ownership and permissions when creating/restoring snapshots (use `sudo` where required). After restoring, run `ldconfig` and re-source any profile scripts if necessary.
- Snapshots speed up iteration and CI significantly but must be refreshed when you intentionally upgrade to a new ROCm nightly or change GPU target.

Reproducibility
- Record exact commit hashes, package versions, and ROCm nightly build identifiers in a `REPRODUCIBLE.md` or in the deliverable logs.

Notes & Caveats
- ROCm nightly builds change frequently; pin versions when creating reproducible artifacts.
- Device permissions and passthrough arguments depend on the host container runtime; adapt instructions to `podman`, `docker`, or `distrobox` specifics.
- If `rocWMMA` support is incomplete, fallback to the best available ROCm assembly/accelerations and document limitations.
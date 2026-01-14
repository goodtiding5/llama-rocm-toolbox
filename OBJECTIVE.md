# Project Objective

Objective
- Define, build, validate, and package a reproducible toolbox container for experimenting with llama.cpp on AMD GPUs using ROCm and rocWMMA, targeting a Strix Halo GPU (gfx1151) on Ubuntu 24.04.

Scope
- High-level goals: provision a reproducible toolbox container that exposes the host GPU, install and validate a ROCm-enabled `llama.cpp` build for the target GPU `gfx1151`, run an inference on a small GGUF model, and produce a deployable trimmed ROCm runtime.
- Artifact sources: `https://github.com/ggml-org/llama.cpp.git` and the latest AMD ROCm nightly builds.
- Outcomes, not implementation details: this document specifies what we want to accomplish; implementation steps are contained in `PLAN.md`.
- Environment: scripts source a common `.toolbox.env` file for toolbox configuration (see repository root). `.toolbox.env` includes `BASE_IMAGE` to configure the toolbox base image. It was renamed from `.build.env` to clarify its primary role in toolbox setup, analogous to ARG declarations used in Dockerfile/Podman builds. For Dockerfile builds, use ARGS declarations for configuration.
- Note: The provisioning script `01-provision-toolbox.sh` supports a `-f|--force` flag to allow destructive recreation of an existing toolbox; by default it will not overwrite an existing toolbox.

Milestones
1. Provision a toolbox container that exposes the host GPU.
2. Install and configure ROCm inside the toolbox.
3. Build a ROCm-enabled `llama.cpp` targeting `gfx1151`.
4. Validate GPU detection and run a sample inference using a small GGUF model.
5. Trim and package ROCm into a deployable runtime or container layout.

Deliverables
- A reproducible toolbox definition and setup instructions/scripts for provisioning the container with GPU passthrough.
- Build artifacts and concise build logs demonstrating a successful ROCm build of `llama.cpp` for `gfx1151`.
- Validation logs and a short verification report showing GPU detection and a completed inference on the selected model.
- A trimmed ROCm runtime layout or container image (or documented steps to produce one) suitable for deployment.

Assumptions & Constraints
- Host: Ubuntu 24.04 with a Strix Halo GPU and 128 GB RAM.
- ROCm: using the latest ROCm nightly; behavior may change across nightly updates.
- Model: tests use a small GGUF model to keep inference resource requirements modest.
- Target GPU ISA: `gfx1151`.

Success Criteria
- The toolbox container detects the Strix Halo GPU and exposes it inside the container.
- `llama.cpp` builds with ROCm support targeting `gfx1151` and the produced binary runs without fatal errors.
- A test inference using `unsloth/gemma-3-1b-it-GGUF` (or equivalent small model) completes successfully and produces reasonable output.
- ROCm installation is reduced to a deployable minimal runtime or documented container packaging approach.

Notes
- Use the `https://github.com/ggml-org/llama.cpp.git` repository and the latest ROCm nightly available at build time.
- Record versions and exact commits used for reproducibility.

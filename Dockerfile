# Multi-stage Dockerfile for llama.cpp ROCm release
# Follows PLAN.md phases for easier debugging and incremental builds
#
# Build instructions:
#   Default: docker build -t llama-rocm-release .
#   Custom GPU: docker build --build-arg GPU_TARGET=gfx1100 -t llama-rocm-gfx1100 .
#   Run: docker run -it --device /dev/kfd --device /dev/dri llama-rocm-release

# Build arguments for configurable options
ARG BASE_IMAGE=docker.io/library/ubuntu:24.04
ARG GPU_TARGET=gfx1151
ARG BUILD_PLATFORM=linux

# Stage 01: Provision base system (Phase 1 equivalent)
FROM $BASE_IMAGE AS build-stage01

ENV ROCM_HOME=/opt/rocm
ENV GPU_TARGET=${GPU_TARGET}
ENV BUILD_PLATFORM=${BUILD_PLATFORM}
ENV NON_INTERACTIVE=1

# Create workspace and copy project files
RUN mkdir -p /workspace

COPY 00-provision-toolbox.sh 01-prepare-env.sh 02-install-rocm.sh 03-build-llamacpp.sh 04-validate-inference.sh 05-package-rocm.sh /workspace/

# Copy downloads directory for offline builds
COPY downloads /workspace/downloads/

WORKDIR /workspace

# Run 01-prepare-env.sh to install base dependencies
RUN bash 01-prepare-env.sh

# Stage 02: Install ROCm (Phase 2)
FROM build-stage01 AS build-stage02

ENV ROCM_HOME=/opt/rocm
ENV GPU_TARGET=${GPU_TARGET}
ENV BUILD_PLATFORM=${BUILD_PLATFORM}
ENV WORKSPACE_DIR=/workspace
ENV NON_INTERACTIVE=1

# Run 02-install-rocm.sh to install ROCm
RUN bash 02-install-rocm.sh

# Stage 03: Build llama.cpp (Phase 3)
FROM build-stage02 AS build-stage03

ENV ROCM_HOME=/opt/rocm
ENV GPU_TARGET=${GPU_TARGET}
ENV BUILD_PLATFORM=${BUILD_PLATFORM}
ENV WORKSPACE_DIR=/workspace
ENV LLAMA_HOME=/opt/llama
ENV NON_INTERACTIVE=1

# Run 03-build-llamacpp.sh to build and install llama.cpp
RUN bash 03-build-llamacpp.sh

# Stage 05: Package ROCm runtime (Phase 5)
FROM build-stage03 AS build-stage05

ENV ROCM_HOME=/opt/rocm
ENV GPU_TARGET=${GPU_TARGET}
ENV BUILD_PLATFORM=${BUILD_PLATFORM}
ENV WORKSPACE_DIR=/workspace
ENV LLAMA_HOME=/opt/llama
ENV NON_INTERACTIVE=1

# Run 05-package-rocm.sh to package ROCm runtime (no archive to save space)
RUN bash 05-package-rocm.sh --no-archive

# Final Release Stage
FROM $BASE_IMAGE

ENV DEBIAN_FRONTEND=noninteractive
ENV NON_INTERACTIVE=1

# Install runtime dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    libcurl4t64 \
    libssl3t64 \
    libgomp1 \
    libstdc++6 \
    libatomic1 \
    curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy trimmed ROCm runtime from stage5
COPY --from=build-stage05 /opt/rocm /opt/rocm

# Copy llama.cpp installation
COPY --from=build-stage05 /opt/llama /opt/llama

# Copy validation script for inference testing
COPY --from=build-stage05 /workspace/04-validate-inference.sh /workspace/bin/
RUN chmod +x /workspace/bin/04-validate-inference.sh

# Modify ubuntu user to llama
RUN mkdir -p /workspace/models && \
    groupmod -n llama ubuntu && \
    usermod -l llama -d /workspace ubuntu && \
    chown -R llama:llama /workspace

# Set environment (prioritize runtime libraries)
ENV PATH="/opt/rocm/bin:/opt/llama/bin:$PATH" \
    LD_LIBRARY_PATH="/opt/rocm/lib:/opt/llama/lib:$LD_LIBRARY_PATH" \
    HOME=/home/llama

# Switch to llama user
USER llama

WORKDIR /workspace

# Default command
CMD ["/bin/bash"]
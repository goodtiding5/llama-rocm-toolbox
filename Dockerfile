# Multi-stage Dockerfile for llama.cpp ROCm release
# Follows PLAN.md phases for easier debugging

# Multi-stage Dockerfile for llama.cpp ROCm release
# Builds llama.cpp with ROCm support for AMD GPUs, following PLAN.md phases
#
# Build instructions:
#   Default: docker build -t llama-rocm-release .
#   Custom GPU: docker build --build-arg GPU_TARGET=gfx1100 -t llama-rocm-gfx1100 .
#   Run: docker run -it --device /dev/kfd --device /dev/dri llama-rocm-release
#
# Follows PLAN.md phases for easier debugging and incremental builds

# Build arguments for configurable GPU target and platform
ARG GPU_TARGET=gfx1151
ARG BUILD_PLATFORM=linux

# Stage 01: Provision base system (Phase 1 equivalent)
FROM ubuntu:24.04 AS build-stage01

# Create workspace and copy project files
RUN mkdir -p /workspace
COPY .build.env tools/ 00-provision-toolbox.sh 01-install-basics.sh 02-install-rocm.sh 03-build-llamacpp.sh 04-validate-inference.sh 05-package-rocm.sh /workspace/

# Override .build.env with build arguments
RUN sed -i "s/GPU_TARGET=.*/GPU_TARGET=${GPU_TARGET}/" /workspace/.build.env && \
    sed -i "s/BUILD_PLATFORM=.*/BUILD_PLATFORM=${BUILD_PLATFORM}/" /workspace/.build.env

WORKDIR /workspace

# Run 01-install-basics.sh to install base dependencies
RUN bash 01-install-basics.sh

# Stage 02: Install ROCm (Phase 2)
FROM build-stage01 AS build-stage02

# Run 02-install-rocm.sh to install ROCm (non-interactive for container build)
RUN export NON_INTERACTIVE=1 && bash 02-install-rocm.sh

# Stage 03: Build llama.cpp (Phase 3)
FROM build-stage02 AS build-stage03

# Run 03-build-llamacpp.sh to build llama.cpp
RUN bash 03-build-llamacpp.sh --install-toolchain --run-install

# Stage 04: Validate inference (Phase 4, optional)
FROM build-stage03 AS build-stage04

# Run 04-validate-inference.sh for validation (optional, can be skipped)
RUN bash 04-validate-inference.sh || echo "Validation skipped or failed"

# Stage 05: Package ROCm runtime (Phase 5)
FROM build-stage04 AS build-stage05

# Run 05-package-rocm.sh to package ROCm runtime (non-interactive for container build)
RUN NON_INTERACTIVE=1 bash 05-package-rocm.sh

# Final Release Stage
FROM ubuntu:24.04

# Copy trimmed ROCm runtime
COPY --from=build-stage05 /opt/rocm.runtime /opt/rocm

# Copy llama.cpp installation
COPY --from=build-stage05 /opt/llama /opt/llama

# Copy environment script
COPY --from=build-stage05 /opt/rocm.runtime/llama.sh /opt/rocm/

# Copy workspace with scripts and tools (optional, for debugging)
COPY --from=build-stage05 /workspace /workspace

# Create workspace directory
RUN mkdir -p /workspace

# Modify ubuntu user to llama
RUN groupmod -n llama ubuntu && \
    usermod -l llama ubuntu && \
    usermod -d /workspace llama && \
    chown -R llama:llama /workspace && \
    chown -R llama:llama /opt/rocm && \
    chown -R llama:llama /opt/llama

# Set environment
ENV PATH="/opt/rocm/bin:/opt/llama/bin:$PATH" \
    LD_LIBRARY_PATH="/opt/rocm/lib:$LD_LIBRARY_PATH" \
    HOME=/workspace

# Switch to llama user
USER llama
WORKDIR /workspace

# Default command
CMD ["/bin/bash"]
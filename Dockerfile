# Single-stage Dockerfile for llama.cpp ROCm release
# Builds llama.cpp with ROCm support for AMD GPUs in one stage to save disk space
#
# Build instructions:
#   Default: docker build -t llama-rocm-release .
#   Custom GPU: docker build --build-arg GPU_TARGET=gfx1100 -t llama-rocm-gfx1100 .
#   Run: docker run -it --device /dev/kfd --device /dev/dri llama-rocm-release

# Build arguments for configurable GPU target and platform
ARG GPU_TARGET=gfx1151
ARG BUILD_PLATFORM=linux
ARG VALIDATION_REQUIRED=0

FROM ubuntu:24.04

# Create workspace and copy project files
RUN mkdir -p /workspace
COPY . /workspace/

# Override .build.env with build arguments
RUN sed -i "s/GPU_TARGET=.*/GPU_TARGET=${GPU_TARGET}/" /workspace/.build.env && \
    sed -i "s/BUILD_PLATFORM=.*/BUILD_PLATFORM=${BUILD_PLATFORM}/" /workspace/.build.env

WORKDIR /workspace

# Run all phases sequentially
RUN bash 01-install-basics.sh
RUN export NON_INTERACTIVE=1 && bash 02-install-rocm.sh
RUN bash 03-build-llamacpp.sh --install-toolchain --run-install
RUN if [ "$VALIDATION_REQUIRED" = "1" ]; then bash 04-validate-inference.sh || echo "Validation skipped or failed"; fi
RUN NON_INTERACTIVE=1 bash 05-package-rocm.sh

# Remove the old ROCm directory after trimming
RUN rm -rf /opt/rocm

# Rename trimmed runtime back to /opt/rocm
RUN mv /opt/rocm.runtime /opt/rocm

# Create workspace directory (already exists)
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
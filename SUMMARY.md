# llama-rocm-ubuntu24.04

A Docker image providing a runtime environment for [llama.cpp](https://github.com/ggerganov/llama.cpp) with AMD ROCm GPU acceleration support, based on Ubuntu 24.04.

## Overview

This image contains:
- Ubuntu 24.04 base system
- AMD ROCm runtime (trimmed for size)
- llama.cpp built with ROCm support for AMD GPUs
- Pre-installed llama.cpp binaries (e.g., llama-cli, llama-simple)

## Usage

### Running with GPU Access

To run containers with GPU access, ensure your host has AMD GPUs and ROCm drivers installed.

```bash
docker run --rm -it --privileged --device /dev/kfd --device /dev/dri openmtx/llama-rocm-ubuntu24.04
```

### Inference Example

```bash
# Assuming you have a GGUF model file
docker run --rm -v /path/to/models:/workspace openmtx/llama-rocm-ubuntu24.04 llama-cli -m /workspace/model.gguf -p "Hello, world!"
```

## Supported Hardware

- AMD GPUs with ROCm support (e.g., Radeon RX 7000 series, Radeon Pro, Instinct)
- Requires host ROCm installation for GPU passthrough

## Build Information

Built from [llama-rocm-toolbox](https://github.com/goodtiding5/llama-rocm-toolbox) using multi-stage Docker builds for optimization.

## Tags

- `latest`: Latest stable build
- `{timestamp}`: Timestamped builds (e.g., 202501130000)

## License

See the [llama.cpp](https://github.com/ggerganov/llama.cpp) license for details.
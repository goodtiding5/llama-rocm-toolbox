# llama-rocm-toolbox

A reproducible containerized setup for experimenting with [llama.cpp](https://github.com/ggml-org/llama.cpp) on AMD GPUs using ROCm, specifically targeting the Strix Halo (gfx1151).

## 🎯 Overview

This project automates the setup of a GPU-accelerated llama.cpp environment with ROCm support. It provides both local toolbox development and containerized deployment options, following a structured 5-phase build process for reliability and debugging.

## ✨ Features

- **Automated ROCm Setup**: Downloads and installs ROCm nightlies with GPU detection
- **Optimized Builds**: Compiles llama.cpp with ROCm support and performance tuning
- **Runtime Trimming**: Creates minimal ROCm runtime (~50MB vs 4GB full)
- **Multi-Platform**: Supports different AMD GPU targets via build arguments
- **Container Ready**: Docker multi-stage builds with incremental debugging
- **Validation**: Automated inference testing with GPU acceleration

## 🚀 Quick Start

### Docker Build (Recommended)

```bash
# Clone repository
git clone <repository-url>
cd llama-rocm-toolbox

# Build container (default: Strix Halo)
docker build -t llama-rocm .

# Run with GPU access
docker run -it --privileged --device /dev/kfd --device /dev/dri llama-rocm

# Inside container, test inference
source /opt/rocm/llama.sh
llama-simple -m /path/to/model.gguf -n 32 "Hello world"
```

### Local Toolbox Development

**Note**: Requires [distrobox](https://distrobox.it/) for GPU passthrough support.

```bash
# Inspect and customize .build.env if needed
cat .build.env

# Provision toolbox (uses TOOLBOX_NAME from .build.env, default: llama-toolbox)
./00-provision-toolbox.sh

# Enter toolbox and run setup
distrobox enter llama-toolbox
./01-install-basics.sh
./02-install-rocm.sh
./03-build-llamacpp.sh
./04-validate-inference.sh
./05-package-rocm.sh
```

## 📋 Prerequisites

### System Requirements
- **Host OS**: Ubuntu 24.04
- **GPU**: AMD GPU with ROCm support (tested: Radeon 8060S, gfx1151)
- **RAM**: 32GB+ recommended for large models
- **Storage**: 50GB+ free space

### Software Dependencies
- **Docker**: For container builds
- **distrobox**: For toolbox development (optional)
- **Git**: For cloning repositories

### Hardware Setup
Ensure GPU passthrough works:
```bash
# Check GPU visibility
lspci | grep -i amd
ls /dev/kfd /dev/dri
```

## ⚙️ Configuration

Edit `.build.env` to customize your build:

```bash
# GPU target architecture
GPU_TARGET=gfx1151

# Build platform
BUILD_PLATFORM=linux

# Installation paths
ROCM_HOME=/opt/rocm
LLAMA_INSTALL_DIR=/opt/llama
WORKSPACE_DIR=/workspace

# Toolbox settings
TOOLBOX_NAME=llama-toolbox
```

## 🏗️ Build Process

The build follows 5 structured phases (see [PLAN.md](PLAN.md)):

1. **Provision** (01): Set up base system with dependencies
2. **ROCm Install** (02): Download and configure ROCm nightly
3. **Build** (03): Compile llama.cpp with ROCm optimizations
4. **Validate** (04): Test inference with sample prompts
5. **Package** (05): Trim ROCm runtime for deployment

### Docker Multi-Stage Builds

```bash
# Build up to specific phase for debugging
docker build --target build-stage01 -t debug-base .
docker build --target build-stage02 -t debug-rocm .
docker build --target build-stage03 -t debug-build .

# Custom GPU target
docker build --build-arg GPU_TARGET=gfx1100 -t llama-gfx1100 .
```

### Build Arguments

- `GPU_TARGET`: AMD GPU architecture (default: `gfx1151`)
- `BUILD_PLATFORM`: Target platform (default: `linux`)

## 🧪 Testing & Validation

### Automated Testing

The build includes validation:

```bash
# Check ROCm installation
rocminfo

# Test inference
llama-simple -m model.gguf -n 32 "What is the capital of France?"
```

Expected output includes GPU detection and token generation speeds.

### Manual Testing

```bash
# Download test model
HF_HUB_ENABLE_HF_TRANSFER=1 llama-cli \
  --hf unsloth/gemma-3-1b-it-GGUF:Q4_K_XL \
  --prompt "Hello world" \
  --n_predict 32
```

## 🔧 Troubleshooting

### Common Issues

**ROCm Download Fails**
- Check internet connectivity
- Update fallback URL in `02-install-rocm.sh`
- Try different ROCm nightly version

**GPU Not Detected**
- Ensure container runs with `--device /dev/kfd --device /dev/dri`
- Check host GPU drivers: `lsmod | grep amdgpu`
- Verify GPU compatibility with ROCm

**Build Fails**
- Check available RAM (32GB+ recommended)
- Ensure all dependencies installed
- Try incremental builds to isolate issues

**Permission Errors**
- Run Docker with `--privileged` if needed
- Check file ownership in toolbox

### Debug Mode

```bash
# Build to specific stage and inspect
docker run -it debug-build bash

# Check environment
echo $ROCM_HOME
echo $LD_LIBRARY_PATH
rocminfo
```

### Logs and Output

- Build logs: Check Docker output for errors
- Validation output: `validation-output.txt`
- ROCm logs: Check `/var/log/rocm-validation.log` (if exists)

## 📁 Project Structure

```
├── .build.env              # Build configuration
├── .gitignore              # Git ignore rules
├── Dockerfile              # Multi-stage container build
├── *.sh                    # Build scripts (00-05 phases)
├── tools/                  # Helper utilities
├── PLAN.md                 # Implementation plan
├── OBJECTIVE.md            # Project goals and scope
├── TODO.md                 # Outstanding tasks
└── README.md               # This file
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Make changes and test builds
4. Commit changes: `git commit -m 'Add amazing feature'`
5. Push to branch: `git push origin feature/amazing-feature`
6. Open a Pull Request

### Development Guidelines

- Follow the 5-phase structure for new features
- Update documentation for configuration changes
- Test both Docker and toolbox workflows
- Ensure GPU compatibility across targets

## 📄 Documentation

- **[OBJECTIVE.md](OBJECTIVE.md)**: Project goals and success criteria
- **[PLAN.md](PLAN.md)**: Detailed implementation phases
- **[TODO.md](TODO.md)**: Current development status

## ⚖️ License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

Note: This project builds upon other open-source components with their own licenses:
- [llama.cpp](https://github.com/ggml-org/llama.cpp) (MIT)
- [ROCm](https://rocm.docs.amd.com/) (Various licenses)

## 🙏 Acknowledgments

- [llama.cpp](https://github.com/ggml-org/llama.cpp) by Georgi Gerganov
- [ROCm](https://rocm.docs.amd.com/) by AMD
- [distrobox](https://distrobox.it/) for container management

---

**Happy experimenting with llama.cpp on AMD GPUs! 🚀**
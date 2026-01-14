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

### Toolbox Setup (Recommended for Development)

This project uses [distrobox](https://distrobox.it/) to create an isolated Ubuntu environment with GPU passthrough for development and testing.

```bash
# Clone repository
git clone <repository-url>
cd llama-rocm-toolbox

# Provision the toolbox (creates 'llama-toolbox' distrobox with GPU access)
./00-provision-toolbox.sh

# Enter the toolbox
distrobox enter llama-toolbox

# Inside the toolbox, run the setup scripts in order
./01-prepare-env.sh          # Install system dependencies
./02-install-rocm.sh         # Install ROCm nightly build
./03-build-llamacpp.sh       # Build llama.cpp with ROCm support
./04-validate-inference.sh   # Test inference with GPU acceleration
./05-package-rocm.sh         # Optional: Trim ROCm runtime for deployment

# Test inference manually
llama-cli -m models/gemma-3-1b-it-UD-Q4_K_XL.gguf -p "What is the capital of France?" -n 32 -ngl 99
```

### Docker Build (For Production Deployment)

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

### Docker Compose (Production)

For production deployment with API key support:

```bash
# Copy sample environment file and add your API keys
cp .docker.env.sample .docker.env
# Edit .docker.env with your actual API keys

# Download a model using the provided script (recommended - requires uv)
./hf_download.sh unsloth/gemma-3-1b-it-GGUF:Q4_K_XL.gguf

# Or use llama.cpp-style quantization shorthand (auto-resolves to full filename)
./hf_download.sh unsloth/gemma-3-1b-it-GGUF:Q4_K_XL

# Or use the --include flag (equivalent)
./hf_download.sh unsloth/gemma-3-1b-it-GGUF --include Q4_K_XL.gguf

# Force re-download even if file exists (useful for corruption recovery)
./hf_download.sh -f unsloth/gemma-3-1b-it-GGUF:Q4_K_XL

# Remove model files from local storage
./hf_download.sh --remove unsloth/gemma-3-1b-it-GGUF:Q4_K_XL

# Alternative: Download using HuggingFace CLI directly
HF_HUB_ENABLE_HF_TRANSFER=1 huggingface-cli download \
  unsloth/gemma-3-1b-it-GGUF \
  Q4_K_XL.gguf \
  --local-dir ./models \
  --local-dir-use-symlinks False

# Alternative: Use llama-cli to download (downloads to HF cache)
# Inside container: llama-cli -hf unsloth/gemma-3-1b-it-GGUF:Q4_K_XL
# This downloads to /workspace/models (due to HF_HOME setting)

# Update .docker.env to point to the downloaded model
# LLAMA_ARG_MODEL=/workspace/models/models--unsloth--gemma-3-1b-it-GGUF/snapshots/.../Q4_K_XL.gguf
# Or for huggingface-cli downloads: LLAMA_ARG_MODEL=/workspace/models/Q4_K_XL.gguf

# Build and run with docker-compose
docker-compose up --build

# Or run in background
docker-compose up -d --build

## Resource Management

The docker-compose configuration includes resource limits and reservations:

- **CPU**: Reserves 4 cores, limited to 8 cores
- **Memory**: Reserves 16GB, limited to 32GB
- **Shared Memory**: 8GB for model operations
- **Memory Lock**: Unlimited for GPU memory management

These limits can be adjusted in `docker-compose.yml` based on your system capabilities and model requirements.

## Model Management

### Model Storage

Models are stored in the `./models` directory on the host and mounted to `/workspace/models` in the container. The `HF_HOME` environment variable is set to `/workspace/models`, so both `huggingface-cli` and `llama-cli -hf` will download models to this location.

Only the models directory is mounted to keep the container focused on model serving.

### Downloading Models

**Note**: The `models/` and `downloads/` directories are tracked by git (via `.gitkeep`) to ensure the directory structure exists, but actual files are ignored for repository size management. Downloads use a local `.cache/` directory to avoid cluttering your global HuggingFace cache.

### Offline ROCm Installation

For offline builds or to reuse downloaded ROCm tarballs:

1. Download the ROCm tarball to `./downloads/`:
   ```bash
   wget -O downloads/therock-dist-linux-gfx1151-7.11.0a20260113.tar.gz \
        https://therock-nightly-tarball.s3.amazonaws.com/therock-dist-linux-gfx1151-7.11.0a20260113.tar.gz
   ```

2. The Docker build will automatically detect and use the existing tarball instead of downloading it again.

The `downloads/` directory is mounted to `/workspace/downloads` in the container for ROCm installation.

#### Using the Download Script (Recommended)

The `hf_download.sh` script supports both downloading and managing model files:

The project includes a convenient `hf_download.sh` script that uses `uvx` (from the `uv` Python package manager) for downloading models without requiring persistent installations. The script can be run from any directory and will always download to the correct `./models` subdirectory relative to the script location.

```bash
# Download a complete model repository
./hf_download.sh microsoft/DialoGPT-medium

# Download specific files using repo:filename syntax
./hf_download.sh unsloth/gemma-3-1b-it-GGUF:Q4_K_XL.gguf

# Or use the --include flag (equivalent)
./hf_download.sh unsloth/gemma-3-1b-it-GGUF --include Q4_K_XL.gguf

# For the Qwen3 model you tried, you can now use the simple llama.cpp-style format:
./hf_download.sh unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF:Q8_K_XL

# Download with additional options
./hf_download.sh <repo-id> --local-dir ./models --include "*.gguf"
```

**Requirements**: Install `uv` first: `curl -LsSf https://astral.sh/uv/install.sh | sh`

The script automatically checks for `uv` installation and provides installation instructions if missing.

#### Alternative Download Methods

```bash
# Download a model using HuggingFace CLI
HF_HUB_ENABLE_HF_TRANSFER=1 huggingface-cli download \
  unsloth/gemma-3-1b-it-GGUF \
  Q4_K_XL.gguf \
  --local-dir ./models \
  --local-dir-use-symlinks False
```

### Switching Models

To switch to a different model:

1. Download the new model to `./models`
2. Update `LLAMA_ARG_MODEL` in `.docker.env` to point to the new model file
3. Restart the container:

```bash
docker-compose down
docker-compose up -d --build
```

**Note**: llama-server loads one model at startup and doesn't support dynamic model switching through API calls. Each model requires a container restart.

**Model Path Formats**:
- `huggingface-cli download --local-dir ./models`: Direct file in `/workspace/models/filename.gguf`
- `llama-cli -hf model:name`: HF cache format in `/workspace/models/models--org--model/snapshots/.../filename.gguf`

### API Usage

Once running, the server provides OpenAI-compatible endpoints:

- **Completions**: `POST /v1/completions`
- **Chat**: `POST /v1/chat/completions`
- **Embeddings**: `POST /v1/embeddings` (if enabled)
- **Health Check**: `GET /v1/health`
```

The `.docker.env` file supports:
- `HF_TOKEN`: Hugging Face API token for model downloads
- `HF_HOME`: HuggingFace cache directory (set to `/workspace/models`)
- `OPENAI_API_KEY`: OpenAI API key for compatible endpoints
- `LLAMA_ARG_MODEL`: Path to the Llama model file (GGUF format)
- `LLAMA_ARG_HOST`: Server host IP (default: 0.0.0.0)
- `LLAMA_ARG_PORT`: Server port (default: 8080)
- `LLAMA_ARG_CTX_SIZE`: Context size for prompt processing
- `LLAMA_ARG_N_GPU_LAYERS`: Number of layers to offload to GPU
- `LLAMA_ARG_API_KEY`: API key for server authentication
- `LLAMA_ARG_THREADS`: Number of CPU threads for generation
- `LLAMA_ARG_EMBEDDING`: Enable embedding extraction endpoint

### Local Toolbox Development

The toolbox provides an isolated Ubuntu 24.04 environment with GPU passthrough. It automatically mounts:
- `./models` → `/workspace/models` (model storage)
- `./downloads` → `/workspace/downloads` (ROCm tarballs)
- `./` → `/workspace` (project files)

```bash
# Provision toolbox (uses TOOLBOX_NAME from .toolbox.env, default: llama-toolbox)
./00-provision-toolbox.sh

# Enter toolbox
distrobox enter llama-toolbox

# Run setup scripts in order (see Quick Start above)
./01-prepare-env.sh
./02-install-rocm.sh
./03-build-llamacpp.sh
./04-validate-inference.sh
./05-package-rocm.sh

# Download models (runs on host, saves to ./models)
exit  # Exit toolbox
./hf_download.sh unsloth/gemma-3-1b-it-GGUF:Q4_K_XL
distrobox enter llama-toolbox  # Re-enter

# Models are now available at /workspace/models/
llama-cli -m /workspace/models/gemma-3-1b-it-UD-Q4_K_XL.gguf -p "Test prompt" -ngl 99
```

**Note**: The toolbox persists across sessions. Use `distrobox stop llama-toolbox` to stop it, and `distrobox rm llama-toolbox` to remove completely.

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

Edit `.toolbox.env` to customize your build:

```bash
# GPU target architecture
GPU_TARGET=gfx1151

# Build platform
BUILD_PLATFORM=linux

# Installation paths
ROCM_HOME=/opt/rocm
LLAMA_HOME=/opt/llama
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

### Pre-Production Validation

Before deploying in production, download a test model and validate inference to ensure ROCm and llama.cpp are working correctly.

#### 1. Install uv (Python Package Manager)
uv is required for fast model downloads:

```bash
# Install uv (one-time)
curl -LsSf https://astral.sh/uv/install.sh | sh
# Restart shell or run: source ~/.bashrc
```

#### 2. Download Test Model
Download a small GGUF model for testing:

```bash
# Download Gemma 3 1B model (Q4_K_XL quantization, ~1.5GB)
./hf_download.sh unsloth/gemma-3-1b-it-GGUF:Q4_K_XL
```

#### 3. Validate Inference
For toolbox:
```bash
distrobox enter llama-toolbox
/workspace/bin/04-validate-inference.sh
```

For Docker:
```bash
# Build and run container
docker-compose up --build -d
# Exec into container
docker-compose exec server /workspace/bin/04-validate-inference.sh
# Or manually: docker-compose exec server llama-cli -m /workspace/models/gemma-3-1b-it-UD-Q4_K_XL.gguf -p "What is the capital of France?" -n 32 -ngl 99
```

Expected output: GPU detection, token generation without errors. If validation fails, check ROCm installation and GPU compatibility.

#### 4. Production Deployment
Once validated:
- Update `.docker.env` with your model path and API settings.
- Change `docker-compose.yml` command to include `--model /workspace/models/your-model.gguf`.
- Run `docker-compose up -d` for production.

### Automated Testing

The build includes validation via `04-validate-inference.sh`:

```bash
# Inside toolbox, after running previous scripts
./04-validate-inference.sh

# Or specify custom binary and model
./04-validate-inference.sh /opt/llama/bin/llama-cli /path/to/model.gguf
```

This script:
- Verifies ROCm installation with `hipconfig` and `rocm-smi`
- Checks for llama-cli binary and model file
- Runs inference with GPU layers (`-ngl 99`) on a test prompt
- Saves output to `validation-output.txt` for inspection

Expected output includes GPU detection and token generation speeds.

### Manual Testing

```bash
# Inside toolbox, test inference with GPU acceleration
llama-cli -m models/gemma-3-1b-it-UD-Q4_K_XL.gguf \
  -p "What is the capital of France?" \
  -n 32 -ngl 99

# Or download and test a model directly
HF_HUB_ENABLE_HF_TRANSFER=1 llama-cli \
  --hf unsloth/gemma-3-1b-it-GGUF:Q4_K_XL \
  -p "Hello world" \
  -n 32 -ngl 99
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
- Check file ownership in toolbox: `sudo chown -R $USER:$USER /workspace`

**Toolbox Issues**
- If GPU not accessible in toolbox: Ensure host has AMDGPU drivers and `/dev/kfd` exists
- Toolbox not starting: Check distrobox logs with `distrobox enter --verbose llama-toolbox`
- ROCm not found in toolbox: Verify `02-install-rocm.sh` completed successfully, check `/opt/rocm/bin/hipconfig`
- Build fails in toolbox: Ensure sufficient RAM (32GB+), check `01-prepare-env.sh` installed dependencies

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
├── .toolbox.env              # Build configuration
├── .cache/                 # Local HuggingFace download cache
├── .gitignore              # Git ignore rules
├── Dockerfile              # Multi-stage container build
├── hf_download.sh          # Model download script using uvx
├── *.sh                    # Build scripts (00-05 phases)
├── tools/                  # Helper utilities
├── models/                 # Downloaded model files (GGUF) - tracked directory
├── downloads/              # ROCm tarballs for offline builds - tracked directory
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
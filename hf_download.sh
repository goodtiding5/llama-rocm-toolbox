#!/bin/bash

# hf_download.sh - Download HuggingFace models using uvx
# Usage: ./hf_download.sh <model-repo-id> [additional-args]

set -e

# Check if uv is installed
if ! command -v uv >/dev/null 2>&1; then
    echo "Error: 'uv' is not installed."
    echo "Please install uv first: curl -LsSf https://astral.sh/uv/install.sh | sh"
    echo "Then restart your shell or run: source ~/.bashrc"
    exit 1
fi

# Parse command line arguments
FORCE=false
SHOW_HELP=false
REMOVE_MODE=false
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            SHOW_HELP=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        --remove)
            REMOVE_MODE=true
            shift
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

# Restore positional arguments
set -- "${POSITIONAL_ARGS[@]}"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="$SCRIPT_DIR/models"
CACHE_DIR="$SCRIPT_DIR/.cache"

# Create directories if they don't exist
mkdir -p "$MODELS_DIR"
mkdir -p "$CACHE_DIR"

# Set HuggingFace cache to local directory
export HF_HUB_CACHE="$CACHE_DIR"
export HF_HOME="$CACHE_DIR"

if [ "$SHOW_HELP" = true ] || [ $# -lt 1 ]; then
    echo "Usage: $0 [options] <model-repo-id[:filename-or-quant]> [additional-args]"
    echo ""
    echo "Options:"
    echo "  -f, --force    Force download even if file already exists"
    echo "  --remove       Remove model files from local storage"
    echo "  -h, --help     Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 microsoft/DialoGPT-medium                    # Download entire repo"
    echo "  $0 -f unsloth/gemma-3-1b-it-GGUF:Q4_K_XL.gguf    # Force download specific file"
    echo "  $0 unsloth/gemma-3-1b-it-GGUF:Q4_K_XL         # Auto-resolve quant to filename"
    echo "  $0 --remove unsloth/gemma-3-1b-it-GGUF:Q4_K_XL  # Remove specific model"
    echo ""
    echo "Note: Use 'uvx hf download <repo-id> --dry-run' to see available files"
    exit 0
fi

# Handle remove mode
if [ "$REMOVE_MODE" = true ]; then
    if [ $# -lt 1 ]; then
        echo "Error: --remove requires a model specifier"
        echo "Usage: $0 --remove <model-repo-id[:filename-or-quant]>"
        exit 1
    fi

    MODEL_SPEC="$1"
    echo "Remove mode: Looking for model files matching '$MODEL_SPEC'"

    # Find files to remove
    if [[ "$MODEL_SPEC" == *":"* ]]; then
        # Has specifier, find specific files
        REPO_ID="${MODEL_SPEC%%:*}"
        SPECIFIER="${MODEL_SPEC#*:}"
        echo "Repository: $REPO_ID"
        echo "Specifier: $SPECIFIER"

        # Find matching files in models directory
        if [[ "$SPECIFIER" == *".gguf" ]] || [[ "$SPECIFIER" == *".bin" ]] || [[ "$SPECIFIER" == *".safetensors" ]]; then
            # Full filename specified
            TARGET_FILE="$MODELS_DIR/$SPECIFIER"
            if [ -f "$TARGET_FILE" ]; then
                echo "Found file: $SPECIFIER"
                read -p "Remove '$SPECIFIER'? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    rm -f "$TARGET_FILE"
                    echo "Removed: $SPECIFIER"
                else
                    echo "Cancelled."
                fi
            else
                echo "File not found: $SPECIFIER"
            fi
        else
            # Quantization specifier - find matching files
            MATCHING_FILES=$(find "$MODELS_DIR" -name "*$SPECIFIER*" -type f \( -name "*.gguf" -o -name "*.bin" -o -name "*.safetensors" \))
            if [ -n "$MATCHING_FILES" ]; then
                echo "Found matching files:"
                echo "$MATCHING_FILES" | while read -r file; do
                    basename "$file"
                done
                read -p "Remove all matching files? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    echo "$MATCHING_FILES" | while read -r file; do
                        rm -f "$file"
                        echo "Removed: $(basename "$file")"
                    done
                else
                    echo "Cancelled."
                fi
            else
                echo "No files found matching quantization '$SPECIFIER'"
            fi
        fi
    else
        # No specifier - remove all files from this repo
        REPO_ID="$MODEL_SPEC"
        echo "Repository: $REPO_ID"
        REPO_FILES=$(find "$MODELS_DIR" -name "*$REPO_ID*" -type f \( -name "*.gguf" -o -name "*.bin" -o -name "*.safetensors" \))
        if [ -n "$REPO_FILES" ]; then
            echo "Found files from repository:"
            echo "$REPO_FILES" | while read -r file; do
                basename "$file"
            done
            read -p "Remove all files from '$REPO_ID'? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo "$REPO_FILES" | while read -r file; do
                    rm -f "$file"
                    echo "Removed: $(basename "$file")"
                done
            else
                echo "Cancelled."
            fi
        else
            echo "No files found from repository '$REPO_ID'"
        fi
    fi
    exit 0
fi

MODEL_REPO="$1"
shift  # Remove first argument, pass remaining to uvx

echo "Downloading model: $MODEL_REPO"
echo "Saving to: $MODELS_DIR"
if [ "$FORCE" = true ]; then
    echo "Force mode: Will re-download existing files"
fi

# Check if dry-run is requested
DRY_RUN=false
if [[ "$*" == *"--dry-run"* ]]; then
    DRY_RUN=true
    echo "Dry-run mode: showing available files without downloading"
fi

# Check if this looks like a repo:filename format
if [[ "$MODEL_REPO" == *":"* ]]; then
    REPO_ID="${MODEL_REPO%%:*}"
    SPECIFIER="${MODEL_REPO#*:}"
    echo "Repository: $REPO_ID"
    echo "Specifier: $SPECIFIER"

    # Check if SPECIFIER looks like a full filename (contains .gguf or similar)
    if [[ "$SPECIFIER" == *".gguf" ]] || [[ "$SPECIFIER" == *".bin" ]] || [[ "$SPECIFIER" == *".safetensors" ]]; then
        # It's already a full filename
        FILENAME="$SPECIFIER"
        echo "Using full filename: $FILENAME"
        echo ""
    else
        # It's a quantization specifier (like Q8_K_XL), find the matching file
        echo "Resolving quantization '$SPECIFIER' to full filename..."
        echo ""

        # Get list of available files
        AVAILABLE_FILES=$(uvx hf download "$REPO_ID" --dry-run 2>/dev/null | grep -E '\.(gguf|bin|safetensors)' | awk '{print $1}')

        if [ -z "$AVAILABLE_FILES" ]; then
            echo "Error: No model files found in repository '$REPO_ID'"
            echo "Try browsing the repository at: https://huggingface.co/$REPO_ID"
            exit 1
        fi

        # Look for files containing the specifier (case-insensitive)
        MATCHING_FILES=$(echo "$AVAILABLE_FILES" | grep -i "$SPECIFIER")

        if [ -z "$MATCHING_FILES" ]; then
            echo "Error: No files found matching quantization '$SPECIFIER'"
            echo "Available model files:"
            echo "$AVAILABLE_FILES"
            echo ""
            echo "Try browsing the repository at: https://huggingface.co/$REPO_ID"
            exit 1
        fi

        # If multiple matches, prefer the first one (user can be more specific if needed)
        FILENAME=$(echo "$MATCHING_FILES" | head -n1)

        if [ $(echo "$MATCHING_FILES" | wc -l) -gt 1 ]; then
            echo "Multiple files match '$SPECIFIER', using: $FILENAME"
            echo "All matches:"
            echo "$MATCHING_FILES"
            echo ""
        else
            echo "Found matching file: $FILENAME"
            echo ""
        fi
    fi

    # Prepare download arguments
    DOWNLOAD_ARGS=("$REPO_ID" "$FILENAME" --local-dir "$MODELS_DIR")
    if [ "$FORCE" = true ]; then
        DOWNLOAD_ARGS+=(--force-download)
        echo "Force download enabled - will re-download even if file exists"
    fi
    DOWNLOAD_ARGS+=("$@")

    # Download the specific file
    if ! uvx hf download "${DOWNLOAD_ARGS[@]}" 2>&1; then
        echo ""
        echo "Error: Failed to download '$FILENAME' from repository '$REPO_ID'"
        echo "Possible causes:"
        echo "  - Repository or file does not exist"
        echo "  - Repository is private (set HF_TOKEN)"
        echo "  - Network connectivity issues"
        echo "  - Invalid filename or repository ID"
        echo ""
        echo "Try browsing the repository at: https://huggingface.co/$REPO_ID"
        echo "Or use 'uvx hf download $REPO_ID --dry-run' to see available files"
        exit 1
    fi
else
    # Prepare download arguments
    DOWNLOAD_ARGS=("$MODEL_REPO" --local-dir "$MODELS_DIR")
    if [ "$FORCE" = true ]; then
        DOWNLOAD_ARGS+=(--force-download)
        echo "Force download enabled - will re-download even if files exist"
    fi
    DOWNLOAD_ARGS+=("$@")

    # Download entire repository
    if ! uvx hf download "${DOWNLOAD_ARGS[@]}" 2>&1; then
        echo ""
        echo "Error: Failed to download repository '$MODEL_REPO'"
        echo "Possible causes:"
        echo "  - Repository does not exist"
        echo "  - Repository is private (set HF_TOKEN)"
        echo "  - Network connectivity issues"
        echo ""
        echo "Try browsing at: https://huggingface.co/$MODEL_REPO"
        exit 1
    fi
fi

# Show success message only for actual downloads
if [ "$DRY_RUN" = false ]; then
    echo "Download completed successfully!"
    echo "Model saved to $MODELS_DIR"
    echo ""
    echo "To use this model, update LLAMA_ARG_MODEL in .docker.env to point to the downloaded file"
    echo "Example: LLAMA_ARG_MODEL=/workspace/models/$FILENAME"
else
    echo ""
    echo "To download for real, remove the --dry-run flag"
fi
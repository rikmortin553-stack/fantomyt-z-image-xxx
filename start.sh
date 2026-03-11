#!/bin/bash
set -euo pipefail

source /opt/venv/bin/activate

WORKDIR=/workspace
COMFY_RUNTIME=/workspace/ComfyUI
COMFY_CACHE=/comfy-cache
CUSTOM_NODES_DIR="$COMFY_RUNTIME/custom_nodes"

mkdir -p "$WORKDIR" "$WORKDIR/output" "$WORKDIR/input" "$WORKDIR/temp" "$WORKDIR/models"
chmod -R 777 "$WORKDIR" || true

if [ ! -d "$COMFY_RUNTIME" ]; then
  cp -r "$COMFY_CACHE" "$COMFY_RUNTIME"
fi
chmod -R 777 "$COMFY_RUNTIME" || true

cd "$COMFY_RUNTIME"

mkdir -p "$CUSTOM_NODES_DIR"
chmod -R 777 "$CUSTOM_NODES_DIR" || true

install_custom_node() {
  local repo_url="$1"
  local dir_name="$2"

  cd "$CUSTOM_NODES_DIR"

  if [ ! -d "$dir_name/.git" ]; then
    git clone --depth 1 "$repo_url" "$dir_name"
  else
    git -C "$dir_name" pull --ff-only || true
  fi

  if [ -f "$dir_name/requirements.txt" ]; then
    pip install -r "$dir_name/requirements.txt" || true
  fi

  chmod -R 777 "$dir_name" || true
  cd "$COMFY_RUNTIME"
}

# Custom nodes from workflow
install_custom_node "https://github.com/rgthree/rgthree-comfy.git" "rgthree-comfy"
install_custom_node "https://github.com/ClownsharkBatwing/RES4LYF.git" "RES4LYF"
install_custom_node "https://github.com/yolain/ComfyUI-Easy-Use.git" "ComfyUI-Easy-Use"
install_custom_node "https://github.com/gseth/ControlAltAI-Nodes.git" "ControlAltAI-Nodes"
install_custom_node "https://github.com/vrgamegirl19/comfyui-vrgamedevgirl.git" "comfyui-vrgamedevgirl"

# Protect GPU ONNX after custom node installs
pip uninstall -y onnxruntime || true
pip install --force-reinstall onnxruntime-gpu || true

# Model directories
mkdir -p models/checkpoints
mkdir -p models/loras
mkdir -p models/vae
mkdir -p models/text_encoders
mkdir -p models/clip_vision
mkdir -p models/diffusion_models
mkdir -p models/controlnet
mkdir -p models/upscale_models
chmod -R 777 models || true

download_file() {
  local dst_dir="$1"
  local filename="$2"
  local url="$3"

  if [ -s "$dst_dir/$filename" ]; then
    echo "[skip] $filename already exists"
    return 0
  fi

  echo "[download] $filename"
  aria2c \
    --allow-overwrite=true \
    --auto-file-renaming=false \
    --check-certificate=false \
    -x 16 -s 16 -k 1M \
    -d "$dst_dir" -o "$filename" "$url" \
    || wget -O "$dst_dir/$filename" "$url"

  test -s "$dst_dir/$filename"
  chmod 666 "$dst_dir/$filename" || true
}

require_env() {
  local var_name="$1"
  if [ -z "${!var_name:-}" ]; then
    echo "[error] Missing required environment variable: $var_name" >&2
    exit 1
  fi
}

# =========================
# Public models
# =========================

# diffusion_models
download_file "models/diffusion_models" "z_image_turbo_bf16.safetensors" "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors?download=true"
download_file "models/diffusion_models" "z_image_bf16.safetensors" "https://huggingface.co/Comfy-Org/z_image/resolve/main/split_files/diffusion_models/z_image_bf16.safetensors?download=true"

# text_encoders
download_file "models/text_encoders" "qwen_3_4b.safetensors" "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors?download=true"

# vae
download_file "models/vae" "ae.safetensors" "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors?download=true"

# upscale_models — ВСЕ ваши апскейлеры
download_file "models/upscale_models" "4xPurePhoto-RealPLSKR.pth" "https://huggingface.co/mp3pintyo/upscale/resolve/8c80d55cdc2cc831912ece1848429cd3be52f9e1/4xPurePhoto-RealPLSKR.pth?download=true"
download_file "models/upscale_models" "4x-UltraSharp.pth" "https://huggingface.co/mp3pintyo/upscale/resolve/8c80d55cdc2cc831912ece1848429cd3be52f9e1/4x-UltraSharp.pth?download=true"
download_file "models/upscale_models" "4x_NMKD-Siax_200k.pth" "https://huggingface.co/uwg/upscaler/resolve/main/ESRGAN/4x_NMKD-Siax_200k.pth?download=true"

# loras — публичные
download_file "models/loras" "image_000003500.safetensors" "https://huggingface.co/Ali4652/z-image-yana/resolve/main/yana%20z%20image_000003500.safetensors?download=true"
download_file "models/loras" "image_000003750.safetensors" "https://huggingface.co/Ali4652/z-image-yana/resolve/main/yana%20z%20image_000003750.safetensors?download=true"

# =========================
# Private / expiring LoRA URLs
# Не хардкодим временные CivitAI-ссылки в образ
# Передавайте их через env при запуске контейнера
# =========================
require_env "FAMEGRID_URL"
require_env "B3TTERNUD3S_URL"

download_file "models/loras" "FameGrid_Revolution.safetensors" "$FAMEGRID_URL"
download_file "models/loras" "b3tternud3s_v3.safetensors" "$B3TTERNUD3S_URL"

jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root > /workspace/jupyter.log 2>&1 &

python main.py --listen 0.0.0.0 --port 3000 --highvram --disable-auto-launch

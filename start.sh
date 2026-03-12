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

# Workflow-derived custom nodes
install_custom_node "https://github.com/ltdrdata/ComfyUI-Manager.git" "ComfyUI-Manager"
install_custom_node "https://github.com/rgthree/rgthree-comfy.git" "rgthree-comfy"
install_custom_node "https://github.com/ClownsharkBatwing/RES4LYF.git" "RES4LYF"
install_custom_node "https://github.com/yolain/ComfyUI-Easy-Use.git" "ComfyUI-Easy-Use"
install_custom_node "https://github.com/gseth/ControlAltAI-Nodes.git" "ControlAltAI-Nodes"
install_custom_node "https://github.com/vrgamegirl19/comfyui-vrgamedevgirl.git" "comfyui-vrgamedevgirl"

# -----------------------------------------------------------------------------
# ONNX fix:
# 1) remove CPU-only onnxruntime if some custom node pulled it in
# 2) reinstall GPU build WITHOUT deps, so pip does not churn protobuf / numpy / etc.
# -----------------------------------------------------------------------------
pip uninstall -y onnxruntime onnxruntime-gpu || true
pip install --no-deps --force-reinstall onnxruntime-gpu==1.24.3 || true

# Optional sanity check
python - <<'PY' || true
try:
    import onnxruntime as ort
    print("[onnx] version:", ort.__version__)
    print("[onnx] providers:", ort.get_available_providers())
except Exception as e:
    print("[onnx][warn] import/providers check failed:", e)
PY

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
    || wget --content-disposition -O "$dst_dir/$filename" "$url"

  test -s "$dst_dir/$filename"
  chmod 666 "$dst_dir/$filename" || true
}

download_civitai_file() {
  local dst_dir="$1"
  local filename="$2"
  local model_version_id="$3"

  if [ -s "$dst_dir/$filename" ]; then
    echo "[skip] $filename already exists"
    return 0
  fi

  if [ -z "${CIVITAI_TOKEN:-}" ]; then
    echo "[warn] CIVITAI_TOKEN not set, skipping $filename"
    return 0
  fi

  local url="https://civitai.com/api/download/models/${model_version_id}?type=Model&format=SafeTensor&token=${CIVITAI_TOKEN}"

  echo "[download] $filename from CivitAI"
  aria2c \
    --allow-overwrite=true \
    --auto-file-renaming=false \
    --check-certificate=false \
    -x 16 -s 16 -k 1M \
    -d "$dst_dir" -o "$filename" "$url" \
    || wget --content-disposition -O "$dst_dir/$filename" "$url"

  test -s "$dst_dir/$filename"
  chmod 666 "$dst_dir/$filename" || true
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

# upscale_models — all provided upscalers
download_file "models/upscale_models" "4xPurePhoto-RealPLSKR.pth" "https://huggingface.co/mp3pintyo/upscale/resolve/8c80d55cdc2cc831912ece1848429cd3be52f9e1/4xPurePhoto-RealPLSKR.pth?download=true"
download_file "models/upscale_models" "4x-UltraSharp.pth" "https://huggingface.co/mp3pintyo/upscale/resolve/8c80d55cdc2cc831912ece1848429cd3be52f9e1/4x-UltraSharp.pth?download=true"
download_file "models/upscale_models" "4x_NMKD-Siax_200k.pth" "https://huggingface.co/uwg/upscaler/resolve/main/ESRGAN/4x_NMKD-Siax_200k.pth?download=true"

# public loras
download_file "models/loras" "image_000003500.safetensors" "https://huggingface.co/Ali4652/z-image-yana/resolve/main/yana%20z%20image_000003500.safetensors?download=true"
download_file "models/loras" "image_000003750.safetensors" "https://huggingface.co/Ali4652/z-image-yana/resolve/main/yana%20z%20image_000003750.safetensors?download=true"

# =========================
# CivitAI LoRAs via CIVITAI_TOKEN
# =========================
# FameGrid 2nd Gen Z Image Qwen
download_civitai_file "models/loras" "FameGrid_Revolution.safetensors" "2733658"

# Second CivitAI LoRA from your provided modelVersionId
download_civitai_file "models/loras" "b3tternud3s_v3.safetensors" "2474435"

jupyter lab \
  --ip=0.0.0.0 \
  --port=8888 \
  --no-browser \
  --allow-root \
  --ServerApp.token='' \
  --ServerApp.password='' \
  --ServerApp.allow_origin='*' \
  --ServerApp.disable_check_xsrf=True \
  --ServerApp.root_dir=/workspace \
  > /workspace/jupyter.log 2>&1 &

python main.py --listen 0.0.0.0 --port 3000 --highvram --disable-auto-launch

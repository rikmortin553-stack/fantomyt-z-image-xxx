# RTX 4090 / image-oriented ComfyUI build
# Stable stack branch selected from workflow analysis:
# - image workflow
# - no Blackwell-only constraints
# - cache-style ComfyUI restore into /workspace at runtime
FROM runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH="/opt/venv/bin:$PATH"

# 1) System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    wget \
    curl \
    aria2 \
    ffmpeg \
    ca-certificates \
    build-essential \
    ninja-build \
    pkg-config \
    libgl1 \
    libglib2.0-0 && \
    rm -rf /var/lib/apt/lists/*

# 2) Python venv on top of the CUDA/PyTorch base image.
# --system-site-packages keeps the CUDA-compatible torch stack from the base image available inside the venv.
RUN python -m venv --system-site-packages /opt/venv && \
    pip install --upgrade pip setuptools wheel

# 3) Base Python dependencies for this image-oriented workflow branch.
# Keep this list stable and let custom nodes add only what they really need at runtime.
RUN pip install \
    numpy \
    Cython \
    pycocotools \
    opencv-python-headless \
    imageio \
    kornia \
    onnxruntime-gpu \
    ultralytics \
    scikit-image \
    piexif \
    pandas \
    matplotlib \
    pillow \
    scipy \
    segment-anything \
    sqlalchemy \
    spandrel \
    soundfile \
    jupyterlab \
    GitPython \
    dill \
    matrix-client \
    pedalboard

# 4) Prepare ComfyUI inside the image cache directory.
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /comfy-cache && \
    cd /comfy-cache && \
    pip install -r requirements.txt

# 5) Runtime entrypoint
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 3000 8888
CMD ["/bin/bash", "/start.sh"]

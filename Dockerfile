
# ================================================================
# 📦 0.1 基础镜像：cuda:12.6.3-cudnn-devel-ubuntu22.04
# ================================================================
FROM pytorch/pytorch:2.7.0-cuda12.8-cudnn9-devel

WORKDIR /app
# ================================================================
# 🕒 1.1 设置系统时区（上海）
# ================================================================
ENV TZ=Asia/Shanghai
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

RUN echo "🔧 [1.1] 设置系统时区为 ${TZ}..." && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && \
    echo "✅ [1.1] 时区设置完成"

# ================================================================
# 🧱 2.1 安装 Python 3.11 + 基础系统依赖
# ================================================================
RUN echo "🔧 [2.1] 安装 Python 3.11 及系统依赖..." && \
    apt-get update && apt-get upgrade -y && \
    apt-get install -y jq && \
    apt-get install -y --no-install-recommends \
        python3.11 python3.11-venv python3.11-dev \
        wget git git-lfs curl procps bc \
        libgl1 libgl1-mesa-glx libglvnd0 \
        libglib2.0-0 libsm6 libxrender1 libxext6 \
        xvfb build-essential \
        libgoogle-perftools-dev \
        sentencepiece \
        libgtk2.0-dev libgtk-3-dev libjpeg-dev libpng-dev libtiff-dev \
        libopenblas-base libopenmpi-dev \
        apt-transport-https htop nano bsdmainutils \
        lsb-release software-properties-common \
        libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
        libncurses5-dev libncursesw5-dev xz-utils tk-dev libffi-dev liblzma-dev && \
    echo "✅ [2.1] 系统依赖安装完成" && \
    curl -sSL https://bootstrap.pypa.io/get-pip.py -o get-pip.py && \
    python3.11 get-pip.py && \
    rm get-pip.py && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /root/.cache /tmp/* && \
    echo "✅ [2.1] Python 3.11 设置完成"

# ================================================================
# 🧱 3.1 安装 PyTorch Nightly + Torch-TensorRT
# ================================================================
RUN echo "🔧 [3.1] 安装 PyTorch Nightly..." && \
    python3.11 -m pip install --upgrade pip && \
    python3.11 -m pip install \
        torch==2.7.0+cu128 \
        torchvision==0.22.0+cu128 \
        torchaudio==2.7.0+cu128 \
        --extra-index-url https://download.pytorch.org/whl/cu128 \
        --no-cache-dir && \
    rm -rf /root/.cache /tmp/* ~/.cache && \
    echo "✅ [3.1] PyTorch 安装完成"

# ================================================================
# 🧱 2.2 安装构建工具 pip/wheel/setuptools/cmake/ninja
# ================================================================
RUN echo "🔧 [2.2] 安装 Python 构建工具..." && \
    python3.11 -m pip install --upgrade pip setuptools wheel cmake ninja --no-cache-dir && \
    echo "✅ [2.2] 构建工具安装完成"

# ================================================================
# 🧱 3.2 安装 Python 推理相关依赖
# ================================================================
RUN echo "🔧 [3.2] 安装额外 Python 包..." && \
    python3.11 -m pip install --no-cache-dir \
        numpy scipy opencv-python scikit-learn Pillow insightface && \
    rm -rf /root/.cache /tmp/* ~/.cache && \
    echo "✅ [3.2] 其他依赖安装完成"

COPY run.sh /app/run.sh
RUN chmod +x /app/run.sh

RUN useradd -m webui
RUN chown -R webui:webui /app
USER webui
RUN mkdir /app/sd-webui

ENTRYPOINT ["/app/run.sh"]


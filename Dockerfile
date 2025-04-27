FROM nvidia/cuda:12.6.3-runtime-ubuntu22.04

WORKDIR /app

# ===============================
# 🚩 安装系统依赖 & CUDA 工具链
# ===============================
RUN echo -e "🔧 开始安装系统依赖和 CUDA 开发工具...\n" && \
    apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
        wget git git-lfs curl procps \
        python3 python3-pip python3-venv \
        libgl1 libgl1-mesa-glx libglvnd0 libglib2.0-0 \
        libsm6 libxrender1 libxext6 \
        xvfb build-essential cmake bc \
        libgoogle-perftools-dev \
        apt-transport-https htop nano bsdmainutils bsdextrautils \
        lsb-release software-properties-common jq && \
    echo -e "✅ 基础系统依赖安装完成\n" && \
    echo -e "🔧 正在安装 CUDA 12.6 工具链和数学库...\n" && \
    apt-get install -y --no-install-recommends \
        cuda-compiler-12-6 libcublas-12-6 libcublas-dev-12-6 && \
    echo -e "✅ CUDA 工具链安装完成\n" && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY run.sh /app/run.sh
RUN chmod +x /app/run.sh

RUN useradd -m webui
RUN chown -R webui:webui /app
USER webui
RUN mkdir /app/sd-webui

ENTRYPOINT ["/app/run.sh"]


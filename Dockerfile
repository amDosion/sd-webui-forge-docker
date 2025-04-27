
# ================================================================
# 📦 0.1 基础镜像：cuda:12.6.3-cudnn-devel-ubuntu22.04
# ================================================================
FROM nvidia/cuda:12.6.3-cudnn-devel-ubuntu22.04

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
    python3.11 -m pip install --pre \
        torch==2.8.0.dev20250420+cu128 \
        torchvision==0.22.0.dev20250420+cu128 \
        torchaudio==2.6.0.dev20250420+cu128 \
        torch-tensorrt==2.8.0.dev20250420+cu128 \
        --extra-index-url https://download.pytorch.org/whl/nightly/cu128 \
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
# 🧱 2.3 安装 xformers 所需 C++ 系统构建依赖
# ================================================================
RUN echo "🔧 [2.3] 安装 xformers C++ 构建依赖..." && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    g++ ninja-build zip unzip && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /root/.cache /tmp/* && \
    echo "✅ [2.3] xformers 构建依赖安装完成"

# ================================================================
# 🧱 2.4 编译安装 GCC 12.4.0（适配 TensorFlow 构建）
# ================================================================
RUN echo "🔧 安装 GCC 12.4.0..." && \
    apt-get update && \
    apt-get install -y libgmp-dev libmpfr-dev libmpc-dev flex bison file && \
    cd /tmp && \
    wget https://ftp.gnu.org/gnu/gcc/gcc-12.4.0/gcc-12.4.0.tar.xz && \
    tar -xf gcc-12.4.0.tar.xz && cd gcc-12.4.0 && \
    mkdir build && cd build && \
    ../configure \
        --disable-bootstrap \
        --disable-libstdcxx-pch \
        --disable-nls \
        --disable-multilib \
        --disable-werror \
        --enable-languages=c,c++ \
        --without-included-gettext \
        --prefix=/opt/gcc-12.4 \
        --with-gmp=/usr \
        --with-mpfr=/usr \
        --with-mpc=/usr && \
    make -j"$(nproc)" && \
    make install && \
    ln -sf /opt/gcc-12.4/bin/gcc /usr/local/bin/gcc && \
    ln -sf /opt/gcc-12.4/bin/g++ /usr/local/bin/g++ && \
    cd / && rm -rf /tmp/gcc-12.4.0* && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /root/.cache /tmp/* && \
    echo "✅ GCC 12.4 安装完成"

# ================================================================
# 🧠 安装 LLVM/Clang 20 + 设置 apt 源 + gpg key
# ================================================================
RUN mkdir -p /usr/share/keyrings && \
    curl -fsSL https://apt.llvm.org/llvm-snapshot.gpg.key | \
    gpg --dearmor -o /usr/share/keyrings/llvm-archive-keyring.gpg && \
    echo "✅ LLVM GPG Key 安装完成"

RUN echo "deb [signed-by=/usr/share/keyrings/llvm-archive-keyring.gpg] http://apt.llvm.org/jammy/ llvm-toolchain-jammy-20 main" \
    > /etc/apt/sources.list.d/llvm-toolchain-jammy-20.list && \
    echo "✅ 已添加 LLVM apt 软件源"

RUN apt-get update && echo "✅ APT 软件源更新完成"

RUN apt-get install -y --no-install-recommends \
    clang-20 clangd-20 clang-format-20 clang-tidy-20 \
    libclang-common-20-dev libclang-20-dev libclang1-20 \
    lld-20 llvm-20 llvm-20-dev llvm-20-runtime \
    llvm-20-tools libomp-20-dev \
    libc++-20-dev libc++abi-20-dev && \
    echo "✅ LLVM/Clang 20 及依赖组件安装完成"

RUN ln -sf /usr/bin/clang-20 /usr/bin/clang && \
    ln -sf /usr/bin/clang++-20 /usr/bin/clang++ && \
    ln -sf /usr/bin/llvm-config-20 /usr/bin/llvm-config && \
    echo "✅ 创建 clang/clang++/llvm-config 别名完成"

RUN echo "✅ LLVM 工具链版本信息如下：" && \
    echo "🔹 clang:        $(clang --version | head -n1)" && \
    echo "🔹 clang++:      $(clang++ --version | head -n1)" && \
    echo "🔹 ld.lld:       $(ld.lld-20 --version)" && \
    echo "🔹 llvm-config:  $(llvm-config --version)"

RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* && \
    echo "🧹 LLVM 安装完成，APT 缓存已清理"

# ================================================================
# 🧱 2.5 安装 TensorFlow 源码构建依赖
# ================================================================
RUN echo "🔧 [2.5] 安装 TensorFlow 构建依赖..." && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    zlib1g-dev libcurl4-openssl-dev libssl-dev liblzma-dev \
    libtool autoconf automake python-is-python3 \
    expect && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /root/.cache /tmp/* && \
    echo "✅ [2.5] TensorFlow 编译依赖安装完成"

RUN echo "🔧 [2.6] 安装 NCCL 2.25.1 (dev + lib)..." && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    libnccl2=2.25.1-1+cuda12.8 \
    libnccl-dev=2.25.1-1+cuda12.8 && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /root/.cache /tmp/* && \
    echo "✅ [2.6] NCCL 安装完成"

RUN if [ -L /usr/local/cuda-12.8/lib/lib64 ]; then \
      echo '⚠️ 递归软链接检测: 修复 /usr/local/cuda-12.8/lib'; \
      rm -rf /usr/local/cuda-12.8/lib && \
      ln -s /usr/local/cuda-12.8/lib64 /usr/local/cuda-12.8/lib; \
    fi

RUN apt-get update && apt-get install -y --reinstall cuda-cudart-dev-12-8 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN echo "🔍 [2.6] 检查 CUDA / cuDNN / NCCL 安装状态..." && \
    echo "====================== CUDA ======================" && \
    nvcc --version || echo "❌ nvcc 不存在" && \
    echo "📁 CUDA 路径检测：" && \
    ls -l /usr/local/cuda* || echo "❌ 未找到 /usr/local/cuda*" && \
    echo "🔍 libcudart 路径：" && \
    find /usr -name "libcudart*" 2>/dev/null || echo "❌ 未找到 libcudart*" && \
    echo "===================== cuDNN ======================" && \
    echo "🔍 cudnn.h 路径：" && \
    find /usr -name "cudnn.h" 2>/dev/null || echo "❌ 未找到 cudnn.h" && \
    echo "🔍 libcudnn.so 路径：" && \
    find /usr -name "libcudnn.so*" 2>/dev/null || echo "❌ 未找到 libcudnn.so*" && \
    echo "===================== NCCL =======================" && \
    dpkg -l | grep nccl || echo "⚠️ 未通过 dpkg 查询到 NCCL 安装信息" && \
    echo "🔍 libnccl 路径：" && \
    find /usr -name "libnccl.so*" 2>/dev/null || echo "❌ 未找到 libnccl.so*" && \
    echo "🔍 nccl.h 路径：" && \
    find /usr -name "nccl.h" 2>/dev/null || echo "❌ 未找到 nccl.h" && \
    echo "==================================================" && \
    echo "✅ [2.6] CUDA / cuDNN / NCCL 检查完成"

# ================================================================
# 🧱 3.2 安装 Python 推理相关依赖
# ================================================================
RUN echo "🔧 [3.2] 安装额外 Python 包..." && \
    python3.11 -m pip install --no-cache-dir \
        numpy scipy opencv-python scikit-learn Pillow insightface && \
    rm -rf /root/.cache /tmp/* ~/.cache && \
    echo "✅ [3.2] 其他依赖安装完成"

# ================================================================
# 🧱 3.3 安装 Bazelisk（自动管理 Bazel）
# ================================================================
RUN echo "🔧 [3.3] 安装 Bazelisk..." && \
    mkdir -p /usr/local/bin && \
    curl -fsSL https://github.com/bazelbuild/bazelisk/releases/download/v1.25.0/bazelisk-linux-amd64 \
    -o /usr/local/bin/bazelisk && \
    chmod +x /usr/local/bin/bazelisk && \
    ln -sf /usr/local/bin/bazelisk /usr/local/bin/bazel && \
    rm -rf /root/.cache /tmp/* ~/.cache && \
    echo "✅ [3.3] Bazelisk 安装完成"

COPY run.sh /app/run.sh
RUN chmod +x /app/run.sh

RUN useradd -m webui
RUN chown -R webui:webui /app
USER webui
RUN mkdir /app/sd-webui

ENTRYPOINT ["/app/run.sh"]


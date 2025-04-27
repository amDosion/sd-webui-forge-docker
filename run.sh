#!/bin/bash
echo "Starting Stable Diffusion WebUI"
if [ ! -d "/app/sd-webui" ] || [ ! "$(ls -A "/app/sd-webui")" ]; then
  echo "Files not found, cloning..."

  if [ "$UI" = "auto" ]; then
    echo "Using AUTOMATIC1111"
    git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git /app/sd-webui
    cd /app/sd-webui
    git checkout dev
  fi

  if [ "$UI" = "forge" ]; then
    echo "Using Forge"
    git clone https://github.com/lllyasviel/stable-diffusion-webui-forge.git /app/sd-webui
    cd /app/sd-webui
  fi
# =========================================
# 补丁修正 launch_utils.py 强制 torch 版本
# =========================================
PATCH_URL="https://raw.githubusercontent.com/amDosion/forage/main/force_torch_version.patch"
PATCH_FILE="force_torch_version.patch"

echo "🔧 下载补丁文件..."
curl -fsSL -o "$PATCH_FILE" "$PATCH_URL" || { echo "❌ 补丁文件下载失败"; exit 1; }

# 检查 patch 是否已经打过，防止重复 patch
if patch --dry-run -p1 < "$PATCH_FILE" > /dev/null 2>&1; then
    echo "🩹 应用补丁到 modules/launch_utils.py ..."
    patch -p1 < "$PATCH_FILE" || { echo "❌ 应用补丁失败"; exit 1; }
    echo "✅ 补丁应用完成！"
else
    echo "✅ 补丁已经应用过，跳过。"
fi

# 设置环境变量，强制使用固定 Torch 版本
export TORCH_COMMAND="pip install torch==2.6.0+cu126 torchvision==0.21.0+cu126 torchaudio==2.6.0+cu126 --extra-index-url https://download.pytorch.org/whl/cu126"
export FORCE_CUDA="126"

# ---------------------------------------------------
# requirements_versions.txt 修复
# ---------------------------------------------------
echo "🔧 [5] 补丁修正 requirements_versions.txt..."
REQ_FILE="$PWD/requirements_versions.txt"
touch "$REQ_FILE"

# 添加或替换某个依赖版本
add_or_replace_requirement() {
  local package="$1"
  local version="$2"
  if grep -q "^$package==" "$REQ_FILE"; then
    echo "🔁 替换: $package==... → $package==$version"
    sed -i "s|^$package==.*|$package==$version|" "$REQ_FILE"
  else
    echo "➕ 追加: $package==$version"
    echo "$package==$version" >> "$REQ_FILE"
  fi
}

# 推荐依赖版本（将统一写入或替换）
add_or_replace_requirement "xformers" "0.0.29.post3"
add_or_replace_requirement "diffusers" "0.31.0"
add_or_replace_requirement "transformers" "4.46.1"
add_or_replace_requirement "torchdiffeq" "0.2.3"
add_or_replace_requirement "torchsde" "0.2.6"
add_or_replace_requirement "protobuf" "4.25.3"
add_or_replace_requirement "pydantic" "2.6.4"
add_or_replace_requirement "open-clip-torch" "2.24.0"
add_or_replace_requirement "GitPython" "3.1.41"

# 🧹 清理注释和空行，保持纯净格式
echo "🧹 清理注释内容..."
CLEANED_REQ_FILE="${REQ_FILE}.cleaned"
sed 's/#.*//' "$REQ_FILE" | sed '/^\s*$/d' > "$CLEANED_REQ_FILE"
mv "$CLEANED_REQ_FILE" "$REQ_FILE"

# ✅ 输出最终依赖列表
echo "📄 最终依赖列表如下："
cat "$REQ_FILE"

  chmod +x /app/sd-webui/webui.sh

  #i don't really know if this is the best way to do this
# ---------------------------------------------------
# 创建并激活虚拟环境
# ---------------------------------------------------
echo "🔍 创建并激活虚拟环境..."

if [ ! -d "./venv" ]; then
  python3 -m venv venv
fi

source ./venv/bin/activate

# ---------------------------------------------------
# 安装 insightface 工具
# ---------------------------------------------------
echo "🔍 检查 insightface 是否已安装..."
if pip show insightface | grep -q "Version"; then
  echo "✅ insightface 已安装，跳过安装"
else
  echo "📦 安装 insightface..."
  pip install --upgrade "insightface" | tee -a "$LOG_FILE"
fi

# ==================================================
# Hugging Face CLI 安装 + Token 登录
# ==================================================
echo "🔐 [10] Hugging Face CLI 检查与 Token 登录..."

if [[ -n "$HUGGINGFACE_TOKEN" ]]; then
  echo "  - 检测到 HUGGINGFACE_TOKEN，准备登录 Hugging Face..."

  # 检查 huggingface-cli 是否存在
  if ! command -v huggingface-cli &>/dev/null; then
    echo "📦 未检测到 huggingface-cli，安装 huggingface_hub[cli]..."
    pip install --upgrade "huggingface_hub[cli]" | tee -a "$LOG_FILE"
  else
    echo "✅ huggingface-cli 已存在，跳过安装。"
  fi

  # 登录 Hugging Face
  if huggingface-cli login --token "$HUGGINGFACE_TOKEN" --add-to-git-credential; then
    echo "  - ✅ Hugging Face CLI 登录成功。"
  else
    echo "  - ⚠️ Hugging Face CLI 登录失败。请检查 Token 是否正确或 huggingface-cli 是否正常工作。"
  fi

else
  echo "  - ⏭️ 未设置 HUGGINGFACE_TOKEN 环境变量，跳过 Hugging Face 登录。"
fi

# 检查 Civitai API Token
if [[ -n "$CIVITAI_API_TOKEN" ]]; then
  echo "  - ✅ 检测到 CIVITAI_API_TOKEN (长度: ${#CIVITAI_API_TOKEN})。"
else
  echo "  - ⏭️ 未设置 CIVITAI_API_TOKEN 环境变量。"
fi

# ---------------------------------------------------
# 退出虚拟环境
# ---------------------------------------------------
deactivate

  exec /app/sd-webui/webui.sh $ARGS
else
  echo "Files found, starting..."
  cd /app/sd-webui
  git pull
  exec /app/sd-webui/webui.sh $ARGS
fi

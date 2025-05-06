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
export TORCH_COMMAND="pip install torch==2.7.0+cu128 --extra-index-url https://download.pytorch.org/whl/cu128"
export FORCE_CUDA="128"

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
add_or_replace_requirement "torch" "2.7.0+cu128"
add_or_replace_requirement "insightface" "0.7.3"
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

echo "🔧 [2] 解析下载开关环境变量 (默认全部启用)..."
# 解析全局下载开关
ENABLE_DOWNLOAD_ALL="${ENABLE_DOWNLOAD:-true}"

# 解析独立的模型和资源类别开关
ENABLE_DOWNLOAD_EXTS="${ENABLE_DOWNLOAD_EXTS:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_MODEL_SD15="${ENABLE_DOWNLOAD_MODEL_SD15:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_MODEL_SDXL="${ENABLE_DOWNLOAD_MODEL_SDXL:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_MODEL_FLUX="${ENABLE_DOWNLOAD_MODEL_FLUX:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_VAE_FLUX="${ENABLE_DOWNLOAD_VAE_FLUX:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_TE_FLUX="${ENABLE_DOWNLOAD_TE_FLUX:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_CNET_SD15="${ENABLE_DOWNLOAD_CNET_SD15:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_CNET_SDXL="${ENABLE_DOWNLOAD_CNET_SDXL:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_CNET_FLUX="${ENABLE_DOWNLOAD_CNET_FLUX:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_VAE="${ENABLE_DOWNLOAD_VAE:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_LORAS="${ENABLE_DOWNLOAD_LORAS:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_EMBEDDINGS="${ENABLE_DOWNLOAD_EMBEDDINGS:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_UPSCALERS="${ENABLE_DOWNLOAD_UPSCALERS:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_TE="${ENABLE_DOWNLOAD_TE:-$ENABLE_DOWNLOAD_ALL}"  # 为 text_encoder 添加独立的开关
# 解析独立的镜像使用开关
USE_HF_MIRROR="${USE_HF_MIRROR:-false}" # 控制是否使用 hf-mirror.com
USE_GIT_MIRROR="${USE_GIT_MIRROR:-false}" # 控制是否使用 gitcode.net

echo "  - 下载总开关        (ENABLE_DOWNLOAD_ALL): ${ENABLE_DOWNLOAD_ALL}"
echo "  - 下载 Extensions   (ENABLE_DOWNLOAD_EXTS): ${ENABLE_DOWNLOAD_EXTS}"
echo "  - 下载 Checkpoint SD1.5 (ENABLE_DOWNLOAD_MODEL_SD15): ${ENABLE_DOWNLOAD_MODEL_SD15}"
echo "  - 下载 Checkpoint SDXL  (ENABLE_DOWNLOAD_MODEL_SDXL): ${ENABLE_DOWNLOAD_MODEL_SDXL}"
echo "  - 下载 Checkpoint FLUX (ENABLE_DOWNLOAD_MODEL_FLUX): ${ENABLE_DOWNLOAD_MODEL_FLUX}"
echo "  - 下载 VAE FLUX       (ENABLE_DOWNLOAD_VAE_FLUX): ${ENABLE_DOWNLOAD_VAE_FLUX}"
echo "  - 下载 TE FLUX        (ENABLE_DOWNLOAD_TE_FLUX): ${ENABLE_DOWNLOAD_TE_FLUX}"
echo "  - 下载 ControlNet SD1.5 (ENABLE_DOWNLOAD_CNET_SD15): ${ENABLE_DOWNLOAD_CNET_SD15}"
echo "  - 下载 ControlNet SDXL  (ENABLE_DOWNLOAD_CNET_SDXL): ${ENABLE_DOWNLOAD_CNET_SDXL}"
echo "  - 下载 ControlNet FLUX  (ENABLE_DOWNLOAD_CNET_FLUX): ${ENABLE_DOWNLOAD_CNET_FLUX}"
echo "  - 下载 通用 VAE     (ENABLE_DOWNLOAD_VAE): ${ENABLE_DOWNLOAD_VAE}"
echo "  - 下载 LoRAs/LyCORIS (ENABLE_DOWNLOAD_LORAS): ${ENABLE_DOWNLOAD_LORAS}"
echo "  - 下载 Embeddings   (ENABLE_DOWNLOAD_EMBEDDINGS): ${ENABLE_DOWNLOAD_EMBEDDINGS}"
echo "  - 下载 Upscalers    (ENABLE_DOWNLOAD_UPSCALERS): ${ENABLE_DOWNLOAD_UPSCALERS}"
echo "  - 下载 Text Encoders   (ENABLE_DOWNLOAD_TE): ${ENABLE_DOWNLOAD_TE}"  # 输出 Text Encoder 的下载开关
echo "  - 是否使用 HF 镜像  (USE_HF_MIRROR): ${USE_HF_MIRROR}" # (hf-mirror.com)
echo "  - 是否使用 Git 镜像 (USE_GIT_MIRROR): ${USE_GIT_MIRROR}" # (gitcode.net)

# 预定义镜像地址 (如果需要可以从环境变量读取，但简单起见先硬编码)
HF_MIRROR_URL="https://hf-mirror.com"
GIT_MIRROR_URL="https://gitcode.net" # 使用 https

# ==================================================
# 网络测试 (可选)
# ==================================================
echo "🌐 [8] 网络连通性测试 (尝试访问 huggingface.co)..."
NET_OK=false # 默认网络不通
# 使用 curl 测试连接，设置超时时间
if curl -fsS --connect-timeout 5 https://huggingface.co > /dev/null; then
  NET_OK=true
  echo "  - ✅ 网络连通 (huggingface.co 可访问)"
else
  # 如果 Hugging Face 不通，尝试 GitHub 作为备选检查
  if curl -fsS --connect-timeout 5 https://github.com > /dev/null; then
      NET_OK=true # 至少 Git 相关操作可能成功
      echo "  - ⚠️ huggingface.co 无法访问，但 github.com 可访问。部分模型下载可能受影响。"
  else
      echo "  - ❌ 网络不通 (无法访问 huggingface.co 和 github.com)。资源下载和插件更新将失败！"
  fi
fi

# ==================================================
# 资源下载 (使用 resources.txt)
# ==================================================
echo "📦 [9] 处理资源下载 (基于 /app/webui/resources.txt 和下载开关)..."
RESOURCE_PATH="/app/webui/resources.txt" # 定义资源列表文件路径

# 检查资源文件是否存在，如果不存在则尝试下载默认版本
if [ ! -f "$RESOURCE_PATH" ]; then
  # 指定默认资源文件的 URL
  DEFAULT_RESOURCE_URL="https://raw.githubusercontent.com/chuan1127/SD-webui-forge/main/resources.txt"
  echo "  - 未找到本地 resources.txt，尝试从 ${DEFAULT_RESOURCE_URL} 下载..."
  # 使用 curl 下载，确保失败时不输出错误页面 (-f)，静默 (-s)，跟随重定向 (-L)
  curl -fsSL -o "$RESOURCE_PATH" "$DEFAULT_RESOURCE_URL"
  if [ $? -eq 0 ]; then
      echo "  - ✅ 默认 resources.txt 下载成功。"
  else
      echo "  - ❌ 下载默认 resources.txt 失败。请手动将资源文件放在 ${RESOURCE_PATH} 或检查网络/URL。"
      # 创建一个空文件以避免后续读取错误，但不会下载任何内容
      touch "$RESOURCE_PATH"
      echo "  - 已创建空的 resources.txt 文件以继续，但不会下载任何资源。"
  fi
else
  echo "  - ✅ 使用本地已存在的 resources.txt: ${RESOURCE_PATH}"
fi

# 定义函数：克隆或更新 Git 仓库 (支持独立 Git 镜像开关)
clone_or_update_repo() {
    # $1: 目标目录, $2: 原始仓库 URL
    local dir="$1" repo_original="$2"
    local dirname
    local repo_url # URL to be used for cloning/pulling

    dirname=$(basename "$dir")

    # 检查是否启用了 Git 镜像以及是否是 GitHub URL
    if [[ "$USE_GIT_MIRROR" == "true" && "$repo_original" == "https://github.com/"* ]]; then
        local git_mirror_host
        git_mirror_host=$(echo "$GIT_MIRROR_URL" | sed 's|https://||; s|http://||; s|/.*||')
        repo_url=$(echo "$repo_original" | sed "s|github.com|$git_mirror_host|")
        echo "    - 使用镜像转换 (Git): $repo_original -> $repo_url"
    else
        repo_url="$repo_original"
    fi

    # 检查扩展下载开关
    if [[ "$ENABLE_DOWNLOAD_EXTS" != "true" ]]; then
        if [ -d "$dir" ]; then
            echo "    - ⏭️ 跳过更新扩展/仓库 (ENABLE_DOWNLOAD_EXTS=false): $dirname"
        else
            echo "    - ⏭️ 跳过克隆扩展/仓库 (ENABLE_DOWNLOAD_EXTS=false): $dirname"
        fi
        return
    fi

    # 尝试更新或克隆
    if [ -d "$dir/.git" ]; then
        echo "    - 🔄 更新扩展/仓库: $dirname (from $repo_url)"
        (cd "$dir" && git pull --ff-only) || echo "      ⚠️ Git pull 失败: $dirname (可能存在本地修改或网络问题)"
    elif [ ! -d "$dir" ]; then
        echo "    - 📥 克隆扩展/仓库: $repo_url -> $dirname (完整克隆)"
        git clone --recursive "$repo_url" "$dir" || echo "      ❌ Git clone 失败: $dirname (检查 URL: $repo_url 和网络)"
    else
        echo "    - ✅ 目录已存在但非 Git 仓库，跳过 Git 操作: $dirname"
    fi  # ✅ 这里是必须的
}

# 定义函数：下载文件 (支持独立 HF 镜像开关)
download_with_progress() {
    # $1: 输出路径, $2: 原始 URL, $3: 资源类型描述, $4: 对应的下载开关变量值
    local output_path="$1" url_original="$2" type="$3" enabled_flag="$4"
    local filename
    local download_url # URL to be used for downloading

    filename=$(basename "$output_path")

    # 检查下载开关
    if [[ "$enabled_flag" != "true" ]]; then
        echo "    - ⏭️ 跳过下载 ${type} (开关 '$enabled_flag' != 'true'): $filename"
        return
    fi
    # 检查网络
    if [[ "$NET_OK" != "true" ]]; then
        echo "    - ❌ 跳过下载 ${type} (网络不通): $filename"
        return
    fi

    # 检查是否启用了 HF 镜像以及是否是 Hugging Face URL
    # 使用步骤 [2] 中定义的 HF_MIRROR_URL
    if [[ "$USE_HF_MIRROR" == "true" && "$url_original" == "https://huggingface.co/"* ]]; then
        # 替换 huggingface.co 为镜像地址
        download_url=$(echo "$url_original" | sed "s|https://huggingface.co|$HF_MIRROR_URL|")
        echo "    - 使用镜像转换 (HF): $url_original -> $download_url"
    else
        # 使用原始 URL
        download_url="$url_original"
    fi

    # 检查文件是否已存在
    if [ ! -f "$output_path" ]; then
        echo "    - ⬇️ 下载 ${type}: $filename (from $download_url)"
        mkdir -p "$(dirname "$output_path")"
        # 执行下载
        wget --progress=bar:force:noscroll --timeout=120 -O "$output_path" "$download_url"
        # 检查结果
        if [ $? -ne 0 ]; then
            echo "      ❌ 下载失败: $filename from $download_url (检查 URL 或网络)"
            rm -f "$output_path"
        else
            echo "      ✅ 下载完成: $filename"
        fi
    else
        echo "    - ✅ 文件已存在，跳过下载 ${type}: $filename"
    fi
}

# ---------------------------------------------------
# 插件黑名单
# ---------------------------------------------------
SKIP_LIST=(
  "$PWD/extensions/stable-diffusion-aws-extension"
  "$PWD/extensions/sd_dreambooth_extension"
  "$PWD/extensions/stable-diffusion-webui-aesthetic-image-scorer"
)

# 函数：检查目标路径是否应跳过
should_skip() {
  local dir_to_check="$1"
  for skip_dir in "${SKIP_DIRS[@]}"; do
    # 完全匹配路径
    if [[ "$dir_to_check" == "$skip_dir" ]]; then
      return 0 # 0 表示应该跳过 (Bash true)
    fi
  done
  return 1 # 1 表示不应该跳过 (Bash false)
}

echo "  - 开始处理 resources.txt 中的条目..."
# 逐行读取 resources.txt 文件 (逗号分隔: 目标路径,源URL)
while IFS=, read -r target_path source_url || [[ -n "$target_path" ]]; do
  # 清理路径和 URL 的前后空格
  target_path=$(echo "$target_path" | xargs)
  source_url=$(echo "$source_url" | xargs)

  # 跳过注释行 (# 开头) 或空行 (路径或 URL 为空)
  [[ "$target_path" =~ ^#.*$ || -z "$target_path" || -z "$source_url" ]] && continue

  # 在目标路径前加上 $PWD
  full_target_path="$PWD/$target_path"

  # 检查是否在黑名单中
  if should_skip "$full_target_path"; then
    echo "    - ⛔ 跳过黑名单条目: $full_target_path"
    continue # 处理下一行
  fi

  # 根据目标路径判断资源类型并调用相应下载函数及正确的独立开关
  case "$full_target_path" in
    # 1. Extensions
    "$PWD/extensions/"*)
        clone_or_update_repo "$target_path" "$source_url" # Uses ENABLE_DOWNLOAD_EXTS internally
        ;;

    # 2. Stable Diffusion Checkpoints
    "$PWD/models/Stable-diffusion/SD1.5/"*)
        download_with_progress "$target_path" "$source_url" "SD 1.5 Checkpoint" "$ENABLE_DOWNLOAD_MODEL_SD15"
        ;;

    "$PWD/models/Stable-diffusion/XL/"*)
        download_with_progress "$target_path" "$source_url" "SDXL Checkpoint" "$ENABLE_DOWNLOAD_MODEL_SDXL"
        ;;

    "$PWD/models/Stable-diffusion/flux/"*)
        download_with_progress "$target_path" "$source_url" "FLUX Checkpoint" "$ENABLE_DOWNLOAD_MODEL_FLUX"
        ;;

    "$PWD/models/Stable-diffusion/*") # Fallback
        echo "    - ❓ 处理未分类 Stable Diffusion 模型: $full_target_path (默认使用 SD1.5 开关)"
        download_with_progress "$target_path" "$source_url" "SD 1.5 Checkpoint (Fallback)" "$ENABLE_DOWNLOAD_MODEL_SD15"
        ;;

    # 3. VAEs
    "$PWD/models/VAE/flux-*.safetensors") # FLUX Specific VAE
        download_with_progress "$target_path" "$source_url" "FLUX VAE" "$ENABLE_DOWNLOAD_VAE_FLUX" # Use specific FLUX VAE switch
        ;;

    "$PWD/models/VAE/*") # Other VAEs
        download_with_progress "$target_path" "$source_url" "VAE Model" "$ENABLE_DOWNLOAD_VAE"
        ;;

    # 4. Text Encoders (Currently FLUX specific)
    "$PWD/models/text_encoder/*")
        download_with_progress "$target_path" "$source_url" "Text Encoder (FLUX)" "$ENABLE_DOWNLOAD_TE_FLUX" # Use specific FLUX TE switch
        ;;

    # 5. ControlNet Models
    "$PWD/models/ControlNet/"*)
    filename=$(basename "$target_path")
    if [[ "$filename" == control_v11* ]]; then
        # 属于 SD 1.5 的 ControlNet 模型
        download_with_progress "$target_path" "$source_url" "ControlNet SD 1.5" "$ENABLE_DOWNLOAD_CNET_SD15"
    elif [[ "$filename" == *sdxl* || "$filename" == *SDXL* ]]; then
        # 属于 SDXL 的 ControlNet 模型
        download_with_progress "$target_path" "$source_url" "ControlNet SDXL" "$ENABLE_DOWNLOAD_CNET_SDXL"
    elif [[ "$filename" == flux-* || "$filename" == *flux* ]]; then
        # 属于 FLUX 的 ControlNet 模型
        download_with_progress "$target_path" "$source_url" "ControlNet FLUX" "$ENABLE_DOWNLOAD_CNET_FLUX"
    else
        echo "    - ❓ 未识别 ControlNet 模型类别: $filename，默认作为 SD1.5 处理"
        download_with_progress "$target_path" "$source_url" "ControlNet SD 1.5 (Fallback)" "$ENABLE_DOWNLOAD_CNET_SD15"
    fi
    ;;


    # 6. LoRA and related models
    "$PWD/models/Lora/*" | "$PWD/models/LyCORIS/*" | "$PWD/models/LoCon/*")
        download_with_progress "$target_path" "$source_url" "LoRA/LyCORIS" "$ENABLE_DOWNLOAD_LORAS"
        ;;

    # 7. Embeddings / Textual Inversion
    "$PWD/models/TextualInversion/*" | "$PWD/embeddings/*")
       download_with_progress "$target_path" "$source_url" "Embedding/Textual Inversion" "$ENABLE_DOWNLOAD_EMBEDDINGS"
       ;;

    # 8. Upscalers
    "$PWD/models/Upscaler/*" | "$PWD/models/ESRGAN/*")
       download_with_progress "$target_path" "$source_url" "Upscaler Model" "$ENABLE_DOWNLOAD_UPSCALERS"
       ;;

    # 9. Fallback for any other paths
    *)
        if [[ "$source_url" == *.git ]]; then
             echo "    - ❓ 处理未分类 Git 仓库: $full_target_path (默认使用 Extension 开关)"
             clone_or_update_repo "$target_path" "$source_url" # Uses ENABLE_DOWNLOAD_EXTS internally
        elif [[ "$source_url" == http* ]]; then
             echo "    - ❓ 处理未分类文件下载: $full_target_path (默认使用 SD1.5 Model 开关)"
             download_with_progress "$target_path" "$source_url" "Unknown Model/File" "$ENABLE_DOWNLOAD_MODEL_SD15"
        else
             echo "    - ❓ 无法识别的资源类型或无效 URL: target='$target_path', source='$source_url'"
        fi
        ;;
  esac # 结束 case
done < "$RESOURCE_PATH" # 从资源文件读取


 #i don't really know if this is the best way to do this
# ---------------------------------------------------
# 创建并激活虚拟环境
# ---------------------------------------------------
echo "🔍 创建并激活虚拟环境..."
  python3 -m venv venv
   source ./venv/bin/activate
   python -m pip install --upgrade pip
   pip install insightface


TARGET_VERSION="0.0.30+0b3963ad"

# 获取当前已安装的 xformers 版本（如果有）
INSTALLED_VERSION=$(python -c "import importlib.metadata as m; print(m.version('xformers'))" 2>/dev/null || echo "none")

if [ "$INSTALLED_VERSION" = "$TARGET_VERSION" ]; then
    echo "xformers $TARGET_VERSION already installed. Skipping installation."
else
    if [ "$INSTALLED_VERSION" != "none" ]; then
        echo "Detected xformers version $INSTALLED_VERSION. Uninstalling..."
        pip uninstall -y xformers
    else
        echo "xformers not currently installed."
    fi

    echo "Installing xformers $TARGET_VERSION..."
    pip install https://huggingface.co/Alissonerdx/xformers-0.0.30-torch2.7.0-cuda12.8/resolve/main/xformers-0.0.30%2B0b3963ad.d20250210-cp312-cp312-linux_x86_64.whl
fi

-------------------------------------------------
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

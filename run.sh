#!/bin/bash

set -e
set -o pipefail

# 日志文件路径
LOG_FILE="/app/webui/launch.log"

# 确保日志目录存在
mkdir -p "$(dirname "$LOG_FILE")"

# 如果日志文件存在则删除，确保全新记录
if [[ -f "$LOG_FILE" ]]; then
  echo "🧹 检测到旧日志，已清除: $LOG_FILE"
  rm -f "$LOG_FILE"
else
  echo "📁 未检测到旧日志，将创建新日志文件: $LOG_FILE"
fi

# 重定向 stdout 和 stderr 到 tee（写入日志文件 + 控制台）
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "🚀 [0] 启动脚本 Stable Diffusion WebUI"
echo "=================================================="

# ---------------------------------------------------
# 系统环境自检
# ---------------------------------------------------
echo "🛠️  [0.5] 系统环境自检..."

# Python 检查
if command -v python3 &>/dev/null; then
  echo "✅ Python3 版本: $(python3 --version)"
else
  echo "❌ 未找到 Python3，脚本将无法运行！"
  exit 1
fi

# pip 检查
if command -v pip3 &>/dev/null; then
  echo "✅ pip3 版本: $(pip3 --version)"
else
  echo "❌ pip3 未安装！请在 Dockerfile 中添加 python3-pip"
  exit 1
fi

# CUDA & GPU 检查（使用 nvidia-smi 原始图表）
if command -v nvidia-smi &>/dev/null; then
  echo "✅ nvidia-smi 检测成功，GPU 原始信息如下："
  echo "--------------------------------------------------"
  nvidia-smi
  echo "--------------------------------------------------"
else
  echo "⚠️ 未检测到 nvidia-smi（可能无 GPU 或驱动未安装）"
fi


# 容器检测
if [ -f "/.dockerenv" ]; then
  echo "📦 正在容器中运行"
else
  echo "🖥️ 非容器环境"
fi

echo "👤 当前用户: $(whoami)"

if [ -w "/app/webui" ]; then
  echo "✅ /app/webui 可写"
else
  echo "❌ /app/webui 不可写，可能会导致运行失败"
  exit 1
fi

echo "✅ 系统环境自检通过"

# ---------------------------------------------------
# 环境变量设置
# ---------------------------------------------------
echo "🔧 [1] 解析 UI 与 ARGS 环境变量..."
UI="${UI:-forge}"
ARGS="${ARGS:---xformers --api --listen --enable-insecure-extension-access --theme dark}"
echo "🧠 UI=${UI}"
echo "🧠 ARGS=${ARGS}"

echo "🔧 [2] 解析下载开关环境变量..."
ENABLE_DOWNLOAD_ALL="${ENABLE_DOWNLOAD:-true}"
ENABLE_DOWNLOAD_MODELS="${ENABLE_DOWNLOAD_MODELS:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_EXTS="${ENABLE_DOWNLOAD_EXTS:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_CONTROLNET="${ENABLE_DOWNLOAD_CONTROLNET:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_VAE="${ENABLE_DOWNLOAD_VAE:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_TEXT_ENCODERS="${ENABLE_DOWNLOAD_TEXT_ENCODERS:-$ENABLE_DOWNLOAD_ALL}"
ENABLE_DOWNLOAD_TRANSFORMERS="${ENABLE_DOWNLOAD_TRANSFORMERS:-$ENABLE_DOWNLOAD_ALL}"
echo "✅ DOWNLOAD_FLAGS: MODELS=$ENABLE_DOWNLOAD_MODELS, EXTS=$ENABLE_DOWNLOAD_EXTS"

export NO_TCMALLOC=1
export PIP_EXTRA_INDEX_URL="https://download.pytorch.org/whl/cu126"
export TORCH_COMMAND="pip install torch==2.6.0+cu126 --extra-index-url https://download.pytorch.org/whl/cu126"

# ---------------------------------------------------
# 设置 Git 源路径
# ---------------------------------------------------
echo "🔧 [3] 设置仓库路径与 Git 源..."
if [ "$UI" = "auto" ]; then
  TARGET_DIR="/app/webui/sd-webui"
  REPO="https://github.com/AUTOMATIC1111/stable-diffusion-webui.git"
elif [ "$UI" = "forge" ]; then
  TARGET_DIR="/app/webui/sd-webui-forge"
  REPO="https://github.com/lllyasviel/stable-diffusion-webui-forge.git"
else
  echo "❌ Unknown UI: $UI"
  exit 1
fi
echo "📁 目标目录: $TARGET_DIR"
echo "🌐 GIT 源: $REPO"

# ---------------------------------------------------
# 克隆/更新仓库
# ---------------------------------------------------
if [ -d "$TARGET_DIR/.git" ]; then
  echo "🔁 仓库已存在，执行 git pull..."
  git -C "$TARGET_DIR" pull --ff-only || echo "⚠️ Git pull failed"
else
  echo "📥 Clone 仓库..."
  git clone "$REPO" "$TARGET_DIR"
  chmod +x "$TARGET_DIR/webui.sh"
fi

# ---------------------------------------------------
# requirements_versions.txt 修复
# ---------------------------------------------------
echo "🔧 [5] 补丁修正 requirements_versions.txt..."
REQ_FILE="$TARGET_DIR/requirements_versions.txt"
touch "$REQ_FILE"

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

# 推荐依赖版本
add_or_replace_requirement "torch" "2.6.0"
add_or_replace_requirement "xformers" "0.0.29.post3"
add_or_replace_requirement "diffusers" "0.32.0"
add_or_replace_requirement "torchdiffeq" "0.2.3"
add_or_replace_requirement "torchsde" "0.2.6"
add_or_replace_requirement "protobuf" "4.25.3"
add_or_replace_requirement "pydantic" "2.6.4"
add_or_replace_requirement "dill" "0.4.0"
add_or_replace_requirement "onnxruntime-gpu" "1.17.1"
add_or_replace_requirement "controlnet-aux" "0.0.10"
add_or_replace_requirement "open-clip-torch" "2.24.0"

check_gitpython_version() {
  local required_version="3.1.41"
  if python3 -c "import git, sys; from packaging import version; sys.exit(0) if version.parse(git.__version__) >= version.parse('$required_version') else sys.exit(1)" 2>/dev/null; then
    echo "✅ GitPython >= $required_version 已存在"
  else
    echo "🔧 添加 GitPython==$required_version"
    add_or_replace_requirement "GitPython" "$required_version"
  fi
}
check_gitpython_version

echo "📦 最终依赖列表如下："
grep -E '^(torch|xformers|diffusers|transformers|torchdiffeq|torchsde|GitPython|protobuf|pydantic|open-clip-torch)=' "$REQ_FILE" | sort

# ---------------------------------------------------
# Python 虚拟环境
# ---------------------------------------------------
cd "$TARGET_DIR"
chmod -R 777 .

echo "🐍 [6] 虚拟环境检查..."

if [ ! -x "venv/bin/activate" ]; then
  echo "📦 创建 venv..."
  python3 -m venv venv

  echo "🔧 激活 venv..."
  # shellcheck source=/dev/null
  source venv/bin/activate

  echo "🔧 [6.1.1] 安装工具包：insightface, huggingface_hub[cli]..."

  # ---------------------------------------------------
  # 安装工具包（insightface 和 huggingface-cli）
  # ---------------------------------------------------
echo "🔍 检查 insightface 是否已安装..."
if python -m pip show insightface | grep -q "Version"; then
  echo "✅ insightface 已安装，跳过安装"
else
  echo "📦 安装 insightface..."
  python -m pip install --upgrade insightface
fi

echo "📦 venv 安装完成 ✅"
deactivate

else
  echo "✅ venv 已存在，跳过创建和安装"
fi

# ---------------------------------------------------
# 创建目录
# ---------------------------------------------------
echo "📁 [7] 初始化项目目录结构..."
mkdir -p extensions models models/ControlNet outputs

# ---------------------------------------------------
# 网络测试
# ---------------------------------------------------
echo "🌐 [8] 网络连通性测试..."
if curl -s --connect-timeout 3 https://www.google.com > /dev/null; then
  NET_OK=true
  echo "✅ 网络连通 (Google 可访问)"
else
  NET_OK=false
  echo "⚠️ 无法访问 Google，部分资源或插件可能无法下载"
fi

# ---------------------------------------------------
# 插件黑名单
# ---------------------------------------------------
SKIP_LIST=(
  "extensions/stable-diffusion-aws-extension"
  "extensions/sd_dreambooth_extension"
  "extensions/stable-diffusion-webui-aesthetic-image-scorer"
)

should_skip() {
  local dir="$1"
  for skip in "${SKIP_LIST[@]}"; do
    [[ "$dir" == "$skip" ]] && return 0
  done
  return 1
}

# ---------------------------------------------------
# 下载资源
# ---------------------------------------------------
echo "📦 [9] 加载资源资源列表..."
RESOURCE_PATH="/app/webui/resources.txt"
mkdir -p /app/webui

if [ ! -f "$RESOURCE_PATH" ]; then
  echo "📥 下载默认 resources.txt..."
  curl -fsSL -o "$RESOURCE_PATH" https://raw.githubusercontent.com/amDosion/sd-webui-forge-docker/master/resources.txt
else
  echo "✅ 使用本地 resources.txt"
fi

declare -A RESOURCE_DECLARED_PATHS

while IFS=, read -r target_path source_url || [[ -n "$target_path" ]]; do
  target_path=$(echo "$target_path" | xargs)
  source_url=$(echo "$source_url" | xargs)

  [[ "$target_path" =~ ^#.*$ || -z "$target_path" || -z "$source_url" ]] && continue

  if [[ "$target_path" == extensions/* ]]; then
    full_path="$TARGET_DIR/$target_path"
    RESOURCE_DECLARED_PATHS["$full_path"]=1
  fi
done < "$RESOURCE_PATH"

clone_or_update_repo() {
  local dir="$1"
  local repo="$2"
  local full_path="$TARGET_DIR/$dir"

  # 仅对 extensions/* 执行声明判断逻辑
  if [[ "$dir" == extensions/* ]]; then
    if [ -d "$full_path" ]; then
      if [[ -z "${RESOURCE_DECLARED_PATHS[$full_path]}" ]]; then
        echo "⏭️ 跳过本地未声明插件: $full_path"
        return
      fi

      if [ -d "$full_path/.git" ]; then
        echo "🔁 更新插件: $full_path"
        if ! git -C "$full_path" diff --quiet || ! git -C "$full_path" diff --cached --quiet; then
          echo "⚠️ 跳过更新：$full_path 存在本地未提交修改"
          return
        fi
        git -C "$full_path" pull --ff-only || echo "⚠️ Git pull 失败: $full_path"
      else
        echo "⚠️ 非 Git 插件目录存在: $full_path，跳过处理"
      fi
    else
      echo "📥 克隆插件: $repo → $full_path"
      git clone --depth=1 "$repo" "$full_path"
    fi
  else
    echo "❌ 非 extensions 路径传入 clone_or_update_repo: $dir"
  fi
}

download_with_progress() {
  local output="$1"; local url="$2"
  if [ ! -f "$output" ]; then
    echo "⬇️ 下载: $output"
    mkdir -p "$(dirname "$output")"
    wget --show-progress -O "$output" "$url"
  else
    echo "✅ 已存在: $output"
  fi
}

while IFS=, read -r dir url; do
  [[ "$dir" =~ ^#.*$ || -z "$dir" ]] && continue
  if should_skip "$dir"; then
    echo "⛔ 跳过黑名单插件: $dir"
    continue
  fi
  case "$dir" in
    extensions/*)
      [[ "$ENABLE_DOWNLOAD_EXTS" == "true" ]] && clone_or_update_repo "$dir" "$url"
      ;;
    models/ControlNet/*)
      [[ "$ENABLE_DOWNLOAD_CONTROLNET" == "true" && "$NET_OK" == "true" ]] && download_with_progress "$dir" "$url"
      ;;
    models/VAE/*)
      [[ "$ENABLE_DOWNLOAD_VAE" == "true" && "$NET_OK" == "true" ]] && download_with_progress "$dir" "$url"
      ;;
    models/text_encoder/*)
      [[ "$ENABLE_DOWNLOAD_TEXT_ENCODERS" == "true" && "$NET_OK" == "true" ]] && download_with_progress "$dir" "$url"
      ;;
    models/*)
      [[ "$ENABLE_DOWNLOAD_MODELS" == "true" && "$NET_OK" == "true" ]] && download_with_progress "$dir" "$url"
      ;;
    *)
      echo "❓ 未识别资源类型: $dir"
      ;;
  esac
done < "$RESOURCE_PATH"

# ---------------------------------------------------
# 🔥 启动最终服务（FIXED!）
# ---------------------------------------------------
echo "🚀 [11] 所有准备就绪，启动 webui.sh ..."

exec bash webui.sh $ARGS

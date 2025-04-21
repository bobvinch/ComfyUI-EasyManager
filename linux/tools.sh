
# 获取脚本所在目录
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

#创建Python环境，安装依赖
CONDA_PATH="/root/miniconda3"
ENV_PATH="$ROOT_DIR/envs/comfyui"
COMFY_DIR="$ROOT_DIR/ComfyUI"

# 初始化Python环境
function InitializePythonEnv() {
    # 检查 Miniconda 是否已安装
    if [ ! -d "$CONDA_PATH" ]; then
        echo "🚀 安装 Miniconda..."
        wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh
        bash miniconda.sh -b -p $CONDA_PATH
        rm miniconda.sh

        # 初始化 conda
        source "$CONDA_PATH/etc/profile.d/conda.sh"
        conda init bash
    else
        echo "✅ Miniconda 已安装"
        source "$CONDA_PATH/etc/profile.d/conda.sh"
    fi

    # 检查环境是否存在
    if ! conda env list | grep -q "$ENV_PATH"; then
        echo "🚀 创建新的 Python 环境. 3.10.."
        echo "📋 当前的 channels 配置："
        conda config --show channels
        conda create -p "$ENV_PATH" python=3.10 -y --override-channels -c defaults
        echo "✅ Python 环境创建完成"
    else
        echo "✅ Python 环境已存在"
    fi
}


function clone_ComfyUI_repos() {
    echo "==========================="
    echo "🚀 从远程仓库克隆应用到本地"
    echo "==========================="

    # 判断源目录和目标目录是否都不存在
    if  [ ! -d "$COMFY_DIR" ]; then
        echo "🚀 从远程仓库克隆应用到本地"
        git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git "$COMFY_DIR"
    else
        echo "⚠️ ComfyUI已存在（在源目录或目标目录中），跳过克隆步骤"
    fi
}

# 获取HF_TOKEN
tools_get_hf_token() {
    CONFIG_TOML="$ROOT_DIR/config.toml"
    local token=""
    if [ -f "$CONFIG_TOML" ]; then
          # 切换到脚本所在目录
          cd "$ROOT_DIR" || exit
          chmod +x parse_toml.sh

          # --- 调试步骤：查看 parse_toml.sh 的直接输出 ---
#          echo "--- Debug: Output from parse_toml.sh ---"
#          ./parse_toml.sh ./config.toml
#          echo "--- End Debug ---"
          # --- 调试结束 ---

          # 原始命令
          token=$(./parse_toml.sh ./config.toml | jq -r '.authorizations[].huggingface_token // empty')
        if [ "$token" = "null" ]; then
            token=""
        fi
    fi
    echo "$token"
}

  ## 安装aria2c
tools_init_aria2c(){

  if command -v aria2c &> /dev/null; then
      echo "✅ aria2c 已安装，跳过安装步骤"
  else
      echo "==========================="
      echo "🚀 开始安装多线程下载工具"
      echo "==========================="
      echo "📦 更新aria2c依赖，并安装aria2c..."
      apt update -y
      apt install -y aria2
      echo "🚀 aria2c安装成功"
  fi
}



# 通过aria2c下载文件
download_file_by_aria2c() {
    # 检查参数数量
    if [ "$#" -lt 3 ]; then
        echo "❌ 参数不足"
        show_usage
        return 1
    fi

    # 解析参数
    local URL="$1"
    local HEADER="$3"
    local DOWNLOAD_DIR="$4"
    local FILENAME

    # 如果没有提供文件名，从URL中提取
    if [ "$#" -eq 3 ]; then
        # 从URL中提取文件名，先去除查询参数，再获取最后一个路径部分
        FILENAME=$(echo "$URL" | sed 's/[?].*$//' | awk -F'/' '{print $NF}')
        HEADER="$2"
        DOWNLOAD_DIR="$3"
    else
        FILENAME="$2"
    fi

    echo "解析参数，下载地址：URL: $URL, 文件名：$FILENAME, 认证头：$HEADER, 下载目录：$DOWNLOAD_DIR"

    # 检查下载目录是否存在，不存在则创建
    if [ ! -d "$DOWNLOAD_DIR" ]; then
        echo "📁 创建下载目录: $DOWNLOAD_DIR"
        mkdir -p "$DOWNLOAD_DIR"
    fi

    # 完整的下载路径
    local FULL_PATH="$DOWNLOAD_DIR/$FILENAME"
    local ARIA2_TEMP_FILE="$FULL_PATH.aria2" # 定义 aria2 临时文件名

    echo "🚀 开始下载..."
    echo "📥 下载链接: $URL"
    echo "📂 保存为: $FULL_PATH"

    # 检查文件是否已存在且完整 (没有 .aria2 文件)
    if [ -f "$FULL_PATH" ] && [ ! -f "$ARIA2_TEMP_FILE" ]; then
        echo "✅ 文件已存在且完整，跳过下载: $FULL_PATH"
        return 0
    elif [ -f "$ARIA2_TEMP_FILE" ]; then
        echo "⏳ 检测到未完成的下载任务 ($ARIA2_TEMP_FILE)，尝试继续下载..."
    fi

    # 使用 aria2c下载
    local aria_cmd=(aria2c -o "$FILENAME" -d "$DOWNLOAD_DIR" -x 16 -s 16)
    # 如果存在 HEADER，则添加到命令数组中
    [ -n "$HEADER" ] && aria_cmd+=(--header="$HEADER")
    # 添加 URL 到命令数组末尾
    aria_cmd+=("$URL")
    # 预览下载命令
    echo "📝 执行下载命令: ${aria_cmd[*]}"

    if "${aria_cmd[@]}"; then
      echo "✅ 下载完成: $FULL_PATH"
      return 0
    else
      echo "❌ 下载失败"
      return 1
    fi
}

# 检查并安装依赖
check_and_install_dependency() {
    local package="$1"

    # 如果命令已存在，直接返回
    if command -v "$package" &> /dev/null; then
        echo "✅ $package 已安装"
        return 0
    fi

    echo "📦 正在安装 $package..."

    # 检查是否有 sudo 权限
    local sudo_cmd=""
    if [ "$EUID" -ne 0 ]; then
        if command -v sudo &> /dev/null; then
            sudo_cmd="sudo"
        else
            echo "❌ 需要 root 权限来安装包"
            return 1
        fi
    fi

    if command -v apt-get &> /dev/null; then
        # Ubuntu 系统
        $sudo_cmd apt-get update
        case "$package" in
            "yq")
                # 下载到临时目录并正确设置权限
                echo "📥 正在下载 yq..."
                local temp_dir=$(mktemp -d)
                $sudo_cmd wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O "$temp_dir/yq"
                $sudo_cmd chmod 755 "$temp_dir/yq"
                $sudo_cmd mv "$temp_dir/yq" /usr/local/bin/yq
                rm -rf "$temp_dir"
                ;;
            "jq")
                $sudo_cmd apt-get install -y jq
                ;;
            *)
                $sudo_cmd apt-get install -y "$package"
                ;;
        esac
    elif command -v brew &> /dev/null; then
        # MacOS 系统
        brew install "$package"
    else
        echo "❌ 未检测到包管理器"
        echo "💡 Ubuntu 系统请确保已安装 apt-get"
        echo "💡 MacOS 系统请安装 Homebrew："
        echo '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        return 1
    fi

    # 检查安装结果
    if command -v "$package" &> /dev/null; then
        echo "✅ $package 安装成功"
        return 0
    else
        echo "❌ $package 安装失败"
        return 1
    fi
}


export  tools_get_hf_token
export  InitializePythonEnv
export  clone_ComfyUI_repos
export  download_file_by_aria2c
export  tools_init_aria2c
export  check_and_install_dependency
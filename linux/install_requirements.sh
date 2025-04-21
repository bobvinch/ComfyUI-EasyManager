#!/bin/bash





# 获取脚本所在目录
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
echo "脚本所在目录是: $ROOT_DIR"
COMFY_DIR="$ROOT_DIR/ComfyUI"

CONDA_PATH="/root/miniconda3"
ENV_PATH="$ROOT_DIR/envs/comfyui"


#镜像源
echo "🚀 设置默认镜像源为阿里云镜像..."
PIP_MIRROR="https://mirrors.aliyun.com/pypi/simple/"
cd "$ROOT_DIR" || exit
chmod +x parse_toml.sh
CUSTOM_MIRROR=$(./parse_toml.sh ./config.toml | jq -r '.resources[].pip_mirror // empty')
if [ -n "$CUSTOM_MIRROR" ] && [ "$CUSTOM_MIRROR" != "null" ]; then
    if [ "$CUSTOM_MIRROR" != "" ]; then
        PIP_MIRROR="$CUSTOM_MIRROR"
        echo "✅ 已设置 镜像源为用户自定镜像源: $CUSTOM_MIRROR"
    else
        echo "⚠️ config.toml 中的 自定义镜像源为空，使用默认的镜像源：$PIP_MIRROR"
    fi
fi

# 版本比较函数
version_compare() {
    local pkg_name="$1"
    local installed_ver="$2"
    local required_ver="$3"

    # 如果需求文件中没有指定版本，返回 0（表示已安装即可）
    if [[ -z "$required_ver" ]]; then
        return 0
    fi

    # 提取版本比较操作符和版本号
    local operator=$(echo "$required_ver" | grep -o '^[<>=!~]*')
    local version=$(echo "$required_ver" | sed 's/^[<>=!~]*//')

    # 移除版本号中的空格
    version=$(echo "$version" | tr -d ' ')
    installed_ver=$(echo "$installed_ver" | tr -d ' ')

    # 调试输出
    # echo "比较: $installed_ver $operator $version" >&2

    case "$operator" in
        "==" | "")
            if [[ "$installed_ver" == "$version" ]]; then
                return 0
            fi
            ;;
        ">=" )
            python3 -c "from packaging import version; exit(not version.parse('$installed_ver') >= version.parse('$version'))" && return 0
            ;;
        ">" )
            python3 -c "from packaging import version; exit(not version.parse('$installed_ver') > version.parse('$version'))" && return 0
            ;;
        "<=" )
            python3 -c "from packaging import version; exit(not version.parse('$installed_ver') <= version.parse('$version'))" && return 0
            ;;
        "<" )
            python3 -c "from packaging import version; exit(not version.parse('$installed_ver') < version.parse('$version'))" && return 0
            ;;
        "!=" )
            if [[ "$installed_ver" != "$version" ]]; then
                return 0
            fi
            ;;
    esac
    return 1
}


# 提取包名和版本要求的函数
get_package_info() {
    local package="$1"
    local pkg_name=""
    local required_ver=""

    # 检查是否包含版本说明符
    if echo "$package" | grep -q '[=><!~]'; then
        pkg_name=$(echo "$package" | cut -d'=' -f1 | cut -d'>' -f1 | cut -d'<' -f1 | tr -d ' ')
        required_ver=$(echo "$package" | sed -E 's/^[^=<>!~]*([=<>!~]+.*)$/\1/' || echo "")
    else
        pkg_name=$(echo "$package" | tr -d ' ')
        required_ver=""
    fi

    echo "$pkg_name|$required_ver"
}

# 定义依赖安装函数
install_requirements() {
      # 检查参数数量
      if [ $# -lt 2 ]; then
          echo "错误：需要两个参数 - requirements 文件路径和 context"
          return 1
      fi
    local req_file="$1"
    local context="$2"

    if [ ! -f "$req_file" ]; then
        echo "⚠️ 未找到依赖文件: $req_file"
        return 1
    fi

    echo "📦 检查${context}依赖..."

    echo "🔍 获取已安装包列表..."
    # 获取已安装包及其版本
    local installed_packages=$(pip list --format=freeze)

    # 创建临时文件存储需要安装的包
    local to_install=()
    local to_upgrade=()

    while IFS= read -r package || [ -n "$package" ]; do
        # 跳过空行和注释行
        [[ -z "$package" || "$package" =~ ^#.*$ ]] && continue

        # 获取包信息
        IFS='|' read -r pkg_name required_ver <<< "$(get_package_info "$package")"

        # 检查包是否已安装及其版本
        local installed_ver=$(echo "$installed_packages" | grep "^${pkg_name}==" | cut -d'=' -f3)

        if [[ -n "$installed_ver" ]]; then
            if [[ -z "$required_ver" ]]; then
                echo "✅ $pkg_name ($installed_ver) 已安装 $required_ver，跳过"
            elif version_compare "$pkg_name" "$installed_ver" "$required_ver"; then
                echo "✅ $pkg_name ($installed_ver) 已安装且版本 $required_ver 符合要求，跳过"
            else
                echo "⚠️ $pkg_name 需要更新版本 ($installed_ver -> $required_ver)"
                to_upgrade+=("$package")
            fi
        else
            echo "📝 添加 $pkg_name 到安装列表"
            to_install+=("$package")
        fi
    done < "$req_file"


    # 将torch、torchvision、torchaudio的依赖从to_install中移除
    # 创建一个新数组来存储非 torch 相关的包
    filtered_install=()
    for package in "${to_install[@]}"; do
        package_clean=$(echo "$package" | tr -d '[:space:]')
        if [[ "$package_clean" != "torch" && "$package_clean" != "torchvision" && "$package_clean" != "torchaudio" ]]; then
            filtered_install+=("$package")
        else
            echo "� 移除 $package"
        fi
    done
    # 更新原数组
    to_install=("${filtered_install[@]}")

    # 批量安装未安装的包
    if [ ${#to_install[@]} -gt 0 ]; then
        echo "📥 开始安装缺失的依赖..."
        if [ -n "$PIP_MIRROR" ]; then
            # 使用自定义镜像源
            if pip install -i "$PIP_MIRROR" "${to_install[@]}"; then
                echo "✅ 所有依赖安装完成"
            else
                echo "❌ 部分依赖安装失败"
                return 1
            fi
        else
            # 使用默认镜像源
            if pip install "${to_install[@]}"; then
                echo "✅ 所有依赖安装完成"
            else
                echo "❌ 部分依赖安装失败"
                return 1
            fi
        fi
    else
        echo "✅ 所有依赖已安装"
    fi

    # 安装需要手动版本的包
    echo "✅ ${context}依赖检查完成"
}


# 安装自定义节点依赖，包含用户的已经安装的节点
install_custom_node_requirements() {
    local custom_nodes_path="$COMFY_DIR/custom_nodes"

    echo "🔍 开始检查自定义节点依赖..."

    # 确保目录存在
    if [ ! -d "$custom_nodes_path" ]; then
        echo "❌ 自定义节点目录不存在: $custom_nodes_path"
        return
    fi

    # 获取所有子目录
    local node_folders=("$custom_nodes_path"/*/)
    local folder_count=${#node_folders[@]}

    echo "📊 共有 $folder_count 个自定义节点，开始遍历..."

    for folder in "${node_folders[@]}"; do
        local req_file="$folder/requirements.txt"

        if [ -f "$req_file" ]; then
            echo "📦 发现依赖文件: $(basename "$folder")"

            if ! install_requirements "$req_file" "$(basename "$folder")"; then
                echo "💥 安装失败: $(basename "$folder")"
            fi
        else
            echo "⏩ 跳过: $(basename "$folder") (无requirements.txt)"
        fi
    done

    echo "✅ 自定义节点依赖检查完成"
}

# 安装强制指定的依赖
check_forced_dependencies() {
    local config_file="$1"
    local to_install=()

    # 检查配置文件是否存在
    if [ ! -f "$config_file" ]; then
        echo "❌ 配置文件不存在: $config_file"
        return 1
    fi

    echo "🔍 检查强制指定的依赖..."




    # 使用 yq 和 jq 解析 TOML 文件中的包信息，优化包名和版本的处理
    local packages_info=$(yq -o=json eval "$config_file" | jq -r '.packages[] | to_entries[] | select(.value != null) | if .value == "" then .key else .value end')

    # 获取已安装的包列表
    local installed_packages=$(pip list --format=freeze)

    while IFS= read -r package || [ -n "$package" ]; do
        # 跳过空行
        [[ -z "$package" ]] && continue

        # 获取包信息
        IFS='|' read -r pkg_name required_ver <<< "$(get_package_info "$package")"

        # 检查包是否已安装及其版本
        local installed_ver=$(echo "$installed_packages" | grep "^${pkg_name}==" | cut -d'=' -f3)

        if [[ -n "$installed_ver" ]]; then
            if [[ -z "$required_ver" ]]; then
                echo "✅ $pkg_name ($installed_ver) 已安装，跳过"
            elif version_compare "$pkg_name" "$installed_ver" "$required_ver"; then
                echo "✅ $pkg_name ($installed_ver) 已安装且版本符合要求，跳过"
            else
                echo "⚠️ $pkg_name 需要更新版本 ($installed_ver -> $required_ver)"
                to_install+=("$package")
                # 卸载 旧版本
                pip uninstall -y "$pkg_name"

            fi
        else
            echo "📝 添加 $pkg_name 到安装列表"
            to_install+=("$package")
        fi
    done <<< "$packages_info"

    # 如果有需要安装的包，执行安装
    if [ ${#to_install[@]} -gt 0 ]; then
        echo "📦 开始安装依赖..."
        for package in "${to_install[@]}"; do
            echo "正在安装 $package..."
            pip install "$package"
        done
    else
        echo "✨ 所有强制指定的依赖都已满足要求"
    fi
}

# 检查并修复依赖
check_dependencies_conflicts() {
    echo "🔍 检查依赖冲突..."

    local check_output
    check_output=$(pip check 2>&1)
    local exit_code=$?

    # 即使 exit_code 为 0，也检查输出中是否包含依赖问题
    if [ $exit_code -eq 0 ] && ! echo "$check_output" | grep -qiE "requirement|not installed|incompatible|conflicts"; then
        echo "✅ 所有依赖关系正常"
        return 0
    fi

    echo "⚠️ 检测到依赖冲突，开始分析..."
    local to_install=()
    local to_upgrade=()

    while IFS= read -r line; do
        # 匹配格式: package X.X.X has requirement pkg==X.X.X; python_version >= "X.X", but you have pkg X.X.X
        if [[ $line =~ ([^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]+has[[:space:]]+requirement[[:space:]]+([^[:space:]]+)==([^;[:space:]]+)([^,]*,[[:space:]]*but[[:space:]]+you[[:space:]]+have[[:space:]]+[^[:space:]]+[[:space:]]+([^[:space:]]+)) ]]; then
            local parent_pkg="${BASH_REMATCH[1]}"
            local parent_ver="${BASH_REMATCH[2]}"
            local pkg_name="${BASH_REMATCH[3]}"
            local required_ver="${BASH_REMATCH[4]}"
            local current_ver="${BASH_REMATCH[6]}"

            echo "📦 检测到版本冲突: $pkg_name"
            echo "   - 当前版本: $current_ver"
            echo "   - 需求版本: ==$required_ver"
            echo "   - 来自包: $parent_pkg $parent_ver"

            to_upgrade+=("$pkg_name==$required_ver")
        fi
    done <<< "$check_output"

    # 执行修复
    if [ ${#to_upgrade[@]} -gt 0 ]; then
        echo "🔧 开始修复依赖问题..."

        for package in "${to_upgrade[@]}"; do
            local pkg_name=$(echo "$package" | grep -o '^[^><=!~]*')
            echo "🗑️ 卸载 $pkg_name..."
            pip uninstall -y "$pkg_name"

            echo "📥 安装 $package..."
            if ! pip install "$package"; then
                echo "⚠️ 安装 $package 失败，尝试查找兼容版本..."
                local compatible_version=$(pip index versions "$pkg_name" | grep -v "YANKED" | head -n1 | cut -d'(' -f2 | cut -d')' -f1)
                if [ -n "$compatible_version" ]; then
                    echo "📦 尝试安装兼容版本: $pkg_name==$compatible_version"
                    pip install "$pkg_name==$compatible_version"
                fi
            fi
        done

        # 再次检查
        if pip check >/dev/null 2>&1; then
            echo "✨ 所有依赖问题已修复"
        else
            echo "⚠️ 仍存在依赖问题，可能需要手动处理"
            pip check
        fi
    else
        echo "✨ 未检测到需要修复的依赖"
    fi
}


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

function InitializeCustomNodeRepos () {

# 安装节点及节点依赖
cd "$COMFY_DIR/custom_nodes" || exit
# 检查必要的工具是否已安装
for tool in yq jq; do
    if ! command -v $tool &> /dev/null; then
        echo "⚙️ $tool 工具未安装，正在安装..."
        if [ "$tool" = "yq" ]; then
            # 尝试使用 apt 安装
            apt-get update && apt-get install -y wget
            wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
            chmod a+x /usr/local/bin/yq
        elif [ "$tool" = "jq" ]; then
            apt-get update && apt-get install -y jq
        fi

        if [ $? -ne 0 ]; then
            echo "❌ $tool 安装失败，请手动安装后重试"
            exit 1
        fi
        echo "✅ $tool 安装成功"
    fi
done

#检查配置文件是否存在
if [ ! -f "$ROOT_DIR/repos.toml" ]; then
    echo "❌ repos.toml 文件不存在，请检查配置文件路径"
    return 1
fi

# 读取 TOML 文件中的仓库列表
REPOS_URLS=$(yq -o=json eval "$ROOT_DIR/repos.toml" | jq -r '.repos[].url')

# 遍历每个仓库
while IFS= read -r repo; do
    # 获取仓库名称（去除.git后缀）
    repo_name=$(basename "$repo" .git)

    echo "🚀 处理仓库: $repo_name"

    # 检查仓库是否已存在
    if [ -d "$repo_name" ]; then
        echo "⚠️ 仓库已存在，跳过克隆步骤"
        cd "$repo_name" || exit
    else
        if git clone "$repo"; then
            echo "✅ 克隆完成"
            cd "$repo_name" || exit
        else
            echo "❌ 克隆失败: $repo_name"
            continue
        fi
    fi

    if [ -f "requirements.txt" ]; then
        install_requirements "requirements.txt" "插件"
    else
        echo "⚠️ 未找到 requirements.txt 文件"
    fi

    cd ..
    echo "-------------------"
  done <<< "$REPOS_URLS"
}

# 初始化 Python 环境
InitializePythonEnv

# 初始化 conda
source "$CONDA_PATH/etc/profile.d/conda.sh"
conda init bash
# 激活环境
echo "🚀 激活 Python 环境..."
conda activate "$ENV_PATH"

#安装ComfyUI环境依赖
echo "🚀 安装ComfyUI环境依赖"
cd "$COMFY_DIR" || exit
install_requirements "requirements.txt" "ComfyUI"

# 安装节点配置文件中的节点
InitializeCustomNodeRepos

# 安装用户自定义的节点依赖
install_custom_node_requirements

# 检查并修复依赖
check_dependencies_conflicts

# 安装强制指定的依赖
check_forced_dependencies "$ROOT_DIR/config.toml"

echo "✨ 所有仓库处理完成"
#!/bin/bash


# autodl 开启学术加速
if [ -f /etc/network_turbo ]; then
    source /etc/network_turbo
fi

# 导出工具函数
source ./tools.sh

# 函数：显示使用方法
show_usage() {
    echo "使用方法: $0 <HF下载token>"
    echo "示例: $0 'dfd44121xxxxxxx'"
}

# 获取脚本所在目录
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
echo "脚本所在目录是: $ROOT_DIR"
COMFY_DIR="$ROOT_DIR/ComfyUI"


# 初始化工具
init_aria2_and_git_lfs() {
    # 检查必要工具
    for tool in yq aria2c git-lfs; do
        if ! command -v $tool &> /dev/null; then
            echo "⚙️ 安装 $tool..."
            case $tool in
                "yq")
                    wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
                    chmod a+x /usr/local/bin/yq
                    ;;
                "aria2c")
                    apt-get update &&  apt-get install -y aria2
                    ;;
                "git-lfs")
                     apt-get update &&  apt-get install -y git-lfs
                    git lfs install
                    ;;
            esac
        fi
    done
}

# 克隆仓库和下载文件
clone_repos_and_download_file() {
  # 初始化 aria2c 和 git-lfs
  init_aria2_and_git_lfs

# 读取 TOML 文件
REPOS_FILE="$ROOT_DIR/repos_hf.toml"

if [ ! -f "$REPOS_FILE" ]; then
    echo "❌ 未找到配置文件：$REPOS_FILE"
else
    echo "🚀 开始处理huggingface仓库下载任务"
    HF_TOKEN=$(tools_get_hf_token)

    # 配置 git 凭证
    git config --global credential.helper store
    git config --global init.defaultBranch main
    echo "https://USER:${HF_TOKEN}@huggingface.co" > ~/.git-credentials
    # 设置 sparse-checkout 来排除 LFS 文件
    git sparse-checkout init
    git sparse-checkout set "!*.safetensors" "!*.ckpt" "!*.bin" "!*.pth" "!*.pt" "!*.onnx" "!*.pkl"

    # 遍历并处理每个下载任务
    yq -o=json eval "$REPOS_FILE" | jq -r '.repos[] | "\(.url)|\(.local_path)|\(.rename_repos)|\(.description)"' | while IFS='|' read -r url local_path rename_repos description; do
        echo "🎯 开始处理: $description"
        echo "📥 仓库地址: $url"
        echo "📂 本地路径: $local_path"
        echo "📝 仓库描述: $description"
        echo "🚀 重新仓库名: $rename_repos"
        # 从 URL 中提取仓库名称
        repo_name=$(basename "$url")
        if [ "$rename_repos" != "null" ]; then
            echo "📝 重命名仓库: $rename_repos"
            repo_name="$rename_repos"
        fi

        fullPath="$COMFY_DIR$local_path/$repo_name"

        # 创建目标目录
        mkdir -p "$fullPath"
        cd "$fullPath" || exit

        # 先克隆仓库（禁用 LFS）
    #    echo "📦 克隆基础仓库..."
    #    GIT_LFS_SKIP_SMUDGE=1 git clone "$url" .
        echo "📦 检查仓库状态..."
        if [ -d ".git" ]; then
            echo "📂 仓库已存在，检查更新..."
        else
            echo "🆕 初始化新仓库..."
            GIT_LFS_SKIP_SMUDGE=1 git clone "$url" .
        fi
        if [ $? -eq 0 ]; then
            # 获取 LFS 文件列表
            echo "🔍 获取大文件列表..."
            git lfs ls-files | while read -r hash type file; do
                echo "处理文件: $file, type: $type, hash: $hash"
                # 检查文件是否存在
                if [ -f "$file" ]; then
                    echo "📝 文件存在，检查大小..."

                    remote_hash=$(git lfs ls-files -a origin/main | grep "$file" | awk '{print $1}')
                    echo "📝 远程文件哈希: $remote_hash"

                    # 使用 ls 获取文件大小（以字节为单位）
                    file_size=$(ls -l "$file" | awk '{print $5}')
                    echo "📊 文件大小: $file_size bytes"

                    if [ -n "$file_size" ]; then
                        if [ "$file_size" -lt 1048576 ]; then
                            echo "🗑️ 文件小于1MB，删除占位文件: $file"
                            rm -f "$file"
                            if [ $? -eq 0 ]; then
                                echo "✅ 占位文件删除成功"
                            else
                                echo "❌ 占位文件删除失败"
                            fi
                        else
                            echo "ℹ️ 文件大于1MB，保留文件"
                        fi
                    else
                        echo "⚠️ 无法获取文件大小"
                    fi
                else
                    echo "⚠️ 文件不存在: $file"
                fi

                # 构建文件下载 URL
                file_url="${url}/resolve/main/${file}"
                save_path="$fullPath"
                # 处理文件路径包含目录的情况
                if [[ "$file" == *"/"* ]]; then
                    # 包含目录的情况
                    file_dir="${file%/*}"
                    file_name="${file##*/}"
                else
                    # 没有目录的情况
                    file_dir=""
                    file_name="$file"
                fi

                # 构建完整的保存路径
                if [ -n "$file_dir" ]; then
                    save_path="${fullPath}/${file_dir}"
                fi

                echo "📥 开始下载文件: $file"
                echo "🔗 下载URL: $file_url"
                echo "📂 保存路径: $save_path"
                # 设置认证头（如果 HF_TOKEN 存在）
                local auth_header=""
                [ -n "$HF_TOKEN" ] && auth_header="Authorization: Bearer $HF_TOKEN"
                if [ -n "$auth_header" ]; then
                     download_file_by_aria2c "$file_url" "$auth_header" "$save_path"
                else
                     download_file_by_aria2c "$file_url" "" "$save_path"
                fi

#                if "$ROOT_DIR"/download.sh "$file_url" "Authorization: Bearer $HF_TOKEN" "$fullPath"; then
#                    echo "✅ 文件下载成功: $file"
#                else
#                    echo "❌ 文件下载失败: $file"
#                fi
                echo "-------------------"
            done

            echo "✅ 完成: $description"
        else
            echo "❌ 克隆失败: $description"
        fi

        echo "-------------------"
    done
fi
echo "✨ Hugging face仓库任务处理完成"
}

clone_repos_and_download_file


export -f clone_repos_and_download_file

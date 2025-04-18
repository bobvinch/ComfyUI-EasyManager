#!/bin/bash

# 检查并安装依赖
install_dependency() {
    if ! command -v "$1" &> /dev/null; then
        echo "正在安装 $1..."
        if command -v apt-get &> /dev/null; then
            # Ubuntu 系统
            sudo apt-get update
            case "$1" in
                "yq")
                    sudo add-apt-repository -y ppa:rmescandon/yq
                    sudo apt-get update
                    sudo apt-get install -y yq
                    ;;
                "jq")
                    sudo apt-get install -y jq
                    ;;
                *)
                    sudo apt-get install -y "$1"
                    ;;
            esac
        elif command -v brew &> /dev/null; then
            # MacOS 系统
            brew install "$1"
        else
            # 如果既没有 apt-get 也没有 brew
            echo "未检测到包管理器。"
            echo "对于 Ubuntu 系统，请确保已安装 apt-get"
            echo "对于 MacOS 系统，请安装 Homebrew："
            echo '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
            exit 1
        fi
    fi
}

# 检查并安装必要的工具
install_dependency "yq"
install_dependency "jq"

# 检查输入文件
if [ "$#" -ne 1 ]; then
    echo "使用方法: $0 <config.toml>"
    exit 1
fi

CONFIG_FILE="$1"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "错误: 文件 $CONFIG_FILE 不存在"
    exit 1
fi

# 使用 yq 将 TOML 转换为 JSON，然后用 jq 格式化
yq -p=toml -o=json eval "$CONFIG_FILE" | jq '.'
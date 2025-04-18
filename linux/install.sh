#!/bin/bash

set -e  # 发生错误时终止脚本执行

PORT="${1:-8188}"
# 获取脚本所在目录
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
echo "脚本所在目录是: $ROOT_DIR"
COMFY_DIR="$ROOT_DIR/ComfyUI"
#创建Python环境，安装依赖
CONDA_PATH="/root/miniconda3"
ENV_PATH="$ROOT_DIR/envs/comfyui"





echo "==========================="
echo "🚀 从远程仓库克隆应用到本地"
echo "==========================="

# autodl 开启学术加速
if [ -f /etc/network_turbo ]; then
    # autodl默认6006
    PORT=6006
    source /etc/network_turbo
fi



# 判断源目录和目标目录是否都不存在
if  [ ! -d "$COMFY_DIR" ]; then
    echo "🚀 从远程仓库克隆应用到本地"
    git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git "$COMFY_DIR"
else
    echo "⚠️ ComfyUI已存在（在源目录或目标目录中），跳过克隆步骤"
fi

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
    conda create -p $ENV_PATH python=3.10 -y --override-channels -c defaults
    echo "✅ Python 环境创建完成"
else
    echo "✅ Python 环境已存在"
fi


echo "🚀 初始化pytorch 环境"
cd "$ROOT_DIR"
chmod +x init_pytorch.sh
./init_pytorch.sh


# 安装节点和依赖
cd "$ROOT_DIR"
chmod +x install_requirements.sh
./install_requirements.sh




echo "==========================="
echo "🚀 开始安装多线程下载工具"
echo "==========================="
## 安装aria2c
if command -v aria2c &> /dev/null; then
    echo "✅ aria2c 已安装，跳过安装步骤"
else
    echo "📦 更新aria2c依赖，并安装aria2c..."
    apt update -y
    apt install -y aria2
fi

echo "🚀 aria2c安装成功"


## 部分模型下载需要的token
HF_TOKEN=""

chmod +x parse_toml.sh

CONFIG_TOML="$ROOT_DIR/config.toml"
if [ ! -f "$CONFIG_TOML" ]; then
    echo "❌ 未找到配置文件：$CONFIG_TOML"
else
    TOKEN_VALUE=$(./parse_toml.sh ./config.toml | jq -r '.authorizations[].huggingface_token // empty')
    if [ -n "$TOKEN_VALUE" ] && [ "$TOKEN_VALUE" != "null" ]; then
        if [ "$TOKEN_VALUE" != "" ]; then
            HF_TOKEN="$TOKEN_VALUE"
            echo "✅ 已设置 huggingface_token 为: $HF_TOKEN"
        else
            echo "⚠️ 警告: config.toml 中的 huggingface_token 值为空，你可能无法正常下载部分huggingface模型"
        fi
    else
        echo "❌ 警告: 无法从 config.toml 中读取 huggingface_token，你可能无法正常下载部分huggingface模型"
    fi
fi



# 检查 TOML 文件
MODELS_TOML="$ROOT_DIR/models.toml"
if [ ! -f "$MODELS_TOML" ]; then
    echo "❌ 未找到模型配置文件：$MODELS_TOML"
else
    echo "🚀 开始下载模型"
    # 给下载脚本添加执行权限
    cd "$ROOT_DIR"
    chmod +x download.sh
    # 使用 yq 将 TOML 转换为 JSON 格式并处理
    yq -o=json eval "$MODELS_TOML" | jq -r '.models[] | "\(.id)|\(.url)|\(.dir)|\(.fileName // "")"' | while IFS='|' read -r id url dir filename; do
        echo "🎯 开始处理任务: $id"
        echo "📥 下载链接: $url"
        echo "📂 下载目录: $COMFY_DIR$dir"
        echo "📄 文件名: $filename"

        # 确保目录存在
        mkdir -p "$COMFY_DIR$dir"

        # 根据是否存在 fileName 来决定下载参数
        if [ -n "$filename" ]; then
            echo "📄 使用指定文件名: $filename"
            if ./download.sh "$url" "$filename" "Authorization: Bearer $HF_TOKEN" "$COMFY_DIR$dir"; then
                echo "✅ 任务 $id 完成"
            else
                echo "❌ 任务 $id 失败"
            fi
        else
            if ./download.sh "$url" "Authorization: Bearer $HF_TOKEN" "$COMFY_DIR$dir"; then
                echo "✅ 任务 $id 完成"
            else
                echo "❌ 任务 $id 失败"
            fi
        fi
        echo "-------------------"
    done

    echo "✨ 所有模型下载任务处理完成"
fi

#安装huggingface仓库
cd "$ROOT_DIR"
echo "🚀 安装huggingface仓库"
chmod +x install_repos_hf.sh
bash ./install_repos_hf.sh "$HF_TOKEN"


#启动ComfyUI
cd "$ROOT_DIR"
echo "🚀 启动ComfyUI"
bash ./start.sh "$PORT"



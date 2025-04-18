#!/bin/bash

set -e  # 发生错误时终止脚本执行

PORT="${1:-8188}"
# autodl 开启学术加速
if [ -f /etc/network_turbo ]; then
    # autodl默认6006
    PORT=6006
    source /etc/network_turbo
fi
# 获取脚本所在目录
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
echo "脚本所在目录是: $ROOT_DIR"
COMFY_DIR="$ROOT_DIR/ComfyUI"

#创建Python环境，安装依赖
CONDA_PATH="/root/miniconda3"
ENV_PATH="$ROOT_DIR/envs/comfyui"
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

echo "🚀 激活 Python 环境..."
conda activate "$ENV_PATH"

#启动ComfyUI
echo "🚀 启动ComfyUI"
python3 "$COMFY_DIR"/main.py --listen 0.0.0.0 --port "$PORT"
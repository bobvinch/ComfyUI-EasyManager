#!/bin/bash

set -e  # 发生错误时终止脚本执行

PORT="8188"
CONDA_PATH="/root/miniconda3"
# 获取脚本所在目录
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# autodl 开启学术加速
if [ -f /etc/network_turbo ]; then
    # autodl默认6006
    PORT=6006
    source /etc/network_turbo
fi

# 如何$1存在
if [ -n "$1" ]; then
    PORT="$1"
fi

# 处理选项
# :p: 表示 -p 选项需要一个参数
while getopts ":p:" opt; do
  case $opt in
    p)
      PORT="$OPTARG"
      ;;
    \?) # 处理无效选项
      echo "无效选项: -$OPTARG" >&2
      exit 1
      ;;
    :) # 处理缺少参数的选项
      echo "选项 -$OPTARG 需要一个参数." >&2
      exit 1
      ;;
  esac
done

# 导出工具函数
source "$ROOT_DIR/tools.sh"


echo "脚本所在目录是: $ROOT_DIR"
COMFY_DIR="$ROOT_DIR/ComfyUI"
#创建Python环境，安装依赖
ENV_PATH="$ROOT_DIR/envs/comfyui"

if  [ ! -d "$COMFY_DIR" ]; then
  echo "🚀 ComfyUI is not installed,pls run install.sh first"
  exit 1
fi


echo "🚀 激活 Python 环境..."
conda init bash
source "$CONDA_PATH"/etc/profile.d/conda.sh
conda activate "$ENV_PATH"

#启动ComfyUI
echo "🚀 启动ComfyUI"

# 启动Python进程并捕获输出
python3 "$COMFY_DIR"/main.py --listen 0.0.0.0 --port "$PORT"
#!/bin/bash

set -e  # 发生错误时终止脚本执行
PORT="8188"

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


# 获取脚本所在目录
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
echo "脚本所在目录是: $ROOT_DIR"


# 导出工具函数
source ./tools.sh

# 初始化Python环境
InitializePythonEnv
# 克隆ComfyUI仓库
clone_ComfyUI_repos

echo "🚀 初始化pytorch 环境"
cd "$ROOT_DIR"
chmod +x init_pytorch.sh
./init_pytorch.sh


# 安装节点和依赖
cd "$ROOT_DIR"
chmod +x install_requirements.sh
./install_requirements.sh

# 下砸模型
cd "$ROOT_DIR"
chmod +x download.sh
./download.sh


#安装huggingface仓库
cd "$ROOT_DIR"
echo "🚀 安装huggingface仓库"
chmod +x install_repos_hf.sh
bash ./install_repos_hf.sh


#启动ComfyUI
cd "$ROOT_DIR"
echo "🚀 启动ComfyUI"
bash ./start.sh "$PORT"


